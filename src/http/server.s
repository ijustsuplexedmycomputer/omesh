// =============================================================================
// Omesh - HTTP Server
// =============================================================================
//
// Minimal HTTP/1.1 server for the search API.
//
// API Endpoints:
//   GET  /health         - Health check
//   POST /index          - Index a document (JSON body: {"content":"..."})
//   GET  /search?q=...   - Search query
//
// =============================================================================

.include "syscall_nums.inc"
.include "http.inc"
.include "json.inc"
.include "index.inc"
.include "mesh.inc"
.include "transport.inc"

// External function for mesh polling
.extern mesh_net_poll

// =============================================================================
// Constants
// =============================================================================

.equ HTTP_DEFAULT_PORT,     8080
.equ POLLIN,                0x0001
.equ HTTP_BACKLOG,          16
.equ HTTP_RECV_BUF_SIZE,    8192
.equ HTTP_SEND_BUF_SIZE,    16384
.equ MAX_QUERY_LEN,         256

// =============================================================================
// Data
// =============================================================================

.section .data
.align 3

.global g_server_fd
g_server_fd:
    .quad   -1

g_server_port:
    .word   HTTP_DEFAULT_PORT

.global g_server_running
g_server_running:
    .word   0

// =============================================================================
// BSS
// =============================================================================

.section .bss
.align 4

recv_buffer:
    .skip   HTTP_RECV_BUF_SIZE

send_buffer:
    .skip   HTTP_SEND_BUF_SIZE

request_state:
    .skip   HTTP_REQ_SIZE

json_arena:
    .skip   JSON_ARENA_SIZE

// =============================================================================
// Read-only data
// =============================================================================

.section .rodata

str_health_ok:
    .asciz "{\"status\":\"ok\"}"
str_health_ok_len = . - str_health_ok - 1

str_error_method:
    .asciz "{\"error\":\"method not allowed\"}"
str_error_method_len = . - str_error_method - 1

str_error_notfound:
    .asciz "{\"error\":\"not found\"}"
str_error_notfound_len = . - str_error_notfound - 1

str_error_bad_request:
    .asciz "{\"error\":\"bad request\"}"
str_error_bad_request_len = . - str_error_bad_request - 1

str_error_internal:
    .asciz "{\"error\":\"internal error\"}"
str_error_internal_len = . - str_error_internal - 1

str_path_health:
    .asciz "/health"
str_path_health_len = . - str_path_health - 1

str_path_index:
    .asciz "/index"
str_path_index_len = . - str_path_index - 1

str_path_search:
    .asciz "/search"
str_path_search_len = . - str_path_search - 1

str_path_peers:
    .asciz "/peers"
str_path_peers_len = . - str_path_peers - 1

str_path_status:
    .asciz "/status"
str_path_status_len = . - str_path_status - 1

str_content_key:
    .asciz "content"

str_query_key:
    .asciz "q"

str_ctype_json:
    .asciz "application/json"

str_indexed_fmt:
    .asciz "{\"status\":\"indexed\",\"doc_id\":%lu}"

str_results_start:
    .asciz "{\"results\":["

str_results_end:
    .asciz "],\"total\":%d}"

str_result_item:
    .asciz "{\"doc_id\":%lu,\"score\":%d}"

str_search_debug:
    .asciz "{\"results\":[],\"total\":0}"
str_search_debug_len = . - str_search_debug - 1

// =============================================================================
// Code
// =============================================================================

.section .text

// =============================================================================
// http_server_init - Initialize HTTP server
// =============================================================================
// Input:
//   x0 = port (0 for default)
// Output:
//   x0 = 0 on success, -errno on error
// =============================================================================
.global http_server_init
.type http_server_init, %function
http_server_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Set port
    cbz     x0, .Lhsi_default_port
    adrp    x1, g_server_port
    add     x1, x1, :lo12:g_server_port
    str     w0, [x1]
    b       .Lhsi_create_socket

.Lhsi_default_port:
    mov     w0, #HTTP_DEFAULT_PORT
    adrp    x1, g_server_port
    add     x1, x1, :lo12:g_server_port
    str     w0, [x1]

.Lhsi_create_socket:
    // Create socket
    mov     x0, #AF_INET
    mov     x1, #SOCK_STREAM
    mov     x2, #0
    mov     x8, #SYS_socket
    svc     #0

    cmp     x0, #0
    b.lt    .Lhsi_error

    mov     x19, x0             // Save socket fd

    // Store fd
    adrp    x1, g_server_fd
    add     x1, x1, :lo12:g_server_fd
    str     x0, [x1]

    // Set SO_REUSEADDR
    sub     sp, sp, #16
    mov     w0, #1
    str     w0, [sp]

    mov     x0, x19
    mov     x1, #SOL_SOCKET
    mov     x2, #SO_REUSEADDR
    mov     x3, sp
    mov     x4, #4
    mov     x8, #SYS_setsockopt
    svc     #0
    add     sp, sp, #16

    // Bind
    sub     sp, sp, #16
    mov     w0, #AF_INET
    adrp    x1, g_server_port
    add     x1, x1, :lo12:g_server_port
    ldrh    w1, [x1]
    // Convert port to network byte order (big endian)
    rev16   w1, w1
    orr     w0, w0, w1, lsl #16
    str     w0, [sp]
    str     xzr, [sp, #4]       // INADDR_ANY
    str     xzr, [sp, #12]

    mov     x0, x19
    mov     x1, sp
    mov     x2, #16
    mov     x8, #SYS_bind
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Lhsi_close_error

    // Listen
    mov     x0, x19
    mov     x1, #HTTP_BACKLOG
    mov     x8, #SYS_listen
    svc     #0

    cmp     x0, #0
    b.lt    .Lhsi_close_error

    // Mark running
    adrp    x0, g_server_running
    add     x0, x0, :lo12:g_server_running
    mov     w1, #1
    str     w1, [x0]

    mov     x0, #0
    b       .Lhsi_ret

.Lhsi_close_error:
    mov     x20, x0             // Save error
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0
    mov     x0, x20
    b       .Lhsi_ret

.Lhsi_error:
    // x0 already has error

.Lhsi_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size http_server_init, .-http_server_init

// =============================================================================
// http_server_run - Run HTTP server with mesh event polling
// =============================================================================
// Input: none
// Output:
//   x0 = 0 on normal shutdown, -errno on error
// =============================================================================
.global http_server_run
.type http_server_run, %function
http_server_run:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    adrp    x19, g_server_fd
    add     x19, x19, :lo12:g_server_fd
    ldr     x19, [x19]          // server fd

.Lhsr_loop:
    // Check if still running
    adrp    x0, g_server_running
    add     x0, x0, :lo12:g_server_running
    ldr     w0, [x0]
    cbz     w0, .Lhsr_shutdown

    // Set up pollfd structure on stack
    // pollfd: int fd (4), short events (2), short revents (2) = 8 bytes
    // timespec: long tv_sec (8), long tv_nsec (8) = 16 bytes
    // Total: 24 bytes, aligned to 32
    sub     sp, sp, #32

    // pollfd at sp+0
    str     w19, [sp]               // fd = server_fd
    mov     w0, #POLLIN
    strh    w0, [sp, #4]            // events = POLLIN
    strh    wzr, [sp, #6]           // revents = 0

    // timespec at sp+16 (100ms timeout for mesh polling)
    str     xzr, [sp, #16]          // tv_sec = 0
    // 100ms in nanoseconds = 100000000 = 0x5F5E100
    movz    x0, #0xE100             // Lower 16 bits
    movk    x0, #0x5F5, lsl #16     // Upper bits
    str     x0, [sp, #24]           // tv_nsec = 100000000

    // ppoll(fds, nfds, timeout, sigmask)
    mov     x0, sp                  // fds
    mov     x1, #1                  // nfds = 1
    add     x2, sp, #16             // timeout
    mov     x3, #0                  // sigmask = NULL
    mov     x8, #SYS_ppoll
    svc     #0

    // Check poll result
    cmp     x0, #0
    b.lt    .Lhsr_poll_error
    b.eq    .Lhsr_poll_timeout

    // Check revents for POLLIN
    ldrh    w0, [sp, #6]
    add     sp, sp, #32
    tst     w0, #POLLIN
    b.eq    .Lhsr_poll_mesh         // No POLLIN, just poll mesh

    // Accept connection
    sub     sp, sp, #32             // Space for sockaddr
    mov     x0, x19
    mov     x1, sp
    add     x2, sp, #16
    mov     w3, #16
    str     w3, [x2]
    mov     x8, #SYS_accept
    svc     #0
    add     sp, sp, #32

    cmp     x0, #0
    b.lt    .Lhsr_poll_mesh         // Accept failed, poll mesh

    mov     x20, x0                 // Client fd

    // Handle request
    mov     x0, x20
    bl      http_handle_client

    // Close client socket
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0

    b       .Lhsr_poll_mesh

.Lhsr_poll_timeout:
    add     sp, sp, #32

.Lhsr_poll_mesh:
    // Poll mesh events (non-blocking)
    bl      mesh_net_poll
    b       .Lhsr_loop

.Lhsr_poll_error:
    add     sp, sp, #32
    // Check for EINTR (interrupted by signal)
    cmn     x0, #EINTR
    b.ne    .Lhsr_loop              // Other error - continue

    // EINTR: Check if shutdown was requested
    bl      signal_shutdown_requested
    cbnz    x0, .Lhsr_shutdown      // Signal received, exit
    b       .Lhsr_loop

.Lhsr_shutdown:
    mov     x0, #0

.Lhsr_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size http_server_run, .-http_server_run

// =============================================================================
// http_server_stop - Signal server to stop
// =============================================================================
.global http_server_stop
.type http_server_stop, %function
http_server_stop:
    adrp    x0, g_server_running
    add     x0, x0, :lo12:g_server_running
    str     wzr, [x0]
    ret
.size http_server_stop, .-http_server_stop

// =============================================================================
// http_handle_client - Handle a single client connection
// =============================================================================
// Input:
//   x0 = client fd
// Output:
//   none
// =============================================================================
.type http_handle_client, %function
http_handle_client:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // client fd from parameter

    // Receive request (read: fd, buf, len)
    adrp    x1, recv_buffer
    add     x1, x1, :lo12:recv_buffer
    mov     x0, x19             // fd
    mov     x2, #HTTP_RECV_BUF_SIZE
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #0
    b.le    .Lhhc_ret

    mov     x21, x0             // bytes received

    // Parse request
    adrp    x0, recv_buffer
    add     x0, x0, :lo12:recv_buffer
    mov     x1, x21             // length
    adrp    x2, request_state
    add     x2, x2, :lo12:request_state
    bl      http_parse_request

    cmp     x0, #0
    b.lt    .Lhhc_bad_request

    // Route request
    adrp    x0, request_state
    add     x0, x0, :lo12:request_state
    mov     x1, x19             // client fd
    bl      http_route_request

    b       .Lhhc_ret

.Lhhc_bad_request:
    // Send 400 Bad Request
    adrp    x0, str_error_bad_request
    add     x0, x0, :lo12:str_error_bad_request
    mov     x1, #str_error_bad_request_len
    mov     x2, #400
    mov     x3, x19
    bl      http_send_json_response
    b       .Lhhc_ret

.Lhhc_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size http_handle_client, .-http_handle_client

// =============================================================================
// http_route_request - Route request to appropriate handler
// =============================================================================
// Input:
//   x0 = request state ptr
//   x1 = client fd
// =============================================================================
.type http_route_request, %function
http_route_request:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // request
    mov     x20, x1             // client fd

    // Check for OPTIONS method first (CORS preflight applies to any path)
    ldr     w0, [x19, #HTTP_REQ_OFF_METHOD]
    cmp     w0, #HTTP_METHOD_OPTIONS
    b.eq    .Lrr_options

    // Get path
    ldr     x21, [x19, #HTTP_REQ_OFF_PATH_PTR]
    ldr     w22, [x19, #HTTP_REQ_OFF_PATH_LEN]  // 4-byte field

    // Check /health
    adrp    x0, str_path_health
    add     x0, x0, :lo12:str_path_health
    mov     x1, #str_path_health_len
    mov     x2, x21
    mov     x3, x22
    bl      path_matches
    cbnz    x0, .Lrr_health

    // Check /index
    adrp    x0, str_path_index
    add     x0, x0, :lo12:str_path_index
    mov     x1, #str_path_index_len
    mov     x2, x21
    mov     x3, x22
    bl      path_matches
    cbnz    x0, .Lrr_index

    // Check /search
    adrp    x0, str_path_search
    add     x0, x0, :lo12:str_path_search
    mov     x1, #str_path_search_len
    mov     x2, x21
    mov     x3, x22
    bl      path_starts_with
    cbnz    x0, .Lrr_search

    // Check /peers
    adrp    x0, str_path_peers
    add     x0, x0, :lo12:str_path_peers
    mov     x1, #str_path_peers_len
    mov     x2, x21
    mov     x3, x22
    bl      path_matches
    cbnz    x0, .Lrr_peers

    // Check /status
    adrp    x0, str_path_status
    add     x0, x0, :lo12:str_path_status
    mov     x1, #str_path_status_len
    mov     x2, x21
    mov     x3, x22
    bl      path_matches
    cbnz    x0, .Lrr_status

    // Not found
    b       .Lrr_notfound

.Lrr_options:
    mov     x0, x19
    mov     x1, x20
    bl      handle_options
    b       .Lrr_ret

.Lrr_health:
    mov     x0, x19
    mov     x1, x20
    bl      handle_health
    b       .Lrr_ret

.Lrr_index:
    mov     x0, x19
    mov     x1, x20
    bl      handle_index
    b       .Lrr_ret

.Lrr_search:
    mov     x0, x19
    mov     x1, x20
    bl      handle_search
    b       .Lrr_ret

.Lrr_peers:
    mov     x0, x19
    mov     x1, x20
    bl      handle_peers
    b       .Lrr_ret

.Lrr_status:
    mov     x0, x19
    mov     x1, x20
    bl      handle_status
    b       .Lrr_ret

.Lrr_notfound:
    adrp    x0, str_error_notfound
    add     x0, x0, :lo12:str_error_notfound
    mov     x1, #str_error_notfound_len
    mov     x2, #404
    mov     x3, x20
    bl      http_send_json_response

.Lrr_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size http_route_request, .-http_route_request

// =============================================================================
// handle_health - Handle GET /health
// =============================================================================
.type handle_health, %function
handle_health:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // request
    mov     x20, x1             // client fd

    // Check method is GET
    ldr     w0, [x19, #HTTP_REQ_OFF_METHOD]
    cmp     w0, #HTTP_METHOD_GET
    b.ne    .Lhh_method_error

    // Send health OK response
    adrp    x0, str_health_ok
    add     x0, x0, :lo12:str_health_ok
    mov     x1, #str_health_ok_len
    mov     x2, #200
    mov     x3, x20
    bl      http_send_json_response
    b       .Lhh_ret

.Lhh_method_error:
    adrp    x0, str_error_method
    add     x0, x0, :lo12:str_error_method
    mov     x1, #str_error_method_len
    mov     x2, #405
    mov     x3, x20
    bl      http_send_json_response

.Lhh_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size handle_health, .-handle_health

// =============================================================================
// handle_options - Handle OPTIONS preflight requests
// =============================================================================
// Input:
//   x0 = request state ptr
//   x1 = client fd
// =============================================================================
.type handle_options, %function
handle_options:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x20, x1             // client fd

    // Send 204 No Content with CORS headers (headers added by http_build_response)
    mov     x0, #0              // NULL body
    mov     x1, #0              // body len = 0
    mov     x2, #204            // 204 No Content
    mov     x3, x20             // fd
    bl      http_send_json_response

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size handle_options, .-handle_options

// =============================================================================
// handle_index - Handle POST /index
// =============================================================================
.type handle_index, %function
handle_index:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // request
    mov     x20, x1             // client fd

    // Check method is POST
    ldr     w0, [x19, #HTTP_REQ_OFF_METHOD]
    cmp     w0, #HTTP_METHOD_POST
    b.ne    .Lhi_method_error

    // Parse JSON body
    ldr     x0, [x19, #HTTP_REQ_OFF_BODY_PTR]
    cbz     x0, .Lhi_bad_request
    ldr     x1, [x19, #HTTP_REQ_OFF_BODY_LEN]
    cbz     x1, .Lhi_bad_request

    adrp    x2, json_arena
    add     x2, x2, :lo12:json_arena
    mov     x3, #JSON_ARENA_SIZE
    bl      json_parse

    cbz     x0, .Lhi_bad_request
    mov     x21, x0             // JSON root

    // Get "content" field
    mov     x0, x21
    adrp    x1, str_content_key
    add     x1, x1, :lo12:str_content_key
    mov     x2, #7              // "content" length
    sub     sp, sp, #16
    add     x3, sp, #0          // out ptr
    add     x4, sp, #8          // out len
    bl      json_get_string

    cmp     x0, #0
    b.lt    .Lhi_bad_request_sp

    ldr     x22, [sp, #0]       // content ptr
    ldr     x23, [sp, #8]       // content len
    add     sp, sp, #16

    // Generate doc ID (simple timestamp-based)
    mov     x0, #CLOCK_MONOTONIC
    sub     sp, sp, #16
    mov     x1, sp
    mov     x8, #SYS_clock_gettime
    svc     #0
    ldr     x24, [sp]           // Use seconds as doc ID
    add     sp, sp, #16

    // Index the document and replicate to peers
    mov     x0, x24             // doc_id
    mov     x1, x22             // content
    mov     x2, x23             // content_len
    bl      replica_index_doc

    cmp     x0, #0
    b.lt    .Lhi_internal_error

    // Build success response
    // Use recv_buffer for JSON output since we're done with the request
    // (send_buffer is used by http_send_json_response for the HTTP wrapper)
    adrp    x0, recv_buffer
    add     x0, x0, :lo12:recv_buffer
    mov     x1, #HTTP_RECV_BUF_SIZE
    bl      json_write_init
    mov     x21, x0             // Save writer

    mov     x0, x21
    bl      json_write_object_start

    // Write "status": "indexed"
    // json_write_key expects x0=key, x1=keylen (uses global writer)
    adrp    x0, str_status_key
    add     x0, x0, :lo12:str_status_key
    mov     x1, #6
    bl      json_write_key

    // json_write_string expects x0=str, x1=len (uses global writer)
    adrp    x0, str_indexed_val
    add     x0, x0, :lo12:str_indexed_val
    mov     x1, #7
    bl      json_write_string

    // Write "doc_id": <id>
    adrp    x0, str_docid_key
    add     x0, x0, :lo12:str_docid_key
    mov     x1, #6
    bl      json_write_key

    // json_write_number expects x0=number (uses global writer)
    mov     x0, x24             // doc_id is a plain integer
    bl      json_write_number

    bl      json_write_object_end

    bl      json_write_finish
    mov     x22, x0             // JSON length

    // Send response (body is in recv_buffer)
    adrp    x0, recv_buffer
    add     x0, x0, :lo12:recv_buffer
    mov     x1, x22
    mov     x2, #200
    mov     x3, x20
    bl      http_send_json_response
    b       .Lhi_ret

.Lhi_bad_request_sp:
    add     sp, sp, #16

.Lhi_bad_request:
    adrp    x0, str_error_bad_request
    add     x0, x0, :lo12:str_error_bad_request
    mov     x1, #str_error_bad_request_len
    mov     x2, #400
    mov     x3, x20
    bl      http_send_json_response
    b       .Lhi_ret

.Lhi_method_error:
    adrp    x0, str_error_method
    add     x0, x0, :lo12:str_error_method
    mov     x1, #str_error_method_len
    mov     x2, #405
    mov     x3, x20
    bl      http_send_json_response
    b       .Lhi_ret

.Lhi_internal_error:
    adrp    x0, str_error_internal
    add     x0, x0, :lo12:str_error_internal
    mov     x1, #str_error_internal_len
    mov     x2, #500
    mov     x3, x20
    bl      http_send_json_response

.Lhi_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

str_status_key:
    .asciz "status"
str_indexed_val:
    .asciz "indexed"
str_docid_key:
    .asciz "doc_id"

    .align 2
.size handle_index, .-handle_index

// =============================================================================
// handle_search - Handle GET /search?q=...
// =============================================================================
// Performs distributed search:
// 1. Executes local FTS query
// 2. Broadcasts query to connected mesh peers
// 3. Waits for peer responses (with timeout)
// 4. Returns merged results from local + peers
// =============================================================================
.type handle_search, %function
handle_search:
    stp     x29, x30, [sp, #-112]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    // sp+96: query_str_ptr (8 bytes)
    // sp+104: query_str_len (4 bytes)

    mov     x19, x0             // request
    mov     x20, x1             // client fd

    // Check method is GET
    ldr     w0, [x19, #HTTP_REQ_OFF_METHOD]
    cmp     w0, #HTTP_METHOD_GET
    b.ne    .Lhs_method_error

    // Get query string
    ldr     x21, [x19, #HTTP_REQ_OFF_QUERY_PTR]
    ldr     w22, [x19, #HTTP_REQ_OFF_QUERY_LEN]  // 4-byte field

    // Find q= parameter
    cbz     x21, .Lhs_bad_request
    cbz     x22, .Lhs_bad_request

    // Simple parse: look for "q="
    mov     x0, x21
    mov     x1, x22
    bl      parse_query_param
    cbz     x0, .Lhs_bad_request

    mov     x21, x0             // query string
    mov     x22, x1             // query length
    // Save query string info for later use in distributed search
    str     x21, [sp, #96]      // Save query_str_ptr
    str     w22, [sp, #104]     // Save query_str_len

    // Initialize query context
    mov     x0, #10             // max results
    bl      fts_query_init
    cbz     x0, .Lhs_internal_error
    mov     x23, x0             // x23 = query context

    // Parse query string
    mov     x0, x23             // context
    mov     x1, x21             // query string
    mov     x2, x22             // query length
    bl      fts_query_parse
    cmp     x0, #0
    b.le    .Lhs_free_bad_request   // No terms or error

    // Execute local search
    mov     x0, x23             // context
    bl      fts_query_execute
    mov     x24, x0             // x24 = local result count

    // =========================================================================
    // Distributed Search: Forward query to mesh peers
    // =========================================================================
    // Clear any previous pending search state
    bl      pending_search_clear

    // Start pending search with max peers estimate
    mov     w0, #8              // Max peers we might have
    bl      pending_search_start
    mov     w25, w0             // w25 = query_id

    // Broadcast search to all connected peers
    // mesh_broadcast_search(query_id, flags, max_results, query_str, query_len)
    mov     w0, w25             // query_id
    mov     w1, #0              // flags = 0 (default)
    mov     w2, #10             // max_results = 10
    ldr     x3, [sp, #96]       // query_str
    ldr     w4, [sp, #104]      // query_len
    bl      mesh_broadcast_search
    mov     w26, w0             // w26 = number of peers sent to

    // If no peers to query, skip waiting
    cbz     w26, .Lhs_no_peers

    // Wait for peer results with 500ms timeout
    mov     w0, #500
    bl      mesh_collect_results
    mov     w27, w0             // w27 = peer results count
    b       .Lhs_build_json

.Lhs_no_peers:
    mov     w27, #0             // No peer results

.Lhs_build_json:
    // =========================================================================
    // Build JSON response with local + peer results
    // =========================================================================
    // Use recv_buffer for JSON output
    adrp    x0, recv_buffer
    add     x0, x0, :lo12:recv_buffer
    mov     x1, #HTTP_RECV_BUF_SIZE
    bl      json_write_init
    mov     x21, x0             // x21 = JSON writer

    mov     x0, x21
    bl      json_write_object_start

    // Write "results": [...]
    adrp    x0, str_results_key
    add     x0, x0, :lo12:str_results_key
    mov     x1, #7
    bl      json_write_key

    bl      json_write_array_start

    // Space for doc_id (8) and score (8) on stack
    sub     sp, sp, #16

    // -------------------------------------------------------------------------
    // Output local results
    // -------------------------------------------------------------------------
    mov     x28, #0             // index for local results

.Lhs_local_result_loop:
    cmp     x28, x24            // Compare with local result count
    b.ge    .Lhs_local_done

    // Get result using fts_query_get_result(ctx, index, &doc_id, &score)
    mov     x0, x23             // context
    mov     x1, x28             // index
    mov     x2, sp              // &doc_id
    add     x3, sp, #8          // &score
    bl      fts_query_get_result

    // Write result object
    mov     x0, x21
    bl      json_write_object_start

    ldr     x0, [sp]            // doc_id

    // Write doc_id
    str     x0, [sp]            // Save doc_id back (fts_query_get_result might have changed it)
    adrp    x0, str_docid_key2
    add     x0, x0, :lo12:str_docid_key2
    mov     x1, #6
    bl      json_write_key

    ldr     x0, [sp]            // doc_id
    bl      json_write_number

    // Write score
    adrp    x0, str_score_key
    add     x0, x0, :lo12:str_score_key
    mov     x1, #5
    bl      json_write_key

    ldr     x0, [sp, #8]        // score
    bl      json_write_number

    bl      json_write_object_end

    add     x28, x28, #1
    b       .Lhs_local_result_loop

.Lhs_local_done:
    // -------------------------------------------------------------------------
    // Output peer results (from distributed search)
    // -------------------------------------------------------------------------
    cbz     w27, .Lhs_all_results_done  // Skip if no peer results

    mov     x28, #0             // index for peer results

.Lhs_peer_result_loop:
    cmp     w28, w27            // Compare with peer result count
    b.ge    .Lhs_all_results_done

    // Get peer result using pending_search_get_result(index, &doc_id, &score)
    mov     w0, w28             // index
    mov     x1, sp              // &doc_id
    add     x2, sp, #8          // &score
    bl      pending_search_get_result
    cmp     w0, #0
    b.ne    .Lhs_all_results_done   // Error getting result

    // Write result object
    mov     x0, x21
    bl      json_write_object_start

    // Write doc_id
    adrp    x0, str_docid_key2
    add     x0, x0, :lo12:str_docid_key2
    mov     x1, #6
    bl      json_write_key

    ldr     x0, [sp]            // doc_id
    bl      json_write_number

    // Write score
    adrp    x0, str_score_key
    add     x0, x0, :lo12:str_score_key
    mov     x1, #5
    bl      json_write_key

    ldr     w0, [sp, #8]        // score (32-bit from peer result)
    bl      json_write_number

    bl      json_write_object_end

    add     x28, x28, #1
    b       .Lhs_peer_result_loop

.Lhs_all_results_done:
    add     sp, sp, #16         // Restore stack

    bl      json_write_array_end

    // Write "total": combined count
    adrp    x0, str_total_key
    add     x0, x0, :lo12:str_total_key
    mov     x1, #5
    bl      json_write_key

    // Total = local results + peer results
    add     x0, x24, x27        // x24 = local count, x27 = peer count
    bl      json_write_number

    bl      json_write_object_end

    bl      json_write_finish
    mov     x22, x0             // JSON length

    // Free query context
    mov     x0, x23
    bl      fts_query_free

    // Clear pending search state
    bl      pending_search_clear

    // Send response (body is in recv_buffer)
    adrp    x0, recv_buffer
    add     x0, x0, :lo12:recv_buffer
    mov     x1, x22             // JSON length
    mov     x2, #200
    mov     x3, x20
    bl      http_send_json_response
    b       .Lhs_ret

.Lhs_free_bad_request:
    // Free query context before sending error
    mov     x0, x23
    bl      fts_query_free
    // Fall through to bad_request

.Lhs_bad_request:
    adrp    x0, str_error_bad_request
    add     x0, x0, :lo12:str_error_bad_request
    mov     x1, #str_error_bad_request_len
    mov     x2, #400
    mov     x3, x20
    bl      http_send_json_response
    b       .Lhs_ret

.Lhs_internal_error:
    adrp    x0, str_error_internal
    add     x0, x0, :lo12:str_error_internal
    mov     x1, #str_error_internal_len
    mov     x2, #500
    mov     x3, x20
    bl      http_send_json_response
    b       .Lhs_ret

.Lhs_method_error:
    adrp    x0, str_error_method
    add     x0, x0, :lo12:str_error_method
    mov     x1, #str_error_method_len
    mov     x2, #405
    mov     x3, x20
    bl      http_send_json_response

.Lhs_ret:
    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #112
    ret

str_results_key:
    .asciz "results"
str_docid_key2:
    .asciz "doc_id"
str_score_key:
    .asciz "score"
str_total_key:
    .asciz "total"

    .align 2
.size handle_search, .-handle_search

// =============================================================================
// handle_peers - Handle GET /peers
// =============================================================================
// Returns list of known peers with connection status
// =============================================================================
.type handle_peers, %function
handle_peers:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0             // request
    mov     x20, x1             // client fd

    // Check method is GET
    ldr     w0, [x19, #HTTP_REQ_OFF_METHOD]
    cmp     w0, #HTTP_METHOD_GET
    b.ne    .Lhp_method_error

    // Start JSON response in recv_buffer
    adrp    x0, recv_buffer
    add     x0, x0, :lo12:recv_buffer
    mov     x1, #HTTP_RECV_BUF_SIZE
    bl      json_write_init
    mov     x21, x0             // writer state

    bl      json_write_object_start

    // Write "peers": [
    adrp    x0, str_peers_key
    add     x0, x0, :lo12:str_peers_key
    mov     x1, #5
    bl      json_write_key

    bl      json_write_array_start

    // Get peer count
    bl      peer_list_count
    mov     x24, x0             // peer count
    mov     x25, #0             // current index

.Lhp_peer_loop:
    cmp     x25, x24
    b.ge    .Lhp_peers_done

    // Get peer entry
    mov     x0, x25
    bl      peer_list_get
    cbz     x0, .Lhp_next_peer
    mov     x26, x0             // peer entry ptr

    // Write peer object
    bl      json_write_object_start

    // Write "node_id": <hex>
    adrp    x0, str_node_id_key
    add     x0, x0, :lo12:str_node_id_key
    mov     x1, #7
    bl      json_write_key

    // Convert node_id to hex string
    ldr     x0, [x26, #PEER_OFF_NODE_ID]
    adrp    x1, hex_buf
    add     x1, x1, :lo12:hex_buf
    bl      u64_to_hex
    adrp    x0, hex_buf
    add     x0, x0, :lo12:hex_buf
    mov     x1, #16
    bl      json_write_string

    // Write "host": <string>
    adrp    x0, str_host_key
    add     x0, x0, :lo12:str_host_key
    mov     x1, #4
    bl      json_write_key

    add     x0, x26, #PEER_OFF_HOST
    bl      strlen_simple
    mov     x1, x0
    add     x0, x26, #PEER_OFF_HOST
    bl      json_write_string

    // Write "port": <number>
    adrp    x0, str_port_key
    add     x0, x0, :lo12:str_port_key
    mov     x1, #4
    bl      json_write_key

    ldrh    w0, [x26, #PEER_OFF_PORT]
    bl      json_write_number

    // Write "status": <string>
    adrp    x0, str_peer_status_key
    add     x0, x0, :lo12:str_peer_status_key
    mov     x1, #6
    bl      json_write_key

    ldrb    w0, [x26, #PEER_OFF_STATUS]
    bl      peer_status_to_string
    mov     x2, x0              // string ptr
    mov     x0, x2
    bl      strlen_simple
    mov     x1, x0
    mov     x0, x2
    bl      json_write_string

    // Write "transport": <string>
    adrp    x0, str_transport_key
    add     x0, x0, :lo12:str_transport_key
    mov     x1, #9
    bl      json_write_key

    ldrb    w0, [x26, #PEER_OFF_TRANSPORT]
    bl      transport_type_to_string
    mov     x2, x0
    mov     x0, x2
    bl      strlen_simple
    mov     x1, x0
    mov     x0, x2
    bl      json_write_string

    // Write "last_seen": <number>
    adrp    x0, str_last_seen_key
    add     x0, x0, :lo12:str_last_seen_key
    mov     x1, #9
    bl      json_write_key

    ldr     x0, [x26, #PEER_OFF_LAST_SEEN]
    bl      json_write_number

    bl      json_write_object_end

.Lhp_next_peer:
    add     x25, x25, #1
    b       .Lhp_peer_loop

.Lhp_peers_done:
    bl      json_write_array_end

    // Write "count": <number>
    adrp    x0, str_count_key
    add     x0, x0, :lo12:str_count_key
    mov     x1, #5
    bl      json_write_key

    mov     x0, x24
    bl      json_write_number

    bl      json_write_object_end

    bl      json_write_finish
    mov     x22, x0             // JSON length

    // Send response
    adrp    x0, recv_buffer
    add     x0, x0, :lo12:recv_buffer
    mov     x1, x22
    mov     x2, #200
    mov     x3, x20
    bl      http_send_json_response
    b       .Lhp_ret

.Lhp_method_error:
    adrp    x0, str_error_method
    add     x0, x0, :lo12:str_error_method
    mov     x1, #str_error_method_len
    mov     x2, #405
    mov     x3, x20
    bl      http_send_json_response

.Lhp_ret:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// Helper: peer_status_to_string
peer_status_to_string:
    cmp     w0, #PEER_STATUS_UNKNOWN
    b.eq    .Lpsts_unknown
    cmp     w0, #PEER_STATUS_CONNECTED
    b.eq    .Lpsts_connected
    cmp     w0, #PEER_STATUS_DISCONNECTED
    b.eq    .Lpsts_disconnected
    cmp     w0, #PEER_STATUS_CONNECTING
    b.eq    .Lpsts_connecting
    cmp     w0, #PEER_STATUS_FAILED
    b.eq    .Lpsts_failed
    // Default
    adrp    x0, str_status_unknown
    add     x0, x0, :lo12:str_status_unknown
    ret
.Lpsts_unknown:
    adrp    x0, str_status_unknown
    add     x0, x0, :lo12:str_status_unknown
    ret
.Lpsts_connected:
    adrp    x0, str_status_connected
    add     x0, x0, :lo12:str_status_connected
    ret
.Lpsts_disconnected:
    adrp    x0, str_status_disconnected
    add     x0, x0, :lo12:str_status_disconnected
    ret
.Lpsts_connecting:
    adrp    x0, str_status_connecting
    add     x0, x0, :lo12:str_status_connecting
    ret
.Lpsts_failed:
    adrp    x0, str_status_failed
    add     x0, x0, :lo12:str_status_failed
    ret

// Helper: transport_type_to_string
transport_type_to_string:
    cmp     w0, #TRANSPORT_TCP
    b.eq    .Lttts_tcp
    cmp     w0, #TRANSPORT_UDP
    b.eq    .Lttts_udp
    cmp     w0, #TRANSPORT_SERIAL
    b.eq    .Lttts_serial
    cmp     w0, #TRANSPORT_BLUETOOTH
    b.eq    .Lttts_bluetooth
    cmp     w0, #TRANSPORT_LORA
    b.eq    .Lttts_lora
    cmp     w0, #TRANSPORT_WIFI_MESH
    b.eq    .Lttts_wifi_mesh
    // Default: none/unknown
    adrp    x0, str_trans_none
    add     x0, x0, :lo12:str_trans_none
    ret
.Lttts_tcp:
    adrp    x0, str_trans_tcp
    add     x0, x0, :lo12:str_trans_tcp
    ret
.Lttts_udp:
    adrp    x0, str_trans_udp
    add     x0, x0, :lo12:str_trans_udp
    ret
.Lttts_serial:
    adrp    x0, str_trans_serial
    add     x0, x0, :lo12:str_trans_serial
    ret
.Lttts_bluetooth:
    adrp    x0, str_trans_bluetooth
    add     x0, x0, :lo12:str_trans_bluetooth
    ret
.Lttts_lora:
    adrp    x0, str_trans_lora
    add     x0, x0, :lo12:str_trans_lora
    ret
.Lttts_wifi_mesh:
    adrp    x0, str_trans_wifi_mesh
    add     x0, x0, :lo12:str_trans_wifi_mesh
    ret

// Helper: u64_to_hex - Convert u64 to hex string
// Input: x0 = value, x1 = output buffer (16 bytes)
// Output: 16 hex chars written
u64_to_hex:
    mov     x2, #16             // 16 hex digits
    add     x1, x1, #15         // Start from end
.Lu64hex_loop:
    cbz     x2, .Lu64hex_done
    and     x3, x0, #0xF
    cmp     x3, #10
    b.lt    .Lu64hex_digit
    add     x3, x3, #('a' - 10)
    b       .Lu64hex_store
.Lu64hex_digit:
    add     x3, x3, #'0'
.Lu64hex_store:
    strb    w3, [x1], #-1
    lsr     x0, x0, #4
    sub     x2, x2, #1
    b       .Lu64hex_loop
.Lu64hex_done:
    ret

// Helper: strlen_simple
strlen_simple:
    mov     x1, x0
    mov     x0, #0
.Lstrlen_loop:
    ldrb    w2, [x1, x0]
    cbz     w2, .Lstrlen_done
    add     x0, x0, #1
    b       .Lstrlen_loop
.Lstrlen_done:
    ret

// Strings for handle_peers
str_peers_key:      .asciz "peers"
str_node_id_key:    .asciz "node_id"
str_host_key:       .asciz "host"
str_port_key:       .asciz "port"
str_peer_status_key:.asciz "status"
str_transport_key:  .asciz "transport"
str_last_seen_key:  .asciz "last_seen"
str_count_key:      .asciz "count"

// Status strings
str_status_unknown:     .asciz "unknown"
str_status_connected:   .asciz "connected"
str_status_disconnected:.asciz "disconnected"
str_status_connecting:  .asciz "connecting"
str_status_failed:      .asciz "failed"

// Transport strings
str_trans_none:     .asciz "none"
str_trans_tcp:      .asciz "tcp"
str_trans_udp:      .asciz "udp"
str_trans_serial:   .asciz "serial"
str_trans_bluetooth:.asciz "bluetooth"
str_trans_lora:     .asciz "lora"
str_trans_wifi_mesh:.asciz "wifi-mesh"

// Hex conversion buffer
.section .bss
hex_buf:    .skip 20

.section .text
    .align 2
.size handle_peers, .-handle_peers

// =============================================================================
// handle_status - Handle GET /status
// =============================================================================
// Returns comprehensive node status information
// =============================================================================
.type handle_status, %function
handle_status:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // request
    mov     x20, x1             // client fd

    // Check method is GET
    ldr     w0, [x19, #HTTP_REQ_OFF_METHOD]
    cmp     w0, #HTTP_METHOD_GET
    b.ne    .Lhst_method_error

    // Simple status response
    adrp    x0, str_status_response
    add     x0, x0, :lo12:str_status_response
    mov     x1, #str_status_response_len
    mov     x2, #200
    mov     x3, x20
    bl      http_send_json_response
    b       .Lhst_ret

.Lhst_method_error:
    adrp    x0, str_error_method
    add     x0, x0, :lo12:str_error_method
    mov     x1, #str_error_method_len
    mov     x2, #405
    mov     x3, x20
    bl      http_send_json_response

.Lhst_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

str_status_response:
    .asciz "{\"status\":\"ok\",\"version\":\"0.4.0\"}"
str_status_response_len = . - str_status_response - 1

    .align 2
.size handle_status, .-handle_status

// =============================================================================
// http_send_json_response - Send HTTP response with JSON body
// =============================================================================
// Input:
//   x0 = JSON body
//   x1 = body length
//   x2 = status code
//   x3 = client fd
// =============================================================================
.global http_send_json_response
.type http_send_json_response, %function
http_send_json_response:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // body
    mov     x20, x1             // body len
    mov     x21, x2             // status
    mov     x22, x3             // fd

    // Build response
    // http_build_response(status, body, body_len, ctype_enum, buf, max)
    mov     x0, x21             // status
    mov     x1, x19             // body
    mov     x2, x20             // body len
    mov     x3, #HTTP_CTYPE_JSON // content-type enum (1)
    adrp    x4, send_buffer
    add     x4, x4, :lo12:send_buffer
    mov     x5, #HTTP_SEND_BUF_SIZE
    bl      http_build_response

    cmp     x0, #0
    b.le    .Lsjr_ret

    mov     x2, x0              // response length

    // Send (write: fd, buf, len)
    mov     x0, x22             // fd
    adrp    x1, send_buffer
    add     x1, x1, :lo12:send_buffer
    // x2 already has response length from http_build_response
    mov     x8, #SYS_write
    svc     #0

.Lsjr_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size http_send_json_response, .-http_send_json_response

// =============================================================================
// Helper: path_matches - Check if path exactly matches
// =============================================================================
// Input:
//   x0 = expected path
//   x1 = expected length
//   x2 = actual path
//   x3 = actual length
// Output:
//   x0 = 1 if match, 0 if not
// =============================================================================
.global path_matches
.type path_matches, %function
path_matches:
    cmp     x1, x3
    b.ne    .Lpm_no

    mov     x4, #0
.Lpm_loop:
    cmp     x4, x1
    b.ge    .Lpm_yes

    ldrb    w5, [x0, x4]
    ldrb    w6, [x2, x4]
    cmp     w5, w6
    b.ne    .Lpm_no

    add     x4, x4, #1
    b       .Lpm_loop

.Lpm_yes:
    mov     x0, #1
    ret

.Lpm_no:
    mov     x0, #0
    ret
.size path_matches, .-path_matches

// =============================================================================
// Helper: path_starts_with - Check if path starts with prefix
// =============================================================================
.global path_starts_with
.type path_starts_with, %function
path_starts_with:
    cmp     x3, x1
    b.lt    .Lpsw_no

    mov     x4, #0
.Lpsw_loop:
    cmp     x4, x1
    b.ge    .Lpsw_yes

    ldrb    w5, [x0, x4]
    ldrb    w6, [x2, x4]
    cmp     w5, w6
    b.ne    .Lpsw_no

    add     x4, x4, #1
    b       .Lpsw_loop

.Lpsw_yes:
    mov     x0, #1
    ret

.Lpsw_no:
    mov     x0, #0
    ret
.size path_starts_with, .-path_starts_with

// =============================================================================
// Helper: parse_query_param - Extract 'q' parameter value
// =============================================================================
// Input:
//   x0 = query string (after '?')
//   x1 = query length
// Output:
//   x0 = value ptr, or 0 if not found
//   x1 = value length
// =============================================================================
.global parse_query_param
.type parse_query_param, %function
parse_query_param:
    // Simple parse: look for "q=" at start or after "&"
    mov     x2, #0              // position

.Lpqp_loop:
    cmp     x2, x1
    b.ge    .Lpqp_notfound

    // Check for "q="
    ldrb    w3, [x0, x2]
    cmp     w3, #'q'
    b.ne    .Lpqp_next_param

    add     x4, x2, #1
    cmp     x4, x1
    b.ge    .Lpqp_notfound

    ldrb    w3, [x0, x4]
    cmp     w3, #'='
    b.ne    .Lpqp_skip

    // Found q=, extract value
    add     x4, x4, #1          // Start of value
    mov     x5, x4              // Start position

.Lpqp_value_loop:
    cmp     x4, x1
    b.ge    .Lpqp_found

    ldrb    w3, [x0, x4]
    cmp     w3, #'&'
    b.eq    .Lpqp_found

    add     x4, x4, #1
    b       .Lpqp_value_loop

.Lpqp_found:
    add     x0, x0, x5          // Value ptr
    sub     x1, x4, x5          // Value length
    ret

.Lpqp_skip:
    add     x2, x2, #1
    b       .Lpqp_loop

.Lpqp_next_param:
    // Skip to next '&'
.Lpqp_skip_loop:
    cmp     x2, x1
    b.ge    .Lpqp_notfound

    ldrb    w3, [x0, x2]
    add     x2, x2, #1
    cmp     w3, #'&'
    b.ne    .Lpqp_skip_loop
    b       .Lpqp_loop

.Lpqp_notfound:
    mov     x0, #0
    mov     x1, #0
    ret
.size parse_query_param, .-parse_query_param

// =============================================================================
// End of server.s
// =============================================================================
