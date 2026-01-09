// =============================================================================
// Omesh - Index Persistence Module
// =============================================================================
//
// Provides save/load functionality for the in-memory FTS index:
// - fts_index_save: Write in-memory terms and postings to disk files
// - fts_index_load: Rebuild in-memory hash table from disk files
//
// CALLING CONVENTION: AAPCS64
//   - Arguments: x0-x7 (x0 = first arg)
//   - Return value: x0
//   - Callee-saved: x19-x28
//   - Caller-saved: x0-x18
//
// ERROR HANDLING:
//   - Returns 0 on success, negative errno on failure
//
// =============================================================================

.include "syscall_nums.inc"
.include "index.inc"

.data

msg_persist_save:
    .asciz "[persist] Saving index...\n"
msg_persist_saved:
    .asciz "[persist] Index saved: "
msg_persist_terms:
    .asciz " terms, "
msg_persist_docs:
    .asciz " docs\n"
msg_persist_load:
    .asciz "[persist] Loading index...\n"
msg_persist_loaded:
    .asciz "[persist] Index loaded: "
msg_persist_no_index:
    .asciz "[persist] No existing index found\n"
msg_persist_corrupt:
    .asciz "[persist] Index file corrupt, starting fresh\n"

.text

// =============================================================================
// fts_index_save - Save in-memory index to disk
// =============================================================================
// Input:
//   (none - uses g_fts_index)
// Output:
//   x0 = 0 on success, negative errno on failure
// Notes:
//   Writes all terms in g_term_hash_table to terms.fts and postings.fts
//   Updates meta.fts with statistics
// =============================================================================
.global fts_index_save
.type fts_index_save, %function
fts_index_save:
    stp     x29, x30, [sp, #-112]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]

    // Print saving message
    adrp    x0, msg_persist_save
    add     x0, x0, :lo12:msg_persist_save
    bl      persist_print_str

    // Get index state
    adrp    x19, g_fts_index
    add     x19, x19, :lo12:g_fts_index

    // Get buffer info
    ldr     x20, [x19, #FTS_STATE_OFF_BUF_COUNT]    // term count
    ldr     x21, [x19, #FTS_STATE_OFF_TOTAL_DOCS]   // doc count

    // Check if anything to save
    cbz     x20, .Lsave_empty

    // Reset file positions - seek to header size
    ldr     x0, [x19, #FTS_STATE_OFF_TERM_FD]
    mov     x1, #FTS_TERM_HDR_SIZE
    mov     x2, #SEEK_SET
    bl      sys_lseek
    cmp     x0, #0
    b.lt    .Lsave_error

    ldr     x0, [x19, #FTS_STATE_OFF_POST_FD]
    mov     x1, #FTS_POST_HDR_SIZE
    mov     x2, #SEEK_SET
    bl      sys_lseek
    cmp     x0, #0
    b.lt    .Lsave_error

    // Initialize counters
    mov     x22, #0                     // terms written
    mov     x23, #0                     // total postings
    mov     x24, #FTS_POST_HDR_SIZE     // current posting offset

    // Iterate hash table
    adrp    x25, g_term_hash_table
    add     x25, x25, :lo12:g_term_hash_table
    mov     x26, #0                     // bucket index

.Lsave_bucket_loop:
    cmp     x26, #FTS_HASH_TABLE_SIZE
    b.ge    .Lsave_write_headers

    // Get bucket head
    ldr     x27, [x25, x26, lsl #3]
    cbz     x27, .Lsave_next_bucket

    // Walk chain
.Lsave_chain_loop:
    cbz     x27, .Lsave_next_bucket

    // Write term entry
    // First, write posting list and get offset
    mov     x0, x27                     // entry ptr
    mov     x1, x24                     // current offset
    bl      persist_write_posting
    cmp     x0, #0
    b.lt    .Lsave_error

    mov     x28, x0                     // posting bytes written

    // Now write term entry to terms.fts
    mov     x0, x27                     // entry ptr
    mov     x1, x24                     // posting offset
    bl      persist_write_term
    cmp     x0, #0
    b.lt    .Lsave_error

    // Update counters
    add     x22, x22, #1                // terms++
    ldr     w0, [x27, #TERMBUF_OFF_POS_COUNT]
    add     x23, x23, x0                // total postings
    add     x24, x24, x28               // advance posting offset

    // Next in chain
    ldr     x27, [x27, #TERMBUF_OFF_NEXT]
    b       .Lsave_chain_loop

.Lsave_next_bucket:
    add     x26, x26, #1
    b       .Lsave_bucket_loop

.Lsave_write_headers:
    // Write term file header
    sub     sp, sp, #64
    ldr     w0, =FTS_TERM_MAGIC
    str     w0, [sp, #FTS_TERM_HDR_MAGIC]
    mov     w0, #FTS_VERSION
    str     w0, [sp, #FTS_TERM_HDR_VERSION]
    str     x22, [sp, #FTS_TERM_HDR_COUNT]
    str     x23, [sp, #FTS_TERM_HDR_TOTAL_POST]
    str     wzr, [sp, #FTS_TERM_HDR_CHECKSUM]      // TODO: calculate
    str     wzr, [sp, #FTS_TERM_HDR_RESERVED]

    ldr     x0, [x19, #FTS_STATE_OFF_TERM_FD]
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    ldr     x0, [x19, #FTS_STATE_OFF_TERM_FD]
    mov     x1, sp
    mov     x2, #FTS_TERM_HDR_SIZE
    bl      sys_write
    cmp     x0, #0
    b.lt    .Lsave_error_sp

    // Write posting file header
    ldr     w0, =FTS_POST_MAGIC
    str     w0, [sp, #FTS_POST_HDR_MAGIC]
    mov     w0, #FTS_VERSION
    str     w0, [sp, #FTS_POST_HDR_VERSION]
    str     x23, [sp, #FTS_POST_HDR_COUNT]
    str     wzr, [sp, #FTS_POST_HDR_CHECKSUM]
    str     wzr, [sp, #FTS_POST_HDR_RESERVED]

    ldr     x0, [x19, #FTS_STATE_OFF_POST_FD]
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    ldr     x0, [x19, #FTS_STATE_OFF_POST_FD]
    mov     x1, sp
    mov     x2, #FTS_POST_HDR_SIZE
    bl      sys_write

    // Write meta file
    ldr     w0, =FTS_META_MAGIC
    str     w0, [sp, #FTS_META_OFF_MAGIC]
    mov     w0, #FTS_VERSION
    str     w0, [sp, #FTS_META_OFF_VERSION]
    str     x21, [sp, #FTS_META_OFF_TOTAL_DOCS]
    str     x22, [sp, #FTS_META_OFF_TOTAL_TERMS]
    str     x23, [sp, #FTS_META_OFF_TOTAL_TOKENS]
    str     xzr, [sp, #FTS_META_OFF_AVG_DOC_LEN]
    str     xzr, [sp, #FTS_META_OFF_LAST_DOC]
    str     xzr, [sp, #FTS_META_OFF_TIMESTAMP]
    str     wzr, [sp, #FTS_META_OFF_CHECKSUM]
    str     wzr, [sp, #FTS_META_OFF_RESERVED]

    ldr     x0, [x19, #FTS_STATE_OFF_META_FD]
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    ldr     x0, [x19, #FTS_STATE_OFF_META_FD]
    mov     x1, sp
    mov     x2, #FTS_META_SIZE
    bl      sys_write

    add     sp, sp, #64

    // Sync files
    ldr     x0, [x19, #FTS_STATE_OFF_TERM_FD]
    bl      sys_fsync
    ldr     x0, [x19, #FTS_STATE_OFF_POST_FD]
    bl      sys_fsync
    ldr     x0, [x19, #FTS_STATE_OFF_META_FD]
    bl      sys_fsync

    // Print stats
    adrp    x0, msg_persist_saved
    add     x0, x0, :lo12:msg_persist_saved
    bl      persist_print_str
    mov     x0, x22
    bl      persist_print_dec
    adrp    x0, msg_persist_terms
    add     x0, x0, :lo12:msg_persist_terms
    bl      persist_print_str
    mov     x0, x21
    bl      persist_print_dec
    adrp    x0, msg_persist_docs
    add     x0, x0, :lo12:msg_persist_docs
    bl      persist_print_str

    // Clear dirty flag
    str     xzr, [x19, #FTS_STATE_OFF_DIRTY]

    mov     x0, #0
    b       .Lsave_done

.Lsave_empty:
    // Nothing to save
    mov     x0, #0
    b       .Lsave_done

.Lsave_error_sp:
    add     sp, sp, #64
.Lsave_error:
    mov     x0, #-EIO

.Lsave_done:
    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #112
    ret
.size fts_index_save, .-fts_index_save

// =============================================================================
// persist_write_term - Write a term entry to terms.fts
// =============================================================================
// Input:
//   x0 = TERMBUF entry pointer
//   x1 = posting offset in postings.fts
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================
.type persist_write_term, %function
persist_write_term:
    // Use fixed 320 byte buffer (24 fixed + 255 max term + padding)
    stp     x29, x30, [sp, #-384]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // entry ptr
    mov     x20, x1                     // posting offset

    // Get term length
    ldrh    w21, [x19, #TERMBUF_OFF_LEN]

    // Calculate entry size (fixed + term + padding)
    add     x22, x21, #FTS_TERM_ENTRY_FIXED
    add     x22, x22, #7
    and     x22, x22, #~7               // Align to 8

    // Buffer is at sp+64
    add     x4, sp, #64

    // Fill fixed portion
    ldr     w0, [x19, #TERMBUF_OFF_HASH]
    str     w0, [x4, #FTS_TERM_OFF_HASH]
    strh    w21, [x4, #FTS_TERM_OFF_LEN]
    ldrh    w0, [x19, #TERMBUF_OFF_FLAGS]
    strh    w0, [x4, #FTS_TERM_OFF_FLAGS]
    str     x20, [x4, #FTS_TERM_OFF_POST_OFFSET]
    mov     w0, #1                      // doc_freq = 1 (single doc)
    str     w0, [x4, #FTS_TERM_OFF_DOC_FREQ]
    ldr     w0, [x19, #TERMBUF_OFF_TERM_FREQ]
    str     w0, [x4, #FTS_TERM_OFF_TOTAL_FREQ]

    // Copy term string
    add     x0, x4, #FTS_TERM_OFF_DATA
    ldr     x1, [x19, #TERMBUF_OFF_TERM_PTR]
    mov     x2, x21
.Lwterm_copy:
    cbz     x2, .Lwterm_copy_done
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     x2, x2, #1
    b       .Lwterm_copy
.Lwterm_copy_done:

    // Write to file
    adrp    x0, g_fts_index
    add     x0, x0, :lo12:g_fts_index
    ldr     x0, [x0, #FTS_STATE_OFF_TERM_FD]
    add     x1, sp, #64                 // buffer
    mov     x2, x22                     // entry size
    bl      sys_write
    cmp     x0, #0
    b.lt    .Lwterm_error

    mov     x0, #0
    b       .Lwterm_done

.Lwterm_error:
    mov     x0, #-EIO

.Lwterm_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #384
    ret
.size persist_write_term, .-persist_write_term

// =============================================================================
// persist_write_posting - Write posting list for a term
// =============================================================================
// Input:
//   x0 = TERMBUF entry pointer
//   x1 = current offset (for verification)
// Output:
//   x0 = bytes written on success, negative errno on failure
// =============================================================================
.type persist_write_posting, %function
persist_write_posting:
    // Fixed buffer: 16 header + 12 entry + 64*4 positions = 284
    // 64 for regs + 288 buffer = 352, round to 384
    stp     x29, x30, [sp, #-384]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // entry ptr

    // Get position count
    ldr     w20, [x19, #TERMBUF_OFF_POS_COUNT]

    // Calculate posting entry size
    // Fixed (12) + positions (pos_count * 4) aligned to 8
    mov     x21, x20
    lsl     x21, x21, #2                // pos_count * 4
    add     x21, x21, #FTS_POST_ENTRY_FIXED
    add     x21, x21, #7
    and     x21, x21, #~7               // Align to 8

    // Also need list header (16 bytes)
    add     x22, x21, #FTS_POST_LIST_HDR_SIZE

    // Buffer is at sp+64
    add     x4, sp, #64

    // Fill list header
    ldr     w0, [x19, #TERMBUF_OFF_HASH]
    str     w0, [x4, #FTS_POST_LIST_HASH]
    mov     w0, #1                      // 1 entry
    str     w0, [x4, #FTS_POST_LIST_COUNT]
    str     w21, [x4, #FTS_POST_LIST_SIZE]
    str     wzr, [x4, #FTS_POST_LIST_FLAGS]

    // Fill posting entry
    add     x5, x4, #FTS_POST_LIST_HDR_SIZE
    ldr     x0, [x19, #TERMBUF_OFF_DOC_ID]
    str     x0, [x5, #FTS_POST_OFF_DOC_ID]
    ldr     w0, [x19, #TERMBUF_OFF_TERM_FREQ]
    strh    w0, [x5, #FTS_POST_OFF_TERM_FREQ]
    strh    w20, [x5, #FTS_POST_OFF_POS_COUNT]

    // Copy positions (inline)
    add     x0, x5, #FTS_POST_OFF_POSITIONS
    ldr     x1, [x19, #TERMBUF_OFF_POSITIONS]
    mov     x2, x20                     // pos_count
.Lwpost_copy:
    cbz     x2, .Lwpost_copy_done
    ldr     w3, [x1], #4
    str     w3, [x0], #4
    sub     x2, x2, #1
    b       .Lwpost_copy
.Lwpost_copy_done:

    // Write to file
    adrp    x0, g_fts_index
    add     x0, x0, :lo12:g_fts_index
    ldr     x0, [x0, #FTS_STATE_OFF_POST_FD]
    add     x1, sp, #64                 // buffer
    mov     x2, x22                     // total size
    bl      sys_write
    cmp     x0, #0
    b.lt    .Lwpost_error

    mov     x0, x22                     // Return bytes written
    b       .Lwpost_done

.Lwpost_error:
    mov     x0, #-EIO

.Lwpost_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #384
    ret
.size persist_write_posting, .-persist_write_posting

// =============================================================================
// fts_index_load - Load index from disk into in-memory hash table
// =============================================================================
// Input:
//   (none - uses g_fts_index which must have been initialized)
// Output:
//   x0 = terms loaded on success, 0 if no index, negative errno on failure
// Notes:
//   Populates g_term_hash_table from terms.fts
//   Sets up TERMBUF entries in the buffer
// =============================================================================
.global fts_index_load
.type fts_index_load, %function
fts_index_load:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    // Print loading message
    adrp    x0, msg_persist_load
    add     x0, x0, :lo12:msg_persist_load
    bl      persist_print_str

    // Get index state
    adrp    x19, g_fts_index
    add     x19, x19, :lo12:g_fts_index

    // Check if term file has content
    ldr     x20, [x19, #FTS_STATE_OFF_TERM_MMAP]
    cbz     x20, .Lload_no_index

    ldr     x21, [x19, #FTS_STATE_OFF_TERM_SIZE]
    cmp     x21, #FTS_TERM_HDR_SIZE
    b.le    .Lload_no_index

    // Verify magic
    ldr     w0, [x20, #FTS_TERM_HDR_MAGIC]
    ldr     w1, =FTS_TERM_MAGIC
    cmp     w0, w1
    b.ne    .Lload_corrupt

    // Get term count
    ldr     x22, [x20, #FTS_TERM_HDR_COUNT]
    cbz     x22, .Lload_no_index

    // Clear hash table first
    adrp    x0, g_term_hash_table
    add     x0, x0, :lo12:g_term_hash_table
    mov     x1, #(FTS_HASH_TABLE_SIZE * 8)
.Lload_clear:
    cbz     x1, .Lload_clear_done
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       .Lload_clear
.Lload_clear_done:

    // Get posting mmap
    ldr     x23, [x19, #FTS_STATE_OFF_POST_MMAP]

    // Iterate term entries
    add     x24, x20, #FTS_TERM_HDR_SIZE    // First entry
    mov     x25, #0                          // Counter

.Lload_term_loop:
    cmp     x25, x22
    b.ge    .Lload_done_ok

    // Read term entry and create TERMBUF
    mov     x0, x24                     // term entry ptr
    mov     x1, x23                     // posting mmap base
    bl      persist_load_term
    cmp     x0, #0
    b.lt    .Lload_error

    // Advance to next term entry
    ldrh    w0, [x24, #FTS_TERM_OFF_LEN]
    add     x0, x0, #FTS_TERM_ENTRY_FIXED
    add     x0, x0, #7
    and     x0, x0, #~7                 // Align
    add     x24, x24, x0

    add     x25, x25, #1
    b       .Lload_term_loop

.Lload_done_ok:
    // Update buffer count
    str     x25, [x19, #FTS_STATE_OFF_BUF_COUNT]

    // Print stats
    adrp    x0, msg_persist_loaded
    add     x0, x0, :lo12:msg_persist_loaded
    bl      persist_print_str
    mov     x0, x25
    bl      persist_print_dec
    adrp    x0, msg_persist_terms
    add     x0, x0, :lo12:msg_persist_terms
    bl      persist_print_str
    ldr     x0, [x19, #FTS_STATE_OFF_TOTAL_DOCS]
    bl      persist_print_dec
    adrp    x0, msg_persist_docs
    add     x0, x0, :lo12:msg_persist_docs
    bl      persist_print_str

    mov     x0, x25
    b       .Lload_done

.Lload_no_index:
    adrp    x0, msg_persist_no_index
    add     x0, x0, :lo12:msg_persist_no_index
    bl      persist_print_str
    mov     x0, #0
    b       .Lload_done

.Lload_corrupt:
    adrp    x0, msg_persist_corrupt
    add     x0, x0, :lo12:msg_persist_corrupt
    bl      persist_print_str
    mov     x0, #0
    b       .Lload_done

.Lload_error:
    mov     x0, #-EIO

.Lload_done:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret
.size fts_index_load, .-fts_index_load

// =============================================================================
// persist_load_term - Load a single term into memory
// =============================================================================
// Input:
//   x0 = term entry pointer (in mmap'd terms.fts)
//   x1 = posting mmap base
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================
.type persist_load_term, %function
persist_load_term:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // term entry
    mov     x20, x1                     // posting base

    // Get index state
    adrp    x21, g_fts_index
    add     x21, x21, :lo12:g_fts_index

    // Get current buffer slot
    ldr     x22, [x21, #FTS_STATE_OFF_BUF_COUNT]
    cmp     x22, #FTS_BUFFER_CAPACITY
    b.ge    .Lload_term_full

    ldr     x0, [x21, #FTS_STATE_OFF_BUF_PTR]
    mov     x1, #TERMBUF_ENTRY_SIZE
    mul     x1, x22, x1
    add     x23, x0, x1                 // New entry ptr

    // Read term data
    ldr     w0, [x19, #FTS_TERM_OFF_HASH]
    str     w0, [x23, #TERMBUF_OFF_HASH]
    mov     x24, x0                     // Save hash

    ldrh    w0, [x19, #FTS_TERM_OFF_LEN]
    strh    w0, [x23, #TERMBUF_OFF_LEN]
    mov     x2, x0                      // term len

    ldrh    w0, [x19, #FTS_TERM_OFF_FLAGS]
    strh    w0, [x23, #TERMBUF_OFF_FLAGS]

    // Get posting list offset and read posting data
    ldr     x0, [x19, #FTS_TERM_OFF_POST_OFFSET]
    add     x0, x20, x0                 // posting list ptr

    // Skip list header, get entry data
    add     x0, x0, #FTS_POST_LIST_HDR_SIZE

    ldr     x1, [x0, #FTS_POST_OFF_DOC_ID]
    str     x1, [x23, #TERMBUF_OFF_DOC_ID]

    ldrh    w1, [x0, #FTS_POST_OFF_TERM_FREQ]
    str     w1, [x23, #TERMBUF_OFF_TERM_FREQ]

    ldrh    w1, [x0, #FTS_POST_OFF_POS_COUNT]
    str     w1, [x23, #TERMBUF_OFF_POS_COUNT]
    mov     x3, x1                      // pos count

    // Allocate positions array
    stp     x0, x2, [sp, #64]           // Save posting ptr and term len
    mov     x0, #0
    mov     x1, #(64 * 4)               // 64 positions max
    mov     x2, #(PROT_READ | PROT_WRITE)
    mov     x3, #(MAP_PRIVATE | MAP_ANONYMOUS)
    mov     x4, #-1
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Lload_term_error
    str     x0, [x23, #TERMBUF_OFF_POSITIONS]
    mov     x4, x0                      // positions array

    ldp     x0, x2, [sp, #64]           // Restore posting ptr and term len

    // Copy positions
    ldr     w1, [x23, #TERMBUF_OFF_POS_COUNT]
    add     x5, x0, #FTS_POST_OFF_POSITIONS
    mov     x6, #0
.Lload_pos_loop:
    cmp     x6, x1
    b.ge    .Lload_pos_done
    ldr     w7, [x5, x6, lsl #2]
    str     w7, [x4, x6, lsl #2]
    add     x6, x6, #1
    b       .Lload_pos_loop
.Lload_pos_done:

    // Allocate and copy term string
    mov     x0, #0
    add     x1, x2, #8                  // term len + padding
    and     x1, x1, #~7
    mov     x3, #(MAP_PRIVATE | MAP_ANONYMOUS)
    mov     x5, #0
    stp     x2, xzr, [sp, #64]          // Save term len
    mov     x2, #(PROT_READ | PROT_WRITE)
    mov     x4, #-1
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Lload_term_error
    str     x0, [x23, #TERMBUF_OFF_TERM_PTR]

    ldp     x2, xzr, [sp, #64]          // Restore term len

    // Copy term bytes
    mov     x1, x0
    add     x0, x19, #FTS_TERM_OFF_DATA
    mov     x3, x2
.Lload_copy_term:
    cbz     x3, .Lload_copy_done
    ldrb    w4, [x0], #1
    strb    w4, [x1], #1
    sub     x3, x3, #1
    b       .Lload_copy_term
.Lload_copy_done:

    // Link into hash table
    adrp    x0, g_term_hash_table
    add     x0, x0, :lo12:g_term_hash_table
    and     x1, x24, #(FTS_HASH_TABLE_SIZE - 1)
    lsl     x1, x1, #3
    add     x0, x0, x1                  // Hash slot

    ldr     x1, [x0]                    // Current head
    str     x1, [x23, #TERMBUF_OFF_NEXT]
    str     x23, [x0]                   // New head

    // Increment buffer count
    ldr     x0, [x21, #FTS_STATE_OFF_BUF_COUNT]
    add     x0, x0, #1
    str     x0, [x21, #FTS_STATE_OFF_BUF_COUNT]

    mov     x0, #0
    b       .Lload_term_done

.Lload_term_full:
    mov     x0, #-ENOMEM
    b       .Lload_term_done

.Lload_term_error:
    mov     x0, #-EIO

.Lload_term_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size persist_load_term, .-persist_load_term

// =============================================================================
// persist_print_str - Print null-terminated string
// =============================================================================
persist_print_str:
    mov     x2, x0
    mov     x3, #0
.Lpps_len:
    ldrb    w4, [x2, x3]
    cbz     w4, .Lpps_write
    add     x3, x3, #1
    b       .Lpps_len
.Lpps_write:
    mov     x1, x2
    mov     x2, x3
    mov     x0, #1          // stdout
    mov     x8, #SYS_write
    svc     #0
    ret

// =============================================================================
// persist_print_dec - Print decimal number
// =============================================================================
persist_print_dec:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    mov     x1, sp
    add     x1, x1, #32         // Buffer
    mov     x2, #0              // Digit count

    cbz     x0, .Lppd_zero

.Lppd_loop:
    cbz     x0, .Lppd_print
    mov     x3, #10
    udiv    x4, x0, x3
    msub    x5, x4, x3, x0
    add     x5, x5, #'0'
    sub     x1, x1, #1
    strb    w5, [x1]
    add     x2, x2, #1
    mov     x0, x4
    b       .Lppd_loop

.Lppd_zero:
    mov     w5, #'0'
    sub     x1, x1, #1
    strb    w5, [x1]
    mov     x2, #1

.Lppd_print:
    mov     x0, #1              // stdout
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #48
    ret
