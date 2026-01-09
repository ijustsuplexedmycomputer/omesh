// =============================================================================
// Omesh - cluster.inc
// Distributed search coordination constants and structures
// =============================================================================

#ifndef CLUSTER_INC
#define CLUSTER_INC

// =============================================================================
// Cluster Configuration
// =============================================================================

.equ CLUSTER_REPLICATION_FACTOR, 2      // Number of replicas per document
.equ CLUSTER_QUERY_TIMEOUT_MS,   5000   // Query timeout in milliseconds
.equ CLUSTER_MAX_PENDING_QUERIES, 64    // Max concurrent queries
.equ CLUSTER_MAX_RESULTS,        100    // Max results per query
.equ CLUSTER_MAX_DOCS,           4096   // Max documents tracked locally
.equ CLUSTER_DEFAULT_PORT,       7878   // Default listen port

// =============================================================================
// Node States
// =============================================================================

.equ NODE_STATE_INIT,            0      // Initializing
.equ NODE_STATE_SYNCING,         1      // Synchronizing with peers
.equ NODE_STATE_READY,           2      // Ready for operations
.equ NODE_STATE_SHUTDOWN,        3      // Shutting down

// =============================================================================
// Node State Structure (64 bytes)
// =============================================================================

.equ NODE_OFF_ID,                0      // [8] This node's ID
.equ NODE_OFF_STATE,             8      // [4] Node state
.equ NODE_OFF_FLAGS,             12     // [4] Node flags
.equ NODE_OFF_DOC_COUNT,         16     // [8] Local document count
.equ NODE_OFF_PEER_COUNT,        24     // [4] Connected peer count
.equ NODE_OFF_REPLICA_OF,        28     // [4] Number of docs we're replica of
.equ NODE_OFF_QUERY_SEQ,         32     // [4] Query sequence counter
.equ NODE_OFF_LAST_SYNC,         40     // [8] Last sync timestamp
.equ NODE_OFF_RESERVED,          48     // [16] Reserved
.equ NODE_SIZE,                  64

// =============================================================================
// Pending Query Structure (48 bytes)
// =============================================================================

.equ PQUERY_OFF_ID,              0      // [4] Query ID
.equ PQUERY_OFF_STATE,           4      // [4] State
.equ PQUERY_OFF_EXPECTED,        8      // [4] Expected response count
.equ PQUERY_OFF_RECEIVED,        12     // [4] Received response count
.equ PQUERY_OFF_RESULTS,         16     // [8] Results buffer ptr
.equ PQUERY_OFF_RESULT_CNT,      24     // [4] Current result count
.equ PQUERY_OFF_MAX_RESULTS,     28     // [4] Max results to collect
.equ PQUERY_OFF_TIMEOUT,         32     // [8] Timeout timestamp (ns)
.equ PQUERY_OFF_CALLBACK,        40     // [8] Completion callback
.equ PQUERY_SIZE,                48

// Pending query states
.equ PQUERY_STATE_FREE,          0      // Slot is free
.equ PQUERY_STATE_PENDING,       1      // Waiting for responses
.equ PQUERY_STATE_COLLECTING,    2      // Collecting results
.equ PQUERY_STATE_DONE,          3      // Complete

// =============================================================================
// Document Ownership Structure (24 bytes)
// =============================================================================

.equ DOCOWN_OFF_DOC_ID,          0      // [8] Document ID
.equ DOCOWN_OFF_PRIMARY,         8      // [8] Primary node ID
.equ DOCOWN_OFF_REPLICAS,        16     // [8] Bitmap of replica node indices
.equ DOCOWN_SIZE,                24

// =============================================================================
// Search Result Entry (16 bytes)
// =============================================================================

.equ RESULT_OFF_DOC_ID,          0      // [8] Document ID
.equ RESULT_OFF_SCORE,           8      // [4] Score (24.8 fixed-point)
.equ RESULT_OFF_FLAGS,           12     // [4] Flags/reserved
.equ RESULT_SIZE,                16

// =============================================================================
// MSG_TYPE_SEARCH Payload Format
// =============================================================================

.equ SEARCH_OFF_QUERY_ID,        0      // [4] Unique query identifier
.equ SEARCH_OFF_FLAGS,           4      // [4] Query flags (AND/OR/PHRASE)
.equ SEARCH_OFF_MAX_RESULTS,     8      // [4] Maximum results requested
.equ SEARCH_OFF_QUERY_LEN,       12     // [4] Query string length
.equ SEARCH_OFF_QUERY_STR,       16     // [N] UTF-8 query string
.equ SEARCH_HDR_SIZE,            16     // Header size before query string

// Search flags (matches index.inc FTS_QUERY_* flags)
.equ SEARCH_FLAG_AND,            0x01   // AND query
.equ SEARCH_FLAG_OR,             0x02   // OR query
.equ SEARCH_FLAG_PHRASE,         0x04   // Phrase query

// =============================================================================
// MSG_TYPE_RESULTS Payload Format
// =============================================================================

.equ RESULTS_OFF_QUERY_ID,       0      // [4] Matching query identifier
.equ RESULTS_OFF_COUNT,          4      // [4] Number of results
.equ RESULTS_OFF_TOTAL,          8      // [4] Total matches (may exceed count)
.equ RESULTS_OFF_RESERVED,       12     // [4] Reserved
.equ RESULTS_OFF_ENTRIES,        16     // [N] Array of result entries
.equ RESULTS_HDR_SIZE,           16     // Header size before entries

// =============================================================================
// MSG_TYPE_INDEX Payload Format
// =============================================================================

.equ INDEX_OFF_DOC_ID,           0      // [8] Document ID
.equ INDEX_OFF_OPERATION,        8      // [4] Operation (PUT/DELETE)
.equ INDEX_OFF_DOC_LEN,          12     // [4] Document length
.equ INDEX_OFF_DOC_DATA,         16     // [N] Document content
.equ INDEX_HDR_SIZE,             16     // Header size before data

// Index operations
.equ INDEX_OP_PUT,               1      // Add/update document
.equ INDEX_OP_DELETE,            2      // Delete document

// =============================================================================
// REPL Command Codes
// =============================================================================

.equ CMD_UNKNOWN,                0
.equ CMD_INDEX,                  1
.equ CMD_SEARCH,                 2
.equ CMD_PEERS,                  3
.equ CMD_STATUS,                 4
.equ CMD_CONNECT,                5
.equ CMD_QUIT,                   6
.equ CMD_HELP,                   7

// =============================================================================
// Buffer Sizes
// =============================================================================

.equ REPL_LINE_SIZE,             1024   // Max input line size
.equ REPL_OUTPUT_SIZE,           4096   // Output buffer size

#endif // CLUSTER_INC
