// =============================================================================
// Omesh - Peer-to-Peer Connection Manager
// =============================================================================
//
// High-level peer management:
// - peer_init: Initialize peer manager
// - peer_connect: Connect to a peer
// - peer_disconnect: Disconnect from peer
// - peer_accept: Accept incoming connection
// - peer_send: Send message to peer
// - peer_broadcast: Send to all peers
// - peer_handle_event: Process epoll event
// - peer_close: Shutdown peer manager
//
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"

// =============================================================================
// Global Data
// =============================================================================

.bss

// Peer manager state
.global g_peer_mgr
.align 4
g_peer_mgr:
    .skip   PEER_MGR_SIZE

// Message buffer for building outgoing messages
.global g_msg_buffer
.align 4
g_msg_buffer:
    .skip   (MSG_HDR_SIZE + 1024)       // Header + 1KB payload

// Receive buffer for incoming data
.global g_recv_buffer
.align 4
g_recv_buffer:
    .skip   NET_RECV_BUF_SIZE

.text

// =============================================================================
// peer_init - Initialize peer manager
// =============================================================================
// Input:
//   x0 = port number (host byte order)
//   x1 = local node ID
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global peer_init
.type peer_init, %function
peer_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save port
    mov     x20, x1                     // Save node ID

    // Initialize reactor
    mov     x0, x19
    mov     x1, x20
    bl      reactor_init
    cmp     x0, #0
    b.lt    .Lpeer_init_ret

    // Initialize peer manager state
    adrp    x1, g_peer_mgr
    add     x1, x1, :lo12:g_peer_mgr
    str     xzr, [x1, #PEER_MGR_OFF_CONNS]
    str     xzr, [x1, #PEER_MGR_OFF_COUNT]
    mov     x0, #NET_MAX_CONNECTIONS
    str     x0, [x1, #PEER_MGR_OFF_CAPACITY]
    adrp    x0, g_reactor
    add     x0, x0, :lo12:g_reactor
    str     x0, [x1, #PEER_MGR_OFF_REACTOR]
    str     x20, [x1, #PEER_MGR_OFF_NODE_ID]
    str     xzr, [x1, #PEER_MGR_OFF_FLAGS]

    mov     x0, #0

.Lpeer_init_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size peer_init, .-peer_init

// =============================================================================
// peer_connect - Connect to a peer
// =============================================================================
// Input:
//   x0 = IPv4 address (network byte order)
//   x1 = port (host byte order)
// Output:
//   x0 = connection pointer or -errno
// =============================================================================
.global peer_connect
.type peer_connect, %function
peer_connect:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save address
    mov     x20, x1                     // Save port

    // Allocate connection
    bl      conn_alloc
    cbz     x0, .Lconnect_full
    mov     x21, x0                     // Save connection ptr

    // Initiate TCP connect
    mov     x0, x19
    mov     x1, x20
    bl      tcp_connect
    cmp     x0, #0
    b.lt    .Lconnect_free_conn
    mov     x22, x0                     // Save fd

    // Store fd in connection
    mov     x0, x21
    mov     x1, x22
    bl      conn_set_tcp_fd

    // Set state to connecting
    mov     x0, x21
    mov     x1, #CONN_STATE_CONNECTING
    bl      conn_set_state

    // Set outbound flag
    mov     x0, x21
    mov     x1, #CONN_FLAG_OUTBOUND
    bl      conn_set_flags

    // Add to epoll - watch for writable (connect complete) and errors
    mov     x0, x22
    mov     x1, #(EPOLLOUT | EPOLLERR | EPOLLHUP)
    mov     x2, x22
    bl      reactor_add
    cmp     x0, #0
    b.lt    .Lconnect_close_socket

    // Return connection pointer
    mov     x0, x21
    b       .Lconnect_ret

.Lconnect_close_socket:
    mov     x19, x0                     // Save error
    mov     x0, x22
    bl      socket_close
    mov     x0, x19
    b       .Lconnect_free_conn

.Lconnect_free_conn:
    mov     x19, x0                     // Save error
    mov     x0, x21
    bl      conn_free
    mov     x0, x19
    b       .Lconnect_ret

.Lconnect_full:
    mov     x0, #-ENOMEM

.Lconnect_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size peer_connect, .-peer_connect

// =============================================================================
// peer_accept - Accept incoming connection
// =============================================================================
// Input:
//   x0 = listening socket fd
// Output:
//   x0 = connection pointer or -errno
// =============================================================================
.global peer_accept
.type peer_accept, %function
peer_accept:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save listen fd

    // Allocate connection
    bl      conn_alloc
    cbz     x0, .Laccept_full
    mov     x20, x0                     // Save connection ptr

    // Accept connection - store address in connection
    mov     x0, x19
    add     x1, x20, #CONN_OFF_ADDR     // Store addr in connection
    bl      tcp_accept
    cmp     x0, #0
    b.lt    .Laccept_free_conn
    mov     x21, x0                     // Save new fd

    // Store fd in connection
    mov     x0, x20
    mov     x1, x21
    bl      conn_set_tcp_fd

    // Set state to connected
    mov     x0, x20
    mov     x1, #CONN_STATE_CONNECTED
    bl      conn_set_state

    // Set inbound flag
    mov     x0, x20
    mov     x1, #CONN_FLAG_INBOUND
    bl      conn_set_flags

    // Set TCP options
    mov     x0, x21
    bl      socket_set_nodelay

    mov     x0, x21
    bl      socket_set_keepalive

    // Add to epoll for reading
    mov     x0, x21
    mov     x1, #(EPOLLIN | EPOLLERR | EPOLLHUP)
    mov     x2, x21
    bl      reactor_add
    cmp     x0, #0
    b.lt    .Laccept_close_socket

    // Update activity timestamp
    mov     x0, x20
    bl      conn_update_activity

    // Return connection pointer
    mov     x0, x20
    b       .Laccept_ret

.Laccept_close_socket:
    mov     x22, x0
    mov     x0, x21
    bl      socket_close
    mov     x0, x22

.Laccept_free_conn:
    mov     x22, x0
    mov     x0, x20
    bl      conn_free
    mov     x0, x22
    b       .Laccept_ret

.Laccept_full:
    mov     x0, #-ENOMEM

.Laccept_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size peer_accept, .-peer_accept

// =============================================================================
// peer_disconnect - Disconnect from peer
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global peer_disconnect
.type peer_disconnect, %function
peer_disconnect:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save connection ptr

    // Get TCP fd
    bl      conn_get_tcp_fd
    mov     x20, x0

    // Remove from epoll
    cmn     x20, #1
    b.eq    .Ldisconnect_free
    mov     x0, x20
    bl      reactor_del

.Ldisconnect_free:
    // Free connection (closes sockets)
    mov     x0, x19
    bl      conn_free

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size peer_disconnect, .-peer_disconnect

// =============================================================================
// peer_send - Send message to peer
// =============================================================================
// Input:
//   x0 = connection pointer
//   x1 = message type
//   x2 = payload pointer (or NULL)
//   x3 = payload length
// Output:
//   x0 = bytes sent or -errno
// =============================================================================
.global peer_send
.type peer_send, %function
peer_send:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // Connection
    mov     x20, x1                     // Type
    mov     x21, x2                     // Payload
    mov     x22, x3                     // Payload length

    // Get local node ID
    bl      reactor_get_node_id
    mov     x23, x0

    // Get remote node ID
    mov     x0, x19
    bl      conn_get_node_id
    mov     x24, x0

    // Build message
    adrp    x0, g_msg_buffer
    add     x0, x0, :lo12:g_msg_buffer
    mov     x1, x20                     // Type
    mov     x2, x23                     // Src node
    mov     x3, x24                     // Dst node
    mov     x4, x21                     // Payload
    mov     x5, x22                     // Payload length
    bl      msg_build
    cmp     x0, #0
    b.lt    .Lsend_ret
    mov     x20, x0                     // Save total size

    // Send message
    mov     x0, x19
    adrp    x1, g_msg_buffer
    add     x1, x1, :lo12:g_msg_buffer
    mov     x2, x20
    bl      conn_send
    cmp     x0, #0
    b.lt    .Lsend_ret

    // Update activity
    mov     x0, x19
    bl      conn_update_activity

    mov     x0, x20                     // Return bytes sent

.Lsend_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size peer_send, .-peer_send

// =============================================================================
// peer_send_hello - Send HELLO message
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = bytes sent or -errno
// =============================================================================
.global peer_send_hello
.type peer_send_hello, %function
peer_send_hello:
    mov     x1, #MSG_TYPE_HELLO
    mov     x2, #0                      // No payload
    mov     x3, #0
    b       peer_send
.size peer_send_hello, .-peer_send_hello

// =============================================================================
// peer_send_ping - Send PING message
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = bytes sent or -errno
// =============================================================================
.global peer_send_ping
.type peer_send_ping, %function
peer_send_ping:
    mov     x1, #MSG_TYPE_PING
    mov     x2, #0
    mov     x3, #0
    b       peer_send
.size peer_send_ping, .-peer_send_ping

// =============================================================================
// peer_send_pong - Send PONG message
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = bytes sent or -errno
// =============================================================================
.global peer_send_pong
.type peer_send_pong, %function
peer_send_pong:
    mov     x1, #MSG_TYPE_PONG
    mov     x2, #0
    mov     x3, #0
    b       peer_send
.size peer_send_pong, .-peer_send_pong

// =============================================================================
// peer_broadcast - Send message to all connected peers
// =============================================================================
// Input:
//   x0 = message type
//   x1 = payload pointer (or NULL)
//   x2 = payload length
// Output:
//   x0 = number of peers sent to
// =============================================================================
.global peer_broadcast
.type peer_broadcast, %function
peer_broadcast:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // Type
    mov     x20, x1                     // Payload
    mov     x21, x2                     // Payload length
    mov     x22, #0                     // Sent count
    adrp    x23, g_conn_pool
    add     x23, x23, :lo12:g_conn_pool
    mov     x24, #0                     // Index

.Lbroadcast_loop:
    cmp     x24, #NET_MAX_CONNECTIONS
    b.hs    .Lbroadcast_done

    // Check if connected
    ldr     w0, [x23, #CONN_OFF_STATE]
    cmp     w0, #CONN_STATE_CONNECTED
    b.ne    .Lbroadcast_next

    // Send to this peer
    mov     x0, x23
    mov     x1, x19
    mov     x2, x20
    mov     x3, x21
    bl      peer_send
    cmp     x0, #0
    b.lt    .Lbroadcast_next

    add     x22, x22, #1

.Lbroadcast_next:
    add     x23, x23, #CONN_SIZE
    add     x24, x24, #1
    b       .Lbroadcast_loop

.Lbroadcast_done:
    mov     x0, x22

    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size peer_broadcast, .-peer_broadcast

// =============================================================================
// peer_handle_connect_complete - Handle connect completion
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global peer_handle_connect_complete
.type peer_handle_connect_complete, %function
peer_handle_connect_complete:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save connection

    // Get TCP fd
    bl      conn_get_tcp_fd
    mov     x20, x0

    // Check for socket error
    bl      socket_get_error
    cbnz    x0, .Lconnect_complete_error

    // Success - update state
    mov     x0, x19
    mov     x1, #CONN_STATE_CONNECTED
    bl      conn_set_state

    // Set TCP options
    mov     x0, x20
    bl      socket_set_nodelay

    mov     x0, x20
    bl      socket_set_keepalive

    // Update epoll to watch for reads
    mov     x0, x20
    mov     x1, #(EPOLLIN | EPOLLERR | EPOLLHUP)
    mov     x2, x20
    bl      reactor_mod

    // Update activity
    mov     x0, x19
    bl      conn_update_activity

    // Send HELLO
    mov     x0, x19
    bl      peer_send_hello

    mov     x0, #0
    b       .Lconnect_complete_ret

.Lconnect_complete_error:
    neg     x0, x0                      // Return -errno

.Lconnect_complete_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size peer_handle_connect_complete, .-peer_handle_connect_complete

// =============================================================================
// peer_handle_readable - Handle readable event
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global peer_handle_readable
.type peer_handle_readable, %function
peer_handle_readable:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save connection

    // Receive data
    adrp    x1, g_recv_buffer
    add     x1, x1, :lo12:g_recv_buffer
    mov     x2, #NET_RECV_BUF_SIZE
    bl      conn_recv
    cmp     x0, #0
    b.lt    .Lreadable_error
    cbz     x0, .Lreadable_closed       // EOF

    mov     x20, x0                     // Save received bytes

    // Update activity
    mov     x0, x19
    bl      conn_update_activity

    // Validate message
    adrp    x0, g_recv_buffer
    add     x0, x0, :lo12:g_recv_buffer
    mov     x1, x20
    bl      msg_validate
    cmp     x0, #0
    b.ne    .Lreadable_invalid

    // Get message type
    adrp    x0, g_recv_buffer
    add     x0, x0, :lo12:g_recv_buffer
    bl      msg_get_type
    mov     x20, x0

    // Handle message based on type
    cmp     x20, #MSG_TYPE_PING
    b.eq    .Lreadable_ping

    cmp     x20, #MSG_TYPE_HELLO
    b.eq    .Lreadable_hello

    // Other message types - just acknowledge
    mov     x0, #0
    b       .Lreadable_ret

.Lreadable_ping:
    // Reply with PONG
    mov     x0, x19
    bl      peer_send_pong
    mov     x0, #0
    b       .Lreadable_ret

.Lreadable_hello:
    // Extract node ID from source
    adrp    x0, g_recv_buffer
    add     x0, x0, :lo12:g_recv_buffer
    bl      msg_get_src_node
    mov     x1, x0
    mov     x0, x19
    bl      conn_set_node_id
    mov     x0, #0
    b       .Lreadable_ret

.Lreadable_closed:
    mov     x0, #-ECONNRESET
    b       .Lreadable_ret

.Lreadable_invalid:
    // Invalid message, but don't disconnect
    mov     x0, #0
    b       .Lreadable_ret

.Lreadable_error:
    // Check if EAGAIN/EWOULDBLOCK
    mov     x1, #-EAGAIN
    cmp     x0, x1
    b.eq    .Lreadable_ok
    mov     x1, #-EWOULDBLOCK
    cmp     x0, x1
    b.eq    .Lreadable_ok
    b       .Lreadable_ret

.Lreadable_ok:
    mov     x0, #0

.Lreadable_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size peer_handle_readable, .-peer_handle_readable

// =============================================================================
// peer_close - Shutdown peer manager
// =============================================================================
// Input: none
// Output:
//   x0 = 0
// =============================================================================
.global peer_close
.type peer_close, %function
peer_close:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    adrp    x19, g_conn_pool
    add     x19, x19, :lo12:g_conn_pool
    mov     x20, #0

.Lpeer_close_loop:
    cmp     x20, #NET_MAX_CONNECTIONS
    b.hs    .Lpeer_close_reactor

    // Check if slot is used
    ldr     w0, [x19, #CONN_OFF_STATE]
    cbz     w0, .Lpeer_close_next

    // Disconnect
    mov     x0, x19
    bl      peer_disconnect

.Lpeer_close_next:
    add     x19, x19, #CONN_SIZE
    add     x20, x20, #1
    b       .Lpeer_close_loop

.Lpeer_close_reactor:
    bl      reactor_close

    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size peer_close, .-peer_close

// =============================================================================
// peer_count - Get number of connected peers
// =============================================================================
// Input: none
// Output:
//   x0 = peer count
// =============================================================================
.global peer_count
.type peer_count, %function
peer_count:
    adrp    x0, g_conn_pool
    add     x0, x0, :lo12:g_conn_pool
    mov     x1, #0                      // Count
    mov     x2, #0                      // Index

.Lpeer_count_loop:
    cmp     x2, #NET_MAX_CONNECTIONS
    b.hs    .Lpeer_count_done

    ldr     w3, [x0, #CONN_OFF_STATE]
    cmp     w3, #CONN_STATE_CONNECTED
    b.ne    .Lpeer_count_next

    add     x1, x1, #1

.Lpeer_count_next:
    add     x0, x0, #CONN_SIZE
    add     x2, x2, #1
    b       .Lpeer_count_loop

.Lpeer_count_done:
    mov     x0, x1
    ret
.size peer_count, .-peer_count

// =============================================================================
// peer_get_node_id - Get local node ID
// =============================================================================
// Input: none
// Output:
//   x0 = node ID
// =============================================================================
.global peer_get_node_id
.type peer_get_node_id, %function
peer_get_node_id:
    adrp    x0, g_peer_mgr
    add     x0, x0, :lo12:g_peer_mgr
    ldr     x0, [x0, #PEER_MGR_OFF_NODE_ID]
    ret
.size peer_get_node_id, .-peer_get_node_id
