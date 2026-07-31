; ROMH bootstrap for Bank 0 - EasyFlash always boots into Ultimax mode,
; which maps ROMH (not the KERNAL) at $E000-$FFFF, so the hardware reset
; vector ($FFFC/$FFFD) has to be supplied here rather than by the KERNAL.
;
; Job: bridge "forced Ultimax boot" back to the normal KERNAL reset path.
; Switch out of Ultimax into 8K game mode, then JMP ($FFFC) to re-enter
; through the KERNAL's own (now real, since KERNAL ROM is back) reset
; vector - which finds our existing CBM80 signature in ROML at $8004 and
; proceeds through cart_start exactly as it already does. Nothing in
; hello_cart.asm's boot logic needs to change for this.
;
; The mode-switch write to $DE02 can't safely be followed by more code
; fetched from this same ROMH page, since the write banks ROMH itself
; out from under the CPU mid-execution - so the switch+rejump has to run
; from a RAM copy instead, immune to the swap. Ported from a real,
; working EasyFlash boot image (EF3BootImage/trampoline.s) rather than
; reasoned out from scratch, since this depends on undocumented
; bank-switch timing that isn't worth guessing at.
;
; Register bits verified against real EAPI driver source (eapi_defs.s):
; $DE02 bit2=MEMCTRL (must be set for GAME/EXROM bits to take effect),
; bit1=EXROM, bit0=GAME (both active-low: bit=1 drives the line low).
; MEMCTRL|EXROM ($06), GAME bit clear, is 8K game mode - BASIC ROM stays
; visible at $A000, matching what JMP ($A000) in cart_start expects.

*=$e000
!fill $ff00-$e000, $ff     ; unused ROMH space - filled like erased flash

romh_start
        sei
        ldx     #$ff
        txs
        cld
        lda     #$37        ; standard CPU port init (same values KERNAL's
        sta     $01         ; own reset uses)
        lda     #$2f
        sta     $00
        ldx     #$00
romh_copy
        lda     ramcode,x
        sta     $0400,x
        inx
        cpx     #ramcode_len
        bne     romh_copy
        jmp     $0400

ramcode
        lda     #$06        ; MEMCTRL|EXROM - 8K game mode
        sta     $de02
        jmp     ($fffc)     ; re-enter via the reset vector, now reading
                            ; real KERNAL ROM instead of this bootstrap
ramcode_end
ramcode_len = ramcode_end - ramcode

!fill $fffc-*, $ff
!word romh_start            ; $FFFC/$FFFD - hardware reset vector
!word $ffff                 ; $FFFE/$FFFF - IRQ/BRK vector (unused; SEI
                             ; above masks interrupts for this bootstrap's
                             ; brief lifetime, and control never returns
                             ; here afterward)
