; Bank 11 content: NETWORK category (HTTPGET/TELNET), built on the
; Ultimate Command Interface SDK (ultimate_sdk.asm). UNTESTED against
; real hardware - see that file's own header: VICE doesn't emulate the
; Command Interface at all, so nothing here has actually run. Written
; directly from the same protocol docs/reference implementation the SDK
; itself cites, and using only primitives that file already implements
; (TCP_CONNECT/SOCK_WRITE/SOCK_READ), not new unverified command bytes.
;
; Both commands share DISK's (bank 10) RAM scratch buffers rather than
; claiming new ones - filename_buf for the target host, filename2_buf
; for HTTPGET's path, dir_buffer for message-building/response text.
; Safe because BASIC is single-threaded: DISK and NETWORK commands
; never run at the same moment. Same reuse pattern bank10_content.asm's
; own send_command already uses for dir_buffer.
;
; NOTE: bank10_content.asm's parse_filename/parse_filename2 are real
; BANK-10 CODE, not resident (shared) routines - every bank is a
; separate assembly (see bank_driver.asm's -DBANKNUM), so those labels
; simply don't exist here, the same reason menu_open needs bank_call to
; be reached from anywhere outside bank 0. Rather than a cross-bank
; call for something this small, net_parse_str below is a local copy of
; the same quoted-string-literal logic, parameterized by target buffer.

; --- BASIC ROM entry points (real, fixed KERNAL/BASIC ROM addresses -
; not part of the switched cartridge ROM, so any bank can reference them
; directly; redeclared here since each bank's content is a separate
; assembly with no shared constants file - same as bank10_content.asm's
; own copy of these same two lines) ---
BAS_FRMNUM  = $ad8a      ; evaluate + require a numeric expression
BAS_GETADR  = $b7f7      ; convert FAC1 to a 16-bit int in $14/$15
CHR_QUOTE   = $22

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_HTTPGET-*, $ff
        jmp     HttpGetCmd
!fill SLOT_TELNET-*, $ff
        jmp     TelnetCmd

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill $8100-*, $ff

*=$8100

; ultimate_sdk.asm's own equates (register/command-byte constants) cost
; no address space, but its actual code does - has to come after the
; fixed slot table above like everything else in this file, not before
; it (an earlier version of this file sourced it first and the SDK's
; real routines collided with - overran past - the slot table's fixed
; low addresses).
;
; VICE_STUB (build_cart.sh --vice-stub) swaps in ultimate_sdk_stub.asm
; instead - same low-level primitive names, fake responses instead of
; touching $DF1C-$DF1F, which VICE doesn't emulate at all. Everything
; below this point (HttpGetCmd/TelnetCmd/net_parse_str/etc.) is
; unchanged either way - it only calls the primitives, never knows
; which variant it's linked against.
!ifdef VICE_STUB {
        !source "ultimate_sdk_stub.asm"
} else {
        !source "ultimate_sdk.asm"
}

; --- HTTPGET "host",port,"path" ---
; Opens a raw TCP socket via ULT_NET_TCP_CONNECT, hand-builds a minimal
; "GET <path> HTTP/1.0\r\nHost: <host>\r\n\r\n" request (same technique
; ultimate_sdk.asm's own ULT_HTTP_GET already uses, just parameterized
; instead of hardcoded to port 80 and "/"), sends it, and prints
; whatever comes back from one SOCK_READ round straight to the screen.
; Large response bodies would need repeated SOCK_READ calls - not done
; here, matching ULT_HTTP_GET's own documented scope.
HttpGetCmd
        lda     #<filename_buf
        sta     ult_outptr
        lda     #>filename_buf
        sta     ult_outptr+1
        jsr     net_parse_str         ; host -> filename_buf, Y=length
        lda     #$00
        sta     filename_buf,y        ; null-terminate for ult_cmd_str

        jsr     BAS_CHRGOT
        cmp     #','
        beq     +                     ; net_missing_comma is too far for
        jmp     net_missing_comma     ; a direct BNE from here
+       jsr     BAS_CHRGET            ; consume comma

        lda     #$00
        sta     $0d                   ; BAS_VALTYP, used as a literal not
        jsr     BAS_FRMNUM            ; the resident.asm forward reference
        jsr     BAS_GETADR            ; (see BankCmd in bank6_content.asm
        lda     $14                   ; for why) - $14/$15 = port, lo/hi
        sta     net_port
        lda     $15
        sta     net_port+1

        jsr     BAS_CHRGOT
        cmp     #','
        beq     +                     ; net_missing_comma is too far for
        jmp     net_missing_comma     ; a direct BNE from here
+       jsr     BAS_CHRGET            ; consume comma

        lda     #<filename2_buf
        sta     ult_outptr
        lda     #>filename2_buf
        sta     ult_outptr+1
        jsr     net_parse_str         ; path -> filename2_buf, Y=length
        lda     #$00
        sta     filename2_buf,y

        jsr     net_tcp_connect       ; -> ult_tmp = socket handle

        ; Build the request line-by-piece into dir_buffer via hg_append
        ldx     #$00
        lda     #<httpget_verb
        sta     ult_ptr
        lda     #>httpget_verb
        sta     ult_ptr+1
        jsr     hg_append             ; "GET "

        lda     #<filename2_buf
        sta     ult_ptr
        lda     #>filename2_buf
        sta     ult_ptr+1
        jsr     hg_append             ; path

        lda     #<httpget_ver
        sta     ult_ptr
        lda     #>httpget_ver
        sta     ult_ptr+1
        jsr     hg_append             ; " HTTP/1.0\r\nHost: "

        lda     #<filename_buf
        sta     ult_ptr
        lda     #>filename_buf
        sta     ult_ptr+1
        jsr     hg_append             ; host

        lda     #<httpget_end
        sta     ult_ptr
        lda     #>httpget_end
        sta     ult_ptr+1
        jsr     hg_append             ; "\r\n\r\n"

        lda     #ULT_TGT_NET
        ldx     #ULT_NET_SOCK_WRITE
        jsr     ult_cmd_start
        lda     ult_tmp               ; socket handle
        jsr     ult_cmd_byte
        lda     #<dir_buffer
        sta     ult_ptr
        lda     #>dir_buffer
        sta     ult_ptr+1
        jsr     ult_cmd_str           ; the request just built
        jsr     ult_cmd_push
        lda     ult_aborted           ; RUN/STOP cancelled a stuck SOCK_
        beq     +                     ; WRITE - see ult_cmd_wait.
        jmp     net_timeout           ; net_timeout is too far for a
+                                       ; direct BNE from here.
        jsr     ult_read_data
        jsr     ult_accept

        lda     #ULT_TGT_NET
        ldx     #ULT_NET_SOCK_READ
        jsr     ult_cmd_start
        lda     ult_tmp               ; socket handle
        jsr     ult_cmd_byte
        lda     #<512
        jsr     ult_cmd_byte          ; requested length, lo/hi
        lda     #>512
        jsr     ult_cmd_byte
        jsr     ult_cmd_push
        lda     ult_aborted           ; RUN/STOP cancelled a stuck SOCK_
        beq     +                     ; READ - the request never got a
        jmp     net_timeout           ; response, nothing to print.
                                        ; net_timeout is too far for a
                                        ; direct BNE from here.
+       lda     #<dir_buffer
        sta     ult_outptr
        lda     #>dir_buffer
        sta     ult_outptr+1
        jsr     ult_read_data
        jsr     ult_accept

        ; NET_CMD_READ_SOCKET's response starts with a 2-byte length
        ; header (LSB first) BEFORE the actual data (confirmed against
        ; the official UCI Network Target protocol doc) - dir_buffer+0/
        ; +1 are that header, not response text. Skipping straight to
        ; +2 is what was missing before: for any response under 256
        ; bytes the header's high byte is $00, which this print loop's
        ; own null-terminator check would hit immediately at index 1,
        ; printing at most one garbage byte and stopping - exactly what
        ; "HTTPGET printed nothing" on real hardware looked like.
        ldx     #$02
hg_print_loop
        lda     dir_buffer,x
        beq     hg_print_done
        jsr     $ffd2
        inx
        bne     hg_print_loop
hg_print_done
        jmp     bank_return_basic

; Appends the null-terminated string at (ult_ptr) into dir_buffer,X,
; advancing X past it. Trashes A/Y.
hg_append
        ldy     #$00
hg_append_loop
        lda     (ult_ptr),y
        beq     hg_append_done
        sta     dir_buffer,x
        inx
        iny
        jmp     hg_append_loop
hg_append_done
        rts

; --- TELNET "host",port ---
; Opens a raw TCP socket and drops into an interactive loop: typed
; characters go out over the socket one at a time, anything the socket
; has waiting gets printed. RUN/STOP exits back to BASIC (same GETIN/
; compare-to-$03 convention menu_open already uses - see common.asm).
; UNVERIFIED assumption carried over from ultimate_sdk.asm's own
; caveats: whether NET_CMD_SOCKET_READ returns immediately with zero
; bytes when nothing's waiting, or blocks, isn't confirmed - if it
; blocks, this loop would stop sending keystrokes out promptly. Written
; the way the docs/reference implementation read, not guessed further.
TelnetCmd
        lda     #<filename_buf
        sta     ult_outptr
        lda     #>filename_buf
        sta     ult_outptr+1
        jsr     net_parse_str         ; host -> filename_buf, Y=length
        lda     #$00
        sta     filename_buf,y

        jsr     BAS_CHRGOT
        cmp     #','
        beq     +                     ; net_missing_comma is too far for
        jmp     net_missing_comma     ; a direct BNE from here
+       jsr     BAS_CHRGET            ; consume comma

        lda     #$00
        sta     $0d                   ; BAS_VALTYP, literal - see above
        jsr     BAS_FRMNUM
        jsr     BAS_GETADR
        lda     $14
        sta     net_port
        lda     $15
        sta     net_port+1

        jsr     net_tcp_connect       ; -> ult_tmp = socket handle
        lda     ult_tmp
        sta     telnet_sock

        cli                           ; OkExt's SEI (resident.asm) holds
                                        ; interrupts off for the whole bank
                                        ; visit - correct for a quick,
                                        ; atomic command like HTTPGET, but
                                        ; fatal for TELNET's own interactive
                                        ; loop below: with interrupts off,
                                        ; the jiffy IRQ's keyboard scan never
                                        ; runs again, so nothing ever lands
                                        ; in the keyboard buffer for GETIN to
                                        ; see - RUN/STOP (or any key) simply
                                        ; can't register, no matter how long
                                        ; you wait. Confirmed live: TELNET
                                        ; never returned to READY. Same fix
                                        ; menu_open already needed for the
                                        ; same reason (see its own comment) -
                                        ; safe to re-enable here since bank
                                        ; 11 is already fully switched in and
                                        ; stable, and irq_hook's own bank_
                                        ; call/bank_return save/restore
                                        ; whatever bank was active regardless
                                        ; of which one that is, the same way
                                        ; it already does for menu_open
                                        ; resting on bank 0.
        ldx     #$00
tn_hdr_loop
        lda     telnet_hdr,x
        beq     tn_loop
        jsr     $ffd2
        inx
        bne     tn_hdr_loop

tn_loop
        jsr     $ffe4                 ; GETIN - non-blocking key read
        beq     tn_check_sock
        cmp     #$03                  ; RUN/STOP
        beq     tn_done
        sta     dir_buffer            ; one-char "string" to send
        lda     #$00
        sta     dir_buffer+1
        lda     #ULT_TGT_NET
        ldx     #ULT_NET_SOCK_WRITE
        jsr     ult_cmd_start
        lda     telnet_sock
        jsr     ult_cmd_byte
        lda     #<dir_buffer
        sta     ult_ptr
        lda     #>dir_buffer
        sta     ult_ptr+1
        jsr     ult_cmd_str
        jsr     ult_cmd_push
        lda     ult_aborted           ; RUN/STOP already got caught by
        bne     tn_done               ; ult_cmd_wait's own GETIN check
                                        ; while this SOCK_WRITE was stuck
                                        ; (see ult_cmd_wait) - same clean
                                        ; exit as tn_loop's own GETIN
                                        ; check just below, not an error
        jsr     ult_read_data
        jsr     ult_accept

tn_check_sock
        lda     #ULT_TGT_NET
        ldx     #ULT_NET_SOCK_READ
        jsr     ult_cmd_start
        lda     telnet_sock
        jsr     ult_cmd_byte
        lda     #<256
        jsr     ult_cmd_byte
        lda     #>256
        jsr     ult_cmd_byte
        jsr     ult_cmd_push
        lda     ult_aborted           ; same as above - a stuck SOCK_READ
        bne     tn_done               ; is exactly the "blocks forever"
                                        ; case this loop's own header
                                        ; comment already flagged
        lda     #<dir_buffer
        sta     ult_outptr
        lda     #>dir_buffer
        sta     ult_outptr+1
        jsr     ult_read_data
        jsr     ult_accept
        ; NET_CMD_READ_SOCKET's response starts with a 2-byte length
        ; header (LSB first), not response text - see HttpGetCmd's own
        ; copy of this same fix for the full explanation.
        ldx     #$02
tn_print_loop
        lda     dir_buffer,x
        beq     tn_print_done
        jsr     $ffd2
        inx
        bne     tn_print_loop
tn_print_done
        jmp     tn_loop

tn_done
        jmp     bank_return_basic

telnet_hdr
        !byte   13
        !text   "[CONNECTED - RUN/STOP TO EXIT]"
        !byte   13,0

; --- Shared: open a TCP connection to filename_buf:net_port.
; Result: ult_tmp = 1-byte socket handle. ---
net_tcp_connect
        lda     #ULT_TGT_NET
        ldx     #ULT_NET_TCP_CONNECT
        jsr     ult_cmd_start
        lda     net_port
        jsr     ult_cmd_byte
        lda     net_port+1
        jsr     ult_cmd_byte
        lda     #<filename_buf
        sta     ult_ptr
        lda     #>filename_buf
        sta     ult_ptr+1
        jsr     ult_cmd_str           ; hostname
        lda     #$00                  ; explicit trailing zero - TCP_
        jsr     ult_cmd_byte          ; CONNECT's hostname IS null-
        jsr     ult_cmd_push          ; terminated on the wire, unlike
                                        ; most other string params (see
                                        ; ULT_HTTP_GET's own note)
        lda     ult_aborted           ; RUN/STOP cancelled a stuck
        beq     +                     ; TCP_CONNECT - shared by HTTPGET
        jmp     net_timeout           ; and TELNET, so a plain message +
                                        ; return to READY covers both.
                                        ; net_timeout is too far for a
                                        ; direct BNE from here.
+       lda     #<dir_buffer
        sta     ult_outptr
        lda     #>dir_buffer
        sta     ult_outptr+1
        jsr     ult_read_data          ; response = 1-byte socket handle
        lda     dir_buffer
        sta     ult_tmp
        jsr     ult_read_status
        jmp     ult_accept

; Parses a double-quoted string literal starting at the current BASIC
; text position into (ult_outptr), up to FILENAME_MAXLEN chars, leaving
; BAS_TXTPTR positioned just after the closing quote. Local copy of
; bank10_content.asm's parse_filename logic - see this file's header
; note on why it can't just call that one directly. On a missing
; opening quote, unterminated string, or overlong name, prints its own
; error and returns via bank_return_basic directly (never returns to
; its caller in that case). Returns: Y = length (0 for "").
; NOTE on the three error exits below: each is reached from inside a
; routine that was itself entered via JSR (net_parse_str is always
; called as "jsr net_parse_str"), but they jump straight to a SHARED
; handler that ends in "jmp bank_return_basic" instead of RTS-ing back
; to the caller. That means net_parse_str's own JSR return address is
; still sitting on the stack, unclaimed, when bank_return_basic's
; single PLA runs expecting to find bank_call's saved "old bank" byte
; instead - it pops half of the orphaned return address, writes THAT
; garbage to the real EasyFlash bank register, and jumps into whatever
; ROM that selects. Confirmed live (JAM right after a correctly-printed
; "?MISSING QUOTE", real hardware bank register corrupted). Fix: each
; error exit first PLAs twice to discard its own return address,
; putting the stack back to exactly where it was before this routine's
; own JSR - only then jump to the shared handler.
net_parse_str
        jsr     BAS_CHRGOT
        cmp     #CHR_QUOTE
        beq     nps_have_quote
        pla
        pla
        jmp     net_missing_quote
nps_have_quote
        ldy     #$00
nps_loop
        jsr     BAS_CHRGET
        cmp     #CHR_QUOTE
        beq     nps_close
        cmp     #$00
        bne     nps_not_end
        pla
        pla
        jmp     net_missing_quote
nps_not_end
        cpy     #FILENAME_MAXLEN
        bcc     nps_store
        pla
        pla
        jmp     net_name_too_long
nps_store
        sta     (ult_outptr),y
        iny
        jmp     nps_loop
nps_close
        jsr     BAS_CHRGET            ; consume the closing quote
        rts

net_missing_quote
        ldx     #$00
nmq_loop
        lda     nmq_msg,x
        beq     nmq_done
        jsr     $ffd2
        inx
        bne     nmq_loop
nmq_done
        jmp     bank_return_basic
nmq_msg
        !text   "?MISSING QUOTE"
        !byte   13,0

net_name_too_long
        ldx     #$00
nntl_loop
        lda     nntl_msg,x
        beq     nntl_done
        jsr     $ffd2
        inx
        bne     nntl_loop
nntl_done
        jmp     bank_return_basic
nntl_msg
        !text   "?HOSTNAME/PATH TOO LONG"
        !byte   13,0

; Shared abort handler: RUN/STOP cancelled a command that was stuck
; inside ult_cmd_wait (see that routine and ult_aborted's own comment,
; both in ultimate_sdk.asm) - the Ultimate's own operation (typically a
; TCP read waiting on a remote host that never responds) never
; finished, so there's no real response to process. Not reached from
; TelnetCmd's own interactive loop, which exits the same way tn_done
; already does (silently, matching ordinary RUN/STOP-to-exit) rather
; than printing this - this path is for the "no session was ever
; established" case (HTTPGET, or TELNET's own initial connect).
net_timeout
        ldx     #$00
ntm_loop
        lda     ntm_msg,x
        beq     ntm_done
        jsr     $ffd2
        inx
        bne     ntm_loop
ntm_done
        jmp     bank_return_basic
ntm_msg
        !text   "?NETWORK TIMEOUT"
        !byte   13,0

net_missing_comma
        ldx     #$00
nmc_loop
        lda     nmc_msg,x
        beq     nmc_done
        jsr     $ffd2
        inx
        bne     nmc_loop
nmc_done
        jmp     bank_return_basic
nmc_msg
        !text   "?MISSING COMMA"
        !byte   13,0

httpget_verb
        !text   "GET "
        !byte   0
httpget_ver
        !text   " HTTP/1.0"
        !byte   13,10
        !text   "Host: "
        !byte   0
httpget_end
        !byte   13,10,13,10,0
