// =============================================================================
// LoRa Transport Implementation
// =============================================================================
//
// Long-range, low-power transport using LoRa radio modules.
// Supports RAK811-style AT command interface over UART.
//
// Features:
// - AT command configuration for LoRa parameters
// - Message framing with CRC (same as serial transport)
// - Spreading factor selection (SF7-SF12)
// - Frequency band selection (US915, EU868, AS923)
// - Peer discovery via broadcast
//
// Frame format (same as serial):
//   [0xAA][0x55][LEN_LO][LEN_HI][PAYLOAD...][CRC_LO][CRC_HI]
//
// LoRa AT Commands (RAK811 style):
//   AT+MODE=P2P          - Set peer-to-peer mode
//   AT+BAND=<band>       - Set frequency band
//   AT+SF=<sf>           - Set spreading factor
//   AT+POWER=<dbm>       - Set TX power
//   AT+SEND=<hex>        - Send data
//   +RCV=<hex>           - Received data notification
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/transport.inc"

// LoRa-specific constants
.equ LORA_MAX_PAYLOAD,      255         // Max LoRa payload (single packet)
.equ LORA_AT_TIMEOUT,       2000        // AT command response timeout (ms)
.equ LORA_RX_TIMEOUT,       100         // Receive poll timeout (ms)

// LoRa bands
.equ LORA_BAND_US915,       0
.equ LORA_BAND_EU868,       1
.equ LORA_BAND_AS923,       2
.equ LORA_BAND_AU915,       3
.equ LORA_BAND_IN865,       4

// LoRa spreading factors
.equ LORA_SF_MIN,           7
.equ LORA_SF_MAX,           12
.equ LORA_SF_DEFAULT,       7

// LoRa power levels
.equ LORA_POWER_MIN,        2
.equ LORA_POWER_MAX,        20
.equ LORA_POWER_DEFAULT,    14

// AT command parsing states
.equ LORA_STATE_IDLE,       0
.equ LORA_STATE_CMD,        1
.equ LORA_STATE_DATA,       2

// LoRa peer tracking
.equ LORA_MAX_PEERS,        16
.equ LORA_PEER_SIZE,        24          // [8] ID + [4] RSSI + [4] SNR + [8] last_seen

// =============================================================================
// Data Section
// =============================================================================

.data

// Transport vtable
.global lora_transport_ops
.align 3
lora_transport_ops:
    .quad   lora_init
    .quad   lora_shutdown
    .quad   lora_send
    .quad   lora_recv
    .quad   lora_get_peers
    .quad   lora_get_quality

// State variables
.align 3
lora_fd:
    .word   -1                          // Serial file descriptor
lora_configured:
    .word   0                           // Configuration complete flag

// Configuration
lora_band:
    .word   LORA_BAND_US915             // Frequency band
lora_sf:
    .word   LORA_SF_DEFAULT             // Spreading factor
lora_power:
    .word   LORA_POWER_DEFAULT          // TX power (dBm)

// Frame state machine (reuse serial protocol)
lora_rx_state:
    .word   SERIAL_STATE_SYNC1
lora_rx_length:
    .word   0
lora_rx_pos:
    .word   0
lora_rx_crc:
    .word   0

// Buffers
.align 4
lora_rx_buffer:
    .skip   LORA_MAX_PAYLOAD + SERIAL_FRAME_OVERHEAD
lora_tx_buffer:
    .skip   LORA_MAX_PAYLOAD + SERIAL_FRAME_OVERHEAD
lora_at_buffer:
    .skip   256                         // AT command buffer
lora_at_response:
    .skip   256                         // AT response buffer

// Peer tracking
.align 3
lora_peers:
    .skip   LORA_MAX_PEERS * LORA_PEER_SIZE
lora_peer_count:
    .word   0

// Packet statistics
lora_tx_count:
    .word   0
lora_rx_count:
    .word   0
lora_rx_errors:
    .word   0

// AT command strings
at_mode_p2p:
    .asciz  "AT+MODE=P2P\r\n"
at_band_us915:
    .asciz  "AT+BAND=US915\r\n"
at_band_eu868:
    .asciz  "AT+BAND=EU868\r\n"
at_band_as923:
    .asciz  "AT+BAND=AS923\r\n"
at_sf_prefix:
    .asciz  "AT+SF="
at_power_prefix:
    .asciz  "AT+POWER="
at_send_prefix:
    .asciz  "AT+SEND="
at_crlf:
    .asciz  "\r\n"
at_ok:
    .asciz  "OK"
at_error:
    .asciz  "ERROR"
rcv_prefix:
    .asciz  "+RCV="

.text

// =============================================================================
// lora_transport_register - Register LoRa transport with transport manager
// =============================================================================
// Output:
//   x0 = 0 on success
// =============================================================================
.global lora_transport_register
.type lora_transport_register, %function
lora_transport_register:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Register with transport manager
    mov     w0, #TRANSPORT_LORA
    adrp    x1, lora_transport_ops
    add     x1, x1, :lo12:lora_transport_ops
    bl      transport_register

    ldp     x29, x30, [sp], #16
    ret
.size lora_transport_register, .-lora_transport_register

// =============================================================================
// lora_init - Initialize LoRa transport
// =============================================================================
// Input:
//   x0 = config pointer (TRANSPORT_CFG_*)
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================
.global lora_init
.type lora_init, %function
lora_init:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save config pointer

    // Extract device path
    add     x20, x19, #TRANSPORT_CFG_DEVICE

    // Check device path is not empty
    ldrb    w0, [x20]
    cbz     w0, .Llora_init_no_device

    // Open serial device
    mov     x0, x20                     // Device path
    mov     w1, #0x0002                 // O_RDWR
    orr     w1, w1, #0x0100             // O_NOCTTY
    orr     w1, w1, #0x0800             // O_NONBLOCK
    mov     x8, #SYS_openat
    mov     x0, #-100                   // AT_FDCWD
    mov     x1, x20
    mov     w2, #0x0002
    orr     w2, w2, #0x0100
    orr     w2, w2, #0x0800
    mov     w3, #0
    svc     #0

    cmp     x0, #0
    b.lt    .Llora_init_fail

    // Save file descriptor
    adrp    x1, lora_fd
    add     x1, x1, :lo12:lora_fd
    str     w0, [x1]
    mov     w21, w0                     // Save fd

    // Configure serial port (115200 8N1)
    mov     w0, w21
    movz    w1, #0xC200                 // 115200 = 0x1C200
    movk    w1, #0x1, lsl #16
    bl      lora_configure_serial
    cmp     x0, #0
    b.lt    .Llora_init_fail_close

    // Wait for module to be ready
    mov     x0, #500                    // 500ms delay
    bl      lora_delay

    // Configure LoRa module via AT commands
    bl      lora_configure_module
    cmp     x0, #0
    b.lt    .Llora_init_fail_close

    // Mark as configured
    adrp    x0, lora_configured
    add     x0, x0, :lo12:lora_configured
    mov     w1, #1
    str     w1, [x0]

    // Clear peer list
    adrp    x0, lora_peer_count
    add     x0, x0, :lo12:lora_peer_count
    str     wzr, [x0]

    // Clear statistics
    adrp    x0, lora_tx_count
    add     x0, x0, :lo12:lora_tx_count
    str     wzr, [x0]
    adrp    x0, lora_rx_count
    add     x0, x0, :lo12:lora_rx_count
    str     wzr, [x0]
    adrp    x0, lora_rx_errors
    add     x0, x0, :lo12:lora_rx_errors
    str     wzr, [x0]

    mov     x0, #0
    b       .Llora_init_ret

.Llora_init_no_device:
    mov     x0, #-22                    // EINVAL
    b       .Llora_init_ret

.Llora_init_fail_close:
    mov     w0, w21
    mov     x8, #SYS_close
    svc     #0
    adrp    x0, lora_fd
    add     x0, x0, :lo12:lora_fd
    mov     w1, #-1
    str     w1, [x0]
    mov     x0, #-5                     // EIO

.Llora_init_fail:
    // x0 already contains error

.Llora_init_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size lora_init, .-lora_init

// =============================================================================
// lora_configure_serial - Configure serial port for LoRa module
// =============================================================================
// Input:
//   w0 = file descriptor
//   w1 = baud rate
// Output:
//   x0 = 0 on success
// =============================================================================
lora_configure_serial:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     w19, w0                     // Save fd

    // Allocate termios structure on stack
    sub     sp, sp, #48

    // Get current settings
    mov     w0, w19
    mov     w1, #TCGETS
    mov     x2, sp
    mov     x8, #SYS_ioctl
    svc     #0
    cmp     x0, #0
    b.lt    .Lconfig_serial_fail

    // Configure for raw mode
    // Clear input flags
    str     wzr, [sp, #TERMIOS_IFLAG]

    // Clear output flags
    str     wzr, [sp, #TERMIOS_OFLAG]

    // Set control flags: CS8, CREAD, CLOCAL
    mov     w0, #CS8
    mov     w1, #CREAD
    orr     w0, w0, w1
    mov     w1, #CLOCAL
    orr     w0, w0, w1
    // Add baud rate (B115200 = 0x1002)
    movz    w1, #0x1002
    orr     w0, w0, w1
    str     w0, [sp, #TERMIOS_CFLAG]

    // Clear local flags (raw mode)
    str     wzr, [sp, #TERMIOS_LFLAG]

    // Set VMIN=1, VTIME=1 (blocking read with 100ms timeout)
    add     x0, sp, #TERMIOS_CC
    mov     w1, #1
    strb    w1, [x0, #VMIN]
    strb    w1, [x0, #VTIME]

    // Apply settings
    mov     w0, w19
    mov     w1, #TCSETSF
    mov     x2, sp
    mov     x8, #SYS_ioctl
    svc     #0

    add     sp, sp, #48
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lconfig_serial_fail:
    add     sp, sp, #48
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size lora_configure_serial, .-lora_configure_serial

// =============================================================================
// lora_configure_module - Configure LoRa module via AT commands
// =============================================================================
// Output:
//   x0 = 0 on success
// =============================================================================
lora_configure_module:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Set P2P mode
    adrp    x0, at_mode_p2p
    add     x0, x0, :lo12:at_mode_p2p
    bl      lora_send_at_command
    cmp     x0, #0
    b.lt    .Lconfig_module_fail

    // Set frequency band
    adrp    x0, lora_band
    add     x0, x0, :lo12:lora_band
    ldr     w0, [x0]

    cmp     w0, #LORA_BAND_EU868
    b.eq    .Lset_band_eu868
    cmp     w0, #LORA_BAND_AS923
    b.eq    .Lset_band_as923

    // Default US915
    adrp    x0, at_band_us915
    add     x0, x0, :lo12:at_band_us915
    b       .Lsend_band

.Lset_band_eu868:
    adrp    x0, at_band_eu868
    add     x0, x0, :lo12:at_band_eu868
    b       .Lsend_band

.Lset_band_as923:
    adrp    x0, at_band_as923
    add     x0, x0, :lo12:at_band_as923

.Lsend_band:
    bl      lora_send_at_command
    cmp     x0, #0
    b.lt    .Lconfig_module_fail

    // Set spreading factor
    adrp    x0, lora_sf
    add     x0, x0, :lo12:lora_sf
    ldr     w19, [x0]

    // Build AT+SF=X command
    adrp    x0, lora_at_buffer
    add     x0, x0, :lo12:lora_at_buffer
    adrp    x1, at_sf_prefix
    add     x1, x1, :lo12:at_sf_prefix
    bl      lora_strcpy

    // Add SF value
    mov     w1, w19
    bl      lora_append_num

    // Add CRLF
    adrp    x1, at_crlf
    add     x1, x1, :lo12:at_crlf
    bl      lora_strcat

    adrp    x0, lora_at_buffer
    add     x0, x0, :lo12:lora_at_buffer
    bl      lora_send_at_command
    cmp     x0, #0
    b.lt    .Lconfig_module_fail

    // Set TX power
    adrp    x0, lora_power
    add     x0, x0, :lo12:lora_power
    ldr     w19, [x0]

    // Build AT+POWER=X command
    adrp    x0, lora_at_buffer
    add     x0, x0, :lo12:lora_at_buffer
    adrp    x1, at_power_prefix
    add     x1, x1, :lo12:at_power_prefix
    bl      lora_strcpy

    mov     w1, w19
    bl      lora_append_num

    adrp    x1, at_crlf
    add     x1, x1, :lo12:at_crlf
    bl      lora_strcat

    adrp    x0, lora_at_buffer
    add     x0, x0, :lo12:lora_at_buffer
    bl      lora_send_at_command

    // Return result
    b       .Lconfig_module_ret

.Lconfig_module_fail:
    mov     x0, #-5                     // EIO

.Lconfig_module_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size lora_configure_module, .-lora_configure_module

// =============================================================================
// lora_send_at_command - Send AT command and wait for response
// =============================================================================
// Input:
//   x0 = command string (null-terminated)
// Output:
//   x0 = 0 on OK, negative on error
// =============================================================================
lora_send_at_command:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save command

    // Get fd
    adrp    x0, lora_fd
    add     x0, x0, :lo12:lora_fd
    ldr     w20, [x0]

    // Calculate command length
    mov     x0, x19
    bl      lora_strlen
    mov     x2, x0

    // Write command
    mov     w0, w20
    mov     x1, x19
    mov     x8, #SYS_write
    svc     #0
    cmp     x0, #0
    b.lt    .Lat_cmd_fail

    // Wait for response
    mov     x0, #LORA_AT_TIMEOUT
    bl      lora_read_response
    cmp     x0, #0
    b.lt    .Lat_cmd_fail

    // Check for OK
    adrp    x0, lora_at_response
    add     x0, x0, :lo12:lora_at_response
    adrp    x1, at_ok
    add     x1, x1, :lo12:at_ok
    bl      lora_strstr
    cbnz    x0, .Lat_cmd_ok

    // Check for ERROR
    adrp    x0, lora_at_response
    add     x0, x0, :lo12:lora_at_response
    adrp    x1, at_error
    add     x1, x1, :lo12:at_error
    bl      lora_strstr
    cbnz    x0, .Lat_cmd_fail

    // No recognized response - assume OK
.Lat_cmd_ok:
    mov     x0, #0
    b       .Lat_cmd_ret

.Lat_cmd_fail:
    mov     x0, #-5                     // EIO

.Lat_cmd_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size lora_send_at_command, .-lora_send_at_command

// =============================================================================
// lora_read_response - Read AT command response
// =============================================================================
// Input:
//   x0 = timeout in milliseconds
// Output:
//   x0 = bytes read, negative on error
// =============================================================================
lora_read_response:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // timeout
    mov     x20, #0                     // bytes read

    adrp    x0, lora_fd
    add     x0, x0, :lo12:lora_fd
    ldr     w0, [x0]

    adrp    x1, lora_at_response
    add     x1, x1, :lo12:lora_at_response

.Lread_resp_loop:
    // Read available data
    adrp    x0, lora_fd
    add     x0, x0, :lo12:lora_fd
    ldr     w0, [x0]
    adrp    x1, lora_at_response
    add     x1, x1, :lo12:lora_at_response
    add     x1, x1, x20
    mov     x2, #255
    sub     x2, x2, x20
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #0
    b.le    .Lread_resp_done

    add     x20, x20, x0

    // Check for newline (end of response)
    adrp    x0, lora_at_response
    add     x0, x0, :lo12:lora_at_response
    add     x0, x0, x20
    sub     x0, x0, #1
    ldrb    w1, [x0]
    cmp     w1, #'\n'
    b.eq    .Lread_resp_done

    // Timeout check would go here (simplified)
    b       .Lread_resp_loop

.Lread_resp_done:
    // Null terminate
    adrp    x0, lora_at_response
    add     x0, x0, :lo12:lora_at_response
    strb    wzr, [x0, x20]

    mov     x0, x20
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size lora_read_response, .-lora_read_response

// =============================================================================
// lora_shutdown - Shutdown LoRa transport
// =============================================================================
.global lora_shutdown
.type lora_shutdown, %function
lora_shutdown:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Close serial port
    adrp    x0, lora_fd
    add     x0, x0, :lo12:lora_fd
    ldr     w0, [x0]
    cmp     w0, #0
    b.lt    .Llora_shutdown_done

    mov     x8, #SYS_close
    svc     #0

    adrp    x0, lora_fd
    add     x0, x0, :lo12:lora_fd
    mov     w1, #-1
    str     w1, [x0]

    // Clear configured flag
    adrp    x0, lora_configured
    add     x0, x0, :lo12:lora_configured
    str     wzr, [x0]

.Llora_shutdown_done:
    ldp     x29, x30, [sp], #16
    ret
.size lora_shutdown, .-lora_shutdown

// =============================================================================
// lora_send - Send data via LoRa
// =============================================================================
// Input:
//   x0 = peer_id (0 = broadcast)
//   x1 = data pointer
//   x2 = data length
// Output:
//   x0 = bytes sent, negative on error
// =============================================================================
.global lora_send
.type lora_send, %function
lora_send:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // peer_id
    mov     x20, x1                     // data
    mov     x21, x2                     // length

    // Check configured
    adrp    x0, lora_configured
    add     x0, x0, :lo12:lora_configured
    ldr     w0, [x0]
    cbz     w0, .Llora_send_not_init

    // Check length
    cmp     x21, #LORA_MAX_PAYLOAD
    b.gt    .Llora_send_too_large

    // Build framed message in tx buffer
    adrp    x22, lora_tx_buffer
    add     x22, x22, :lo12:lora_tx_buffer

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
    bl      lora_memcpy

    // Calculate CRC over length + payload
    add     x0, x22, #2
    add     w1, w21, #2                 // length field + payload
    bl      serial_crc16

    // Store CRC (little endian)
    add     x1, x22, #4
    add     x1, x1, x21
    and     w2, w0, #0xFF
    strb    w2, [x1, #0]
    lsr     w2, w0, #8
    strb    w2, [x1, #1]

    // Build AT+SEND command with hex data
    adrp    x0, lora_at_buffer
    add     x0, x0, :lo12:lora_at_buffer
    adrp    x1, at_send_prefix
    add     x1, x1, :lo12:at_send_prefix
    bl      lora_strcpy

    // Convert frame to hex
    mov     x1, x22
    add     w2, w21, #SERIAL_FRAME_OVERHEAD
    bl      lora_append_hex

    // Add CRLF
    adrp    x1, at_crlf
    add     x1, x1, :lo12:at_crlf
    bl      lora_strcat

    // Send AT command
    adrp    x0, lora_at_buffer
    add     x0, x0, :lo12:lora_at_buffer
    bl      lora_send_at_command
    cmp     x0, #0
    b.lt    .Llora_send_fail

    // Update stats
    adrp    x0, lora_tx_count
    add     x0, x0, :lo12:lora_tx_count
    ldr     w1, [x0]
    add     w1, w1, #1
    str     w1, [x0]

    mov     x0, x21
    b       .Llora_send_ret

.Llora_send_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    b       .Llora_send_ret

.Llora_send_too_large:
    mov     x0, #TRANSPORT_ERR_INVALID
    b       .Llora_send_ret

.Llora_send_fail:
    mov     x0, #-5                     // EIO

.Llora_send_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size lora_send, .-lora_send

// =============================================================================
// lora_recv - Receive data via LoRa
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = buffer length
//   x2 = timeout in milliseconds
// Output:
//   x0 = bytes received, negative on error
//   x1 = peer_id (0 for LoRa since we don't have addressing)
// =============================================================================
.global lora_recv
.type lora_recv, %function
lora_recv:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // out buffer
    mov     x20, x1                     // buffer length
    mov     x21, x2                     // timeout

    // Check configured
    adrp    x0, lora_configured
    add     x0, x0, :lo12:lora_configured
    ldr     w0, [x0]
    cbz     w0, .Llora_recv_not_init

    // Read from serial
    adrp    x0, lora_fd
    add     x0, x0, :lo12:lora_fd
    ldr     w0, [x0]

    adrp    x1, lora_rx_buffer
    add     x1, x1, :lo12:lora_rx_buffer
    mov     x2, #256
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #0
    b.le    .Llora_recv_no_data

    mov     x22, x0                     // bytes read

    // Check for +RCV= prefix (received data notification)
    adrp    x0, lora_rx_buffer
    add     x0, x0, :lo12:lora_rx_buffer
    adrp    x1, rcv_prefix
    add     x1, x1, :lo12:rcv_prefix
    bl      lora_strstr
    cbz     x0, .Llora_recv_no_data

    // Parse hex data after +RCV=
    add     x0, x0, #5                  // Skip "+RCV="
    mov     x1, x19                     // Output buffer
    mov     x2, x20                     // Buffer length
    bl      lora_parse_hex_frame
    cmp     x0, #0
    b.le    .Llora_recv_error

    // Update stats
    adrp    x1, lora_rx_count
    add     x1, x1, :lo12:lora_rx_count
    ldr     w2, [x1]
    add     w2, w2, #1
    str     w2, [x1]

    mov     x1, #0                      // peer_id = 0 (unknown)
    b       .Llora_recv_ret

.Llora_recv_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    mov     x1, #0
    b       .Llora_recv_ret

.Llora_recv_no_data:
    mov     x0, #TRANSPORT_ERR_TIMEOUT
    mov     x1, #0
    b       .Llora_recv_ret

.Llora_recv_error:
    adrp    x1, lora_rx_errors
    add     x1, x1, :lo12:lora_rx_errors
    ldr     w2, [x1]
    add     w2, w2, #1
    str     w2, [x1]
    mov     x0, #TRANSPORT_ERR_FRAME
    mov     x1, #0

.Llora_recv_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size lora_recv, .-lora_recv

// =============================================================================
// lora_parse_hex_frame - Parse hex-encoded frame and validate CRC
// =============================================================================
// Input:
//   x0 = hex string
//   x1 = output buffer
//   x2 = output buffer length
// Output:
//   x0 = payload length, negative on error
// =============================================================================
lora_parse_hex_frame:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // hex string
    mov     x20, x1                     // output
    mov     x21, x2                     // max length

    // Decode hex to rx_buffer first
    adrp    x22, lora_rx_buffer
    add     x22, x22, :lo12:lora_rx_buffer

    mov     x0, x19
    mov     x1, x22
    mov     x2, #LORA_MAX_PAYLOAD
    bl      lora_hex_decode
    cmp     x0, #SERIAL_FRAME_OVERHEAD
    b.lt    .Lparse_hex_error

    mov     w21, w0                     // Total frame length

    // Verify sync bytes
    ldrb    w0, [x22, #0]
    cmp     w0, #SERIAL_SYNC_BYTE1
    b.ne    .Lparse_hex_error

    ldrb    w0, [x22, #1]
    cmp     w0, #SERIAL_SYNC_BYTE2
    b.ne    .Lparse_hex_error

    // Get payload length
    ldrb    w0, [x22, #2]
    ldrb    w1, [x22, #3]
    lsl     w1, w1, #8
    orr     w19, w0, w1                 // Payload length

    // Verify length
    add     w0, w19, #SERIAL_FRAME_OVERHEAD
    cmp     w0, w21
    b.ne    .Lparse_hex_error

    // Verify CRC
    add     x0, x22, #2                 // Length field start
    add     w1, w19, #2                 // Length + payload
    bl      serial_crc16
    mov     w1, w0                      // Calculated CRC

    // Get stored CRC
    add     x0, x22, #4
    add     x0, x0, x19
    ldrb    w2, [x0, #0]
    ldrb    w3, [x0, #1]
    lsl     w3, w3, #8
    orr     w2, w2, w3                  // Stored CRC

    cmp     w1, w2
    b.ne    .Lparse_hex_crc_error

    // Copy payload to output
    mov     x0, x20
    add     x1, x22, #4
    mov     w2, w19
    bl      lora_memcpy

    mov     x0, x19                     // Return payload length
    b       .Lparse_hex_ret

.Lparse_hex_error:
    mov     x0, #TRANSPORT_ERR_FRAME
    b       .Lparse_hex_ret

.Lparse_hex_crc_error:
    mov     x0, #TRANSPORT_ERR_CRC

.Lparse_hex_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size lora_parse_hex_frame, .-lora_parse_hex_frame

// =============================================================================
// lora_get_peers - Get list of known LoRa peers
// =============================================================================
// Input:
//   x0 = buffer for peer list
//   x1 = max peers
// Output:
//   x0 = peer count
// =============================================================================
.global lora_get_peers
.type lora_get_peers, %function
lora_get_peers:
    // LoRa doesn't have explicit peer tracking (broadcast medium)
    // Return 0 peers
    mov     x0, #0
    ret
.size lora_get_peers, .-lora_get_peers

// =============================================================================
// lora_get_quality - Get link quality for LoRa
// =============================================================================
// Input:
//   x0 = peer_id (ignored for LoRa)
// Output:
//   x0 = quality 0-100 based on packet success rate
// =============================================================================
.global lora_get_quality
.type lora_get_quality, %function
lora_get_quality:
    // Calculate quality from RX success rate
    adrp    x0, lora_rx_count
    add     x0, x0, :lo12:lora_rx_count
    ldr     w1, [x0]

    adrp    x0, lora_rx_errors
    add     x0, x0, :lo12:lora_rx_errors
    ldr     w2, [x0]

    // Total attempts
    add     w3, w1, w2
    cbz     w3, .Lquality_unknown

    // Quality = (rx_count * 100) / total
    mov     w0, #100
    mul     w1, w1, w0
    udiv    w0, w1, w3
    ret

.Lquality_unknown:
    mov     x0, #-1
    ret
.size lora_get_quality, .-lora_get_quality

// =============================================================================
// Helper Functions
// =============================================================================

// lora_delay - Delay for specified milliseconds (simplified busy wait)
lora_delay:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Use nanosleep
    sub     sp, sp, #32
    movz    x1, #0x4240                 // 1000000 = 0xF4240
    movk    x1, #0xF, lsl #16
    mul     x0, x0, x1
    movz    x1, #0xCA00                 // 1000000000 = 0x3B9ACA00
    movk    x1, #0x9ACA, lsl #16
    movk    x1, #0x3B, lsl #32
    udiv    x2, x0, x1                  // seconds
    msub    x3, x2, x1, x0              // nanoseconds
    str     x2, [sp, #0]
    str     x3, [sp, #8]

    mov     x0, sp
    mov     x1, #0
    mov     x8, #SYS_nanosleep
    svc     #0

    add     sp, sp, #32
    ldp     x29, x30, [sp], #16
    ret

// lora_strlen - Get string length
lora_strlen:
    mov     x1, #0
.Lstrlen_loop:
    ldrb    w2, [x0, x1]
    cbz     w2, .Lstrlen_done
    add     x1, x1, #1
    b       .Lstrlen_loop
.Lstrlen_done:
    mov     x0, x1
    ret

// lora_strcpy - Copy string (returns pointer to end)
lora_strcpy:
    mov     x2, x0
.Lstrcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    cbnz    w3, .Lstrcpy_loop
    sub     x0, x0, #1                  // Point to null terminator
    ret

// lora_strcat - Concatenate string
lora_strcat:
    // Find end of dest
.Lstrcat_find:
    ldrb    w2, [x0]
    cbz     w2, .Lstrcat_copy
    add     x0, x0, #1
    b       .Lstrcat_find
.Lstrcat_copy:
    ldrb    w2, [x1], #1
    strb    w2, [x0], #1
    cbnz    w2, .Lstrcat_copy
    ret

// lora_strstr - Find substring
lora_strstr:
    mov     x2, x0                      // haystack
    mov     x3, x1                      // needle
.Lstrstr_loop:
    ldrb    w4, [x2]
    cbz     w4, .Lstrstr_notfound
    mov     x5, x2
    mov     x6, x3
.Lstrstr_match:
    ldrb    w7, [x6]
    cbz     w7, .Lstrstr_found
    ldrb    w8, [x5]
    cmp     w7, w8
    b.ne    .Lstrstr_next
    add     x5, x5, #1
    add     x6, x6, #1
    b       .Lstrstr_match
.Lstrstr_next:
    add     x2, x2, #1
    b       .Lstrstr_loop
.Lstrstr_found:
    mov     x0, x2
    ret
.Lstrstr_notfound:
    mov     x0, #0
    ret

// lora_memcpy - Copy memory
lora_memcpy:
    cbz     x2, .Lmemcpy_done
.Lmemcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    subs    x2, x2, #1
    b.ne    .Lmemcpy_loop
.Lmemcpy_done:
    ret

// lora_append_num - Append decimal number to string
// Input: x0 = string end, w1 = number
// Output: x0 = new string end
lora_append_num:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    mov     x2, x0                      // Save position
    mov     w3, w1                      // Number

    // Convert to decimal (max 3 digits for SF/power)
    mov     w4, #10
    add     x5, sp, #16                 // Temp buffer

    // Generate digits in reverse
    mov     x6, #0
.Lappend_num_loop:
    udiv    w7, w3, w4
    msub    w8, w7, w4, w3
    add     w8, w8, #'0'
    strb    w8, [x5, x6]
    add     x6, x6, #1
    mov     w3, w7
    cbnz    w3, .Lappend_num_loop

    // Copy in reverse order
.Lappend_num_rev:
    sub     x6, x6, #1
    ldrb    w7, [x5, x6]
    strb    w7, [x2], #1
    cbnz    x6, .Lappend_num_rev

    strb    wzr, [x2]
    mov     x0, x2

    ldp     x29, x30, [sp], #32
    ret

// lora_append_hex - Append hex-encoded data
// Input: x0 = string end, x1 = data, w2 = length
// Output: x0 = new string end
lora_append_hex:
    cbz     w2, .Lappend_hex_done
    mov     x3, x0
.Lappend_hex_loop:
    ldrb    w4, [x1], #1

    // High nibble
    lsr     w5, w4, #4
    cmp     w5, #10
    b.lt    .Lhex_hi_digit
    add     w5, w5, #('A' - 10)
    b       .Lhex_hi_store
.Lhex_hi_digit:
    add     w5, w5, #'0'
.Lhex_hi_store:
    strb    w5, [x3], #1

    // Low nibble
    and     w5, w4, #0xF
    cmp     w5, #10
    b.lt    .Lhex_lo_digit
    add     w5, w5, #('A' - 10)
    b       .Lhex_lo_store
.Lhex_lo_digit:
    add     w5, w5, #'0'
.Lhex_lo_store:
    strb    w5, [x3], #1

    subs    w2, w2, #1
    b.ne    .Lappend_hex_loop

.Lappend_hex_done:
    strb    wzr, [x3]
    mov     x0, x3
    ret

// lora_hex_decode - Decode hex string to binary
// Input: x0 = hex string, x1 = output, x2 = max output length
// Output: x0 = bytes decoded
lora_hex_decode:
    mov     x3, #0                      // Output position
.Lhex_decode_loop:
    cmp     x3, x2
    b.ge    .Lhex_decode_done

    // Get high nibble
    ldrb    w4, [x0], #1
    cbz     w4, .Lhex_decode_done
    cmp     w4, #'\r'
    b.eq    .Lhex_decode_done
    cmp     w4, #'\n'
    b.eq    .Lhex_decode_done

    bl      .Lhex_char_to_val
    lsl     w5, w4, #4

    // Get low nibble
    ldrb    w4, [x0], #1
    cbz     w4, .Lhex_decode_done
    bl      .Lhex_char_to_val
    orr     w5, w5, w4

    strb    w5, [x1, x3]
    add     x3, x3, #1
    b       .Lhex_decode_loop

.Lhex_decode_done:
    mov     x0, x3
    ret

.Lhex_char_to_val:
    cmp     w4, #'0'
    b.lt    .Lhex_invalid
    cmp     w4, #'9'
    b.le    .Lhex_digit
    cmp     w4, #'A'
    b.lt    .Lhex_invalid
    cmp     w4, #'F'
    b.le    .Lhex_upper
    cmp     w4, #'a'
    b.lt    .Lhex_invalid
    cmp     w4, #'f'
    b.gt    .Lhex_invalid
    sub     w4, w4, #('a' - 10)
    ret
.Lhex_upper:
    sub     w4, w4, #('A' - 10)
    ret
.Lhex_digit:
    sub     w4, w4, #'0'
    ret
.Lhex_invalid:
    mov     w4, #0
    ret
