; Bank 8 content: SOUND category (SOUND/VOLUME/WAVE/ADSR/FILTER). All
; stubs for now - each prints its own name via a small inline loop (see
; resident.asm's print_stub_suffix comment for why), then the shared
; print_stub_suffix tail. Real logic (direct SID register writes,
; $D400-$D418) comes later.

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_SOUND-*, $ff
        jmp     SoundCmd
!fill SLOT_VOLUME-*, $ff
        jmp     VolumeCmd
!fill SLOT_WAVE-*, $ff
        jmp     WaveCmd
!fill SLOT_ADSR-*, $ff
        jmp     AdsrCmd
!fill SLOT_FILTER-*, $ff
        jmp     FilterCmd

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill $8100-*, $ff

*=$8100

SoundCmd
        ldx     #0
sound_print_loop
        lda     sound_name,x
        beq     sound_print_done
        jsr     $ffd2
        inx
        bne     sound_print_loop
sound_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
VolumeCmd
        ldx     #0
volume_print_loop
        lda     volume_name,x
        beq     volume_print_done
        jsr     $ffd2
        inx
        bne     volume_print_loop
volume_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
WaveCmd
        ldx     #0
wave_print_loop
        lda     wave_name,x
        beq     wave_print_done
        jsr     $ffd2
        inx
        bne     wave_print_loop
wave_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
AdsrCmd
        ldx     #0
adsr_print_loop
        lda     adsr_name,x
        beq     adsr_print_done
        jsr     $ffd2
        inx
        bne     adsr_print_loop
adsr_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
FilterCmd
        ldx     #0
filter_print_loop
        lda     filter_name,x
        beq     filter_print_done
        jsr     $ffd2
        inx
        bne     filter_print_loop
filter_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic

sound_name
        !text   "SOUND"
        !byte   0
volume_name
        !text   "VOLUME"
        !byte   0
wave_name
        !text   "WAVE"
        !byte   0
adsr_name
        !text   "ADSR"
        !byte   0
filter_name
        !text   "FILTER"
        !byte   0
