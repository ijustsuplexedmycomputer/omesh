// =============================================================================
// Omesh - JSON Parser Tests
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/json.inc"

.global _start

// =============================================================================
// Test Data
// =============================================================================

.section .rodata

test_header:
    .asciz "\n=== JSON Parser Tests ===\n\n"

// Test 1: Parse null
test1_name:
    .asciz "Test 1: Parse null"
test1_input:
    .asciz "null"
test1_input_len = . - test1_input - 1

// Test 2: Parse true
test2_name:
    .asciz "Test 2: Parse true"
test2_input:
    .asciz "true"
test2_input_len = . - test2_input - 1

// Test 3: Parse false
test3_name:
    .asciz "Test 3: Parse false"
test3_input:
    .asciz "false"
test3_input_len = . - test3_input - 1

// Test 4: Parse integer
test4_name:
    .asciz "Test 4: Parse integer"
test4_input:
    .asciz "42"
test4_input_len = . - test4_input - 1

// Test 5: Parse negative integer
test5_name:
    .asciz "Test 5: Parse negative integer"
test5_input:
    .asciz "-123"
test5_input_len = . - test5_input - 1

// Test 6: Parse string
test6_name:
    .asciz "Test 6: Parse string"
test6_input:
    .asciz "\"hello world\""
test6_input_len = . - test6_input - 1

// Test 7: Parse empty object
test7_name:
    .asciz "Test 7: Parse empty object"
test7_input:
    .asciz "{}"
test7_input_len = . - test7_input - 1

// Test 8: Parse simple object
test8_name:
    .asciz "Test 8: Parse simple object"
test8_input:
    .asciz "{\"name\":\"test\",\"count\":42}"
test8_input_len = . - test8_input - 1

// Test 9: Parse empty array
test9_name:
    .asciz "Test 9: Parse empty array"
test9_input:
    .asciz "[]"
test9_input_len = . - test9_input - 1

// Test 10: Parse array of numbers
test10_name:
    .asciz "Test 10: Parse array of numbers"
test10_input:
    .asciz "[1,2,3]"
test10_input_len = . - test10_input - 1

// Test 11: JSON writer - simple object
test11_name:
    .asciz "Test 11: JSON writer - simple object"

// Test 12: Get string from object
test12_name:
    .asciz "Test 12: Get string from object"
test12_input:
    .asciz "{\"query\":\"hello\",\"limit\":10}"
test12_input_len = . - test12_input - 1

msg_pass:
    .asciz " [PASS]\n"
msg_fail:
    .asciz " [FAIL]\n"
msg_summary:
    .asciz "\nTests passed: "
msg_of:
    .asciz " of "
msg_newline:
    .asciz "\n"
msg_type:
    .asciz "  type="
msg_value:
    .asciz "  value="
msg_len:
    .asciz "  len="

.section .bss
    .align 4
arena:
    .skip 16384                 // 16KB arena for parsing
write_buf:
    .skip 1024                  // Buffer for JSON writer
str_ptr_out:
    .skip 8
str_len_out:
    .skip 8

.section .data
tests_passed:
    .word 0
tests_total:
    .word 12

// =============================================================================
// Main Test Runner
// =============================================================================

.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Print header
    adr     x0, test_header
    bl      print_str

    // Run tests
    bl      test1_parse_null
    bl      test2_parse_true
    bl      test3_parse_false
    bl      test4_parse_integer
    bl      test5_parse_negative
    bl      test6_parse_string
    bl      test7_parse_empty_object
    bl      test8_parse_simple_object
    bl      test9_parse_empty_array
    bl      test10_parse_array
    bl      test11_json_writer
    bl      test12_get_string

    // Print summary
    adr     x0, msg_summary
    bl      print_str

    adr     x0, tests_passed
    ldr     w0, [x0]
    bl      print_num

    adr     x0, msg_of
    bl      print_str

    adr     x0, tests_total
    ldr     w0, [x0]
    bl      print_num

    adr     x0, msg_newline
    bl      print_str

    // Exit with code based on test results
    adr     x0, tests_passed
    ldr     w0, [x0]
    adr     x1, tests_total
    ldr     w1, [x1]
    cmp     w0, w1
    cset    w0, ne              // 0 if all passed, 1 if any failed

    mov     x8, #SYS_exit
    svc     #0

// =============================================================================
// Test 1: Parse null
// =============================================================================

test1_parse_null:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Print test name
    adr     x0, test1_name
    bl      print_str

    // Parse "null"
    adr     x0, test1_input
    mov     x1, #test1_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    // Check result
    cmp     x0, #0
    b.eq    1f

    // Check type is NULL
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_NULL
    b.ne    1f

    // Pass
    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 2: Parse true
// =============================================================================

test2_parse_true:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test2_name
    bl      print_str

    adr     x0, test2_input
    mov     x1, #test2_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    cmp     x0, #0
    b.eq    1f

    // Check type is BOOL
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_BOOL
    b.ne    1f

    // Check value is 1 (true)
    ldr     x1, [x0, #JSON_VAL_OFF_DATA]
    cmp     x1, #1
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 3: Parse false
// =============================================================================

test3_parse_false:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test3_name
    bl      print_str

    adr     x0, test3_input
    mov     x1, #test3_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    cmp     x0, #0
    b.eq    1f

    // Check type is BOOL
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_BOOL
    b.ne    1f

    // Check value is 0 (false)
    ldr     x1, [x0, #JSON_VAL_OFF_DATA]
    cmp     x1, #0
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 4: Parse integer
// =============================================================================

test4_parse_integer:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test4_name
    bl      print_str

    adr     x0, test4_input
    mov     x1, #test4_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    cmp     x0, #0
    b.eq    1f

    // Check type is NUMBER
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_NUMBER
    b.ne    1f

    // Check value is 42 (in fixed-point, high 32 bits = 42)
    ldr     x1, [x0, #JSON_VAL_OFF_DATA]
    lsr     x1, x1, #32         // Get integer part
    cmp     x1, #42
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 5: Parse negative integer
// =============================================================================

test5_parse_negative:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test5_name
    bl      print_str

    adr     x0, test5_input
    mov     x1, #test5_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    cmp     x0, #0
    b.eq    1f

    // Check type is NUMBER
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_NUMBER
    b.ne    1f

    // Check value is -123 (in fixed-point)
    ldr     x1, [x0, #JSON_VAL_OFF_DATA]
    asr     x1, x1, #32         // Get integer part (signed)
    cmn     x1, #123            // Compare with -123 (cmn adds)
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 6: Parse string
// =============================================================================

test6_parse_string:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test6_name
    bl      print_str

    adr     x0, test6_input
    mov     x1, #test6_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    cmp     x0, #0
    b.eq    1f

    // Check type is STRING
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_STRING
    b.ne    1f

    // Check length is 11 ("hello world")
    ldr     x1, [x0, #JSON_VAL_OFF_LEN]
    cmp     x1, #11
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 7: Parse empty object
// =============================================================================

test7_parse_empty_object:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test7_name
    bl      print_str

    adr     x0, test7_input
    mov     x1, #test7_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    cmp     x0, #0
    b.eq    1f

    // Check type is OBJECT
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_OBJECT
    b.ne    1f

    // Check length is 0 (no members)
    ldr     x1, [x0, #JSON_VAL_OFF_LEN]
    cmp     x1, #0
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 8: Parse simple object
// =============================================================================

test8_parse_simple_object:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test8_name
    bl      print_str

    // {"name":"test","count":42}
    adr     x0, test8_input
    mov     x1, #test8_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    cmp     x0, #0
    b.eq    1f

    // Check type is OBJECT
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_OBJECT
    b.ne    1f

    // Check length is 2 (two members)
    ldr     x1, [x0, #JSON_VAL_OFF_LEN]
    cmp     x1, #2
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 9: Parse empty array
// =============================================================================

test9_parse_empty_array:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test9_name
    bl      print_str

    adr     x0, test9_input
    mov     x1, #test9_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    cmp     x0, #0
    b.eq    1f

    // Check type is ARRAY
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_ARRAY
    b.ne    1f

    // Check length is 0
    ldr     x1, [x0, #JSON_VAL_OFF_LEN]
    cmp     x1, #0
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 10: Parse array of numbers
// =============================================================================

test10_parse_array:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test10_name
    bl      print_str

    // [1,2,3]
    adr     x0, test10_input
    mov     x1, #test10_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    cmp     x0, #0
    b.eq    1f

    // Check type is ARRAY
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_ARRAY
    b.ne    1f

    // Check length is 3
    ldr     x1, [x0, #JSON_VAL_OFF_LEN]
    cmp     x1, #3
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 11: JSON writer
// =============================================================================

test11_json_writer:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    adr     x0, test11_name
    bl      print_str

    // Write {"status":"ok","code":200}
    adr     x0, write_buf
    mov     x1, #1024
    bl      json_write_init
    mov     x19, x0             // Save writer pointer

    mov     x0, x19
    bl      json_write_object_start

    // json_write_key(key, len)
    adr     x0, str_status
    mov     x1, #6
    bl      json_write_key

    // json_write_string(str, len)
    adr     x0, str_ok
    mov     x1, #2
    bl      json_write_string

    // json_write_key(key, len)
    adr     x0, str_code
    mov     x1, #4
    bl      json_write_key

    // json_write_number(value) - fixed point
    mov     x0, #200
    lsl     x0, x0, #32
    bl      json_write_number

    mov     x0, x19
    bl      json_write_object_end

    mov     x0, x19
    bl      json_write_finish
    mov     x20, x0             // Save length

    // Check length > 0
    cmp     x20, #0
    b.le    1f

    // Verify output starts with '{'
    adr     x0, write_buf
    ldrb    w0, [x0]
    cmp     w0, #'{'
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

str_status:
    .asciz "status"
str_ok:
    .asciz "ok"
str_code:
    .asciz "code"

    .align 2

// =============================================================================
// Test 12: Get string from object
// =============================================================================

test12_get_string:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    adr     x0, test12_name
    bl      print_str

    // Parse {"query":"hello","limit":10}
    adr     x0, test12_input
    mov     x1, #test12_input_len
    adr     x2, arena
    mov     x3, #16384
    bl      json_parse

    cmp     x0, #0
    b.eq    1f
    mov     x19, x0             // Save root value

    // Get "query" string
    mov     x0, x19
    adr     x1, str_query
    mov     x2, #5
    adr     x3, str_ptr_out
    adr     x4, str_len_out
    bl      json_get_string

    cmp     x0, #0
    b.lt    1f

    // Check length is 5 ("hello")
    adr     x0, str_len_out
    ldr     x0, [x0]
    cmp     x0, #5
    b.ne    1f

    // Get "limit" number
    mov     x0, x19
    adr     x1, str_limit
    mov     x2, #5
    bl      json_get_number

    // Check value is 10 (fixed point)
    lsr     x0, x0, #32
    cmp     x0, #10
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #32
    ret

str_query:
    .asciz "query"
str_limit:
    .asciz "limit"

    .align 2

// =============================================================================
// Helper: Print pass
// =============================================================================

test_pass:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, msg_pass
    bl      print_str

    // Increment pass count
    adr     x0, tests_passed
    ldr     w1, [x0]
    add     w1, w1, #1
    str     w1, [x0]

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Helper: Print fail
// =============================================================================

test_fail:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, msg_fail
    bl      print_str

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Helper: Print string
// =============================================================================

print_str:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x19, x0

    // Find length
    mov     x1, #0
1:
    ldrb    w2, [x19, x1]
    cbz     w2, 2f
    add     x1, x1, #1
    b       1b
2:
    mov     x2, x1
    mov     x1, x19
    mov     x0, #1              // stdout
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Helper: Print number
// =============================================================================

print_num:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Convert to string
    mov     x1, x0
    add     x2, sp, #16         // Use stack for buffer
    mov     x3, x2
    add     x3, x3, #10         // End of buffer
    mov     x0, #0
    strb    w0, [x3]            // Null terminate
    sub     x3, x3, #1

    cbz     x1, 3f              // Handle 0

1:
    cbz     x1, 2f
    mov     x4, #10
    udiv    x5, x1, x4
    msub    x6, x5, x4, x1      // remainder
    add     w6, w6, #'0'
    strb    w6, [x3]
    sub     x3, x3, #1
    mov     x1, x5
    b       1b

2:
    add     x3, x3, #1
    b       4f

3:
    mov     w0, #'0'
    strb    w0, [x3]

4:
    // Print
    mov     x1, x3
    mov     x0, #1
    // Find length
    mov     x2, #0
5:
    ldrb    w4, [x1, x2]
    cbz     w4, 6f
    add     x2, x2, #1
    b       5b
6:
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #32
    ret
