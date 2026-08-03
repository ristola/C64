; ============================================================
; Ultimate Command Interface SDK - VICE STUB
; ============================================================
; Fake stand-in for ultimate_sdk.asm's low-level primitives, built
; only into the VICE-STUB variant (see build_cart.sh --vice-stub and
; bank11_content.asm's !ifdef VICE_STUB). $DF1C-$DF1F is proprietary
; Ultimate 64/1541-Ultimate II+ FPGA hardware - VICE has no emulation
; of it at all, so nothing that actually touches those registers can
; ever run here. Every primitive below fakes a plausible response
; instead of touching hardware, so HttpGetCmd/TelnetCmd's OWN logic
; (quote/comma parsing, request-building via hg_append, error paths)
; still runs for real and gets exercised in VICE - that's where the
; real stack-corruption bug actually turned up before, not in the
; wire protocol. The real ultimate_sdk.asm still needs its own final
; check on actual Ultimate hardware; this only proves the BASIC-
; facing half.
;
; Label-for-label match with ultimate_sdk.asm's low-level primitives
; and equates used by bank11_content.asm, so that file's code doesn't
; know or care which variant it's linked against. Only the primitives
; bank11_content.asm actually calls directly are implemented -
; ultimate_sdk.asm's higher-level ULT_* wrappers (ULT_HTTP_GET,
; ULT_MOUNT_D64, etc.) aren't used from there, so they're not stubbed.
; ============================================================

; --- Targets/command bytes (same values as ultimate_sdk.asm - only
; the NET ones are actually referenced from bank11_content.asm, the
; rest exist purely so this file's equate set matches the real one) ---
ULT_TGT_DOS1 = $01
ULT_TGT_DOS2 = $02
ULT_TGT_NET  = $03
ULT_TGT_CTRL = $04

ULT_DOS_OPEN_FILE  = $02
ULT_DOS_READ_DATA  = $04
ULT_DOS_CHANGE_DIR = $11
ULT_DOS_OPEN_DIR   = $13
ULT_DOS_READ_DIR   = $14
ULT_DOS_MOUNT_DISK = $23

ULT_NET_GET_IP      = $05
ULT_NET_TCP_CONNECT = $07
ULT_NET_SOCK_READ   = $10
ULT_NET_SOCK_WRITE  = $11

; --- Zero page scratch (same range as the real SDK) ---
ult_ptr    = $10
ult_outptr = $12
ult_reqlen = $14
ult_tmp    = $16
ult_aborted = $17  ; always 0 here - the stub never blocks, so there's
                     ; nothing to abort (see the real ultimate_sdk.asm's
                     ; equate for why real hardware needs this)

; Always idle - there's no real busy hardware state to wait on.
ult_wait_idle
        rts

; Remembers the command byte (X) so ult_read_data knows which canned
; response to hand back. A fresh TCP_CONNECT also resets the "already
; sent the canned SOCK_READ response" flag - the natural point
; representing a new connection.
ult_cmd_start
        stx     net_stub_last_cmd
        cpx     #ULT_NET_TCP_CONNECT
        bne     ucs_done
        lda     #$00
        sta     net_stub_read_done
ucs_done
        rts

; Parameters are ignored entirely - the stub doesn't need the real
; host/port/data to fake a response.
ult_cmd_byte
        rts
ult_cmd_str
        rts
ult_cmd_push
        lda     #$00
        sta     ult_aborted
        rts

; Canned response, chosen by whichever command ult_cmd_start last saw:
;   TCP_CONNECT -> a fake 1-byte socket handle ($01)
;   SOCK_READ   -> a fixed fake HTTP response, once per "connection"
;                  (further polls - e.g. TELNET's loop - get an empty
;                  read after that, matching "nothing waiting" instead
;                  of firehosing the same text forever)
;   anything else (SOCK_WRITE etc.) -> empty; callers don't use this
;                  routine's result after a write
ult_read_data
        lda     net_stub_last_cmd
        cmp     #ULT_NET_TCP_CONNECT
        beq     urd_connect
        cmp     #ULT_NET_SOCK_READ
        beq     urd_check_read
        jmp     urd_empty
; Copies a FIXED byte count (STUB_TOTAL_LEN, header + body), not a
; null-terminator scan - real NET_CMD_READ_SOCKET responses are framed
; by an explicit 2-byte length header (confirmed against the official
; UCI Network Target protocol doc), not a null terminator, and the
; body itself isn't guaranteed null-free. Scanning for a zero byte
; here would also break on the header's own high byte, which is $00
; for any body under 256 bytes long - exactly the real bug this stub
; needs to keep reproducing so bank11_content.asm's print loops (which
; skip the first 2 bytes as the length header) get tested against the
; same framing real hardware actually uses.
urd_check_read
        lda     net_stub_read_done
        bne     urd_empty
        lda     #$01
        sta     net_stub_read_done
        ldy     #$00
urd_copy
        cpy     #STUB_TOTAL_LEN
        beq     urd_copy_done
        lda     stub_http_response,y
        sta     (ult_outptr),y
        iny
        bne     urd_copy
urd_copy_done
        lda     #$00
        sta     (ult_outptr),y
        sty     ult_tmp
        rts
urd_connect
        ldy     #$00
        lda     #$01            ; fake socket handle
        sta     (ult_outptr),y
        iny
        lda     #$00
        sta     (ult_outptr),y
        sty     ult_tmp
        rts
urd_empty
        ldy     #$00
        lda     #$00
        sta     (ult_outptr),y
        sty     ult_tmp
        rts

; Fake "00,OK" - real callers (net_tcp_connect) read this and discard
; it without checking, so an empty string is just as good; kept as a
; separate routine for the label-for-label match.
ult_read_status
        ldy     #$00
        lda     #$00
        sta     (ult_outptr),y
        sty     ult_tmp
        rts

; No real DATA_ACC handshake to wait on.
ult_accept
        rts

; 2-byte length header (LSB first) ahead of the body, matching real
; NET_CMD_READ_SOCKET framing - STUB_TOTAL_LEN covers the header
; itself too, computed from the label span so it can't drift out of
; sync with the text below.
stub_http_response
        !byte   <(stub_http_body_end-stub_http_body), >(stub_http_body_end-stub_http_body)
stub_http_body
        !text   "HTTP/1.0 200 OK"
        !byte   13,10,13,10
        !text   "HELLO FROM THE VICE STUB - NOT A REAL SERVER"
        !byte   13,10
stub_http_body_end
STUB_TOTAL_LEN = stub_http_body_end - stub_http_response
