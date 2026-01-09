// =============================================================================
// Omesh - mesh.inc
// Mesh networking constants and structures
// =============================================================================

#ifndef MESH_INC
#define MESH_INC

// =============================================================================
// Peer Status Constants
// =============================================================================

.equ PEER_STATUS_UNKNOWN,       0       // Never contacted
.equ PEER_STATUS_CONNECTED,     1       // Currently connected
.equ PEER_STATUS_DISCONNECTED,  2       // Was connected, now disconnected
.equ PEER_STATUS_CONNECTING,    3       // Connection in progress
.equ PEER_STATUS_FAILED,        4       // Connection failed

// =============================================================================
// Peer Entry Structure (48 bytes)
// =============================================================================
//
// Stored peer information for persistence and connection management
//

.equ PEER_OFF_NODE_ID,          0       // [8] Unique node identifier
.equ PEER_OFF_HOST,             8       // [16] Host string (null-terminated, e.g. "127.0.0.1")
.equ PEER_OFF_PORT,             24      // [2] Port number
.equ PEER_OFF_STATUS,           26      // [1] Connection status
.equ PEER_OFF_FLAGS,            27      // [1] Peer flags
.equ PEER_OFF_LAST_SEEN,        28      // [8] Last activity timestamp (seconds)
.equ PEER_OFF_CONN_FD,          36      // [4] Connection file descriptor (-1 if not connected)
.equ PEER_OFF_TRANSPORT,        40      // [1] Transport type (TRANSPORT_*)
.equ PEER_OFF_LINK_QUALITY,     41      // [1] Link quality (0-100, 255=unknown)
.equ PEER_OFF_RESERVED,         42      // [6] Reserved for future use
.equ PEER_ENTRY_SIZE,           48

// Peer flags
.equ PEER_FLAG_SEED,            0x01    // This is a seed/bootstrap peer
.equ PEER_FLAG_OUTBOUND,        0x02    // We initiated connection
.equ PEER_FLAG_INBOUND,         0x04    // Peer initiated connection
.equ PEER_FLAG_PERSISTENT,      0x08    // Keep in list even when disconnected

// =============================================================================
// Peer List Structure (Header + Array)
// =============================================================================
//
// Header (32 bytes) followed by peer entries
//

.equ PEERLIST_OFF_MAGIC,        0       // [4] Magic number "PEER"
.equ PEERLIST_OFF_VERSION,      4       // [4] Structure version
.equ PEERLIST_OFF_COUNT,        8       // [4] Number of peers
.equ PEERLIST_OFF_CAPACITY,     12      // [4] Max peers
.equ PEERLIST_OFF_LOCAL_ID,     16      // [8] Our node ID
.equ PEERLIST_OFF_RESERVED,     24      // [8] Reserved
.equ PEERLIST_HDR_SIZE,         32

.equ PEERLIST_MAGIC,            0x52454550  // "PEER" in little-endian
.equ PEERLIST_VERSION,          1

// =============================================================================
// Mesh Configuration Defaults
// =============================================================================

.equ MESH_DEFAULT_PORT,         9000    // Default mesh communication port
.equ MESH_MAX_PEERS,            64      // Maximum peers in list
.equ MESH_TARGET_CONNECTIONS,   5       // Target number of active connections
.equ MESH_MAX_CONNECTIONS,      16      // Maximum simultaneous connections

.equ MESH_HOST_MAX_LEN,         15      // Max host string length (xxx.xxx.xxx.xxx)

// =============================================================================
// Mesh Message Types (extends net.inc MSG_TYPE_*)
// =============================================================================

.equ MESH_MSG_HELLO,            0x0001  // Initial handshake
.equ MESH_MSG_HELLO_ACK,        0x0002  // Handshake response
.equ MESH_MSG_HEARTBEAT,        0x0003  // Keep-alive ping
.equ MESH_MSG_HEARTBEAT_ACK,    0x0004  // Keep-alive pong
.equ MESH_MSG_PEER_LIST_REQ,    0x0005  // Request peer list
.equ MESH_MSG_PEER_LIST,        0x0006  // Peer list response
.equ MESH_MSG_SEARCH_REQ,       0x0202  // Forward search query
.equ MESH_MSG_SEARCH_RESP,      0x0203  // Return search results

// =============================================================================
// HELLO Payload Structure (24 bytes)
// =============================================================================

.equ HELLO_OFF_NODE_ID,         0       // [8] Sender's node ID
.equ HELLO_OFF_VERSION,         8       // [4] Protocol version
.equ HELLO_OFF_MESH_PORT,       12      // [2] Mesh listen port
.equ HELLO_OFF_HTTP_PORT,       14      // [2] HTTP API port
.equ HELLO_OFF_FLAGS,           16      // [4] Node flags
.equ HELLO_OFF_RESERVED,        20      // [4] Reserved
.equ HELLO_PAYLOAD_SIZE,        24

// =============================================================================
// Timeouts (milliseconds)
// =============================================================================

.equ MESH_CONNECT_TIMEOUT,      5000    // Connection timeout
.equ MESH_HEARTBEAT_INTERVAL,   30000   // Heartbeat every 30s
.equ MESH_HEARTBEAT_TIMEOUT,    10000   // Heartbeat response timeout
.equ MESH_PEER_DEAD_TIMEOUT,    90000   // Peer considered dead after 90s

// =============================================================================
// File paths
// =============================================================================

// Peer list is stored in current directory by default
// Path: ./omesh.peers

#endif // MESH_INC
