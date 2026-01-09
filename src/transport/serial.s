// =============================================================================
// Serial/UART Transport Implementation
// =============================================================================
//
// Serial transport backend for the transport abstraction layer.
// Implements framed communication over serial ports with:
//   - Sync bytes (0xAA 0x55) for frame detection
//   - 16-bit length field (little-endian)
//   - Payload data
//   - CRC-16 CCITT for error detection
//
// Frame format:
//   [SYNC1: 0xAA] [SYNC2: 0x55] [LEN_LO] [LEN_HI] [PAYLOAD...] [CRC_LO] [CRC_HI]
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/transport.inc"

.global serial_transport_register
.global serial_transport_ops
.global serial_crc16

// External transport manager
.extern transport_register

.text

// =============================================================================
// serial_transport_register - Register serial transport with manager
// =============================================================================
// Input: none
// Output:
//   x0 = 0 on success
// =============================================================================

serial_transport_register:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Register with transport manager
    mov     x0, #TRANSPORT_SERIAL
    adrp    x1, serial_transport_ops
    add     x1, x1, :lo12:serial_transport_ops
    bl      transport_register

    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// serial_init - Initialize serial transport
// =============================================================================
// Input:
//   x0 = pointer to transport_config
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================

serial_init:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    str     x23, [sp, #48]

    mov     x19, x0                     // Save config pointer

    // Get device path from config
    add     x20, x19, #TRANSPORT_CFG_DEVICE

    // Check if device path is empty
    ldrb    w0, [x20]
    cbz     w0, .Lserial_init_no_device

    // Open serial device
    mov     x0, #AT_FDCWD
    mov     x1, x20                     // device path
    mov     x2, #(O_RDWR | O_NOCTTY | O_NONBLOCK)
    mov     x8, #SYS_openat
    svc     #0

    cmp     x0, #0
    b.lt    .Lserial_init_error

    mov     w21, w0                     // Save fd

    // Store fd
    adrp    x1, serial_fd
    add     x1, x1, :lo12:serial_fd
    str     w21, [x1]

    // Configure serial port
    mov     w0, w21
    mov     x1, x19                     // config
    bl      serial_configure
    cmp     x0, #0
    b.lt    .Lserial_init_close_error

    // Flush any stale data
    mov     w0, w21
    mov     x1, #TCFLSH
    mov     x2, #TCIOFLUSH
    mov     x8, #SYS_ioctl
    svc     #0

    // Initialize receive state machine
    adrp    x0, serial_rx_state
    add     x0, x0, :lo12:serial_rx_state
    str     wzr, [x0]                   // STATE_SYNC1

    adrp    x0, serial_rx_index
    add     x0, x0, :lo12:serial_rx_index
    str     wzr, [x0]

    // Initialize peer as connected (point-to-point)
    adrp    x0, serial_peer_connected
    add     x0, x0, :lo12:serial_peer_connected
    mov     w1, #1
    str     w1, [x0]

    // Reset statistics
    adrp    x0, serial_stats_crc_errors
    add     x0, x0, :lo12:serial_stats_crc_errors
    str     xzr, [x0]

    adrp    x0, serial_stats_frames_ok
    add     x0, x0, :lo12:serial_stats_frames_ok
    str     xzr, [x0]

    mov     x0, #0
    ldr     x23, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lserial_init_no_device:
    mov     x0, #TRANSPORT_ERR_INVALID
    ldr     x23, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lserial_init_close_error:
    mov     x22, x0                     // Save error
    mov     w0, w21
    mov     x8, #SYS_close
    svc     #0
    mov     x0, x22
    ldr     x23, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lserial_init_error:
    ldr     x23, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret


// =============================================================================
// serial_configure - Configure serial port settings
// =============================================================================
// Input:
//   w0 = fd
//   x1 = pointer to transport_config
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================

serial_configure:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     w19, w0                     // fd
    mov     x20, x1                     // config

    // Get baud rate from config
    ldr     w21, [x20, #TRANSPORT_CFG_BAUD]

    // Get serial options from config
    add     x22, x20, #TRANSPORT_CFG_OPTIONS

    // Allocate termios on stack (offset 48, size 36)
    add     x2, sp, #48                 // termios buffer

    // Get current terminal attributes
    mov     w0, w19
    mov     x1, #TCGETS
    mov     x8, #SYS_ioctl
    svc     #0
    cmp     x0, #0
    b.lt    .Lconfig_error

    add     x2, sp, #48                 // termios buffer

    // Clear all flags for raw mode
    str     wzr, [x2, #TERMIOS_IFLAG]   // No input processing
    str     wzr, [x2, #TERMIOS_OFLAG]   // No output processing
    str     wzr, [x2, #TERMIOS_LFLAG]   // No local processing

    // Build cflag: baud | size | CREAD | CLOCAL
    bl      serial_baud_to_cflag        // Convert baud rate
    mov     w23, w0                     // cflag

    // Get data bits from options
    ldr     w0, [x22, #SERIAL_OPT_DATA_BITS]
    cmp     w0, #0
    b.eq    .Lconfig_default_bits
    cmp     w0, #5
    b.eq    .Lconfig_cs5
    cmp     w0, #6
    b.eq    .Lconfig_cs6
    cmp     w0, #7
    b.eq    .Lconfig_cs7
    // Default to 8 bits
.Lconfig_default_bits:
    mov     w0, #CS8
    orr     w23, w23, w0
    b       .Lconfig_stop_bits
.Lconfig_cs5:
    // CS5 = 0, no bits to set
    b       .Lconfig_stop_bits
.Lconfig_cs6:
    mov     w0, #CS6
    orr     w23, w23, w0
    b       .Lconfig_stop_bits
.Lconfig_cs7:
    mov     w0, #CS7
    orr     w23, w23, w0

.Lconfig_stop_bits:
    // Get stop bits from options
    ldr     w0, [x22, #SERIAL_OPT_STOP_BITS]
    cmp     w0, #2
    b.ne    .Lconfig_parity
    orr     w23, w23, #CSTOPB

.Lconfig_parity:
    // Get parity from options
    ldr     w0, [x22, #SERIAL_OPT_PARITY]
    cbz     w0, .Lconfig_flow           // 0 = none
    cmp     w0, #1
    b.eq    .Lconfig_parity_odd
    // Even parity
    orr     w23, w23, #PARENB
    b       .Lconfig_flow
.Lconfig_parity_odd:
    orr     w23, w23, #(PARENB | PARODD)

.Lconfig_flow:
    // Get flow control from options
    ldr     w0, [x22, #SERIAL_OPT_FLOW_CTRL]
    cbz     w0, .Lconfig_enable         // 0 = none
    cmp     w0, #1
    b.ne    .Lconfig_sw_flow
    // Hardware flow control (CRTSCTS = 0x80000000)
    mov     w0, #0x8000
    lsl     w0, w0, #16
    orr     w23, w23, w0
    b       .Lconfig_enable
.Lconfig_sw_flow:
    // Software flow control (set in iflag)
    add     x2, sp, #48
    ldr     w0, [x2, #TERMIOS_IFLAG]
    mov     w1, #(IXON | IXOFF)
    orr     w0, w0, w1
    str     w0, [x2, #TERMIOS_IFLAG]

.Lconfig_enable:
    // Enable receiver and local mode
    mov     w0, #(CREAD | CLOCAL)
    orr     w23, w23, w0

    // Store cflag
    add     x2, sp, #48
    str     w23, [x2, #TERMIOS_CFLAG]

    // Set control characters for raw mode
    add     x3, x2, #TERMIOS_CC
    mov     w0, #1
    strb    w0, [x3, #VMIN]             // Min 1 char
    strb    wzr, [x3, #VTIME]           // No timeout

    // Apply settings
    mov     w0, w19
    mov     x1, #TCSETSF
    mov     x8, #SYS_ioctl
    svc     #0
    cmp     x0, #0
    b.lt    .Lconfig_error

    // Set DTR and RTS
    mov     w0, w19
    mov     x1, #TIOCMGET
    sub     sp, sp, #16
    mov     x2, sp
    mov     x8, #SYS_ioctl
    svc     #0

    ldr     w0, [sp]
    orr     w0, w0, #(TIOCM_DTR | TIOCM_RTS)
    str     w0, [sp]

    mov     w0, w19
    mov     x1, #TIOCMSET
    mov     x2, sp
    mov     x8, #SYS_ioctl
    svc     #0
    add     sp, sp, #16

    mov     x0, #0
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

.Lconfig_error:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret


// =============================================================================
// serial_baud_to_cflag - Convert baud rate to cflag value
// =============================================================================
// Input:
//   w21 = baud rate (e.g., 9600, 115200)
// Output:
//   w0 = cflag baud rate bits
// =============================================================================

serial_baud_to_cflag:
    // Check common baud rates
    // Use lookup table approach for cleaner code
    mov     w0, #9600
    cmp     w21, w0
    b.eq    .Lbaud_9600
    mov     w0, #19200
    cmp     w21, w0
    b.eq    .Lbaud_19200
    mov     w0, #38400
    cmp     w21, w0
    b.eq    .Lbaud_38400
    movz    w0, #0xE100                  // 57600 = 0xE100
    cmp     w21, w0
    b.eq    .Lbaud_57600
    movz    w0, #0xC200                  // 115200 = 0x1C200
    movk    w0, #0x1, lsl #16
    cmp     w21, w0
    b.eq    .Lbaud_115200
    movz    w0, #0x8400                  // 230400 = 0x38400
    movk    w0, #0x3, lsl #16
    cmp     w21, w0
    b.eq    .Lbaud_230400
    movz    w0, #0x0800                  // 460800 = 0x70800
    movk    w0, #0x7, lsl #16
    cmp     w21, w0
    b.eq    .Lbaud_460800
    movz    w0, #0x1000                  // 921600 = 0xE1000
    movk    w0, #0xE, lsl #16
    cmp     w21, w0
    b.eq    .Lbaud_921600

    // Default to 115200
.Lbaud_115200:
    movz    w0, #B115200
    ret
.Lbaud_9600:
    mov     w0, #B9600
    ret
.Lbaud_19200:
    mov     w0, #B19200
    ret
.Lbaud_38400:
    mov     w0, #B38400
    ret
.Lbaud_57600:
    movz    w0, #B57600
    ret
.Lbaud_230400:
    movz    w0, #B230400
    ret
.Lbaud_460800:
    movz    w0, #B460800
    ret
.Lbaud_921600:
    movz    w0, #B921600
    ret


// =============================================================================
// serial_shutdown - Shutdown serial transport
// =============================================================================
// Input: none
// Output: none
// =============================================================================

serial_shutdown:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Close serial fd if open
    adrp    x0, serial_fd
    add     x0, x0, :lo12:serial_fd
    ldr     w0, [x0]
    cmp     w0, #0
    b.le    .Lserial_shutdown_done

    mov     x8, #SYS_close
    svc     #0

    // Clear fd
    adrp    x0, serial_fd
    add     x0, x0, :lo12:serial_fd
    str     wzr, [x0]

    // Mark peer as disconnected
    adrp    x0, serial_peer_connected
    add     x0, x0, :lo12:serial_peer_connected
    str     wzr, [x0]

.Lserial_shutdown_done:
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// serial_send - Send framed data over serial
// =============================================================================
// Input:
//   x0 = peer_id (ignored for serial - point-to-point)
//   x1 = data pointer
//   x2 = data length
// Output:
//   x0 = bytes sent (payload only) on success, negative errno on failure
// =============================================================================

serial_send:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x20, x1                     // data
    mov     w21, w2                     // length

    // Check length
    cmp     w21, #SERIAL_MAX_PAYLOAD
    b.gt    .Lsend_too_long

    // Get fd
    adrp    x0, serial_fd
    add     x0, x0, :lo12:serial_fd
    ldr     w19, [x0]
    cmp     w19, #0
    b.le    .Lsend_not_init

    // Calculate CRC of payload
    mov     x0, x20
    mov     w1, w21
    bl      serial_crc16
    mov     w22, w0                     // CRC

    // Build frame header in tx buffer
    adrp    x23, serial_tx_buffer
    add     x23, x23, :lo12:serial_tx_buffer

    mov     w0, #SERIAL_SYNC_BYTE1
    strb    w0, [x23, #0]
    mov     w0, #SERIAL_SYNC_BYTE2
    strb    w0, [x23, #1]
    strb    w21, [x23, #2]              // Length low byte
    lsr     w0, w21, #8
    strb    w0, [x23, #3]               // Length high byte

    // Copy payload
    add     x0, x23, #SERIAL_FRAME_HDR_SIZE
    mov     x1, x20
    mov     w2, w21
    bl      serial_memcpy

    // Append CRC
    add     w24, w21, #SERIAL_FRAME_HDR_SIZE
    strb    w22, [x23, x24]             // CRC low byte
    lsr     w0, w22, #8
    add     w24, w24, #1
    strb    w0, [x23, x24]              // CRC high byte

    // Calculate total frame size
    add     w24, w21, #SERIAL_FRAME_OVERHEAD

    // Write frame to serial port
    mov     w0, w19
    mov     x1, x23
    mov     x2, x24
    mov     x8, #SYS_write
    svc     #0

    cmp     x0, #0
    b.lt    .Lsend_error

    // Return payload length sent
    mov     x0, x21

    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lsend_too_long:
    mov     x0, #TRANSPORT_ERR_INVALID
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lsend_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lsend_error:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret


// =============================================================================
// serial_recv - Receive framed data from serial
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = buffer length
//   x2 = timeout in milliseconds (ignored - non-blocking)
// Output:
//   x0 = bytes received (payload) on success, negative errno on failure
//   x1 = peer_id (always 1 for serial)
// =============================================================================

serial_recv:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // output buffer
    mov     w20, w1                     // buffer length

    // Get fd
    adrp    x0, serial_fd
    add     x0, x0, :lo12:serial_fd
    ldr     w21, [x0]
    cmp     w21, #0
    b.le    .Lrecv_not_init

    // Read available bytes into temp buffer
    adrp    x22, serial_raw_buffer
    add     x22, x22, :lo12:serial_raw_buffer

    mov     w0, w21
    mov     x1, x22
    mov     x2, #256                    // Read up to 256 bytes
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #0
    b.lt    .Lrecv_check_eagain
    b.eq    .Lrecv_no_data

    mov     w23, w0                     // Bytes read
    mov     w24, #0                     // Index into raw buffer

    // Process each byte through state machine
.Lrecv_process_loop:
    cmp     w24, w23
    b.ge    .Lrecv_no_complete_frame

    ldrb    w0, [x22, x24]
    add     w24, w24, #1
    bl      serial_process_byte

    // Check if we got a complete frame
    cmp     x0, #0
    b.gt    .Lrecv_got_frame
    b       .Lrecv_process_loop

.Lrecv_got_frame:
    // x0 = payload length
    mov     w23, w0

    // Check if payload fits in output buffer
    cmp     w23, w20
    b.gt    .Lrecv_buffer_too_small

    // Copy payload to output buffer
    mov     x0, x19
    adrp    x1, serial_rx_buffer
    add     x1, x1, :lo12:serial_rx_buffer
    mov     w2, w23
    bl      serial_memcpy

    // Increment success counter
    adrp    x0, serial_stats_frames_ok
    add     x0, x0, :lo12:serial_stats_frames_ok
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    mov     x0, x23                     // payload length
    mov     x1, #1                      // peer_id = 1 (single peer)
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lrecv_check_eagain:
    cmn     x0, #EAGAIN
    b.eq    .Lrecv_no_data
    cmn     x0, #EWOULDBLOCK
    b.eq    .Lrecv_no_data
    // Real error
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lrecv_no_data:
.Lrecv_no_complete_frame:
    mov     x0, #TRANSPORT_ERR_TIMEOUT
    mov     x1, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lrecv_buffer_too_small:
    mov     x0, #TRANSPORT_ERR_FULL
    mov     x1, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Lrecv_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    mov     x1, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret


// =============================================================================
// serial_process_byte - Process one byte through frame state machine
// =============================================================================
// Input:
//   w0 = byte to process
// Output:
//   x0 = payload length if frame complete, 0 otherwise, -1 on CRC error
// =============================================================================

serial_process_byte:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     w19, w0                     // Save byte

    // Get current state
    adrp    x0, serial_rx_state
    add     x0, x0, :lo12:serial_rx_state
    ldr     w20, [x0]

    // State dispatch
    cmp     w20, #SERIAL_STATE_SYNC1
    b.eq    .Lstate_sync1
    cmp     w20, #SERIAL_STATE_SYNC2
    b.eq    .Lstate_sync2
    cmp     w20, #SERIAL_STATE_LEN_LO
    b.eq    .Lstate_len_lo
    cmp     w20, #SERIAL_STATE_LEN_HI
    b.eq    .Lstate_len_hi
    cmp     w20, #SERIAL_STATE_DATA
    b.eq    .Lstate_data
    cmp     w20, #SERIAL_STATE_CRC_LO
    b.eq    .Lstate_crc_lo
    cmp     w20, #SERIAL_STATE_CRC_HI
    b.eq    .Lstate_crc_hi

    // Invalid state, reset
    b       .Lstate_reset

.Lstate_sync1:
    cmp     w19, #SERIAL_SYNC_BYTE1
    b.ne    .Lstate_no_change
    mov     w0, #SERIAL_STATE_SYNC2
    b       .Lstate_set

.Lstate_sync2:
    cmp     w19, #SERIAL_SYNC_BYTE2
    b.ne    .Lstate_check_sync1
    mov     w0, #SERIAL_STATE_LEN_LO
    b       .Lstate_set

.Lstate_check_sync1:
    // Maybe this is start of new sync
    cmp     w19, #SERIAL_SYNC_BYTE1
    b.eq    .Lstate_no_change           // Stay in SYNC2 (got SYNC1 again)
    b       .Lstate_reset

.Lstate_len_lo:
    // Store length low byte
    adrp    x0, serial_rx_length
    add     x0, x0, :lo12:serial_rx_length
    strh    w19, [x0]
    mov     w0, #SERIAL_STATE_LEN_HI
    b       .Lstate_set

.Lstate_len_hi:
    // Complete length
    adrp    x0, serial_rx_length
    add     x0, x0, :lo12:serial_rx_length
    ldrh    w1, [x0]
    orr     w1, w1, w19, lsl #8
    strh    w1, [x0]

    // Validate length
    cmp     w1, #SERIAL_MAX_PAYLOAD
    b.gt    .Lstate_reset
    cbz     w1, .Lstate_reset

    // Initialize receive index
    adrp    x0, serial_rx_index
    add     x0, x0, :lo12:serial_rx_index
    str     wzr, [x0]

    mov     w0, #SERIAL_STATE_DATA
    b       .Lstate_set

.Lstate_data:
    // Store byte in buffer
    adrp    x0, serial_rx_index
    add     x0, x0, :lo12:serial_rx_index
    ldr     w1, [x0]

    adrp    x2, serial_rx_buffer
    add     x2, x2, :lo12:serial_rx_buffer
    strb    w19, [x2, x1]

    add     w1, w1, #1
    str     w1, [x0]

    // Check if all data received
    adrp    x0, serial_rx_length
    add     x0, x0, :lo12:serial_rx_length
    ldrh    w2, [x0]
    cmp     w1, w2
    b.lt    .Lstate_no_change

    mov     w0, #SERIAL_STATE_CRC_LO
    b       .Lstate_set

.Lstate_crc_lo:
    adrp    x0, serial_rx_crc
    add     x0, x0, :lo12:serial_rx_crc
    strh    w19, [x0]
    mov     w0, #SERIAL_STATE_CRC_HI
    b       .Lstate_set

.Lstate_crc_hi:
    // Complete CRC
    adrp    x0, serial_rx_crc
    add     x0, x0, :lo12:serial_rx_crc
    ldrh    w1, [x0]
    orr     w1, w1, w19, lsl #8
    strh    w1, [x0]

    // Verify CRC
    adrp    x0, serial_rx_buffer
    add     x0, x0, :lo12:serial_rx_buffer
    adrp    x2, serial_rx_length
    add     x2, x2, :lo12:serial_rx_length
    ldrh    w1, [x2]
    bl      serial_crc16

    adrp    x2, serial_rx_crc
    add     x2, x2, :lo12:serial_rx_crc
    ldrh    w2, [x2]
    cmp     w0, w2
    b.ne    .Lstate_crc_error

    // Frame complete and valid
    // Reset state
    adrp    x0, serial_rx_state
    add     x0, x0, :lo12:serial_rx_state
    str     wzr, [x0]

    // Return payload length
    adrp    x0, serial_rx_length
    add     x0, x0, :lo12:serial_rx_length
    ldrh    w0, [x0]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lstate_crc_error:
    // Increment CRC error counter
    adrp    x0, serial_stats_crc_errors
    add     x0, x0, :lo12:serial_stats_crc_errors
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]
    // Fall through to reset

.Lstate_reset:
    adrp    x0, serial_rx_state
    add     x0, x0, :lo12:serial_rx_state
    str     wzr, [x0]
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lstate_set:
    adrp    x1, serial_rx_state
    add     x1, x1, :lo12:serial_rx_state
    str     w0, [x1]
.Lstate_no_change:
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// =============================================================================
// serial_crc16 - Calculate CRC-16 CCITT
// =============================================================================
// Input:
//   x0 = data pointer
//   w1 = data length
// Output:
//   w0 = CRC-16 value
//
// Polynomial: 0x1021 (CCITT)
// Initial value: 0xFFFF
// =============================================================================

serial_crc16:
    mov     w2, #0xFFFF                 // Initial CRC
    cbz     w1, .Lcrc_done

.Lcrc_loop:
    ldrb    w3, [x0], #1                // Load byte, advance pointer
    eor     w2, w2, w3, lsl #8          // CRC ^= byte << 8

    mov     w4, #8                      // 8 bits per byte
.Lcrc_bit_loop:
    lsl     w2, w2, #1                  // CRC <<= 1
    tst     w2, #0x10000                // Check if bit 16 set
    b.eq    .Lcrc_no_xor
    mov     w5, #0x1021
    eor     w2, w2, w5                  // CRC ^= polynomial
.Lcrc_no_xor:
    and     w2, w2, #0xFFFF             // Keep 16 bits
    subs    w4, w4, #1
    b.ne    .Lcrc_bit_loop

    subs    w1, w1, #1
    b.ne    .Lcrc_loop

.Lcrc_done:
    mov     w0, w2
    ret


// =============================================================================
// serial_get_peers - Get list of serial peers (always 1 or 0)
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = max peers
// Output:
//   x0 = number of peers (0 or 1)
// =============================================================================

serial_get_peers:
    cbz     x1, .Lget_peers_none        // No space

    // Check if connected
    adrp    x2, serial_peer_connected
    add     x2, x2, :lo12:serial_peer_connected
    ldr     w2, [x2]
    cbz     w2, .Lget_peers_none

    // Fill in peer structure
    mov     x1, #1                      // peer_id = 1
    str     x1, [x0, #TPEER_OFF_ID]

    // Address: device path (store in first 16 bytes)
    adrp    x2, serial_fd
    add     x2, x2, :lo12:serial_fd
    ldr     w2, [x2]
    str     x2, [x0, #TPEER_OFF_ADDR]   // Store fd as "address"
    str     xzr, [x0, #TPEER_OFF_ADDR + 8]

    // Quality based on CRC error rate
    bl      serial_calc_quality
    str     w0, [x0, #TPEER_OFF_QUALITY]

    // Flags
    mov     w1, #(TPEER_FLAG_CONNECTED | TPEER_FLAG_REACHABLE)
    str     w1, [x0, #TPEER_OFF_FLAGS]

    mov     x0, #1
    ret

.Lget_peers_none:
    mov     x0, #0
    ret


// =============================================================================
// serial_get_quality - Get link quality for serial connection
// =============================================================================
// Input:
//   x0 = peer_id (ignored)
// Output:
//   w0 = quality (0-100)
// =============================================================================

serial_get_quality:
    // Fall through to calc_quality

// =============================================================================
// serial_calc_quality - Calculate quality from error rate
// =============================================================================
// Output:
//   w0 = quality (0-100)
// =============================================================================

serial_calc_quality:
    adrp    x0, serial_stats_frames_ok
    add     x0, x0, :lo12:serial_stats_frames_ok
    ldr     x1, [x0]                    // good frames

    adrp    x0, serial_stats_crc_errors
    add     x0, x0, :lo12:serial_stats_crc_errors
    ldr     x2, [x0]                    // bad frames

    add     x3, x1, x2                  // total frames
    cbz     x3, .Lquality_default       // No frames yet

    // quality = (good * 100) / total
    mov     x0, #100
    mul     x1, x1, x0
    udiv    x0, x1, x3

    // Clamp to 0-100
    cmp     x0, #100
    b.le    .Lquality_ok
    mov     x0, #100
.Lquality_ok:
    ret

.Lquality_default:
    mov     x0, #100                    // Default to 100 if no data
    ret


// =============================================================================
// serial_memcpy - Simple memory copy
// =============================================================================
// Input:
//   x0 = dest
//   x1 = src
//   w2 = length
// =============================================================================

serial_memcpy:
    cbz     w2, .Lmemcpy_done
.Lmemcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    subs    w2, w2, #1
    b.ne    .Lmemcpy_loop
.Lmemcpy_done:
    ret


// =============================================================================
// Data Section
// =============================================================================

.data

// Serial transport operations vtable
.balign 8
serial_transport_ops:
    .quad   serial_init                 // init
    .quad   serial_shutdown             // shutdown
    .quad   serial_send                 // send
    .quad   serial_recv                 // recv
    .quad   serial_get_peers            // get_peers
    .quad   serial_get_quality          // get_link_quality

// Serial file descriptor
serial_fd:
    .word   0
    .balign 4

// Peer connection status
serial_peer_connected:
    .word   0
    .balign 4

// Receive state machine
serial_rx_state:
    .word   0
serial_rx_length:
    .hword  0
serial_rx_crc:
    .hword  0
serial_rx_index:
    .word   0
    .balign 8

// Statistics
serial_stats_crc_errors:
    .quad   0
serial_stats_frames_ok:
    .quad   0

// Buffers
.balign 8
serial_rx_buffer:
    .space  SERIAL_MAX_PAYLOAD, 0

serial_tx_buffer:
    .space  SERIAL_MAX_PAYLOAD + SERIAL_FRAME_OVERHEAD, 0

serial_raw_buffer:
    .space  256, 0

