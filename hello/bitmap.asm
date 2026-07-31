; Real VIC-II hi-res bitmap mode (320x200, 1 bit/pixel) for the compass
; rose, replacing the character-based dots -- a genuine smooth circle
; instead of 16 sparse "." characters. Included from common.asm.
;
; Bitmap lives at $2000-$3F3F (8000 bytes, must be $2000/$0000-aligned
; within the current 16K VIC bank). That collides with the sprite-frame
; copy buffer the compass/bounce phases also use at $2000, but they
; never run at the same time as this bitmap, so it's a safe reuse.
;
; Zero page ($2b-$37): px/py = set_pixel's pixel coordinates; pix_addr
; = computed bitmap byte address; bit_row = scanline within the 8x8
; cell; font_ptr = current glyph; plot_x/plot_y = glyph blit position;
; saved_d011/d018 = video mode registers, to restore text mode after;
; bm_ptr = scratch pointer for the clear/color-fill loops.
px = $2b
py = $2c
pix_addr = $2d
bit_row = $2f
font_ptr = $30
plot_x = $32
plot_y = $33
saved_d011 = $34
saved_d018 = $35
bm_ptr = $36
bl_bits = $38        ; blit_letter's scratch for the current row's byte

; --- set_pixel: plot a white pixel at (px,py). px=0-255, py=0-199.
; Preserves X/Y (the ring/font-blit loops both use X as their own
; index across this call -- learned that the hard way twice already
; this session with delay() and goto_rc doing the same clobbering). ---
set_pixel
        txa
        pha
        tya
        pha

        lda     py
        lsr
        lsr
        lsr
        tax                  ; X = cell row 0-24
        lda     py
        and     #$07
        sta     bit_row      ; scanline within the cell, 0-7

        lda     px
        and     #$f8         ; (px/8)*8 -- the cell-column's byte offset
        clc
        adc     row_lo,x
        sta     pix_addr
        lda     row_hi,x
        adc     #$00
        sta     pix_addr+1
        lda     pix_addr
        clc
        adc     bit_row
        sta     pix_addr
        bcc     sp_nocarry
        inc     pix_addr+1
sp_nocarry
        lda     px
        and     #$07
        tax
        lda     bitmask,x
        ldy     #$00
        ora     (pix_addr),y
        sta     (pix_addr),y

        pla
        tay
        pla
        tax
        rts

bitmask !byte $80,$40,$20,$10,$08,$04,$02,$01

; Byte offset of bitmap row-band R*8 (R=0-24): 320 bytes per band (40
; cells x 8 bytes), added to (px/8)*8 + (py mod 8) in set_pixel.
row_lo
        !byte <(0*320),<(1*320),<(2*320),<(3*320),<(4*320)
        !byte <(5*320),<(6*320),<(7*320),<(8*320),<(9*320)
        !byte <(10*320),<(11*320),<(12*320),<(13*320),<(14*320)
        !byte <(15*320),<(16*320),<(17*320),<(18*320),<(19*320)
        !byte <(20*320),<(21*320),<(22*320),<(23*320),<(24*320)
; +$2000 baked in here (the bitmap base) so pix_addr ends up as the
; actual absolute address -- row_lo needs no equivalent adjustment
; since $2000's low byte is 0. Without this, set_pixel silently wrote
; to low memory/zero page instead of the bitmap; found by hand-tracing
; since the bitmap stayed all-zero no matter how long I waited.
row_hi
        !byte >(0*320+$2000),>(1*320+$2000),>(2*320+$2000),>(3*320+$2000),>(4*320+$2000)
        !byte >(5*320+$2000),>(6*320+$2000),>(7*320+$2000),>(8*320+$2000),>(9*320+$2000)
        !byte >(10*320+$2000),>(11*320+$2000),>(12*320+$2000),>(13*320+$2000),>(14*320+$2000)
        !byte >(15*320+$2000),>(16*320+$2000),>(17*320+$2000),>(18*320+$2000),>(19*320+$2000)
        !byte >(20*320+$2000),>(21*320+$2000),>(22*320+$2000),>(23*320+$2000),>(24*320+$2000)

; --- Clear the 8000-byte bitmap ($2000-$3F3F) to black. ---
clear_bitmap
        lda     #$00
        sta     bm_ptr
        lda     #$20
        sta     bm_ptr+1
cb_loop
        lda     #$00         ; A got reused as bm_ptr+1's high byte above -
        ldy     #$00         ; without reloading it here, this wrote $20
cb_page                      ; (leftover) instead of $00 to the whole bitmap
        sta     (bm_ptr),y
        iny
        bne     cb_page
        inc     bm_ptr+1
        lda     bm_ptr+1
        cmp     #$3f
        bne     cb_loop
        ldy     #$00
cb_final
        lda     #$00
        sta     (bm_ptr),y
        iny
        cpy     #64
        bne     cb_final
        rts

; --- Fill the 1000-byte color info area ($0400-$07E7) with white
; foreground / black background per cell. Stops well short of
; $07F8-$07FF, which are the sprite pointer bytes. ---
set_bitmap_colors
        lda     #$00
        sta     bm_ptr
        lda     #$04
        sta     bm_ptr+1
scc_loop
        ldy     #$00
scc_page
        lda     #$10
        sta     (bm_ptr),y
        iny
        bne     scc_page
        inc     bm_ptr+1
        lda     bm_ptr+1
        cmp     #$07
        bne     scc_loop
        ldy     #$00
scc_final
        lda     #$10
        sta     (bm_ptr),y
        iny
        cpy     #232
        bne     scc_final
        rts

; --- Draw the compass ring: 32 points around a circle (radius 90,
; centered at pixel 127,100), each a 2x2 blob so it reads as a
; connected ring instead of dots. Points precomputed from 8-way
; circle symmetry (5 base angles across one octant, mirrored). ---
draw_ring
        ldx     #$00
dr_loop
        lda     #127
        clc
        adc     ring_dx,x
        sta     px
        lda     #100
        clc
        adc     ring_dy,x
        sta     py
        jsr     set_pixel
        inc     px
        jsr     set_pixel
        dec     px
        inc     py
        jsr     set_pixel
        inc     px
        jsr     set_pixel
        dec     px
        dec     py
        inx
        cpx     #32
        bne     dr_loop
        rts

ring_dx
        !byte 0,90,0,-90
        !byte 64,64,-64,-64
        !byte 18,88,88,18,-18,-88,-88,-18
        !byte 34,83,83,34,-34,-83,-83,-34
        !byte 50,75,75,50,-50,-75,-75,-50
ring_dy
        !byte 90,0,-90,0
        !byte 64,-64,-64,64
        !byte 88,18,-18,-88,-88,-18,18,88
        !byte 83,34,-34,-83,-83,-34,34,83
        !byte 75,50,-50,-75,-75,-50,50,75

; --- Blit a 5x7 letter glyph at (plot_x,plot_y). font_ptr = 7 bytes,
; one per row, pattern in bits 4-0 (bit4=leftmost column). ---
blit_letter
        ldy     #$00
bl_row
        lda     (font_ptr),y
        sta     bl_bits
        tya
        clc
        adc     plot_y
        sta     py
        ldx     #$00
bl_col
        lda     bl_bits
        and     bl_masks,x
        beq     bl_skip
        txa
        clc
        adc     plot_x
        sta     px
        jsr     set_pixel    ; preserves X/Y internally
bl_skip
        inx
        cpx     #$05
        bne     bl_col
        iny
        cpy     #$07
        bne     bl_row
        rts
bl_masks !byte $10,$08,$04,$02,$01

letter_n !byte $11,$19,$15,$15,$13,$11,$11
letter_s !byte $0f,$10,$10,$0e,$01,$01,$1e
letter_e !byte $1f,$10,$10,$1e,$10,$10,$1f
letter_w !byte $11,$11,$11,$15,$15,$1b,$11

; --- Draw the whole compass background: clear bitmap, set colors,
; draw the ring, blit N/S/E/W at the 4 cardinal ring points. Caller
; must already have switched into bitmap mode. ---
draw_compass_bitmap
        jsr     clear_bitmap
        jsr     set_bitmap_colors
        jsr     draw_ring

        lda     #<letter_n
        sta     font_ptr
        lda     #>letter_n
        sta     font_ptr+1
        lda     #124
        sta     plot_x
        lda     #1
        sta     plot_y
        jsr     blit_letter

        lda     #<letter_s
        sta     font_ptr
        lda     #>letter_s
        sta     font_ptr+1
        lda     #124
        sta     plot_x
        lda     #192
        sta     plot_y
        jsr     blit_letter

        lda     #<letter_e
        sta     font_ptr
        lda     #>letter_e
        sta     font_ptr+1
        lda     #222
        sta     plot_x
        lda     #97
        sta     plot_y
        jsr     blit_letter

        lda     #<letter_w
        sta     font_ptr
        lda     #>letter_w
        sta     font_ptr+1
        lda     #27
        sta     plot_x
        lda     #97
        sta     plot_y
        jsr     blit_letter
        rts

; --- Switch into hi-res bitmap mode, saving the current text-mode
; registers so bitmap_mode_off can put them back. ---
bitmap_mode_on
        lda     $d011
        sta     saved_d011
        lda     $d018
        sta     saved_d018
        ora     #$20         ; BMM bit
        sta     $d011
        lda     #$18         ; screen/color info @ $0400, bitmap @ $2000
        sta     $d018
        rts

bitmap_mode_off
        lda     saved_d011
        sta     $d011
        lda     saved_d018
        sta     $d018
        rts
