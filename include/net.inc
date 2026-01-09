// =============================================================================
// Omesh - net.inc
// Network layer constants and structures
// =============================================================================

#ifndef NET_INC
#define NET_INC

// =============================================================================
// Wire Protocol Constants
// =============================================================================

.equ MSG_MAGIC,             0x4853454D  // "MESH" in little-endian
.equ MSG_VERSION,           1
.equ MSG_HDR_SIZE,          40

// Header field offsets
.equ MSG_OFF_MAGIC,         0           // [4] Magic number
.equ MSG_OFF_VERSION,       4           // [1] Protocol version
.equ MSG_OFF_TYPE,          5           // [1] Message type
.equ MSG_OFF_FLAGS,         6           // [2] Message flags
.equ MSG_OFF_SEQ,           8           // [4] Sequence number
.equ MSG_OFF_LENGTH,        12          // [4] Payload length
.equ MSG_OFF_SRC_NODE,      16          // [8] Source node ID
.equ MSG_OFF_DST_NODE,      24          // [8] Destination node ID
.equ MSG_OFF_CHECKSUM,      32          // [4] CRC32 checksum
.equ MSG_OFF_RESERVED,      36          // [4] Reserved
.equ MSG_OFF_PAYLOAD,       40          // [N] Payload starts here

// =============================================================================
// Message Types
// =============================================================================

// Control messages (TCP)
.equ MSG_TYPE_PING,         0x01        // Keepalive
.equ MSG_TYPE_PONG,         0x02        // Keepalive response
.equ MSG_TYPE_HELLO,        0x03        // Node introduction
.equ MSG_TYPE_GOODBYE,      0x04        // Graceful disconnect
.equ MSG_TYPE_DISCOVER,     0x05        // Peer discovery request
.equ MSG_TYPE_PEERS,        0x06        // Peer list response

// RPC messages (TCP)
.equ MSG_TYPE_REQUEST,      0x10        // RPC request
.equ MSG_TYPE_RESPONSE,     0x11        // RPC response
.equ MSG_TYPE_ERROR,        0x12        // Error response

// Data messages (UDP preferred)
.equ MSG_TYPE_DATA,         0x20        // Bulk data transfer
.equ MSG_TYPE_ACK,          0x21        // Data acknowledgment
.equ MSG_TYPE_NACK,         0x22        // Negative acknowledgment

// Index/Search messages
.equ MSG_TYPE_SEARCH,       0x30        // Search query
.equ MSG_TYPE_RESULTS,      0x31        // Search results
.equ MSG_TYPE_INDEX,        0x32        // Index update

// =============================================================================
// Message Flags
// =============================================================================

.equ MSG_FLAG_COMPRESSED,   0x0001      // Payload is compressed
.equ MSG_FLAG_ENCRYPTED,    0x0002      // Payload is encrypted
.equ MSG_FLAG_FRAGMENT,     0x0004      // Part of fragmented message
.equ MSG_FLAG_LAST_FRAG,    0x0008      // Last fragment
.equ MSG_FLAG_RELIABLE,     0x0010      // Requires acknowledgment
.equ MSG_FLAG_PRIORITY,     0x0020      // High priority

// =============================================================================
// Connection State Structure (80 bytes)
// =============================================================================

.equ CONN_OFF_TCP_FD,       0           // [8] TCP socket fd
.equ CONN_OFF_UDP_FD,       8           // [8] UDP socket fd (or -1)
.equ CONN_OFF_STATE,        16          // [4] Connection state
.equ CONN_OFF_FLAGS,        20          // [4] Connection flags
.equ CONN_OFF_NODE_ID,      24          // [8] Remote node ID
.equ CONN_OFF_RECV_BUF,     32          // [8] Receive buffer ptr
.equ CONN_OFF_RECV_LEN,     40          // [8] Data in recv buffer
.equ CONN_OFF_SEND_BUF,     48          // [8] Send buffer ptr
.equ CONN_OFF_SEND_LEN,     56          // [8] Data in send buffer
.equ CONN_OFF_LAST_ACTIVE,  64          // [8] Last activity timestamp
.equ CONN_OFF_ADDR,         72          // [8] Remote address (sockaddr_in)
.equ CONN_SIZE,             80

// Connection states
.equ CONN_STATE_NONE,       0           // Slot is free
.equ CONN_STATE_CONNECTING, 1           // TCP connect in progress
.equ CONN_STATE_CONNECTED,  2           // Fully connected
.equ CONN_STATE_CLOSING,    3           // Graceful close in progress
.equ CONN_STATE_CLOSED,     4           // Closed, pending cleanup

// Connection flags
.equ CONN_FLAG_OUTBOUND,    0x0001      // We initiated connection
.equ CONN_FLAG_INBOUND,     0x0002      // Peer initiated connection
.equ CONN_FLAG_UDP_READY,   0x0004      // UDP channel established
.equ CONN_FLAG_AUTHENTICATED, 0x0008   // Peer authenticated

// =============================================================================
// Reactor State Structure (64 bytes)
// =============================================================================

.equ REACTOR_OFF_EPOLL_FD,  0           // [8] epoll file descriptor
.equ REACTOR_OFF_TCP_FD,    8           // [8] Listening TCP socket
.equ REACTOR_OFF_UDP_FD,    16          // [8] UDP socket
.equ REACTOR_OFF_EVENTS,    24          // [8] Events buffer ptr
.equ REACTOR_OFF_MAX_EVENTS,32          // [8] Max events per wait
.equ REACTOR_OFF_RUNNING,   40          // [8] Running flag
.equ REACTOR_OFF_NODE_ID,   48          // [8] Local node ID
.equ REACTOR_OFF_CONN_COUNT,56          // [8] Active connection count
.equ REACTOR_SIZE,          64

// =============================================================================
// Peer Manager State Structure (48 bytes)
// =============================================================================

.equ PEER_MGR_OFF_CONNS,    0           // [8] Connection array ptr
.equ PEER_MGR_OFF_COUNT,    8           // [8] Active connection count
.equ PEER_MGR_OFF_CAPACITY, 16          // [8] Max connections
.equ PEER_MGR_OFF_REACTOR,  24          // [8] Reactor ptr
.equ PEER_MGR_OFF_NODE_ID,  32          // [8] Local node ID
.equ PEER_MGR_OFF_FLAGS,    40          // [8] Manager flags
.equ PEER_MGR_SIZE,         48

// =============================================================================
// Buffer and Limit Constants
// =============================================================================

.equ NET_RECV_BUF_SIZE,     65536       // 64KB receive buffer
.equ NET_SEND_BUF_SIZE,     65536       // 64KB send buffer
.equ NET_MAX_MSG_SIZE,      0x1000000   // 16MB max message
.equ NET_MAX_CONNECTIONS,   256         // Max peer connections
.equ NET_MAX_EVENTS,        64          // epoll max events per wait
.equ NET_LISTEN_BACKLOG,    128         // TCP listen backlog
.equ NET_DEFAULT_PORT,      7878        // Default listening port

// =============================================================================
// sockaddr_in structure (16 bytes, but we use 8 for compactness)
// For our purposes: [2] family | [2] port | [4] addr
// =============================================================================

.equ SOCKADDR_OFF_FAMILY,   0           // [2] sa_family (AF_INET)
.equ SOCKADDR_OFF_PORT,     2           // [2] port (network byte order)
.equ SOCKADDR_OFF_ADDR,     4           // [4] IPv4 address
.equ SOCKADDR_IN_SIZE,      16          // Full sockaddr_in size

// =============================================================================
// epoll_event structure (12 bytes on aarch64, padded to 16)
// =============================================================================

.equ EPOLL_EVENT_EVENTS,    0           // [4] events mask
.equ EPOLL_EVENT_DATA,      4           // [8] user data (we use fd)
.equ EPOLL_EVENT_SIZE,      12          // Actual size (kernel uses 12)

// =============================================================================
// CRC32 Constants
// =============================================================================

.equ CRC32_INIT,            0xFFFFFFFF  // Initial CRC value
.equ CRC32_XOR_OUT,         0xFFFFFFFF  // Final XOR value

// =============================================================================
// Timeout Values (milliseconds)
// =============================================================================

.equ NET_EPOLL_TIMEOUT,     1000        // epoll wait timeout (1s)
.equ NET_CONNECT_TIMEOUT,   5000        // Connection timeout (5s)
.equ NET_PING_INTERVAL,     30000       // Ping interval (30s)
.equ NET_PING_TIMEOUT,      10000       // Ping response timeout (10s)

// =============================================================================
// fcntl constants for non-blocking
// =============================================================================

.equ F_GETFL,               3           // Get file status flags
.equ F_SETFL,               4           // Set file status flags

// =============================================================================
// IPPROTO level for TCP options
// =============================================================================

.equ IPPROTO_TCP_LEVEL,     6           // For setsockopt TCP options

#endif // NET_INC
