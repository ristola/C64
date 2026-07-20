; Hello World for Commodore 64 — 8K autostart cartridge image
; Assembler: ACME
; Build: Tasks: Run Task > Build Cartridge Image (or "Build All")

*=$8000

; --- Cartridge autostart header ---
; KERNAL reset routine looks for "CBM80" at $8004 and, if found, jumps
; indirectly through the cold-start vector below instead of booting BASIC.
!word cart_start     ; cold-start vector
!word cart_start     ; NMI vector (just reuse cold-start for this demo)
!byte $c3,$c2,$cd,$38,$30  ; "CBM80" autostart signature (KERNAL checks
                            ; these exact bytes, not plain ASCII "CBM80")

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
        cli                 ; re-enable interrupts (delay loop needs the jiffy clock)

        jsr     start       ; run the shared program body (in common.asm)
forever
        jmp     forever     ; nothing to return to — halt here

!source "common.asm"
