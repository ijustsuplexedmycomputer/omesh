// =============================================================================
// TCP Transport Implementation
// =============================================================================
//
// TCP/IP transport backend for the transport abstraction layer.
// Wraps existing socket primitives into the transport_ops interface.
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/transport.inc"

.global tcp_transport_register
.global tcp_transport_ops

// External socket primitives
.extern tcp_listen
.extern tcp_connect
.extern tcp_accept
.extern socket_close
.extern socket_set_nonblock
.extern socket_set_nodelay
.extern socket_set_keepalive
.extern htons
.extern inet_addr

// External peer/connection management
.extern conn_alloc
.extern conn_free
.extern conn_set_tcp_fd
.extern conn_get_tcp_fd
.extern conn_send
.extern conn_recv
.extern conn_get_by_node
.extern conn_count
.extern g_conn_pool

// External reactor
.extern reactor_add
.extern reactor_del

.text

// =============================================================================
// tcp_transport_register - Register TCP transport with manager
// =============================================================================
// Input: none
// Output:
//   x0 = 0 on success
// =============================================================================

tcp_transport_register:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Register with transport manager
    mov     x0, #TRANSPORT_TCP
    adrp    x1, tcp_transport_ops
    add     x1, x1, :lo12:tcp_transport_ops
    bl      transport_register

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// tcp_init - Initialize TCP transport
// =============================================================================
// Input:
//   x0 = pointer to transport_config
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================

tcp_init:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save config pointer

    // Get port from config
    ldr     w20, [x19, #TRANSPORT_CFG_PORT]
    cbz     w20, .Ltcp_init_no_listen

    // Check if LISTEN flag is set
    ldr     w0, [x19, #TRANSPORT_CFG_FLAGS]
    tst     w0, #TRANSPORT_FLAG_LISTEN
    b.eq    .Ltcp_init_no_listen

    // Create listening socket
    mov     w0, w20                     // port
    bl      tcp_listen
    cmp     x0, #0
    b.lt    .Ltcp_init_error

    // Store listen fd
    adrp    x1, tcp_listen_fd
    add     x1, x1, :lo12:tcp_listen_fd
    str     w0, [x1]

    // Make non-blocking
    bl      socket_set_nonblock

.Ltcp_init_no_listen:
    // Store config
    adrp    x0, tcp_config
    add     x0, x0, :lo12:tcp_config
    mov     x1, x19
    mov     x2, #TRANSPORT_CFG_SIZE
    bl      memcpy_simple

    mov     x0, #0
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Ltcp_init_error:
    // x0 already has error code
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret


// =============================================================================
// tcp_shutdown - Shutdown TCP transport
// =============================================================================
// Input: none
// Output: none
// =============================================================================

tcp_shutdown:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Close listen socket if open
    adrp    x0, tcp_listen_fd
    add     x0, x0, :lo12:tcp_listen_fd
    ldr     w0, [x0]
    cmp     w0, #0
    b.le    .Ltcp_shutdown_done

    mov     x8, #SYS_close
    svc     #0

    // Clear fd
    adrp    x0, tcp_listen_fd
    add     x0, x0, :lo12:tcp_listen_fd
    str     wzr, [x0]

.Ltcp_shutdown_done:
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// tcp_send - Send data to a peer via TCP
// =============================================================================
// Input:
//   x0 = peer_id (node_id)
//   x1 = data pointer
//   x2 = data length
// Output:
//   x0 = bytes sent on success, negative errno on failure
// =============================================================================

tcp_send:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // peer_id
    mov     x20, x1                     // data
    mov     x21, x2                     // length

    // Find connection for this peer
    mov     x0, x19
    bl      conn_get_by_node
    cmp     x0, #0
    b.lt    .Ltcp_send_no_peer

    mov     x22, x0                     // connection index

    // Get fd from connection
    bl      conn_get_tcp_fd
    cmp     w0, #0
    b.le    .Ltcp_send_no_peer

    // Send data
    mov     w0, w0                      // fd
    mov     x1, x20                     // data
    mov     x2, x21                     // length
    mov     x8, #SYS_write
    svc     #0

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Ltcp_send_no_peer:
    mov     x0, #TRANSPORT_ERR_NO_PEER
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret


// =============================================================================
// tcp_recv - Receive data via TCP (non-blocking check all connections)
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = buffer length
//   x2 = timeout in milliseconds
// Output:
//   x0 = bytes received on success, negative errno on failure
//   x1 = peer_id of sender
// =============================================================================

tcp_recv:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // buffer
    mov     x20, x1                     // buffer len
    mov     x21, x2                     // timeout

    // For now, use a simple poll over connections
    // TODO: Integrate with epoll for proper multiplexing

    mov     x22, #0                     // connection index

.Ltcp_recv_loop:
    // Check if we've checked all connections
    bl      conn_count
    cmp     x22, x0
    b.ge    .Ltcp_recv_timeout

    // Get fd for this connection
    mov     x0, x22
    bl      conn_get_tcp_fd
    cmp     w0, #0
    b.le    .Ltcp_recv_next

    mov     w23, w0                     // Save fd

    // Try non-blocking read
    mov     w0, w23
    mov     x1, x19
    mov     x2, x20
    mov     x8, #SYS_read
    svc     #0

    // Check result
    cmp     x0, #0
    b.gt    .Ltcp_recv_got_data
    // EAGAIN/EWOULDBLOCK means no data
    cmn     x0, #11                     // -EAGAIN
    b.eq    .Ltcp_recv_next
    cmn     x0, #35                     // -EWOULDBLOCK
    b.eq    .Ltcp_recv_next

    // Other error or connection closed
    b       .Ltcp_recv_next

.Ltcp_recv_got_data:
    mov     x24, x0                     // bytes received

    // Get node_id for this connection
    mov     x0, x22
    bl      conn_get_node_id
    mov     x1, x0                      // peer_id in x1

    mov     x0, x24                     // bytes in x0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Ltcp_recv_next:
    add     x22, x22, #1
    b       .Ltcp_recv_loop

.Ltcp_recv_timeout:
    mov     x0, #TRANSPORT_ERR_TIMEOUT
    mov     x1, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret


// =============================================================================
// tcp_get_peers - Get list of connected TCP peers
// =============================================================================
// Input:
//   x0 = buffer pointer (array of transport_peer structures)
//   x1 = max peers
// Output:
//   x0 = number of peers written
// =============================================================================

tcp_get_peers:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // output buffer
    mov     x20, x1                     // max peers
    mov     x21, #0                     // peers written
    mov     x22, #0                     // connection index

    // Get total connections
    bl      conn_count
    mov     x23, x0                     // total connections

.Ltcp_peers_loop:
    // Check limits
    cmp     x21, x20                    // written >= max?
    b.ge    .Ltcp_peers_done
    cmp     x22, x23                    // index >= total?
    b.ge    .Ltcp_peers_done

    // Check if connection has valid fd
    mov     x0, x22
    bl      conn_get_tcp_fd
    cmp     w0, #0
    b.le    .Ltcp_peers_next

    // Get node_id
    mov     x0, x22
    bl      conn_get_node_id
    mov     x24, x0                     // node_id

    // Calculate output position
    mov     x0, #TPEER_SIZE
    mul     x0, x21, x0
    add     x0, x19, x0                 // peer struct pointer

    // Fill in peer structure
    str     x24, [x0, #TPEER_OFF_ID]    // peer_id

    // Address would require more info, leave as zeros for now
    stp     xzr, xzr, [x0, #TPEER_OFF_ADDR]

    // Quality = 100 for TCP (reliable)
    mov     w1, #100
    str     w1, [x0, #TPEER_OFF_QUALITY]

    // Flags = connected
    mov     w1, #TPEER_FLAG_CONNECTED
    str     w1, [x0, #TPEER_OFF_FLAGS]

    add     x21, x21, #1

.Ltcp_peers_next:
    add     x22, x22, #1
    b       .Ltcp_peers_loop

.Ltcp_peers_done:
    mov     x0, x21
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret


// =============================================================================
// tcp_get_quality - Get link quality to peer (always 100 for TCP)
// =============================================================================
// Input:
//   x0 = peer_id
// Output:
//   x0 = quality score (0-100), or -1 if unknown
// =============================================================================

tcp_get_quality:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Check if peer exists
    bl      conn_get_by_node
    cmp     x0, #0
    b.lt    .Ltcp_quality_unknown

    // TCP is reliable, always return 100
    mov     x0, #100
    ldp     x29, x30, [sp], #16
    ret

.Ltcp_quality_unknown:
    mov     x0, #-1
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// memcpy_simple - Simple memory copy helper
// =============================================================================
// Input:
//   x0 = dest
//   x1 = src
//   x2 = length
// =============================================================================

memcpy_simple:
    cbz     x2, .Lmemcpy_done
.Lmemcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    subs    x2, x2, #1
    b.ne    .Lmemcpy_loop
.Lmemcpy_done:
    ret


// =============================================================================
// Data Section
// =============================================================================

.data

// TCP transport operations vtable
.balign 8
tcp_transport_ops:
    .quad   tcp_init                    // init
    .quad   tcp_shutdown                // shutdown
    .quad   tcp_send                    // send
    .quad   tcp_recv                    // recv
    .quad   tcp_get_peers               // get_peers
    .quad   tcp_get_quality             // get_link_quality

// TCP listen socket fd
tcp_listen_fd:
    .word   0
    .balign 8

// TCP transport config (copy of passed config)
tcp_config:
    .space  TRANSPORT_CFG_SIZE, 0

