; Explorer ROM menu features with real implementations.
; Included from common.asm. Shares its zero-page conventions: these
; routines' own scratch variables live in $18-$1C, chosen to avoid
; common.asm's $02-$08 range. Like everything else here, any of these
; variables MUST be zero page, not inline data — the cartridge build's
; code segment is read-only ROM, so an inline byte could never be written.
hd_addr  = $18       ; 2 bytes ($18/$19): print_hexdump start address
hd_count = $1a       ; 2 bytes ($1a/$1b): print_hexdump byte count
jt_val   = $1c       ; joystick port snapshot
sp_pos   = $1d       ; 4 bytes: sprite0 x,y / sprite1 x,y
sp_dir   = $21       ; 4 bytes: per-axis direction (0=increasing,1=decreasing)
collision_count = $25
compass_idx = $26    ; current compass frame, 0-7
frame_ptr = $27      ; 2 bytes ($27/$28): source pointer for sprite-frame copies

; --- Wait for a keypress, then return (shared tail for these screens) ---
feat_wait_return
        jsr     $ffe4
        beq     feat_wait_return
        rts

; --- Print A as two hex digits ---
print_hex
        pha
        lsr
        lsr
        lsr
        lsr
        jsr     print_nybble
        pla
print_nybble
        and     #$0f
        cmp     #$0a
        bcc     pn_digit
        clc
        adc     #$07
pn_digit
        clc
        adc     #$30
        jmp     $ffd2

; --- Hex dump: hd_addr = start, hd_count = byte count (16-bit) ---
; 8 bytes per row as "AAAA: b0 b1 b2 b3 b4 b5 b6 b7".
print_hexdump
hd_loop
        lda     hd_count
        ora     hd_count+1
        beq     hd_done
        lda     hd_addr+1
        jsr     print_hex
        lda     hd_addr
        jsr     print_hex
        lda     #$3a         ; ':'
        jsr     $ffd2
        lda     #$20
        jsr     $ffd2
        ldy     #$00
hd_row
        lda     hd_count
        ora     hd_count+1
        beq     hd_row_done
        lda     (hd_addr),y
        jsr     print_hex
        lda     #$20
        jsr     $ffd2
        lda     hd_count     ; hd_count -= 1 (16-bit)
        bne     hd_dec_lo
        dec     hd_count+1
hd_dec_lo
        dec     hd_count
        iny
        cpy     #$08
        bne     hd_row
hd_row_done
        lda     #$0d
        jsr     $ffd2
        tya                  ; hd_addr += Y (bytes printed this row)
        clc
        adc     hd_addr
        sta     hd_addr
        bcc     hd_loop
        inc     hd_addr+1
        jmp     hd_loop
hd_done
        rts

; --- Graphics Demo: color-cycle intro, then two bouncing hardware
; sprites with real VIC-II sprite-sprite collision detection ---
feat_graphics_demo
        lda     #$93
        jsr     $ffd2
        ldx     #$00
fgd_hdr
        lda     gd_hdr,x
        beq     fgd_colors
        jsr     $ffd2
        inx
        bne     fgd_hdr

; short color-cycle intro (~1.6 sec, not interruptible - it's brief)
fgd_colors
        ldx     #$00
fgd_color_loop
        stx     $d020
        stx     $d021
        txa
        pha
        lda     #6
        jsr     delay
        pla
        tax
        inx
        cpx     #$10
        bne     fgd_color_loop
        lda     #$00
        sta     $d020
        sta     $d021

; The cartridge build's code lives in ROM the VIC-II can't see (it has
; its own bus and always reads underlying RAM, regardless of what the
; CPU has banked in) -- so the sprite shape has to be copied into RAM
; the VIC can actually see, not just pointed at wherever it's assembled.
; $2000 is block-aligned (128 = $2000/64) and well clear of our own
; code in either build.
        ldx     #$00
fgd_copy_sprite
        lda     sprite_shape,x
        sta     $2000,x
        inx
        cpx     #63
        bne     fgd_copy_sprite

        lda     #$80         ; sprite pointer block 128 = $2000/64
        sta     $07f8        ; sprite 0 pointer (in default screen's
        sta     $07f9        ; sprite 1 pointer  pointer bytes, $07F8-F)
        lda     #$00
        sta     $d017        ; normal size - the compass phase turns on
        sta     $d01d        ; 2x expand for sprite 0, and a second run of
                              ; this demo would otherwise inherit that
        lda     #$03
        sta     $d015        ; enable sprites 0 and 1
        lda     #$01
        sta     $d027        ; sprite 0 color: white
        lda     #$02
        sta     $d028        ; sprite 1 color: red

        lda     #50
        sta     sp_pos+0     ; sprite0 X
        lda     #80
        sta     sp_pos+1     ; sprite0 Y
        lda     #200
        sta     sp_pos+2     ; sprite1 X
        lda     #150
        sta     sp_pos+3     ; sprite1 Y
        lda     #$00
        sta     sp_dir+0
        sta     sp_dir+1
        sta     sp_dir+2
        sta     sp_dir+3
        sta     collision_count
        sta     $d000
        sta     $d001
        sta     $d002
        sta     $d003

fgd_sprite_loop
        ldy     #$00
        jsr     bounce_axis  ; sprite0 X
        ldy     #$01
        jsr     bounce_axis  ; sprite0 Y
        ldy     #$02
        jsr     bounce_axis  ; sprite1 X
        ldy     #$03
        jsr     bounce_axis  ; sprite1 Y

        lda     $d01e        ; sprite-sprite collision bits (clears on read)
        beq     fgd_no_coll
        inc     collision_count
        lda     #$13         ; HOME
        jsr     $ffd2
        lda     #$11         ; cursor down to the bottom status line
        ldx     #24
fgd_coll_down
        jsr     $ffd2
        dex
        bne     fgd_coll_down
        ldx     #$00
fgd_coll_msg
        lda     coll_msg,x
        beq     fgd_coll_hex
        jsr     $ffd2
        inx
        bne     fgd_coll_msg
fgd_coll_hex
        lda     collision_count
        jsr     print_hex
fgd_no_coll

        lda     #2
        jsr     delay
        jsr     $ffe4
        beq     fgd_sprite_loop  ; no key - keep animating
        jmp     fgd_compass      ; key pressed - on to the compass phase

gd_hdr
        !text   "GRAPHICS DEMO"
        !byte   $0d
        !text   "SPRITES BOUNCE - WATCH FOR COLLISIONS"
        !byte   $0d
        !text   "PRESS ANY KEY TO STOP"
        !byte   $0d,$0d,$00
coll_msg
        !text   "COLLISIONS: $"
        !byte   $00

; --- Bounce one axis and write it to the matching VIC register.
; Y = slot (0=sprite0 X, 1=sprite0 Y, 2=sprite1 X, 3=sprite1 Y). ---
bounce_axis
        lda     sp_dir,y
        bne     ba_dec
        lda     sp_pos,y
        clc
        adc     sp_step,y
        cmp     sp_max,y
        bcc     ba_store
        ldx     sp_max,y     ; hit the max edge - clamp and reverse
        lda     #$01
        sta     sp_dir,y
        txa
        jmp     ba_store
ba_dec
        lda     sp_pos,y
        sec
        sbc     sp_step,y
        cmp     sp_min,y
        bcs     ba_store
        ldx     sp_min,y     ; hit the min edge - clamp and reverse
        lda     #$00
        sta     sp_dir,y
        txa
ba_store
        sta     sp_pos,y
        ldx     sp_vicreg,y
        sta     $d000,x
        rts

sp_min    !byte 24,50,24,50
sp_max    !byte 250,229,250,229
sp_step   !byte 2,1,3,2
sp_vicreg !byte 0,1,2,3

; 24x21 sprite: a simple filled 12x12 block, centered.
sprite_shape
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $03,$ff,$c0
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00

; --- Compass phase: a single hi-res (not multicolor) sprite that hops
; around the drawn ring itself -- N, NE, E, SE, S, SW, W, NW, cycling
; like a wind vane -- with its needle tip pointing outward past the
; ring at each stop, plus a text label. Runs until a key is pressed. ---
fgd_compass
        lda     #$93
        jsr     $ffd2
        ldx     #$00
fgdc_hdr
        lda     compass_hdr,x
        beq     fgdc_hdr_pause
        jsr     $ffd2
        inx
        bne     fgdc_hdr
fgdc_hdr_pause
        lda     #60          ; ~1 sec to read the header before the
        jsr     delay        ; screen switches to the bitmap graphic
fgdc_setup
        jsr     bitmap_mode_on
        jsr     draw_compass_bitmap

        lda     #$fd         ; block 253 = $3f40/64 -- NOT the $2000 buffer
        sta     $07f8        ; the bounce phase used: that's now the bitmap
        lda     #$01         ; (occupies $2000-$3F3F), active at the same
        sta     $d015        ; time as this sprite copy runs, unlike before
        sta     $d027        ; white
        sta     $d017        ; double height -- 2x makes it a real needle
        sta     $d01d        ; instead of a speck lost in the ring
        lda     #$00
        sta     compass_idx

fgdc_loop
        ldx     compass_idx
        lda     frame_lo,x
        sta     frame_ptr
        lda     frame_hi,x
        sta     frame_ptr+1
        ldy     #$00
fgdc_copy
        lda     (frame_ptr),y
        sta     $3f40,y
        iny
        cpy     #63
        bne     fgdc_copy

        lda     compass_sp_x,x   ; hop the sprite to this frame's spot on
        sta     $d000            ; the ring itself, rather than sitting
        lda     compass_sp_y,x   ; fixed at the hub -- same X index as the
        sta     $d001            ; frame tables above, so it stays in sync

        lda     #25
        jsr     delay
        jsr     $ffe4
        bne     fgdc_done

        inc     compass_idx
        lda     compass_idx
        cmp     #8
        bne     fgdc_loop
        lda     #$00
        sta     compass_idx
        jmp     fgdc_loop

fgdc_done
        lda     #$00
        sta     $d015        ; disable sprite before leaving
        jsr     bitmap_mode_off
        rts

compass_hdr
        !text   "COMPASS - WIND DIRECTION"
        !byte   $0d
        !text   "PRESS ANY KEY TO STOP"
        !byte   $0d,$0d,$00
        !byte   $00

frame_lo !byte <compass_n,<compass_ne,<compass_e,<compass_se
         !byte <compass_s,<compass_sw,<compass_w,<compass_nw
frame_hi !byte >compass_n,>compass_ne,>compass_e,>compass_se
         !byte >compass_s,>compass_sw,>compass_w,>compass_nw

; --- Per-direction sprite position, same N/NE/E/SE/S/SW/W/NW order as
; frame_lo/frame_hi above. draw_ring (bitmap.asm) draws its ring at
; radius 90 around bitmap pixel (127,100); these are that same ring,
; one point per compass direction, converted to sprite coordinates via
; spriteX = bitmapX+1, spriteY = bitmapY+31 -- the exact offset the
; original fixed hub placement (bitmap 127,100 -> sprite 128,131) was
; already using, just generalized to the other 7 ring points instead
; of only ever landing on the center. Each frame's needle tip faces
; away from its own hub within its 24x21 sprite image (see compass_n
; etc. below), so placing that hub here makes the tip point outward
; past the ring at every stop.
compass_sp_x !byte 128,192,218,192,128,64,38,64
compass_sp_y !byte 41,67,131,195,221,195,131,67

; Each frame is the same 4x4 center hub (rows 8-11, cols 10-13) plus a
; pointer aimed at that direction. N/S/E/W get real triangles -- a
; sprite row is a horizontal strip, so a shape that tapers row-by-row
; reads cleanly as a triangle for vertical directions, and for E/W the
; taper runs across a few rows to fake a sideways arrowhead. The
; diagonals (NE/SE/SW/NW) use a 3-step stair of shrinking blocks along
; the diagonal instead -- a real single-point triangle isn't legible
; at this resolution on a 45-degree angle, so this is an honest
; wedge/streak rather than a claimed triangle.
compass_n
        !byte $00,$18,$00    ; tip
        !byte $00,$3c,$00
        !byte $00,$7e,$00
        !byte $00,$ff,$00    ; base
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00

compass_s
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$ff,$00    ; base
        !byte $00,$7e,$00
        !byte $00,$3c,$00
        !byte $00,$18,$00    ; tip
        !byte $00,$00,$00

compass_e
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$3c,$c0    ; base (near hub)
        !byte $00,$3c,$f8    ; widest point (tip row)
        !byte $00,$3c,$f8    ; widest point (tip row)
        !byte $00,$3c,$c0    ; base (near hub)
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00

compass_w
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $03,$3c,$00    ; base (near hub)
        !byte $1f,$3c,$00    ; widest point (tip row)
        !byte $1f,$3c,$00    ; widest point (tip row)
        !byte $03,$3c,$00    ; base (near hub)
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00

compass_ne
        !byte $00,$00,$0f    ; outer step
        !byte $00,$00,$3c
        !byte $00,$00,$f0    ; inner step
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00

compass_se
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$00,$00
        !byte $00,$00,$f0    ; inner step
        !byte $00,$00,$3c
        !byte $00,$00,$0f    ; outer step
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00

compass_sw
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$00,$00
        !byte $0f,$00,$00    ; inner step
        !byte $3c,$00,$00
        !byte $f0,$00,$00    ; outer step
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00

compass_nw
        !byte $f0,$00,$00    ; outer step
        !byte $3c,$00,$00
        !byte $0f,$00,$00    ; inner step
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$3c,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00
        !byte $00,$00,$00

; --- SID Music Demo: plays a short fanfare on voice 1, ENTER stops it ---
feat_sid_demo
        lda     #$93
        jsr     $ffd2
        ldx     #$00
fsd_hdr
        lda     sd_hdr,x
        beq     fsd_play
        jsr     $ffd2
        inx
        bne     fsd_hdr
fsd_play
        lda     #$0f
        sta     $d418        ; volume 15, filter off
        lda     #$09
        sta     $d405        ; attack 0, decay 9
        lda     #$00
        sta     $d406        ; sustain 0, release 0
        ldx     #$00
fsd_note_loop
        lda     sd_freq_lo,x
        sta     $d400
        lda     sd_freq_hi,x
        sta     $d401
        lda     #$11         ; triangle wave, gate on
        sta     $d404
        lda     sd_gate_dur,x
        jsr     delay
        lda     #$10         ; gate off
        sta     $d404
        lda     #5
        jsr     delay

        jsr     $ffe4        ; ENTER interrupts and stops early
        cmp     #$0d
        bne     fsd_next
        lda     #$10
        sta     $d404        ; make sure the voice is silenced
        rts
fsd_next
        inx
        cpx     #8
        bne     fsd_note_loop
        jmp     feat_wait_return

sd_hdr
        !text   "SID MUSIC DEMO"
        !byte   $0d
        !text   "STAR TREK FANFARE (APPROXIMATE)"
        !byte   $0d
        !text   "ENTER TO STOP"
        !byte   $0d,$0d,$00

; This is NOT a verified transcription -- I don't have sheet music to
; work from, just the famous fanfare's well-known shape: a couple of
; low pickup notes, a dramatic upward leap, then a stepwise descent
; back down to the same low note it started on. SID freq register =
; Hz * 16777216 / 985248 (PAL clock).
;                 D3    A3    A4    G4    F4    E4    D4    D3
sd_freq_lo  !byte <2500,<3746,<7491,<6674,<5946,<5613,<5000,<2500
sd_freq_hi  !byte >2500,>3746,>7491,>6674,>5946,>5613,>5000,>2500
sd_gate_dur !byte 10,   10,   40,   12,   12,   12,   12,   40

; --- Joystick Tester: live-reads port 2 (CIA1 $DC00), active-low bits ---
feat_joystick_tester
        lda     #$93
        jsr     $ffd2
        ldx     #$00
fjt_hdr
        lda     jt_hdr,x
        beq     fjt_loop
        jsr     $ffd2
        inx
        bne     fjt_hdr
fjt_loop
        lda     #$13         ; HOME
        jsr     $ffd2
        lda     #$11         ; cursor down x4 to the status line
        jsr     $ffd2
        jsr     $ffd2
        jsr     $ffd2
        jsr     $ffd2
        lda     $dc00
        sta     jt_val
        ldx     #$00
fjt_bit_loop
        lda     jt_labels,x
        jsr     $ffd2
        lda     #$3a         ; ':'
        jsr     $ffd2
        lda     jt_val
        and     jt_masks,x
        bne     fjt_released ; bit set = released (active low)
        lda     #$2a         ; '*' = pressed
        jmp     fjt_print
fjt_released
        lda     #$2e         ; '.' = released
fjt_print
        jsr     $ffd2
        lda     #$20
        jsr     $ffd2
        inx
        cpx     #$05
        bne     fjt_bit_loop
        jsr     $ffe4
        beq     fjt_loop
        rts

jt_hdr
        !text   "JOYSTICK TESTER (PORT 2)"
        !byte   $0d
        !text   "PRESS ANY KEY TO RETURN"
        !byte   $0d,$0d,$00
jt_masks !byte $01,$02,$04,$08,$10   ; up,down,left,right,fire
jt_labels !text "UDLRF"

; --- CIA #1 Timer Monitor: hex dump of $DC00-$DC0F ---
feat_cia_monitor
        lda     #$93
        jsr     $ffd2
        ldx     #$00
fcm_hdr
        lda     cm_hdr,x
        beq     fcm_dump
        jsr     $ffd2
        inx
        bne     fcm_hdr
fcm_dump
        lda     #<$dc00
        sta     hd_addr
        lda     #>$dc00
        sta     hd_addr+1
        lda     #16
        sta     hd_count
        lda     #$00
        sta     hd_count+1
        jsr     print_hexdump
        jmp     feat_wait_return

cm_hdr
        !text   "CIA #1 REGISTERS ($DC00-$DC0F)"
        !byte   $0d,$0d,$00

; --- VIC-II Register Viewer: hex dump of $D000-$D02E ---
feat_vic_viewer
        lda     #$93
        jsr     $ffd2
        ldx     #$00
fvv_hdr
        lda     vv_hdr,x
        beq     fvv_dump
        jsr     $ffd2
        inx
        bne     fvv_hdr
fvv_dump
        lda     #<$d000
        sta     hd_addr
        lda     #>$d000
        sta     hd_addr+1
        lda     #47
        sta     hd_count
        lda     #$00
        sta     hd_count+1
        jsr     print_hexdump
        jmp     feat_wait_return

vv_hdr
        !text   "VIC-II REGISTERS ($D000-$D02E)"
        !byte   $0d,$0d,$00

; --- Memory Viewer: hex dump of zero page ($00-$7F) ---
feat_memory_viewer
        lda     #$93
        jsr     $ffd2
        ldx     #$00
fmv_hdr
        lda     mv_hdr,x
        beq     fmv_dump
        jsr     $ffd2
        inx
        bne     fmv_hdr
fmv_dump
        lda     #$00
        sta     hd_addr
        sta     hd_addr+1
        lda     #128
        sta     hd_count
        lda     #$00
        sta     hd_count+1
        jsr     print_hexdump
        jmp     feat_wait_return

mv_hdr
        !text   "MEMORY VIEWER - ZERO PAGE ($00-$7F)"
        !byte   $0d,$0d,$00
