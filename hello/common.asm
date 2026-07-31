; Shared program body — included by both the PRG build (hello.asm) and
; the cartridge build (hello_cart.asm). Entered as a subroutine (JSR).
; Never returns: after the splash/message it drops into mainloop and stays
; resident, watching for F1 to open the menu.

; Scratch zero page — always real writable RAM regardless of banking, unlike
; the code segment itself: for the PRG build that's normal RAM anyway, but
; for the cartridge build the code lives in ROM ($8000-$9FFF, read-only in
; 8K Game mode), so a variable declared inline there could never be written.
dly_cnt = $02        ; delay() countdown
num_val = $03        ; accumulated numeric menu selection (1-12)
str_ptr  = $04       ; 2 bytes ($04/$05): indirect pointer for stub names
mul_tmp  = $06       ; scratch for num_val = num_val*10 + digit
draw_ptr = $07       ; 2 bytes ($07/$08): indirect pointer for menu_data

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

; --- Background loop: idle, watching for F1 to open the menu ---
mainloop
        jsr     $ffe4        ; GETIN - non-blocking read of one key (0 = none)
        beq     mainloop
        cmp     #$85         ; F1
        bne     mainloop
        jsr     menu_open
        jmp     mainloop

; --- C64 Explorer ROM main menu ---
; Type a number (1-12) then RETURN to launch a tool, or use the F-key
; shortcuts directly. Everything below routes to a labeled "not yet
; implemented" screen except F7, which really does reset the machine.
menu_open
        jsr     menu_draw
        lda     #$00
        sta     num_val
menu_wait
        jsr     $ffe4
        beq     menu_wait

        cmp     #$03         ; RUN/STOP - back out of the menu entirely
        bne     +
!ifdef BANKNUM {
        jmp     bank_return  ; cart build: menu_open is reached via
                              ; irq_hook's bank_call, so it has to finish
                              ; the same way - a bare RTS here would leave
                              ; bank_call's saved-bank byte stranded on
                              ; the stack, corrupting the next unrelated
                              ; RTS that ran anywhere in the system
} else {
        rts                  ; PRG build: no bank switching exists here -
                              ; returns straight to mainloop
}
+
        cmp     #$0d         ; RETURN - dispatch the typed number
        beq     menu_dispatch_num
        cmp     #$85         ; F1 = Help
        bne     +
        jmp     menu_help
+
        cmp     #$86         ; F3 = ROM Monitor
        bne     +
        jmp     menu_rommon
+
        cmp     #$87         ; F5 = Disassembler
        bne     +
        jmp     menu_disasm
+
        cmp     #$88         ; F7 = Reset
        bne     +
        jmp     menu_reset
+

        cmp     #$30         ; digit '0'-'9' ?
        bcc     menu_wait
        cmp     #$3a
        bcs     menu_wait
        pha                  ; save the typed char to echo it
        jsr     $ffd2
        pla
        sec
        sbc     #$30         ; A = digit value 0-9
        sta     mul_tmp
        lda     num_val
        asl                  ; num_val*2
        sta     num_val
        asl                  ; num_val*4
        asl                  ; num_val*8
        clc
        adc     num_val      ; *8 + *2 = *10
        clc
        adc     mul_tmp      ; + digit
        sta     num_val
        jmp     menu_wait

; Items with a real implementation are dispatched here by number;
; everything else falls through to the generic "not implemented" stub.
; CMP doesn't touch A, so num_val stays in A across this whole chain.
menu_dispatch_num
        lda     num_val
        bne     +
        jmp     menu_open    ; nothing typed - just redraw
+
        cmp     #13
        bcs     menu_open    ; >12 - invalid, redraw

        cmp     #1
        bne     nd1
        jsr     feat_graphics_demo
        jmp     menu_open
nd1     cmp     #2
        bne     nd2
        jsr     feat_sid_demo
        jmp     menu_open
nd2     cmp     #3
        bne     nd3
        jsr     feat_sprite_editor
        jmp     menu_open
nd3     cmp     #4
        bne     nd4
        jsr     feat_joystick_tester
        jmp     menu_open
nd4     cmp     #6
        bne     nd6
        jsr     feat_cia_monitor
        jmp     menu_open
nd6     cmp     #7
        bne     nd7
        jsr     feat_vic_viewer
        jmp     menu_open
nd7     cmp     #8
        bne     nd8
        jsr     feat_memory_viewer
        jmp     menu_open
nd8
        jsr     show_stub    ; A = 1-12, looks up the name itself
        jmp     menu_open

menu_help
        lda     #<name_help
        sta     str_ptr
        lda     #>name_help
        sta     str_ptr+1
        jsr     show_named_stub
        jmp     menu_open
menu_rommon
        lda     #<name_rommon
        sta     str_ptr
        lda     #>name_rommon
        sta     str_ptr+1
        jsr     show_named_stub
        jmp     menu_open
menu_disasm
        lda     #<name_disasm
        sta     str_ptr
        lda     #>name_disasm
        sta     str_ptr+1
        jsr     show_named_stub
        jmp     menu_open
menu_reset
        jmp     ($fffc)      ; real KERNAL reset — not a stub

menu_draw
        lda     #$93         ; clear screen
        jsr     $ffd2
        lda     #<menu_data  ; menu_data is >255 bytes, so this needs a full
        sta     draw_ptr     ; 16-bit pointer (X-indexed would wrap at 256
        lda     #>menu_data  ; and silently truncate — bit us once already).
        sta     draw_ptr+1
        ; SEI while we print: something in the cartridge context's IRQ path
        ; was clobbering draw_ptr mid-loop (confirmed by watching it read
        ; back as $0000 partway through a long print) — never observed on
        ; the PRG target, but this print loop is long enough to span many
        ; IRQs, so hold interrupts off for the ~1/4 second this takes.
        sei
        ldy     #$00
menu_draw_loop
        lda     (draw_ptr),y
        beq     menu_draw_done
        jsr     $ffd2
        iny
        bne     menu_draw_loop
        inc     draw_ptr+1   ; Y wrapped past 256 bytes - bump the high byte
        jmp     menu_draw_loop
menu_draw_done
        cli
        rts

; --- Generic "not implemented yet" screen ---
; show_stub: A = menu number (1-12), looks up the name via item_lo/item_hi.
; show_named_stub: str_ptr already points at a null-terminated name.
show_stub
        tax
        dex
        lda     item_lo,x
        sta     str_ptr
        lda     item_hi,x
        sta     str_ptr+1
show_named_stub
        lda     #$93
        jsr     $ffd2
        lda     #$9e         ; yellow
        jsr     $ffd2
        sei                  ; same zero-page-pointer protection as menu_draw
        ldy     #$00
stub_name_loop
        lda     (str_ptr),y
        beq     stub_name_done
        jsr     $ffd2
        iny
        bne     stub_name_loop
stub_name_done
        cli
        lda     #$0d
        jsr     $ffd2
        lda     #$0d
        jsr     $ffd2
        lda     #$05         ; white
        jsr     $ffd2
        ldx     #$00
stub_msg_loop
        lda     stub_msg,x
        beq     stub_wait
        jsr     $ffd2
        inx
        bne     stub_msg_loop
stub_wait
        jsr     $ffe4
        beq     stub_wait
        rts

stub_msg
        !text   "NOT YET IMPLEMENTED"
        !byte   $0d,$0d
        !text   "PRESS ANY KEY TO RETURN"
        !byte   $00

name_help   !text "HELP" : !byte 0
name_rommon !text "ROM MONITOR" : !byte 0
name_disasm !text "DISASSEMBLER" : !byte 0

name01 !text "GRAPHICS DEMO" : !byte 0
name02 !text "SID MUSIC DEMO" : !byte 0
name03 !text "SPRITE EDITOR" : !byte 0
name04 !text "JOYSTICK TESTER" : !byte 0
name05 !text "KEYBOARD MATRIX VIEWER" : !byte 0
name06 !text "CIA TIMER MONITOR" : !byte 0
name07 !text "VIC-II REGISTER VIEWER" : !byte 0
name08 !text "MEMORY VIEWER" : !byte 0
name09 !text "ASSEMBLY MONITOR" : !byte 0
name10 !text "MACHINE LANGUAGE TUTORIAL" : !byte 0
name11 !text "BASIC WORKSPACE" : !byte 0
name12 !text "HARDWARE DIAGNOSTICS" : !byte 0

item_lo !byte <name01,<name02,<name03,<name04,<name05,<name06
        !byte <name07,<name08,<name09,<name10,<name11,<name12
item_hi !byte >name01,>name02,>name03,>name04,>name05,>name06
        !byte >name07,>name08,>name09,>name10,>name11,>name12

; No "|" side borders here — like "©" earlier, PETSCII "|" doesn't render as
; a vertical bar in the default charset. Stick to "=" (already proven safe,
; used in the splash) instead of guessing at another graphic character.
menu_data
        !byte   $9f                                        ; cyan
        !text   "=============================="
        !byte   $0d
        !text   " C64 ULTIMATE SDK - SHACKMATE"
        !byte   $0d
        !text   "=============================="
        !byte   $0d,$0d
        !byte   $9e                                        ; yellow
        !text   "1. GRAPHICS DEMO"
        !byte   $0d
        !text   "2. SID MUSIC DEMO"
        !byte   $0d
        !text   "3. SPRITE EDITOR"
        !byte   $0d
        !text   "4. JOYSTICK TESTER"
        !byte   $0d
        !text   "5. KEYBOARD MATRIX VIEWER"
        !byte   $0d
        !text   "6. CIA TIMER MONITOR"
        !byte   $0d
        !text   "7. VIC-II REGISTER VIEWER"
        !byte   $0d
        !text   "8. MEMORY VIEWER"
        !byte   $0d
        !text   "9. ASSEMBLY MONITOR"
        !byte   $0d
        !text   "10. MACHINE LANGUAGE TUTORIAL"
        !byte   $0d
        !text   "11. BASIC WORKSPACE"
        !byte   $0d
        !text   "12. HARDWARE DIAGNOSTICS"
        !byte   $0d,$0d
        !byte   $9f                                        ; cyan
        !text   "F1 = HELP"
        !byte   $0d
        !text   "F3 = ROM MONITOR"
        !byte   $0d
        !text   "F5 = DISASSEMBLER"
        !byte   $0d
        !text   "F7 = RESET"
        !byte   $0d,$0d
        !byte   $05                                        ; white
        !text   "SELECT: "
        !byte   $00

; --- Cycle-counting busy-wait delay (~1/60 sec per unit) ---
; A = number of ~jiffy-length units to wait (max 255, ~4.25 sec)
; A plain busy-loop rather than the CIA/jiffy-clock ($A2) so it needs no
; interrupts or hardware setup — safe to call from any entry context
; (BASIC's SYS, or a cartridge's autostart vector before IRQs are running).
; Preserves X/Y: the busy-wait itself needs both as scratch, and a caller
; looping on X/Y across a delay() call (as the demo features do) would
; otherwise silently get X reset to 0 every time — found this the hard way.
delay
        sta     dly_cnt
        txa
        pha
        tya
        pha
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
        pla
        tay
        pla
        tax
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
        !byte   $05                                        ; white
        !text   "BUILD 10"
        !byte   $0D
        !byte   $00

msg
        !text   "GOTTA LOVE ASSEMBLER !!!"
        !byte   $0d, $00

!source "features.asm"
!source "bitmap.asm"
!source "spriteeditor.asm"
