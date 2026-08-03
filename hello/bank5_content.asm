; Bank 5 content: MEMORY category. DUMP/FILL/MOVE are statements;
; FIND/HEX$/DEC$ are functions (dispatched via resident.asm's
; EvaluateFunction/IEVAL). FIND still stubs to a placeholder numeric
; 0 via func_result_hi/lo + bank_return. HEX$/DEC$ are real: BASIC's
; actual string-descriptor convention - $B47D to allocate N bytes
; (A=length in, $62/$63=data pointer out), write the bytes yourself,
; then $B4CA to finalize (sets BAS_VALTYP=$FF and builds the temp
; descriptor) - reverse-engineered by statically disassembling the real
; BASIC ROM's own CHR$ handler ($B6EC, found via the ROM's function
; address table at $A052+19*2), not guessed at or recalled from general
; C64 knowledge: cross-checked several nearby table entries (USR->
; $0310, RND->$E097, SIN->$E26B) against their well-known real addresses
; to confirm the table location itself was read correctly first. Unlike
; a live VICE trace, this needed no display access - just the same
; basic-901226-01.bin ROM image VICE itself loads.
;
; EvaluateFunction (resident.asm) needed a small extension for this:
; it always used to build FAC1 from func_result_hi/lo via $B391
; (numeric only) after any function call. Now it checks a new
; func_is_string flag (slots.asm) first - HexDollarFunc/DecDollarFunc
; set it before returning; every other (numeric) function is unaffected
; since EvaluateFunction itself clears the flag before every call.
;
; $B47D/$B4CA are real BASIC ROM code ($A000-$BFFF), always mapped
; regardless of which EasyFlash bank is switched in - safe to JSR
; directly, same as BAS_FRMNUM/BAS_GETADR already are elsewhere in this
; project. The zero page they touch ($61-$63 for the allocation, $16/
; $17/$19-$21 for the temp string-descriptor stack) overlaps this
; project's own $02-$38 menu scratch range (ultimate_sdk.asm/
; features.asm), but that's not a real conflict: HEX$/DEC$ only ever
; run during ordinary foreground BASIC evaluation, never while the F1
; menu is active (EvaluateFunction already holds interrupts off with
; SEI for its whole bank_call round trip, so the menu's own IRQ-driven
; entry point can't fire mid-call) - BASIC is simply using its own
; zero page exactly as it always does for any string operation.

BAS_FRMNUM  = $ad8a      ; evaluate + require a numeric expression
BAS_GETADR  = $b7f7      ; convert FAC1 to a 16-bit int in $14/$15
BAS_CHRGET  = $73        ; JSR: get next char, advance TXTPTR
BAS_CHRGOT  = $79        ; JSR: re-get current char, don't advance
BAS_VALTYP  = $0d
BAS_GETSPA  = $b47d      ; allocate a string: A=length in, out $62/$63=
                          ; data pointer (write your bytes there)
BAS_STRFIN  = $b4ca      ; finalize the string built via BAS_GETSPA:
                          ; sets BAS_VALTYP=$FF and the temp descriptor
CHR_LPAREN  = $28
CHR_RPAREN  = $29
CHR_QUOTE   = $22

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_DUMP-*, $ff
        jmp     DumpCmd
!fill SLOT_FILL-*, $ff
        jmp     FillCmd
!fill SLOT_MOVE-*, $ff
        jmp     MoveCmd
!fill SLOT_FIND-*, $ff
        jmp     FindFunc
!fill SLOT_HEXDOLLAR-*, $ff
        jmp     HexDollarFunc
!fill SLOT_DECDOLLAR-*, $ff
        jmp     DecDollarFunc

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill $8100-*, $ff

*=$8100

DumpCmd
        ldx     #0
dump_print_loop
        lda     dump_name,x
        beq     dump_print_done
        jsr     $ffd2
        inx
        bne     dump_print_loop
dump_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
FillCmd
        ldx     #0
fill_print_loop
        lda     fill_name,x
        beq     fill_print_done
        jsr     $ffd2
        inx
        bne     fill_print_loop
fill_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
MoveCmd
        ldx     #0
move_print_loop
        lda     move_name,x
        beq     move_print_done
        jsr     $ffd2
        inx
        bne     move_print_loop
move_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic

dump_name
        !text   "DUMP"
        !byte   0
fill_name
        !text   "FILL"
        !byte   0
move_name
        !text   "MOVE"
        !byte   0

FindFunc
        lda     #$00
        sta     func_result_hi
        sta     func_result_lo
        jmp     bank_return
; --- HEX$(n): 16-bit n (0-65535) as 4 uppercase hex digits, zero-padded
; (e.g. HEX$(255) = "00FF") - same fixed width the retired HEX command
; (basicext.asm) used to print directly, now as a real string result.
; "(" / ")" are hand-parsed here rather than reusing BASIC's own generic
; function-call paren machinery (real ROM, but only reachable through
; the stock per-token function dispatcher our own EXTFUNCTOK path
; bypasses entirely) - same style DELETE/RENAME already use for their
; own quoted-string parsing in bank10_content.asm. ---
HexDollarFunc
        jsr     BAS_CHRGOT
        cmp     #CHR_LPAREN
        beq     +
        jmp     func_syntax_error
+       jsr     BAS_CHRGET      ; consume '('
        lda     #$00
        sta     BAS_VALTYP
        jsr     BAS_FRMNUM      ; evaluate + require numeric -> FAC1
        jsr     BAS_GETADR      ; $14/$15 = 16-bit value, low/high
        jsr     BAS_CHRGOT
        cmp     #CHR_RPAREN
        beq     +
        jmp     func_syntax_error
+       jsr     BAS_CHRGET      ; consume ')'
        lda     #4
        jsr     BAS_GETSPA      ; allocate a 4-byte string -> $62/$63
        ldy     #0
        lda     $15             ; high byte first (most-significant digits)
        jsr     hex_write_byte
        lda     $14
        jsr     hex_write_byte
        jsr     BAS_STRFIN
        lda     #1
        sta     func_is_string
        jmp     bank_return

; --- DEC$("hex string"): the inverse of HEX$ - takes a quoted string
; of 1-4 hex digits (0-9, A-F, a-f) and returns its decimal value as a
; string, e.g. DEC$("D020") = "53280". C64 BASIC has no hex-literal
; syntax (no "$FF"-style prefix), so the argument has to be a real
; quoted string - DEC$(D020) without quotes parses "D020" as an
; undefined variable name (silently 0), not a hex constant. That's why
; this takes a string, not DEC$(n)'s old numeric argument (which was
; just STR$ without the leading space - not actually useful as HEX$'s
; inverse, and not what "the decimal value of the hex number entered"
; means). ---
DecDollarFunc
        jsr     BAS_CHRGOT
        cmp     #CHR_LPAREN
        beq     +
        jmp     func_syntax_error
+       jsr     BAS_CHRGET      ; consume '('
        jsr     BAS_CHRGOT
        cmp     #CHR_QUOTE
        beq     +
        jmp     func_syntax_error
+       jsr     BAS_CHRGET      ; consume opening quote
        lda     #0
        sta     hex_acc_lo
        sta     hex_acc_hi
        sta     hex_digit_count
dec_hex_loop
        jsr     BAS_CHRGOT
        cmp     #CHR_QUOTE
        beq     dec_hex_done
        cmp     #0              ; end of line - unterminated string
        beq     dhl_error
        ldx     hex_digit_count
        cpx     #4              ; a 16-bit value can't hold a 5th digit
        beq     dhl_error
        jsr     hex_char_to_nibble
        bcc     dhl_valid
dhl_error
        jmp     func_syntax_error
dhl_valid
        pha                     ; stash the nibble - shifting clobbers A
        ldx     #4
dec_shift_loop
        asl     hex_acc_lo
        rol     hex_acc_hi
        dex
        bne     dec_shift_loop
        pla
        ora     hex_acc_lo
        sta     hex_acc_lo
        inc     hex_digit_count
        jsr     BAS_CHRGET
        jmp     dec_hex_loop
dec_hex_done
        jsr     BAS_CHRGET      ; consume closing quote
        jsr     BAS_CHRGOT
        cmp     #CHR_RPAREN
        beq     +
        jmp     func_syntax_error
+       jsr     BAS_CHRGET      ; consume ')'
        lda     hex_acc_lo
        sta     $14
        lda     hex_acc_hi
        sta     $15
        jsr     dec_to_buf      ; digits -> dec_buf, dtb_outpos = count
        lda     dtb_outpos
        jsr     BAS_GETSPA      ; allocate dtb_outpos bytes -> $62/$63
        ldy     #0
dec_copy
        cpy     dtb_outpos
        beq     dec_copy_done
        lda     dec_buf,y
        sta     ($62),y
        iny
        jmp     dec_copy
dec_copy_done
        jsr     BAS_STRFIN
        lda     #1
        sta     func_is_string
        jmp     bank_return

; A (PETSCII char) -> A = nibble value 0-15, carry clear, if it's a
; valid hex digit (0-9, A-F, a-f); carry set (A undefined) otherwise.
hex_char_to_nibble
        cmp     #'0'
        bcc     hctn_bad
        cmp     #'9'+1
        bcs     hctn_not_digit
        sec
        sbc     #'0'
        clc
        rts
hctn_not_digit
        cmp     #'A'
        bcc     hctn_bad
        cmp     #'F'+1
        bcs     hctn_try_lower
        sec
        sbc     #'A'-10
        clc
        rts
hctn_try_lower
        cmp     #'a'
        bcc     hctn_bad
        cmp     #'f'+1
        bcs     hctn_bad
        sec
        sbc     #'a'-10
        clc
        rts
hctn_bad
        sec
        rts

; --- Shared "?SYNTAX ERROR" tail for HEX$/DEC$'s own hand-rolled paren
; checks. Falls back to a plain numeric 0 result rather than a real
; trapped BASIC error (JMP $A437 with an error-index in X, per the ROM's
; own paren-mismatch handling) - this project has no verified, live-
; traced error-code convention yet (see the [[feedback-verify-c64-facts]]
; memory), and func_is_string's own EvaluateFunction default already
; makes "print a message, then resolve to numeric 0" the safe fallback
; shared by every other stub in this codebase - not silent, just not a
; true abort back to the command loop. Revisit once error dispatch is
; traced live, the same way $B47D/$B4CA were. ---
func_syntax_error
        ldx     #0
fse_loop
        lda     fse_msg,x
        beq     fse_done
        jsr     $ffd2
        inx
        bne     fse_loop
fse_done
        lda     #$00
        sta     func_result_hi
        sta     func_result_lo
        jmp     bank_return
fse_msg
        !text   "?SYNTAX ERROR"
        !byte   13,0

; --- Writes A as 2 uppercase hex digit chars to ($62),Y, Y+=2 on
; return. Local, self-contained variant of features.asm's print_hex
; (that one prints via CHROUT and lives in Bank 0's own content - not
; reachable from here without a full bank_call, not worth it for two
; instructions' difference). ---
hex_write_byte
        pha
        lsr
        lsr
        lsr
        lsr
        jsr     hex_nybble_to_ay
        pla
        and     #$0f
        jsr     hex_nybble_to_ay
        rts

; A (0-15) -> hex char, written to ($62),Y, Y+=1 on return.
hex_nybble_to_ay
        cmp     #$0a
        bcc     hn_digit
        clc
        adc     #7
hn_digit
        clc
        adc     #'0'
        sta     ($62),y
        iny
        rts

; --- Converts the 16-bit value in $14/$15 (BAS_GETADR's own output) to
; decimal ASCII digits in dec_buf, no leading zeros (0 itself still
; writes one digit "0"). Same repeated-subtraction algorithm as
; resident.asm's print_decimal_word - reusing its pow10_lo/pow10_hi
; table directly (a same-bank JSR/reference, not a cross-bank call:
; resident.asm is assembled into this same 8K bank image, unlike
; another bank's content) - but writing into a buffer instead of
; printing via CHROUT, since DEC$ needs the final digit count before it
; can allocate the right-sized result string via BAS_GETSPA. Leaves
; dtb_outpos = final digit count (1-5) for the caller. ---
dec_to_buf
        lda     $14
        sta     pdw_lo
        lda     $15
        sta     pdw_hi
        lda     #0
        sta     pdw_started
        sta     dtb_outpos
        ldx     #0
dtb_digit
        lda     #0
        sta     pdw_count
dtb_sub
        lda     pdw_lo
        sec
        sbc     pow10_lo,x
        tay
        lda     pdw_hi
        sbc     pow10_hi,x
        bcc     dtb_digit_done  ; borrow occurred - can't subtract again
        sty     pdw_lo
        sta     pdw_hi
        inc     pdw_count
        jmp     dtb_sub
dtb_digit_done
        cpx     #4
        beq     dtb_force       ; ones place: always writes, never suppressed
        lda     pdw_count
        bne     dtb_force       ; nonzero digit: write it, mark "started"
        lda     pdw_started
        beq     dtb_skip        ; leading zero, nothing real written yet
dtb_force
        lda     #1
        sta     pdw_started
        lda     pdw_count
        clc
        adc     #'0'
        ldy     dtb_outpos
        sta     dec_buf,y
        inc     dtb_outpos
dtb_skip
        inx
        cpx     #5
        bne     dtb_digit
        rts
