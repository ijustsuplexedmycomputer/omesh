// =============================================================================
// Omesh - Mesh Networking Layer
// =============================================================================
//
// Node-to-node TCP communication for mesh networking.
//
// Functions:
//   mesh_net_init(mesh_port)     - Initialize mesh networking
//   mesh_net_connect_peers()     - Connect to all known peers
//   mesh_net_run()               - Run mesh event loop (blocking)
//   mesh_net_stop()              - Stop mesh event loop
//   mesh_net_close()             - Cleanup mesh networking
//
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"
.include "mesh.inc"
.include "cluster.inc"

// =============================================================================
// Constants
// =============================================================================

.equ MESH_MAX_CONNS,        64          // Max mesh connections
.equ MESH_RECV_BUF_SIZE,    4096        // Receive buffer per connection

// epoll constants
.equ EPOLL_CTL_ADD,         1
.equ EPOLL_CTL_DEL,         2
.equ EPOLL_CTL_MOD,         3
.equ EPOLLIN,               0x001
.equ EPOLLOUT,              0x004
.equ EPOLLERR,              0x008
.equ EPOLLHUP,              0x010
.equ EPOLLRDHUP,            0x2000

// Socket constants
.equ AF_INET,               2
.equ SOCK_STREAM,           1
.equ SOCK_NONBLOCK,         2048
.equ SOCK_CLOEXEC,          524288

// =============================================================================
// Mesh Connection Entry (32 bytes)
// =============================================================================

.equ MCONN_OFF_FD,          0           // [4] Socket fd (-1 if unused)
.equ MCONN_OFF_STATE,       4           // [4] Connection state
.equ MCONN_OFF_PEER_IDX,    8           // [4] Index in peer_list (-1 if unknown)
.equ MCONN_OFF_NODE_ID,     12          // [8] Remote node ID (once known)
.equ MCONN_OFF_FLAGS,       20          // [4] Connection flags
.equ MCONN_OFF_RECV_LEN,    24          // [4] Bytes in receive buffer
.equ MCONN_OFF_RESERVED,    28          // [4] Reserved
.equ MCONN_SIZE,            32

// Connection states
.equ MCONN_STATE_FREE,      0
.equ MCONN_STATE_CONNECTING,1           // TCP connect in progress
.equ MCONN_STATE_WAIT_HELLO,2           // Waiting for HELLO
.equ MCONN_STATE_CONNECTED, 3           // Fully connected
.equ MCONN_STATE_CLOSING,   4

// Connection flags
.equ MCONN_FLAG_OUTBOUND,   0x01        // We initiated
.equ MCONN_FLAG_INBOUND,    0x02        // They initiated

// =============================================================================
// Data Section
// =============================================================================

.section .data

// Mesh state
.align 4
mesh_epoll_fd:      .word   -1          // epoll file descriptor
mesh_listen_fd:     .word   -1          // TCP listener fd
mesh_listen_port:   .word   0           // Mesh listening port
mesh_running:       .word   0           // Running flag
mesh_local_node_id: .quad   0           // Our node ID

// Heartbeat timing (seconds)
.align 8
mesh_last_heartbeat:.quad   0           // Last heartbeat send time
mesh_last_check:    .quad   0           // Last peer timeout check time

// Heartbeat constants (seconds)
.equ HEARTBEAT_INTERVAL,    30          // Send heartbeat every 30 seconds
.equ HEARTBEAT_TIMEOUT,     90          // Peer dead after 90 seconds
.equ RECONNECT_INTERVAL,    10          // Check reconnection every 10 seconds

// Connection table (64 entries * 32 bytes = 2KB)
mesh_conns:         .skip   MESH_MAX_CONNS * MCONN_SIZE

// Receive buffer (shared, one message at a time)
mesh_recv_buf:      .skip   MESH_RECV_BUF_SIZE

// Send buffer for building messages
mesh_send_buf:      .skip   256         // MSG_HDR_SIZE + HELLO_PAYLOAD_SIZE + extra

// epoll events buffer (16 events * 12 bytes)
mesh_events:        .skip   16 * 16     // 16 events * 16 bytes each on aarch64

// =============================================================================
// Read-only strings
// =============================================================================

.section .rodata

mesh_str_init:      .asciz "[mesh] Initializing on port "
mesh_str_newline:   .asciz "\n"
mesh_str_connect:   .asciz "[mesh] Connecting to "
mesh_str_colon:     .asciz ":"
mesh_str_accepted:  .asciz "[mesh] Accepted connection from peer\n"
mesh_str_connected: .asciz "[mesh] Connected to peer, sending HELLO\n"
mesh_str_hello_recv:.asciz "[mesh] Received HELLO from node "
mesh_str_hello_sent:.asciz "[mesh] Sent HELLO to peer\n"
mesh_str_peer_disc: .asciz "[mesh] Peer disconnected\n"
mesh_str_running:   .asciz "[mesh] Event loop running\n"
mesh_str_stopped:   .asciz "[mesh] Event loop stopped\n"
mesh_str_req_peers: .asciz "[mesh] Requesting peer list\n"
mesh_str_send_peers:.asciz "[mesh] Sending peer list ("
mesh_str_peers:     .asciz " peers)\n"
mesh_str_recv_peers:.asciz "[mesh] Received peer list with "
mesh_str_new_peer:  .asciz "[mesh] Discovered new peer: "
mesh_str_conn_new:  .asciz "[mesh] Auto-connecting to discovered peer\n"
mesh_str_add_peer:  .asciz "[mesh] Added inbound peer to list\n"
mesh_str_upd_peer:  .asciz "[mesh] Updated existing peer's node_id\n"
mesh_str_recv_search: .asciz "[mesh] Received search query\n"
mesh_str_recv_results: .asciz "[mesh] Received search results\n"
mesh_str_recv_index: .asciz "[mesh] Received index update\n"
mesh_str_broadcast_search: .asciz "[mesh] Broadcasting search to peers\n"

// =============================================================================
// Code Section
// =============================================================================

.section .text

// =============================================================================
// mesh_print - Print null-terminated string
// =============================================================================
mesh_print:
    mov     x2, x0
    mov     x3, #0
.Lmp_len:
    ldrb    w4, [x2, x3]
    cbz     w4, .Lmp_write
    add     x3, x3, #1
    b       .Lmp_len
.Lmp_write:
    mov     x1, x2
    mov     x2, x3
    mov     x0, #1
    mov     x8, #SYS_write
    svc     #0
    ret

// =============================================================================
// mesh_print_num - Print decimal number
// =============================================================================
mesh_print_num:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    mov     x1, x0
    add     x2, sp, #16
    mov     x3, x2
    add     x3, x3, #12
    strb    wzr, [x3]
    sub     x3, x3, #1

    cbz     x1, .Lmpn_zero

.Lmpn_loop:
    cbz     x1, .Lmpn_print
    mov     x4, #10
    udiv    x5, x1, x4
    msub    x6, x5, x4, x1
    add     w6, w6, #'0'
    strb    w6, [x3]
    sub     x3, x3, #1
    mov     x1, x5
    b       .Lmpn_loop

.Lmpn_zero:
    mov     w0, #'0'
    strb    w0, [x3]
    b       .Lmpn_do_print

.Lmpn_print:
    add     x3, x3, #1

.Lmpn_do_print:
    mov     x0, x3
    bl      mesh_print

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// mesh_print_hex - Print 64-bit hex number
// =============================================================================
mesh_print_hex:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    mov     x1, x0
    add     x2, sp, #16

    // "0x" prefix
    mov     w3, #'0'
    strb    w3, [x2], #1
    mov     w3, #'x'
    strb    w3, [x2], #1

    // 16 hex digits
    mov     x4, #16
.Lmph_loop:
    sub     x4, x4, #1
    lsl     x5, x4, #2          // *4 for bit position
    lsr     x6, x1, x5
    and     x6, x6, #0xF
    cmp     x6, #10
    b.lt    .Lmph_digit
    add     x6, x6, #('a' - 10)
    b       .Lmph_store
.Lmph_digit:
    add     x6, x6, #'0'
.Lmph_store:
    strb    w6, [x2], #1
    cbnz    x4, .Lmph_loop

    strb    wzr, [x2]           // Null terminate

    add     x0, sp, #16
    bl      mesh_print

    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// mesh_net_init - Initialize mesh networking
// =============================================================================
// Input:  x0 = mesh port
// Output: x0 = 0 on success, negative on error
// =============================================================================
.global mesh_net_init
.type mesh_net_init, %function
mesh_net_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0             // Save port

    // Print init message
    adrp    x0, mesh_str_init
    add     x0, x0, :lo12:mesh_str_init
    bl      mesh_print
    mov     x0, x19
    bl      mesh_print_num
    adrp    x0, mesh_str_newline
    add     x0, x0, :lo12:mesh_str_newline
    bl      mesh_print

    // Store port
    adrp    x0, mesh_listen_port
    add     x0, x0, :lo12:mesh_listen_port
    str     w19, [x0]

    // Get our node ID from node module
    bl      node_get_id
    adrp    x1, mesh_local_node_id
    add     x1, x1, :lo12:mesh_local_node_id
    str     x0, [x1]

    // Initialize connection table (set all fds to -1)
    adrp    x0, mesh_conns
    add     x0, x0, :lo12:mesh_conns
    mov     x1, #MESH_MAX_CONNS
    mov     w2, #-1
.Linit_conns:
    str     w2, [x0, #MCONN_OFF_FD]
    str     wzr, [x0, #MCONN_OFF_STATE]
    add     x0, x0, #MCONN_SIZE
    sub     x1, x1, #1
    cbnz    x1, .Linit_conns

    // Create epoll instance
    // epoll_create1(flags) - x0 = flags (0 = none)
    mov     x0, #0              // flags (no EPOLL_CLOEXEC needed)
    mov     x8, #SYS_epoll_create1
    svc     #0
    cmp     x0, #0
    b.lt    .Linit_err

    adrp    x1, mesh_epoll_fd
    add     x1, x1, :lo12:mesh_epoll_fd
    str     w0, [x1]

    // Create TCP listener
    mov     x0, x19             // port
    bl      tcp_listen
    cmp     x0, #0
    b.lt    .Linit_err_epoll

    adrp    x1, mesh_listen_fd
    add     x1, x1, :lo12:mesh_listen_fd
    str     w0, [x1]
    mov     x19, x0             // Save listen fd

    // Add listener to epoll
    adrp    x0, mesh_epoll_fd
    add     x0, x0, :lo12:mesh_epoll_fd
    ldr     w0, [x0]
    mov     x1, #EPOLL_CTL_ADD
    mov     x2, x19             // listen fd

    // Build epoll_event on stack (16 bytes on aarch64: 4 events + 4 pad + 8 data)
    sub     sp, sp, #16
    mov     w3, #EPOLLIN
    str     w3, [sp]            // events at offset 0
    str     x19, [sp, #8]       // data at offset 8 (NOT 4!)
    mov     x3, sp

    mov     x8, #SYS_epoll_ctl
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Linit_err_listen

    mov     x0, #0
    b       .Linit_done

.Linit_err_listen:
    // Close listen fd
    adrp    x0, mesh_listen_fd
    add     x0, x0, :lo12:mesh_listen_fd
    ldr     w0, [x0]
    mov     x8, #SYS_close
    svc     #0

.Linit_err_epoll:
    // Close epoll fd
    adrp    x0, mesh_epoll_fd
    add     x0, x0, :lo12:mesh_epoll_fd
    ldr     w0, [x0]
    mov     x8, #SYS_close
    svc     #0

.Linit_err:
    mov     x0, #-1

.Linit_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size mesh_net_init, .-mesh_net_init

// =============================================================================
// mesh_conn_alloc - Allocate a connection slot
// =============================================================================
// Output: x0 = pointer to slot, or NULL if full
// =============================================================================
mesh_conn_alloc:
    adrp    x0, mesh_conns
    add     x0, x0, :lo12:mesh_conns
    mov     x1, #MESH_MAX_CONNS

.Lalloc_loop:
    ldr     w2, [x0, #MCONN_OFF_STATE]
    cbz     w2, .Lalloc_found   // FREE state
    add     x0, x0, #MCONN_SIZE
    sub     x1, x1, #1
    cbnz    x1, .Lalloc_loop

    mov     x0, #0              // No free slot
    ret

.Lalloc_found:
    ret

// =============================================================================
// mesh_conn_find_by_fd - Find connection by fd
// =============================================================================
// Input:  x0 = fd
// Output: x0 = pointer to slot, or NULL if not found
// =============================================================================
mesh_conn_find_by_fd:
    mov     x3, x0              // Save fd
    adrp    x0, mesh_conns
    add     x0, x0, :lo12:mesh_conns
    mov     x1, #MESH_MAX_CONNS

.Lfind_fd_loop:
    ldr     w2, [x0, #MCONN_OFF_FD]
    cmp     w2, w3
    b.eq    .Lfind_fd_found
    add     x0, x0, #MCONN_SIZE
    sub     x1, x1, #1
    cbnz    x1, .Lfind_fd_loop

    mov     x0, #0
    ret

.Lfind_fd_found:
    ret

// =============================================================================
// mesh_net_connect_peer - Connect to a specific peer
// =============================================================================
// Input:  x0 = peer host string, x1 = port
// Output: x0 = 0 on success (connecting), negative on error
// =============================================================================
.global mesh_net_connect_peer
.type mesh_net_connect_peer, %function
mesh_net_connect_peer:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // host
    mov     x20, x1             // port

    // Print connecting message
    adrp    x0, mesh_str_connect
    add     x0, x0, :lo12:mesh_str_connect
    bl      mesh_print
    mov     x0, x19
    bl      mesh_print
    adrp    x0, mesh_str_colon
    add     x0, x0, :lo12:mesh_str_colon
    bl      mesh_print
    mov     x0, x20
    bl      mesh_print_num
    adrp    x0, mesh_str_newline
    add     x0, x0, :lo12:mesh_str_newline
    bl      mesh_print

    // Allocate connection slot
    bl      mesh_conn_alloc
    cbz     x0, .Lconnect_err_full
    mov     x21, x0             // Save conn ptr

    // Parse host to IP address
    mov     x0, x19
    bl      inet_addr
    cmp     x0, #0
    b.lt    .Lconnect_err
    mov     x22, x0             // Save IP (network order)

    // Initiate TCP connect
    mov     x0, x22             // IP
    mov     x1, x20             // port
    bl      tcp_connect
    cmp     x0, #0
    b.lt    .Lconnect_err       // Error (not EINPROGRESS)

    // Store fd and state
    str     w0, [x21, #MCONN_OFF_FD]
    mov     w1, #MCONN_STATE_CONNECTING
    str     w1, [x21, #MCONN_OFF_STATE]
    mov     w1, #MCONN_FLAG_OUTBOUND
    str     w1, [x21, #MCONN_OFF_FLAGS]
    mov     w1, #-1
    str     w1, [x21, #MCONN_OFF_PEER_IDX]
    str     xzr, [x21, #MCONN_OFF_NODE_ID]

    mov     x19, x0             // Save fd

    // Add to epoll (wait for writable = connect complete)
    adrp    x0, mesh_epoll_fd
    add     x0, x0, :lo12:mesh_epoll_fd
    ldr     w0, [x0]
    mov     x1, #EPOLL_CTL_ADD
    mov     x2, x19             // fd

    sub     sp, sp, #16
    mov     w3, #(EPOLLOUT | EPOLLERR | EPOLLHUP)
    str     w3, [sp]
    str     x19, [sp, #8]       // data at offset 8
    mov     x3, sp

    mov     x8, #SYS_epoll_ctl
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Lconnect_err_close

    mov     x0, #0
    b       .Lconnect_done

.Lconnect_err_close:
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0

.Lconnect_err:
    // Free the slot
    str     wzr, [x21, #MCONN_OFF_STATE]
    mov     w0, #-1
    str     w0, [x21, #MCONN_OFF_FD]

.Lconnect_err_full:
    mov     x0, #-1

.Lconnect_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size mesh_net_connect_peer, .-mesh_net_connect_peer

// =============================================================================
// mesh_net_connect_peers - Connect to all known peers
// =============================================================================
// Output: x0 = number of connections initiated
// =============================================================================
.global mesh_net_connect_peers
.type mesh_net_connect_peers, %function
mesh_net_connect_peers:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, #0             // count
    mov     x20, #0             // index

    // Get peer count
    bl      peer_list_count
    cbz     x0, .Lconnect_peers_done

.Lconnect_peers_loop:
    // Get peer at index
    mov     x0, x20
    bl      peer_list_get
    cbz     x0, .Lconnect_peers_next

    // x0 = peer entry pointer
    // Get host (offset 8, 16 bytes)
    add     x0, x0, #PEER_OFF_HOST

    // Get port (offset 24, 2 bytes)
    mov     x1, x0
    sub     x1, x1, #PEER_OFF_HOST
    add     x1, x1, #PEER_OFF_PORT
    ldrh    w1, [x1]

    // Connect
    bl      mesh_net_connect_peer
    cmp     x0, #0
    b.lt    .Lconnect_peers_next

    add     x19, x19, #1

.Lconnect_peers_next:
    add     x20, x20, #1
    bl      peer_list_count
    cmp     x20, x0
    b.lt    .Lconnect_peers_loop

.Lconnect_peers_done:
    mov     x0, x19
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size mesh_net_connect_peers, .-mesh_net_connect_peers

// =============================================================================
// mesh_send_hello - Send HELLO message
// =============================================================================
// Input:  x0 = fd
// Output: x0 = bytes sent or negative error
// =============================================================================
mesh_send_hello:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0             // Save fd

    // Build HELLO message
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    mov     x1, #MSG_TYPE_HELLO

    // Get local node ID
    adrp    x2, mesh_local_node_id
    add     x2, x2, :lo12:mesh_local_node_id
    ldr     x2, [x2]

    mov     x3, #0              // dst_node (broadcast)
    bl      msg_init

    // Build HELLO payload (24 bytes)
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    add     x0, x0, #MSG_HDR_SIZE   // Payload area

    // node_id [0-7]
    adrp    x1, mesh_local_node_id
    add     x1, x1, :lo12:mesh_local_node_id
    ldr     x1, [x1]
    str     x1, [x0, #HELLO_OFF_NODE_ID]

    // version [8-11]
    mov     w1, #1              // Protocol version 1
    str     w1, [x0, #HELLO_OFF_VERSION]

    // mesh_port [12-13]
    adrp    x1, mesh_listen_port
    add     x1, x1, :lo12:mesh_listen_port
    ldr     w1, [x1]
    strh    w1, [x0, #HELLO_OFF_MESH_PORT]

    // http_port [14-15]
    mov     w1, #8080           // Default HTTP port
    strh    w1, [x0, #HELLO_OFF_HTTP_PORT]

    // flags [16-19]
    str     wzr, [x0, #HELLO_OFF_FLAGS]

    // reserved [20-23]
    str     wzr, [x0, #HELLO_OFF_RESERVED]

    // Set payload length and finalize
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    mov     w1, #HELLO_PAYLOAD_SIZE
    str     w1, [x0, #MSG_OFF_LENGTH]

    bl      msg_finalize

    // Send message
    mov     x0, x19             // fd
    adrp    x1, mesh_send_buf
    add     x1, x1, :lo12:mesh_send_buf
    mov     x2, #(MSG_HDR_SIZE + HELLO_PAYLOAD_SIZE)
    mov     x8, #SYS_write
    svc     #0

    cmp     x0, #0
    b.lt    .Lsend_hello_done

    // Print sent message
    adrp    x0, mesh_str_hello_sent
    add     x0, x0, :lo12:mesh_str_hello_sent
    bl      mesh_print

    mov     x0, #(MSG_HDR_SIZE + HELLO_PAYLOAD_SIZE)

.Lsend_hello_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// mesh_send_peer_list_req - Request peer list from connected node
// =============================================================================
// Input:  x0 = fd
// Output: x0 = bytes sent or negative error
// =============================================================================
mesh_send_peer_list_req:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0             // Save fd

    // Print requesting message
    adrp    x0, mesh_str_req_peers
    add     x0, x0, :lo12:mesh_str_req_peers
    bl      mesh_print

    // Build PEER_LIST_REQ message (no payload)
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    mov     x1, #MSG_TYPE_DISCOVER

    // Get local node ID
    adrp    x2, mesh_local_node_id
    add     x2, x2, :lo12:mesh_local_node_id
    ldr     x2, [x2]

    mov     x3, #0              // dst_node (broadcast)
    bl      msg_init

    // Set payload length to 0 and finalize
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    str     wzr, [x0, #MSG_OFF_LENGTH]
    bl      msg_finalize

    // Send message
    mov     x0, x19             // fd
    adrp    x1, mesh_send_buf
    add     x1, x1, :lo12:mesh_send_buf
    mov     x2, #MSG_HDR_SIZE   // Just header, no payload
    mov     x8, #SYS_write
    svc     #0

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// mesh_send_ping - Send PING message to peer
// =============================================================================
// Input:  x0 = fd
// Output: x0 = bytes sent or negative error
// =============================================================================
mesh_send_ping:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0             // Save fd

    // Build PING message (no payload)
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    mov     x1, #MSG_TYPE_PING

    // Get local node ID
    adrp    x2, mesh_local_node_id
    add     x2, x2, :lo12:mesh_local_node_id
    ldr     x2, [x2]

    mov     x3, #0              // dst_node (broadcast)
    bl      msg_init

    // Set payload length to 0 and finalize
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    str     wzr, [x0, #MSG_OFF_LENGTH]
    bl      msg_finalize

    // Send message
    mov     x0, x19             // fd
    adrp    x1, mesh_send_buf
    add     x1, x1, :lo12:mesh_send_buf
    mov     x2, #MSG_HDR_SIZE   // Just header, no payload
    mov     x8, #SYS_write
    svc     #0

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// mesh_send_pong - Send PONG message in response to PING
// =============================================================================
// Input:  x0 = fd
// Output: x0 = bytes sent or negative error
// =============================================================================
mesh_send_pong:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0             // Save fd

    // Build PONG message (no payload)
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    mov     x1, #MSG_TYPE_PONG

    // Get local node ID
    adrp    x2, mesh_local_node_id
    add     x2, x2, :lo12:mesh_local_node_id
    ldr     x2, [x2]

    mov     x3, #0              // dst_node (broadcast)
    bl      msg_init

    // Set payload length to 0 and finalize
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    str     wzr, [x0, #MSG_OFF_LENGTH]
    bl      msg_finalize

    // Send message
    mov     x0, x19             // fd
    adrp    x1, mesh_send_buf
    add     x1, x1, :lo12:mesh_send_buf
    mov     x2, #MSG_HDR_SIZE   // Just header, no payload
    mov     x8, #SYS_write
    svc     #0

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// mesh_send_peer_list - Send our known peers to connected node
// =============================================================================
// Input:  x0 = fd
// Output: x0 = bytes sent or negative error
// =============================================================================
// Peer list payload format:
//   [4] count - number of peers
//   For each peer:
//     [8] node_id
//     [16] host (null-padded)
//     [2] port
//   Total: 4 + count * 26 bytes
// =============================================================================
.equ PEER_ENTRY_WIRE_SIZE, 26   // 8 + 16 + 2

mesh_send_peer_list:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // Save fd

    // Get peer count
    bl      peer_list_count
    mov     x20, x0             // peer count

    // Print sending message
    adrp    x0, mesh_str_send_peers
    add     x0, x0, :lo12:mesh_str_send_peers
    bl      mesh_print
    mov     x0, x20
    bl      mesh_print_num
    adrp    x0, mesh_str_peers
    add     x0, x0, :lo12:mesh_str_peers
    bl      mesh_print

    // Build PEER_LIST message
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    mov     x1, #MSG_TYPE_PEERS

    adrp    x2, mesh_local_node_id
    add     x2, x2, :lo12:mesh_local_node_id
    ldr     x2, [x2]

    mov     x3, #0              // dst_node
    bl      msg_init

    // Build payload: count + peer entries
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    add     x0, x0, #MSG_HDR_SIZE   // Point to payload area

    // Store count
    str     w20, [x0], #4

    // Iterate peers and add to payload
    mov     x21, #0             // index
    mov     x22, x0             // payload pointer

.Lsend_peers_loop:
    cmp     x21, x20
    b.ge    .Lsend_peers_done

    // Get peer at index
    mov     x0, x21
    bl      peer_list_get
    cbz     x0, .Lsend_peers_next

    // Copy node_id [0-7]
    ldr     x1, [x0, #PEER_OFF_NODE_ID]
    str     x1, [x22], #8

    // Copy host [8-23] (16 bytes)
    add     x1, x0, #PEER_OFF_HOST
    ldr     x2, [x1]
    str     x2, [x22], #8
    ldr     x2, [x1, #8]
    str     x2, [x22], #8

    // Copy port [24-25]
    ldrh    w1, [x0, #PEER_OFF_PORT]
    strh    w1, [x22], #2

.Lsend_peers_next:
    add     x21, x21, #1
    b       .Lsend_peers_loop

.Lsend_peers_done:
    // Calculate payload length: 4 + count * 26
    mov     x0, #PEER_ENTRY_WIRE_SIZE
    mul     x0, x20, x0
    add     x0, x0, #4          // + count field

    // Set payload length
    adrp    x1, mesh_send_buf
    add     x1, x1, :lo12:mesh_send_buf
    str     w0, [x1, #MSG_OFF_LENGTH]
    mov     x20, x0             // Save payload length

    // Finalize message
    mov     x0, x1
    bl      msg_finalize

    // Send message
    mov     x0, x19             // fd
    adrp    x1, mesh_send_buf
    add     x1, x1, :lo12:mesh_send_buf
    add     x2, x20, #MSG_HDR_SIZE  // header + payload
    mov     x8, #SYS_write
    svc     #0

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// mesh_handle_peer_list - Handle received peer list
// =============================================================================
// Input:  x0 = payload pointer, x1 = payload length
// Output: x0 = number of new peers added
// =============================================================================
mesh_handle_peer_list:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // payload ptr
    mov     x20, x1             // payload len
    mov     x23, #0             // new peers added

    // Check minimum length (at least count field)
    cmp     x20, #4
    b.lt    .Lhandle_peers_done

    // Read count
    ldr     w21, [x19], #4      // count, advance pointer

    // Print received message
    adrp    x0, mesh_str_recv_peers
    add     x0, x0, :lo12:mesh_str_recv_peers
    bl      mesh_print
    mov     x0, x21
    bl      mesh_print_num
    adrp    x0, mesh_str_peers
    add     x0, x0, :lo12:mesh_str_peers
    bl      mesh_print

    // Validate count vs payload length
    mov     x0, #PEER_ENTRY_WIRE_SIZE
    mul     x0, x21, x0
    add     x0, x0, #4
    cmp     x0, x20
    b.gt    .Lhandle_peers_done     // Not enough data

    mov     x22, #0             // index

.Lhandle_peers_entry:
    cmp     x22, x21
    b.ge    .Lhandle_peers_done

    // Read peer entry
    ldr     x24, [x19]          // node_id at offset 0

    // Skip our own node (by node_id)
    adrp    x0, mesh_local_node_id
    add     x0, x0, :lo12:mesh_local_node_id
    ldr     x0, [x0]
    cmp     x24, x0
    b.eq    .Lhandle_peers_skip

    // Skip our own node (by port) - prevents connecting to ourselves
    // This handles the case where node_id is unknown (0)
    ldrh    w0, [x19, #24]      // port at offset 24
    adrp    x1, mesh_listen_port
    add     x1, x1, :lo12:mesh_listen_port
    ldr     w1, [x1]
    cmp     w0, w1
    b.eq    .Lhandle_peers_skip

    // Check if we already know this peer by node_id
    mov     x0, x24
    bl      peer_list_find
    cmp     x0, #0
    b.ge    .Lhandle_peers_skip     // Already known by node_id

    // Also check by host:port (handles case where node_id was 0 or different)
    add     x0, x19, #8         // host at offset 8
    ldrh    w1, [x19, #24]      // port at offset 24
    bl      peer_list_find_by_addr
    cmp     x0, #0
    b.ge    .Lhandle_peers_skip     // Already known by host:port

    // New peer! Print discovery message
    adrp    x0, mesh_str_new_peer
    add     x0, x0, :lo12:mesh_str_new_peer
    bl      mesh_print

    // Print host:port
    add     x0, x19, #8         // host at offset 8
    bl      mesh_print
    adrp    x0, mesh_str_colon
    add     x0, x0, :lo12:mesh_str_colon
    bl      mesh_print
    ldrh    w0, [x19, #24]      // port at offset 24
    bl      mesh_print_num
    adrp    x0, mesh_str_newline
    add     x0, x0, :lo12:mesh_str_newline
    bl      mesh_print

    // Add to peer list
    add     x0, x19, #8         // host
    ldrh    w1, [x19, #24]      // port
    mov     x2, x24             // node_id
    bl      peer_list_add
    cmp     x0, #0
    b.lt    .Lhandle_peers_skip

    add     x23, x23, #1        // Increment new peers count

    // Auto-connect to new peer
    adrp    x0, mesh_str_conn_new
    add     x0, x0, :lo12:mesh_str_conn_new
    bl      mesh_print

    add     x0, x19, #8         // host
    ldrh    w1, [x19, #24]      // port
    bl      mesh_net_connect_peer

.Lhandle_peers_skip:
    // Advance to next entry
    add     x19, x19, #PEER_ENTRY_WIRE_SIZE
    add     x22, x22, #1
    b       .Lhandle_peers_entry

.Lhandle_peers_done:
    mov     x0, x23             // Return new peers count
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// =============================================================================
// mesh_handle_connect_complete - Handle connection completion
// =============================================================================
// Input:  x0 = conn ptr
// =============================================================================
mesh_handle_connect_complete:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0             // Save conn ptr

    // Check socket error
    ldr     w0, [x19, #MCONN_OFF_FD]
    bl      socket_get_error
    cbnz    x0, .Lconnect_failed

    // Print connected
    adrp    x0, mesh_str_connected
    add     x0, x0, :lo12:mesh_str_connected
    bl      mesh_print

    // Update state to waiting for HELLO response
    mov     w0, #MCONN_STATE_WAIT_HELLO
    str     w0, [x19, #MCONN_OFF_STATE]

    // Modify epoll to wait for readable
    adrp    x0, mesh_epoll_fd
    add     x0, x0, :lo12:mesh_epoll_fd
    ldr     w0, [x0]
    mov     x1, #EPOLL_CTL_MOD
    ldr     w2, [x19, #MCONN_OFF_FD]

    sub     sp, sp, #16
    mov     w3, #(EPOLLIN | EPOLLERR | EPOLLHUP)
    str     w3, [sp]
    ldr     x4, [x19, #MCONN_OFF_FD]
    str     x4, [sp, #8]        // data at offset 8
    mov     x3, sp

    mov     x8, #SYS_epoll_ctl
    svc     #0
    add     sp, sp, #16

    // Send HELLO
    ldr     w0, [x19, #MCONN_OFF_FD]
    bl      mesh_send_hello

    b       .Lconnect_complete_done

.Lconnect_failed:
    // Close and free connection
    ldr     w0, [x19, #MCONN_OFF_FD]
    mov     x8, #SYS_close
    svc     #0

    mov     w0, #-1
    str     w0, [x19, #MCONN_OFF_FD]
    str     wzr, [x19, #MCONN_OFF_STATE]

.Lconnect_complete_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// mesh_handle_accept - Handle incoming connection
// =============================================================================
mesh_handle_accept:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Accept connection
    adrp    x0, mesh_listen_fd
    add     x0, x0, :lo12:mesh_listen_fd
    ldr     w0, [x0]
    mov     x1, #0              // Don't need addr
    mov     x2, #0
    mov     x8, #SYS_accept4
    // SOCK_NONBLOCK (2048) | SOCK_CLOEXEC (524288) = 526336 = 0x80800
    mov     w3, #0x0800
    movk    w3, #0x8, lsl #16
    svc     #0

    cmp     x0, #0
    b.lt    .Laccept_done

    mov     x19, x0             // Save new fd

    // Print accepted
    adrp    x0, mesh_str_accepted
    add     x0, x0, :lo12:mesh_str_accepted
    bl      mesh_print

    // Allocate connection slot
    bl      mesh_conn_alloc
    cbz     x0, .Laccept_close

    // Store connection info
    str     w19, [x0, #MCONN_OFF_FD]
    mov     w1, #MCONN_STATE_WAIT_HELLO
    str     w1, [x0, #MCONN_OFF_STATE]
    mov     w1, #MCONN_FLAG_INBOUND
    str     w1, [x0, #MCONN_OFF_FLAGS]
    mov     w1, #-1
    str     w1, [x0, #MCONN_OFF_PEER_IDX]
    str     xzr, [x0, #MCONN_OFF_NODE_ID]

    // Add to epoll
    adrp    x0, mesh_epoll_fd
    add     x0, x0, :lo12:mesh_epoll_fd
    ldr     w0, [x0]
    mov     x1, #EPOLL_CTL_ADD
    mov     x2, x19

    sub     sp, sp, #16
    mov     w3, #(EPOLLIN | EPOLLERR | EPOLLHUP)
    str     w3, [sp]
    str     x19, [sp, #8]       // data at offset 8
    mov     x3, sp

    mov     x8, #SYS_epoll_ctl
    svc     #0
    add     sp, sp, #16

    b       .Laccept_done

.Laccept_close:
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0

.Laccept_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// mesh_handle_data - Handle incoming data
// =============================================================================
// Input:  x0 = conn ptr
// =============================================================================
mesh_handle_data:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    mov     x19, x0             // conn ptr

    // Read data
    ldr     w0, [x19, #MCONN_OFF_FD]
    adrp    x1, mesh_recv_buf
    add     x1, x1, :lo12:mesh_recv_buf
    mov     x2, #MESH_RECV_BUF_SIZE
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #0
    b.le    .Ldata_disconnect   // EOF or error

    mov     x20, x0             // bytes received

    // Validate message
    adrp    x0, mesh_recv_buf
    add     x0, x0, :lo12:mesh_recv_buf
    mov     x1, x20
    bl      msg_validate
    cmp     x0, #0
    b.lt    .Ldata_done         // Invalid message

    // Get message type
    adrp    x0, mesh_recv_buf
    add     x0, x0, :lo12:mesh_recv_buf
    ldrb    w21, [x0, #MSG_OFF_TYPE]

    // Handle by type
    cmp     w21, #MSG_TYPE_PING
    b.eq    .Ldata_ping

    cmp     w21, #MSG_TYPE_PONG
    b.eq    .Ldata_pong

    cmp     w21, #MSG_TYPE_HELLO
    b.eq    .Ldata_hello

    cmp     w21, #MSG_TYPE_DISCOVER
    b.eq    .Ldata_peer_req

    cmp     w21, #MSG_TYPE_PEERS
    b.eq    .Ldata_peer_list

    cmp     w21, #MSG_TYPE_SEARCH
    b.eq    .Ldata_search

    cmp     w21, #MSG_TYPE_RESULTS
    b.eq    .Ldata_results

    cmp     w21, #MSG_TYPE_INDEX
    b.eq    .Ldata_index

    // Other message types - just ignore for now
    b       .Ldata_done

.Ldata_ping:
    // Received PING - respond with PONG
    ldr     w0, [x19, #MCONN_OFF_FD]
    bl      mesh_send_pong

    // Update last seen for this connection's peer
    ldr     x0, [x19, #MCONN_OFF_NODE_ID]
    cbz     x0, .Ldata_done
    bl      peer_list_find
    cmp     x0, #0
    b.lt    .Ldata_done
    bl      peer_list_update_last_seen
    b       .Ldata_done

.Ldata_pong:
    // Received PONG - update last seen timestamp
    ldr     x0, [x19, #MCONN_OFF_NODE_ID]
    cbz     x0, .Ldata_done
    bl      peer_list_find
    cmp     x0, #0
    b.lt    .Ldata_done
    bl      peer_list_update_last_seen
    b       .Ldata_done

.Ldata_hello:
    // Get remote node_id from payload
    adrp    x0, mesh_recv_buf
    add     x0, x0, :lo12:mesh_recv_buf
    add     x0, x0, #MSG_HDR_SIZE
    ldr     x20, [x0, #HELLO_OFF_NODE_ID]

    // Store in connection
    str     x20, [x19, #MCONN_OFF_NODE_ID]

    // Update state to connected
    mov     w0, #MCONN_STATE_CONNECTED
    str     w0, [x19, #MCONN_OFF_STATE]

    // Print received HELLO
    adrp    x0, mesh_str_hello_recv
    add     x0, x0, :lo12:mesh_str_hello_recv
    bl      mesh_print
    mov     x0, x20
    bl      mesh_print_hex
    adrp    x0, mesh_str_newline
    add     x0, x0, :lo12:mesh_str_newline
    bl      mesh_print

    // If we're inbound, send HELLO back
    ldr     w0, [x19, #MCONN_OFF_FLAGS]
    tst     w0, #MCONN_FLAG_INBOUND
    b.eq    .Ldata_hello_update_peer

    ldr     w0, [x19, #MCONN_OFF_FD]
    bl      mesh_send_hello

.Ldata_hello_update_peer:
    // Try to find peer in peer_list
    mov     x0, x20             // node_id
    bl      peer_list_find
    cmp     x0, #0
    b.lt    .Ldata_hello_add_peer

    // Update peer status to connected
    mov     x1, #PEER_STATUS_CONNECTED
    bl      peer_list_update_status
    b       .Ldata_hello_req_peers

.Ldata_hello_add_peer:
    // Peer not found by node_id - either:
    // 1. Existing peer with node_id=0 (outbound connection before HELLO)
    // 2. Truly new peer (inbound connection)
    // Need to get peer's IP address via getpeername and check by host:port

    // Stack layout (48 bytes):
    //   sp+0  to sp+15: sockaddr_in (16 bytes)
    //   sp+16 to sp+19: addrlen (4 bytes)
    //   sp+20 to sp+21: mesh_port from HELLO
    //   sp+22 to sp+23: padding
    //   sp+24 to sp+47: IP string buffer (24 bytes, max needed is 16)
    sub     sp, sp, #48

    // Initialize addrlen = 16
    mov     w0, #16
    str     w0, [sp, #16]

    // Call getpeername(fd, addr, &addrlen)
    ldr     w0, [x19, #MCONN_OFF_FD]
    mov     x1, sp              // sockaddr_in
    add     x2, sp, #16         // addrlen ptr
    mov     x8, #SYS_getpeername
    svc     #0
    cmp     x0, #0
    b.lt    .Ldata_hello_add_done

    // Extract IP address from sockaddr_in (bytes 4-7)
    // Convert to dotted-decimal string in a temp buffer
    add     x0, sp, #24         // IP string buffer
    ldr     w1, [sp, #4]        // sin_addr (network byte order)

    // Convert IPv4 to string: x.x.x.x
    // Byte 0 (least significant in mem, first in IP)
    and     w2, w1, #0xff
    bl      mesh_itoa_byte
    mov     w3, #'.'
    strb    w3, [x0], #1

    lsr     w1, w1, #8
    and     w2, w1, #0xff
    bl      mesh_itoa_byte
    mov     w3, #'.'
    strb    w3, [x0], #1

    lsr     w1, w1, #8
    and     w2, w1, #0xff
    bl      mesh_itoa_byte
    mov     w3, #'.'
    strb    w3, [x0], #1

    lsr     w1, w1, #8
    and     w2, w1, #0xff
    bl      mesh_itoa_byte
    strb    wzr, [x0]           // null terminate

    // Get mesh_port from HELLO payload and save it
    adrp    x0, mesh_recv_buf
    add     x0, x0, :lo12:mesh_recv_buf
    add     x0, x0, #MSG_HDR_SIZE
    ldrh    w0, [x0, #HELLO_OFF_MESH_PORT]
    strh    w0, [sp, #20]       // Save mesh_port

    // Try to find peer by host:port
    add     x0, sp, #24         // host string
    ldrh    w1, [sp, #20]       // mesh_port
    bl      peer_list_find_by_addr
    cmp     x0, #0
    b.lt    .Ldata_hello_truly_new

    // Found existing peer - update its node_id
    mov     x1, x20             // node_id from HELLO
    bl      peer_list_update_node_id

    // Update status to connected
    add     x0, sp, #24         // host
    ldrh    w1, [sp, #20]       // port
    bl      peer_list_find_by_addr
    mov     x1, #PEER_STATUS_CONNECTED
    bl      peer_list_update_status

    // Print that we updated a peer
    adrp    x0, mesh_str_upd_peer
    add     x0, x0, :lo12:mesh_str_upd_peer
    bl      mesh_print
    b       .Ldata_hello_add_done

.Ldata_hello_truly_new:
    // Truly new peer - add to peer list
    add     x0, sp, #24         // host string
    ldrh    w1, [sp, #20]       // mesh_port
    mov     x2, x20             // node_id
    bl      peer_list_add

    // Print that we added a peer
    adrp    x0, mesh_str_add_peer
    add     x0, x0, :lo12:mesh_str_add_peer
    bl      mesh_print

.Ldata_hello_add_done:
    add     sp, sp, #48

.Ldata_hello_req_peers:
    // Request peer list from newly connected node
    ldr     w0, [x19, #MCONN_OFF_FD]
    bl      mesh_send_peer_list_req

    b       .Ldata_done

.Ldata_peer_req:
    // Received peer list request - send our peers
    ldr     w0, [x19, #MCONN_OFF_FD]
    bl      mesh_send_peer_list
    b       .Ldata_done

.Ldata_peer_list:
    // Received peer list - process it
    adrp    x0, mesh_recv_buf
    add     x0, x0, :lo12:mesh_recv_buf
    ldr     w1, [x0, #MSG_OFF_LENGTH]   // payload length
    add     x0, x0, #MSG_HDR_SIZE       // payload pointer
    bl      mesh_handle_peer_list
    b       .Ldata_done

.Ldata_search:
    // Received search query - execute local search and return results
    adrp    x0, mesh_str_recv_search
    add     x0, x0, :lo12:mesh_str_recv_search
    bl      mesh_print

    // Call handle_search(fd, msg_buf)
    ldr     w0, [x19, #MCONN_OFF_FD]
    adrp    x1, mesh_recv_buf
    add     x1, x1, :lo12:mesh_recv_buf
    bl      handle_search
    b       .Ldata_done

.Ldata_results:
    // Received search results - forward to router for aggregation
    adrp    x0, mesh_str_recv_results
    add     x0, x0, :lo12:mesh_str_recv_results
    bl      mesh_print

    // Call handle_results(fd, msg_buf)
    ldr     w0, [x19, #MCONN_OFF_FD]
    adrp    x1, mesh_recv_buf
    add     x1, x1, :lo12:mesh_recv_buf
    bl      handle_results
    b       .Ldata_done

.Ldata_index:
    // Received index update - replicate document locally
    adrp    x0, mesh_str_recv_index
    add     x0, x0, :lo12:mesh_str_recv_index
    bl      mesh_print

    // Call handle_index(fd, msg_buf)
    ldr     w0, [x19, #MCONN_OFF_FD]
    adrp    x1, mesh_recv_buf
    add     x1, x1, :lo12:mesh_recv_buf
    bl      handle_index
    b       .Ldata_done

.Ldata_disconnect:
    // Print disconnect message
    adrp    x0, mesh_str_peer_disc
    add     x0, x0, :lo12:mesh_str_peer_disc
    bl      mesh_print

    // Update peer status if known
    ldr     x0, [x19, #MCONN_OFF_NODE_ID]
    cbz     x0, .Ldata_close

    bl      peer_list_find
    cmp     x0, #0
    b.lt    .Ldata_close

    mov     x1, #PEER_STATUS_DISCONNECTED
    bl      peer_list_update_status

.Ldata_close:
    // Remove from epoll
    adrp    x0, mesh_epoll_fd
    add     x0, x0, :lo12:mesh_epoll_fd
    ldr     w0, [x0]
    mov     x1, #EPOLL_CTL_DEL
    ldr     w2, [x19, #MCONN_OFF_FD]
    mov     x3, #0
    mov     x8, #SYS_epoll_ctl
    svc     #0

    // Close socket
    ldr     w0, [x19, #MCONN_OFF_FD]
    mov     x8, #SYS_close
    svc     #0

    // Free slot
    mov     w0, #-1
    str     w0, [x19, #MCONN_OFF_FD]
    str     wzr, [x19, #MCONN_OFF_STATE]

.Ldata_done:
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// mesh_periodic_tasks - Perform periodic maintenance tasks
// =============================================================================
// Called every epoll timeout (1 second) to:
// 1. Send heartbeats to connected peers (every HEARTBEAT_INTERVAL seconds)
// 2. Check for timed-out peers (every RECONNECT_INTERVAL seconds)
// 3. Attempt reconnection to disconnected peers
// =============================================================================
mesh_periodic_tasks:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    // Get current time (seconds since epoch)
    sub     sp, sp, #16
    mov     x0, #0              // CLOCK_REALTIME
    mov     x1, sp
    mov     x8, #SYS_clock_gettime
    svc     #0
    ldr     x19, [sp]           // x19 = current time (seconds)
    add     sp, sp, #16

    // Check if it's time to send heartbeats
    adrp    x0, mesh_last_heartbeat
    add     x0, x0, :lo12:mesh_last_heartbeat
    ldr     x20, [x0]           // Last heartbeat time

    sub     x1, x19, x20        // Time since last heartbeat
    cmp     x1, #HEARTBEAT_INTERVAL
    b.lt    .Lperiodic_check_timeouts

    // Time to send heartbeats
    str     x19, [x0]           // Update last heartbeat time
    bl      mesh_send_heartbeats

.Lperiodic_check_timeouts:
    // Check if it's time to check peer timeouts
    adrp    x0, mesh_last_check
    add     x0, x0, :lo12:mesh_last_check
    ldr     x20, [x0]           // Last check time

    sub     x1, x19, x20        // Time since last check
    cmp     x1, #RECONNECT_INTERVAL
    b.lt    .Lperiodic_done

    // Time to check timeouts and attempt reconnection
    str     x19, [x0]           // Update last check time
    mov     x0, x19             // Pass current time
    bl      mesh_check_peer_timeouts
    bl      mesh_attempt_reconnection

.Lperiodic_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// =============================================================================
// mesh_send_heartbeats - Send PING to all connected peers
// =============================================================================
mesh_send_heartbeats:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Iterate through all connections
    adrp    x19, mesh_conns
    add     x19, x19, :lo12:mesh_conns
    mov     x20, #0             // Connection index

.Lheartbeat_loop:
    cmp     x20, #MESH_MAX_CONNS
    b.ge    .Lheartbeat_done

    // Check if slot has valid connected connection
    ldr     w0, [x19, #MCONN_OFF_FD]
    cmp     w0, #0
    b.lt    .Lheartbeat_next

    ldr     w1, [x19, #MCONN_OFF_STATE]
    cmp     w1, #MCONN_STATE_CONNECTED
    b.ne    .Lheartbeat_next

    // Send PING to this peer - reload fd in case cmp clobbered flags
    ldr     w0, [x19, #MCONN_OFF_FD]
    bl      mesh_send_ping

.Lheartbeat_next:
    add     x19, x19, #MCONN_SIZE
    add     x20, x20, #1
    b       .Lheartbeat_loop

.Lheartbeat_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// mesh_check_peer_timeouts - Check and mark timed-out peers
// =============================================================================
// Input: x0 = current time (seconds)
// =============================================================================
mesh_check_peer_timeouts:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // Current time
    mov     x20, #0             // Peer index

    // Get peer count
    bl      peer_list_count
    mov     x21, x0             // Total peers

.Ltimeout_loop:
    cmp     x20, x21
    b.ge    .Ltimeout_done

    // Get peer entry
    mov     x0, x20
    bl      peer_list_get
    cbz     x0, .Ltimeout_next
    mov     x22, x0             // Peer entry pointer

    // Check peer status - only check CONNECTED peers
    ldrb    w0, [x22, #PEER_OFF_STATUS]
    cmp     w0, #PEER_STATUS_CONNECTED
    b.ne    .Ltimeout_next

    // Check last_seen timestamp
    ldr     x0, [x22, #PEER_OFF_LAST_SEEN]
    cbz     x0, .Ltimeout_next  // Never seen, skip

    sub     x0, x19, x0         // Time since last seen
    cmp     x0, #HEARTBEAT_TIMEOUT
    b.lt    .Ltimeout_next

    // Peer has timed out - mark as DISCONNECTED
    mov     x0, x20             // Peer index
    mov     x1, #PEER_STATUS_DISCONNECTED
    bl      peer_list_update_status

    // Close the connection if we have one
    ldr     w0, [x22, #PEER_OFF_CONN_FD]
    cmp     w0, #0
    b.lt    .Ltimeout_next
    mov     x8, #SYS_close
    svc     #0

    // Clear the conn_fd
    mov     w0, #-1
    str     w0, [x22, #PEER_OFF_CONN_FD]

.Ltimeout_next:
    add     x20, x20, #1
    b       .Ltimeout_loop

.Ltimeout_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// mesh_attempt_reconnection - Try to reconnect to disconnected peers
// =============================================================================
mesh_attempt_reconnection:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, #0             // Peer index

    // Get peer count
    bl      peer_list_count
    mov     x20, x0             // Total peers

.Lreconn_loop:
    cmp     x19, x20
    b.ge    .Lreconn_done

    // Get peer entry
    mov     x0, x19
    bl      peer_list_get
    cbz     x0, .Lreconn_next
    mov     x21, x0             // Peer entry pointer

    // Check peer status - only reconnect to DISCONNECTED peers
    ldrb    w0, [x21, #PEER_OFF_STATUS]
    cmp     w0, #PEER_STATUS_DISCONNECTED
    b.ne    .Lreconn_next

    // Check if it's a persistent peer (seed peer or explicit --peer)
    ldrb    w0, [x21, #PEER_OFF_FLAGS]
    tst     w0, #PEER_FLAG_PERSISTENT
    b.eq    .Lreconn_next       // Skip non-persistent peers

    // Mark as CONNECTING
    mov     x0, x19
    mov     x1, #PEER_STATUS_CONNECTING
    bl      peer_list_update_status

    // Attempt to reconnect
    add     x0, x21, #PEER_OFF_HOST
    ldrh    w1, [x21, #PEER_OFF_PORT]
    bl      mesh_net_connect_peer

.Lreconn_next:
    add     x19, x19, #1
    b       .Lreconn_loop

.Lreconn_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// mesh_net_run - Run mesh event loop
// =============================================================================
// Output: x0 = 0 on clean exit
// =============================================================================
.global mesh_net_run
.type mesh_net_run, %function
mesh_net_run:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    // Set running flag
    adrp    x0, mesh_running
    add     x0, x0, :lo12:mesh_running
    mov     w1, #1
    str     w1, [x0]

    // Print running
    adrp    x0, mesh_str_running
    add     x0, x0, :lo12:mesh_str_running
    bl      mesh_print

.Lrun_loop:
    // Check running flag
    adrp    x0, mesh_running
    add     x0, x0, :lo12:mesh_running
    ldr     w0, [x0]
    cbz     w0, .Lrun_stop

    // epoll_wait
    adrp    x0, mesh_epoll_fd
    add     x0, x0, :lo12:mesh_epoll_fd
    ldr     w0, [x0]
    adrp    x1, mesh_events
    add     x1, x1, :lo12:mesh_events
    mov     x2, #16             // maxevents
    mov     x3, #1000           // timeout 1s
    mov     x8, #SYS_epoll_pwait
    mov     x4, #0              // sigmask
    svc     #0

    cmp     x0, #0
    b.lt    .Lrun_periodic      // Error or interrupted, do periodic tasks
    cbz     x0, .Lrun_periodic  // Timeout, do periodic tasks

    mov     x19, x0             // event count
    mov     x20, #0             // event index

.Lrun_event_loop:
    cmp     x20, x19
    b.ge    .Lrun_periodic      // After all events, do periodic tasks

    // Get event (epoll_event is 16 bytes on aarch64: 4 events + 4 pad + 8 data)
    adrp    x0, mesh_events
    add     x0, x0, :lo12:mesh_events
    mov     x1, #16             // event size on aarch64
    mul     x1, x20, x1
    add     x0, x0, x1

    ldr     w21, [x0]           // events at offset 0
    ldr     x22, [x0, #8]       // data (fd) at offset 8

    // Check if it's the listen socket
    adrp    x0, mesh_listen_fd
    add     x0, x0, :lo12:mesh_listen_fd
    ldr     w0, [x0]
    cmp     w22, w0
    b.eq    .Lrun_accept

    // Find connection by fd
    mov     x0, x22
    bl      mesh_conn_find_by_fd
    cbz     x0, .Lrun_next_event

    mov     x23, x0             // conn ptr (using another reg temporarily)

    // Check for error/hangup
    tst     w21, #(EPOLLERR | EPOLLHUP)
    b.ne    .Lrun_disconnect

    // Check connection state
    ldr     w0, [x23, #MCONN_OFF_STATE]
    cmp     w0, #MCONN_STATE_CONNECTING
    b.eq    .Lrun_connect_complete

    // Check for readable
    tst     w21, #EPOLLIN
    b.eq    .Lrun_next_event

    mov     x0, x23
    bl      mesh_handle_data
    b       .Lrun_next_event

.Lrun_accept:
    bl      mesh_handle_accept
    b       .Lrun_next_event

.Lrun_connect_complete:
    mov     x0, x23
    bl      mesh_handle_connect_complete
    b       .Lrun_next_event

.Lrun_disconnect:
    // Handle disconnect same as data (will detect EOF)
    mov     x0, x23
    bl      mesh_handle_data
    b       .Lrun_next_event

.Lrun_next_event:
    add     x20, x20, #1
    b       .Lrun_event_loop

.Lrun_periodic:
    // Periodic maintenance: heartbeats, timeouts, reconnection
    bl      mesh_periodic_tasks
    b       .Lrun_loop

.Lrun_stop:
    // Print stopped
    adrp    x0, mesh_str_stopped
    add     x0, x0, :lo12:mesh_str_stopped
    bl      mesh_print

    mov     x0, #0
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size mesh_net_run, .-mesh_net_run

// =============================================================================
// mesh_net_stop - Stop mesh event loop
// =============================================================================
.global mesh_net_stop
.type mesh_net_stop, %function
mesh_net_stop:
    adrp    x0, mesh_running
    add     x0, x0, :lo12:mesh_running
    str     wzr, [x0]
    ret
.size mesh_net_stop, .-mesh_net_stop

// =============================================================================
// mesh_net_poll - Non-blocking poll for mesh events
// =============================================================================
// Call this periodically when running HTTP server to process mesh events.
// Output: x0 = number of events processed
// =============================================================================
.global mesh_net_poll
.type mesh_net_poll, %function
mesh_net_poll:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    // Check if mesh is initialized
    adrp    x0, mesh_epoll_fd
    add     x0, x0, :lo12:mesh_epoll_fd
    ldr     w0, [x0]
    cmp     w0, #0
    b.lt    .Lpoll_not_init

    // epoll_wait with timeout=0 (non-blocking)
    adrp    x0, mesh_epoll_fd
    add     x0, x0, :lo12:mesh_epoll_fd
    ldr     w0, [x0]
    adrp    x1, mesh_events
    add     x1, x1, :lo12:mesh_events
    mov     x2, #16             // maxevents
    mov     x3, #0              // timeout 0 = non-blocking
    mov     x8, #SYS_epoll_pwait
    mov     x4, #0              // sigmask
    svc     #0

    cmp     x0, #0
    b.le    .Lpoll_periodic     // No events or error

    mov     x19, x0             // event count
    mov     x20, #0             // event index
    mov     x21, #0             // processed count

.Lpoll_event_loop:
    cmp     x20, x19
    b.ge    .Lpoll_periodic

    // Get event (epoll_event is 16 bytes on aarch64)
    adrp    x0, mesh_events
    add     x0, x0, :lo12:mesh_events
    mov     x1, #16
    mul     x1, x20, x1
    add     x0, x0, x1

    ldr     w22, [x0]           // events at offset 0
    ldr     x23, [x0, #8]       // data (fd) at offset 8

    // Check if it's the listen socket
    adrp    x0, mesh_listen_fd
    add     x0, x0, :lo12:mesh_listen_fd
    ldr     w0, [x0]
    cmp     w23, w0
    b.eq    .Lpoll_accept

    // Find connection by fd
    mov     x0, x23
    bl      mesh_conn_find_by_fd
    cbz     x0, .Lpoll_next_event

    // Save conn ptr temporarily
    str     x0, [sp, #-16]!

    // Check for error/hangup
    tst     w22, #(EPOLLERR | EPOLLHUP)
    b.ne    .Lpoll_disconnect

    // Check connection state
    ldr     x0, [sp]
    ldr     w1, [x0, #MCONN_OFF_STATE]
    cmp     w1, #MCONN_STATE_CONNECTING
    b.eq    .Lpoll_connect_complete

    // Check for readable
    tst     w22, #EPOLLIN
    b.eq    .Lpoll_next_event_pop

    ldr     x0, [sp]
    bl      mesh_handle_data
    add     x21, x21, #1
    b       .Lpoll_next_event_pop

.Lpoll_accept:
    bl      mesh_handle_accept
    add     x21, x21, #1
    b       .Lpoll_next_event

.Lpoll_connect_complete:
    ldr     x0, [sp]
    bl      mesh_handle_connect_complete
    add     x21, x21, #1
    b       .Lpoll_next_event_pop

.Lpoll_disconnect:
    ldr     x0, [sp]
    bl      mesh_handle_data
    add     x21, x21, #1

.Lpoll_next_event_pop:
    add     sp, sp, #16

.Lpoll_next_event:
    add     x20, x20, #1
    b       .Lpoll_event_loop

.Lpoll_periodic:
    // Do periodic tasks (heartbeats, timeouts, reconnection)
    bl      mesh_periodic_tasks

    mov     x0, x21             // Return processed count
    b       .Lpoll_done

.Lpoll_not_init:
    mov     x0, #0

.Lpoll_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size mesh_net_poll, .-mesh_net_poll

// =============================================================================
// mesh_broadcast_search - Broadcast search query to all connected peers
// =============================================================================
// Input:
//   w0 = query_id
//   w1 = flags (SEARCH_FLAG_*)
//   w2 = max_results
//   x3 = query string pointer
//   w4 = query string length
// Output:
//   x0 = number of peers sent to, or negative error
// =============================================================================
.global mesh_broadcast_search
.type mesh_broadcast_search, %function
mesh_broadcast_search:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     w19, w0             // query_id
    mov     w20, w1             // flags
    mov     w21, w2             // max_results
    mov     x22, x3             // query string
    mov     w23, w4             // query length
    mov     x24, #0             // peers sent count

    // Print broadcast message
    adrp    x0, mesh_str_broadcast_search
    add     x0, x0, :lo12:mesh_str_broadcast_search
    bl      mesh_print

    // Validate query length
    cmp     w23, #0
    b.eq    .Lbcast_done
    cmp     w23, #1024
    b.hi    .Lbcast_done

    // Build SEARCH message in send buffer
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    mov     x1, #MSG_TYPE_SEARCH

    // Get our node ID for source
    adrp    x2, mesh_local_node_id
    add     x2, x2, :lo12:mesh_local_node_id
    ldr     x2, [x2]

    mov     x3, #0              // dst = broadcast
    bl      msg_init

    // Build search payload
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    add     x0, x0, #MSG_HDR_SIZE   // Payload start

    // Store query_id [0-3]
    str     w19, [x0, #SEARCH_OFF_QUERY_ID]

    // Store flags [4-7]
    str     w20, [x0, #SEARCH_OFF_FLAGS]

    // Store max_results [8-11]
    str     w21, [x0, #SEARCH_OFF_MAX_RESULTS]

    // Store query_len [12-15]
    str     w23, [x0, #SEARCH_OFF_QUERY_LEN]

    // Copy query string [16+]
    add     x0, x0, #SEARCH_OFF_QUERY_STR
    mov     x1, x22             // source
    mov     w2, w23             // length

.Lbcast_copy_query:
    cbz     w2, .Lbcast_copy_done
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     w2, w2, #1
    b       .Lbcast_copy_query

.Lbcast_copy_done:
    // Set payload length
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    add     w1, w23, #SEARCH_HDR_SIZE   // header + query string
    str     w1, [x0, #MSG_OFF_LENGTH]

    // Finalize message
    bl      msg_finalize

    // Calculate total message size
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    ldr     w25, [x0, #MSG_OFF_LENGTH]
    add     w25, w25, #MSG_HDR_SIZE     // Total size

    // Send to all connected peers
    adrp    x26, mesh_conns
    add     x26, x26, :lo12:mesh_conns
    mov     x19, #0             // Connection index

.Lbcast_loop:
    cmp     x19, #MESH_MAX_CONNS
    b.ge    .Lbcast_done

    // Check if slot has valid connection
    ldr     w0, [x26, #MCONN_OFF_FD]
    cmp     w0, #0
    b.lt    .Lbcast_next

    // Check connection state (must be connected)
    ldr     w1, [x26, #MCONN_OFF_STATE]
    cmp     w1, #MCONN_STATE_CONNECTED
    b.ne    .Lbcast_next

    // Send search message
    mov     w20, w0             // Save fd
    adrp    x1, mesh_send_buf
    add     x1, x1, :lo12:mesh_send_buf
    mov     w2, w25             // size
    mov     x8, #SYS_write
    svc     #0

    cmp     x0, #0
    b.lt    .Lbcast_next

    // Increment peers sent count
    add     x24, x24, #1

.Lbcast_next:
    add     x26, x26, #MCONN_SIZE
    add     x19, x19, #1
    b       .Lbcast_loop

.Lbcast_done:
    mov     x0, x24             // Return peers sent count
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size mesh_broadcast_search, .-mesh_broadcast_search

// =============================================================================
// mesh_collect_results - Wait for distributed search results with timeout
// =============================================================================
// Input:
//   w0 = timeout in milliseconds (0 = don't wait, just poll once)
// Output:
//   w0 = number of results collected
// Note:
//   Polls mesh_net_poll() repeatedly until either:
//   - All expected peers have responded (pending_search_is_complete())
//   - Timeout expires
//   Then returns the number of peer results collected.
// =============================================================================
.global mesh_collect_results
.type mesh_collect_results, %function
mesh_collect_results:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     w19, w0                     // timeout_ms

    // Get start time
    sub     sp, sp, #32                 // Space for two timespec structs
    mov     x0, #0                      // CLOCK_REALTIME
    mov     x1, sp                      // &start_time
    mov     x8, #SYS_clock_gettime
    svc     #0

    // Store start time in x20 (seconds) and x21 (nanoseconds)
    ldr     x20, [sp, #0]               // start_sec
    ldr     x21, [sp, #8]               // start_nsec

.Lmcr_poll_loop:
    // Check if already complete
    bl      pending_search_is_complete
    cbnz    w0, .Lmcr_done

    // If timeout is 0, just poll once and return
    cbz     w19, .Lmcr_poll_once

    // Check elapsed time
    mov     x0, #0                      // CLOCK_REALTIME
    mov     x1, sp                      // &current_time
    mov     x8, #SYS_clock_gettime
    svc     #0

    // Calculate elapsed milliseconds
    ldr     x0, [sp, #0]                // current_sec
    sub     x0, x0, x20                 // elapsed_sec
    mov     x1, #1000
    mul     x0, x0, x1                  // elapsed_sec * 1000

    ldr     x1, [sp, #8]                // current_nsec
    sub     x1, x1, x21                 // elapsed_nsec (may be negative)
    // 1000000 = 0x000F4240
    mov     x2, #0x4240
    movk    x2, #0x000F, lsl #16
    sdiv    x1, x1, x2                  // elapsed_nsec / 1000000 = elapsed_ms from nsec
    add     x0, x0, x1                  // total elapsed_ms

    cmp     x0, x19
    b.ge    .Lmcr_done                  // Timeout expired

.Lmcr_poll_once:
    // Poll for mesh events (non-blocking)
    bl      mesh_net_poll

    // If timeout is 0, we're done after one poll
    cbz     w19, .Lmcr_done

    // Small sleep to avoid busy-waiting (10ms)
    add     x0, sp, #16                 // Use upper part of stack for sleep timespec
    str     xzr, [x0]                   // seconds = 0
    // 10000000 = 0x00989680
    mov     x1, #0x9680
    movk    x1, #0x0098, lsl #16
    str     x1, [x0, #8]                // nanoseconds = 10ms
    mov     x1, #0                      // No remainder struct
    mov     x8, #SYS_nanosleep
    svc     #0

    b       .Lmcr_poll_loop

.Lmcr_done:
    add     sp, sp, #32                 // Restore stack

    // Return number of results collected
    bl      pending_search_get_count

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size mesh_collect_results, .-mesh_collect_results

// =============================================================================
// mesh_send_index - Send INDEX message to peers based on bitmap
// =============================================================================
// Input:
//   x0 = document ID
//   w1 = operation (INDEX_OP_PUT or INDEX_OP_DELETE)
//   x2 = content pointer (for PUT)
//   w3 = content length (for PUT)
//   x4 = peer bitmap (bits set for peers to send to)
// Output:
//   x0 = number of peers sent to, or negative error
// =============================================================================
.global mesh_send_index
.type mesh_send_index, %function
mesh_send_index:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0             // doc_id
    mov     w20, w1             // operation
    mov     x21, x2             // content
    mov     w22, w3             // content length
    mov     x23, x4             // peer bitmap
    mov     x24, #0             // peers sent count

    // Validate: if PUT, need content
    cmp     w20, #INDEX_OP_PUT
    b.ne    .Lsend_idx_build
    cbz     x21, .Lsend_idx_done

.Lsend_idx_build:
    // Build INDEX message in send buffer
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    mov     x1, #MSG_TYPE_INDEX

    // Get our node ID for source
    adrp    x2, mesh_local_node_id
    add     x2, x2, :lo12:mesh_local_node_id
    ldr     x2, [x2]

    mov     x3, #0              // dst = broadcast
    bl      msg_init

    // Build index payload
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    add     x0, x0, #MSG_HDR_SIZE   // Payload start

    // Store doc_id [0-7]
    str     x19, [x0, #INDEX_OFF_DOC_ID]

    // Store operation [8-11]
    str     w20, [x0, #INDEX_OFF_OPERATION]

    // Store content length [12-15]
    str     w22, [x0, #INDEX_OFF_DOC_LEN]

    // Copy content [16+] if PUT operation
    cmp     w20, #INDEX_OP_PUT
    b.ne    .Lsend_idx_set_len

    add     x0, x0, #INDEX_OFF_DOC_DATA
    mov     x1, x21             // source
    mov     w2, w22             // length

.Lsend_idx_copy:
    cbz     w2, .Lsend_idx_set_len
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     w2, w2, #1
    b       .Lsend_idx_copy

.Lsend_idx_set_len:
    // Set payload length
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    add     w1, w22, #INDEX_HDR_SIZE    // header + content
    str     w1, [x0, #MSG_OFF_LENGTH]

    // Finalize message
    bl      msg_finalize

    // Calculate total message size
    adrp    x0, mesh_send_buf
    add     x0, x0, :lo12:mesh_send_buf
    ldr     w25, [x0, #MSG_OFF_LENGTH]
    add     w25, w25, #MSG_HDR_SIZE     // Total size

    // Send to peers based on bitmap
    // We iterate through peer list and check bitmap bits
    mov     x26, #0             // peer index

.Lsend_idx_loop:
    // Check if we've processed all bits
    cbz     x23, .Lsend_idx_done

    // Check if this peer index bit is set
    mov     x0, #1
    lsl     x0, x0, x26
    tst     x23, x0
    b.eq    .Lsend_idx_next

    // Clear the bit
    bic     x23, x23, x0

    // Get peer entry
    mov     x0, x26
    bl      peer_list_get
    cbz     x0, .Lsend_idx_next

    // Get peer node_id
    ldr     x1, [x0, #PEER_OFF_NODE_ID]
    cbz     x1, .Lsend_idx_next

    // Find connection by node_id
    mov     x19, x1             // Save node_id
    adrp    x0, mesh_conns
    add     x0, x0, :lo12:mesh_conns
    mov     x1, #MESH_MAX_CONNS

.Lsend_idx_find_conn:
    cbz     x1, .Lsend_idx_next     // No matching connection

    // Check if connected and matching node_id
    ldr     w2, [x0, #MCONN_OFF_STATE]
    cmp     w2, #MCONN_STATE_CONNECTED
    b.ne    .Lsend_idx_next_conn

    ldr     x2, [x0, #MCONN_OFF_NODE_ID]
    cmp     x2, x19
    b.eq    .Lsend_idx_send

.Lsend_idx_next_conn:
    add     x0, x0, #MCONN_SIZE
    sub     x1, x1, #1
    b       .Lsend_idx_find_conn

.Lsend_idx_send:
    // Found matching connection - send INDEX message
    ldr     w0, [x0, #MCONN_OFF_FD]
    adrp    x1, mesh_send_buf
    add     x1, x1, :lo12:mesh_send_buf
    mov     w2, w25             // size
    mov     x8, #SYS_write
    svc     #0

    cmp     x0, #0
    b.lt    .Lsend_idx_next

    add     x24, x24, #1        // Increment sent count

.Lsend_idx_next:
    add     x26, x26, #1
    cmp     x26, #64            // Max peers
    b.lt    .Lsend_idx_loop

.Lsend_idx_done:
    mov     x0, x24             // Return peers sent count
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size mesh_send_index, .-mesh_send_index

// =============================================================================
// mesh_net_close - Cleanup mesh networking
// =============================================================================
.global mesh_net_close
.type mesh_net_close, %function
mesh_net_close:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Close all connections
    adrp    x0, mesh_conns
    add     x0, x0, :lo12:mesh_conns
    mov     x1, #MESH_MAX_CONNS

.Lclose_conns:
    ldr     w2, [x0, #MCONN_OFF_FD]
    cmp     w2, #0
    b.lt    .Lclose_next

    // Close fd
    mov     x8, #SYS_close
    svc     #0

.Lclose_next:
    add     x0, x0, #MCONN_SIZE
    sub     x1, x1, #1
    cbnz    x1, .Lclose_conns

    // Close listen socket
    adrp    x0, mesh_listen_fd
    add     x0, x0, :lo12:mesh_listen_fd
    ldr     w0, [x0]
    cmp     w0, #0
    b.lt    .Lclose_epoll
    mov     x8, #SYS_close
    svc     #0

.Lclose_epoll:
    // Close epoll
    adrp    x0, mesh_epoll_fd
    add     x0, x0, :lo12:mesh_epoll_fd
    ldr     w0, [x0]
    cmp     w0, #0
    b.lt    .Lclose_done
    mov     x8, #SYS_close
    svc     #0

.Lclose_done:
    ldp     x29, x30, [sp], #16
    ret
.size mesh_net_close, .-mesh_net_close

// =============================================================================
// mesh_itoa_byte - Convert byte (0-255) to decimal string
// =============================================================================
// Input:  x0 = output buffer pointer
//         w2 = byte value (0-255)
// Output: x0 = updated pointer (after last digit)
// Clobbers: w3, w4, w5, w6
// =============================================================================
mesh_itoa_byte:
    // Handle 0 specially
    cbz     w2, .Litoa_zero

    mov     w6, #0                  // w6 = flag: have we output a digit?

    // Divide by 100
    mov     w3, #100
    udiv    w4, w2, w3              // w4 = hundreds digit
    cbz     w4, .Litoa_tens

    // Output hundreds digit
    add     w5, w4, #'0'
    strb    w5, [x0], #1
    mov     w6, #1                  // set flag

    // Update remaining value
    msub    w2, w4, w3, w2          // w2 = w2 - w4 * 100

.Litoa_tens:
    // Divide by 10
    mov     w3, #10
    udiv    w4, w2, w3              // w4 = tens digit

    // Output if tens > 0 OR we've already output hundreds
    cbnz    w4, .Litoa_tens_output
    cbz     w6, .Litoa_ones         // skip if no hundreds and tens is 0

.Litoa_tens_output:
    add     w5, w4, #'0'
    strb    w5, [x0], #1

    // Update remaining value
    msub    w2, w4, w3, w2          // w2 = w2 - w4 * 10

.Litoa_ones:
    // Output ones digit
    add     w5, w2, #'0'
    strb    w5, [x0], #1
    ret

.Litoa_zero:
    mov     w5, #'0'
    strb    w5, [x0], #1
    ret

// =============================================================================
// End of mesh_net.s
// =============================================================================
