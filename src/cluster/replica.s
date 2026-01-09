// =============================================================================
// Omesh - Replication Manager
// =============================================================================
//
// Primary-replica document replication:
// - replica_init: Initialize ownership table
// - replica_index_doc: Index document and replicate to peers
// - replica_get_primary: Get primary node for document
// - replica_get_replicas: Get replica bitmap for document
// - replica_record_ownership: Record document ownership
// - replica_find_ownership: Find ownership entry by doc ID
// - replica_select_peers: Select replica peers for document
//
// CALLING CONVENTION: AAPCS64
//   - Arguments: x0-x7 (x0 = first arg)
//   - Return value: x0
//   - Callee-saved: x19-x28
//   - Caller-saved: x0-x18
//
// ERROR HANDLING:
//   - Returns 0 or positive value on success, negative errno on failure
//
// PUBLIC API:
//
//   replica_init() -> 0
//       Initialize ownership table and replication state.
//       Must be called before replica_index_doc.
//
//   replica_index_doc(doc_id, content_ptr, content_len) -> term_count | -errno
//       Index document locally and replicate to peers:
//       1. Store in doc_store_put
//       2. Index via fts_index_add
//       3. Record ownership (this node is primary)
//       4. Replicate to selected peers (hash-based selection)
//       Returns number of terms indexed on success.
//
//   replica_get_primary(doc_id) -> node_id | -ENOENT
//       Lookup primary node for document.
//       Returns -ENOENT if document not in ownership table.
//
//   replica_get_replicas(doc_id) -> bitmap | -ENOENT
//       Return bitmap of nodes holding replicas.
//       Returns -ENOENT if document not found.
//
//   replica_record_ownership(doc_id, primary_node_id, replica_bitmap) -> 0 | -errno
//       Record document ownership entry.
//       Returns -ENOMEM if ownership table full.
//
//   replica_find_ownership(doc_id) -> entry_ptr | -ENOENT
//       Find ownership entry by document ID.
//       Returns pointer to DOCOWN structure or -ENOENT.
//
//   replica_select_peers(doc_id) -> bitmap
//       Select replica peers using hash-based selection.
//       Returns bitmap of peer indices to replicate to.
//
// INTERNAL STATE:
//   g_doc_ownership   - Array of DOCOWN_SIZE * CLUSTER_MAX_DOCS entries
//   g_ownership_count - Number of entries in ownership table
//
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"
.include "cluster.inc"

.data

// =============================================================================
// Ownership Table
// =============================================================================

.align 8
.global g_doc_ownership
g_doc_ownership:
    .skip   DOCOWN_SIZE * CLUSTER_MAX_DOCS

.global g_ownership_count
g_ownership_count:
    .quad   0

// Message buffer for replication
.align 8
replica_msg_buf:
    .skip   NET_MAX_MSG_SIZE + MSG_HDR_SIZE

.text

// =============================================================================
// replica_init - Initialize replication manager
// =============================================================================
// Output:
//   x0 = 0
// =============================================================================
.global replica_init
.type replica_init, %function
replica_init:
    // Clear ownership count
    adrp    x0, g_ownership_count
    add     x0, x0, :lo12:g_ownership_count
    str     xzr, [x0]

    // Clear ownership table (zero doc_id means free slot)
    adrp    x0, g_doc_ownership
    add     x0, x0, :lo12:g_doc_ownership
    mov     x1, #(DOCOWN_SIZE * CLUSTER_MAX_DOCS)
.Lreplica_init_clear:
    cbz     x1, .Lreplica_init_done
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       .Lreplica_init_clear

.Lreplica_init_done:
    mov     x0, #0
    ret
.size replica_init, .-replica_init

// =============================================================================
// replica_find_ownership - Find ownership entry by document ID
// =============================================================================
// Input:
//   x0 = document ID
// Output:
//   x0 = pointer to ownership entry, or NULL if not found
// =============================================================================
.global replica_find_ownership
.type replica_find_ownership, %function
replica_find_ownership:
    cbz     x0, .Lfind_not_found        // Doc ID 0 is invalid

    adrp    x1, g_doc_ownership
    add     x1, x1, :lo12:g_doc_ownership
    adrp    x2, g_ownership_count
    add     x2, x2, :lo12:g_ownership_count
    ldr     x2, [x2]

    cbz     x2, .Lfind_not_found        // Empty table

    mov     x3, #0                      // Index
.Lfind_loop:
    cmp     x3, x2
    b.hs    .Lfind_not_found

    // Check doc ID at current slot
    ldr     x4, [x1, #DOCOWN_OFF_DOC_ID]
    cmp     x4, x0
    b.eq    .Lfind_found

    // Next slot
    add     x1, x1, #DOCOWN_SIZE
    add     x3, x3, #1
    b       .Lfind_loop

.Lfind_found:
    mov     x0, x1
    ret

.Lfind_not_found:
    mov     x0, #0
    ret
.size replica_find_ownership, .-replica_find_ownership

// =============================================================================
// replica_alloc_ownership - Allocate new ownership entry
// =============================================================================
// Input:
//   x0 = document ID
// Output:
//   x0 = pointer to new entry, or NULL if full
// =============================================================================
.global replica_alloc_ownership
.type replica_alloc_ownership, %function
replica_alloc_ownership:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                     // Doc ID

    // Check if already exists
    bl      replica_find_ownership
    cbnz    x0, .Lalloc_exists

    // Check capacity
    adrp    x0, g_ownership_count
    add     x0, x0, :lo12:g_ownership_count
    ldr     x1, [x0]
    cmp     x1, #CLUSTER_MAX_DOCS
    b.hs    .Lalloc_full

    // Allocate new slot
    mov     x2, #DOCOWN_SIZE
    mul     x2, x1, x2
    adrp    x3, g_doc_ownership
    add     x3, x3, :lo12:g_doc_ownership
    add     x3, x3, x2                  // Pointer to new slot

    // Initialize entry
    str     x19, [x3, #DOCOWN_OFF_DOC_ID]
    str     xzr, [x3, #DOCOWN_OFF_PRIMARY]
    str     xzr, [x3, #DOCOWN_OFF_REPLICAS]

    // Increment count
    add     x1, x1, #1
    str     x1, [x0]

    mov     x0, x3
    b       .Lalloc_ret

.Lalloc_exists:
    // Return existing entry
    b       .Lalloc_ret

.Lalloc_full:
    mov     x0, #0

.Lalloc_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size replica_alloc_ownership, .-replica_alloc_ownership

// =============================================================================
// replica_record_ownership - Record document ownership
// =============================================================================
// Input:
//   x0 = document ID
//   x1 = primary node ID
//   x2 = replicas bitmap
// Output:
//   x0 = 0 on success, -errno on failure
// =============================================================================
.global replica_record_ownership
.type replica_record_ownership, %function
replica_record_ownership:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Doc ID
    mov     x20, x1                     // Primary
    mov     x21, x2                     // Replicas

    // Allocate or find entry
    mov     x0, x19
    bl      replica_alloc_ownership
    cbz     x0, .Lrecord_full

    // Store ownership info
    str     x19, [x0, #DOCOWN_OFF_DOC_ID]
    str     x20, [x0, #DOCOWN_OFF_PRIMARY]
    str     x21, [x0, #DOCOWN_OFF_REPLICAS]

    mov     x0, #0
    b       .Lrecord_ret

.Lrecord_full:
    mov     x0, #-28                    // -ENOSPC

.Lrecord_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size replica_record_ownership, .-replica_record_ownership

// =============================================================================
// replica_get_primary - Get primary node for document
// =============================================================================
// Input:
//   x0 = document ID
// Output:
//   x0 = primary node ID, or 0 if not found
// =============================================================================
.global replica_get_primary
.type replica_get_primary, %function
replica_get_primary:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      replica_find_ownership
    cbz     x0, .Lget_primary_none

    ldr     x0, [x0, #DOCOWN_OFF_PRIMARY]
    b       .Lget_primary_ret

.Lget_primary_none:
    mov     x0, #0

.Lget_primary_ret:
    ldp     x29, x30, [sp], #16
    ret
.size replica_get_primary, .-replica_get_primary

// =============================================================================
// replica_get_replicas - Get replica bitmap for document
// =============================================================================
// Input:
//   x0 = document ID
// Output:
//   x0 = replica bitmap, or 0 if not found
// =============================================================================
.global replica_get_replicas
.type replica_get_replicas, %function
replica_get_replicas:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      replica_find_ownership
    cbz     x0, .Lget_replicas_none

    ldr     x0, [x0, #DOCOWN_OFF_REPLICAS]
    b       .Lget_replicas_ret

.Lget_replicas_none:
    mov     x0, #0

.Lget_replicas_ret:
    ldp     x29, x30, [sp], #16
    ret
.size replica_get_replicas, .-replica_get_replicas

// =============================================================================
// replica_select_peers - Select replica peers using hash
// =============================================================================
// Input:
//   x0 = document ID
//   x1 = peer count (available peers)
// Output:
//   x0 = bitmap of selected peer indices
// Note:
//   Selects up to CLUSTER_REPLICATION_FACTOR peers using hash-based selection.
//   Skips index 0 (self) if selected.
// =============================================================================
.global replica_select_peers
.type replica_select_peers, %function
replica_select_peers:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Doc ID
    mov     x20, x1                     // Peer count

    // No peers available
    cbz     x20, .Lselect_none

    // Simple hash-based selection
    // Use doc_id bits to select peer indices
    mov     x0, #0                      // Result bitmap
    mov     x2, #0                      // Selected count

.Lselect_loop:
    cmp     x2, #CLUSTER_REPLICATION_FACTOR
    b.hs    .Lselect_done

    // Calculate peer index: (doc_id >> (8*i)) % peer_count
    mov     x3, #8
    mul     x3, x3, x2                  // Shift amount
    lsr     x4, x19, x3                 // Shifted doc_id
    udiv    x5, x4, x20                 // Quotient
    msub    x4, x5, x20, x4             // Remainder = index

    // Set bit in bitmap
    mov     x5, #1
    lsl     x5, x5, x4
    orr     x0, x0, x5

    add     x2, x2, #1
    b       .Lselect_loop

.Lselect_done:
    b       .Lselect_ret

.Lselect_none:
    mov     x0, #0

.Lselect_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size replica_select_peers, .-replica_select_peers

// =============================================================================
// replica_index_doc - Index document locally and replicate
// =============================================================================
// Input:
//   x0 = document ID
//   x1 = content pointer
//   x2 = content length
// Output:
//   x0 = 0 on success, -errno on failure
//
// This is the primary entry point for indexing a document. It:
// 1. Stores document locally (in full impl, calls doc_store_put)
// 2. Indexes document locally (in full impl, calls fts_index_add)
// 3. Records this node as primary owner
// 4. Selects replica peers and sends INDEX messages
// =============================================================================
.global replica_index_doc
.type replica_index_doc, %function
replica_index_doc:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // Doc ID
    mov     x20, x1                     // Content
    mov     x21, x2                     // Length

    // Validate inputs
    cbz     x19, .Lindex_doc_invalid
    cbz     x20, .Lindex_doc_invalid

    // Index document for full-text search
    mov     x0, x19                     // Doc ID
    mov     x1, x20                     // Content
    mov     x2, x21                     // Length
    bl      fts_index_add
    cmp     x0, #0
    b.lt    .Lindex_doc_ret             // Return error from fts_index_add

    // Update node document count
    bl      node_inc_doc_count

    // Get our node ID
    bl      node_get_id
    mov     x22, x0                     // Our node ID

    // Get peer count for replica selection
    bl      node_get_peer_count
    mov     x23, x0

    // Select replica peers
    mov     x0, x19                     // Doc ID
    mov     x1, x23                     // Peer count
    bl      replica_select_peers
    mov     x24, x0                     // Replica bitmap

    // Record ownership (we are primary)
    mov     x0, x19                     // Doc ID
    mov     x1, x22                     // Primary = us
    mov     x2, x24                     // Replicas
    bl      replica_record_ownership
    cmp     x0, #0
    b.lt    .Lindex_doc_ret

    // Send INDEX message to replica peers
    cbz     x24, .Lindex_doc_success    // No replicas needed

    // mesh_send_index(doc_id, operation, content, length, peer_bitmap)
    mov     x0, x19                     // Doc ID
    mov     w1, #INDEX_OP_PUT           // Operation
    mov     x2, x20                     // Content
    mov     w3, w21                     // Length
    mov     x4, x24                     // Peer bitmap
    bl      mesh_send_index
    // Ignore send errors - document is still indexed locally

.Lindex_doc_success:
    mov     x0, #0
    b       .Lindex_doc_ret

.Lindex_doc_invalid:
    mov     x0, #-22                    // -EINVAL

.Lindex_doc_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size replica_index_doc, .-replica_index_doc

// =============================================================================
// replica_delete_doc - Delete document and propagate
// =============================================================================
// Input:
//   x0 = document ID
// Output:
//   x0 = 0 on success, -errno on failure
// =============================================================================
.global replica_delete_doc
.type replica_delete_doc, %function
replica_delete_doc:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Doc ID

    // Validate
    cbz     x19, .Ldelete_doc_invalid

    // Find ownership entry
    mov     x0, x19
    bl      replica_find_ownership
    cbz     x0, .Ldelete_doc_notfound
    mov     x20, x0                     // Ownership entry

    // Get replica bitmap before deleting
    ldr     x21, [x20, #DOCOWN_OFF_REPLICAS]

    // Clear the ownership entry (mark as free)
    str     xzr, [x20, #DOCOWN_OFF_DOC_ID]
    str     xzr, [x20, #DOCOWN_OFF_PRIMARY]
    str     xzr, [x20, #DOCOWN_OFF_REPLICAS]

    // In full implementation:
    // 1. Call doc_store_delete(doc_id)
    // 2. Call fts_index_remove(doc_id)

    // Decrement document count
    bl      node_dec_doc_count

    // Build DELETE message for replicas
    cbz     x21, .Ldelete_doc_success   // No replicas

    adrp    x0, replica_msg_buf
    add     x0, x0, :lo12:replica_msg_buf
    mov     x1, x19                     // Doc ID
    mov     x2, #INDEX_OP_DELETE        // Operation
    mov     x3, #0                      // No data
    mov     x4, #0                      // No length
    bl      build_index_msg
    cmp     x0, #0
    b.lt    .Ldelete_doc_ret

    // Would send to replicas here

.Ldelete_doc_success:
    mov     x0, #0
    b       .Ldelete_doc_ret

.Ldelete_doc_invalid:
    mov     x0, #-22                    // -EINVAL
    b       .Ldelete_doc_ret

.Ldelete_doc_notfound:
    mov     x0, #-2                     // -ENOENT

.Ldelete_doc_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size replica_delete_doc, .-replica_delete_doc

// =============================================================================
// replica_get_ownership_count - Get count of owned documents
// =============================================================================
// Output:
//   x0 = ownership count
// =============================================================================
.global replica_get_ownership_count
.type replica_get_ownership_count, %function
replica_get_ownership_count:
    adrp    x0, g_ownership_count
    add     x0, x0, :lo12:g_ownership_count
    ldr     x0, [x0]
    ret
.size replica_get_ownership_count, .-replica_get_ownership_count

// =============================================================================
// replica_is_primary - Check if we are primary for document
// =============================================================================
// Input:
//   x0 = document ID
// Output:
//   x0 = 1 if we are primary, 0 otherwise
// =============================================================================
.global replica_is_primary
.type replica_is_primary, %function
replica_is_primary:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                     // Doc ID

    // Get primary
    bl      replica_get_primary
    cbz     x0, .Lis_primary_no

    mov     x19, x0                     // Primary node ID

    // Get our node ID
    bl      node_get_id

    // Compare
    cmp     x0, x19
    b.ne    .Lis_primary_no

    mov     x0, #1
    b       .Lis_primary_ret

.Lis_primary_no:
    mov     x0, #0

.Lis_primary_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size replica_is_primary, .-replica_is_primary
