// =============================================================================
// Omesh - wal.s
// Write-Ahead Log for crash recovery
// =============================================================================
//
// The WAL ensures durability by logging operations before applying them.
// On crash, uncommitted WAL entries are replayed to recover state.
//
// WAL entry format (24 bytes header + data):
//   [4] Magic: "WAL\0"
//   [4] Total length (header + data)
//   [8] Sequence number
//   [4] Operation type (PUT, DELETE, COMMIT)
//   [4] CRC32 checksum of data
//   [N] Operation data
//
// For PUT operations, data format:
//   [8] Document ID
//   [8] File offset
//   [4] Content length
//   [N] Content
//
// For DELETE operations:
//   [8] Document ID
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/store.inc"

.extern sys_openat
.extern sys_close
.extern sys_read
.extern sys_write
.extern sys_lseek
.extern sys_fsync
.extern sys_ftruncate
.extern sys_clock_gettime
.extern crc32_calc
.extern memcpy

.text
.balign 4

// =============================================================================
// wal_init - Initialize write-ahead log
//
// Input:
//   x0 = path to WAL file
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global wal_init
.type wal_init, %function
wal_init:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // path

    // Open/create WAL file
    mov     x0, #AT_FDCWD
    mov     x1, x19
    mov     x2, #(O_RDWR | O_CREAT | O_APPEND)
    mov     x3, #0644
    bl      sys_openat
    cmp     x0, #0
    b.lt    .Lwal_init_error

    mov     x20, x0             // fd

    // Get file size
    mov     x1, #0
    mov     x2, #SEEK_END
    bl      sys_lseek
    mov     x21, x0             // file size

    // Scan to find highest sequence number
    mov     x22, #0             // seq = 0
    cbz     x21, .Lwal_init_store

    // Seek to beginning
    mov     x0, x20
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    // Scan for sequence numbers
    mov     x0, x20
    mov     x1, x21
    bl      wal_scan_max_seq
    mov     x22, x0

.Lwal_init_store:
    // Store state
    adrp    x0, g_wal_state
    add     x0, x0, :lo12:g_wal_state
    str     x20, [x0, #WAL_STATE_OFF_FD]
    str     x22, [x0, #WAL_STATE_OFF_SEQ]
    str     xzr, [x0, #WAL_STATE_OFF_DIR_FD]
    ldr     x1, =WAL_SYNC_INTERVAL
    str     x1, [x0, #WAL_STATE_OFF_SYNC_INT]
    str     xzr, [x0, #WAL_STATE_OFF_LAST_SYNC]
    str     x21, [x0, #WAL_STATE_OFF_SIZE]

    mov     x0, #0
    b       .Lwal_init_done

.Lwal_init_error:
    // x0 has error

.Lwal_init_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size wal_init, . - wal_init

// =============================================================================
// wal_scan_max_seq - Scan WAL file for highest sequence number
//
// Input:
//   x0 = fd
//   x1 = file size
// Output:
//   x0 = max sequence number found
// =============================================================================
.type wal_scan_max_seq, %function
wal_scan_max_seq:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    str     x23, [sp, #48]

    mov     x19, x0             // fd
    mov     x20, x1             // remaining size
    mov     x21, #0             // max seq
    mov     x22, #0             // current offset

.Lwal_scan_loop:
    // Need at least header size
    cmp     x20, #WAL_HDR_SIZE
    b.lt    .Lwal_scan_done

    // Seek to current offset
    mov     x0, x19
    mov     x1, x22
    mov     x2, #SEEK_SET
    bl      sys_lseek

    // Read header
    sub     sp, sp, #32
    mov     x0, x19
    mov     x1, sp
    mov     x2, #WAL_HDR_SIZE
    bl      sys_read
    cmp     x0, #WAL_HDR_SIZE
    b.ne    .Lwal_scan_read_done

    // Verify magic
    ldr     w0, [sp, #WAL_OFF_MAGIC]
    ldr     w1, =WAL_MAGIC
    cmp     w0, w1
    b.ne    .Lwal_scan_read_done

    // Get sequence number
    ldr     x23, [sp, #WAL_OFF_SEQ]
    cmp     x23, x21
    csel    x21, x23, x21, gt   // max = max(max, seq)

    // Get length and advance
    ldr     w0, [sp, #WAL_OFF_LENGTH]
    add     sp, sp, #32

    add     x22, x22, x0        // offset += length
    sub     x20, x20, x0        // remaining -= length
    b       .Lwal_scan_loop

.Lwal_scan_read_done:
    add     sp, sp, #32

.Lwal_scan_done:
    mov     x0, x21

    ldr     x23, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size wal_scan_max_seq, . - wal_scan_max_seq

// =============================================================================
// wal_append - Append entry to WAL
//
// Input:
//   x0 = operation type (WAL_OP_PUT, WAL_OP_DELETE, WAL_OP_COMMIT)
//   x1 = document ID (for PUT/DELETE)
//   x2 = data pointer (content for PUT, NULL for others)
//   x3 = data length
// Output:
//   x0 = sequence number on success, negative errno on error
// =============================================================================
.global wal_append
.type wal_append, %function
wal_append:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0             // op
    mov     x20, x1             // doc_id
    mov     x21, x2             // data ptr
    mov     x22, x3             // data len

    adrp    x23, g_wal_state
    add     x23, x23, :lo12:g_wal_state

    // Increment sequence number
    ldr     x24, [x23, #WAL_STATE_OFF_SEQ]
    add     x24, x24, #1
    str     x24, [x23, #WAL_STATE_OFF_SEQ]

    // Calculate entry size
    mov     x25, #WAL_HDR_SIZE
    cmp     x19, #WAL_OP_PUT
    b.ne    .Lwal_append_not_put
    add     x25, x25, #20       // doc_id(8) + offset(8) + len(4)
    add     x25, x25, x22       // + content
    b       .Lwal_append_calc_crc

.Lwal_append_not_put:
    cmp     x19, #WAL_OP_DELETE
    b.ne    .Lwal_append_calc_crc
    add     x25, x25, #8        // doc_id only

.Lwal_append_calc_crc:
    // Calculate CRC32 of data portion
    mov     x26, #0             // crc = 0 if no data
    cbz     x21, .Lwal_append_write

    mov     x0, x21
    mov     x1, x22
    bl      crc32_calc
    mov     x26, x0

.Lwal_append_write:
    // Build header on stack
    sub     sp, sp, #32
    ldr     w0, =WAL_MAGIC
    str     w0, [sp, #WAL_OFF_MAGIC]
    str     w25, [sp, #WAL_OFF_LENGTH]
    str     x24, [sp, #WAL_OFF_SEQ]
    str     w19, [sp, #WAL_OFF_OP]
    str     w26, [sp, #WAL_OFF_CHECKSUM]

    // Write header
    ldr     x0, [x23, #WAL_STATE_OFF_FD]
    mov     x1, sp
    mov     x2, #WAL_HDR_SIZE
    bl      sys_write
    cmp     x0, #WAL_HDR_SIZE
    b.ne    .Lwal_append_error

    add     sp, sp, #32

    // Write operation-specific data
    cmp     x19, #WAL_OP_PUT
    b.eq    .Lwal_append_put_data
    cmp     x19, #WAL_OP_DELETE
    b.eq    .Lwal_append_delete_data
    b       .Lwal_append_success

.Lwal_append_put_data:
    // Write: doc_id, offset placeholder, content_len, content
    sub     sp, sp, #32
    str     x20, [sp, #0]       // doc_id
    str     xzr, [sp, #8]       // offset (filled later)
    str     w22, [sp, #16]      // content_len

    ldr     x0, [x23, #WAL_STATE_OFF_FD]
    mov     x1, sp
    mov     x2, #20
    bl      sys_write
    cmp     x0, #20
    b.ne    .Lwal_append_error_sp32

    add     sp, sp, #32

    // Write content
    cbz     x22, .Lwal_append_success

    ldr     x0, [x23, #WAL_STATE_OFF_FD]
    mov     x1, x21
    mov     x2, x22
    bl      sys_write
    cmp     x0, x22
    b.ne    .Lwal_append_error
    b       .Lwal_append_success

.Lwal_append_delete_data:
    // Write doc_id only
    sub     sp, sp, #16
    str     x20, [sp]

    ldr     x0, [x23, #WAL_STATE_OFF_FD]
    mov     x1, sp
    mov     x2, #8
    bl      sys_write
    add     sp, sp, #16

    cmp     x0, #8
    b.ne    .Lwal_append_error

.Lwal_append_success:
    // Update size
    ldr     x0, [x23, #WAL_STATE_OFF_SIZE]
    add     x0, x0, x25
    str     x0, [x23, #WAL_STATE_OFF_SIZE]

    // Return sequence number
    mov     x0, x24
    b       .Lwal_append_done

.Lwal_append_error_sp32:
    add     sp, sp, #32
.Lwal_append_error:
    mov     x0, #-EIO

.Lwal_append_done:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size wal_append, . - wal_append

// =============================================================================
// wal_sync - Sync WAL to disk
//
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global wal_sync
.type wal_sync, %function
wal_sync:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, g_wal_state
    add     x0, x0, :lo12:g_wal_state
    ldr     x0, [x0, #WAL_STATE_OFF_FD]
    cbz     x0, .Lwal_sync_not_open

    bl      sys_fsync
    b       .Lwal_sync_done

.Lwal_sync_not_open:
    mov     x0, #0

.Lwal_sync_done:
    ldp     x29, x30, [sp], #16
    ret
.size wal_sync, . - wal_sync

// =============================================================================
// wal_checkpoint - Write commit marker and sync
//
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global wal_checkpoint
.type wal_checkpoint, %function
wal_checkpoint:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Append commit marker
    mov     x0, #WAL_OP_COMMIT
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    bl      wal_append
    cmp     x0, #0
    b.lt    .Lwal_cp_done

    // Sync
    bl      wal_sync

.Lwal_cp_done:
    ldp     x29, x30, [sp], #16
    ret
.size wal_checkpoint, . - wal_checkpoint

// =============================================================================
// wal_truncate - Truncate WAL after successful checkpoint
//
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global wal_truncate
.type wal_truncate, %function
wal_truncate:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, g_wal_state
    add     x0, x0, :lo12:g_wal_state
    ldr     x1, [x0, #WAL_STATE_OFF_FD]
    cbz     x1, .Lwal_trunc_not_open

    // Truncate to zero
    mov     x0, x1
    mov     x1, #0
    bl      sys_ftruncate
    cmp     x0, #0
    b.lt    .Lwal_trunc_done

    // Reset state
    adrp    x0, g_wal_state
    add     x0, x0, :lo12:g_wal_state
    str     xzr, [x0, #WAL_STATE_OFF_SIZE]
    // Keep sequence number for monotonicity

    mov     x0, #0
    b       .Lwal_trunc_done

.Lwal_trunc_not_open:
    mov     x0, #0

.Lwal_trunc_done:
    ldp     x29, x30, [sp], #16
    ret
.size wal_truncate, . - wal_truncate

// =============================================================================
// wal_recover - Replay uncommitted WAL entries
//
// Input:
//   x0 = callback function pointer
//        callback(op, doc_id, data, len) -> 0 or error
// Output:
//   x0 = 0 on success, negative errno on error
//
// Calls callback for each uncommitted entry. Stops at COMMIT marker.
// =============================================================================
.global wal_recover
.type wal_recover, %function
wal_recover:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // callback

    adrp    x20, g_wal_state
    add     x20, x20, :lo12:g_wal_state

    ldr     x21, [x20, #WAL_STATE_OFF_SIZE]
    cbz     x21, .Lwal_recover_success  // Empty WAL

    // Seek to beginning
    ldr     x0, [x20, #WAL_STATE_OFF_FD]
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    mov     x22, #0             // offset

.Lwal_recover_loop:
    cmp     x22, x21
    b.ge    .Lwal_recover_success

    // Read header
    sub     sp, sp, #32
    ldr     x0, [x20, #WAL_STATE_OFF_FD]
    mov     x1, sp
    mov     x2, #WAL_HDR_SIZE
    bl      sys_read
    cmp     x0, #WAL_HDR_SIZE
    b.ne    .Lwal_recover_read_error

    // Verify magic
    ldr     w0, [sp, #WAL_OFF_MAGIC]
    ldr     w1, =WAL_MAGIC
    cmp     w0, w1
    b.ne    .Lwal_recover_corrupt

    // Get operation and length
    ldr     w23, [sp, #WAL_OFF_OP]
    ldr     w24, [sp, #WAL_OFF_LENGTH]
    add     sp, sp, #32

    // Check for commit marker
    cmp     x23, #WAL_OP_COMMIT
    b.eq    .Lwal_recover_success

    // Read operation data
    sub     x0, x24, #WAL_HDR_SIZE
    cbz     x0, .Lwal_recover_next

    // Allocate buffer for data
    sub     sp, sp, x0
    mov     x1, sp
    ldr     x0, [x20, #WAL_STATE_OFF_FD]
    sub     x2, x24, #WAL_HDR_SIZE
    bl      sys_read

    // Call callback
    mov     x0, x23             // op
    ldr     x1, [sp]            // doc_id
    add     x2, sp, #8          // data ptr
    sub     x3, x24, #WAL_HDR_SIZE
    sub     x3, x3, #8          // data len (minus doc_id)
    blr     x19

    sub     x1, x24, #WAL_HDR_SIZE
    add     sp, sp, x1

    cmp     x0, #0
    b.lt    .Lwal_recover_done

.Lwal_recover_next:
    add     x22, x22, x24
    b       .Lwal_recover_loop

.Lwal_recover_read_error:
    add     sp, sp, #32
.Lwal_recover_corrupt:
    mov     x0, #-EIO
    b       .Lwal_recover_done

.Lwal_recover_success:
    mov     x0, #0

.Lwal_recover_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size wal_recover, . - wal_recover

// =============================================================================
// wal_close - Close WAL file
//
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global wal_close
.type wal_close, %function
wal_close:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    adrp    x19, g_wal_state
    add     x19, x19, :lo12:g_wal_state

    ldr     x0, [x19, #WAL_STATE_OFF_FD]
    cbz     x0, .Lwal_close_not_open

    // Sync first
    bl      sys_fsync

    // Close
    ldr     x0, [x19, #WAL_STATE_OFF_FD]
    bl      sys_close

    // Zero state
    str     xzr, [x19, #WAL_STATE_OFF_FD]
    str     xzr, [x19, #WAL_STATE_OFF_SIZE]

.Lwal_close_not_open:
    mov     x0, #0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size wal_close, . - wal_close

// =============================================================================
// wal_get_seq - Get current sequence number
//
// Output:
//   x0 = current sequence number
// =============================================================================
.global wal_get_seq
.type wal_get_seq, %function
wal_get_seq:
    adrp    x0, g_wal_state
    add     x0, x0, :lo12:g_wal_state
    ldr     x0, [x0, #WAL_STATE_OFF_SEQ]
    ret
.size wal_get_seq, . - wal_get_seq

// =============================================================================
// BSS Section - Global state
// =============================================================================

.section .bss
.balign 8

.global g_wal_state
g_wal_state:
    .skip   WAL_STATE_SIZE

// =============================================================================
// End of wal.s
// =============================================================================
