; Shared program body — included by both the PRG build (hello.asm) and
; the cartridge build (hello_cart.asm). Entered as a subroutine (JSR);
; ends in RTS so both callers (BASIC's SYS and the cart stub) get control back.

; Scratch counter for delay(), pinned to zero page. Zero page is always real
; writable RAM regardless of banking, unlike the code segment itself: for the
; PRG build that's normal RAM anyway, but for the cartridge build the code
; lives in ROM ($8000-$9FFF, read-only in 8K Game mode), so a variable
; declared inline there could never actually be written.
dly_cnt = $02

start
        lda     #$00        ; black border + background
        sta     $d020
        sta     $d021

        lda     #$93        ; clear screen
        jsr     $ffd2

        ldx     #$00
splash_loop
        lda     splash,x
        beq     splash_done
        jsr     $ffd2
        inx
        bne     splash_loop
splash_done

        lda     #120        ; 60 Hz * 2 sec = 120 ticks
        jsr     delay       ; hold splash on screen

        lda     #$05        ; reset to white text
        jsr     $ffd2
        lda     #$93        ; clear screen
        jsr     $ffd2

        ldx     #$00
loop
        lda     msg,x
        beq     done
        jsr     $ffd2
        inx
        bne     loop
done
        rts

; --- Cycle-counting busy-wait delay (~1/60 sec per unit) ---
; A = number of ~jiffy-length units to wait (max 255, ~4.25 sec)
; A plain busy-loop rather than the CIA/jiffy-clock ($A2) so it needs no
; interrupts or hardware setup — safe to call from any entry context
; (BASIC's SYS, or a cartridge's autostart vector before IRQs are running).
delay
        sta     dly_cnt
dly_unit
        ldy     #$0d
dly_outer
        ldx     #$00
dly_inner
        dex
        bne     dly_inner
        dey
        bne     dly_outer
        dec     dly_cnt
        bne     dly_unit
        rts

; --- Splash screen (40-col PETSCII, vertically centered at row 10-14) ---
; PETSCII color codes: $9F=cyan $9E=yellow $05=white
; The C64's default charset has no true "©" glyph (it's a line/box-drawing
; character there instead), so spell it out as "(C)" like period C64
; software did — unambiguous on any charset.
; 10x $0D positions content at row 10 (center of 25-row screen)
splash
        !byte   $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D  ; move to row 10
        !byte   $9F                                        ; cyan
        !text   "========================================"  ; 40 chars
        !byte   $0D,$0D
        !byte   $9E                                        ; yellow
        !text   "    SHACKMATE (C) 2026 BY N4LDR & WD4VA"
        !byte   $0D,$0D
        !byte   $9F                                        ; cyan
        !text   "========================================"
        !byte   $0D
        !byte   $00

msg
        !text   "GOTTA LOVE ASSEMBLER !!!"
        !byte   $0d, $00
