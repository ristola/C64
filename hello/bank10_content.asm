; Bank 10 content: DISK category (DIR/DEVICE/CD/DELETE/RENAME/DLOAD/
; DSAVE). Real KERNAL disk I/O, verified live in VICE before writing
; any of this - not guessed at, per this project's established practice
; (see the [[feedback-verify-c64-facts]] memory: three real bugs in this
; project already came from unverified ROM/hardware assumptions):
;   - the exact byte layout of a "$" directory listing (link/size/text/
;     $00 per entry, filenames stored with the high bit set so a plain
;     CHROUT loop renders them correctly) was captured directly from a
;     real load in VICE, not recalled from memory.
;   - DLOAD's post-load fixup (VARTAB relink + JSR $A659/$A533/JMP
;     $A480, not BAS_NEWSTT) was found by breakpointing $FFD5 and
;     single-stepping real BASIC ROM's own "LOAD" command handler.
;   - DSAVE's KERNAL SAVE calling convention (A = zero-page address of
;     the start pointer, X/Y = end address) was confirmed the same way,
;     breakpointing $FFD8 during a real "SAVE" command.
;
; LOAD/SAVE are stock BASIC V2 keywords already - the tokenizer would
; never reach our own tables for those exact names (stock keyword table
; is tried first), so these are DLOAD/DSAVE instead, per slots.asm's
; own comment on the same collision.
;
; DELETE/RENAME/CD are scoped to quoted filename literals only (not a
; general string expression via FRMEVL) - real filenames are what every
; one of these commands actually needs in practice, and this avoids
; depending on BASIC's string-descriptor/FRMEVL-return internals, which
; have never been verified in this project (unlike the numeric BAS_
; FRMNUM/BAS_GETADR path, already proven by BANK/DEVICE). DELETE/
; RENAME/CD also don't read back the disk drive's error-channel
; response - a real failure (e.g. file not found) fails silently for
; now; reading channel 15's response back is a reasonable later
; refinement, not attempted here.

BAS_FRMNUM  = $ad8a      ; evaluate + require a numeric expression
BAS_GETADR  = $b7f7      ; convert FAC1 to a 16-bit int in $14/$15
BAS_CHRGET  = $73        ; JSR: get next char, advance TXTPTR
BAS_CHRGOT  = $79        ; JSR: re-get current char, don't advance
CHR_QUOTE   = $22

; Zero page $14/$15 is used as a plain traversal pointer by both DIR
; (see dir_ptr_inc below) and send_command's scmd_ptr - never at the
; same time, since DIR always finishes before DELETE/RENAME/CD/
; send_command ever runs. Reuses the same "safe between a BAS_GETADR
; call and printing" window bank6_content.asm's BankCmd already relies
; on - nothing here calls BAS_FRMNUM/BAS_GETADR to conflict with it.
; Defined here (before first use) rather than down by send_command
; itself so ACME resolves it as zero-page on the first pass instead of
; falling back to a wider absolute-addressing encoding.
scmd_ptr = $14

KERNAL_SETNAM = $ffbd
KERNAL_SETLFS = $ffba
KERNAL_OPEN   = $ffc0
KERNAL_CLOSE  = $ffc3
KERNAL_CHKOUT = $ffc9
KERNAL_CLRCHN = $ffcc
KERNAL_LOAD   = $ffd5
KERNAL_SAVE   = $ffd8

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_DIR-*, $ff
        jmp     DirCmd
!fill SLOT_DEVICE-*, $ff
        jmp     DeviceCmd
!fill SLOT_CD-*, $ff
        jmp     CdCmd
!fill SLOT_DELETE-*, $ff
        jmp     DeleteCmd
!fill SLOT_RENAME-*, $ff
        jmp     RenameCmd
!fill SLOT_DLOAD-*, $ff
        jmp     DloadCmd
!fill SLOT_DSAVE-*, $ff
        jmp     DsaveCmd

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill $8100-*, $ff

*=$8100

; --- DEVICE <n>: set the default device number used by every other
; DISK command. Any byte value is accepted (0-255, same as BankCmd's
; numeric-argument pattern in bank6_content.asm) - unlike an out-of-
; range bank number, a bogus device number can't crash anything; the
; KERNAL will just report "DEVICE NOT PRESENT" naturally when used. ---
DeviceCmd
        lda     #$00
        sta     $0d           ; BAS_VALTYP (see bank6_content.asm's
                                ; BankCmd for why this is a literal here)
        jsr     BAS_FRMNUM
        jsr     BAS_GETADR    ; $14/$15 = 16-bit value, low/high
        lda     $15
        bne     device_range_error
        lda     $14
        sta     disk_device
        jmp     bank_return_basic
device_range_error
        ldx     #0
device_err_loop
        lda     device_err_msg,x
        beq     device_err_done
        jsr     $ffd2
        inx
        bne     device_err_loop
device_err_done
        jmp     bank_return_basic
device_err_msg
        !text   "?DEVICE OUT OF RANGE (0-255)"
        !byte   13,0

; --- DIR: real "$" directory listing. Loads into dir_buffer (slots.asm)
; via secondary address 1 with our own target address, NOT secondary 0
; (which would use the file's embedded address - $0801, clobbering the
; user's actual BASIC program) - verified live in VICE. Prints "<blocks>
; <filename>" one line per entry, including the header line (which
; prints as "0 <diskname>"): entries are plain PETSCII text, not real
; BASIC tokens, so this just walks dir_buffer linearly using the $00
; terminator each entry ends with, stopping at an all-zero link. The
; binary block-count is printed with print_decimal_word rather than
; copied from the entry's own text bytes (which are pre-padded for
; BASIC's LIST command to insert its own line-number text into - not
; useful here since DIR does its own printing, not LIST's). Uses zero
; page $14/$15 as its own traversal pointer once the load itself is
; done - the same "safe to reuse between a BAS_GETADR call and printing"
; window bank6_content.asm's BankCmd already relies on; nothing in this
; loop calls BAS_FRMNUM/BAS_GETADR again to conflict with it. ---
DirCmd
        lda     #1
        ldx     #<dir_name
        ldy     #>dir_name
        jsr     KERNAL_SETNAM
        lda     #2            ; logical file number
        ldx     disk_device
        ldy     #1            ; secondary address 1: use OUR address below,
                                ; not the file's own embedded one
        jsr     KERNAL_SETLFS
        lda     #0            ; 0 = load (not verify)
        ldx     #<dir_buffer
        ldy     #>dir_buffer
        jsr     KERNAL_LOAD
        bcs     dir_load_error
        lda     #<dir_buffer
        sta     $14
        lda     #>dir_buffer
        sta     $15
dir_entry_loop
        ldy     #0
        lda     ($14),y
        sta     disk_namelen    ; reused as a plain 1-byte scratch here
        iny
        lda     ($14),y
        ora     disk_namelen
        beq     dir_done        ; link == $0000 -> end of directory
        ldy     #2
        lda     ($14),y
        pha
        iny
        lda     ($14),y
        tax                     ; X = size, high byte
        pla                     ; A = size, low byte
        jsr     print_decimal_word
        lda     #' '
        jsr     $ffd2
        clc                     ; advance past the 4-byte link+size header
        lda     $14
        adc     #4
        sta     $14
        bcc     dir_find_quote
        inc     $15
dir_find_quote
        ldy     #0
        lda     ($14),y
        beq     dir_line_end    ; terminator with no quote ever found
        cmp     #CHR_QUOTE
        beq     dir_quote_found
        jsr     dir_ptr_inc
        jmp     dir_find_quote
dir_quote_found
        jsr     dir_ptr_inc     ; skip the opening quote
dir_print_name
        ldy     #0
        lda     ($14),y
        beq     dir_line_end
        cmp     #CHR_QUOTE
        beq     dir_name_done
        jsr     $ffd2
        jsr     dir_ptr_inc
        jmp     dir_print_name
dir_name_done
        jsr     dir_ptr_inc     ; skip the closing quote
dir_skip_rest
        ldy     #0
        lda     ($14),y
        beq     dir_line_end
        jsr     dir_ptr_inc
        jmp     dir_skip_rest
dir_line_end
        jsr     dir_ptr_inc     ; skip the $00 terminator - now pointing
                                  ; at the next entry's link
        lda     #13
        jsr     $ffd2
        jmp     dir_entry_loop
dir_done
        jmp     bank_return_basic
dir_load_error
        pha
        ldx     #0
dir_err_loop
        lda     dir_err_msg,x
        beq     dir_err_msg_done
        jsr     $ffd2
        inx
        bne     dir_err_loop
dir_err_msg_done
        pla
        ldx     #0
        jsr     print_decimal_word
        lda     #13
        jsr     $ffd2
        jmp     bank_return_basic

dir_ptr_inc
        inc     $14
        bne     dir_ptr_inc_done
        inc     $15
dir_ptr_inc_done
        rts

dir_name
        !text   "$"
dir_err_msg
        !text   "?DISK ERROR "
        !byte   0

; --- Parses a double-quoted string literal starting at the current
; BASIC text position into filename_buf (up to FILENAME_MAXLEN chars),
; leaving BAS_TXTPTR positioned just after the closing quote. See this
; file's header comment for why this is scoped to literals only. On a
; missing opening quote, an unterminated string, or a name over
; FILENAME_MAXLEN, prints its own error and returns via bank_return_
; basic directly - same style as BankCmd's range-error handling in
; bank6_content.asm; never returns to its caller in that case.
; Returns: Y = filename length (0 for "").
parse_filename
        jsr     BAS_CHRGOT
        cmp     #CHR_QUOTE
        beq     pf_have_quote
        jmp     disk_missing_quote
pf_have_quote
        ldy     #0
pf_loop
        jsr     BAS_CHRGET
        cmp     #CHR_QUOTE
        beq     pf_close
        cmp     #0
        beq     disk_missing_quote
        cpy     #FILENAME_MAXLEN
        bcs     disk_name_too_long
        sta     filename_buf,y
        iny
        jmp     pf_loop
pf_close
        jsr     BAS_CHRGET           ; consume the closing quote
        rts

; Same as parse_filename, targeting filename2_buf - RENAME's second
; name. A second small copy rather than one routine taking a runtime
; buffer-select flag: the buffers are fixed compile-time addresses, and
; there's no free zero page for a genuine runtime pointer here (see
; DIR's own comment on reusing $14/$15 - only safe because nothing else
; needs it at that moment; parse_filename2 runs during RENAME's own
; argument parsing, a different, incompatible window).
parse_filename2
        jsr     BAS_CHRGOT
        cmp     #CHR_QUOTE
        beq     pf2_have_quote
        jmp     disk_missing_quote
pf2_have_quote
        ldy     #0
pf2_loop
        jsr     BAS_CHRGET
        cmp     #CHR_QUOTE
        beq     pf2_close
        cmp     #0
        beq     disk_missing_quote
        cpy     #FILENAME_MAXLEN
        bcs     disk_name_too_long
        sta     filename2_buf,y
        iny
        jmp     pf2_loop
pf2_close
        jsr     BAS_CHRGET
        rts

disk_missing_quote
        ldx     #0
dmq_loop
        lda     dmq_msg,x
        beq     dmq_done
        jsr     $ffd2
        inx
        bne     dmq_loop
dmq_done
        jmp     bank_return_basic
dmq_msg
        !text   "?MISSING QUOTE"
        !byte   13,0

disk_name_too_long
        ldx     #0
dntl_loop
        lda     dntl_msg,x
        beq     dntl_done
        jsr     $ffd2
        inx
        bne     dntl_loop
dntl_done
        jmp     bank_return_basic
dntl_msg
        !text   "?FILENAME TOO LONG"
        !byte   13,0

; --- Sends a command string (X/Y = pointer, null-terminated, built by
; each caller into dir_buffer - reused as scratch here since DIR isn't
; running at the same time) to the disk drive's command channel,
; exactly the public-KERNAL-API technique real BASIC programs use via
; "OPEN 15,dev,15" + "PRINT#15,cmd$" + "CLOSE 15" (OPEN/CHKOUT/CHROUT/
; CLRCHN/CLOSE - no ROM-internals guessing, same routines every disk-
; access reference uses). ---
send_command
        stx     scmd_ptr
        sty     scmd_ptr+1
        lda     #0
        ldx     scmd_ptr
        ldy     scmd_ptr+1
        jsr     KERNAL_SETNAM   ; no filename for OPEN itself
        lda     #15             ; logical file number
        ldx     disk_device
        ldy     #15             ; secondary address 15 = command channel
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        bcs     send_command_err
        ldx     #15
        jsr     KERNAL_CHKOUT
        bcs     send_command_err_close
        ldy     #0
sc_loop
        lda     (scmd_ptr),y
        beq     sc_done
        jsr     $ffd2
        iny
        bne     sc_loop
sc_done
        jsr     KERNAL_CLRCHN
        lda     #15
        jmp     KERNAL_CLOSE
send_command_err_close
        jsr     KERNAL_CLRCHN
        lda     #15
        jsr     KERNAL_CLOSE
send_command_err
        rts

; --- DELETE "name": disk drive SCRATCH command ("S0:name"). ---
DeleteCmd
        jsr     parse_filename
        sty     disk_namelen
        ldx     #0
        lda     #'S'
        sta     dir_buffer,x
        inx
        lda     #'0'
        sta     dir_buffer,x
        inx
        lda     #':'
        sta     dir_buffer,x
        inx
        ldy     #0
delete_copy
        cpy     disk_namelen
        beq     delete_copy_done
        lda     filename_buf,y
        sta     dir_buffer,x
        inx
        iny
        jmp     delete_copy
delete_copy_done
        lda     #0
        sta     dir_buffer,x
        ldx     #<dir_buffer
        ldy     #>dir_buffer
        jsr     send_command
        jmp     bank_return_basic

; --- RENAME "old","new": disk drive RENAME command ("R0:new=old"). ---
RenameCmd
        jsr     parse_filename        ; old name -> filename_buf
        sty     disk_namelen
        jsr     BAS_CHRGOT
        cmp     #','
        bne     rename_missing_comma
        jsr     BAS_CHRGET                   ; consume the comma
        jsr     parse_filename2       ; new name -> filename2_buf
        sty     disk_namelen2
        ldx     #0
        lda     #'R'
        sta     dir_buffer,x
        inx
        lda     #'0'
        sta     dir_buffer,x
        inx
        lda     #':'
        sta     dir_buffer,x
        inx
        ldy     #0
rename_copy_new
        cpy     disk_namelen2
        beq     rename_copy_new_done
        lda     filename2_buf,y
        sta     dir_buffer,x
        inx
        iny
        jmp     rename_copy_new
rename_copy_new_done
        lda     #'='
        sta     dir_buffer,x
        inx
        ldy     #0
rename_copy_old
        cpy     disk_namelen
        beq     rename_copy_old_done
        lda     filename_buf,y
        sta     dir_buffer,x
        inx
        iny
        jmp     rename_copy_old
rename_copy_old_done
        lda     #0
        sta     dir_buffer,x
        ldx     #<dir_buffer
        ldy     #>dir_buffer
        jsr     send_command
        jmp     bank_return_basic
rename_missing_comma
        ldx     #0
rmc_loop
        lda     rmc_msg,x
        beq     rmc_done
        jsr     $ffd2
        inx
        bne     rmc_loop
rmc_done
        jmp     bank_return_basic
rmc_msg
        !text   "?MISSING COMMA"
        !byte   13,0

; --- CD "name": partition/subdirectory change, CMD-drive convention
; ("CD:name"). Untested against real hardware (no CMD-style drive
; available here), but built from the same standard, documented
; command-channel technique as DELETE/RENAME above - the mechanism is
; verified even though this exact command string isn't. ---
CdCmd
        jsr     parse_filename
        sty     disk_namelen
        ldx     #0
        lda     #'C'
        sta     dir_buffer,x
        inx
        lda     #'D'
        sta     dir_buffer,x
        inx
        lda     #':'
        sta     dir_buffer,x
        inx
        ldy     #0
cd_copy
        cpy     disk_namelen
        beq     cd_copy_done
        lda     filename_buf,y
        sta     dir_buffer,x
        inx
        iny
        jmp     cd_copy
cd_copy_done
        lda     #0
        sta     dir_buffer,x
        ldx     #<dir_buffer
        ldy     #>dir_buffer
        jsr     send_command
        jmp     bank_return_basic

; --- DLOAD "name": real KERNAL LOAD using the file's own embedded
; address (secondary 0) - same "replace the current program" semantics
; as stock LOAD, which is the whole reason this exists (renamed only
; because the token LOAD is already a stock BASIC V2 keyword). A
; successful load needs BASIC's own post-load relink (VARTAB + JSR
; $A659/$A533/JMP $A480) instead of the usual JMP BAS_NEWSTT - see
; resident.asm's bank_return_load for the live-traced reasoning. ---
DloadCmd
        jsr     parse_filename
        tya                   ; A = length (must move before LDY below
                                ; clobbers Y, since Y held the length)
        ldx     #<filename_buf
        ldy     #>filename_buf
        jsr     KERNAL_SETNAM
        lda     #2            ; logical file number
        ldx     disk_device
        ldy     #0            ; secondary 0: use the file's own embedded
                                ; load address (real LOAD semantics)
        jsr     KERNAL_SETLFS
        lda     #0            ; 0 = load
        ldx     $2b           ; BASIC's own TXTTAB (start-of-program
        ldy     $2c           ; pointer) - stock LOAD passes this too,
                                ; confirmed live (X=$01/Y=$08 = $0801)
        jsr     KERNAL_LOAD
        bcs     dload_error
        stx     $2d           ; VARTAB low = load's returned end address
        sty     $2e           ; VARTAB high
        jmp     bank_return_load
dload_error
        pha
        ldx     #0
dload_err_loop
        lda     dload_err_msg,x
        beq     dload_err_msg_done
        jsr     $ffd2
        inx
        bne     dload_err_loop
dload_err_msg_done
        pla
        ldx     #0
        jsr     print_decimal_word
        lda     #13
        jsr     $ffd2
        jmp     bank_return_basic
dload_err_msg
        !text   "?DISK ERROR "
        !byte   0

; --- DSAVE "name": real KERNAL SAVE, saving the current BASIC program
; (TXTTAB through VARTAB, exactly what stock SAVE saves) - convention
; (A = zero-page address of the start pointer, X/Y = end address)
; confirmed live: breakpointing $FFD8 during a real "SAVE" command
; showed A=$2B, X/Y = VARTAB. ---
DsaveCmd
        jsr     parse_filename
        tya
        ldx     #<filename_buf
        ldy     #>filename_buf
        jsr     KERNAL_SETNAM
        lda     #2
        ldx     disk_device
        ldy     #0
        jsr     KERNAL_SETLFS
        lda     #$2b          ; zero-page address holding the start
                                ; pointer (TXTTAB, $2B/$2C)
        ldx     $2d           ; end address low = VARTAB low
        ldy     $2e           ; end address high = VARTAB high
        jsr     KERNAL_SAVE
        bcs     dsave_error
        jmp     bank_return_basic
dsave_error
        pha
        ldx     #0
dsave_err_loop
        lda     dsave_err_msg,x
        beq     dsave_err_msg_done
        jsr     $ffd2
        inx
        bne     dsave_err_loop
dsave_err_msg_done
        pla
        ldx     #0
        jsr     print_decimal_word
        lda     #13
        jsr     $ffd2
        jmp     bank_return_basic
dsave_err_msg
        !text   "?DISK ERROR "
        !byte   0
