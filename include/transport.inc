// =============================================================================
// Omesh - Transport Interface Definitions
// =============================================================================
//
// Abstract transport layer supporting multiple communication backends:
// - TCP/IP (ethernet, WiFi client)
// - Serial/UART (direct connections, radio TNCs)
// - UDP (broadcast discovery, low-overhead messaging)
// - Future: WiFi mesh, LoRa, Bluetooth, etc.
//
// Each transport implements the transport_ops interface.
//
// =============================================================================

#ifndef TRANSPORT_INC
#define TRANSPORT_INC

// =============================================================================
// Transport Operation Offsets (vtable structure)
// =============================================================================
//
// Each transport provides a 48-byte ops structure with function pointers:
//
//   init(config_ptr) -> 0 on success, -errno on failure
//   shutdown() -> void
//   send(peer_id, data_ptr, data_len) -> bytes sent, -errno on failure
//   recv(buf_ptr, buf_len, timeout_ms) -> bytes received, -errno on failure
//                                         peer_id returned in x1
//   get_peers(buf_ptr, max_peers) -> peer count
//   get_link_quality(peer_id) -> 0-100 quality score, -1 if unknown
//
// =============================================================================

.equ TRANSPORT_OP_INIT,         0       // [8] init function pointer
.equ TRANSPORT_OP_SHUTDOWN,     8       // [8] shutdown function pointer
.equ TRANSPORT_OP_SEND,         16      // [8] send function pointer
.equ TRANSPORT_OP_RECV,         24      // [8] recv function pointer
.equ TRANSPORT_OP_GET_PEERS,    32      // [8] get_peers function pointer
.equ TRANSPORT_OP_LINK_QUALITY, 40      // [8] get_link_quality function pointer
.equ TRANSPORT_OPS_SIZE,        48

// =============================================================================
// Transport Types
// =============================================================================

.equ TRANSPORT_NONE,        0           // No transport configured
.equ TRANSPORT_TCP,         1           // TCP/IP transport
.equ TRANSPORT_UDP,         2           // UDP transport
.equ TRANSPORT_SERIAL,      3           // Serial/UART transport
.equ TRANSPORT_BLUETOOTH,   4           // Bluetooth transport (future)
.equ TRANSPORT_LORA,        5           // LoRa transport (future)
.equ TRANSPORT_WIFI_MESH,   6           // 802.11s WiFi mesh (future)
.equ TRANSPORT_AX25,        7           // AX.25 packet radio (future)

// =============================================================================
// Transport Configuration Structure (128 bytes)
// =============================================================================
//
// Common configuration for all transports. Transport-specific options
// are stored in the options field.
//
// =============================================================================

.equ TRANSPORT_CFG_TYPE,        0       // [4] Transport type (TRANSPORT_*)
.equ TRANSPORT_CFG_FLAGS,       4       // [4] Configuration flags
.equ TRANSPORT_CFG_PORT,        8       // [4] Port number (TCP/UDP)
.equ TRANSPORT_CFG_BAUD,        12      // [4] Baud rate (serial)
.equ TRANSPORT_CFG_DEVICE,      16      // [64] Device path (e.g., /dev/ttyUSB0)
.equ TRANSPORT_CFG_OPTIONS,     80      // [48] Transport-specific options
.equ TRANSPORT_CFG_SIZE,        128

// Configuration flags
.equ TRANSPORT_FLAG_ENABLED,    0x01    // Transport is enabled
.equ TRANSPORT_FLAG_PRIMARY,    0x02    // Primary transport for outgoing
.equ TRANSPORT_FLAG_LISTEN,     0x04    // Listen for incoming connections
.equ TRANSPORT_FLAG_BROADCAST,  0x08    // Support broadcast (UDP)

// =============================================================================
// Transport Peer Structure (32 bytes)
// =============================================================================
//
// Information about a peer reachable via transport.
//
// =============================================================================

.equ TPEER_OFF_ID,              0       // [8] Peer ID (node_id)
.equ TPEER_OFF_ADDR,            8       // [16] Address (IP:port or device-specific)
.equ TPEER_OFF_QUALITY,         24      // [4] Link quality (0-100)
.equ TPEER_OFF_FLAGS,           28      // [4] Peer flags
.equ TPEER_SIZE,                32

// Peer flags
.equ TPEER_FLAG_CONNECTED,      0x01    // Currently connected
.equ TPEER_FLAG_REACHABLE,      0x02    // Recently reachable
.equ TPEER_FLAG_SEED,           0x04    // Seed peer (always try to connect)

// =============================================================================
// Serial Transport Configuration (in TRANSPORT_CFG_OPTIONS)
// =============================================================================

.equ SERIAL_OPT_DATA_BITS,      0       // [4] Data bits (5-8, default 8)
.equ SERIAL_OPT_STOP_BITS,      4       // [4] Stop bits (1-2, default 1)
.equ SERIAL_OPT_PARITY,         8       // [4] Parity (0=none, 1=odd, 2=even)
.equ SERIAL_OPT_FLOW_CTRL,      12      // [4] Flow control (0=none, 1=hw, 2=sw)
.equ SERIAL_OPT_RESERVED,       16      // [32] Reserved

// Common baud rates
.equ BAUD_9600,                 9600
.equ BAUD_19200,                19200
.equ BAUD_38400,                38400
.equ BAUD_57600,                57600
.equ BAUD_115200,               115200
.equ BAUD_230400,               230400
.equ BAUD_460800,               460800
.equ BAUD_921600,               921600

// =============================================================================
// Serial Frame Format
// =============================================================================
//
// Framing protocol for serial transport:
//   [SYNC: 2 bytes 0xAA 0x55]
//   [LENGTH: 2 bytes, little-endian, payload length]
//   [PAYLOAD: LENGTH bytes]
//   [CRC16: 2 bytes, CCITT CRC-16]
//
// Total overhead: 6 bytes per frame
// Max payload: 65535 bytes
//
// =============================================================================

.equ SERIAL_SYNC_BYTE1,         0xAA
.equ SERIAL_SYNC_BYTE2,         0x55
.equ SERIAL_FRAME_HDR_SIZE,     4       // sync (2) + length (2)
.equ SERIAL_FRAME_CRC_SIZE,     2       // CRC-16
.equ SERIAL_FRAME_OVERHEAD,     6       // header + CRC
.equ SERIAL_MAX_PAYLOAD,        4096    // Max payload per frame

// =============================================================================
// Transport Error Codes
// =============================================================================

.equ TRANSPORT_ERR_NONE,        0       // Success
.equ TRANSPORT_ERR_NOT_INIT,    -1      // Transport not initialized
.equ TRANSPORT_ERR_INVALID,     -2      // Invalid parameter
.equ TRANSPORT_ERR_NO_PEER,     -3      // Peer not found
.equ TRANSPORT_ERR_TIMEOUT,     -4      // Operation timed out
.equ TRANSPORT_ERR_DISCONNECTED,-5      // Peer disconnected
.equ TRANSPORT_ERR_CRC,         -6      // CRC check failed
.equ TRANSPORT_ERR_FRAME,       -7      // Frame format error
.equ TRANSPORT_ERR_FULL,        -8      // Buffer full
.equ TRANSPORT_ERR_DEVICE,      -9      // Device error

// =============================================================================
// Transport Manager Constants
// =============================================================================

.equ MAX_TRANSPORTS,            8       // Max registered transport types
.equ MAX_ACTIVE_TRANSPORTS,     4       // Max simultaneously active transports
.equ MAX_TRANSPORT_PEERS,       64      // Max peers per transport

// Active transport entry structure (24 bytes)
.equ ACTIVE_TRANS_TYPE,         0       // [4] Transport type
.equ ACTIVE_TRANS_FD,           4       // [4] Listening fd (-1 if none)
.equ ACTIVE_TRANS_OPS,          8       // [8] Pointer to transport_ops
.equ ACTIVE_TRANS_FLAGS,        16      // [4] Flags
.equ ACTIVE_TRANS_RESERVED,     20      // [4] Reserved
.equ ACTIVE_TRANS_SIZE,         24

// Active transport flags
.equ ACTIVE_TRANS_FLAG_ENABLED, 0x01    // Transport is enabled
.equ ACTIVE_TRANS_FLAG_LISTEN,  0x02    // Listening for connections
.equ ACTIVE_TRANS_FLAG_PRIMARY, 0x04    // Primary transport for outgoing

// =============================================================================
// Termios Constants for Serial Configuration
// =============================================================================

// ioctl commands for termios
.equ TCGETS,                0x5401      // Get terminal attributes
.equ TCSETS,                0x5402      // Set terminal attributes immediately
.equ TCSETSW,               0x5403      // Set terminal attributes after output drain
.equ TCSETSF,               0x5404      // Set terminal attributes after flush
.equ TCFLSH,                0x540B      // Flush input/output
.equ TIOCEXCL,              0x540C      // Exclusive mode
.equ TIOCNXCL,              0x540D      // Disable exclusive mode
.equ TIOCSCTTY,             0x540E      // Make controlling tty
.equ TIOCOUTQ,              0x5411      // Output queue size
.equ TIOCSTI,               0x5412      // Simulate terminal input
.equ TIOCMGET,              0x5415      // Get modem status bits
.equ TIOCMSET,              0x5418      // Set modem status bits

// Flush queue selectors
.equ TCIFLUSH,              0           // Flush input
.equ TCOFLUSH,              1           // Flush output
.equ TCIOFLUSH,             2           // Flush both

// termios structure offsets (aarch64 Linux)
.equ TERMIOS_IFLAG,         0           // [4] Input flags
.equ TERMIOS_OFLAG,         4           // [4] Output flags
.equ TERMIOS_CFLAG,         8           // [4] Control flags
.equ TERMIOS_LFLAG,         12          // [4] Local flags
.equ TERMIOS_LINE,          16          // [1] Line discipline
.equ TERMIOS_CC,            17          // [19] Control characters
.equ TERMIOS_SIZE,          36          // Minimum termios size

// Control character indices (c_cc array)
.equ VINTR,                 0
.equ VQUIT,                 1
.equ VERASE,                2
.equ VKILL,                 3
.equ VEOF,                  4
.equ VTIME,                 5           // Read timeout (tenths of second)
.equ VMIN,                  6           // Minimum chars for read
.equ VSWTC,                 7
.equ VSTART,                8
.equ VSTOP,                 9
.equ VSUSP,                 10
.equ VEOL,                  11
.equ VREPRINT,              12
.equ VDISCARD,              13
.equ VWERASE,               14
.equ VLNEXT,                15
.equ VEOL2,                 16

// Input flags (c_iflag)
.equ IGNBRK,                0x00001     // Ignore break
.equ BRKINT,                0x00002     // Break causes interrupt
.equ IGNPAR,                0x00004     // Ignore parity errors
.equ PARMRK,                0x00008     // Mark parity errors
.equ INPCK,                 0x00010     // Enable input parity
.equ ISTRIP,                0x00020     // Strip 8th bit
.equ INLCR,                 0x00040     // Map NL to CR
.equ IGNCR,                 0x00080     // Ignore CR
.equ ICRNL,                 0x00100     // Map CR to NL
.equ IXON,                  0x00400     // Enable XON/XOFF output
.equ IXANY,                 0x00800     // Any char restarts output
.equ IXOFF,                 0x01000     // Enable XON/XOFF input

// Output flags (c_oflag)
.equ OPOST,                 0x00001     // Post-process output
.equ ONLCR,                 0x00004     // Map NL to CR-NL

// Control flags (c_cflag)
.equ CBAUD,                 0x0000100f  // Baud rate mask
.equ CSIZE,                 0x00000030  // Character size mask
.equ CS5,                   0x00000000  // 5 data bits
.equ CS6,                   0x00000010  // 6 data bits
.equ CS7,                   0x00000020  // 7 data bits
.equ CS8,                   0x00000030  // 8 data bits
.equ CSTOPB,                0x00000040  // 2 stop bits (else 1)
.equ CREAD,                 0x00000080  // Enable receiver
.equ PARENB,                0x00000100  // Enable parity
.equ PARODD,                0x00000200  // Odd parity (else even)
.equ HUPCL,                 0x00000400  // Hangup on close
.equ CLOCAL,                0x00000800  // Local connection (ignore modem)
.equ CRTSCTS,               0x80000000  // Hardware flow control

// Baud rate values for c_cflag (standard rates)
.equ B0,                    0x00000000
.equ B50,                   0x00000001
.equ B75,                   0x00000002
.equ B110,                  0x00000003
.equ B134,                  0x00000004
.equ B150,                  0x00000005
.equ B200,                  0x00000006
.equ B300,                  0x00000007
.equ B600,                  0x00000008
.equ B1200,                 0x00000009
.equ B1800,                 0x0000000a
.equ B2400,                 0x0000000b
.equ B4800,                 0x0000000c
.equ B9600,                 0x0000000d
.equ B19200,                0x0000000e
.equ B38400,                0x0000000f
// Extended baud rates (CBAUDEX | value)
.equ CBAUDEX,               0x00001000
.equ B57600,                0x00001001
.equ B115200,               0x00001002
.equ B230400,               0x00001003
.equ B460800,               0x00001004
.equ B500000,               0x00001005
.equ B576000,               0x00001006
.equ B921600,               0x00001007
.equ B1000000,              0x00001008
.equ B1152000,              0x00001009
.equ B1500000,              0x0000100a
.equ B2000000,              0x0000100b
.equ B2500000,              0x0000100c
.equ B3000000,              0x0000100d
.equ B3500000,              0x0000100e
.equ B4000000,              0x0000100f

// Local flags (c_lflag)
.equ ISIG,                  0x00001     // Enable signals
.equ ICANON,                0x00002     // Canonical mode (line editing)
.equ ECHO,                  0x00008     // Enable echo
.equ ECHOE,                 0x00010     // Echo erase
.equ ECHOK,                 0x00020     // Echo kill
.equ ECHONL,                0x00040     // Echo NL
.equ NOFLSH,                0x00080     // Disable flush after interrupt
.equ IEXTEN,                0x08000     // Extended input processing

// Modem control bits (TIOCMGET/TIOCMSET)
.equ TIOCM_LE,              0x001       // Line enable
.equ TIOCM_DTR,             0x002       // Data terminal ready
.equ TIOCM_RTS,             0x004       // Request to send
.equ TIOCM_ST,              0x008       // Secondary transmit
.equ TIOCM_SR,              0x010       // Secondary receive
.equ TIOCM_CTS,             0x020       // Clear to send
.equ TIOCM_CAR,             0x040       // Carrier detect
.equ TIOCM_CD,              0x040       // Carrier detect (alias)
.equ TIOCM_RNG,             0x080       // Ring
.equ TIOCM_RI,              0x080       // Ring (alias)
.equ TIOCM_DSR,             0x100       // Data set ready

// =============================================================================
// Serial State Machine Constants
// =============================================================================

.equ SERIAL_STATE_SYNC1,    0           // Waiting for first sync byte
.equ SERIAL_STATE_SYNC2,    1           // Waiting for second sync byte
.equ SERIAL_STATE_LEN_LO,   2           // Waiting for length low byte
.equ SERIAL_STATE_LEN_HI,   3           // Waiting for length high byte
.equ SERIAL_STATE_DATA,     4           // Receiving payload data
.equ SERIAL_STATE_CRC_LO,   5           // Waiting for CRC low byte
.equ SERIAL_STATE_CRC_HI,   6           // Waiting for CRC high byte

#endif // TRANSPORT_INC
