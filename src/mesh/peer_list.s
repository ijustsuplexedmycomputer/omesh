// =============================================================================
// Omesh - Peer List Management
// =============================================================================
//
// Manages the list of known peers for mesh networking.
//
// Public API:
//   peer_list_init()                    - Initialize peer list
//   peer_list_add(host, port, node_id)  - Add a peer
//   peer_list_remove(node_id)           - Remove a peer
//   peer_list_get(index)                - Get peer by index
//   peer_list_find(node_id)             - Find peer by node ID
//   peer_list_count()                   - Number of known peers
//   peer_list_save(path)                - Save to disk
//   peer_list_load(path)                - Load from disk
//   peer_list_set_local_id(node_id)     - Set our node ID
//
// =============================================================================

.include "syscall_nums.inc"
.include "mesh.inc"
.include "transport.inc"

// =============================================================================
// Data Section
// =============================================================================

.section .data
.align 3

// Peer list storage (header + entries)
// Total size: 32 (header) + 64 * 48 (entries) = 3104 bytes
peer_list_data:
    .word   PEERLIST_MAGIC          // Magic
    .word   PEERLIST_VERSION        // Version
    .word   0                       // Count
    .word   MESH_MAX_PEERS          // Capacity
    .quad   0                       // Local node ID
    .quad   0                       // Reserved
    // Entries follow in BSS

.section .bss
.align 3

peer_list_entries:
    .skip   MESH_MAX_PEERS * PEER_ENTRY_SIZE

// =============================================================================
// Read-only Data
// =============================================================================

.section .rodata

default_peer_path:
    .asciz  "./omesh.peers"

// =============================================================================
// Code Section
// =============================================================================

.section .text

// =============================================================================
// peer_list_init - Initialize the peer list
// =============================================================================
// Input: none
// Output:
//   x0 = 0 on success
// =============================================================================
.global peer_list_init
.type peer_list_init, %function
peer_list_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Get header pointer
    adrp    x0, peer_list_data
    add     x0, x0, :lo12:peer_list_data

    // Set magic
    mov     w1, #(PEERLIST_MAGIC & 0xFFFF)
    movk    w1, #(PEERLIST_MAGIC >> 16), lsl #16
    str     w1, [x0, #PEERLIST_OFF_MAGIC]

    // Set version
    mov     w1, #PEERLIST_VERSION
    str     w1, [x0, #PEERLIST_OFF_VERSION]

    // Set count to 0
    str     wzr, [x0, #PEERLIST_OFF_COUNT]

    // Set capacity
    mov     w1, #MESH_MAX_PEERS
    str     w1, [x0, #PEERLIST_OFF_CAPACITY]

    // Clear entries array
    adrp    x0, peer_list_entries
    add     x0, x0, :lo12:peer_list_entries
    mov     x1, #(MESH_MAX_PEERS * PEER_ENTRY_SIZE)
    mov     x2, #0

.Lpli_clear_loop:
    cbz     x1, .Lpli_done
    strb    wzr, [x0, x2]
    add     x2, x2, #1
    sub     x1, x1, #1
    b       .Lpli_clear_loop

.Lpli_done:
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret
.size peer_list_init, .-peer_list_init

// =============================================================================
// peer_list_set_local_id - Set our node ID
// =============================================================================
// Input:
//   x0 = node_id
// Output: none
// =============================================================================
.global peer_list_set_local_id
.type peer_list_set_local_id, %function
peer_list_set_local_id:
    adrp    x1, peer_list_data
    add     x1, x1, :lo12:peer_list_data
    str     x0, [x1, #PEERLIST_OFF_LOCAL_ID]
    ret
.size peer_list_set_local_id, .-peer_list_set_local_id

// =============================================================================
// peer_list_get_local_id - Get our node ID
// =============================================================================
// Input: none
// Output:
//   x0 = node_id
// =============================================================================
.global peer_list_get_local_id
.type peer_list_get_local_id, %function
peer_list_get_local_id:
    adrp    x0, peer_list_data
    add     x0, x0, :lo12:peer_list_data
    ldr     x0, [x0, #PEERLIST_OFF_LOCAL_ID]
    ret
.size peer_list_get_local_id, .-peer_list_get_local_id

// =============================================================================
// peer_list_add - Add a new peer to the list
// =============================================================================
// Input:
//   x0 = host string pointer (null-terminated, max 15 chars)
//   x1 = port number
//   x2 = node_id (0 to auto-assign later)
// Output:
//   x0 = peer index on success, -1 if list full, -2 if duplicate
// =============================================================================
.global peer_list_add
.type peer_list_add, %function
peer_list_add:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // host
    mov     x20, x1             // port
    mov     x21, x2             // node_id

    // Check if peer with this node_id already exists (if node_id != 0)
    cbz     x21, .Lpla_find_slot
    mov     x0, x21
    bl      peer_list_find
    cmp     x0, #0
    b.ge    .Lpla_duplicate

.Lpla_find_slot:
    // Find empty slot
    adrp    x0, peer_list_data
    add     x0, x0, :lo12:peer_list_data
    ldr     w1, [x0, #PEERLIST_OFF_COUNT]
    ldr     w2, [x0, #PEERLIST_OFF_CAPACITY]

    // Check if full
    cmp     w1, w2
    b.ge    .Lpla_full

    // Get entry pointer
    adrp    x3, peer_list_entries
    add     x3, x3, :lo12:peer_list_entries
    mov     x4, #PEER_ENTRY_SIZE
    mul     x4, x1, x4          // offset = count * entry_size
    add     x22, x3, x4         // x22 = entry pointer

    // Store node_id
    str     x21, [x22, #PEER_OFF_NODE_ID]

    // Copy host string (max 15 chars + null)
    add     x0, x22, #PEER_OFF_HOST
    mov     x1, x19
    mov     x2, #0

.Lpla_copy_host:
    cmp     x2, #15
    b.ge    .Lpla_host_done
    ldrb    w3, [x1, x2]
    strb    w3, [x0, x2]
    cbz     w3, .Lpla_host_done
    add     x2, x2, #1
    b       .Lpla_copy_host

.Lpla_host_done:
    // Ensure null termination
    strb    wzr, [x0, x2]

    // Store port
    strh    w20, [x22, #PEER_OFF_PORT]

    // Set initial status
    mov     w0, #PEER_STATUS_UNKNOWN
    strb    w0, [x22, #PEER_OFF_STATUS]

    // Clear flags
    strb    wzr, [x22, #PEER_OFF_FLAGS]

    // Clear last_seen
    str     xzr, [x22, #PEER_OFF_LAST_SEEN]

    // Set conn_fd to -1
    mov     w0, #-1
    str     w0, [x22, #PEER_OFF_CONN_FD]

    // Set default transport (TCP)
    mov     w0, #TRANSPORT_TCP
    strb    w0, [x22, #PEER_OFF_TRANSPORT]

    // Set link quality to unknown (255)
    mov     w0, #255
    strb    w0, [x22, #PEER_OFF_LINK_QUALITY]

    // Increment count
    adrp    x0, peer_list_data
    add     x0, x0, :lo12:peer_list_data
    ldr     w1, [x0, #PEERLIST_OFF_COUNT]
    add     w1, w1, #1
    str     w1, [x0, #PEERLIST_OFF_COUNT]

    // Return index (old count)
    sub     x0, x1, #1
    b       .Lpla_done

.Lpla_full:
    mov     x0, #-1
    b       .Lpla_done

.Lpla_duplicate:
    mov     x0, #-2

.Lpla_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size peer_list_add, .-peer_list_add

// =============================================================================
// peer_list_remove - Remove a peer by node_id
// =============================================================================
// Input:
//   x0 = node_id
// Output:
//   x0 = 0 on success, -1 if not found
// =============================================================================
.global peer_list_remove
.type peer_list_remove, %function
peer_list_remove:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // node_id to remove

    // Find peer index
    bl      peer_list_find
    cmp     x0, #0
    b.lt    .Lplr_not_found

    mov     x20, x0             // index to remove

    // Get entry addresses
    adrp    x1, peer_list_entries
    add     x1, x1, :lo12:peer_list_entries
    mov     x2, #PEER_ENTRY_SIZE
    mul     x3, x20, x2         // offset of entry to remove
    add     x4, x1, x3          // ptr to entry to remove

    // Get count
    adrp    x5, peer_list_data
    add     x5, x5, :lo12:peer_list_data
    ldr     w6, [x5, #PEERLIST_OFF_COUNT]

    // If this is not the last entry, copy last entry here
    sub     w7, w6, #1          // last index
    cmp     w20, w7
    b.ge    .Lplr_just_decrement

    // Copy last entry to removed slot
    mul     x8, x7, x2          // offset of last entry
    add     x9, x1, x8          // ptr to last entry

    // Copy 48 bytes
    mov     x10, #PEER_ENTRY_SIZE
.Lplr_copy_loop:
    cbz     x10, .Lplr_just_decrement
    ldrb    w11, [x9], #1
    strb    w11, [x4], #1
    sub     x10, x10, #1
    b       .Lplr_copy_loop

.Lplr_just_decrement:
    // Decrement count
    sub     w6, w6, #1
    str     w6, [x5, #PEERLIST_OFF_COUNT]

    mov     x0, #0
    b       .Lplr_done

.Lplr_not_found:
    mov     x0, #-1

.Lplr_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size peer_list_remove, .-peer_list_remove

// =============================================================================
// peer_list_get - Get peer entry by index
// =============================================================================
// Input:
//   x0 = index
// Output:
//   x0 = pointer to peer entry, or NULL if invalid index
// =============================================================================
.global peer_list_get
.type peer_list_get, %function
peer_list_get:
    // Check bounds
    adrp    x1, peer_list_data
    add     x1, x1, :lo12:peer_list_data
    ldr     w2, [x1, #PEERLIST_OFF_COUNT]

    cmp     w0, w2
    b.ge    .Lplg_invalid
    cmp     x0, #0
    b.lt    .Lplg_invalid

    // Calculate entry address
    adrp    x1, peer_list_entries
    add     x1, x1, :lo12:peer_list_entries
    mov     x2, #PEER_ENTRY_SIZE
    mul     x2, x0, x2
    add     x0, x1, x2
    ret

.Lplg_invalid:
    mov     x0, #0
    ret
.size peer_list_get, .-peer_list_get

// =============================================================================
// peer_list_find - Find peer by node_id
// =============================================================================
// Input:
//   x0 = node_id
// Output:
//   x0 = index if found, -1 if not found
// =============================================================================
.global peer_list_find
.type peer_list_find, %function
peer_list_find:
    cbz     x0, .Lplf_not_found     // Don't search for node_id 0

    adrp    x1, peer_list_data
    add     x1, x1, :lo12:peer_list_data
    ldr     w2, [x1, #PEERLIST_OFF_COUNT]

    adrp    x3, peer_list_entries
    add     x3, x3, :lo12:peer_list_entries

    mov     x4, #0              // index

.Lplf_loop:
    cmp     w4, w2
    b.ge    .Lplf_not_found

    // Load node_id at this entry
    mov     x5, #PEER_ENTRY_SIZE
    mul     x5, x4, x5
    ldr     x6, [x3, x5]        // node_id at offset 0

    cmp     x6, x0
    b.eq    .Lplf_found

    add     x4, x4, #1
    b       .Lplf_loop

.Lplf_found:
    mov     x0, x4
    ret

.Lplf_not_found:
    mov     x0, #-1
    ret
.size peer_list_find, .-peer_list_find

// =============================================================================
// peer_list_find_by_addr - Find peer by host:port
// =============================================================================
// Input:
//   x0 = host string pointer (null-terminated)
//   w1 = port
// Output:
//   x0 = peer index, or -1 if not found
// =============================================================================
.global peer_list_find_by_addr
.type peer_list_find_by_addr, %function
peer_list_find_by_addr:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // host
    mov     w20, w1             // port

    adrp    x21, peer_list_data
    add     x21, x21, :lo12:peer_list_data
    ldr     w22, [x21, #PEERLIST_OFF_COUNT]

    adrp    x21, peer_list_entries
    add     x21, x21, :lo12:peer_list_entries

    mov     x4, #0              // index

.Lplfa_loop:
    cmp     w4, w22
    b.ge    .Lplfa_not_found

    // Calculate entry address
    mov     x5, #PEER_ENTRY_SIZE
    mul     x5, x4, x5
    add     x5, x21, x5         // entry ptr

    // Check port first (faster)
    ldrh    w6, [x5, #PEER_OFF_PORT]
    cmp     w6, w20
    b.ne    .Lplfa_next

    // Compare host strings
    mov     x0, x19             // search host
    add     x1, x5, #PEER_OFF_HOST
    bl      strcmp_simple
    cbz     x0, .Lplfa_found

.Lplfa_next:
    add     x4, x4, #1
    b       .Lplfa_loop

.Lplfa_found:
    mov     x0, x4
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Lplfa_not_found:
    mov     x0, #-1
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size peer_list_find_by_addr, .-peer_list_find_by_addr

// Simple string compare - returns 0 if equal
strcmp_simple:
    ldrb    w2, [x0], #1
    ldrb    w3, [x1], #1
    cmp     w2, w3
    b.ne    .Lstrcmp_ne
    cbz     w2, .Lstrcmp_eq
    b       strcmp_simple
.Lstrcmp_eq:
    mov     x0, #0
    ret
.Lstrcmp_ne:
    mov     x0, #1
    ret

// =============================================================================
// peer_list_update_node_id - Update peer's node_id
// =============================================================================
// Input:
//   x0 = peer index
//   x1 = new node_id
// Output:
//   x0 = 0 on success, -1 on error
// =============================================================================
.global peer_list_update_node_id
.type peer_list_update_node_id, %function
peer_list_update_node_id:
    adrp    x2, peer_list_data
    add     x2, x2, :lo12:peer_list_data
    ldr     w3, [x2, #PEERLIST_OFF_COUNT]

    // Bounds check
    cmp     x0, x3
    b.ge    .Lpuni_error
    cmp     x0, #0
    b.lt    .Lpuni_error

    // Get entry address
    adrp    x2, peer_list_entries
    add     x2, x2, :lo12:peer_list_entries
    mov     x3, #PEER_ENTRY_SIZE
    mul     x3, x0, x3
    add     x2, x2, x3

    // Store new node_id
    str     x1, [x2, #PEER_OFF_NODE_ID]
    mov     x0, #0
    ret

.Lpuni_error:
    mov     x0, #-1
    ret
.size peer_list_update_node_id, .-peer_list_update_node_id

// =============================================================================
// peer_list_count - Get number of peers
// =============================================================================
// Input: none
// Output:
//   x0 = peer count
// =============================================================================
.global peer_list_count
.type peer_list_count, %function
peer_list_count:
    adrp    x0, peer_list_data
    add     x0, x0, :lo12:peer_list_data
    ldr     w0, [x0, #PEERLIST_OFF_COUNT]
    ret
.size peer_list_count, .-peer_list_count

// =============================================================================
// peer_list_save - Save peer list to file
// =============================================================================
// Input:
//   x0 = path (or NULL for default)
// Output:
//   x0 = 0 on success, -errno on error
// =============================================================================
.global peer_list_save
.type peer_list_save, %function
peer_list_save:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Use default path if NULL
    cbnz    x0, .Lpls_have_path
    adrp    x0, default_peer_path
    add     x0, x0, :lo12:default_peer_path

.Lpls_have_path:
    mov     x19, x0             // path

    // Open file for writing (create/truncate)
    // open(path, O_WRONLY|O_CREAT|O_TRUNC, 0644)
    mov     x1, #(O_WRONLY | O_CREAT | O_TRUNC)
    mov     x2, #0644
    mov     x8, #SYS_openat
    mov     x0, #AT_FDCWD
    mov     x1, x19
    mov     x2, #(O_WRONLY | O_CREAT | O_TRUNC)
    mov     x3, #0644
    svc     #0

    cmp     x0, #0
    b.lt    .Lpls_error

    mov     x20, x0             // fd

    // Write header
    adrp    x1, peer_list_data
    add     x1, x1, :lo12:peer_list_data
    mov     x2, #PEERLIST_HDR_SIZE
    mov     x8, #SYS_write
    svc     #0

    cmp     x0, #PEERLIST_HDR_SIZE
    b.ne    .Lpls_write_error

    // Get count and write entries
    adrp    x1, peer_list_data
    add     x1, x1, :lo12:peer_list_data
    ldr     w3, [x1, #PEERLIST_OFF_COUNT]
    cbz     w3, .Lpls_close

    // Write entries
    mov     x0, x20
    adrp    x1, peer_list_entries
    add     x1, x1, :lo12:peer_list_entries
    mov     x2, #PEER_ENTRY_SIZE
    mul     x2, x3, x2          // count * entry_size
    mov     x8, #SYS_write
    svc     #0

    cmp     x0, #0
    b.lt    .Lpls_write_error

.Lpls_close:
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0

    mov     x0, #0
    b       .Lpls_done

.Lpls_write_error:
    mov     x19, x0             // save error
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0
    mov     x0, x19
    b       .Lpls_done

.Lpls_error:
    // x0 already has error

.Lpls_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size peer_list_save, .-peer_list_save

// =============================================================================
// peer_list_load - Load peer list from file
// =============================================================================
// Input:
//   x0 = path (or NULL for default)
// Output:
//   x0 = number of peers loaded, or -errno on error
// =============================================================================
.global peer_list_load
.type peer_list_load, %function
peer_list_load:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    // Use default path if NULL
    cbnz    x0, .Lpll_have_path
    adrp    x0, default_peer_path
    add     x0, x0, :lo12:default_peer_path

.Lpll_have_path:
    mov     x19, x0             // path

    // Open file for reading
    mov     x0, #AT_FDCWD
    mov     x1, x19
    mov     x2, #O_RDONLY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0

    cmp     x0, #0
    b.lt    .Lpll_error

    mov     x20, x0             // fd

    // Read header into temp buffer on stack
    sub     sp, sp, #32
    mov     x0, x20
    mov     x1, sp
    mov     x2, #PEERLIST_HDR_SIZE
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #PEERLIST_HDR_SIZE
    b.ne    .Lpll_read_error

    // Validate magic
    ldr     w1, [sp, #PEERLIST_OFF_MAGIC]
    mov     w2, #(PEERLIST_MAGIC & 0xFFFF)
    movk    w2, #(PEERLIST_MAGIC >> 16), lsl #16
    cmp     w1, w2
    b.ne    .Lpll_bad_format

    // Validate version
    ldr     w1, [sp, #PEERLIST_OFF_VERSION]
    cmp     w1, #PEERLIST_VERSION
    b.ne    .Lpll_bad_format

    // Get count (limit to capacity)
    ldr     w21, [sp, #PEERLIST_OFF_COUNT]
    cmp     w21, #MESH_MAX_PEERS
    b.le    .Lpll_count_ok
    mov     w21, #MESH_MAX_PEERS
.Lpll_count_ok:

    // Save local_id from header
    ldr     x22, [sp, #PEERLIST_OFF_LOCAL_ID]
    add     sp, sp, #32

    // Read entries if any
    cbz     w21, .Lpll_no_entries

    mov     x0, x20
    adrp    x1, peer_list_entries
    add     x1, x1, :lo12:peer_list_entries
    mov     x2, #PEER_ENTRY_SIZE
    mul     x2, x21, x2
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #0
    b.lt    .Lpll_read_error_noadjust

.Lpll_no_entries:
    // Update header
    adrp    x0, peer_list_data
    add     x0, x0, :lo12:peer_list_data
    str     w21, [x0, #PEERLIST_OFF_COUNT]
    str     x22, [x0, #PEERLIST_OFF_LOCAL_ID]

    // Close file
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0

    // Return count
    mov     x0, x21
    b       .Lpll_done

.Lpll_read_error:
    add     sp, sp, #32

.Lpll_read_error_noadjust:
    mov     x19, x0
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0
    mov     x0, x19
    b       .Lpll_done

.Lpll_bad_format:
    add     sp, sp, #32
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0
    mov     x0, #-22           // -EINVAL
    b       .Lpll_done

.Lpll_error:
    // x0 already has error

.Lpll_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size peer_list_load, .-peer_list_load

// =============================================================================
// peer_list_update_status - Update peer status
// =============================================================================
// Input:
//   x0 = index
//   x1 = new status
// Output:
//   x0 = 0 on success, -1 if invalid index
// =============================================================================
.global peer_list_update_status
.type peer_list_update_status, %function
peer_list_update_status:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x2, x1              // save status

    bl      peer_list_get
    cbz     x0, .Lplus_invalid

    strb    w2, [x0, #PEER_OFF_STATUS]
    mov     x0, #0
    b       .Lplus_done

.Lplus_invalid:
    mov     x0, #-1

.Lplus_done:
    ldp     x29, x30, [sp], #16
    ret
.size peer_list_update_status, .-peer_list_update_status

// =============================================================================
// peer_list_update_last_seen - Update peer last_seen timestamp
// =============================================================================
// Input:
//   x0 = index
// Output:
//   x0 = 0 on success, -1 if invalid index
// =============================================================================
.global peer_list_update_last_seen
.type peer_list_update_last_seen, %function
peer_list_update_last_seen:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    bl      peer_list_get
    cbz     x0, .Lpluls_invalid
    mov     x19, x0

    // Get current time
    sub     sp, sp, #16
    mov     x0, #0              // CLOCK_REALTIME
    mov     x1, sp
    mov     x8, #SYS_clock_gettime
    svc     #0

    ldr     x0, [sp]            // seconds
    add     sp, sp, #16

    str     x0, [x19, #PEER_OFF_LAST_SEEN]
    mov     x0, #0
    b       .Lpluls_done

.Lpluls_invalid:
    mov     x0, #-1

.Lpluls_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size peer_list_update_last_seen, .-peer_list_update_last_seen

// =============================================================================
// peer_list_set_conn_fd - Set connection fd for peer
// =============================================================================
// Input:
//   x0 = index
//   x1 = fd (-1 for disconnected)
// Output:
//   x0 = 0 on success, -1 if invalid index
// =============================================================================
.global peer_list_set_conn_fd
.type peer_list_set_conn_fd, %function
peer_list_set_conn_fd:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x2, x1              // save fd

    bl      peer_list_get
    cbz     x0, .Lplscf_invalid

    str     w2, [x0, #PEER_OFF_CONN_FD]
    mov     x0, #0
    b       .Lplscf_done

.Lplscf_invalid:
    mov     x0, #-1

.Lplscf_done:
    ldp     x29, x30, [sp], #16
    ret
.size peer_list_set_conn_fd, .-peer_list_set_conn_fd

// =============================================================================
// peer_list_set_transport - Set transport type for peer
// =============================================================================
// Input:
//   x0 = index
//   x1 = transport type (TRANSPORT_*)
// Output:
//   x0 = 0 on success, -1 if invalid index
// =============================================================================
.global peer_list_set_transport
.type peer_list_set_transport, %function
peer_list_set_transport:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x2, x1              // save transport

    bl      peer_list_get
    cbz     x0, .Lplst_invalid

    strb    w2, [x0, #PEER_OFF_TRANSPORT]
    mov     x0, #0
    b       .Lplst_done

.Lplst_invalid:
    mov     x0, #-1

.Lplst_done:
    ldp     x29, x30, [sp], #16
    ret
.size peer_list_set_transport, .-peer_list_set_transport

// =============================================================================
// peer_list_get_transport - Get transport type for peer
// =============================================================================
// Input:
//   x0 = index
// Output:
//   x0 = transport type, or TRANSPORT_NONE if invalid index
// =============================================================================
.global peer_list_get_transport
.type peer_list_get_transport, %function
peer_list_get_transport:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      peer_list_get
    cbz     x0, .Lplgt_invalid

    ldrb    w0, [x0, #PEER_OFF_TRANSPORT]
    b       .Lplgt_done

.Lplgt_invalid:
    mov     x0, #TRANSPORT_NONE

.Lplgt_done:
    ldp     x29, x30, [sp], #16
    ret
.size peer_list_get_transport, .-peer_list_get_transport

// =============================================================================
// peer_list_set_link_quality - Set link quality for peer
// =============================================================================
// Input:
//   x0 = index
//   x1 = link quality (0-100, 255=unknown)
// Output:
//   x0 = 0 on success, -1 if invalid index
// =============================================================================
.global peer_list_set_link_quality
.type peer_list_set_link_quality, %function
peer_list_set_link_quality:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x2, x1              // save quality

    bl      peer_list_get
    cbz     x0, .Lplslq_invalid

    strb    w2, [x0, #PEER_OFF_LINK_QUALITY]
    mov     x0, #0
    b       .Lplslq_done

.Lplslq_invalid:
    mov     x0, #-1

.Lplslq_done:
    ldp     x29, x30, [sp], #16
    ret
.size peer_list_set_link_quality, .-peer_list_set_link_quality

// =============================================================================
// peer_list_get_link_quality - Get link quality for peer
// =============================================================================
// Input:
//   x0 = index
// Output:
//   x0 = link quality (0-100), or 255 if unknown/invalid
// =============================================================================
.global peer_list_get_link_quality
.type peer_list_get_link_quality, %function
peer_list_get_link_quality:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      peer_list_get
    cbz     x0, .Lplglq_invalid

    ldrb    w0, [x0, #PEER_OFF_LINK_QUALITY]
    b       .Lplglq_done

.Lplglq_invalid:
    mov     x0, #255            // Unknown

.Lplglq_done:
    ldp     x29, x30, [sp], #16
    ret
.size peer_list_get_link_quality, .-peer_list_get_link_quality

// =============================================================================
// peer_list_find_by_transport - Find peers reachable via specific transport
// =============================================================================
// Input:
//   x0 = transport type (TRANSPORT_*)
//   x1 = buffer for indices
//   x2 = max indices to return
// Output:
//   x0 = number of matching peers
// =============================================================================
.global peer_list_find_by_transport
.type peer_list_find_by_transport, %function
peer_list_find_by_transport:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // transport type to find
    mov     x20, x1             // output buffer
    mov     x21, x2             // max count
    mov     x22, #0             // found count

    // Get peer count
    bl      peer_list_count
    mov     x3, x0              // total peers
    mov     x4, #0              // current index

.Lplfbt_loop:
    cmp     x4, x3
    b.ge    .Lplfbt_done
    cmp     x22, x21            // check if buffer full
    b.ge    .Lplfbt_done

    // Get peer entry
    mov     x0, x4
    bl      peer_list_get
    cbz     x0, .Lplfbt_next

    // Check transport type
    ldrb    w5, [x0, #PEER_OFF_TRANSPORT]
    cmp     w5, w19
    b.ne    .Lplfbt_next

    // Store index in buffer
    str     w4, [x20, x22, lsl #2]
    add     x22, x22, #1

.Lplfbt_next:
    add     x4, x4, #1
    b       .Lplfbt_loop

.Lplfbt_done:
    mov     x0, x22             // return count

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size peer_list_find_by_transport, .-peer_list_find_by_transport

// =============================================================================
// End of peer_list.s
// =============================================================================
