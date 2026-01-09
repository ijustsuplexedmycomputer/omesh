// =============================================================================
// Omesh - docs.s
// Document storage - append-only log with CRC32 checksums
// =============================================================================
//
// Provides persistent document storage using an append-only log.
// Documents are written sequentially with headers containing:
//   - Magic number for validation
//   - Document ID
//   - Timestamp
//   - Flags (deleted, compressed)
//   - CRC32 checksum
//
// Reads use mmap for efficiency; writes append to the file.
// Deletion marks the flags field; compaction removes deleted records.
//
// CALLING CONVENTION: AAPCS64
//   - Arguments: x0-x7 (x0 = first arg)
//   - Return value: x0
//   - Callee-saved: x19-x28
//   - Caller-saved: x0-x18
//
// ERROR HANDLING:
//   - Returns 0 on success, negative errno on failure
//   - -ENOENT (-2): Document not found
//   - -EINVAL (-22): Invalid document or corrupted data
//   - -ENOSPC (-28): No space left on device
//
// PUBLIC API:
//
//   doc_store_init(path) -> 0 | -errno
//       Initialize document storage from file at path.
//       Creates file if it doesn't exist.
//       Must be called before other doc_store_* functions.
//
//   doc_store_put(doc_id, data_ptr, data_len) -> 0 | -errno
//       Store document with given ID and content.
//       Appends to log with header and CRC32 checksum.
//
//   doc_store_get(doc_id, buf_ptr, buf_len) -> bytes_read | -errno
//       Read document into buffer.
//       Returns number of bytes read on success.
//       Returns -ENOENT if document not found or deleted.
//
//   doc_store_delete(doc_id) -> 0 | -errno
//       Mark document as deleted (tombstone).
//       Space reclaimed on compaction.
//
//   doc_store_close() -> 0 | -errno
//       Flush and close document storage.
//
// DOCUMENT HEADER (see store.inc for offsets):
//   [0-3]   Magic (0x44434F4D = "DOCD")
//   [4-11]  Document ID
//   [12-19] Timestamp (ns since epoch)
//   [20-23] Flags
//   [24-27] Data length
//   [28-31] CRC32 checksum
//   [32+]   Document data
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/store.inc"

// Import HAL functions
.extern sys_openat
.extern sys_close
.extern sys_read
.extern sys_write
.extern sys_lseek
.extern sys_fsync
.extern sys_ftruncate
.extern sys_mmap
.extern sys_munmap
.extern sys_clock_gettime
.extern g_features

.text
.balign 4

// =============================================================================
// doc_store_init - Initialize document storage
//
// Input:
//   x0 = path to docs.dat file (null-terminated)
// Output:
//   x0 = 0 on success, negative errno on error
//
// Opens or creates the document storage file, mmaps it for reading,
// and initializes the global state.
// =============================================================================
.global doc_store_init
.type doc_store_init, %function
doc_store_init:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // Save path

    // Open file with O_RDWR | O_CREAT
    mov     x0, #AT_FDCWD
    mov     x1, x19
    mov     x2, #(O_RDWR | O_CREAT)
    mov     x3, #0644
    bl      sys_openat
    cmp     x0, #0
    b.lt    .Lds_init_error

    mov     x20, x0             // Save fd

    // Get file size with lseek to end
    mov     x1, #0
    mov     x2, #SEEK_END
    bl      sys_lseek
    cmp     x0, #0
    b.lt    .Lds_init_close_error

    mov     x21, x0             // File size
    mov     x22, x0             // Write position = end

    // Seek back to beginning
    mov     x0, x20
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    // If file is empty, initialize next_id to 1
    mov     x23, #1             // next_doc_id

    // If file has content, scan to find highest doc_id
    cbz     x21, .Lds_init_mmap

    // mmap the file for reading
    mov     x0, #0              // addr hint
    mov     x1, x21             // length
    mov     x2, #PROT_READ
    mov     x3, #MAP_PRIVATE
    mov     x4, x20             // fd
    mov     x5, #0              // offset
    bl      sys_mmap

    // Check for mmap error (returns addr or negative errno)
    cmn     x0, #4096
    b.hi    .Lds_init_mmap_error

    mov     x24, x0             // mmap base

    // Scan documents to find highest ID
    mov     x0, x24             // base
    mov     x1, x21             // size
    bl      doc_store_scan_max_id
    add     x23, x0, #1         // next_id = max_id + 1
    b       .Lds_init_store_state

.Lds_init_mmap:
    // Empty file - no mmap yet
    mov     x24, #0             // No mmap

.Lds_init_store_state:
    // Store state in global structure
    adrp    x0, g_doc_store
    add     x0, x0, :lo12:g_doc_store
    str     x20, [x0, #DOCSTORE_OFF_FD]
    str     x22, [x0, #DOCSTORE_OFF_WRITE_POS]
    str     x21, [x0, #DOCSTORE_OFF_FILE_SIZE]
    str     x24, [x0, #DOCSTORE_OFF_MMAP_BASE]
    str     x21, [x0, #DOCSTORE_OFF_MMAP_SIZE]
    str     x23, [x0, #DOCSTORE_OFF_NEXT_ID]

    mov     x0, #0
    b       .Lds_init_done

.Lds_init_mmap_error:
    mov     x19, x0             // Save error
    mov     x0, x20
    bl      sys_close
    mov     x0, x19
    b       .Lds_init_done

.Lds_init_close_error:
    mov     x19, x0             // Save error
    mov     x0, x20
    bl      sys_close
    mov     x0, x19
    b       .Lds_init_done

.Lds_init_error:
    // x0 already has error

.Lds_init_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size doc_store_init, . - doc_store_init

// =============================================================================
// doc_store_put - Store a new document
//
// Input:
//   x0 = content pointer
//   x1 = content length
//   x2 = pointer to receive document ID (8 bytes)
// Output:
//   x0 = file offset of record on success, negative errno on error
//
// Appends a new document record to the file.
// =============================================================================
.global doc_store_put
.type doc_store_put, %function
doc_store_put:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0             // content ptr
    mov     x20, x1             // content len
    mov     x21, x2             // out_id ptr

    // Load store state
    adrp    x22, g_doc_store
    add     x22, x22, :lo12:g_doc_store

    // Check content size
    mov     x0, #DOC_MAX_SIZE
    cmp     x20, x0
    b.gt    .Lds_put_too_big

    // Allocate doc ID
    ldr     x23, [x22, #DOCSTORE_OFF_NEXT_ID]
    add     x0, x23, #1
    str     x0, [x22, #DOCSTORE_OFF_NEXT_ID]

    // Store doc ID to output
    cbz     x21, .Lds_put_skip_out_id
    str     x23, [x21]
.Lds_put_skip_out_id:

    // Calculate CRC32 of content
    mov     x0, x19
    mov     x1, x20
    bl      crc32_calc
    mov     x24, x0             // CRC32

    // Get current timestamp
    sub     sp, sp, #16
    mov     x0, #CLOCK_REALTIME
    mov     x1, sp
    bl      sys_clock_gettime
    ldr     x25, [sp]           // seconds
    add     sp, sp, #16

    // Save current write position (this is our return value)
    ldr     x26, [x22, #DOCSTORE_OFF_WRITE_POS]

    // Build header on stack (28 bytes, aligned to 32)
    sub     sp, sp, #32
    ldr     w0, =DOC_MAGIC
    str     w0, [sp, #DOC_OFF_MAGIC]
    add     w0, w20, #DOC_HDR_SIZE
    str     w0, [sp, #DOC_OFF_LENGTH]
    str     x23, [sp, #DOC_OFF_ID]
    str     w25, [sp, #DOC_OFF_TIMESTAMP]
    str     wzr, [sp, #DOC_OFF_FLAGS]
    str     w24, [sp, #DOC_OFF_CHECKSUM]

    // Write header
    ldr     x0, [x22, #DOCSTORE_OFF_FD]
    mov     x1, sp
    mov     x2, #DOC_HDR_SIZE
    bl      sys_write
    cmp     x0, #DOC_HDR_SIZE
    b.ne    .Lds_put_write_error

    add     sp, sp, #32

    // Write content
    ldr     x0, [x22, #DOCSTORE_OFF_FD]
    mov     x1, x19
    mov     x2, x20
    bl      sys_write
    cmp     x0, x20
    b.ne    .Lds_put_write_error2

    // Update write position
    add     x0, x20, #DOC_HDR_SIZE
    ldr     x1, [x22, #DOCSTORE_OFF_WRITE_POS]
    add     x1, x1, x0
    str     x1, [x22, #DOCSTORE_OFF_WRITE_POS]
    str     x1, [x22, #DOCSTORE_OFF_FILE_SIZE]

    // Return the offset where we wrote the record
    mov     x0, x26
    b       .Lds_put_done

.Lds_put_too_big:
    mov     x0, #-EFBIG
    b       .Lds_put_done

.Lds_put_write_error:
    add     sp, sp, #32
.Lds_put_write_error2:
    mov     x0, #-EIO
    b       .Lds_put_done

.Lds_put_done:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret
.size doc_store_put, . - doc_store_put

// =============================================================================
// doc_store_get - Retrieve a document by offset
//
// Input:
//   x0 = file offset of document record
//   x1 = output buffer pointer
//   x2 = output buffer size
// Output:
//   x0 = bytes copied on success, negative errno on error
//
// Reads document from mmap, verifies magic and checksum.
// =============================================================================
.global doc_store_get
.type doc_store_get, %function
doc_store_get:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // offset
    mov     x20, x1             // out buf
    mov     x21, x2             // buf size

    // Load store state
    adrp    x22, g_doc_store
    add     x22, x22, :lo12:g_doc_store

    // Check if we need to remap (file grew since last mmap)
    ldr     x0, [x22, #DOCSTORE_OFF_MMAP_BASE]
    cbz     x0, .Lds_get_remap

    ldr     x1, [x22, #DOCSTORE_OFF_FILE_SIZE]
    ldr     x2, [x22, #DOCSTORE_OFF_MMAP_SIZE]
    cmp     x1, x2
    b.gt    .Lds_get_remap
    b       .Lds_get_check_bounds

.Lds_get_remap:
    bl      doc_store_remap
    cmp     x0, #0
    b.lt    .Lds_get_done

.Lds_get_check_bounds:
    // Check offset is within file
    ldr     x0, [x22, #DOCSTORE_OFF_FILE_SIZE]
    add     x1, x19, #DOC_HDR_SIZE
    cmp     x1, x0
    b.gt    .Lds_get_invalid

    // Get pointer to record
    ldr     x23, [x22, #DOCSTORE_OFF_MMAP_BASE]
    add     x23, x23, x19       // record ptr

    // Verify magic
    ldr     w0, [x23, #DOC_OFF_MAGIC]
    ldr     w1, =DOC_MAGIC
    cmp     w0, w1
    b.ne    .Lds_get_corrupt

    // Check if deleted
    ldr     w0, [x23, #DOC_OFF_FLAGS]
    tst     w0, #DOC_FLAG_DELETED
    b.ne    .Lds_get_deleted

    // Get content length
    ldr     w24, [x23, #DOC_OFF_LENGTH]
    sub     w24, w24, #DOC_HDR_SIZE

    // Check buffer size
    cmp     x21, x24
    b.lt    .Lds_get_too_small

    // Verify CRC32
    add     x0, x23, #DOC_OFF_CONTENT
    mov     x1, x24
    bl      crc32_calc
    ldr     w1, [x23, #DOC_OFF_CHECKSUM]
    cmp     w0, w1
    b.ne    .Lds_get_corrupt

    // Copy content to output buffer
    mov     x0, x20
    add     x1, x23, #DOC_OFF_CONTENT
    mov     x2, x24
    bl      memcpy

    // Return content length
    mov     x0, x24
    b       .Lds_get_done

.Lds_get_invalid:
    mov     x0, #-EINVAL
    b       .Lds_get_done

.Lds_get_corrupt:
    mov     x0, #-EIO
    b       .Lds_get_done

.Lds_get_deleted:
    mov     x0, #-ENOENT
    b       .Lds_get_done

.Lds_get_too_small:
    mov     x0, #-ENOBUFS
    b       .Lds_get_done

.Lds_get_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size doc_store_get, . - doc_store_get

// =============================================================================
// doc_store_get_header - Get document header info without copying content
//
// Input:
//   x0 = file offset
//   x1 = pointer to receive doc_id (8 bytes)
//   x2 = pointer to receive content_len (8 bytes)
//   x3 = pointer to receive flags (4 bytes)
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global doc_store_get_header
.type doc_store_get_header, %function
doc_store_get_header:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // offset
    mov     x20, x1             // out_id
    mov     x21, x2             // out_len
    mov     x22, x3             // out_flags

    // Load store state
    adrp    x0, g_doc_store
    add     x0, x0, :lo12:g_doc_store
    ldr     x1, [x0, #DOCSTORE_OFF_MMAP_BASE]
    cbz     x1, .Ldgh_no_mmap

    // Get record pointer
    add     x1, x1, x19

    // Verify magic
    ldr     w2, [x1, #DOC_OFF_MAGIC]
    ldr     w3, =DOC_MAGIC
    cmp     w2, w3
    b.ne    .Ldgh_corrupt

    // Extract doc_id
    cbz     x20, .Ldgh_skip_id
    ldr     x2, [x1, #DOC_OFF_ID]
    str     x2, [x20]
.Ldgh_skip_id:

    // Extract content length
    cbz     x21, .Ldgh_skip_len
    ldr     w2, [x1, #DOC_OFF_LENGTH]
    sub     w2, w2, #DOC_HDR_SIZE
    str     x2, [x21]
.Ldgh_skip_len:

    // Extract flags
    cbz     x22, .Ldgh_skip_flags
    ldr     w2, [x1, #DOC_OFF_FLAGS]
    str     w2, [x22]
.Ldgh_skip_flags:

    mov     x0, #0
    b       .Ldgh_done

.Ldgh_no_mmap:
    mov     x0, #-ENOENT
    b       .Ldgh_done

.Ldgh_corrupt:
    mov     x0, #-EIO

.Ldgh_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size doc_store_get_header, . - doc_store_get_header

// =============================================================================
// doc_store_mark_deleted - Mark a document as deleted
//
// Input:
//   x0 = file offset of document record
// Output:
//   x0 = 0 on success, negative errno on error
//
// Sets the DELETED flag in the document header.
// Does not reclaim space - that's done by compaction.
// =============================================================================
.global doc_store_mark_deleted
.type doc_store_mark_deleted, %function
doc_store_mark_deleted:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // offset

    // Load store state
    adrp    x20, g_doc_store
    add     x20, x20, :lo12:g_doc_store

    // Seek to flags field
    ldr     x0, [x20, #DOCSTORE_OFF_FD]
    add     x1, x19, #DOC_OFF_FLAGS
    mov     x2, #SEEK_SET
    bl      sys_lseek
    cmp     x0, #0
    b.lt    .Lds_del_done

    // Read current flags
    sub     sp, sp, #16
    ldr     x0, [x20, #DOCSTORE_OFF_FD]
    mov     x1, sp
    mov     x2, #4
    bl      sys_read
    cmp     x0, #4
    b.ne    .Lds_del_read_error

    // Set deleted flag
    ldr     w0, [sp]
    orr     w0, w0, #DOC_FLAG_DELETED
    str     w0, [sp]

    // Seek back
    ldr     x0, [x20, #DOCSTORE_OFF_FD]
    add     x1, x19, #DOC_OFF_FLAGS
    mov     x2, #SEEK_SET
    bl      sys_lseek

    // Write updated flags
    ldr     x0, [x20, #DOCSTORE_OFF_FD]
    mov     x1, sp
    mov     x2, #4
    bl      sys_write
    cmp     x0, #4
    b.ne    .Lds_del_write_error

    add     sp, sp, #16
    mov     x0, #0
    b       .Lds_del_done

.Lds_del_read_error:
.Lds_del_write_error:
    add     sp, sp, #16
    mov     x0, #-EIO

.Lds_del_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size doc_store_mark_deleted, . - doc_store_mark_deleted

// =============================================================================
// doc_store_sync - Sync document store to disk
//
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global doc_store_sync
.type doc_store_sync, %function
doc_store_sync:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, g_doc_store
    add     x0, x0, :lo12:g_doc_store
    ldr     x0, [x0, #DOCSTORE_OFF_FD]
    bl      sys_fsync

    ldp     x29, x30, [sp], #16
    ret
.size doc_store_sync, . - doc_store_sync

// =============================================================================
// doc_store_close - Close document store
//
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global doc_store_close
.type doc_store_close, %function
doc_store_close:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    adrp    x19, g_doc_store
    add     x19, x19, :lo12:g_doc_store

    // Sync first
    ldr     x0, [x19, #DOCSTORE_OFF_FD]
    bl      sys_fsync

    // Unmap if mapped
    ldr     x0, [x19, #DOCSTORE_OFF_MMAP_BASE]
    cbz     x0, .Lds_close_no_unmap
    ldr     x1, [x19, #DOCSTORE_OFF_MMAP_SIZE]
    bl      sys_munmap

.Lds_close_no_unmap:
    // Close fd
    ldr     x0, [x19, #DOCSTORE_OFF_FD]
    bl      sys_close

    // Zero the state
    str     xzr, [x19, #DOCSTORE_OFF_FD]
    str     xzr, [x19, #DOCSTORE_OFF_MMAP_BASE]

    mov     x0, #0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size doc_store_close, . - doc_store_close

// =============================================================================
// doc_store_remap - Remap file after growth
//
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.type doc_store_remap, %function
doc_store_remap:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    adrp    x19, g_doc_store
    add     x19, x19, :lo12:g_doc_store

    // Unmap old mapping if exists
    ldr     x0, [x19, #DOCSTORE_OFF_MMAP_BASE]
    cbz     x0, .Lds_remap_new
    ldr     x1, [x19, #DOCSTORE_OFF_MMAP_SIZE]
    bl      sys_munmap

.Lds_remap_new:
    // Get current file size
    ldr     x20, [x19, #DOCSTORE_OFF_FILE_SIZE]
    cbz     x20, .Lds_remap_empty

    // Create new mapping
    mov     x0, #0              // addr hint
    mov     x1, x20             // length
    mov     x2, #PROT_READ
    mov     x3, #MAP_PRIVATE
    ldr     x4, [x19, #DOCSTORE_OFF_FD]
    mov     x5, #0              // offset
    bl      sys_mmap

    cmn     x0, #4096
    b.hi    .Lds_remap_error

    str     x0, [x19, #DOCSTORE_OFF_MMAP_BASE]
    str     x20, [x19, #DOCSTORE_OFF_MMAP_SIZE]
    mov     x0, #0
    b       .Lds_remap_done

.Lds_remap_empty:
    str     xzr, [x19, #DOCSTORE_OFF_MMAP_BASE]
    str     xzr, [x19, #DOCSTORE_OFF_MMAP_SIZE]
    mov     x0, #0
    b       .Lds_remap_done

.Lds_remap_error:
    // x0 has error

.Lds_remap_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size doc_store_remap, . - doc_store_remap

// =============================================================================
// doc_store_scan_max_id - Scan file to find highest document ID
//
// Input:
//   x0 = mmap base
//   x1 = file size
// Output:
//   x0 = highest document ID found (0 if empty/error)
// =============================================================================
.type doc_store_scan_max_id, %function
doc_store_scan_max_id:
    mov     x2, x0              // current ptr
    add     x3, x0, x1          // end ptr
    mov     x4, #0              // max id

.Lscan_loop:
    // Need at least header size remaining
    add     x5, x2, #DOC_HDR_SIZE
    cmp     x5, x3
    b.gt    .Lscan_done

    // Check magic
    ldr     w6, [x2, #DOC_OFF_MAGIC]
    ldr     w7, =DOC_MAGIC
    cmp     w6, w7
    b.ne    .Lscan_done         // Corrupt, stop

    // Get doc ID
    ldr     x6, [x2, #DOC_OFF_ID]
    cmp     x6, x4
    csel    x4, x6, x4, gt      // max = max(max, id)

    // Get record length and advance
    ldr     w6, [x2, #DOC_OFF_LENGTH]
    add     x2, x2, x6
    b       .Lscan_loop

.Lscan_done:
    mov     x0, x4
    ret
.size doc_store_scan_max_id, . - doc_store_scan_max_id

// =============================================================================
// CRC32 Functions
// Uses hardware CRC32 instruction if available, otherwise software fallback
// =============================================================================

// -----------------------------------------------------------------------------
// crc32_calc - Calculate CRC32 of data
//
// Input:
//   x0 = data pointer
//   x1 = data length
// Output:
//   x0 = CRC32 value
// -----------------------------------------------------------------------------
.global crc32_calc
.type crc32_calc, %function
crc32_calc:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Check for hardware CRC32 support
    adrp    x2, g_features
    add     x2, x2, :lo12:g_features
    ldr     x3, [x2, #FEAT_OFF_FLAGS]
    tbnz    x3, #FEAT_BIT_CRC32, .Lcrc_hw

    // Software fallback
    bl      crc32_sw
    b       .Lcrc_done

.Lcrc_hw:
    bl      crc32_hw

.Lcrc_done:
    ldp     x29, x30, [sp], #16
    ret
.size crc32_calc, . - crc32_calc

// -----------------------------------------------------------------------------
// crc32_hw - Hardware CRC32C (Castagnoli) implementation
//
// Input:
//   x0 = data pointer
//   x1 = data length
// Output:
//   x0 = CRC32 value
// -----------------------------------------------------------------------------
.type crc32_hw, %function
crc32_hw:
    mov     w2, #CRC32_INIT     // Initial CRC

    // Process 8 bytes at a time
.Lcrc_hw_8:
    cmp     x1, #8
    b.lt    .Lcrc_hw_1
    ldr     x3, [x0], #8
    crc32cx w2, w2, x3
    sub     x1, x1, #8
    b       .Lcrc_hw_8

    // Process remaining bytes
.Lcrc_hw_1:
    cbz     x1, .Lcrc_hw_done
    ldrb    w3, [x0], #1
    crc32cb w2, w2, w3
    sub     x1, x1, #1
    b       .Lcrc_hw_1

.Lcrc_hw_done:
    mvn     w0, w2              // Final XOR
    ret
.size crc32_hw, . - crc32_hw

// -----------------------------------------------------------------------------
// crc32_sw - Software CRC32 implementation (table-based)
//
// Input:
//   x0 = data pointer
//   x1 = data length
// Output:
//   x0 = CRC32 value
// -----------------------------------------------------------------------------
.type crc32_sw, %function
crc32_sw:
    mov     w2, #CRC32_INIT     // Initial CRC
    adrp    x3, crc32_table
    add     x3, x3, :lo12:crc32_table

.Lcrc_sw_loop:
    cbz     x1, .Lcrc_sw_done
    ldrb    w4, [x0], #1        // Next byte
    eor     w5, w2, w4          // crc ^ byte
    and     w5, w5, #0xFF       // Index into table
    lsl     w5, w5, #2          // * 4 for word offset
    ldr     w6, [x3, w5, uxtw]  // table[index]
    lsr     w2, w2, #8          // crc >> 8
    eor     w2, w2, w6          // ^ table[index]
    sub     x1, x1, #1
    b       .Lcrc_sw_loop

.Lcrc_sw_done:
    mvn     w0, w2              // Final XOR
    ret
.size crc32_sw, . - crc32_sw

// =============================================================================
// memcpy - Copy memory
//
// Input:
//   x0 = dest
//   x1 = src
//   x2 = len
// Output:
//   x0 = dest
// =============================================================================
.global memcpy
.type memcpy, %function
memcpy:
    mov     x3, x0              // Save dest for return

    // Copy 8 bytes at a time
.Lmemcpy_8:
    cmp     x2, #8
    b.lt    .Lmemcpy_1
    ldr     x4, [x1], #8
    str     x4, [x0], #8
    sub     x2, x2, #8
    b       .Lmemcpy_8

    // Copy remaining bytes
.Lmemcpy_1:
    cbz     x2, .Lmemcpy_done
    ldrb    w4, [x1], #1
    strb    w4, [x0], #1
    sub     x2, x2, #1
    b       .Lmemcpy_1

.Lmemcpy_done:
    mov     x0, x3
    ret
.size memcpy, . - memcpy

// =============================================================================
// memcmp - Compare memory
//
// Input:
//   x0 = ptr1
//   x1 = ptr2
//   x2 = len
// Output:
//   x0 = 0 if equal, <0 if ptr1<ptr2, >0 if ptr1>ptr2
// =============================================================================
.global memcmp
.type memcmp, %function
memcmp:
.Lmemcmp_loop:
    cbz     x2, .Lmemcmp_equal
    ldrb    w3, [x0], #1
    ldrb    w4, [x1], #1
    sub     x2, x2, #1
    cmp     w3, w4
    b.eq    .Lmemcmp_loop
    sub     w0, w3, w4
    ret

.Lmemcmp_equal:
    mov     x0, #0
    ret
.size memcmp, . - memcmp

// =============================================================================
// memset - Fill memory with byte
//
// Input:
//   x0 = dest
//   x1 = byte value
//   x2 = len
// Output:
//   x0 = dest
// =============================================================================
.global memset
.type memset, %function
memset:
    mov     x3, x0              // Save dest

    // Broadcast byte to 8-byte value
    and     x1, x1, #0xFF
    mov     x4, #0x0101010101010101
    mul     x4, x1, x4

    // Fill 8 bytes at a time
.Lmemset_8:
    cmp     x2, #8
    b.lt    .Lmemset_1
    str     x4, [x0], #8
    sub     x2, x2, #8
    b       .Lmemset_8

    // Fill remaining bytes
.Lmemset_1:
    cbz     x2, .Lmemset_done
    strb    w1, [x0], #1
    sub     x2, x2, #1
    b       .Lmemset_1

.Lmemset_done:
    mov     x0, x3
    ret
.size memset, . - memset

// =============================================================================
// BSS Section - Global state
// =============================================================================

.section .bss
.balign 8

.global g_doc_store
g_doc_store:
    .skip   DOCSTORE_SIZE

// =============================================================================
// Read-only data - CRC32 lookup table
// =============================================================================

.section .rodata
.balign 4

// CRC32 lookup table (IEEE 802.3 polynomial, reflected)
crc32_table:
    .word 0x00000000, 0x77073096, 0xee0e612c, 0x990951ba
    .word 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3
    .word 0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988
    .word 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91
    .word 0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de
    .word 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7
    .word 0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec
    .word 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5
    .word 0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172
    .word 0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b
    .word 0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940
    .word 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59
    .word 0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116
    .word 0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f
    .word 0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924
    .word 0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d
    .word 0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a
    .word 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433
    .word 0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818
    .word 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01
    .word 0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e
    .word 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457
    .word 0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c
    .word 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65
    .word 0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2
    .word 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb
    .word 0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0
    .word 0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9
    .word 0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086
    .word 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f
    .word 0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4
    .word 0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad
    .word 0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a
    .word 0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683
    .word 0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8
    .word 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1
    .word 0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe
    .word 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7
    .word 0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc
    .word 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5
    .word 0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252
    .word 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b
    .word 0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60
    .word 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79
    .word 0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236
    .word 0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f
    .word 0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04
    .word 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d
    .word 0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a
    .word 0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713
    .word 0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38
    .word 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21
    .word 0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e
    .word 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777
    .word 0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c
    .word 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45
    .word 0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2
    .word 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db
    .word 0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0
    .word 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9
    .word 0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6
    .word 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf
    .word 0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94
    .word 0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d

// =============================================================================
// End of docs.s
// =============================================================================
