// =============================================================================
// Omesh - Main Entry Point
// =============================================================================
//
// Initializes all subsystems in proper order and runs the interactive REPL
// or HTTP API server.
//
// Usage:
//   ./omesh              Run interactive REPL
//   ./omesh --http       Run HTTP API server on port 8080
//   ./omesh --http 9090  Run HTTP API server on port 9090
//
// Initialization order:
//   1. hal_init      - CPU detection, features
//   2. doc_store_init - Document storage (WAL)
//   3. fts_index_init - Full-text search index
//   4. node_init     - Cluster node identity
//   5. handler_init  - Message handlers
//   6. replica_init  - Replication manager
//   7. router_init   - Query router
//
// =============================================================================

.include "syscall_nums.inc"
.include "cluster.inc"
.include "index.inc"
.include "mesh.inc"
.include "transport.inc"

// External reference to environ (defined in config.s)
.extern environ

.data
// Data file paths (current directory)
index_path:
    .asciz  "."
docs_path:
    .asciz  "./docs.dat"

// Banner
banner:
    .ascii  "\n"
    .ascii  "  ___  __  __ _____ ____  _   _ \n"
    .ascii  " / _ \\|  \\/  | ____/ ___|| | | |\n"
    .ascii  "| | | | |\\/| |  _| \\___ \\| |_| |\n"
    .ascii  "| |_| | |  | | |___ ___) |  _  |\n"
    .ascii  " \\___/|_|  |_|_____|____/|_| |_|\n"
    .ascii  "\n"
    .ascii  "Distributed Full-Text Search Engine\n"
    .ascii  "Version 0.1.0 (aarch64 assembly)\n"
    .asciz  "\n"

// Debug messages
msg_init_signal:    .asciz "[init] signal_init..."
msg_init_hal:       .asciz "[init] hal_init..."
msg_init_store:     .asciz "[init] doc_store_init..."
msg_init_fts:       .asciz "[init] fts_index_init..."
msg_init_node:      .asciz "[init] node_init..."
msg_init_handler:   .asciz "[init] handler_init..."
msg_init_replica:   .asciz "[init] replica_init..."
msg_init_router:    .asciz "[init] router_init..."
msg_init_load:      .asciz "[init] fts_index_load..."
msg_init_http:      .asciz "[init] http_server_init..."
msg_init_ok:        .asciz " OK\n"
msg_init_fail:      .asciz " FAILED\n"
msg_init_done:      .asciz "[init] All systems ready\n"
msg_shutdown:       .asciz "\nShutting down...\n"
msg_shutdown_save:  .asciz "[shutdown] Saving index...\n"
msg_shutdown_done:  .asciz "Goodbye.\n"

// Mode messages
msg_repl_mode:      .asciz "[mode] Starting interactive REPL\n"
msg_http_mode:      .asciz "[mode] Starting HTTP API server on port "
msg_setup_mode:     .asciz "[mode] Starting setup wizard\n"
msg_config_loaded:  .asciz "[config] Loaded configuration from ~/.omesh/config\n"
msg_no_config:      .asciz "[config] No configuration found. Run --setup to configure.\n"
msg_http_ready:     .asciz "[http] Server ready, press Ctrl+C to stop\n"
msg_newline:        .asciz "\n"

// Command line args
arg_http:           .asciz "--http"
arg_setup:          .asciz "--setup"
arg_show_config:    .asciz "--show-config"
arg_mesh:           .asciz "--mesh"
arg_mesh_port:      .asciz "--mesh-port"
arg_peer:           .asciz "--peer"
arg_node_id:        .asciz "--node-id"
arg_no_mesh:        .asciz "--no-mesh"
arg_transport:      .asciz "--transport"
arg_serial_device:  .asciz "--serial-device"
arg_serial_baud:    .asciz "--serial-baud"
arg_udp_port:       .asciz "--udp-port"

// Transport type strings
transport_tcp:      .asciz "tcp"
transport_serial:   .asciz "serial"
transport_udp:      .asciz "udp"
transport_lora:     .asciz "lora"
transport_bluetooth: .asciz "bluetooth"
transport_wifi_mesh: .asciz "wifi-mesh"

// Mesh init messages
msg_init_mesh:      .asciz "[init] peer_list_init..."
msg_init_mesh_net:  .asciz "[init] mesh_net_init..."
msg_mesh_mode:      .asciz "[mode] Starting mesh networking on port "
msg_mesh_ready:     .asciz "[mesh] Mesh ready, press Ctrl+C to stop\n"
msg_mesh_peer:      .asciz "[mesh] Initial peer: "

// Transport init messages
msg_init_transport: .asciz "[init] transport_init..."
msg_transport_tcp:  .asciz "[transport] Using TCP transport\n"
msg_transport_serial: .asciz "[transport] Using serial transport: "
msg_transport_baud: .asciz " @ "
msg_transport_udp:  .asciz "[transport] Using UDP transport on port "
msg_transport_lora: .asciz "[transport] Using LoRa transport\n"
msg_transport_bt:   .asciz "[transport] Using Bluetooth transport\n"
msg_transport_wmesh: .asciz "[transport] Using WiFi Mesh transport\n"

// Global state
.align 4
g_init_complete:
    .word   0
g_http_mode:
    .word   0
g_setup_mode:
    .word   0               // --setup flag (run setup wizard)
g_show_config:
    .word   0               // --show-config flag
g_mesh_mode:
    .word   0               // --mesh flag (run mesh event loop)
g_http_port:
    .word   8080
g_mesh_enabled:
    .word   1               // Mesh enabled by default
g_mesh_port:
    .word   9000            // Default mesh port
g_node_id:
    .quad   0               // Node ID (0 = auto-generate)

// Initial peer storage (for --peer flag)
g_initial_peer_host:
    .skip   16              // Max 15 chars + null
g_initial_peer_port:
    .word   0

// Transport configuration
g_transport_type:
    .word   TRANSPORT_TCP       // Default to TCP
g_serial_device:
    .skip   64                  // Serial device path (e.g., /dev/ttyUSB0)
g_serial_baud:
    .word   115200              // Default baud rate
g_udp_port:
    .word   9001                // Default UDP port

.text

// =============================================================================
// print_msg - Print a null-terminated string
// =============================================================================
// Input: x0 = string pointer
// Clobbers: x0-x8
// =============================================================================
print_msg:
    mov     x2, x0          // Save string pointer
    mov     x3, #0          // Length counter
.Lpm_len:
    ldrb    w4, [x2, x3]
    cbz     w4, .Lpm_write
    add     x3, x3, #1
    b       .Lpm_len
.Lpm_write:
    mov     x1, x2          // buf
    mov     x2, x3          // len
    mov     x0, #1          // stdout
    mov     x8, #SYS_write
    svc     #0
    ret

// =============================================================================
// omesh_init - Initialize all subsystems
// =============================================================================
// Input:
//   x0 = index path (null-terminated), or NULL for current directory
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================
.global omesh_init
.global g_mesh_port
.type omesh_init, %function
omesh_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Check if already initialized
    adrp    x1, g_init_complete
    add     x1, x1, :lo12:g_init_complete
    ldr     w2, [x1]
    cbnz    w2, .Linit_already_done

    // Save index path (or use default)
    cbz     x0, .Luse_default_path
    mov     x19, x0
    b       .Lstart_init

.Luse_default_path:
    adrp    x19, index_path
    add     x19, x19, :lo12:index_path

.Lstart_init:
    // 0. Initialize signal handlers first
    adrp    x0, msg_init_signal
    add     x0, x0, :lo12:msg_init_signal
    bl      print_msg
    bl      signal_init
    cmp     x0, #0
    b.lt    .Linit_fail_signal
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    // 1. Initialize HAL (CPU features)
    adrp    x0, msg_init_hal
    add     x0, x0, :lo12:msg_init_hal
    bl      print_msg
    bl      hal_init
    cmp     x0, #0
    b.lt    .Linit_fail_hal
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    // 2. Initialize document store
    adrp    x0, msg_init_store
    add     x0, x0, :lo12:msg_init_store
    bl      print_msg
    adrp    x0, docs_path
    add     x0, x0, :lo12:docs_path
    bl      doc_store_init
    cmp     x0, #0
    b.lt    .Linit_fail_store
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    // 3. Initialize FTS index
    adrp    x0, msg_init_fts
    add     x0, x0, :lo12:msg_init_fts
    bl      print_msg
    mov     x0, x19         // path
    bl      fts_index_init
    cmp     x0, #0
    b.lt    .Linit_fail_fts
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    // 3b. Load persisted index if available
    adrp    x0, msg_init_load
    add     x0, x0, :lo12:msg_init_load
    bl      print_msg
    bl      fts_index_load
    // Ignore return value - 0 or positive is OK
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    // 4. Initialize node
    adrp    x0, msg_init_node
    add     x0, x0, :lo12:msg_init_node
    bl      print_msg
    // Use specified node_id if provided, otherwise auto-generate
    adrp    x0, g_node_id
    add     x0, x0, :lo12:g_node_id
    ldr     x0, [x0]
    bl      node_init
    cmp     x0, #0
    b.lt    .Linit_fail_node
    mov     x0, #NODE_STATE_READY
    bl      node_set_state
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    // 5. Initialize handlers
    adrp    x0, msg_init_handler
    add     x0, x0, :lo12:msg_init_handler
    bl      print_msg
    bl      handler_init
    cmp     x0, #0
    b.lt    .Linit_fail_handler
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    // 6. Initialize replica manager
    adrp    x0, msg_init_replica
    add     x0, x0, :lo12:msg_init_replica
    bl      print_msg
    bl      replica_init
    cmp     x0, #0
    b.lt    .Linit_fail_replica
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    // 7. Initialize router
    adrp    x0, msg_init_router
    add     x0, x0, :lo12:msg_init_router
    bl      print_msg
    bl      router_init
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    // 8. Initialize mesh peer list (if mesh enabled)
    adrp    x0, g_mesh_enabled
    add     x0, x0, :lo12:g_mesh_enabled
    ldr     w0, [x0]
    cbz     w0, .Lskip_mesh_init

    adrp    x0, msg_init_mesh
    add     x0, x0, :lo12:msg_init_mesh
    bl      print_msg
    bl      peer_list_init

    // Set node ID in peer list
    adrp    x0, g_node_id
    add     x0, x0, :lo12:g_node_id
    ldr     x0, [x0]
    bl      peer_list_set_local_id

    // Try to load existing peer list
    mov     x0, #0              // Use default path
    bl      peer_list_load
    // Ignore errors (file may not exist)

    // Add initial peer if specified
    adrp    x0, g_initial_peer_host
    add     x0, x0, :lo12:g_initial_peer_host
    ldrb    w1, [x0]
    cbz     w1, .Lmesh_init_done    // No initial peer

    // Add the initial peer
    adrp    x1, g_initial_peer_port
    add     x1, x1, :lo12:g_initial_peer_port
    ldr     w1, [x1]
    mov     x2, #0              // No node_id yet
    bl      peer_list_add

.Lmesh_init_done:
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    // 9. Initialize mesh networking (TCP listener)
    adrp    x0, msg_init_mesh_net
    add     x0, x0, :lo12:msg_init_mesh_net
    bl      print_msg

    adrp    x0, g_mesh_port
    add     x0, x0, :lo12:g_mesh_port
    ldr     w0, [x0]
    bl      mesh_net_init
    cmp     x0, #0
    b.lt    .Lmesh_net_init_fail

    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg
    b       .Lskip_mesh_init

.Lmesh_net_init_fail:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_msg
    // Continue anyway, mesh will be disabled

.Lskip_mesh_init:
    // 10. Register and initialize transport layer
    adrp    x0, msg_init_transport
    add     x0, x0, :lo12:msg_init_transport
    bl      print_msg

    // Register TCP transport
    bl      tcp_transport_register

    // Register serial transport
    bl      serial_transport_register

    // Register UDP transport
    bl      udp_transport_register

    // Register LoRa transport
    bl      lora_transport_register

    // Register Bluetooth transport
    bl      bluetooth_transport_register

    // Register WiFi Mesh transport
    bl      wifi_mesh_transport_register

    // Check which transport is selected
    adrp    x0, g_transport_type
    add     x0, x0, :lo12:g_transport_type
    ldr     w0, [x0]
    cmp     w0, #TRANSPORT_SERIAL
    b.eq    .Linit_serial_transport
    cmp     w0, #TRANSPORT_UDP
    b.eq    .Linit_udp_transport
    cmp     w0, #TRANSPORT_LORA
    b.eq    .Linit_lora_transport
    cmp     w0, #TRANSPORT_BLUETOOTH
    b.eq    .Linit_bt_transport
    cmp     w0, #TRANSPORT_WIFI_MESH
    b.eq    .Linit_wmesh_transport

    // Default: TCP transport (already handled by mesh_net)
    adrp    x0, msg_transport_tcp
    add     x0, x0, :lo12:msg_transport_tcp
    bl      print_msg
    b       .Ltransport_init_done

.Linit_serial_transport:
    // Print serial transport info
    adrp    x0, msg_transport_serial
    add     x0, x0, :lo12:msg_transport_serial
    bl      print_msg

    adrp    x0, g_serial_device
    add     x0, x0, :lo12:g_serial_device
    bl      print_msg

    adrp    x0, msg_transport_baud
    add     x0, x0, :lo12:msg_transport_baud
    bl      print_msg

    adrp    x0, g_serial_baud
    add     x0, x0, :lo12:g_serial_baud
    ldr     w0, [x0]
    bl      print_num

    adrp    x0, msg_newline
    add     x0, x0, :lo12:msg_newline
    bl      print_msg

    // Build transport config on stack
    sub     sp, sp, #TRANSPORT_CFG_SIZE
    mov     x0, sp

    // Clear config
    mov     x1, #TRANSPORT_CFG_SIZE
.Lclear_cfg:
    subs    x1, x1, #8
    str     xzr, [x0, x1]
    b.gt    .Lclear_cfg

    // Set transport type
    mov     w1, #TRANSPORT_SERIAL
    str     w1, [x0, #TRANSPORT_CFG_TYPE]

    // Set flags (enabled + listen)
    mov     w1, #(TRANSPORT_FLAG_ENABLED | TRANSPORT_FLAG_LISTEN)
    str     w1, [x0, #TRANSPORT_CFG_FLAGS]

    // Set baud rate
    adrp    x1, g_serial_baud
    add     x1, x1, :lo12:g_serial_baud
    ldr     w1, [x1]
    str     w1, [x0, #TRANSPORT_CFG_BAUD]

    // Copy device path
    add     x1, x0, #TRANSPORT_CFG_DEVICE
    adrp    x2, g_serial_device
    add     x2, x2, :lo12:g_serial_device
    mov     x3, #63
.Lcopy_dev:
    ldrb    w4, [x2], #1
    strb    w4, [x1], #1
    cbz     w4, .Ldev_copied
    subs    x3, x3, #1
    b.gt    .Lcopy_dev
    strb    wzr, [x1]           // Null terminate
.Ldev_copied:

    // Initialize transport
    mov     x0, sp
    bl      transport_init
    add     sp, sp, #TRANSPORT_CFG_SIZE

    cmp     x0, #0
    b.lt    .Ltransport_init_fail
    b       .Ltransport_init_done

.Linit_udp_transport:
    // Print UDP transport info
    adrp    x0, msg_transport_udp
    add     x0, x0, :lo12:msg_transport_udp
    bl      print_msg

    adrp    x0, g_udp_port
    add     x0, x0, :lo12:g_udp_port
    ldr     w0, [x0]
    bl      print_num

    adrp    x0, msg_newline
    add     x0, x0, :lo12:msg_newline
    bl      print_msg

    // Build transport config on stack
    sub     sp, sp, #TRANSPORT_CFG_SIZE
    mov     x0, sp

    // Clear config
    mov     x1, #TRANSPORT_CFG_SIZE
.Lclear_udp_cfg:
    subs    x1, x1, #8
    str     xzr, [x0, x1]
    b.gt    .Lclear_udp_cfg

    // Set transport type
    mov     w1, #TRANSPORT_UDP
    str     w1, [x0, #TRANSPORT_CFG_TYPE]

    // Set flags (enabled + listen)
    mov     w1, #(TRANSPORT_FLAG_ENABLED | TRANSPORT_FLAG_LISTEN)
    str     w1, [x0, #TRANSPORT_CFG_FLAGS]

    // Set port (reuse baud field for port)
    adrp    x1, g_udp_port
    add     x1, x1, :lo12:g_udp_port
    ldr     w1, [x1]
    str     w1, [x0, #TRANSPORT_CFG_PORT]

    // Initialize transport
    mov     x0, sp
    bl      transport_init
    add     sp, sp, #TRANSPORT_CFG_SIZE

    cmp     x0, #0
    b.lt    .Ltransport_init_fail
    b       .Ltransport_init_done

.Linit_lora_transport:
    // Print LoRa transport info
    adrp    x0, msg_transport_lora
    add     x0, x0, :lo12:msg_transport_lora
    bl      print_msg

    // Build transport config
    sub     sp, sp, #TRANSPORT_CFG_SIZE
    mov     x0, sp

    mov     x1, #TRANSPORT_CFG_SIZE
.Lclear_lora_cfg:
    subs    x1, x1, #8
    str     xzr, [x0, x1]
    b.gt    .Lclear_lora_cfg

    mov     w1, #TRANSPORT_LORA
    str     w1, [x0, #TRANSPORT_CFG_TYPE]
    mov     w1, #(TRANSPORT_FLAG_ENABLED | TRANSPORT_FLAG_LISTEN)
    str     w1, [x0, #TRANSPORT_CFG_FLAGS]

    // Copy device path
    add     x1, x0, #TRANSPORT_CFG_DEVICE
    adrp    x2, g_serial_device
    add     x2, x2, :lo12:g_serial_device
    mov     x3, #63
.Lcopy_lora_dev:
    ldrb    w4, [x2], #1
    strb    w4, [x1], #1
    cbz     w4, .Llora_dev_copied
    subs    x3, x3, #1
    b.gt    .Lcopy_lora_dev
    strb    wzr, [x1]
.Llora_dev_copied:

    mov     x0, sp
    bl      transport_init
    add     sp, sp, #TRANSPORT_CFG_SIZE
    cmp     x0, #0
    b.lt    .Ltransport_init_fail
    b       .Ltransport_init_done

.Linit_bt_transport:
    // Print Bluetooth transport info
    adrp    x0, msg_transport_bt
    add     x0, x0, :lo12:msg_transport_bt
    bl      print_msg

    // Build transport config
    sub     sp, sp, #TRANSPORT_CFG_SIZE
    mov     x0, sp

    mov     x1, #TRANSPORT_CFG_SIZE
.Lclear_bt_cfg:
    subs    x1, x1, #8
    str     xzr, [x0, x1]
    b.gt    .Lclear_bt_cfg

    mov     w1, #TRANSPORT_BLUETOOTH
    str     w1, [x0, #TRANSPORT_CFG_TYPE]
    mov     w1, #(TRANSPORT_FLAG_ENABLED | TRANSPORT_FLAG_LISTEN)
    str     w1, [x0, #TRANSPORT_CFG_FLAGS]

    mov     x0, sp
    bl      transport_init
    add     sp, sp, #TRANSPORT_CFG_SIZE
    cmp     x0, #0
    b.lt    .Ltransport_init_fail
    b       .Ltransport_init_done

.Linit_wmesh_transport:
    // Print WiFi Mesh transport info
    adrp    x0, msg_transport_wmesh
    add     x0, x0, :lo12:msg_transport_wmesh
    bl      print_msg

    // Build transport config
    sub     sp, sp, #TRANSPORT_CFG_SIZE
    mov     x0, sp

    mov     x1, #TRANSPORT_CFG_SIZE
.Lclear_wmesh_cfg:
    subs    x1, x1, #8
    str     xzr, [x0, x1]
    b.gt    .Lclear_wmesh_cfg

    mov     w1, #TRANSPORT_WIFI_MESH
    str     w1, [x0, #TRANSPORT_CFG_TYPE]
    mov     w1, #(TRANSPORT_FLAG_ENABLED | TRANSPORT_FLAG_LISTEN)
    str     w1, [x0, #TRANSPORT_CFG_FLAGS]

    // Copy interface name from device field
    add     x1, x0, #TRANSPORT_CFG_DEVICE
    adrp    x2, g_serial_device
    add     x2, x2, :lo12:g_serial_device
    mov     x3, #15
.Lcopy_wmesh_if:
    ldrb    w4, [x2], #1
    strb    w4, [x1], #1
    cbz     w4, .Lwmesh_if_copied
    subs    x3, x3, #1
    b.gt    .Lcopy_wmesh_if
    strb    wzr, [x1]
.Lwmesh_if_copied:

    mov     x0, sp
    bl      transport_init
    add     sp, sp, #TRANSPORT_CFG_SIZE
    cmp     x0, #0
    b.lt    .Ltransport_init_fail

.Ltransport_init_done:
    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg
    b       .Linit_complete

.Ltransport_init_fail:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_msg
    // Continue anyway

.Linit_complete:
    // Mark initialization complete
    adrp    x1, g_init_complete
    add     x1, x1, :lo12:g_init_complete
    mov     w2, #1
    str     w2, [x1]

    adrp    x0, msg_init_done
    add     x0, x0, :lo12:msg_init_done
    bl      print_msg

.Linit_already_done:
    mov     x0, #0
    b       .Linit_ret

.Linit_fail_signal:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_msg
    mov     x0, #-7
    b       .Linit_ret

.Linit_fail_hal:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_msg
    mov     x0, #-1
    b       .Linit_ret

.Linit_fail_store:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_msg
    mov     x0, #-2
    b       .Linit_ret

.Linit_fail_fts:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_msg
    mov     x0, #-3
    b       .Linit_ret

.Linit_fail_node:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_msg
    mov     x0, #-4
    b       .Linit_ret

.Linit_fail_handler:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_msg
    mov     x0, #-5
    b       .Linit_ret

.Linit_fail_replica:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_msg
    mov     x0, #-6
    b       .Linit_ret

.Linit_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size omesh_init, .-omesh_init

// =============================================================================
// omesh_shutdown - Clean shutdown
// =============================================================================
// Output:
//   x0 = 0
// =============================================================================
.global omesh_shutdown
.type omesh_shutdown, %function
omesh_shutdown:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Print shutdown message
    adrp    x0, msg_shutdown
    add     x0, x0, :lo12:msg_shutdown
    bl      print_msg

    // Save index before closing
    bl      fts_index_save

    // Close index
    bl      fts_index_close

    // Clear init flag
    adrp    x0, g_init_complete
    add     x0, x0, :lo12:g_init_complete
    str     wzr, [x0]

    // Print goodbye
    adrp    x0, msg_shutdown_done
    add     x0, x0, :lo12:msg_shutdown_done
    bl      print_msg

    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret
.size omesh_shutdown, .-omesh_shutdown

// =============================================================================
// _start - Program entry point
// =============================================================================
.global _start
_start:
    // Set up stack frame
    mov     x29, sp

    // Save argc, argv for later parsing
    ldr     x19, [sp]           // argc
    add     x20, sp, #8         // argv

    // Set up environ pointer for getenv
    // Stack layout: [argc][argv[0]]...[argv[argc-1]][NULL][envp[0]]...
    // envp = sp + 8 + (argc+1)*8 = sp + 8*(argc+2)
    add     x0, x19, #2         // argc + 2
    lsl     x0, x0, #3          // * 8
    add     x0, sp, x0          // sp + offset = envp
    adrp    x1, environ
    add     x1, x1, :lo12:environ
    str     x0, [x1]            // environ = envp

    // Print banner
    adrp    x0, banner
    add     x0, x0, :lo12:banner
    bl      print_msg

    // Parse command line arguments
    bl      parse_args

    // Check for setup mode FIRST (before full init)
    adrp    x0, g_setup_mode
    add     x0, x0, :lo12:g_setup_mode
    ldr     w0, [x0]
    cbnz    w0, .Lstart_setup

    // Initialize all subsystems
    mov     x0, #0              // Use default path
    bl      omesh_init
    cmp     x0, #0
    b.lt    .Lexit_init_err

    // Check mode and start appropriate service
    adrp    x0, g_http_mode
    add     x0, x0, :lo12:g_http_mode
    ldr     w0, [x0]
    cbnz    w0, .Lstart_http

    // Check for mesh-only mode
    adrp    x0, g_mesh_mode
    add     x0, x0, :lo12:g_mesh_mode
    ldr     w0, [x0]
    cbnz    w0, .Lstart_mesh

    // REPL mode
    adrp    x0, msg_repl_mode
    add     x0, x0, :lo12:msg_repl_mode
    bl      print_msg
    bl      repl_init
    bl      repl_run
    b       .Lshutdown

.Lstart_setup:
    // Setup wizard mode
    adrp    x0, msg_setup_mode
    add     x0, x0, :lo12:msg_setup_mode
    bl      print_msg

    // Run the wizard (it handles HAL init internally)
    bl      wizard_run

    // Exit cleanly after wizard
    mov     x0, #0
    mov     x8, #SYS_exit
    svc     #0

.Lstart_mesh:
    // Mesh-only mode
    adrp    x0, msg_mesh_mode
    add     x0, x0, :lo12:msg_mesh_mode
    bl      print_msg

    // Print port number
    adrp    x0, g_mesh_port
    add     x0, x0, :lo12:g_mesh_port
    ldr     w0, [x0]
    bl      print_num
    adrp    x0, msg_newline
    add     x0, x0, :lo12:msg_newline
    bl      print_msg

    // Connect to initial peers
    bl      mesh_net_connect_peers

    adrp    x0, msg_mesh_ready
    add     x0, x0, :lo12:msg_mesh_ready
    bl      print_msg

    // Run mesh event loop (blocks until stopped)
    bl      mesh_net_run
    b       .Lshutdown

.Lstart_http:
    // HTTP mode
    adrp    x0, msg_http_mode
    add     x0, x0, :lo12:msg_http_mode
    bl      print_msg

    // Print port number
    adrp    x0, g_http_port
    add     x0, x0, :lo12:g_http_port
    ldr     w0, [x0]
    bl      print_num
    adrp    x0, msg_newline
    add     x0, x0, :lo12:msg_newline
    bl      print_msg

    // Init HTTP server
    adrp    x0, msg_init_http
    add     x0, x0, :lo12:msg_init_http
    bl      print_msg
    adrp    x0, g_http_port
    add     x0, x0, :lo12:g_http_port
    ldr     w0, [x0]
    bl      http_server_init
    cmp     x0, #0
    b.lt    .Lhttp_init_fail

    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_msg

    adrp    x0, msg_http_ready
    add     x0, x0, :lo12:msg_http_ready
    bl      print_msg

    // Connect to initial peers if mesh is enabled
    adrp    x0, g_mesh_enabled
    add     x0, x0, :lo12:g_mesh_enabled
    ldr     w0, [x0]
    cbz     w0, .Lhttp_skip_mesh_connect

    bl      mesh_net_connect_peers

.Lhttp_skip_mesh_connect:
    // Run HTTP server (blocks until stopped)
    bl      http_server_run
    b       .Lshutdown

.Lhttp_init_fail:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_msg
    mov     x0, #1
    mov     x8, #SYS_exit
    svc     #0

.Lshutdown:
    // Clean shutdown
    bl      omesh_shutdown

    // Exit cleanly
    mov     x0, #0
    mov     x8, #SYS_exit
    svc     #0

.Lexit_init_err:
    // Exit with init error code
    neg     x0, x0              // Convert negative to positive
    mov     x8, #SYS_exit
    svc     #0
.size _start, .-_start

// =============================================================================
// parse_args - Parse command line arguments
// =============================================================================
// Uses x19 = argc, x20 = argv from _start
// =============================================================================
parse_args:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]

    // Skip argv[0] (program name)
    cmp     x19, #1
    b.le    .Lpa_done

    mov     x21, #1             // arg index

.Lpa_loop:
    cmp     x21, x19
    b.ge    .Lpa_done

    // Get argv[i]
    lsl     x0, x21, #3         // *8
    ldr     x22, [x20, x0]      // argv[i]

    // Check for --setup
    adrp    x0, arg_setup
    add     x0, x0, :lo12:arg_setup
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_show_config

    // Found --setup
    adrp    x0, g_setup_mode
    add     x0, x0, :lo12:g_setup_mode
    mov     w1, #1
    str     w1, [x0]
    b       .Lpa_next

.Lpa_check_show_config:
    // Check for --show-config
    adrp    x0, arg_show_config
    add     x0, x0, :lo12:arg_show_config
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_http

    // Found --show-config
    adrp    x0, g_show_config
    add     x0, x0, :lo12:g_show_config
    mov     w1, #1
    str     w1, [x0]
    b       .Lpa_next

.Lpa_check_http:
    // Check for --http
    adrp    x0, arg_http
    add     x0, x0, :lo12:arg_http
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_mesh

    // Found --http
    adrp    x0, g_http_mode
    add     x0, x0, :lo12:g_http_mode
    mov     w1, #1
    str     w1, [x0]

    // Check for optional port number in next arg
    add     x21, x21, #1
    cmp     x21, x19
    b.ge    .Lpa_done

    lsl     x0, x21, #3
    ldr     x0, [x20, x0]       // argv[i+1]
    bl      parse_port
    cmp     x0, #0
    b.le    .Lpa_next_no_inc   // Not a port, don't skip

    // Valid port
    adrp    x1, g_http_port
    add     x1, x1, :lo12:g_http_port
    str     w0, [x1]
    b       .Lpa_next

.Lpa_check_mesh:
    // Check for --mesh (mesh-only mode)
    adrp    x0, arg_mesh
    add     x0, x0, :lo12:arg_mesh
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_mesh_port

    // Found --mesh
    adrp    x0, g_mesh_mode
    add     x0, x0, :lo12:g_mesh_mode
    mov     w1, #1
    str     w1, [x0]
    b       .Lpa_next

.Lpa_check_mesh_port:
    // Check for --mesh-port
    adrp    x0, arg_mesh_port
    add     x0, x0, :lo12:arg_mesh_port
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_peer

    // Found --mesh-port, get next arg
    add     x21, x21, #1
    cmp     x21, x19
    b.ge    .Lpa_done

    lsl     x0, x21, #3
    ldr     x0, [x20, x0]
    bl      parse_port
    cmp     x0, #0
    b.le    .Lpa_next

    adrp    x1, g_mesh_port
    add     x1, x1, :lo12:g_mesh_port
    str     w0, [x1]
    b       .Lpa_next

.Lpa_check_peer:
    // Check for --peer
    adrp    x0, arg_peer
    add     x0, x0, :lo12:arg_peer
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_node_id

    // Found --peer, get next arg (HOST:PORT format)
    add     x21, x21, #1
    cmp     x21, x19
    b.ge    .Lpa_done

    lsl     x0, x21, #3
    ldr     x0, [x20, x0]       // argv[i+1] = "HOST:PORT"
    bl      parse_host_port
    b       .Lpa_next

.Lpa_check_node_id:
    // Check for --node-id
    adrp    x0, arg_node_id
    add     x0, x0, :lo12:arg_node_id
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_no_mesh

    // Found --node-id, get next arg
    add     x21, x21, #1
    cmp     x21, x19
    b.ge    .Lpa_done

    lsl     x0, x21, #3
    ldr     x0, [x20, x0]
    bl      parse_hex64
    adrp    x1, g_node_id
    add     x1, x1, :lo12:g_node_id
    str     x0, [x1]
    b       .Lpa_next

.Lpa_check_no_mesh:
    // Check for --no-mesh
    adrp    x0, arg_no_mesh
    add     x0, x0, :lo12:arg_no_mesh
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_transport

    // Found --no-mesh
    adrp    x0, g_mesh_enabled
    add     x0, x0, :lo12:g_mesh_enabled
    str     wzr, [x0]
    b       .Lpa_next

.Lpa_check_transport:
    // Check for --transport
    adrp    x0, arg_transport
    add     x0, x0, :lo12:arg_transport
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_serial_device

    // Found --transport, get next arg
    add     x21, x21, #1
    cmp     x21, x19
    b.ge    .Lpa_done

    lsl     x0, x21, #3
    ldr     x23, [x20, x0]          // transport type string(s)

    // Parse transport(s) - may be comma-separated like "tcp,bluetooth"
    bl      parse_transport_list
    b       .Lpa_next

.Lpa_check_serial_device:
    // Check for --serial-device
    adrp    x0, arg_serial_device
    add     x0, x0, :lo12:arg_serial_device
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_serial_baud

    // Found --serial-device, get next arg
    add     x21, x21, #1
    cmp     x21, x19
    b.ge    .Lpa_done

    lsl     x0, x21, #3
    ldr     x23, [x20, x0]          // device path

    // Copy device path to g_serial_device
    adrp    x24, g_serial_device
    add     x24, x24, :lo12:g_serial_device
    mov     x0, x24
    mov     x1, x23
    mov     x2, #63                 // Max length
    bl      strncpy
    b       .Lpa_next

.Lpa_check_serial_baud:
    // Check for --serial-baud
    adrp    x0, arg_serial_baud
    add     x0, x0, :lo12:arg_serial_baud
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_check_udp_port

    // Found --serial-baud, get next arg
    add     x21, x21, #1
    cmp     x21, x19
    b.ge    .Lpa_done

    lsl     x0, x21, #3
    ldr     x0, [x20, x0]
    bl      parse_baud
    cmp     x0, #0
    b.le    .Lpa_next

    adrp    x1, g_serial_baud
    add     x1, x1, :lo12:g_serial_baud
    str     w0, [x1]
    b       .Lpa_next

.Lpa_check_udp_port:
    // Check for --udp-port
    adrp    x0, arg_udp_port
    add     x0, x0, :lo12:arg_udp_port
    mov     x1, x22
    bl      strcmp
    cbnz    x0, .Lpa_next

    // Found --udp-port, get next arg
    add     x21, x21, #1
    cmp     x21, x19
    b.ge    .Lpa_done

    lsl     x0, x21, #3
    ldr     x0, [x20, x0]
    bl      parse_port
    cmp     x0, #0
    b.le    .Lpa_next

    adrp    x1, g_udp_port
    add     x1, x1, :lo12:g_udp_port
    str     w0, [x1]

.Lpa_next:
    add     x21, x21, #1
.Lpa_next_no_inc:
    b       .Lpa_loop

.Lpa_done:
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size parse_args, .-parse_args

// =============================================================================
// strcmp - Compare two null-terminated strings
// =============================================================================
// Input: x0 = str1, x1 = str2
// Output: x0 = 0 if equal, non-zero if different
// =============================================================================
strcmp:
    mov     x2, #0
.Lstrcmp_loop:
    ldrb    w3, [x0, x2]
    ldrb    w4, [x1, x2]
    cmp     w3, w4
    b.ne    .Lstrcmp_diff
    cbz     w3, .Lstrcmp_equal
    add     x2, x2, #1
    b       .Lstrcmp_loop
.Lstrcmp_equal:
    mov     x0, #0
    ret
.Lstrcmp_diff:
    sub     x0, x3, x4
    ret
.size strcmp, .-strcmp

// =============================================================================
// parse_port - Parse port number from string
// =============================================================================
// Input: x0 = string
// Output: x0 = port number (0 if invalid)
// =============================================================================
parse_port:
    mov     x1, #0              // result
    mov     x2, #0              // index
.Lpp_loop:
    ldrb    w3, [x0, x2]
    cbz     w3, .Lpp_done
    cmp     w3, #'0'
    b.lt    .Lpp_invalid
    cmp     w3, #'9'
    b.gt    .Lpp_invalid

    sub     w3, w3, #'0'
    mov     x4, #10
    mul     x1, x1, x4
    add     x1, x1, x3

    add     x2, x2, #1
    cmp     x2, #5              // Max 5 digits
    b.lt    .Lpp_loop

.Lpp_done:
    // Check valid port range (1-65535)
    mov     x4, #65535
    cmp     x1, x4
    b.gt    .Lpp_invalid
    cmp     x1, #1
    b.lt    .Lpp_invalid
    mov     x0, x1
    ret

.Lpp_invalid:
    mov     x0, #0
    ret
.size parse_port, .-parse_port

// =============================================================================
// parse_host_port - Parse HOST:PORT string
// =============================================================================
// Input: x0 = string "HOST:PORT"
// Output: stores in g_initial_peer_host and g_initial_peer_port
// =============================================================================
parse_host_port:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // input string

    // Find colon
    mov     x1, #0
.Lphp_find_colon:
    ldrb    w2, [x19, x1]
    cbz     w2, .Lphp_no_colon  // No colon found
    cmp     w2, #':'
    b.eq    .Lphp_found_colon
    add     x1, x1, #1
    cmp     x1, #15             // Max host length
    b.lt    .Lphp_find_colon

.Lphp_no_colon:
    // No colon or too long - treat as just host with default port
    mov     x1, #15
    b       .Lphp_copy_host

.Lphp_found_colon:
    // x1 = position of colon (= host length)
    mov     x20, x1             // Save colon position

.Lphp_copy_host:
    // Copy host (up to x1 chars)
    adrp    x2, g_initial_peer_host
    add     x2, x2, :lo12:g_initial_peer_host
    mov     x3, #0

.Lphp_copy_loop:
    cmp     x3, x1
    b.ge    .Lphp_copy_done
    cmp     x3, #15
    b.ge    .Lphp_copy_done
    ldrb    w4, [x19, x3]
    strb    w4, [x2, x3]
    add     x3, x3, #1
    b       .Lphp_copy_loop

.Lphp_copy_done:
    strb    wzr, [x2, x3]       // Null terminate

    // Parse port (after colon)
    add     x0, x19, x20
    add     x0, x0, #1          // Skip colon
    bl      parse_port
    cmp     x0, #0
    b.le    .Lphp_default_port

    adrp    x1, g_initial_peer_port
    add     x1, x1, :lo12:g_initial_peer_port
    str     w0, [x1]
    b       .Lphp_done

.Lphp_default_port:
    adrp    x1, g_initial_peer_port
    add     x1, x1, :lo12:g_initial_peer_port
    mov     w0, #9000           // Default mesh port
    str     w0, [x1]

.Lphp_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size parse_host_port, .-parse_host_port

// =============================================================================
// parse_hex64 - Parse hexadecimal 64-bit value
// =============================================================================
// Input: x0 = string (optionally prefixed with 0x)
// Output: x0 = parsed value
// =============================================================================
parse_hex64:
    mov     x1, x0              // input
    mov     x0, #0              // result

    // Skip optional 0x prefix
    ldrb    w2, [x1]
    cmp     w2, #'0'
    b.ne    .Lph_loop
    ldrb    w2, [x1, #1]
    cmp     w2, #'x'
    b.ne    .Lph_loop
    add     x1, x1, #2

.Lph_loop:
    ldrb    w2, [x1], #1
    cbz     w2, .Lph_done

    // Convert hex digit
    cmp     w2, #'0'
    b.lt    .Lph_done
    cmp     w2, #'9'
    b.le    .Lph_digit

    cmp     w2, #'a'
    b.lt    .Lph_upper
    cmp     w2, #'f'
    b.gt    .Lph_done
    sub     w2, w2, #('a' - 10)
    b       .Lph_add

.Lph_upper:
    cmp     w2, #'A'
    b.lt    .Lph_done
    cmp     w2, #'F'
    b.gt    .Lph_done
    sub     w2, w2, #('A' - 10)
    b       .Lph_add

.Lph_digit:
    sub     w2, w2, #'0'

.Lph_add:
    lsl     x0, x0, #4
    add     x0, x0, x2
    b       .Lph_loop

.Lph_done:
    ret
.size parse_hex64, .-parse_hex64

// =============================================================================
// print_num - Print a number
// =============================================================================
// Input: x0 = number
// =============================================================================
print_num:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    mov     x1, x0
    add     x2, sp, #16
    mov     x3, x2
    add     x3, x3, #12
    mov     w0, #0
    strb    w0, [x3]
    sub     x3, x3, #1

    cbz     x1, .Lpn_zero

.Lpn_loop:
    cbz     x1, .Lpn_write
    mov     x4, #10
    udiv    x5, x1, x4
    msub    x6, x5, x4, x1
    add     w6, w6, #'0'
    strb    w6, [x3]
    sub     x3, x3, #1
    mov     x1, x5
    b       .Lpn_loop

.Lpn_zero:
    mov     w0, #'0'
    strb    w0, [x3]
    b       .Lpn_print

.Lpn_write:
    add     x3, x3, #1

.Lpn_print:
    mov     x1, x3
    mov     x2, #0
.Lpn_len:
    ldrb    w4, [x1, x2]
    cbz     w4, .Lpn_do
    add     x2, x2, #1
    b       .Lpn_len
.Lpn_do:
    mov     x0, #1
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #32
    ret
.size print_num, .-print_num

// =============================================================================
// strncpy - Copy string with max length
// =============================================================================
// Input:
//   x0 = dest
//   x1 = src
//   x2 = max length (not including null)
// Output:
//   x0 = dest (null terminated)
// =============================================================================
strncpy:
    mov     x3, x0              // Save dest
    mov     x4, #0              // index
.Lsn_loop:
    cmp     x4, x2
    b.ge    .Lsn_done
    ldrb    w5, [x1, x4]
    strb    w5, [x0, x4]
    cbz     w5, .Lsn_ret        // Source ended
    add     x4, x4, #1
    b       .Lsn_loop
.Lsn_done:
    strb    wzr, [x0, x4]       // Null terminate
.Lsn_ret:
    mov     x0, x3
    ret
.size strncpy, .-strncpy

// =============================================================================
// parse_baud - Parse baud rate from string
// =============================================================================
// Input: x0 = string
// Output: x0 = baud rate (0 if invalid)
// =============================================================================
parse_baud:
    mov     x1, #0              // result
    mov     x2, #0              // index
.Lpb_loop:
    ldrb    w3, [x0, x2]
    cbz     w3, .Lpb_done
    cmp     w3, #'0'
    b.lt    .Lpb_invalid
    cmp     w3, #'9'
    b.gt    .Lpb_invalid

    sub     w3, w3, #'0'
    mov     x4, #10
    mul     x1, x1, x4
    add     x1, x1, x3

    add     x2, x2, #1
    cmp     x2, #10             // Max 10 digits
    b.lt    .Lpb_loop

.Lpb_done:
    // Validate common baud rates
    mov     x4, #9600
    cmp     x1, x4
    b.eq    .Lpb_valid
    mov     x4, #19200
    cmp     x1, x4
    b.eq    .Lpb_valid
    mov     x4, #38400
    cmp     x1, x4
    b.eq    .Lpb_valid
    movz    x4, #0xE100         // 57600
    cmp     x1, x4
    b.eq    .Lpb_valid
    movz    x4, #0xC200         // 115200
    movk    x4, #0x1, lsl #16
    cmp     x1, x4
    b.eq    .Lpb_valid
    movz    x4, #0x8400         // 230400
    movk    x4, #0x3, lsl #16
    cmp     x1, x4
    b.eq    .Lpb_valid
    movz    x4, #0x0800         // 460800
    movk    x4, #0x7, lsl #16
    cmp     x1, x4
    b.eq    .Lpb_valid
    movz    x4, #0x1000         // 921600
    movk    x4, #0xE, lsl #16
    cmp     x1, x4
    b.eq    .Lpb_valid

    // Allow any non-zero value (for custom rates)
    cbnz    x1, .Lpb_valid

.Lpb_invalid:
    mov     x0, #0
    ret

.Lpb_valid:
    mov     x0, x1
    ret
.size parse_baud, .-parse_baud

// =============================================================================
// parse_transport_list - Parse comma-separated transport list
// =============================================================================
// Input: x23 = transport string (e.g., "tcp,bluetooth" or just "tcp")
// Output: none (adds transports to active list, sets g_transport_type)
// =============================================================================
parse_transport_list:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x25, x26, [sp, #48]

    mov     x19, x23                // Input string pointer
    mov     x20, #0                 // First transport flag (0 = not yet set)

    // Allocate temp buffer on stack for single transport name (32 bytes)
    // We'll use sp+56 area (stack frame has room)

.Lptl_loop:
    // Skip leading whitespace/commas
.Lptl_skip_ws:
    ldrb    w21, [x19]
    cbz     w21, .Lptl_done         // End of string
    cmp     w21, #','
    b.eq    .Lptl_next_char
    cmp     w21, #' '
    b.eq    .Lptl_next_char
    cmp     w21, #'\t'
    b.eq    .Lptl_next_char
    b       .Lptl_start_token

.Lptl_next_char:
    add     x19, x19, #1
    b       .Lptl_skip_ws

.Lptl_start_token:
    // x19 points to start of transport name
    mov     x22, x19                // Save start
    mov     x25, #0                 // Length counter

    // Find end of token (comma, space, or null)
.Lptl_scan_token:
    ldrb    w21, [x19, x25]
    cbz     w21, .Lptl_token_end
    cmp     w21, #','
    b.eq    .Lptl_token_end
    cmp     w21, #' '
    b.eq    .Lptl_token_end
    cmp     w21, #'\t'
    b.eq    .Lptl_token_end
    add     x25, x25, #1
    cmp     x25, #31                // Max 31 chars
    b.lt    .Lptl_scan_token

.Lptl_token_end:
    // x22 = start of token, x25 = length
    cbz     x25, .Lptl_advance      // Empty token, skip

    // Copy token to temp buffer (null-terminate)
    sub     sp, sp, #32
    mov     x0, sp
    mov     x1, x22
    mov     x2, x25

.Lptl_copy:
    cbz     x2, .Lptl_copy_done
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     x2, x2, #1
    b       .Lptl_copy

.Lptl_copy_done:
    strb    wzr, [x0]               // Null terminate

    // Convert name to type
    mov     x0, sp
    bl      transport_type_from_string
    mov     x26, x0                 // Save type

    // Free temp buffer
    add     sp, sp, #32

    // Check if valid type
    cmp     x26, #TRANSPORT_NONE
    b.eq    .Lptl_advance           // Invalid, skip

    // Add to active transports
    mov     x0, x26
    bl      transport_add_active

    // If first valid transport, also set g_transport_type for backwards compat
    cbnz    x20, .Lptl_not_first

    // Set g_transport_type
    adrp    x0, g_transport_type
    add     x0, x0, :lo12:g_transport_type
    str     w26, [x0]
    mov     x20, #1                 // Mark first as set

.Lptl_not_first:

.Lptl_advance:
    // Move past this token
    add     x19, x22, x25
    b       .Lptl_loop

.Lptl_done:
    ldp     x25, x26, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size parse_transport_list, .-parse_transport_list
