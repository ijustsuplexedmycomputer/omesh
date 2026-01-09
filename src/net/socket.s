// =============================================================================
// Omesh - Socket Utilities
// =============================================================================
//
// Low-level socket wrapper functions:
// - tcp_listen: Create and bind a listening TCP socket
// - tcp_connect: Non-blocking TCP connect
// - tcp_accept: Accept incoming connection
// - udp_bind: Create and bind UDP socket
// - socket_set_nonblock: Set non-blocking mode
// - socket_set_nodelay: Disable Nagle's algorithm
// - socket_set_keepalive: Enable TCP keepalive
// - socket_get_error: Get pending socket error
// - socket_close: Close socket
//
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"

.text

// =============================================================================
// tcp_listen - Create a listening TCP socket
// =============================================================================
// Input:
//   x0 = port number (host byte order)
// Output:
//   x0 = socket fd or -errno
// =============================================================================
.global tcp_listen
.type tcp_listen, %function
tcp_listen:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save port

    // Create socket: socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0)
    mov     x0, #AF_INET
    ldr     x1, =(SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC)
    mov     x2, #0
    mov     x8, #SYS_socket
    svc     #0

    cmp     x0, #0
    b.lt    .Ltcp_listen_ret
    mov     x20, x0                     // Save socket fd

    // Set SO_REUSEADDR
    // setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(int))
    mov     w21, #1
    str     w21, [sp, #-16]!            // Store 1 on stack
    mov     x0, x20
    mov     x1, #SOL_SOCKET
    mov     x2, #SO_REUSEADDR
    mov     x3, sp
    mov     x4, #4
    mov     x8, #SYS_setsockopt
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Ltcp_listen_close

    // Build sockaddr_in on stack
    // struct sockaddr_in { sin_family, sin_port, sin_addr, sin_zero }
    sub     sp, sp, #16
    mov     x0, #AF_INET
    strh    w0, [sp, #SOCKADDR_OFF_FAMILY]

    // Convert port to network byte order (big-endian)
    rev16   w0, w19
    strh    w0, [sp, #SOCKADDR_OFF_PORT]

    // Bind to INADDR_ANY (0.0.0.0)
    str     wzr, [sp, #SOCKADDR_OFF_ADDR]
    str     xzr, [sp, #8]               // Zero sin_zero

    // bind(fd, &addr, sizeof(sockaddr_in))
    mov     x0, x20
    mov     x1, sp
    mov     x2, #SOCKADDR_IN_SIZE
    mov     x8, #SYS_bind
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Ltcp_listen_close

    // listen(fd, backlog)
    mov     x0, x20
    mov     x1, #NET_LISTEN_BACKLOG
    mov     x8, #SYS_listen
    svc     #0

    cmp     x0, #0
    b.lt    .Ltcp_listen_close

    mov     x0, x20                     // Return socket fd
    b       .Ltcp_listen_ret

.Ltcp_listen_close:
    mov     x21, x0                     // Save error
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0
    mov     x0, x21                     // Return error

.Ltcp_listen_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size tcp_listen, .-tcp_listen

// =============================================================================
// tcp_connect - Non-blocking TCP connect
// =============================================================================
// Input:
//   x0 = IPv4 address (network byte order)
//   x1 = port number (host byte order)
// Output:
//   x0 = socket fd or -errno (-EINPROGRESS means connect in progress)
// =============================================================================
.global tcp_connect
.type tcp_connect, %function
tcp_connect:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save address
    mov     x20, x1                     // Save port

    // Create socket
    mov     x0, #AF_INET
    ldr     x1, =(SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC)
    mov     x2, #0
    mov     x8, #SYS_socket
    svc     #0

    cmp     x0, #0
    b.lt    .Ltcp_connect_ret
    mov     x21, x0                     // Save socket fd

    // Build sockaddr_in on stack
    sub     sp, sp, #16
    mov     x0, #AF_INET
    strh    w0, [sp, #SOCKADDR_OFF_FAMILY]
    rev16   w0, w20
    strh    w0, [sp, #SOCKADDR_OFF_PORT]
    str     w19, [sp, #SOCKADDR_OFF_ADDR]
    str     xzr, [sp, #8]

    // connect(fd, &addr, sizeof(sockaddr_in))
    mov     x0, x21
    mov     x1, sp
    mov     x2, #SOCKADDR_IN_SIZE
    mov     x8, #SYS_connect
    svc     #0
    add     sp, sp, #16

    // Check result
    cmp     x0, #0
    b.eq    .Ltcp_connect_success       // Connected immediately

    // Check for EINPROGRESS
    mov     x1, #-EINPROGRESS
    cmp     x0, x1
    b.eq    .Ltcp_connect_success       // Connect in progress, return fd

    // Error - close socket
    mov     x22, x0                     // Save error
    mov     x0, x21
    mov     x8, #SYS_close
    svc     #0
    mov     x0, x22
    b       .Ltcp_connect_ret

.Ltcp_connect_success:
    mov     x0, x21                     // Return socket fd

.Ltcp_connect_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size tcp_connect, .-tcp_connect

// =============================================================================
// tcp_accept - Accept incoming TCP connection
// =============================================================================
// Input:
//   x0 = listening socket fd
//   x1 = pointer to store sockaddr_in (or NULL)
// Output:
//   x0 = new socket fd or -errno
// =============================================================================
.global tcp_accept
.type tcp_accept, %function
tcp_accept:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x1                     // Save addr ptr

    // Use accept4 for atomic NONBLOCK | CLOEXEC
    // accept4(fd, addr, addrlen, flags)
    mov     x2, sp
    sub     sp, sp, #16
    mov     x3, #SOCKADDR_IN_SIZE
    str     w3, [x2]                    // addrlen

    cbz     x19, .Ltcp_accept_no_addr
    mov     x1, x19
    b       .Ltcp_accept_call

.Ltcp_accept_no_addr:
    mov     x1, sp                      // Use stack for addr

.Ltcp_accept_call:
    // x0 already has listen fd
    ldr     x3, =(SOCK_NONBLOCK | SOCK_CLOEXEC)
    mov     x8, #SYS_accept4
    svc     #0

    add     sp, sp, #16
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size tcp_accept, .-tcp_accept

// =============================================================================
// udp_bind - Create and bind UDP socket
// =============================================================================
// Input:
//   x0 = port number (host byte order)
// Output:
//   x0 = socket fd or -errno
// =============================================================================
.global udp_bind
.type udp_bind, %function
udp_bind:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save port

    // Create socket
    mov     x0, #AF_INET
    ldr     x1, =(SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC)
    mov     x2, #0
    mov     x8, #SYS_socket
    svc     #0

    cmp     x0, #0
    b.lt    .Ludp_bind_ret
    mov     x20, x0                     // Save socket fd

    // Set SO_REUSEADDR
    mov     w0, #1
    str     w0, [sp, #-16]!
    mov     x0, x20
    mov     x1, #SOL_SOCKET
    mov     x2, #SO_REUSEADDR
    mov     x3, sp
    mov     x4, #4
    mov     x8, #SYS_setsockopt
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Ludp_bind_close

    // Build sockaddr_in
    sub     sp, sp, #16
    mov     x0, #AF_INET
    strh    w0, [sp, #SOCKADDR_OFF_FAMILY]
    rev16   w0, w19
    strh    w0, [sp, #SOCKADDR_OFF_PORT]
    str     wzr, [sp, #SOCKADDR_OFF_ADDR]
    str     xzr, [sp, #8]

    // bind
    mov     x0, x20
    mov     x1, sp
    mov     x2, #SOCKADDR_IN_SIZE
    mov     x8, #SYS_bind
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Ludp_bind_close

    mov     x0, x20
    b       .Ludp_bind_ret

.Ludp_bind_close:
    mov     x19, x0
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0
    mov     x0, x19

.Ludp_bind_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size udp_bind, .-udp_bind

// =============================================================================
// socket_set_nonblock - Set socket to non-blocking mode
// =============================================================================
// Input:
//   x0 = socket fd
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global socket_set_nonblock
.type socket_set_nonblock, %function
socket_set_nonblock:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                     // Save fd

    // Get current flags
    mov     x1, #F_GETFL
    mov     x2, #0
    mov     x8, #SYS_fcntl
    svc     #0

    cmp     x0, #0
    b.lt    .Lnonblock_ret

    // Set O_NONBLOCK
    orr     x2, x0, #O_NONBLOCK
    mov     x0, x19
    mov     x1, #F_SETFL
    mov     x8, #SYS_fcntl
    svc     #0

.Lnonblock_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size socket_set_nonblock, .-socket_set_nonblock

// =============================================================================
// socket_set_nodelay - Disable Nagle's algorithm (TCP_NODELAY)
// =============================================================================
// Input:
//   x0 = socket fd
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global socket_set_nodelay
.type socket_set_nodelay, %function
socket_set_nodelay:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     w1, #1
    str     w1, [sp, #-16]!

    // setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(int))
    mov     x1, #IPPROTO_TCP_LEVEL
    mov     x2, #TCP_NODELAY
    mov     x3, sp
    mov     x4, #4
    mov     x8, #SYS_setsockopt
    svc     #0

    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret
.size socket_set_nodelay, .-socket_set_nodelay

// =============================================================================
// socket_set_keepalive - Enable TCP keepalive
// =============================================================================
// Input:
//   x0 = socket fd
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global socket_set_keepalive
.type socket_set_keepalive, %function
socket_set_keepalive:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                     // Save fd

    mov     w0, #1
    str     w0, [sp, #-16]!

    // SO_KEEPALIVE
    mov     x0, x19
    mov     x1, #SOL_SOCKET
    mov     x2, #SO_KEEPALIVE
    mov     x3, sp
    mov     x4, #4
    mov     x8, #SYS_setsockopt
    svc     #0

    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Lkeepalive_ret

    // TCP_KEEPIDLE = 60 seconds
    mov     w0, #60
    str     w0, [sp, #-16]!
    mov     x0, x19
    mov     x1, #IPPROTO_TCP_LEVEL
    mov     x2, #TCP_KEEPIDLE
    mov     x3, sp
    mov     x4, #4
    mov     x8, #SYS_setsockopt
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Lkeepalive_ret

    // TCP_KEEPINTVL = 10 seconds
    mov     w0, #10
    str     w0, [sp, #-16]!
    mov     x0, x19
    mov     x1, #IPPROTO_TCP_LEVEL
    mov     x2, #TCP_KEEPINTVL
    mov     x3, sp
    mov     x4, #4
    mov     x8, #SYS_setsockopt
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Lkeepalive_ret

    // TCP_KEEPCNT = 3 probes
    mov     w0, #3
    str     w0, [sp, #-16]!
    mov     x0, x19
    mov     x1, #IPPROTO_TCP_LEVEL
    mov     x2, #TCP_KEEPCNT
    mov     x3, sp
    mov     x4, #4
    mov     x8, #SYS_setsockopt
    svc     #0
    add     sp, sp, #16

.Lkeepalive_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size socket_set_keepalive, .-socket_set_keepalive

// =============================================================================
// socket_get_error - Get pending socket error (SO_ERROR)
// =============================================================================
// Input:
//   x0 = socket fd
// Output:
//   x0 = pending error (0 if none) or -errno
// =============================================================================
.global socket_get_error
.type socket_get_error, %function
socket_get_error:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Allocate space for error value and length
    sub     sp, sp, #16
    mov     w1, #4
    str     w1, [sp, #4]                // optlen = 4
    str     wzr, [sp]                   // error = 0

    // getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
    mov     x1, #SOL_SOCKET
    mov     x2, #SO_ERROR
    mov     x3, sp
    add     x4, sp, #4
    mov     x8, #SYS_getsockopt
    svc     #0

    cmp     x0, #0
    b.lt    .Lget_error_ret

    // Return the error value
    ldr     w0, [sp]

.Lget_error_ret:
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret
.size socket_get_error, .-socket_get_error

// =============================================================================
// socket_close - Close socket
// =============================================================================
// Input:
//   x0 = socket fd
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global socket_close
.type socket_close, %function
socket_close:
    mov     x8, #SYS_close
    svc     #0
    ret
.size socket_close, .-socket_close

// =============================================================================
// htons - Convert 16-bit value to network byte order
// =============================================================================
// Input:
//   x0 = host value
// Output:
//   x0 = network value
// =============================================================================
.global htons
.type htons, %function
htons:
    rev16   w0, w0
    and     x0, x0, #0xFFFF
    ret
.size htons, .-htons

// =============================================================================
// htonl - Convert 32-bit value to network byte order
// =============================================================================
// Input:
//   x0 = host value
// Output:
//   x0 = network value
// =============================================================================
.global htonl
.type htonl, %function
htonl:
    rev     w0, w0
    ret
.size htonl, .-htonl

// =============================================================================
// ntohs - Convert 16-bit value from network byte order
// =============================================================================
// Input:
//   x0 = network value
// Output:
//   x0 = host value
// =============================================================================
.global ntohs
.type ntohs, %function
ntohs:
    rev16   w0, w0
    and     x0, x0, #0xFFFF
    ret
.size ntohs, .-ntohs

// =============================================================================
// ntohl - Convert 32-bit value from network byte order
// =============================================================================
// Input:
//   x0 = network value
// Output:
//   x0 = host value
// =============================================================================
.global ntohl
.type ntohl, %function
ntohl:
    rev     w0, w0
    ret
.size ntohl, .-ntohl

// =============================================================================
// inet_addr - Parse dotted-decimal IPv4 address string
// =============================================================================
// Input:
//   x0 = pointer to null-terminated string (e.g., "127.0.0.1")
// Output:
//   x0 = IPv4 address in network byte order, or -1 on error
// =============================================================================
.global inet_addr
.type inet_addr, %function
inet_addr:
    mov     x1, x0                      // String ptr
    mov     w2, #0                      // Result
    mov     w3, #0                      // Current octet value
    mov     w4, #0                      // Octet count

.Linet_loop:
    ldrb    w5, [x1], #1
    cbz     w5, .Linet_end_octet

    cmp     w5, #'.'
    b.eq    .Linet_dot

    // Must be digit
    sub     w5, w5, #'0'
    cmp     w5, #9
    b.hi    .Linet_error

    // octet = octet * 10 + digit
    mov     w6, #10
    mul     w3, w3, w6
    add     w3, w3, w5

    // Check overflow (> 255)
    cmp     w3, #255
    b.hi    .Linet_error

    b       .Linet_loop

.Linet_dot:
    // Store octet and shift result
    lsl     w2, w2, #8
    orr     w2, w2, w3
    mov     w3, #0
    add     w4, w4, #1
    cmp     w4, #4
    b.hs    .Linet_error
    b       .Linet_loop

.Linet_end_octet:
    // Store final octet
    lsl     w2, w2, #8
    orr     w2, w2, w3
    add     w4, w4, #1

    cmp     w4, #4
    b.ne    .Linet_error

    // Convert to network byte order (already in correct order from parsing)
    rev     w0, w2
    ret

.Linet_error:
    mov     x0, #-1
    ret
.size inet_addr, .-inet_addr
