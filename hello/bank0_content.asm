; Bank 0 content: Boot/Menu. cart_start and everything under menu_open
; (common.asm/features.asm/bitmap.asm/spriteeditor.asm) are unchanged
; from the single-bank design - nothing in that call graph ever leaves
; Bank 0's own address space, so it's a copy-paste, not a rewrite.
; irq_hook/read_f1/zp_save/zp_restore/save_screen/restore_screen and
; the BASIC-extension dispatcher moved OUT to resident.asm, since those
; have to work regardless of which bank happens to be switched in -
; see resident.asm for why.

; --- Cartridge autostart header ---
; KERNAL reset routine looks for "CBM80" at $8004 and, if found, jumps
; indirectly through the cold-start vector below instead of booting BASIC.
; (Reached here via romh_boot.asm's bridge from EasyFlash's forced
; Ultimax boot back to this normal KERNAL autostart path - see that
; file for why that's needed at all.)
!word cart_start     ; cold-start vector
!word cart_start     ; NMI vector (just reuse cold-start for this demo)
!byte $c3,$c2,$cd,$38,$30  ; "CBM80" autostart signature (KERNAL checks
                            ; these exact bytes, not plain ASCII "CBM80")

; --- Fixed-slot jump table entry for this bank (slots.asm) ---
!fill SLOT_MENU_OPEN-*, $ff
        jmp     menu_open

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in - keeps it available for later
; slots without ever having to relocate cart_start.
!fill $8100-*, $ff

*=$8100
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
        lda     #$00
        sta     f1_state
        sta     cur_bank    ; hardware always resets with bank 0 selected -
                             ; keep the RAM shadow in sync from the start
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

        cli                 ; re-enable interrupts (delay loop needs the jiffy clock)

; Welcome screen: flash the splash banner for ~1 second, then go
; straight on to BASIC below - no menu here. F1 still opens it
; afterward via irq_hook as usual; this is just a startup banner.
        lda     #$00
        sta     $d020
        sta     $d021
        lda     #$93
        jsr     $ffd2
        ldx     #$00
cart_boot_splash
        lda     splash,x
        beq     cart_boot_splash_done
        jsr     $ffd2
        inx
        bne     cart_boot_splash
cart_boot_splash_done
        lda     #60         ; ~1 second (60 jiffies)
        jsr     delay

; Arm the BASIC-extension countdown right here, not back before the
; splash - interrupts (and so irq_hook's countdown) have been running
; since the CLI above, and this whole splash detour has already burned
; ~60 jiffies of it. Arming it that early let the countdown reach 0
; and fire mid-splash, well before BASIC's cold start below even runs -
; which then clobbered our freshly-installed vectors right back to
; stock as part of its own RAM-vector init, so neither CLS nor HEX ever
; survived to see a keystroke. Setting it fresh right before the jump
; means BASIC's cold start (a quick banner print) has long finished by
; the time it counts down again.
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

!source "common.asm"
