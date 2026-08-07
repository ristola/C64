; Bank 13 content: FastLoader. FastDload replaces DloadCmd's own
; previous KERNAL_LOAD call with the same raw OPEN/CHKIN/CHRIN
; technique DirCmd (bank10_content.asm) already proved out for "$"
; listings - skips KERNAL_LOAD's own internal overhead (message-
; printing checks, its own more general-purpose read loop) on every
; single byte transferred. Real gain is modest, not a classic turbo-
; loader: both the old KERNAL_LOAD path and this one still ride the
; same stock, bit-banged IEC serial bus KERNAL routines underneath -
; a genuine multi-x speedup needs custom drive-side code, deliberately
; out of scope here. This bank is part of the protected "system" range
; - see slots.asm's FIRST_USER_BANK comment for the wider policy.
;
; Called via bank_call from DloadCmd (bank 10), not a BASIC keyword of
; its own - filename_buf/disk_namelen must already be set (DloadCmd's
; own parse_filename_opt call does this before the bank_call), and X/Y
; = destination address, matching KERNAL_LOAD's own calling convention
; so DloadCmd's existing "ldx $2b / ldy $2c" (TXTTAB) needed no change.
; Reports success/failure via fastload_error (slots.asm) rather than
; the carry flag, since bank_return's own PLA/STA sequence
; (resident.asm) doesn't guarantee carry survives back to the caller -
; already holds interrupts disabled the whole way (inherited from
; OkExt's own SEI, still in effect for this whole bank_call round trip
; - no extra SEI/CLI needed here).

KERNAL_SETNAM = $ffbd
KERNAL_SETLFS = $ffba
KERNAL_OPEN   = $ffc0
KERNAL_CLOSE  = $ffc3
KERNAL_CHKIN  = $ffc6
KERNAL_CHRIN  = $ffcf
KERNAL_CLRCHN = $ffcc

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_FASTDLOAD-*, $ff
        jmp     FastDload

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill BANK_CONTENT_START-*, $ff

*=BANK_CONTENT_START

; X/Y = destination address (TXTTAB, passed through bank_call
; untouched - it doesn't reference X/Y at all).
FastDload
        stx     $14             ; own copy of the destination pointer -
        sty     $15             ; TXTTAB itself must stay untouched
        lda     disk_namelen
        ldx     #<filename_buf
        ldy     #>filename_buf
        jsr     KERNAL_SETNAM
        lda     #1              ; logical file number
        ldx     disk_device
        ldy     #0              ; SA=0 - no LOAD-style embedded-vs-
        jsr     KERNAL_SETLFS    ; supplied-address distinction here,
                                   ; same as DirCmd's own "$" open
        jsr     KERNAL_OPEN
        bcc     +
        lda     #1
        sta     fastload_error
        jmp     bank_return
+       ldx     #1
        jsr     KERNAL_CHKIN
        bcc     +
        jsr     KERNAL_CLRCHN
        lda     #1
        jsr     KERNAL_CLOSE
        lda     #2
        sta     fastload_error
        jmp     bank_return
+       jsr     KERNAL_CHRIN    ; discard the file's own embedded load
        jsr     KERNAL_CHRIN    ; address (2 bytes) - real KERNAL_LOAD
                                   ; always consumes this itself; a raw
                                   ; CHRIN loop needs the same explicit
                                   ; skip DirCmd's own "$" read already
                                   ; does, or the destination starts 2
                                   ; bytes short
fastload_read_loop
        jsr     KERNAL_CHRIN
        ldy     #0
        sta     ($14),y
        jsr     fastload_ptr_inc
        lda     $90             ; STATUS - nonzero = EOF or error, stop
                                  ; (same simplification DirCmd's own
                                  ; read loop already relies on - real,
                                  ; proven live this session)
        beq     fastload_read_loop
        jsr     KERNAL_CLRCHN
        lda     #1
        jsr     KERNAL_CLOSE
        lda     #0
        sta     fastload_error
        jmp     bank_return

fastload_ptr_inc
        inc     $14
        bne     fastload_ptr_inc_done
        inc     $15
fastload_ptr_inc_done
        rts
