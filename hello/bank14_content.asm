; Bank 14 content: the F1 Cart Menu. Everything under menu_open (common.
; asm, and features.asm/bitmap.asm/spriteeditor.asm which common.asm
; itself !source's) lived in Bank 0 originally; moved here once Bank 0
; ran out of room to hold it all - twice - as menu features kept
; growing. See bank0_content.asm's own header comment and slots.asm's
; SLOT_JET_CHARSET_SETUP comment for the full story. This bank is part
; of the protected "system" range - see slots.asm's FIRST_USER_BANK
; comment for the wider policy.
;
; jet_charset_setup/jet_bold_font/jet_copyright_glyph moved here too
; (from bank0_content.asm, unchanged otherwise) - menu_draw_title
; (common.asm, below) is jet_charset_setup's other caller, and having
; two copies of that routine (one per caller's bank) would just be two
; things to keep in sync instead of one. jet_bold_font_big (this file's
; original, first occupant - a 2x pixel-doubled version of jet_bold_
; font for the Cart Menu's own title) is now just one more piece
; jet_charset_setup patches in locally, the same way it always patched
; jet_bold_font/jet_copyright_glyph - no bank_call needed for that step
; any more now that all three live together.

JET_CHARSET = $2800        ; must match resident.asm's own copy of this
                             ; constant (jet_anim_tick's own home) - see
                             ; jet_charset_setup below for the full story

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_MENU_OPEN-*, $ff
        jmp     menu_open
!fill SLOT_JET_CHARSET_SETUP-*, $ff
        jmp     jet_charset_setup_xbank

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill BANK_CONTENT_START-*, $ff

*=BANK_CONTENT_START

; jet_charset_setup has two callers that need two different calling
; conventions: bank0_content.asm's jet_setup reaches it cross-bank, via
; bank_call (needs to end in bank_return), while menu_draw_title
; (common.asm, below) is same-bank now that both live here (needs a
; plain rts, and can't go through bank_call/bank_return at all - there'd
; be no matching bank_call on the stack to unwind). Rather than pick one
; convention and force the other caller to work around it, this slot's
; own trampoline is the ONLY thing that does the bank_call dance -
; jet_charset_setup itself stays a plain, ordinary subroutine either
; way.
jet_charset_setup_xbank
        jsr     jet_charset_setup
        jmp     bank_return

; Copies via indirect-indexed addressing (2 zero-page pointer pairs)
; rather than unrolled page-relative LDA/STA pairs - smaller code.
; Borrows $10-$13 (ultimate_sdk.asm's own scratch range) only
; transiently, only during this one-time boot-time copy, well before
; any NETWORK command could possibly be in flight to actually be using
; them. The VIC-II hardwires character ROM at $1000-$1FFF (relative to
; VIC bank 0, which this whole project already assumes) regardless of
; what's written to CPU-visible RAM there, so the custom charset needs
; a genuinely different location - $2800-$2FFF (block 5) is free: not
; zero page/stack/vectors, not screen memory ($0400-$07FF), and past
; the sprite scratch block ($2000, only 64 bytes, used transiently).
;
; Copying the real character ROM requires briefly clearing CHAREN (bit
; 2 of $01) so it's visible at $D000-$D7FF instead of the I/O registers
; ($D000-$DFFF normally shows VIC/SID/CIA/color RAM) - during that
; window the CPU can't see those registers at all, so an IRQ landing
; here and touching any of them would silently corrupt something. SEI
; for the whole copy, same reasoning as every other bank-switch-
; adjacent critical section in this project - safe here specifically
; because this whole routine only ever runs from inside irq_hook's own
; IRQ context (jet_setup's two callers) or menu_open's own (menu_draw_
; title, itself reached via irq_hook's F1 dispatch), both of which
; already have interrupts disabled on entry. No SEI/CLI here (an
; earlier version had one, wrongly copied from other bank-switch-
; adjacent code in this project) - confirmed live as the actual cause
; of a real regression once already (broke keyboard input AND the F1
; menu for the rest of the session, from a single one-time corruption
; event, when an explicit CLI here re-enabled interrupts mid-execution
; before the natural point they should come back on). CHAREN still
; needs protecting from OUR OWN code just below (nothing else should
; touch $D000-$D7FF while it's borrowed for the char ROM view), just
; not via SEI/CLI.
;
; jet_charset_ready (slots.asm) skips the expensive part (the 2KB ROM
; copy + glyph patches) on every call after the first - the $2800 data
; never changes once written, so a later call (JET replaying the flyby,
; or the Cart Menu redrawing its title) only needs to re-point $D018,
; not redo the whole copy.
jet_charset_setup
        lda     jet_charset_ready
        bne     jcs_repoint
        lda     #$01
        sta     jet_charset_ready
        lda     $01
        pha
        and     #$fb        ; clear CHAREN - char ROM visible at $D000
        sta     $01
        lda     #$00
        sta     $10         ; source ptr lo ($D0xx)
        sta     $12         ; dest ptr lo (JET_CHARSET+xx)
        lda     #$d0
        sta     $11         ; source ptr hi
        lda     #>JET_CHARSET
        sta     $13         ; dest ptr hi
        ldx     #$08        ; 8 pages = 2KB
jcs_page_loop
        ldy     #$00
jcs_byte_loop
        lda     ($10),y
        sta     ($12),y
        iny
        bne     jcs_byte_loop
        inc     $11
        inc     $13
        dex
        bne     jcs_page_loop
        pla
        sta     $01         ; CHAREN back on - I/O registers visible again

        ldx     #$00        ; patch the 16 custom bold-letter-half
jcs_patch                     ; glyphs over character codes $80-$8F -
        lda     jet_bold_font,x  ; reverse-video space range, unused
        sta     JET_CHARSET+$400,x  ; anywhere on this boot screen
        inx
        cpx     #128        ; 16 chars x 8 bytes
        bne     jcs_patch

        ldx     #$00        ; patch the copyright-symbol glyph over
jcs_patch_copy                ; character code $b0
        lda     jet_copyright_glyph,x
        sta     JET_CHARSET+($90*8),x
        inx
        cpx     #8
        bne     jcs_patch_copy

        ; Patch $C0-$FF: 64 more glyphs for the F1 Cart Menu's 2x-size
        ; title (jet_bold_font_big, below) - same idea as the two
        ; patches above, just page-spanning (512 bytes instead of a
        ; single page), so it needs the same 16-bit-pointer/page-
        ; counter shape the initial 2KB ROM copy above used, not a
        ; single-page X-indexed loop.
        ; $C0-$FF, not $A0-$DF: every code 128-255 in the real character
        ; ROM is hardwired as the reverse-video mirror of some code
        ; 0-127 (that's literally how REVERSE ON/the blinking cursor
        ; work - no VIC-II reverse bit, just pre-inverted glyph data),
        ; and $A0-$DF collided with reverse-space ($A0, the SELECT:
        ; prompt's blinking cursor sitting on a blank input) and
        ; reverse-digits ($B0-$B9, once one gets typed) - confirmed
        ; live: the cursor showed a fragment of the bold "S" instead of
        ; a normal block. $C0-$FF mirrors screen codes $40-$7F instead
        ; (PETSCII graphics/line-drawing symbols), none of which this
        ; menu's own text ever displays, let alone under the cursor.
        lda     #<jet_bold_font_big
        sta     $10
        lda     #>jet_bold_font_big
        sta     $11
        lda     #<(JET_CHARSET+$600)
        sta     $12
        lda     #>(JET_CHARSET+$600)
        sta     $13
        ldx     #$02        ; 2 pages = 512 bytes
jcs_big_page_loop
        ldy     #$00
jcs_big_byte_loop
        lda     ($10),y
        sta     ($12),y
        iny
        bne     jcs_big_byte_loop
        inc     $11
        inc     $13
        dex
        bne     jcs_big_page_loop

jcs_repoint
        lda     #$1a        ; screen still at $0400 (block 1), charset
        sta     $d018       ; now at $2800 (block 5)
        rts

; 8 unique letters (S H A C K M T E - "SHACKMATE" has two As, sharing
; one glyph pair), each 16x8 bold pixels split into a left-half and
; right-half 8x8 character, in that order, matching resident.asm's
; jet_letters $80-$8F assignments. Designed as simple bold block
; letters (not a pixel-exact match to the ROM font - just legible and
; consistently bold) via scratchpad/gen_boldfont.py, hand-checked as
; ASCII art before encoding.
; Right half of every letter has its rightmost pixel column cleared
; (bit 0) compared to the original solid-block version - a deliberate
; 1px gap so adjacent letters don't visually merge when placed with no
; layout spacing between them (jet_letters/jet_letters_big_top/bot,
; resident.asm/common.asm, poke letters directly adjacent, column by
; column, with no blank column of their own between them). Checked
; against every letter pair in "SHACKMATE": most have a fully solid
; edge column on at least one side (H's left, M's left, T's left, E's
; left, K's left) that would otherwise touch the previous letter's own
; right edge outright. 1px doubles to a 2px gap in jet_bold_font_big
; (below), generated from this same trimmed data.
jet_bold_font
        !byte $7f, $ff, $e0, $7f, $00, $00, $ff, $7f  ; S left
        !byte $fe, $fe, $00, $f8, $7e, $02, $fe, $fe  ; S right
        !byte $f0, $f0, $f0, $ff, $ff, $f0, $f0, $f0  ; H left
        !byte $0e, $0e, $0e, $fe, $fe, $0e, $0e, $0e  ; H right
        !byte $0f, $3f, $79, $f0, $ff, $ff, $f0, $f0  ; A left
        !byte $f0, $fc, $9e, $0e, $fe, $fe, $0e, $0e  ; A right
        !byte $1f, $7f, $f0, $f0, $f0, $f0, $7f, $1f  ; C left
        !byte $f8, $fe, $00, $00, $00, $00, $fe, $f8  ; C right
        !byte $f0, $f0, $f0, $ff, $ff, $f0, $f0, $f0  ; K left
        !byte $3e, $7c, $f8, $c0, $c0, $f8, $7c, $3e  ; K right
        !byte $e0, $f0, $fc, $f7, $f3, $f0, $f0, $f0  ; M left
        !byte $06, $0e, $3e, $ee, $ce, $0e, $0e, $0e  ; M right
        !byte $ff, $ff, $0f, $0f, $0f, $0f, $0f, $0f  ; T left
        !byte $fe, $fe, $c0, $c0, $c0, $c0, $c0, $c0  ; T right
        !byte $ff, $ff, $f0, $ff, $ff, $f0, $ff, $ff  ; E left
        !byte $fe, $fe, $00, $f0, $f0, $00, $fe, $fe  ; E right

; Small circle-C copyright symbol, character code $b0 - single normal-
; width 8x8 glyph (not a left/right pair like the bold font above),
; used once in the copyright line below SHACKMATE.
jet_copyright_glyph
        !byte $7e, $81, $bd, $a1, $a1, $bd, $81, $7e

; Auto-generated by scratchpad/gen_bigfont.py (re-run after jet_bold_
; font's own right-edge trim above) - 2x pixel-doubled version of jet_
; bold_font. 8 letters x 8 quadrants (4 across, 2 down) = 64 chars,
; landing on $C0-$FF once copied to JET_CHARSET (see jet_charset_setup's
; own comment above for why not $A0-$DF). Order per letter: top
; row left-to-right (4 chars), then bottom row left-to-right - matches
; common.asm's jet_letters_big_top/jet_letters_big_bot tables, which
; reference these codes by name.
jet_bold_font_big
        !byte $3f, $3f, $ff, $ff, $fc, $fc, $3f, $3f  ; S code $c0
        !byte $ff, $ff, $ff, $ff, $00, $00, $ff, $ff  ; S code $c1
        !byte $ff, $ff, $ff, $ff, $00, $00, $ff, $ff  ; S code $c2
        !byte $fc, $fc, $fc, $fc, $00, $00, $c0, $c0  ; S code $c3
        !byte $00, $00, $00, $00, $ff, $ff, $3f, $3f  ; S code $c4
        !byte $00, $00, $00, $00, $ff, $ff, $ff, $ff  ; S code $c5
        !byte $3f, $3f, $00, $00, $ff, $ff, $ff, $ff  ; S code $c6
        !byte $fc, $fc, $0c, $0c, $fc, $fc, $fc, $fc  ; S code $c7
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff  ; H code $c8
        !byte $00, $00, $00, $00, $00, $00, $ff, $ff  ; H code $c9
        !byte $00, $00, $00, $00, $00, $00, $ff, $ff  ; H code $ca
        !byte $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc  ; H code $cb
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff  ; H code $cc
        !byte $ff, $ff, $00, $00, $00, $00, $00, $00  ; H code $cd
        !byte $ff, $ff, $00, $00, $00, $00, $00, $00  ; H code $ce
        !byte $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc  ; H code $cf
        !byte $00, $00, $0f, $0f, $3f, $3f, $ff, $ff  ; A code $d0
        !byte $ff, $ff, $ff, $ff, $c3, $c3, $00, $00  ; A code $d1
        !byte $ff, $ff, $ff, $ff, $c3, $c3, $00, $00  ; A code $d2
        !byte $00, $00, $f0, $f0, $fc, $fc, $fc, $fc  ; A code $d3
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff  ; A code $d4
        !byte $ff, $ff, $ff, $ff, $00, $00, $00, $00  ; A code $d5
        !byte $ff, $ff, $ff, $ff, $00, $00, $00, $00  ; A code $d6
        !byte $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc  ; A code $d7
        !byte $03, $03, $3f, $3f, $ff, $ff, $ff, $ff  ; C code $d8
        !byte $ff, $ff, $ff, $ff, $00, $00, $00, $00  ; C code $d9
        !byte $ff, $ff, $ff, $ff, $00, $00, $00, $00  ; C code $da
        !byte $c0, $c0, $fc, $fc, $00, $00, $00, $00  ; C code $db
        !byte $ff, $ff, $ff, $ff, $3f, $3f, $03, $03  ; C code $dc
        !byte $00, $00, $00, $00, $ff, $ff, $ff, $ff  ; C code $dd
        !byte $00, $00, $00, $00, $ff, $ff, $ff, $ff  ; C code $de
        !byte $00, $00, $00, $00, $fc, $fc, $c0, $c0  ; C code $df
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff  ; K code $e0
        !byte $00, $00, $00, $00, $00, $00, $ff, $ff  ; K code $e1
        !byte $0f, $0f, $3f, $3f, $ff, $ff, $f0, $f0  ; K code $e2
        !byte $fc, $fc, $f0, $f0, $c0, $c0, $00, $00  ; K code $e3
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff  ; K code $e4
        !byte $ff, $ff, $00, $00, $00, $00, $00, $00  ; K code $e5
        !byte $f0, $f0, $ff, $ff, $3f, $3f, $0f, $0f  ; K code $e6
        !byte $00, $00, $c0, $c0, $f0, $f0, $fc, $fc  ; K code $e7
        !byte $fc, $fc, $ff, $ff, $ff, $ff, $ff, $ff  ; M code $e8
        !byte $00, $00, $00, $00, $f0, $f0, $3f, $3f  ; M code $e9
        !byte $00, $00, $00, $00, $0f, $0f, $fc, $fc  ; M code $ea
        !byte $3c, $3c, $fc, $fc, $fc, $fc, $fc, $fc  ; M code $eb
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff  ; M code $ec
        !byte $0f, $0f, $00, $00, $00, $00, $00, $00  ; M code $ed
        !byte $f0, $f0, $00, $00, $00, $00, $00, $00  ; M code $ee
        !byte $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc  ; M code $ef
        !byte $ff, $ff, $ff, $ff, $00, $00, $00, $00  ; T code $f0
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff  ; T code $f1
        !byte $ff, $ff, $ff, $ff, $f0, $f0, $f0, $f0  ; T code $f2
        !byte $fc, $fc, $fc, $fc, $00, $00, $00, $00  ; T code $f3
        !byte $00, $00, $00, $00, $00, $00, $00, $00  ; T code $f4
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff  ; T code $f5
        !byte $f0, $f0, $f0, $f0, $f0, $f0, $f0, $f0  ; T code $f6
        !byte $00, $00, $00, $00, $00, $00, $00, $00  ; T code $f7
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff  ; E code $f8
        !byte $ff, $ff, $ff, $ff, $00, $00, $ff, $ff  ; E code $f9
        !byte $ff, $ff, $ff, $ff, $00, $00, $ff, $ff  ; E code $fa
        !byte $fc, $fc, $fc, $fc, $00, $00, $00, $00  ; E code $fb
        !byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff  ; E code $fc
        !byte $ff, $ff, $00, $00, $ff, $ff, $ff, $ff  ; E code $fd
        !byte $ff, $ff, $00, $00, $ff, $ff, $ff, $ff  ; E code $fe
        !byte $00, $00, $00, $00, $fc, $fc, $fc, $fc  ; E code $ff

; The F1 Cart Menu itself - menu_open, menu_draw_title (jet_charset_
; setup's other, same-bank caller), all submenus, and everything else
; that used to be !source'd from bank0_content.asm. Brings in features.
; asm/bitmap.asm/spriteeditor.asm transitively (common.asm !source's
; them itself).
!source "common.asm"
