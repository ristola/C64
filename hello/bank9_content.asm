; Bank 9 content: CARTRIDGE-flash category (FLASHERASE/FLASHLOAD/
; FLASHVERIFY). Stubs only - these would write to the actual EasyFlash
; chip (not just RAM or a bank-select register like BANK does), so a
; wrong command sequence risks corrupting the cartridge itself,
; including the resident kernel every bank depends on. Real logic
; needs a separately-verified EAPI erase/program command sequence
; before being wired up for real - not guessed at alongside everything
; else. Each stub prints its own name via a small inline loop (see
; resident.asm's print_stub_suffix comment for why), then the shared
; print_stub_suffix tail.

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_FLASHERASE-*, $ff
        jmp     FlashEraseCmd
!fill SLOT_FLASHLOAD-*, $ff
        jmp     FlashLoadCmd
!fill SLOT_FLASHVERIFY-*, $ff
        jmp     FlashVerifyCmd

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill $8100-*, $ff

*=$8100

FlashEraseCmd
        ldx     #0
flasherase_print_loop
        lda     flasherase_name,x
        beq     flasherase_print_done
        jsr     $ffd2
        inx
        bne     flasherase_print_loop
flasherase_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
FlashLoadCmd
        ldx     #0
flashload_print_loop
        lda     flashload_name,x
        beq     flashload_print_done
        jsr     $ffd2
        inx
        bne     flashload_print_loop
flashload_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
FlashVerifyCmd
        ldx     #0
flashverify_print_loop
        lda     flashverify_name,x
        beq     flashverify_print_done
        jsr     $ffd2
        inx
        bne     flashverify_print_loop
flashverify_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic

flasherase_name
        !text   "FLASHERASE"
        !byte   0
flashload_name
        !text   "FLASHLOAD"
        !byte   0
flashverify_name
        !text   "FLASHVERIFY"
        !byte   0
