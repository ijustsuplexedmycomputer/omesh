// =============================================================================
// Omesh - HTTP Parser Module
// =============================================================================
//
// Minimal HTTP/1.1 request parser for the API server.
//
// CALLING CONVENTION: AAPCS64
//   - Arguments: x0-x7 (x0 = first arg)
//   - Return value: x0
//   - Callee-saved: x19-x28
//   - Caller-saved: x0-x18
//
// PUBLIC API:
//
//   http_parse_request(buf, len, req_out) -> 0 | error
//       Parse HTTP request from buffer into HTTP_REQ structure.
//       Returns 0 on success, HTTP_ERR_* on error.
//
//   http_build_response(status, body, body_len, ctype, buf, max) -> len
//       Build HTTP response into buffer.
//       Returns bytes written or negative error.
//
//   http_get_status_text(status) -> ptr
//       Get status text for status code.
//
// =============================================================================

.include "syscall_nums.inc"
.include "http.inc"

.data

// Method strings for parsing
str_get:        .asciz "GET"
str_post:       .asciz "POST"
str_put:        .asciz "PUT"
str_delete:     .asciz "DELETE"
str_head:       .asciz "HEAD"
str_options:    .asciz "OPTIONS"

// Header names (lowercase for case-insensitive compare)
str_hdr_host:           .asciz "host"
str_hdr_content_length: .asciz "content-length"
str_hdr_content_type:   .asciz "content-type"
str_hdr_connection:     .asciz "connection"
str_hdr_transfer_enc:   .asciz "transfer-encoding"

// Header values
str_keepalive:  .asciz "keep-alive"
str_close:      .asciz "close"
str_chunked:    .asciz "chunked"

// HTTP version strings
str_http10:     .asciz "HTTP/1.0"
str_http11:     .asciz "HTTP/1.1"

// Status text
str_status_200: .asciz "OK"
str_status_201: .asciz "Created"
str_status_204: .asciz "No Content"
str_status_400: .asciz "Bad Request"
str_status_404: .asciz "Not Found"
str_status_405: .asciz "Method Not Allowed"
str_status_500: .asciz "Internal Server Error"
str_status_501: .asciz "Not Implemented"

// Response template parts
str_resp_ver:       .asciz "HTTP/1.1 "
str_resp_crlf:      .asciz "\r\n"
str_resp_ctype:     .asciz "Content-Type: "
str_resp_clen:      .asciz "Content-Length: "
str_resp_conn:      .asciz "Connection: close\r\n"
str_resp_server:    .asciz "Server: omesh/0.1\r\n"

// Content types
str_ctype_json:     .asciz "application/json"
str_ctype_text:     .asciz "text/plain"
str_ctype_html:     .asciz "text/html"

// CORS headers
str_cors_origin:    .asciz "Access-Control-Allow-Origin: *\r\n"
str_cors_methods:   .asciz "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
str_cors_headers:   .asciz "Access-Control-Allow-Headers: Content-Type\r\n"

.text

// =============================================================================
// http_parse_request - Parse HTTP request
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = buffer length
//   x2 = HTTP_REQ structure pointer (output)
// Output:
//   x0 = 0 on success, HTTP_ERR_* on error
// =============================================================================
.global http_parse_request
.type http_parse_request, %function
http_parse_request:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]

    mov     x19, x0                 // buf
    mov     x20, x1                 // len
    mov     x21, x2                 // req_out

    // Clear request structure
    mov     x0, x21
    mov     x1, #HTTP_REQ_SIZE
.Lclear_req:
    cbz     x1, .Lclear_done
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       .Lclear_req
.Lclear_done:

    // Store raw buffer info
    str     x19, [x21, #HTTP_REQ_OFF_RAW_PTR]
    str     x20, [x21, #HTTP_REQ_OFF_RAW_LEN]

    // Find end of request line (first \r\n)
    mov     x22, #0                 // position
.Lfind_line_end:
    cmp     x22, x20
    b.ge    .Lparse_incomplete
    ldrb    w0, [x19, x22]
    cmp     w0, #'\r'
    b.eq    .Lfound_cr
    add     x22, x22, #1
    b       .Lfind_line_end

.Lfound_cr:
    add     x23, x22, #1
    cmp     x23, x20
    b.ge    .Lparse_incomplete
    ldrb    w0, [x19, x23]
    cmp     w0, #'\n'
    b.ne    .Lparse_bad_header
    // x22 = position of \r, request line is [0, x22)

    // Parse method
    mov     x0, x19                 // buf start
    mov     x1, x22                 // line length
    bl      http_parse_method
    cmp     x0, #HTTP_METHOD_UNKNOWN
    b.eq    .Lparse_bad_method
    str     w0, [x21, #HTTP_REQ_OFF_METHOD]
    mov     x24, x1                 // position after method + space

    // Parse path (until space or ?)
    add     x25, x19, x24           // path start
    str     x25, [x21, #HTTP_REQ_OFF_PATH_PTR]
    mov     x26, #0                 // path length
.Lparse_path:
    add     x0, x24, x26
    cmp     x0, x22
    b.ge    .Lparse_bad_path
    ldrb    w0, [x25, x26]
    cmp     w0, #' '
    b.eq    .Lpath_done
    cmp     w0, #'?'
    b.eq    .Lpath_has_query
    add     x26, x26, #1
    b       .Lparse_path

.Lpath_has_query:
    str     w26, [x21, #HTTP_REQ_OFF_PATH_LEN]
    add     x26, x26, #1            // skip '?'
    add     x27, x25, x26           // query start
    str     x27, [x21, #HTTP_REQ_OFF_QUERY_PTR]
    // Find end of query
    mov     x28, #0
.Lparse_query:
    add     x0, x24, x26
    add     x0, x0, x28
    cmp     x0, x22
    b.ge    .Lparse_bad_path
    ldrb    w0, [x27, x28]
    cmp     w0, #' '
    b.eq    .Lquery_done
    add     x28, x28, #1
    b       .Lparse_query
.Lquery_done:
    str     w28, [x21, #HTTP_REQ_OFF_QUERY_LEN]
    add     x24, x24, x26
    add     x24, x24, x28
    add     x24, x24, #1            // skip space
    b       .Lparse_version

.Lpath_done:
    str     w26, [x21, #HTTP_REQ_OFF_PATH_LEN]
    add     x24, x24, x26
    add     x24, x24, #1            // skip space

.Lparse_version:
    // Parse HTTP version
    add     x0, x19, x24
    sub     x1, x22, x24            // remaining length
    bl      http_parse_version
    cmp     x0, #0
    b.eq    .Lparse_bad_version
    str     w0, [x21, #HTTP_REQ_OFF_VERSION]

    // Move past request line
    add     x22, x22, #2            // skip \r\n

    // Parse headers
    mov     x24, x22                // current position
.Lparse_headers:
    // Check for end of headers (\r\n)
    cmp     x24, x20
    b.ge    .Lparse_incomplete
    ldrb    w0, [x19, x24]
    cmp     w0, #'\r'
    b.ne    .Lparse_header_line

    add     x0, x24, #1
    cmp     x0, x20
    b.ge    .Lparse_incomplete
    ldrb    w0, [x19, x0]
    cmp     w0, #'\n'
    b.ne    .Lparse_header_line

    // End of headers
    add     x24, x24, #2
    str     x24, [x21, #HTTP_REQ_OFF_HEADER_END]

    // Check for body
    ldr     x0, [x21, #HTTP_REQ_OFF_CONTENT_LEN]
    cbz     x0, .Lparse_no_body

    // Has body - calculate body pointer and check if complete
    add     x25, x19, x24           // body start
    str     x25, [x21, #HTTP_REQ_OFF_BODY_PTR]
    sub     x26, x20, x24           // bytes remaining
    str     x26, [x21, #HTTP_REQ_OFF_BODY_LEN]

    // Check if we have full body
    cmp     x26, x0
    b.lt    .Lparse_incomplete

    // Full body received
    mov     w0, #HTTP_REQ_FLAG_COMPLETE
    orr     w0, w0, #HTTP_REQ_FLAG_HAS_BODY
    str     w0, [x21, #HTTP_REQ_OFF_FLAGS]
    mov     x0, #0
    b       .Lparse_done

.Lparse_no_body:
    mov     w0, #HTTP_REQ_FLAG_COMPLETE
    str     w0, [x21, #HTTP_REQ_OFF_FLAGS]
    mov     x0, #0
    b       .Lparse_done

.Lparse_header_line:
    // Find end of header line
    mov     x25, x24
.Lfind_header_end:
    cmp     x25, x20
    b.ge    .Lparse_incomplete
    ldrb    w0, [x19, x25]
    cmp     w0, #'\r'
    b.eq    .Lfound_header_end
    add     x25, x25, #1
    b       .Lfind_header_end

.Lfound_header_end:
    // Parse this header line [x24, x25)
    add     x0, x19, x24            // header start
    sub     x1, x25, x24            // header length
    mov     x2, x21                 // req struct
    bl      http_parse_header

    // Move past header line
    add     x24, x25, #2            // skip \r\n
    b       .Lparse_headers

.Lparse_incomplete:
    mov     x0, #HTTP_ERR_INCOMPLETE
    b       .Lparse_done

.Lparse_bad_method:
    mov     x0, #HTTP_ERR_BAD_METHOD
    b       .Lparse_done

.Lparse_bad_path:
    mov     x0, #HTTP_ERR_BAD_PATH
    b       .Lparse_done

.Lparse_bad_version:
    mov     x0, #HTTP_ERR_BAD_VERSION
    b       .Lparse_done

.Lparse_bad_header:
    mov     x0, #HTTP_ERR_BAD_HEADER

.Lparse_done:
    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret
.size http_parse_request, .-http_parse_request

// =============================================================================
// http_parse_method - Parse HTTP method
// =============================================================================
// Input:
//   x0 = line start
//   x1 = line length
// Output:
//   x0 = HTTP_METHOD_* enum
//   x1 = position after method + space
// =============================================================================
.type http_parse_method, %function
http_parse_method:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0
    mov     x20, x1

    // Check GET
    adrp    x1, str_get
    add     x1, x1, :lo12:str_get
    mov     x2, #3
    bl      http_memcmp_n
    cbz     x0, .Lmethod_get

    // Check POST
    mov     x0, x19
    adrp    x1, str_post
    add     x1, x1, :lo12:str_post
    mov     x2, #4
    bl      http_memcmp_n
    cbz     x0, .Lmethod_post

    // Check PUT
    mov     x0, x19
    adrp    x1, str_put
    add     x1, x1, :lo12:str_put
    mov     x2, #3
    bl      http_memcmp_n
    cbz     x0, .Lmethod_put

    // Check DELETE
    mov     x0, x19
    adrp    x1, str_delete
    add     x1, x1, :lo12:str_delete
    mov     x2, #6
    bl      http_memcmp_n
    cbz     x0, .Lmethod_delete

    // Check OPTIONS
    mov     x0, x19
    adrp    x1, str_options
    add     x1, x1, :lo12:str_options
    mov     x2, #7
    bl      http_memcmp_n
    cbz     x0, .Lmethod_options

    // Unknown method
    mov     x0, #HTTP_METHOD_UNKNOWN
    mov     x1, #0
    b       .Lmethod_done

.Lmethod_get:
    mov     x0, #HTTP_METHOD_GET
    mov     x1, #4                  // "GET "
    b       .Lmethod_done

.Lmethod_post:
    mov     x0, #HTTP_METHOD_POST
    mov     x1, #5                  // "POST "
    b       .Lmethod_done

.Lmethod_put:
    mov     x0, #HTTP_METHOD_PUT
    mov     x1, #4                  // "PUT "
    b       .Lmethod_done

.Lmethod_delete:
    mov     x0, #HTTP_METHOD_DELETE
    mov     x1, #7                  // "DELETE "
    b       .Lmethod_done

.Lmethod_options:
    mov     x0, #HTTP_METHOD_OPTIONS
    mov     x1, #8                  // "OPTIONS "

.Lmethod_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size http_parse_method, .-http_parse_method

// =============================================================================
// http_parse_version - Parse HTTP version
// =============================================================================
// Input:
//   x0 = version string start
//   x1 = max length
// Output:
//   x0 = HTTP_VERSION_* or 0 on error
// =============================================================================
.type http_parse_version, %function
http_parse_version:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0
    mov     x20, x1

    // Check HTTP/1.1
    adrp    x1, str_http11
    add     x1, x1, :lo12:str_http11
    mov     x2, #8
    bl      http_memcmp_n
    cbz     x0, .Lversion_11

    // Check HTTP/1.0
    mov     x0, x19
    adrp    x1, str_http10
    add     x1, x1, :lo12:str_http10
    mov     x2, #8
    bl      http_memcmp_n
    cbz     x0, .Lversion_10

    mov     x0, #0
    b       .Lversion_done

.Lversion_11:
    mov     x0, #HTTP_VERSION_11
    b       .Lversion_done

.Lversion_10:
    mov     x0, #HTTP_VERSION_10

.Lversion_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size http_parse_version, .-http_parse_version

// =============================================================================
// http_parse_header - Parse single header line
// =============================================================================
// Input:
//   x0 = header line start
//   x1 = header line length (excluding \r\n)
//   x2 = HTTP_REQ structure
// Output:
//   x0 = 0 on success
// =============================================================================
.type http_parse_header, %function
http_parse_header:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                 // line start
    mov     x20, x1                 // line length
    mov     x21, x2                 // req struct

    // Find colon
    mov     x22, #0
.Lfind_colon:
    cmp     x22, x20
    b.ge    .Lheader_done           // No colon, skip
    ldrb    w0, [x19, x22]
    cmp     w0, #':'
    b.eq    .Lfound_colon
    add     x22, x22, #1
    b       .Lfind_colon

.Lfound_colon:
    // x22 = position of colon
    // Header name is [0, x22), value starts after ": "

    // Skip ": " (colon and optional whitespace)
    add     x23, x22, #1
.Lskip_ws:
    cmp     x23, x20
    b.ge    .Lheader_done
    ldrb    w0, [x19, x23]
    cmp     w0, #' '
    b.eq    .Lskip_ws_next
    cmp     w0, #'\t'
    b.eq    .Lskip_ws_next
    b       .Lgot_value
.Lskip_ws_next:
    add     x23, x23, #1
    b       .Lskip_ws

.Lgot_value:
    // x23 = start of value, value length = x20 - x23
    sub     x24, x20, x23           // value length

    // Check which header this is (case-insensitive)
    // Check Host:
    mov     x0, x19
    mov     x1, x22                 // name length
    adrp    x2, str_hdr_host
    add     x2, x2, :lo12:str_hdr_host
    mov     x3, #4
    bl      http_hdr_match
    cbnz    x0, .Lhdr_host

    // Check Content-Length:
    mov     x0, x19
    mov     x1, x22
    adrp    x2, str_hdr_content_length
    add     x2, x2, :lo12:str_hdr_content_length
    mov     x3, #14
    bl      http_hdr_match
    cbnz    x0, .Lhdr_content_length

    // Check Content-Type:
    mov     x0, x19
    mov     x1, x22
    adrp    x2, str_hdr_content_type
    add     x2, x2, :lo12:str_hdr_content_type
    mov     x3, #12
    bl      http_hdr_match
    cbnz    x0, .Lhdr_content_type

    // Check Connection:
    mov     x0, x19
    mov     x1, x22
    adrp    x2, str_hdr_connection
    add     x2, x2, :lo12:str_hdr_connection
    mov     x3, #10
    bl      http_hdr_match
    cbnz    x0, .Lhdr_connection

    // Unknown header, skip
    b       .Lheader_done

.Lhdr_host:
    add     x0, x19, x23            // value ptr
    str     x0, [x21, #HTTP_REQ_OFF_HOST_PTR]
    str     w24, [x21, #HTTP_REQ_OFF_HOST_LEN]
    b       .Lheader_done

.Lhdr_content_length:
    // Parse integer value
    add     x0, x19, x23
    mov     x1, x24
    bl      http_parse_int
    str     x0, [x21, #HTTP_REQ_OFF_CONTENT_LEN]
    b       .Lheader_done

.Lhdr_content_type:
    add     x0, x19, x23
    str     x0, [x21, #HTTP_REQ_OFF_CONTENT_TYPE]
    str     w24, [x21, #HTTP_REQ_OFF_CTYPE_LEN]
    b       .Lheader_done

.Lhdr_connection:
    // Check for keep-alive
    add     x0, x19, x23
    mov     x1, x24
    adrp    x2, str_keepalive
    add     x2, x2, :lo12:str_keepalive
    mov     x3, #10
    bl      http_hdr_match
    cbz     x0, .Lheader_done
    mov     w0, #1
    str     w0, [x21, #HTTP_REQ_OFF_KEEPALIVE]

.Lheader_done:
    mov     x0, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size http_parse_header, .-http_parse_header

// =============================================================================
// http_hdr_match - Case-insensitive header name match
// =============================================================================
// Input:
//   x0 = header name from request
//   x1 = header name length
//   x2 = expected name (lowercase)
//   x3 = expected name length
// Output:
//   x0 = 1 if match, 0 if no match
// =============================================================================
.type http_hdr_match, %function
http_hdr_match:
    // Check lengths match
    cmp     x1, x3
    b.ne    .Lhdr_no_match

    mov     x4, #0
.Lhdr_cmp_loop:
    cmp     x4, x1
    b.ge    .Lhdr_match_yes

    ldrb    w5, [x0, x4]            // char from request
    ldrb    w6, [x2, x4]            // char from expected

    // Convert to lowercase
    cmp     w5, #'A'
    b.lt    .Lhdr_no_conv
    cmp     w5, #'Z'
    b.gt    .Lhdr_no_conv
    add     w5, w5, #32             // to lowercase
.Lhdr_no_conv:

    cmp     w5, w6
    b.ne    .Lhdr_no_match

    add     x4, x4, #1
    b       .Lhdr_cmp_loop

.Lhdr_match_yes:
    mov     x0, #1
    ret

.Lhdr_no_match:
    mov     x0, #0
    ret
.size http_hdr_match, .-http_hdr_match

// =============================================================================
// http_parse_int - Parse decimal integer
// =============================================================================
// Input:
//   x0 = string pointer
//   x1 = string length
// Output:
//   x0 = parsed value
// =============================================================================
.type http_parse_int, %function
http_parse_int:
    mov     x2, #0                  // result
    mov     x3, #0                  // index

.Lparse_int_loop:
    cmp     x3, x1
    b.ge    .Lparse_int_done

    ldrb    w4, [x0, x3]
    cmp     w4, #'0'
    b.lt    .Lparse_int_done
    cmp     w4, #'9'
    b.gt    .Lparse_int_done

    sub     w4, w4, #'0'
    mov     x5, #10
    mul     x2, x2, x5
    add     x2, x2, x4

    add     x3, x3, #1
    b       .Lparse_int_loop

.Lparse_int_done:
    mov     x0, x2
    ret
.size http_parse_int, .-http_parse_int

// =============================================================================
// http_memcmp_n - Compare n bytes
// =============================================================================
// Input:
//   x0 = ptr1
//   x1 = ptr2
//   x2 = n bytes
// Output:
//   x0 = 0 if equal, non-zero if different
// =============================================================================
.type http_memcmp_n, %function
http_memcmp_n:
    mov     x3, #0
.Lmemcmp_loop:
    cmp     x3, x2
    b.ge    .Lmemcmp_equal

    ldrb    w4, [x0, x3]
    ldrb    w5, [x1, x3]
    cmp     w4, w5
    b.ne    .Lmemcmp_diff

    add     x3, x3, #1
    b       .Lmemcmp_loop

.Lmemcmp_equal:
    mov     x0, #0
    ret

.Lmemcmp_diff:
    sub     x0, x4, x5
    ret
.size http_memcmp_n, .-http_memcmp_n

// =============================================================================
// http_build_response - Build HTTP response
// =============================================================================
// Input:
//   x0 = status code
//   x1 = body pointer (or NULL)
//   x2 = body length
//   x3 = content-type (HTTP_CTYPE_* enum)
//   x4 = output buffer
//   x5 = max buffer size
// Output:
//   x0 = bytes written, or negative error
// =============================================================================
.global http_build_response
.type http_build_response, %function
http_build_response:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0                 // status
    mov     x20, x1                 // body ptr
    mov     x21, x2                 // body len
    mov     x22, x3                 // content type
    mov     x23, x4                 // output buf
    mov     x24, x5                 // max size
    mov     x25, #0                 // bytes written

    // Write "HTTP/1.1 "
    adrp    x0, str_resp_ver
    add     x0, x0, :lo12:str_resp_ver
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    // Write status code
    mov     x0, x19
    add     x1, x23, x25
    bl      http_write_int
    add     x25, x25, x0

    // Write space
    mov     w0, #' '
    strb    w0, [x23, x25]
    add     x25, x25, #1

    // Write status text
    mov     x0, x19
    bl      http_get_status_text
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    // Write \r\n
    adrp    x0, str_resp_crlf
    add     x0, x0, :lo12:str_resp_crlf
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    // Write Server header
    adrp    x0, str_resp_server
    add     x0, x0, :lo12:str_resp_server
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    // Write CORS headers
    adrp    x0, str_cors_origin
    add     x0, x0, :lo12:str_cors_origin
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    adrp    x0, str_cors_methods
    add     x0, x0, :lo12:str_cors_methods
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    adrp    x0, str_cors_headers
    add     x0, x0, :lo12:str_cors_headers
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    // Write Content-Type header if body present
    cbz     x20, .Lresp_no_ctype

    adrp    x0, str_resp_ctype
    add     x0, x0, :lo12:str_resp_ctype
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    // Get content type string
    mov     x0, x22
    bl      http_get_ctype_str
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    adrp    x0, str_resp_crlf
    add     x0, x0, :lo12:str_resp_crlf
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

.Lresp_no_ctype:
    // Write Content-Length header
    adrp    x0, str_resp_clen
    add     x0, x0, :lo12:str_resp_clen
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    mov     x0, x21                 // body length
    add     x1, x23, x25
    bl      http_write_int
    add     x25, x25, x0

    adrp    x0, str_resp_crlf
    add     x0, x0, :lo12:str_resp_crlf
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    // Write Connection: close
    adrp    x0, str_resp_conn
    add     x0, x0, :lo12:str_resp_conn
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    // Write final \r\n
    adrp    x0, str_resp_crlf
    add     x0, x0, :lo12:str_resp_crlf
    add     x1, x23, x25
    bl      http_strcpy
    add     x25, x25, x0

    // Write body if present
    cbz     x20, .Lresp_done
    cbz     x21, .Lresp_done

    // Check space
    add     x0, x25, x21
    cmp     x0, x24
    b.gt    .Lresp_too_large

    // Copy body
    mov     x0, #0
.Lresp_copy_body:
    cmp     x0, x21
    b.ge    .Lresp_body_done
    ldrb    w1, [x20, x0]
    add     x2, x23, x25
    strb    w1, [x2, x0]
    add     x0, x0, #1
    b       .Lresp_copy_body

.Lresp_body_done:
    add     x25, x25, x21

.Lresp_done:
    mov     x0, x25
    b       .Lresp_exit

.Lresp_too_large:
    mov     x0, #HTTP_ERR_TOO_LARGE

.Lresp_exit:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size http_build_response, .-http_build_response

// =============================================================================
// http_get_status_text - Get status text for code
// =============================================================================
// Input:
//   x0 = status code
// Output:
//   x0 = pointer to status text
// =============================================================================
.global http_get_status_text
.type http_get_status_text, %function
http_get_status_text:
    cmp     x0, #200
    b.eq    .Lstatus_200
    cmp     x0, #201
    b.eq    .Lstatus_201
    cmp     x0, #204
    b.eq    .Lstatus_204
    cmp     x0, #400
    b.eq    .Lstatus_400
    cmp     x0, #404
    b.eq    .Lstatus_404
    cmp     x0, #405
    b.eq    .Lstatus_405
    cmp     x0, #500
    b.eq    .Lstatus_500
    cmp     x0, #501
    b.eq    .Lstatus_501
    // Default to 500
    b       .Lstatus_500

.Lstatus_200:
    adrp    x0, str_status_200
    add     x0, x0, :lo12:str_status_200
    ret
.Lstatus_201:
    adrp    x0, str_status_201
    add     x0, x0, :lo12:str_status_201
    ret
.Lstatus_204:
    adrp    x0, str_status_204
    add     x0, x0, :lo12:str_status_204
    ret
.Lstatus_400:
    adrp    x0, str_status_400
    add     x0, x0, :lo12:str_status_400
    ret
.Lstatus_404:
    adrp    x0, str_status_404
    add     x0, x0, :lo12:str_status_404
    ret
.Lstatus_405:
    adrp    x0, str_status_405
    add     x0, x0, :lo12:str_status_405
    ret
.Lstatus_500:
    adrp    x0, str_status_500
    add     x0, x0, :lo12:str_status_500
    ret
.Lstatus_501:
    adrp    x0, str_status_501
    add     x0, x0, :lo12:str_status_501
    ret
.size http_get_status_text, .-http_get_status_text

// =============================================================================
// http_get_ctype_str - Get content type string
// =============================================================================
// Input:
//   x0 = HTTP_CTYPE_* enum
// Output:
//   x0 = pointer to content type string
// =============================================================================
.type http_get_ctype_str, %function
http_get_ctype_str:
    cmp     x0, #HTTP_CTYPE_JSON
    b.eq    .Lctype_json
    cmp     x0, #HTTP_CTYPE_TEXT_PLAIN
    b.eq    .Lctype_text
    cmp     x0, #HTTP_CTYPE_TEXT_HTML
    b.eq    .Lctype_html
    // Default to text/plain
    b       .Lctype_text

.Lctype_json:
    adrp    x0, str_ctype_json
    add     x0, x0, :lo12:str_ctype_json
    ret
.Lctype_text:
    adrp    x0, str_ctype_text
    add     x0, x0, :lo12:str_ctype_text
    ret
.Lctype_html:
    adrp    x0, str_ctype_html
    add     x0, x0, :lo12:str_ctype_html
    ret
.size http_get_ctype_str, .-http_get_ctype_str

// =============================================================================
// http_strcpy - Copy null-terminated string
// =============================================================================
// Input:
//   x0 = source string
//   x1 = destination
// Output:
//   x0 = bytes copied (not including null)
// =============================================================================
.type http_strcpy, %function
http_strcpy:
    mov     x2, #0
.Lstrcpy_loop:
    ldrb    w3, [x0, x2]
    cbz     w3, .Lstrcpy_done
    strb    w3, [x1, x2]
    add     x2, x2, #1
    b       .Lstrcpy_loop
.Lstrcpy_done:
    mov     x0, x2
    ret
.size http_strcpy, .-http_strcpy

// =============================================================================
// http_write_int - Write integer as decimal string
// =============================================================================
// Input:
//   x0 = integer value
//   x1 = destination buffer
// Output:
//   x0 = bytes written
// =============================================================================
.type http_write_int, %function
http_write_int:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    mov     x2, x1                  // dest
    cbz     x0, .Lwint_zero

    // Build digits in reverse on stack
    add     x3, sp, #32             // temp buffer end
    mov     x4, #0                  // digit count

.Lwint_loop:
    cbz     x0, .Lwint_copy
    mov     x5, #10
    udiv    x6, x0, x5
    msub    x7, x6, x5, x0          // remainder
    add     x7, x7, #'0'
    sub     x3, x3, #1
    strb    w7, [x3]
    add     x4, x4, #1
    mov     x0, x6
    b       .Lwint_loop

.Lwint_copy:
    // Copy digits to destination
    mov     x0, #0
.Lwint_copy_loop:
    cmp     x0, x4
    b.ge    .Lwint_done
    ldrb    w5, [x3, x0]
    strb    w5, [x2, x0]
    add     x0, x0, #1
    b       .Lwint_copy_loop

.Lwint_done:
    ldp     x29, x30, [sp], #48
    ret

.Lwint_zero:
    mov     w0, #'0'
    strb    w0, [x2]
    mov     x0, #1
    ldp     x29, x30, [sp], #48
    ret
.size http_write_int, .-http_write_int
