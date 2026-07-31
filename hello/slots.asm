; Shared constants for the bank-switched build: the fixed-slot jump
; table layout, and the RAM addresses used by the resident kernel
; (resident.asm) and the cross-bank call mechanism. Included by both
; resident.asm and every bank's own content file - each bank is a
; separate ACME assembly that never sees another bank's labels, so
; anything that has to be agreed on across banks (slot numbering, RAM
; variable addresses) has to be a shared compile-time constant here,
; not a real address resolved from some other bank's code.

; --- Fixed-slot jump table: $8010-$80FF, 60 slots x 4 bytes. Every
; bank reserves this same range at the same addresses; a bank only
; fills in the slots it actually implements, each with a plain
; "JMP <real address>" (3 bytes + 1 pad). resident.asm's dispatch
; tables store (bank, slot) pairs using these constants - never a raw
; label - since that's the only address that's guaranteed valid before
; the slot's own bank is even switched in. ---
SLOT_BASE = $8010
SLOT_SIZE = 4

SLOT_MENU_OPEN        = SLOT_BASE + 0*SLOT_SIZE  ; bank 0
SLOT_CLS              = SLOT_BASE + 1*SLOT_SIZE  ; bank 1

; --- SCREEN + HELP (bank 1) ---
SLOT_COLOR            = SLOT_BASE + 2*SLOT_SIZE
SLOT_BORDER           = SLOT_BASE + 3*SLOT_SIZE
SLOT_BACKGROUND       = SLOT_BASE + 4*SLOT_SIZE
SLOT_LOCATE           = SLOT_BASE + 5*SLOT_SIZE
SLOT_PRINTAT          = SLOT_BASE + 6*SLOT_SIZE
SLOT_HELP             = SLOT_BASE + 7*SLOT_SIZE

; --- GRAPHICS (bank 2) ---
SLOT_HIRES            = SLOT_BASE + 8*SLOT_SIZE
SLOT_MULTI            = SLOT_BASE + 9*SLOT_SIZE
SLOT_TEXT             = SLOT_BASE + 10*SLOT_SIZE
SLOT_PLOT             = SLOT_BASE + 11*SLOT_SIZE
SLOT_LINE             = SLOT_BASE + 12*SLOT_SIZE
SLOT_BOX              = SLOT_BASE + 13*SLOT_SIZE
SLOT_CIRCLE           = SLOT_BASE + 14*SLOT_SIZE
SLOT_PAINT            = SLOT_BASE + 15*SLOT_SIZE

; --- SPRITES (bank 3) ---
SLOT_SPRITE           = SLOT_BASE + 16*SLOT_SIZE
SLOT_SPRITEON         = SLOT_BASE + 17*SLOT_SIZE
SLOT_SPRITEOFF        = SLOT_BASE + 18*SLOT_SIZE
SLOT_SPRITECOLOR      = SLOT_BASE + 19*SLOT_SIZE

; --- INPUT (bank 4, all functions) ---
SLOT_JOY              = SLOT_BASE + 20*SLOT_SIZE
SLOT_JOYUP            = SLOT_BASE + 21*SLOT_SIZE
SLOT_JOYDOWN          = SLOT_BASE + 22*SLOT_SIZE
SLOT_JOYLEFT          = SLOT_BASE + 23*SLOT_SIZE
SLOT_JOYRIGHT         = SLOT_BASE + 24*SLOT_SIZE
SLOT_JOYFIRE          = SLOT_BASE + 25*SLOT_SIZE

; --- MEMORY (bank 5) ---
SLOT_DOKE             = SLOT_BASE + 26*SLOT_SIZE
SLOT_DUMP             = SLOT_BASE + 27*SLOT_SIZE
SLOT_FILL             = SLOT_BASE + 28*SLOT_SIZE
SLOT_MOVE             = SLOT_BASE + 29*SLOT_SIZE
SLOT_DEEK             = SLOT_BASE + 30*SLOT_SIZE  ; function
SLOT_FIND             = SLOT_BASE + 31*SLOT_SIZE  ; function
SLOT_HEXDOLLAR        = SLOT_BASE + 32*SLOT_SIZE  ; function, HEX$
SLOT_DECDOLLAR        = SLOT_BASE + 33*SLOT_SIZE  ; function, DEC$

; --- CARTRIDGE non-flash (bank 6) ---
SLOT_CARTINFO         = SLOT_BASE + 34*SLOT_SIZE
SLOT_BANK             = SLOT_BASE + 35*SLOT_SIZE
SLOT_BANKS            = SLOT_BASE + 36*SLOT_SIZE

; --- SOUND (bank 8) ---
SLOT_SOUND            = SLOT_BASE + 37*SLOT_SIZE
SLOT_VOLUME           = SLOT_BASE + 38*SLOT_SIZE
SLOT_WAVE             = SLOT_BASE + 39*SLOT_SIZE
SLOT_ADSR             = SLOT_BASE + 40*SLOT_SIZE
SLOT_FILTER           = SLOT_BASE + 41*SLOT_SIZE

; --- CARTRIDGE-flash (bank 9, stubs only - real flash-program logic
; needs a separately-verified EAPI erase/write sequence, not guessed at
; alongside everything else) ---
SLOT_FLASHERASE       = SLOT_BASE + 42*SLOT_SIZE
SLOT_FLASHLOAD        = SLOT_BASE + 43*SLOT_SIZE
SLOT_FLASHVERIFY      = SLOT_BASE + 44*SLOT_SIZE

; --- DISK (bank 10). LOAD/SAVE are stock BASIC V2 keywords already -
; the tokenizer would never even reach our tables for those exact
; names (stock keyword table is tried first), so ours are DLOAD/DSAVE
; instead, not LOAD/SAVE. ---
SLOT_DIR              = SLOT_BASE + 45*SLOT_SIZE
SLOT_DEVICE           = SLOT_BASE + 46*SLOT_SIZE
SLOT_CD               = SLOT_BASE + 47*SLOT_SIZE
SLOT_DELETE           = SLOT_BASE + 48*SLOT_SIZE
SLOT_RENAME           = SLOT_BASE + 49*SLOT_SIZE
SLOT_DLOAD            = SLOT_BASE + 50*SLOT_SIZE
SLOT_DSAVE            = SLOT_BASE + 51*SLOT_SIZE
; slots 52-59 reserved for future banks/commands
;
; install_basic_ext itself does NOT get a slot - unlike menu_open (real
; per-bank content in Bank 0) or ClsCmd/HexCmd (real per-bank content in
; Bank 1), install_basic_ext only pokes $0304-$0309 with addresses of
; resident routines (ConvertToTokens etc.) that are identical in every
; bank - so it's resident code itself, called with a plain JSR from
; irq_hook like any other resident-to-resident call, no bank_call needed.

; --- Cross-bank call state (plain RAM, not zero page - zero page has
; no room left; see the project's reference-c64-hardware-facts memory).
; Continues right after hello_cart.asm's existing f1_state/
; basic_ext_countdown bytes. ---
f1_state             = $0373   ; irq_hook's F1 debounce latch
basic_ext_countdown  = $0374   ; jiffies until install_basic_ext runs
cur_bank             = $0375   ; RAM shadow of the selected EasyFlash bank
bank_tmp             = $0376   ; bank_call/bank_return scratch
call_ptr             = $0377   ; 2 bytes: bank_call's JMP target
ext_count            = $0379   ; ConvertToTokens' 1-based ExtTab match counter
func_result_hi       = $037a   ; extended-function result, high byte
func_result_lo       = $037b   ; extended-function result, low byte
resting_bank         = $037c   ; the bank BASIC was actually resting on
                                ; just before the current bank_call visit -
                                ; cur_bank itself becomes the TARGET bank
                                ; for the duration of the call, so this is
                                ; what CARTINFO/BANKS actually want to read

; Tiny trampoline (7 bytes: LDA bank_tmp / STA $DE00 / RTS), copied into
; RAM once at boot (cart_start). The actual $DE00 write MUST execute
; from RAM, not from ROM-resident code living inside the very $8000-
; $9FFF window being switched - empirically confirmed: doing the write
; from resident.asm (identical bytes in every bank, so not a content
; problem) crashed every single time, immediately after the write, deep
; in BASIC ROM - a hardware settling hazard right around the switch,
; the same class of problem romh_boot.asm's boot trampoline already
; solves the same way for the Ultimax-to-8K-mode switch.
ram_bank_switch      = $0380

; --- print_decimal_word scratch (resident.asm) and DISK category state
; (bank 10) - continues right after ram_bank_switch's 7-byte trampoline. ---
pdw_lo               = $0387   ; print_decimal_word's 16-bit working value
pdw_hi               = $0388
pdw_count            = $0389   ; current digit's subtraction count
pdw_started          = $038a   ; 0 until the first non-suppressed digit prints
disk_device          = $038b   ; default device number for DISK commands
                                ; (boot default: 8, set in bank0_content.asm's
                                ; cart_start alongside f1_state's own init)
disk_namelen         = $038c   ; RENAME's old-name length (bank 10)
disk_namelen2        = $038d   ; RENAME's new-name length (bank 10)
func_is_string       = $038e   ; EvaluateFunction's own scratch (resident.
                                ; asm) - see EvaluateFunction's comment
dtb_outpos           = $038f   ; DEC$'s dec_to_buf: current digit-buffer
                                ; write index (bank 5)
dec_buf              = $0390   ; DEC$'s digit scratch, up to 5 bytes
                                ; (65535) - bank 5, continues to $0394

; --- EasyFlash registers (verified against real EAPI driver source,
; not guessed - see romh_boot.asm and the plan's hardware-facts notes) ---
EASYFLASH_BANK    = $de00
EASYFLASH_CONTROL = $de02
EASYFLASH_8K_MODE = $06         ; MEMCTRL|EXROM - BASIC ROM stays visible

; Total number of banks actually built (0-12, see build_cart.sh's loop) -
; every one gets the full resident kernel regardless of whether it has
; real content yet (bank_driver.asm sources resident.asm unconditionally),
; so any of these is safe to switch to; anything >= this isn't - update
; here when adding a 14th bank.
TOTAL_BANKS = 13

; --- zero-page save/restore span (unchanged from the single-bank
; design - common.asm/ultimate_sdk.asm/features.asm/bitmap.asm's
; scratch, $02-$38) ---
zp_save_buf = $033c
zp_save_len = 55

; --- screen/color/border save-restore buffers (unchanged) ---
scr_save_buf  = $c000
col_save_buf  = $c400
misc_save_buf = $c800

; --- DISK (bank 10) scratch buffers - misc_save_buf only actually uses
; 3 of its nominal 1024 bytes (border/background/text colors), leaving
; the rest of $C000-$CFFF free; these can't live in bank 10's own
; $8000-$9FFF content area since that's EasyFlash ROM at runtime, not
; writable RAM (same lesson as ram_bank_switch needing to run from RAM). ---
filename_buf     = $c900   ; DELETE/RENAME/CD/DLOAD/DSAVE's filename arg
filename2_buf    = $c920   ; RENAME's second (new) name
FILENAME_MAXLEN  = 16      ; real CBM DOS filename length limit
dir_buffer       = $c940   ; DIR's "$" directory-listing load target,
                            ; runs to $cfff (1728 bytes - comfortably
                            ; covers realistic directory sizes)
