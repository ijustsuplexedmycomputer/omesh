// =============================================================================
// Bluetooth Transport Implementation
// =============================================================================
//
// Short-range mesh transport using Bluetooth RFCOMM (Serial Port Profile).
// Provides serial-like communication over Bluetooth connections.
//
// Features:
// - RFCOMM socket connections
// - Device discovery and pairing
// - Multiple peer connections
// - Link quality from RSSI
//
// Socket family: AF_BLUETOOTH = 31
// Protocol: BTPROTO_RFCOMM = 3
//
// Frame format (same as serial):
//   [0xAA][0x55][LEN_LO][LEN_HI][PAYLOAD...][CRC_LO][CRC_HI]
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/transport.inc"

// Bluetooth socket constants
.equ AF_BLUETOOTH,          31
.equ BTPROTO_RFCOMM,        3
.equ BTPROTO_L2CAP,         0
.equ BTPROTO_HCI,           1

// RFCOMM socket address structure (10 bytes)
.equ SOCKADDR_RC_FAMILY,    0           // [2] AF_BLUETOOTH
.equ SOCKADDR_RC_BDADDR,    2           // [6] Bluetooth address
.equ SOCKADDR_RC_CHANNEL,   8           // [1] RFCOMM channel
.equ SOCKADDR_RC_SIZE,      10

// Bluetooth address structure (6 bytes)
.equ BDADDR_SIZE,           6

// HCI ioctl commands
.equ HCIGETDEVLIST,         0x800448D2
.equ HCIGETDEVINFO,         0x800448D3
.equ HCIINQUIRY,            0x800448F0

// Bluetooth transport constants
.equ BT_MAX_PEERS,          8
.equ BT_PEER_SIZE,          32          // [6] bdaddr + [1] channel + [1] flags + [4] rssi + [4] quality + [8] last_seen + [8] reserved
.equ BT_MAX_PAYLOAD,        1024
.equ BT_LISTEN_BACKLOG,     5

// Peer structure offsets
.equ BT_PEER_BDADDR,        0           // [6] Bluetooth address
.equ BT_PEER_CHANNEL,       6           // [1] RFCOMM channel
.equ BT_PEER_FLAGS,         7           // [1] Connection flags
.equ BT_PEER_FD,            8           // [4] Socket FD
.equ BT_PEER_RSSI,          12          // [4] Signal strength
.equ BT_PEER_QUALITY,       16          // [4] Link quality 0-100
.equ BT_PEER_LAST_SEEN,     20          // [8] Timestamp
.equ BT_PEER_TX_COUNT,      28          // [4] Packets sent

// Peer flags
.equ BT_PEER_FLAG_CONNECTED,    0x01
.equ BT_PEER_FLAG_LISTENING,    0x02
.equ BT_PEER_FLAG_DISCOVERED,   0x04

// =============================================================================
// Data Section
// =============================================================================

.data

// Transport vtable
.global bluetooth_transport_ops
.align 3
bluetooth_transport_ops:
    .quad   bt_init
    .quad   bt_shutdown
    .quad   bt_send
    .quad   bt_recv
    .quad   bt_get_peers
    .quad   bt_get_quality

// State
.align 3
bt_listen_fd:
    .word   -1                          // Listening socket
bt_channel:
    .word   1                           // RFCOMM channel
bt_configured:
    .word   0
bt_discover_mode:
    .word   0                           // Discovery enabled

// Local Bluetooth address
bt_local_addr:
    .skip   BDADDR_SIZE

// Peer tracking
.align 3
bt_peers:
    .skip   BT_MAX_PEERS * BT_PEER_SIZE
bt_peer_count:
    .word   0

// Buffers
.align 4
bt_rx_buffer:
    .skip   BT_MAX_PAYLOAD + SERIAL_FRAME_OVERHEAD
bt_tx_buffer:
    .skip   BT_MAX_PAYLOAD + SERIAL_FRAME_OVERHEAD

// Frame state machine
bt_rx_state:
    .word   SERIAL_STATE_SYNC1
bt_rx_length:
    .word   0
bt_rx_pos:
    .word   0
bt_rx_crc:
    .word   0

// Statistics
bt_tx_count:
    .word   0
bt_rx_count:
    .word   0
bt_rx_errors:
    .word   0

// Device name
bt_device_name:
    .skip   64

.text

// =============================================================================
// bluetooth_transport_register - Register Bluetooth transport
// =============================================================================
.global bluetooth_transport_register
.type bluetooth_transport_register, %function
bluetooth_transport_register:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     w0, #TRANSPORT_BLUETOOTH
    adrp    x1, bluetooth_transport_ops
    add     x1, x1, :lo12:bluetooth_transport_ops
    bl      transport_register

    ldp     x29, x30, [sp], #16
    ret
.size bluetooth_transport_register, .-bluetooth_transport_register

// =============================================================================
// bt_init - Initialize Bluetooth transport
// =============================================================================
// Input:
//   x0 = config pointer (TRANSPORT_CFG_*)
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================
.global bt_init
.type bt_init, %function
bt_init:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save config

    // Check if Bluetooth is available by creating a test socket
    mov     w0, #AF_BLUETOOTH
    mov     w1, #1                      // SOCK_STREAM
    mov     w2, #BTPROTO_RFCOMM
    mov     x8, #SYS_socket
    svc     #0
    cmp     x0, #0
    b.lt    .Lbt_init_no_bt

    // Close test socket
    mov     x8, #SYS_close
    svc     #0

    // Create RFCOMM listening socket
    mov     w0, #AF_BLUETOOTH
    mov     w1, #1                      // SOCK_STREAM
    mov     w2, #BTPROTO_RFCOMM
    mov     x8, #SYS_socket
    svc     #0
    cmp     x0, #0
    b.lt    .Lbt_init_fail

    mov     w20, w0                     // Save socket fd

    // Build bind address
    sub     sp, sp, #16
    mov     x21, sp

    // Clear address structure
    str     xzr, [x21]
    str     xzr, [x21, #8]

    // Set family
    mov     w0, #AF_BLUETOOTH
    strh    w0, [x21, #SOCKADDR_RC_FAMILY]

    // Set BDADDR_ANY (all zeros)
    // Already zeroed above

    // Set channel
    adrp    x0, bt_channel
    add     x0, x0, :lo12:bt_channel
    ldr     w0, [x0]
    strb    w0, [x21, #SOCKADDR_RC_CHANNEL]

    // Bind socket
    mov     w0, w20
    mov     x1, x21
    mov     w2, #SOCKADDR_RC_SIZE
    mov     x8, #SYS_bind
    svc     #0
    cmp     x0, #0
    b.lt    .Lbt_init_bind_fail

    // Listen for connections
    mov     w0, w20
    mov     w1, #BT_LISTEN_BACKLOG
    mov     x8, #SYS_listen
    svc     #0
    cmp     x0, #0
    b.lt    .Lbt_init_listen_fail

    add     sp, sp, #16

    // Save listen fd
    adrp    x0, bt_listen_fd
    add     x0, x0, :lo12:bt_listen_fd
    str     w20, [x0]

    // Mark configured
    adrp    x0, bt_configured
    add     x0, x0, :lo12:bt_configured
    mov     w1, #1
    str     w1, [x0]

    // Clear peer list
    adrp    x0, bt_peer_count
    add     x0, x0, :lo12:bt_peer_count
    str     wzr, [x0]

    // Clear stats
    adrp    x0, bt_tx_count
    add     x0, x0, :lo12:bt_tx_count
    str     wzr, [x0]
    adrp    x0, bt_rx_count
    add     x0, x0, :lo12:bt_rx_count
    str     wzr, [x0]
    adrp    x0, bt_rx_errors
    add     x0, x0, :lo12:bt_rx_errors
    str     wzr, [x0]

    mov     x0, #0
    b       .Lbt_init_ret

.Lbt_init_no_bt:
    mov     x0, #-93                    // EPROTONOSUPPORT
    b       .Lbt_init_ret

.Lbt_init_listen_fail:
.Lbt_init_bind_fail:
    add     sp, sp, #16
    mov     w0, w20
    mov     x8, #SYS_close
    svc     #0
    mov     x0, #-98                    // EADDRINUSE
    b       .Lbt_init_ret

.Lbt_init_fail:
    // x0 already has error

.Lbt_init_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size bt_init, .-bt_init

// =============================================================================
// bt_shutdown - Shutdown Bluetooth transport
// =============================================================================
.global bt_shutdown
.type bt_shutdown, %function
bt_shutdown:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Close all peer connections
    adrp    x19, bt_peers
    add     x19, x19, :lo12:bt_peers

    adrp    x0, bt_peer_count
    add     x0, x0, :lo12:bt_peer_count
    ldr     w1, [x0]

.Lbt_shutdown_peers:
    cbz     w1, .Lbt_shutdown_listen
    sub     w1, w1, #1

    // Get peer fd
    mov     x2, #BT_PEER_SIZE
    mul     x2, x1, x2
    add     x2, x19, x2
    ldr     w0, [x2, #BT_PEER_FD]

    cmp     w0, #0
    b.lt    .Lbt_shutdown_peers

    mov     x8, #SYS_close
    svc     #0
    b       .Lbt_shutdown_peers

.Lbt_shutdown_listen:
    // Close listen socket
    adrp    x0, bt_listen_fd
    add     x0, x0, :lo12:bt_listen_fd
    ldr     w0, [x0]
    cmp     w0, #0
    b.lt    .Lbt_shutdown_done

    mov     x8, #SYS_close
    svc     #0

    adrp    x0, bt_listen_fd
    add     x0, x0, :lo12:bt_listen_fd
    mov     w1, #-1
    str     w1, [x0]

.Lbt_shutdown_done:
    // Clear configured
    adrp    x0, bt_configured
    add     x0, x0, :lo12:bt_configured
    str     wzr, [x0]

    // Clear peer count
    adrp    x0, bt_peer_count
    add     x0, x0, :lo12:bt_peer_count
    str     wzr, [x0]

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size bt_shutdown, .-bt_shutdown

// =============================================================================
// bt_send - Send data via Bluetooth
// =============================================================================
// Input:
//   x0 = peer_id (index into peer array, or 0 for broadcast to all)
//   x1 = data pointer
//   x2 = data length
// Output:
//   x0 = bytes sent, negative on error
// =============================================================================
.global bt_send
.type bt_send, %function
bt_send:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // peer_id
    mov     x20, x1                     // data
    mov     x21, x2                     // length

    // Check configured
    adrp    x0, bt_configured
    add     x0, x0, :lo12:bt_configured
    ldr     w0, [x0]
    cbz     w0, .Lbt_send_not_init

    // Check length
    cmp     x21, #BT_MAX_PAYLOAD
    b.gt    .Lbt_send_too_large

    // Build framed message
    adrp    x22, bt_tx_buffer
    add     x22, x22, :lo12:bt_tx_buffer

    // Sync bytes
    mov     w0, #SERIAL_SYNC_BYTE1
    strb    w0, [x22, #0]
    mov     w0, #SERIAL_SYNC_BYTE2
    strb    w0, [x22, #1]

    // Length (little endian)
    and     w0, w21, #0xFF
    strb    w0, [x22, #2]
    lsr     w0, w21, #8
    strb    w0, [x22, #3]

    // Copy payload
    mov     x0, x22
    add     x0, x0, #4
    mov     x1, x20
    mov     x2, x21
    bl      bt_memcpy

    // Calculate CRC
    add     x0, x22, #2
    add     w1, w21, #2
    bl      serial_crc16

    // Store CRC
    add     x1, x22, #4
    add     x1, x1, x21
    and     w2, w0, #0xFF
    strb    w2, [x1, #0]
    lsr     w2, w0, #8
    strb    w2, [x1, #1]

    // Total frame length
    add     w23, w21, #SERIAL_FRAME_OVERHEAD

    // If peer_id > 0, send to specific peer
    cbnz    x19, .Lbt_send_one

    // Broadcast to all connected peers
    adrp    x24, bt_peers
    add     x24, x24, :lo12:bt_peers

    adrp    x0, bt_peer_count
    add     x0, x0, :lo12:bt_peer_count
    ldr     w19, [x0]
    mov     w0, #0                      // peer index

.Lbt_send_all_loop:
    cmp     w0, w19
    b.ge    .Lbt_send_done

    // Get peer entry
    mov     x1, #BT_PEER_SIZE
    mul     x1, x0, x1
    add     x1, x24, x1

    // Check if connected
    ldrb    w2, [x1, #BT_PEER_FLAGS]
    tst     w2, #BT_PEER_FLAG_CONNECTED
    b.eq    .Lbt_send_all_next

    // Get fd and send
    ldr     w3, [x1, #BT_PEER_FD]
    cmp     w3, #0
    b.lt    .Lbt_send_all_next

    stp     x0, x1, [sp, #-16]!

    mov     w0, w3
    mov     x1, x22
    mov     x2, x23
    mov     x8, #SYS_write
    svc     #0

    ldp     x0, x1, [sp], #16

.Lbt_send_all_next:
    add     w0, w0, #1
    b       .Lbt_send_all_loop

.Lbt_send_one:
    // Send to specific peer
    sub     x0, x19, #1                 // Convert to 0-based index
    adrp    x1, bt_peer_count
    add     x1, x1, :lo12:bt_peer_count
    ldr     w1, [x1]
    cmp     x0, x1
    b.ge    .Lbt_send_no_peer

    // Get peer fd
    mov     x1, #BT_PEER_SIZE
    mul     x1, x0, x1
    adrp    x2, bt_peers
    add     x2, x2, :lo12:bt_peers
    add     x2, x2, x1

    ldr     w0, [x2, #BT_PEER_FD]
    cmp     w0, #0
    b.lt    .Lbt_send_not_connected

    mov     x1, x22
    mov     x2, x23
    mov     x8, #SYS_write
    svc     #0
    cmp     x0, #0
    b.lt    .Lbt_send_fail

.Lbt_send_done:
    // Update stats
    adrp    x0, bt_tx_count
    add     x0, x0, :lo12:bt_tx_count
    ldr     w1, [x0]
    add     w1, w1, #1
    str     w1, [x0]

    mov     x0, x21
    b       .Lbt_send_ret

.Lbt_send_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    b       .Lbt_send_ret

.Lbt_send_too_large:
    mov     x0, #TRANSPORT_ERR_INVALID
    b       .Lbt_send_ret

.Lbt_send_no_peer:
    mov     x0, #TRANSPORT_ERR_NO_PEER
    b       .Lbt_send_ret

.Lbt_send_not_connected:
    mov     x0, #TRANSPORT_ERR_DISCONNECTED
    b       .Lbt_send_ret

.Lbt_send_fail:
    mov     x0, #-5                     // EIO

.Lbt_send_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size bt_send, .-bt_send

// =============================================================================
// bt_recv - Receive data via Bluetooth
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = buffer length
//   x2 = timeout in milliseconds
// Output:
//   x0 = bytes received, negative on error
//   x1 = peer_id (1-based index of sender)
// =============================================================================
.global bt_recv
.type bt_recv, %function
bt_recv:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // out buffer
    mov     x20, x1                     // buffer length
    mov     x21, x2                     // timeout

    // Check configured
    adrp    x0, bt_configured
    add     x0, x0, :lo12:bt_configured
    ldr     w0, [x0]
    cbz     w0, .Lbt_recv_not_init

    // First, try to accept new connections
    adrp    x0, bt_listen_fd
    add     x0, x0, :lo12:bt_listen_fd
    ldr     w22, [x0]
    cmp     w22, #0
    b.lt    .Lbt_recv_check_peers

    // Try non-blocking accept
    mov     w0, w22
    mov     x1, #0                      // Don't need peer addr
    mov     x2, #0
    mov     x8, #SYS_accept
    svc     #0

    cmp     x0, #0
    b.lt    .Lbt_recv_check_peers

    // Got new connection - add to peer list
    mov     w23, w0                     // New socket fd
    bl      bt_add_peer

.Lbt_recv_check_peers:
    // Try to read from each connected peer
    adrp    x24, bt_peers
    add     x24, x24, :lo12:bt_peers

    adrp    x0, bt_peer_count
    add     x0, x0, :lo12:bt_peer_count
    ldr     w22, [x0]
    mov     w23, #0                     // peer index

.Lbt_recv_peer_loop:
    cmp     w23, w22
    b.ge    .Lbt_recv_no_data

    // Get peer entry
    mov     x0, #BT_PEER_SIZE
    mul     x0, x23, x0
    add     x0, x24, x0

    // Check if connected
    ldrb    w1, [x0, #BT_PEER_FLAGS]
    tst     w1, #BT_PEER_FLAG_CONNECTED
    b.eq    .Lbt_recv_next_peer

    // Try to read
    ldr     w0, [x0, #BT_PEER_FD]
    cmp     w0, #0
    b.lt    .Lbt_recv_next_peer

    adrp    x1, bt_rx_buffer
    add     x1, x1, :lo12:bt_rx_buffer
    mov     x2, #BT_MAX_PAYLOAD
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #0
    b.le    .Lbt_recv_next_peer

    // Got data - process frame
    mov     x21, x0                     // bytes read
    adrp    x0, bt_rx_buffer
    add     x0, x0, :lo12:bt_rx_buffer
    mov     x1, x19                     // output buffer
    mov     x2, x20                     // output length
    bl      bt_process_frame

    cmp     x0, #0
    b.le    .Lbt_recv_next_peer

    // Success - return with peer_id
    add     w1, w23, #1                 // 1-based peer_id

    // Update stats
    adrp    x2, bt_rx_count
    add     x2, x2, :lo12:bt_rx_count
    ldr     w3, [x2]
    add     w3, w3, #1
    str     w3, [x2]

    b       .Lbt_recv_ret

.Lbt_recv_next_peer:
    add     w23, w23, #1
    b       .Lbt_recv_peer_loop

.Lbt_recv_no_data:
    mov     x0, #TRANSPORT_ERR_TIMEOUT
    mov     x1, #0
    b       .Lbt_recv_ret

.Lbt_recv_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    mov     x1, #0

.Lbt_recv_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size bt_recv, .-bt_recv

// =============================================================================
// bt_process_frame - Process received frame and extract payload
// =============================================================================
// Input:
//   x0 = frame buffer
//   x1 = output buffer
//   x2 = output max length
// Output:
//   x0 = payload length, negative on error
// =============================================================================
bt_process_frame:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // frame
    mov     x20, x1                     // output
    mov     x21, x2                     // max length

    // Check sync bytes
    ldrb    w0, [x19, #0]
    cmp     w0, #SERIAL_SYNC_BYTE1
    b.ne    .Lprocess_frame_error

    ldrb    w0, [x19, #1]
    cmp     w0, #SERIAL_SYNC_BYTE2
    b.ne    .Lprocess_frame_error

    // Get length
    ldrb    w0, [x19, #2]
    ldrb    w1, [x19, #3]
    lsl     w1, w1, #8
    orr     w22, w0, w1                 // Payload length

    // Verify CRC
    add     x0, x19, #2
    add     w1, w22, #2
    bl      serial_crc16
    mov     w1, w0                      // Calculated CRC

    // Get stored CRC
    add     x0, x19, #4
    add     x0, x0, x22
    ldrb    w2, [x0, #0]
    ldrb    w3, [x0, #1]
    lsl     w3, w3, #8
    orr     w2, w2, w3

    cmp     w1, w2
    b.ne    .Lprocess_frame_crc_error

    // Copy payload
    cmp     w22, w21
    b.gt    .Lprocess_frame_error

    mov     x0, x20
    add     x1, x19, #4
    mov     w2, w22
    bl      bt_memcpy

    mov     x0, x22
    b       .Lprocess_frame_ret

.Lprocess_frame_error:
    mov     x0, #TRANSPORT_ERR_FRAME
    b       .Lprocess_frame_ret

.Lprocess_frame_crc_error:
    adrp    x0, bt_rx_errors
    add     x0, x0, :lo12:bt_rx_errors
    ldr     w1, [x0]
    add     w1, w1, #1
    str     w1, [x0]
    mov     x0, #TRANSPORT_ERR_CRC

.Lprocess_frame_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size bt_process_frame, .-bt_process_frame

// =============================================================================
// bt_add_peer - Add new peer to peer list
// =============================================================================
// Input:
//   w0 = socket fd
// Output:
//   x0 = peer_id (1-based), or negative on error
// =============================================================================
bt_add_peer:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     w19, w0                     // socket fd

    // Check if room for more peers
    adrp    x0, bt_peer_count
    add     x0, x0, :lo12:bt_peer_count
    ldr     w1, [x0]
    cmp     w1, #BT_MAX_PEERS
    b.ge    .Lbt_add_peer_full

    // Get peer entry
    mov     x2, #BT_PEER_SIZE
    mul     x2, x1, x2
    adrp    x3, bt_peers
    add     x3, x3, :lo12:bt_peers
    add     x3, x3, x2

    // Clear entry
    mov     x4, #0
    str     x4, [x3, #0]
    str     x4, [x3, #8]
    str     x4, [x3, #16]
    str     x4, [x3, #24]

    // Set fd
    str     w19, [x3, #BT_PEER_FD]

    // Set flags
    mov     w4, #BT_PEER_FLAG_CONNECTED
    strb    w4, [x3, #BT_PEER_FLAGS]

    // Set initial quality
    mov     w4, #50
    str     w4, [x3, #BT_PEER_QUALITY]

    // Increment count
    add     w1, w1, #1
    str     w1, [x0]

    // Return 1-based peer_id
    mov     x0, x1
    b       .Lbt_add_peer_ret

.Lbt_add_peer_full:
    // Close socket since we can't track it
    mov     w0, w19
    mov     x8, #SYS_close
    svc     #0
    mov     x0, #TRANSPORT_ERR_FULL

.Lbt_add_peer_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size bt_add_peer, .-bt_add_peer

// =============================================================================
// bt_get_peers - Get list of connected peers
// =============================================================================
// Input:
//   x0 = buffer for peer list
//   x1 = max peers
// Output:
//   x0 = peer count
// =============================================================================
.global bt_get_peers
.type bt_get_peers, %function
bt_get_peers:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // output buffer
    mov     x20, x1                     // max peers

    adrp    x0, bt_peer_count
    add     x0, x0, :lo12:bt_peer_count
    ldr     w0, [x0]

    // Return min(peer_count, max_peers)
    cmp     w0, w20
    csel    w0, w0, w20, lt

    // TODO: Copy peer info to output buffer if needed

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size bt_get_peers, .-bt_get_peers

// =============================================================================
// bt_get_quality - Get link quality for a peer
// =============================================================================
// Input:
//   x0 = peer_id (1-based)
// Output:
//   x0 = quality 0-100, -1 if unknown
// =============================================================================
.global bt_get_quality
.type bt_get_quality, %function
bt_get_quality:
    cbz     x0, .Lbt_quality_unknown

    sub     x0, x0, #1                  // Convert to 0-based

    adrp    x1, bt_peer_count
    add     x1, x1, :lo12:bt_peer_count
    ldr     w1, [x1]
    cmp     x0, x1
    b.ge    .Lbt_quality_unknown

    // Get quality from peer entry
    mov     x1, #BT_PEER_SIZE
    mul     x1, x0, x1
    adrp    x2, bt_peers
    add     x2, x2, :lo12:bt_peers
    add     x2, x2, x1

    ldr     w0, [x2, #BT_PEER_QUALITY]
    ret

.Lbt_quality_unknown:
    mov     x0, #-1
    ret
.size bt_get_quality, .-bt_get_quality

// =============================================================================
// Helper: bt_memcpy
// =============================================================================
bt_memcpy:
    cbz     x2, .Lbt_memcpy_done
.Lbt_memcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    subs    x2, x2, #1
    b.ne    .Lbt_memcpy_loop
.Lbt_memcpy_done:
    ret
