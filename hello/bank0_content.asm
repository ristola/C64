; Bank 0 content: Boot only - cart_start and the boot splash (jet_setup/
; tower_anim_start/JetCmd/jet_sprite). The F1 Cart Menu (menu_open and
; everything under it - common.asm, and features.asm/bitmap.asm/
; spriteeditor.asm which common.asm itself !source's) used to live here
; too ("nothing leaves Bank 0's own address space", a leftover from
; porting the original single-bank design), but Bank 0 filled up
; completely - twice - as menu features kept growing (first the 2x-size
; title's glyph data, then the EXIT item + selection-pointer cursor),
; and there's more menu work still to come. Rather than keep rescuing
; one oversized piece into an ad-hoc home each time it happened again,
; the whole menu moved out to Bank 14, leaving Bank 0 with just what
; actually has to run at hardware reset or during the boot-time flyby -
; see slots.asm's SLOT_JET_CHARSET_SETUP comment and bank14_content.
; asm's own header for the rest of the story. jet_charset_setup itself
; (the character-ROM copy the flyby's bold lettering needs) moved to
; Bank 14 too, since menu_draw_title (common.asm) is its other caller -
; jet_setup below now reaches it via a nested bank_call instead of a
; plain JSR.
;
; irq_hook/read_f1/zp_save/zp_restore/save_screen/restore_screen and
; the BASIC-extension dispatcher live in resident.asm, since those
; have to work regardless of which bank happens to be switched in -
; see resident.asm for why.

; --- Cartridge autostart header ---
; KERNAL reset routine looks for "CBM80" at $8004 and, if found, jumps
; indirectly through the cold-start vector below instead of booting BASIC.
; (Reached here via romh_boot.asm's bridge from EasyFlash's forced
; Ultimax boot back to this normal KERNAL autostart path - see that
; file for why that's needed at all.)
!word cart_start     ; cold-start vector
!word nmi_safe       ; NMI vector - NOT cart_start (see nmi_safe's comment
                       ; for why that crashed every RESTORE press)
!byte $c3,$c2,$cd,$38,$30  ; "CBM80" autostart signature (KERNAL checks
                            ; these exact bytes, not plain ASCII "CBM80")

; RESTORE (alone, no RUN/STOP) fires a real 6502 NMI - unlike IRQ, this
; can't be masked with SEI and fires no matter what's running. Verified
; against the real KERNAL NMI-entry disassembly ($FE43/$FE47): it PHAs
; A, TXA/PHA, TYA/PHA (in that order), checks CIA2 for the actual NMI
; source, and - for the RESTORE-key/autostart-scan path - does a plain
; "JMP ($8002)" straight into whatever this header declares, no RTI of
; its own. That word used to just repeat cart_start, meaning every
; single RESTORE press re-ran full cold boot (RAMTAS memory test,
; reinstalling the F1 IRQ hook, JMP straight into BASIC's own cold
; start again) - non-maskably, from literally any point in whatever was
; running, including mid-IRQ. That's the reported "RESTORE crashes
; BASIC": cart_start never RTIs, so NMI's own hardware-pushed PC/P (and
; the 3 bytes above, A/X/Y) just pile up unbalanced on the stack every
; time, on top of a mid-flight RAMTAS wipe of whatever real memory the
; running program depended on.
;
; Fix: unwind exactly what $FE47 pushed (Y first - it was pushed last -
; then X, then A) and RTI normally, same as a real NMI service routine
; that has nothing to do. Makes RESTORE alone an inert no-op while this
; cart is active, matching how plenty of real commercial carts
; deliberately disable it rather than risk a mid-execution reinit.
;
; Lives in resident.asm, not here, despite the header word above
; pointing straight at it from bank 0's own ROM - $0318/$0319 (below)
; point at it directly too, unconditionally, bypassing the header/$FD02
; check entirely (see that hookup's own comment for why), so it has to
; be reachable no matter which bank happens to be switched in when NMI
; fires - the exact same reasoning irq_hook itself already follows.
; This label reference still resolves correctly from here since
; bank_driver.asm assembles this file and resident.asm as one unit.

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
; No SLOT_MENU_OPEN entry any more - menu_open lives in Bank 14 now
; (see this file's own header comment); irq_hook (resident.asm)
; bank_calls there directly instead of through here.
!fill SLOT_TOWER_ANIM_START-*, $ff
        jmp     tower_anim_start
!fill SLOT_JET-*, $ff
        jmp     JetCmd
!fill SLOT_REBOOT-*, $ff
        jmp     RebootCmd

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in - keeps it available for later
; slots without ever having to relocate cart_start.
!fill BANK_CONTENT_START-*, $ff

*=BANK_CONTENT_START
cart_start
; The cart-autostart check happens right at the top of the KERNAL's reset
; routine — before it initializes the VIC-II/screen editor, CIA/IRQ timers,
; or re-enables interrupts (SEI is still in effect here). Replicate the same
; init calls the KERNAL would normally do before jumping to BASIC, so KERNAL
; text output ($FFD2) and the jiffy clock (used by our delay loop) both work.
        ldx     #$ff
        stx     $d016       ; standard VIC-II init (matches normal boot)
        jsr     $fda3       ; IOINIT - init CIA/SID
        jsr     $fd50       ; RAMTAS - memory test & pointer setup
        jsr     $fd15       ; RESTOR - restore default IRQ/vectors
        jsr     $ff5b       ; CINT  - init screen editor & VIC-II text mode

; Wedge our F1 watcher into the jiffy IRQ chain (RESTOR just reset this
; vector to its default $EA31, so install ours after RESTOR, before CLI —
; otherwise a jiffy IRQ could land mid-write, with the vector pointing
; half at $EA31 and half at irq_hook).
        lda     #<irq_hook
        sta     $0314
        lda     #>irq_hook
        sta     $0315

; Point the REAL NMI vector ($0318/$0319, also just reset to its KERNAL
; default by RESTOR above) straight at nmi_safe, instead of leaving it at
; that default. The header's own $8002/$8003 "NMI vector" is NOT this -
; it's only consulted by the real KERNAL's default $0318 handler ($FE47),
; which re-checks the CBM80 signature at $8004 via $FD02 every single
; time an NMI fires, live, and only redirects through $8002 if that
; check currently succeeds. Since NMI (unlike IRQ) can't be masked by
; SEI, it can land at literally any instruction boundary, including mid-
; bank_call while some OTHER bank (1, 5, 11, ...) is switched in for an
; ordinary command like HELP or DEC$ - at that instant $8004 holds
; whatever that bank's own ROM starts with, not "CBM80", so the check
; fails and NMI falls straight through to the real, destructive RESTORE-
; key handler (RESTOR/IOINIT/VIC-II color-table reinit) instead of our
; safe stub - confirmed live via VICE: a watchpoint on $D020/$D021 (the
; border/background color registers) caught this exact sequence writing
; the KERNAL's own default blue/light-blue palette mid-session, with the
; hardware NMI vector ($FFFA) confirmed unmodified (still $FE43, as it
; always is - real KERNAL ROM, not ours to change) and the call chain
; traced stack-to-disassembly through $FE66 (RESTOR) -> $FE69 (IOINIT)
; -> $FE6C (color table copy, where the watch fired) -> $A002 (BASIC's
; own warm-start vector) - this is the actual, long-chased "screen
; resets to stock colors" bug, not a zero-page/TEMPST issue after all.
; Bypassing the header/$FD02 check entirely here removes the dependency
; on which bank happens to be active when NMI fires.
        lda     #<nmi_safe
        sta     $0318
        lda     #>nmi_safe
        sta     $0319

        lda     #$00
        sta     f1_state
        sta     cur_bank    ; hardware always resets with bank 0 selected -
                             ; keep the RAM shadow in sync from the start
        sta     bank_call_depth  ; RAM's power-on value is undefined - a
                                   ; stale nonzero byte here would freeze
                                   ; the jet animation/F1 menu forever,
                                   ; the exact symptom this counter itself
                                   ; was added to fix
        sta     jet_charset_ready  ; jet_charset_setup (bank 14) sets
                                     ; this itself once its copy completes
        lda     #1
        sta     fastload_enabled  ; FASTLOAD defaults to ON every power
                                    ; cycle/REBOOT - see slots.asm's own
                                    ; comment on why this doesn't persist
        sta     $09          ; menu_cursor (common.asm) - literal, not
                               ; the symbol; see its own comment for why.
                               ; Top-level Cart Menu's selection pointer
                               ; defaults to item 1 - only set here,
                               ; once; see that comment for how it stays
                               ; at 1 on every
                               ; subsequent F1 press without needing to
                               ; be reset again
        lda     #8
        sta     disk_device ; DISK category's default device number

; Copy the bank-switch trampoline into RAM at $0380 - see slots.asm's
; ram_bank_switch and resident.asm's ram_bank_switch_template for why
; the actual $DE00 write has to execute from RAM, not from ROM-resident
; code living inside the very $8000-$9FFF window it switches.
        ldx     #$00
cart_copy_trampoline
        lda     ram_bank_switch_template,x
        sta     ram_bank_switch,x
        inx
        cpx     #ram_bank_switch_template_end-ram_bank_switch_template
        bne     cart_copy_trampoline

; Do the jet-flyby charset's one-time 2KB ROM copy right here, while
; interrupts are still off, instead of lazily on the animation's first
; jiffy tick (the old approach - jet_setup calling this from inside
; irq_hook). That copy clears CHAREN for its whole duration (exposing
; character ROM at $D000, hiding CIA1's keyboard-matrix registers along
; with everything else normally there), and takes long enough (2048
; byte-copies) to run past a full jiffy tick period - confirmed live
; that doing this from inside the IRQ was corrupting the very next
; keyboard scan afterward: RETURN specifically stopped being recognized
; as end-of-line (screen editor kept treating the line as still open)
; until a throwaway keystroke was typed first. Doing the copy here,
; before CLI, means it's not competing with any jiffy IRQ at all - there
; isn't one running yet. jet_charset_setup itself sets jet_charset_ready
; when it finishes, so jet_setup's own later call (from the real
; animation start) just takes the cheap $D018-repoint path.
;
; bank_call, not a plain JSR - jet_charset_setup lives in Bank 14 now
; (slots.asm's SLOT_JET_CHARSET_SETUP comment has the full story).
; Safe to nest this early: cur_bank/bank_call_depth are already
; initialized above, interrupts don't need to be on for bank_call
; itself to work, and jet_charset_setup_xbank's own bank_return leaves
; cur_bank back at 0 before this continues.
        lda     #<SLOT_JET_CHARSET_SETUP
        sta     call_ptr
        lda     #>SLOT_JET_CHARSET_SETUP
        sta     call_ptr+1
        lda     #14             ; Bank 14
        jsr     bank_call

        cli                 ; re-enable interrupts (delay loop needs the jiffy clock)

; No splash screen - straight on to BASIC below. Just a clean black
; screen (matches the look while the KERNAL init calls above ran with
; interrupts still off) rather than whatever garbage happened to be in
; screen RAM. The broadcast-tower icon sprite (echoing the SHACKMATE
; badge artwork) appears later - it's started from resident.asm's
; irq_hook shortly after BASIC's cold start below has settled, so it
; bounces around over the live READY prompt - see tower_anim_start for
; why (BASIC cold start clobbers RAM vectors, so anything wanting to
; survive it has to be re-armed after, the same reasoning
; basic_ext_countdown below already follows). F1 still opens the
; interactive menu afterward via irq_hook as usual.
        lda     #$00
        sta     $d020
        sta     $d021
        lda     #$93
        jsr     $ffd2

; Arm the BASIC-extension countdown right here, right before the jump -
; interrupts (and so irq_hook's countdown) have been running since the
; CLI above, so setting this any earlier risks it reaching 0 and firing
; before BASIC's cold start below even runs, which then clobbers our
; freshly-installed vectors right back to stock as part of its own
; RAM-vector init, so neither CLS nor HEX ever survived to see a
; keystroke. Setting it fresh right before the jump means BASIC's cold
; start (a quick banner print) has long finished by the time it counts
; down again.
        lda     #30
        sta     basic_ext_countdown

; Hand off to BASIC's own cold start exactly like the KERNAL reset
; routine would if it hadn't found a CBM80 signature at all: JSR
; $FDA3/$FD50/$FD15/$FF5B, CLI, JMP ($A000), verified against the real
; KERNAL disassembly at $FCE2-$FCFF. $A000/$A001 hold a vector (not code
; to run directly - JMP $A000 instead of JMP ($A000) executes BASIC
; ROM's raw header bytes as instructions and hangs), which point at
; BASIC's actual cold-start routine - prints the
; "**** COMMODORE 64 BASIC ****" banner and drops into READY. This makes
; the cart transparent from here on: irq_hook (resident.asm) stays
; resident and watches for F1.
        jmp     ($a000)

; --- Boot splash jet-flyby one-time setup - relocated here from
; resident.asm (see slots.asm's SLOT_TOWER_ANIM_START comment for why:
; resident.asm's 2KB budget couldn't hold this once the animation grew
; past the old bouncing-icon version). Reached via bank_call from
; irq_hook, so - unlike the old plain-JSR tower_anim_start - this must
; end via bank_return (RTS-based), not a bare RTS. jet_anim_tick and
; everything it needs on a PER-TICK basis (when cur_bank could be
; anything) still lives in resident.asm; only this one-time init moved.
; Row 11, columns 11-28 (18 cols, centered: (40-18)/2=11) - vertically
; near the middle of the 25-row screen ("fly across the center of the
; page"), well clear of both the boot banner (rows 0-3) and the
; copyright line below it (row 13).
JET_TEXT_SCREEN = $05c3        ; $0400 + 11*40 + 11
JET_TEXT_COLOR  = $d9c3        ; $d800 + 11*40 + 11

; Row 13, columns 9-30 (22 chars, centered: (40-22)/2=9) - one blank
; row below SHACKMATE for spacing. Static, not part of the reveal/fade
; animation - printed once here and erased once in irq_hook alongside
; jet_charset_revert.
JET_COPY_SCREEN = $0611        ; $0400 + 13*40 + 9
JET_COPY_COLOR  = $da11        ; $d800 + 13*40 + 9
JET_COPY_LEN    = 22

; ~214 jiffies, split: fly+reveal+exit (127 ticks - the jet keeps
; flying and reveals its trail the whole time it crosses the visible
; area, then continues another beat to carry itself fully off the
; right edge instead of just vanishing - see jat_fly's MSB handling),
; a short hold (30 ticks), then the fade wipe. JET_FADE_TICKS is 9
; letters x 7 ticks/letter, not 6 - the fade subtick sequence actually
; takes 7 calls to reach its own erase step (0,1,2,3,4,5,6 - confirmed
; live: budgeting 6 left the last couple of letters permanently
; stuck mid-fade, never actually erased).
JET_FLY_TICKS   = 127
JET_HOLD_TICKS  = 30
JET_FADE_TICKS  = 63
JET_TOTAL_TICKS = JET_FLY_TICKS + JET_HOLD_TICKS + JET_FADE_TICKS
; No JET_CHARSET here any more - only jet_charset_setup ever referenced
; it, and that moved to Bank 14 along with the constant's own copy.

; Reached two ways now: once automatically at boot (tower_anim_start,
; bank_call'd from irq_hook, ending via bank_return) and on demand via
; the JET BASIC command (JetCmd, bank_call'd from OkExt/resident.asm's
; command dispatch, ending via bank_return_basic instead - a command
; resumes BASIC's statement loop directly, it doesn't RTS back to a
; JSR the way a bank_call'd-from-IRQ routine does). Both wrap this
; same setup work rather than one calling the other through ANOTHER
; layer of bank_call, which would double up (and mismatch) the bank-
; restore stack byte each expects. Safe to run again mid-session (JET
; while a flyby is already in progress just restarts it cleanly) and
; safe from the same CHAREN-copy reentrancy concern jet_charset_setup's
; own comment already covers - OkExt already holds SEI for JetCmd's
; whole visit, same as irq_hook's own IRQ context already does for
; tower_anim_start's.
jet_setup
        ldx     #$00
tas_copy_sprite
        lda     jet_sprite,x
        sta     $2000,x     ; same scratch block feat_graphics_demo/the
        inx                  ; sprite editor use transiently - nothing
        cpx     #63          ; else touches it this soon after boot
        bne     tas_copy_sprite

; bank_call into Bank 14 - see cart_start's own identical call for why
; (jet_charset_setup moved there). Nested one level deeper here than
; cart_start's own call: tower_anim_start/JetCmd already reached this
; bank via their own bank_call from irq_hook/OkExt before jet_setup
; (this routine) runs - explicitly supported, see bank_call's own
; bank_call_depth comment (resident.asm).
        lda     #<SLOT_JET_CHARSET_SETUP
        sta     call_ptr
        lda     #>SLOT_JET_CHARSET_SETUP
        sta     call_ptr+1
        lda     #14             ; Bank 14
        jsr     bank_call

        ldx     #$00        ; blank the SHACKMATE text row before the
tas_clear_text                ; jet has painted anything into it - 18
        lda     #$20        ; bytes now (2 columns/letter, bold font)
        sta     JET_TEXT_SCREEN,x
        inx
        cpx     #18
        bne     tas_clear_text

        ldx     #$00        ; blank the copyright row too - it reveals
tas_clear_copy                ; progressively during the flyby now,
        lda     #$20        ; same as the SHACKMATE row (see resident.
        sta     JET_COPY_SCREEN,x  ; asm's jet_copy_reveal_char)
        inx
        cpx     #JET_COPY_LEN
        bne     tas_clear_copy

        lda     #$80        ; block 128 = $2000/64
        sta     $07f8       ; sprite 0 data pointer
        lda     #20
        sta     $d000       ; sprite 0 X - starts just past the left edge
        sta     tower_x     ; (jet's current X - see jet_anim_tick)
        lda     #$00
        sta     jet_x_hi    ; sprite X MSB - see jat_fly
        sta     $d010
        lda     #121
        sta     $d001       ; sprite 0 Y - vertically centered on row
        sta     tower_y     ; 11's text (see JET_TEXT_SCREEN's comment)
        lda     #$01        ; white - shared multicolor 1 (fuselage/
        sta     $d025       ; wings). Shared by every multicolor sprite,
                              ; not just this one - harmless here since
                              ; sprite 0 is the only sprite active this
                              ; early in boot
        lda     #$02        ; red - shared multicolor 2 (tail fin)
        sta     $d026
        lda     #$0e        ; light blue - sprite 0's own color (cockpit
        sta     $d027       ; window)
        lda     #$00
        sta     jet_reveal_idx
        sta     jet_fade_idx
        sta     jet_fade_subtick
        sta     jet_copy_reveal_idx
        sta     jet_copy_fade_pos
        lda     #$01
        sta     $d01c       ; sprite 0 = multicolor mode (bit 0) - the
                              ; sprite data below is 2-bit/pixel, wrong
                              ; colors (and only half as wide) without
                              ; this
        sta     $d015       ; enable sprite 0
        sta     $d017       ; 2x Y-expand
        sta     $d01d       ; 2x X-expand - multicolor pixels are
                              ; already double-wide, so this makes the
                              ; on-screen sprite 48x42
        lda     #JET_TOTAL_TICKS
        sta     tower_anim_ticks
        rts

; Thin bank_call-convention wrapper around jet_setup, for irq_hook's
; one-time boot invocation.
tower_anim_start
        jsr     jet_setup
        jmp     bank_return

; JET command - replays the flyby on demand. Thin bank_return_basic-
; convention wrapper around the same jet_setup, for BASIC's own
; command dispatch (OkExt/resident.asm).
JetCmd
        lda     #$93        ; clear screen first - unlike the automatic
        jsr     $ffd2       ; boot-time trigger (which already starts on
                              ; a freshly-cleared screen), JET typed on
                              ; demand could be run over an arbitrary
                              ; screen full of program listing/output
        jsr     jet_setup
        jmp     bank_return_basic

; REBOOT command - a real hardware reset (same as the F1 menu's own
; "reset" option, common.asm's menu_reset), not a soft/partial clear.
; Never returns through bank_return_basic - the reset vector takes over
; permanently, re-running romh_boot.asm's CBM80 bridging and BASIC's
; own cold start from scratch, so every piece of RAM (including zero
; page) ends up in the same state a power cycle would leave it in.
RebootCmd
        jmp     ($fffc)

; jet_charset_setup (the character-ROM copy this flyby's bold lettering
; needs, plus jet_bold_font/jet_copyright_glyph, the data it patches
; in) moved to Bank 14 - see slots.asm's SLOT_JET_CHARSET_SETUP comment
; for the full story and bank14_content.asm for the routine itself.

; 4-color (multicolor mode) 12x21-effective-pixel sprite: an original
; commercial-jet design flying nose-right for the left-to-right flyby.
; 2 bits/pixel: 00=transparent, 01=shared multicolor 1 ($D025, white
; fuselage/wings), 10=this sprite's own color ($D027, blue cockpit
; window near the nose), 11=shared multicolor 2 ($D026, red tail fin
; near the tail) - see tower_anim_start above for where those registers
; get set. Generated from an explicit column-position model (see
; scratchpad/gen_jet_color2.py), not hand-toggled bit-by-bit.
; Larger red tail (C) and blue nose/cockpit (B) sections than the
; original design - more color presence, not just thin accent lines,
; while keeping the white fuselage/wings dominant.
; Nose tapers to a sharper point over fewer rows now, and the blue
; canopy/cockpit section is much bigger, extending further back toward
; the body instead of being a thin sliver right at the tip.
jet_sprite
        !byte $01, $00, $00, $05, $40, $00, $15, $50, $00, $55, $54, $00, $15, $54, $00, $f5, $55, $00, $fd, $55, $80
        !byte $ff, $56, $a0, $ff, $56, $a8, $3d, $5a, $a8, $0d, $5a, $a8, $ff, $56, $a8, $ff, $56, $a0, $fd, $55, $80
        !byte $f5, $55, $00, $55, $54, $00, $15, $50, $00, $05, $40, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00

; No "!source common.asm" here any more - the whole F1 Cart Menu moved
; to Bank 14 (see this file's own header comment).
