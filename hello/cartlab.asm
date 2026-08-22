; ============================================================
; SHACKMATE Cartridge Lab - standalone disk program
; ============================================================
; Reads/backs up a target EPROM cartridge (Magic Desk protocol, $DE00
; bank-select) plugged directly into the C64's expansion port.
;
; Why this exists as a separate .prg instead of living in the SHACKMATE
; cartridge itself: this tool's whole point is to read a DIFFERENT
; cartridge than the one supplying the code that's running. Doing that
; from inside the SHACKMATE cartridge would require disabling its own
; ROM while code is still executing from it - survivable only via a
; RAM-trampoline, and there'd be no way to get the cartridge's own ROM
; back afterward without a second cartridge already occupying the port.
; A plain LOAD/RUN program sits in RAM from the moment it starts - none
; of ITS OWN code ever lives in $8000-$9FFF, so it can freely bank-
; switch and read that window without any risk of pulling the rug out
; from under itself. Workflow: boot normally, physically swap the
; SHACKMATE cartridge out for the target EPROM board, then
; LOAD"CARTLAB",8 and RUN.
;
; No JEDEC/chip-ID support: confirmed against the real SST27SF512
; datasheet that Product Identification on that chip (and the classic
; 27Cxxx parts before it) is a HARDWARE-only mode - it requires 11.4-
; 12V forced onto A9, a voltage this board cannot generate. There is no
; software command sequence that returns a usable ID on this hardware,
; so there's no point pretending otherwise with a fake protocol trace.
; Same underlying reason WRITE (F2 in the READ screen) always shows a
; "not supported" message instead of doing anything: programming this
; chip needs that same 11.4-12V, which this board cannot generate
; either - there is no software workaround for missing hardware.

; --- BASIC stub: "10 SYS2064" - RUN autostarts straight into the
; machine code at $0810 (2064 decimal), right after this 12-byte stub.
*=$0801
        !byte   $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00

*=$0810

; --- Zero page (this program owns the whole machine while it runs -
; BASIC is idle, not sharing the screen/keyboard with anything else,
; so there's no need to avoid BASIC's own $02-$8F pointer area the way
; the cartridge build's own code has to). ---
rd_addr      = $02   ; 2 bytes: indirect read pointer for the EPROM window
eprom_bank   = $06   ; which bank (0..EPROM_PHYSICAL_BANKS-1) is active -
                       ; also doubles as the current chunk number when
                       ; view_mode=1 (FILE VIEW)
eprom_offset = $07   ; 2 bytes: byte offset into that bank's own window
hd_count     = $09   ; 2 bytes: generic byte counter, reused by whichever
                       ; routine is running (READ EPROM's page-exit count,
                       ; read_device's digit count, fl_seek_chunk's skip
                       ; count - never more than one of these at once)
bt_same_flag = $0c   ; do_bank_test's own scratch (0=data differed)
fn_len       = $0d   ; BACKUP EPROM/DISK LOAD: number of characters typed
                       ; for the filename (also doubles as read_filename's
                       ; own buffer index while it's running)
dv_num       = $0e   ; BACKUP EPROM/DISK LOAD: target device number,
                       ; defaulted from the KERNAL's own current-device
                       ; byte ($BA) so it matches whatever device CARTLAB
                       ; was LOADed from instead of a hardcoded guess
view_mode    = $0f   ; READ EPROM screen: 0 = live cartridge (via $DE00),
                       ; 1 = FILE VIEW (via FILE_BUF, loaded by DISK LOAD)
pct_acc      = $10   ; 2 bytes: do_backup_eprom's own SAVE progress -
                       ; an 8.8 fixed-point accumulator, not a plain
                       ; percentage. EPROM_PHYSICAL_BANKS*64 pages make
                       ; up a whole backup; PCT_STEP (added once per
                       ; page) is chosen so the accumulator's HIGH byte
                       ; is always the correct 0-100 percent, reaching
                       ; exactly 100 on the final page with no rounding
                       ; drift - see PCT_STEP's own comment.
dir_ptr      = $12   ; 2 bytes: lr_read_dir's own directory-listing
                       ; traversal pointer - same byte-layout walk as
                       ; bank10_content.asm's DirCmd (verified live
                       ; there already; see lr_read_dir's own comment),
                       ; just a different zero-page address since this
                       ; program's own $02-$11 is already spoken for
lr_dest_ptr  = $14   ; 2 bytes: lr_rd_quote_found's own LR_NAME_TABLE
                       ; write pointer - separate from dir_ptr since
                       ; both are live at once while copying a filename
                       ; (dir_ptr reads the source listing, lr_dest_ptr
                       ; writes the destination table entry)
str_ptr_id   = $16   ; 2 bytes: this file's own generic print_str
                       ; pointer - shared by do_identify/do_file_tools
                       ; below, neither of which run concurrently with
                       ; each other or anything above using $16/$17
reu_c64_addr = $1a   ; 2 bytes: reu_xfer's own C64-side DMA address
reu_addr     = $1c   ; 3 bytes ($1c/$1d/$1e): reu_xfer's own REU-side
                       ; DMA address (lo/hi/bank) - a real REU only
                       ; needs enough of the bank byte to address its
                       ; own actual size; unused upper bits are simply
                       ; never set here
reu_len      = $1f   ; 2 bytes: reu_xfer's own transfer length (0 means
                       ; 65536, per the REU hardware's own convention -
                       ; not used that way here, every real transfer
                       ; this file ever asks for is 1-8192 bytes)
rp_initialized = $21 ; 0 until do_read_eprom's first-ever entry, which
                       ; zeroes eprom_bank/eprom_offset/view_mode and
                       ; sets this to 1 - every entry after that skips
                       ; the reset, so backing out (<-) and pressing R
                       ; again resumes exactly where you left off
                       ; (live bank/offset, or FILE VIEW with whatever
                       ; was loaded) instead of jumping back to live
                       ; bank $00
reu_checked  = $22   ; 0 until start's first-ever run, which calls
                       ; check_reu_present exactly once and sets this to
                       ; 1 - never re-checked after that, since the
                       ; check itself clobbers FILE_BUF/REU bank 0
                       ; offset 0 and would corrupt a real loaded file
                       ; if it ran again on every menu redraw
reu_present  = $23   ; set by check_reu_present: 1 = REU hardware
                       ; responded correctly to a STORE+FETCH round
                       ; trip, 0 = it didn't (REU disabled/absent - see
                       ; check_reu_present's own comment). DISK LOAD (the
                       ; one REU-dependent entry point left after VERIFY/
                       ; COMPARE was removed) checks this first via reu_
                       ; gate and refuses with a clear message instead of
                       ; silently showing
                       ; stale/wrong data the way FILE VIEW paging used
                       ; to when reu_xfer's FETCH/STORE silently no-op
                       ; with no REU present - confirmed live as the
                       ; actual root cause of that bug

; FILE_BUF used to sit at $2000, back when this program's own code was
; well under 8K. It has since grown past $2000 (REU TOOLS/DIAGNOSTICS/
; SEARCH ROM/etc. all added since) - confirmed live: the tail end of
; dm_hdr_msg (DIAGNOSTICS' own header text) landed at $1ff4 and ran
; past $2000, so any earlier DISK LOAD/REU LOAD write into FILE_BUF was
; silently overwriting that string (and whatever other code/data
; happened to land in $2000+), which is why DIAGNOSTICS specifically
; printed garbage and hung after using LOAD/REU first. FILE_BUF is
; just a symbolic address, not something the assembler tracks
; positionally the way *=$8000-style bank content is on the cartridge
; side, so nothing caught this at build time - see the !if guard at the
; very end of this file, added for exactly that reason. Moved above
; LR_NAME_TABLE's own end ($4000+1088=$4440) with real margin instead
; of back below $2000, since this program keeps growing and $2000 has
; already proven too tight once.
FILE_BUF = $4500     ; scratch 8KB buffer for DISK LOAD/REU TOOLS - well
                       ; clear of LR_NAME_TABLE ($4000-$4440) below it
                       ; and the cartridge ROM window ($8000-$9FFF)
                       ; above it, so it's safe regardless of which view
                       ; mode is currently active

EASYFLASH_BANK    = $de00

; --- Standard Commodore REU (1700/1764/1750) DMA register interface -
; $DF00-$DF0A, identical on real REU hardware and VICE's own REU
; emulation (-reu). This is well-established, decades-old public REU
; documentation, NOT verified against a physical REU by this project -
; unlike the SST27SF512/EASYFLASH_BANK facts elsewhere in this file,
; there is no REU hardware here yet to confirm it against, so treat the
; exact command-byte/status-bit values as "standard, but worth a real
; live test" rather than already-confirmed project fact. The DMA
; transfer itself steals bus cycles the same way VIC-II badlines do -
; by the time the instruction after the command-register write runs,
; the whole transfer has already completed, so none of this needs a
; completion-polling loop. ---
REU_STATUS   = $df00   ; R: bit7=IRQ bit6=End Of Block bit5=FAULT
                          ; (verify mismatch) - reading this register
                          ; clears bits 7-5
REU_COMMAND  = $df01   ; W: writing here (with the execute bit set)
                          ; starts the transfer immediately
REU_C64_LO   = $df02
REU_C64_HI   = $df03
REU_REU_LO   = $df04
REU_REU_HI   = $df05
REU_REU_BANK = $df06
REU_LEN_LO   = $df07
REU_LEN_HI   = $df08
REU_IRQ_MASK = $df09
REU_ADDR_CTRL = $df0a

; Command byte = execute(bit7) + FF00-disable(bit4, so the write here
; itself triggers the transfer rather than needing a dummy STA $FF00
; first) + transfer type (bits1-0): 00=C64->REU 01=REU->C64 10=SWAP
; 11=COMPARE. These exact byte values ($90/$91/$93) are the ones
; universally cited in REU programming references.
REU_CMD_STORE   = $90   ; C64 -> REU
REU_CMD_FETCH   = $91   ; REU -> C64
REU_CMD_COMPARE = $93   ; REU vs C64, sets STATUS bit5 (FAULT) on any
                           ; mismatch found during the transfer

; --- REU layout - three fixed 64K regions, each the bank byte of a
; REU address with lo/hi always 0 at the region's own start (a 24-bit
; REU address is lo/hi/bank; 64K is exactly one bank-byte step). DISK
; LOAD (F8 in READ EPROM/FILE VIEW) fills all three the same way:
; stream the file into ORIGINAL, then copy ORIGINAL -> WORKING and
; WORKING -> UNDO (reu_copy_region) so all three start out identical.
; ORIGINAL is never written to again after that - it's the untouched
; reference copy. WORKING is what FILE VIEW's own pager actually pages
; through, and where an E=EDIT change lands. UNDO exists as a pristine
; snapshot for a future "revert WORKING" feature - this session only
; sets it up; nothing reads it back yet. ---
REU_ORIGINAL_BANK = $00   ; REU $000000-$00FFFF
REU_WORKING_BANK  = $01   ; REU $010000-$01FFFF
REU_UNDO_BANK     = $02   ; REU $020000-$02FFFF

EPROM_PHYSICAL_BANKS = 8   ; the installed chip's real capacity (27C512/
                            ; 27SF512 = 64KB = 8 banks) - bump when a
                            ; bigger chip goes in the socket, same
                            ; constant this project's cartridge build
                            ; already uses (slots.asm) for the same
                            ; reason. Also doubles as the max chunk count
                            ; DISK LOAD will page through in FILE VIEW.

; pct_acc's per-page step, in 8.8 fixed point: 100*256/(EPROM_PHYSICAL_
; BANKS*64 pages). Exact (no rounding drift by the last page) only when
; EPROM_PHYSICAL_BANKS*64 evenly divides 25600 - true for 8 (=50 exactly)
; and 16 (=25 exactly); 32/64 would truncate here and land a page or two
; short of a clean 100% on the last page - cosmetic only, worth revisiting
; with a real divide if a bigger chip family actually goes in the socket.
PCT_STEP = 25600/(EPROM_PHYSICAL_BANKS*64)

; fl_seek_chunk's own per-page step - different from PCT_STEP above
; despite the identical-looking formula: PCT_STEP is calibrated for
; the SAVE side's full EPROM_PHYSICAL_BANKS*64-page multi-bank total,
; but fl_seek_chunk only ever reads ONE 8192-byte/64-page chunk per
; call regardless of chip size, so its own total is always exactly 64
; pages: 25600/64 = 400 - too big for the single-byte immediate add
; PCT_STEP uses (fl_update_pct does a real 16-bit add instead). Reusing
; PCT_STEP here directly (an earlier version of this did exactly that)
; meant a full chunk's worth of updates only ever added up to 64*50=
; 3200, whose high byte tops out around 12 - the percentage visibly
; stalling in the low teens instead of ever reaching 100.
PCT_STEP_LOAD = 25600/64

; fl_show_pct's fixed column for the "(NNN%)" field on row 0, to the
; right of "LOADING "<name>"" - chosen with enough margin that even a
; full 16-char name never collides: "LOADING " (8) + '"' (1) + 16 + '"'
; (1) = 26 max, so column 30 always leaves at least a few blank
; columns before the percent field starts.
FL_PCT_COL = 30

; LOAD FILE TO RAM's own directory-browse state. Capped at 64 entries
; (a real 1541 directory can hold up to 144, but 64 covers every
; practical test disk and keeps LR_NAME_TABLE's size sane) - lr_count
; is clamped to this, so a fuller disk just shows its first 64 entries
; rather than overflowing anything.
LR_MAX_FILES  = 64
LR_NAME_LEN   = 17          ; 16 chars (CBM DOS's own filename limit,
                               ; same cap read_filename/ensure_bin_ext
                               ; already enforce) + 1 null terminator -
                               ; same "walk to $00" convention as fn_buf
LR_ROWS       = 20          ; visible rows per screen page - comfortably
                               ; fits under the header/footer on a 25-row
                               ; screen
LR_MODE_LOAD   = 0          ; lr_browse_select: load the pick into
                               ; FILE_BUF and browse it (LOAD FILE TO RAM)
LR_MODE_BROWSE = 2          ; lr_browse_select: RETURN does nothing (just
                               ; redraws) - FILE / DISK TOOLS reuses this
                               ; whole picker purely to browse/DEL, not to
                               ; load or verify anything
LR_NAME_TABLE = $4000       ; LR_MAX_FILES*LR_NAME_LEN = 1088 bytes -
                               ; well clear of both this program's code
                               ; and FILE_BUF ($2000-$3FFF), which
                               ; lr_read_dir also borrows as scratch
                               ; space for the raw "$" listing itself
                               ; (a full directory is well under 8KB,
                               ; and by the time a file actually gets
                               ; loaded into FILE_BUF for real, the
                               ; directory listing that lived there has
                               ; already been fully parsed into
                               ; LR_NAME_TABLE and is no longer needed)
; lr_count/lr_cursor/lr_top themselves are plain assembled bytes (see
; below, next to LR_NAME_TABLE's data) rather than "=" zero-page
; assignments - unlike rd_addr/eprom_bank/etc. above, nothing here
; needs indirect addressing through them, and $C0-$FF specifically is
; real KERNAL zero-page workspace (GETIN/CHRIN/STATUS all live there)
; that's actively in use throughout this very routine's own KERNAL
; calls, not actually free just because BASIC itself is idle.

; Function-key PETSCII codes from the KERNAL screen editor. F1/F3/F5/F7
; ($85-$88) are already relied on elsewhere in this project (common.
; asm's F1 menu - F7 specifically is its own "Reset" hotkey, so it's
; confirmed live in this exact codebase already). F2/F4/F6/F8 ($89/$8A/
; $8B/$8C, i.e. SHIFT+F1/F3/F5/F7) are standard KERNAL codes following
; the identical pattern F4/F6 already used successfully in this program.
KEY_F1        = $85
KEY_F2        = $89
KEY_F3        = $86
KEY_F4        = $8a
KEY_F5        = $87
KEY_F6        = $8b
KEY_F7        = $88
KEY_F8        = $8c
KEY_BACKARROW = $5f   ; already verified live elsewhere in this project
                        ; (common.asm) as the "exit to main menu" key

; PETSCII color-control codes sent inline in text data via CHROUT -
; these don't produce a visible character, they just change the color
; of whatever's printed after them until the next one.
COLOR_WHITE = $05
COLOR_GREEN = $1e
COLOR_CYAN  = $9f

KERNAL_SETNAM = $ffbd
KERNAL_SETLFS = $ffba
KERNAL_OPEN   = $ffc0
KERNAL_CLOSE  = $ffc3
KERNAL_CHKIN  = $ffc6
KERNAL_CHKOUT = $ffc9
KERNAL_CHRIN  = $ffcf
KERNAL_CLRCHN = $ffcc
KERNAL_READST = $ffb7
CHROUT        = $ffd2
GETIN         = $ffe4

KERNAL_CURDEV = $ba  ; KERNAL zero page: "current device number" - kept
                       ; up to date by SETLFS/LOAD, so right after CARTLAB
                       ; itself was LOADed this already holds that same
                       ; device number - used as the default in every
                       ; filename/device prompt in this program

; ============================================================
; Main menu
; ============================================================


; --- Build-time guard: start must be the literal FIRST executable
; byte at $0810 - cartlab_boot.asm's own chain-loader jumps to
; $0810 directly (bypassing BASIC/the SYS stub entirely, so the
; splash screen stays up with no LOAD-message/READY-prompt gap -
; see that file's own header comment for the full reasoning).
; Nothing may be placed between "*=$0810" and "start" other than
; zero-page/constant "=" equates (which emit no bytes) - real code
; or data here would silently break that jump. Confirmed the hard
; way: cartlab_charset_setup/mn_poke_logo used to live right here,
; making $0810 land on cartlab_charset_setup's own entry point
; instead - jumping there would run the charset setup and then
; crash on its own RTS (no return address was ever pushed, since
; a JMP got it there, not a JSR). ---
!if * != $0810 {
        !error "start is no longer the first byte at $0810 - cartlab_boot.asm's direct jump here would land on the wrong code"
}

start
        lda     reu_checked     ; true-cold-boot-only REU presence check
        bne     mn_reu_checked    ; - see reu_checked's own comment for
        lda     #$01                ; why this can't just run every time
        sta     reu_checked           ; start does (every menu redraw)
        jsr     check_reu_present
mn_reu_checked
        jsr     cartlab_charset_setup
        lda     #$93
        jsr     CHROUT
        ldx     #$00
mn_top_border
        lda     cl_border_txt,x
        beq     mn_top_border_done
        jsr     CHROUT
        inx
        bne     mn_top_border
mn_top_border_done
        lda     #$0d
        jsr     CHROUT      ; row 0 done, cursor -> row 1
        jsr     CHROUT      ; blank row 1, cursor -> row 2
        jsr     CHROUT      ; row 2 reserved for SHACKMATE (poked below),
                               ; cursor -> row 3
        jsr     CHROUT      ; blank row 3, cursor -> row 4
        jsr     CHROUT      ; row 4 reserved for copyright (poked below),
                               ; cursor -> row 5
        jsr     CHROUT      ; blank row 5, cursor -> row 6
        jsr     mn_poke_logo
        ldx     #$00
mn_hdr
        lda     mn_hdr_msg,x
        beq     mn_wait
        jsr     CHROUT
        inx
        bne     mn_hdr
mn_wait
        jsr     GETIN
        beq     mn_wait
        cmp     #$49         ; 'I' IDENTIFY ROM / CARTRIDGE
        beq     mn_identify
        cmp     #$42         ; 'B' BANK SCANNER
        beq     mn_banktest
        cmp     #$52         ; 'R' READ CARTRIDGE / EPROM
        beq     mn_read
        cmp     #$46         ; 'F' FILE / DISK TOOLS
        beq     mn_filetools
        cmp     #$51         ; 'Q' quit to BASIC
        beq     mn_quit
        cmp     #KEY_BACKARROW
        beq     mn_quit
        jmp     mn_wait
mn_read
        jsr     do_read_eprom ; resumes wherever the last visit left off
                                 ; (live bank/offset or FILE VIEW with
                                 ; whatever was loaded) - do_read_eprom's
                                 ; own first-entry check is what seeds
                                 ; live bank $00 the very first time.
                                 ; F7=SAVE key is what reaches do_backup_
                                 ; eprom now that COPY isn't a separate
                                 ; top-level command any more (see
                                 ; rp_disk_save)
        jmp     start
mn_banktest
        jsr     do_bank_test
        jmp     start
mn_identify
        jsr     do_identify
        jmp     start
mn_filetools
        jsr     do_file_tools
        jmp     start
mn_quit
        lda     #$93         ; clear screen - otherwise BASIC's own READY
        jsr     CHROUT         ; prompt lands its cursor wherever this
                                  ; menu's own last redraw left it (right
                                  ; after "SELECT: "), instead of a clean
                                  ; screen
        lda     #$00
        sta     $c6           ; flush the keyboard buffer (NDX=0) - any
                                  ; stray queued keystroke left over from
                                  ; a sub-screen (e.g. FILE/DISK TOOLS'
                                  ; own device-number prompt, backed out
                                  ; of mid-type) would otherwise get
                                  ; silently echoed by BASIC's own input
                                  ; line the instant it regains control
        ldx     #$ff
        txs                  ; reset the stack pointer - a long CARTLAB
                                ; session (every menu option visited, each
                                ; with its own JSR/RTS nesting) has no
                                ; guarantee of staying perfectly balanced,
                                ; and this used to just RTS, trusting
                                ; whatever return address happened to be
                                ; sitting on top of the stack - confirmed
                                ; live as a real hang (blank screen,
                                ; blinking cursor, READY. never appearing)
                                ; after visiting every menu option before
                                ; quitting. Resetting here means neither
                                ; this jump nor BASIC's own subsequent
                                ; execution depends on that state at all.
        jmp     $a474        ; BASIC's own warm-start entry - prints
                                ; READY. and resumes its main loop via the
                                ; IMAIN vector ($0302); confirmed by direct
                                ; disassembly of the real BASIC ROM
                                ; (basic-901226-01.bin), not recalled from
                                ; memory - not a bare RTS back to some
                                ; assumed caller

; --- Persistent bold "SHACKMATE" header, shown on every main-menu
; redraw (not just the boot splash) - see cartlab_boot.asm's own
; header comment for why this exists as a second copy: showing the
; logo once during boot and then never again gave no real reason to
; have it. JET_CHARSET here is $3000, not cartlab_boot.asm's own
; $2800 - this program's own code/data currently ends around $24EB,
; leaving only ~800 bytes of margin at $2800 (uncomfortably close
; given how much this file has already grown past earlier estimates -
; see FILE_BUF's own comment for the exact bug that mistake caused
; once already); $3000 leaves comfortable room regardless. jet_bold_
; font/jet_copyright_glyph/jet_letters are verbatim copies of
; cartlab_boot.asm's own tables (which are themselves verbatim copies
; of bank14_content.asm's) - see that file's own comments for the
; design notes. sm_colors matches cartlab_boot.asm's own fixed palette
; choice for consistency between the two screens. ---
JET_CHARSET = $3000

; --- SEI/CLI-protected char ROM -> RAM copy + bold-font/copyright-
; glyph patch - same technique (and same hang this project already hit
; once without the SEI/CLI) as cartlab_boot.asm's own charset setup;
; see that file's own comment for the full explanation of why clearing
; CHAREN without disabling interrupts first can hang forever. Safe to
; call every time the main menu redraws (not just once) - copying/
; patching the same data again is harmless, just a few thousand
; cycles, imperceptible next to a whole screen redraw. ---
cartlab_charset_setup
        sei
        lda     $01
        pha
        and     #$fb        ; clear CHAREN - char ROM visible at $D000
        sta     $01
        lda     #$00
        sta     $fb         ; source ptr lo ($D0xx)
        sta     $fd         ; dest ptr lo
        lda     #$d0
        sta     $fc         ; source ptr hi
        lda     #>JET_CHARSET
        sta     $fe         ; dest ptr hi
        ldx     #$08        ; 8 pages = 2KB
ccs_page_loop
        ldy     #$00
ccs_byte_loop
        lda     ($fb),y
        sta     ($fd),y
        iny
        bne     ccs_byte_loop
        inc     $fc
        inc     $fe
        dex
        bne     ccs_page_loop
        pla
        sta     $01         ; CHAREN back on - I/O registers visible again
        cli

        ldx     #$00        ; patch the 16 custom bold-letter-half
ccs_patch                     ; glyphs over character codes $80-$8F
        lda     jet_bold_font,x
        sta     JET_CHARSET+$400,x
        inx
        cpx     #128
        bne     ccs_patch

        ldx     #$00        ; patch the copyright-symbol glyph over
ccs_patch_copy                ; character code $90
        lda     jet_copyright_glyph,x
        sta     JET_CHARSET+$480,x
        inx
        cpx     #8
        bne     ccs_patch_copy

        lda     #$00
        sta     $d020       ; black border/background - matches the
        sta     $d021         ; boot splash's own look
        lda     #>JET_CHARSET   ; $D018's charset field (bits 3-1) wants
        lsr                       ; (address/2048)<<1, i.e. address>>10 -
        lsr                       ; two shifts of the high byte (address
        ora     #$10               ; >>8), not three (confirmed by hand:
        sta     $d018                ; $3000>>10 = 6<<1's own bit position
                                        ; = $0C, matching (address/2048)=6
                                        ; put back into bits 3-1 - three
                                        ; shifts would give $3000's block
                                        ; NUMBER unshifted ($06, landing in
                                        ; the wrong bit position) rather
                                        ; than the block VALUE this
                                        ; register field actually needs;
                                        ; caught by hand-checking against
                                        ; cartlab_boot.asm's own hardcoded
                                        ; $1A for $2800 before trusting
                                        ; this general version for $3000
        rts

; --- Pokes SHACKMATE (row 2, cols 11-28) and the copyright line
; (row 4, cols 9-30) directly to screen+color RAM - see cartlab_boot.
; asm's own sm_loop/cp_loop comment for why direct pokes, not CHROUT,
; are required for these specific codes. ---
mn_poke_logo
        ldx     #$00
mpl_sm_loop
        lda     jet_letters,x
        sta     $045b,x     ; $0400 + 2*40+11
        lda     sm_colors,x
        sta     $d85b,x     ; $d800 + 2*40+11
        inx
        cpx     #18
        bne     mpl_sm_loop
        ldx     #$00
mpl_cp_loop
        lda     copyright_txt,x
        sta     $04a9,x     ; $0400 + 4*40+9
        lda     #$01        ; white
        sta     $d8a9,x     ; $d800 + 4*40+9
        inx
        cpx     #22
        bne     mpl_cp_loop
        rts

cl_border_txt
        !text   "========================================"
        !byte   $00

mn_hdr_msg
        !text   "         CARTRIDGE & EPROM LAB"
        !byte   $0d
        !text   "===================================="
        !byte   $0d,$0d
        !text   "(I)DENTIFY ROM / CARTRIDGE"
        !byte   $0d
        !text   "(B)ANK SCANNER"
        !byte   $0d
        !text   "(R)EAD CARTRIDGE / EPROM"
        !byte   $0d
        !text   "(F)ILE / DISK TOOLS"
        !byte   $0d,$0d
        !byte   COLOR_GREEN
        !text   "<-"
        !byte   COLOR_CYAN
        !text   "=QUIT"
        !byte   COLOR_WHITE
        !byte   $0d,$0d
        !text   "SELECT: "
        !byte   $00

; ============================================================
; A -> two uppercase hex digit chars via CHROUT
; ============================================================
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
        jmp     CHROUT

; ============================================================
; A (0-99) -> decimal digit chars via CHROUT, no leading zero. Used for
; device numbers, which people read/type in decimal (e.g. "11"), unlike
; the hex-everywhere convention the rest of this program uses for EPROM
; addresses/data.
; ============================================================
print_dec
        ldy     #$00
pd_tens
        cmp     #10
        bcc     pd_ones
        sec
        sbc     #10
        iny
        jmp     pd_tens
pd_ones
        pha
        tya
        beq     pd_skip_tens
        clc
        adc     #$30
        jsr     CHROUT
pd_skip_tens
        pla
        clc
        adc     #$30
        jmp     CHROUT

; ============================================================
; A (0-100) -> a fixed 4-character field "NNN%" (leading spaces for the
; hundreds/tens columns when not needed) via CHROUT. Used for COPY's
; save/verify progress - printing a constant width every time means the
; caller can update it in place later with four cursor-left codes ($9D)
; instead of needing to know which screen row it's on.
; ============================================================
print_pct
        cmp     #100
        beq     pp_100
        pha
        lda     #$20
        jsr     CHROUT        ; hundreds column always blank under 100
        pla
        cmp     #10
        bcs     pp_two_digit
        pha
        lda     #$20
        jsr     CHROUT        ; tens column blank for single digits
        pla
        clc
        adc     #$30
        jsr     CHROUT
        jmp     pp_pct
pp_two_digit
        jsr     print_dec
        jmp     pp_pct
pp_100
        lda     #$31
        jsr     CHROUT
        lda     #$30
        jsr     CHROUT
        lda     #$30
        jsr     CHROUT
pp_pct
        lda     #$25         ; '%'
        jmp     CHROUT

; ============================================================
; READ EPROM / FILE VIEW: hex+ASCII viewer, shared between two data
; sources selected by view_mode - live cartridge (direct $DE00 bank-
; select + indirect reads, same as always) or a file previously loaded
; into FILE_BUF by DISK LOAD. No bank_call/resident-kernel indirection
; needed either way, since this program's own code never lives in
; either source's address range.
;
; Controls: F1=(re)read  F2=write (unsupported on this hardware)
;           F3=next bank/chunk  F4=previous bank/chunk
;           F5=next page  F6=previous page
;           F7=disk save (always backs up the LIVE cartridge)
;           F8=disk load (switches into FILE VIEW)
;           <-=exit to menu
; ============================================================
do_read_eprom
        lda     rp_initialized
        bne     rp_resume
        lda     #$01
        sta     rp_initialized
        lda     #$00
        sta     eprom_bank
        sta     eprom_offset
        sta     eprom_offset+1
        sta     view_mode
rp_resume
        jmp     rp_full

; rp_full: clear-and-redraw everything - border, header label, the 16
; data rows, and the key legend. Used for first entry into the screen
; and whenever the header TEXT itself needs to change (switching
; view_mode) or the screen was completely taken over by something else
; (do_backup_eprom/do_disk_load's own prompts). Plain navigation (F1
; refresh, F3-F6, E=EDIT) uses rp_update instead, which only patches
; the bank/chunk number and the white data table in place - see its
; own comment for why that's safe now (it wasn't, briefly: with FILE
; VIEW's legend one line longer than live mode's, rp_full's own total
; row count overflowed the 25-row screen by one, forcing a scroll on
; every redraw that silently invalidated rp_update's fixed cursor
; math - fixed by trimming rp_ctrl_file_msg's blank separator row, see
; its own comment). ---
rp_show
rp_full
        lda     #$93
        jsr     CHROUT
        lda     view_mode
        bne     rp_hdr_file
        ldx     #$00
rp_hdr
        lda     rp_hdr_msg,x
        beq     rp_hdr_done
        jsr     CHROUT
        inx
        bne     rp_hdr
        jmp     rp_hdr_done
rp_hdr_file
        ldx     #$00
rp_hdr_file_loop
        lda     rp_hdr_file_msg,x
        beq     rp_hdr_done
        jsr     CHROUT
        inx
        bne     rp_hdr_file_loop
rp_hdr_done
        lda     eprom_bank
        jsr     print_hex
        lda     view_mode
        bne     rp_hdr2_file
        ldx     #$00
rp_hdr2
        lda     rp_hdr2_msg,x
        beq     rp_full_data
        jsr     CHROUT
        inx
        bne     rp_hdr2
        jmp     rp_full_data
rp_hdr2_file
        ldx     #$00
rp_hdr2_file_loop
        lda     rp_hdr2_file_msg,x
        beq     rp_full_data
        jsr     CHROUT
        inx
        bne     rp_hdr2_file_loop
rp_full_data
        jsr     rp_data
        lda     view_mode
        bne     rp_ctrl_file
        ldx     #$00
rp_ctrl
        lda     rp_ctrl_msg,x
        bne     rp_ctrl_ch
        jmp     rp_enter_wait
rp_ctrl_ch
        jsr     CHROUT
        inx
        bne     rp_ctrl
        jmp     rp_enter_wait
rp_ctrl_file
        ldx     #$00
rp_ctrl_file_loop
        lda     rp_ctrl_file_msg,x
        bne     rp_ctrl_file_ch
        jmp     rp_enter_wait
rp_ctrl_file_ch
        jsr     CHROUT
        inx
        bne     rp_ctrl_file_loop
        jmp     rp_enter_wait

; rp_data: the 16-row hex+ASCII table - called by rp_full, which
; continues on into the key legend right after.
; --- Live mode: rd_addr is the real $8000+offset address, used both to
; read (via (rd_addr),y) and to display - the two have always been the
; same value there. File mode is now REU-backed (LOAD FILE TO RAM/DISK
; LOAD stream the whole file into REU via reu_stream_file, not just one
; 8192-byte chunk into FILE_BUF - see lr_browse_select_not_reu's own
; comment) - each redraw fetches just the current 128-byte page fresh
; from REU into FILE_BUF's own start, so rd_addr for reading has to
; stay FILE_BUF-relative (0-127) regardless of where in the file this
; page actually is. rp_disp_addr is what's actually shown on screen: in
; live mode it's simply set equal to rd_addr (no behavior change from
; before); in file mode it's the true file-relative address (eprom_
; bank*8192+eprom_offset, matching VIEW/EDIT REU's own addressing), a
; separate value from the FILE_BUF-relative rd_addr driving the reads. ---
rp_data
        lda     view_mode
        bne     rp_select_file
        lda     eprom_bank
        sta     EASYFLASH_BANK
        lda     eprom_offset+1
        clc
        adc     #$80
        sta     rd_addr+1
        lda     eprom_offset
        sta     rd_addr
        lda     rd_addr
        sta     rp_disp_addr
        lda     rd_addr+1
        sta     rp_disp_addr+1
        jmp     rp_select_done
rp_select_file
        lda     eprom_bank
        jsr     reu_bank_base   ; reu_addr = eprom_bank*8192
        clc
        lda     reu_addr
        adc     eprom_offset
        sta     reu_addr
        lda     reu_addr+1
        adc     eprom_offset+1
        sta     reu_addr+1
        lda     reu_addr+2
        adc     #$00
        sta     reu_addr+2
        lda     reu_addr        ; rp_disp_addr = reu_addr (16-bit, file-
        sta     rp_disp_addr      ; relative - this program only ever
        lda     reu_addr+1        ; addresses up to EPROM_PHYSICAL_BANKS*
        sta     rp_disp_addr+1    ; 8192, well under 64K, so reu_addr's
                                     ; own bank byte is always 0 here,
                                     ; BEFORE the WORKING-region shift
                                     ; below - shown address stays file-
                                     ; relative, not a raw REU address
        lda     #REU_WORKING_BANK  ; actual REU read comes from WORKING,
        sta     reu_addr+2           ; not raw address 0 - see this
                                        ; file's own REU layout comment
        lda     #<FILE_BUF
        sta     reu_c64_addr
        lda     #>FILE_BUF
        sta     reu_c64_addr+1
        lda     #<128
        sta     reu_len
        lda     #>128
        sta     reu_len+1
        lda     #REU_CMD_FETCH
        jsr     reu_xfer
        lda     #<FILE_BUF
        sta     rd_addr
        lda     #>FILE_BUF
        sta     rd_addr+1
rp_select_done
        lda     #$00
        sta     hd_count
rp_row
        lda     #$24         ; '$' address prefix - matches this
        jsr     CHROUT        ; project's hex convention everywhere else
        lda     rp_disp_addr+1
        jsr     print_hex
        lda     rp_disp_addr
        jsr     print_hex
        lda     #$3a         ; ':'
        jsr     CHROUT
        lda     #$20
        jsr     CHROUT
        ldy     #$00         ; column within THIS row (0-7) - a LOCAL
                               ; index; rd_addr alone tracks the
                               ; absolute read position (advanced by 8
                               ; below, once per row)
rp_col
        lda     (rd_addr),y
        jsr     print_hex
        lda     #$20
        jsr     CHROUT
        iny
        cpy     #$08
        bne     rp_col
        ldy     #$00
rp_ascii
        lda     (rd_addr),y
        cmp     #$20
        bcc     rp_ascii_dot
        cmp     #$7f
        bcs     rp_ascii_dot
        jsr     CHROUT
        jmp     rp_ascii_next
rp_ascii_dot
        lda     #$2e         ; '.'
        jsr     CHROUT
rp_ascii_next
        iny
        cpy     #$08
        bne     rp_ascii
        lda     #$0d
        jsr     CHROUT
        lda     rd_addr
        clc
        adc     #$08
        sta     rd_addr
        bcc     +
        inc     rd_addr+1
+       clc
        lda     rp_disp_addr
        adc     #$08
        sta     rp_disp_addr
        bcc     +
        inc     rp_disp_addr+1
+       lda     hd_count     ; total bytes shown this page (0,8,...,128) -
        clc                   ; purely the loop-exit counter, plays no
        adc     #$08          ; role in addressing
        sta     hd_count
        cmp     #128
        bne     rp_row
        rts

; rp_update: partial redraw - only the two things that ever actually
; change from a navigation keypress: the bank/chunk number sitting
; inside the already-on-screen header line, and the 16-row white data
; table - border/label/legend (all the green/cyan chrome) stay
; untouched, avoiding both the full-screen flash rp_full causes and
; (now that rp_ctrl_file_msg no longer overflows past row 24 - see its
; own comment) the screen-scroll that used to throw this fixed HOME-
; relative positioning off by a row. Repositioning uses plain PETSCII
; cursor-movement codes (HOME/down/right), not a real screen-pointer
; recalculation - enough since both spots are at fixed, known
; positions once nothing before them is scrolling. Live and file-view
; headers happen to put the number at the same column (19), which is
; what makes reusing one fixed position safe for both. ---
rp_update
        ldx     #$00
rp_upd_pos1
        lda     rp_pos_bank_msg,x
        beq     rp_upd_bank
        jsr     CHROUT
        inx
        bne     rp_upd_pos1
rp_upd_bank
        lda     #COLOR_CYAN  ; matches the header's own "BANK $"/"CHUNK $"
        jsr     CHROUT        ; color - rp_data always leaves color state
                                ; on white afterward, so this has to be
                                ; set explicitly here every time
        lda     eprom_bank
        jsr     print_hex
        ldx     #$00
rp_upd_pos2
        lda     rp_pos_data_msg,x
        beq     rp_upd_data
        jsr     CHROUT
        inx
        bne     rp_upd_pos2
rp_upd_data
        lda     #COLOR_WHITE
        jsr     CHROUT
        jsr     rp_data
        jmp     rp_enter_wait

rp_pos_bank_msg
        !byte   $13,$11
        !fill   19,$1d
        !byte   $00
rp_pos_data_msg
        !byte   $13
        !fill   4,$11
        !byte   $00

; --- A = eprom_bank -> reu_addr = A*8192 (24-bit). Loop-based rather
; than a real multiply - eprom_bank is always small (0..EPROM_PHYSICAL_
; BANKS-1), so this runs at most a handful of times, once per redraw. ---
reu_bank_base
        lda     #$00
        sta     reu_addr
        sta     reu_addr+1
        sta     reu_addr+2
        lda     eprom_bank
        beq     rbb_done
        sta     rbb_count
rbb_loop
        clc
        lda     reu_addr+1
        adc     #$20         ; 8192's own high byte - one bank's worth
        sta     reu_addr+1
        lda     reu_addr+2
        adc     #$00
        sta     reu_addr+2
        dec     rbb_count
        bne     rbb_loop
rbb_done
        rts

rp_disp_addr !byte 0,0
rbb_count    !byte 0

rp_enter_wait
        lda     #$01
        sta     $cc          ; disable cursor blink - this screen is pure
                                ; single-key navigation, not text entry,
                                ; so a blinking cursor sitting over the
                                ; last-drawn character is just visual
                                ; noise. prompt_fn_dev re-enables it for
                                ; the screens that actually need typing.
rp_wait
        jsr     GETIN
        beq     rp_wait
        cmp     #KEY_F1
        bne     rp_w1
        jmp     rp_refresh
rp_w1   cmp     #KEY_F2
        beq     rp_wait      ; WRITE: no VPP hardware to do anything with -
                               ; silently ignored, not even a message
        cmp     #KEY_F3
        bne     rp_w3
        lda     view_mode    ; BANK+ is live-cartridge-only - a loaded
        bne     rp_wait        ; FILE isn't organized into physical
                                  ; banks the way the real EPROM chip
                                  ; is, so this is silently ignored in
                                  ; FILE VIEW, same treatment F2 gets
        jmp     rp_next_bank
rp_w3   cmp     #KEY_F4
        bne     rp_w4
        lda     view_mode    ; BANK- - see the F3 case just above
        bne     rp_wait
        jmp     rp_prev_bank
rp_w4   cmp     #KEY_F5
        bne     rp_w5
        jmp     rp_next_page
rp_w5   cmp     #KEY_F6
        bne     rp_w6
        jmp     rp_prev_page
rp_w6   cmp     #KEY_F7
        bne     rp_w7
        jmp     rp_disk_save
rp_w7   cmp     #KEY_F8
        bne     rp_w8
        jmp     rp_disk_load
rp_w8   cmp     #$45         ; 'E' edit (FILE VIEW mode only)
        bne     rp_w9
        jmp     rp_edit
rp_w9   cmp     #KEY_BACKARROW
        bne     rp_w10
        jmp     rp_quit
rp_w10  jmp     rp_wait

rp_refresh
        jmp     rp_update      ; live mode: a genuinely fresh read, since
                               ; nothing here is ever cached; file mode:
                               ; just redraws the currently loaded chunk

rp_disk_save
        jsr     do_backup_eprom
        lda     #$00
        sta     eprom_bank
        sta     eprom_offset
        sta     eprom_offset+1
        jmp     rp_full

rp_disk_load
        jsr     do_disk_load
        jmp     rp_full

; --- E: edit one byte in the currently-displayed page - FILE VIEW mode
; only (view_mode=1); silently ignored in LIVE mode (F2/WRITE's own
; convention - no VPP hardware to program the EPROM through either
; way). Prompts for a 2-hex-digit offset (0-7F) within the page, then a
; 2-hex-digit new value; updates the on-screen page cache (FILE_BUF)
; and writes the single byte back to REU's WORKING region only - never
; ORIGINAL/UNDO, so ORIGINAL still reflects exactly what was loaded,
; not what's since been edited here (a future "revert WORKING" feature
; would read it back from there).
; Folds in what used to be REU TOOLS' own "VIEW/EDIT REU" E key -
; removed as a separate screen; same edit capability, reached through
; this shared viewer instead. reu_addr gets recomputed from scratch by
; rp_data on the redraw this ends with, so there's no need to save/
; restore it around the single-byte write the way the old standalone
; screen had to. ---
rp_edit
        lda     view_mode
        bne     rp_edit_go
        jmp     rp_wait      ; LIVE mode - nothing writable, ignore
rp_edit_go
        lda     #<rp_edit_off_msg
        ldy     #>rp_edit_off_msg
        jsr     print_str
        jsr     reu_read_hex_byte
        cmp     #128
        bcs     rp_edit_bad     ; offset must be 0-7F
        sta     rp_edit_off
        lda     #<rp_edit_val_msg
        ldy     #>rp_edit_val_msg
        jsr     print_str
        jsr     reu_read_hex_byte
        ldy     rp_edit_off
        sta     FILE_BUF,y      ; update the cache so the redraw below
                                    ; shows the new value immediately
        lda     eprom_bank      ; reu_addr = WORKING_BANK's own base +
        jsr     reu_bank_base     ; eprom_bank*8192 + eprom_offset +
        clc                       ; rp_edit_off - i.e. this exact byte's
        lda     reu_addr          ; real REU address
        adc     eprom_offset
        sta     reu_addr
        lda     reu_addr+1
        adc     eprom_offset+1
        sta     reu_addr+1
        lda     reu_addr+2
        adc     #$00
        sta     reu_addr+2
        clc
        lda     reu_addr
        adc     rp_edit_off
        sta     reu_addr
        lda     reu_addr+1
        adc     #$00
        sta     reu_addr+1
        lda     reu_addr+2
        adc     #$00
        sta     reu_addr+2
        lda     #REU_WORKING_BANK
        sta     reu_addr+2
        lda     rp_edit_off     ; reu_c64_addr = FILE_BUF + rp_edit_off -
        sta     reu_c64_addr      ; FILE_BUF's own low byte is 0, so the
        lda     #>FILE_BUF        ; offset (0-127) can't carry into the
        sta     reu_c64_addr+1    ; high byte
        lda     #$01
        sta     reu_len
        lda     #$00
        sta     reu_len+1
        lda     #REU_CMD_STORE
        jsr     reu_xfer
rp_edit_bad
        jmp     rp_update       ; redraw to show the edited byte

; --- PAGE/BANK navigation - identical for both view modes now that
; FILE VIEW is REU-backed: rp_data's own file-mode branch fetches
; whatever 128-byte page eprom_bank/eprom_offset currently point at
; fresh from REU on every redraw, so there's no "loaded chunk" left to
; run off the end of and no disk access mid-navigation - paging or
; changing banks is just arithmetic on eprom_bank/eprom_offset either
; way. This used to be two separate code paths (live vs a transparent
; disk-reload-on-chunk-boundary one for FILE VIEW, with BANK+/BANK-
; disabled there entirely) before REU TOOLS added a real flat address
; space to view file data through - see lr_browse_select_not_reu's own
; comment for where the file now actually gets loaded. ---
rp_next_page
        lda     eprom_offset
        clc
        adc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #$00
        sta     eprom_offset+1
        lda     eprom_offset+1
        cmp     #>8192
        bcc     rp_np_update  ; BCS/BCC can't reach rp_next_bank's own
        jmp     rp_next_bank    ; distance directly, hence the extra hop
rp_np_update
        jmp     rp_update

rp_prev_page
        lda     eprom_offset
        ora     eprom_offset+1
        bne     rp_pp_sub    ; not at the first page of this bank -
                               ; just subtract 128
        lda     eprom_bank   ; at the first page - move to the previous
        bne     rp_pp_bank_ok ; bank's last page instead
        lda     #EPROM_PHYSICAL_BANKS
rp_pp_bank_ok
        sec
        sbc     #1
        sta     eprom_bank
        lda     #<(8192-128)
        sta     eprom_offset
        lda     #>(8192-128)
        sta     eprom_offset+1
        jmp     rp_update
rp_pp_sub
        lda     eprom_offset
        sec
        sbc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        sbc     #$00
        sta     eprom_offset+1
        jmp     rp_update

rp_next_bank
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
        inc     eprom_bank
        lda     eprom_bank
        cmp     #EPROM_PHYSICAL_BANKS
        bcs     rp_nb_wrap
        jmp     rp_update
rp_nb_wrap
        lda     #$00
        sta     eprom_bank
        jmp     rp_update

rp_prev_bank
        lda     eprom_bank
        bne     rp_pb_ok
        lda     #EPROM_PHYSICAL_BANKS
rp_pb_ok
        sec
        sbc     #1
        sta     eprom_bank
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
        jmp     rp_update

rp_quit
        rts

rp_hdr_msg
        !byte   COLOR_WHITE
        !text   "===================================="
        !byte   $0d
        !byte   COLOR_GREEN
        !text   "EPROM READ"
        !byte   COLOR_CYAN
        !text   " - BANK $"
        !byte   $00
rp_hdr2_msg
        !text   " ($8000-$9FFF)"
        !byte   $0d
        !byte   COLOR_WHITE
        !text   "===================================="
        !byte   $0d,$0d,$00
rp_hdr_file_msg
        !byte   COLOR_WHITE
        !text   "===================================="
        !byte   $0d
        !byte   COLOR_GREEN
        !text   "FILE VIEW"
        !byte   COLOR_CYAN
        !text   " - CHUNK $"
        !byte   $00
rp_hdr2_file_msg
        !text   " (FROM DISK)"
        !byte   $0d
        !byte   COLOR_WHITE
        !text   "===================================="
        !byte   $0d,$0d,$00

; Abbreviated to a 4-column x 2-row grid (10 visible chars per column,
; 4x10=40) plus a short third line for back-arrow, centered, with a
; blank line above separating it from the data table - color-control
; bytes ($1E/$9F) don't consume a column position themselves, only the
; actual text after them does, so the padding spaces account for
; visible width only. F2 has no description since WRITE is silently
; ignored - see rp_w1 above.
rp_ctrl_msg
        !byte   $0d
        !byte   COLOR_GREEN
        !text   "F1"
        !byte   COLOR_CYAN
        !text   "=READ   "
        !byte   COLOR_GREEN
        !text   "F2"
        !text   "        "
        !byte   COLOR_GREEN
        !text   "F3"
        !byte   COLOR_CYAN
        !text   "=BANK+  "
        !byte   COLOR_GREEN
        !text   "F4"
        !byte   COLOR_CYAN
        !text   "=BANK-"
        !byte   $0d
        !byte   COLOR_GREEN
        !text   "F5"
        !byte   COLOR_CYAN
        !text   "=PAGE+  "
        !byte   COLOR_GREEN
        !text   "F6"
        !byte   COLOR_CYAN
        !text   "=PAGE-  "
        !byte   COLOR_GREEN
        !text   "F7"
        !byte   COLOR_CYAN
        !text   "=SAVE   "
        !byte   COLOR_GREEN
        !text   "F8"
        !byte   COLOR_CYAN
        !text   "=LOAD"
        !byte   $0d
        !fill   16,$20        ; center "<-=BACK" (7 chars) in 40 columns
        !byte   COLOR_GREEN
        !text   "<-"
        !byte   COLOR_CYAN
        !text   "=BACK"
        !byte   $0d
        !byte   COLOR_WHITE
        !byte   $00

; --- FILE VIEW's own legend - identical except F3/F4 are blanked out
; (same "just the label, no description" treatment F2 already gets),
; since BANK+/BANK- are disabled in this mode - see rp_next_bank's own
; comment for why. No leading blank-row $0d here unlike rp_ctrl_msg -
; this legend has one extra line (E=EDIT) that live mode doesn't, and
; that's exactly enough to push the total past the screen's 25 rows if
; a blank separator row is kept too: confirmed live, the resulting
; overflow (printing past row 24) forces the whole screen to scroll up
; one row on every single redraw, permanently losing the top border
; off-screen. ---
rp_ctrl_file_msg
        !byte   COLOR_GREEN
        !text   "F1"
        !byte   COLOR_CYAN
        !text   "=READ   "
        !byte   COLOR_GREEN
        !text   "F2"
        !text   "        "
        !byte   COLOR_GREEN
        !text   "F3"
        !text   "        "
        !byte   COLOR_GREEN
        !text   "F4"
        !text   "      "
        !byte   $0d
        !byte   COLOR_GREEN
        !text   "F5"
        !byte   COLOR_CYAN
        !text   "=PAGE+  "
        !byte   COLOR_GREEN
        !text   "F6"
        !byte   COLOR_CYAN
        !text   "=PAGE-  "
        !byte   COLOR_GREEN
        !text   "F7"
        !byte   COLOR_CYAN
        !text   "=SAVE   "
        !byte   COLOR_GREEN
        !text   "F8"
        !byte   COLOR_CYAN
        !text   "=LOAD"
        !byte   $0d
        !byte   COLOR_GREEN
        !text   "E"
        !byte   COLOR_CYAN
        !text   "=EDIT"
        !byte   $0d
        !fill   16,$20        ; center "<-=BACK" (7 chars) in 40 columns
        !byte   COLOR_GREEN
        !text   "<-"
        !byte   COLOR_CYAN
        !text   "=BACK"
        !byte   $0d
        !byte   COLOR_WHITE
        !byte   $00

rp_edit_off !byte 0
rp_edit_off_msg
        !text   "BYTE OFFSET (00-7F): "
        !byte   $00
rp_edit_val_msg
        !byte   $0d
        !text   "NEW VALUE (00-FF): "
        !byte   $00

; ============================================================
; A -> A*10, via 10 additions (X clobbered as the loop counter). Only
; ever called with a single decimal digit's worth of existing value
; (device numbers realistically top out around 30), so plain repeated
; addition is simpler here than a real shift-based multiply.
; ============================================================
times10
        sta     bt_same_flag  ; do_bank_test's own scratch, safely free -
                                ; BACKUP EPROM and BANK LATCH TEST never
                                ; run at the same time
        lda     #$00
        ldx     #10
t10_loop
        clc
        adc     bt_same_flag
        dex
        bne     t10_loop
        rts

; ============================================================
; Reads a filename (up to 16 chars, matching CBM DOS's own limit) from
; the keyboard into fn_buf, null-terminated, with fn_len set to the
; typed length (0 if RETURN was pressed immediately - callers treat
; that as "use the default name"). DEL/backspace is supported since
; typos in a 16-char field are likely; echoing the raw DEL byte back
; via CHROUT is enough since the KERNAL screen editor already treats
; $14 as destructive backspace on output, not just input.
;
; The running buffer index lives in fn_len (zero page), not X - the
; KERNAL's GETIN uses X internally while shifting its own keyboard
; buffer and does not guarantee preserving it, so an index kept in X
; across repeated "jsr GETIN" calls silently loses track of where it
; is (confirmed live: characters were landing 2 slots into fn_buf
; instead of at the start). X is only ever loaded from fn_len
; immediately before each indexed access, never trusted to still hold
; the right value after a GETIN call.
; ============================================================
read_filename
        lda     #$00
        sta     fn_len
rf_loop
        jsr     GETIN
        beq     rf_loop
        cmp     #$0d
        beq     rf_done
        cmp     #$14
        beq     rf_del
        cmp     #$20
        bcc     rf_loop       ; ignore other control chars
        cmp     #$5b
        bcs     rf_loop       ; keep to space/digits/upper-punct - avoids
                                ; the C64 charset's graphics-glyph range
        ldx     fn_len
        cpx     #16
        bcs     rf_loop       ; buffer full - ignore further typing
        sta     fn_buf,x
        inx
        stx     fn_len
        jsr     CHROUT
        jmp     rf_loop
rf_del
        lda     fn_len
        beq     rf_loop       ; nothing to delete
        dec     fn_len
        lda     #$14
        jsr     CHROUT
        jmp     rf_loop
rf_done
        ldx     fn_len
        lda     #$00
        sta     fn_buf,x
        lda     #$0d
        jmp     CHROUT

; ============================================================
; Reads a 1-2 digit decimal device number from the keyboard into
; dv_num, accumulating digit-by-digit (dv_num = dv_num*10 + digit) the
; same way a person reads a number left to right. hd_count's low byte
; (unused until the caller's own real work starts) is reused as the
; digit-count scratch. RETURN with no digits typed at all leaves dv_num
; untouched, so the caller can pre-load it with the KERNAL's current-
; device default beforehand.
; ============================================================
read_device
        lda     #$00
        sta     hd_count
rd_loop
        jsr     GETIN
        beq     rd_loop
        cmp     #$0d
        beq     rd_done
        cmp     #$30
        bcc     rd_loop
        cmp     #$3a
        bcs     rd_loop
        pha
        lda     hd_count
        cmp     #2
        bcs     rd_full
        tax                     ; a fresh hd_count==0 test is needed here
        cpx     #0              ; (not "bne" off the cmp #2 above - that
        bne     rd_accumulate   ; leaves Z set from hd_count-2, which is
                                  ; only ever true when hd_count=2, already
                                  ; branched away via bcs - reusing it made
                                  ; the "==0" and "==1" cases indistinguish-
                                  ; able and this whole fix a no-op, caught
                                  ; live: still showed 89 after this "fix")
        lda     #$00            ; hd_count=0 (1st digit typed) - clear
        sta     dv_num          ; dv_num first. It was pre-loaded with
                                  ; the caller's default purely for the
                                  ; "RETURN with nothing typed" case
                                  ; (see this routine's own comment); once
                                  ; real typing starts that preload must
                                  ; not bleed into the accumulated value -
                                  ; confirmed live as the cause of typing
                                  ; "9" alone (device default 8 preloaded)
                                  ; producing 89, i.e. 8*10+9
rd_accumulate
        inc     hd_count
        lda     dv_num
        jsr     times10
        sta     dv_num
        pla
        pha
        sec
        sbc     #$30
        clc
        adc     dv_num
        sta     dv_num
        pla
        jsr     CHROUT
        jmp     rd_loop
rd_full
        pla
        jmp     rd_loop
rd_done
        lda     #$0d
        jmp     CHROUT

; ============================================================
; Prompts for a filename (RETURN defaults to EPROM.BIN) and a device
; number (RETURN defaults to the KERNAL's current device), leaving the
; choice in fn_buf/fn_len/dv_num - shared by BACKUP EPROM and DISK
; LOAD so the prompt text and defaulting logic only exist once.
; ============================================================
prompt_fn_dev
        lda     #$00
        sta     $cc          ; re-enable cursor blink - READ EPROM turns
                               ; it off (rp_enter_wait) since that screen
                               ; is pure navigation, but typing a
                               ; filename/device number here needs a
                               ; visible insertion point
        ldx     #$00
pfd_fn_loop
        lda     be_fn_prompt_txt,x
        beq     pfd_read_fn
        jsr     CHROUT
        inx
        bne     pfd_fn_loop
pfd_read_fn
        jsr     read_filename
        lda     fn_len
        bne     pfd_check_ext   ; user typed a name - make sure it has
                                   ; an extension before moving on
        ldx     #$00
pfd_fn_default
        lda     be_default_name,x
        sta     fn_buf,x
        beq     pfd_fn_default_done
        inx
        jmp     pfd_fn_default
pfd_fn_default_done
        stx     fn_len
        jmp     pfd_dev_prompt
pfd_check_ext
        jsr     ensure_bin_ext
pfd_dev_prompt
        ldx     #$00
pfd_dev_loop
        lda     be_dev_prompt_txt,x
        beq     pfd_dev_show_default
        jsr     CHROUT
        inx
        bne     pfd_dev_loop
pfd_dev_show_default
        lda     KERNAL_CURDEV
        jsr     print_dec
        lda     #$29         ; ')'
        jsr     CHROUT
        lda     #$20
        jsr     CHROUT
        lda     KERNAL_CURDEV
        sta     dv_num       ; pre-load the default; read_device leaves
                               ; it untouched if RETURN is pressed with
                               ; no digits typed
        jmp     read_device

; --- If the just-typed filename (fn_buf/fn_len) has no "." extension,
; append ".BIN" - matches BACKUP EPROM's own default name (EPROM.BIN)
; and means DISK LOAD can find a file saved this way again without the
; user having to type the extension either. Only when there's no "."
; already (an explicit extension the user typed is always left alone)
; and only when there's room: CBM DOS's own filename limit is 16 chars
; total (already enforced by read_filename), so a typed name longer
; than 12 chars wouldn't leave room for ".BIN" - left as-is rather than
; silently truncating what the user typed. ---
ensure_bin_ext
        ldx     #$00
ebe_scan
        cpx     fn_len
        beq     ebe_no_dot      ; walked the whole typed name, no '.' found
        lda     fn_buf,x
        cmp     #$2e            ; '.'
        beq     ebe_done        ; already has an extension - leave it
        inx
        jmp     ebe_scan
ebe_no_dot
        lda     fn_len
        cmp     #13
        bcs     ebe_done        ; no room within the 16-char limit
        ldx     fn_len
        ldy     #$00
ebe_suffix_loop
        lda     ebe_bin_ext,y
        sta     fn_buf,x
        inx
        iny
        cpy     #4
        bne     ebe_suffix_loop
        stx     fn_len
        lda     #$00
        sta     fn_buf,x        ; null-terminate - be_confirm_name_loop
                                    ; below walks fn_buf by null
                                    ; terminator, not fn_len
ebe_done
        rts
ebe_bin_ext !text ".BIN"

; ============================================================
; BACKUP EPROM ("COPY" on the main menu): reads every physical bank
; from the LIVE cartridge and streams the raw bytes to disk via KERNAL
; OPEN/CHKOUT/CHROUT - same approach as the cartridge build's own
; feat_backup_eprom, minus the bank_call indirection (not needed here
; since none of this code's own bytes live in the window being
; switched). Always reads the real cartridge via $DE00, regardless of
; whether the READ screen currently has FILE VIEW active - re-saving a
; file you just loaded back to disk isn't a meaningful action, so this
; never reads from FILE_BUF.
; ============================================================
do_backup_eprom
        lda     #$93
        jsr     CHROUT
        ldx     #$00
be_hdr
        lda     be_hdr_msg,x
        beq     be_prompt
        jsr     CHROUT
        inx
        bne     be_hdr
be_prompt
        jsr     prompt_fn_dev
be_confirm
        ldx     #$00
be_confirm_msg
        lda     be_confirm_txt,x
        beq     be_confirm_name
        jsr     CHROUT
        inx
        bne     be_confirm_msg
be_confirm_name
        ldx     #$00
be_confirm_name_loop
        lda     fn_buf,x
        beq     be_confirm_dev
        jsr     CHROUT
        inx
        bne     be_confirm_name_loop
be_confirm_dev
        ldx     #$00
be_confirm_dev_msg
        lda     be_confirm_dev_txt,x
        beq     be_confirm_dev_num
        jsr     CHROUT
        inx
        bne     be_confirm_dev_msg
be_confirm_dev_num
        lda     dv_num
        jsr     print_dec
        ldx     #$00
be_confirm_dev_end
        lda     be_confirm_dev_end_txt,x
        beq     be_open
        jsr     CHROUT
        inx
        bne     be_confirm_dev_end
; ",S,W" has to be appended for this OPEN (raw KERNAL_OPEN/CHKOUT, not
; the KERNAL_SAVE vector) - CBM DOS defaults a plain OPEN to READ mode
; when no mode letter is given, so without ",W" opening a not-yet-
; existing EPROM.BIN fails at the DOS level (FILE NOT FOUND) even
; though KERNAL_OPEN's own carry flag doesn't catch it - CHKOUT still
; "succeeds" and every CHROUT after it silently goes nowhere. Built
; into the separate be_wname buffer, not appended onto fn_buf itself -
; keeps fn_buf holding the clean, unsuffixed name the user actually
; typed.
be_open
        ldx     #$00
be_open_copy
        cpx     fn_len
        beq     be_open_suffix
        lda     fn_buf,x
        sta     be_wname,x
        inx
        bne     be_open_copy
be_open_suffix
        ldy     #$00
be_open_suffix_loop
        lda     be_write_suffix,y
        sta     be_wname,x
        inx
        iny
        cpy     #4
        bne     be_open_suffix_loop
        stx     be_wname_len
        lda     be_wname_len
        ldx     #<be_wname
        ldy     #>be_wname
        jsr     KERNAL_SETNAM
        lda     #2
        ldx     dv_num
        ldy     #1
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        bcc     be_open_ok
        jmp     be_error_close   ; OPEN can fail (e.g. bad device) while
                                    ; still leaving logical file #2 marked
                                    ; open in the KERNAL's own tables -
                                    ; without closing it here, the NEXT
                                    ; OPEN of file #2 fails too, even to a
                                    ; device that IS present (confirmed
                                    ; live)
; be_open printed the confirm line up through the opening "(" already
; (be_confirm_dev_end_txt) - this fills in the initial "  0%)" while
; CHROUT is STILL on the SCREEN (before the CHKOUT below redirects it
; to the file). Getting this order right matters: the original version
; of this routine did the initial percent print AFTER CHKOUT, so it
; silently landed inside EPROM.BIN itself instead of on screen -
; confirmed live as the reason no percentage, not even "0%", ever
; appeared while a save was running.
be_open_ok
        lda     #$00
        sta     pct_acc
        sta     pct_acc+1
        lda     #$00
        jsr     print_pct
        lda     #$29         ; ')'
        jsr     CHROUT
        ldx     #2
        jsr     KERNAL_CHKOUT
        bcc     be_write_ok
        jmp     be_error_close
be_write_ok
        lda     #$00
        sta     eprom_bank
be_bank_loop
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
be_page_loop
        lda     eprom_bank
        sta     EASYFLASH_BANK
        lda     eprom_offset+1
        clc
        adc     #$80
        sta     rd_addr+1
        lda     eprom_offset
        sta     rd_addr
        ldy     #$00
be_byte_loop
        lda     (rd_addr),y
        jsr     CHROUT
        iny
        bpl     be_byte_loop

        lda     eprom_offset
        clc
        adc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #$00
        sta     eprom_offset+1

        jsr     be_update_pct  ; every 128-byte PAGE, not just once per
                                  ; 8192-byte bank - true 1541 drive
                                  ; emulation can take 20-30 real seconds
                                  ; per bank, and updating only at bank
                                  ; boundaries left the screen static
                                  ; that whole time, easily read as a
                                  ; hang. Leaves CHROUT pointed at the
                                  ; SCREEN on return; re-CHKOUT to the
                                  ; file below only if there's more to
                                  ; write, same as the bank-boundary
                                  ; logic this replaced.
        lda     eprom_offset+1
        cmp     #>8192
        bcs     be_bank_done   ; whole 8K bank streamed
        ldx     #2
        jsr     KERNAL_CHKOUT
        jmp     be_page_loop
be_bank_done
        inc     eprom_bank
        lda     eprom_bank
        cmp     #EPROM_PHYSICAL_BANKS
        bcc     be_more_banks
        jmp     be_bank_loop_done  ; last bank done - CHROUT is already
                                      ; back on the screen (be_update_pct
                                      ; left it there), nothing more to
                                      ; redirect
be_more_banks
        ldx     #2
        jsr     KERNAL_CHKOUT
        jmp     be_bank_loop
be_bank_loop_done
        lda     #2
        jsr     KERNAL_CLOSE
        lda     #$0d
        jsr     CHROUT
        lda     #$0d
        jsr     CHROUT

; --- Bumps pct_acc by PCT_STEP and reprints it in place as "NNN%)" -
; the trailing ")" is part of the reprinted field (not left over from
; be_open_ok's own one-time print) so 5 cursor-lefts, not 4, always
; lines back up to right before where the percent digits start; see
; pct_acc's own comment (zero page block above) for why its high byte
; alone is the right value to print. Called from the SAVE loop above,
; where it has to CLRCHN first since CHKOUT has CHROUT pointed at the
; file at that point. ---
be_update_pct
        jsr     KERNAL_CLRCHN
        jmp     pct_bump_and_show

; --- Same bump-and-reprint as be_update_pct, minus the CLRCHN - for
; callers where CHROUT was never redirected away from the screen to
; begin with (no CHKOUT ever issued), so there's nothing to clear back.
; CLRCHN's real, KERNAL-documented job is resetting the DEFAULT input
; channel back to the keyboard - calling it between CHRIN calls that
; still expect CHKIN's own file redirection to be live is a real risk
; (silently reading from the keyboard instead of the file, i.e.
; hanging with no visible error), not a proven-safe shortcut. reu_
; stream_file's own read loop (LOAD FILE TO RAM) uses this instead of
; be_update_pct to avoid relying on that unverified assumption. ---
reu_update_pct
pct_bump_and_show
        clc
        lda     pct_acc
        adc     #PCT_STEP
        sta     pct_acc
        lda     pct_acc+1
        adc     #$00
        sta     pct_acc+1
        lda     #$9d
        jsr     CHROUT
        lda     #$9d
        jsr     CHROUT
        lda     #$9d
        jsr     CHROUT
        lda     #$9d
        jsr     CHROUT
        lda     #$9d
        jsr     CHROUT
        lda     pct_acc+1
        jsr     print_pct
        lda     #$29         ; ')'
        jsr     CHROUT
        rts

; ============================================================
; FILE / DISK TOOLS ('F' on the main menu): the same directory-picker
; screen DISK LOAD already shares (lr_dev_prompt onward),
; just in LR_MODE_BROWSE - RETURN is a no-op in that mode (see lr_
; browse_select's own comment), so this screen is purely for browsing
; the disk and DEL-ing junk files, without picking one to load or
; verify. jmp (not jsr) into lr_dev_prompt for the same reason do_
; verify_file does - every real exit from that whole picker flow is a
; plain rts, so it lands correctly on whoever called do_file_tools
; regardless of which path was taken to get there. ---
do_file_tools
        lda     #LR_MODE_BROWSE
        sta     lr_mode
        lda     #$93
        jsr     CHROUT
        ldx     #$00
ftl_hdr
        lda     ftl_hdr_msg,x
        beq     ftl_hdr_done
        jsr     CHROUT
        inx
        bne     ftl_hdr
ftl_hdr_done
        jmp     lr_dev_prompt

ftl_hdr_msg
        !text   "FILE / DISK TOOLS"
        !byte   $0d,$0d,$00

be_error
        ldx     #$00
be_err_loop
        lda     be_err_msg,x
        beq     be_err_wait
        jsr     CHROUT
        inx
        bne     be_err_loop
be_err_wait
        jsr     GETIN
        beq     be_err_wait
        rts
be_error_close
        lda     #2
        jsr     KERNAL_CLOSE
        jmp     be_error

be_hdr_msg
        !text   "COPY CARTRIDGE / EPROM"
        !byte   $0d,$0d,$00
be_fn_prompt_txt
        !text   "FILENAME (RETURN FOR EPROM.BIN): "
        !byte   $00
be_dev_prompt_txt
        !text   "DEVICE (RETURN FOR #"
        !byte   $00
; Confirm line is built in three pieces around the filename/device
; number, same as before, but now ends in an open "(" instead of ")..."
; - be_open_ok (above) fills in the live "NNN%)" itself, and
; be_update_pct keeps it current in place for the rest of the save.
; One combined "SAVING <name>,<dev> (NNN%)" line instead of a separate
; (and previously broken - see be_open_ok's own comment) status line
; below it.
be_confirm_txt
        !byte   $0d,$0d
        !text   "SAVING "
        !byte   $00
be_confirm_dev_txt
        !text   ","
        !byte   $00
be_confirm_dev_end_txt
        !text   " ("
        !byte   $00
be_err_msg
        !text   "?SAVE ERROR - PRESS ANY KEY"
        !byte   $0d,$00
be_default_name
        !text   "EPROM.BIN"
        !byte   $00
fn_buf  !fill   17,0

; be_open's write-mode filename, built fresh each COPY from fn_buf plus
; ",S,W" - kept separate from fn_buf itself so be_verify's later plain-
; READ reopen still uses the clean typed name (see be_open's own
; comment for why a leftover ",W" there would break it). 16-char name
; (read_filename's own limit) + 4-char suffix, no null terminator
; needed since SETNAM always gets an explicit length.
be_write_suffix !text ",S,W"
be_wname        !fill 20,0
be_wname_len    !byte 0

; ============================================================
; DISK LOAD (F8 in the READ screen): prompts for a device, then shows
; that device's directory as a pickable list (same lr_dev_prompt/lr_
; browse flow LOAD FILE TO RAM uses from the main menu), loads the
; chosen file's first 8192-byte chunk into FILE_BUF, and switches the
; READ screen into FILE VIEW mode so the same hex+ASCII viewer displays
; it. Previously used prompt_fn_dev (BACKUP EPROM's own "type a
; filename to SAVE" prompt) here by mistake - that's for writing a new
; file, not picking an existing one to load, and gave no way to browse
; what's actually on the disk. lr_browse_select_go's own LOAD branch
; (fl_seek_chunk + view_mode=1 + jmp rp_show) already does exactly what
; this screen needs, so this just reuses LR_MODE_LOAD wholesale rather
; than duplicating that logic a second time. ---
; ============================================================
do_disk_load
        jsr     reu_gate
        bcs     ddl_abort
        lda     #LR_MODE_LOAD
        sta     lr_mode
        lda     #$93
        jsr     CHROUT
        ldx     #$00
dl_hdr
        lda     dl_hdr_msg,x
        beq     dl_hdr_done
        jsr     CHROUT
        inx
        bne     dl_hdr
dl_hdr_done
        jmp     lr_dev_prompt
ddl_abort
        rts

dl_hdr_msg
        !text   "DISK LOAD"
        !byte   $0d,$0d,$00

; ============================================================
; Loads one 8192-byte chunk from the file already named in fn_buf/
; fn_len (on device dv_num) into FILE_BUF - specifically chunk number
; eprom_bank (0-based), by reopening the file from scratch and reading-
; and-discarding every earlier chunk first. CBM DOS sequential files
; have no random-access seek, so this is the only correct way to reach
; an arbitrary chunk - slower for high chunk numbers, but always
; correct, and simple enough to trust. Running out of bytes early
; (short file / past EOF) just leaves the rest of FILE_BUF holding
; whatever was already there, the same way an under-sized EPROM dump
; would show blank past its real content.
; ============================================================
; --- Shows "LOADING "<name>"" on row 0 and "(NNN%)" on row 1 while the
; target chunk is read. Row 1 is reprinted via ABSOLUTE positioning
; (HOME + one CRSR-DOWN) rather than
; relative cursor-left counting - an earlier version of this tried
; cursor-left and got the math right in isolation, but with a variable-
; length filename on the SAME line, one wrong assumption anywhere in
; that chain compounds every single update; putting the percent field
; on its own fixed row sidesteps the whole class of bug instead of
; chasing it. CHRIN/CHKIN only redirect INPUT, never CHROUT, so (same
; reasoning be_verify's own comment already covers) these prints go
; straight to the screen throughout, no CLRCHN dance needed the way the
; SAVE side needs one. Percentage tracks fl_read_page's 64 pages - one
; full 8192-byte chunk, NOT EPROM_PHYSICAL_BANKS*64 (that's the SAVE
; side's own multi-bank total; this only ever reads a single chunk per
; call) - see PCT_STEP_LOAD's own comment. The skip phase for
; eprom_bank>0 (discarding earlier chunks first, CBM DOS sequential
; files having no random-access seek) has no size to report progress
; against, so it stays silent at 0% until the real read starts; that's
; also the uncommon case here (LOAD FILE TO RAM and DISK LOAD both
; always start at chunk 0 - only F3/F4 paging past chunk 0 within FILE
; VIEW ever triggers it). Clears the screen on entry; every caller
; already does its own full redraw (rp_full) right after fl_seek_chunk
; returns, which naturally overwrites this popup - no cleanup needed
; here. ---
fl_seek_chunk
        lda     #$93
        jsr     CHROUT
        ldx     #$00
fl_load_hdr
        lda     fl_loading_txt,x
        beq     fl_load_name
        jsr     CHROUT
        inx
        bne     fl_load_hdr
fl_load_name
        lda     #$22         ; '"'
        jsr     CHROUT
        ldx     #$00
fl_load_name_loop
        lda     fn_buf,x
        beq     fl_load_name_done
        jsr     CHROUT
        inx
        bne     fl_load_name_loop
fl_load_name_done
        lda     #$22         ; '"'
        jsr     CHROUT
        lda     #$00
        sta     pct_acc
        sta     pct_acc+1
        jsr     fl_show_pct      ; row 1: initial "(  0%)"

        lda     fn_len
        ldx     #<fn_buf
        ldy     #>fn_buf
        jsr     KERNAL_SETNAM
        lda     #3
        ldx     dv_num
        ldy     #0
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        bcc     fl_open_ok
        jmp     fl_error_close   ; OPEN can fail while still leaving
                                    ; logical file #3 marked open in the
                                    ; KERNAL's own tables - without
                                    ; closing it here, the NEXT OPEN of
                                    ; file #3 fails too (same real-
                                    ; hardware quirk be_open_ok/lr_rd_
                                    ; open_ok guard against)
fl_open_ok
        ldx     #3
        jsr     KERNAL_CHKIN
        bcc     fl_chkin_ok
        jmp     fl_error_close
fl_chkin_ok
        lda     eprom_bank
        sta     hd_count        ; chunks left to skip before the real read
        beq     fl_do_read
fl_skip_loop
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
fl_skip_page
        ldy     #$00
fl_skip_byte
        jsr     KERNAL_CHRIN
        jsr     KERNAL_READST
        bne     fl_done_close    ; EOF mid-skip - nothing further to load
        iny
        bpl     fl_skip_byte
        lda     eprom_offset
        clc
        adc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #$00
        sta     eprom_offset+1
        cmp     #>8192
        bcc     fl_skip_page
        dec     hd_count
        bne     fl_skip_loop
fl_do_read
        lda     #$00
        sta     eprom_offset
        sta     eprom_offset+1
fl_read_page
        lda     eprom_offset+1
        clc
        adc     #>FILE_BUF
        sta     rd_addr+1
        lda     eprom_offset
        sta     rd_addr
        ldy     #$00
fl_read_byte
        jsr     KERNAL_CHRIN
        sta     (rd_addr),y
        jsr     KERNAL_READST
        bne     fl_done_close    ; EOF - stop, leaving the rest of this
                                    ; chunk as whatever FILE_BUF already
                                    ; held from a previous load
        iny
        bpl     fl_read_byte
        jsr     fl_update_pct    ; every page - see this routine's own
                                    ; header comment for why no CLRCHN/
                                    ; CHKOUT dance is needed here, unlike
                                    ; the SAVE side's identical-looking
                                    ; be_update_pct
        jsr     GETIN            ; non-blocking - returns 0 immediately
                                    ; if nothing's queued, so this never
                                    ; slows a normal load down. Without
                                    ; this, there was no way to escape a
                                    ; slow/stuck read at all: the read
                                    ; loop never checked for a keypress,
                                    ; so a chunk that's taking a long
                                    ; time (or genuinely hung) left the
                                    ; user stuck on a static "LOADING"
                                    ; screen with the F-key legend gone
                                    ; and no way back - confirmed live.
        cmp     #KEY_BACKARROW
        beq     fl_done_close    ; user bailed - stop here, same as EOF
        lda     eprom_offset
        clc
        adc     #128
        sta     eprom_offset
        lda     eprom_offset+1
        adc     #$00
        sta     eprom_offset+1
        cmp     #>8192
        bcc     fl_read_page
fl_done_close
        jsr     KERNAL_CLRCHN
        lda     #3
        jsr     KERNAL_CLOSE
        rts
fl_error_close
        lda     #3
        jsr     KERNAL_CLOSE
        rts

; --- Bumps pct_acc by PCT_STEP_LOAD (16-bit add - see that constant's
; own comment for why this one doesn't fit in a single-byte step the
; way the SAVE side's PCT_STEP does) and reprints row 1 in place. ---
fl_update_pct
        clc
        lda     pct_acc
        adc     #<PCT_STEP_LOAD
        sta     pct_acc
        lda     pct_acc+1
        adc     #>PCT_STEP_LOAD
        sta     pct_acc+1
        jsr     fl_show_pct
        rts

; --- Repositions to row 0/column FL_PCT_COL (HOME + FL_PCT_COL x CRSR
; RIGHT - absolute, not relative to wherever the filename happened to
; end, so it's independent of the name's length) and prints "(NNN%)"
; from pct_acc's high byte - 6 characters, always the same width
; regardless of the value, so nothing before or after it on the row
; can ever conflict with this. ---
fl_show_pct
        lda     #$13         ; HOME
        jsr     CHROUT
        ldx     #FL_PCT_COL
fl_show_pct_right
        lda     #$1d         ; CRSR RIGHT
        jsr     CHROUT
        dex
        bne     fl_show_pct_right
        lda     #$28         ; '('
        jsr     CHROUT
        lda     pct_acc+1
        jsr     print_pct
        lda     #$29         ; ')'
        jsr     CHROUT
        rts

fl_loading_txt
        !text   "LOADING "
        !byte   $00

lr_dev_prompt
        ldx     #$00
lr_dev_loop
        lda     be_dev_prompt_txt,x
        beq     lr_dev_show_default
        jsr     CHROUT
        inx
        bne     lr_dev_loop
lr_dev_show_default
        lda     KERNAL_CURDEV
        jsr     print_dec
        lda     #$29         ; ')'
        jsr     CHROUT
        lda     #$20
        jsr     CHROUT
        lda     KERNAL_CURDEV
        sta     dv_num
        jsr     read_device

        jsr     lr_read_dir
        lda     lr_count
        bne     lr_have_files
        ldx     #$00
lr_none_msg
        lda     lr_none_txt,x
        beq     lr_none_wait
        jsr     CHROUT
        inx
        bne     lr_none_msg
lr_none_wait
        jsr     GETIN
        beq     lr_none_wait
        rts
lr_have_files
        lda     #$00
        sta     lr_cursor
        sta     lr_top

; --- lr_browse: redraws the current page (header + up to LR_ROWS
; entries, cursor row marked with "> ") and waits for CRSR UP/DOWN,
; RETURN, or back-arrow. Full redraw on every move rather than a
; partial update, same tradeoff READ EPROM's rp_full makes on its own
; less-frequent redraws - this list is short enough (LR_ROWS=20 rows,
; plain text) that the redraw cost isn't visible. ---
lr_browse
        lda     #$93
        jsr     CHROUT
        lda     lr_mode
        cmp     #LR_MODE_BROWSE
        bne     lr_browse_hdr_not_browse
        ldx     #$00
lr_browse_hdr_browse
        lda     lr_browse_hdr_browse_msg,x
        beq     lr_browse_rows_init
        jsr     CHROUT
        inx
        bne     lr_browse_hdr_browse
lr_browse_hdr_not_browse
lr_browse_hdr_load
        ldx     #$00
lr_browse_hdr
        lda     lr_browse_hdr_msg,x
        beq     lr_browse_rows_init
        jsr     CHROUT
        inx
        bne     lr_browse_hdr
lr_browse_rows_init
        lda     lr_top
        sta     hd_count        ; row-walk index (0-based into the full
                                    ; list) - hd_count reused, safe: this
                                    ; screen never runs alongside EPROM
                                    ; DUMP or read_device's own digit
                                    ; count, same sharing rule already
                                    ; covers other screens in this file
        ldx     #$00            ; on-screen row counter, 0..LR_ROWS-1
lr_browse_row
        cpx     #LR_ROWS
        beq     lr_browse_rows_done
        lda     hd_count
        cmp     lr_count
        bcs     lr_browse_rows_done  ; ran out of real entries
        pha
        lda     hd_count
        cmp     lr_cursor
        bne     lr_browse_no_mark
        lda     #$1e         ; green
        jsr     CHROUT
        lda     #$3e         ; '>'
        jsr     CHROUT
        lda     #$20
        jsr     CHROUT
        jmp     lr_browse_mark_done
lr_browse_no_mark
        lda     #$05         ; white
        jsr     CHROUT
        lda     #$20
        jsr     CHROUT
        lda     #$20
        jsr     CHROUT
lr_browse_mark_done
        pla
        jsr     lr_print_name   ; A = index into LR_NAME_TABLE (still
                                   ; hd_count's value - lr_print_name
                                   ; doesn't touch it)
        lda     #$0d
        jsr     CHROUT
        inc     hd_count
        inx
        jmp     lr_browse_row
lr_browse_rows_done
        lda     #$05         ; white
        jsr     CHROUT
        ldx     #$00
lr_browse_ctrl
        lda     lr_browse_ctrl_msg,x
        beq     lr_browse_wait
        jsr     CHROUT
        inx
        bne     lr_browse_ctrl
lr_browse_wait
        jsr     GETIN
        beq     lr_browse_wait
        cmp     #$11         ; CRSR DOWN
        beq     lr_browse_down
        cmp     #$91         ; CRSR UP
        beq     lr_browse_up
        cmp     #$0d         ; RETURN - load the highlighted entry
        beq     lr_browse_select
        cmp     #$14         ; DEL/INST - delete the highlighted entry
        bne     lr_browse_w1
        jmp     lr_browse_delete
lr_browse_w1
        cmp     #KEY_BACKARROW
        beq     lr_browse_back
        jmp     lr_browse_wait
lr_browse_down
        lda     lr_cursor
        clc
        adc     #1
        cmp     lr_count
        bcs     lr_browse_wait  ; already at the last entry
        sta     lr_cursor
        jsr     lr_scroll_fix
        jmp     lr_browse
lr_browse_up
        lda     lr_cursor
        beq     lr_browse_wait  ; already at the first entry
        sec
        sbc     #1
        sta     lr_cursor
        jsr     lr_scroll_fix
        jmp     lr_browse
lr_browse_back
        rts
lr_browse_select
        lda     lr_mode
        cmp     #LR_MODE_BROWSE
        bne     lr_browse_select_go  ; FILE / DISK TOOLS: RETURN is a
        jmp     lr_browse              ; no-op here, just redraw - browse/
                                          ; DEL only, nothing to load or
                                          ; verify in this mode
lr_browse_select_go
        lda     lr_cursor
        jsr     lr_copy_name_to_fn ; fn_buf/fn_len = the selected entry
        lda     #REU_ORIGINAL_BANK  ; dv_num already set by lr_dev_prompt -
        jsr     reu_stream_file       ; streams the WHOLE file into REU
                                         ; (not just one chunk) so paging
                                         ; below never needs to reopen the
                                         ; file again, unlike the old fl_
                                         ; seek_chunk-per-chunk approach
        bcc     lls_load_ok
        lda     #<rl_fail_txt
        ldy     #>rl_fail_txt
        jsr     print_str
lls_load_fail_wait
        jsr     GETIN
        beq     lls_load_fail_wait
        rts
lls_load_ok
        lda     #REU_ORIGINAL_BANK  ; populate WORKING (what the viewer
        ldx     #REU_WORKING_BANK     ; below actually pages through) and
        ldy     reu_file_chunks         ; UNDO (a pristine snapshot for a
        jsr     reu_copy_region           ; future revert feature) from
        lda     #REU_WORKING_BANK          ; the just-loaded ORIGINAL -
        ldx     #REU_UNDO_BANK               ; only as many chunks as the
        ldy     reu_file_chunks               ; file actually has, not
        jsr     reu_copy_region                 ; always the full region
                                                    ; (see reu_copy_
                                                    ; region's own comment)
        lda     #$01
        sta     view_mode
        lda     #$00
        sta     eprom_bank
        sta     eprom_offset
        sta     eprom_offset+1
        jmp     rp_show             ; tail into the existing FILE VIEW
                                       ; browser - its own <- returns to
                                       ; whoever called do_disk_load,
                                       ; same "JMP, not JSR, so the RTS
                                       ; deep inside still lands on the
                                       ; right caller" pattern do_read_
                                       ; eprom itself already relies on

; --- DEL/INST on the highlighted entry: confirms (Y/anything-else),
; then scratches it via the real CBM DOS "S:name" command channel
; sequence (same mechanism c1541 -delete and BASIC's own OPEN 15,8,15,
; "S:name":CLOSE15 both use) - no read-back of channel 15's own error
; response afterward, same "fails silently for now" scope decision
; bank10_content.asm's DELETE command already made. Re-reads the
; directory afterward so the list reflects the deletion immediately,
; clamping lr_cursor if the deleted entry was the last one and
; resetting lr_top to 0 (simplest safe choice - scrolls back to the
; top rather than trying to preserve scroll position through a
; changed list). ---
lr_browse_delete
        lda     lr_cursor
        jsr     lr_copy_name_to_fn ; fn_buf/fn_len = the entry to delete
        ldx     #$00
lr_del_confirm_hdr
        lda     lr_del_confirm_txt,x
        beq     lr_del_confirm_name
        jsr     CHROUT
        inx
        bne     lr_del_confirm_hdr
lr_del_confirm_name
        ldx     #$00
lr_del_confirm_name_loop
        lda     fn_buf,x
        beq     lr_del_confirm_q
        jsr     CHROUT
        inx
        bne     lr_del_confirm_name_loop
lr_del_confirm_q
        ldx     #$00
lr_del_confirm_q_loop
        lda     lr_del_confirm_q_txt,x
        beq     lr_del_confirm_wait
        jsr     CHROUT
        inx
        bne     lr_del_confirm_q_loop
lr_del_confirm_wait
        jsr     GETIN
        beq     lr_del_confirm_wait
        cmp     #$59         ; 'Y'
        beq     lr_del_do
        jmp     lr_browse    ; anything else - cancel, just redraw
lr_del_do
        ldx     #$00
lr_del_build_loop
        lda     fn_buf,x
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
                                  ; sty fn_len relies on; +2 for "S:"
        ldx     #<lr_del_cmd
        ldy     #>lr_del_cmd
        jsr     KERNAL_SETNAM
        lda     #15
        ldx     dv_num
        ldy     #15
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        lda     #15
        jsr     KERNAL_CLOSE
        jsr     lr_read_dir
        lda     lr_count
        bne     lr_del_have_files
        jmp     lr_none_msg      ; deleted the last file - reuse the
                                    ; existing "no files" screen (also
                                    ; correctly rts's back to whoever
                                    ; called do_disk_load/do_verify_
                                    ; file/do_file_tools)
lr_del_have_files
        lda     #$00
        sta     lr_top
        lda     lr_cursor
        cmp     lr_count
        bcc     lr_del_cursor_ok
        lda     lr_count
        sec
        sbc     #1
        sta     lr_cursor
lr_del_cursor_ok
        jmp     lr_browse

lr_del_confirm_txt
        !text   "DELETE "
        !byte   $00
lr_del_confirm_q_txt
        !text   "? (Y/N) "
        !byte   $00
lr_del_cmd !fill 18,0   ; "S:" (2) + up to 16 chars - no null needed,
                          ; SETNAM takes an explicit length

; --- Keeps lr_cursor on screen after a CRSR move: scrolls lr_top up or
; down by exactly one row at a time (cursor moves one row at a time
; too, so it can never leave the visible page by more than one row in
; a single step). ---
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
        bne     lr_scroll_done   ; cursor is still within the current page
        inc     lr_top
lr_scroll_done
        rts

; --- A = index into LR_NAME_TABLE -> prints that entry's name via
; CHROUT (no fixed width - short names just end early). ---
lr_print_name
        jsr     lr_table_addr    ; dir_ptr = &LR_NAME_TABLE[A]
        ldy     #$00
lr_pn_loop
        lda     (dir_ptr),y
        beq     lr_pn_done
        jsr     CHROUT
        iny
        jmp     lr_pn_loop
lr_pn_done
        rts

; --- A = index into LR_NAME_TABLE -> copies that entry into fn_buf,
; null-terminated, with fn_len set - same convention read_filename
; itself leaves fn_buf/fn_len in, so fl_seek_chunk (which only knows
; about fn_buf/fn_len/dv_num, not LR_NAME_TABLE) can load it unchanged.
; ---
lr_copy_name_to_fn
        jsr     lr_table_addr
        ldy     #$00
lr_cn_loop
        lda     (dir_ptr),y
        sta     fn_buf,y
        beq     lr_cn_done
        iny
        jmp     lr_cn_loop
lr_cn_done
        sty     fn_len           ; Y already equals the exact character
                                    ; count here - it's only ever
                                    ; incremented for a real (non-null)
                                    ; char, so it never counts the
                                    ; terminator itself
        rts

; --- A (0..LR_MAX_FILES-1) -> dir_ptr = &LR_NAME_TABLE[A*LR_NAME_LEN].
; Plain repeated addition (X = A as the loop counter): LR_MAX_FILES
; tops out at 64, so this is at most 64 additions, same "simpler than a
; real multiply for a small, one-off value" reasoning times10 above
; already uses. ---
lr_table_addr
        sta     hd_count         ; stash the index - safe, see
                                    ; lr_browse_rows_init's own comment
        lda     #<LR_NAME_TABLE
        sta     dir_ptr
        lda     #>LR_NAME_TABLE
        sta     dir_ptr+1
        ldx     hd_count
        beq     lr_ta_done       ; index 0 - table base is already correct
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

; --- Reads the "$" directory from dv_num via OPEN/CHKIN/CHRIN (not
; KERNAL_LOAD - same reasoning bank10_content.asm's DirCmd already
; worked out and verified live: LOAD prints its own "SEARCHING FOR $"/
; "LOADING" status text, and this needs to parse the result, not just
; display it), into FILE_BUF as scratch (a full directory is well under
; 8KB, and nothing else needs FILE_BUF until a file is actually
; selected afterward), then walks that raw listing with the exact same
; verified byte layout DirCmd's own header comment documents (link/
; size/quoted-name/type, all PETSCII text terminated by $00, entry list
; itself terminated by a $0000 link) - except storing each real file's
; name into LR_NAME_TABLE instead of printing it. A header entry (disk
; name/ID) always has size 0; the trailing "BLOCKS FREE." entry has no
; quoted name at all - both skipped via lr_rd_skip, same as DirCmd's
; own dir_skip_silent. ---
lr_read_dir
        lda     #$00
        sta     lr_count
        sta     lr_rd_seen_header
        lda     #1
        ldx     #<lr_dir_filename
        ldy     #>lr_dir_filename
        jsr     KERNAL_SETNAM
        lda     #2
        ldx     dv_num
        ldy     #0
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        bcc     lr_rd_open_ok
        lda     #2
        jsr     KERNAL_CLOSE     ; OPEN can fail (e.g. device not
                                    ; present) while still leaving
                                    ; logical file #2 marked open in the
                                    ; KERNAL's own tables - without this,
                                    ; the NEXT OPEN of file #2 fails too,
                                    ; even to a device that IS present
                                    ; (confirmed live: pick a bad device,
                                    ; then a good one - "NO FILES FOUND"
                                    ; both times)
        rts                      ; open failed - lr_count stays 0,
                                    ; caller shows "NO FILES FOUND"
lr_rd_open_ok
        ldx     #2
        jsr     KERNAL_CHKIN
        bcc     lr_rd_chkin_ok
        lda     #2
        jsr     KERNAL_CLOSE
        rts                      ; CHKIN failed - lr_count stays 0,
                                    ; caller shows "NO FILES FOUND"
lr_rd_chkin_ok
        jsr     KERNAL_CHRIN     ; discard the pseudo-file's own 2-byte
        jsr     KERNAL_CHRIN     ; embedded load address, same as DirCmd
        lda     #<FILE_BUF
        sta     dir_ptr
        lda     #>FILE_BUF
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

        lda     #<FILE_BUF
        sta     dir_ptr
        lda     #>FILE_BUF
        sta     dir_ptr+1
lr_rd_entry_loop
        ldy     #$00
        lda     (dir_ptr),y
        sta     bt_same_flag     ; scratch - do_bank_test never runs
                                    ; concurrently with this screen
        iny
        lda     (dir_ptr),y
        ora     bt_same_flag
        bne     lr_rd_have_link
        rts                      ; link == $0000 - end of directory
lr_rd_have_link
        clc                       ; skip past the link (already read
        lda     dir_ptr             ; above) and the 2-byte size field -
        adc     #4                  ; the size VALUE itself isn't needed
        sta     dir_ptr             ; to decide real-file-vs-not (see
        bcc     +                   ; below): only its position needs
        inc     dir_ptr+1           ; skipping to reach the quoted name
+
; --- The disk-name/ID header entry is always exactly the FIRST entry
; in a CBM DOS directory listing (guaranteed by the format - it's read
; from the fixed track/sector 18/0 header, not a real file), so that's
; the reliable way to skip it - NOT "size == 0", which an earlier
; version of this used (matching bank10_content.asm's own DirCmd) on
; the assumption "every real file is always >= 1 block". That's true
; for a properly-closed file but not for a splat/never-closed one
; (confirmed live: a 0-block splat file was silently invisible to this
; picker, indistinguishable from the header by that old check - exactly
; the kind of leftover junk file DEL exists to clean up, so it needs to
; actually show up here to select). Every entry after the first is
; checked by lr_rd_find_quote below instead - a quoted name means a
; real entry (whatever its size); no quote at all means the trailing
; "BLOCKS FREE." footer. ---
        lda     lr_rd_seen_header
        bne     lr_rd_find_quote ; not the header - look for a real entry
        lda     #$01
        sta     lr_rd_seen_header
        jmp     lr_rd_skip        ; this IS the header - always skip it
lr_rd_find_quote
        ldy     #$00
        lda     (dir_ptr),y
        bne     +
        jmp     lr_rd_skip        ; terminator, no quote - free-space entry
+       cmp     #$22              ; '"'
        beq     lr_rd_quote_found
        jsr     lr_rd_ptr_inc
        jmp     lr_rd_find_quote
; --- Found the opening quote of a real file's name. Copies chars up to
; the closing quote (or CBM DOS's own 16-char cap) into LR_NAME_TABLE
; via lr_dest_ptr - a SEPARATE zero-page pointer from dir_ptr, not
; lr_table_addr/dir_ptr reused: dir_ptr is busy walking the SOURCE
; listing in FILE_BUF at this exact moment, so overwriting it here (an
; earlier draft of this routine tried exactly that) would lose the
; caller's place in the middle of the walk. Y serves double duty per
; iteration - 0 to read the current source char (dir_ptr always points
; directly AT that char, advanced one at a time via lr_rd_ptr_inc, so
; no growing source index is needed), then X's value to write it at
; the right offset in the destination - never both at once, so no
; conflict. ---
lr_rd_quote_found
        jsr     lr_rd_ptr_inc     ; skip the opening quote
        lda     lr_count
        cmp     #LR_MAX_FILES
        bcs     lr_rd_skip        ; table already full - stop collecting
                                    ; but keep skipping to a clean EOF
        jsr     lr_set_dest       ; lr_dest_ptr = &LR_NAME_TABLE[lr_count]
        ldx     #$00
lr_rd_name_loop
        ldy     #$00
        lda     (dir_ptr),y
        beq     lr_rd_name_term   ; terminator with no closing quote -
                                     ; shouldn't happen for a real entry,
                                     ; treat as malformed and bail
        cmp     #$22              ; '"'
        beq     lr_rd_name_closed
        cpx     #16
        beq     lr_rd_name_skip   ; already at CBM's own filename cap -
                                     ; keep walking the source to find
                                     ; the closing quote, stop copying
        pha                       ; save the char
        txa
        tay                       ; Y = X (destination offset)
        pla                       ; restore the char
        sta     (lr_dest_ptr),y
        inx
lr_rd_name_skip
        jsr     lr_rd_ptr_inc
        jmp     lr_rd_name_loop
lr_rd_name_term
        jmp     lr_rd_skip
lr_rd_name_closed
        jsr     lr_rd_ptr_inc     ; skip the closing quote
        txa
        tay                       ; Y = X (final length) - null-
                                     ; terminate right after the last
                                     ; copied char
        lda     #$00
        sta     (lr_dest_ptr),y
        inc     lr_count
        jmp     lr_rd_skip        ; done with this entry - walk past
                                     ; the type/rest to the next one,
                                     ; same tail every entry uses

; --- Sets lr_dest_ptr = &LR_NAME_TABLE[lr_count*LR_NAME_LEN] (reads
; lr_count directly, no argument needed - always called right where
; lr_count already holds the slot being filled). Same repeated-addition
; approach as lr_table_addr below, kept as a separate routine (rather
; than parameterizing which pointer to set) since that's simpler than
; threading a pointer-select argument through every call site for
; what's only two use cases. ---
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

; --- Walks dir_ptr to this entry's own $00 terminator without copying
; anything (used both for entries lr_rd_quote_found already finished
; with, and directly for header/footer entries that were never real
; files to begin with), then steps past that terminator onto the next
; entry's link bytes. Mirrors bank10_content.asm's DirCmd/dir_skip_
; silent exactly, just operating on dir_ptr instead of $14/$15. ---
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

lr_dir_filename !text "$"

lr_none_txt
        !text   "NO FILES FOUND - PRESS ANY KEY"
        !byte   $0d,$00
lr_browse_hdr_msg
        !text   "LOAD FILE TO RAM - SELECT A FILE"
        !byte   $0d
        !text   "===================================="
        !byte   $0d,$00
lr_browse_hdr_browse_msg
        !text   "FILE / DISK TOOLS"
        !byte   $0d
        !text   "===================================="
        !byte   $0d,$00
lr_browse_ctrl_msg
        !byte   $0d
        !text   "CRSR=MOVE  RETURN=SELECT  DEL=DELETE"
        !byte   $0d
        !text   "<-=BACK"
        !byte   $0d,$00

; --- LOAD FILE TO RAM's own directory-browse state - plain assembled
; bytes, not "=" zero-page assignments (see LR_MAX_FILES's own comment
; above for why $C0-$FF specifically isn't actually free here). ---
lr_count  !byte 0
lr_cursor !byte 0
lr_top    !byte 0
lr_mode   !byte 0        ; LR_MODE_LOAD or LR_MODE_BROWSE - which action
                            ; lr_browse_select takes on RETURN
lr_rd_seen_header !byte 0 ; lr_read_dir's own "have we skipped the
                            ; disk-name/ID header entry yet" flag - see
                            ; lr_rd_have_link's own comment

; to $DE00 and shows the first 8 bytes read back at $8000 for each -
; a software-side check for whether the $DE00 latch write is actually
; having any effect at all. $DE00 itself is write-only (can't be read
; back to confirm the latch captured a value - true of every board
; using this bank-select scheme, confirmed against EasyFlash's own real
; EAPI driver, which keeps its own RAM-side shadow for the same reason)
; and neither GAME nor EXROM are memory-mapped/readable by any C64
; register - they're pure hardware inputs to the PLA. This is the
; closest thing to a direct test software can do: if every bank shows
; IDENTICAL data, the latch write isn't reaching the chip's address
; lines at all (or nothing is actually being read as ROM to begin
; with); if the data actually differs per bank, bank switching is
; electrically working, independent of the separate GAME/EXROM
; question. ---
do_bank_test
        lda     #$93
        jsr     CHROUT
        ldx     #$00
bt_hdr
        lda     bt_hdr_msg,x
        beq     bt_start
        jsr     CHROUT
        inx
        bne     bt_hdr
bt_start
        lda     #$01
        sta     bt_same_flag
        lda     #$00
        sta     eprom_bank
bt_loop
        lda     eprom_bank
        sta     EASYFLASH_BANK
        lda     #$00
        sta     rd_addr
        lda     #$80
        sta     rd_addr+1
        ldx     #$00
bt_row_hdr
        lda     bt_row_msg,x
        beq     bt_row_hdr_done
        jsr     CHROUT
        inx
        bne     bt_row_hdr
bt_row_hdr_done
        lda     eprom_bank
        jsr     print_hex
        lda     #$3a
        jsr     CHROUT
        lda     #$20
        jsr     CHROUT
        ldy     #$00
bt_col
        lda     (rd_addr),y
        jsr     print_hex
        lda     #$20
        jsr     CHROUT
        ldx     eprom_bank
        bne     bt_col_cmp
        lda     (rd_addr),y      ; bank 0: record as the reference row
        sta     bt_ref,y
        jmp     bt_col_next
bt_col_cmp
        lda     (rd_addr),y
        cmp     bt_ref,y
        beq     bt_col_next
        lda     #$00
        sta     bt_same_flag     ; found a difference from bank 0
bt_col_next
        iny
        cpy     #$08
        bne     bt_col
        lda     #$0d
        jsr     CHROUT
        inc     eprom_bank
        lda     eprom_bank
        cmp     #EPROM_PHYSICAL_BANKS
        bne     bt_loop
        lda     #$0d
        jsr     CHROUT
        lda     bt_same_flag
        beq     bt_differs
        ldx     #$00
bt_identical_msg
        lda     bt_identical_txt,x
        beq     bt_wait
        jsr     CHROUT
        inx
        bne     bt_identical_msg
        jmp     bt_wait
bt_differs
        ldx     #$00
bt_differs_msg
        lda     bt_differs_txt,x
        beq     bt_wait
        jsr     CHROUT
        inx
        bne     bt_differs_msg
bt_wait
        jsr     GETIN
        beq     bt_wait
        rts

bt_hdr_msg
        !text   "BANK SCANNER"
        !byte   $0d,$0d,$00
bt_row_msg
        !text   "BANK $"
        !byte   $00
bt_identical_txt
        !text   "ALL BANKS SHOW IDENTICAL DATA -"
        !byte   $0d
        !text   "THE $DE00 LATCH WRITE MAY NOT BE"
        !byte   $0d
        !text   "REACHING THE CHIP AT ALL."
        !byte   $0d,$00
bt_differs_txt
        !text   "DATA DIFFERS PER BANK - BANK"
        !byte   $0d
        !text   "SWITCHING IS ELECTRICALLY WORKING."
        !byte   $0d,$00
bt_ref !fill 8,0

; ============================================================
; IDENTIFY ROM / CARTRIDGE ('I' on the main menu): this hardware can't
; read a real chip ID (see this file's own header comment - Product ID
; mode needs 11.4-12V this board can't generate), so this reads what
; IS actually readable instead: bank 0's own reset/NMI vectors and the
; standard C64 cartridge autostart signature bytes at $8004-$8008
; ("CBM80" - $C3,$C2,$CD,$38,$30, the exact bytes the KERNAL itself
; checks for at boot to decide whether to autostart a cartridge). A
; match means this is a standard autostart-format cartridge image,
; not a claim about the chip itself. ---
do_identify
        lda     #$00
        sta     EASYFLASH_BANK
        lda     #$93
        jsr     CHROUT
        ldx     #$00
di_hdr
        lda     di_hdr_msg,x
        beq     di_vec
        jsr     CHROUT
        inx
        bne     di_hdr
di_vec
        lda     #<di_reset_msg
        ldy     #>di_reset_msg
        jsr     print_str
        lda     $8001
        jsr     print_hex
        lda     $8000
        jsr     print_hex
        lda     #$0d
        jsr     CHROUT
        lda     #<di_nmi_msg
        ldy     #>di_nmi_msg
        jsr     print_str
        lda     $8003
        jsr     print_hex
        lda     $8002
        jsr     print_hex
        lda     #$0d
        jsr     CHROUT
        lda     #$0d
        jsr     CHROUT
        lda     #<di_sig_msg
        ldy     #>di_sig_msg
        jsr     print_str
        ldx     #$00
di_sig_loop
        lda     $8004,x
        jsr     print_hex
        lda     #$20
        jsr     CHROUT
        inx
        cpx     #$05
        bne     di_sig_loop
        lda     #$0d
        jsr     CHROUT
        lda     #$0d
        jsr     CHROUT
        ldx     #$00
di_sig_check
        lda     $8004,x
        cmp     cbm80_sig,x
        bne     di_no_match
        inx
        cpx     #$05
        bne     di_sig_check
        lda     #<di_match_txt
        ldy     #>di_match_txt
        jsr     print_str
        jmp     di_wait
di_no_match
        lda     #<di_nomatch_txt
        ldy     #>di_nomatch_txt
        jsr     print_str
di_wait
        jsr     GETIN
        beq     di_wait
        rts

; --- Print a null-terminated string. A/Y = low/high of its address -
; same shape as this file's own print_hex, added here rather than
; converting every message in this file to use it (existing inline
; loops elsewhere already work; this just avoids yet another one for
; the several messages do_identify itself prints). ---
print_str
        sta     str_ptr_id
        sty     str_ptr_id+1
        ldy     #$00
ps_loop
        lda     (str_ptr_id),y
        beq     ps_done
        jsr     CHROUT
        iny
        bne     ps_loop
ps_done
        rts

cbm80_sig !byte $c3,$c2,$cd,$38,$30   ; "CBM80" - see this feature's own
                                         ; header comment

di_hdr_msg
        !text   "IDENTIFY ROM / CARTRIDGE"
        !byte   $0d,$0d,$00
di_reset_msg
        !text   "RESET VECTOR: $"
        !byte   $00
di_nmi_msg
        !text   "NMI VECTOR:   $"
        !byte   $00
di_sig_msg
        !text   "SIGNATURE ($8004-$8008): "
        !byte   $0d
        !byte   $00
di_match_txt
        !text   "CBM80 AUTOSTART SIGNATURE FOUND -"
        !byte   $0d
        !text   "THIS IS A STANDARD AUTOSTART CARTRIDGE."
        !byte   $0d
        !text   "PRESS ANY KEY"
        !byte   $0d,$00
di_nomatch_txt
        !text   "NO CBM80 SIGNATURE - NOT A STANDARD"
        !byte   $0d
        !text   "AUTOSTART CARTRIDGE IMAGE."
        !byte   $0d
        !text   "PRESS ANY KEY"
        !byte   $0d,$00

; --- Writes reu_c64_addr/reu_addr/reu_len (already set by the caller)
; to the REU's own DMA registers, then triggers the transfer by writing
; the command byte (A) - execute+FF00-disable+type, see REU_CMD_STORE/
; FETCH/COMPARE's own comments. The transfer itself steals bus cycles
; the same way a VIC-II badline does, so it's already finished by the
; time the very next instruction runs - no completion poll needed.
; Reads REU_STATUS first (and discards it) before touching any other
; register - confirmed live that without this, only the very FIRST
; reu_xfer call after boot actually moves data; every call after that
; silently no-ops (destination keeps showing whatever the first
; transfer left there, no matter what address/length is requested) -
; the End Of Block/Fault bits in $DF00 latch until read, and appear to
; block the REU from starting a new transfer while still set. ---
reu_xfer
        pha
        lda     REU_STATUS      ; drain any latched IRQ/EOB/FAULT bits
                                    ; from the previous transfer - see
                                    ; this routine's own header comment
        lda     reu_c64_addr
        sta     REU_C64_LO
        lda     reu_c64_addr+1
        sta     REU_C64_HI
        lda     reu_addr
        sta     REU_REU_LO
        lda     reu_addr+1
        sta     REU_REU_HI
        lda     reu_addr+2
        sta     REU_REU_BANK
        lda     reu_len
        sta     REU_LEN_LO
        lda     reu_len+1
        sta     REU_LEN_HI
        lda     #$00
        sta     REU_ADDR_CTRL   ; both addresses auto-increment
        pla
        sta     REU_COMMAND     ; triggers the transfer
        rts

; --- Detects real REU hardware by round-tripping a known byte through
; REU bank 0 offset 0 (FILE_BUF's own scratch, safe - nothing has been
; loaded yet the one time this ever runs, see reu_checked's own
; comment). STORE $A5 there, deliberately clobber the C64-side copy
; with $00, then FETCH the same REU location back: if a real REU acted
; on the STORE, the FETCH restores $A5; if REU is absent (both calls
; silently no-op, per reu_xfer's own header comment), the C64 side
; still reads back the $00 we just clobbered it with. Sets reu_present
; (1/0) - never a false positive either way, since the two outcomes
; are bytewise distinguishable and nothing else touches FILE_BUF or
; REU bank 0 offset 0 between the STORE and the FETCH. ---
check_reu_present
        lda     #$a5
        sta     FILE_BUF
        lda     #<FILE_BUF
        sta     reu_c64_addr
        lda     #>FILE_BUF
        sta     reu_c64_addr+1
        lda     #$00
        sta     reu_addr
        sta     reu_addr+1
        sta     reu_addr+2
        lda     #<1
        sta     reu_len
        lda     #>1
        sta     reu_len+1
        lda     #REU_CMD_STORE
        jsr     reu_xfer
        lda     #$00
        sta     FILE_BUF        ; deliberately wrong - only a real FETCH
                                    ; below can put $A5 back
        lda     #REU_CMD_FETCH
        jsr     reu_xfer
        lda     FILE_BUF
        cmp     #$a5
        bne     crp_absent
        lda     #$01
        sta     reu_present
        rts
crp_absent
        lda     #$00
        sta     reu_present
        rts

; --- Shared REU-required gate - call at the top of any screen that
; needs real REU hardware (currently just DISK LOAD/FILE VIEW's REU
; paging). Returns with carry CLEAR if REU is
; present (caller proceeds as normal); if reu_present is 0 (see check_
; reu_present's own comment), prints a clear error instead of silently
; showing/comparing wrong data the way FILE VIEW paging used to,
; waits for a keypress, and returns with carry SET - caller should
; rts straight back to the main menu in that case. ---
reu_gate
        lda     reu_present
        bne     rg_ok
        lda     #$93
        jsr     CHROUT
        ldx     #$00
rg_msg
        lda     reu_absent_txt,x
        beq     rg_wait
        jsr     CHROUT
        inx
        bne     rg_msg
rg_wait
        jsr     GETIN
        beq     rg_wait
        sec
        rts
rg_ok
        clc
        rts

reu_absent_txt
        !text   "REU NOT DETECTED"
        !byte   $0d,$0d
        !text   "THIS SCREEN NEEDS A RAM EXPANSION UNIT"
        !byte   $0d
        !text   "(MIN 256K). ENABLE IT IN YOUR EMULATOR"
        !byte   $0d
        !text   "OR HARDWARE, THEN RESTART CARTLAB."
        !byte   $0d,$0d
        !text   "PRESS ANY KEY..."
        !byte   $0d,$00

; --- A = target REU bank byte (REU_ORIGINAL_BANK etc - the region's
; own 64K-aligned start). Streams fn_buf/fn_len (on device dv_num) into
; REU starting at that region's own address 0, one FILE_BUF-sized
; (8192-byte) chunk at a time - read the chunk from disk into ordinary
; C64 RAM first, then DMA-store that whole chunk to REU in one shot.
; Carry set on open/CHKIN failure only. Every caller loads into
; REU_ORIGINAL_BANK specifically and then uses reu_copy_region to
; populate WORKING/UNDO from it - see this file's own REU layout
; comment (near REU_ORIGINAL_BANK's declaration) for why. ---
reu_stream_file
        sta     rl_target_bank
        lda     #$00
        sta     reu_file_chunks   ; counts up as real chunks get stored
                                     ; below - see reu_copy_region's own
                                     ; comment for why this exists
        lda     #$93         ; clear screen - the caller's own picker
        jsr     CHROUT         ; screen was still showing behind this
                                  ; message otherwise (confirmed live)
        lda     #<rl_loading_msg
        ldy     #>rl_loading_msg
        jsr     print_str
        lda     fn_len
        ldx     #<fn_buf
        ldy     #>fn_buf
        jsr     KERNAL_SETNAM
        lda     #4
        ldx     dv_num
        ldy     #0
        jsr     KERNAL_SETLFS
        jsr     KERNAL_OPEN
        bcc     rl_open_ok
        php                      ; save OPEN's own carry=1 error state -
                                    ; KERNAL_CLOSE below sets its own
                                    ; carry on return, which would
                                    ; otherwise clobber it
        lda     #4
        jsr     KERNAL_CLOSE     ; OPEN can fail while still leaving
                                    ; logical file #4 marked open in the
                                    ; KERNAL's own tables - without this,
                                    ; the NEXT OPEN of file #4 fails too
        plp
        rts                     ; carry already set by KERNAL_OPEN
rl_open_ok
        ldx     #4
        jsr     KERNAL_CHKIN
        bcc     rl_chkin_ok
        lda     #4
        jsr     KERNAL_CLOSE
        sec
        rts
rl_chkin_ok
        lda     #$00
        sta     reu_addr
        sta     reu_addr+1
        lda     rl_target_bank
        sta     reu_addr+2
        lda     #$00            ; pct_acc/PCT_STEP (shared with BACKUP
        sta     pct_acc           ; EPROM's own SAVE progress) - PCT_STEP
        sta     pct_acc+1         ; is calibrated for a full EPROM_
        lda     #$00              ; PHYSICAL_BANKS*64-page (64K) scan,
        jsr     print_pct          ; which is exactly one REU region's
        lda     #$29         ; ')'   worth - see rl_byte_loop's own 128-
        jsr     CHROUT                ; byte update call below
; --- Reads one 128-byte PAGE at a time (Y as the advancing index, 0-
; 127, "iny/bpl" - same trick be_byte_loop's own SAVE-side read loop
; already uses) rather than treating rd_addr/hd_count as full 16-bit
; values re-added-with-carry on every single byte. The 16-bit pointer/
; counter math now only happens once per 128 bytes instead of 128
; times - CHRIN/READST's own KERNAL overhead still dominates the real
; cost (unaffected by this), but this removes real, avoidable per-byte
; 6502 work on top of that. ---
rl_chunk_loop
        lda     #<FILE_BUF
        sta     rd_addr
        lda     #>FILE_BUF
        sta     rd_addr+1
        lda     #$00
        sta     hd_count        ; this chunk's own byte count (0-8192,
        sta     hd_count+1        ; reused - safe, nothing else needs it
                                     ; mid-load)
rl_page_loop
        ldy     #$00
rl_byte_loop
        jsr     KERNAL_CHRIN
        sta     (rd_addr),y
        jsr     KERNAL_READST
        bne     rl_page_eof     ; EOF - Y (0-127) + 1 is this page's own
                                    ; real byte count, not a full 128
        iny
        bpl     rl_byte_loop    ; loop while Y<128
        ; fall through: a full 128-byte page was just read
rl_page_full
        clc                     ; rd_addr += 128, hd_count += 128
        lda     rd_addr
        adc     #128
        sta     rd_addr
        lda     rd_addr+1
        adc     #$00
        sta     rd_addr+1
        clc
        lda     hd_count
        adc     #128
        sta     hd_count
        lda     hd_count+1
        adc     #$00
        sta     hd_count+1
        jsr     reu_update_pct  ; NOT be_update_pct - see that routine's
                                    ; own comment for why this loop needs
                                    ; the CLRCHN-free version
        lda     hd_count+1
        cmp     #>8192
        bcc     rl_page_loop
        lda     hd_count
        cmp     #<8192
        bcc     rl_page_loop
        jmp     rl_chunk_done
rl_page_eof
        iny                     ; Y (0-127) -> real byte count (1-128)
                                    ; this page - rd_addr itself is never
                                    ; read again after this, so only
                                    ; hd_count needs the adjustment
        tya
        clc
        adc     hd_count
        sta     hd_count
        lda     hd_count+1
        adc     #$00
        sta     hd_count+1
rl_chunk_done
        lda     hd_count
        ora     hd_count+1
        beq     rl_stream_done  ; nothing read this pass - truly done
        lda     #<FILE_BUF
        sta     reu_c64_addr
        lda     #>FILE_BUF
        sta     reu_c64_addr+1
        lda     hd_count
        sta     reu_len
        lda     hd_count+1
        sta     reu_len+1
        lda     #REU_CMD_STORE
        jsr     reu_xfer
        inc     reu_file_chunks ; this pass genuinely stored (some or all
                                    ; of) a chunk - it needs to be in the
                                    ; WORKING/UNDO copy too
        clc                     ; reu_addr += hd_count (24-bit)
        lda     reu_addr
        adc     hd_count
        sta     reu_addr
        lda     reu_addr+1
        adc     hd_count+1
        sta     reu_addr+1
        lda     reu_addr+2
        adc     #$00
        sta     reu_addr+2
        cmp     rl_target_bank  ; safety cap: a file bigger than 64K
        bne     rl_stream_done    ; would otherwise silently overflow
                                     ; into the next REU region (ORIGINAL
                                     ; ->WORKING or WORKING->UNDO) -
                                     ; truncate here instead of corrupting
                                     ; whatever sits past this region
        lda     hd_count+1
        cmp     #>8192          ; less than a full chunk means rl_byte_
        bne     rl_stream_done    ; loop's own EOF branch is what got us
                                     ; here - genuinely done, not just
                                     ; between chunks
        lda     hd_count
        cmp     #<8192
        bne     rl_stream_done
        jmp     rl_chunk_loop   ; exactly a full chunk - EOF not yet
                                    ; confirmed, go read the next one
rl_stream_done
        jsr     KERNAL_CLRCHN
        lda     #4
        jsr     KERNAL_CLOSE
        clc
        rts

rl_target_bank !byte 0
reu_file_chunks !byte 0  ; how many 8192-byte chunks the last reu_
                            ; stream_file call actually stored - always
                            ; at least 1 for any real (non-empty) file,
                            ; since even a 1-byte file still needs its
                            ; one containing chunk copied

; --- A = source REU bank byte, X = dest REU bank byte, Y = number of
; 8192-byte chunks to copy (1-8) -> copies that many chunks from one
; region to the other, 8192 bytes (one FILE_BUF) at a time via fetch-
; then-store through ordinary C64 RAM - REU's own DMA only ever moves
; data between REU and the C64 side, there's no REU-to-REU transfer
; type, so a bounce through FILE_BUF is the only way to move data
; between two REU regions at all. Used right after reu_stream_file to
; populate WORKING/UNDO from a freshly-loaded ORIGINAL - see this
; file's own REU layout comment for why. Y is normally reu_file_
; chunks (how many chunks the file just loaded into ORIGINAL actually
; touched, set by reu_stream_file itself) rather than a hardcoded 8 -
; copying the full 64K region regardless of the real file size wasted
; up to 16 unnecessary 8192-byte REU transfers for a small file
; (confirmed live as a real, avoidable chunk of the total DISK LOAD
; wait, on top of the KERNAL disk-read time that dominates it). ---
reu_copy_region
        cpy     #$00
        beq     rcr_none        ; nothing to copy (an empty file) - the
                                    ; loop below is decrement-then-branch
                                    ; (runs at least once no matter what),
                                    ; so Y=0 would wrap to 255 and copy
                                    ; 256 chunks instead of zero
        sta     rcr_src_bank
        stx     rcr_dst_bank
        lda     #$00
        sta     rcr_off
        sta     rcr_off+1
        sty     rcr_chunks_left
rcr_loop
        lda     rcr_off
        sta     reu_addr
        lda     rcr_off+1
        sta     reu_addr+1
        lda     rcr_src_bank
        sta     reu_addr+2
        lda     #<FILE_BUF
        sta     reu_c64_addr
        lda     #>FILE_BUF
        sta     reu_c64_addr+1
        lda     #<8192
        sta     reu_len
        lda     #>8192
        sta     reu_len+1
        lda     #REU_CMD_FETCH
        jsr     reu_xfer
        lda     rcr_off
        sta     reu_addr
        lda     rcr_off+1
        sta     reu_addr+1
        lda     rcr_dst_bank
        sta     reu_addr+2
        lda     #<FILE_BUF
        sta     reu_c64_addr
        lda     #>FILE_BUF
        sta     reu_c64_addr+1
        lda     #<8192
        sta     reu_len
        lda     #>8192
        sta     reu_len+1
        lda     #REU_CMD_STORE
        jsr     reu_xfer
        clc
        lda     rcr_off
        adc     #<8192
        sta     rcr_off
        lda     rcr_off+1
        adc     #>8192
        sta     rcr_off+1
        dec     rcr_chunks_left
        bne     rcr_loop
rcr_none
        rts

rcr_src_bank    !byte 0
rcr_dst_bank    !byte 0
rcr_off         !byte 0,0
rcr_chunks_left !byte 0

rl_loading_msg
        !text   "LOADING TO REU ("
        !byte   $00
rl_done_txt
        !text   "DONE - PRESS ANY KEY"
        !byte   $0d,$00
rl_fail_txt
        !text   "?LOAD ERROR - PRESS ANY KEY"
        !byte   $0d,$00

; --- Reads exactly 2 hex-digit keypresses (0-9/A-F only, each echoed)
; and returns their combined byte value in A. No DEL/backspace - a
; fixed 2-char field doesn't need it the way a filename field does. ---
reu_read_hex_byte
        jsr     reu_read_hex_digit
        asl
        asl
        asl
        asl
        sta     rhb_tmp
        jsr     reu_read_hex_digit
        ora     rhb_tmp
        rts
reu_read_hex_digit
rhd_loop
        jsr     GETIN
        beq     rhd_loop
        cmp     #$30         ; '0'
        bcc     rhd_loop
        cmp     #$3a         ; '9'+1
        bcc     rhd_ok
        cmp     #$41         ; 'A'
        bcc     rhd_loop
        cmp     #$47         ; 'F'+1
        bcs     rhd_loop
rhd_ok
        pha
        jsr     CHROUT
        pla
        jsr     sr_hex_nibble
        rts

; --- A = ASCII hex digit char ('0'-'9'/'A'-'F') -> A = its 0-15
; nibble value. ---
sr_hex_nibble
        cmp     #$3a         ; '9'+1
        bcc     shn_digit
        sec
        sbc     #$07         ; extra adjustment for 'A'-'F'
shn_digit
        sec
        sbc     #$30
        rts

reu_addr_save !byte 0,0,0
rhb_tmp       !byte 0

; --- Guards against exactly the bug FILE_BUF's own comment describes:
; this program's assembled code/data silently growing past FILE_BUF (a
; plain symbolic address, not a real *= boundary the assembler tracks)
; and getting corrupted at runtime by whatever gets DMA'd/loaded into
; that "scratch" memory. Same technique the cartridge build's own bank_
; driver.asm uses to catch a bank overflowing into the resident kernel
; region - !error here instead of a silent, much-harder-to-diagnose
; runtime corruption bug next time this file grows. ---
!if * > FILE_BUF {
        !error "cartlab.asm's own code/data has grown past FILE_BUF - move FILE_BUF (and LR_NAME_TABLE if needed) higher and rebuild"
}

; --- Same guard, for the main-menu logo's own charset copy - JET_
; CHARSET ($3000) needs to stay clear of this program's own code/data
; too, same reasoning as the FILE_BUF guard just above. ---
!if * > JET_CHARSET {
        !error "cartlab.asm's own code/data has grown past JET_CHARSET - move JET_CHARSET higher and rebuild"
}

; Character-code PAIRS (left half, right half) for "SHACKMATE", left
; to right - verbatim copy of cartlab_boot.asm's own jet_letters (see
; that file's own comment for the design notes/generation process).
jet_letters
        !byte $80, $81   ; S
        !byte $82, $83   ; H
        !byte $84, $85   ; A
        !byte $86, $87   ; C
        !byte $88, $89   ; K
        !byte $8a, $8b   ; M
        !byte $84, $85   ; A
        !byte $8c, $8d   ; T
        !byte $8e, $8f   ; E

; Per-half-character color, matching jet_letters 1-for-1 - same fixed
; palette as cartlab_boot.asm's own sm_colors, kept identical so the
; boot splash and this main menu look consistent.
sm_colors
        !byte 10, 10       ; S
        !byte 10, 10       ; H
        !byte 4, 4         ; A
        !byte 13, 13       ; C
        !byte 4, 4         ; K
        !byte 1, 1         ; M
        !byte 1, 1         ; A
        !byte 1, 1         ; T
        !byte 1, 1         ; E

; "(c) 2026 - N4LDR & WD4VA" - verbatim copy of cartlab_boot.asm's own
; copyright_txt (screen codes, not ASCII).
copyright_txt
        !byte $90, $20, $32, $30, $32, $36, $20, $2d, $20
        !byte $0e, $34, $0c, $04, $12, $20, $26, $20
        !byte $17, $04, $34, $16, $01

; 8 unique letters (S H A C K M T E), each 16x8 bold pixels split into
; a left-half/right-half 8x8 character pair - verbatim copy of
; cartlab_boot.asm's own jet_bold_font (itself a verbatim copy of
; bank14_content.asm's - see that file's own header comment for the
; design notes/generation process).
jet_bold_font
        !byte $7f, $ff, $e0, $7f, $00, $00, $ff, $7f  ; S left
        !byte $fe, $fe, $00, $f8, $7e, $02, $fe, $fe  ; S right
        !byte $f0, $f0, $f0, $ff, $ff, $f0, $f0, $f0  ; H left
        !byte $0e, $0e, $0e, $fe, $fe, $0e, $0e, $0e  ; H right
        !byte $0f, $3f, $79, $f0, $ff, $ff, $f0, $f0  ; A left
        !byte $f0, $fc, $9e, $0e, $fe, $fe, $0e, $0e  ; A right
        !byte $1f, $7f, $f0, $f0, $f0, $f0, $7f, $1f  ; C left
        !byte $f8, $fe, $00, $00, $00, $00, $fe, $f8  ; C right
        !byte $f0, $f0, $f0, $ff, $ff, $f0, $f0, $f0  ; K left
        !byte $3e, $7c, $f8, $c0, $c0, $f8, $7c, $3e  ; K right
        !byte $e0, $f0, $fc, $f7, $f3, $f0, $f0, $f0  ; M left
        !byte $06, $0e, $3e, $ee, $ce, $0e, $0e, $0e  ; M right
        !byte $ff, $ff, $0f, $0f, $0f, $0f, $0f, $0f  ; T left
        !byte $fe, $fe, $c0, $c0, $c0, $c0, $c0, $c0  ; T right
        !byte $ff, $ff, $f0, $ff, $ff, $f0, $ff, $ff  ; E left
        !byte $fe, $fe, $00, $f0, $f0, $00, $fe, $fe  ; E right

; Small circle-C copyright symbol, character code $90 here - verbatim
; copy of cartlab_boot.asm's own jet_copyright_glyph.
jet_copyright_glyph
        !byte $7e, $81, $bd, $a1, $a1, $bd, $81, $7e
