; ============================================================
; Ultimate 64 / 1541-Ultimate II+ Command Interface SDK
; ============================================================
; IMPORTANT — this is UNTESTED. There is no way to verify it from
; here: VICE does not emulate the Ultimate Command Interface at all
; (it's proprietary FPGA hardware, not part of a stock C64), so
; nothing in this file has been run against the real thing, unlike
; everything else in this project. It's written directly from the
; official protocol docs and cross-checked byte-for-byte against a
; known working reference implementation, but please treat it as a
; first draft to test on real hardware, not verified-working code.
;
; Sources:
;   https://1541u-documentation.readthedocs.io/en/latest/uci/
;   https://github.com/xlar54/ultimateii-dos-lib (reference C impl,
;   used here to pin down exact wire framing the prose docs leave
;   ambiguous — e.g. which commands null-terminate their string
;   parameter and which don't; see note on ULT_HTTP_GET below)
;
; Include this file and JSR the ULT_* entry points. String/buffer
; parameters are passed via zero-page pointers you set before the
; call (documented per routine) rather than in registers, since
; several of them are filenames/hostnames of arbitrary length.
; ============================================================

; --- Command Interface registers ---
ULT_CTRL     = $df1c   ; write: control register
ULT_STATUS   = $df1c   ; read:  status register
ULT_CMDDATA  = $df1d   ; write: command data register
ULT_RESPDATA = $df1e   ; read only: response data register
ULT_STATDATA = $df1f   ; read only: status data register

; --- Control register bits (write to ULT_CTRL) ---
ULT_PUSH_CMD = $01
ULT_DATA_ACC = $02
ULT_ABORT    = $04
ULT_CLR_ERR  = $08

; --- Status register bits (read from ULT_STATUS) ---
ULT_ST_CMDBUSY    = $01
ULT_ST_DATAACC    = $02
ULT_ST_ERROR      = $04
ULT_ST_STATE_MASK = $30   ; 2-bit STATE field: 00=idle 01=busy 1x=data
ULT_ST_STATE_BUSY = $10
ULT_ST_STATAV     = $40   ; status-string byte available at ULT_STATDATA
ULT_ST_DATAAV     = $80   ; response-data byte available at ULT_RESPDATA

; --- Targets ---
ULT_TGT_DOS1 = $01
ULT_TGT_DOS2 = $02
ULT_TGT_NET  = $03
ULT_TGT_CTRL = $04

; --- DOS command bytes ---
ULT_DOS_OPEN_FILE  = $02
ULT_DOS_READ_DATA  = $04
ULT_DOS_CHANGE_DIR = $11
ULT_DOS_OPEN_DIR   = $13
ULT_DOS_READ_DIR   = $14
ULT_DOS_MOUNT_DISK = $23

; --- Network command bytes ---
ULT_NET_GET_IP     = $05
ULT_NET_TCP_CONNECT= $07
ULT_NET_SOCK_READ  = $10
ULT_NET_SOCK_WRITE = $11

; --- Zero page scratch (SDK-private: $10-$17) ---
; Pick a different range if you also use common.asm's menu system
; ($02-$08) in the same build — these two ranges don't overlap.
ult_ptr    = $10   ; 2 bytes: pointer to a null-terminated param string
ult_outptr = $12   ; 2 bytes: pointer to caller's output buffer
ult_reqlen = $14   ; 2 bytes: requested length (LSB first) for reads
ult_tmp    = $16   ; 1 byte scratch
ult_aborted = $17  ; 1 byte: set by ult_cmd_wait when RUN/STOP cancels a
                     ; command that never finished (see ult_cmd_wait) -
                     ; callers must check this after ult_cmd_push and
                     ; bail out instead of processing a response that
                     ; never arrived. Confirmed live on real hardware:
                     ; NET_CMD_SOCKET_READ (and likely TCP_CONNECT) can
                     ; block indefinitely waiting on the Ultimate's own
                     ; network I/O - exactly the risk this file's
                     ; ULT_HTTP_GET comment already flagged as unverified
                     ; before real hardware confirmed it.

; ============================================================
; Low-level primitives
; ============================================================

; Wait until the protocol is idle (both STATE bits clear).
; Trashes A.
ult_wait_idle
        lda     ULT_STATUS
        and     #ULT_ST_STATE_MASK
        bne     ult_wait_idle
        rts

; Begin a command: A = target, X = command byte.
; Waits for idle, then writes target+command. Follow with any
; combination of ult_cmd_byte / ult_cmd_str for parameters, then
; finish with ult_cmd_push.
ult_cmd_start
        pha
        jsr     ult_wait_idle
        pla
        sta     ULT_CMDDATA     ; target byte
        stx     ULT_CMDDATA     ; command byte
        rts

; Write one extra parameter byte: A = byte.
ult_cmd_byte
        sta     ULT_CMDDATA
        rts

; Write a null-terminated parameter string from (ult_ptr).
; The terminator itself is NOT sent (matches how the DOS and most
; network commands frame their string parameters — length-implicit,
; no trailing zero on the wire). ULT_HTTP_GET's connect step needs
; an explicit trailing zero instead; see the note there.
ult_cmd_str
        ldy     #$00
ult_cmd_str_loop
        lda     (ult_ptr),y
        beq     ult_cmd_str_done
        sta     ULT_CMDDATA
        iny
        bne     ult_cmd_str_loop
ult_cmd_str_done
        rts

; Push the assembled command and wait for it to finish.
ult_cmd_push
        lda     #$00
        sta     ult_aborted
        lda     ULT_CTRL
        ora     #ULT_PUSH_CMD
        sta     ULT_CTRL
        lda     ULT_STATUS
        and     #ULT_ST_ERROR
        beq     ult_cmd_wait
        lda     ULT_CTRL        ; command was rejected - clear the error
        ora     #ULT_CLR_ERR    ; flag. Caller should check status and
        sta     ULT_CTRL        ; may want to retry; we don't loop here
        rts                     ; to avoid an unbounded retry loop.
; Waits for BUSY to clear, but not unconditionally - also polls GETIN
; every pass so a stuck command (Ultimate itself blocked on a real
; network read that never gets a response) can still be cancelled by
; RUN/STOP instead of hanging the whole machine forever. Sets
; ult_aborted and issues ULT_ABORT (never used before this) rather than
; waiting for BUSY to clear on its own, since after RUN/STOP is pressed
; there's no reason to trust the operation will ever finish normally.
ult_cmd_wait
        jsr     $ffe4           ; GETIN - non-blocking, doesn't disturb
        beq     ucw_check       ; the Command Interface registers at all
        cmp     #$03            ; RUN/STOP
        bne     ucw_check
        lda     ULT_CTRL
        ora     #ULT_ABORT
        sta     ULT_CTRL
        lda     #$01
        sta     ult_aborted
        rts
ucw_check
        lda     ULT_STATUS
        and     #ULT_ST_STATE_MASK
        cmp     #ULT_ST_STATE_BUSY
        beq     ult_cmd_wait
        rts

; Read all currently available response data into (ult_outptr).
; Null-terminates the buffer and returns the LAST PAGE's byte count in Y
; (and ult_tmp) - not a full 16-bit total, since no current caller needs
; one (every caller either reads a single fixed-size record right after
; the call, before ult_outptr could matter again, or scans the buffer
; for the null terminator instead of trusting a length). Make sure the
; buffer has room - this doesn't bound the length itself, the DATA_AV
; status flag does, and the docs describe transport chunks up to 512
; bytes (see ULT_READ_FILE's own comment).
;
; Y is only 8 bits, so "iny / bne loop" alone silently wraps every 256
; bytes - not a truncation, active corruption: once Y wraps to 0, the
; loop would exit (bne fails) even with more DATAAV data still waiting,
; and the null-terminator write right after would then land at offset 0,
; overwriting the response's own first byte instead of its last one.
; Found by reading, not live hardware (VICE can't reach this code at
; all) - HTTPGET's own SOCK_READ already requests up to 512 bytes per
; call, well past where this would have bitten. Fixed the standard 6502
; way: advance ult_outptr's own high byte on each page crossing so
; (ult_outptr),y keeps landing on fresh memory instead of wrapping back
; over what's already been written. That mutates ult_outptr, which every
; existing caller assumes survives a call unchanged (e.g. ULT_HTTP_GET
; re-reads (ult_outptr),y right after its own first ult_read_data call) -
; saved/restored via the stack rather than auditing every call site.
ult_read_data
        lda     ult_outptr
        pha
        lda     ult_outptr+1
        pha
        ldy     #$00
ult_read_data_loop
        lda     ULT_STATUS
        and     #ULT_ST_DATAAV
        beq     ult_read_data_done
        lda     ULT_RESPDATA
        sta     (ult_outptr),y
        iny
        bne     ult_read_data_loop
        inc     ult_outptr+1
        jmp     ult_read_data_loop
ult_read_data_done
        lda     #$00
        sta     (ult_outptr),y
        sty     ult_tmp
        pla
        sta     ult_outptr+1
        pla
        sta     ult_outptr
        rts

; Read the status string (e.g. "00,OK") into (ult_outptr).
; Null-terminates it. Byte count (last page only) in Y / ult_tmp - same
; page-crossing fix as ult_read_data above, for the same reason (status
; strings are normally short, but nothing stops a future one from
; growing past 256 bytes, and the corruption-on-wrap failure mode is bad
; enough - real data loss, not just a truncated print - to guard against
; unconditionally rather than only where it's known to bite today).
ult_read_status
        lda     ult_outptr
        pha
        lda     ult_outptr+1
        pha
        ldy     #$00
ult_read_status_loop
        lda     ULT_STATUS
        and     #ULT_ST_STATAV
        beq     ult_read_status_done
        lda     ULT_STATDATA
        sta     (ult_outptr),y
        iny
        bne     ult_read_status_loop
        inc     ult_outptr+1
        jmp     ult_read_status_loop
ult_read_status_done
        lda     #$00
        sta     (ult_outptr),y
        sty     ult_tmp
        pla
        sta     ult_outptr+1
        pla
        sta     ult_outptr
        rts

; Acknowledge a completed exchange (call after reading data/status).
ult_accept
        lda     ULT_CTRL
        ora     #ULT_DATA_ACC
        sta     ULT_CTRL
ult_accept_wait
        lda     ULT_STATUS
        and     #ULT_ST_DATAACC
        bne     ult_accept_wait
        rts

; ============================================================
; High-level API
; ============================================================

; --- ULT_MOUNT_D64 ---
; Mount a disk image. Caller sets: A = drive ID (e.g. 8),
; ult_ptr = pointer to null-terminated image path/filename.
; Result status string ("00,OK" etc) ends up in ult_outptr after
; you call ult_read_status + ult_accept yourself.
ULT_MOUNT_D64
        pha
        lda     #ULT_TGT_DOS1
        ldx     #ULT_DOS_MOUNT_DISK
        jsr     ult_cmd_start
        pla
        jsr     ult_cmd_byte    ; drive id
        jsr     ult_cmd_str     ; image filename
        jmp     ult_cmd_push

; --- ULT_OPEN_USB ---
; There is no dedicated "open USB" command in the protocol — USB
; storage is just another path (typically "usb0:") in the same
; unified DOS filesystem as the SD card, so this maps to
; DOS_CMD_CHANGE_DIR. Caller sets ult_ptr to the target path first.
ULT_OPEN_USB
        lda     #ULT_TGT_DOS1
        ldx     #ULT_DOS_CHANGE_DIR
        jsr     ult_cmd_start
        jsr     ult_cmd_str
        jmp     ult_cmd_push

; --- ULT_LIST_DIRECTORY ---
; Opens the current directory and pulls whatever entries are
; immediately available into (ult_outptr), as repeated
; [attribute-byte][name...]0 records. Caller sets ult_outptr first.
; This is a single bulk read, not a full paginated loop — large
; directories may need more than one ULT_DOS_READ_DIR round trip,
; which isn't implemented here yet.
ULT_LIST_DIRECTORY
        lda     #ULT_TGT_DOS1
        ldx     #ULT_DOS_OPEN_DIR
        jsr     ult_cmd_start
        jsr     ult_cmd_push
        jsr     ult_read_status
        jsr     ult_accept

        lda     #ULT_TGT_DOS1
        ldx     #ULT_DOS_READ_DIR
        jsr     ult_cmd_start
        jsr     ult_cmd_push
        jmp     ult_read_data

; --- ULT_READ_FILE ---
; Caller sets: ult_ptr = filename, ult_outptr = buffer,
; ult_reqlen = requested byte count (LSB first, max 65535, though
; the transport itself moves data in <=512-byte chunks per the
; docs — for anything large you'll want to call this in a loop).
; Opens the file read-only, requests the data, and reads whatever
; comes back into ult_outptr.
ULT_READ_FILE
        lda     #ULT_TGT_DOS1
        ldx     #ULT_DOS_OPEN_FILE
        jsr     ult_cmd_start
        lda     #$01            ; attrib: read mode
        jsr     ult_cmd_byte
        jsr     ult_cmd_str
        jsr     ult_cmd_push
        jsr     ult_read_status
        jsr     ult_accept

        lda     #ULT_TGT_DOS1
        ldx     #ULT_DOS_READ_DATA
        jsr     ult_cmd_start
        lda     ult_reqlen
        jsr     ult_cmd_byte
        lda     ult_reqlen+1
        jsr     ult_cmd_byte
        jsr     ult_cmd_push
        jmp     ult_read_data

; --- ULT_GET_IP ---
; Caller sets ult_outptr to a buffer of at least 12 bytes.
; Result: 4 bytes IP, 4 bytes netmask, 4 bytes gateway.
ULT_GET_IP
        lda     #ULT_TGT_NET
        ldx     #ULT_NET_GET_IP
        jsr     ult_cmd_start
        lda     #$00            ; interface 0
        jsr     ult_cmd_byte
        jsr     ult_cmd_push
        jmp     ult_read_data

; --- ULT_SEND_ETHERNET ---
; There's no raw-Ethernet-frame command either — the Ultimate's
; network target operates at the TCP/UDP socket level, so this maps
; to NET_CMD_SOCKET_WRITE on an already-open socket (see
; ULT_HTTP_GET for how a socket gets opened).
; Caller sets: A = socket handle, ult_ptr = null-terminated data.
; Result (2 bytes: bytes actually sent, LSB first) goes to
; ult_outptr after you call ult_read_data yourself.
ULT_SEND_ETHERNET
        pha
        lda     #ULT_TGT_NET
        ldx     #ULT_NET_SOCK_WRITE
        jsr     ult_cmd_start
        pla
        jsr     ult_cmd_byte    ; socket handle
        jsr     ult_cmd_str     ; data
        jmp     ult_cmd_push

; --- ULT_HTTP_GET ---
; The protocol has a separate, more full-featured HTTP target
; (handle-based: create a request header, exchange it, then query
; the response header/body by handle) that I could only find
; second-hand prose documentation for for, not a verified reference
; implementation — so rather than guess at that framing, this
; builds the GET request by hand over a raw TCP socket instead,
; which is the same technique the reference DOS/network library
; uses for everything else and that I've verified byte-for-byte.
;
; Caller sets: ult_ptr = null-terminated hostname (e.g. "example.com"),
; ult_outptr = response buffer. Uses port 80 always. This issues the
; request and one read — for anything beyond a small response you'll
; need to call ult_read_data again (the socket stays open).
;
; NOTE: unlike the DOS commands, TCP_SOCKET_CONNECT's hostname
; parameter IS null-terminated on the wire (confirmed from the
; reference implementation) — that's why this doesn't just use
; ult_cmd_str alone for the hostname.
ULT_HTTP_GET
        lda     #ULT_TGT_NET
        ldx     #ULT_NET_TCP_CONNECT
        jsr     ult_cmd_start
        lda     #<80            ; port 80, LSB first
        jsr     ult_cmd_byte
        lda     #>80
        jsr     ult_cmd_byte
        jsr     ult_cmd_str     ; hostname
        lda     #$00            ; explicit terminator - see note above
        jsr     ult_cmd_byte
        jsr     ult_cmd_push
        jsr     ult_read_data   ; response data = 1-byte socket handle
        ldy     #$00
        lda     (ult_outptr),y
        sta     ult_tmp         ; stash the socket handle
        jsr     ult_read_status
        jsr     ult_accept

        lda     #ULT_TGT_NET
        ldx     #ULT_NET_SOCK_WRITE
        jsr     ult_cmd_start
        lda     ult_tmp
        jsr     ult_cmd_byte    ; socket handle
        lda     #<http_get_req
        sta     ult_ptr
        lda     #>http_get_req
        sta     ult_ptr+1
        jsr     ult_cmd_str     ; "GET / HTTP/1.0\r\n\r\n"
        jsr     ult_cmd_push
        jsr     ult_read_data
        jsr     ult_accept

        lda     #ULT_TGT_NET
        ldx     #ULT_NET_SOCK_READ
        jsr     ult_cmd_start
        lda     ult_tmp
        jsr     ult_cmd_byte    ; socket handle
        lda     #<512
        jsr     ult_cmd_byte    ; requested length, LSB first
        lda     #>512
        jsr     ult_cmd_byte
        jsr     ult_cmd_push
        jmp     ult_read_data   ; response into ult_outptr

; Minimal fixed request line — good enough to fetch "/" from a
; plain HTTP server. Swap this for a real path/Host: header as
; needed; it's plain text so easy to edit.
http_get_req
        !text "GET / HTTP/1.0"
        !byte $0d,$0a,$0d,$0a,$00
