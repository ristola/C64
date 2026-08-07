; Bank 2 content: GRAPHICS category (HIRES/MULTI/TEXT/PLOT/LINE/BOX/
; CIRCLE/PAINT). All stubs for now - each prints its own name via a
; small inline loop (fixed compile-time address; see resident.asm's
; print_stub_suffix comment for why a shared routine can't take a
; runtime pointer here), then the shared print_stub_suffix tail. Real
; logic (porting bitmap.asm's set_pixel/bitmap_mode_on core, writing
; the LINE/BOX/CIRCLE/PAINT algorithms from scratch) comes later.

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_HIRES-*, $ff
        jmp     HiresCmd
!fill SLOT_MULTI-*, $ff
        jmp     MultiCmd
!fill SLOT_TEXT-*, $ff
        jmp     TextCmd
!fill SLOT_PLOT-*, $ff
        jmp     PlotCmd
!fill SLOT_LINE-*, $ff
        jmp     LineCmd
!fill SLOT_BOX-*, $ff
        jmp     BoxCmd
!fill SLOT_CIRCLE-*, $ff
        jmp     CircleCmd
!fill SLOT_PAINT-*, $ff
        jmp     PaintCmd

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill BANK_CONTENT_START-*, $ff

*=BANK_CONTENT_START

HiresCmd
        ldx     #0
hires_print_loop
        lda     hires_name,x
        beq     hires_print_done
        jsr     $ffd2
        inx
        bne     hires_print_loop
hires_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
MultiCmd
        ldx     #0
multi_print_loop
        lda     multi_name,x
        beq     multi_print_done
        jsr     $ffd2
        inx
        bne     multi_print_loop
multi_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
TextCmd
        ldx     #0
text_print_loop
        lda     text_name,x
        beq     text_print_done
        jsr     $ffd2
        inx
        bne     text_print_loop
text_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
PlotCmd
        ldx     #0
plot_print_loop
        lda     plot_name,x
        beq     plot_print_done
        jsr     $ffd2
        inx
        bne     plot_print_loop
plot_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
LineCmd
        ldx     #0
line_print_loop
        lda     line_name,x
        beq     line_print_done
        jsr     $ffd2
        inx
        bne     line_print_loop
line_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
BoxCmd
        ldx     #0
box_print_loop
        lda     box_name,x
        beq     box_print_done
        jsr     $ffd2
        inx
        bne     box_print_loop
box_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
CircleCmd
        ldx     #0
circle_print_loop
        lda     circle_name,x
        beq     circle_print_done
        jsr     $ffd2
        inx
        bne     circle_print_loop
circle_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
PaintCmd
        ldx     #0
paint_print_loop
        lda     paint_name,x
        beq     paint_print_done
        jsr     $ffd2
        inx
        bne     paint_print_loop
paint_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic

hires_name
        !text   "HIRES"
        !byte   0
multi_name
        !text   "MULTI"
        !byte   0
text_name
        !text   "TEXT"
        !byte   0
plot_name
        !text   "PLOT"
        !byte   0
line_name
        !text   "LINE"
        !byte   0
box_name
        !text   "BOX"
        !byte   0
circle_name
        !text   "CIRCLE"
        !byte   0
paint_name
        !text   "PAINT"
        !byte   0
