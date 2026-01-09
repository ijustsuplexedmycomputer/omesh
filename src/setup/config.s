// Configuration File Parser/Writer
// src/setup/config.s
//
// Handles reading and writing omesh config files in key=value format.
// Config file location: ~/.omesh/config
//
// Format:
//   # Comment line
//   key=value
//   key = value with spaces
//
// Functions:
//   config_init     - Initialize config state
//   config_load     - Load config from file
//   config_save     - Save config to file
//   config_get      - Get string value by key
//   config_set      - Set string value by key
//   config_get_int  - Get integer value by key
//   config_get_bool - Get boolean value by key

.include "include/syscall_nums.inc"
.include "include/setup.inc"

.global config_init
.global config_load
.global config_save
.global config_get
.global config_set
.global config_get_int
.global config_get_bool
.global config_get_list
.global config_has_value

// ============================================================================
// Data Section
// ============================================================================

.section .data

// Default config directory and file
config_dir_suffix:      .asciz "/.omesh"
config_file_name:       .asciz "/config"

// Boolean true values
bool_true_1:            .asciz "true"
bool_true_2:            .asciz "yes"
bool_true_3:            .asciz "1"
bool_true_4:            .asciz "on"

// ============================================================================
// BSS Section
// ============================================================================

.section .bss

// Global config state
.align 8
config_state:
    .skip CONFIG_STATE_SIZE

// Temporary buffers
.align 8
config_path_buf:
    .skip CONFIG_PATH_MAX

config_line_buf:
    .skip CONFIG_LINE_MAX

// ============================================================================
// Text Section
// ============================================================================

.section .text

// ----------------------------------------------------------------------------
// config_init - Initialize configuration state
// ----------------------------------------------------------------------------
// Inputs:
//   none
// Outputs:
//   x0 = 0 on success, negative on error
// Clobbers: x0-x3
// ----------------------------------------------------------------------------
config_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Clear config state
    adrp    x0, config_state
    add     x0, x0, :lo12:config_state
    mov     x1, #0
    mov     x2, #CONFIG_STATE_SIZE

.Lclear_loop:
    cbz     x2, .Lclear_done
    strb    w1, [x0], #1
    sub     x2, x2, #1
    b       .Lclear_loop

.Lclear_done:
    // Build default config path: $HOME/.omesh/config
    // First, get HOME environment variable
    adrp    x0, env_home
    add     x0, x0, :lo12:env_home
    bl      getenv_simple

    cbz     x0, .Linit_no_home

    // Copy HOME to path buffer
    adrp    x1, config_path_buf
    add     x1, x1, :lo12:config_path_buf
    mov     x2, x1                      // Save dest start

.Lcopy_home:
    ldrb    w3, [x0], #1
    strb    w3, [x1], #1
    cbnz    w3, .Lcopy_home
    sub     x1, x1, #1                  // Back up over null

    // Append /.omesh
    adrp    x0, config_dir_suffix
    add     x0, x0, :lo12:config_dir_suffix

.Lcopy_dir:
    ldrb    w3, [x0], #1
    strb    w3, [x1], #1
    cbnz    w3, .Lcopy_dir
    sub     x1, x1, #1                  // Back up over null

    // Append /config
    adrp    x0, config_file_name
    add     x0, x0, :lo12:config_file_name

.Lcopy_file:
    ldrb    w3, [x0], #1
    strb    w3, [x1], #1
    cbnz    w3, .Lcopy_file

    // Copy path to config state
    adrp    x0, config_state
    add     x0, x0, :lo12:config_state
    add     x0, x0, #CONFIG_STATE_FILEPATH
    adrp    x1, config_path_buf
    add     x1, x1, :lo12:config_path_buf

.Lcopy_to_state:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    cbnz    w3, .Lcopy_to_state

    mov     x0, #CONFIG_SUCCESS
    b       .Linit_done

.Linit_no_home:
    // No HOME set, use default /tmp/.omesh/config
    adrp    x0, config_state
    add     x0, x0, :lo12:config_state
    add     x0, x0, #CONFIG_STATE_FILEPATH
    adrp    x1, default_config_path
    add     x1, x1, :lo12:default_config_path

.Lcopy_default:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    cbnz    w3, .Lcopy_default

    mov     x0, #CONFIG_SUCCESS

.Linit_done:
    ldp     x29, x30, [sp], #16
    ret

// Helper strings
.section .rodata
env_home:               .asciz "HOME"
default_config_path:    .asciz "/tmp/.omesh/config"

.section .text

// ----------------------------------------------------------------------------
// getenv_simple - Simple getenv implementation
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = pointer to variable name
// Outputs:
//   x0 = pointer to value or NULL
// ----------------------------------------------------------------------------
getenv_simple:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]

    mov     x19, x0                     // Save var name

    // Get environ pointer
    adrp    x20, environ
    add     x20, x20, :lo12:environ
    ldr     x20, [x20]                  // x20 = environ

    cbz     x20, .Lgetenv_not_found

.Lgetenv_loop:
    ldr     x21, [x20], #8              // Get next envp entry
    cbz     x21, .Lgetenv_not_found

    // Compare var name with entry prefix
    mov     x0, x19                     // var name
    mov     x1, x21                     // env entry

.Lgetenv_cmp:
    ldrb    w2, [x0], #1                // char from var name
    ldrb    w3, [x1], #1                // char from env entry

    cbz     w2, .Lgetenv_check_eq       // End of var name
    cmp     w2, w3
    b.ne    .Lgetenv_loop               // Mismatch, try next

    b       .Lgetenv_cmp

.Lgetenv_check_eq:
    // Var name ended, check if env entry has '='
    cmp     w3, #'='
    b.ne    .Lgetenv_loop               // No '=', try next

    // Found it! x1 points to value
    mov     x0, x1
    b       .Lgetenv_done

.Lgetenv_not_found:
    mov     x0, #0

.Lgetenv_done:
    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldr     x21, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

// External reference
.section .data
.global environ
.weak environ
environ: .quad 0

.section .text

// ----------------------------------------------------------------------------
// config_load - Load configuration from file
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = path (or NULL to use default)
// Outputs:
//   x0 = 0 on success, negative on error
// ----------------------------------------------------------------------------
config_load:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    str     x22, [sp, #40]
    str     x23, [sp, #48]

    // Use provided path or default
    cbnz    x0, .Lload_use_path
    adrp    x0, config_state
    add     x0, x0, :lo12:config_state
    add     x0, x0, #CONFIG_STATE_FILEPATH

.Lload_use_path:
    mov     x19, x0                     // x19 = path

    // Open file for reading
    mov     x0, x19
    mov     x1, #0                      // O_RDONLY
    mov     x8, #SYS_openat
    mov     x0, #-100                   // AT_FDCWD
    mov     x1, x19
    mov     x2, #0                      // O_RDONLY
    svc     #0

    cmp     x0, #0
    b.lt    .Lload_no_file              // File doesn't exist is OK

    mov     x20, x0                     // x20 = fd

    // Read file contents line by line
    adrp    x21, config_line_buf
    add     x21, x21, :lo12:config_line_buf
    mov     x22, #0                     // Line position

.Lload_read_loop:
    // Read one byte
    mov     x0, x20                     // fd
    add     x1, x21, x22                // buffer + pos
    mov     x2, #1                      // count
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #0
    b.le    .Lload_eof                  // EOF or error

    // Check for newline
    ldrb    w0, [x21, x22]
    cmp     w0, #'\n'
    b.eq    .Lload_process_line

    // Check for buffer overflow
    add     x22, x22, #1
    cmp     x22, #CONFIG_LINE_MAX
    b.lt    .Lload_read_loop

    // Line too long, skip rest
.Lload_skip_line:
    mov     x0, x20
    add     x1, x21, x22
    mov     x2, #1
    mov     x8, #SYS_read
    svc     #0
    cmp     x0, #0
    b.le    .Lload_eof
    ldrb    w0, [x21, x22]
    cmp     w0, #'\n'
    b.ne    .Lload_skip_line
    mov     x22, #0
    b       .Lload_read_loop

.Lload_process_line:
    // Null terminate line
    mov     w0, #0
    strb    w0, [x21, x22]

    // Parse the line
    mov     x0, x21
    bl      config_parse_line

    // Reset for next line
    mov     x22, #0
    b       .Lload_read_loop

.Lload_eof:
    // Process any remaining content
    cbz     x22, .Lload_close
    mov     w0, #0
    strb    w0, [x21, x22]
    mov     x0, x21
    bl      config_parse_line

.Lload_close:
    // Close file
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0

    // Mark as loaded
    adrp    x0, config_state
    add     x0, x0, :lo12:config_state
    ldr     w1, [x0, #CONFIG_STATE_FLAGS]
    orr     w1, w1, #CONFIG_STATE_LOADED
    str     w1, [x0, #CONFIG_STATE_FLAGS]

    mov     x0, #CONFIG_SUCCESS
    b       .Lload_done

.Lload_no_file:
    // File doesn't exist - not an error, just empty config
    mov     x0, #CONFIG_SUCCESS

.Lload_done:
    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldr     x21, [sp, #32]
    ldr     x22, [sp, #40]
    ldr     x23, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

// ----------------------------------------------------------------------------
// config_parse_line - Parse a single config line
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = pointer to line (null-terminated)
// Outputs:
//   x0 = 0 on success
// Internal function
// ----------------------------------------------------------------------------
config_parse_line:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]

    mov     x19, x0                     // x19 = line start

    // Skip leading whitespace
.Lparse_skip_ws:
    ldrb    w0, [x19]
    cmp     w0, #' '
    b.eq    .Lparse_next_ws
    cmp     w0, #'\t'
    b.eq    .Lparse_next_ws
    b       .Lparse_check_empty

.Lparse_next_ws:
    add     x19, x19, #1
    b       .Lparse_skip_ws

.Lparse_check_empty:
    // Check for empty line or comment
    ldrb    w0, [x19]
    cbz     w0, .Lparse_done            // Empty line
    cmp     w0, #'#'
    b.eq    .Lparse_done                // Comment

    // Find '=' separator
    mov     x20, x19                    // x20 = key start

.Lparse_find_eq:
    ldrb    w0, [x19]
    cbz     w0, .Lparse_done            // No '=' found
    cmp     w0, #'='
    b.eq    .Lparse_found_eq
    add     x19, x19, #1
    b       .Lparse_find_eq

.Lparse_found_eq:
    // x19 points to '=', x20 is key start
    mov     x21, x19                    // x21 = position of '='

    // Trim trailing whitespace from key
    sub     x19, x19, #1
.Lparse_trim_key:
    cmp     x19, x20
    b.lt    .Lparse_done                // Empty key
    ldrb    w0, [x19]
    cmp     w0, #' '
    b.eq    .Lparse_trim_key_next
    cmp     w0, #'\t'
    b.eq    .Lparse_trim_key_next
    b       .Lparse_key_done

.Lparse_trim_key_next:
    sub     x19, x19, #1
    b       .Lparse_trim_key

.Lparse_key_done:
    // Null terminate key
    add     x19, x19, #1
    mov     w0, #0
    strb    w0, [x19]

    // Move past '=' and skip whitespace for value
    add     x19, x21, #1
.Lparse_skip_val_ws:
    ldrb    w0, [x19]
    cmp     w0, #' '
    b.eq    .Lparse_next_val_ws
    cmp     w0, #'\t'
    b.eq    .Lparse_next_val_ws
    b       .Lparse_got_value

.Lparse_next_val_ws:
    add     x19, x19, #1
    b       .Lparse_skip_val_ws

.Lparse_got_value:
    // x20 = key, x19 = value
    // Trim trailing whitespace from value
    mov     x21, x19
.Lparse_find_val_end:
    ldrb    w0, [x21]
    cbz     w0, .Lparse_trim_val
    add     x21, x21, #1
    b       .Lparse_find_val_end

.Lparse_trim_val:
    sub     x21, x21, #1
.Lparse_trim_val_loop:
    cmp     x21, x19
    b.lt    .Lparse_set_value
    ldrb    w0, [x21]
    cmp     w0, #' '
    b.eq    .Lparse_trim_val_next
    cmp     w0, #'\t'
    b.eq    .Lparse_trim_val_next
    cmp     w0, #'\r'
    b.eq    .Lparse_trim_val_next
    b       .Lparse_set_value

.Lparse_trim_val_next:
    mov     w0, #0
    strb    w0, [x21]
    sub     x21, x21, #1
    b       .Lparse_trim_val_loop

.Lparse_set_value:
    // Set the config value
    mov     x0, x20                     // key
    mov     x1, x19                     // value
    bl      config_set

.Lparse_done:
    mov     x0, #CONFIG_SUCCESS
    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldr     x21, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

// ----------------------------------------------------------------------------
// config_save - Save configuration to file
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = path (or NULL to use default)
// Outputs:
//   x0 = 0 on success, negative on error
// ----------------------------------------------------------------------------
config_save:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    str     x22, [sp, #40]
    str     x23, [sp, #48]

    // Use provided path or default
    cbnz    x0, .Lsave_use_path
    adrp    x0, config_state
    add     x0, x0, :lo12:config_state
    add     x0, x0, #CONFIG_STATE_FILEPATH

.Lsave_use_path:
    mov     x19, x0                     // x19 = path

    // Create parent directory
    mov     x0, x19
    bl      config_ensure_dir

    // Open file for writing (create/truncate)
    mov     x0, #-100                   // AT_FDCWD
    mov     x1, x19                     // path
    mov     x2, #0x241                  // O_WRONLY | O_CREAT | O_TRUNC
    mov     x3, #CONFIG_FILE_MODE
    mov     x8, #SYS_openat
    svc     #0

    cmp     x0, #0
    b.lt    .Lsave_error
    mov     x20, x0                     // x20 = fd

    // Write header comment
    mov     x0, x20
    adrp    x1, config_header
    add     x1, x1, :lo12:config_header
    mov     x2, #config_header_len
    mov     x8, #SYS_write
    svc     #0

    // Write each entry
    adrp    x21, config_state
    add     x21, x21, :lo12:config_state
    ldr     w22, [x21, #CONFIG_STATE_COUNT]
    add     x21, x21, #CONFIG_STATE_ENTRIES
    mov     x23, #0                     // entry index

.Lsave_loop:
    cmp     x23, x22
    b.ge    .Lsave_close

    // Calculate entry pointer
    mov     x0, #CONFIG_ENTRY_SIZE
    mul     x0, x23, x0
    add     x0, x21, x0                 // x0 = entry ptr

    // Check if key is non-empty
    ldrb    w1, [x0, #CONFIG_ENTRY_KEY]
    cbz     w1, .Lsave_next

    // Write key
    mov     x1, x0                      // Save entry ptr
    add     x0, x1, #CONFIG_ENTRY_KEY
    bl      strlen
    mov     x2, x0                      // len
    mov     x0, x20                     // fd
    add     x1, x1, #CONFIG_ENTRY_KEY   // Recalculate - x1 was clobbered

    // Recalculate entry pointer
    mov     x0, #CONFIG_ENTRY_SIZE
    mul     x0, x23, x0
    add     x1, x21, x0
    add     x1, x1, #CONFIG_ENTRY_KEY

    // Get key length
    mov     x0, x1
    bl      strlen
    mov     x2, x0

    // Write key
    mov     x0, x20
    mov     x0, #CONFIG_ENTRY_SIZE
    mul     x0, x23, x0
    add     x1, x21, x0
    add     x1, x1, #CONFIG_ENTRY_KEY
    mov     x0, x20
    mov     x8, #SYS_write
    svc     #0

    // Write '='
    mov     x0, x20
    adrp    x1, char_equals
    add     x1, x1, :lo12:char_equals
    mov     x2, #1
    mov     x8, #SYS_write
    svc     #0

    // Write value
    mov     x0, #CONFIG_ENTRY_SIZE
    mul     x0, x23, x0
    add     x1, x21, x0
    add     x1, x1, #CONFIG_ENTRY_VALUE
    mov     x0, x1
    bl      strlen
    mov     x2, x0

    mov     x0, #CONFIG_ENTRY_SIZE
    mul     x0, x23, x0
    add     x1, x21, x0
    add     x1, x1, #CONFIG_ENTRY_VALUE
    mov     x0, x20
    mov     x8, #SYS_write
    svc     #0

    // Write newline
    mov     x0, x20
    adrp    x1, char_newline
    add     x1, x1, :lo12:char_newline
    mov     x2, #1
    mov     x8, #SYS_write
    svc     #0

.Lsave_next:
    add     x23, x23, #1
    b       .Lsave_loop

.Lsave_close:
    // Close file
    mov     x0, x20
    mov     x8, #SYS_close
    svc     #0

    // Clear dirty flag
    adrp    x0, config_state
    add     x0, x0, :lo12:config_state
    ldr     w1, [x0, #CONFIG_STATE_FLAGS]
    and     w1, w1, #~CONFIG_STATE_DIRTY
    str     w1, [x0, #CONFIG_STATE_FLAGS]

    mov     x0, #CONFIG_SUCCESS
    b       .Lsave_done

.Lsave_error:
    mov     x0, #CONFIG_ERR_IO

.Lsave_done:
    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldr     x21, [sp, #32]
    ldr     x22, [sp, #40]
    ldr     x23, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

// Helper data
.section .rodata
config_header:
    .ascii "# Omesh Configuration\n"
    .ascii "# Generated by omesh setup wizard\n"
    .ascii "\n"
.equ config_header_len, . - config_header

char_equals:    .ascii "="
char_newline:   .ascii "\n"

.section .text

// ----------------------------------------------------------------------------
// config_ensure_dir - Ensure config directory exists
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = full file path
// Outputs:
//   x0 = 0 on success
// ----------------------------------------------------------------------------
config_ensure_dir:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    // Copy path to buffer and find last '/'
    adrp    x0, config_path_buf
    add     x0, x0, :lo12:config_path_buf
    mov     x1, x19
    mov     x2, #0                      // Last '/' position

.Lensure_copy:
    ldrb    w3, [x1]
    strb    w3, [x0]
    cbz     w3, .Lensure_mkdir
    cmp     w3, #'/'
    b.ne    .Lensure_copy_next

    // Record '/' position
    adrp    x2, config_path_buf
    add     x2, x2, :lo12:config_path_buf
    sub     x2, x0, x2

.Lensure_copy_next:
    add     x0, x0, #1
    add     x1, x1, #1
    b       .Lensure_copy

.Lensure_mkdir:
    // Null terminate at last '/'
    cbz     x2, .Lensure_done
    adrp    x0, config_path_buf
    add     x0, x0, :lo12:config_path_buf
    add     x0, x0, x2
    mov     w1, #0
    strb    w1, [x0]

    // Create directory (ignore errors - may exist)
    mov     x0, #-100                   // AT_FDCWD
    adrp    x1, config_path_buf
    add     x1, x1, :lo12:config_path_buf
    mov     x2, #CONFIG_DIR_MODE
    mov     x8, #SYS_mkdirat
    svc     #0

.Lensure_done:
    mov     x0, #0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ----------------------------------------------------------------------------
// config_get - Get string value by key
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = key (null-terminated string)
// Outputs:
//   x0 = pointer to value or NULL if not found
// ----------------------------------------------------------------------------
config_get:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]

    mov     x19, x0                     // x19 = key

    // Get config state
    adrp    x20, config_state
    add     x20, x20, :lo12:config_state
    ldr     w21, [x20, #CONFIG_STATE_COUNT]
    add     x20, x20, #CONFIG_STATE_ENTRIES

    mov     x0, #0                      // entry index

.Lget_loop:
    cmp     x0, x21
    b.ge    .Lget_not_found

    // Calculate entry pointer
    mov     x1, #CONFIG_ENTRY_SIZE
    mul     x1, x0, x1
    add     x1, x20, x1                 // x1 = entry ptr

    // Compare key
    str     x0, [sp, #40]               // Save index
    add     x0, x1, #CONFIG_ENTRY_KEY
    mov     x1, x19
    bl      strcmp
    mov     x1, x0                      // Save strcmp result
    ldr     x0, [sp, #40]               // Restore index

    cbnz    x1, .Lget_next

    // Found - return value pointer
    mov     x1, #CONFIG_ENTRY_SIZE
    mul     x1, x0, x1
    add     x0, x20, x1
    add     x0, x0, #CONFIG_ENTRY_VALUE
    b       .Lget_done

.Lget_next:
    ldr     x0, [sp, #40]
    add     x0, x0, #1
    b       .Lget_loop

.Lget_not_found:
    mov     x0, #0

.Lget_done:
    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldr     x21, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

// ----------------------------------------------------------------------------
// config_set - Set string value by key
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = key (null-terminated string)
//   x1 = value (null-terminated string)
// Outputs:
//   x0 = 0 on success, negative on error
// ----------------------------------------------------------------------------
config_set:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    str     x22, [sp, #40]
    str     x23, [sp, #48]

    mov     x19, x0                     // x19 = key
    mov     x22, x1                     // x22 = value

    // Check key length
    mov     x0, x19
    bl      strlen
    cmp     x0, #CONFIG_KEY_MAX
    b.ge    .Lset_too_long

    // Check value length
    mov     x0, x22
    bl      strlen
    cmp     x0, #CONFIG_VALUE_MAX
    b.ge    .Lset_too_long

    // Get config state
    adrp    x20, config_state
    add     x20, x20, :lo12:config_state
    ldr     w21, [x20, #CONFIG_STATE_COUNT]
    add     x23, x20, #CONFIG_STATE_ENTRIES

    mov     x0, #0                      // entry index

.Lset_find_loop:
    cmp     x0, x21
    b.ge    .Lset_add_new

    // Calculate entry pointer
    mov     x1, #CONFIG_ENTRY_SIZE
    mul     x1, x0, x1
    add     x1, x23, x1                 // x1 = entry ptr

    // Compare key
    str     x0, [sp, #56]               // Save index
    add     x0, x1, #CONFIG_ENTRY_KEY
    mov     x1, x19
    bl      strcmp
    mov     x1, x0                      // Save strcmp result
    ldr     x0, [sp, #56]               // Restore index

    cbnz    x1, .Lset_find_next

    // Found existing entry - update value
    mov     x1, #CONFIG_ENTRY_SIZE
    mul     x1, x0, x1
    add     x0, x23, x1
    add     x0, x0, #CONFIG_ENTRY_VALUE
    mov     x1, x22
    bl      strcpy

    // Mark as modified
    mov     x1, #CONFIG_ENTRY_SIZE
    ldr     x0, [sp, #56]
    mul     x1, x0, x1
    add     x0, x23, x1
    ldr     w1, [x0, #CONFIG_ENTRY_FLAGS]
    orr     w1, w1, #CONFIG_FLAG_MODIFIED
    str     w1, [x0, #CONFIG_ENTRY_FLAGS]

    b       .Lset_mark_dirty

.Lset_find_next:
    ldr     x0, [sp, #56]
    add     x0, x0, #1
    b       .Lset_find_loop

.Lset_add_new:
    // Check if space available
    cmp     x21, #CONFIG_MAX_ENTRIES
    b.ge    .Lset_no_space

    // Calculate new entry pointer
    mov     x1, #CONFIG_ENTRY_SIZE
    mul     x1, x21, x1
    add     x0, x23, x1

    // Copy key
    str     x0, [sp, #56]               // Save entry ptr
    add     x0, x0, #CONFIG_ENTRY_KEY
    mov     x1, x19
    bl      strcpy

    // Copy value
    ldr     x0, [sp, #56]
    add     x0, x0, #CONFIG_ENTRY_VALUE
    mov     x1, x22
    bl      strcpy

    // Set type to string
    ldr     x0, [sp, #56]
    mov     w1, #CONFIG_TYPE_STRING
    str     w1, [x0, #CONFIG_ENTRY_TYPE]
    mov     w1, #CONFIG_FLAG_MODIFIED
    str     w1, [x0, #CONFIG_ENTRY_FLAGS]

    // Increment count
    add     w21, w21, #1
    str     w21, [x20, #CONFIG_STATE_COUNT]

.Lset_mark_dirty:
    // Mark config as dirty
    ldr     w1, [x20, #CONFIG_STATE_FLAGS]
    orr     w1, w1, #CONFIG_STATE_DIRTY
    str     w1, [x20, #CONFIG_STATE_FLAGS]

    mov     x0, #CONFIG_SUCCESS
    b       .Lset_done

.Lset_too_long:
    mov     x0, #CONFIG_ERR_TOO_LONG
    b       .Lset_done

.Lset_no_space:
    mov     x0, #CONFIG_ERR_NO_SPACE

.Lset_done:
    ldr     x19, [sp, #16]
    ldr     x20, [sp, #24]
    ldr     x21, [sp, #32]
    ldr     x22, [sp, #40]
    ldr     x23, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

// ----------------------------------------------------------------------------
// config_get_int - Get integer value by key
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = key (null-terminated string)
//   x1 = default value
// Outputs:
//   x0 = integer value or default if not found
// ----------------------------------------------------------------------------
config_get_int:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x1                     // Save default

    bl      config_get
    cbz     x0, .Lget_int_default

    // Parse integer
    bl      parse_int
    b       .Lget_int_done

.Lget_int_default:
    mov     x0, x19

.Lget_int_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ----------------------------------------------------------------------------
// config_get_bool - Get boolean value by key
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = key (null-terminated string)
//   x1 = default value (0 or 1)
// Outputs:
//   x0 = 0 (false) or 1 (true)
// ----------------------------------------------------------------------------
config_get_bool:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x1                     // Save default

    bl      config_get
    cbz     x0, .Lget_bool_default

    // Check for true values
    mov     x19, x0                     // Save value ptr

    // Check "true"
    mov     x0, x19
    adrp    x1, bool_true_1
    add     x1, x1, :lo12:bool_true_1
    bl      strcasecmp
    cbz     x0, .Lget_bool_true

    // Check "yes"
    mov     x0, x19
    adrp    x1, bool_true_2
    add     x1, x1, :lo12:bool_true_2
    bl      strcasecmp
    cbz     x0, .Lget_bool_true

    // Check "1"
    mov     x0, x19
    adrp    x1, bool_true_3
    add     x1, x1, :lo12:bool_true_3
    bl      strcmp
    cbz     x0, .Lget_bool_true

    // Check "on"
    mov     x0, x19
    adrp    x1, bool_true_4
    add     x1, x1, :lo12:bool_true_4
    bl      strcasecmp
    cbz     x0, .Lget_bool_true

    // Not a true value, return false
    mov     x0, #0
    b       .Lget_bool_done

.Lget_bool_true:
    mov     x0, #1
    b       .Lget_bool_done

.Lget_bool_default:
    mov     x0, x19

.Lget_bool_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ----------------------------------------------------------------------------
// Helper Functions
// ----------------------------------------------------------------------------

// strlen - Get string length
// Input: x0 = string
// Output: x0 = length
strlen:
    mov     x1, x0
.Lstrlen_loop:
    ldrb    w2, [x1], #1
    cbnz    w2, .Lstrlen_loop
    sub     x0, x1, x0
    sub     x0, x0, #1
    ret

// strcpy - Copy string
// Input: x0 = dest, x1 = src
// Output: x0 = dest
strcpy:
    mov     x2, x0
.Lstrcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    cbnz    w3, .Lstrcpy_loop
    mov     x0, x2
    ret

// strcmp - Compare strings
// Input: x0 = s1, x1 = s2
// Output: x0 = 0 if equal, non-zero otherwise
strcmp:
.Lstrcmp_loop:
    ldrb    w2, [x0], #1
    ldrb    w3, [x1], #1
    cmp     w2, w3
    b.ne    .Lstrcmp_diff
    cbz     w2, .Lstrcmp_equal
    b       .Lstrcmp_loop

.Lstrcmp_equal:
    mov     x0, #0
    ret

.Lstrcmp_diff:
    sub     x0, x2, x3
    ret

// strcasecmp - Compare strings case-insensitively
// Input: x0 = s1, x1 = s2
// Output: x0 = 0 if equal, non-zero otherwise
strcasecmp:
.Lstrcasecmp_loop:
    ldrb    w2, [x0], #1
    ldrb    w3, [x1], #1

    // Convert to lowercase
    cmp     w2, #'A'
    b.lt    .Lstrcasecmp_c1_done
    cmp     w2, #'Z'
    b.gt    .Lstrcasecmp_c1_done
    add     w2, w2, #32
.Lstrcasecmp_c1_done:
    cmp     w3, #'A'
    b.lt    .Lstrcasecmp_c2_done
    cmp     w3, #'Z'
    b.gt    .Lstrcasecmp_c2_done
    add     w3, w3, #32
.Lstrcasecmp_c2_done:

    cmp     w2, w3
    b.ne    .Lstrcasecmp_diff
    cbz     w2, .Lstrcasecmp_equal
    b       .Lstrcasecmp_loop

.Lstrcasecmp_equal:
    mov     x0, #0
    ret

.Lstrcasecmp_diff:
    sub     x0, x2, x3
    ret

// parse_int - Parse integer from string
// Input: x0 = string
// Output: x0 = integer value
parse_int:
    mov     x1, #0                      // result
    mov     x2, #0                      // negative flag

    // Check for minus sign
    ldrb    w3, [x0]
    cmp     w3, #'-'
    b.ne    .Lparse_int_loop
    mov     x2, #1
    add     x0, x0, #1

.Lparse_int_loop:
    ldrb    w3, [x0], #1
    cbz     w3, .Lparse_int_done

    // Check if digit
    sub     w3, w3, #'0'
    cmp     w3, #9
    b.hi    .Lparse_int_done

    // result = result * 10 + digit
    mov     x4, #10
    mul     x1, x1, x4
    add     x1, x1, x3
    b       .Lparse_int_loop

.Lparse_int_done:
    // Apply sign
    cbz     x2, .Lparse_int_positive
    neg     x1, x1

.Lparse_int_positive:
    mov     x0, x1
    ret

// ----------------------------------------------------------------------------
// config_get_list - Get comma-separated values as array of pointers
// ----------------------------------------------------------------------------
// Parses a config value like "tcp,bluetooth,wifi-mesh" into separate strings.
// The strings are written into the provided buffer, null-terminated.
//
// Inputs:
//   x0 = key (null-terminated string)
//   x1 = buffer to store strings (strings stored consecutively)
//   x2 = pointer to array of char* (to store pointers to each string)
//   x3 = max items
// Outputs:
//   x0 = number of items parsed, 0 if key not found or empty
// ----------------------------------------------------------------------------
config_get_list:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    str     x25, [sp, #64]

    mov     x20, x1                     // x20 = string buffer
    mov     x21, x2                     // x21 = pointer array
    mov     x22, x3                     // x22 = max items
    mov     x23, #0                     // x23 = item count
    mov     x24, x20                    // x24 = current write position

    // Get the config value
    bl      config_get
    cbz     x0, .Lgetlist_done

    mov     x19, x0                     // x19 = value string

    // Check if empty string
    ldrb    w0, [x19]
    cbz     w0, .Lgetlist_done

.Lgetlist_item_start:
    // Check max items
    cmp     x23, x22
    b.ge    .Lgetlist_done

    // Store pointer to this item in the array
    str     x24, [x21, x23, lsl #3]

    // Skip leading whitespace
.Lgetlist_skip_ws:
    ldrb    w0, [x19]
    cbz     w0, .Lgetlist_terminate_last
    cmp     w0, #' '
    b.eq    .Lgetlist_skip_ws_next
    cmp     w0, #'\t'
    b.ne    .Lgetlist_copy_char
.Lgetlist_skip_ws_next:
    add     x19, x19, #1
    b       .Lgetlist_skip_ws

.Lgetlist_copy_char:
    ldrb    w0, [x19], #1

    // Check for end of string
    cbz     w0, .Lgetlist_terminate_last

    // Check for comma separator
    cmp     w0, #','
    b.eq    .Lgetlist_end_item

    // Copy character
    strb    w0, [x24], #1
    b       .Lgetlist_copy_char

.Lgetlist_end_item:
    // Trim trailing whitespace from current item
    sub     x25, x24, #1
.Lgetlist_trim_ws:
    cmp     x25, x20
    b.lt    .Lgetlist_terminate
    ldrb    w0, [x25]
    cmp     w0, #' '
    b.eq    .Lgetlist_trim_next
    cmp     w0, #'\t'
    b.ne    .Lgetlist_terminate
.Lgetlist_trim_next:
    sub     x25, x25, #1
    sub     x24, x24, #1
    b       .Lgetlist_trim_ws

.Lgetlist_terminate:
    // Null-terminate this item
    strb    wzr, [x24], #1

    // Increment item count
    add     x23, x23, #1

    // Continue to next item
    b       .Lgetlist_item_start

.Lgetlist_terminate_last:
    // Trim trailing whitespace from last item
    sub     x25, x24, #1
.Lgetlist_trim_last:
    // Get the start of current item
    ldr     x0, [x21, x23, lsl #3]
    cmp     x25, x0
    b.lt    .Lgetlist_final_term
    ldrb    w0, [x25]
    cmp     w0, #' '
    b.eq    .Lgetlist_trim_last_next
    cmp     w0, #'\t'
    b.ne    .Lgetlist_final_term
.Lgetlist_trim_last_next:
    sub     x25, x25, #1
    sub     x24, x24, #1
    b       .Lgetlist_trim_last

.Lgetlist_final_term:
    // Null-terminate the last item
    strb    wzr, [x24]

    // Check if item is empty
    ldr     x0, [x21, x23, lsl #3]
    ldrb    w0, [x0]
    cbz     w0, .Lgetlist_done          // Empty item, don't count

    // Increment final count
    add     x23, x23, #1

.Lgetlist_done:
    mov     x0, x23                     // Return item count

    ldr     x25, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// ----------------------------------------------------------------------------
// config_has_value - Check if a value exists in a comma-separated list
// ----------------------------------------------------------------------------
// Checks if the given value is one of the comma-separated values in the
// config entry. Useful for checking if a transport is enabled, etc.
//
// Inputs:
//   x0 = key (null-terminated string)
//   x1 = value to find (null-terminated string)
// Outputs:
//   x0 = 1 if value found, 0 if not found
// ----------------------------------------------------------------------------
config_has_value:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x20, x1                     // x20 = value to find

    // Get the config value
    bl      config_get
    cbz     x0, .Lhasval_not_found

    mov     x19, x0                     // x19 = comma-separated string

.Lhasval_item_start:
    // Skip leading whitespace
.Lhasval_skip_ws:
    ldrb    w0, [x19]
    cbz     w0, .Lhasval_not_found
    cmp     w0, #' '
    b.eq    .Lhasval_skip_next
    cmp     w0, #'\t'
    b.ne    .Lhasval_compare
.Lhasval_skip_next:
    add     x19, x19, #1
    b       .Lhasval_skip_ws

.Lhasval_compare:
    // Compare current item with search value
    mov     x21, x19                    // x21 = start of current item
    mov     x22, x20                    // x22 = search value pointer

.Lhasval_cmp_loop:
    ldrb    w0, [x21]                   // Current char from list
    ldrb    w1, [x22]                   // Current char from search

    // Check if search value ended
    cbz     w1, .Lhasval_check_end

    // Check if list item ended (comma or null)
    cbz     w0, .Lhasval_no_match
    cmp     w0, #','
    b.eq    .Lhasval_no_match

    // Compare characters (case-insensitive)
    // Convert to lowercase
    cmp     w0, #'A'
    b.lt    .Lhasval_cmp_c1_done
    cmp     w0, #'Z'
    b.gt    .Lhasval_cmp_c1_done
    add     w0, w0, #32
.Lhasval_cmp_c1_done:
    cmp     w1, #'A'
    b.lt    .Lhasval_cmp_c2_done
    cmp     w1, #'Z'
    b.gt    .Lhasval_cmp_c2_done
    add     w1, w1, #32
.Lhasval_cmp_c2_done:

    cmp     w0, w1
    b.ne    .Lhasval_no_match

    add     x21, x21, #1
    add     x22, x22, #1
    b       .Lhasval_cmp_loop

.Lhasval_check_end:
    // Search value ended, check if list item also ended
    ldrb    w0, [x21]
    cbz     w0, .Lhasval_found          // End of string = match
    cmp     w0, #','
    b.eq    .Lhasval_found              // Comma = match
    cmp     w0, #' '
    b.eq    .Lhasval_found              // Space = match (trailing ws)
    cmp     w0, #'\t'
    b.eq    .Lhasval_found              // Tab = match
    // Item continues, not a match
    b       .Lhasval_no_match

.Lhasval_no_match:
    // Skip to next comma or end
.Lhasval_skip_item:
    ldrb    w0, [x19], #1
    cbz     w0, .Lhasval_not_found
    cmp     w0, #','
    b.ne    .Lhasval_skip_item
    // Found comma, check next item
    b       .Lhasval_item_start

.Lhasval_found:
    mov     x0, #1
    b       .Lhasval_done

.Lhasval_not_found:
    mov     x0, #0

.Lhasval_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size config_has_value, .-config_has_value

// ============================================================================
// Behavior Helper Functions
// ============================================================================
// High-level functions to check runtime behaviors based on config.

// ============================================================================
// behavior_relay_enabled - Check if relay_for_others is enabled
// ============================================================================
// Output: x0 = 1 if enabled, 0 if disabled
// ============================================================================
.global behavior_relay_enabled
.type behavior_relay_enabled, %function
behavior_relay_enabled:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, cfg_key_relay
    add     x0, x0, :lo12:cfg_key_relay
    bl      config_get_bool
    // Default to yes if not configured (community-friendly default)
    cmp     x0, #-1
    csel    x0, x0, xzr, ne     // If -1 (not found), return 0? No, default yes
    b.ne    .Lrelay_ret
    mov     x0, #1              // Default: relay enabled

.Lrelay_ret:
    ldp     x29, x30, [sp], #16
    ret
.size behavior_relay_enabled, .-behavior_relay_enabled

// ============================================================================
// behavior_discoverable - Check if node is discoverable
// ============================================================================
// Output: x0 = 1 if discoverable, 0 if not
// ============================================================================
.global behavior_discoverable
.type behavior_discoverable, %function
behavior_discoverable:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, cfg_key_discoverable
    add     x0, x0, :lo12:cfg_key_discoverable
    bl      config_get_bool
    cmp     x0, #-1
    b.ne    .Ldisc_ret
    mov     x0, #1              // Default: discoverable

.Ldisc_ret:
    ldp     x29, x30, [sp], #16
    ret
.size behavior_discoverable, .-behavior_discoverable

// ============================================================================
// behavior_store_others - Get store_others_data setting
// ============================================================================
// Output: x0 = 0 (no), 1 (cache), 2 (replicate)
// ============================================================================
.global behavior_store_others
.type behavior_store_others, %function
behavior_store_others:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    adrp    x0, cfg_key_store_others
    add     x0, x0, :lo12:cfg_key_store_others
    bl      config_get
    cbz     x0, .Lstore_default

    mov     x19, x0             // Save value pointer

    // Check "cache"
    adrp    x1, cfg_val_cache
    add     x1, x1, :lo12:cfg_val_cache
    bl      cfg_strcmp_simple
    cbz     x0, .Lstore_cache

    // Check "replicate"
    mov     x0, x19
    adrp    x1, cfg_val_replicate
    add     x1, x1, :lo12:cfg_val_replicate
    bl      cfg_strcmp_simple
    cbz     x0, .Lstore_replicate

    // Check "yes" (same as replicate)
    mov     x0, x19
    adrp    x1, cfg_val_yes
    add     x1, x1, :lo12:cfg_val_yes
    bl      cfg_strcmp_simple
    cbz     x0, .Lstore_replicate

    // Default to no
    b       .Lstore_no

.Lstore_cache:
    mov     x0, #1
    b       .Lstore_ret

.Lstore_replicate:
    mov     x0, #2
    b       .Lstore_ret

.Lstore_no:
    mov     x0, #0
    b       .Lstore_ret

.Lstore_default:
    mov     x0, #0              // Default: no

.Lstore_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size behavior_store_others, .-behavior_store_others

// ============================================================================
// behavior_use_internet - Get use_internet setting
// ============================================================================
// Output: x0 = 0 (no), 1 (backup), 2 (yes)
// ============================================================================
.global behavior_use_internet
.type behavior_use_internet, %function
behavior_use_internet:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    adrp    x0, cfg_key_use_internet
    add     x0, x0, :lo12:cfg_key_use_internet
    bl      config_get
    cbz     x0, .Linet_default

    mov     x19, x0

    // Check "yes"
    adrp    x1, cfg_val_yes
    add     x1, x1, :lo12:cfg_val_yes
    bl      cfg_strcmp_simple
    cbz     x0, .Linet_yes

    // Check "backup"
    mov     x0, x19
    adrp    x1, cfg_val_backup
    add     x1, x1, :lo12:cfg_val_backup
    bl      cfg_strcmp_simple
    cbz     x0, .Linet_backup

    // Default: no
    b       .Linet_no

.Linet_yes:
    mov     x0, #2
    b       .Linet_ret

.Linet_backup:
    mov     x0, #1
    b       .Linet_ret

.Linet_no:
    mov     x0, #0
    b       .Linet_ret

.Linet_default:
    mov     x0, #2              // Default: yes (use internet)

.Linet_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size behavior_use_internet, .-behavior_use_internet

// cfg_strcmp_simple - Simple string comparison
// Input: x0, x1 = strings
// Output: x0 = 0 if equal
cfg_strcmp_simple:
    ldrb    w2, [x0], #1
    ldrb    w3, [x1], #1
    cmp     w2, w3
    b.ne    .Lcfgcmp_diff
    cbz     w2, .Lcfgcmp_eq
    b       cfg_strcmp_simple
.Lcfgcmp_eq:
    mov     x0, #0
    ret
.Lcfgcmp_diff:
    mov     x0, #1
    ret
.size cfg_strcmp_simple, .-cfg_strcmp_simple

// ============================================================================
// Behavior config keys
// ============================================================================
.section .rodata
cfg_key_relay:          .asciz "relay_for_others"
cfg_key_discoverable:   .asciz "discoverable"
cfg_key_store_others:   .asciz "store_others_data"
cfg_key_use_internet:   .asciz "use_internet"
cfg_val_cache:          .asciz "cache"
cfg_val_replicate:      .asciz "replicate"
cfg_val_yes:            .asciz "yes"
cfg_val_backup:         .asciz "backup"
