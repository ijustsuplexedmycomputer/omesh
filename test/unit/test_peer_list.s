// =============================================================================
// Omesh - Peer List Unit Tests
// =============================================================================
//
// Tests:
//   1. peer_list_init
//   2. Add 3 peers
//   3. Verify count = 3
//   4. Get peer by index, verify data
//   5. Find peer by node_id
//   6. Remove peer
//   7. Verify count = 2
//   8. Save to /tmp/peers.dat
//   9. Clear and reload
//  10. Verify count = 2 and data intact
//
// =============================================================================

.include "syscall_nums.inc"
.include "mesh.inc"

// =============================================================================
// Test data
// =============================================================================

.section .data

test_host1:     .asciz "127.0.0.1"
test_host2:     .asciz "192.168.1.1"
test_host3:     .asciz "10.0.0.50"

test_path:      .asciz "/tmp/omesh_test_peers.dat"

// Test counters
tests_run:      .word 0
tests_passed:   .word 0

// =============================================================================
// Read-only strings
// =============================================================================

.section .rodata

str_header:
    .asciz "\n=== Peer List Unit Tests ===\n\n"
str_test_init:
    .asciz "[TEST] peer_list_init... "
str_test_add:
    .asciz "[TEST] peer_list_add (3 peers)... "
str_test_count:
    .asciz "[TEST] peer_list_count = 3... "
str_test_get:
    .asciz "[TEST] peer_list_get... "
str_test_find:
    .asciz "[TEST] peer_list_find... "
str_test_remove:
    .asciz "[TEST] peer_list_remove... "
str_test_count2:
    .asciz "[TEST] peer_list_count = 2... "
str_test_save:
    .asciz "[TEST] peer_list_save... "
str_test_reload:
    .asciz "[TEST] peer_list_load after clear... "
str_test_verify:
    .asciz "[TEST] Verify reloaded data... "

str_pass:       .asciz "PASS\n"
str_fail:       .asciz "FAIL\n"

str_summary:    .asciz "\n=== Results: "
str_slash:      .asciz "/"
str_passed:     .asciz " passed ===\n\n"

// =============================================================================
// Code
// =============================================================================

.section .text

// =============================================================================
// print_str - Print null-terminated string
// =============================================================================
print_str:
    mov     x2, x0
    mov     x3, #0
.Lps_len:
    ldrb    w4, [x2, x3]
    cbz     w4, .Lps_write
    add     x3, x3, #1
    b       .Lps_len
.Lps_write:
    mov     x1, x2
    mov     x2, x3
    mov     x0, #1
    mov     x8, #SYS_write
    svc     #0
    ret

// =============================================================================
// print_num - Print decimal number
// =============================================================================
print_num:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    mov     x1, x0
    add     x2, sp, #16
    mov     x3, x2
    add     x3, x3, #12
    strb    wzr, [x3]
    sub     x3, x3, #1

    cbz     x1, .Lpn_zero

.Lpn_loop:
    cbz     x1, .Lpn_print
    mov     x4, #10
    udiv    x5, x1, x4
    msub    x6, x5, x4, x1
    add     w6, w6, #'0'
    strb    w6, [x3]
    sub     x3, x3, #1
    mov     x1, x5
    b       .Lpn_loop

.Lpn_zero:
    mov     w0, #'0'
    strb    w0, [x3]
    b       .Lpn_do_print

.Lpn_print:
    add     x3, x3, #1

.Lpn_do_print:
    mov     x0, x3
    bl      print_str

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// record_test - Increment test counter
// =============================================================================
record_test:
    adrp    x0, tests_run
    add     x0, x0, :lo12:tests_run
    ldr     w1, [x0]
    add     w1, w1, #1
    str     w1, [x0]
    ret

// =============================================================================
// record_pass - Increment pass counter and print PASS
// =============================================================================
record_pass:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     w1, [x0]
    add     w1, w1, #1
    str     w1, [x0]

    adrp    x0, str_pass
    add     x0, x0, :lo12:str_pass
    bl      print_str

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// record_fail - Print FAIL
// =============================================================================
record_fail:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, str_fail
    add     x0, x0, :lo12:str_fail
    bl      print_str

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// _start - Entry point
// =============================================================================
.global _start
_start:
    // Print header
    adrp    x0, str_header
    add     x0, x0, :lo12:str_header
    bl      print_str

    // =========================================================================
    // Test 1: peer_list_init
    // =========================================================================
    adrp    x0, str_test_init
    add     x0, x0, :lo12:str_test_init
    bl      print_str
    bl      record_test

    bl      peer_list_init
    cmp     x0, #0
    b.ne    .Ltest1_fail

    // Also set a local node ID
    mov     x0, #0xBEEF
    movk    x0, #0xDEAD, lsl #16
    movk    x0, #0x1234, lsl #32
    bl      peer_list_set_local_id

    bl      record_pass
    b       .Ltest2

.Ltest1_fail:
    bl      record_fail

    // =========================================================================
    // Test 2: Add 3 peers
    // =========================================================================
.Ltest2:
    adrp    x0, str_test_add
    add     x0, x0, :lo12:str_test_add
    bl      print_str
    bl      record_test

    // Add peer 1
    adrp    x0, test_host1
    add     x0, x0, :lo12:test_host1
    mov     x1, #8080
    mov     x2, #0x1111
    movk    x2, #0x1111, lsl #16
    movk    x2, #0x1111, lsl #32
    movk    x2, #0x1111, lsl #48
    bl      peer_list_add
    cmp     x0, #0
    b.lt    .Ltest2_fail

    // Add peer 2
    adrp    x0, test_host2
    add     x0, x0, :lo12:test_host2
    mov     x1, #9000
    mov     x2, #0x2222
    movk    x2, #0x2222, lsl #16
    movk    x2, #0x2222, lsl #32
    movk    x2, #0x2222, lsl #48
    bl      peer_list_add
    cmp     x0, #1
    b.ne    .Ltest2_fail

    // Add peer 3
    adrp    x0, test_host3
    add     x0, x0, :lo12:test_host3
    mov     x1, #7000
    mov     x2, #0x3333
    movk    x2, #0x3333, lsl #16
    movk    x2, #0x3333, lsl #32
    movk    x2, #0x3333, lsl #48
    bl      peer_list_add
    cmp     x0, #2
    b.ne    .Ltest2_fail

    bl      record_pass
    b       .Ltest3

.Ltest2_fail:
    bl      record_fail

    // =========================================================================
    // Test 3: Verify count = 3
    // =========================================================================
.Ltest3:
    adrp    x0, str_test_count
    add     x0, x0, :lo12:str_test_count
    bl      print_str
    bl      record_test

    bl      peer_list_count
    cmp     x0, #3
    b.ne    .Ltest3_fail

    bl      record_pass
    b       .Ltest4

.Ltest3_fail:
    bl      record_fail

    // =========================================================================
    // Test 4: Get peer by index, verify data
    // =========================================================================
.Ltest4:
    adrp    x0, str_test_get
    add     x0, x0, :lo12:str_test_get
    bl      print_str
    bl      record_test

    // Get peer 1 (index 0)
    mov     x0, #1
    bl      peer_list_get
    cbz     x0, .Ltest4_fail

    // Check node_id
    ldr     x1, [x0, #PEER_OFF_NODE_ID]
    mov     x2, #0x2222
    movk    x2, #0x2222, lsl #16
    movk    x2, #0x2222, lsl #32
    movk    x2, #0x2222, lsl #48
    cmp     x1, x2
    b.ne    .Ltest4_fail

    // Check port
    ldrh    w1, [x0, #PEER_OFF_PORT]
    mov     w3, #9000
    cmp     w1, w3
    b.ne    .Ltest4_fail

    bl      record_pass
    b       .Ltest5

.Ltest4_fail:
    bl      record_fail

    // =========================================================================
    // Test 5: Find peer by node_id
    // =========================================================================
.Ltest5:
    adrp    x0, str_test_find
    add     x0, x0, :lo12:str_test_find
    bl      print_str
    bl      record_test

    mov     x0, #0x3333
    movk    x0, #0x3333, lsl #16
    movk    x0, #0x3333, lsl #32
    movk    x0, #0x3333, lsl #48
    bl      peer_list_find
    cmp     x0, #2              // Should be at index 2
    b.ne    .Ltest5_fail

    // Find non-existent
    mov     x0, #0x9999
    movk    x0, #0x9999, lsl #16
    movk    x0, #0x9999, lsl #32
    movk    x0, #0x9999, lsl #48
    bl      peer_list_find
    cmp     x0, #-1
    b.ne    .Ltest5_fail

    bl      record_pass
    b       .Ltest6

.Ltest5_fail:
    bl      record_fail

    // =========================================================================
    // Test 6: Remove peer
    // =========================================================================
.Ltest6:
    adrp    x0, str_test_remove
    add     x0, x0, :lo12:str_test_remove
    bl      print_str
    bl      record_test

    // Remove peer with node_id 0x2222...
    mov     x0, #0x2222
    movk    x0, #0x2222, lsl #16
    movk    x0, #0x2222, lsl #32
    movk    x0, #0x2222, lsl #48
    bl      peer_list_remove
    cmp     x0, #0
    b.ne    .Ltest6_fail

    bl      record_pass
    b       .Ltest7

.Ltest6_fail:
    bl      record_fail

    // =========================================================================
    // Test 7: Verify count = 2
    // =========================================================================
.Ltest7:
    adrp    x0, str_test_count2
    add     x0, x0, :lo12:str_test_count2
    bl      print_str
    bl      record_test

    bl      peer_list_count
    cmp     x0, #2
    b.ne    .Ltest7_fail

    bl      record_pass
    b       .Ltest8

.Ltest7_fail:
    bl      record_fail

    // =========================================================================
    // Test 8: Save to file
    // =========================================================================
.Ltest8:
    adrp    x0, str_test_save
    add     x0, x0, :lo12:str_test_save
    bl      print_str
    bl      record_test

    adrp    x0, test_path
    add     x0, x0, :lo12:test_path
    bl      peer_list_save
    cmp     x0, #0
    b.lt    .Ltest8_fail

    bl      record_pass
    b       .Ltest9

.Ltest8_fail:
    bl      record_fail

    // =========================================================================
    // Test 9: Clear and reload
    // =========================================================================
.Ltest9:
    adrp    x0, str_test_reload
    add     x0, x0, :lo12:str_test_reload
    bl      print_str
    bl      record_test

    // Re-init (clears list)
    bl      peer_list_init

    // Verify empty
    bl      peer_list_count
    cbnz    x0, .Ltest9_fail

    // Load from file
    adrp    x0, test_path
    add     x0, x0, :lo12:test_path
    bl      peer_list_load
    cmp     x0, #2              // Should load 2 peers
    b.ne    .Ltest9_fail

    bl      record_pass
    b       .Ltest10

.Ltest9_fail:
    bl      record_fail

    // =========================================================================
    // Test 10: Verify reloaded data
    // =========================================================================
.Ltest10:
    adrp    x0, str_test_verify
    add     x0, x0, :lo12:str_test_verify
    bl      print_str
    bl      record_test

    // Verify count
    bl      peer_list_count
    cmp     x0, #2
    b.ne    .Ltest10_fail

    // Verify we can find one of the peers
    mov     x0, #0x1111
    movk    x0, #0x1111, lsl #16
    movk    x0, #0x1111, lsl #32
    movk    x0, #0x1111, lsl #48
    bl      peer_list_find
    cmp     x0, #0
    b.lt    .Ltest10_fail

    bl      record_pass
    b       .Ldone

.Ltest10_fail:
    bl      record_fail

    // =========================================================================
    // Summary
    // =========================================================================
.Ldone:
    adrp    x0, str_summary
    add     x0, x0, :lo12:str_summary
    bl      print_str

    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     w0, [x0]
    bl      print_num

    adrp    x0, str_slash
    add     x0, x0, :lo12:str_slash
    bl      print_str

    adrp    x0, tests_run
    add     x0, x0, :lo12:tests_run
    ldr     w0, [x0]
    bl      print_num

    adrp    x0, str_passed
    add     x0, x0, :lo12:str_passed
    bl      print_str

    // Clean up test file
    mov     x0, #AT_FDCWD
    adrp    x1, test_path
    add     x1, x1, :lo12:test_path
    mov     x2, #0
    mov     x8, #SYS_unlinkat
    svc     #0

    // Exit with 0 if all passed, 1 otherwise
    adrp    x0, tests_run
    add     x0, x0, :lo12:tests_run
    ldr     w1, [x0]
    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     w0, [x0]
    cmp     w0, w1
    b.eq    .Lexit_success

    mov     x0, #1
    mov     x8, #SYS_exit
    svc     #0

.Lexit_success:
    mov     x0, #0
    mov     x8, #SYS_exit
    svc     #0

// =============================================================================
// End of test_peer_list.s
// =============================================================================
