// =============================================================================
// Omesh - Wire Protocol Implementation
// =============================================================================
//
// Message encoding/decoding with CRC32 checksums:
// - msg_init: Initialize message header
// - msg_set_payload: Set message payload
// - msg_finalize: Calculate and set checksum
// - msg_validate: Verify message integrity
// - msg_get_*: Accessor functions
//
// Wire format: 40-byte header + variable payload
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"

// External: crc32_calc defined in docs.s (has hw/sw fallback)
.extern crc32_calc

.text

// =============================================================================
// msg_init - Initialize message header
// =============================================================================
// Input:
//   x0 = buffer pointer (must be at least MSG_HDR_SIZE bytes)
//   x1 = message type
//   x2 = source node ID
//   x3 = destination node ID
// Output:
//   x0 = 0
// =============================================================================
.global msg_init
.type msg_init, %function
msg_init:
    // Store magic number
    ldr     w4, =MSG_MAGIC
    str     w4, [x0, #MSG_OFF_MAGIC]

    // Store version and type
    mov     w4, #MSG_VERSION
    strb    w4, [x0, #MSG_OFF_VERSION]
    strb    w1, [x0, #MSG_OFF_TYPE]

    // Clear flags
    strh    wzr, [x0, #MSG_OFF_FLAGS]

    // Clear sequence number (caller should set if needed)
    str     wzr, [x0, #MSG_OFF_SEQ]

    // Clear length (will be set by msg_set_payload or msg_finalize)
    str     wzr, [x0, #MSG_OFF_LENGTH]

    // Store node IDs
    str     x2, [x0, #MSG_OFF_SRC_NODE]
    str     x3, [x0, #MSG_OFF_DST_NODE]

    // Clear checksum and reserved
    str     wzr, [x0, #MSG_OFF_CHECKSUM]
    str     wzr, [x0, #MSG_OFF_RESERVED]

    mov     x0, #0
    ret
.size msg_init, .-msg_init

// =============================================================================
// msg_set_seq - Set message sequence number
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = sequence number
// Output:
//   x0 = 0
// =============================================================================
.global msg_set_seq
.type msg_set_seq, %function
msg_set_seq:
    str     w1, [x0, #MSG_OFF_SEQ]
    mov     x0, #0
    ret
.size msg_set_seq, .-msg_set_seq

// =============================================================================
// msg_set_flags - Set message flags
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = flags
// Output:
//   x0 = 0
// =============================================================================
.global msg_set_flags
.type msg_set_flags, %function
msg_set_flags:
    strh    w1, [x0, #MSG_OFF_FLAGS]
    mov     x0, #0
    ret
.size msg_set_flags, .-msg_set_flags

// =============================================================================
// msg_set_payload - Copy payload into message buffer
// =============================================================================
// Input:
//   x0 = message buffer pointer
//   x1 = payload pointer
//   x2 = payload length
// Output:
//   x0 = 0 or -EINVAL if too large
// =============================================================================
.global msg_set_payload
.type msg_set_payload, %function
msg_set_payload:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save buffer ptr

    // Check payload size
    ldr     x3, =NET_MAX_MSG_SIZE
    cmp     x2, x3
    b.hi    .Lset_payload_error

    // Store length
    str     w2, [x19, #MSG_OFF_LENGTH]

    // Copy payload
    cbz     x2, .Lset_payload_done

    add     x0, x19, #MSG_OFF_PAYLOAD   // Destination
    // x1 = source
    // x2 = length

.Lset_payload_copy:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    subs    x2, x2, #1
    b.ne    .Lset_payload_copy

.Lset_payload_done:
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lset_payload_error:
    mov     x0, #-EINVAL
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size msg_set_payload, .-msg_set_payload

// =============================================================================
// msg_finalize - Calculate and store checksum
// =============================================================================
// Input:
//   x0 = message buffer pointer
// Output:
//   x0 = 0
// =============================================================================
.global msg_finalize
.type msg_finalize, %function
msg_finalize:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                     // Save buffer ptr

    // Clear checksum field before calculation
    str     wzr, [x19, #MSG_OFF_CHECKSUM]

    // Calculate total length = header + payload
    ldr     w1, [x19, #MSG_OFF_LENGTH]
    add     x1, x1, #MSG_HDR_SIZE

    // Calculate CRC32
    mov     x0, x19
    bl      crc32_calc

    // Store checksum
    str     w0, [x19, #MSG_OFF_CHECKSUM]

    mov     x0, #0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size msg_finalize, .-msg_finalize

// =============================================================================
// msg_validate - Verify message integrity
// =============================================================================
// Input:
//   x0 = message buffer pointer
//   x1 = available buffer length
// Output:
//   x0 = 0 if valid, -EINVAL if invalid, -EMSGSIZE if incomplete
// =============================================================================
.global msg_validate
.type msg_validate, %function
msg_validate:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Buffer ptr
    mov     x20, x1                     // Available length

    // Check minimum header size
    cmp     x20, #MSG_HDR_SIZE
    b.lo    .Lvalidate_incomplete

    // Check magic number
    ldr     w2, [x19, #MSG_OFF_MAGIC]
    ldr     w3, =MSG_MAGIC
    cmp     w2, w3
    b.ne    .Lvalidate_invalid

    // Check version
    ldrb    w2, [x19, #MSG_OFF_VERSION]
    cmp     w2, #MSG_VERSION
    b.ne    .Lvalidate_invalid

    // Get payload length and check total size
    ldr     w21, [x19, #MSG_OFF_LENGTH]
    add     x22, x21, #MSG_HDR_SIZE     // Total message size

    // Check if we have complete message
    cmp     x20, x22
    b.lo    .Lvalidate_incomplete

    // Check payload size limit
    ldr     x2, =NET_MAX_MSG_SIZE
    cmp     x21, x2
    b.hi    .Lvalidate_invalid

    // Save and clear stored checksum
    ldr     w20, [x19, #MSG_OFF_CHECKSUM]
    str     wzr, [x19, #MSG_OFF_CHECKSUM]

    // Calculate checksum
    mov     x0, x19
    mov     x1, x22
    bl      crc32_calc
    mov     w21, w0

    // Restore checksum
    str     w20, [x19, #MSG_OFF_CHECKSUM]

    // Compare checksums
    cmp     w20, w21
    b.ne    .Lvalidate_invalid

    // Valid message
    mov     x0, #0
    b       .Lvalidate_ret

.Lvalidate_incomplete:
    mov     x0, #-EMSGSIZE
    b       .Lvalidate_ret

.Lvalidate_invalid:
    mov     x0, #-EINVAL

.Lvalidate_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size msg_validate, .-msg_validate

// =============================================================================
// msg_get_type - Get message type
// =============================================================================
// Input:
//   x0 = message buffer pointer
// Output:
//   x0 = message type
// =============================================================================
.global msg_get_type
.type msg_get_type, %function
msg_get_type:
    ldrb    w0, [x0, #MSG_OFF_TYPE]
    ret
.size msg_get_type, .-msg_get_type

// =============================================================================
// msg_get_flags - Get message flags
// =============================================================================
// Input:
//   x0 = message buffer pointer
// Output:
//   x0 = message flags
// =============================================================================
.global msg_get_flags
.type msg_get_flags, %function
msg_get_flags:
    ldrh    w0, [x0, #MSG_OFF_FLAGS]
    ret
.size msg_get_flags, .-msg_get_flags

// =============================================================================
// msg_get_seq - Get sequence number
// =============================================================================
// Input:
//   x0 = message buffer pointer
// Output:
//   x0 = sequence number
// =============================================================================
.global msg_get_seq
.type msg_get_seq, %function
msg_get_seq:
    ldr     w0, [x0, #MSG_OFF_SEQ]
    ret
.size msg_get_seq, .-msg_get_seq

// =============================================================================
// msg_get_length - Get payload length
// =============================================================================
// Input:
//   x0 = message buffer pointer
// Output:
//   x0 = payload length
// =============================================================================
.global msg_get_length
.type msg_get_length, %function
msg_get_length:
    ldr     w0, [x0, #MSG_OFF_LENGTH]
    ret
.size msg_get_length, .-msg_get_length

// =============================================================================
// msg_get_src_node - Get source node ID
// =============================================================================
// Input:
//   x0 = message buffer pointer
// Output:
//   x0 = source node ID
// =============================================================================
.global msg_get_src_node
.type msg_get_src_node, %function
msg_get_src_node:
    ldr     x0, [x0, #MSG_OFF_SRC_NODE]
    ret
.size msg_get_src_node, .-msg_get_src_node

// =============================================================================
// msg_get_dst_node - Get destination node ID
// =============================================================================
// Input:
//   x0 = message buffer pointer
// Output:
//   x0 = destination node ID
// =============================================================================
.global msg_get_dst_node
.type msg_get_dst_node, %function
msg_get_dst_node:
    ldr     x0, [x0, #MSG_OFF_DST_NODE]
    ret
.size msg_get_dst_node, .-msg_get_dst_node

// =============================================================================
// msg_get_payload - Get pointer to payload
// =============================================================================
// Input:
//   x0 = message buffer pointer
// Output:
//   x0 = payload pointer
// =============================================================================
.global msg_get_payload
.type msg_get_payload, %function
msg_get_payload:
    add     x0, x0, #MSG_OFF_PAYLOAD
    ret
.size msg_get_payload, .-msg_get_payload

// =============================================================================
// msg_get_total_size - Get total message size (header + payload)
// =============================================================================
// Input:
//   x0 = message buffer pointer
// Output:
//   x0 = total size
// =============================================================================
.global msg_get_total_size
.type msg_get_total_size, %function
msg_get_total_size:
    ldr     w0, [x0, #MSG_OFF_LENGTH]
    add     x0, x0, #MSG_HDR_SIZE
    ret
.size msg_get_total_size, .-msg_get_total_size

// =============================================================================
// msg_build - Build complete message with payload
// =============================================================================
// Input:
//   x0 = buffer pointer
//   x1 = message type
//   x2 = source node ID
//   x3 = destination node ID
//   x4 = payload pointer (or NULL)
//   x5 = payload length
// Output:
//   x0 = total message size or -errno
// =============================================================================
.global msg_build
.type msg_build, %function
msg_build:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // Buffer
    mov     x20, x1                     // Type
    mov     x21, x2                     // Src node
    mov     x22, x3                     // Dst node
    mov     x23, x4                     // Payload
    mov     x24, x5                     // Payload length

    // Initialize header
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x22
    bl      msg_init

    // Set payload if provided
    cbz     x23, .Lbuild_finalize
    cbz     x24, .Lbuild_finalize

    mov     x0, x19
    mov     x1, x23
    mov     x2, x24
    bl      msg_set_payload
    cmp     x0, #0
    b.lt    .Lbuild_ret

.Lbuild_finalize:
    // Finalize (calculate checksum)
    mov     x0, x19
    bl      msg_finalize

    // Return total size
    ldr     w0, [x19, #MSG_OFF_LENGTH]
    add     x0, x0, #MSG_HDR_SIZE

.Lbuild_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size msg_build, .-msg_build
