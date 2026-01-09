// =============================================================================
// Omesh - test_store.s
// Storage layer test program
// =============================================================================
//
// Tests document storage, index, and WAL functionality.
// Creates temporary files in /tmp for testing.
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/store.inc"

// Import HAL
.extern hal_init
.extern print_str
.extern print_dec
.extern print_hex
.extern print_newline
.extern print_char

// Import storage functions
.extern doc_store_init
.extern doc_store_put
.extern doc_store_get
.extern doc_store_get_header
.extern doc_store_mark_deleted
.extern doc_store_sync
.extern doc_store_close

.extern doc_index_init
.extern doc_index_lookup
.extern doc_index_insert
.extern doc_index_remove
.extern doc_index_sync
.extern doc_index_close
.extern doc_index_count

.extern wal_init
.extern wal_append
.extern wal_sync
.extern wal_checkpoint
.extern wal_truncate
.extern wal_close
.extern wal_get_seq

.extern crc32_calc
.extern memcmp

.text
.balign 4

// =============================================================================
// _start - Test entry point
// =============================================================================
.global _start
_start:
    mov     x29, sp

    // Initialize HAL first
    bl      hal_init

    // Print header
    adrp    x0, msg_header
    add     x0, x0, :lo12:msg_header
    bl      print_str

    // Initialize test counters
    adrp    x19, test_passed
    add     x19, x19, :lo12:test_passed
    str     xzr, [x19]
    adrp    x20, test_total
    add     x20, x20, :lo12:test_total
    str     xzr, [x20]

    // Run tests
    bl      test_crc32
    bl      test_doc_store_init
    bl      test_doc_store_put
    bl      test_doc_store_get
    bl      test_doc_store_delete
    bl      test_doc_index_init
    bl      test_doc_index_insert_lookup
    bl      test_doc_index_remove
    bl      test_wal_init
    bl      test_wal_append

    // Print summary
    adrp    x0, msg_summary
    add     x0, x0, :lo12:msg_summary
    bl      print_str

    ldr     x0, [x19]
    bl      print_dec

    mov     x0, #'/'
    bl      print_char

    ldr     x0, [x20]
    bl      print_dec

    adrp    x0, msg_tests_passed
    add     x0, x0, :lo12:msg_tests_passed
    bl      print_str
    bl      print_newline

    // Cleanup
    bl      cleanup_test_files

    // Exit with appropriate code
    ldr     x0, [x19]           // passed
    ldr     x1, [x20]           // total
    cmp     x0, x1
    b.eq    .Lexit_success

    mov     x0, #1
    mov     x8, #SYS_exit_group
    svc     #0

.Lexit_success:
    mov     x0, #0
    mov     x8, #SYS_exit_group
    svc     #0

// =============================================================================
// Test helper functions
// =============================================================================

// Print [PASS] or [FAIL] and increment counters
// x0 = 0 for pass, non-zero for fail
// x1 = test name string
test_result:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0
    mov     x20, x1

    // Increment total
    adrp    x0, test_total
    add     x0, x0, :lo12:test_total
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    cbz     x19, .Ltest_pass

    // FAIL
    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_str
    b       .Ltest_name

.Ltest_pass:
    // Increment passed
    adrp    x0, test_passed
    add     x0, x0, :lo12:test_passed
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_str

.Ltest_name:
    mov     x0, x20
    bl      print_str
    bl      print_newline

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_crc32 - Test CRC32 implementation
// =============================================================================
test_crc32:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Calculate CRC32 of known data
    adrp    x0, test_data
    add     x0, x0, :lo12:test_data
    mov     x1, #11             // "Hello World"
    bl      crc32_calc

    // Expected CRC32C of "Hello World" = 0x691DAA2F
    ldr     x1, =0x691DAA2F
    cmp     x0, x1
    cset    w0, ne

    adrp    x1, name_crc32
    add     x1, x1, :lo12:name_crc32
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_doc_store_init - Test document store initialization
// =============================================================================
test_doc_store_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, path_test_docs
    add     x0, x0, :lo12:path_test_docs
    bl      doc_store_init

    cmp     x0, #0
    cset    w0, ne

    adrp    x1, name_doc_init
    add     x1, x1, :lo12:name_doc_init
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_doc_store_put - Test storing a document
// =============================================================================
test_doc_store_put:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Put a document
    adrp    x0, test_content
    add     x0, x0, :lo12:test_content
    mov     x1, #25             // "This is test document 1"
    sub     sp, sp, #16
    mov     x2, sp              // out_id
    bl      doc_store_put

    mov     x19, x0             // save offset
    ldr     x20, [sp]           // doc_id
    add     sp, sp, #16

    // Check offset >= 0
    cmp     x19, #0
    b.lt    .Ltest_put_fail

    // Check doc_id > 0
    cmp     x20, #0
    b.le    .Ltest_put_fail

    mov     x0, #0
    b       .Ltest_put_result

.Ltest_put_fail:
    mov     x0, #1

.Ltest_put_result:
    adrp    x1, name_doc_put
    add     x1, x1, :lo12:name_doc_put
    bl      test_result

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_doc_store_get - Test retrieving a document
// =============================================================================
test_doc_store_get:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // First put a document
    adrp    x0, test_content2
    add     x0, x0, :lo12:test_content2
    mov     x1, #18             // "Another test doc"
    sub     sp, sp, #16
    mov     x2, sp
    bl      doc_store_put

    mov     x19, x0             // offset
    add     sp, sp, #16

    cmp     x19, #0
    b.lt    .Ltest_get_fail

    // Sync to ensure mmap is updated
    bl      doc_store_sync

    // Get the document
    sub     sp, sp, #64
    mov     x0, x19
    mov     x1, sp
    mov     x2, #64
    bl      doc_store_get

    cmp     x0, #18             // should return 18 bytes
    b.ne    .Ltest_get_fail_sp

    // Compare content
    mov     x0, sp
    adrp    x1, test_content2
    add     x1, x1, :lo12:test_content2
    mov     x2, #18
    bl      memcmp
    add     sp, sp, #64

    cmp     x0, #0
    cset    w0, ne
    b       .Ltest_get_result

.Ltest_get_fail_sp:
    add     sp, sp, #64
.Ltest_get_fail:
    mov     x0, #1

.Ltest_get_result:
    adrp    x1, name_doc_get
    add     x1, x1, :lo12:name_doc_get
    bl      test_result

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// test_doc_store_delete - Test deleting a document
// =============================================================================
test_doc_store_delete:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Put a document
    adrp    x0, test_content
    add     x0, x0, :lo12:test_content
    mov     x1, #10
    mov     x2, #0
    bl      doc_store_put

    mov     x19, x0             // offset
    cmp     x19, #0
    b.lt    .Ltest_del_fail

    // Delete it
    mov     x0, x19
    bl      doc_store_mark_deleted
    cmp     x0, #0
    b.ne    .Ltest_del_fail

    // Sync and try to get - should fail with ENOENT
    bl      doc_store_sync

    sub     sp, sp, #64
    mov     x0, x19
    mov     x1, sp
    mov     x2, #64
    bl      doc_store_get
    add     sp, sp, #64

    cmn     x0, #ENOENT
    cset    w0, ne
    b       .Ltest_del_result

.Ltest_del_fail:
    mov     x0, #1

.Ltest_del_result:
    adrp    x1, name_doc_del
    add     x1, x1, :lo12:name_doc_del
    bl      test_result

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_doc_index_init - Test index initialization
// =============================================================================
test_doc_index_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, path_test_idx
    add     x0, x0, :lo12:path_test_idx
    bl      doc_index_init

    cmp     x0, #0
    cset    w0, ne

    adrp    x1, name_idx_init
    add     x1, x1, :lo12:name_idx_init
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_doc_index_insert_lookup - Test index insert and lookup
// =============================================================================
test_doc_index_insert_lookup:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Insert several entries
    mov     x19, #100           // doc_id
    mov     x20, #1000          // offset

    mov     x0, x19
    mov     x1, x20
    bl      doc_index_insert
    cmp     x0, #0
    b.ne    .Ltest_idx_fail

    add     x19, x19, #1
    add     x20, x20, #100
    mov     x0, x19
    mov     x1, x20
    bl      doc_index_insert
    cmp     x0, #0
    b.ne    .Ltest_idx_fail

    add     x19, x19, #1
    add     x20, x20, #100
    mov     x0, x19
    mov     x1, x20
    bl      doc_index_insert
    cmp     x0, #0
    b.ne    .Ltest_idx_fail

    // Lookup middle entry (doc_id=101, offset=1100)
    mov     x0, #101
    bl      doc_index_lookup
    cmp     x0, #1100
    b.ne    .Ltest_idx_fail

    // Lookup non-existent
    mov     x0, #999
    bl      doc_index_lookup
    cmn     x0, #ENOENT
    b.ne    .Ltest_idx_fail

    mov     x0, #0
    b       .Ltest_idx_result

.Ltest_idx_fail:
    mov     x0, #1

.Ltest_idx_result:
    adrp    x1, name_idx_lookup
    add     x1, x1, :lo12:name_idx_lookup
    bl      test_result

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_doc_index_remove - Test index removal
// =============================================================================
test_doc_index_remove:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Insert an entry
    mov     x0, #200
    mov     x1, #2000
    bl      doc_index_insert
    cmp     x0, #0
    b.ne    .Ltest_idx_rm_fail

    // Verify it exists
    mov     x0, #200
    bl      doc_index_lookup
    cmp     x0, #2000
    b.ne    .Ltest_idx_rm_fail

    // Remove it
    mov     x0, #200
    bl      doc_index_remove
    cmp     x0, #0
    b.ne    .Ltest_idx_rm_fail

    // Verify it's gone
    mov     x0, #200
    bl      doc_index_lookup
    cmn     x0, #ENOENT
    cset    w0, ne
    b       .Ltest_idx_rm_result

.Ltest_idx_rm_fail:
    mov     x0, #1

.Ltest_idx_rm_result:
    adrp    x1, name_idx_remove
    add     x1, x1, :lo12:name_idx_remove
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_wal_init - Test WAL initialization
// =============================================================================
test_wal_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, path_test_wal
    add     x0, x0, :lo12:path_test_wal
    bl      wal_init

    cmp     x0, #0
    cset    w0, ne

    adrp    x1, name_wal_init
    add     x1, x1, :lo12:name_wal_init
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_wal_append - Test WAL append and sync
// =============================================================================
test_wal_append:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Append a PUT entry
    mov     x0, #WAL_OP_PUT
    mov     x1, #42             // doc_id
    adrp    x2, test_content
    add     x2, x2, :lo12:test_content
    mov     x3, #10
    bl      wal_append

    mov     x19, x0
    cmp     x19, #0
    b.le    .Ltest_wal_fail

    // Append a DELETE entry
    mov     x0, #WAL_OP_DELETE
    mov     x1, #42
    mov     x2, #0
    mov     x3, #0
    bl      wal_append

    cmp     x0, x19
    b.le    .Ltest_wal_fail

    // Sync
    bl      wal_sync
    cmp     x0, #0
    b.ne    .Ltest_wal_fail

    // Get sequence number
    bl      wal_get_seq
    cmp     x0, #2
    b.lt    .Ltest_wal_fail

    mov     x0, #0
    b       .Ltest_wal_result

.Ltest_wal_fail:
    mov     x0, #1

.Ltest_wal_result:
    adrp    x1, name_wal_append
    add     x1, x1, :lo12:name_wal_append
    bl      test_result

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// cleanup_test_files - Remove test files
// =============================================================================
cleanup_test_files:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Close stores
    bl      doc_store_close
    bl      doc_index_close
    bl      wal_close

    // Delete test files
    mov     x0, #AT_FDCWD
    adrp    x1, path_test_docs
    add     x1, x1, :lo12:path_test_docs
    mov     x2, #0
    bl      sys_unlinkat

    mov     x0, #AT_FDCWD
    adrp    x1, path_test_idx
    add     x1, x1, :lo12:path_test_idx
    mov     x2, #0
    bl      sys_unlinkat

    mov     x0, #AT_FDCWD
    adrp    x1, path_test_wal
    add     x1, x1, :lo12:path_test_wal
    mov     x2, #0
    bl      sys_unlinkat

    ldp     x29, x30, [sp], #16
    ret

// Import sys_unlinkat
.extern sys_unlinkat

// =============================================================================
// Data section
// =============================================================================

.section .data
.balign 8

test_passed:
    .quad   0

test_total:
    .quad   0

.section .rodata
.balign 8

msg_header:
    .asciz "=== Omesh Storage Tests ===\n"

msg_pass:
    .asciz "[PASS] "

msg_fail:
    .asciz "[FAIL] "

msg_summary:
    .asciz "=== "

msg_tests_passed:
    .asciz " tests passed ===\n"

// Test names
name_crc32:
    .asciz "CRC32 calculation"

name_doc_init:
    .asciz "Document store init"

name_doc_put:
    .asciz "Document store put"

name_doc_get:
    .asciz "Document store get"

name_doc_del:
    .asciz "Document store delete"

name_idx_init:
    .asciz "Document index init"

name_idx_lookup:
    .asciz "Document index insert/lookup"

name_idx_remove:
    .asciz "Document index remove"

name_wal_init:
    .asciz "WAL init"

name_wal_append:
    .asciz "WAL append/sync"

// Test file paths
path_test_docs:
    .asciz "/tmp/omesh_test_docs.dat"

path_test_idx:
    .asciz "/tmp/omesh_test_docs.idx"

path_test_wal:
    .asciz "/tmp/omesh_test.wal"

// Test data
test_data:
    .asciz "Hello World"

test_content:
    .asciz "This is test document 1"

test_content2:
    .asciz "Another test doc"

// =============================================================================
// End of test_store.s
// =============================================================================
