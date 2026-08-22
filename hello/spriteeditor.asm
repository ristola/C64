; Sprite Editor: single-color 24x21 hi-res sprite, edited as a text-mode
; grid with a live hardware-sprite preview alongside it. Its own bank
; (16) - relocated out of Bank 15 (Menu Features) once the CARTRIDGE
; LAB port needed the room; reached via a cross-bank bank_call from
; Bank 15's own feat_dispatch (SLOT_SPRITE_EDITOR, slots.asm) rather
; than a same-bank JSR, since it's a self-contained feature that never
; needs a SECOND round-trip mid-operation (unlike bitmap.asm, which
; stayed in Bank 15 because the graphics demo calls into it repeatedly
; every frame - cross-bank overhead on every one of those would be a
; real cost, not just a one-time entry/exit).
;
; Edits happen directly in the sprite data buffer at $2000 (block 128 =
; $2000/64) - the same scratch block feat_graphics_demo uses transiently
; for its bounce-phase sprite - so there's no separate "compile" step:
; toggling a grid cell writes straight into the bytes the VIC is already
; reading, and the preview updates on the very next frame.
;
; Persistent cursor position lives in ordinary RAM at $CA00+, not zero
; page: this file's code segment is cartridge ROM (can't be written),
; and zero page's protected span ($02-$38 - see hello_cart.asm's
; zp_save) is already fully claimed by the other feature files. Plain
; RAM sidesteps both problems, since none of this needs indirect
; addressing - $2000,X / $2000,Y with an 8-bit offset reaches the whole
; 63-byte sprite.
; Same 8-entry bit-mask table bitmap.asm declares (SET/CLEAR PIXEL's own
; needs) - redeclared here rather than shared, now that this file moved
; to its own bank (16): a separate ACME assembly pass never sees
; bitmap.asm's copy, same "redeclare identically" convention this
; project already uses for num_val/dly_cnt between common.asm and
; features.asm.
bitmask !byte $80,$40,$20,$10,$08,$04,$02,$01

se_cur_x  = $ca00     ; cursor column, 0-23
se_cur_y  = $ca01     ; cursor row, 0-20
se_tmp    = $ca02     ; fse_calc_offset scratch
se_row    = $ca03     ; fse_draw_grid's current row while printing
se_col    = $ca04     ; fse_draw_grid's current column while printing
se_tmp2   = $ca05     ; fdg_print_cell scratch

feat_sprite_editor
        lda     #$93
        jsr     $ffd2
        ldx     #$00
fse_hdr
        lda     se_hdr,x
        beq     fse_init
        jsr     $ffd2
        inx
        bne     fse_hdr

; Blank the sprite buffer - it's shared scratch, so don't trust
; whatever the last demo that touched $2000 left behind.
fse_init
        ldx     #$00
        lda     #$00
fse_init_loop
        sta     $2000,x
        inx
        cpx     #63
        bne     fse_init_loop

        lda     #$00
        sta     se_cur_x
        sta     se_cur_y

; Hardware sprite 0 = live preview, parked clear of the 24-column grid
; (which occupies text columns 0-23, leaving 24-39 free on the right).
        lda     #$80        ; block 128 = $2000/64
        sta     $07f8
        lda     #$01
        sta     $d015       ; enable sprite 0
        sta     $d017       ; 2x2 expand - a 24x21 sprite at true scale
        sta     $d01d       ; reads as barely more than a smudge; doubled
        sta     $d027       ; is easier to read back against the grid, and
        lda     #226        ; clear of the 24-column grid to its left
        sta     $d000       ; (col 24 starts at sprite-space 216)
        lda     #70
        sta     $d001

fse_loop
        jsr     fse_draw_grid
        jsr     $ffe4
        beq     fse_loop

        cmp     #$03        ; RUN/STOP - exit
        beq     fse_done
        cmp     #$11        ; CRSR DOWN
        bne     +
        jsr     fse_move_down
        jmp     fse_loop
+
        cmp     #$91        ; CRSR UP
        bne     +
        jsr     fse_move_up
        jmp     fse_loop
+
        cmp     #$1d        ; CRSR RIGHT
        bne     +
        jsr     fse_move_right
        jmp     fse_loop
+
        cmp     #$9d        ; CRSR LEFT
        bne     +
        jsr     fse_move_left
        jmp     fse_loop
+
        cmp     #$20        ; SPACE - toggle the pixel under the cursor
        bne     +
        jsr     fse_toggle
        jmp     fse_loop
+
        cmp     #$43        ; 'C' - clear
        bne     +
        jsr     fse_clear_all
        jmp     fse_loop
+
        cmp     #$46        ; 'F' - fill
        bne     +
        jsr     fse_fill_all
        jmp     fse_loop
+
        jmp     fse_loop

fse_done
        lda     #$00
        sta     $d015       ; disable the preview sprite
        rts

fse_move_down
        inc     se_cur_y
        lda     se_cur_y
        cmp     #21
        bne     +
        lda     #$00
        sta     se_cur_y
+
        rts

fse_move_up
        dec     se_cur_y
        bpl     +
        lda     #20
        sta     se_cur_y
+
        rts

fse_move_right
        inc     se_cur_x
        lda     se_cur_x
        cmp     #24
        bne     +
        lda     #$00
        sta     se_cur_x
+
        rts

fse_move_left
        dec     se_cur_x
        bpl     +
        lda     #23
        sta     se_cur_x
+
        rts

; --- byte offset (X) and bit mask index (Y) for (se_cur_x,se_cur_y) ---
; offset = cur_y*3 + cur_x/8 (3 bytes/row, 24 cols = 3 bytes wide);
; bit index = cur_x mod 8, used against bitmap.asm's bitmask table.
fse_calc_offset
        lda     se_cur_y
        asl
        clc
        adc     se_cur_y    ; A = cur_y*3
        sta     se_tmp
        lda     se_cur_x
        lsr
        lsr
        lsr                ; A = cur_x/8
        clc
        adc     se_tmp
        tax
        lda     se_cur_x
        and     #$07
        tay
        rts

fse_toggle
        jsr     fse_calc_offset
        lda     $2000,x
        eor     bitmask,y
        sta     $2000,x
        rts

fse_clear_all
        ldx     #$00
        lda     #$00
fca_loop
        sta     $2000,x
        inx
        cpx     #63
        bne     fca_loop
        rts

fse_fill_all
        ldx     #$00
        lda     #$ff
ffa_loop
        sta     $2000,x
        inx
        cpx     #63
        bne     ffa_loop
        rts

; --- Redraw the whole grid + status lines every loop iteration.
; Simpler and safer than tracking/erasing just the moved cursor cell,
; and cheap enough at keypress-driven speed (not an animation loop) -
; HOME + fixed line counts keeps it in place without scrolling, same
; pattern feat_joystick_tester already uses for its live status line. --
fse_draw_grid
        lda     #$13        ; HOME
        jsr     $ffd2

        lda     #$00
        sta     se_row
fdg_row_loop
        lda     #$00
        sta     se_col
fdg_col_loop
        lda     se_col
        cmp     se_cur_x
        bne     fdg_not_cursor
        lda     se_row
        cmp     se_cur_y
        bne     fdg_not_cursor
        lda     #$12        ; RVS ON - highlight the cursor cell
        jsr     $ffd2
        jsr     fdg_print_cell
        lda     #$92        ; RVS OFF
        jsr     $ffd2
        jmp     fdg_col_next
fdg_not_cursor
        jsr     fdg_print_cell
fdg_col_next
        inc     se_col
        lda     se_col
        cmp     #24
        bne     fdg_col_loop

        lda     #$0d
        jsr     $ffd2
        inc     se_row
        lda     se_row
        cmp     #21
        bne     fdg_row_loop

        ldx     #$00
fdg_status
        lda     se_status,x
        beq     fdg_status_done
        jsr     $ffd2
        inx
        bne     fdg_status
fdg_status_done
        rts

; prints '*' (set) or '.' (clear) for the pixel at (se_col,se_row)
fdg_print_cell
        lda     se_row
        asl
        clc
        adc     se_row      ; A = row*3
        sta     se_tmp2
        lda     se_col
        lsr
        lsr
        lsr
        clc
        adc     se_tmp2
        tax
        lda     se_col
        and     #$07
        tay
        lda     $2000,x
        and     bitmask,y
        beq     fdg_off
        lda     #$2a        ; '*'
        jmp     $ffd2
fdg_off
        lda     #$2e        ; '.'
        jmp     $ffd2

se_hdr
        !text   "SPRITE EDITOR"
        !byte   $0d,$00

se_status
        !text   "SPACE=TOGGLE  C=CLEAR  F=FILL"
        !byte   $0d
        !text   "CRSR=MOVE  STOP=EXIT"
        !byte   $0d,$00
