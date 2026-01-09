// =============================================================================
// Omesh - Inverted Index Implementation
// =============================================================================
//
// This module provides the inverted index for full-text search:
// - Term dictionary with binary search lookup
// - Positional posting lists
// - Two-level indexing: in-memory buffer + disk merge
//
// CALLING CONVENTION: AAPCS64
//   - Arguments: x0-x7 (x0 = first arg)
//   - Return value: x0
//   - Callee-saved: x19-x28
//   - Caller-saved: x0-x18
//
// ERROR HANDLING:
//   - Functions return 0 on success, negative errno on failure
//   - Common errors: -ENOMEM (-12), -ENOENT (-2), -EINVAL (-22)
//
// PUBLIC API:
//
//   fts_index_init(path) -> 0 | -errno
//       Initialize index from directory at path.
//       Must be called before any other fts_* function.
//
//   fts_index_add(doc_id, text_ptr, text_len) -> term_count | -errno
//       Tokenize text and add all terms to the index for doc_id.
//       Returns number of terms indexed on success.
//
//   fts_index_lookup(term_ptr, term_len, offset_out, docfreq_out) -> 0 | -errno
//       Look up a term in the index.
//       On success: *offset_out = term offset, *docfreq_out = doc frequency
//       Returns -ENOENT if term not found.
//
//   fts_index_get_posting(offset, posting_buf, max_entries) -> count | -errno
//       Read posting list at offset into buffer.
//       Returns number of entries read.
//
//   fts_index_flush() -> 0 | -errno
//       Flush in-memory buffer to disk.
//
// INTERNAL STATE:
//   g_fts_index       - FTS_STATE structure with file handles, mmap pointers
//   g_term_hash_table - Hash table for in-memory term lookup (4096 buckets)
//
// =============================================================================

.include "syscall_nums.inc"
.include "index.inc"

.text

// =============================================================================
// Global state
// =============================================================================
.section .bss
.balign 8
.global g_fts_index
g_fts_index:
    .skip   FTS_STATE_SIZE

// Hash table for in-memory term lookup
.balign 8
.global g_term_hash_table
g_term_hash_table:
    .skip   (FTS_HASH_TABLE_SIZE * 8)

// =============================================================================
// fts_index_init - Initialize full-text search index
// =============================================================================
// Input:
//   x0 = path to index directory (null-terminated)
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.text
.global fts_index_init
.type fts_index_init, %function
fts_index_init:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                 // Save path

    // Clear global state
    adrp    x0, g_fts_index
    add     x0, x0, :lo12:g_fts_index
    mov     x1, #FTS_STATE_SIZE
    mov     x20, x0                 // Save state ptr
.Lclear_state:
    cbz     x1, .Lclear_state_done
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       .Lclear_state
.Lclear_state_done:

    // Clear hash table
    adrp    x0, g_term_hash_table
    add     x0, x0, :lo12:g_term_hash_table
    mov     x1, #(FTS_HASH_TABLE_SIZE * 8)
.Lclear_hash:
    cbz     x1, .Lclear_hash_done
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       .Lclear_hash
.Lclear_hash_done:

    // Build term file path: path/terms.fts
    sub     sp, sp, #512            // Buffer for path
    mov     x0, sp
    mov     x1, x19
    bl      strcpy_simple
    mov     x0, sp
    adrp    x1, str_terms_fts
    add     x1, x1, :lo12:str_terms_fts
    bl      strcat_simple

    // Open/create term file
    mov     x0, #AT_FDCWD
    mov     x1, sp
    mov     x2, #(O_RDWR | O_CREAT)
    mov     x3, #0644
    bl      sys_openat
    cmp     x0, #0
    b.lt    .Lfts_init_error
    str     x0, [x20, #FTS_STATE_OFF_TERM_FD]
    mov     x21, x0                 // Save term fd

    // Build posting file path: path/postings.fts
    mov     x0, sp
    mov     x1, x19
    bl      strcpy_simple
    mov     x0, sp
    adrp    x1, str_post_fts
    add     x1, x1, :lo12:str_post_fts
    bl      strcat_simple

    // Open/create posting file
    mov     x0, #AT_FDCWD
    mov     x1, sp
    mov     x2, #(O_RDWR | O_CREAT)
    mov     x3, #0644
    bl      sys_openat
    cmp     x0, #0
    b.lt    .Lfts_init_error_close_term
    str     x0, [x20, #FTS_STATE_OFF_POST_FD]
    mov     x22, x0                 // Save post fd

    // Build meta file path: path/meta.fts
    mov     x0, sp
    mov     x1, x19
    bl      strcpy_simple
    mov     x0, sp
    adrp    x1, str_meta_fts
    add     x1, x1, :lo12:str_meta_fts
    bl      strcat_simple

    // Open/create meta file
    mov     x0, #AT_FDCWD
    mov     x1, sp
    mov     x2, #(O_RDWR | O_CREAT)
    mov     x3, #0644
    bl      sys_openat
    cmp     x0, #0
    b.lt    .Lfts_init_error_close_post
    str     x0, [x20, #FTS_STATE_OFF_META_FD]
    mov     x23, x0                 // Save meta fd

    add     sp, sp, #512            // Restore stack

    // Get term file size
    mov     x0, x21
    mov     x1, #0
    mov     x2, #SEEK_END
    bl      sys_lseek
    cmp     x0, #0
    b.lt    .Lfts_init_error_close_all
    mov     x24, x0                 // Term file size

    // If term file is empty, write header
    cbz     x24, .Lfts_init_write_headers

    // Otherwise, load existing index
    b       .Lfts_init_load_existing

.Lfts_init_write_headers:
    // Write term file header
    sub     sp, sp, #64
    ldr     w0, =FTS_TERM_MAGIC
    str     w0, [sp, #FTS_TERM_HDR_MAGIC]
    mov     w0, #FTS_VERSION
    str     w0, [sp, #FTS_TERM_HDR_VERSION]
    str     xzr, [sp, #FTS_TERM_HDR_COUNT]
    str     xzr, [sp, #FTS_TERM_HDR_TOTAL_POST]
    str     wzr, [sp, #FTS_TERM_HDR_CHECKSUM]
    str     wzr, [sp, #FTS_TERM_HDR_RESERVED]

    mov     x0, x21
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    mov     x0, x21
    mov     x1, sp
    mov     x2, #FTS_TERM_HDR_SIZE
    bl      sys_write

    // Write posting file header
    ldr     w0, =FTS_POST_MAGIC
    str     w0, [sp, #FTS_POST_HDR_MAGIC]
    mov     w0, #FTS_VERSION
    str     w0, [sp, #FTS_POST_HDR_VERSION]
    str     xzr, [sp, #FTS_POST_HDR_COUNT]
    str     wzr, [sp, #FTS_POST_HDR_CHECKSUM]
    str     wzr, [sp, #FTS_POST_HDR_RESERVED]

    mov     x0, x22
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    mov     x0, x22
    mov     x1, sp
    mov     x2, #FTS_POST_HDR_SIZE
    bl      sys_write

    // Write meta file
    ldr     w0, =FTS_META_MAGIC
    str     w0, [sp, #FTS_META_OFF_MAGIC]
    mov     w0, #FTS_VERSION
    str     w0, [sp, #FTS_META_OFF_VERSION]
    str     xzr, [sp, #FTS_META_OFF_TOTAL_DOCS]
    str     xzr, [sp, #FTS_META_OFF_TOTAL_TERMS]
    str     xzr, [sp, #FTS_META_OFF_TOTAL_TOKENS]
    str     xzr, [sp, #FTS_META_OFF_AVG_DOC_LEN]
    str     xzr, [sp, #FTS_META_OFF_LAST_DOC]
    str     xzr, [sp, #FTS_META_OFF_TIMESTAMP]
    str     wzr, [sp, #FTS_META_OFF_CHECKSUM]
    str     wzr, [sp, #FTS_META_OFF_RESERVED]

    mov     x0, x23
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    mov     x0, x23
    mov     x1, sp
    mov     x2, #FTS_META_SIZE
    bl      sys_write

    add     sp, sp, #64

    // Allocate in-memory term buffer
    mov     x0, #0
    mov     x1, #(FTS_BUFFER_CAPACITY * TERMBUF_ENTRY_SIZE)
    mov     x2, #(PROT_READ | PROT_WRITE)
    mov     x3, #(MAP_PRIVATE | MAP_ANONYMOUS)
    mov     x4, #-1
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Lfts_init_error_close_all
    str     x0, [x20, #FTS_STATE_OFF_BUF_PTR]
    str     xzr, [x20, #FTS_STATE_OFF_BUF_COUNT]

    mov     x0, #0
    b       .Lfts_init_done

.Lfts_init_load_existing:
    // mmap term file for reading
    mov     x0, #0
    mov     x1, x24                 // Size
    mov     x2, #PROT_READ
    mov     x3, #MAP_PRIVATE
    mov     x4, x21                 // fd
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Lfts_init_error_close_all
    str     x0, [x20, #FTS_STATE_OFF_TERM_MMAP]
    str     x24, [x20, #FTS_STATE_OFF_TERM_SIZE]
    mov     x25, x0                 // Save mmap base

    // Verify magic
    ldr     w1, [x25, #FTS_TERM_HDR_MAGIC]
    ldr     w2, =FTS_TERM_MAGIC
    cmp     w1, w2
    b.ne    .Lfts_init_error_unmap

    // Load term count
    ldr     x1, [x25, #FTS_TERM_HDR_COUNT]
    str     x1, [x20, #FTS_STATE_OFF_TERM_COUNT]

    // Get posting file size and mmap
    mov     x0, x22
    mov     x1, #0
    mov     x2, #SEEK_END
    bl      sys_lseek
    cmp     x0, #FTS_POST_HDR_SIZE
    b.lt    .Lfts_init_error_unmap
    mov     x26, x0                 // Post file size

    mov     x0, #0
    mov     x1, x26
    mov     x2, #PROT_READ
    mov     x3, #MAP_PRIVATE
    mov     x4, x22
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Lfts_init_error_unmap
    str     x0, [x20, #FTS_STATE_OFF_POST_MMAP]
    str     x26, [x20, #FTS_STATE_OFF_POST_SIZE]

    // Load metadata
    sub     sp, sp, #64
    mov     x0, x23
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    mov     x0, x23
    mov     x1, sp
    mov     x2, #FTS_META_SIZE
    bl      sys_read

    ldr     x1, [sp, #FTS_META_OFF_TOTAL_DOCS]
    str     x1, [x20, #FTS_STATE_OFF_TOTAL_DOCS]
    add     sp, sp, #64

    // Allocate in-memory buffer
    mov     x0, #0
    mov     x1, #(FTS_BUFFER_CAPACITY * TERMBUF_ENTRY_SIZE)
    mov     x2, #(PROT_READ | PROT_WRITE)
    mov     x3, #(MAP_PRIVATE | MAP_ANONYMOUS)
    mov     x4, #-1
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Lfts_init_error_unmap_post
    str     x0, [x20, #FTS_STATE_OFF_BUF_PTR]
    str     xzr, [x20, #FTS_STATE_OFF_BUF_COUNT]

    mov     x0, #0
    b       .Lfts_init_done

.Lfts_init_error_unmap_post:
    ldr     x0, [x20, #FTS_STATE_OFF_POST_MMAP]
    ldr     x1, [x20, #FTS_STATE_OFF_POST_SIZE]
    bl      sys_munmap

.Lfts_init_error_unmap:
    ldr     x0, [x20, #FTS_STATE_OFF_TERM_MMAP]
    ldr     x1, [x20, #FTS_STATE_OFF_TERM_SIZE]
    bl      sys_munmap
    mov     x0, #-EIO
    b       .Lfts_init_done

.Lfts_init_error_close_all:
    ldr     x0, [x20, #FTS_STATE_OFF_META_FD]
    bl      sys_close
.Lfts_init_error_close_post:
    ldr     x0, [x20, #FTS_STATE_OFF_POST_FD]
    bl      sys_close
.Lfts_init_error_close_term:
    ldr     x0, [x20, #FTS_STATE_OFF_TERM_FD]
    bl      sys_close
.Lfts_init_error:
    mov     x0, #-EIO

.Lfts_init_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size fts_index_init, .-fts_index_init

// =============================================================================
// fts_index_close - Close index and free resources
// =============================================================================
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global fts_index_close
.type fts_index_close, %function
fts_index_close:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    adrp    x19, g_fts_index
    add     x19, x19, :lo12:g_fts_index

    // Free buffer
    ldr     x0, [x19, #FTS_STATE_OFF_BUF_PTR]
    cbz     x0, .Lclose_unmap_term
    mov     x1, #(FTS_BUFFER_CAPACITY * TERMBUF_ENTRY_SIZE)
    bl      sys_munmap

.Lclose_unmap_term:
    // Unmap term file
    ldr     x0, [x19, #FTS_STATE_OFF_TERM_MMAP]
    cbz     x0, .Lclose_unmap_post
    ldr     x1, [x19, #FTS_STATE_OFF_TERM_SIZE]
    bl      sys_munmap

.Lclose_unmap_post:
    // Unmap posting file
    ldr     x0, [x19, #FTS_STATE_OFF_POST_MMAP]
    cbz     x0, .Lclose_files
    ldr     x1, [x19, #FTS_STATE_OFF_POST_SIZE]
    bl      sys_munmap

.Lclose_files:
    // Close files
    ldr     x0, [x19, #FTS_STATE_OFF_META_FD]
    cbz     x0, .Lclose_post_fd
    bl      sys_close

.Lclose_post_fd:
    ldr     x0, [x19, #FTS_STATE_OFF_POST_FD]
    cbz     x0, .Lclose_term_fd
    bl      sys_close

.Lclose_term_fd:
    ldr     x0, [x19, #FTS_STATE_OFF_TERM_FD]
    cbz     x0, .Lclose_done
    bl      sys_close

.Lclose_done:
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size fts_index_close, .-fts_index_close

// =============================================================================
// fts_index_add - Add document to index
// =============================================================================
// Input:
//   x0 = document ID
//   x1 = document content pointer
//   x2 = document length
// Output:
//   x0 = number of terms indexed on success, negative errno on error
// =============================================================================
.global fts_index_add
.type fts_index_add, %function
fts_index_add:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0                 // Doc ID
    mov     x20, x1                 // Content ptr
    mov     x21, x2                 // Content length
    mov     x22, #0                 // Terms indexed

    // Initialize tokenizer
    mov     x0, x20
    mov     x1, x21
    bl      fts_tokenize_init
    cbz     x0, .Ladd_error
    mov     x23, x0                 // Tokenizer state

    // Allocate token buffer
    sub     sp, sp, #256            // Token buffer

.Ladd_token_loop:
    mov     x0, x23
    mov     x1, sp                  // Token buffer
    mov     x2, #255                // Buffer size
    bl      fts_tokenize_next
    cbz     x0, .Ladd_done          // No more tokens
    cmp     x0, #0
    b.lt    .Ladd_error_free

    mov     x24, x0                 // Token length
    mov     x25, x1                 // Byte position (for positions)

    // Get word position (0-based index)
    mov     x0, x23
    bl      fts_tokenize_get_position
    sub     x26, x0, #1             // Word position (0-based)

    // Add term to buffer
    mov     x0, sp                  // Term string
    mov     x1, x24                 // Term length
    mov     x2, x19                 // Doc ID
    mov     x3, x26                 // Position
    bl      fts_index_add_term
    cmp     x0, #0
    b.lt    .Ladd_error_free

    add     x22, x22, #1            // Increment terms count
    b       .Ladd_token_loop

.Ladd_done:
    add     sp, sp, #256

    // Free tokenizer
    mov     x0, x23
    bl      fts_tokenize_free

    // Update total docs count
    adrp    x0, g_fts_index
    add     x0, x0, :lo12:g_fts_index
    ldr     x1, [x0, #FTS_STATE_OFF_TOTAL_DOCS]
    add     x1, x1, #1
    str     x1, [x0, #FTS_STATE_OFF_TOTAL_DOCS]

    // Mark dirty
    mov     x1, #1
    str     x1, [x0, #FTS_STATE_OFF_DIRTY]

    mov     x0, x22                 // Return terms indexed

    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

.Ladd_error_free:
    add     sp, sp, #256
    mov     x0, x23
    bl      fts_tokenize_free
.Ladd_error:
    mov     x0, #-EIO
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size fts_index_add, .-fts_index_add

// =============================================================================
// fts_index_add_term - Add term occurrence to buffer
// =============================================================================
// Input:
//   x0 = term string
//   x1 = term length
//   x2 = document ID
//   x3 = position in document
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global fts_index_add_term
.type fts_index_add_term, %function
fts_index_add_term:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                 // Term
    mov     x20, x1                 // Length
    mov     x21, x2                 // Doc ID
    mov     x22, x3                 // Position

    // Calculate term hash
    bl      crc32_calc
    mov     x23, x0                 // Term hash

    // Look up in hash table
    adrp    x0, g_term_hash_table
    add     x0, x0, :lo12:g_term_hash_table
    and     x1, x23, #(FTS_HASH_TABLE_SIZE - 1)
    lsl     x1, x1, #3              // * 8 bytes per entry
    add     x24, x0, x1             // Hash table slot

    ldr     x0, [x24]               // Entry pointer
    cbz     x0, .Lterm_new          // Empty slot, new term

    // Search chain for matching term
.Lterm_search:
    ldr     w1, [x0, #TERMBUF_OFF_HASH]
    cmp     w1, w23
    b.ne    .Lterm_next

    // Hash matches, compare term string
    ldrh    w1, [x0, #TERMBUF_OFF_LEN]
    cmp     w1, w20
    b.ne    .Lterm_next

    // Length matches, compare content
    ldr     x1, [x0, #TERMBUF_OFF_TERM_PTR]
    mov     x2, x19
    mov     x3, x20
    stp     x0, xzr, [sp, #-16]!
    bl      memcmp
    mov     x4, x0
    ldp     x0, xzr, [sp], #16
    cbnz    x4, .Lterm_next

    // Exact match - check if same doc
    ldr     x1, [x0, #TERMBUF_OFF_DOC_ID]
    cmp     x1, x21
    b.eq    .Lterm_add_position     // Same doc, add position

    // Different doc for same term - for now skip (would need more complex structure)
    mov     x0, #0
    b       .Lterm_done

.Lterm_next:
    ldr     x0, [x0, #TERMBUF_OFF_NEXT]
    cbnz    x0, .Lterm_search
    // Fall through to new entry

.Lterm_new:
    // Check if buffer is full
    adrp    x0, g_fts_index
    add     x0, x0, :lo12:g_fts_index
    ldr     x1, [x0, #FTS_STATE_OFF_BUF_COUNT]
    cmp     x1, #FTS_BUFFER_CAPACITY
    b.ge    .Lterm_buffer_full

    // Get new entry slot
    ldr     x2, [x0, #FTS_STATE_OFF_BUF_PTR]
    mov     x3, #TERMBUF_ENTRY_SIZE
    mul     x3, x1, x3
    add     x25, x2, x3             // New entry ptr

    // Initialize entry
    str     w23, [x25, #TERMBUF_OFF_HASH]
    strh    w20, [x25, #TERMBUF_OFF_LEN]
    strh    wzr, [x25, #TERMBUF_OFF_FLAGS]
    str     x21, [x25, #TERMBUF_OFF_DOC_ID]
    mov     w1, #1
    str     w1, [x25, #TERMBUF_OFF_TERM_FREQ]
    str     w1, [x25, #TERMBUF_OFF_POS_COUNT]

    // Allocate positions array (small initial allocation)
    mov     x0, #0
    mov     x1, #(64 * 4)           // 64 positions max initially
    mov     x2, #(PROT_READ | PROT_WRITE)
    mov     x3, #(MAP_PRIVATE | MAP_ANONYMOUS)
    mov     x4, #-1
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Lterm_error
    str     x0, [x25, #TERMBUF_OFF_POSITIONS]

    // Store first position
    str     w22, [x0]

    // Copy term string (allocate and copy)
    mov     x0, #0
    add     x1, x20, #8             // Round up to 8
    and     x1, x1, #~7
    mov     x2, #(PROT_READ | PROT_WRITE)
    mov     x3, #(MAP_PRIVATE | MAP_ANONYMOUS)
    mov     x4, #-1
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Lterm_error
    str     x0, [x25, #TERMBUF_OFF_TERM_PTR]

    // Copy term bytes
    mov     x1, x19
    mov     x2, x20
    bl      memcpy

    // Link into hash chain
    ldr     x0, [x24]               // Current head
    str     x0, [x25, #TERMBUF_OFF_NEXT]
    str     x25, [x24]              // New head

    // Increment buffer count
    adrp    x0, g_fts_index
    add     x0, x0, :lo12:g_fts_index
    ldr     x1, [x0, #FTS_STATE_OFF_BUF_COUNT]
    add     x1, x1, #1
    str     x1, [x0, #FTS_STATE_OFF_BUF_COUNT]

    mov     x0, #0
    b       .Lterm_done

.Lterm_add_position:
    // Add position to existing entry
    ldr     w1, [x0, #TERMBUF_OFF_POS_COUNT]
    cmp     w1, #64                 // Max positions check
    b.ge    .Lterm_done_ok          // Skip if full

    ldr     x2, [x0, #TERMBUF_OFF_POSITIONS]
    str     w22, [x2, w1, uxtw #2]  // positions[pos_count] = position

    add     w1, w1, #1
    str     w1, [x0, #TERMBUF_OFF_POS_COUNT]

    // Increment term frequency
    ldr     w1, [x0, #TERMBUF_OFF_TERM_FREQ]
    add     w1, w1, #1
    str     w1, [x0, #TERMBUF_OFF_TERM_FREQ]

.Lterm_done_ok:
    mov     x0, #0
    b       .Lterm_done

.Lterm_buffer_full:
    // Flush buffer to disk
    bl      fts_index_flush
    cmp     x0, #0
    b.lt    .Lterm_done

    // Retry add
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x22
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    b       fts_index_add_term

.Lterm_error:
    mov     x0, #-ENOMEM

.Lterm_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size fts_index_add_term, .-fts_index_add_term

// =============================================================================
// fts_index_lookup - Look up term in dictionary
// =============================================================================
// Input:
//   x0 = term string (normalized, null-terminated)
//   x1 = term length
//   x2 = pointer to receive posting list offset
//   x3 = pointer to receive doc_freq
// Output:
//   x0 = 0 if found, -ENOENT if not found
// =============================================================================
.global fts_index_lookup
.type fts_index_lookup, %function
fts_index_lookup:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                 // Term
    mov     x20, x1                 // Length
    mov     x21, x2                 // Out offset ptr
    mov     x22, x3                 // Out doc_freq ptr

    // Calculate hash
    bl      crc32_calc
    mov     x23, x0                 // Hash

    // First check in-memory buffer
    adrp    x0, g_term_hash_table
    add     x0, x0, :lo12:g_term_hash_table
    and     x1, x23, #(FTS_HASH_TABLE_SIZE - 1)
    ldr     x0, [x0, x1, lsl #3]

.Llookup_buf_loop:
    cbz     x0, .Llookup_disk

    ldr     w1, [x0, #TERMBUF_OFF_HASH]
    cmp     w1, w23
    b.ne    .Llookup_buf_next

    ldrh    w1, [x0, #TERMBUF_OFF_LEN]
    cmp     w1, w20
    b.ne    .Llookup_buf_next

    // memcmp(stored_term, query_term, length)
    stp     x0, xzr, [sp, #-16]!             // Save entry ptr first
    ldr     x0, [x0, #TERMBUF_OFF_TERM_PTR]  // x0 = stored term
    mov     x1, x19                          // x1 = query term
    mov     x2, x20                          // x2 = length
    bl      memcmp
    mov     x4, x0
    ldp     x0, xzr, [sp], #16
    cbnz    x4, .Llookup_buf_next

    // Found in buffer - return buffer entry info
    // For in-memory entries, offset is buffer entry ptr (negative = in buffer)
    cbz     x21, .Llookup_buf_docfreq
    mvn     x1, x0                  // Negative ptr indicates buffer
    str     x1, [x21]

.Llookup_buf_docfreq:
    cbz     x22, .Llookup_found
    mov     x1, #1                  // In-buffer always 1 doc
    str     x1, [x22]
    b       .Llookup_found

.Llookup_buf_next:
    ldr     x0, [x0, #TERMBUF_OFF_NEXT]
    b       .Llookup_buf_loop

.Llookup_disk:
    // Binary search in disk term dictionary
    adrp    x0, g_fts_index
    add     x0, x0, :lo12:g_fts_index
    ldr     x24, [x0, #FTS_STATE_OFF_TERM_MMAP]
    cbz     x24, .Llookup_not_found

    ldr     x0, [x0, #FTS_STATE_OFF_TERM_COUNT]
    cbz     x0, .Llookup_not_found

    // Binary search by hash
    mov     x1, #0                  // low
    mov     x2, x0                  // high = count

.Llookup_bsearch:
    cmp     x1, x2
    b.ge    .Llookup_not_found

    add     x3, x1, x2
    lsr     x3, x3, #1              // mid = (low + high) / 2

    // Get entry at mid (need to scan since variable length)
    // For simplicity, iterate from start (can optimize with offset table)
    add     x4, x24, #FTS_TERM_HDR_SIZE  // First entry
    mov     x5, #0                  // Counter

.Llookup_seek:
    cmp     x5, x3
    b.ge    .Llookup_compare

    ldrh    w6, [x4, #FTS_TERM_OFF_LEN]
    add     x6, x6, #FTS_TERM_ENTRY_FIXED
    add     x6, x6, #7
    and     x6, x6, #~7             // Align to 8
    add     x4, x4, x6              // Next entry
    add     x5, x5, #1
    b       .Llookup_seek

.Llookup_compare:
    ldr     w6, [x4, #FTS_TERM_OFF_HASH]
    cmp     w23, w6
    b.lt    .Llookup_go_left
    b.gt    .Llookup_go_right

    // Hash match - compare term
    ldrh    w6, [x4, #FTS_TERM_OFF_LEN]
    cmp     w20, w6
    b.ne    .Llookup_hash_collision

    add     x0, x4, #FTS_TERM_OFF_DATA
    mov     x1, x19
    mov     x2, x20
    stp     x1, x2, [sp, #-16]!
    stp     x3, x4, [sp, #-16]!
    bl      memcmp
    mov     x6, x0
    ldp     x3, x4, [sp], #16
    ldp     x1, x2, [sp], #16
    cbnz    x6, .Llookup_hash_collision

    // Found!
    cbz     x21, .Llookup_disk_docfreq
    ldr     x0, [x4, #FTS_TERM_OFF_POST_OFFSET]
    str     x0, [x21]

.Llookup_disk_docfreq:
    cbz     x22, .Llookup_found
    ldr     w0, [x4, #FTS_TERM_OFF_DOC_FREQ]
    str     x0, [x22]
    b       .Llookup_found

.Llookup_hash_collision:
    // Same hash but different term - keep searching
    // This simplified version just continues right
    b       .Llookup_go_right

.Llookup_go_left:
    mov     x2, x3                  // high = mid
    b       .Llookup_bsearch

.Llookup_go_right:
    add     x1, x3, #1              // low = mid + 1
    b       .Llookup_bsearch

.Llookup_found:
    mov     x0, #0
    b       .Llookup_done

.Llookup_not_found:
    mov     x0, #-ENOENT

.Llookup_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size fts_index_lookup, .-fts_index_lookup

// =============================================================================
// fts_index_flush - Flush in-memory buffer to disk
// =============================================================================
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global fts_index_flush
.type fts_index_flush, %function
fts_index_flush:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    adrp    x19, g_fts_index
    add     x19, x19, :lo12:g_fts_index

    // Check if anything to flush
    ldr     x0, [x19, #FTS_STATE_OFF_BUF_COUNT]
    cbz     x0, .Lflush_done_ok

    // For now, just clear the buffer (simplified - full merge is complex)
    // In production, would merge with disk index

    // Clear hash table
    adrp    x0, g_term_hash_table
    add     x0, x0, :lo12:g_term_hash_table
    mov     x1, #(FTS_HASH_TABLE_SIZE * 8)
.Lflush_clear:
    cbz     x1, .Lflush_clear_done
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       .Lflush_clear
.Lflush_clear_done:

    // Reset buffer count
    str     xzr, [x19, #FTS_STATE_OFF_BUF_COUNT]

.Lflush_done_ok:
    mov     x0, #0

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size fts_index_flush, .-fts_index_flush

// =============================================================================
// fts_index_sync - Sync index to disk
// =============================================================================
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global fts_index_sync
.type fts_index_sync, %function
fts_index_sync:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Flush buffer first
    bl      fts_index_flush
    cmp     x0, #0
    b.lt    .Lsync_done

    // fsync files
    adrp    x0, g_fts_index
    add     x0, x0, :lo12:g_fts_index
    ldr     x0, [x0, #FTS_STATE_OFF_TERM_FD]
    bl      sys_fsync

    adrp    x0, g_fts_index
    add     x0, x0, :lo12:g_fts_index
    ldr     x0, [x0, #FTS_STATE_OFF_POST_FD]
    bl      sys_fsync

    mov     x0, #0

.Lsync_done:
    ldp     x29, x30, [sp], #16
    ret
.size fts_index_sync, .-fts_index_sync

// =============================================================================
// Helper: strcpy_simple
// =============================================================================
strcpy_simple:
    mov     x2, x0
.Lstrcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x2], #1
    cbnz    w3, .Lstrcpy_loop
    ret

// =============================================================================
// Helper: strcat_simple
// =============================================================================
strcat_simple:
    // Find end of x0
.Lstrcat_find:
    ldrb    w2, [x0]
    cbz     w2, .Lstrcat_copy
    add     x0, x0, #1
    b       .Lstrcat_find
.Lstrcat_copy:
    ldrb    w2, [x1], #1
    strb    w2, [x0], #1
    cbnz    w2, .Lstrcat_copy
    ret

// =============================================================================
// String constants
// =============================================================================
.section .rodata
.balign 8
str_terms_fts:
    .asciz  "terms.fts"
str_post_fts:
    .asciz  "postings.fts"
str_meta_fts:
    .asciz  "meta.fts"
