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
menu_cursor = $09    ; top-level menu's cursor position, 1-12 - only
                      ; ever set explicitly at boot (bank0_content.asm's
                      ; cart_start, once) and by menu_cursor_move
                      ; below; irq_hook's zp_save/zp_restore (resident.
                      ; asm) already brackets the whole $02-$38 range
                      ; around every F1 visit, same as num_val etc., so
                      ; whatever the cursor lands on during one visit is
                      ; discarded and reverts to the boot-time value of 1
                      ; the next time F1 is pressed - "defaults to item
                      ; 1" for free, no extra reset code needed here.
                      ; INC/DEC/LDA/STA/CPX below address it as the
                      ; literal $09, not this name - ACME (confirmed by
                      ; a throwaway isolated test) picks 3-byte absolute
                      ; addressing instead of 2-byte zero-page for those
                      ; specific opcodes when the operand is a symbol
                      ; here, for reasons not worth chasing further; the
                      ; literal reliably gets the compact form instead.
lab_cursor  = $0a    ; CARTRIDGE LAB submenu's own cursor, 1-6 - same
                      ; idea as menu_cursor, but explicitly reset to 1
                      ; every time menu_lab_open runs (below) rather
                      ; than relying on zp_save/zp_restore: a submenu
                      ; gets entered/left many times within one F1
                      ; visit (zp_save/zp_restore only brackets the
                      ; whole visit, not each submenu trip), so it needs
                      ; its own explicit "defaults to item 1" reset.
diag_cursor = $0b    ; DIAGNOSTICS submenu's cursor, 1-6 - same
                      ; as lab_cursor, reset in menu_diag_open.
cur_menu    = $0c    ; which of the three cursors above is "live" right
                      ; now: 0=top-level (menu_cursor), 1=CARTRIDGE LAB
                      ; (lab_cursor), 2=DIAGNOSTICS (diag_
                      ; cursor). menu_cursor_move/menu_highlight_update
                      ; (below) both index menu_cursor,cur_menu (i.e.
                      ; the literal $09,X - same oversized-addressing
                      ; workaround as menu_cursor itself) and the
                      ; per-menu tables alongside them to work generically
                      ; across all three, rather than needing three
                      ; near-identical copies of both routines. Set by
                      ; menu_open/menu_lab_open/menu_diag_open, each
                      ; right before their own draw/wait loop starts.
mhu_cursor_val     = $0d  ; menu_highlight_update's own scratch: the
                            ; current menu's cursor value, latched once
                            ; per call so X is free to reuse as the
                            ; per-row loop counter afterward
mhu_item_count_p1  = $0e  ; ditto, latched item-count-plus-1 (the loop
                            ; bound menu_highlight_update's row loop
                            ; compares X against - see menu_item_
                            ; counts_p1 below for why it's +1)

; Per-menu tables, indexed by cur_menu (0=top,1=lab,2=diag) - menu_
; cursor_move/menu_highlight_update both read these instead of having
; the item count/starting row hardcoded per menu.
menu_item_counts    !byte 8, 8, 6    ; for wraparound (menu_cursor_move)
menu_item_counts_p1 !byte 9, 9, 7    ; for the row loop bound
                                       ; (menu_highlight_update) - +1
                                       ; because that loop's X starts at
                                       ; 1 and stops the iteration AFTER
                                       ; X reaches the real count, same
                                       ; shape the original hardcoded
                                       ; "cpx #13" (12 items) already
                                       ; used
; Color-RAM address of each menu's own item row 1 - $D800 + firstRow*40,
; precomputed (menu_highlight_update needs no multiply this way): top-
; level items start row 6 (menu_data's own row-budget comment), both
; submenus start row 4 (menu_lab_data/menu_diag_data - shorter screens,
; no 2x-size title eating into their own row budget).
menu_color_base_lo !byte <($d800+6*40), <($d800+4*40), <($d800+4*40)
menu_color_base_hi !byte >($d800+6*40), >($d800+4*40), >($d800+4*40)

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
        lda     #$00
        sta     $0c          ; cur_menu (top-level=0) - literal, not the
                               ; symbol; see menu_cursor's own comment
                               ; for why. Set before menu_draw, which
                               ; paints the highlight using whatever
                               ; cur_menu currently is; also correctly
                               ; resets it back to 0 every time a
                               ; submenu returns
                               ; here via "jmp menu_open"
        jsr     menu_draw
        lda     #$00
        sta     num_val
menu_wait
        jsr     $ffe4
        bne     +
        jsr     menu_sparkle_update  ; idle - twinkle the title, then
        jmp     menu_wait              ; keep polling
+
        cmp     #$03         ; RUN/STOP - back out of the menu entirely
        beq     menu_exit
        cmp     #$0d         ; RETURN - dispatch the typed number (or,
        beq     menu_dispatch_num  ; if none was typed, the pointer's
                                     ; current selection - see there)
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
        cmp     #$11         ; CRSR DOWN
        bne     +
        ldy     #0
        jsr     menu_cursor_move
        jmp     menu_wait
+
        cmp     #$91         ; CRSR UP
        bne     +
        ldy     #1
        jsr     menu_cursor_move
        jmp     menu_wait
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

; Shared by RUN/STOP (menu_wait above) and item 8, EXIT (menu_
; dispatch_num below) - same "leave the menu" action either way.
menu_exit
        jsr     menu_charset_off  ; back to the stock character ROM
                                    ; before returning to BASIC - see
                                    ; that routine's own comment for why
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

; Items with a real implementation are dispatched here by number;
; everything else falls through to the generic "not implemented" stub.
; CMP doesn't touch A, so num_val stays in A across this whole chain.
menu_dispatch_num
        lda     num_val
        bne     +
        lda     $09          ; menu_cursor - nothing typed, RETURN alone
                               ; activates whatever it's currently on
        sta     num_val      ; feat_dispatch (bank 15) reads its
                               ; selector back out of num_val, so this
                               ; path has to leave it holding the
                               ; effective selection too, same as if it
                               ; had been typed
+
        cmp     #9
        bcc     +            ; < 9 - valid, continue below
        jmp     menu_open    ; >8 - invalid, redraw
+
        cmp     #1
        bne     nd1
        jsr     menu_lab_open
        jmp     menu_open
nd1     cmp     #2
        bne     nd2
        lda     #FEAT_SID
        sta     num_val
        jsr     feat_call
        jmp     menu_open
nd2     cmp     #3
        bne     nd3
        lda     #FEAT_SPRITE_EDITOR
        sta     num_val
        jsr     feat_call
        jmp     menu_open
nd3     cmp     #6
        bne     nd6
        jsr     menu_diag_open
        jmp     menu_open
nd6     cmp     #7
        bne     nd7
        jsr     menu_fastload_open
        jmp     menu_open
nd7     cmp     #8
        beq     menu_exit
        jsr     show_stub    ; A = 4-5 in practice (1-3/6-8 all have
                               ; real dispatch above), looks up the name
                               ; itself
        jmp     menu_open

; Shared bank_call-into-Bank-21 helper for every feat_X launch site
; (menu_dispatch_num above, menu_diag_dispatch_num below) - num_val
; must already hold the right FEAT_* constant (slots.asm) before this
; runs; see feat_dispatch's own comment (bank15_content.asm) for why
; that, not A, is the argument channel - bank_call itself already
; claims A for the bank number.
feat_call
        lda     #<SLOT_FEAT_DISPATCH
        sta     call_ptr
        lda     #>SLOT_FEAT_DISPATCH
        sta     call_ptr+1
        lda     #15             ; Bank 15
        jsr     bank_call
        rts

; --- CARTRIDGE LAB submenu (item 1) - EPROM/flash chip tools. All six
; sub-items are stubs for now (no real chip read/write/program logic
; exists yet - programmer-cartridge/README.md is still concept-stage,
; no design work done) - routed through the same show_named_stub "NOT
; YET IMPLEMENTED" screen every other unimplemented top-level item
; already uses. Own draw/wait/dispatch loop mirrors menu_open/
; menu_dispatch_num's own shape above (same num_val accumulator, reused
; safely since the two loops never run concurrently - menu_lab_open is
; only ever reached via a JSR from within menu_open's own dispatch).
; Back arrow (unshifted left-arrow key, $5F) returns to the main menu
; instead of exiting the whole system the way RUN/STOP does at the top
; level - verify $5F live before relying on it; PETSCII key codes for
; this project have so far only been confirmed for F1/F3/F5/F7 (menu_
; open above) and RUN/STOP (menu_wait above), not this one.
menu_lab_open
        lda     #1
        sta     $0a          ; lab_cursor - defaults to item 1, but only
                               ; on a FRESH entry from the top-level menu;
                               ; menu_lab_dispatch_num's own return path
                               ; jumps to menu_lab_redraw below instead,
                               ; which skips this so the pointer stays on
                               ; whatever item was just launched rather
                               ; than snapping back to item 1 every time
menu_lab_redraw
        lda     #1
        sta     $0c          ; cur_menu (CARTRIDGE LAB=1) - literal, see
                               ; menu_cursor's own comment for why. Must
                               ; be set before menu_lab_draw, which
                               ; paints the highlight
        jsr     menu_lab_draw
        lda     #$00
        sta     num_val
menu_lab_wait
        jsr     $ffe4
        beq     menu_lab_wait

        cmp     #$5f         ; back arrow - return to the main menu
        beq     menu_lab_back

        cmp     #$0d         ; RETURN - dispatch the typed number
        beq     menu_lab_dispatch_num

        cmp     #$11         ; CRSR DOWN
        bne     +
        ldy     #0
        jsr     menu_cursor_move
        jmp     menu_lab_wait
+
        cmp     #$91         ; CRSR UP
        bne     +
        ldy     #1
        jsr     menu_cursor_move
        jmp     menu_lab_wait
+
        cmp     #$30         ; digit '0'-'9' ?
        bcc     menu_lab_wait
        cmp     #$3a
        bcs     menu_lab_wait
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
        jmp     menu_lab_wait
menu_lab_back
        rts                  ; menu_open's own item-1 case does
                              ; "jmp menu_open" right after this jsr
                              ; returns, redrawing the main menu

menu_lab_dispatch_num
        lda     num_val
        bne     +
        lda     $0a          ; lab_cursor - nothing typed, RETURN alone
        sta     num_val      ; activates whatever it's currently on
+
        cmp     #9
        bcs     menu_lab_redraw  ; >8 - invalid, redraw - leave the
                                   ; pointer as-is, nothing was launched
        sta     $0a          ; lab_cursor - track the item actually being
                               ; launched (covers RETURN-with-typed-digit
                               ; too, not just cursor-based selection), so
                               ; returning here shows the same highlight

        cmp     #1
        bne     ld1
        lda     #FEAT_READ_CHIP
        sta     num_val
        jsr     feat_call
        jmp     menu_lab_redraw
ld1     cmp     #2
        bne     ld2
        lda     #FEAT_VERIFY_EPROM
        sta     num_val
        jsr     feat_call
        jmp     menu_lab_redraw
ld2     cmp     #3
        bne     ld3
        lda     eprom_read_done
        bne     ld2_dump
        lda     #<lab_name03_nodata
        sta     str_ptr
        lda     #>lab_name03_nodata
        sta     str_ptr+1
        jsr     show_named_stub
        jmp     menu_lab_redraw
ld2_dump
        lda     #FEAT_EPROM_DUMP
        sta     num_val
        jsr     feat_call
        jmp     menu_lab_redraw
ld3     cmp     #4
        bne     ld4
        lda     #FEAT_BACKUP_EPROM
        sta     num_val
        jsr     feat_call
        jmp     menu_lab_redraw
ld4     cmp     #5
        bne     ld5
        lda     #FEAT_LOAD_EPROM
        sta     num_val
        jsr     feat_call
        jmp     menu_lab_redraw
ld5     cmp     #6
        bne     ld6
        lda     #FEAT_BANK_SCANNER
        sta     num_val
        jsr     feat_call
        jmp     menu_lab_redraw
ld6     cmp     #7
        bne     ld7
        lda     #FEAT_EPROM_DUMP  ; HEX VIEWER is the same viewer DUMP
        sta     num_val             ; EPROM uses, just reachable without
        jsr     feat_call           ; needing READ CHIP run first (no
        jmp     menu_lab_redraw     ; eprom_read_done gate)
ld7     cmp     #8
        beq     +
        jmp     menu_lab_redraw ; shouldn't happen - already range-checked
+       lda     #FEAT_SEARCH_ROM
        sta     num_val
        jsr     feat_call
        jmp     menu_lab_redraw

lab_name03_nodata !text "NO EPROM DATA - RUN READ EPROM FIRST" : !byte 0

menu_lab_draw
        lda     #$93         ; clear screen
        jsr     $ffd2
        lda     #<menu_lab_data
        sta     draw_ptr
        lda     #>menu_lab_data
        sta     draw_ptr+1
        sei                  ; same draw_ptr protection as menu_draw
        ldy     #$00
menu_lab_draw_loop
        lda     (draw_ptr),y
        beq     menu_lab_draw_done
        jsr     $ffd2
        iny
        bne     menu_lab_draw_loop
        inc     draw_ptr+1
        jmp     menu_lab_draw_loop
menu_lab_draw_done
        cli
        jsr     menu_highlight_update  ; paint the pointer - cur_menu
                                          ; was already set to 1 by
                                          ; menu_lab_redraw before this ran
        rts

menu_lab_data
        !byte   $9f                                        ; cyan
        !text   "=============================="
        !byte   $0d
        !text   "         CARTRIDGE LAB"
        !byte   $0d
        !text   "=============================="
        !byte   $0d,$0d
        !byte   $1f                                        ; blue
        !text   "1. READ EPROM"
        !byte   $0d
        !text   "2. VERIFY EPROM"
        !byte   $0d
        !text   "3. DUMP EPROM"
        !byte   $0d
        !text   "4. BACKUP EPROM"
        !byte   $0d
        !text   "5. LOAD EPROM TO RAM"
        !byte   $0d
        !text   "6. BANK SCANNER"
        !byte   $0d
        !text   "7. HEX VIEWER"
        !byte   $0d
        !text   "8. SEARCH ROM"
        !byte   $0d,$0d
        !byte   $9f                                        ; cyan
        !text   "<- = BACK"
        !byte   $0d,$0d
        !byte   $05                                        ; white
        !text   "SELECT: "
        !byte   $00

; --- DIAGNOSTICS submenu (item 6) - JOYSTICK TESTER and KEYBOARD
; MATRIX VIEWER used to be their own top-level items 4 and 5; CIA TIMER
; MONITOR/VIC-II REGISTER VIEWER/MEMORY VIEWER/ASSEMBLY MONITOR used to
; be top-level items 4-7. All six now live here instead, so the top-
; level list groups every hardware-inspection tool under one entry as
; the menu keeps growing. Same submenu shape as CARTRIDGE LAB (menu_
; lab_open) above - see that routine's own comments for the back-
; arrow/dispatch details, unchanged here.
menu_diag_open
        lda     #1
        sta     $0b          ; diag_cursor - defaults to item 1, but only
                               ; on a FRESH entry from the top-level menu;
                               ; menu_diag_dispatch_num's own return path
                               ; jumps to menu_diag_redraw below instead,
                               ; which skips this so the pointer stays on
                               ; whatever item was just launched rather
                               ; than snapping back to a fixed position
                               ; every time (previously this even reused
                               ; the #2 already in A from cur_menu below,
                               ; so it landed on item 2, not 1)
menu_diag_redraw
        lda     #2
        sta     $0c          ; cur_menu (DIAGNOSTICS=2) -
                               ; literal, see menu_cursor's own comment
                               ; for why. Must be set before menu_diag_
                               ; draw, which paints the highlight
        jsr     menu_diag_draw
        lda     #$00
        sta     num_val
menu_diag_wait
        jsr     $ffe4
        beq     menu_diag_wait

        cmp     #$5f         ; back arrow - return to the main menu
        beq     menu_diag_back

        cmp     #$0d         ; RETURN - dispatch the typed number
        beq     menu_diag_dispatch_num

        cmp     #$11         ; CRSR DOWN
        bne     +
        ldy     #0
        jsr     menu_cursor_move
        jmp     menu_diag_wait
+
        cmp     #$91         ; CRSR UP
        bne     +
        ldy     #1
        jsr     menu_cursor_move
        jmp     menu_diag_wait
+
        cmp     #$30         ; digit '0'-'9' ?
        bcc     menu_diag_wait
        cmp     #$3a
        bcs     menu_diag_wait
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
        jmp     menu_diag_wait
menu_diag_back
        rts                  ; menu_dispatch_num's item-6 case does
                              ; "jmp menu_open" right after this jsr
                              ; returns, redrawing the main menu

menu_diag_dispatch_num
        lda     num_val
        bne     +
        lda     $0b          ; diag_cursor - nothing typed, RETURN alone
        sta     num_val      ; activates whatever it's currently on
+
        cmp     #7
        bcs     menu_diag_redraw  ; >6 - invalid, redraw - leave the
                                    ; pointer as-is, nothing was launched
        sta     $0b          ; diag_cursor - track the item actually being
                               ; launched (covers RETURN-with-typed-digit
                               ; too, not just cursor-based selection), so
                               ; returning here shows the same highlight

        cmp     #1
        bne     dd1
        lda     #FEAT_JOYSTICK
        sta     num_val
        jsr     feat_call
        jmp     menu_diag_redraw
dd1     cmp     #2
        bne     dd2
        lda     #<diag_name02
        sta     str_ptr
        lda     #>diag_name02
        sta     str_ptr+1
        jsr     show_named_stub
        jmp     menu_diag_redraw
dd2     cmp     #3
        bne     dd3
        lda     #FEAT_CIA
        sta     num_val
        jsr     feat_call
        jmp     menu_diag_redraw
dd3     cmp     #4
        bne     dd4
        lda     #FEAT_VIC
        sta     num_val
        jsr     feat_call
        jmp     menu_diag_redraw
dd4     cmp     #5
        bne     dd5
        lda     #FEAT_MEMORY
        sta     num_val
        jsr     feat_call
        jmp     menu_diag_redraw
dd5     cmp     #6
        beq     +
        jmp     menu_diag_redraw ; shouldn't happen - already range-checked
+       lda     #<diag_name06
        sta     str_ptr
        lda     #>diag_name06
        sta     str_ptr+1
        jsr     show_named_stub
        jmp     menu_diag_redraw

diag_name02 !text "KEYBOARD MATRIX VIEWER" : !byte 0
diag_name06 !text "ASSEMBLY MONITOR" : !byte 0

menu_diag_draw
        lda     #$93         ; clear screen
        jsr     $ffd2
        lda     #<menu_diag_data
        sta     draw_ptr
        lda     #>menu_diag_data
        sta     draw_ptr+1
        sei                  ; same draw_ptr protection as menu_draw
        ldy     #$00
menu_diag_draw_loop
        lda     (draw_ptr),y
        beq     menu_diag_draw_done
        jsr     $ffd2
        iny
        bne     menu_diag_draw_loop
        inc     draw_ptr+1
        jmp     menu_diag_draw_loop
menu_diag_draw_done
        cli
        jsr     menu_highlight_update  ; paint the pointer - cur_menu
                                          ; was already set to 2 by
                                          ; menu_diag_redraw before this ran
        rts

menu_diag_data
        !byte   $9f                                        ; cyan
        !text   "=============================="
        !byte   $0d
        !text   "          DIAGNOSTICS"
        !byte   $0d
        !text   "=============================="
        !byte   $0d,$0d
        !byte   $1f                                        ; blue
        !text   "1. JOYSTICK TESTER"
        !byte   $0d
        !text   "2. KEYBOARD MATRIX VIEWER"
        !byte   $0d
        !text   "3. CIA TIMER MONITOR"
        !byte   $0d
        !text   "4. VIC-II REGISTER VIEWER"
        !byte   $0d
        !text   "5. MEMORY VIEWER"
        !byte   $0d
        !text   "6. ASSEMBLY MONITOR"
        !byte   $0d,$0d
        !byte   $9f                                        ; cyan
        !text   "<- = BACK"
        !byte   $0d,$0d
        !byte   $05                                        ; white
        !text   "SELECT: "
        !byte   $00

; --- FASTLOAD SETTINGS (item 7) - shows/toggles fastload_enabled
; (slots.asm), which DloadCmd (bank10_content.asm) checks before
; deciding whether to bank_call into FastDload (bank 13, real, working)
; or fall back to plain KERNAL_LOAD. No BASIC command for this
; deliberately - an earlier BASIC-command-plus-boot-banner version was
; built and backed out (see git history) after turning out to be
; genuinely hard to verify was even displaying; this F1-menu-only
; version is simpler to reason about and test. $1E/$1C are CHROUT's own
; green/red control codes, same convention DIR uses (bank10_content.asm).
menu_fastload_open
        lda     #$93
        jsr     $ffd2
        lda     #$9f            ; cyan
        jsr     $ffd2
        ldx     #0
mfl_title_loop
        lda     mfl_title,x
        beq     mfl_title_done
        jsr     $ffd2
        inx
        bne     mfl_title_loop
mfl_title_done
        lda     fastload_enabled
        beq     mfl_show_off
        lda     #$1e            ; green
        jsr     $ffd2
        ldx     #0
mfl_on_loop
        lda     mfl_on_msg,x
        beq     mfl_prompt
        jsr     $ffd2
        inx
        bne     mfl_on_loop
mfl_show_off
        lda     #$1c            ; red
        jsr     $ffd2
        ldx     #0
mfl_off_loop
        lda     mfl_off_msg,x
        beq     mfl_prompt
        jsr     $ffd2
        inx
        bne     mfl_off_loop
mfl_prompt
        lda     #$05            ; white
        jsr     $ffd2
        ldx     #0
mfl_prompt_loop
        lda     mfl_prompt_msg,x
        beq     mfl_wait
        jsr     $ffd2
        inx
        bne     mfl_prompt_loop
mfl_wait
        jsr     $ffe4
        beq     mfl_wait
        cmp     #'1'
        bne     +
        lda     #1
        sta     fastload_enabled
        jmp     menu_fastload_open    ; redraw with the new status
+       cmp     #'0'
        bne     +
        lda     #0
        sta     fastload_enabled
        jmp     menu_fastload_open
+       rts                            ; any other key - back to main menu

mfl_title
        !text   "FASTLOAD SETTINGS"
        !byte   $0d,$0d,0
mfl_on_msg
        !text   "STATUS: ENABLED"
        !byte   $0d,$0d,0
mfl_off_msg
        !text   "STATUS: DISABLED"
        !byte   $0d,$0d,0
mfl_prompt_msg
        !text   "PRESS 1 TO ENABLE"
        !byte   $0d
        !text   "PRESS 0 TO DISABLE"
        !byte   $0d
        !text   "ANY OTHER KEY TO RETURN"
        !byte   $0d,0

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
        ; SEI now, before menu_draw_title's screen/color-RAM poke: this
        ; whole routine runs nested inside irq_hook's F1 dispatch with
        ; interrupts already re-enabled (see irq_hook's own CLI before its
        ; bank_call into here), so a stray jiffy IRQ landing mid-poke is
        ; exactly the same class of hazard that was already found and
        ; fixed for draw_ptr below (confirmed by watching it read back as
        ; $0000 partway through a long print) — just widening the existing
        ; protected window to cover the title poke too, since it's directly
        ; adjacent and just as exposed. Held for the whole ~1/4 second this
        ; and the print loop take.
        sei
        jsr     menu_draw_title
        lda     #<menu_data  ; menu_data is >255 bytes, so this needs a full
        sta     draw_ptr     ; 16-bit pointer (X-indexed would wrap at 256
        lda     #>menu_data  ; and silently truncate — bit us once already).
        sta     draw_ptr+1
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
        jsr     menu_highlight_update  ; paint the pointer onto whichever
                                          ; item menu_cursor is currently
                                          ; on (item 1 by default - see
                                          ; menu_cursor's own comment)
        rts

; --- Title sparkle: up to SPARKLE_SLOTS stars flash briefly at random
; positions (from the sparkle_offsets candidates, in the blank rows
; above/below the title) and random times while menu_wait is idle.
; Top-level menu only: menu_lab_wait/menu_diag_wait don't call this -
; their own screens use rows 0/3 for real content (their own divider/
; heading), not blank padding, so poking sparkles there would corrupt
; them.
;
; Two earlier versions of this were both stateless formulas (a fixed
; position always flashing on a fixed schedule, then a slower fixed
; schedule) - confirmed live as first "very rapid", then still "pretty
; frequent" and always the same repeating pattern. This version keeps
; real state per slot (a countdown and which candidate it's using) so
; positions and timing genuinely vary run to run, and rate-limits
; itself to real jiffy ticks (below) rather than however fast menu_
; wait's GETIN loop happens to spin, so the pace doesn't depend on
; that loop's own speed.
;
; $10 latches the last $A2 (TIME, jiffy clock low byte) this was called
; with; work only happens once that's changed (i.e., at most once per
; 1/60 sec, however many times this actually gets called in between).
; $11-$13 are each slot's countdown (0 = inactive/available, otherwise
; ticks left until it goes fully dark); $14-$16 are each slot's
; candidate index into sparkle_offsets while active. $D012 (current
; raster line) free-runs far faster than menu_wait's own loop and isn't
; synced to it, so it's a convenient, already-ticking entropy source -
; same idea jet_reveal_letter (resident.asm) already uses for the boot
; flyby's own letter-color choice.
;
; While a slot's countdown is running, it flickers (mostly dark, lit on
; roughly 1 tick in 4 - a real flash, not a steady dot the whole time)
; rather than staying solidly on until it expires - user feedback was
; "make the sparkle flash more than it stays on". Yellow ($07), not
; white - also requested. Each activation also rolls its own random
; duration (SPARKLE_TICKS_MIN..MAX) instead of a fixed one, on top of
; the random position and random wait-until-next-one this already had,
; so nothing about a given sparkle repeats the same way twice.
SPARKLE_SLOTS      = 3
SPARKLE_COUNT      = 9      ; candidates in sparkle_offsets below
SPARKLE_CHANCE     = $7f    ; ~1-in-128 per tick that a free slot
                               ; lights (~2.1 sec average gap - was
                               ; $1f/~1-in-32/~0.5 sec, user feedback
                               ; wanted more delay between sparkles)
SPARKLE_TICKS_MIN  = 20     ; on-time once lit: MIN + (0..range), so
SPARKLE_TICKS_RANGE = $1f   ;  ~0.33-0.85 sec at 60Hz
sparkle_offsets !byte 4, 11, 20, 29, 36, 126, 135, 144, 153
menu_sparkle_update
        lda     $a2
        cmp     $10
        beq     msu_rts      ; same tick as last call - nothing to do
        sta     $10

        ldx     #0           ; age down/expire any active slots first
msu_age_loop
        lda     $11,x
        beq     msu_age_next   ; already inactive
        sec
        sbc     #1
        sta     $11,x
        beq     msu_expire      ; just hit 0 - erase and free the slot
        ldy     $14,x           ; still counting down - flicker: lit on
        lda     sparkle_offsets,y  ; roughly 1 tick in 4 (raster's low
        tay                        ; 2 bits, resampled every tick),
        lda     $d012              ; dark the rest - a flash, not a
        and     #$03               ; steady glow
        bne     msu_flicker_dark
        lda     #42          ; '*' - same value as screen code and
        sta     $0400,y      ; PETSCII for punctuation in this range
        lda     #$07         ; yellow
        sta     $d800,y
        jmp     msu_age_next
msu_flicker_dark
        lda     #$20         ; space
        sta     $0400,y
        jmp     msu_age_next
msu_expire
        ldy     $14,x
        lda     sparkle_offsets,y
        tay
        lda     #$20         ; space
        sta     $0400,y
msu_age_next
        inx
        cpx     #SPARKLE_SLOTS
        bne     msu_age_loop

        lda     $d012        ; roll for a new one - low odds, checked
        and     #SPARKLE_CHANCE  ; once per real tick (see above), so
        bne     msu_rts          ; this is a per-second-ish rate, not
                                   ; per-loop-iteration
        ldx     #0           ; find a free (inactive) slot, if any
msu_find_free
        lda     $11,x
        beq     msu_activate
        inx
        cpx     #SPARKLE_SLOTS
        bne     msu_find_free
        rts                  ; all slots busy - try again next tick

msu_activate
        lda     $d012        ; pick a pseudo-random candidate 0-8:
        eor     $a2          ; mix raster+jiffy, then reduce mod 9 by
msu_reduce                     ; repeated subtraction (no divide on
        cmp     #SPARKLE_COUNT  ; 6502) - cheap since it only runs on
        bcc     msu_reduced      ; the rare tick a slot actually lights
        sbc     #SPARKLE_COUNT   ; (carry's already right for this from
        jmp     msu_reduce       ; the cmp just above, no extra sec)
msu_reduced
        cmp     $14,x        ; same candidate this slot used last time?
        bne     msu_pos_ok   ; (still holds it even while inactive -
        clc                   ; nothing clears $14-$16 on expiry, only
        adc     #1            ; the timer) - bump to the next candidate
        cmp     #SPARKLE_COUNT  ; instead (wrapping past the last one
        bcc     msu_pos_ok      ; back to 0), guaranteeing back-to-back
        lda     #0              ; sparkles in the same slot never repeat
msu_pos_ok                       ; the same position
        sta     $14,x
        lda     $d012        ; random duration this time: a different
        eor     $a2          ; raster+jiffy mix (this one hasn't been
        and     #SPARKLE_TICKS_RANGE  ; reduced mod 9, just masked, so
        clc                            ; it's independent-ish of the
        adc     #SPARKLE_TICKS_MIN     ; position roll just above)
        sta     $11,x
msu_rts
        rts

; --- Selection pointer: CRSR UP/DOWN (menu_wait/menu_lab_wait/menu_
; diag_wait) move the CURRENT menu's own cursor (menu_cursor/lab_
; cursor/diag_cursor, selected via cur_menu - see its own comment
; above) and repaint the highlight; RETURN with nothing typed
; (menu_dispatch_num/menu_lab_dispatch_num/menu_diag_dispatch_num)
; activates whichever item it's currently on. One shared pair of
; routines for all three menus, table-driven by cur_menu (menu_item_
; counts/menu_item_counts_p1/menu_color_base_lo/menu_color_base_hi,
; above) instead of three near-identical copies - Bank 14 had the room
; for three copies (each one is small), but keeping the logic itself in
; one place means a future bug fix or tweak doesn't have to be found
; and repeated three times. Wraps at both ends (top->1 going down, 1-
; >top going up) rather than stopping, same as the top-level menu
; already did before submenus got their own pointer too.
;
; cur_menu doubles as the index into menu_cursor/lab_cursor/diag_cursor
; (consecutive zero-page bytes, $09-$0b) via indexed addressing -
; "$09,x" rather than the symbol, same oversized-addressing workaround
; menu_cursor's own comment already explains.
menu_cursor_move
        ldx     $0c             ; cur_menu - literal, see menu_cursor's
                                   ; own comment for why
        cpy     #0              ; Y = 0 for down (call site sets it),
        beq     mcm_down        ; nonzero for up
        dec     $09,x
        lda     $09,x
        bne     mcm_done
        lda     menu_item_counts,x
        sta     $09,x
        jmp     mcm_done
mcm_down
        inc     $09,x
        lda     $09,x
        cmp     menu_item_counts,x
        beq     mcm_done        ; == count is still valid, no wrap
        bcc     mcm_done        ; < count likewise
        lda     #1              ; > count - wrap back to the first item
        sta     $09,x
mcm_done
        jmp     menu_highlight_update

; Recolors the current menu's item rows' color RAM directly (not a
; redraw - the text itself never changes) - blue ($1f's raw color
; value, 6) normally, white (1) for whichever row its own cursor points
; at. Whole-row width (40 columns) regardless of each item's actual
; text length, same as a normal menu selection bar - simpler than
; tracking each line's exact length, and the blank space past shorter
; items highlighting too reads fine visually. Recoloring every row
; unconditionally on every move (rather than just erasing the old row
; and painting the new one) means there's no "previous position" to
; track and nothing to go stale if this and each menu's own initial
; draw-time call ever disagree about anything.
menu_highlight_update
        ldx     $0c             ; cur_menu - literal, see menu_cursor's
                                   ; own comment for why
        lda     $09,x           ; this menu's own cursor value
        sta     $0d             ; mhu_cursor_val
        lda     menu_item_counts_p1,x
        sta     $0e             ; mhu_item_count_p1
        lda     menu_color_base_lo,x
        sta     draw_ptr        ; reused - menu_draw isn't running
        lda     menu_color_base_hi,x  ; concurrently with this
        sta     draw_ptr+1
        ldx     #1              ; item number - X is free to become
                                   ; this now that cur_menu's been read
mhu_row_loop
        lda     #$06            ; blue (unselected)
        cpx     $0d             ; mhu_cursor_val
        bne     mhu_have_color
        lda     #$01            ; white (selected)
mhu_have_color
        ldy     #39
mhu_col_loop
        sta     (draw_ptr),y
        dey                     ; counting down to 0 needs no separate
        bpl     mhu_col_loop    ; cpy - dey itself sets N once Y wraps
                                  ; past 0 to $ff
        clc                     ; advance draw_ptr to the next row down
        lda     draw_ptr        ; (40 color-RAM bytes/row, same as
        adc     #40             ; screen RAM - real hardware layout,
        sta     draw_ptr        ; not a project convention)
        bcc     +
        inc     draw_ptr+1
+       inx
        cpx     $0e             ; mhu_item_count_p1
        bne     mhu_row_loop
        rts

; --- Cart Menu title: "SHACKMATE" at 2x size (both dimensions) - a
; pixel-doubled version of the boot splash's own bold block-letter font
; (jet_bold_font/jet_charset_setup, bank14_content.asm - same bank as
; this file now, both having moved out of Bank 0 together), not the
; same $80-$8F glyphs the flyby uses directly: those are single-size
; and stay untouched so the boot splash still looks the same. The
; doubled glyphs (jet_bold_font_big, also bank14_content.asm) patch
; into character codes $C0-$FF instead, copied into JET_CHARSET as
; part of jet_charset_setup's own one-time work, gated by the same
; jet_charset_ready flag as the rest of that routine - a plain JSR
; below, not a bank_call, since jet_charset_setup lives right here in
; Bank 14 too (see slots.asm's SLOT_JET_CHARSET_SETUP comment for the
; one caller that DOES still need a bank_call to reach it - bank0_
; content.asm's jet_setup). Like the single-size glyphs, CHROUT would
; misinterpret these codes as color/control codes rather than print
; them, so this pokes screen/color RAM directly instead of using $ffd2.
; $C0-$FF, not $A0-$DF (a $20 shift from the first version of this
; code): every code 128-255 is hardwired in the real character ROM as
; the reverse-video mirror of some code 0-127, and $A0-$DF collided
; with reverse-space and reverse-digits - confirmed live, the SELECT:
; prompt's blinking cursor showed a fragment of the bold "S" instead of
; a normal block. See jet_charset_setup's own comment (bank14_content.
; asm) for the full explanation.
; Each letter is now 4 characters wide x 2 characters tall (doubling
; both the original 2-wide x 1-tall size) - 9 letters x 4 columns = 36,
; centered on the 40-column screen with 2 columns of padding either
; side. The top half of every letter lands on one screen row, the
; bottom half on the row below; jet_letters_big_top/bot (below) hold
; the $C0-$FF codes in that order.
MENU_TITLE_ROW1   = $042a   ; $0400 + 1*40 + 2 (row 1, col 2)
MENU_TITLE_ROW2   = $0452   ; $0400 + 2*40 + 2 (row 2, col 2)
MENU_TITLE_COLOR1 = $d82a
MENU_TITLE_COLOR2 = $d852
menu_draw_title
        jsr     jet_charset_setup
        ldy     #0
mdt_loop
        lda     jet_letters_big_top,y
        sta     MENU_TITLE_ROW1,y
        lda     jet_letters_big_bot,y
        sta     MENU_TITLE_ROW2,y
        lda     #$01            ; white
        sta     MENU_TITLE_COLOR1,y
        sta     MENU_TITLE_COLOR2,y
        iny
        cpy     #36
        bne     mdt_loop
        rts

; Code pairs from bank14_content.asm's jet_bold_font_big, 4 per letter,
; left to right, spelling "SHACKMATE" (the two As share one glyph, same
; as jet_letters/jet_bold_font already do for the single-size font).
jet_letters_big_top
        !byte $c0,$c1,$c2,$c3   ; S
        !byte $c8,$c9,$ca,$cb   ; H
        !byte $d0,$d1,$d2,$d3   ; A
        !byte $d8,$d9,$da,$db   ; C
        !byte $e0,$e1,$e2,$e3   ; K
        !byte $e8,$e9,$ea,$eb   ; M
        !byte $d0,$d1,$d2,$d3   ; A
        !byte $f0,$f1,$f2,$f3   ; T
        !byte $f8,$f9,$fa,$fb   ; E
jet_letters_big_bot
        !byte $c4,$c5,$c6,$c7   ; S
        !byte $cc,$cd,$ce,$cf   ; H
        !byte $d4,$d5,$d6,$d7   ; A
        !byte $dc,$dd,$de,$df   ; C
        !byte $e4,$e5,$e6,$e7   ; K
        !byte $ec,$ed,$ee,$ef   ; M
        !byte $d4,$d5,$d6,$d7   ; A
        !byte $f4,$f5,$f6,$f7   ; T
        !byte $fc,$fd,$fe,$ff   ; E

; Reverts $D018 to the stock charset (screen $0400, char ROM $1000) -
; called right before leaving the menu (RUN/STOP in menu_open below).
; Not doing this would leave a user's own program looking at
; JET_CHARSET instead of the real character ROM: harmless for ordinary
; text (jet_charset_setup copied the whole ROM font first, patching
; only $80-$8F/$90/$C0-$FF), but the literal byte $90, or bytes $C0-$FF
; in their own program, would show the copyright glyph or a SHACKMATE
; letter fragment (single- or double-size) instead of what they
; actually typed. $80-$8F can still collide with a reverse-video
; capital letter (A-O) the same way $A0-$DF used to collide with
; reverse-space/digits (see jet_charset_setup's own comment, bank14_
; content.asm) - not fixed here, since the boot splash that uses those
; codes has no blinking cursor to expose it; worth revisiting if that
; ever changes.
menu_charset_off
        lda     #$15        ; stock: screen $0400, char ROM $1000
        sta     $d018
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

; Only MACHINE LANGUAGE TUTORIAL/BASIC WORKSPACE (4-5) still fall
; through to the generic show_stub lookup below - CARTRIDGE LAB (1),
; SID MUSIC DEMO (2), SPRITE EDITOR (3), DIAGNOSTICS (6, its own
; submenu now - see menu_diag_open below), FASTLOAD SETTINGS (7) and
; EXIT (8) all have real explicit dispatch in menu_dispatch_num, same
; as before - this table is kept complete for all 8 anyway (not just
; 4-5) purely for consistency with that existing pattern; the rest are
; simply never reached through it. CIA TIMER MONITOR/VIC-II REGISTER
; VIEWER/MEMORY VIEWER/ASSEMBLY MONITOR moved into the DIAGNOSTICS
; submenu (diag_name02/diag_name06 and FEAT_CIA/FEAT_VIC/FEAT_MEMORY
; above) and no longer have top-level entries at all.
name01 !text "CARTRIDGE LAB" : !byte 0
name02 !text "SID MUSIC DEMO" : !byte 0
name03 !text "SPRITE EDITOR" : !byte 0
name04 !text "MACHINE LANGUAGE TUTORIAL" : !byte 0
name05 !text "BASIC WORKSPACE" : !byte 0
name06 !text "DIAGNOSTICS" : !byte 0
name07 !text "FASTLOAD SETTINGS" : !byte 0
name08 !text "EXIT" : !byte 0

item_lo !byte <name01,<name02,<name03,<name04,<name05,<name06
        !byte <name07,<name08
item_hi !byte >name01,>name02,>name03,>name04,>name05,>name06
        !byte >name07,>name08

; Rows 0-2 are left blank here on purpose - rows 1 and 2 get the bold
; 2x-size "SHACKMATE" title poked directly into screen/color RAM by
; menu_draw_title (called from menu_draw, above), not printed via
; CHROUT - see that routine's own comment for why. These four leading
; $0D's just advance the cursor past them without touching their
; content, so this print picks back up at row 4 with the subtitle. No
; "====" divider below the subtitle any more - the bigger title reads
; clearly enough on its own that the divider just added visual noise
; between it and the item list.
; Row-budget note (learned the hard way once already - see git history
; for "pushed off the screen"): this whole block has to land "SELECT: "
; on row 24, the screen's last one, with zero rows to spare - one more
; blank row anywhere below would overflow to a nonexistent row 25 and
; scroll the whole screen (title included) up and off the top.
; Item rows start at MENU_ITEM_FIRST_ROW (menu_highlight_update, above)
; - keep that constant in sync if this layout changes again.
menu_data
        !byte   $0d,$0d,$0d,$0d
        !byte   $9f                                        ; cyan
        !text   "           SUPER CARTRIDGE V1"
        !byte   $0d,$0d
        !byte   $1f                                        ; blue
        !text   "1. CARTRIDGE LAB"
        !byte   $0d
        !text   "2. SID MUSIC DEMO"
        !byte   $0d
        !text   "3. SPRITE EDITOR"
        !byte   $0d
        !text   "4. MACHINE LANGUAGE TUTORIAL"
        !byte   $0d
        !text   "5. BASIC WORKSPACE"
        !byte   $0d
        !text   "6. DIAGNOSTICS"
        !byte   $0d
        !text   "7. FASTLOAD SETTINGS"
        !byte   $0d
        !text   "8. EXIT"
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

; No "!source features.asm/bitmap.asm/spriteeditor.asm" here any more -
; they moved to Bank 15 (bank15_content.asm), reached through
; feat_call/feat_dispatch above instead of a plain same-bank JSR - see
; slots.asm's SLOT_FEAT_DISPATCH comment for the full story.
