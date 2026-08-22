; ============================================================
; SHACKMATE Cartridge Lab - disk boot splash / chain-loader
; ============================================================
; Standalone disk program, first file on the boot disk (autostarts via
; LOAD"*",8,1). Shows a splash screen - including a static copy of the
; same bold "SHACKMATE" lettering the cartridge's own boot animation
; reveals (jet_bold_font/jet_copyright_glyph, bank14_content.asm - just
; the raw character-bitmap DATA, none of the fly-in/fade/IRQ animation
; logic that data feeds on the cartridge side, which is deeply tied
; into that build's own resident kernel and not something a plain disk
; program can use directly) - then chain-loads and runs CARTLAB.
;
; Chain-load technique: a direct KERNAL LOAD ($FFD5) call, not a BASIC
; "LOAD" statement - confirmed live that the BASIC-statement approach
; (line 20 "LOAD"CARTLAB",8,1", auto-running once loaded - the
; standard C64 chain-load trick) leaves BASIC's own "SEARCHING FOR/
; LOADING/READY." status text sitting on screen (BASIC's own command
; interpreter prints that, wrapping the KERNAL call - the KERNAL
; routine itself never does), which broke the point of a splash screen
; the user wanted to STAY on screen with no gap before CARTLAB's own
; menu appears. Calling $FFD5 directly bypasses BASIC's interpreter
; entirely, so nothing prints and the splash is undisturbed right up
; until CARTLAB's own first instruction (a screen clear) runs.
;
; This does bring back the exact risk the old BASIC-statement approach
; was chosen to avoid: this program's own code lives at $0801+, the
; SAME range CARTLAB's incoming bytes will overwrite as they arrive -
; if the code doing the loading (and the JMP into CARTLAB afterward)
; lived there too, it would overwrite ITSELF mid-load and crash. Fixed
; with a small trampoline (boot_trampoline_src below) that gets copied
; to $C000 - safe, plain RAM on a stock C64 regardless of CHAREN, and
; well outside CARTLAB's own $0801-load range - then run FROM THERE,
; so the actual LOAD call and the JMP $0810 after it are never at risk
; of being overwritten by the very data they're loading. $0810 is
; CARTLAB's own machine-code entry (cartlab.asm's own "start" label) -
; that file carries a matching build-time guard confirming "start" is
; genuinely the first byte there, since jumping in via secondary
; address 1 (use the file's own embedded load address) rather than
; through its BASIC stub means nothing else double-checks that at
; runtime the way a normal SYS call chain would.
; ============================================================

; --- BASIC stub - single tokenized line, "10 SYS2061". Computed by
; hand against the real BASIC token value (SYS=$9E) the same way
; cartlab.asm's own stub is:
;   line 10 record: next-line-ptr($0B,$08) line#(10=$0A,$00)
;                    $9E "2061" $00                        = 12 bytes
;   end-of-program marker: $00,$00
; Total BASIC area: $0801-$080C (12 bytes); machine code starts at
; $080D (2061 decimal) - matches the SYS target above.
*=$0801
        !byte $0b,$08, $0a,$00, $9e,$32,$30,$36,$31, $00
        !byte $00,$00

*=$080d

CHROUT = $ffd2
KERNAL_SETNAM = $ffbd
KERNAL_SETLFS = $ffba
KERNAL_LOAD   = $ffd5

boot_start
; --- Char ROM -> RAM copy + bold-font/copyright-glyph patch, same
; technique as bank14_content.asm's own jet_charset_setup (that file's
; own comment explains the CHAREN dance and the $80-$8F/$90 patch
; targets - this is a standalone copy since this program shares no
; bank/memory with the cartridge build). $2800 chosen to match that
; same file's own JET_CHARSET address - arbitrary here (this program
; has the whole $0000-$3FFF VIC bank to itself), kept identical purely
; so anyone cross-referencing the cartridge's own code recognizes it.
;
; SEI/CLI around the CHAREN-cleared window below is NOT part of the
; original jet_charset_setup - added here after this exact hang was
; confirmed live. Clearing CHAREN maps character ROM over the ENTIRE
; $D000-$DFFF window, which includes CIA1 at $DC00 - if the stock
; KERNAL's own 60Hz IRQ fires during this copy (nothing here disables
; interrupts otherwise), it tries to acknowledge its CIA1 timer via a
; register that's momentarily character-ROM data instead, never clears
; the real interrupt source, and the CPU re-enters the same broken IRQ
; forever - a permanent hang with no visible symptom (the screen simply
; never advances past whatever it last showed). The cartridge's own
; jet_charset_setup gets away without this because that build's whole
; boot sequence/interrupt setup is fundamentally different (its own
; resident kernel, not the stock KERNAL IRQ this plain disk program
; runs under) - not a case of "the original omitted this safely",
; genuinely a different context. ---
        sei
        lda     $01
        pha
        and     #$fb        ; clear CHAREN - char ROM visible at $D000
        sta     $01
        lda     #$00
        sta     $fb         ; source ptr lo ($D0xx) - zero page scratch,
        sta     $fd           ; safe: nothing else running yet
        lda     #$d0
        sta     $fc         ; source ptr hi
        lda     #$28
        sta     $fe         ; dest ptr hi ($2800)
        ldx     #$08        ; 8 pages = 2KB
bcs_page_loop
        ldy     #$00
bcs_byte_loop
        lda     ($fb),y
        sta     ($fd),y
        iny
        bne     bcs_byte_loop
        inc     $fc
        inc     $fe
        dex
        bne     bcs_page_loop
        pla
        sta     $01         ; CHAREN back on - I/O registers visible again
        cli

        ldx     #$00        ; patch the 16 custom bold-letter-half
bcs_patch                     ; glyphs over character codes $80-$8F
        lda     jet_bold_font,x
        sta     $2c00,x     ; $2800 + $400 (code $80 * 8)
        inx
        cpx     #128
        bne     bcs_patch

        ldx     #$00        ; patch the copyright-symbol glyph over
bcs_patch_copy                ; character code $90
        lda     jet_copyright_glyph,x
        sta     $2c80,x     ; $2800 + $90*8
        inx
        cpx     #8
        bne     bcs_patch_copy

        lda     #$1a        ; screen $0400 (block 1), charset $2800
        sta     $d018         ; (block 5)
        lda     #$00        ; black border/background - matches CARTLAB's
        sta     $d020         ; own look (cartlab_charset_setup does the
        sta     $d021         ; same), instead of the default blue

; --- Clear screen, print the plain-text rows via ordinary CHROUT
; (safe for standard PETSCII text), poke the two custom-glyph rows
; (SHACKMATE/copyright) directly to screen+color RAM - see this file's
; own header comment on why CHROUT/PRINT can't be trusted with raw
; codes $80-$8F/$90 (PETSCII-to-screen-code translation would remap
; them to something else entirely). ---
        lda     #$93        ; clear screen
        jsr     CHROUT
        lda     #$05        ; white
        jsr     CHROUT
        ldx     #$00
bs_border1
        lda     border_txt,x
        beq     bs_border1_done
        jsr     CHROUT
        inx
        bne     bs_border1
bs_border1_done
        lda     #$0d
        jsr     CHROUT      ; row 0 done, cursor -> row 1
        jsr     CHROUT      ; blank row 1, cursor -> row 2
        jsr     CHROUT      ; row 2 reserved for SHACKMATE (poked below),
                               ; cursor -> row 3
        jsr     CHROUT      ; blank row 3 - breathing room between the
                               ; logo and the copyright line below it
                               ; (confirmed live: no gap read as smashed
                               ; together), cursor -> row 4
        jsr     CHROUT      ; row 4 reserved for copyright (poked below),
                               ; cursor -> row 5
        jsr     CHROUT      ; blank row 5, cursor -> row 6
        ldx     #$00
bs_tools
        lda     tools_txt,x
        beq     bs_tools_done
        jsr     CHROUT
        inx
        bne     bs_tools
bs_tools_done
        lda     #$0d
        jsr     CHROUT      ; row 5 done, cursor -> row 6
        jsr     CHROUT      ; blank row 6, cursor -> row 7
        ldx     #$00
bs_loading
        lda     loading_txt,x
        beq     bs_loading_done
        jsr     CHROUT
        inx
        bne     bs_loading
bs_loading_done
        lda     #$0d
        jsr     CHROUT      ; row 7 done, cursor -> row 8
        jsr     CHROUT      ; blank row 8, cursor -> row 9
        ldx     #$00
bs_border2
        lda     border_txt,x
        beq     bs_border2_done
        jsr     CHROUT
        inx
        bne     bs_border2
bs_border2_done
        lda     #$0d
        jsr     CHROUT

; --- SHACKMATE, row 2, columns 11-28 (18 cols, centered: (40-18)/2=
; 11 - same placement bank0_content.asm's own tower_anim_start uses).
; sm_colors is a fixed, deliberately-chosen palette (not a port of the
; cartridge's own reveal, which picks essentially at random off
; raster-line timing - there's no single "real" color per letter to
; match). ---
        ldx     #$00
sm_loop
        lda     jet_letters,x
        sta     $045b,x     ; $0400 + 2*40+11
        lda     sm_colors,x
        sta     $d85b,x     ; $d800 + 2*40+11
        inx
        cpx     #18
        bne     sm_loop

; --- Copyright line, row 4, columns 9-30 (22 cols, centered:
; (40-22)/2=9 - same column resident.asm's own JET_COPY_SCREEN uses,
; one row lower than that file's own row 3 so it isn't sitting right
; up against the SHACKMATE logo above it - confirmed live. ---
        ldx     #$00
cp_loop
        lda     copyright_txt,x
        sta     $04a9,x     ; $0400 + 4*40+9
        lda     #$01        ; white
        sta     $d8a9,x     ; $d800 + 4*40+9
        inx
        cpx     #22
        bne     cp_loop

; --- Hold the splash on screen briefly before chain-loading - long
; enough to actually read it, short enough not to feel like a stall.
; Plain nested busy-wait (not the jiffy-clock/$A2 approach) so there's
; no wraparound edge case to get wrong for a one-shot boot delay. ---
        ldx     #$03
bd_outer
        ldy     #$00
bd_mid
        lda     #$00
bd_inner
        sec
        sbc     #$01
        bne     bd_inner
        dey
        bne     bd_mid
        dex
        bne     bd_outer

; --- Copy the trampoline (code+filename, see its own comment below)
; to safe memory and jump there - see this file's own header comment
; for why this whole indirection exists. No screen clear and no
; charset revert here any more: CARTLAB's own "start" does its own
; screen clear and sets up its own (identical) custom charset as its
; very first action, so the splash now stays completely undisturbed
; right up until that happens - confirmed live as the actual goal
; ("keep the boot screen up until CARTLAB's menu appears"), which the
; old clear+revert+BASIC-LOAD approach here couldn't deliver. ---
        ldy     #$00
tramp_copy_loop
        lda     boot_trampoline_src,y
        sta     TRAMP_BASE,y
        iny
        cpy     #(boot_trampoline_end-boot_trampoline_src)
        bne     tramp_copy_loop
        jmp     TRAMP_BASE

; --- Trampoline: opens/loads CARTLAB directly via the KERNAL LOAD
; vector (bypassing BASIC's own command interpreter, which is what
; prints the "SEARCHING FOR/LOADING/READY." text a plain BASIC LOAD
; statement can't avoid), then jumps straight into its machine-code
; entry point. Copied verbatim to TRAMP_BASE ($C000 - ordinary RAM
; regardless of CHAREN, and well clear of CARTLAB's own $0801+ load
; range) before running, since CARTLAB's incoming bytes will overwrite
; this code's ORIGINAL location (wherever ACME assembled it below,
; within this program's own $0801+ range) while this trampoline is
; still using it - assembled at its normal address like everything
; else in this file, but every address IT OWN CODE references is
; computed relative to TRAMP_BASE (not its own assembled address), so
; it still works correctly once relocated there. Device number comes
; from $BA (KERNAL's own "last used device" byte, already set to
; whatever this program itself was loaded from by the time it's
; running) rather than a hardcoded 8, matching cartlab.asm's own dv_num
; default. Secondary address 1 in SETLFS means "use the file's own
; embedded 2-byte load address" (CARTLAB's own header specifies
; $0801), same as a plain "LOAD"CARTLAB",8,1" would. ---
TRAMP_BASE = $c000
boot_trampoline_src
        lda     #7
        ldx     #<(TRAMP_BASE+tramp_fn-boot_trampoline_src)
        ldy     #>(TRAMP_BASE+tramp_fn-boot_trampoline_src)
        jsr     KERNAL_SETNAM
        lda     #1          ; logical file number
        ldx     $ba         ; device - KERNAL's own last-used-device byte
        ldy     #1          ; secondary address 1 - use CARTLAB's own
        jsr     KERNAL_SETLFS ; embedded load address, not X/Y below
        lda     #0          ; 0 = LOAD (not verify)
        jsr     KERNAL_LOAD
        jmp     $0810       ; CARTLAB's own machine-code entry point
                               ; (cartlab.asm's own "start" - that file
                               ; carries its own build-time guard
                               ; confirming this address is correct)
tramp_fn
        !text "CARTLAB"
boot_trampoline_end

border_txt
        !text "========================================"
        !byte $00
tools_txt
        !text "      EPROM / FLASH / CART TOOLS"
        !byte $00
loading_txt
        !text "           LOADING CARTLAB..."
        !byte $00

; Character-code PAIRS (left half, right half) for "SHACKMATE", left
; to right - identical to resident.asm's own jet_letters table (same
; codes, same order, same jet_bold_font this file patched in above).
jet_letters
        !byte $80, $81   ; S
        !byte $82, $83   ; H
        !byte $84, $85   ; A
        !byte $86, $87   ; C
        !byte $88, $89   ; K
        !byte $8a, $8b   ; M
        !byte $84, $85   ; A
        !byte $8c, $8d   ; T
        !byte $8e, $8f   ; E

; Per-half-character color, matching jet_letters 1-for-1 (18 entries -
; both halves of a letter always share one color). 10=light red (S/H),
; 4=purple (A/K), 13=light green (C), 1=white (M/A/T/E) - a fixed
; approximation of the reference screenshot's own look, not a pixel-
; exact match (see this section's own header comment on why there's no
; single "correct" answer to match against).
sm_colors
        !byte 10, 10       ; S
        !byte 10, 10       ; H
        !byte 4, 4         ; A
        !byte 13, 13       ; C
        !byte 4, 4         ; K
        !byte 1, 1         ; M
        !byte 1, 1         ; A
        !byte 1, 1         ; T
        !byte 1, 1         ; E

; "(c) 2026 - N4LDR & WD4VA" - identical to resident.asm's own jet_
; copyright_text (screen codes, not ASCII - see that table's own
; comment for the character-by-character breakdown).
copyright_txt
        !byte $90, $20, $32, $30, $32, $36, $20, $2d, $20
        !byte $0e, $34, $0c, $04, $12, $20, $26, $20
        !byte $17, $04, $34, $16, $01

; 8 unique letters (S H A C K M T E), each 16x8 bold pixels split into
; a left-half/right-half 8x8 character pair - verbatim copy of bank14_
; content.asm's own jet_bold_font (see that file's own header comment
; for the design notes/generation process). Static data only; none of
; the reveal/fade logic that consumes it on the cartridge side.
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

; Small circle-C copyright symbol, character code $90 here (see this
; file's own bcs_patch_copy comment) - verbatim copy of bank14_
; content.asm's own jet_copyright_glyph.
jet_copyright_glyph
        !byte $7e, $81, $bd, $a1, $a1, $bd, $81, $7e
