; Hello World for Commodore 64
; Assembler: ACME
; Debug: F5 (assembles, launches VICE, starts debugging)

*=$0801             ; BASIC start address

; --- Tiny BASIC stub: 10 SYS 2064 ---
!byte $0b, $08       ; pointer to next BASIC line
!byte $0a, $00       ; line number 10
!byte $9e            ; SYS token
!text "2064"
!byte $00, $00, $00  ; end of BASIC program

*=$0810              ; 2064 decimal = $0810

!source "common.asm"
