// Unit Tests for Config Parser/Writer
// test/unit/test_config.s

.include "include/syscall_nums.inc"
.include "include/setup.inc"

.global _start

// ============================================================================
// Test Data
// ============================================================================

.section .rodata

msg_test_start:     .asciz "=== Config Parser Tests ===\n"
msg_test_init:      .asciz "Test 1: config_init... "
msg_test_set:       .asciz "Test 2: config_set... "
msg_test_get:       .asciz "Test 3: config_get... "
msg_test_get_int:   .asciz "Test 4: config_get_int... "
msg_test_get_bool:  .asciz "Test 5: config_get_bool... "
msg_test_save:      .asciz "Test 6: config_save... "
msg_test_load:      .asciz "Test 7: config_load... "
msg_test_parse:     .asciz "Test 8: parse edge cases... "
msg_pass:           .asciz "PASS\n"
msg_fail:           .asciz "FAIL\n"
msg_all_pass:       .asciz "\nAll tests passed!\n"
msg_some_fail:      .asciz "\nSome tests failed!\n"

// Test keys and values
test_key1:          .asciz "transport"
test_val1:          .asciz "tcp"
test_key2:          .asciz "bind_port"
test_val2:          .asciz "8080"
test_key3:          .asciz "http_enabled"
test_val3:          .asciz "true"
test_key4:          .asciz "wal_enabled"
test_val4:          .asciz "false"
test_key5:          .asciz "debug_mode"
test_val5:          .asciz "yes"
test_key6:          .asciz "verbose"
test_val6:          .asciz "1"
test_key7:          .asciz "quiet"
test_val7:          .asciz "no"

// Test file path
test_config_path:   .asciz "/tmp/test_omesh_config"

// ============================================================================
// BSS
// ============================================================================

.section .bss

.align 3
test_count:         .skip 8
pass_count:         .skip 8

// ============================================================================
// Text Section
// ============================================================================

.section .text

_start:
    // Initialize counters
    adrp    x0, test_count
    add     x0, x0, :lo12:test_count
    str     xzr, [x0]
    adrp    x0, pass_count
    add     x0, x0, :lo12:pass_count
    str     xzr, [x0]

    // Print header
    adrp    x1, msg_test_start
    add     x1, x1, :lo12:msg_test_start
    bl      print_str

    // Run tests
    bl      test_init
    bl      test_set
    bl      test_get
    bl      test_get_int
    bl      test_get_bool
    bl      test_save
    bl      test_load
    bl      test_parse_edge_cases

    // Print summary
    adrp    x0, test_count
    add     x0, x0, :lo12:test_count
    ldr     x1, [x0]
    adrp    x0, pass_count
    add     x0, x0, :lo12:pass_count
    ldr     x2, [x0]

    cmp     x1, x2
    b.ne    .Lsome_fail

    adrp    x1, msg_all_pass
    add     x1, x1, :lo12:msg_all_pass
    bl      print_str
    mov     x0, #0
    b       .Lexit

.Lsome_fail:
    adrp    x1, msg_some_fail
    add     x1, x1, :lo12:msg_some_fail
    bl      print_str
    mov     x0, #1

.Lexit:
    mov     x8, #SYS_exit
    svc     #0

// ----------------------------------------------------------------------------
// Test 1: config_init
// ----------------------------------------------------------------------------
test_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, msg_test_init
    add     x1, x1, :lo12:msg_test_init
    bl      print_str

    bl      config_init

    cmp     x0, #0
    b.ne    .Linit_fail

    bl      print_pass
    b       .Linit_done

.Linit_fail:
    bl      print_fail

.Linit_done:
    ldp     x29, x30, [sp], #16
    ret

// ----------------------------------------------------------------------------
// Test 2: config_set
// ----------------------------------------------------------------------------
test_set:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, msg_test_set
    add     x1, x1, :lo12:msg_test_set
    bl      print_str

    // Set several values
    adrp    x0, test_key1
    add     x0, x0, :lo12:test_key1
    adrp    x1, test_val1
    add     x1, x1, :lo12:test_val1
    bl      config_set
    cbnz    x0, .Lset_fail

    adrp    x0, test_key2
    add     x0, x0, :lo12:test_key2
    adrp    x1, test_val2
    add     x1, x1, :lo12:test_val2
    bl      config_set
    cbnz    x0, .Lset_fail

    adrp    x0, test_key3
    add     x0, x0, :lo12:test_key3
    adrp    x1, test_val3
    add     x1, x1, :lo12:test_val3
    bl      config_set
    cbnz    x0, .Lset_fail

    adrp    x0, test_key4
    add     x0, x0, :lo12:test_key4
    adrp    x1, test_val4
    add     x1, x1, :lo12:test_val4
    bl      config_set
    cbnz    x0, .Lset_fail

    adrp    x0, test_key5
    add     x0, x0, :lo12:test_key5
    adrp    x1, test_val5
    add     x1, x1, :lo12:test_val5
    bl      config_set
    cbnz    x0, .Lset_fail

    adrp    x0, test_key6
    add     x0, x0, :lo12:test_key6
    adrp    x1, test_val6
    add     x1, x1, :lo12:test_val6
    bl      config_set
    cbnz    x0, .Lset_fail

    adrp    x0, test_key7
    add     x0, x0, :lo12:test_key7
    adrp    x1, test_val7
    add     x1, x1, :lo12:test_val7
    bl      config_set
    cbnz    x0, .Lset_fail

    bl      print_pass
    b       .Lset_done

.Lset_fail:
    bl      print_fail

.Lset_done:
    ldp     x29, x30, [sp], #16
    ret

// ----------------------------------------------------------------------------
// Test 3: config_get
// ----------------------------------------------------------------------------
test_get:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    adrp    x1, msg_test_get
    add     x1, x1, :lo12:msg_test_get
    bl      print_str

    // Get transport value
    adrp    x0, test_key1
    add     x0, x0, :lo12:test_key1
    bl      config_get
    cbz     x0, .Lget_fail

    // Verify value is "tcp"
    mov     x19, x0
    ldrb    w1, [x19]
    cmp     w1, #'t'
    b.ne    .Lget_fail
    ldrb    w1, [x19, #1]
    cmp     w1, #'c'
    b.ne    .Lget_fail
    ldrb    w1, [x19, #2]
    cmp     w1, #'p'
    b.ne    .Lget_fail
    ldrb    w1, [x19, #3]
    cbnz    w1, .Lget_fail

    // Get non-existent key
    adrp    x0, nonexistent_key
    add     x0, x0, :lo12:nonexistent_key
    bl      config_get
    cbnz    x0, .Lget_fail              // Should return NULL

    bl      print_pass
    b       .Lget_done

.Lget_fail:
    bl      print_fail

.Lget_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.section .rodata
nonexistent_key:    .asciz "nonexistent_key_xyz"
.section .text

// ----------------------------------------------------------------------------
// Test 4: config_get_int
// ----------------------------------------------------------------------------
test_get_int:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, msg_test_get_int
    add     x1, x1, :lo12:msg_test_get_int
    bl      print_str

    // Get bind_port (should be 8080)
    adrp    x0, test_key2
    add     x0, x0, :lo12:test_key2
    mov     x1, #0                      // default
    bl      config_get_int

    // Verify value is 8080
    mov     x1, #8080
    cmp     x0, x1
    b.ne    .Lget_int_fail

    // Get non-existent (should return default)
    adrp    x0, nonexistent_key
    add     x0, x0, :lo12:nonexistent_key
    mov     x1, #9999                   // default
    bl      config_get_int
    mov     x1, #9999
    cmp     x0, x1
    b.ne    .Lget_int_fail

    bl      print_pass
    b       .Lget_int_done

.Lget_int_fail:
    bl      print_fail

.Lget_int_done:
    ldp     x29, x30, [sp], #16
    ret

// ----------------------------------------------------------------------------
// Test 5: config_get_bool
// ----------------------------------------------------------------------------
test_get_bool:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, msg_test_get_bool
    add     x1, x1, :lo12:msg_test_get_bool
    bl      print_str

    // Get http_enabled (should be true/1)
    adrp    x0, test_key3
    add     x0, x0, :lo12:test_key3
    mov     x1, #0                      // default
    bl      config_get_bool
    cmp     x0, #1
    b.ne    .Lget_bool_fail

    // Get wal_enabled (should be false/0)
    adrp    x0, test_key4
    add     x0, x0, :lo12:test_key4
    mov     x1, #1                      // default
    bl      config_get_bool
    cmp     x0, #0
    b.ne    .Lget_bool_fail

    // Get debug_mode ("yes" = true)
    adrp    x0, test_key5
    add     x0, x0, :lo12:test_key5
    mov     x1, #0
    bl      config_get_bool
    cmp     x0, #1
    b.ne    .Lget_bool_fail

    // Get verbose ("1" = true)
    adrp    x0, test_key6
    add     x0, x0, :lo12:test_key6
    mov     x1, #0
    bl      config_get_bool
    cmp     x0, #1
    b.ne    .Lget_bool_fail

    // Get quiet ("no" = false)
    adrp    x0, test_key7
    add     x0, x0, :lo12:test_key7
    mov     x1, #1
    bl      config_get_bool
    cmp     x0, #0
    b.ne    .Lget_bool_fail

    bl      print_pass
    b       .Lget_bool_done

.Lget_bool_fail:
    bl      print_fail

.Lget_bool_done:
    ldp     x29, x30, [sp], #16
    ret

// ----------------------------------------------------------------------------
// Test 6: config_save
// ----------------------------------------------------------------------------
test_save:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, msg_test_save
    add     x1, x1, :lo12:msg_test_save
    bl      print_str

    // Save to test file
    adrp    x0, test_config_path
    add     x0, x0, :lo12:test_config_path
    bl      config_save

    cmp     x0, #0
    b.ne    .Lsave_fail

    bl      print_pass
    b       .Lsave_done

.Lsave_fail:
    bl      print_fail

.Lsave_done:
    ldp     x29, x30, [sp], #16
    ret

// ----------------------------------------------------------------------------
// Test 7: config_load
// ----------------------------------------------------------------------------
test_load:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, msg_test_load
    add     x1, x1, :lo12:msg_test_load
    bl      print_str

    // Re-initialize (clears state)
    bl      config_init

    // Load from test file
    adrp    x0, test_config_path
    add     x0, x0, :lo12:test_config_path
    bl      config_load

    cmp     x0, #0
    b.ne    .Lload_fail

    // Verify value was loaded
    adrp    x0, test_key1
    add     x0, x0, :lo12:test_key1
    bl      config_get
    cbz     x0, .Lload_fail

    // Check value is still "tcp"
    ldrb    w1, [x0]
    cmp     w1, #'t'
    b.ne    .Lload_fail

    bl      print_pass
    b       .Lload_done

.Lload_fail:
    bl      print_fail

.Lload_done:
    ldp     x29, x30, [sp], #16
    ret

// ----------------------------------------------------------------------------
// Test 8: Parse edge cases
// ----------------------------------------------------------------------------
test_parse_edge_cases:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, msg_test_parse
    add     x1, x1, :lo12:msg_test_parse
    bl      print_str

    // Re-initialize
    bl      config_init

    // Test with spaces around '='
    adrp    x0, edge_key1
    add     x0, x0, :lo12:edge_key1
    adrp    x1, edge_val1
    add     x1, x1, :lo12:edge_val1
    bl      config_set
    cbnz    x0, .Ledge_fail

    // Test empty value
    adrp    x0, edge_key2
    add     x0, x0, :lo12:edge_key2
    adrp    x1, edge_val2
    add     x1, x1, :lo12:edge_val2
    bl      config_set
    cbnz    x0, .Ledge_fail

    // Verify retrieval
    adrp    x0, edge_key1
    add     x0, x0, :lo12:edge_key1
    bl      config_get
    cbz     x0, .Ledge_fail

    adrp    x0, edge_key2
    add     x0, x0, :lo12:edge_key2
    bl      config_get
    cbz     x0, .Ledge_fail

    bl      print_pass
    b       .Ledge_done

.Ledge_fail:
    bl      print_fail

.Ledge_done:
    ldp     x29, x30, [sp], #16
    ret

.section .rodata
edge_key1:      .asciz "spaced_key"
edge_val1:      .asciz "value with spaces"
edge_key2:      .asciz "empty_key"
edge_val2:      .asciz ""
.section .text

// ----------------------------------------------------------------------------
// Helper Functions
// ----------------------------------------------------------------------------

// print_str - Print null-terminated string
// Input: x1 = string pointer
print_str:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x1

    // Get string length
    mov     x0, #0
.Lps_len:
    ldrb    w2, [x19, x0]
    cbz     w2, .Lps_write
    add     x0, x0, #1
    b       .Lps_len

.Lps_write:
    mov     x2, x0                      // length
    mov     x0, #1                      // stdout
    mov     x1, x19                     // buffer
    mov     x8, #SYS_write
    svc     #0

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// print_pass - Print PASS and increment counters
print_pass:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    bl      print_str

    // Increment test count
    adrp    x0, test_count
    add     x0, x0, :lo12:test_count
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    // Increment pass count
    adrp    x0, pass_count
    add     x0, x0, :lo12:pass_count
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    ldp     x29, x30, [sp], #16
    ret

// print_fail - Print FAIL and increment test count
print_fail:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, msg_fail
    add     x1, x1, :lo12:msg_fail
    bl      print_str

    // Increment test count only
    adrp    x0, test_count
    add     x0, x0, :lo12:test_count
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    ldp     x29, x30, [sp], #16
    ret
