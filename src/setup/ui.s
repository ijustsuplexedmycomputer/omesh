// Terminal UI Helpers for Setup Wizard
// src/setup/ui.s
//
// Simple ANSI terminal UI functions for the setup wizard.
// These provide formatted output without ncurses dependency.
//
// Functions:
//   ui_clear              - Clear screen
//   ui_set_cursor         - Move cursor to row, col
//   ui_bold_on            - Enable bold text
//   ui_bold_off           - Reset formatting
//   ui_color              - Set foreground color
//   ui_color_reset        - Reset colors
//   ui_print_header       - Print centered header with box
//   ui_print_menu         - Print menu with selection highlight
//   ui_prompt_string      - Get string input
//   ui_prompt_int         - Get integer input
//   ui_prompt_choice      - Get menu selection
//   ui_prompt_yesno       - Get yes/no answer
//   ui_print_line         - Print horizontal line
//   ui_print_box          - Print text in a box

.include "include/syscall_nums.inc"
.include "include/setup.inc"

.global ui_clear
.global ui_set_cursor
.global ui_bold_on
.global ui_bold_off
.global ui_color
.global ui_color_reset
.global ui_print_header
.global ui_print_menu
.global ui_prompt_string
.global ui_prompt_int
.global ui_prompt_choice
.global ui_prompt_yesno
.global ui_print_line
.global ui_print_box
.global ui_print
.global ui_println
.global ui_get_terminal_size

// ============================================================================
// Constants
// ============================================================================

// ANSI color codes
.equ COLOR_BLACK,           30
.equ COLOR_RED,             31
.equ COLOR_GREEN,           32
.equ COLOR_YELLOW,          33
.equ COLOR_BLUE,            34
.equ COLOR_MAGENTA,         35
.equ COLOR_CYAN,            36
.equ COLOR_WHITE,           37

// Input buffer size
.equ INPUT_BUF_SIZE,        256

// ============================================================================
// BSS Section
// ============================================================================

.section .bss
.align 8

// Input buffer
input_buf:
    .skip INPUT_BUF_SIZE

// Format buffer for ANSI sequences
ansi_buf:
    .skip 32

// Terminal size
term_width:
    .skip 4
term_height:
    .skip 4

// ============================================================================
// Text Section
// ============================================================================

.section .text

// ----------------------------------------------------------------------------
// ui_clear - Clear the screen
// ----------------------------------------------------------------------------
// Uses ANSI escape sequence: ESC[2J ESC[H
// ----------------------------------------------------------------------------
.type ui_clear, %function
ui_clear:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x0, #1              // stdout
    adrp    x1, ansi_clear
    add     x1, x1, :lo12:ansi_clear
    mov     x2, #7              // Length of "\033[2J\033[H"
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #16
    ret
.size ui_clear, . - ui_clear

// ----------------------------------------------------------------------------
// ui_set_cursor - Move cursor to position
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = row (1-based)
//   x1 = col (1-based)
// ----------------------------------------------------------------------------
.type ui_set_cursor, %function
ui_set_cursor:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // row
    mov     x20, x1             // col

    // Build escape sequence: ESC[row;colH
    adrp    x0, ansi_buf
    add     x0, x0, :lo12:ansi_buf

    mov     w1, #0x1B           // ESC
    strb    w1, [x0], #1
    mov     w1, #'['
    strb    w1, [x0], #1

    // Convert row to string
    mov     x1, x19
    bl      ui_int_to_str
    // x0 now points past the digits

    mov     w1, #';'
    strb    w1, [x0], #1

    // Convert col to string
    mov     x1, x20
    bl      ui_int_to_str

    mov     w1, #'H'
    strb    w1, [x0], #1
    strb    wzr, [x0]           // Null terminate

    // Calculate length
    adrp    x1, ansi_buf
    add     x1, x1, :lo12:ansi_buf
    sub     x2, x0, x1

    // Write
    mov     x0, #1
    mov     x8, #SYS_write
    svc     #0

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size ui_set_cursor, . - ui_set_cursor

// ----------------------------------------------------------------------------
// ui_bold_on - Enable bold text
// ----------------------------------------------------------------------------
.type ui_bold_on, %function
ui_bold_on:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x0, #1
    adrp    x1, ansi_bold
    add     x1, x1, :lo12:ansi_bold
    mov     x2, #4              // "\033[1m"
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #16
    ret
.size ui_bold_on, . - ui_bold_on

// ----------------------------------------------------------------------------
// ui_bold_off - Reset text formatting
// ----------------------------------------------------------------------------
.type ui_bold_off, %function
ui_bold_off:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x0, #1
    adrp    x1, ansi_reset
    add     x1, x1, :lo12:ansi_reset
    mov     x2, #4              // "\033[0m"
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #16
    ret
.size ui_bold_off, . - ui_bold_off

// ----------------------------------------------------------------------------
// ui_color - Set foreground color
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = color code (30-37)
// ----------------------------------------------------------------------------
.type ui_color, %function
ui_color:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    // Build escape sequence: ESC[XXm
    adrp    x0, ansi_buf
    add     x0, x0, :lo12:ansi_buf

    mov     w1, #0x1B
    strb    w1, [x0], #1
    mov     w1, #'['
    strb    w1, [x0], #1

    mov     x1, x19
    bl      ui_int_to_str

    mov     w1, #'m'
    strb    w1, [x0], #1
    strb    wzr, [x0]

    adrp    x1, ansi_buf
    add     x1, x1, :lo12:ansi_buf
    sub     x2, x0, x1

    mov     x0, #1
    mov     x8, #SYS_write
    svc     #0

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size ui_color, . - ui_color

// ----------------------------------------------------------------------------
// ui_color_reset - Reset colors
// ----------------------------------------------------------------------------
.type ui_color_reset, %function
ui_color_reset:
    b       ui_bold_off         // Same as reset
.size ui_color_reset, . - ui_color_reset

// ----------------------------------------------------------------------------
// ui_print - Print string to stdout
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = string pointer
// ----------------------------------------------------------------------------
.type ui_print, %function
ui_print:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0             // Save string pointer
    bl      ui_strlen
    mov     x2, x0              // Length

    mov     x0, #1              // stdout
    mov     x1, x19             // Buffer
    mov     x8, #SYS_write
    svc     #0

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size ui_print, . - ui_print

// ----------------------------------------------------------------------------
// ui_println - Print string with newline
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = string pointer
// ----------------------------------------------------------------------------
.type ui_println, %function
ui_println:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      ui_print

    mov     x0, #1
    adrp    x1, str_newline
    add     x1, x1, :lo12:str_newline
    mov     x2, #1
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #16
    ret
.size ui_println, . - ui_println

// ----------------------------------------------------------------------------
// ui_print_header - Print centered header in a box
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = title string
// ----------------------------------------------------------------------------
.type ui_print_header, %function
ui_print_header:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // Save title

    // Get title length
    bl      ui_strlen
    mov     x20, x0             // Title length

    // Get terminal width (default 80)
    bl      ui_get_terminal_size
    adrp    x0, term_width
    add     x0, x0, :lo12:term_width
    ldr     w21, [x0]
    cmp     w21, #40
    b.ge    .Lheader_width_ok
    mov     w21, #80
.Lheader_width_ok:

    // Calculate left padding: (width - title_len - 4) / 2
    // The 4 accounts for "| " and " |"
    sub     x22, x21, x20
    sub     x22, x22, #4
    lsr     x22, x22, #1        // x22 = left padding

    // Print newline
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Print top border: + followed by dashes and +
    bl      ui_bold_on
    mov     x0, #COLOR_CYAN
    bl      ui_color

    adrp    x0, str_box_tl
    add     x0, x0, :lo12:str_box_tl
    bl      ui_print

    sub     x0, x21, #2         // width - 2 corners
    bl      ui_print_hline

    adrp    x0, str_box_tr
    add     x0, x0, :lo12:str_box_tr
    bl      ui_print

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Print title line: | padding title padding |
    adrp    x0, str_box_v
    add     x0, x0, :lo12:str_box_v
    bl      ui_print

    // Left space
    mov     x0, #1
    bl      ui_print_spaces

    // Left padding
    mov     x0, x22
    bl      ui_print_spaces

    // Reset color, print title bold
    bl      ui_color_reset
    bl      ui_bold_on
    mov     x0, x19
    bl      ui_print
    bl      ui_bold_off

    // Set color back for right side
    mov     x0, #COLOR_CYAN
    bl      ui_color

    // Right padding = width - title_len - left_padding - 4
    sub     x0, x21, x20
    sub     x0, x0, x22
    sub     x0, x0, #4
    bl      ui_print_spaces

    // Right space
    mov     x0, #1
    bl      ui_print_spaces

    adrp    x0, str_box_v
    add     x0, x0, :lo12:str_box_v
    bl      ui_print

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Print bottom border
    adrp    x0, str_box_bl
    add     x0, x0, :lo12:str_box_bl
    bl      ui_print

    sub     x0, x21, #2
    bl      ui_print_hline

    adrp    x0, str_box_br
    add     x0, x0, :lo12:str_box_br
    bl      ui_print

    bl      ui_color_reset

    // Two newlines after header
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size ui_print_header, . - ui_print_header

// ----------------------------------------------------------------------------
// ui_print_hline - Print horizontal line characters
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = count
// ----------------------------------------------------------------------------
.type ui_print_hline, %function
ui_print_hline:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0
    cbz     x19, .Lhline_done

.Lhline_loop:
    adrp    x0, str_box_h
    add     x0, x0, :lo12:str_box_h
    bl      ui_print

    sub     x19, x19, #1
    cbnz    x19, .Lhline_loop

.Lhline_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size ui_print_hline, . - ui_print_hline

// ----------------------------------------------------------------------------
// ui_print_spaces - Print space characters
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = count
// ----------------------------------------------------------------------------
.type ui_print_spaces, %function
ui_print_spaces:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0
    cmp     x19, #0
    b.le    .Lspaces_done

.Lspaces_loop:
    mov     x0, #1
    adrp    x1, str_space
    add     x1, x1, :lo12:str_space
    mov     x2, #1
    mov     x8, #SYS_write
    svc     #0

    sub     x19, x19, #1
    cbnz    x19, .Lspaces_loop

.Lspaces_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size ui_print_spaces, . - ui_print_spaces

// ----------------------------------------------------------------------------
// ui_print_menu - Print menu with selection highlight
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = pointer to array of string pointers
//   x1 = count of options
//   x2 = selected index (0-based)
// ----------------------------------------------------------------------------
.type ui_print_menu, %function
ui_print_menu:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0             // Options array
    mov     x20, x1             // Count
    mov     x21, x2             // Selected
    mov     x22, #0             // Current index

.Lmenu_loop:
    cmp     x22, x20
    b.ge    .Lmenu_done

    // Check if this is selected
    cmp     x22, x21
    b.ne    .Lmenu_not_selected

    // Selected - print with highlight
    bl      ui_bold_on
    mov     x0, #COLOR_CYAN
    bl      ui_color
    adrp    x0, str_menu_sel
    add     x0, x0, :lo12:str_menu_sel
    bl      ui_print
    b       .Lmenu_print_option

.Lmenu_not_selected:
    adrp    x0, str_menu_item
    add     x0, x0, :lo12:str_menu_item
    bl      ui_print

.Lmenu_print_option:
    // Print option number
    add     x0, x22, #1
    bl      ui_print_digit

    adrp    x0, str_menu_sep
    add     x0, x0, :lo12:str_menu_sep
    bl      ui_print

    // Print option text
    ldr     x0, [x19, x22, lsl #3]
    bl      ui_print

    cmp     x22, x21
    b.ne    .Lmenu_no_reset
    bl      ui_color_reset

.Lmenu_no_reset:
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    add     x22, x22, #1
    b       .Lmenu_loop

.Lmenu_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size ui_print_menu, . - ui_print_menu

// ----------------------------------------------------------------------------
// ui_prompt_string - Get string input from user
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = prompt string
//   x1 = buffer to store result
//   x2 = max length
// Outputs:
//   x0 = length of input (0 if empty/cancelled)
// ----------------------------------------------------------------------------
.type ui_prompt_string, %function
ui_prompt_string:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    mov     x19, x1             // Buffer
    mov     x20, x2             // Max length

    // Print prompt
    bl      ui_print

    // Print ": "
    adrp    x0, str_prompt_sep
    add     x0, x0, :lo12:str_prompt_sep
    bl      ui_print

    // Read input
    mov     x0, #0              // stdin
    mov     x1, x19
    mov     x2, x20
    sub     x2, x2, #1          // Leave room for null
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #0
    b.le    .Lprompt_str_empty

    mov     x21, x0             // Save length

    // Remove trailing newline
    sub     x1, x21, #1
    ldrb    w2, [x19, x1]
    cmp     w2, #'\n'
    b.ne    .Lprompt_str_done
    strb    wzr, [x19, x1]
    sub     x21, x21, #1

.Lprompt_str_done:
    // Null terminate
    strb    wzr, [x19, x21]
    mov     x0, x21
    b       .Lprompt_str_ret

.Lprompt_str_empty:
    strb    wzr, [x19]
    mov     x0, #0

.Lprompt_str_ret:
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size ui_prompt_string, . - ui_prompt_string

// ----------------------------------------------------------------------------
// ui_prompt_int - Get integer input from user
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = prompt string
//   x1 = default value
// Outputs:
//   x0 = integer value
// ----------------------------------------------------------------------------
.type ui_prompt_int, %function
ui_prompt_int:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x1             // Default value

    // Print prompt
    bl      ui_print

    // Print default hint
    adrp    x0, str_default_start
    add     x0, x0, :lo12:str_default_start
    bl      ui_print

    mov     x0, x19
    bl      ui_print_number

    adrp    x0, str_default_end
    add     x0, x0, :lo12:str_default_end
    bl      ui_print

    // Read input
    adrp    x1, input_buf
    add     x1, x1, :lo12:input_buf
    mov     x0, #0
    mov     x2, #INPUT_BUF_SIZE - 1
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #1
    b.le    .Lprompt_int_default  // Empty or error - use default

    // Parse integer
    adrp    x0, input_buf
    add     x0, x0, :lo12:input_buf
    bl      ui_parse_int
    b       .Lprompt_int_done

.Lprompt_int_default:
    mov     x0, x19

.Lprompt_int_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size ui_prompt_int, . - ui_prompt_int

// ----------------------------------------------------------------------------
// ui_prompt_choice - Get menu selection from user
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = prompt string
//   x1 = pointer to array of string pointers
//   x2 = count of options
// Outputs:
//   x0 = selected index (0-based)
// ----------------------------------------------------------------------------
.type ui_prompt_choice, %function
ui_prompt_choice:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]

    mov     x19, x0             // Prompt
    mov     x20, x1             // Options
    mov     x21, x2             // Count

    // Print prompt
    mov     x0, x19
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Print menu
    mov     x0, x20
    mov     x1, x21
    mov     x2, #0              // No selection highlight initially
    bl      ui_print_menu

    // Print selection prompt
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    adrp    x0, str_choice_prompt
    add     x0, x0, :lo12:str_choice_prompt
    bl      ui_print

    // Read input
    adrp    x1, input_buf
    add     x1, x1, :lo12:input_buf
    mov     x0, #0
    mov     x2, #INPUT_BUF_SIZE - 1
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #1
    b.le    .Lprompt_choice_default

    // Parse number
    adrp    x0, input_buf
    add     x0, x0, :lo12:input_buf
    bl      ui_parse_int

    // Convert to 0-based and validate
    sub     x0, x0, #1
    cmp     x0, #0
    b.lt    .Lprompt_choice_default
    cmp     x0, x21
    b.ge    .Lprompt_choice_default
    b       .Lprompt_choice_done

.Lprompt_choice_default:
    mov     x0, #0

.Lprompt_choice_done:
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size ui_prompt_choice, . - ui_prompt_choice

// ----------------------------------------------------------------------------
// ui_prompt_yesno - Get yes/no answer from user
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = prompt string
//   x1 = default (0 = no, 1 = yes)
// Outputs:
//   x0 = 0 (no) or 1 (yes)
// ----------------------------------------------------------------------------
.type ui_prompt_yesno, %function
ui_prompt_yesno:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x1             // Default

    // Print prompt
    bl      ui_print

    // Print [y/n] with default highlighted
    cbz     x19, .Lyesno_default_no
    adrp    x0, str_yesno_y
    add     x0, x0, :lo12:str_yesno_y
    b       .Lyesno_print_hint
.Lyesno_default_no:
    adrp    x0, str_yesno_n
    add     x0, x0, :lo12:str_yesno_n
.Lyesno_print_hint:
    bl      ui_print

    // Read input
    adrp    x1, input_buf
    add     x1, x1, :lo12:input_buf
    mov     x0, #0
    mov     x2, #INPUT_BUF_SIZE - 1
    mov     x8, #SYS_read
    svc     #0

    cmp     x0, #1
    b.le    .Lyesno_default     // Empty - use default

    // Check first character
    adrp    x0, input_buf
    add     x0, x0, :lo12:input_buf
    ldrb    w0, [x0]

    // Check for 'y' or 'Y'
    cmp     w0, #'y'
    b.eq    .Lyesno_yes
    cmp     w0, #'Y'
    b.eq    .Lyesno_yes

    // Check for 'n' or 'N'
    cmp     w0, #'n'
    b.eq    .Lyesno_no
    cmp     w0, #'N'
    b.eq    .Lyesno_no

    // Unknown - use default
    b       .Lyesno_default

.Lyesno_yes:
    mov     x0, #1
    b       .Lyesno_done

.Lyesno_no:
    mov     x0, #0
    b       .Lyesno_done

.Lyesno_default:
    mov     x0, x19

.Lyesno_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size ui_prompt_yesno, . - ui_prompt_yesno

// ----------------------------------------------------------------------------
// ui_print_line - Print horizontal separator line
// ----------------------------------------------------------------------------
.type ui_print_line, %function
ui_print_line:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x0, #COLOR_CYAN
    bl      ui_color

    // Get width
    bl      ui_get_terminal_size
    adrp    x0, term_width
    add     x0, x0, :lo12:term_width
    ldr     w0, [x0]
    cmp     w0, #0
    b.ne    .Lline_width_ok
    mov     w0, #80
.Lline_width_ok:

    bl      ui_print_hline

    bl      ui_color_reset
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    ldp     x29, x30, [sp], #16
    ret
.size ui_print_line, . - ui_print_line

// ----------------------------------------------------------------------------
// ui_get_terminal_size - Get terminal dimensions
// ----------------------------------------------------------------------------
// Outputs: Updates term_width and term_height globals
// Uses ioctl TIOCGWINSZ
// ----------------------------------------------------------------------------
.type ui_get_terminal_size, %function
ui_get_terminal_size:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // winsize struct on stack (4 shorts = 8 bytes)
    sub     sp, sp, #16

    // ioctl(STDOUT, TIOCGWINSZ, &winsize)
    mov     x0, #1              // stdout
    mov     x1, #0x5413         // TIOCGWINSZ
    mov     x2, sp
    mov     x8, #SYS_ioctl
    svc     #0

    cmp     x0, #0
    b.lt    .Lterm_size_default

    // ws_row at offset 0, ws_col at offset 2
    ldrh    w0, [sp, #2]        // cols
    ldrh    w1, [sp]            // rows

    adrp    x2, term_width
    add     x2, x2, :lo12:term_width
    str     w0, [x2]

    adrp    x2, term_height
    add     x2, x2, :lo12:term_height
    str     w1, [x2]
    b       .Lterm_size_done

.Lterm_size_default:
    // Use defaults
    adrp    x2, term_width
    add     x2, x2, :lo12:term_width
    mov     w0, #TERM_WIDTH_DEFAULT
    str     w0, [x2]

    adrp    x2, term_height
    add     x2, x2, :lo12:term_height
    mov     w0, #TERM_HEIGHT_DEFAULT
    str     w0, [x2]

.Lterm_size_done:
    add     sp, sp, #16
    ldp     x29, x30, [sp], #32
    ret
.size ui_get_terminal_size, . - ui_get_terminal_size

// ============================================================================
// Helper Functions
// ============================================================================

// ui_strlen - Get string length
.type ui_strlen, %function
ui_strlen:
    mov     x1, x0
.Lui_strlen_loop:
    ldrb    w2, [x1], #1
    cbnz    w2, .Lui_strlen_loop
    sub     x0, x1, x0
    sub     x0, x0, #1
    ret
.size ui_strlen, . - ui_strlen

// ui_int_to_str - Convert integer to string at buffer position
// Input: x0 = buffer pointer, x1 = value
// Output: x0 = pointer past last digit
.type ui_int_to_str, %function
ui_int_to_str:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    mov     x2, x0              // Buffer
    mov     x3, x1              // Value

    // Handle 0 specially
    cbnz    x3, .Lint_to_str_convert
    mov     w4, #'0'
    strb    w4, [x2], #1
    mov     x0, x2
    b       .Lint_to_str_done

.Lint_to_str_convert:
    // Build digits in reverse on stack
    add     x4, sp, #32         // Temp buffer end
    mov     x5, x4              // Current position

.Lint_to_str_loop:
    cbz     x3, .Lint_to_str_copy
    mov     x6, #10
    udiv    x7, x3, x6
    msub    x8, x7, x6, x3      // x8 = x3 % 10
    add     w8, w8, #'0'
    sub     x5, x5, #1
    strb    w8, [x5]
    mov     x3, x7
    b       .Lint_to_str_loop

.Lint_to_str_copy:
    // Copy from temp to buffer
.Lint_to_str_copy_loop:
    cmp     x5, x4
    b.ge    .Lint_to_str_finish
    ldrb    w6, [x5], #1
    strb    w6, [x2], #1
    b       .Lint_to_str_copy_loop

.Lint_to_str_finish:
    mov     x0, x2

.Lint_to_str_done:
    ldp     x29, x30, [sp], #48
    ret
.size ui_int_to_str, . - ui_int_to_str

// ui_parse_int - Parse integer from string
// Input: x0 = string
// Output: x0 = integer value
.type ui_parse_int, %function
ui_parse_int:
    mov     x1, #0              // Result
    mov     x2, #10             // Multiplier

.Lparse_int_loop:
    ldrb    w3, [x0], #1
    sub     w4, w3, #'0'
    cmp     w4, #9
    b.hi    .Lparse_int_done
    madd    x1, x1, x2, x4
    b       .Lparse_int_loop

.Lparse_int_done:
    mov     x0, x1
    ret
.size ui_parse_int, . - ui_parse_int

// ui_print_digit - Print single digit (1-9)
// Input: x0 = digit value
.type ui_print_digit, %function
ui_print_digit:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    add     w0, w0, #'0'
    strb    w0, [sp, #16]       // Store in safe location (not over saved regs)
    mov     x0, #1
    add     x1, sp, #16
    mov     x2, #1
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #32
    ret
.size ui_print_digit, . - ui_print_digit

// ui_print_number - Print number
// Input: x0 = number
.type ui_print_number, %function
ui_print_number:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Convert to string
    adrp    x1, ansi_buf
    add     x1, x1, :lo12:ansi_buf
    add     x0, x1, #16         // Use end of buffer
    bl      ui_int_to_str_rev

    // Print
    adrp    x0, ansi_buf
    add     x0, x0, :lo12:ansi_buf
    add     x0, x0, #16
    bl      ui_print

    ldp     x29, x30, [sp], #32
    ret
.size ui_print_number, . - ui_print_number

// ui_int_to_str_rev - Convert int to string (builds backward from x0)
// Input: x0 = buffer end, x1 = value
// Output: writes string, x0 = start of string
.type ui_int_to_str_rev, %function
ui_int_to_str_rev:
    mov     x2, x0              // End of buffer
    mov     x3, x1              // Value

    // Null terminate
    strb    wzr, [x2]

    // Handle 0
    cbnz    x3, .Lrev_loop
    sub     x2, x2, #1
    mov     w4, #'0'
    strb    w4, [x2]
    mov     x0, x2
    ret

.Lrev_loop:
    cbz     x3, .Lrev_done
    sub     x2, x2, #1
    mov     x4, #10
    udiv    x5, x3, x4
    msub    x6, x5, x4, x3      // x6 = x3 % 10
    add     w6, w6, #'0'
    strb    w6, [x2]
    mov     x3, x5
    b       .Lrev_loop

.Lrev_done:
    mov     x0, x2
    ret
.size ui_int_to_str_rev, . - ui_int_to_str_rev

// ============================================================================
// Read-only Data
// ============================================================================

.section .rodata
.balign 8

// ANSI escape sequences
ansi_clear:
    .ascii "\033[2J\033[H"
    .equ ansi_clear_len, . - ansi_clear

ansi_bold:
    .asciz "\033[1m"

ansi_reset:
    .asciz "\033[0m"

// Box drawing (ASCII fallback)
str_box_tl:
    .asciz "+"

str_box_tr:
    .asciz "+"

str_box_bl:
    .asciz "+"

str_box_br:
    .asciz "+"

str_box_h:
    .asciz "-"

str_box_v:
    .asciz "|"

str_space:
    .asciz " "

str_newline:
    .asciz "\n"

str_prompt_sep:
    .asciz ": "

str_default_start:
    .asciz " ["

str_default_end:
    .asciz "]: "

str_yesno_y:
    .asciz " [Y/n]: "

str_yesno_n:
    .asciz " [y/N]: "

str_choice_prompt:
    .asciz "Enter choice: "

str_menu_sel:
    .asciz "  > "

str_menu_item:
    .asciz "    "

str_menu_sep:
    .asciz ". "

// ============================================================================
// End of ui.s
// ============================================================================
