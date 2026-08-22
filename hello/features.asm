; Explorer ROM menu features with real implementations.
; Included from common.asm. Shares its zero-page conventions: these
; routines' own scratch variables live in $18-$1C, chosen to avoid
; common.asm's $02-$08 range. Like everything else here, any of these
; variables MUST be zero page, not inline data — the cartridge build's
; code segment is read-only ROM, so an inline byte could never be written.
str_ptr  = $04       ; 2 bytes ($04/$05): id_lookup's matched-name
                       ; pointer - same physical bytes as common.asm's
                       ; own str_ptr declaration, redeclared here for
                       ; the same reason num_val/dly_cnt below are (this
                       ; is a separate ACME assembly pass that never
                       ; sees common.asm's copy)
hd_addr  = $18       ; 2 bytes ($18/$19): print_hexdump start address
hd_count = $1a       ; 2 bytes ($1a/$1b): print_hexdump byte count

; KERNAL disk I/O entry points - same addresses bank10_content.asm
; declares for DIR/DSAVE, redeclared here for feat_backup_eprom (this
; is a separate ACME assembly pass that never sees that copy).
KERNAL_SETNAM = $ffbd
KERNAL_SETLFS = $ffba
KERNAL_OPEN   = $ffc0
KERNAL_CLOSE  = $ffc3
KERNAL_CHKIN  = $ffc6
KERNAL_CHKOUT = $ffc9
KERNAL_CHRIN  = $ffcf
KERNAL_CLRCHN = $ffcc
KERNAL_READST = $ffb7

; PETSCII function-key codes - same values cartlab.asm's own KEY_F1-F8
; declare, used by feat_eprom_dump's own F-key navigation (DUMP EPROM/
; HEX VIEWER), matching the standalone's do_read_eprom controls.
KEY_F1 = $85
KEY_F2 = $89
KEY_F3 = $86
KEY_F4 = $8a
KEY_F5 = $87
KEY_F6 = $8b
KEY_F7 = $88
KEY_F8 = $8c

jt_val   = $1c       ; joystick port snapshot
frame_ptr = $27      ; 2 bytes ($27/$28): lr_dest_ptr's own backing bytes
                       ; (features.asm's LOAD/VERIFY EPROM picker) - name
                       ; kept from this var's original owner, the now-
                       ; removed graphics demo's sprite-frame copy loop
; pct_acc/PCT_STEP (slots.asm) - lr_verify_selected reuses feat_backup_
; eprom's own progress accumulator; safe, the two screens never run
; concurrently, same sharing rule as everything else in this file.

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

; --- A (0-99) -> two decimal digits via $ffd2, no leading-zero
; suppression - print_pct's own two-digit case handles that itself
; before calling this. Same shape as cartlab.asm's own print_dec. ---
print_dec
        ldy     #$00
pd_tens
        cmp     #10
        bcc     pd_ones
        sec
        sbc     #10
        iny
        bne     pd_tens
pd_ones
        pha
        tya
        beq     pd_skip_tens
        clc
        adc     #$30
        jsr     $ffd2
pd_skip_tens
        pla
        clc
        adc     #$30
        jmp     $ffd2

; --- A (0-100) -> a fixed 4-character field "NNN%" (leading spaces for
; unused hundreds/tens columns) via $ffd2 - constant width so the
; caller can update it in place later with cursor-left codes instead of
; tracking screen position. Same shape as cartlab.asm's own print_pct,
; used here by lr_verify_selected's progress display. ---
print_pct
        cmp     #100
        beq     pp_100
        pha
        lda     #$20
        jsr     $ffd2         ; hundreds column always blank under 100
        pla
        cmp     #10
        bcs     pp_two_digit
        pha
        lda     #$20
        jsr     $ffd2         ; tens column blank for single digits
        pla
        clc
        adc     #$30
        jsr     $ffd2
        jmp     pp_pct
pp_two_digit
        jsr     print_dec
        jmp     pp_pct
pp_100
        lda     #$31
        jsr     $ffd2
        lda     #$30
        jsr     $ffd2
        lda     #$30
        jsr     $ffd2
pp_pct
        lda     #$25         ; '%'
        jmp     $ffd2

; --- Print a null-terminated string. A/Y = low/high of its address.
; str_ptr reused (id_lookup's own pointer) - safe, none of this file's
; string-printing call sites run concurrently with id_lookup (BACKUP
; EPROM/READ CHIP), same sharing rule bt_ref/hd_count etc. already use
; elsewhere in this file. ---
print_str
        sta     str_ptr
        sty     str_ptr+1
        ldy     #$00
ps_loop
        lda     (str_ptr),y
        beq     ps_done
        jsr     $ffd2
        iny
        bne     ps_loop
ps_done
        rts

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

; --- EPROM/Bank Dump: live hex dump of any cartridge bank's own
; $8000-$9FFF ROM window - reads the flash/EPROM through the same
; $DE00 bank-select register the real hardware uses (see
; docs/HARDWARE_PLATFORM.md's Phase 0 board), one 8-byte row and 16-row
; (128-byte) page at a time - 128 divides the 8192-byte window evenly
; (64 pages/bank), so the last page of a bank never has to read past
; $9FFF into whatever's mapped above the cartridge window. Each page
; needs a real bank_call into resident_copy_page (resident.asm), since
; the bank being read is, by definition, not bank 15 itself for
; anything but bank 15's own page - that routine just raw-copies the
; 128 bytes into eprom_page_buf (RAM, unaffected by the bank switch);
; the actual hex/address formatting below runs after bank_return, back
; on bank 15, using the ordinary print_hex already in this file (the
; resident kernel's own budget is too tight to duplicate that loop
; there too - see resident_copy_page's comment). eprom_bank/eprom_offset
; (slots.asm) remember where the browse currently is across keypresses.
; F1=READ (refresh), F3/F4=BANK+/-, F5/F6=PAGE+/-, F7=SAVE (BACKUP
; EPROM), F8=LOAD (LOAD EPROM TO RAM's own directory picker, re-entered
; and left the same way any other nested screen here is - see
; fed_load's own comment), <-=BACK. Same key set/legend as cartlab.asm's
; own do_read_eprom (live-cartridge mode) - full redraw on every action
; rather than porting rp_update's partial-redraw optimization too: this
; file already redraws on every move elsewhere (lr_browse, lrl_show),
; and skipping that trick keeps this port smaller without losing any
; actual navigation.
feat_eprom_dump
        lda     #$00
        sta     eprom_bank
        sta     eprom_offset
        sta     eprom_offset+1
fed_show
        lda     #$93         ; clear screen
        jsr     $ffd2
        lda     #<fed_hdr_msg
        ldy     #>fed_hdr_msg
        jsr     print_str
        lda     eprom_bank
        jsr     print_hex
        lda     #<fed_hdr2_msg
        ldy     #>fed_hdr2_msg
        jsr     print_str
        jsr     fed_data
        lda     #<fed_ctrl_msg
        ldy     #>fed_ctrl_msg
        jsr     print_str
fed_wait
        jsr     $ffe4
        beq     fed_wait
        cmp     #KEY_F1
        bne     fed_w1
        jmp     fed_show        ; refresh - full clear+redraw
fed_w1  cmp     #KEY_F3
        bne     fed_w3
        jmp     fed_next_bank
fed_w3  cmp     #KEY_F4
        bne     fed_w4
        jmp     fed_prev_bank
fed_w4  cmp     #KEY_F5
        bne     fed_w5
        jmp     fed_next_page
fed_w5  cmp     #KEY_F6
        bne     fed_w6
        jmp     fed_prev_page
fed_w6  cmp     #KEY_F7
        bne     fed_w7
        jmp     fed_save
fed_w7  cmp     #KEY_F8
        bne     fed_w8
        jmp     fed_load
fed_w8  cmp     #$5f         ; back arrow
        bne     fed_wait
        rts                  ; back to CARTRIDGE LAB

; --- The 16-row hex+ASCII table alone, shared by fed_show above - ends
; in rts rather than falling into the legend, so callers can redraw
; just this part... except none here currently do (see this feature's
; own header comment on skipping rp_update); split out anyway since it
; keeps fed_show itself short and mirrors cartlab.asm's own rp_data
; split for anyone porting further changes across later. ---
fed_data
        lda     eprom_offset+1
        clc
        adc     #$80         ; window base $8000, high byte only - offset
        sta     hd_addr+1     ; is always page-aligned to 128 so this never
        lda     eprom_offset  ; needs a real 16-bit add across pages
        sta     hd_addr
        lda     #<resident_copy_page
        sta     call_ptr
        lda     #>resident_copy_page
        sta     call_ptr+1
        lda     eprom_bank
        jsr     bank_call    ; fills eprom_page_buf; hd_addr (still the
                               ; real $8000+offset address) survives the
                               ; round trip since it's zero page, not
                               ; part of the switched ROM window
        lda     #$00
        sta     hd_count     ; byte-within-page index, also drives fpr's
                               ; 128-byte loop bound (wraps 0 at 128)
fpr_row
        lda     #$24         ; '$' - not "0x": PETSCII lowercase 'x'
        jsr     $ffd2         ; doesn't render as a literal x on the C64's
                                ; default uppercase/graphics charset (shows
                                ; a graphic symbol instead) - confirmed
                                ; live. "$" matches this project's own
                                ; hex convention everywhere else anyway.
        lda     hd_addr+1
        jsr     print_hex
        lda     hd_addr
        jsr     print_hex
        lda     #$3a         ; ':'
        jsr     $ffd2
        lda     #$20
        jsr     $ffd2
        lda     hd_count     ; remember this row's starting index so the
        sta     jt_val        ; ASCII pass below can re-walk the same 8
                               ; bytes - reuses the joystick tester's own
                               ; scratch byte, safe since DUMP EPROM and
                               ; JOYSTICK TESTER never run concurrently
                               ; (same reasoning eprom_bank/hd_count
                               ; themselves are already shared on)
        ldx     #$00
fpr_col
        ldy     hd_count
        lda     eprom_page_buf,y
        jsr     print_hex
        lda     #$20
        jsr     $ffd2
        inc     hd_count
        inx
        cpx     #$08
        bne     fpr_col
        lda     jt_val       ; hex loop's own trailing space above already
        sta     hd_count     ; separates it from the ASCII column - rewind
                               ; to re-walk the same 8 bytes (39 cols total:
                               ; "$AAAA: " (7) + "XX "x8 (24) + 8 ASCII)
        ldx     #$00
fpr_ascii
        ldy     hd_count
        lda     eprom_page_buf,y
        cmp     #$20         ; below space - not printable, show '.'
        bcc     fpr_ascii_dot
        cmp     #$7f         ; DEL and above (incl. all reverse-video/
        bcs     fpr_ascii_dot ; control codes $80-$FF) - show '.' too
        jsr     $ffd2        ; $20-$7E prints as itself, safely (no
        jmp     fpr_ascii_next ; control-code side effects in this range)
fpr_ascii_dot
        lda     #$2e         ; '.'
        jsr     $ffd2
fpr_ascii_next
        inc     hd_count
        inx
        cpx     #$08
        bne     fpr_ascii
        lda     #$0d
        jsr     $ffd2
        lda     hd_addr
        clc
        adc     #$08
        sta     hd_addr
        bcc     +
        inc     hd_addr+1
+       lda     hd_count
        cmp     #128
        bne     fpr_row      ; loop until all 128 bytes are printed
        rts

fed_next_page
        lda     eprom_offset
        clc
        adc     #<128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #>128
        sta     eprom_offset+1
        lda     eprom_offset+1
        cmp     #>8192       ; whole 8K bank window shown - wrap to the
        bcs     fed_next_bank ; next bank
        jmp     fed_show
fed_next_bank
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
        inc     eprom_bank
        lda     eprom_bank
        cmp     #EPROM_PHYSICAL_BANKS  ; the installed chip's own real
        bcc     fed_show2               ; capacity, not TOTAL_BANKS - see
                                          ; that constant's own comment
                                          ; (slots.asm)
        lda     #$00
        sta     eprom_bank
fed_show2
        jmp     fed_show

fed_prev_page
        lda     eprom_offset
        ora     eprom_offset+1
        bne     fed_pp_sub
        lda     eprom_bank
        bne     fed_pp_bank_ok
        lda     #EPROM_PHYSICAL_BANKS
fed_pp_bank_ok
        sec
        sbc     #1
        sta     eprom_bank
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
        jmp     fed_show
fed_pp_sub
        lda     eprom_offset
        sec
        sbc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        sbc     #$00
        sta     eprom_offset+1
        jmp     fed_show

fed_prev_bank
        lda     eprom_bank
        bne     fed_pb_ok
        lda     #EPROM_PHYSICAL_BANKS
fed_pb_ok
        sec
        sbc     #1
        sta     eprom_bank
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
        jmp     fed_show

; --- F7=SAVE: BACKUP EPROM already writes every bank straight to disk
; on its own - this is just a shortcut into it from inside the viewer,
; same as cartlab.asm's own rp_disk_save. Resets bank/offset to 0 after,
; same as that routine does. ---
fed_save
        jsr     feat_backup_eprom
        lda     #$00
        sta     eprom_bank
        sta     eprom_offset
        sta     eprom_offset+1
        jmp     fed_show

; --- F8=LOAD: hands off to LOAD EPROM TO RAM's own directory-picker/
; multi-chunk viewer (feat_load_eprom's own entry point) rather than
; duplicating that picker a second time in here - cartlab.asm's own
; rp_disk_load switches the SAME viewer into FILE VIEW mode instead,
; but that's only possible there because do_read_eprom/rp_show already
; carry a live/file mode switch this simpler single-mode viewer doesn't
; have. Pressing back-arrow from the loaded file's own view returns to
; its file list (not straight back here) - one extra back-arrow press
; from cartlab.asm's own single-viewer flow, traded for reusing an
; already-working picker instead of a second copy of it. jsr, not jmp -
; every exit path in that whole flow ends in a plain rts, so this
; returns cleanly here regardless of which one was taken. ---
fed_load
        lda     #LR_MODE_LOAD
        sta     lr_mode
        jsr     lr_start
        lda     #$00         ; lr_start's own LOAD flow reuses eprom_
        sta     eprom_bank    ; bank/eprom_offset for its own chunk/page
        sta     eprom_offset  ; state - reset back to fed_show's own
        sta     eprom_offset+1 ; "bank 0, page 0" before returning to it
        jmp     fed_show

fed_hdr_msg
        !text   "EPROM / BANK DUMP - BANK $"
        !byte   $00
fed_hdr2_msg
        !text   " ($8000-$9FFF)"
        !byte   $0d,$0d,$00
fed_ctrl_msg
        !byte   $0d
        !text   "F1=READ  F3=BANK+  F4=BANK-"
        !byte   $0d
        !text   "F5=PAGE+  F6=PAGE-  F7=SAVE  F8=LOAD"
        !byte   $0d
        !text   "<-=BACK"
        !byte   $0d,$00

; --- BACKUP EPROM (CARTRIDGE LAB item 4): reads every physical bank
; (EPROM_PHYSICAL_BANKS, slots.asm - the installed chip's own real
; capacity, not TOTAL_BANKS) through the same bank_call/resident_
; copy_page mechanism EPROM DUMP uses, streaming the raw bytes straight
; to a disk file via KERNAL OPEN/CHKOUT/CHROUT as they're read - no
; whole-chip RAM buffer needed (64KB wouldn't fit anyway), and no
; BASIC-loadable 2-byte address header either: this is a raw 1:1
; content copy, not a PRG, so it's a faithful backup (openable in a
; hex editor, or written back to a chip later) rather than something
; meant to LOAD back into BASIC. Fixed filename, since the F1 menu has
; no text-entry UI to prompt for one. Reuses eprom_bank/eprom_offset/
; hd_count as loop counters - same "never runs concurrently with EPROM
; DUMP" reasoning that already lets those be shared between screens. ---
feat_backup_eprom
        lda     #$93
        jsr     $ffd2
        lda     #<fbe_hdr_msg
        ldy     #>fbe_hdr_msg
        jsr     print_str
fbe_hdr_dev
        lda     disk_device
        jsr     fbe_print_devnum   ; disk_device is a real 1-2 digit
                                      ; device number (no leading zero
                                      ; for single digits) - different
                                      ; from fbe_print_dec below, which
                                      ; is only ever called on a
                                      ; guaranteed two-digit 10-99 value
        lda     #$20         ; ' '
        jsr     $ffd2
        lda     #$28         ; '('
        jsr     $ffd2
fbe_open
        ; ",S,W" is required, not decorative - unlike DsaveCmd
        ; (bank10_content.asm), this uses a raw KERNAL_OPEN/CHKOUT, not
        ; the KERNAL_SAVE vector, and CBM DOS defaults a plain OPEN to
        ; READ mode when no mode letter is given. Without ",W" here,
        ; opening a not-yet-existing EPROM.BIN fails at the DOS level
        ; (FILE NOT FOUND) even though KERNAL_OPEN's own carry flag
        ; doesn't catch it - CHKOUT still "succeeds" and every CHROUT
        ; after it silently goes nowhere.
        lda     #fbe_filename_end-fbe_filename
        ldx     #<fbe_filename
        ldy     #>fbe_filename
        jsr     KERNAL_SETNAM
        lda     #2              ; logical file number
        ldx     disk_device
        ldy     #1              ; secondary address - same convention
        jsr     KERNAL_SETLFS    ; DsaveCmd's own SAVE already uses
        jsr     KERNAL_OPEN
        bcc     fbe_open_ok
        jmp     fbe_error
; be_open_ok fills in the initial "  0%)" while CHROUT is STILL on the
; SCREEN (before the CHKOUT below redirects it to the file) - printing
; it after CHKOUT, like the first version of this routine did, would
; silently write those bytes into EPROM.BIN itself instead of showing
; them (same bug already fixed in cartlab.asm's COPY - see that
; routine's own comment for how this was confirmed live).
fbe_open_ok
        lda     #$00
        sta     pct_acc
        sta     pct_acc+1
        lda     #$00
        jsr     fbe_print_pct
        lda     #$29         ; ')'
        jsr     $ffd2
        ldx     #2
        jsr     KERNAL_CHKOUT    ; redirect CHROUT to the file from here on
        bcc     fbe_write_ok
        jmp     fbe_error_close
fbe_write_ok

        lda     #$00
        sta     eprom_bank
fbe_bank_loop
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
fbe_page_loop
        lda     eprom_offset+1
        clc
        adc     #$80
        sta     hd_addr+1
        lda     eprom_offset
        sta     hd_addr
        lda     #<resident_copy_page
        sta     call_ptr
        lda     #>resident_copy_page
        sta     call_ptr+1
        lda     eprom_bank
        jsr     bank_call        ; fills eprom_page_buf with 128 bytes
        ldy     #$00
fbe_byte_loop
        lda     eprom_page_buf,y
        jsr     $ffd2            ; CHROUT, now writing to the file
        iny
        bpl     fbe_byte_loop    ; 0..127, same Y-wraps-at-128 trick
                                   ; resident_copy_page's own loop uses

        lda     eprom_offset
        clc
        adc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #$00
        sta     eprom_offset+1

        jsr     fbe_update_pct  ; every 128-byte PAGE, not just once per
                                   ; 8192-byte bank - see cartlab.asm's
                                   ; identical be_update_pct for why
                                   ; (true 1541 emulation can take 20-30
                                   ; real seconds per bank; updating only
                                   ; at bank boundaries left this screen
                                   ; static that whole time, easily read
                                   ; as a hang). Leaves CHROUT pointed at
                                   ; the SCREEN on return; re-CHKOUT to
                                   ; the file below only if there's more
                                   ; to write.
        lda     eprom_offset+1
        cmp     #>8192           ; whole 8K bank streamed - next bank
        bcs     fbe_bank_done
        ldx     #2
        jsr     KERNAL_CHKOUT
        jmp     fbe_page_loop
fbe_bank_done
        inc     eprom_bank
        lda     eprom_bank
        cmp     #EPROM_PHYSICAL_BANKS
        bcc     fbe_more_banks
        jmp     fbe_bank_loop_done  ; last bank done - CHROUT already
                                       ; back on the screen (fbe_update_
                                       ; pct left it there)
fbe_more_banks
        ldx     #2
        jsr     KERNAL_CHKOUT
        jmp     fbe_bank_loop
fbe_bank_loop_done
        lda     #2
        jsr     KERNAL_CLOSE
        lda     #<fbe_done_msg_txt
        ldy     #>fbe_done_msg_txt
        jsr     print_str
fbe_wait
        jmp     feat_wait_return

fbe_error
        pha
        lda     #<fbe_err_msg
        ldy     #>fbe_err_msg
        jsr     print_str
fbe_err_code
        pla
        ldx     #0
        jsr     print_decimal_word
        lda     #13
        jsr     $ffd2
        jmp     feat_wait_return
fbe_error_close
        lda     #2
        jsr     KERNAL_CLOSE
        jmp     fbe_error

; --- Bumps pct_acc by PCT_STEP and reprints it in place as "NNN%)" -
; the trailing ")" is part of the reprinted field (not left over from
; fbe_open_ok's own one-time print), so 5 cursor-lefts, not 4, always
; lines back up to right before the percent digits start. Identical
; technique to cartlab.asm's own be_update_pct - see that routine's
; comment for the pct_acc fixed-point reasoning. ---
fbe_update_pct
        clc
        lda     pct_acc
        adc     #PCT_STEP
        sta     pct_acc
        lda     pct_acc+1
        adc     #$00
        sta     pct_acc+1
        jsr     KERNAL_CLRCHN
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     pct_acc+1
        jsr     fbe_print_pct
        lda     #$29         ; ')'
        jsr     $ffd2
        rts

; --- A (0-100) -> fixed 4-char field "NNN%" via CHROUT, same format
; and reasoning as cartlab.asm's own print_pct (ported here since this
; file had no percent formatter yet). ---
fbe_print_pct
        cmp     #100
        beq     fpp_100
        pha
        lda     #$20
        jsr     $ffd2
        pla
        cmp     #10
        bcs     fpp_two_digit
        pha
        lda     #$20
        jsr     $ffd2
        pla
        clc
        adc     #$30
        jsr     $ffd2
        jmp     fpp_pct
fpp_two_digit
        jsr     fbe_print_dec
        jmp     fpp_pct
fpp_100
        lda     #$31
        jsr     $ffd2
        lda     #$30
        jsr     $ffd2
        lda     #$30
        jsr     $ffd2
fpp_pct
        lda     #$25         ; '%'
        jmp     $ffd2

; --- A (0-99) -> decimal digit chars via CHROUT, no leading zero -
; used once, for disk_device in the header line above (a real device
; number like "8", not a fixed-width field). ---
fbe_print_devnum
        ldy     #$00
fpdn_tens
        cmp     #10
        bcc     fpdn_ones
        sec
        sbc     #10
        iny
        jmp     fpdn_tens
fpdn_ones
        pha
        tya
        beq     fpdn_skip_tens
        clc
        adc     #$30
        jsr     $ffd2
fpdn_skip_tens
        pla
        clc
        adc     #$30
        jmp     $ffd2

; --- A (10-99) -> two ASCII decimal digit chars via CHROUT. ---
fbe_print_dec
        ldy     #$00
fpd_tens
        cmp     #10
        bcc     fpd_ones
        sec
        sbc     #10
        iny
        jmp     fpd_tens
fpd_ones
        pha
        tya
        clc
        adc     #$30
        jsr     $ffd2
        pla
        clc
        adc     #$30
        jmp     $ffd2

fbe_hdr_msg
        !text   "BACKUP EPROM"
        !byte   $0d,$0d
        !text   "SAVING EPROM.BIN,"
        !byte   $00
fbe_done_msg_txt
        !text   "BACKUP COMPLETE"
        !byte   $0d,$00
fbe_err_msg
        !text   "?SAVE ERROR "
        !byte   0
fbe_filename
        !text   "EPROM.BIN,S,W"
fbe_filename_end

; --- READ CHIP (CARTRIDGE LAB item 1): the "read" half of the
; CARTRIDGE LAB workflow - two independent things happen here, and only
; one of them can ever fail on a genuine 27Cxxx EPROM:
;
; 1. A REAL content read through resident_copy_page (the same bank_call
;    target EPROM DUMP's own paging uses), confirming the actual read
;    path - $DE00 bank-select + the live $8000-$9FFF window - works.
;    This is what eprom_read_done is now based on, and it succeeds
;    regardless of chip type; no raw hex dump here (that's EPROM DUMP's
;    own job, not this screen's), just a plain confirmation.
; 2. The JEDEC unlock/autoselect sequence (id_read_chip below), looked
;    up against id_table - informational only. A genuine 27Cxxx OTP/UV
;    EPROM has no autoselect capability at all: its Electronic
;    Signature mode needs 11.5-12.5V forced onto pin A9, a voltage this
;    board has no way to generate or switch onto the C64's own 5V
;    address bus, so no software sequence can ever read it here. That's
;    reported honestly (frc_id_unk_txt below) rather than treated as a
;    read failure - it isn't one. ---
feat_read_chip
        lda     #$93
        jsr     $ffd2
        ldx     #$00
frc_hdr
        lda     frc_hdr_msg,x
        beq     frc_proto
        jsr     $ffd2
        inx
        bne     frc_hdr
frc_proto
        lda     #<frc_proto_txt
        ldy     #>frc_proto_txt
        jsr     print_str
frc_id
        jsr     id_read_chip     ; A = mfg, X = dev
        pha
        txa
        pha
        ldx     #$00
frc_id_msg
        lda     frc_id_msg_txt,x
        beq     frc_id_show
        jsr     $ffd2
        inx
        bne     frc_id_msg
frc_id_show
        pla                      ; dev
        tax
        pla                      ; mfg
        pha
        jsr     print_hex
        lda     #$20
        jsr     $ffd2
        txa
        jsr     print_hex
        lda     #$20
        jsr     $ffd2
        pla                      ; mfg (again, for the lookup call)
        jsr     id_lookup
        bcc     frc_id_unknown
        ldy     #$00
frc_id_name
        lda     (str_ptr),y
        beq     frc_id_done
        jsr     $ffd2
        iny
        bne     frc_id_name
        jmp     frc_id_done
frc_id_unknown
        ldx     #$00
frc_id_unk_msg
        lda     frc_id_unk_txt,x
        beq     frc_id_done
        jsr     $ffd2
        inx
        bne     frc_id_unk_msg
frc_id_done
        lda     #$0d
        jsr     $ffd2
        lda     #$0d
        jsr     $ffd2

frc_content
        lda     #$00
        sta     hd_addr
        lda     #$80
        sta     hd_addr+1
        lda     #<resident_copy_page
        sta     call_ptr
        lda     #>resident_copy_page
        sta     call_ptr+1
        lda     #$00         ; bank 0
        jsr     bank_call
        lda     #$01
        sta     eprom_read_done
        lda     #<frc_content_msg_txt
        ldy     #>frc_content_msg_txt
        jsr     print_str
frc_done
        jmp     feat_wait_return

frc_content_msg_txt
        !text   "EPROM READ OK"
        !byte   $0d,$0d,$00
; --- The real JEDEC unlock/autoselect protocol id_read_chip actually
; sends (features.asm's own id_read_template) - not a database lookup
; (this project has no access to real EPROM-programmer chip-database
; "protocol ID" numbers, and won't fabricate one), just an honest trace
; of the real command bytes/addresses this code issues. ---
frc_proto_txt
        !text   "PROTOCOL:"
        !byte   $0d
        !text   " $AA->$8555  $55->$82AA"
        !byte   $0d
        !text   " $90->$8555 (ENTER ID MODE)"
        !byte   $0d
        !text   " READ $8000(MFG) $8001(DEV)"
        !byte   $0d
        !text   " $F0->$8000 (RESET)"
        !byte   $0d,$0d,$00
frc_id_msg_txt
        !text   "CHIP ID: $"
        !byte   $00
frc_id_unk_txt
        !text   "NO ID RESPONSE"
        !byte   $0d
        !text   "(27CXX EPROMS NEED 12V ON A9 FOR ID -"
        !byte   $0d
        !text   "NOT AVAILABLE ON THIS BOARD)"
        !byte   $00

; --- Copies id_read_template into RAM at id_read_ram and runs it from
; there - see id_read_ram's own comment (slots.asm) for why this can't
; just execute from this bank's own ROM. Briefly disables interrupts
; around the copied routine's own brief run - irq_hook's own bank_call
; (F1/animation handling) landing mid-unlock-sequence would corrupt
; both the pending flash command and cur_bank's bank-15 assumption.
; Returns: A = manufacturer ID, X = device ID. ---
id_read_chip
        ldy     #id_read_template_end-id_read_template-1
irc_copy
        lda     id_read_template,y
        sta     id_read_ram,y
        dey
        bpl     irc_copy
        sei
        jsr     id_read_ram
        cli
        rts

; NOTE: earlier version of this routine also toggled an EASYFLASH_
; CONTROL ($DE02) register around each write, copied from EasyFlash's
; own real EAPI driver (eapi-am29f040.s, skoe.de). That's EasyFlash-
; specific hardware, not this board: docs/HARDWARE_PLATFORM.md's own
; verified facts say the Phase 0 test board has "a single 74LS273
; 8-bit latch at $DE00, write-only. No separate control register" -
; confirmed live the hard way, writing $85 (bit 7 set) to $DE02 hung
; the real board hard enough to need a power cycle, not just RESET.
; Matches the board's own documented Magic Desk behavior exactly: bit
; 7 written to $DE00 disables the cartridge and, with LOCK=YES (the
; board's default), stays disabled "until a hardware reset" - if
; $DE02 isn't decoded as a separate register and aliases onto the same
; $DE00 latch (plausible on a board this simple), that $85 write would
; do precisely that, stranding execution in RAM once bank 15's own ROM
; disappears out from under it. Removed entirely - this board's socket
; may not even wire /WE to begin with (it reads pre-programmed chips,
; it isn't a flash programmer), in which case these writes are safely
; ignored by the chip and the ID read below just correctly reports
; UNKNOWN, same as a genuine 27Cxxx OTP EPROM would.
id_read_template
        lda     #$00
        sta     EASYFLASH_BANK   ; select bank 0 - matches the known bank
                                   ; EasyFlash's own EAPI driver checks
                                   ; against for a predictable read
        lda     #$aa
        sta     $8555
        lda     #$55
        sta     $82aa
        lda     #$90             ; enter autoselect/software ID mode
        sta     $8555
        lda     $8000            ; manufacturer ID
        pha
        ldx     $8001            ; device ID
        lda     #$f0             ; exit autoselect mode (reset command)
        sta     $8000
        lda     #15              ; restore bank 15 - this code's own
        sta     EASYFLASH_BANK    ; bank, needed before returning to ROM
        pla                      ; A = manufacturer ID (X still = device)
        rts
id_read_template_end

frc_hdr_msg
        !text   "READ EPROM"
        !byte   $0d,$0d
        !text   "READING VIA $DE00..."
        !byte   $0d,$0d,$00

; --- Curated JEDEC/Autoselect device-ID table - AM29F040B (this
; project's own Phase 1 target chip, docs/HARDWARE_PLATFORM.md) plus
; pin-compatible alternates from the same 29F/39F/29C flash family
; across the vendors likely to turn up in a DIP-32 socket. Deliberately
; NOT the full ~280-entry table this came from - most of that list is
; SPI-flash/PIC/AVR/8051 parts with no electrical path to this
; cartridge's socket at all, and classic 27Cxxx OTP/UV EPROMs (the
; Phase 0 test board's own default chip) have no JEDEC ID capability
; whatsoever - only flash-type chips (29Fxxx/39xxx/29Cxxx) can ever
; answer this query, so only those are worth cataloging here.
;
; IMPORTANT: id_lookup below is real and tested, but nothing calls it
; with a genuine hardware-read ID yet. Actually issuing the JEDEC
; unlock sequence (writes of $AA/$55/$90 to specific addresses) into a
; live 8K-banked ROM window depends on exactly how the chip's full
; address ($5555/$2AAA, which needs more address bits than the C64
; cartridge port's A0-A12 exposes) aliases down into this project's 8K
; window - not verified against a real datasheet or EasyFlash's own
; EAPI reference yet (EasyFlash-ProgRef.pdf/EasyFlash-AppSupport.pdf,
; per HARDWARE_PLATFORM.md). Same "needs a separately-verified
; sequence, not something guessed at" rule ARCHITECTURE.md already
; applies to FLASHERASE/FLASHLOAD/FLASHVERIFY - wiring this table up
; to a real read is a follow-up task, not guessed at here.
ID_COUNT = 13
id_mfg !byte $01,$01,$01,$bf,$bf,$bf,$1f,$1f,$1f,$1f,$c2,$20,$04
id_dev !byte $20,$a4,$d5,$b5,$b6,$b7,$d5,$da,$5b,$a4,$a4,$e2,$a4
id_name_lo !byte <idn00,<idn01,<idn02,<idn03,<idn04,<idn05,<idn06
           !byte <idn07,<idn08,<idn09,<idn10,<idn11,<idn12
id_name_hi !byte >idn00,>idn01,>idn02,>idn03,>idn04,>idn05,>idn06
           !byte >idn07,>idn08,>idn09,>idn10,>idn11,>idn12

idn00 !text "AMD AM29F010" : !byte 0
idn01 !text "AMD AM29F040B" : !byte 0
idn02 !text "AMD AM29F080" : !byte 0
idn03 !text "SST SST39SF010" : !byte 0
idn04 !text "SST SST39SF020" : !byte 0
idn05 !text "SST SST39SF040" : !byte 0
idn06 !text "ATMEL AT29C010A" : !byte 0
idn07 !text "ATMEL AT29C020" : !byte 0
idn08 !text "ATMEL AT29C040" : !byte 0
idn09 !text "ATMEL AT29C040A" : !byte 0
idn10 !text "MACRONIX MX29F040" : !byte 0
idn11 !text "ST M29F040B" : !byte 0
idn12 !text "FUJITSU MBM29F040" : !byte 0

; --- A=mfg byte, X=device byte -> if found in id_table, str_ptr is set
; to the matching name (null-terminated) and carry is SET; if no match,
; carry is CLEAR and str_ptr is untouched. Y clobbered. ---
id_lookup
        stx     il_dev
        ldy     #$00
il_loop
        cpy     #ID_COUNT
        beq     il_notfound
        cmp     id_mfg,y
        bne     il_next
        pha
        lda     il_dev
        cmp     id_dev,y
        beq     il_match
        pla
il_next
        iny
        jmp     il_loop
il_match
        pla                  ; discard the saved mfg byte - already matched
        lda     id_name_lo,y
        sta     str_ptr
        lda     id_name_hi,y
        sta     str_ptr+1
        sec
        rts
il_notfound
        clc
        rts
il_dev !byte 0

; ============================================================
; BANK SCANNER (CARTRIDGE LAB) - writes each bank number 0..
; EPROM_PHYSICAL_BANKS-1 to $DE00 and shows the first 8 bytes read back
; at $8000 for each, same diagnostic value and reasoning as cartlab.
; asm's own do_bank_test (see that routine's header comment for the
; full explanation of why this is the closest thing to a direct latch
; test software can do on this hardware) - ported to read through
; bank_call/resident_copy_page instead of a direct indirect read,
; since Bank 15's own code can't safely read a DIFFERENT bank's
; $8000-$9FFF window without switching itself out first. Reuses
; eprom_page_buf (only the first 8 bytes of its 128 matter here) and
; bt_ref (a new 8-byte RAM scratch spot, F1-menu-safe same as eprom_
; page_buf/id_read_ram - see slots.asm) rather than needing a second
; 128-byte buffer just to hold one reference row. ---
feat_bank_scanner
        lda     #$93
        jsr     $ffd2
        lda     #<bs_hdr_msg
        ldy     #>bs_hdr_msg
        jsr     print_str
bs_start
        lda     #$01
        sta     hd_count        ; "all identical" flag - hd_count reused,
                                    ; safe: BANK SCANNER never runs
                                    ; concurrently with EPROM DUMP/READ
                                    ; CHIP/BACKUP EPROM, same sharing
                                    ; rule those already rely on
        lda     #$00
        sta     eprom_bank
bs_loop
        lda     #$00
        sta     hd_addr
        lda     #$80
        sta     hd_addr+1
        lda     #<resident_copy_page
        sta     call_ptr
        lda     #>resident_copy_page
        sta     call_ptr+1
        lda     eprom_bank
        jsr     bank_call        ; fills eprom_page_buf (only bytes 0-7
                                    ; of it matter here)
        lda     #<bs_row_msg
        ldy     #>bs_row_msg
        jsr     print_str
        lda     eprom_bank
        jsr     print_hex
        lda     #$3a         ; ':'
        jsr     $ffd2
        lda     #$20
        jsr     $ffd2
        ldy     #$00
bs_col
        lda     eprom_page_buf,y
        jsr     print_hex
        lda     #$20
        jsr     $ffd2
        ldx     eprom_bank
        bne     bs_col_cmp
        lda     eprom_page_buf,y  ; bank 0: record as the reference row
        sta     bt_ref,y
        jmp     bs_col_next
bs_col_cmp
        lda     eprom_page_buf,y
        cmp     bt_ref,y
        beq     bs_col_next
        lda     #$00
        sta     hd_count         ; found a difference from bank 0
bs_col_next
        iny
        cpy     #$08
        bne     bs_col
        lda     #$0d
        jsr     $ffd2
        inc     eprom_bank
        lda     eprom_bank
        cmp     #EPROM_PHYSICAL_BANKS
        bne     bs_loop
        lda     #$0d
        jsr     $ffd2
        lda     hd_count
        beq     bs_differs
        lda     #<bs_identical_txt
        ldy     #>bs_identical_txt
        jsr     print_str
        jmp     bs_wait
bs_differs
        lda     #<bs_differs_txt
        ldy     #>bs_differs_txt
        jsr     print_str
bs_wait
        jmp     feat_wait_return

bs_hdr_msg
        !text   "BANK SCANNER"
        !byte   $0d,$0d,$00
bs_row_msg
        !text   "BANK $"
        !byte   $00
bs_identical_txt
        !text   "ALL BANKS SHOW IDENTICAL DATA -"
        !byte   $0d
        !text   "THE $DE00 LATCH WRITE MAY NOT BE"
        !byte   $0d
        !text   "REACHING THE CHIP AT ALL."
        !byte   $0d,$00
bs_differs_txt
        !text   "DATA DIFFERS PER BANK - BANK"
        !byte   $0d
        !text   "SWITCHING IS ELECTRICALLY WORKING."
        !byte   $0d,$00

; ============================================================
; VERIFY EPROM / LOAD EPROM TO RAM (CARTRIDGE LAB) - shared directory-
; picker UI ported from cartlab.asm's own lr_* (LOAD FILE TO RAM/
; VERIFY-COMPARE picker there). Uses disk_device directly rather than
; prompting for one (unlike cartlab.asm - this cartridge already has a
; real "DEVICE <n>" BASIC+ command setting that same variable for every
; other DISK operation, so a second, separate prompt here would just be
; inconsistent). dir_ptr/lr_dest_ptr reuse hd_addr/frame_ptr (zero page)
; rather than claiming new bytes - see slots.asm's own LR_* comment for
; the RAM window this shares with DISK's buffers, and why that's safe.
dir_ptr = hd_addr
lr_dest_ptr = frame_ptr
lr_dir_filename !text "$"

; --- LOAD EPROM TO RAM's own scratch (lr_load_selected/lrl_* below).
; FILE_BUF is the same $2000 8KB RAM window cartlab.asm's own FILE_BUF
; uses - free here now that the dead graphics-demo code (bitmap/sprite
; at $2000-$3F3F) is gone, and outside every bank's own $8000-$9FFF ROM
; window so it survives bank_call's own bank switches untouched. eprom_
; bank/eprom_offset (already declared) double as the current chunk
; index and read/page position, exactly like cartlab.asm's own do_read_
; eprom/fl_seek_chunk reuse them for FILE VIEW - safe here on the same
; "not concurrent with BANK SCANNER/VERIFY/etc" grounds already covering
; every other reuse in this file. PCT_STEP_LOAD is 16-bit (unlike the
; SAVE/VERIFY side's PCT_STEP) because one full chunk is 64 pages, not
; EPROM_PHYSICAL_BANKS*64 - see cartlab.asm's own PCT_STEP_LOAD comment
; for the same reasoning. ---
FILE_BUF = $2000
PCT_STEP_LOAD = 25600/64

feat_verify_eprom
        lda     #LR_MODE_VERIFY
        sta     lr_mode
        jmp     lr_start
feat_load_eprom
        lda     #LR_MODE_LOAD
        sta     lr_mode

lr_start
        lda     #$93
        jsr     $ffd2
        lda     lr_mode
        cmp     #LR_MODE_VERIFY
        bne     lr_start_load
        lda     #<lr_hdr_verify_msg
        ldy     #>lr_hdr_verify_msg
        jsr     print_str
        jmp     lr_read_dir_go
lr_start_load
        lda     #<lr_hdr_load_msg
        ldy     #>lr_hdr_load_msg
        jsr     print_str
lr_read_dir_go
        jsr     lr_read_dir
        lda     lr_count
        bne     lr_have_files
        lda     #<lr_none_txt
        ldy     #>lr_none_txt
        jsr     print_str
lr_none_wait
        jsr     $ffe4
        beq     lr_none_wait
        rts
lr_have_files
        lda     #$00
        sta     lr_cursor
        sta     lr_top

; --- lr_browse: redraws the current page (up to LR_ROWS entries,
; cursor row marked "> ") and waits for CRSR UP/DOWN, RETURN, DEL, or
; back-arrow. Same full-redraw-per-move tradeoff cartlab.asm's own
; lr_browse already makes. ---
lr_browse
        lda     #$93
        jsr     $ffd2
        lda     lr_mode
        cmp     #LR_MODE_VERIFY
        bne     lr_browse_hdr_load
        lda     #<lr_browse_hdr_verify_msg
        ldy     #>lr_browse_hdr_verify_msg
        jsr     print_str
        jmp     lr_browse_rows_init
lr_browse_hdr_load
        lda     #<lr_browse_hdr_load_msg
        ldy     #>lr_browse_hdr_load_msg
        jsr     print_str
lr_browse_rows_init
        lda     lr_top
        sta     hd_count        ; row-walk index - safe, see lr_read_
                                    ; dir's own comment on sharing this
        ldx     #$00
lr_browse_row
        cpx     #LR_ROWS
        beq     lr_browse_rows_done
        lda     hd_count
        cmp     lr_count
        bcs     lr_browse_rows_done
        pha
        lda     hd_count
        cmp     lr_cursor
        bne     lr_browse_no_mark
        lda     #$1e         ; green
        jsr     $ffd2
        lda     #$3e         ; '>'
        jsr     $ffd2
        lda     #$20
        jsr     $ffd2
        jmp     lr_browse_mark_done
lr_browse_no_mark
        lda     #$05         ; white
        jsr     $ffd2
        lda     #$20
        jsr     $ffd2
        lda     #$20
        jsr     $ffd2
lr_browse_mark_done
        pla
        jsr     lr_print_name
        lda     #$0d
        jsr     $ffd2
        inc     hd_count
        inx
        jmp     lr_browse_row
lr_browse_rows_done
        lda     #$05
        jsr     $ffd2
        lda     #<lr_browse_ctrl_msg
        ldy     #>lr_browse_ctrl_msg
        jsr     print_str
lr_browse_wait
        jsr     $ffe4
        beq     lr_browse_wait
        cmp     #$11         ; CRSR DOWN
        beq     lr_browse_down
        cmp     #$91         ; CRSR UP
        beq     lr_browse_up
        cmp     #$0d         ; RETURN
        beq     lr_browse_select
        cmp     #$14         ; DEL/INST - delete the highlighted entry
        beq     lr_browse_delete
        cmp     #$5f         ; back arrow
        beq     lr_browse_back
        jmp     lr_browse_wait
lr_browse_down
        lda     lr_cursor
        clc
        adc     #1
        cmp     lr_count
        bcs     lr_browse_wait
        sta     lr_cursor
        jsr     lr_scroll_fix
        jmp     lr_browse
lr_browse_up
        lda     lr_cursor
        beq     lr_browse_wait
        sec
        sbc     #1
        sta     lr_cursor
        jsr     lr_scroll_fix
        jmp     lr_browse
lr_browse_back
        rts
lr_browse_select
        lda     lr_cursor
        jsr     lr_copy_name_to_fn
        lda     lr_mode
        cmp     #LR_MODE_VERIFY
        bne     lr_do_load
        jsr     lr_verify_selected
        jmp     lr_browse
lr_do_load
        jsr     lr_load_selected
        jmp     lr_browse

; --- DEL/INST on the highlighted entry: confirms (Y/anything-else),
; then scratches it via the real CBM DOS "S:name" command channel
; sequence (same mechanism bank10_content.asm's own DELETE command and
; cartlab.asm's own lr_browse_delete both already use) - no read-back of
; channel 15's own error response afterward, same "fails silently for
; now" scope decision bank10_content.asm's DELETE already made. Jumps
; back into lr_read_dir_go to re-read the directory and redraw (or show
; "no files" if that was the last entry) - same routine lr_start's own
; first read already uses, so there's no separate "reset cursor/top"
; copy to keep in sync. ---
lr_browse_delete
        lda     lr_cursor
        jsr     lr_copy_name_to_fn ; filename_buf/lr_fn_len = entry to delete
        lda     #<lr_del_confirm_txt
        ldy     #>lr_del_confirm_txt
        jsr     print_str
        lda     #<filename_buf
        ldy     #>filename_buf
        jsr     print_str
        lda     #<lr_del_confirm_q_txt
        ldy     #>lr_del_confirm_q_txt
        jsr     print_str
lr_del_confirm_wait
        jsr     $ffe4
        beq     lr_del_confirm_wait
        cmp     #$59         ; 'Y'
        beq     lr_del_do
        jmp     lr_browse    ; anything else - cancel, just redraw
lr_del_do
        ldx     #$00
lr_del_build_loop
        lda     filename_buf,x
        sta     lr_del_cmd+2,x
        beq     lr_del_build_done
        inx
        jmp     lr_del_build_loop
lr_del_build_done
        lda     #$53         ; 'S'
        sta     lr_del_cmd
        lda     #$3a         ; ':'
        sta     lr_del_cmd+1
        txa                  ; X still holds fn_len's own value (the
        clc                    ; null's position, not counted) - same
        adc     #2             ; convention lr_copy_name_to_fn's own
                                  ; sty lr_fn_len relies on; +2 for "S:"
        ldx     #<lr_del_cmd
        ldy     #>lr_del_cmd
        jsr     KERNAL_SETNAM
        lda     #15
        ldx     disk_device
        ldy     #15
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        lda     #15
        jsr     KERNAL_CLOSE
        jmp     lr_read_dir_go

lr_del_confirm_txt
        !text   "DELETE "
        !byte   $00
lr_del_confirm_q_txt
        !text   "? (Y/N) "
        !byte   $00

; --- Keeps lr_cursor on screen after a CRSR move - see cartlab.asm's
; own lr_scroll_fix for the full reasoning, unchanged here. ---
lr_scroll_fix
        lda     lr_cursor
        cmp     lr_top
        bcs     lr_scroll_check_bottom
        dec     lr_top
        rts
lr_scroll_check_bottom
        lda     lr_top
        clc
        adc     #LR_ROWS
        cmp     lr_cursor
        bne     lr_scroll_done
        inc     lr_top
lr_scroll_done
        rts

; --- A = index into LR_NAME_TABLE -> prints that entry's name. ---
lr_print_name
        jsr     lr_table_addr
        ldy     #$00
lr_pn_loop
        lda     (dir_ptr),y
        beq     lr_pn_done
        jsr     $ffd2
        iny
        jmp     lr_pn_loop
lr_pn_done
        rts

; --- A = index into LR_NAME_TABLE -> copies that entry into
; filename_buf, null-terminated, with lr_fn_len set. ---
lr_copy_name_to_fn
        jsr     lr_table_addr
        ldy     #$00
lr_cn_loop
        lda     (dir_ptr),y
        sta     filename_buf,y
        beq     lr_cn_done
        iny
        jmp     lr_cn_loop
lr_cn_done
        sty     lr_fn_len
        rts

; --- A (0..LR_MAX_FILES-1) -> dir_ptr = &LR_NAME_TABLE[A*LR_NAME_LEN].
; Plain repeated addition, same reasoning cartlab.asm's own lr_table_
; addr/times10 already use for a small, one-off value. ---
lr_table_addr
        sta     hd_count         ; stash the index - safe, see
                                    ; lr_read_dir's own comment
        lda     #<LR_NAME_TABLE
        sta     dir_ptr
        lda     #>LR_NAME_TABLE
        sta     dir_ptr+1
        ldx     hd_count
        beq     lr_ta_done
lr_ta_loop
        clc
        lda     dir_ptr
        adc     #LR_NAME_LEN
        sta     dir_ptr
        lda     dir_ptr+1
        adc     #$00
        sta     dir_ptr+1
        dex
        bne     lr_ta_loop
lr_ta_done
        rts

; --- lr_count -> lr_dest_ptr = &LR_NAME_TABLE[lr_count*LR_NAME_LEN]. ---
lr_set_dest
        lda     #<LR_NAME_TABLE
        sta     lr_dest_ptr
        lda     #>LR_NAME_TABLE
        sta     lr_dest_ptr+1
        ldx     lr_count
        beq     lr_sd_done
lr_sd_loop
        clc
        lda     lr_dest_ptr
        adc     #LR_NAME_LEN
        sta     lr_dest_ptr
        lda     lr_dest_ptr+1
        adc     #$00
        sta     lr_dest_ptr+1
        dex
        bne     lr_sd_loop
lr_sd_done
        rts

; --- Reads the "$" directory from disk_device via OPEN/CHKIN/CHRIN
; into LR_RAW_BUF (slots.asm), then walks it with the same verified
; byte layout bank10_content.asm's DirCmd/cartlab.asm's own lr_read_dir
; both already document and rely on - see either of those for the full
; explanation. Storing each real file's name into LR_NAME_TABLE instead
; of printing it. The disk-name/ID header entry is always exactly the
; FIRST entry (guaranteed by the CBM DOS format itself), so that's how
; it gets skipped - NOT "size == 0" (a 0-block splat file would be
; indistinguishable from the header by that check alone - confirmed
; live in cartlab.asm's own identical routine before this exact fix).
; hd_count/bt_ref reused as scratch throughout - safe, this screen
; never runs alongside BANK SCANNER/EPROM DUMP/READ CHIP/BACKUP EPROM. ---
lr_read_dir
        lda     #$00
        sta     lr_count
        sta     lr_rd_seen_header
        lda     #1
        ldx     #<lr_dir_filename
        ldy     #>lr_dir_filename
        jsr     KERNAL_SETNAM
        lda     #2
        ldx     disk_device
        ldy     #0
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        bcc     lr_rd_open_ok
        rts
lr_rd_open_ok
        ldx     #2
        jsr     KERNAL_CHKIN
        bcc     lr_rd_chkin_ok
        lda     #2
        jsr     KERNAL_CLOSE
        rts
lr_rd_chkin_ok
        jsr     KERNAL_CHRIN     ; discard the pseudo-file's own 2-byte
        jsr     KERNAL_CHRIN     ; embedded load address
        lda     #<LR_RAW_BUF
        sta     dir_ptr
        lda     #>LR_RAW_BUF
        sta     dir_ptr+1
lr_rd_read_loop
        jsr     KERNAL_CHRIN
        ldy     #$00
        sta     (dir_ptr),y
        jsr     lr_rd_ptr_inc
        jsr     KERNAL_READST
        beq     lr_rd_read_loop
        jsr     KERNAL_CLRCHN
        lda     #2
        jsr     KERNAL_CLOSE

        lda     #<LR_RAW_BUF
        sta     dir_ptr
        lda     #>LR_RAW_BUF
        sta     dir_ptr+1
lr_rd_entry_loop
        ldy     #$00
        lda     (dir_ptr),y
        sta     bt_ref
        iny
        lda     (dir_ptr),y
        ora     bt_ref
        bne     lr_rd_have_link
        rts
lr_rd_have_link
        clc
        lda     dir_ptr
        adc     #4
        sta     dir_ptr
        bcc     +
        inc     dir_ptr+1
+
        lda     lr_rd_seen_header
        bne     lr_rd_find_quote
        lda     #$01
        sta     lr_rd_seen_header
        jmp     lr_rd_skip
lr_rd_find_quote
        ldy     #$00
        lda     (dir_ptr),y
        bne     +
        jmp     lr_rd_skip
+       cmp     #$22
        beq     lr_rd_quote_found
        jsr     lr_rd_ptr_inc
        jmp     lr_rd_find_quote
lr_rd_quote_found
        jsr     lr_rd_ptr_inc
        lda     lr_count
        cmp     #LR_MAX_FILES
        bcs     lr_rd_skip
        jsr     lr_set_dest
        ldx     #$00
lr_rd_name_loop
        ldy     #$00
        lda     (dir_ptr),y
        beq     lr_rd_skip
        cmp     #$22
        beq     lr_rd_name_closed
        cpx     #16
        beq     lr_rd_name_skip
        pha
        txa
        tay
        pla
        sta     (lr_dest_ptr),y
        inx
lr_rd_name_skip
        jsr     lr_rd_ptr_inc
        jmp     lr_rd_name_loop
lr_rd_name_closed
        jsr     lr_rd_ptr_inc
        txa
        tay
        lda     #$00
        sta     (lr_dest_ptr),y
        inc     lr_count
        jmp     lr_rd_skip
lr_rd_skip
        ldy     #$00
        lda     (dir_ptr),y
        beq     lr_rd_skip_done
        jsr     lr_rd_ptr_inc
        jmp     lr_rd_skip
lr_rd_skip_done
        jsr     lr_rd_ptr_inc
        jmp     lr_rd_entry_loop

lr_rd_ptr_inc
        inc     dir_ptr
        bne     lr_rd_ptr_inc_done
        inc     dir_ptr+1
lr_rd_ptr_inc_done
        rts

; --- VERIFY: streams filename_buf/lr_fn_len from disk_device and
; compares it byte-for-byte against a fresh live read (bank_call +
; resident_copy_page, same mechanism EPROM DUMP/BACKUP EPROM already
; use) - no percentage display here (unlike cartlab.asm's own be_
; verify) to keep this within Bank 15's tight remaining ROM budget;
; the header/footer messages are enough to show it's running and how
; it finished. ---
lr_verify_selected
        lda     #<lrv_hdr_txt
        ldy     #>lrv_hdr_txt
        jsr     print_str
lrv_open
        lda     lr_fn_len
        ldx     #<filename_buf
        ldy     #>filename_buf
        jsr     KERNAL_SETNAM
        lda     #4
        ldx     disk_device
        ldy     #0
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        bcc     lrv_open_ok
        jmp     lrv_fail
lrv_open_ok
        ldx     #4
        jsr     KERNAL_CHKIN
        bcc     lrv_chkin_ok
        lda     #4
        jsr     KERNAL_CLOSE
        jmp     lrv_fail
lrv_chkin_ok
        lda     #$00
        sta     pct_acc
        sta     pct_acc+1
        lda     #$00
        jsr     print_pct
        lda     #$29         ; ')'
        jsr     $ffd2
        lda     #$00
        sta     eprom_bank
lrv_bank_loop
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
lrv_page_loop
        lda     eprom_offset+1
        clc
        adc     #$80
        sta     hd_addr+1
        lda     eprom_offset
        sta     hd_addr
        lda     #<resident_copy_page
        sta     call_ptr
        lda     #>resident_copy_page
        sta     call_ptr+1
        lda     eprom_bank
        jsr     bank_call        ; fills eprom_page_buf
        ldy     #$00
lrv_byte_loop
        lda     eprom_page_buf,y
        sta     bt_ref
        jsr     KERNAL_CHRIN
        cmp     bt_ref
        bne     lrv_mismatch
        iny
        bpl     lrv_byte_loop
        lda     eprom_offset
        clc
        adc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #$00
        sta     eprom_offset+1
        jsr     lrv_update_pct
        lda     eprom_offset+1
        cmp     #>8192
        bcc     lrv_page_loop
        inc     eprom_bank
        lda     eprom_bank
        cmp     #EPROM_PHYSICAL_BANKS
        bcc     lrv_bank_loop
        jsr     KERNAL_CLRCHN
        lda     #4
        jsr     KERNAL_CLOSE
        lda     #<lrv_ok_txt
        ldy     #>lrv_ok_txt
        jsr     print_str
        jmp     lrv_wait
lrv_mismatch
        jsr     KERNAL_CLRCHN
        lda     #4
        jsr     KERNAL_CLOSE
lrv_fail
        lda     #<lrv_fail_txt
        ldy     #>lrv_fail_txt
        jsr     print_str
lrv_wait
        jsr     $ffe4
        beq     lrv_wait
        rts

; --- Bumps pct_acc by PCT_STEP and reprints it in place as "NNN%)" -
; the trailing ")" is part of the reprinted field, so 5 cursor-lefts
; (not 4) always lines back up to right before the percent digits
; start. Same shape/reasoning as cartlab.asm's own be_update_pct; the
; CLRCHN here is a harmless no-op (CHKIN only redirects CHRIN/input, so
; $ffd2 was never pointed anywhere but the screen to begin with). ---
lrv_update_pct
        clc
        lda     pct_acc
        adc     #PCT_STEP
        sta     pct_acc
        lda     pct_acc+1
        adc     #$00
        sta     pct_acc+1
        jsr     KERNAL_CLRCHN
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     pct_acc+1
        jsr     print_pct
        lda     #$29         ; ')'
        jmp     $ffd2

lr_hdr_verify_msg
        !text   "VERIFY EPROM"
        !byte   $0d,$0d,$00
lr_hdr_load_msg
        !text   "LOAD EPROM TO RAM"
        !byte   $0d,$0d,$00
lr_none_txt
        !text   "NO FILES FOUND - PRESS ANY KEY"
        !byte   $0d,$00
lr_browse_hdr_verify_msg
        !text   "VERIFY EPROM - SELECT A FILE"
        !byte   $0d
        !text   "===================================="
        !byte   $0d,$00
lr_browse_hdr_load_msg
        !text   "LOAD EPROM TO RAM - SELECT A FILE"
        !byte   $0d
        !text   "===================================="
        !byte   $0d,$00
lr_browse_ctrl_msg
        !byte   $0d
        !text   "CRSR=MOVE RETURN=SELECT DEL=DELETE <-=BACK"
        !byte   $0d,$00
lrv_hdr_txt
        !text   "VERIFYING ("
        !byte   $00
lrv_ok_txt
        !text   "VERIFY OK - FILE MATCHES CARTRIDGE"
        !byte   $0d
        !text   "PRESS ANY KEY"
        !byte   $0d,$00
lrv_fail_txt
        !text   "?VERIFY FAILED - PRESS ANY KEY"
        !byte   $0d,$00

; --- LOAD: full multi-chunk hex+ASCII browser over filename_buf/lr_fn_
; len, real parity with cartlab.asm's own do_read_eprom/FILE VIEW mode -
; matches BACKUP EPROM's own output, which can span up to EPROM_
; PHYSICAL_BANKS*8192 bytes (the whole chip, not just one bank). Only
; one 8KB chunk (FILE_BUF) is ever held in RAM at once; paging past a
; chunk's own last page transparently re-opens the file and reads
; forward to the next chunk (lrl_load_chunk) - exactly cartlab.asm's
; own fl_seek_chunk technique, chosen there (and kept here) because a
; sequential CBM DOS file has no real random-access seek. CRSR UP/DOWN
; page (wrapping across all EPROM_PHYSICAL_BANKS chunks, same
; unconditional wrap cartlab.asm's own rp_next_bank/rp_prev_bank use -
; a chunk past the real end of a short file just keeps showing
; whatever FILE_BUF last held there, same as the standalone). ---
lr_load_selected
        lda     #$00
        sta     eprom_bank
        jsr     lrl_load_chunk
        bcc     lrl_ls_ok
        jmp     lrl_fail
lrl_ls_ok
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
        jmp     lrl_show

; --- A/carry-clean entry: opens filename_buf/lr_fn_len fresh, skips
; eprom_bank whole 8192-byte chunks (reading and discarding, same
; "no real seek" reasoning above), then reads the next chunk into
; FILE_BUF, showing "(nnn%)" progress as it goes. hd_addr/hd_count
; reused as the read pointer/skip-counter - safe, this always finishes
; before lrl_show's own unrelated use of them starts. Carry set on
; open/CHKIN failure only; a short file (EOF mid-read) is not a
; failure - same "just show what's there" reasoning as cartlab.asm's
; own fl_seek_chunk. ---
lrl_load_chunk
        lda     #$93
        jsr     $ffd2
        lda     #<lrl_hdr_txt
        ldy     #>lrl_hdr_txt
        jsr     print_str
        lda     #$00
        sta     pct_acc
        sta     pct_acc+1
        lda     #$00
        jsr     print_pct
        lda     #$29         ; ')'
        jsr     $ffd2
        lda     lr_fn_len
        ldx     #<filename_buf
        ldy     #>filename_buf
        jsr     KERNAL_SETNAM
        lda     #4
        ldx     disk_device
        ldy     #0
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        bcc     lrlc_open_ok
        sec
        rts
lrlc_open_ok
        ldx     #4
        jsr     KERNAL_CHKIN
        bcc     lrlc_chkin_ok
        lda     #4
        jsr     KERNAL_CLOSE
        sec
        rts
lrlc_chkin_ok
        lda     eprom_bank
        sta     hd_count        ; chunks left to skip
        beq     lrlc_read
lrlc_skip_loop
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
lrlc_skip_page
        ldy     #$00
lrlc_skip_byte
        jsr     KERNAL_CHRIN
        jsr     KERNAL_READST
        bne     lrlc_done       ; EOF mid-skip - nothing further to load
        iny
        bpl     lrlc_skip_byte
        lda     eprom_offset
        clc
        adc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #$00
        sta     eprom_offset+1
        cmp     #>8192
        bcc     lrlc_skip_page
        dec     hd_count
        bne     lrlc_skip_loop
lrlc_read
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
lrlc_read_page
        lda     eprom_offset+1
        clc
        adc     #>FILE_BUF
        sta     hd_addr+1
        lda     eprom_offset
        sta     hd_addr
        ldy     #$00
lrlc_read_byte
        jsr     KERNAL_CHRIN
        sta     (hd_addr),y
        jsr     KERNAL_READST
        bne     lrlc_done
        iny
        bpl     lrlc_read_byte
        jsr     lrl_update_pct
        lda     eprom_offset
        clc
        adc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #$00
        sta     eprom_offset+1
        cmp     #>8192
        bcc     lrlc_read_page
lrlc_done
        jsr     KERNAL_CLRCHN
        lda     #4
        jsr     KERNAL_CLOSE
        clc
        rts

; --- Bumps pct_acc by PCT_STEP_LOAD (16-bit - one chunk is 64 pages,
; not EPROM_PHYSICAL_BANKS*64, so the per-bank PCT_STEP above would
; finish nowhere near 100% here) and reprints "(nnn%)" in place with 5
; cursor-lefts, same technique as lrv_update_pct. ---
lrl_update_pct
        clc
        lda     pct_acc
        adc     #<PCT_STEP_LOAD
        sta     pct_acc
        lda     pct_acc+1
        adc     #>PCT_STEP_LOAD
        sta     pct_acc+1
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     #$9d
        jsr     $ffd2
        lda     pct_acc+1
        jsr     print_pct
        lda     #$29         ; ')'
        jmp     $ffd2

; --- Redraws the current 128-byte page (16 rows of 8 bytes) starting
; at FILE_BUF+eprom_offset, then waits for CRSR UP/DOWN or back-arrow.
; hd_addr doubles as both the "$xxxx:" address shown per row and the
; indirect read pointer - same dual use cartlab.asm's own rp_row makes
; of rd_addr - incremented by 8 once per row rather than recomputed
; from eprom_offset+hd_count each time. ---
lrl_show
        lda     #$93
        jsr     $ffd2
        lda     #<lrl_page_hdr_msg
        ldy     #>lrl_page_hdr_msg
        jsr     print_str
        lda     eprom_bank
        jsr     print_hex
        lda     #$0d
        jsr     $ffd2
        lda     #$0d
        jsr     $ffd2
        lda     eprom_offset+1
        clc
        adc     #>FILE_BUF
        sta     hd_addr+1
        lda     eprom_offset
        sta     hd_addr
        lda     #$00
        sta     hd_count        ; row counter, 0-15
lrl_row
        lda     #$24         ; '$'
        jsr     $ffd2
        lda     hd_addr+1
        jsr     print_hex
        lda     hd_addr
        jsr     print_hex
        lda     #$3a         ; ':'
        jsr     $ffd2
        lda     #$20
        jsr     $ffd2
        ldy     #$00
lrl_col
        lda     (hd_addr),y
        jsr     print_hex
        lda     #$20
        jsr     $ffd2
        iny
        cpy     #$08
        bne     lrl_col
        ldy     #$00
lrl_ascii
        lda     (hd_addr),y
        cmp     #$20
        bcc     lrl_ascii_dot
        cmp     #$7f
        bcs     lrl_ascii_dot
        jsr     $ffd2
        jmp     lrl_ascii_next
lrl_ascii_dot
        lda     #$2e         ; '.'
        jsr     $ffd2
lrl_ascii_next
        iny
        cpy     #$08
        bne     lrl_ascii
        lda     #$0d
        jsr     $ffd2
        lda     hd_addr
        clc
        adc     #$08
        sta     hd_addr
        bcc     +
        inc     hd_addr+1
+       inc     hd_count
        lda     hd_count
        cmp     #$10
        bne     lrl_row
        lda     #<lrl_ctrl_msg
        ldy     #>lrl_ctrl_msg
        jsr     print_str
lrl_wait
        jsr     $ffe4
        beq     lrl_wait
        cmp     #$11         ; CRSR DOWN - next page
        beq     lrl_next_page
        cmp     #$91         ; CRSR UP - previous page
        beq     lrl_prev_page
        cmp     #$5f         ; back arrow - return to the file list
        beq     lrl_back
        jmp     lrl_wait
lrl_back
        rts

lrl_next_page
        lda     eprom_offset
        clc
        adc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #$00
        sta     eprom_offset+1
        cmp     #>8192
        bcs     lrl_np_wrap     ; BCC can't reach lrl_show directly - see
        jmp     lrl_show        ; the extra hop below (same distance
                                    ; issue cartlab.asm's own rp_next_page
                                    ; hits, same fix)
lrl_np_wrap
        inc     eprom_bank
        lda     eprom_bank
        cmp     #EPROM_PHYSICAL_BANKS
        bcc     +
        lda     #$00
        sta     eprom_bank
+       jsr     lrl_load_chunk
        bcc     lrl_np_ok
        jmp     lrl_fail
lrl_np_ok
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
        jmp     lrl_show

lrl_prev_page
        lda     eprom_offset
        ora     eprom_offset+1
        bne     lrl_pp_sub
        lda     eprom_bank
        bne     lrl_pp_bank_ok
        lda     #EPROM_PHYSICAL_BANKS
lrl_pp_bank_ok
        sec
        sbc     #1
        sta     eprom_bank
        jsr     lrl_load_chunk
        bcc     lrl_pp_ok
        jmp     lrl_fail
lrl_pp_ok
        lda     #<(8192-128)
        sta     eprom_offset
        lda     #>(8192-128)
        sta     eprom_offset+1
        jmp     lrl_show
lrl_pp_sub
        lda     eprom_offset
        sec
        sbc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        sbc     #$00
        sta     eprom_offset+1
        jmp     lrl_show

lrl_fail
        lda     #<lrl_fail_txt
        ldy     #>lrl_fail_txt
        jsr     print_str
lrl_fail_wait
        jsr     $ffe4
        beq     lrl_fail_wait
        rts

lrl_hdr_txt
        !text   "LOADING ("
        !byte   $00
lrl_page_hdr_msg
        !text   "LOAD EPROM TO RAM  CHUNK $"
        !byte   $00
lrl_ctrl_msg
        !byte   $0d
        !text   "CRSR=PAGE <-=BACK"
        !byte   $0d,$00
lrl_fail_txt
        !text   "?LOAD ERROR - PRESS ANY KEY"
        !byte   $0d,$00

; ============================================================
; SEARCH ROM (CARTRIDGE LAB item 8) - prompts for a hex byte pattern,
; then scans every physical EPROM bank via bank_call+resident_copy_page
; (same mechanism BANK SCANNER/VERIFY EPROM already use) reporting each
; bank/offset where it's found. A pattern is never checked against a
; run of bytes that would cross a 128-byte page boundary - accepted
; scope cut, same "keep it within Bank 15's ROM budget" tradeoff already
; behind VERIFY/LOAD's own cuts (no percentage display, single-page
; viewer) elsewhere in this file. A pattern that happens to start in the
; last few bytes of a chip's internal page boundary would be missed;
; genuinely random-looking pattern bytes make this an unlikely miss in
; practice, and it's far cheaper than mirroring a whole 8K bank into RAM
; to search across the seam. ---
feat_search_rom
        lda     #$93
        jsr     $ffd2
        lda     #<sr_hdr_msg
        ldy     #>sr_hdr_msg
        jsr     print_str
        jsr     sr_read_pattern
        lda     sr_pat_len
        bne     sr_have_pattern
        rts                      ; nothing typed - cancel, same "RETURN
                                    ; alone = back out" convention lr_
                                    ; browse_back's own rts already uses
sr_have_pattern
        lda     #$0d
        jsr     $ffd2
        lda     #<sr_scanning_msg
        ldy     #>sr_scanning_msg
        jsr     print_str
        lda     #$00
        sta     eprom_bank
        sta     sr_found
sr_bank_loop
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
sr_page_loop
        lda     eprom_offset+1
        clc
        adc     #$80
        sta     hd_addr+1
        lda     eprom_offset
        sta     hd_addr
        lda     #<resident_copy_page
        sta     call_ptr
        lda     #>resident_copy_page
        sta     call_ptr+1
        lda     eprom_bank
        jsr     bank_call        ; fills eprom_page_buf
        ldy     #$00
sr_byte_loop
        tya
        clc
        adc     sr_pat_len
        cmp     #129
        bcs     sr_byte_next     ; pattern would run past this page's
                                    ; end - skip (see this feature's own
                                    ; header comment)
        sty     sr_y_save
        jsr     sr_try_match
        bcc     sr_no_match
        ldy     sr_y_save
        jsr     sr_report_match
sr_no_match
        ldy     sr_y_save
sr_byte_next
        iny
        bne     sr_byte_loop
        lda     eprom_offset
        clc
        adc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #$00
        sta     eprom_offset+1
        lda     eprom_offset+1
        cmp     #>8192
        bcc     sr_page_loop
        inc     eprom_bank
        lda     eprom_bank
        cmp     #EPROM_PHYSICAL_BANKS
        bcc     sr_bank_loop
        lda     sr_found
        bne     sr_done_found
        lda     #<sr_none_txt
        ldy     #>sr_none_txt
        jsr     print_str
        jmp     feat_wait_return
sr_done_found
        lda     #<sr_done_txt
        ldy     #>sr_done_txt
        jsr     print_str
        jmp     feat_wait_return

; --- Y = candidate start index (0-127) into eprom_page_buf -> carry set
; if sr_pat_len bytes starting there match sr_pattern. Clobbers Y/X. ---
sr_try_match
        ldx     #$00
sr_tm_loop
        cpx     sr_pat_len
        beq     sr_tm_match
        lda     eprom_page_buf,y
        cmp     sr_pattern,x
        bne     sr_tm_fail
        iny
        inx
        jmp     sr_tm_loop
sr_tm_match
        sec
        rts
sr_tm_fail
        clc
        rts

; --- Y = matching start index (0-127) into the current page -> prints
; "BANK $xx OFFSET $xxxx" and sets sr_found. hd_addr reused as scratch
; for the 16-bit offset - safe, this page's own bank_call already
; finished before this ever runs. ---
sr_report_match
        tya
        clc
        adc     eprom_offset
        sta     hd_addr
        lda     eprom_offset+1
        adc     #$00
        sta     hd_addr+1
        lda     #<sr_found_msg
        ldy     #>sr_found_msg
        jsr     print_str
        lda     eprom_bank
        jsr     print_hex
        lda     #<sr_offset_msg
        ldy     #>sr_offset_msg
        jsr     print_str
        lda     hd_addr+1
        jsr     print_hex
        lda     hd_addr
        jsr     print_hex
        lda     #$0d
        jsr     $ffd2
        lda     #$01
        sta     sr_found
        rts

; --- Reads up to 16 hex-digit chars (0-9/A-F only) from the keyboard
; into filename_buf (reused - safe, same "F1 menu open" reasoning
; filename_buf's other reuses elsewhere in this file already rely on),
; using lr_fn_len as the running index rather than X - GETIN doesn't
; guarantee X survives across repeated calls, same gotcha cartlab.asm's
; own read_filename already documents. RETURN with nothing typed leaves
; sr_pat_len at 0 (feat_search_rom's own cancel path). An odd number of
; typed digits silently drops the trailing one so the digit count is
; always a whole number of bytes. Converts the typed digit pairs into
; sr_pattern/sr_pat_len (up to 8 bytes) before returning. ---
sr_read_pattern
        lda     #<sr_prompt_msg
        ldy     #>sr_prompt_msg
        jsr     print_str
        lda     #$00
        sta     lr_fn_len
srp_loop
        jsr     $ffe4
        beq     srp_loop
        cmp     #$0d
        beq     srp_done
        cmp     #$14         ; DEL/INST
        beq     srp_del
        cmp     #$30         ; '0'
        bcc     srp_loop
        cmp     #$3a         ; '9'+1
        bcc     srp_accept
        cmp     #$41         ; 'A'
        bcc     srp_loop
        cmp     #$47         ; 'F'+1
        bcs     srp_loop
srp_accept
        ldx     lr_fn_len
        cpx     #16
        bcs     srp_loop
        sta     filename_buf,x
        inx
        stx     lr_fn_len
        jsr     $ffd2
        jmp     srp_loop
srp_del
        lda     lr_fn_len
        beq     srp_loop
        dec     lr_fn_len
        lda     #$14
        jsr     $ffd2
        jmp     srp_loop
srp_done
        lda     lr_fn_len
        and     #$01
        beq     srp_even
        dec     lr_fn_len    ; odd count - drop the trailing nibble
srp_even
        lda     #$00
        sta     sr_pat_len
        lda     lr_fn_len
        beq     srp_conv_done  ; nothing typed
        lsr
        sta     sr_pat_len     ; byte count = digit count / 2
        ldx     #$00           ; filename_buf read index
        ldy     #$00           ; sr_pattern write index
srp_conv_loop
        cpy     sr_pat_len
        beq     srp_conv_done
        lda     filename_buf,x
        jsr     sr_hex_nibble
        asl
        asl
        asl
        asl
        sta     bt_ref         ; high nibble, shifted into place - bt_
                                  ; ref reused, safe: SEARCH ROM never
                                  ; runs concurrently with BANK SCANNER/
                                  ; EPROM DUMP/READ CHIP/BACKUP EPROM,
                                  ; same sharing rule those already use
        inx
        lda     filename_buf,x
        jsr     sr_hex_nibble
        ora     bt_ref
        sta     sr_pattern,y
        inx
        iny
        jmp     srp_conv_loop
srp_conv_done
        rts

; --- A = ASCII hex digit ('0'-'9'/'A'-'F', already validated by sr_
; read_pattern's own charset restriction) -> A = nibble value 0-15. ---
sr_hex_nibble
        cmp     #$3a
        bcc     +
        sec
        sbc     #7
+       and     #$0f
        rts

sr_hdr_msg
        !text   "SEARCH ROM"
        !byte   $0d,$0d,$00
sr_prompt_msg
        !text   "ENTER HEX BYTES (E.G. A9008D):"
        !byte   $0d
        !byte   $00
sr_scanning_msg
        !text   "SCANNING..."
        !byte   $0d,$0d,$00
sr_found_msg
        !text   "BANK $"
        !byte   $00
sr_offset_msg
        !text   " OFFSET $"
        !byte   $00
sr_none_txt
        !text   "PATTERN NOT FOUND - PRESS ANY KEY"
        !byte   $0d,$00
sr_done_txt
        !text   "SEARCH COMPLETE - PRESS ANY KEY"
        !byte   $0d,$00
