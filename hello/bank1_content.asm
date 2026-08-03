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

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill $8100-*, $ff

*=$8100

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
HelpCmd
        ldx     #0
help1_loop
        lda     help_text1,x
        beq     help1_done
        jsr     $ffd2
        inx
        bne     help1_loop
help1_done
        jsr     help_wait_key
        ldx     #0
help2_loop
        lda     help_text2,x
        beq     help2_done
        jsr     $ffd2
        inx
        bne     help2_loop
help2_done
        jmp     bank_return_basic

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
help_more_msg
        !byte   13
        !text   "-- PRESS ANY KEY --"
        !byte   0

help_text1
        !text   "SCREEN:"
        !byte   13
        !text   "  CLS COLOR LOCATE PRINTAT"
        !byte   13
        !text   "  HELP"
        !byte   13,13
        !text   "GRAPHICS:"
        !byte   13
        !text   "  HIRES MULTI TEXT PLOT LINE"
        !byte   13
        !text   "  BOX CIRCLE PAINT"
        !byte   13,13
        !text   "SPRITES:"
        !byte   13
        !text   "  SPRITE SPRITEON SPRITEOFF"
        !byte   13
        !text   "  SPRITECOLOR"
        !byte   13,13
        !text   "INPUT:"
        !byte   13
        !text   "  JOY JOYUP JOYDOWN JOYLEFT"
        !byte   13
        !text   "  JOYRIGHT JOYFIRE"
        !byte   13,13
        !byte   0
help_text2
        !text   "MEMORY:"
        !byte   13
        !text   "  DUMP FILL MOVE"
        !byte   13
        !text   "  FIND HEX$ DEC$"
        !byte   13,13
        !text   "CARTRIDGE:"
        !byte   13
        !text   "  CARTINFO BANK BANKS"
        !byte   13
        !text   "  FLASHERASE FLASHLOAD FLASHVERIFY"
        !byte   13,13
        !text   "SOUND:"
        !byte   13
        !text   "  SOUND VOLUME WAVE ADSR"
        !byte   13
        !text   "  FILTER"
        !byte   13,13
        !text   "DISK:"
        !byte   13
        !text   "  DIR DEVICE CD DELETE RENAME"
        !byte   13,0
