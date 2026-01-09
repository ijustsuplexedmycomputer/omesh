// =============================================================================
// Serial Transport Unit Tests
// =============================================================================
//
// Tests for serial transport functionality:
// - CRC-16 CCITT calculation
// - Frame encoding/decoding (via internal state machine)
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/transport.inc"

.extern serial_crc16

.global _start

.text

_start:
    // Print test header
    adrp    x0, msg_header
    add     x0, x0, :lo12:msg_header
    bl      print_string

    // Initialize test counters
    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    str     xzr, [x0]
    adrp    x0, tests_total
    add     x0, x0, :lo12:tests_total
    str     xzr, [x0]

    // Test 1: CRC-16 empty data
    bl      test_crc16_empty

    // Test 2: CRC-16 single byte
    bl      test_crc16_single

    // Test 3: CRC-16 "123456789"
    bl      test_crc16_standard

    // Test 4: CRC-16 known pattern
    bl      test_crc16_pattern

    // Test 5: Frame sync bytes
    bl      test_sync_bytes

    // Print summary
    adrp    x0, msg_summary1
    add     x0, x0, :lo12:msg_summary1
    bl      print_string

    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     x0, [x0]
    bl      print_number

    adrp    x0, msg_summary2
    add     x0, x0, :lo12:msg_summary2
    bl      print_string

    adrp    x0, tests_total
    add     x0, x0, :lo12:tests_total
    ldr     x0, [x0]
    bl      print_number

    adrp    x0, msg_summary3
    add     x0, x0, :lo12:msg_summary3
    bl      print_string

    // Exit with status based on tests
    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     x1, [x0]
    adrp    x0, tests_total
    add     x0, x0, :lo12:tests_total
    ldr     x2, [x0]
    cmp     x1, x2
    b.eq    .Lexit_success
    mov     x0, #1
    b       .Lexit
.Lexit_success:
    mov     x0, #0
.Lexit:
    mov     x8, #SYS_exit_group
    svc     #0


// =============================================================================
// Test: CRC-16 of empty data should be 0xFFFF (initial value)
// =============================================================================
test_crc16_empty:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Increment test count
    adrp    x0, tests_total
    add     x0, x0, :lo12:tests_total
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    // Print test name
    adrp    x0, test1_name
    add     x0, x0, :lo12:test1_name
    bl      print_string

    // Call CRC function with zero length
    adrp    x0, test_data
    add     x0, x0, :lo12:test_data
    mov     w1, #0
    bl      serial_crc16

    // Expected: 0xFFFF (no data processed)
    mov     w1, #0xFFFF
    cmp     w0, w1
    b.ne    .Ltest1_fail

    // Pass
    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_string
    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]
    ldp     x29, x30, [sp], #16
    ret

.Ltest1_fail:
    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_string
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// Test: CRC-16 of single byte 'A' (0x41) - check consistency
// =============================================================================
test_crc16_single:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Increment test count
    adrp    x0, tests_total
    add     x0, x0, :lo12:tests_total
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    // Print test name
    adrp    x0, test2_name
    add     x0, x0, :lo12:test2_name
    bl      print_string

    // Call CRC function
    adrp    x0, test_single_byte
    add     x0, x0, :lo12:test_single_byte
    mov     w1, #1
    bl      serial_crc16
    mov     w19, w0                     // Save first result

    // CRC should be different from initial value (0xFFFF)
    mov     w1, #0xFFFF
    cmp     w19, w1
    b.eq    .Ltest2_fail

    // CRC should be non-zero
    cbz     w19, .Ltest2_fail

    // Call again - should get same result (consistency check)
    adrp    x0, test_single_byte
    add     x0, x0, :lo12:test_single_byte
    mov     w1, #1
    bl      serial_crc16

    cmp     w0, w19
    b.ne    .Ltest2_fail

    // Pass
    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_string
    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Ltest2_fail:
    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_string
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// =============================================================================
// Test: CRC-16 of "123456789" (standard test vector)
// =============================================================================
test_crc16_standard:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Increment test count
    adrp    x0, tests_total
    add     x0, x0, :lo12:tests_total
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    // Print test name
    adrp    x0, test3_name
    add     x0, x0, :lo12:test3_name
    bl      print_string

    // Call CRC function
    adrp    x0, test_standard
    add     x0, x0, :lo12:test_standard
    mov     w1, #9
    bl      serial_crc16

    // Standard CRC-16 CCITT check value for "123456789" = 0x29B1
    mov     w1, #0x29B1
    cmp     w0, w1
    b.ne    .Ltest3_fail

    // Pass
    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_string
    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]
    ldp     x29, x30, [sp], #16
    ret

.Ltest3_fail:
    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_string
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// Test: CRC-16 of known binary pattern
// =============================================================================
test_crc16_pattern:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Increment test count
    adrp    x0, tests_total
    add     x0, x0, :lo12:tests_total
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    // Print test name
    adrp    x0, test4_name
    add     x0, x0, :lo12:test4_name
    bl      print_string

    // Call CRC function with 0x00 0xFF pattern
    adrp    x0, test_pattern
    add     x0, x0, :lo12:test_pattern
    mov     w1, #4
    bl      serial_crc16

    // Store result for comparison
    mov     w19, w0

    // CRC should be non-zero and consistent
    cbz     w19, .Ltest4_fail

    // Calculate again - should get same result
    adrp    x0, test_pattern
    add     x0, x0, :lo12:test_pattern
    mov     w1, #4
    bl      serial_crc16

    cmp     w0, w19
    b.ne    .Ltest4_fail

    // Pass
    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_string
    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]
    ldp     x29, x30, [sp], #16
    ret

.Ltest4_fail:
    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_string
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// Test: Sync byte constants
// =============================================================================
test_sync_bytes:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Increment test count
    adrp    x0, tests_total
    add     x0, x0, :lo12:tests_total
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    // Print test name
    adrp    x0, test5_name
    add     x0, x0, :lo12:test5_name
    bl      print_string

    // Verify sync byte constants
    mov     w0, #SERIAL_SYNC_BYTE1
    cmp     w0, #0xAA
    b.ne    .Ltest5_fail

    mov     w0, #SERIAL_SYNC_BYTE2
    cmp     w0, #0x55
    b.ne    .Ltest5_fail

    // Verify frame overhead
    mov     w0, #SERIAL_FRAME_OVERHEAD
    cmp     w0, #6
    b.ne    .Ltest5_fail

    // Pass
    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_string
    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]
    ldp     x29, x30, [sp], #16
    ret

.Ltest5_fail:
    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_string
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// Helper: Print null-terminated string
// =============================================================================
print_string:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                     // Save string pointer

    // Find string length
    mov     x1, x0
.Lstrlen_loop:
    ldrb    w2, [x1], #1
    cbnz    w2, .Lstrlen_loop
    sub     x2, x1, x19
    sub     x2, x2, #1                  // Don't count null

    // Write to stdout
    mov     x0, #STDOUT_FILENO
    mov     x1, x19
    mov     x8, #SYS_write
    svc     #0

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// =============================================================================
// Helper: Print number
// =============================================================================
print_number:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    // Convert number to string (simple decimal)
    add     x1, sp, #32                 // End of buffer
    mov     x2, x0
    mov     x3, #10

    strb    wzr, [x1]                   // Null terminator
    sub     x1, x1, #1

.Lnum_loop:
    udiv    x4, x2, x3
    msub    x5, x4, x3, x2              // remainder
    add     w5, w5, #'0'
    strb    w5, [x1]
    sub     x1, x1, #1
    mov     x2, x4
    cbnz    x2, .Lnum_loop

    add     x0, x1, #1
    bl      print_string

    ldp     x29, x30, [sp], #48
    ret


// =============================================================================
// Data Section
// =============================================================================

.section .rodata

msg_header:
    .asciz "\n=== Serial Transport Tests ===\n\n"

test1_name:
    .asciz "Test 1: CRC-16 empty data "
test2_name:
    .asciz "Test 2: CRC-16 single byte "
test3_name:
    .asciz "Test 3: CRC-16 '123456789' "
test4_name:
    .asciz "Test 4: CRC-16 consistency "
test5_name:
    .asciz "Test 5: Sync byte constants "

msg_pass:
    .asciz "[PASS]\n"
msg_fail:
    .asciz "[FAIL]\n"

msg_summary1:
    .asciz "\n=== "
msg_summary2:
    .asciz "/"
msg_summary3:
    .asciz " tests passed ===\n"

test_data:
    .byte   0
test_single_byte:
    .ascii  "A"
test_standard:
    .ascii  "123456789"
test_pattern:
    .byte   0x00, 0xFF, 0x00, 0xFF

.data
tests_passed:
    .quad   0
tests_total:
    .quad   0

