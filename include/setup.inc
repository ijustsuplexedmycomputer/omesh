// Setup and Configuration Constants
// include/setup.inc

.ifndef SETUP_INC
.equ SETUP_INC, 1

// ============================================================================
// Config File Constants
// ============================================================================

// Config file paths
.equ CONFIG_PATH_MAX,           256         // Max path length
.equ CONFIG_DIR_MODE,           0755        // Directory permissions
.equ CONFIG_FILE_MODE,          0644        // File permissions

// Config entry limits
.equ CONFIG_MAX_ENTRIES,        64          // Max config entries
.equ CONFIG_KEY_MAX,            64          // Max key length
.equ CONFIG_VALUE_MAX,          256         // Max value length
.equ CONFIG_LINE_MAX,           320         // Max line length (key + = + value)

// Config entry structure
// struct config_entry {
//     char key[64];       // offset 0
//     char value[256];    // offset 64
//     uint32_t type;      // offset 320
//     uint32_t flags;     // offset 324
// }
.equ CONFIG_ENTRY_SIZE,         328
.equ CONFIG_ENTRY_KEY,          0
.equ CONFIG_ENTRY_VALUE,        64
.equ CONFIG_ENTRY_TYPE,         320
.equ CONFIG_ENTRY_FLAGS,        324

// Config value types
.equ CONFIG_TYPE_STRING,        0
.equ CONFIG_TYPE_INT,           1
.equ CONFIG_TYPE_BOOL,          2
.equ CONFIG_TYPE_PATH,          3

// Config entry flags
.equ CONFIG_FLAG_NONE,          0x00
.equ CONFIG_FLAG_READONLY,      0x01        // Cannot be modified
.equ CONFIG_FLAG_REQUIRED,      0x02        // Must have a value
.equ CONFIG_FLAG_MODIFIED,      0x04        // Has been changed

// Config state structure
// struct config_state {
//     uint32_t entry_count;       // offset 0
//     uint32_t flags;             // offset 4
//     char filepath[256];         // offset 8
//     config_entry entries[64];   // offset 264
// }
.equ CONFIG_STATE_SIZE,         21256       // 264 + 64*328
.equ CONFIG_STATE_COUNT,        0
.equ CONFIG_STATE_FLAGS,        4
.equ CONFIG_STATE_FILEPATH,     8
.equ CONFIG_STATE_ENTRIES,      264

// Config state flags
.equ CONFIG_STATE_LOADED,       0x01        // Config loaded from file
.equ CONFIG_STATE_DIRTY,        0x02        // Has unsaved changes

// ============================================================================
// Error Codes
// ============================================================================

.equ CONFIG_SUCCESS,            0
.equ CONFIG_ERR_NOT_FOUND,      -1          // Key not found
.equ CONFIG_ERR_NO_SPACE,       -2          // No space for new entry
.equ CONFIG_ERR_INVALID,        -3          // Invalid key or value
.equ CONFIG_ERR_IO,             -4          // I/O error
.equ CONFIG_ERR_PARSE,          -5          // Parse error
.equ CONFIG_ERR_TOO_LONG,       -6          // Key or value too long

// ============================================================================
// Default Configuration Keys
// ============================================================================

// These are the standard config keys used by omesh

// Node configuration
// node_id=<string>          - Unique node identifier
// node_name=<string>        - Human-readable node name
// node_role=<string>        - Node role: personal, home, bridge, community, offgrid, custom

// Network configuration
// transport=<string>        - Transport type (tcp, udp, serial, lora, bluetooth, wifi-mesh)
// transports=<list>         - Comma-separated list of enabled transports
// bind_addr=<string>        - Address to bind to
// bind_port=<int>           - Port to bind to
// peer_addrs=<string>       - Comma-separated peer addresses
// trusted_peers=<list>      - Comma-separated list of trusted peer addresses
// network_name=<string>     - Network/mesh name for grouping

// Serial/LoRa configuration
// serial_device=<string>    - Serial device path (/dev/ttyUSB0)
// serial_baud=<int>         - Baud rate (115200)

// Bluetooth configuration
// bt_channel=<int>          - RFCOMM channel (1-30)

// Storage configuration
// data_dir=<string>         - Data directory path
// wal_enabled=<bool>        - Enable write-ahead log
// store_others_data=<string>- How to handle others' data: no, cache, replicate

// Cluster configuration
// cluster_name=<string>     - Cluster name
// replication=<int>         - Replication factor

// HTTP configuration
// http_enabled=<bool>       - Enable HTTP server
// http_port=<int>           - HTTP port (8080)

// Privacy/network behavior
// relay_for_others=<bool>   - Relay traffic for other nodes: yes, no
// discoverable=<bool>       - Allow others to discover this node: yes, no
// use_internet=<string>     - When to use internet: no, backup, yes

// ============================================================================
// Setup Wizard Constants
// ============================================================================

// Wizard modes
.equ WIZARD_MODE_EASY,          0           // Automatic with defaults
.equ WIZARD_MODE_GUIDED,        1           // Interactive Q&A
.equ WIZARD_MODE_ADVANCED,      2           // Full manual config

// Hardware detection flags
.equ HW_FLAG_WIFI,              0x01        // WiFi adapter found
.equ HW_FLAG_BLUETOOTH,         0x02        // Bluetooth adapter found
.equ HW_FLAG_SERIAL,            0x04        // Serial port found
.equ HW_FLAG_LORA,              0x08        // LoRa device found

// Terminal UI constants
.equ TERM_WIDTH_MIN,            40
.equ TERM_WIDTH_DEFAULT,        80
.equ TERM_HEIGHT_MIN,           10
.equ TERM_HEIGHT_DEFAULT,       24

// ANSI escape codes for terminal UI
// (Use in .ascii strings)
// \033[0m  - Reset
// \033[1m  - Bold
// \033[32m - Green
// \033[33m - Yellow
// \033[34m - Blue
// \033[36m - Cyan

.endif // SETUP_INC
