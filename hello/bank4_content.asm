; Bank 4 content: INPUT category (JOY/JOYUP/JOYDOWN/JOYLEFT/JOYRIGHT/
; JOYFIRE) - all functions, dispatched via resident.asm's
; EvaluateFunction (IEVAL), not statements. Stubs return a placeholder
; 0 via the already-verified numeric-result path (func_result_hi/lo +
; bank_return, resident.asm's $B391 FAC1 construction) - real logic
; (reading CIA port $DC00/$DC01) comes later.

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_JOY-*, $ff
        jmp     JoyFunc
!fill SLOT_JOYUP-*, $ff
        jmp     JoyUpFunc
!fill SLOT_JOYDOWN-*, $ff
        jmp     JoyDownFunc
!fill SLOT_JOYLEFT-*, $ff
        jmp     JoyLeftFunc
!fill SLOT_JOYRIGHT-*, $ff
        jmp     JoyRightFunc
!fill SLOT_JOYFIRE-*, $ff
        jmp     JoyFireFunc

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill BANK_CONTENT_START-*, $ff

*=BANK_CONTENT_START

JoyFunc
        lda     #$00
        sta     func_result_hi
        sta     func_result_lo
        jmp     bank_return
JoyUpFunc
        lda     #$00
        sta     func_result_hi
        sta     func_result_lo
        jmp     bank_return
JoyDownFunc
        lda     #$00
        sta     func_result_hi
        sta     func_result_lo
        jmp     bank_return
JoyLeftFunc
        lda     #$00
        sta     func_result_hi
        sta     func_result_lo
        jmp     bank_return
JoyRightFunc
        lda     #$00
        sta     func_result_hi
        sta     func_result_lo
        jmp     bank_return
JoyFireFunc
        lda     #$00
        sta     func_result_hi
        sta     func_result_lo
        jmp     bank_return
