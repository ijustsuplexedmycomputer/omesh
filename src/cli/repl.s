// =============================================================================
// Omesh - Interactive REPL (Read-Eval-Print Loop)
// =============================================================================
//
// Interactive command-line interface:
// - repl_init: Initialize REPL state
// - repl_run: Main REPL loop
// - repl_cmd_*: Individual command handlers
//
// Commands:
//   index <text>     - Index a document
//   search <query>   - Execute distributed search
//   peers            - List connected peers
//   status           - Show node status
//   connect <ip:port>- Connect to peer
//   quit             - Exit REPL
//   help             - Show commands
//
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"
.include "cluster.inc"

.data

// =============================================================================
// REPL Strings
// =============================================================================

str_banner:
    .asciz  "\nOmesh Distributed Search v0.1\n"
str_banner_len = . - str_banner

str_prompt:
    .asciz  "omesh> "
str_prompt_len = . - str_prompt

str_newline:
    .asciz  "\n"

str_help:
    .ascii  "\nCommands:\n"
    .ascii  "  index <text>      Index a document\n"
    .ascii  "  search <query>    Execute distributed search\n"
    .ascii  "  peers             List connected peers\n"
    .ascii  "  status            Show node status\n"
    .ascii  "  connect <ip:port> Connect to peer\n"
    .ascii  "  quit              Exit REPL\n"
    .asciz  "  help              Show this help\n\n"
str_help_len = . - str_help

str_goodbye:
    .asciz  "Goodbye.\n"
str_goodbye_len = . - str_goodbye

str_unknown:
    .asciz  "Unknown command. Type 'help' for available commands.\n"
str_unknown_len = . - str_unknown

str_status_hdr:
    .asciz  "\nNode Status:\n"
str_node_id:
    .asciz  "  Node ID: 0x"
str_state:
    .asciz  "  State:   "
str_docs:
    .asciz  "  Docs:    "
str_peers:
    .asciz  "  Peers:   "

str_state_init:
    .asciz  "INIT\n"
str_state_syncing:
    .asciz  "SYNCING\n"
str_state_ready:
    .asciz  "READY\n"
str_state_shutdown:
    .asciz  "SHUTDOWN\n"

str_no_peers:
    .asciz  "No connected peers.\n"

str_indexed:
    .asciz  "Indexed doc 0x"
str_indexed_suffix:
    .asciz  " (local)\n"

str_search_hdr:
    .asciz  "Query "
str_search_results:
    .asciz  " results:\n"
str_no_results:
    .asciz  "No results found.\n"

str_doc_prefix:
    .asciz  "  [doc:0x"
str_score_prefix:
    .asciz  "]  score:"

str_connect_usage:
    .asciz  "Usage: connect <ip:port>\n"
str_index_usage:
    .asciz  "Usage: index <text>\n"
str_search_usage:
    .asciz  "Usage: search <query>\n"

// Command strings for matching
cmd_help:
    .asciz  "help"
cmd_quit:
    .asciz  "quit"
cmd_exit:
    .asciz  "exit"
cmd_status:
    .asciz  "status"
cmd_peers:
    .asciz  "peers"
cmd_index:
    .asciz  "index"
cmd_search:
    .asciz  "search"
cmd_connect:
    .asciz  "connect"

// =============================================================================
// REPL Buffers
// =============================================================================

.align 8
repl_line_buf:
    .skip   REPL_LINE_SIZE

repl_output_buf:
    .skip   REPL_OUTPUT_SIZE

// Document ID counter for simple ID generation
doc_id_counter:
    .quad   0

.text

// =============================================================================
// repl_init - Initialize REPL
// =============================================================================
// Output:
//   x0 = 0
// =============================================================================
.global repl_init
.type repl_init, %function
repl_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Print banner
    mov     x0, #1                      // stdout
    adrp    x1, str_banner
    add     x1, x1, :lo12:str_banner
    mov     x2, #(str_banner_len - 1)
    mov     x8, #SYS_write
    svc     #0

    // Print node ID
    adrp    x1, str_node_id
    add     x1, x1, :lo12:str_node_id
    bl      print_str
    bl      node_get_id
    bl      print_hex64
    adrp    x1, str_newline
    add     x1, x1, :lo12:str_newline
    bl      print_str

    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret
.size repl_init, .-repl_init

// =============================================================================
// repl_run - Main REPL loop
// =============================================================================
// Output:
//   x0 = 0 on quit, -errno on error
// =============================================================================
.global repl_run
.type repl_run, %function
repl_run:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

.Lrepl_loop:
    // Check if shutdown was requested (signal received)
    bl      signal_shutdown_requested
    cbnz    x0, .Lrepl_shutdown

    // Print prompt
    mov     x0, #1                      // stdout
    adrp    x1, str_prompt
    add     x1, x1, :lo12:str_prompt
    mov     x2, #(str_prompt_len - 1)
    mov     x8, #SYS_write
    svc     #0

    // Read line from stdin
    mov     x0, #0                      // stdin
    adrp    x1, repl_line_buf
    add     x1, x1, :lo12:repl_line_buf
    mov     x2, #(REPL_LINE_SIZE - 1)
    mov     x8, #SYS_read
    svc     #0

    // Save return value
    mov     x20, x0

    // Check for EINTR (signal interrupted the read)
    cmn     x20, #EINTR
    b.ne    .Lrepl_not_eintr

    // EINTR: check if shutdown was requested
    bl      signal_shutdown_requested
    cbnz    x0, .Lrepl_shutdown
    // Not shutdown, retry read
    b       .Lrepl_loop

.Lrepl_not_eintr:
    mov     x0, x20
    cmp     x0, #0
    b.le    .Lrepl_eof                  // EOF or error

    // Null-terminate and strip newline
    adrp    x1, repl_line_buf
    add     x1, x1, :lo12:repl_line_buf
    add     x2, x1, x0
    sub     x2, x2, #1                  // Last char position
    ldrb    w3, [x2]
    cmp     w3, #10                     // newline?
    b.ne    .Lrepl_no_strip
    strb    wzr, [x2]                   // Replace with null
    b       .Lrepl_parse

.Lrepl_no_strip:
    strb    wzr, [x2, #1]               // Null terminate

.Lrepl_parse:
    // Skip leading whitespace
    adrp    x0, repl_line_buf
    add     x0, x0, :lo12:repl_line_buf
.Lrepl_skip_ws:
    ldrb    w1, [x0]
    cbz     w1, .Lrepl_loop             // Empty line
    cmp     w1, #' '
    b.ne    .Lrepl_dispatch
    add     x0, x0, #1
    b       .Lrepl_skip_ws

.Lrepl_dispatch:
    // x0 = pointer to command start

    // Check each command
    mov     x19, x0                     // Save command pointer

    // help
    adrp    x1, cmd_help
    add     x1, x1, :lo12:cmd_help
    bl      str_prefix_match
    cbnz    x0, .Lrepl_cmd_help

    // quit
    mov     x0, x19
    adrp    x1, cmd_quit
    add     x1, x1, :lo12:cmd_quit
    bl      str_prefix_match
    cbnz    x0, .Lrepl_cmd_quit

    // exit
    mov     x0, x19
    adrp    x1, cmd_exit
    add     x1, x1, :lo12:cmd_exit
    bl      str_prefix_match
    cbnz    x0, .Lrepl_cmd_quit

    // status
    mov     x0, x19
    adrp    x1, cmd_status
    add     x1, x1, :lo12:cmd_status
    bl      str_prefix_match
    cbnz    x0, .Lrepl_cmd_status

    // peers
    mov     x0, x19
    adrp    x1, cmd_peers
    add     x1, x1, :lo12:cmd_peers
    bl      str_prefix_match
    cbnz    x0, .Lrepl_cmd_peers

    // index
    mov     x0, x19
    adrp    x1, cmd_index
    add     x1, x1, :lo12:cmd_index
    bl      str_prefix_match
    cbnz    x0, .Lrepl_cmd_index

    // search
    mov     x0, x19
    adrp    x1, cmd_search
    add     x1, x1, :lo12:cmd_search
    bl      str_prefix_match
    cbnz    x0, .Lrepl_cmd_search

    // connect
    mov     x0, x19
    adrp    x1, cmd_connect
    add     x1, x1, :lo12:cmd_connect
    bl      str_prefix_match
    cbnz    x0, .Lrepl_cmd_connect

    // Unknown command
    adrp    x1, str_unknown
    add     x1, x1, :lo12:str_unknown
    bl      print_str
    b       .Lrepl_loop

.Lrepl_cmd_help:
    bl      repl_cmd_help
    b       .Lrepl_loop

.Lrepl_cmd_quit:
    bl      repl_cmd_quit
    b       .Lrepl_done

.Lrepl_cmd_status:
    bl      repl_cmd_status
    b       .Lrepl_loop

.Lrepl_cmd_peers:
    bl      repl_cmd_peers
    b       .Lrepl_loop

.Lrepl_cmd_index:
    mov     x0, x19
    bl      repl_cmd_index
    b       .Lrepl_loop

.Lrepl_cmd_search:
    mov     x0, x19
    bl      repl_cmd_search
    b       .Lrepl_loop

.Lrepl_cmd_connect:
    mov     x0, x19
    bl      repl_cmd_connect
    b       .Lrepl_loop

.Lrepl_shutdown:
    // Shutdown signal received - exit cleanly
    b       .Lrepl_done

.Lrepl_eof:
    // Print newline on EOF
    adrp    x1, str_newline
    add     x1, x1, :lo12:str_newline
    bl      print_str

.Lrepl_done:
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size repl_run, .-repl_run

// =============================================================================
// repl_cmd_help - Show help
// =============================================================================
.global repl_cmd_help
.type repl_cmd_help, %function
repl_cmd_help:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x0, #1
    adrp    x1, str_help
    add     x1, x1, :lo12:str_help
    mov     x2, #(str_help_len - 1)
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #16
    ret
.size repl_cmd_help, .-repl_cmd_help

// =============================================================================
// repl_cmd_quit - Exit REPL
// =============================================================================
.global repl_cmd_quit
.type repl_cmd_quit, %function
repl_cmd_quit:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, str_goodbye
    add     x1, x1, :lo12:str_goodbye
    bl      print_str

    ldp     x29, x30, [sp], #16
    ret
.size repl_cmd_quit, .-repl_cmd_quit

// =============================================================================
// repl_cmd_status - Show node status
// =============================================================================
.global repl_cmd_status
.type repl_cmd_status, %function
repl_cmd_status:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Header
    adrp    x1, str_status_hdr
    add     x1, x1, :lo12:str_status_hdr
    bl      print_str

    // Node ID
    adrp    x1, str_node_id
    add     x1, x1, :lo12:str_node_id
    bl      print_str
    bl      node_get_id
    bl      print_hex64
    adrp    x1, str_newline
    add     x1, x1, :lo12:str_newline
    bl      print_str

    // State
    adrp    x1, str_state
    add     x1, x1, :lo12:str_state
    bl      print_str
    bl      node_get_state

    cmp     w0, #NODE_STATE_INIT
    b.ne    1f
    adrp    x1, str_state_init
    add     x1, x1, :lo12:str_state_init
    b       2f
1:  cmp     w0, #NODE_STATE_SYNCING
    b.ne    1f
    adrp    x1, str_state_syncing
    add     x1, x1, :lo12:str_state_syncing
    b       2f
1:  cmp     w0, #NODE_STATE_READY
    b.ne    1f
    adrp    x1, str_state_ready
    add     x1, x1, :lo12:str_state_ready
    b       2f
1:  adrp    x1, str_state_shutdown
    add     x1, x1, :lo12:str_state_shutdown
2:  bl      print_str

    // Doc count
    adrp    x1, str_docs
    add     x1, x1, :lo12:str_docs
    bl      print_str
    bl      node_get_doc_count
    bl      print_dec64
    adrp    x1, str_newline
    add     x1, x1, :lo12:str_newline
    bl      print_str

    // Peer count
    adrp    x1, str_peers
    add     x1, x1, :lo12:str_peers
    bl      print_str
    bl      node_get_peer_count
    bl      print_dec64
    adrp    x1, str_newline
    add     x1, x1, :lo12:str_newline
    bl      print_str

    ldp     x29, x30, [sp], #16
    ret
.size repl_cmd_status, .-repl_cmd_status

// =============================================================================
// repl_cmd_peers - List connected peers
// =============================================================================
.global repl_cmd_peers
.type repl_cmd_peers, %function
repl_cmd_peers:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      node_get_peer_count
    cbz     w0, .Lpeers_none

    // In full implementation, would iterate peer list
    // For now, just show count
    adrp    x1, str_peers
    add     x1, x1, :lo12:str_peers
    bl      print_str
    bl      node_get_peer_count
    bl      print_dec64
    adrp    x1, str_newline
    add     x1, x1, :lo12:str_newline
    bl      print_str
    b       .Lpeers_done

.Lpeers_none:
    adrp    x1, str_no_peers
    add     x1, x1, :lo12:str_no_peers
    bl      print_str

.Lpeers_done:
    ldp     x29, x30, [sp], #16
    ret
.size repl_cmd_peers, .-repl_cmd_peers

// =============================================================================
// repl_cmd_index - Index a document
// =============================================================================
// Input:
//   x0 = full command line pointer
// =============================================================================
.global repl_cmd_index
.type repl_cmd_index, %function
repl_cmd_index:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    // Skip "index" and whitespace
    add     x0, x19, #5                 // Skip "index"
.Lindex_skip_ws:
    ldrb    w1, [x0]
    cbz     w1, .Lindex_usage           // No argument
    cmp     w1, #' '
    b.ne    .Lindex_have_arg
    add     x0, x0, #1
    b       .Lindex_skip_ws

.Lindex_have_arg:
    mov     x19, x0                     // Text to index

    // Calculate text length
    mov     x1, x0
.Lindex_len:
    ldrb    w2, [x1]
    cbz     w2, .Lindex_len_done
    add     x1, x1, #1
    b       .Lindex_len
.Lindex_len_done:
    sub     x2, x1, x19                 // Length

    cbz     x2, .Lindex_usage           // Empty text

    // Generate document ID (simple: timestamp-based)
    sub     sp, sp, #16
    mov     x0, #0                      // CLOCK_REALTIME
    mov     x1, sp
    mov     x8, #SYS_clock_gettime
    svc     #0

    ldr     x0, [sp]                    // seconds
    ldr     x1, [sp, #8]                // nanoseconds
    add     sp, sp, #16

    // doc_id = (seconds << 32) | (nanoseconds >> 8)
    lsl     x0, x0, #32
    lsr     x1, x1, #8
    orr     x0, x0, x1

    // Add counter to ensure uniqueness
    adrp    x3, doc_id_counter
    add     x3, x3, :lo12:doc_id_counter
    ldr     x4, [x3]
    add     x4, x4, #1
    str     x4, [x3]
    eor     x0, x0, x4

    // Store doc_id
    mov     x20, x0

    // Index the document
    mov     x1, x19                     // Content
    // x2 already has length
    bl      replica_index_doc

    // Print result
    adrp    x1, str_indexed
    add     x1, x1, :lo12:str_indexed
    bl      print_str
    mov     x0, x20
    bl      print_hex64
    adrp    x1, str_indexed_suffix
    add     x1, x1, :lo12:str_indexed_suffix
    bl      print_str

    b       .Lindex_done

.Lindex_usage:
    adrp    x1, str_index_usage
    add     x1, x1, :lo12:str_index_usage
    bl      print_str

.Lindex_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size repl_cmd_index, .-repl_cmd_index

// =============================================================================
// repl_cmd_search - Execute search
// =============================================================================
// Input:
//   x0 = full command line pointer
// =============================================================================
.global repl_cmd_search
.type repl_cmd_search, %function
repl_cmd_search:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    // Skip "search" and whitespace
    add     x0, x19, #6                 // Skip "search"
.Lsearch_skip_ws:
    ldrb    w1, [x0]
    cbz     w1, .Lsearch_usage
    cmp     w1, #' '
    b.ne    .Lsearch_have_arg
    add     x0, x0, #1
    b       .Lsearch_skip_ws

.Lsearch_have_arg:
    mov     x19, x0                     // Query string

    // Calculate query length
    mov     x1, x0
.Lsearch_len:
    ldrb    w2, [x1]
    cbz     w2, .Lsearch_len_done
    add     x1, x1, #1
    b       .Lsearch_len
.Lsearch_len_done:
    sub     x1, x1, x19                 // Length

    cbz     x1, .Lsearch_usage

    // Execute search
    mov     x0, x19                     // Query
    // x1 = length
    mov     x2, #10                     // Max results
    mov     x3, #SEARCH_FLAG_OR         // Default OR
    mov     x4, #0                      // No callback
    bl      router_search

    cmp     x0, #0
    b.lt    .Lsearch_error

    mov     x19, x0                     // Query ID

    // Print header
    adrp    x1, str_search_hdr
    add     x1, x1, :lo12:str_search_hdr
    bl      print_str
    mov     x0, x19
    bl      print_dec64
    adrp    x1, str_search_results
    add     x1, x1, :lo12:str_search_results
    bl      print_str

    // In full implementation, would wait for results
    // For now, just indicate no results (local only, no index)
    adrp    x1, str_no_results
    add     x1, x1, :lo12:str_no_results
    bl      print_str

    b       .Lsearch_done

.Lsearch_error:
.Lsearch_usage:
    adrp    x1, str_search_usage
    add     x1, x1, :lo12:str_search_usage
    bl      print_str

.Lsearch_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size repl_cmd_search, .-repl_cmd_search

// =============================================================================
// repl_cmd_connect - Connect to peer
// =============================================================================
// Input:
//   x0 = full command line pointer
// =============================================================================
.global repl_cmd_connect
.type repl_cmd_connect, %function
repl_cmd_connect:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Skip "connect" and get argument
    add     x0, x0, #7                  // Skip "connect"
.Lconnect_skip_ws:
    ldrb    w1, [x0]
    cbz     w1, .Lconnect_usage
    cmp     w1, #' '
    b.ne    .Lconnect_have_arg
    add     x0, x0, #1
    b       .Lconnect_skip_ws

.Lconnect_have_arg:
    // In full implementation, would parse IP:port and call tcp_connect
    // For now, just show usage
    adrp    x1, str_connect_usage
    add     x1, x1, :lo12:str_connect_usage
    bl      print_str
    b       .Lconnect_done

.Lconnect_usage:
    adrp    x1, str_connect_usage
    add     x1, x1, :lo12:str_connect_usage
    bl      print_str

.Lconnect_done:
    ldp     x29, x30, [sp], #16
    ret
.size repl_cmd_connect, .-repl_cmd_connect

// =============================================================================
// Helper: str_prefix_match - Check if string starts with prefix
// =============================================================================
// Input:
//   x0 = string pointer
//   x1 = prefix pointer
// Output:
//   x0 = 1 if match, 0 if no match
// =============================================================================
str_prefix_match:
.Lprefix_loop:
    ldrb    w2, [x1], #1                // Prefix char
    cbz     w2, .Lprefix_match          // End of prefix = match

    ldrb    w3, [x0], #1                // String char
    cmp     w2, w3
    b.ne    .Lprefix_nomatch

    b       .Lprefix_loop

.Lprefix_match:
    // Check that prefix ends at word boundary (space or end)
    ldrb    w2, [x0]
    cbz     w2, .Lprefix_yes            // End of string
    cmp     w2, #' '
    b.eq    .Lprefix_yes                // Space after

.Lprefix_nomatch:
    mov     x0, #0
    ret

.Lprefix_yes:
    mov     x0, #1
    ret

// =============================================================================
// Helper: print_str - Print null-terminated string
// =============================================================================
// Input:
//   x1 = string pointer
// =============================================================================
print_str:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x2, x1
.Lpstr_len:
    ldrb    w0, [x2]
    cbz     w0, .Lpstr_write
    add     x2, x2, #1
    b       .Lpstr_len

.Lpstr_write:
    sub     x2, x2, x1                  // Length
    mov     x0, #1                      // stdout
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Helper: print_hex64 - Print 64-bit value in hex
// =============================================================================
// Input:
//   x0 = value
// =============================================================================
print_hex64:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    mov     x1, x0
    adrp    x2, repl_output_buf
    add     x2, x2, :lo12:repl_output_buf
    mov     x3, #16                     // 16 hex digits

.Lhex_loop:
    cbz     x3, .Lhex_print

    // Extract high nibble
    lsr     x4, x1, #60
    and     x4, x4, #0xF

    // Convert to ASCII
    cmp     x4, #10
    b.lo    .Lhex_digit
    add     x4, x4, #('a' - 10)
    b       .Lhex_store
.Lhex_digit:
    add     x4, x4, #'0'
.Lhex_store:
    strb    w4, [x2], #1

    lsl     x1, x1, #4
    sub     x3, x3, #1
    b       .Lhex_loop

.Lhex_print:
    mov     x0, #1                      // stdout
    adrp    x1, repl_output_buf
    add     x1, x1, :lo12:repl_output_buf
    mov     x2, #16
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Helper: print_dec64 - Print 64-bit value in decimal
// =============================================================================
// Input:
//   x0 = value
// =============================================================================
print_dec64:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    mov     x1, x0
    adrp    x2, repl_output_buf
    add     x2, x2, :lo12:repl_output_buf
    add     x2, x2, #20                 // End of buffer
    mov     x3, #0                      // Digit count

    // Handle zero
    cbnz    x1, .Ldec_loop
    mov     w4, #'0'
    strb    w4, [x2, #-1]!
    mov     x3, #1
    b       .Ldec_print

.Ldec_loop:
    cbz     x1, .Ldec_print

    // Divide by 10
    mov     x4, #10
    udiv    x5, x1, x4
    msub    x4, x5, x4, x1              // Remainder

    // Convert to ASCII and store (backwards)
    add     x4, x4, #'0'
    strb    w4, [x2, #-1]!
    add     x3, x3, #1

    mov     x1, x5
    b       .Ldec_loop

.Ldec_print:
    mov     x0, #1                      // stdout
    mov     x1, x2                      // Start of digits
    mov     x2, x3                      // Length
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #32
    ret
