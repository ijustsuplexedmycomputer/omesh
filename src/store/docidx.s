// =============================================================================
// Omesh - docidx.s
// Document index - sorted array with binary search
// =============================================================================
//
// Maintains a sorted mapping from document IDs to file offsets.
// Enables O(log n) lookup of documents.
//
// The index consists of:
//   - On-disk sorted array (mmap'd for reads)
//   - In-memory buffer for pending inserts
//   - Periodic merge of buffer to disk
//
// Index file format:
//   Header (16 bytes):
//     [4] Magic: "DIDX"
//     [4] Version
//     [8] Entry count
//   Entries (16 bytes each, sorted by doc_id):
//     [8] Document ID
//     [8] File offset (-1 if deleted)
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/store.inc"

// Import syscall wrappers
.extern sys_openat
.extern sys_close
.extern sys_read
.extern sys_write
.extern sys_lseek
.extern sys_fsync
.extern sys_ftruncate
.extern sys_mmap
.extern sys_munmap
.extern sys_madvise
.extern memcpy
.extern memcmp

.text
.balign 4

// =============================================================================
// doc_index_init - Initialize document index
//
// Input:
//   x0 = path to docs.idx file
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global doc_index_init
.type doc_index_init, %function
doc_index_init:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // path

    // Open with O_RDWR | O_CREAT
    mov     x0, #AT_FDCWD
    mov     x1, x19
    mov     x2, #(O_RDWR | O_CREAT)
    mov     x3, #0644
    bl      sys_openat
    cmp     x0, #0
    b.lt    .Ldi_init_error

    mov     x20, x0             // fd

    // Get file size
    mov     x1, #0
    mov     x2, #SEEK_END
    bl      sys_lseek
    cmp     x0, #0
    b.lt    .Ldi_init_close_error

    mov     x21, x0             // file size

    // If empty, write header
    cbnz    x21, .Ldi_init_load

    // Seek to beginning
    mov     x0, x20
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    // Write header
    sub     sp, sp, #16
    ldr     w0, =IDX_MAGIC
    str     w0, [sp, #IDX_HDR_MAGIC]
    mov     w0, #IDX_VERSION
    str     w0, [sp, #IDX_HDR_VERSION]
    str     xzr, [sp, #IDX_HDR_COUNT]

    mov     x0, x20
    mov     x1, sp
    mov     x2, #IDX_HDR_SIZE
    bl      sys_write
    add     sp, sp, #16

    cmp     x0, #IDX_HDR_SIZE
    b.ne    .Ldi_init_close_error

    mov     x21, #IDX_HDR_SIZE  // new file size
    mov     x22, #0             // entry count
    b       .Ldi_init_mmap

.Ldi_init_load:
    // Verify file has at least header
    cmp     x21, #IDX_HDR_SIZE
    b.lt    .Ldi_init_corrupt

    // Read header to verify magic
    mov     x0, x20
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    sub     sp, sp, #16
    mov     x0, x20
    mov     x1, sp
    mov     x2, #IDX_HDR_SIZE
    bl      sys_read
    cmp     x0, #IDX_HDR_SIZE
    b.ne    .Ldi_init_read_error

    // Verify magic
    ldr     w0, [sp, #IDX_HDR_MAGIC]
    ldr     w1, =IDX_MAGIC
    cmp     w0, w1
    b.ne    .Ldi_init_magic_error

    // Load entry count
    ldr     x22, [sp, #IDX_HDR_COUNT]
    add     sp, sp, #16

.Ldi_init_mmap:
    // mmap the file
    cbz     x21, .Ldi_init_no_mmap
    mov     x0, #0
    mov     x1, x21
    mov     x2, #PROT_READ
    mov     x3, #MAP_PRIVATE
    mov     x4, x20
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Ldi_init_mmap_error
    mov     x23, x0
    b       .Ldi_init_alloc_buf

.Ldi_init_no_mmap:
    mov     x23, #0

.Ldi_init_alloc_buf:
    // Allocate in-memory buffer for pending inserts
    mov     x0, #0
    mov     x1, #(IDX_BUFFER_CAPACITY * IDX_ENTRY_SIZE)
    mov     x2, #(PROT_READ | PROT_WRITE)
    mov     x3, #(MAP_PRIVATE | MAP_ANONYMOUS)
    mov     x4, #-1
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Ldi_init_buf_error
    mov     x24, x0             // buffer ptr

    // Store state
    adrp    x0, g_doc_index
    add     x0, x0, :lo12:g_doc_index
    str     x20, [x0, #DOCIDX_OFF_FD]
    str     x23, [x0, #DOCIDX_OFF_MMAP_BASE]
    str     x21, [x0, #DOCIDX_OFF_MMAP_SIZE]
    str     x22, [x0, #DOCIDX_OFF_COUNT]
    mov     x1, #IDX_BUFFER_CAPACITY
    str     x1, [x0, #DOCIDX_OFF_CAPACITY]
    str     xzr, [x0, #DOCIDX_OFF_DIRTY]
    str     x24, [x0, #DOCIDX_OFF_BUF_PTR]
    str     xzr, [x0, #DOCIDX_OFF_BUF_COUNT]

    mov     x0, #0
    b       .Ldi_init_done

.Ldi_init_buf_error:
    mov     x19, x0
    cbz     x23, .Ldi_init_buf_err2
    mov     x0, x23
    mov     x1, x21
    bl      sys_munmap
.Ldi_init_buf_err2:
    mov     x0, x20
    bl      sys_close
    mov     x0, x19
    b       .Ldi_init_done

.Ldi_init_mmap_error:
    mov     x19, x0
    mov     x0, x20
    bl      sys_close
    mov     x0, x19
    b       .Ldi_init_done

.Ldi_init_read_error:
.Ldi_init_magic_error:
    add     sp, sp, #16
.Ldi_init_corrupt:
    mov     x0, #-EIO
    mov     x19, x0
    mov     x0, x20
    bl      sys_close
    mov     x0, x19
    b       .Ldi_init_done

.Ldi_init_close_error:
    mov     x19, x0
    mov     x0, x20
    bl      sys_close
    mov     x0, x19
    b       .Ldi_init_done

.Ldi_init_error:
    // x0 already has error

.Ldi_init_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size doc_index_init, . - doc_index_init

// =============================================================================
// doc_index_lookup - Look up document by ID
//
// Input:
//   x0 = document ID
// Output:
//   x0 = file offset on success, -ENOENT if not found
//
// Searches the buffer first, then the disk index.
// =============================================================================
.global doc_index_lookup
.type doc_index_lookup, %function
doc_index_lookup:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // doc_id

    adrp    x20, g_doc_index
    add     x20, x20, :lo12:g_doc_index

    // First search the in-memory buffer (linear search, it's small)
    ldr     x21, [x20, #DOCIDX_OFF_BUF_PTR]
    ldr     x22, [x20, #DOCIDX_OFF_BUF_COUNT]

    mov     x0, x21             // buffer ptr
    mov     x1, x22             // buffer count
.Ldi_lookup_buf:
    cbz     x1, .Ldi_lookup_disk
    ldr     x2, [x0, #IDX_OFF_DOC_ID]
    cmp     x2, x19
    b.eq    .Ldi_lookup_buf_found
    add     x0, x0, #IDX_ENTRY_SIZE
    sub     x1, x1, #1
    b       .Ldi_lookup_buf

.Ldi_lookup_buf_found:
    ldr     x0, [x0, #IDX_OFF_FILE_OFFSET]
    // Check if deleted
    cmn     x0, #1
    b.eq    .Ldi_lookup_notfound
    b       .Ldi_lookup_done

.Ldi_lookup_disk:
    // Binary search in disk index
    ldr     x0, [x20, #DOCIDX_OFF_MMAP_BASE]
    cbz     x0, .Ldi_lookup_notfound
    ldr     x1, [x20, #DOCIDX_OFF_COUNT]
    cbz     x1, .Ldi_lookup_notfound

    // x0 = mmap base, need to skip header
    add     x0, x0, #IDX_HDR_SIZE
    mov     x2, x19             // doc_id to find
    // x1 = count
    bl      binary_search_index

    cmp     x0, #0
    b.lt    .Ldi_lookup_notfound

    // Found - get the offset
    ldr     x1, [x20, #DOCIDX_OFF_MMAP_BASE]
    add     x1, x1, #IDX_HDR_SIZE
    lsl     x2, x0, #4          // * 16
    add     x1, x1, x2
    ldr     x0, [x1, #IDX_OFF_FILE_OFFSET]

    // Check if deleted
    cmn     x0, #1
    b.eq    .Ldi_lookup_notfound
    b       .Ldi_lookup_done

.Ldi_lookup_notfound:
    mov     x0, #-ENOENT

.Ldi_lookup_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size doc_index_lookup, . - doc_index_lookup

// =============================================================================
// binary_search_index - Binary search in sorted index array
//
// Input:
//   x0 = array base (pointer to first entry)
//   x1 = entry count
//   x2 = doc_id to find
// Output:
//   x0 = index if found, -1 if not found
// =============================================================================
.type binary_search_index, %function
binary_search_index:
    mov     x3, #0              // low
    mov     x4, x1              // high

.Lbs_loop:
    cmp     x3, x4
    b.ge    .Lbs_notfound

    add     x5, x3, x4
    lsr     x5, x5, #1          // mid = (low + high) / 2

    lsl     x6, x5, #4          // offset = mid * 16
    add     x6, x0, x6          // ptr to entry
    ldr     x7, [x6]            // entry.doc_id

    cmp     x2, x7
    b.eq    .Lbs_found
    b.lt    .Lbs_left

    // Go right
    add     x3, x5, #1
    b       .Lbs_loop

.Lbs_left:
    mov     x4, x5
    b       .Lbs_loop

.Lbs_found:
    mov     x0, x5
    ret

.Lbs_notfound:
    mov     x0, #-1
    ret
.size binary_search_index, . - binary_search_index

// =============================================================================
// doc_index_insert - Insert entry into index
//
// Input:
//   x0 = document ID
//   x1 = file offset
// Output:
//   x0 = 0 on success, negative errno on error
//
// Adds to in-memory buffer. If buffer is full, triggers merge.
// =============================================================================
.global doc_index_insert
.type doc_index_insert, %function
doc_index_insert:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // doc_id
    mov     x20, x1             // offset

    adrp    x21, g_doc_index
    add     x21, x21, :lo12:g_doc_index

    // Check if buffer is full
    ldr     x22, [x21, #DOCIDX_OFF_BUF_COUNT]
    mov     x0, #IDX_BUFFER_CAPACITY
    cmp     x22, x0
    b.lt    .Ldi_insert_add

    // Buffer full - merge first
    bl      doc_index_merge
    cmp     x0, #0
    b.lt    .Ldi_insert_done

    // Buffer is now empty
    mov     x22, #0

.Ldi_insert_add:
    // Add entry to buffer
    ldr     x0, [x21, #DOCIDX_OFF_BUF_PTR]
    lsl     x1, x22, #4         // offset = count * 16
    add     x0, x0, x1
    str     x19, [x0, #IDX_OFF_DOC_ID]
    str     x20, [x0, #IDX_OFF_FILE_OFFSET]

    // Increment count
    add     x22, x22, #1
    str     x22, [x21, #DOCIDX_OFF_BUF_COUNT]

    // Mark dirty
    mov     x0, #1
    str     x0, [x21, #DOCIDX_OFF_DIRTY]

    mov     x0, #0

.Ldi_insert_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size doc_index_insert, . - doc_index_insert

// =============================================================================
// doc_index_remove - Mark index entry as deleted
//
// Input:
//   x0 = document ID
// Output:
//   x0 = 0 on success, -ENOENT if not found
//
// Sets the file offset to -1 to mark as deleted.
// =============================================================================
.global doc_index_remove
.type doc_index_remove, %function
doc_index_remove:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    mov     x19, x0             // doc_id

    adrp    x20, g_doc_index
    add     x20, x20, :lo12:g_doc_index

    // First check in-memory buffer
    ldr     x21, [x20, #DOCIDX_OFF_BUF_PTR]
    ldr     x1, [x20, #DOCIDX_OFF_BUF_COUNT]
    mov     x0, x21

.Ldi_remove_buf:
    cbz     x1, .Ldi_remove_disk
    ldr     x2, [x0, #IDX_OFF_DOC_ID]
    cmp     x2, x19
    b.eq    .Ldi_remove_buf_found
    add     x0, x0, #IDX_ENTRY_SIZE
    sub     x1, x1, #1
    b       .Ldi_remove_buf

.Ldi_remove_buf_found:
    // Mark as deleted
    mov     x1, #-1
    str     x1, [x0, #IDX_OFF_FILE_OFFSET]
    mov     x0, #1
    str     x0, [x20, #DOCIDX_OFF_DIRTY]
    mov     x0, #0
    b       .Ldi_remove_done

.Ldi_remove_disk:
    // Insert a deletion marker into the buffer
    mov     x0, x19
    mov     x1, #-1             // -1 = deleted
    bl      doc_index_insert

.Ldi_remove_done:
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size doc_index_remove, . - doc_index_remove

// =============================================================================
// doc_index_merge - Merge buffer with disk index
//
// Output:
//   x0 = 0 on success, negative errno on error
//
// Sorts the buffer, merges with existing index, writes new sorted index.
// =============================================================================
.global doc_index_merge
.type doc_index_merge, %function
doc_index_merge:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    adrp    x19, g_doc_index
    add     x19, x19, :lo12:g_doc_index

    ldr     x20, [x19, #DOCIDX_OFF_BUF_COUNT]
    cbz     x20, .Ldi_merge_success  // Nothing to merge

    // Sort the buffer
    ldr     x0, [x19, #DOCIDX_OFF_BUF_PTR]
    mov     x1, x20
    bl      sort_index_entries

    // Calculate new index size
    ldr     x21, [x19, #DOCIDX_OFF_COUNT]  // disk count
    add     x22, x21, x20       // max new count (may be less due to updates)

    // Allocate temporary buffer for merged index
    add     x0, x22, #1         // +1 for header
    lsl     x0, x0, #4          // * 16
    add     x0, x0, #IDX_HDR_SIZE
    mov     x23, x0             // new size

    mov     x0, #0
    mov     x1, x23
    mov     x2, #(PROT_READ | PROT_WRITE)
    mov     x3, #(MAP_PRIVATE | MAP_ANONYMOUS)
    mov     x4, #-1
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Ldi_merge_error
    mov     x24, x0             // new buffer

    // Write header
    ldr     w1, =IDX_MAGIC
    str     w1, [x24, #IDX_HDR_MAGIC]
    mov     w1, #IDX_VERSION
    str     w1, [x24, #IDX_HDR_VERSION]
    // Count will be filled in later

    // Merge: walk both sorted arrays
    ldr     x25, [x19, #DOCIDX_OFF_MMAP_BASE]
    cbz     x25, .Ldi_merge_buf_only
    add     x25, x25, #IDX_HDR_SIZE  // disk entries start

    ldr     x0, [x19, #DOCIDX_OFF_BUF_PTR]  // buf ptr
    mov     x1, x20             // buf count
    mov     x2, x25             // disk ptr
    mov     x3, x21             // disk count
    add     x4, x24, #IDX_HDR_SIZE  // output ptr
    bl      merge_sorted_entries
    mov     x26, x0             // final count
    b       .Ldi_merge_write

.Ldi_merge_buf_only:
    // No disk index, just copy buffer
    add     x0, x24, #IDX_HDR_SIZE
    ldr     x1, [x19, #DOCIDX_OFF_BUF_PTR]
    lsl     x2, x20, #4
    bl      memcpy
    mov     x26, x20

.Ldi_merge_write:
    // Store count in header
    str     x26, [x24, #IDX_HDR_COUNT]

    // Calculate final size
    lsl     x0, x26, #4
    add     x23, x0, #IDX_HDR_SIZE

    // Truncate file to new size
    ldr     x0, [x19, #DOCIDX_OFF_FD]
    mov     x1, x23
    bl      sys_ftruncate
    cmp     x0, #0
    b.lt    .Ldi_merge_trunc_error

    // Seek to beginning
    ldr     x0, [x19, #DOCIDX_OFF_FD]
    mov     x1, #0
    mov     x2, #SEEK_SET
    bl      sys_lseek

    // Write merged index
    ldr     x0, [x19, #DOCIDX_OFF_FD]
    mov     x1, x24
    mov     x2, x23
    bl      sys_write
    cmp     x0, x23
    b.ne    .Ldi_merge_write_error

    // Sync
    ldr     x0, [x19, #DOCIDX_OFF_FD]
    bl      sys_fsync

    // Unmap old mapping
    ldr     x0, [x19, #DOCIDX_OFF_MMAP_BASE]
    cbz     x0, .Ldi_merge_no_old_unmap
    ldr     x1, [x19, #DOCIDX_OFF_MMAP_SIZE]
    bl      sys_munmap
.Ldi_merge_no_old_unmap:

    // Free temp buffer
    mov     x0, x24
    mov     x1, x23
    bl      sys_munmap

    // Create new mmap
    mov     x0, #0
    mov     x1, x23
    mov     x2, #PROT_READ
    mov     x3, #MAP_PRIVATE
    ldr     x4, [x19, #DOCIDX_OFF_FD]
    mov     x5, #0
    bl      sys_mmap
    cmn     x0, #4096
    b.hi    .Ldi_merge_remap_error

    // Update state
    str     x0, [x19, #DOCIDX_OFF_MMAP_BASE]
    str     x23, [x19, #DOCIDX_OFF_MMAP_SIZE]
    str     x26, [x19, #DOCIDX_OFF_COUNT]
    str     xzr, [x19, #DOCIDX_OFF_BUF_COUNT]
    str     xzr, [x19, #DOCIDX_OFF_DIRTY]

.Ldi_merge_success:
    mov     x0, #0
    b       .Ldi_merge_done

.Ldi_merge_remap_error:
    // Critical error - index may be corrupt
    mov     x0, #-EIO
    b       .Ldi_merge_done

.Ldi_merge_write_error:
.Ldi_merge_trunc_error:
    mov     x0, x24
    mov     x1, x23
    bl      sys_munmap
    mov     x0, #-EIO
    b       .Ldi_merge_done

.Ldi_merge_error:
    // x0 already has error

.Ldi_merge_done:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size doc_index_merge, . - doc_index_merge

// =============================================================================
// sort_index_entries - Sort array of index entries by doc_id (insertion sort)
//
// Input:
//   x0 = array pointer
//   x1 = count
// =============================================================================
.type sort_index_entries, %function
sort_index_entries:
    cmp     x1, #2
    b.lt    .Lsort_done

    mov     x2, #1              // i = 1

.Lsort_outer:
    cmp     x2, x1
    b.ge    .Lsort_done

    // Load entry[i]
    lsl     x3, x2, #4
    add     x3, x0, x3
    ldr     x4, [x3, #IDX_OFF_DOC_ID]
    ldr     x5, [x3, #IDX_OFF_FILE_OFFSET]

    // j = i - 1
    sub     x6, x2, #1

.Lsort_inner:
    cmp     x6, #0
    b.lt    .Lsort_insert

    // Load entry[j]
    lsl     x7, x6, #4
    add     x7, x0, x7
    ldr     x8, [x7, #IDX_OFF_DOC_ID]

    // If entry[j].id <= key.id, stop
    cmp     x8, x4
    b.le    .Lsort_insert

    // Move entry[j] to entry[j+1]
    ldr     x9, [x7, #IDX_OFF_FILE_OFFSET]
    add     x10, x7, #IDX_ENTRY_SIZE
    str     x8, [x10, #IDX_OFF_DOC_ID]
    str     x9, [x10, #IDX_OFF_FILE_OFFSET]

    sub     x6, x6, #1
    b       .Lsort_inner

.Lsort_insert:
    // Insert key at j+1
    add     x6, x6, #1
    lsl     x7, x6, #4
    add     x7, x0, x7
    str     x4, [x7, #IDX_OFF_DOC_ID]
    str     x5, [x7, #IDX_OFF_FILE_OFFSET]

    add     x2, x2, #1
    b       .Lsort_outer

.Lsort_done:
    ret
.size sort_index_entries, . - sort_index_entries

// =============================================================================
// merge_sorted_entries - Merge two sorted entry arrays
//
// Input:
//   x0 = buf ptr (new entries)
//   x1 = buf count
//   x2 = disk ptr (existing entries)
//   x3 = disk count
//   x4 = output ptr
// Output:
//   x0 = final count (after removing duplicates)
//
// When same doc_id appears in both, buf entry wins (it's newer).
// Entries with offset=-1 (deleted) are skipped in output.
// =============================================================================
.type merge_sorted_entries, %function
merge_sorted_entries:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0             // buf ptr
    mov     x20, x1             // buf count
    mov     x21, x2             // disk ptr
    mov     x22, x3             // disk count
    mov     x23, x4             // out ptr
    mov     x24, #0             // out count

.Lmerge_loop:
    // Check if either input exhausted
    cbz     x20, .Lmerge_disk_rest
    cbz     x22, .Lmerge_buf_rest

    // Compare heads
    ldr     x25, [x19, #IDX_OFF_DOC_ID]  // buf id
    ldr     x26, [x21, #IDX_OFF_DOC_ID]  // disk id

    cmp     x25, x26
    b.lt    .Lmerge_take_buf
    b.gt    .Lmerge_take_disk

    // Same ID - take buf (newer), skip disk
    ldr     x0, [x19, #IDX_OFF_FILE_OFFSET]
    cmn     x0, #1              // check if deleted
    b.eq    .Lmerge_skip_both

    // Copy buf entry
    str     x25, [x23, #IDX_OFF_DOC_ID]
    str     x0, [x23, #IDX_OFF_FILE_OFFSET]
    add     x23, x23, #IDX_ENTRY_SIZE
    add     x24, x24, #1

.Lmerge_skip_both:
    add     x19, x19, #IDX_ENTRY_SIZE
    sub     x20, x20, #1
    add     x21, x21, #IDX_ENTRY_SIZE
    sub     x22, x22, #1
    b       .Lmerge_loop

.Lmerge_take_buf:
    ldr     x0, [x19, #IDX_OFF_FILE_OFFSET]
    cmn     x0, #1
    b.eq    .Lmerge_skip_buf

    str     x25, [x23, #IDX_OFF_DOC_ID]
    str     x0, [x23, #IDX_OFF_FILE_OFFSET]
    add     x23, x23, #IDX_ENTRY_SIZE
    add     x24, x24, #1

.Lmerge_skip_buf:
    add     x19, x19, #IDX_ENTRY_SIZE
    sub     x20, x20, #1
    b       .Lmerge_loop

.Lmerge_take_disk:
    ldr     x0, [x21, #IDX_OFF_FILE_OFFSET]
    cmn     x0, #1
    b.eq    .Lmerge_skip_disk

    str     x26, [x23, #IDX_OFF_DOC_ID]
    str     x0, [x23, #IDX_OFF_FILE_OFFSET]
    add     x23, x23, #IDX_ENTRY_SIZE
    add     x24, x24, #1

.Lmerge_skip_disk:
    add     x21, x21, #IDX_ENTRY_SIZE
    sub     x22, x22, #1
    b       .Lmerge_loop

.Lmerge_disk_rest:
    // Copy remaining disk entries
    cbz     x22, .Lmerge_done
    ldr     x25, [x21, #IDX_OFF_DOC_ID]
    ldr     x0, [x21, #IDX_OFF_FILE_OFFSET]
    cmn     x0, #1
    b.eq    .Lmerge_skip_disk_rest

    str     x25, [x23, #IDX_OFF_DOC_ID]
    str     x0, [x23, #IDX_OFF_FILE_OFFSET]
    add     x23, x23, #IDX_ENTRY_SIZE
    add     x24, x24, #1

.Lmerge_skip_disk_rest:
    add     x21, x21, #IDX_ENTRY_SIZE
    sub     x22, x22, #1
    b       .Lmerge_disk_rest

.Lmerge_buf_rest:
    // Copy remaining buf entries
    cbz     x20, .Lmerge_done
    ldr     x25, [x19, #IDX_OFF_DOC_ID]
    ldr     x0, [x19, #IDX_OFF_FILE_OFFSET]
    cmn     x0, #1
    b.eq    .Lmerge_skip_buf_rest

    str     x25, [x23, #IDX_OFF_DOC_ID]
    str     x0, [x23, #IDX_OFF_FILE_OFFSET]
    add     x23, x23, #IDX_ENTRY_SIZE
    add     x24, x24, #1

.Lmerge_skip_buf_rest:
    add     x19, x19, #IDX_ENTRY_SIZE
    sub     x20, x20, #1
    b       .Lmerge_buf_rest

.Lmerge_done:
    mov     x0, x24

    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size merge_sorted_entries, . - merge_sorted_entries

// =============================================================================
// doc_index_sync - Sync index to disk
//
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global doc_index_sync
.type doc_index_sync, %function
doc_index_sync:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, g_doc_index
    add     x0, x0, :lo12:g_doc_index

    // Check if dirty
    ldr     x1, [x0, #DOCIDX_OFF_DIRTY]
    cbz     x1, .Ldi_sync_done

    // Merge buffer to disk
    bl      doc_index_merge
    cmp     x0, #0
    b.lt    .Ldi_sync_done

    // fsync
    adrp    x0, g_doc_index
    add     x0, x0, :lo12:g_doc_index
    ldr     x0, [x0, #DOCIDX_OFF_FD]
    bl      sys_fsync

.Ldi_sync_done:
    ldp     x29, x30, [sp], #16
    ret
.size doc_index_sync, . - doc_index_sync

// =============================================================================
// doc_index_close - Close index
//
// Output:
//   x0 = 0 on success, negative errno on error
// =============================================================================
.global doc_index_close
.type doc_index_close, %function
doc_index_close:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    adrp    x19, g_doc_index
    add     x19, x19, :lo12:g_doc_index

    // Sync first
    bl      doc_index_sync

    // Unmap index
    ldr     x0, [x19, #DOCIDX_OFF_MMAP_BASE]
    cbz     x0, .Ldi_close_no_unmap
    ldr     x1, [x19, #DOCIDX_OFF_MMAP_SIZE]
    bl      sys_munmap
.Ldi_close_no_unmap:

    // Free buffer
    ldr     x0, [x19, #DOCIDX_OFF_BUF_PTR]
    cbz     x0, .Ldi_close_no_buf
    mov     x1, #(IDX_BUFFER_CAPACITY * IDX_ENTRY_SIZE)
    bl      sys_munmap
.Ldi_close_no_buf:

    // Close fd
    ldr     x0, [x19, #DOCIDX_OFF_FD]
    bl      sys_close

    // Zero state
    str     xzr, [x19, #DOCIDX_OFF_FD]
    str     xzr, [x19, #DOCIDX_OFF_MMAP_BASE]
    str     xzr, [x19, #DOCIDX_OFF_BUF_PTR]

    mov     x0, #0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size doc_index_close, . - doc_index_close

// =============================================================================
// doc_index_count - Get number of entries in index
//
// Output:
//   x0 = entry count (disk + buffer)
// =============================================================================
.global doc_index_count
.type doc_index_count, %function
doc_index_count:
    adrp    x0, g_doc_index
    add     x0, x0, :lo12:g_doc_index
    ldr     x1, [x0, #DOCIDX_OFF_COUNT]
    ldr     x2, [x0, #DOCIDX_OFF_BUF_COUNT]
    add     x0, x1, x2
    ret
.size doc_index_count, . - doc_index_count

// =============================================================================
// BSS Section - Global state
// =============================================================================

.section .bss
.balign 8

.global g_doc_index
g_doc_index:
    .skip   DOCIDX_SIZE

// =============================================================================
// End of docidx.s
// =============================================================================
