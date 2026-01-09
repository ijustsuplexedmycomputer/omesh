// =============================================================================
// WiFi Mesh Transport Implementation (802.11s)
// =============================================================================
//
// 802.11s kernel-level WiFi mesh networking transport.
// The kernel handles mesh routing - we use TCP/UDP on the mesh interface.
//
// Features:
// - Uses existing TCP or UDP transport on mesh interface
// - Monitors mesh peer status via /sys or netlink
// - Provides mesh-specific link quality from signal strength
//
// Setup (requires root):
//   iw dev wlan0 interface add mesh0 type mp
//   iw dev mesh0 mesh join omesh-mesh
//   ip link set mesh0 up
//   ip addr add 192.168.77.1/24 dev mesh0
//
// Note: Mesh interface must be created externally (by root/sudo).
// This transport uses the interface once it exists.
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/transport.inc"

// WiFi Mesh constants
.equ WIFI_MESH_MAX_PEERS,   32
.equ WIFI_MESH_PEER_SIZE,   48          // [6] MAC + [4] IP + [4] signal + [4] quality + [8] rx_bytes + [8] tx_bytes + [8] last_seen + [6] pad
.equ WIFI_MESH_MAX_PAYLOAD, 1400        // Leave room for mesh headers

// Peer structure offsets
.equ WMESH_PEER_MAC,        0           // [6] MAC address
.equ WMESH_PEER_IP,         6           // [4] IP address (from ARP)
.equ WMESH_PEER_SIGNAL,     10          // [4] Signal strength (dBm)
.equ WMESH_PEER_QUALITY,    14          // [4] Link quality (0-100)
.equ WMESH_PEER_RX_BYTES,   18          // [8] Bytes received
.equ WMESH_PEER_TX_BYTES,   26          // [8] Bytes sent
.equ WMESH_PEER_LAST_SEEN,  34          // [8] Timestamp
.equ WMESH_PEER_FLAGS,      42          // [2] Flags
.equ WMESH_PEER_PAD,        44          // [4] Padding

// Peer flags
.equ WMESH_PEER_FLAG_ACTIVE,    0x01
.equ WMESH_PEER_FLAG_CONNECTED, 0x02
.equ WMESH_PEER_FLAG_MPATH,     0x04    // Has mesh path

// Default mesh configuration
.equ WIFI_MESH_DEFAULT_PORT,    9100
.equ WIFI_MESH_CHANNEL_DEFAULT, 6

// =============================================================================
// Data Section
// =============================================================================

.data

// Transport vtable
.global wifi_mesh_transport_ops
.align 3
wifi_mesh_transport_ops:
    .quad   wifi_mesh_init
    .quad   wifi_mesh_shutdown
    .quad   wifi_mesh_send
    .quad   wifi_mesh_recv
    .quad   wifi_mesh_get_peers
    .quad   wifi_mesh_get_quality

// State
.align 3
wmesh_socket_fd:
    .word   -1                          // UDP socket on mesh interface
wmesh_configured:
    .word   0
wmesh_port:
    .word   WIFI_MESH_DEFAULT_PORT

// Interface name
wmesh_interface:
    .skip   16                          // Interface name (e.g., "mesh0")

// Mesh ID
wmesh_mesh_id:
    .skip   32                          // Mesh network ID

// Peer tracking
.align 3
wmesh_peers:
    .skip   WIFI_MESH_MAX_PEERS * WIFI_MESH_PEER_SIZE
wmesh_peer_count:
    .word   0

// Buffers (use UDP framing)
.align 4
wmesh_rx_buffer:
    .skip   WIFI_MESH_MAX_PAYLOAD + SERIAL_FRAME_OVERHEAD
wmesh_tx_buffer:
    .skip   WIFI_MESH_MAX_PAYLOAD + SERIAL_FRAME_OVERHEAD

// Statistics
wmesh_tx_count:
    .word   0
wmesh_rx_count:
    .word   0
wmesh_tx_bytes:
    .quad   0
wmesh_rx_bytes:
    .quad   0

// Path for reading mesh stations
mesh_stations_path_prefix:
    .asciz  "/sys/kernel/debug/ieee80211/"
mesh_stations_path_suffix:
    .asciz  "/netdev:"
mesh_stations_suffix:
    .asciz  "/stations"

default_interface:
    .asciz  "mesh0"
default_mesh_id:
    .asciz  "omesh-mesh"

.text

// =============================================================================
// wifi_mesh_transport_register - Register WiFi Mesh transport
// =============================================================================
.global wifi_mesh_transport_register
.type wifi_mesh_transport_register, %function
wifi_mesh_transport_register:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     w0, #TRANSPORT_WIFI_MESH
    adrp    x1, wifi_mesh_transport_ops
    add     x1, x1, :lo12:wifi_mesh_transport_ops
    bl      transport_register

    ldp     x29, x30, [sp], #16
    ret
.size wifi_mesh_transport_register, .-wifi_mesh_transport_register

// =============================================================================
// wifi_mesh_init - Initialize WiFi Mesh transport
// =============================================================================
// Input:
//   x0 = config pointer (TRANSPORT_CFG_*)
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================
.global wifi_mesh_init
.type wifi_mesh_init, %function
wifi_mesh_init:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save config

    // Copy interface name from config or use default
    adrp    x20, wmesh_interface
    add     x20, x20, :lo12:wmesh_interface

    add     x1, x19, #TRANSPORT_CFG_DEVICE
    ldrb    w0, [x1]
    cbz     w0, .Lwmesh_use_default_if

    // Copy from config
    mov     x0, x20
    mov     x2, #15
    bl      wmesh_strncpy
    b       .Lwmesh_check_interface

.Lwmesh_use_default_if:
    // Use default "mesh0"
    mov     x0, x20
    adrp    x1, default_interface
    add     x1, x1, :lo12:default_interface
    mov     x2, #15
    bl      wmesh_strncpy

.Lwmesh_check_interface:
    // Check if mesh interface exists by trying to get its index
    mov     w0, #AF_INET
    mov     w1, #2                      // SOCK_DGRAM
    mov     w2, #0
    mov     x8, #SYS_socket
    svc     #0
    cmp     x0, #0
    b.lt    .Lwmesh_init_fail

    mov     w21, w0                     // temp socket

    // Use ioctl SIOCGIFINDEX to check interface exists
    // For simplicity, we'll just try to create the UDP socket and bind

    mov     w0, w21
    mov     x8, #SYS_close
    svc     #0

    // Create UDP socket
    mov     w0, #AF_INET
    mov     w1, #2                      // SOCK_DGRAM
    mov     w2, #0                      // IPPROTO_UDP
    mov     x8, #SYS_socket
    svc     #0
    cmp     x0, #0
    b.lt    .Lwmesh_init_fail

    mov     w21, w0                     // UDP socket

    // Enable broadcast
    sub     sp, sp, #16
    mov     w0, #1
    str     w0, [sp]

    mov     w0, w21
    mov     w1, #1                      // SOL_SOCKET
    mov     w2, #6                      // SO_BROADCAST
    mov     x3, sp
    mov     w4, #4
    mov     x8, #SYS_setsockopt
    svc     #0

    // Get port from config
    ldr     w22, [x19, #TRANSPORT_CFG_PORT]
    cbz     w22, .Lwmesh_use_default_port
    b       .Lwmesh_bind

.Lwmesh_use_default_port:
    mov     w22, #WIFI_MESH_DEFAULT_PORT

.Lwmesh_bind:
    // Save port
    adrp    x0, wmesh_port
    add     x0, x0, :lo12:wmesh_port
    str     w22, [x0]

    // Build sockaddr_in
    mov     x0, sp
    str     xzr, [x0]
    str     xzr, [x0, #8]

    mov     w1, #AF_INET
    strh    w1, [x0]                    // sin_family

    // Port in network byte order (big endian)
    and     w1, w22, #0xFF
    lsl     w1, w1, #8
    lsr     w2, w22, #8
    orr     w1, w1, w2
    strh    w1, [x0, #2]                // sin_port

    // INADDR_ANY = 0
    str     wzr, [x0, #4]               // sin_addr

    // Bind
    mov     w0, w21
    mov     x1, sp
    mov     w2, #16
    mov     x8, #SYS_bind
    svc     #0

    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Lwmesh_init_bind_fail

    // Make socket non-blocking
    mov     w0, w21
    mov     w1, #3                      // F_GETFL
    mov     x2, #0
    mov     x8, #SYS_fcntl
    svc     #0
    mov     w22, w0

    mov     w0, w21
    mov     w1, #4                      // F_SETFL
    orr     w2, w22, #0x800             // O_NONBLOCK
    mov     x8, #SYS_fcntl
    svc     #0

    // Save socket fd
    adrp    x0, wmesh_socket_fd
    add     x0, x0, :lo12:wmesh_socket_fd
    str     w21, [x0]

    // Mark configured
    adrp    x0, wmesh_configured
    add     x0, x0, :lo12:wmesh_configured
    mov     w1, #1
    str     w1, [x0]

    // Clear peer list
    adrp    x0, wmesh_peer_count
    add     x0, x0, :lo12:wmesh_peer_count
    str     wzr, [x0]

    // Clear stats
    adrp    x0, wmesh_tx_count
    add     x0, x0, :lo12:wmesh_tx_count
    str     wzr, [x0]
    adrp    x0, wmesh_rx_count
    add     x0, x0, :lo12:wmesh_rx_count
    str     wzr, [x0]
    adrp    x0, wmesh_tx_bytes
    add     x0, x0, :lo12:wmesh_tx_bytes
    str     xzr, [x0]
    adrp    x0, wmesh_rx_bytes
    add     x0, x0, :lo12:wmesh_rx_bytes
    str     xzr, [x0]

    // Scan for mesh peers (initial)
    bl      wifi_mesh_scan_peers

    mov     x0, #0
    b       .Lwmesh_init_ret

.Lwmesh_init_bind_fail:
    mov     w0, w21
    mov     x8, #SYS_close
    svc     #0
    mov     x0, #-98                    // EADDRINUSE
    b       .Lwmesh_init_ret

.Lwmesh_init_fail:
    // x0 has error

.Lwmesh_init_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size wifi_mesh_init, .-wifi_mesh_init

// =============================================================================
// wifi_mesh_shutdown - Shutdown WiFi Mesh transport
// =============================================================================
.global wifi_mesh_shutdown
.type wifi_mesh_shutdown, %function
wifi_mesh_shutdown:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Close socket
    adrp    x0, wmesh_socket_fd
    add     x0, x0, :lo12:wmesh_socket_fd
    ldr     w0, [x0]
    cmp     w0, #0
    b.lt    .Lwmesh_shutdown_done

    mov     x8, #SYS_close
    svc     #0

    adrp    x0, wmesh_socket_fd
    add     x0, x0, :lo12:wmesh_socket_fd
    mov     w1, #-1
    str     w1, [x0]

.Lwmesh_shutdown_done:
    // Clear configured
    adrp    x0, wmesh_configured
    add     x0, x0, :lo12:wmesh_configured
    str     wzr, [x0]

    ldp     x29, x30, [sp], #16
    ret
.size wifi_mesh_shutdown, .-wifi_mesh_shutdown

// =============================================================================
// wifi_mesh_send - Send data via WiFi Mesh
// =============================================================================
// Input:
//   x0 = peer_id (0 = broadcast)
//   x1 = data pointer
//   x2 = data length
// Output:
//   x0 = bytes sent, negative on error
// =============================================================================
.global wifi_mesh_send
.type wifi_mesh_send, %function
wifi_mesh_send:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // peer_id
    mov     x20, x1                     // data
    mov     x21, x2                     // length

    // Check configured
    adrp    x0, wmesh_configured
    add     x0, x0, :lo12:wmesh_configured
    ldr     w0, [x0]
    cbz     w0, .Lwmesh_send_not_init

    // Check length
    cmp     x21, #WIFI_MESH_MAX_PAYLOAD
    b.gt    .Lwmesh_send_too_large

    // Build framed message (same as UDP)
    adrp    x22, wmesh_tx_buffer
    add     x22, x22, :lo12:wmesh_tx_buffer

    // Sync bytes
    mov     w0, #SERIAL_SYNC_BYTE1
    strb    w0, [x22, #0]
    mov     w0, #SERIAL_SYNC_BYTE2
    strb    w0, [x22, #1]

    // Length
    and     w0, w21, #0xFF
    strb    w0, [x22, #2]
    lsr     w0, w21, #8
    strb    w0, [x22, #3]

    // Copy payload
    mov     x0, x22
    add     x0, x0, #4
    mov     x1, x20
    mov     x2, x21
    bl      wmesh_memcpy

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

    // Get socket fd
    adrp    x0, wmesh_socket_fd
    add     x0, x0, :lo12:wmesh_socket_fd
    ldr     w24, [x0]

    // Build destination address
    sub     sp, sp, #16
    str     xzr, [sp]
    str     xzr, [sp, #8]

    mov     w0, #AF_INET
    strh    w0, [sp]

    // Port in network byte order
    adrp    x0, wmesh_port
    add     x0, x0, :lo12:wmesh_port
    ldr     w0, [x0]
    and     w1, w0, #0xFF
    lsl     w1, w1, #8
    lsr     w2, w0, #8
    orr     w1, w1, w2
    strh    w1, [sp, #2]

    // For broadcast, use 255.255.255.255
    cbz     x19, .Lwmesh_send_broadcast

    // For unicast, look up peer IP
    // For now, just broadcast (TODO: implement peer lookup)

.Lwmesh_send_broadcast:
    mov     w0, #0xFF
    orr     w0, w0, w0, lsl #8
    orr     w0, w0, w0, lsl #16
    str     w0, [sp, #4]                // 255.255.255.255

    // sendto
    mov     w0, w24
    mov     x1, x22
    mov     x2, x23
    mov     w3, #0                      // flags
    mov     x4, sp
    mov     w5, #16
    mov     x8, #SYS_sendto
    svc     #0

    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Lwmesh_send_fail

    // Update stats
    adrp    x1, wmesh_tx_count
    add     x1, x1, :lo12:wmesh_tx_count
    ldr     w2, [x1]
    add     w2, w2, #1
    str     w2, [x1]

    adrp    x1, wmesh_tx_bytes
    add     x1, x1, :lo12:wmesh_tx_bytes
    ldr     x2, [x1]
    add     x2, x2, x21
    str     x2, [x1]

    mov     x0, x21
    b       .Lwmesh_send_ret

.Lwmesh_send_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    b       .Lwmesh_send_ret

.Lwmesh_send_too_large:
    mov     x0, #TRANSPORT_ERR_INVALID
    b       .Lwmesh_send_ret

.Lwmesh_send_fail:
    mov     x0, #-5                     // EIO

.Lwmesh_send_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size wifi_mesh_send, .-wifi_mesh_send

// =============================================================================
// wifi_mesh_recv - Receive data via WiFi Mesh
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = buffer length
//   x2 = timeout in milliseconds
// Output:
//   x0 = bytes received, negative on error
//   x1 = peer_id (0 for unknown)
// =============================================================================
.global wifi_mesh_recv
.type wifi_mesh_recv, %function
wifi_mesh_recv:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // out buffer
    mov     x20, x1                     // buffer length
    mov     x21, x2                     // timeout

    // Check configured
    adrp    x0, wmesh_configured
    add     x0, x0, :lo12:wmesh_configured
    ldr     w0, [x0]
    cbz     w0, .Lwmesh_recv_not_init

    // Get socket fd
    adrp    x0, wmesh_socket_fd
    add     x0, x0, :lo12:wmesh_socket_fd
    ldr     w22, [x0]

    // recvfrom
    sub     sp, sp, #32                 // sockaddr + addrlen

    mov     w0, #16
    str     w0, [sp, #16]               // addrlen

    mov     w0, w22
    adrp    x1, wmesh_rx_buffer
    add     x1, x1, :lo12:wmesh_rx_buffer
    mov     x2, #WIFI_MESH_MAX_PAYLOAD
    mov     w3, #0                      // flags
    mov     x4, sp                      // sockaddr
    add     x5, sp, #16                 // addrlen ptr
    mov     x8, #SYS_recvfrom
    svc     #0

    add     sp, sp, #32

    cmp     x0, #0
    b.le    .Lwmesh_recv_no_data

    mov     x21, x0                     // bytes received

    // Process frame
    adrp    x0, wmesh_rx_buffer
    add     x0, x0, :lo12:wmesh_rx_buffer
    mov     x1, x19
    mov     x2, x20
    bl      wmesh_process_frame
    cmp     x0, #0
    b.le    .Lwmesh_recv_error

    // Update stats
    adrp    x1, wmesh_rx_count
    add     x1, x1, :lo12:wmesh_rx_count
    ldr     w2, [x1]
    add     w2, w2, #1
    str     w2, [x1]

    adrp    x1, wmesh_rx_bytes
    add     x1, x1, :lo12:wmesh_rx_bytes
    ldr     x2, [x1]
    add     x2, x2, x0
    str     x2, [x1]

    mov     x1, #0                      // peer_id = 0 (TODO: look up from source IP)
    b       .Lwmesh_recv_ret

.Lwmesh_recv_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    mov     x1, #0
    b       .Lwmesh_recv_ret

.Lwmesh_recv_no_data:
    mov     x0, #TRANSPORT_ERR_TIMEOUT
    mov     x1, #0
    b       .Lwmesh_recv_ret

.Lwmesh_recv_error:
    mov     x1, #0

.Lwmesh_recv_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size wifi_mesh_recv, .-wifi_mesh_recv

// =============================================================================
// wmesh_process_frame - Process received frame
// =============================================================================
// Input:
//   x0 = frame buffer
//   x1 = output buffer
//   x2 = output max length
// Output:
//   x0 = payload length, negative on error
// =============================================================================
wmesh_process_frame:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0
    mov     x20, x1
    mov     x21, x2

    // Check sync bytes
    ldrb    w0, [x19, #0]
    cmp     w0, #SERIAL_SYNC_BYTE1
    b.ne    .Lwmesh_process_error

    ldrb    w0, [x19, #1]
    cmp     w0, #SERIAL_SYNC_BYTE2
    b.ne    .Lwmesh_process_error

    // Get length
    ldrb    w0, [x19, #2]
    ldrb    w1, [x19, #3]
    lsl     w1, w1, #8
    orr     w22, w0, w1

    // Verify CRC
    add     x0, x19, #2
    add     w1, w22, #2
    bl      serial_crc16
    mov     w1, w0

    add     x0, x19, #4
    add     x0, x0, x22
    ldrb    w2, [x0, #0]
    ldrb    w3, [x0, #1]
    lsl     w3, w3, #8
    orr     w2, w2, w3

    cmp     w1, w2
    b.ne    .Lwmesh_process_crc_error

    // Copy payload
    cmp     w22, w21
    b.gt    .Lwmesh_process_error

    mov     x0, x20
    add     x1, x19, #4
    mov     w2, w22
    bl      wmesh_memcpy

    mov     x0, x22
    b       .Lwmesh_process_ret

.Lwmesh_process_error:
    mov     x0, #TRANSPORT_ERR_FRAME
    b       .Lwmesh_process_ret

.Lwmesh_process_crc_error:
    mov     x0, #TRANSPORT_ERR_CRC

.Lwmesh_process_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size wmesh_process_frame, .-wmesh_process_frame

// =============================================================================
// wifi_mesh_scan_peers - Scan for mesh peers from sysfs
// =============================================================================
wifi_mesh_scan_peers:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // TODO: Read /sys/kernel/debug/ieee80211/.../stations/
    // For now, just return (peers discovered via received packets)

    ldp     x29, x30, [sp], #16
    ret
.size wifi_mesh_scan_peers, .-wifi_mesh_scan_peers

// =============================================================================
// wifi_mesh_get_peers - Get list of mesh peers
// =============================================================================
// Input:
//   x0 = buffer for peer list
//   x1 = max peers
// Output:
//   x0 = peer count
// =============================================================================
.global wifi_mesh_get_peers
.type wifi_mesh_get_peers, %function
wifi_mesh_get_peers:
    adrp    x0, wmesh_peer_count
    add     x0, x0, :lo12:wmesh_peer_count
    ldr     w0, [x0]

    cmp     w0, w1
    csel    w0, w0, w1, lt
    ret
.size wifi_mesh_get_peers, .-wifi_mesh_get_peers

// =============================================================================
// wifi_mesh_get_quality - Get link quality
// =============================================================================
// Input:
//   x0 = peer_id
// Output:
//   x0 = quality 0-100, -1 if unknown
// =============================================================================
.global wifi_mesh_get_quality
.type wifi_mesh_get_quality, %function
wifi_mesh_get_quality:
    // Calculate quality from packet stats
    adrp    x0, wmesh_rx_count
    add     x0, x0, :lo12:wmesh_rx_count
    ldr     w1, [x0]

    adrp    x0, wmesh_tx_count
    add     x0, x0, :lo12:wmesh_tx_count
    ldr     w2, [x0]

    add     w3, w1, w2
    cbz     w3, .Lwmesh_quality_unknown

    // For now, return 80 if we have traffic, 50 otherwise
    cmp     w3, #10
    b.lt    .Lwmesh_quality_low
    mov     x0, #80
    ret

.Lwmesh_quality_low:
    mov     x0, #50
    ret

.Lwmesh_quality_unknown:
    mov     x0, #-1
    ret
.size wifi_mesh_get_quality, .-wifi_mesh_get_quality

// =============================================================================
// Helper functions
// =============================================================================

// wmesh_memcpy
wmesh_memcpy:
    cbz     x2, .Lwmesh_memcpy_done
.Lwmesh_memcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    subs    x2, x2, #1
    b.ne    .Lwmesh_memcpy_loop
.Lwmesh_memcpy_done:
    ret

// wmesh_strncpy
wmesh_strncpy:
    mov     x3, x0
.Lwmesh_strncpy_loop:
    cbz     x2, .Lwmesh_strncpy_done
    ldrb    w4, [x1], #1
    strb    w4, [x0], #1
    cbz     w4, .Lwmesh_strncpy_ret
    sub     x2, x2, #1
    b       .Lwmesh_strncpy_loop
.Lwmesh_strncpy_done:
    strb    wzr, [x0]
.Lwmesh_strncpy_ret:
    mov     x0, x3
    ret
