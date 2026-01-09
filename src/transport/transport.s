// =============================================================================
// Transport Manager - Abstract Transport Layer
// =============================================================================
//
// Manages multiple transport backends through a common interface.
// Each transport registers its ops structure, and the manager routes
// calls to the active transport.
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/transport.inc"

.global transport_register
.global transport_init
.global transport_shutdown
.global transport_send
.global transport_recv
.global transport_get_peers
.global transport_get_quality
.global transport_get_active
.global transport_set_active
.global transport_init_multi
.global transport_add_active
.global transport_get_active_count
.global transport_get_by_index
.global transport_type_from_string
.global g_active_transports
.global g_active_transport_count

.text

// =============================================================================
// transport_register - Register a transport implementation
// =============================================================================
// Input:
//   x0 = transport type (TRANSPORT_TCP, TRANSPORT_SERIAL, etc.)
//   x1 = pointer to transport_ops structure
// Output:
//   x0 = 0 on success, -1 on failure
// =============================================================================

transport_register:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Validate transport type
    cmp     x0, #MAX_TRANSPORTS
    b.ge    .Lreg_invalid

    // Store ops pointer in registry
    adrp    x2, transport_registry
    add     x2, x2, :lo12:transport_registry
    str     x1, [x2, x0, lsl #3]    // registry[type] = ops

    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

.Lreg_invalid:
    mov     x0, #-1
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// transport_init - Initialize the active transport
// =============================================================================
// Input:
//   x0 = pointer to transport_config structure
// Output:
//   x0 = 0 on success, negative errno on failure
// =============================================================================

transport_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save config pointer

    // Get transport type from config
    ldr     w20, [x19, #TRANSPORT_CFG_TYPE]

    // Validate type
    cmp     w20, #MAX_TRANSPORTS
    b.ge    .Linit_invalid

    // Get ops from registry
    adrp    x0, transport_registry
    add     x0, x0, :lo12:transport_registry
    ldr     x0, [x0, x20, lsl #3]

    // Check if transport is registered
    cbz     x0, .Linit_not_registered

    // Store as active transport
    adrp    x1, active_transport_ops
    add     x1, x1, :lo12:active_transport_ops
    str     x0, [x1]

    adrp    x1, active_transport_type
    add     x1, x1, :lo12:active_transport_type
    str     w20, [x1]

    // Call transport's init function
    ldr     x1, [x0, #TRANSPORT_OP_INIT]
    cbz     x1, .Linit_no_init

    mov     x0, x19                     // config pointer
    blr     x1

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Linit_invalid:
    mov     x0, #TRANSPORT_ERR_INVALID
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Linit_not_registered:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Linit_no_init:
    // No init function, but that's OK
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// =============================================================================
// transport_shutdown - Shutdown the active transport
// =============================================================================
// Input: none
// Output: none
// =============================================================================

transport_shutdown:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Get active ops
    adrp    x0, active_transport_ops
    add     x0, x0, :lo12:active_transport_ops
    ldr     x0, [x0]
    cbz     x0, .Lshutdown_done

    // Call shutdown function
    ldr     x1, [x0, #TRANSPORT_OP_SHUTDOWN]
    cbz     x1, .Lshutdown_clear

    blr     x1

.Lshutdown_clear:
    // Clear active transport
    adrp    x0, active_transport_ops
    add     x0, x0, :lo12:active_transport_ops
    str     xzr, [x0]

    adrp    x0, active_transport_type
    add     x0, x0, :lo12:active_transport_type
    str     wzr, [x0]

.Lshutdown_done:
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// transport_send - Send data to a peer
// =============================================================================
// Input:
//   x0 = peer_id
//   x1 = data pointer
//   x2 = data length
// Output:
//   x0 = bytes sent on success, negative errno on failure
// =============================================================================

transport_send:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save peer_id
    mov     x20, x1                     // Save data ptr
    mov     x3, x2                      // Save length in x3

    // Get active ops
    adrp    x0, active_transport_ops
    add     x0, x0, :lo12:active_transport_ops
    ldr     x0, [x0]
    cbz     x0, .Lsend_not_init

    // Get send function
    ldr     x4, [x0, #TRANSPORT_OP_SEND]
    cbz     x4, .Lsend_no_func

    // Call send(peer_id, data, len)
    mov     x0, x19
    mov     x1, x20
    mov     x2, x3
    blr     x4

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lsend_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lsend_no_func:
    mov     x0, #TRANSPORT_ERR_INVALID
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// =============================================================================
// transport_recv - Receive data from transport
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = buffer length
//   x2 = timeout in milliseconds (0 = non-blocking, -1 = infinite)
// Output:
//   x0 = bytes received on success, negative errno on failure
//   x1 = peer_id of sender (if applicable)
// =============================================================================

transport_recv:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save buf ptr
    mov     x20, x1                     // Save buf len
    mov     x3, x2                      // Save timeout

    // Get active ops
    adrp    x0, active_transport_ops
    add     x0, x0, :lo12:active_transport_ops
    ldr     x0, [x0]
    cbz     x0, .Lrecv_not_init

    // Get recv function
    ldr     x4, [x0, #TRANSPORT_OP_RECV]
    cbz     x4, .Lrecv_no_func

    // Call recv(buf, len, timeout)
    mov     x0, x19
    mov     x1, x20
    mov     x2, x3
    blr     x4

    // x0 = bytes received, x1 = peer_id (set by transport)
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lrecv_not_init:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    mov     x1, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lrecv_no_func:
    mov     x0, #TRANSPORT_ERR_INVALID
    mov     x1, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// =============================================================================
// transport_get_peers - Get list of reachable peers
// =============================================================================
// Input:
//   x0 = buffer pointer (array of transport_peer structures)
//   x1 = max number of peers
// Output:
//   x0 = number of peers written to buffer
// =============================================================================

transport_get_peers:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save buf ptr
    mov     x20, x1                     // Save max peers

    // Get active ops
    adrp    x0, active_transport_ops
    add     x0, x0, :lo12:active_transport_ops
    ldr     x0, [x0]
    cbz     x0, .Lpeers_not_init

    // Get get_peers function
    ldr     x2, [x0, #TRANSPORT_OP_GET_PEERS]
    cbz     x2, .Lpeers_no_func

    // Call get_peers(buf, max)
    mov     x0, x19
    mov     x1, x20
    blr     x2

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lpeers_not_init:
    mov     x0, #0                      // No peers
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lpeers_no_func:
    mov     x0, #0                      // No peers
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// =============================================================================
// transport_get_quality - Get link quality to a peer
// =============================================================================
// Input:
//   x0 = peer_id
// Output:
//   x0 = quality score (0-100), or -1 if unknown
// =============================================================================

transport_get_quality:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                     // Save peer_id

    // Get active ops
    adrp    x0, active_transport_ops
    add     x0, x0, :lo12:active_transport_ops
    ldr     x0, [x0]
    cbz     x0, .Lquality_not_init

    // Get link_quality function
    ldr     x1, [x0, #TRANSPORT_OP_LINK_QUALITY]
    cbz     x1, .Lquality_no_func

    // Call get_link_quality(peer_id)
    mov     x0, x19
    blr     x1

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lquality_not_init:
    mov     x0, #-1
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lquality_no_func:
    mov     x0, #-1                     // Unknown
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// =============================================================================
// transport_get_active - Get the active transport type
// =============================================================================
// Output:
//   x0 = transport type (TRANSPORT_*), or TRANSPORT_NONE if none active
// =============================================================================

transport_get_active:
    adrp    x0, active_transport_type
    add     x0, x0, :lo12:active_transport_type
    ldr     w0, [x0]
    ret


// =============================================================================
// transport_set_active - Set the active transport by type
// =============================================================================
// Input:
//   x0 = transport type
// Output:
//   x0 = 0 on success, -1 if transport not registered
// =============================================================================

transport_set_active:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Validate type
    cmp     x0, #MAX_TRANSPORTS
    b.ge    .Lset_invalid

    // Get ops from registry
    mov     x1, x0                      // Save type
    adrp    x2, transport_registry
    add     x2, x2, :lo12:transport_registry
    ldr     x2, [x2, x0, lsl #3]

    // Check if registered
    cbz     x2, .Lset_invalid

    // Set as active
    adrp    x0, active_transport_ops
    add     x0, x0, :lo12:active_transport_ops
    str     x2, [x0]

    adrp    x0, active_transport_type
    add     x0, x0, :lo12:active_transport_type
    str     w1, [x0]

    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

.Lset_invalid:
    mov     x0, #-1
    ldp     x29, x30, [sp], #16
    ret


// =============================================================================
// transport_type_from_string - Convert transport name to type constant
// =============================================================================
// Input:
//   x0 = transport name string (e.g., "tcp", "bluetooth")
// Output:
//   x0 = transport type (TRANSPORT_*), or TRANSPORT_NONE if unknown
// =============================================================================

transport_type_from_string:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                     // Save string pointer

    // Check "tcp"
    adrp    x1, str_tcp
    add     x1, x1, :lo12:str_tcp
    bl      strcasecmp_transport
    cbz     x0, .Ltype_tcp

    // Check "udp"
    mov     x0, x19
    adrp    x1, str_udp
    add     x1, x1, :lo12:str_udp
    bl      strcasecmp_transport
    cbz     x0, .Ltype_udp

    // Check "serial"
    mov     x0, x19
    adrp    x1, str_serial
    add     x1, x1, :lo12:str_serial
    bl      strcasecmp_transport
    cbz     x0, .Ltype_serial

    // Check "bluetooth"
    mov     x0, x19
    adrp    x1, str_bluetooth
    add     x1, x1, :lo12:str_bluetooth
    bl      strcasecmp_transport
    cbz     x0, .Ltype_bluetooth

    // Check "lora"
    mov     x0, x19
    adrp    x1, str_lora
    add     x1, x1, :lo12:str_lora
    bl      strcasecmp_transport
    cbz     x0, .Ltype_lora

    // Check "wifi-mesh"
    mov     x0, x19
    adrp    x1, str_wifi_mesh
    add     x1, x1, :lo12:str_wifi_mesh
    bl      strcasecmp_transport
    cbz     x0, .Ltype_wifi_mesh

    // Unknown
    mov     x0, #TRANSPORT_NONE
    b       .Ltype_done

.Ltype_tcp:
    mov     x0, #TRANSPORT_TCP
    b       .Ltype_done

.Ltype_udp:
    mov     x0, #TRANSPORT_UDP
    b       .Ltype_done

.Ltype_serial:
    mov     x0, #TRANSPORT_SERIAL
    b       .Ltype_done

.Ltype_bluetooth:
    mov     x0, #TRANSPORT_BLUETOOTH
    b       .Ltype_done

.Ltype_lora:
    mov     x0, #TRANSPORT_LORA
    b       .Ltype_done

.Ltype_wifi_mesh:
    mov     x0, #TRANSPORT_WIFI_MESH

.Ltype_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// strcasecmp_transport - Case-insensitive string compare
// Input: x0 = s1, x1 = s2
// Output: x0 = 0 if equal
strcasecmp_transport:
.Lstrcasecmp_t_loop:
    ldrb    w2, [x0], #1
    ldrb    w3, [x1], #1

    // Convert to lowercase
    cmp     w2, #'A'
    b.lt    .Lstrcasecmp_t_c1_done
    cmp     w2, #'Z'
    b.gt    .Lstrcasecmp_t_c1_done
    add     w2, w2, #32
.Lstrcasecmp_t_c1_done:
    cmp     w3, #'A'
    b.lt    .Lstrcasecmp_t_c2_done
    cmp     w3, #'Z'
    b.gt    .Lstrcasecmp_t_c2_done
    add     w3, w3, #32
.Lstrcasecmp_t_c2_done:

    cmp     w2, w3
    b.ne    .Lstrcasecmp_t_diff
    cbz     w2, .Lstrcasecmp_t_equal
    b       .Lstrcasecmp_t_loop

.Lstrcasecmp_t_equal:
    mov     x0, #0
    ret

.Lstrcasecmp_t_diff:
    mov     x0, #1
    ret


// =============================================================================
// transport_add_active - Add a transport to the active list
// =============================================================================
// Input:
//   x0 = transport type (TRANSPORT_*)
// Output:
//   x0 = 0 on success, negative on error
// =============================================================================

transport_add_active:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save transport type

    // Check if already at max
    adrp    x0, g_active_transport_count
    add     x0, x0, :lo12:g_active_transport_count
    ldr     w20, [x0]
    cmp     w20, #MAX_ACTIVE_TRANSPORTS
    b.ge    .Ladd_full

    // Check if transport is registered
    adrp    x0, transport_registry
    add     x0, x0, :lo12:transport_registry
    ldr     x1, [x0, x19, lsl #3]
    cbz     x1, .Ladd_not_registered

    // Check if already active
    adrp    x0, g_active_transports
    add     x0, x0, :lo12:g_active_transports
    mov     x2, #0

.Ladd_check_dup:
    cmp     w2, w20
    b.ge    .Ladd_do_add

    // Check type at this index
    mov     x3, #ACTIVE_TRANS_SIZE
    mul     x3, x2, x3
    add     x3, x0, x3
    ldr     w4, [x3, #ACTIVE_TRANS_TYPE]
    cmp     w4, w19
    b.eq    .Ladd_already_active

    add     x2, x2, #1
    b       .Ladd_check_dup

.Ladd_do_add:
    // Add to active list
    adrp    x0, g_active_transports
    add     x0, x0, :lo12:g_active_transports
    mov     x2, #ACTIVE_TRANS_SIZE
    mul     x2, x20, x2
    add     x0, x0, x2

    // Set type
    str     w19, [x0, #ACTIVE_TRANS_TYPE]

    // Set fd to -1 (not yet initialized)
    mov     w2, #-1
    str     w2, [x0, #ACTIVE_TRANS_FD]

    // Set ops pointer
    adrp    x2, transport_registry
    add     x2, x2, :lo12:transport_registry
    ldr     x2, [x2, x19, lsl #3]
    str     x2, [x0, #ACTIVE_TRANS_OPS]

    // Set flags
    mov     w2, #ACTIVE_TRANS_FLAG_ENABLED
    str     w2, [x0, #ACTIVE_TRANS_FLAGS]

    // Increment count
    add     w20, w20, #1
    adrp    x0, g_active_transport_count
    add     x0, x0, :lo12:g_active_transport_count
    str     w20, [x0]

    // Also set as active transport if first one
    cmp     w20, #1
    b.ne    .Ladd_success

    adrp    x0, active_transport_type
    add     x0, x0, :lo12:active_transport_type
    str     w19, [x0]

    adrp    x0, transport_registry
    add     x0, x0, :lo12:transport_registry
    ldr     x1, [x0, x19, lsl #3]
    adrp    x0, active_transport_ops
    add     x0, x0, :lo12:active_transport_ops
    str     x1, [x0]

.Ladd_success:
    mov     x0, #0
    b       .Ladd_done

.Ladd_full:
    mov     x0, #TRANSPORT_ERR_FULL
    b       .Ladd_done

.Ladd_not_registered:
    mov     x0, #TRANSPORT_ERR_NOT_INIT
    b       .Ladd_done

.Ladd_already_active:
    mov     x0, #0                      // Not an error, just skip

.Ladd_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret


// =============================================================================
// transport_init_multi - Initialize all active transports
// =============================================================================
// Input:
//   x0 = pointer to transport_config structure (used for all transports)
// Output:
//   x0 = number of transports successfully initialized
// =============================================================================

transport_init_multi:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save config pointer
    mov     x20, #0                     // Current index
    mov     x21, #0                     // Success count

    // Get count
    adrp    x0, g_active_transport_count
    add     x0, x0, :lo12:g_active_transport_count
    ldr     w22, [x0]

.Linit_multi_loop:
    cmp     w20, w22
    b.ge    .Linit_multi_done

    // Get transport entry
    adrp    x0, g_active_transports
    add     x0, x0, :lo12:g_active_transports
    mov     x1, #ACTIVE_TRANS_SIZE
    mul     x1, x20, x1
    add     x0, x0, x1

    // Get ops pointer
    ldr     x1, [x0, #ACTIVE_TRANS_OPS]
    cbz     x1, .Linit_multi_next

    // Get init function
    ldr     x2, [x1, #TRANSPORT_OP_INIT]
    cbz     x2, .Linit_multi_no_init

    // Update config with this transport type
    ldr     w3, [x0, #ACTIVE_TRANS_TYPE]
    str     w3, [x19, #TRANSPORT_CFG_TYPE]

    // Call init
    str     x0, [sp, #-16]!             // Save entry pointer
    mov     x0, x19
    blr     x2
    ldr     x1, [sp], #16               // Restore entry pointer

    // Check result
    cmp     x0, #0
    b.lt    .Linit_multi_next

    // Store fd if returned
    str     w0, [x1, #ACTIVE_TRANS_FD]

.Linit_multi_no_init:
    add     x21, x21, #1

.Linit_multi_next:
    add     x20, x20, #1
    b       .Linit_multi_loop

.Linit_multi_done:
    mov     x0, x21                     // Return success count

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret


// =============================================================================
// transport_get_active_count - Get number of active transports
// =============================================================================
// Output:
//   x0 = number of active transports
// =============================================================================

transport_get_active_count:
    adrp    x0, g_active_transport_count
    add     x0, x0, :lo12:g_active_transport_count
    ldr     w0, [x0]
    ret


// =============================================================================
// transport_get_by_index - Get active transport info by index
// =============================================================================
// Input:
//   x0 = index (0 to count-1)
// Output:
//   x0 = pointer to active transport entry, or NULL if invalid index
// =============================================================================

transport_get_by_index:
    // Check bounds
    adrp    x1, g_active_transport_count
    add     x1, x1, :lo12:g_active_transport_count
    ldr     w1, [x1]
    cmp     w0, w1
    b.ge    .Lget_idx_invalid

    // Calculate pointer
    adrp    x1, g_active_transports
    add     x1, x1, :lo12:g_active_transports
    mov     x2, #ACTIVE_TRANS_SIZE
    mul     x2, x0, x2
    add     x0, x1, x2
    ret

.Lget_idx_invalid:
    mov     x0, #0
    ret


// =============================================================================
// transport_select_for_peer - Select best transport for reaching a peer
// =============================================================================
// Input:
//   x0 = peer's preferred transport type (from peer entry)
//   x1 = flags (0 = default, 1 = prefer_offline, 2 = prefer_internet)
// Output:
//   x0 = best transport type to use, or TRANSPORT_NONE if no suitable transport
// =============================================================================
.global transport_select_for_peer
.type transport_select_for_peer, %function
transport_select_for_peer:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // peer's transport
    mov     x20, x1                     // flags

    // First check if peer's transport is active
    cbz     x19, .Ltsfp_fallback        // No transport = try fallback

    // Check if peer's preferred transport is active
    adrp    x0, g_active_transport_count
    add     x0, x0, :lo12:g_active_transport_count
    ldr     w21, [x0]                   // active count

    cbz     w21, .Ltsfp_none            // No active transports

    // Search active transports for peer's preferred
    adrp    x0, g_active_transports
    add     x0, x0, :lo12:g_active_transports
    mov     x22, #0                     // index

.Ltsfp_search:
    cmp     w22, w21
    b.ge    .Ltsfp_fallback             // Not found, try fallback

    // Get transport type at this index
    mov     x1, #ACTIVE_TRANS_SIZE
    mul     x1, x22, x1
    add     x1, x0, x1
    ldr     w2, [x1, #ACTIVE_TRANS_TYPE]

    cmp     w2, w19
    b.eq    .Ltsfp_found

    add     x22, x22, #1
    b       .Ltsfp_search

.Ltsfp_found:
    // Peer's preferred transport is active, use it
    mov     x0, x19
    b       .Ltsfp_done

.Ltsfp_fallback:
    // Peer's transport not available, select based on priority
    // Priority order for prefer_offline (flag=1): serial, bluetooth, lora, wifi-mesh, tcp, udp
    // Priority order for prefer_internet (flag=2): tcp, udp, wifi-mesh, bluetooth, serial, lora
    // Default (flag=0): tcp, serial, bluetooth, udp, wifi-mesh, lora

    cmp     x20, #1
    b.eq    .Ltsfp_offline_priority
    cmp     x20, #2
    b.eq    .Ltsfp_internet_priority

    // Default priority order
    mov     x0, #TRANSPORT_TCP
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_tcp
    mov     x0, #TRANSPORT_SERIAL
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_serial
    mov     x0, #TRANSPORT_BLUETOOTH
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_bluetooth
    mov     x0, #TRANSPORT_UDP
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_udp
    mov     x0, #TRANSPORT_WIFI_MESH
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_wmesh
    mov     x0, #TRANSPORT_LORA
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_lora
    b       .Ltsfp_none

.Ltsfp_offline_priority:
    // Offline-first: serial, bluetooth, lora, wifi-mesh, tcp, udp
    mov     x0, #TRANSPORT_SERIAL
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_serial
    mov     x0, #TRANSPORT_BLUETOOTH
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_bluetooth
    mov     x0, #TRANSPORT_LORA
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_lora
    mov     x0, #TRANSPORT_WIFI_MESH
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_wmesh
    mov     x0, #TRANSPORT_TCP
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_tcp
    mov     x0, #TRANSPORT_UDP
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_udp
    b       .Ltsfp_none

.Ltsfp_internet_priority:
    // Internet-first: tcp, udp, wifi-mesh, bluetooth, serial, lora
    mov     x0, #TRANSPORT_TCP
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_tcp
    mov     x0, #TRANSPORT_UDP
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_udp
    mov     x0, #TRANSPORT_WIFI_MESH
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_wmesh
    mov     x0, #TRANSPORT_BLUETOOTH
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_bluetooth
    mov     x0, #TRANSPORT_SERIAL
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_serial
    mov     x0, #TRANSPORT_LORA
    bl      transport_is_active
    cbnz    x0, .Ltsfp_return_lora
    b       .Ltsfp_none

.Ltsfp_return_tcp:
    mov     x0, #TRANSPORT_TCP
    b       .Ltsfp_done
.Ltsfp_return_udp:
    mov     x0, #TRANSPORT_UDP
    b       .Ltsfp_done
.Ltsfp_return_serial:
    mov     x0, #TRANSPORT_SERIAL
    b       .Ltsfp_done
.Ltsfp_return_bluetooth:
    mov     x0, #TRANSPORT_BLUETOOTH
    b       .Ltsfp_done
.Ltsfp_return_lora:
    mov     x0, #TRANSPORT_LORA
    b       .Ltsfp_done
.Ltsfp_return_wmesh:
    mov     x0, #TRANSPORT_WIFI_MESH
    b       .Ltsfp_done

.Ltsfp_none:
    mov     x0, #TRANSPORT_NONE

.Ltsfp_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size transport_select_for_peer, .-transport_select_for_peer


// =============================================================================
// transport_is_active - Check if a transport type is in the active list
// =============================================================================
// Input:
//   x0 = transport type
// Output:
//   x0 = 1 if active, 0 if not
// =============================================================================
.global transport_is_active
.type transport_is_active, %function
transport_is_active:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x1, x0                      // save type to check

    // Get count
    adrp    x0, g_active_transport_count
    add     x0, x0, :lo12:g_active_transport_count
    ldr     w2, [x0]

    cbz     w2, .Ltia_not_found

    // Search
    adrp    x0, g_active_transports
    add     x0, x0, :lo12:g_active_transports
    mov     x3, #0                      // index

.Ltia_loop:
    cmp     w3, w2
    b.ge    .Ltia_not_found

    // Get type at index
    mov     x4, #ACTIVE_TRANS_SIZE
    mul     x4, x3, x4
    add     x4, x0, x4
    ldr     w5, [x4, #ACTIVE_TRANS_TYPE]

    cmp     w5, w1
    b.eq    .Ltia_found

    add     x3, x3, #1
    b       .Ltia_loop

.Ltia_found:
    mov     x0, #1
    b       .Ltia_done

.Ltia_not_found:
    mov     x0, #0

.Ltia_done:
    ldp     x29, x30, [sp], #16
    ret
.size transport_is_active, .-transport_is_active


// =============================================================================
// transport_get_priority - Get transport priority for routing
// =============================================================================
// Input:
//   x0 = transport type
// Output:
//   x0 = priority score (higher = better, 0 = not supported)
// =============================================================================
.global transport_get_priority
.type transport_get_priority, %function
transport_get_priority:
    // Return priority based on typical latency/reliability
    // TCP: 100 (most reliable for general use)
    // Serial: 90 (direct, low latency)
    // Bluetooth: 80 (short range but fast)
    // UDP: 70 (fast but unreliable)
    // WiFi Mesh: 60 (medium range, variable)
    // LoRa: 50 (long range but slow)

    cmp     x0, #TRANSPORT_TCP
    b.eq    .Lpriority_tcp
    cmp     x0, #TRANSPORT_SERIAL
    b.eq    .Lpriority_serial
    cmp     x0, #TRANSPORT_BLUETOOTH
    b.eq    .Lpriority_bluetooth
    cmp     x0, #TRANSPORT_UDP
    b.eq    .Lpriority_udp
    cmp     x0, #TRANSPORT_WIFI_MESH
    b.eq    .Lpriority_wmesh
    cmp     x0, #TRANSPORT_LORA
    b.eq    .Lpriority_lora

    mov     x0, #0                      // Unknown
    ret

.Lpriority_tcp:
    mov     x0, #100
    ret
.Lpriority_serial:
    mov     x0, #90
    ret
.Lpriority_bluetooth:
    mov     x0, #80
    ret
.Lpriority_udp:
    mov     x0, #70
    ret
.Lpriority_wmesh:
    mov     x0, #60
    ret
.Lpriority_lora:
    mov     x0, #50
    ret
.size transport_get_priority, .-transport_get_priority


// =============================================================================
// Data Section
// =============================================================================

.data

// Registry of transport ops (indexed by type)
// Up to MAX_TRANSPORTS entries, each is a pointer to transport_ops
transport_registry:
    .space  MAX_TRANSPORTS * 8, 0

// Currently active transport (for backwards compatibility)
active_transport_ops:
    .quad   0

active_transport_type:
    .word   TRANSPORT_NONE
    .balign 8

// Multi-transport support
g_active_transports:
    .space  MAX_ACTIVE_TRANSPORTS * ACTIVE_TRANS_SIZE, 0

g_active_transport_count:
    .word   0
    .balign 8

// Transport name strings
.section .rodata
str_tcp:        .asciz "tcp"
str_udp:        .asciz "udp"
str_serial:     .asciz "serial"
str_bluetooth:  .asciz "bluetooth"
str_lora:       .asciz "lora"
str_wifi_mesh:  .asciz "wifi-mesh"

