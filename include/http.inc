// =============================================================================
// Omesh - HTTP Protocol Constants
// =============================================================================
//
// Minimal HTTP/1.1 parsing support for the API server.
// Supports GET and POST methods with JSON bodies.
//
// =============================================================================

#ifndef HTTP_INC
#define HTTP_INC

// =============================================================================
// HTTP Methods
// =============================================================================

.equ HTTP_METHOD_UNKNOWN,   0
.equ HTTP_METHOD_GET,       1
.equ HTTP_METHOD_POST,      2
.equ HTTP_METHOD_PUT,       3
.equ HTTP_METHOD_DELETE,    4
.equ HTTP_METHOD_HEAD,      5
.equ HTTP_METHOD_OPTIONS,   6

// =============================================================================
// HTTP Status Codes
// =============================================================================

.equ HTTP_STATUS_OK,                    200
.equ HTTP_STATUS_CREATED,               201
.equ HTTP_STATUS_NO_CONTENT,            204
.equ HTTP_STATUS_BAD_REQUEST,           400
.equ HTTP_STATUS_NOT_FOUND,             404
.equ HTTP_STATUS_METHOD_NOT_ALLOWED,    405
.equ HTTP_STATUS_INTERNAL_ERROR,        500
.equ HTTP_STATUS_NOT_IMPLEMENTED,       501

// =============================================================================
// HTTP Version
// =============================================================================

.equ HTTP_VERSION_10,       10      // HTTP/1.0
.equ HTTP_VERSION_11,       11      // HTTP/1.1

// =============================================================================
// HTTP Request Structure (128 bytes)
// =============================================================================
//
// Parsed HTTP request data
//

.equ HTTP_REQ_OFF_METHOD,       0       // [4] HTTP method enum
.equ HTTP_REQ_OFF_VERSION,      4       // [4] HTTP version (10 or 11)
.equ HTTP_REQ_OFF_PATH_PTR,     8       // [8] Pointer to path string
.equ HTTP_REQ_OFF_PATH_LEN,     16      // [4] Path length
.equ HTTP_REQ_OFF_QUERY_PTR,    20      // [8] Pointer to query string (after ?)
.equ HTTP_REQ_OFF_QUERY_LEN,    28      // [4] Query string length
.equ HTTP_REQ_OFF_HOST_PTR,     32      // [8] Host header value
.equ HTTP_REQ_OFF_HOST_LEN,     40      // [4] Host header length
.equ HTTP_REQ_OFF_CONTENT_TYPE, 44      // [8] Content-Type header
.equ HTTP_REQ_OFF_CTYPE_LEN,    52      // [4] Content-Type length
.equ HTTP_REQ_OFF_CONTENT_LEN,  56      // [8] Content-Length value
.equ HTTP_REQ_OFF_BODY_PTR,     64      // [8] Pointer to body start
.equ HTTP_REQ_OFF_BODY_LEN,     72      // [8] Actual body length received
.equ HTTP_REQ_OFF_KEEPALIVE,    80      // [4] Connection: keep-alive flag
.equ HTTP_REQ_OFF_FLAGS,        84      // [4] Parsing flags
.equ HTTP_REQ_OFF_RAW_PTR,      88      // [8] Raw request buffer
.equ HTTP_REQ_OFF_RAW_LEN,      96      // [8] Raw request length
.equ HTTP_REQ_OFF_HEADER_END,   104     // [8] Offset where headers end
.equ HTTP_REQ_OFF_RESERVED,     112     // [16] Reserved
.equ HTTP_REQ_SIZE,             128

// Request flags
.equ HTTP_REQ_FLAG_COMPLETE,    0x01    // Full request received
.equ HTTP_REQ_FLAG_CHUNKED,     0x02    // Transfer-Encoding: chunked
.equ HTTP_REQ_FLAG_HAS_BODY,    0x04    // Request has body

// =============================================================================
// HTTP Response Structure (64 bytes)
// =============================================================================

.equ HTTP_RESP_OFF_STATUS,      0       // [4] Status code
.equ HTTP_RESP_OFF_VERSION,     4       // [4] HTTP version
.equ HTTP_RESP_OFF_BODY_PTR,    8       // [8] Response body pointer
.equ HTTP_RESP_OFF_BODY_LEN,    16      // [8] Response body length
.equ HTTP_RESP_OFF_CTYPE_PTR,   24      // [8] Content-Type string
.equ HTTP_RESP_OFF_CTYPE_LEN,   32      // [4] Content-Type length
.equ HTTP_RESP_OFF_FLAGS,       36      // [4] Response flags
.equ HTTP_RESP_OFF_RESERVED,    40      // [24] Reserved
.equ HTTP_RESP_SIZE,            64

// =============================================================================
// Header Parsing
// =============================================================================

// Known header indices (for fast comparison)
.equ HTTP_HDR_HOST,             0
.equ HTTP_HDR_CONTENT_LENGTH,   1
.equ HTTP_HDR_CONTENT_TYPE,     2
.equ HTTP_HDR_CONNECTION,       3
.equ HTTP_HDR_TRANSFER_ENC,     4
.equ HTTP_HDR_ACCEPT,           5
.equ HTTP_HDR_USER_AGENT,       6
.equ HTTP_HDR_UNKNOWN,          255

// =============================================================================
// Limits
// =============================================================================

.equ HTTP_MAX_PATH_LEN,         2048
.equ HTTP_MAX_HEADER_LEN,       8192
.equ HTTP_MAX_BODY_LEN,         (1 << 20)   // 1MB max body
.equ HTTP_MAX_HEADERS,          64

// =============================================================================
// Common Content Types
// =============================================================================

// Content type enum for fast comparison
.equ HTTP_CTYPE_UNKNOWN,        0
.equ HTTP_CTYPE_JSON,           1
.equ HTTP_CTYPE_TEXT_PLAIN,     2
.equ HTTP_CTYPE_TEXT_HTML,      3
.equ HTTP_CTYPE_FORM_URL,       4

// =============================================================================
// Parser State
// =============================================================================

.equ HTTP_PARSE_REQUEST_LINE,   0
.equ HTTP_PARSE_HEADERS,        1
.equ HTTP_PARSE_BODY,           2
.equ HTTP_PARSE_COMPLETE,       3
.equ HTTP_PARSE_ERROR,          -1

// =============================================================================
// Error Codes
// =============================================================================

.equ HTTP_ERR_NONE,             0
.equ HTTP_ERR_INCOMPLETE,       -1      // Need more data
.equ HTTP_ERR_BAD_METHOD,       -2
.equ HTTP_ERR_BAD_PATH,         -3
.equ HTTP_ERR_BAD_VERSION,      -4
.equ HTTP_ERR_BAD_HEADER,       -5
.equ HTTP_ERR_TOO_LARGE,        -6
.equ HTTP_ERR_INTERNAL,         -7

#endif // HTTP_INC
