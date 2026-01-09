// =============================================================================
// UDP Transport Implementation
// =============================================================================
//
// UDP transport backend for the transport abstraction layer.
// Supports:
//   - Unicast messaging to specific peers
//   - Broadcast discovery for peer detection
//   - Low-overhead, connectionless communication
//
// Frame format (same as serial for consistency):
//   [SYNC1: 0xAA] [SYNC2: 0x55] [LEN_LO] [LEN_HI] [PAYLOAD...] [CRC_LO] [CRC_HI]
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/transport.inc"

.global udp_transport_register
.global udp_transport_ops

// External functions
.extern transport_register
.extern udp_bind
.extern htons
.extern htonl
.extern ntohs
.extern ntohl
.extern serial_crc16              // Reuse CRC from serial transport

.text

// =============================================================================
// udp_transport_register - Register UDP transport with manager
// =============================================================================
// Input: none
// Output:
//   x0 = 0 on success
// =============================================================================

udp_transport_register:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Register with transport manager
    mov     x0, #TRANSPORT_UDP
    adrp    x1, udp_transport_ops
    add     x1, x1, :lo12:udp_transport_ops
    bl      transport_register

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// udp_init - Initialize UDP transport
// =============================================================================
// Input:
//   x0 = pointer to transport_config
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================

udp_init:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save config pointer

    // Get port from config
    ldr     w20, [x19, #TRANSPORT_CFG_PORT]
    cbz     w20, .Ludp_init_no_port

    // Create and bind UDP socket
    mov     w0, w20
    bl      udp_bind
    cmp     x0, #0
    b.lt    .Ludp_init_error

    // Store socket fd
    adrp    x1, udp_socket_fd
    add     x1, x1, :lo12:udp_socket_fd
    str     w0, [x1]
    mov     w21, w0                     // Save fd

    // Check if broadcast is enabled
    ldr     w0, [x19, #TRANSPORT_CFG_FLAGS]
    tst     w0, #TRANSPORT_FLAG_BROADCAST
    b.eq    .Ludp_init_no_broadcast

    // Enable SO_BROADCAST
    mov     w0, #1
    sub     sp, sp, #16
    str     w0, [sp]
    mov     w0, w21
    mov     x1, #SOL_SOCKET
    mov     x2, #SO_BROADCAST
    mov     x3, sp
    mov     x4, #4
    mov     x8, #SYS_setsockopt
    svc     #0
    add     sp, sp, #16

    // Store broadcast enabled flag
    adrp    x0, udp_broadcast_enabled
    add     x0, x0, :lo12:udp_broadcast_enabled
    mov     w1, #1
    str     w1, [x0]

.Ludp_init_no_broadcast:
    // Store port
    adrp    x0, udp_port
    add     x0, x0, :lo12:udp_port
    str     w20, [x0]

    // Initialize peer list
    adrp    x0, udp_peers
    add     x0, x0, :lo12:udp_peers
    mov     x1, #(UDP_MAX_PEERS * UDP_PEER_SIZE)
.Ludp_clear_peers:
    subs    x1, x1, #8
    str     xzr, [x0, x1]
    b.gt    .Ludp_clear_peers

    adrp    x0, udp_peer_count
    add     x0, x0, :lo12:udp_peer_count
    str     wzr, [x0]

    // Reset statistics
    adrp    x0, udp_stats_rx_packets
    add     x0, x0, :lo12:udp_stats_rx_packets
    str     xzr, [x0]

    adrp    x0, udp_stats_tx_packets
    add     x0, x0, :lo12:udp_stats_tx_packets
    str     xzr, [x0]

    adrp    x0, udp_stats_crc_errors
    add     x0, x0, :lo12:udp_stats_crc_errors
    str     xzr, [x0]

    mov     x0, #0
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Ludp_init_no_port:
    mov     x0, #TRANSPORT_ERR_INVALID
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Ludp_init_error:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret


// =============================================================================
// udp_shutdown - Shutdown UDP transport
// =============================================================================
// Input: none
// Output: none
// =============================================================================

udp_shutdown:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Close socket if open
    adrp    x0, udp_socket_fd
    add     x0, x0, :lo12:udp_socket_fd
    ldr     w0, [x0]
    cmp     w0, #0
    b.le    .Ludp_shutdown_done

    mov     x8, #SYS_close
    svc     #0

    // Clear fd
    adrp    x0, udp_socket_fd
    add     x0, x0, :lo12:udp_socket_fd
    str     wzr, [x0]

.Ludp_shutdown_done:
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// udp_send - Send framed data via UDP
// =============================================================================
// Input:
//   x0 = peer_id (or 0 for broadcast)
//   x1 = data pointer
//   x2 = data length
// Output:
//   x0 = bytes sent (payload only) on success, negative errno on failure
// =============================================================================

udp_send:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // peer_id
    mov     x20, x1                     // data
    mov     w21, w2                     // length

    // Check length
    cmp     w21, #SERIAL_MAX_PAYLOAD
    b.gt    .Ludp_send_too_long

    // Get socket fd
    adrp    x0, udp_socket_fd
    add     x0, x0, :lo12:udp_socket_fd
    ldr     w22, [x0]
    cmp     w22, #0
    b.le    .Ludp_send_not_init

    // Calculate CRC of payload
    mov     x0, x20
    mov     w1, w21
    bl      serial_crc16
    mov     w23, w0                     // CRC

    // Build frame in tx buffer
    adrp    x24, udp_tx_buffer
    add     x24, x24, :lo12:udp_tx_buffer

    mov     w0, #SERIAL_SYNC_BYTE1
    strb    w0, [x24, #0]
    mov     w0, #SERIAL_SYNC_BYTE2
    strb    w0, [x24, #1]
    strb    w21, [x24, #2]              // Length low byte
    lsr     w0, w21, #8
    strb    w0, [x24, #3]               // Length high byte

    // Copy payload
    add     x0, x24, #SERIAL_FRAME_HDR_SIZE
    mov     x1, x20
    mov     w2, w21
    bl      udp_memcpy

    // Append CRC
    add     w0, w21, #SERIAL_FRAME_HDR_SIZE
    strb    w23, [x24, x0]              // CRC low byte
    lsr     w1, w23, #8
    add     w0, w0, #1
    strb    w1, [x24, x0]               // CRC high byte

    // Calculate total frame size
    add     w0, w21, #SERIAL_FRAME_OVERHEAD

    // Build destination address
    sub     sp, sp, #16

    // Check if broadcast or unicast
    cbz     x19, .Ludp_send_broadcast

    // Unicast: look up peer address
    mov     x0, x19
    bl      udp_find_peer
    cmp     x0, #0
    b.lt    .Ludp_send_no_peer

    // Copy peer's address
    ldr     w1, [x0, #UDP_PEER_OFF_ADDR]
    ldr     w2, [x0, #UDP_PEER_OFF_PORT]
    b       .Ludp_send_build_addr

.Ludp_send_broadcast:
    // Broadcast address: 255.255.255.255
    mov     w1, #0xFFFFFFFF
    adrp    x0, udp_port
    add     x0, x0, :lo12:udp_port
    ldr     w2, [x0]
    bl      htons
    mov     w2, w0

.Ludp_send_build_addr:
    mov     w0, #AF_INET
    strh    w0, [sp, #0]                // sin_family
    strh    w2, [sp, #2]                // sin_port (network order)
    str     w1, [sp, #4]                // sin_addr (network order)
    str     xzr, [sp, #8]               // padding

    // Send datagram
    add     w3, w21, #SERIAL_FRAME_OVERHEAD  // Total length
    mov     w0, w22                     // socket fd
    mov     x1, x24                     // buffer
    mov     x2, x3                      // length
    mov     x3, #0                      // flags
    mov     x4, sp                      // dest_addr
    mov     x5, #16                     // addrlen
    mov     x8, #SYS_sendto
    svc     #0

    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Ludp_send_error

    // Increment TX counter
    adrp    x1, udp_stats_tx_packets
    add     x1, x1, :lo12:udp_stats_tx_packets
    ldr     x2, [x1]
    add     x2, x2, #1
    str     x2, [x1]

    // Return payload length
    mov     x0, x21
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

.Ludp_send_too_long:
    mov     x0, #TRANSPORT_ERR_INVALID
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

.Ludp_send_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

.Ludp_send_no_peer:
    add     sp, sp, #16
    mov     x0, #TRANSPORT_ERR_NO_PEER
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

.Ludp_send_error:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret


// =============================================================================
// udp_recv - Receive framed data via UDP
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = buffer length
//   x2 = timeout in milliseconds (ignored - non-blocking)
// Output:
//   x0 = bytes received (payload) on success, negative errno on failure
//   x1 = peer_id of sender
// =============================================================================

udp_recv:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // output buffer
    mov     w20, w1                     // buffer length

    // Get socket fd
    adrp    x0, udp_socket_fd
    add     x0, x0, :lo12:udp_socket_fd
    ldr     w21, [x0]
    cmp     w21, #0
    b.le    .Ludp_recv_not_init

    // Receive datagram with sender address
    adrp    x22, udp_rx_buffer
    add     x22, x22, :lo12:udp_rx_buffer

    // sockaddr_in for sender
    add     x23, sp, #64                // sender address at sp+64
    mov     w0, #16
    str     w0, [sp, #80]               // addrlen at sp+80

    mov     w0, w21                     // socket fd
    mov     x1, x22                     // buffer
    mov     x2, #UDP_BUFFER_SIZE        // max length
    mov     x3, #0                      // flags
    mov     x4, x23                     // src_addr
    add     x5, sp, #80                 // addrlen pointer
    mov     x8, #SYS_recvfrom
    svc     #0

    cmp     x0, #0
    b.lt    .Ludp_recv_check_eagain
    b.eq    .Ludp_recv_no_data

    mov     w24, w0                     // bytes received

    // Validate frame (minimum size: header + CRC)
    cmp     w24, #SERIAL_FRAME_OVERHEAD
    b.lt    .Ludp_recv_frame_error

    // Check sync bytes
    ldrb    w0, [x22, #0]
    cmp     w0, #SERIAL_SYNC_BYTE1
    b.ne    .Ludp_recv_frame_error
    ldrb    w0, [x22, #1]
    cmp     w0, #SERIAL_SYNC_BYTE2
    b.ne    .Ludp_recv_frame_error

    // Get payload length
    ldrb    w0, [x22, #2]
    ldrb    w1, [x22, #3]
    orr     w0, w0, w1, lsl #8
    mov     w21, w0                     // payload length

    // Validate length
    add     w1, w21, #SERIAL_FRAME_OVERHEAD
    cmp     w1, w24
    b.ne    .Ludp_recv_frame_error

    // Check if payload fits in output buffer
    cmp     w21, w20
    b.gt    .Ludp_recv_buffer_full

    // Verify CRC
    add     x0, x22, #SERIAL_FRAME_HDR_SIZE
    mov     w1, w21
    bl      serial_crc16
    mov     w1, w0                      // calculated CRC

    // Get received CRC
    add     w0, w21, #SERIAL_FRAME_HDR_SIZE
    ldrb    w2, [x22, x0]
    add     w0, w0, #1
    ldrb    w3, [x22, x0]
    orr     w2, w2, w3, lsl #8          // received CRC

    cmp     w1, w2
    b.ne    .Ludp_recv_crc_error

    // CRC OK - copy payload to output buffer
    mov     x0, x19
    add     x1, x22, #SERIAL_FRAME_HDR_SIZE
    mov     w2, w21
    bl      udp_memcpy

    // Increment RX counter
    adrp    x0, udp_stats_rx_packets
    add     x0, x0, :lo12:udp_stats_rx_packets
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    // Add/update peer from sender address
    ldr     w0, [x23, #4]               // sin_addr
    ldrh    w1, [x23, #2]               // sin_port
    bl      udp_add_or_update_peer
    mov     x1, x0                      // peer_id

    mov     x0, x21                     // payload length
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

.Ludp_recv_check_eagain:
    cmn     x0, #EAGAIN
    b.eq    .Ludp_recv_no_data
    cmn     x0, #EWOULDBLOCK
    b.eq    .Ludp_recv_no_data
    // Real error
    mov     x1, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

.Ludp_recv_no_data:
    mov     x0, #TRANSPORT_ERR_TIMEOUT
    mov     x1, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

.Ludp_recv_frame_error:
    mov     x0, #TRANSPORT_ERR_FRAME
    mov     x1, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

.Ludp_recv_buffer_full:
    mov     x0, #TRANSPORT_ERR_FULL
    mov     x1, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

.Ludp_recv_crc_error:
    // Increment CRC error counter
    adrp    x0, udp_stats_crc_errors
    add     x0, x0, :lo12:udp_stats_crc_errors
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    mov     x0, #TRANSPORT_ERR_CRC
    mov     x1, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

.Ludp_recv_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    mov     x1, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret


// =============================================================================
// udp_get_peers - Get list of known UDP peers
// =============================================================================
// Input:
//   x0 = buffer pointer (array of transport_peer structures)
//   x1 = max peers
// Output:
//   x0 = number of peers written
// =============================================================================

udp_get_peers:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // output buffer
    mov     w20, w1                     // max peers
    mov     w21, #0                     // peers written
    mov     w22, #0                     // index

    adrp    x23, udp_peers
    add     x23, x23, :lo12:udp_peers

    adrp    x0, udp_peer_count
    add     x0, x0, :lo12:udp_peer_count
    ldr     w24, [x0]                   // total peers

.Ludp_peers_loop:
    cmp     w21, w20                    // written >= max?
    b.ge    .Ludp_peers_done
    cmp     w22, w24                    // index >= total?
    b.ge    .Ludp_peers_done

    // Calculate peer entry address
    mov     w0, #UDP_PEER_SIZE
    mul     w0, w22, w0
    add     x1, x23, x0                 // peer entry

    // Check if peer is active
    ldr     w0, [x1, #UDP_PEER_OFF_FLAGS]
    tst     w0, #UDP_PEER_FLAG_ACTIVE
    b.eq    .Ludp_peers_next

    // Calculate output position
    mov     w0, #TPEER_SIZE
    mul     w0, w21, w0
    add     x2, x19, x0                 // output entry

    // Fill transport_peer structure
    // Use index+1 as peer_id
    add     w0, w22, #1
    str     x0, [x2, #TPEER_OFF_ID]

    // Store IP:port in address field
    ldr     w0, [x1, #UDP_PEER_OFF_ADDR]
    str     w0, [x2, #TPEER_OFF_ADDR]
    ldr     w0, [x1, #UDP_PEER_OFF_PORT]
    str     w0, [x2, #TPEER_OFF_ADDR + 4]
    str     xzr, [x2, #TPEER_OFF_ADDR + 8]

    // Quality based on packet success rate
    ldr     w0, [x1, #UDP_PEER_OFF_RX_OK]
    ldr     w3, [x1, #UDP_PEER_OFF_RX_FAIL]
    add     w3, w0, w3
    cbz     w3, .Ludp_peers_default_quality
    mov     w4, #100
    mul     w0, w0, w4
    udiv    w0, w0, w3
    b       .Ludp_peers_store_quality
.Ludp_peers_default_quality:
    mov     w0, #50                     // Unknown quality
.Ludp_peers_store_quality:
    str     w0, [x2, #TPEER_OFF_QUALITY]

    // Flags
    mov     w0, #(TPEER_FLAG_CONNECTED | TPEER_FLAG_REACHABLE)
    str     w0, [x2, #TPEER_OFF_FLAGS]

    add     w21, w21, #1

.Ludp_peers_next:
    add     w22, w22, #1
    b       .Ludp_peers_loop

.Ludp_peers_done:
    mov     x0, x21
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret


// =============================================================================
// udp_get_quality - Get link quality to peer
// =============================================================================
// Input:
//   x0 = peer_id
// Output:
//   w0 = quality (0-100), or -1 if unknown
// =============================================================================

udp_get_quality:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      udp_find_peer
    cmp     x0, #0
    b.lt    .Ludp_quality_unknown

    // Calculate quality from packet stats
    ldr     w1, [x0, #UDP_PEER_OFF_RX_OK]
    ldr     w2, [x0, #UDP_PEER_OFF_RX_FAIL]
    add     w2, w1, w2
    cbz     w2, .Ludp_quality_unknown

    mov     w3, #100
    mul     w1, w1, w3
    udiv    w0, w1, w2

    ldp     x29, x30, [sp], #16
    ret

.Ludp_quality_unknown:
    mov     w0, #-1
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// udp_find_peer - Find peer by ID
// =============================================================================
// Input:
//   x0 = peer_id
// Output:
//   x0 = pointer to peer entry, or -1 if not found
// =============================================================================

udp_find_peer:
    cbz     x0, .Ludp_find_not_found

    // peer_id is index+1
    sub     x0, x0, #1

    adrp    x1, udp_peer_count
    add     x1, x1, :lo12:udp_peer_count
    ldr     w1, [x1]
    cmp     x0, x1
    b.ge    .Ludp_find_not_found

    // Calculate address
    adrp    x1, udp_peers
    add     x1, x1, :lo12:udp_peers
    mov     x2, #UDP_PEER_SIZE
    mul     x0, x0, x2
    add     x0, x1, x0

    // Check if active
    ldr     w1, [x0, #UDP_PEER_OFF_FLAGS]
    tst     w1, #UDP_PEER_FLAG_ACTIVE
    b.eq    .Ludp_find_not_found

    ret

.Ludp_find_not_found:
    mov     x0, #-1
    ret


// =============================================================================
// udp_add_or_update_peer - Add new peer or update existing
// =============================================================================
// Input:
//   w0 = IP address (network order)
//   w1 = port (network order)
// Output:
//   x0 = peer_id
// =============================================================================

udp_add_or_update_peer:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     w19, w0                     // IP
    mov     w20, w1                     // port

    // Search for existing peer
    adrp    x21, udp_peers
    add     x21, x21, :lo12:udp_peers

    adrp    x0, udp_peer_count
    add     x0, x0, :lo12:udp_peer_count
    ldr     w22, [x0]                   // count

    mov     w0, #0                      // index
.Ludp_search_peer:
    cmp     w0, w22
    b.ge    .Ludp_add_new_peer

    mov     w1, #UDP_PEER_SIZE
    mul     w1, w0, w1
    add     x2, x21, x1                 // peer entry

    // Check if matches
    ldr     w3, [x2, #UDP_PEER_OFF_ADDR]
    cmp     w3, w19
    b.ne    .Ludp_search_next
    ldr     w3, [x2, #UDP_PEER_OFF_PORT]
    cmp     w3, w20
    b.ne    .Ludp_search_next

    // Found - update last_seen and increment rx_ok
    // Get current time
    stp     x0, x2, [sp, #-16]!
    sub     sp, sp, #16
    mov     x0, #CLOCK_MONOTONIC
    mov     x1, sp
    mov     x8, #SYS_clock_gettime
    svc     #0
    ldr     x3, [sp]                    // seconds
    add     sp, sp, #16
    ldp     x0, x2, [sp], #16

    str     x3, [x2, #UDP_PEER_OFF_LAST_SEEN]
    ldr     w3, [x2, #UDP_PEER_OFF_RX_OK]
    add     w3, w3, #1
    str     w3, [x2, #UDP_PEER_OFF_RX_OK]

    // Return peer_id (index + 1)
    add     x0, x0, #1
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Ludp_search_next:
    add     w0, w0, #1
    b       .Ludp_search_peer

.Ludp_add_new_peer:
    // Check if room for new peer
    cmp     w22, #UDP_MAX_PEERS
    b.ge    .Ludp_peer_full

    // Add new peer
    mov     w0, #UDP_PEER_SIZE
    mul     w0, w22, w0
    add     x2, x21, x0                 // new peer entry

    str     w19, [x2, #UDP_PEER_OFF_ADDR]
    str     w20, [x2, #UDP_PEER_OFF_PORT]
    mov     w0, #UDP_PEER_FLAG_ACTIVE
    str     w0, [x2, #UDP_PEER_OFF_FLAGS]
    mov     w0, #1
    str     w0, [x2, #UDP_PEER_OFF_RX_OK]
    str     wzr, [x2, #UDP_PEER_OFF_RX_FAIL]

    // Get current time for last_seen
    sub     sp, sp, #16
    mov     x0, #CLOCK_MONOTONIC
    mov     x1, sp
    mov     x8, #SYS_clock_gettime
    svc     #0
    ldr     x0, [sp]
    add     sp, sp, #16
    str     x0, [x2, #UDP_PEER_OFF_LAST_SEEN]

    // Increment count
    add     w22, w22, #1
    adrp    x0, udp_peer_count
    add     x0, x0, :lo12:udp_peer_count
    str     w22, [x0]

    // Return peer_id (index + 1)
    mov     x0, x22
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Ludp_peer_full:
    // Return peer_id 0 (broadcast/unknown)
    mov     x0, #0
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret


// =============================================================================
// udp_memcpy - Simple memory copy
// =============================================================================
// Input:
//   x0 = dest
//   x1 = src
//   w2 = length
// =============================================================================

udp_memcpy:
    cbz     w2, .Ludp_memcpy_done
.Ludp_memcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    subs    w2, w2, #1
    b.ne    .Ludp_memcpy_loop
.Ludp_memcpy_done:
    ret


// =============================================================================
// Constants
// =============================================================================

.equ UDP_MAX_PEERS,         32
.equ UDP_BUFFER_SIZE,       4096 + SERIAL_FRAME_OVERHEAD

// UDP peer entry structure
.equ UDP_PEER_OFF_ADDR,     0           // [4] IP address (network order)
.equ UDP_PEER_OFF_PORT,     4           // [4] Port (network order)
.equ UDP_PEER_OFF_FLAGS,    8           // [4] Flags
.equ UDP_PEER_OFF_RX_OK,    12          // [4] Successful receives
.equ UDP_PEER_OFF_RX_FAIL,  16          // [4] Failed receives
.equ UDP_PEER_OFF_LAST_SEEN, 20         // [8] Last seen timestamp
.equ UDP_PEER_OFF_NODE_ID,  28          // [8] Node ID (if known)
.equ UDP_PEER_SIZE,         36

// Peer flags
.equ UDP_PEER_FLAG_ACTIVE,  0x01


// =============================================================================
// Data Section
// =============================================================================

.data

// UDP transport operations vtable
.balign 8
udp_transport_ops:
    .quad   udp_init                    // init
    .quad   udp_shutdown                // shutdown
    .quad   udp_send                    // send
    .quad   udp_recv                    // recv
    .quad   udp_get_peers               // get_peers
    .quad   udp_get_quality             // get_link_quality

// UDP socket
udp_socket_fd:
    .word   0
udp_port:
    .word   0
udp_broadcast_enabled:
    .word   0
    .balign 4

// Peer tracking
udp_peer_count:
    .word   0
    .balign 8

udp_peers:
    .space  UDP_MAX_PEERS * UDP_PEER_SIZE, 0

// Statistics
udp_stats_rx_packets:
    .quad   0
udp_stats_tx_packets:
    .quad   0
udp_stats_crc_errors:
    .quad   0

// Buffers
.balign 8
udp_rx_buffer:
    .space  UDP_BUFFER_SIZE, 0

udp_tx_buffer:
    .space  UDP_BUFFER_SIZE, 0

