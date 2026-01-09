// =============================================================================
// Omesh - HTTP Parser Unit Tests
// =============================================================================
//
// Tests HTTP request parsing and response building.
//
// =============================================================================

.include "syscall_nums.inc"
.include "http.inc"

.data

msg_banner:
    .asciz  "=== Omesh HTTP Parser Tests ===\n"

msg_pass:
    .asciz  "[PASS] "

msg_fail:
    .asciz  "[FAIL] "

msg_newline:
    .asciz  "\n"

msg_summary_pre:
    .asciz  "=== "

msg_summary_mid:
    .asciz  "/"

msg_summary_post:
    .asciz  " tests passed ===\n"

// Test names
test_name_parse_get:
    .asciz  "Parse GET request\n"

test_name_parse_post:
    .asciz  "Parse POST request\n"

test_name_parse_path:
    .asciz  "Parse path correctly\n"

test_name_parse_query:
    .asciz  "Parse query string\n"

test_name_parse_headers:
    .asciz  "Parse headers\n"

test_name_parse_content_len:
    .asciz  "Parse Content-Length\n"

test_name_parse_body:
    .asciz  "Parse request body\n"

test_name_build_200:
    .asciz  "Build 200 response\n"

test_name_build_404:
    .asciz  "Build 404 response\n"

test_name_build_body:
    .asciz  "Build response with body\n"

// Test HTTP requests
req_simple_get:
    .ascii  "GET / HTTP/1.1\r\n"
    .ascii  "Host: localhost\r\n"
    .asciz  "\r\n"
req_simple_get_len = . - req_simple_get - 1

req_get_path:
    .ascii  "GET /api/search HTTP/1.1\r\n"
    .ascii  "Host: localhost\r\n"
    .asciz  "\r\n"
req_get_path_len = . - req_get_path - 1

req_get_query:
    .ascii  "GET /search?q=hello&limit=10 HTTP/1.1\r\n"
    .ascii  "Host: localhost\r\n"
    .asciz  "\r\n"
req_get_query_len = . - req_get_query - 1

req_post_json:
    .ascii  "POST /api/index HTTP/1.1\r\n"
    .ascii  "Host: localhost\r\n"
    .ascii  "Content-Type: application/json\r\n"
    .ascii  "Content-Length: 27\r\n"
    .ascii  "\r\n"
    .asciz  "{\"text\":\"hello world test\"}"
req_post_json_len = . - req_post_json - 1

// Expected values
expected_path_root:
    .asciz  "/"
expected_path_search:
    .asciz  "/api/search"
expected_query:
    .asciz  "q=hello&limit=10"

.bss
.align 8
http_req:
    .skip   HTTP_REQ_SIZE

response_buf:
    .skip   4096

.text

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
// print_dec - Print decimal number
// =============================================================================
print_dec:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    mov     x1, sp
    add     x1, x1, #32
    mov     x2, #0

    cbz     x0, .Lpd_zero

.Lpd_loop:
    cbz     x0, .Lpd_print
    mov     x3, #10
    udiv    x4, x0, x3
    msub    x5, x4, x3, x0
    add     x5, x5, #'0'
    sub     x1, x1, #1
    strb    w5, [x1]
    add     x2, x2, #1
    mov     x0, x4
    b       .Lpd_loop

.Lpd_zero:
    mov     w5, #'0'
    sub     x1, x1, #1
    strb    w5, [x1]
    mov     x2, #1

.Lpd_print:
    mov     x0, #1
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// test_pass - Print pass message
// =============================================================================
test_pass:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0

    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_str
    mov     x0, x19
    bl      print_str

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_fail - Print fail message
// =============================================================================
test_fail:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0

    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_str
    mov     x0, x19
    bl      print_str

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// _start - Test entry point
// =============================================================================
.global _start
_start:
    mov     x29, sp
    mov     x19, #0                 // passed count
    mov     x20, #0                 // total count

    // Print banner
    adrp    x0, msg_banner
    add     x0, x0, :lo12:msg_banner
    bl      print_str

    // Test 1: Parse simple GET
    add     x20, x20, #1
    adrp    x0, req_simple_get
    add     x0, x0, :lo12:req_simple_get
    mov     x1, #req_simple_get_len
    adrp    x2, http_req
    add     x2, x2, :lo12:http_req
    bl      http_parse_request
    cmp     x0, #0
    b.ne    .Ltest1_fail

    // Check method is GET
    adrp    x0, http_req
    add     x0, x0, :lo12:http_req
    ldr     w1, [x0, #HTTP_REQ_OFF_METHOD]
    cmp     w1, #HTTP_METHOD_GET
    b.ne    .Ltest1_fail

    add     x19, x19, #1
    adrp    x0, test_name_parse_get
    add     x0, x0, :lo12:test_name_parse_get
    bl      test_pass
    b       .Ltest2

.Ltest1_fail:
    adrp    x0, test_name_parse_get
    add     x0, x0, :lo12:test_name_parse_get
    bl      test_fail

.Ltest2:
    // Test 2: Parse POST request
    add     x20, x20, #1
    adrp    x0, req_post_json
    add     x0, x0, :lo12:req_post_json
    mov     x1, #req_post_json_len
    adrp    x2, http_req
    add     x2, x2, :lo12:http_req
    bl      http_parse_request
    cmp     x0, #0
    b.ne    .Ltest2_fail

    // Check method is POST
    adrp    x0, http_req
    add     x0, x0, :lo12:http_req
    ldr     w1, [x0, #HTTP_REQ_OFF_METHOD]
    cmp     w1, #HTTP_METHOD_POST
    b.ne    .Ltest2_fail

    add     x19, x19, #1
    adrp    x0, test_name_parse_post
    add     x0, x0, :lo12:test_name_parse_post
    bl      test_pass
    b       .Ltest3

.Ltest2_fail:
    adrp    x0, test_name_parse_post
    add     x0, x0, :lo12:test_name_parse_post
    bl      test_fail

.Ltest3:
    // Test 3: Parse path correctly
    add     x20, x20, #1
    adrp    x0, req_get_path
    add     x0, x0, :lo12:req_get_path
    mov     x1, #req_get_path_len
    adrp    x2, http_req
    add     x2, x2, :lo12:http_req
    bl      http_parse_request
    cmp     x0, #0
    b.ne    .Ltest3_fail

    // Check path length is 11 ("/api/search")
    adrp    x0, http_req
    add     x0, x0, :lo12:http_req
    ldr     w1, [x0, #HTTP_REQ_OFF_PATH_LEN]
    cmp     w1, #11
    b.ne    .Ltest3_fail

    add     x19, x19, #1
    adrp    x0, test_name_parse_path
    add     x0, x0, :lo12:test_name_parse_path
    bl      test_pass
    b       .Ltest4

.Ltest3_fail:
    adrp    x0, test_name_parse_path
    add     x0, x0, :lo12:test_name_parse_path
    bl      test_fail

.Ltest4:
    // Test 4: Parse query string
    add     x20, x20, #1
    adrp    x0, req_get_query
    add     x0, x0, :lo12:req_get_query
    mov     x1, #req_get_query_len
    adrp    x2, http_req
    add     x2, x2, :lo12:http_req
    bl      http_parse_request
    cmp     x0, #0
    b.ne    .Ltest4_fail

    // Check query length is 16 ("q=hello&limit=10")
    adrp    x0, http_req
    add     x0, x0, :lo12:http_req
    ldr     w1, [x0, #HTTP_REQ_OFF_QUERY_LEN]
    cmp     w1, #16
    b.ne    .Ltest4_fail

    add     x19, x19, #1
    adrp    x0, test_name_parse_query
    add     x0, x0, :lo12:test_name_parse_query
    bl      test_pass
    b       .Ltest5

.Ltest4_fail:
    adrp    x0, test_name_parse_query
    add     x0, x0, :lo12:test_name_parse_query
    bl      test_fail

.Ltest5:
    // Test 5: Parse headers (Host)
    add     x20, x20, #1
    adrp    x0, req_simple_get
    add     x0, x0, :lo12:req_simple_get
    mov     x1, #req_simple_get_len
    adrp    x2, http_req
    add     x2, x2, :lo12:http_req
    bl      http_parse_request
    cmp     x0, #0
    b.ne    .Ltest5_fail

    // Check Host header was parsed (length = 9 for "localhost")
    adrp    x0, http_req
    add     x0, x0, :lo12:http_req
    ldr     w1, [x0, #HTTP_REQ_OFF_HOST_LEN]
    cmp     w1, #9
    b.ne    .Ltest5_fail

    add     x19, x19, #1
    adrp    x0, test_name_parse_headers
    add     x0, x0, :lo12:test_name_parse_headers
    bl      test_pass
    b       .Ltest6

.Ltest5_fail:
    adrp    x0, test_name_parse_headers
    add     x0, x0, :lo12:test_name_parse_headers
    bl      test_fail

.Ltest6:
    // Test 6: Parse Content-Length
    add     x20, x20, #1
    adrp    x0, req_post_json
    add     x0, x0, :lo12:req_post_json
    mov     x1, #req_post_json_len
    adrp    x2, http_req
    add     x2, x2, :lo12:http_req
    bl      http_parse_request
    cmp     x0, #0
    b.ne    .Ltest6_fail

    // Check Content-Length is 27
    adrp    x0, http_req
    add     x0, x0, :lo12:http_req
    ldr     x1, [x0, #HTTP_REQ_OFF_CONTENT_LEN]
    cmp     x1, #27
    b.ne    .Ltest6_fail

    add     x19, x19, #1
    adrp    x0, test_name_parse_content_len
    add     x0, x0, :lo12:test_name_parse_content_len
    bl      test_pass
    b       .Ltest7

.Ltest6_fail:
    adrp    x0, test_name_parse_content_len
    add     x0, x0, :lo12:test_name_parse_content_len
    bl      test_fail

.Ltest7:
    // Test 7: Parse request body
    add     x20, x20, #1
    adrp    x0, req_post_json
    add     x0, x0, :lo12:req_post_json
    mov     x1, #req_post_json_len
    adrp    x2, http_req
    add     x2, x2, :lo12:http_req
    bl      http_parse_request
    cmp     x0, #0
    b.ne    .Ltest7_fail

    // Check body pointer is set and body length
    adrp    x0, http_req
    add     x0, x0, :lo12:http_req
    ldr     x1, [x0, #HTTP_REQ_OFF_BODY_PTR]
    cbz     x1, .Ltest7_fail
    ldr     x2, [x0, #HTTP_REQ_OFF_BODY_LEN]
    cmp     x2, #27
    b.ne    .Ltest7_fail

    add     x19, x19, #1
    adrp    x0, test_name_parse_body
    add     x0, x0, :lo12:test_name_parse_body
    bl      test_pass
    b       .Ltest8

.Ltest7_fail:
    adrp    x0, test_name_parse_body
    add     x0, x0, :lo12:test_name_parse_body
    bl      test_fail

.Ltest8:
    // Test 8: Build 200 response
    add     x20, x20, #1
    mov     x0, #HTTP_STATUS_OK
    mov     x1, #0                  // no body
    mov     x2, #0
    mov     x3, #HTTP_CTYPE_JSON
    adrp    x4, response_buf
    add     x4, x4, :lo12:response_buf
    mov     x5, #4096
    bl      http_build_response
    cmp     x0, #0
    b.le    .Ltest8_fail

    // Check response starts with "HTTP/1.1 200"
    adrp    x1, response_buf
    add     x1, x1, :lo12:response_buf
    ldrb    w2, [x1]
    cmp     w2, #'H'
    b.ne    .Ltest8_fail

    add     x19, x19, #1
    adrp    x0, test_name_build_200
    add     x0, x0, :lo12:test_name_build_200
    bl      test_pass
    b       .Ltest9

.Ltest8_fail:
    adrp    x0, test_name_build_200
    add     x0, x0, :lo12:test_name_build_200
    bl      test_fail

.Ltest9:
    // Test 9: Build 404 response
    add     x20, x20, #1
    mov     x0, #HTTP_STATUS_NOT_FOUND
    mov     x1, #0
    mov     x2, #0
    mov     x3, #HTTP_CTYPE_JSON
    adrp    x4, response_buf
    add     x4, x4, :lo12:response_buf
    mov     x5, #4096
    bl      http_build_response
    cmp     x0, #0
    b.le    .Ltest9_fail

    add     x19, x19, #1
    adrp    x0, test_name_build_404
    add     x0, x0, :lo12:test_name_build_404
    bl      test_pass
    b       .Ltest10

.Ltest9_fail:
    adrp    x0, test_name_build_404
    add     x0, x0, :lo12:test_name_build_404
    bl      test_fail

.Ltest10:
    // Test 10: Build response with body
    add     x20, x20, #1
    mov     x0, #HTTP_STATUS_OK
    adrp    x1, expected_path_root
    add     x1, x1, :lo12:expected_path_root
    mov     x2, #1                  // body length
    mov     x3, #HTTP_CTYPE_TEXT_PLAIN
    adrp    x4, response_buf
    add     x4, x4, :lo12:response_buf
    mov     x5, #4096
    bl      http_build_response
    cmp     x0, #0
    b.le    .Ltest10_fail

    add     x19, x19, #1
    adrp    x0, test_name_build_body
    add     x0, x0, :lo12:test_name_build_body
    bl      test_pass
    b       .Lsummary

.Ltest10_fail:
    adrp    x0, test_name_build_body
    add     x0, x0, :lo12:test_name_build_body
    bl      test_fail

.Lsummary:
    // Print summary
    adrp    x0, msg_summary_pre
    add     x0, x0, :lo12:msg_summary_pre
    bl      print_str
    mov     x0, x19
    bl      print_dec
    adrp    x0, msg_summary_mid
    add     x0, x0, :lo12:msg_summary_mid
    bl      print_str
    mov     x0, x20
    bl      print_dec
    adrp    x0, msg_summary_post
    add     x0, x0, :lo12:msg_summary_post
    bl      print_str

    // Exit with status based on tests
    cmp     x19, x20
    b.eq    .Lexit_success
    mov     x0, #1
    mov     x8, #SYS_exit
    svc     #0

.Lexit_success:
    mov     x0, #0
    mov     x8, #SYS_exit
    svc     #0
