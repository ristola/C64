; Bank 1 content: BASIC+ core command bodies. The tokenizer/detokenizer/
; dispatcher engine that used to live alongside these in basicext.asm
; moved to resident.asm - it has to work regardless of which bank is
; switched in, same reasoning as irq_hook. Only the actual command
; bodies stay here, reached through the fixed-slot jump table
; (slots.asm) that resident.asm's ExecuteCommand bank_calls into.
;
; SCREEN category lives here alongside CLS (small enough not to need
; its own bank) - COLOR/LOCATE/PRINTAT are stubs for
; now (each prints its own name via a small inline loop, then
; resident.asm's shared print_stub_suffix - see that routine's comment
; for why this can't be one shared routine taking a runtime pointer:
; $8000-$9FFF is EasyFlash ROM, not RAM). HELP is real, not a stub -
; lists every category/command actually implemented so far.

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_CLS-*, $ff
        jmp     ClsCmd
!fill SLOT_COLOR-*, $ff
        jmp     ColorCmd
!fill SLOT_LOCATE-*, $ff
        jmp     LocateCmd
!fill SLOT_PRINTAT-*, $ff
        jmp     PrintAtCmd
!fill SLOT_HELP-*, $ff
        jmp     HelpCmd
!fill SLOT_RENUM-*, $ff
        jmp     RenumCmd

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill BANK_CONTENT_START-*, $ff

*=BANK_CONTENT_START

; --- CLS: clear the screen. As simple as a new command gets. ---
; Every cross-bank-callable routine has to finish via bank_return/
; bank_return_basic, never a bare RTS or a tail-jump into something
; that itself just RTS's - bank_call pushed a bank-restore byte, plain
; CHROUT here (via a leftover JMP instead of JSR+bank_return_basic) has
; no idea that's there and left it stranded on the stack, corrupting
; whatever RTS ran next. That's what was actually behind "CLS reopens
; the menu" and the old HEX command locking up everything.
ClsCmd
        lda     #$93
        jsr     $ffd2
        jmp     bank_return_basic

ColorCmd
        ldx     #0
color_print_loop
        lda     color_name,x
        beq     color_print_done
        jsr     $ffd2
        inx
        bne     color_print_loop
color_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
LocateCmd
        ldx     #0
locate_print_loop
        lda     locate_name,x
        beq     locate_print_done
        jsr     $ffd2
        inx
        bne     locate_print_loop
locate_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
PrintAtCmd
        ldx     #0
printat_print_loop
        lda     printat_name,x
        beq     printat_print_done
        jsr     $ffd2
        inx
        bne     printat_print_loop
printat_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic

color_name
        !text   "COLOR"
        !byte   0
locate_name
        !text   "LOCATE"
        !byte   0
printat_name
        !text   "PRINTAT"
        !byte   0

; --- HELP: list every category and command actually implemented so
; far (not the full aspirational roadmap - this stays accurate as each
; bank gets built out, rather than promising things that don't work
; yet). Plain CHROUT loop over a null-terminated text block; embedded
; $0D bytes are real carriage returns, handled by CHROUT itself exactly
; like ClsCmd's $93 is - no special-casing needed here. Split into two
; pages (page 1 fits comfortably in 25 rows; both stay under 256 bytes,
; needed anyway since each has its own fixed-address print loop rather
; than one longer block needing a page-crossing index fix - the obvious
; fix, self-modifying the loop's own high-byte operand, does NOT work
; here: $8000-$9FFF is EasyFlash ROM, confirmed empirically, see
; resident.asm's print_stub_suffix comment for the same lesson learned
; on a different routine) with a "press any key" pause + screen clear
; between them, so the first page doesn't scroll away unread before the
; second prints. ---
; help_text1/help_text2 are walked with a 16-bit zero-page pointer, not
; a plain 8-bit X index: help_text2 has grown past 256 bytes (adding
; per-keyword color bytes plus the DEL alias pushed it to 304), and an
; "ldx #0 / inx / bne loop" 8-bit loop silently stops dead the moment X
; wraps 255->0 - no crash, no error, just print output cutting off mid-
; word with everything past byte 256 (including help_text2's own
; trailing HELP_LTBLU color-restore byte) never reached. Confirmed live:
; that's exactly why DEVICE was rendering as "DEVIC" and HELP wasn't
; restoring the text color afterward - both the same bug. $14/$15 is
; free here the same way bank10_content.asm's DIR/send_command already
; established it's safe to reuse as a plain traversal pointer (nothing
; else needs it during a direct-mode command's own bank_call window).
HelpCmd
        lda     #<help_text1
        sta     $14
        lda     #>help_text1
        sta     $15
help1_loop
        ldy     #0
        lda     ($14),y
        beq     help1_done
        jsr     $ffd2
        jsr     help_ptr_inc
        jmp     help1_loop
help1_done
        jsr     help_wait_key
        lda     #<help_text2
        sta     $14
        lda     #>help_text2
        sta     $15
help2_loop
        ldy     #0
        lda     ($14),y
        beq     help2_done
        jsr     $ffd2
        jsr     help_ptr_inc
        jmp     help2_loop
help2_done
        lda     #13
        jsr     $ffd2
        jmp     bank_return_basic

help_ptr_inc
        inc     $14
        bne     help_ptr_inc_done
        inc     $15
help_ptr_inc_done
        rts

; Prints a small prompt, flushes any stray already-buffered key (same
; idea as irq_hook's own GETIN flush in resident.asm), then blocks on
; GETIN until a fresh key arrives - lets the user actually read a page
; before more text appears instead of everything scrolling past at
; once. Clears the screen afterward so the next page starts fresh
; rather than running on below this page's tail.
;
; cli first: OkExt's own sei is still in effect this whole time (not
; lifted until bank_return_basic, at the very end of HelpCmd), and GETIN
; only ever sees a NEW keypress via the jiffy IRQ's own keyboard scan -
; with interrupts off, that scan can't run, so help_flush/help_wait_loop
; below could only ever be satisfied by characters already sitting in
; the buffer from BEFORE HELP was invoked, never a live keypress typed
; in response to the prompt. Confirmed live: this silently ate the
; user's very next keystroke after HELP (consumed here instead of
; reaching the READY prompt afterward), which read as "Return doesn't
; do anything until I type a throwaway character first" - same root
; cause already fixed once for TelnetCmd's own interactive loop.
help_wait_key
        cli
        ldx     #0
help_prompt_loop
        lda     help_more_msg,x
        beq     help_prompt_done
        jsr     $ffd2
        inx
        bne     help_prompt_loop
help_prompt_done
help_flush
        jsr     $ffe4
        bne     help_flush
help_wait_loop
        jsr     $ffe4
        beq     help_wait_loop
        lda     #$93
        jsr     $ffd2
        rts
; Column-aligned layout: each category name is padded to a fixed
; 9-char field (matching "CARTRIDGE", the longest one) in cyan,
; followed by a space and its commands in white, wrapping to an
; indented continuation line (10 spaces, aligning under the commands,
; not repeating the category name) when a category's command list
; doesn't fit the remaining ~30 columns. $9F/$05 are real CHROUT color
; codes (cyan/white), not custom rendering - same mechanism as the
; boot banner's own color choices elsewhere in this project.
HELP_CYAN  = $9f
HELP_LTBLU = $9a        ; CINT's own default text color - restored at
                          ; the end so HELP's own color choices don't
                          ; bleed into whatever's typed afterward
HELP_GREEN = $1e        ; completed keyword/function - real logic, not
                          ; just a name+"NOT YET IMPLEMENTED" stub (see
                          ; resident.asm's print_stub_suffix comment)
HELP_GRAY  = $98        ; still-stubbed keyword/function - update here
                          ; as each one gets built out for real

help_more_msg
        !byte   13
        !byte   HELP_CYAN
        !text   "             PRESS ANY KEY"
        !byte   0

help_text1
        !byte   13
        !byte   HELP_CYAN
        !text   "     SHACKMATE BASIC+ COMMANDS (1/2)"
        !byte   13
        !text   "--------------------------------------"
        !byte   13,13
        !text   "SCREEN   "
        !byte   HELP_GREEN
        !text   "CLS "
        !byte   HELP_GRAY
        !text   "COLOR LOCATE PRINTAT "
        !byte   HELP_GREEN
        !text   "HELP"
        !byte   13
        !text   "          "
        !byte   HELP_GREEN
        !text   "RENUM"
        !byte   13
        !byte   HELP_CYAN
        !text   "GRAPHICS "
        !byte   HELP_GRAY
        !text   "HIRES MULTI TEXT PLOT LINE"
        !byte   13
        !text   "          BOX CIRCLE PAINT"
        !byte   13
        !byte   HELP_CYAN
        !text   "SPRITES  "
        !byte   HELP_GRAY
        !text   "SPRITE SPRITEON SPRITEOFF"
        !byte   13
        !text   "          SPRITECOLOR"
        !byte   13
        !byte   HELP_CYAN
        !text   "INPUT    "
        !byte   HELP_GRAY
        !text   "JOY JOYUP JOYDOWN JOYLEFT"
        !byte   13
        !text   "          JOYRIGHT JOYFIRE"
        !byte   13,13
        !byte   0
help_text2
        !byte   HELP_CYAN
        !text   "     SHACKMATE BASIC+ COMMANDS (2/2)"
        !byte   13
        !text   "--------------------------------------"
        !byte   13,13
        !text   "MEMORY   "
        !byte   HELP_GRAY
        !text   "DUMP FILL MOVE FIND "
        !byte   HELP_GREEN
        !text   "HEX DEC"
        !byte   13
        !byte   HELP_CYAN
        !text   "CARTRIDGE"
        !byte   HELP_GREEN
        !text   " CARTINFO BANK BANKS "
        !byte   HELP_GRAY
        !text   "FLASHERASE"
        !byte   13
        !text   "          FLASHLOAD FLASHVERIFY"
        !byte   13
        !byte   HELP_CYAN
        !text   "SOUND    "
        !byte   HELP_GRAY
        !text   "SOUND VOLUME WAVE ADSR FILTER"
        !byte   13
        !byte   HELP_CYAN
        !text   "DISK     "
        !byte   HELP_GREEN
        !text   "DIR DEVICE CD DELETE/DEL RENAME"
        !byte   13
        !text   "          DLOAD DSAVE"
        !byte   13,13
        !byte   HELP_LTBLU
        !byte   0

; ============================================================
; RENUM [start[,step]] - renumber the whole program, rewriting every
; GOTO/GOSUB/THEN/RUN/RESTORE line-number reference to match. No
; arguments: start=10, step=10 (matches the classic default). One
; argument: that start, step=10. Both: exactly as given.
;
; Verified against the real BASIC ROM (basic-901226-01.bin, statically
; disassembled - see the project's reference-c64-hardware-facts memory)
; rather than assumed, per this project's own hard-learned rule: real
; BASIC ROM has an existing routine, LINKPRG ($A533), that walks a
; program from TXTTAB by scanning for each line's own $00 terminator
; (not by trusting existing link-pointer VALUES) and rewrites every
; link pointer to match - exactly the relocation RENUM needs after
; changing every line's digit count, and it's a plain, balanced
; JSR/RTS routine (confirmed by reading its actual bytes), safe to call
; from anywhere. Its caller is expected to then copy the pointer it
; leaves in $22/$23 (address of the final terminator's own start - the
; caller adds 2, past that terminator, before storing into VARTAB;
; confirmed against real NEW's own identical +2, $a64c-$a657) into
; VARTAB.
;
; NEW/CLR's own shared tail that does that VARTAB copy plus the rest of
; the CLR-equivalent reset (resetting ARYTAB/STREND/FRETOP, clearing
; variables) lives at $A659 - deliberately NOT called here: disassembly
; showed its own ending pops 2 bytes off the stack and manufactures a
; fresh return via a hard TXS reset to a fixed low stack pointer,
; assuming those 2 bytes are BASIC main-loop's own return address (true
; when NEW/CLR are dispatched directly from BASIC's statement loop, not
; true here - we're several JSRs deep inside OkExt/bank_call). Calling
; it would discard bank_call's pushed old-bank byte and strand SEI
; forever, the exact same class of bug already root-caused once this
; session for a totally different reason (bank_call's old PHP/PLP) and
; explicitly named in this project's RUN-hang fix. The 6 pointer copies
; and the DATA-pointer reset ($A81D, also a plain balanced RTS routine)
; are done by hand below instead - only a dozen extra bytes.
;
; Every abort path below (?SYNTAX ERROR / ?RENUM RANGE ERROR /
; ?PROGRAM TOO LARGE FOR RENUM) runs from THIS routine's own top level,
; zero JSR frames deeper than bank_call already put on the stack -
; never from inside renum_copy_body/renum_handle_refs/etc, which only
; ever signal failure back via carry and a normal RTS. That's the same
; "orphaned return address" bug class bank10_content.asm's
; parse_filename hit twice already (see its own comment) - jumping
; straight to bank_return_basic from any deeper point would strand a
; JSR return address bank_return_basic's single PLA would then
; misread as the old bank. And critically: every abort here happens
; BEFORE the RENUM_BUF-to-TXTTAB copy-back, so the user's real program
; is never touched unless the whole rebuild - argument parsing, the
; per-line rewrite, and the buffer-size check - has already succeeded.
;
; Token bytes tracked: GOTO=$89, RUN=$8A, RESTORE=$8C, GOSUB=$8D,
; THEN=$A7. A tracked token is always followed by zero or more
; comma-separated line-number literals (a bare single one normally; a
; comma list only for ON...GOTO/GOSUB, which reuses the same GOTO/GOSUB
; token) - renum_handle_refs parses however many are actually there and
; leaves anything else (a THEN followed by a statement, a bare RUN/
; RESTORE) completely alone. Numbers that don't match any real line in
; the program are left with their own (unchanged) value, re-emitted
; through the same decimal writer as everything else - the only
; observable effect is that a stray leading zero, if anyone ever typed
; one, gets normalized away; the reference itself was already going to
; be a runtime "UNDEF'D STATEMENT" error either way. Text inside quoted
; strings or after REM is never tokenized as these keywords in the
; first place (real BASIC's own tokenizer already excludes both), so
; nothing here needs to special-case them - a literal "GOTO" typed
; inside a PRINT string is just ASCII bytes, never token $89.
; ============================================================

BAS_CHRGET  = $73
BAS_CHRGOT  = $79
RENUM_LINKPRG = $a533
RENUM_DATAPTR_RESET = $a81d

RenumCmd
        lda     #10
        sta     renum_start
        lda     #0
        sta     renum_start+1
        lda     #10
        sta     renum_step
        lda     #0
        sta     renum_step+1
        jsr     BAS_CHRGOT
        cmp     #0
        beq     renum_args_done
        cmp     #':'
        beq     renum_args_done
        jsr     renum_parse_arg
        lda     renum_pval
        sta     renum_start
        lda     renum_pval+1
        sta     renum_start+1
        jsr     BAS_CHRGOT
        cmp     #','
        bne     renum_args_done
        jsr     BAS_CHRGET
        jsr     renum_parse_arg
        lda     renum_pval
        sta     renum_step
        lda     renum_pval+1
        sta     renum_step+1
renum_args_done
        lda     renum_step
        ora     renum_step+1
        bne     +
        jmp     renum_error_range       ; step of 0 would never advance
+       lda     $2b
        sta     renum_src
        lda     $2c
        sta     renum_src+1
        ldy     #1
        lda     (renum_src),y
        bne     renum_have_program
        jmp     bank_return_basic       ; empty program - nothing to do
renum_have_program
        lda     #<RENUM_BUF
        sta     renum_dest
        lda     #>RENUM_BUF
        sta     renum_dest+1
        lda     renum_start
        sta     renum_curnew
        lda     renum_start+1
        sta     renum_curnew+1
renum_main_loop
        ldy     #1
        lda     (renum_src),y
        beq     renum_finalize          ; end of program (0000 link)
        lda     renum_curnew+1
        cmp     #$fa                    ; renum_curnew >= 64000?
        bcc     +
        jmp     renum_error_range
+       lda     #$ff                    ; placeholder link (LINKPRG
        jsr     renum_putc              ; fixes these up for real once
        bcc     +                       ; the whole program is copied
        jmp     renum_error_toolarge    ; back into place)
+       lda     #$ff
        jsr     renum_putc
        bcc     +
        jmp     renum_error_toolarge
+       lda     renum_curnew
        jsr     renum_putc
        bcc     +
        jmp     renum_error_toolarge
+       lda     renum_curnew+1
        jsr     renum_putc
        bcc     +
        jmp     renum_error_toolarge
+       jsr     renum_skip4             ; renum_src past old link+linenum
        jsr     renum_copy_body
        bcc     +
        jmp     renum_error_toolarge
+       clc
        lda     renum_curnew
        adc     renum_step
        sta     renum_curnew
        lda     renum_curnew+1
        adc     renum_step+1
        sta     renum_curnew+1
        jmp     renum_main_loop
renum_finalize
        lda     #0
        jsr     renum_putc
        bcc     +
        jmp     renum_error_toolarge
+       lda     #0
        jsr     renum_putc
        bcc     +
        jmp     renum_error_toolarge
+       lda     renum_dest
        sec
        sbc     #<RENUM_BUF
        sta     renum_len
        lda     renum_dest+1
        sbc     #>RENUM_BUF
        sta     renum_len+1
        lda     $2b
        sta     renum_src               ; copy-back destination = TXTTAB
        lda     $2c
        sta     renum_src+1
        lda     #<RENUM_BUF
        sta     renum_dest              ; copy-back source = RENUM_BUF
        lda     #>RENUM_BUF
        sta     renum_dest+1
renum_copyback_loop
        ldy     #0
        lda     (renum_dest),y
        sta     (renum_src),y
        inc     renum_dest
        bne     +
        inc     renum_dest+1
+       inc     renum_src
        bne     +
        inc     renum_src+1
+       lda     renum_len
        bne     +
        dec     renum_len+1
+       dec     renum_len
        lda     renum_len
        ora     renum_len+1
        bne     renum_copyback_loop
        jsr     RENUM_LINKPRG
        clc                             ; VARTAB = end of program: LINKPRG
        lda     $22                     ; leaves $22/$23 pointing AT the
        adc     #2                      ; final 0000 terminator's own
        sta     $2d                     ; start, not past it - real NEW
        lda     $23                     ; ($a64c-$a657, verified) always
        adc     #0                      ; adds 2 for exactly this reason
        sta     $2e
        lda     $2d
        sta     $2f                     ; ARYTAB = VARTAB
        lda     $2e
        sta     $30
        lda     $2d
        sta     $31                     ; STREND = VARTAB
        lda     $2e
        sta     $32
        lda     $37
        sta     $33                     ; FRETOP = MEMSIZ
        lda     $38
        sta     $34
        jsr     RENUM_DATAPTR_RESET
        jmp     bank_return_basic

renum_error_range
        ldx     #0
rer_loop
        lda     renum_range_msg,x
        beq     rer_done
        jsr     $ffd2
        inx
        bne     rer_loop
rer_done
        jmp     bank_return_basic
renum_error_toolarge
        ldx     #0
ret_loop
        lda     renum_toolarge_msg,x
        beq     ret_done
        jsr     $ffd2
        inx
        bne     ret_loop
ret_done
        jmp     bank_return_basic
renum_error_syntax
        ldx     #0
res_loop
        lda     renum_syntax_msg,x
        beq     res_done
        jsr     $ffd2
        inx
        bne     res_loop
res_done
        jmp     bank_return_basic

renum_range_msg
        !text   "?RENUM RANGE ERROR"
        !byte   13,0
renum_toolarge_msg
        !text   "?PROGRAM TOO LARGE FOR RENUM"
        !byte   13,0
renum_syntax_msg
        !text   "?SYNTAX ERROR"
        !byte   13,0

; --- renum_src += 4 (skip a line's old link+linenum fields). ---
renum_skip4
        clc
        lda     renum_src
        adc     #4
        sta     renum_src
        bcc     +
        inc     renum_src+1
+       rts

; --- Copies/rewrites one line's statement body (renum_src -> renum_dest
; via renum_putc), stopping after writing the $00 terminator. Carry set
; on return = renum_putc hit RENUM_BUF_END (propagated, not handled
; here - see this file's RENUM header comment on why only RenumCmd's
; own top level ever jumps to bank_return_basic). ---
renum_copy_body
        jsr     renum_getc
        cmp     #0
        beq     rcb_terminator
        cmp     #$89            ; GOTO
        beq     rcb_reftoken
        cmp     #$8a            ; RUN
        beq     rcb_reftoken
        cmp     #$8c            ; RESTORE
        beq     rcb_reftoken
        cmp     #$8d            ; GOSUB
        beq     rcb_reftoken
        cmp     #$a7            ; THEN
        beq     rcb_reftoken
        jsr     renum_putc
        bcs     rcb_overflow
        jmp     renum_copy_body
rcb_terminator
        jsr     renum_putc
        bcs     rcb_overflow
        clc
        rts
rcb_reftoken
        jsr     renum_putc
        bcs     rcb_overflow
        jsr     renum_handle_refs
        bcs     rcb_overflow
        jmp     renum_copy_body
rcb_overflow
        sec
        rts

; --- Called right after a tracked token byte has been written. Copies
; through any spaces, then (if a decimal literal follows) parses it,
; resolves old->new via renum_lookup, and writes the new number; repeats
; on a comma (ON...GOTO/GOSUB lists). Leaves renum_src untouched beyond
; whatever it actually consumed if no digit follows at all. ---
renum_handle_refs
rhr_loop
        jsr     renum_peek
        cmp     #' '
        bne     rhr_check_digit
        jsr     renum_getc
        jsr     renum_putc
        bcs     rhr_overflow
        jmp     rhr_loop
rhr_check_digit
        cmp     #'0'
        bcc     rhr_done
        cmp     #'9'+1
        bcs     rhr_done
        jsr     renum_parse_ref_number
        jsr     renum_lookup
        bcc     rhr_have_new
        lda     renum_pval
        sta     renum_newval
        lda     renum_pval+1
        sta     renum_newval+1
rhr_have_new
        lda     renum_newval
        ldx     renum_newval+1
        jsr     renum_write_decimal
        bcs     rhr_overflow
        jsr     renum_peek
        cmp     #','
        bne     rhr_done
        jsr     renum_getc
        jsr     renum_putc
        bcs     rhr_overflow
        jmp     rhr_loop
rhr_done
        clc
        rts
rhr_overflow
        sec
        rts

; --- Parses a decimal literal at renum_src into renum_pval - caller
; already confirmed the first digit via renum_peek. No overflow guard
; (unlike renum_parse_arg): a reference too large to fit 16 bits can't
; match any real line number anyway, so wrapping is harmless - it just
; falls through renum_lookup as "not found" and gets re-emitted as-is.
renum_parse_ref_number
        lda     #0
        sta     renum_pval
        sta     renum_pval+1
rprn_loop
        jsr     renum_peek
        cmp     #'0'
        bcc     rprn_done
        cmp     #'9'+1
        bcs     rprn_done
        jsr     renum_getc
        sec
        sbc     #'0'
        jsr     renum_x10_plus_digit
        jmp     rprn_loop
rprn_done
        rts

; --- Scans the ORIGINAL program (own pointer, renum_search - independent
; of renum_src, which is mid-line whenever this runs) from TXTTAB,
; comparing each line's own line-number field to renum_pval while
; tracking the new number it would get (start + position*step, computed
; additively as the scan advances rather than via a separate multiply).
; Carry clear + renum_newval set on a match; carry set (not found) if
; the scan reaches the 0000 end-of-program link first. ---
renum_lookup
        lda     renum_start
        sta     renum_newval
        lda     renum_start+1
        sta     renum_newval+1
        lda     $2b
        sta     renum_search
        lda     $2c
        sta     renum_search+1
rl_loop
        ldy     #1
        lda     (renum_search),y
        bne     rl_check
        sec
        rts
rl_check
        ldy     #3
        lda     (renum_search),y
        cmp     renum_pval+1
        bne     rl_next
        ldy     #2
        lda     (renum_search),y
        cmp     renum_pval
        bne     rl_next
        clc
        rts
rl_next
        clc
        lda     renum_newval
        adc     renum_step
        sta     renum_newval
        lda     renum_newval+1
        adc     renum_step+1
        sta     renum_newval+1
        ldy     #0
        lda     (renum_search),y
        pha
        ldy     #1
        lda     (renum_search),y
        sta     renum_search+1
        pla
        sta     renum_search
        jmp     rl_loop

; --- A=lo, X=hi -> writes the value as decimal ASCII digits via
; renum_putc (no leading zeros; zero itself still writes one "0"),
; identical algorithm to resident.asm's print_decimal_word/bank5's
; dec_to_buf, reusing their pdw_lo/pdw_hi/pdw_count/pdw_started scratch
; and pow10_lo/pow10_hi table (same-assembly reference into resident.asm,
; safe - see bank5_content.asm's dec_to_buf comment on why). Carry set
; on return = renum_putc overflowed partway through. ---
renum_write_decimal
        sta     pdw_lo
        stx     pdw_hi
        lda     #0
        sta     pdw_started
        ldx     #0
rwd_digit
        lda     #0
        sta     pdw_count
rwd_sub
        lda     pdw_lo
        sec
        sbc     pow10_lo,x
        tay
        lda     pdw_hi
        sbc     pow10_hi,x
        bcc     rwd_digit_done
        sty     pdw_lo
        sta     pdw_hi
        inc     pdw_count
        jmp     rwd_sub
rwd_digit_done
        cpx     #4
        beq     rwd_force
        lda     pdw_count
        bne     rwd_force
        lda     pdw_started
        beq     rwd_skip
rwd_force
        lda     #1
        sta     pdw_started
        lda     pdw_count
        clc
        adc     #'0'
        jsr     renum_putc
        bcs     rwd_overflow
rwd_skip
        inx
        cpx     #5
        bne     rwd_digit
        clc
        rts
rwd_overflow
        sec
        rts

; --- RENUM's own argument parser (live BASIC text via BAS_CHRGET/
; BAS_CHRGOT, not renum_src): reads a decimal literal into renum_pval.
; Unlike renum_parse_ref_number, this DOES guard against overflow -
; these values seed renum_curnew's own arithmetic, so an unclamped wrap
; could produce a too-small "new" line number that then silently
; collides with a later one instead of tripping the >63999 range check.
; Requires at least one digit (syntax error otherwise, aborted straight
; from here - safe, still at RenumCmd's own top level, nothing rebuilt
; yet). ---
renum_parse_arg
        lda     #0
        sta     renum_pval
        sta     renum_pval+1
        jsr     BAS_CHRGOT
        cmp     #'0'
        bcs     +
        jmp     renum_error_syntax
+       cmp     #'9'+1
        bcc     rpa_loop
        jmp     renum_error_syntax
rpa_loop
        jsr     BAS_CHRGOT
        cmp     #'0'
        bcc     rpa_done
        cmp     #'9'+1
        bcs     rpa_done
        lda     renum_pval+1
        cmp     #>6554
        bcc     rpa_ok
        beq     +
        jmp     renum_error_range
+       lda     renum_pval
        cmp     #<6554
        bcc     rpa_ok
        jmp     renum_error_range
rpa_ok
        jsr     BAS_CHRGOT
        sec
        sbc     #'0'
        pha
        jsr     BAS_CHRGET      ; advance past this digit
        pla
        jsr     renum_x10_plus_digit
        jmp     rpa_loop
rpa_done
        rts

; --- renum_pval = renum_pval*10 + A (A = digit, 0-9 on entry). Shared
; by renum_parse_arg and renum_parse_ref_number - both need the exact
; same 6502-has-no-multiply shift/add sequence (x*10 = x*8 + x*2), just
; from different sources of digits. Uses pdw_lo/pdw_hi as scratch (free
; at this point - renum_write_decimal's own use of them never overlaps
; a caller's use of this routine). ---
renum_x10_plus_digit
        pha
        lda     renum_pval
        asl
        sta     pdw_lo
        lda     renum_pval+1
        rol
        sta     pdw_hi
        lda     pdw_lo
        sta     renum_pval
        lda     pdw_hi
        sta     renum_pval+1
        asl     renum_pval
        rol     renum_pval+1
        asl     renum_pval
        rol     renum_pval+1
        clc
        lda     renum_pval
        adc     pdw_lo
        sta     renum_pval
        lda     renum_pval+1
        adc     pdw_hi
        sta     renum_pval+1
        pla
        clc
        adc     renum_pval
        sta     renum_pval
        bcc     +
        inc     renum_pval+1
+       rts

; --- Reads one byte from (renum_src),0, advances renum_src, returns
; that byte in A (the byte just consumed - not real CHRGET's "returns
; the NEW current byte after advancing" convention, since this walks
; our own renum_src pointer, not BASIC's TXTPTR). ---
renum_getc
        ldy     #0
        lda     (renum_src),y
        pha
        inc     renum_src
        bne     +
        inc     renum_src+1
+       pla
        rts

; --- Reads (renum_src),0 WITHOUT advancing - lets callers decide
; whether to consume it. ---
renum_peek
        ldy     #0
        lda     (renum_src),y
        rts

; --- A = byte to write at (renum_dest),0. Checks RENUM_BUF_END BEFORE
; writing (not after) so a byte is never actually written past the
; buffer; advances renum_dest only on success. Carry set + nothing
; written = buffer full; carry clear = written, renum_dest advanced. ---
renum_putc
        pha
        lda     renum_dest+1
        cmp     #>RENUM_BUF_END
        bcc     rp_room
        bne     rp_full
        lda     renum_dest
        cmp     #<RENUM_BUF_END
        bcs     rp_full
rp_room
        pla
        ldy     #0
        sta     (renum_dest),y
        inc     renum_dest
        bne     +
        inc     renum_dest+1
+       clc
        rts
rp_full
        pla
        sec
        rts
