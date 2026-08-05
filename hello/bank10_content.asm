; Bank 10 content: DISK category (DIR/DEVICE/CD/DELETE/RENAME). Real
; KERNAL disk I/O, verified live in VICE before writing any of this -
; not guessed at, per this project's established practice (see the
; [[feedback-verify-c64-facts]] memory: three real bugs in this project
; already came from unverified ROM/hardware assumptions): the exact
; byte layout of a "$" directory listing (link/size/text/$00 per entry,
; filenames stored with the high bit set so a plain CHROUT loop renders
; them correctly) was captured directly from a real load in VICE, not
; recalled from memory.
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

; Real CHROUT color codes (not custom rendering) - same mechanism as
; bank1_content.asm's HELP_WHITE/HELP_LTBLU/HELP_CYAN.
DIR_WHITE = $05
DIR_LTBLU = $9a
DIR_CYAN  = $9f
DIR_RED   = $1c
DIR_GREEN = $1e

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
KERNAL_CHKIN  = $ffc6
KERNAL_CHKOUT = $ffc9
KERNAL_CHRIN  = $ffcf
KERNAL_CLRCHN = $ffcc
KERNAL_LOAD   = $ffd5
KERNAL_SAVE   = $ffd8

; Real BASIC ROM ($A000-$BFFF, always mapped regardless of EasyFlash
; banking) - verified by static disassembly, same bar as BAS_FRMNUM/
; BAS_GETADR elsewhere in this project. See bank1_content.asm's RENUM
; header comment for the full LINKPRG writeup: it relinks a program's
; line pointers by scanning for each line's own $00 terminator (not by
; trusting stale ones), leaving the address of the final terminator's
; own start in $22/$23 - the caller has to add 2 (past that terminator)
; before storing into VARTAB, confirmed against real NEW's own identical
; +2 (verified: $a64c-$a657) - exactly what's needed after DLOAD
; replaces the program, same as after RENUM rewrites it.
; Deliberately NOT using real BASIC's own post-LOAD tail ($A659, the
; same shared NEW/CLR routine RENUM's header explains) - it resets the
; CPU stack and manufactures its own return assuming its caller is
; BASIC's main loop, which isn't true several JSRs deep inside bank_call.
BAS_LINKPRG = $a533
BAS_DATAPTR_RESET = $a81d

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
; DISK command (0-255). Originally used BAS_FRMNUM/BAS_GETADR (real
; BASIC ROM expression evaluation), the same pattern BankCmd uses - but
; that's exactly what's live when this locks up on real typed input
; ("DEVICE 8"), and BankCmd's own use of the identical pattern was never
; actually confirmed working either (just assumed, per the old comment
; here - a real bug in this project's own established practice of not
; trusting an unverified assumption). BASIC's error dispatcher (already
; documented elsewhere in this project - see resident.asm's OkNew
; comment on RUN's manufactured-return trick) resets the CPU stack to a
; fixed point and jumps straight back to the main loop on some error
; paths, completely bypassing bank_return_basic - which would strand
; SEI forever and leave cur_bank stuck on 10, exactly matching "locks
; up". Rather than chase which exact FRMEVL path triggers that without
; live hardware access, this sidesteps BAS_FRMNUM/BAS_GETADR entirely:
; a self-contained decimal parser using only BAS_CHRGET/BAS_CHRGOT
; (plain, balanced ROM routines - confirmed safe throughout this
; project already) and pdw_lo/pdw_hi as a 16-bit accumulator (free,
; shared scratch - see resident.asm's print_decimal_word/bank5's
; dec_to_buf for the same reuse). Same *10+digit shift/add technique as
; RENUM's renum_x10_plus_digit (bank1_content.asm) - accumulates as a
; full 16-bit value so a value briefly over 255 mid-parse doesn't wrap
; and hide a real range error; only checked against 255 once parsing
; finishes. ---
DeviceCmd
        jsr     BAS_CHRGOT
        cmp     #'0'
        bcs     +
        jmp     device_syntax_error
+       cmp     #'9'+1
        bcc     dv_first_ok
        jmp     device_syntax_error
dv_first_ok
        lda     #0
        sta     pdw_lo
        sta     pdw_hi
dv_loop
        jsr     BAS_CHRGOT
        cmp     #'0'
        bcc     dv_parsed
        cmp     #'9'+1
        bcs     dv_parsed
        lda     pdw_hi          ; overflow guard: once the accumulator
        beq     dv_digit_ok     ; already exceeds 255 (hi nonzero), any
        jmp     device_range_error     ; further digit only makes it a
                                         ; bigger out-of-range value -
                                         ; caught here every iteration,
                                         ; before another *10+digit can
                                         ; ever get near a real 16-bit
                                         ; (65535) wraparound
dv_digit_ok
        jsr     BAS_CHRGOT
        sec
        sbc     #'0'
        pha
        jsr     BAS_CHRGET      ; advance past this digit
        pla
        pha                     ; dev_acc = dev_acc*10 + digit, same
        lda     pdw_lo          ; shift/add sequence as RENUM's
        asl                     ; renum_x10_plus_digit
        sta     dv_tmp_lo
        lda     pdw_hi
        rol
        sta     dv_tmp_hi
        lda     dv_tmp_lo
        sta     pdw_lo
        lda     dv_tmp_hi
        sta     pdw_hi
        asl     pdw_lo
        rol     pdw_hi
        asl     pdw_lo
        rol     pdw_hi
        clc
        lda     pdw_lo
        adc     dv_tmp_lo
        sta     pdw_lo
        lda     pdw_hi
        adc     dv_tmp_hi
        sta     pdw_hi
        pla
        clc
        adc     pdw_lo
        sta     pdw_lo
        bcc     +
        inc     pdw_hi
+       jmp     dv_loop
dv_parsed
        lda     pdw_hi          ; hi byte clear -> pdw_lo alone (an
        bne     device_range_error     ; 8-bit value) is already 0-255,
        lda     pdw_lo                  ; nothing further to check
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
device_syntax_error
        ldx     #0
device_syn_loop
        lda     device_syn_msg,x
        beq     device_syn_done
        jsr     $ffd2
        inx
        bne     device_syn_loop
device_syn_done
        jmp     bank_return_basic
device_err_msg
        !text   "?DEVICE OUT OF RANGE (0-255)"
        !byte   13,0
device_syn_msg
        !text   "?SYNTAX ERROR"
        !byte   13,0

; --- DIR: real "$" directory listing. Loads into dir_buffer (slots.asm)
; via secondary address 0, which per the real (verified, not the
; earlier wrong assumption here) KERNAL LOAD semantics means "ignore
; the file's own embedded 2-byte address, use the X/Y address passed to
; LOAD instead". An earlier version of this used secondary address 1
; with a comment claiming THAT meant "use our own address" - backwards:
; SA=1 actually means "use the file's OWN embedded address, ignore X/Y
; entirely" - which for a "$" directory listing is a fixed spot inside
; live screen memory ($0401), so the real directory data was landing
; there instead of dir_buffer (visible as garbled/graphics-looking
; characters splattered across the screen), while dir_buffer itself
; was never actually written and dir_entry_loop below was walking
; whatever uninitialized memory happened to be sitting there - caught
; live via garbage output ("65535" from print_decimal_word on
; leftover/uninitialized bytes) once someone actually looked at real
; output, not just whether the LOAD call errored. Prints "<blocks>
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
; Suppresses KERNAL's own "SEARCHING FOR $"/"LOADING" status messages
; for the duration of the LOAD below (SETMSG, real KERNAL $FF90 -
; confirmed by disassembling the real ROM: it's just "STA $9D" plus a
; small shared status-clear tail, so any A value is taken literally as
; the new MSGFLG). Without this, those messages ran straight into our
; own first output line with no newline between them ("LOADING0
; TESTDISK"). Saved/restored around the LOAD call itself (via PHP/PHA,
; PLA/PLP - PHP specifically to protect LOAD's own carry result, which
; SETMSG's own internal execution could otherwise clobber) rather than
; disabled permanently, so a real LOAD/SAVE typed later still shows its
; own status messages normally.
; NOTE: this used to also suppress KERNAL's own "SEARCHING FOR $"/
; "LOADING" messages via SETMSG ($FF90, A=0) around the LOAD call
; below, purely cosmetic (so they wouldn't run into this command's own
; first output line). Reverted: confirmed live in VICE that it broke
; DIR outright (instant blue-screen reset, zero output - matching real
; BASIC's own native RESTOR/CINT error-recovery path firing, bypassing
; dir_load_error's own "bcs" check entirely). Real KERNAL LOAD very
; likely branches to a completely different internal path when its own
; "show my messages" flag is off - probably assuming it's being called
; the same way BASIC's own LOAD statement calls it, jumping straight
; into BASIC's native error reporting on failure instead of just
; returning with carry set - not worth chasing further to keep a
; cosmetic improvement; the KERNAL chatter is back but DIR works.
; --- Reads the "$" directory via OPEN/CHKIN/CHRIN instead of the
; higher-level KERNAL_LOAD - deliberately: LOAD prints its own
; "SEARCHING FOR $"/"LOADING" status text (real KERNAL behavior, gated
; by MSGFLG/$9D), and suppressing that via SETMSG was tried and
; confirmed live in VICE to break DIR outright (instant reset, likely
; LOAD taking a different internal path - probably assuming BASIC's own
; error-reporting convention - when its message flag is off). OPEN/
; CHKIN/CHRIN never runs any of LOAD's own message-printing code at
; all, sidestepping the whole class of risk rather than fighting it -
; same low-level primitives send_command already uses successfully
; elsewhere in this file, just CHKIN (input) instead of CHKOUT
; (output). $90 is real KERNAL STATUS, updated by CHRIN on every read;
; nonzero means EOF or a real error either way, both correctly stop the
; read here. ---
DirCmd
        lda     #1
        ldx     #<dir_name
        ldy     #>dir_name
        jsr     KERNAL_SETNAM
        lda     #2            ; logical file number
        ldx     disk_device
        ldy     #0            ; secondary address (no LOAD-style embedded-
                                ; vs-supplied-address distinction here)
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        bcc     +
        jmp     dir_load_error
+       ldx     #2
        jsr     KERNAL_CHKIN
        bcc     +
        jmp     dir_chkin_error
+       jsr     KERNAL_CHRIN    ; discard the file's own embedded load
        jsr     KERNAL_CHRIN    ; address (2 bytes) - every C64 PRG file,
                                  ; including this pseudo-file, starts
                                  ; with one; real KERNAL_LOAD always
                                  ; consumes it itself and never stores it
                                  ; into the destination buffer, but a raw
                                  ; CHRIN loop has no such built-in
                                  ; special case - without this, dir_buffer
                                  ; started 2 bytes offset from every real
                                  ; entry, showing garbage numbers first
        lda     #<dir_buffer
        sta     $14
        lda     #>dir_buffer
        sta     $15
dir_read_loop
        jsr     KERNAL_CHRIN
        ldy     #0
        sta     ($14),y
        jsr     dir_ptr_inc
        lda     $90             ; STATUS - nonzero = EOF or error, stop
        beq     dir_read_loop
        jsr     KERNAL_CLRCHN
        lda     #2
        jsr     KERNAL_CLOSE
        lda     #<dir_buffer
        sta     $14
        lda     #>dir_buffer
        sta     $15
        ldx     #0
dir_header_loop
        lda     dir_header_msg,x
        beq     dir_header_done
        jsr     $ffd2
        inx
        bne     dir_header_loop
dir_header_done
; --- Just the filenames, one per line, "NAME.TYPE" in white - no block
; counts, no the disk-name/ID header line, no "BLOCKS FREE." footer.
; The header entry (disk name + 2-char format ID, e.g. "2A") and the
; trailing free-space entry are both distinguishable from a real file
; without any special-case text matching: every REAL file's own size
; field (the 2 bytes right after the link pointer) is always >= 1
; block, while the header entry's is always exactly 0 - and the free-
; space entry has no quoted name at all (dir_find_quote hits the $00
; terminator before ever finding an opening quote). Both cases skip via
; dir_skip_silent, which walks to the terminator without printing
; anything AND without printing the trailing CR real entries get -
; otherwise the header/footer would still leave behind blank lines. ---
dir_entry_loop
        ldy     #0
        lda     ($14),y
        sta     disk_namelen    ; reused as a plain 1-byte scratch here
        iny
        lda     ($14),y
        ora     disk_namelen
        bne     +
        jmp     dir_done        ; link == $0000 -> end of directory
+
        ldy     #2
        lda     ($14),y
        sta     disk_namelen    ; size, low byte (scratch, see above)
        iny
        lda     ($14),y
        sta     disk_namelen2   ; size, high byte (scratch - RENAME's
                                  ; own use never overlaps DIR's)
        clc                     ; advance past the 4-byte link+size header
        lda     $14
        adc     #4
        sta     $14
        bcc     +
        inc     $15
+
        lda     disk_namelen
        ora     disk_namelen2
        bne     dir_find_quote  ; size != 0 -> a real file, try to print it
        jmp     dir_skip_silent ; size == 0 -> disk-name/ID header entry
dir_find_quote
        ldy     #0
        lda     ($14),y
        bne     +
        jmp     dir_skip_silent ; terminator, no quote found (free-space
                                  ; entry - "BLOCKS FREE." has none)
+       cmp     #CHR_QUOTE
        beq     dir_quote_found
        jsr     dir_ptr_inc
        jmp     dir_find_quote
; Name and type are buffered (not printed as they're walked) so the
; whole entry's color can be decided up front: red for a name ending
; ".BIN", green for a "PRG" type, white for everything else. Buffering
; first (rather than a lookahead/lookback while streaming) is the
; simplest way to know the name's last 4 chars before any of it has
; been printed.
dir_quote_found
        jsr     dir_ptr_inc     ; skip the opening quote
        ldx     #0
dir_buf_name_loop
        ldy     #0
        lda     ($14),y
        beq     dir_buf_name_done ; terminator with no closing quote -
                                    ; shouldn't happen for a real entry,
                                    ; but don't run off the end
        cmp     #CHR_QUOTE
        beq     dir_buf_name_closed
        cpx     #FILENAME_MAXLEN ; don't overrun the buffer on a
        beq     dir_buf_name_skip ; longer-than-expected name
        sta     dir_namebuf,x
        inx
dir_buf_name_skip
        jsr     dir_ptr_inc
        jmp     dir_buf_name_loop
dir_buf_name_closed
        jsr     dir_ptr_inc     ; skip the closing quote
dir_buf_name_done
        stx     dir_namebuf_len
; Padding between the closing quote and the type (PRG/SEQ/etc) is
; variable-width (the drive right-pads short names to align it), so
; skip spaces first rather than assuming a fixed offset.
dir_skip_padding
        ldy     #0
        lda     ($14),y
        beq     dir_buf_type_done
        cmp     #' '
        bne     dir_buf_type_loop
        jsr     dir_ptr_inc
        jmp     dir_skip_padding
dir_buf_type_loop
        ldx     #0
dir_buf_type_char
        ldy     #0
        lda     ($14),y
        beq     dir_buf_type_done
        cmp     #' '            ; type is a short word (PRG/SEQ/USR/REL,
        beq     dir_buf_type_done ; sometimes < or * for locked/splat) -
        cpx     #3               ; a space marks the end of it
        beq     dir_buf_type_skip
        sta     dir_typebuf,x
        inx
dir_buf_type_skip
        jsr     dir_ptr_inc
        jmp     dir_buf_type_char
dir_buf_type_done
        stx     dir_typebuf_len
dir_skip_rest
        ldy     #0
        lda     ($14),y
        beq     dir_color_decide
        jsr     dir_ptr_inc
        jmp     dir_skip_rest
dir_color_decide
        lda     #0
        sta     dir_name_has_dot
        ldx     #0
dir_scan_dot_loop
        cpx     dir_namebuf_len
        beq     dir_scan_dot_done
        lda     dir_namebuf,x
        cmp     #'.'
        bne     dir_scan_dot_next
        lda     #1
        sta     dir_name_has_dot
        jmp     dir_scan_dot_done
dir_scan_dot_next
        inx
        jmp     dir_scan_dot_loop
dir_scan_dot_done
        lda     #DIR_WHITE
        sta     dir_entry_color
        lda     dir_namebuf_len
        cmp     #4
        bcc     dir_check_prg    ; too short to end in ".BIN"
        sec
        sbc     #4
        tax
        lda     dir_namebuf,x
        cmp     #'.'
        bne     dir_check_prg
        inx
        lda     dir_namebuf,x
        cmp     #'B'
        bne     dir_check_prg
        inx
        lda     dir_namebuf,x
        cmp     #'I'
        bne     dir_check_prg
        inx
        lda     dir_namebuf,x
        cmp     #'N'
        bne     dir_check_prg
        lda     #DIR_RED
        sta     dir_entry_color
        jmp     dir_print_entry
dir_check_prg
        lda     dir_typebuf_len
        cmp     #3
        bne     dir_print_entry
        lda     dir_typebuf+0
        cmp     #'P'
        bne     dir_print_entry
        lda     dir_typebuf+1
        cmp     #'R'
        bne     dir_print_entry
        lda     dir_typebuf+2
        cmp     #'G'
        bne     dir_print_entry
        lda     #DIR_GREEN
        sta     dir_entry_color
dir_print_entry
        lda     dir_entry_color
        jsr     $ffd2
        ldx     #0
dir_print_name_buf
        cpx     dir_namebuf_len
        beq     dir_print_name_buf_done
        lda     dir_namebuf,x
        jsr     $ffd2
        inx
        jmp     dir_print_name_buf
dir_print_name_buf_done
        lda     dir_name_has_dot
        beq     +
        jmp     dir_line_end     ; name already has its own extension -
                                    ; don't also append ".TYPE"
+       lda     #'.'
        jsr     $ffd2
        ldx     #0
dir_print_type_buf
        cpx     dir_typebuf_len
        beq     dir_line_end
        lda     dir_typebuf,x
        jsr     $ffd2
        inx
        jmp     dir_print_type_buf
dir_line_end
        jsr     dir_ptr_inc     ; skip the $00 terminator - now pointing
                                  ; at the next entry's link
        lda     #13
        jsr     $ffd2
        jmp     dir_entry_loop
dir_skip_silent
        ldy     #0
        lda     ($14),y
        beq     dir_skip_silent_done
        jsr     dir_ptr_inc
        jmp     dir_skip_silent
dir_skip_silent_done
        jsr     dir_ptr_inc     ; skip the $00 terminator - no CR, this
        jmp     dir_entry_loop   ; entry printed nothing
dir_done
        lda     #DIR_LTBLU      ; restore CINT's own default text color -
        jsr     $ffd2            ; see bank1_content.asm's HELP_LTBLU for
                                  ; why (same idea: don't let a command's
                                  ; own color choice bleed into whatever
                                  ; prints after it)
        jmp     bank_return_basic
dir_chkin_error
        pha
        jsr     KERNAL_CLRCHN   ; CHKIN failed after a successful OPEN -
        lda     #2              ; close the now-orphaned channel before
        jsr     KERNAL_CLOSE    ; reporting the error
        pla
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
; Starts on its own fresh line below the typed "DIR" (same reason
; HELP's own text starts with a leading CR), then "DIRECTORY LISTING"
; in the same cyan HELP uses for its own category labels, underlined
; with a dash row matching the title's own width (not a full-page
; divider like HELP's own 40-dash rule, which spans its wider titles) -
; DIR_WHITE for the actual filenames right below already; nothing here
; needs its own color reset before continuing into dir_entry_loop.
dir_header_msg
        !byte   13
        !byte   DIR_CYAN
        !text   "DIRECTORY LISTING"
        !byte   13
        !text   "-----------------"
        !byte   13,0
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
; NOTE on the three error exits below: this routine is always entered
; via "jsr parse_filename", but its error paths jump straight to a
; shared handler (disk_missing_quote/disk_name_too_long) that ends in
; "jmp bank_return_basic" instead of RTS-ing back to the caller first -
; leaving this routine's own JSR return address orphaned on the stack.
; bank_return_basic's single PLA then pops half of that orphaned
; address instead of bank_call's real "old bank" byte, writes the
; garbage to the actual EasyFlash bank register, and jumps into
; whatever ROM that selects - a JAM. Confirmed live via the identical
; bug in bank11_content.asm's net_parse_str (same shape, caught when
; HTTPGET was first tested against real typed input) - this routine
; was never actually exercised down its error paths before, only the
; success path ("Working, KERNAL-verified live in VICE" was true of
; DIR/CD/etc.'s normal operation, not of typing a bare unclosed quote).
; Fix: PLA twice (discard the orphaned return address) before jumping
; to the shared handler, restoring the stack to pre-JSR state.
parse_filename
        jsr     BAS_CHRGOT
        cmp     #CHR_QUOTE
        beq     pf_have_quote
        pla
        pla
        jmp     disk_missing_quote
pf_have_quote
        ldy     #0
pf_loop
        jsr     BAS_CHRGET
        cmp     #CHR_QUOTE
        beq     pf_close
        cmp     #0
        bne     pf_not_end
        pla
        pla
        jmp     disk_missing_quote
pf_not_end
        cpy     #FILENAME_MAXLEN
        bcc     pf_store
        pla
        pla
        jmp     disk_name_too_long
pf_store
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
; Same stack-orphaning hazard as parse_filename above - same fix.
parse_filename2
        jsr     BAS_CHRGOT
        cmp     #CHR_QUOTE
        beq     pf2_have_quote
        pla
        pla
        jmp     disk_missing_quote
pf2_have_quote
        ldy     #0
pf2_loop
        jsr     BAS_CHRGET
        cmp     #CHR_QUOTE
        beq     pf2_close
        cmp     #0
        bne     pf2_not_end
        pla
        pla
        jmp     disk_missing_quote
pf2_not_end
        cpy     #FILENAME_MAXLEN
        bcc     pf2_store
        pla
        pla
        jmp     disk_name_too_long
pf2_store
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

; --- DLOAD "name": loads a PRG into the current BASIC program area,
; using disk_device instead of needing ",8" every time. Secondary
; address 0 with X/Y=TXTTAB (not 1, and not the file's own embedded
; address) - same "force our own address, ignore the file's" convention
; DIR's own header comment already worked out and verified live for
; the "$" directory listing, and the same behavior real BASIC's own
; plain "LOAD" statement uses for a normal (non-",1") program load.
; After a successful load, TXTTAB has real tokenized program bytes but
; every OTHER pointer (VARTAB, ARYTAB, STREND, FRETOP) is stale from
; whatever program used to be there - BAS_LINKPRG plus the same 6
; pointer copies RENUM's finalize step already does (bank1_content.asm)
; fixes that up, real BASIC ROM code exercising the exact same path a
; real LOAD would. ---
DloadCmd
        jsr     parse_filename
        sty     disk_namelen
        lda     disk_namelen
        ldx     #<filename_buf
        ldy     #>filename_buf
        jsr     KERNAL_SETNAM
        lda     #1              ; logical file number
        ldx     disk_device
        ldy     #0              ; SA=0: force load to X/Y below, ignore
        jsr     KERNAL_SETLFS    ; the file's own embedded address
        lda     #0              ; 0 = load (not verify)
        ldx     $2b             ; TXTTAB low
        ldy     $2c             ; TXTTAB high
        jsr     KERNAL_LOAD
        bcs     dload_error
        jsr     BAS_LINKPRG
        clc                     ; VARTAB = end of program: LINKPRG leaves
        lda     $22             ; $22/$23 pointing AT the final 0000
        adc     #2              ; terminator's own start, not past it -
        sta     $2d             ; real NEW ($a64c-$a657, verified) always
        lda     $23             ; adds 2 for exactly this reason (it
        adc     #0              ; writes that same terminator at TXTTAB,
        sta     $2e             ; then sets VARTAB=TXTTAB+2)
        lda     $2d
        sta     $2f             ; ARYTAB = VARTAB
        lda     $2e
        sta     $30
        lda     $2d
        sta     $31             ; STREND = VARTAB
        lda     $2e
        sta     $32
        lda     $37
        sta     $33             ; FRETOP = MEMSIZ
        lda     $38
        sta     $34
        jsr     BAS_DATAPTR_RESET
        jmp     bank_return_basic
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
        !text   "?LOAD ERROR "
        !byte   0

; --- DSAVE "name": saves the current BASIC program (TXTTAB to VARTAB)
; using disk_device, same "no ,8 needed" convenience as DLOAD. KERNAL
; SAVE's calling convention (A = zero-page address of a 2-byte pointer
; to the START address, X/Y = END address directly, not a pointer) -
; confirmed by disassembling the real KERNAL ROM's own $FFD8 jump-table
; entry (kernal-901227-03.bin, the same image VICE loads): it reads
; ($00,X) from whatever zero-page address A holds, i.e. #$2b here reads
; TXTTAB itself as the start address. ---
DsaveCmd
        jsr     parse_filename
        sty     disk_namelen
        lda     disk_namelen
        ldx     #<filename_buf
        ldy     #>filename_buf
        jsr     KERNAL_SETNAM
        lda     #1
        ldx     disk_device
        ldy     #0
        jsr     KERNAL_SETLFS
        lda     #$2b            ; zero-page pointer to the start address
        ldx     $2d             ; VARTAB low (end address)
        ldy     $2e             ; VARTAB high
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
        !text   "?SAVE ERROR "
        !byte   0

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

