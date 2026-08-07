; Bank 6 content: CARTRIDGE non-flash category (CARTINFO/BANK/BANKS).
; Real logic - exposes cur_bank/$DE00, the same mechanism bank_call
; already uses safely. BANK n changes which bank BASIC "rests" on
; between commands (as opposed to bank_call's own transient visits);
; this is safe because bank_call/bank_return already treat cur_bank as
; the dynamic source of truth for "which bank to restore afterward" -
; nothing hardcodes bank 0 except irq_hook's F1 path (which explicitly
; targets bank 0 for menu_open and correctly restores whatever cur_bank
; was before, via the same mechanism), so F1/menu keeps working no
; matter which bank is currently resting. Every bank 0-12 has the full
; resident kernel baked in regardless of real content (bank_driver.asm
; sources resident.asm unconditionally) - the ONLY genuinely unsafe
; case is a bank number that was never built at all (>= TOTAL_BANKS,
; slots.asm), which could read unprogrammed/erased flash where the
; resident kernel is supposed to be, crashing the very next jiffy IRQ -
; hence the range check below rather than trusting any argument blindly.

BAS_FRMNUM = $ad8a       ; evaluate + require a numeric expression
BAS_GETADR = $b7f7       ; convert FAC1 to a 16-bit int in $14/$15

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_CARTINFO-*, $ff
        jmp     CartInfoCmd
!fill SLOT_BANK-*, $ff
        jmp     BankCmd
!fill SLOT_BANKS-*, $ff
        jmp     BanksCmd

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill BANK_CONTENT_START-*, $ff

*=BANK_CONTENT_START

; --- CARTINFO: name, current resting bank, total banks built. ---
CartInfoCmd
        ldx     #0
cartinfo_print_loop
        lda     cartinfo_name,x
        beq     cartinfo_print_done
        jsr     $ffd2
        inx
        bne     cartinfo_print_loop
cartinfo_print_done
        ldx     #0
cartinfo_cb_loop
        lda     cartinfo_cb_msg,x
        beq     cartinfo_cb_done
        jsr     $ffd2
        inx
        bne     cartinfo_cb_loop
cartinfo_cb_done
        lda     resting_bank
        ldx     #0
        jsr     print_decimal_word
        lda     #13
        jsr     $ffd2
        ldx     #0
cartinfo_tb_loop
        lda     cartinfo_tb_msg,x
        beq     cartinfo_tb_done
        jsr     $ffd2
        inx
        bne     cartinfo_tb_loop
cartinfo_tb_done
        lda     #TOTAL_BANKS
        ldx     #0
        jsr     print_decimal_word
        lda     #13
        jsr     $ffd2
        jmp     bank_return_basic

cartinfo_name
        !text   "SHACKMATE CARTRIDGE"
        !byte   13,0
cartinfo_cb_msg
        !text   "CURRENT BANK: "
        !byte   0
cartinfo_tb_msg
        !text   "TOTAL BANKS: "
        !byte   0

; --- BANK <n>: switch which bank BASIC rests on. Rejects anything
; outside 0-(TOTAL_BANKS-1) rather than trusting the argument, since an
; out-of-range value could select unprogrammed flash where the
; resident kernel (irq_hook etc.) is supposed to be, crashing on the
; very next jiffy IRQ. The actual switch happens via resident.asm's
; bank_commit, not here - see that routine's comment for why doing it
; directly from bank-specific code corrupts the very next instruction
; fetch (confirmed live: an earlier version of this command that did
; its own "sta cur_bank / jsr ram_bank_switch" produced a "?SYNTAX
; ERROR" that traced back to executing garbage from whatever bank had
; just become active instead of this command's own next instruction). ---
BankCmd
        lda     #$00
        sta     $0d          ; BAS_VALTYP - real BASIC interpreter
                               ; state, used as a literal (not the
                               ; resident.asm forward reference) so
                               ; ACME can size this zero-page access
        jsr     BAS_FRMNUM
        jsr     BAS_GETADR    ; $14/$15 = 16-bit value, low/high
        lda     $15
        bne     bank_range_error   ; high byte set - definitely >255
        lda     $14
        cmp     #TOTAL_BANKS
        bcs     bank_range_error
        jmp     bank_commit    ; tail-jump into resident code BEFORE any
                                 ; switch happens - see bank_commit's own
                                 ; comment
bank_range_error
        ldx     #0
bank_err_loop
        lda     bank_err_msg,x
        beq     bank_err_done
        jsr     $ffd2
        inx
        bne     bank_err_loop
bank_err_done
        jmp     bank_return_basic

bank_err_msg
        !text   "?BANK OUT OF RANGE (0-12)"
        !byte   13,0

; --- BANKS: what each bank is (or will be), plus which one is
; currently resting. ---
BanksCmd
        ldx     #0
banks_print_loop
        lda     banks_map,x
        beq     banks_print_done
        jsr     $ffd2
        inx
        bne     banks_print_loop
banks_print_done
        ldx     #0
banks_cur_loop
        lda     banks_cur_msg,x
        beq     banks_cur_done
        jsr     $ffd2
        inx
        bne     banks_cur_loop
banks_cur_done
        lda     resting_bank
        ldx     #0
        jsr     print_decimal_word
        lda     #13
        jsr     $ffd2
        jmp     bank_return_basic

banks_map
        !text   " 0 BOOT/MENU"
        !byte   13
        !text   " 1 BASIC+ CORE/SCREEN"
        !byte   13
        !text   " 2 GRAPHICS"
        !byte   13
        !text   " 3 SPRITES"
        !byte   13
        !text   " 4 INPUT"
        !byte   13
        !text   " 5 MEMORY"
        !byte   13
        !text   " 6 CARTRIDGE"
        !byte   13
        !text   " 7 INLINE-ASM"
        !byte   13
        !text   " 8 SOUND"
        !byte   13
        !text   " 9 CARTRIDGE-FLASH"
        !byte   13
        !text   " 10 DISK"
        !byte   13
        !text   " 11-12 RESERVED"
        !byte   13,0
banks_cur_msg
        !text   "CURRENT: "
        !byte   0
