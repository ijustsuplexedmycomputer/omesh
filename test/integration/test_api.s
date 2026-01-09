// =============================================================================
// Omesh - HTTP API Server Integration Test
// =============================================================================
//
// Tests the HTTP server initialization and helper functions.
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/http.inc"

.global _start

// =============================================================================
// Test Data
// =============================================================================

.section .rodata

test_header:
    .asciz "\n=== HTTP API Server Tests ===\n\n"

// Test 1: Server init
test1_name:
    .asciz "Test 1: Server init on port 18080"

// Test 2: Server stop
test2_name:
    .asciz "Test 2: Server stop"

// Test 3: Path matches
test3_name:
    .asciz "Test 3: Path exact match"

// Test 4: Path starts with
test4_name:
    .asciz "Test 4: Path prefix match"

// Test 5: Parse query param
test5_name:
    .asciz "Test 5: Parse query param q="

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

path_health:
    .asciz "/health"
path_health_len = . - path_health - 1

path_search:
    .asciz "/search"
path_search_len = . - path_search - 1

path_search_query:
    .asciz "/search?q=test"
path_search_query_len = . - path_search_query - 1

query_string:
    .asciz "q=hello&limit=10"
query_string_len = . - query_string - 1

.section .data
tests_passed:
    .word 0
tests_total:
    .word 5

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
    bl      test1_server_init
    bl      test2_server_stop
    bl      test3_path_matches
    bl      test4_path_starts_with
    bl      test5_parse_query

    // Print summary
    adr     x0, msg_summary
    bl      print_str

    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     w0, [x0]
    bl      print_num

    adr     x0, msg_of
    bl      print_str

    adrp    x0, tests_total
    add     x0, x0, :lo12:tests_total
    ldr     w0, [x0]
    bl      print_num

    adr     x0, msg_newline
    bl      print_str

    // Exit with code based on test results
    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
    ldr     w0, [x0]
    adrp    x1, tests_total
    add     x1, x1, :lo12:tests_total
    ldr     w1, [x1]
    cmp     w0, w1
    cset    w0, ne              // 0 if all passed, 1 if any failed

    mov     x8, #SYS_exit
    svc     #0

// =============================================================================
// Test 1: Server init
// =============================================================================

test1_server_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test1_name
    bl      print_str

    // Init server on high port to avoid permission issues
    mov     x0, #18080
    bl      http_server_init

    cmp     x0, #0
    b.lt    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 2: Server stop
// =============================================================================

test2_server_stop:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test2_name
    bl      print_str

    // Stop the server
    bl      http_server_stop

    // Check running flag is 0
    adrp    x0, g_server_running
    add     x0, x0, :lo12:g_server_running
    ldr     w0, [x0]
    cbnz    w0, 1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    // Close the socket
    adrp    x0, g_server_fd
    add     x0, x0, :lo12:g_server_fd
    ldr     x0, [x0]
    cmp     x0, #0
    b.lt    3f
    mov     x8, #SYS_close
    svc     #0
3:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 3: Path matches
// =============================================================================

test3_path_matches:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test3_name
    bl      print_str

    // Test exact match
    adr     x0, path_health
    mov     x1, #path_health_len
    adr     x2, path_health
    mov     x3, #path_health_len
    bl      path_matches

    cmp     x0, #1
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 4: Path starts with
// =============================================================================

test4_path_starts_with:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test4_name
    bl      print_str

    // Test prefix match: "/search" starts with "/search?q=test"
    adr     x0, path_search
    mov     x1, #path_search_len
    adr     x2, path_search_query
    mov     x3, #path_search_query_len
    bl      path_starts_with

    cmp     x0, #1
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test 5: Parse query param
// =============================================================================

test5_parse_query:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    adr     x0, test5_name
    bl      print_str

    // Parse "q=hello&limit=10" to get "hello"
    adr     x0, query_string
    mov     x1, #query_string_len
    bl      parse_query_param

    // Check result is non-null
    cbz     x0, 1f

    // Check length is 5 ("hello")
    cmp     x1, #5
    b.ne    1f

    // Check first char is 'h'
    ldrb    w2, [x0]
    cmp     w2, #'h'
    b.ne    1f

    bl      test_pass
    b       2f
1:
    bl      test_fail
2:
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// External references
// =============================================================================

.extern http_server_init
.extern http_server_stop
.extern g_server_running
.extern g_server_fd
.extern path_matches
.extern path_starts_with
.extern parse_query_param

// =============================================================================
// Helper: Print pass
// =============================================================================

test_pass:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, msg_pass
    bl      print_str

    // Increment pass count
    adrp    x0, tests_passed
    add     x0, x0, :lo12:tests_passed
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

    mov     x1, x0
    add     x2, sp, #16
    mov     x3, x2
    add     x3, x3, #10
    mov     x0, #0
    strb    w0, [x3]
    sub     x3, x3, #1

    cbz     x1, 3f

1:
    cbz     x1, 2f
    mov     x4, #10
    udiv    x5, x1, x4
    msub    x6, x5, x4, x1
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
    mov     x1, x3
    mov     x0, #1
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
