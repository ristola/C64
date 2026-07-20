; Hello World for Commodore 64
; Assemble: Cmd+Shift+B   (Assemble only)
; Run:      Cmd+Shift+P > Tasks: Run Task > Assemble & Run in VICE

        .cpu    "6502"

        * = $0801           ; BASIC start address

; --- Tiny BASIC stub: 10 SYS 2064 ---
        .byte   $0b, $08    ; pointer to next BASIC line
        .byte   $0a, $00    ; line number 10
        .byte   $9e         ; SYS token
        .text   "2064"
        .byte   $00, $00, $00  ; end of BASIC program

        * = $0810           ; 2064 decimal = $0810

start
        lda     #$93        ; clear screen (CHR$147)
        jsr     $ffd2

        ldx     #$00
loop
        lda     msg,x
        beq     done
        jsr     $ffd2
        inx
        bne     loop
done
        rts

msg
        .text   "HELLO, WORLD!"
        .byte   $0d, $00
