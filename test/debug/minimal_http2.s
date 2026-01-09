// Minimal HTTP server - Step 2: Add parsing
.include "syscall_nums.inc"
.include "http.inc"

.equ AF_INET, 2
.equ SOCK_STREAM, 1
.equ SOL_SOCKET, 1
.equ SO_REUSEADDR, 2

.section .data
response:
    .ascii "HTTP/1.1 200 OK\r\n"
    .ascii "Content-Length: 2\r\n"
    .ascii "Connection: close\r\n"
    .ascii "\r\n"
    .ascii "OK"
response_len = . - response

response_bad:
    .ascii "HTTP/1.1 400 Bad\r\n"
    .ascii "Content-Length: 3\r\n"
    .ascii "\r\n"
    .ascii "BAD"
response_bad_len = . - response_bad

.section .bss
.align 4
recv_buf:
    .skip 4096
http_req:
    .skip HTTP_REQ_SIZE

.section .text
.global _start
_start:
    // Create socket
    mov     x0, #AF_INET
    mov     x1, #SOCK_STREAM
    mov     x2, #0
    mov     x8, #SYS_socket
    svc     #0
    mov     x19, x0             // server fd

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

    // Bind to port 9998
    sub     sp, sp, #16
    mov     w0, #AF_INET
    mov     w1, #0x0E27         // 9998 in network byte order
    orr     w0, w0, w1, lsl #16
    str     w0, [sp]
    str     xzr, [sp, #4]
    str     xzr, [sp, #12]
    mov     x0, x19
    mov     x1, sp
    mov     x2, #16
    mov     x8, #SYS_bind
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    exit_error

    // Listen
    mov     x0, x19
    mov     x1, #16
    mov     x8, #SYS_listen
    svc     #0

accept_loop:
    // Accept connection
    sub     sp, sp, #32
    mov     x0, x19
    mov     x1, sp
    add     x2, sp, #16
    mov     w3, #16
    str     w3, [x2]
    mov     x8, #SYS_accept
    svc     #0
    add     sp, sp, #32

    cmp     x0, #0
    b.lt    accept_loop
    mov     x20, x0             // client fd

    // Read request
    mov     x0, x20
    adrp    x1, recv_buf
    add     x1, x1, :lo12:recv_buf
    mov     x2, #4096
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #0
    b.le    close_client
    mov     x21, x0             // bytes read

    // Parse request
    adrp    x0, recv_buf
    add     x0, x0, :lo12:recv_buf
    mov     x1, x21
    adrp    x2, http_req
    add     x2, x2, :lo12:http_req
    bl      http_parse_request

    cmp     x0, #0
    b.lt    send_bad

    // Parse succeeded - send OK
    mov     x0, x20
    adrp    x1, response
    add     x1, x1, :lo12:response
    mov     x2, #response_len
    mov     x8, #SYS_write
    svc     #0
    b       close_client

send_bad:
    // Parse failed - send BAD
    mov     x0, x20
    adrp    x1, response_bad
    add     x1, x1, :lo12:response_bad
    mov     x2, #response_bad_len
    mov     x8, #SYS_write
    svc     #0

close_client:
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0
    b       accept_loop

exit_error:
    mov     x0, #1
    mov     x8, #SYS_exit
    svc     #0
