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
SLOT_DUMP             = SLOT_BASE + 27*SLOT_SIZE
SLOT_FILL             = SLOT_BASE + 28*SLOT_SIZE
SLOT_MOVE             = SLOT_BASE + 29*SLOT_SIZE
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

; --- DISK (bank 10) ---
SLOT_DIR              = SLOT_BASE + 45*SLOT_SIZE
SLOT_DEVICE           = SLOT_BASE + 46*SLOT_SIZE
SLOT_CD               = SLOT_BASE + 47*SLOT_SIZE
SLOT_DELETE           = SLOT_BASE + 48*SLOT_SIZE
SLOT_RENAME           = SLOT_BASE + 49*SLOT_SIZE
SLOT_DLOAD            = SLOT_BASE + 50*SLOT_SIZE
SLOT_DSAVE            = SLOT_BASE + 51*SLOT_SIZE

; --- NETWORK (bank 11, Ultimate Command Interface - see
; ultimate_sdk.asm's header: UNTESTED, no way to verify without real
; Ultimate64/1541U hardware) ---
SLOT_HTTPGET          = SLOT_BASE + 52*SLOT_SIZE
SLOT_TELNET           = SLOT_BASE + 53*SLOT_SIZE

; --- Boot splash one-time setup (bank 0) - tower_anim_start/
; jet_charset_setup/jet_bold_font/jet_sprite live in
; bank0_content.asm now, not resident.asm: resident.asm has a hard
; ~2KB budget ($97C0-$9FFF) shared by every bank, and this is ~350
; bytes of
; code+data that only ever runs once, at the exact moment cur_bank is
; still guaranteed 0 (right after cold boot, before any BASIC extension
; command could plausibly have run yet) - safe to reach via a one-time
; bank_call from irq_hook instead of staying resident. jet_anim_tick
; itself (called every subsequent tick, when cur_bank could be
; anything) still has to stay resident - only the setup moved. ---
SLOT_TOWER_ANIM_START = SLOT_BASE + 54*SLOT_SIZE

; JET - replays the boot splash flyby on demand. Bank 0, same as
; tower_anim_start (which it shares its actual setup work with via
; jet_setup - see bank0_content.asm) - the first BASIC-typeable
; command to ever live in bank 0, everything else there so far being
; either menu_open (F1-only, not BASIC-reachable) or this one-time boot
; init.
SLOT_JET              = SLOT_BASE + 55*SLOT_SIZE
SLOT_REBOOT           = SLOT_BASE + 56*SLOT_SIZE  ; bank 0
SLOT_RENUM            = SLOT_BASE + 57*SLOT_SIZE  ; bank 1
; slots 58-59 reserved for future banks/commands
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

; --- Boot splash jet-flyby animation (resident.asm's irq_hook) - NOT
; zero page: this runs from irq_hook while BASIC is live (after the
; jmp ($a000) cold-start handoff), so zero page is real, in-use BASIC
; interpreter state by then, not scratch - see tower_anim_start's own
; comment. Continues right after dec_buf.
;
; tower_x/tower_y/tower_anim_ticks are reused from the original
; bouncing-icon version of this animation (still named "tower_*" to
; avoid a wider rename) - tower_x is now the jet's one-way X position
; instead of a bounced one, tower_y is set once and never updated.
; tower_dir_x/tower_dir_y are dead - the jet flies one direction only,
; no bounce - left declared rather than removed so nothing downstream
; shifts address. ---
tower_x              = $0395   ; jet sprite X position
tower_dir_x          = $0396   ; unused (no longer bounces)
tower_y              = $0397   ; jet sprite Y position (set once)
tower_dir_y          = $0398   ; unused (no longer bounces)
tower_anim_ticks     = $0399   ; jiffies remaining; 0 = animation inactive;
                                 ; also doubles as the fly/hold/fade phase
                                 ; selector - see jet_anim_tick

; --- NETWORK (bank 11) scratch - continues right after tower_anim_ticks.
; Not zero page: same reasoning as everything else in this block, and
; the Ultimate SDK's own zero-page range ($10-$17, ultimate_sdk.asm) is
; scratch for one in-flight command, not state that needs to survive
; across TELNET's whole interactive loop. ---
net_port             = $039a   ; 2 bytes: HTTPGET/TELNET's target port
telnet_sock          = $039c   ; TELNET's open socket handle

; --- VICE-stub-only scratch (ultimate_sdk_stub.asm) - unused in the
; real hardware build, but the constant costs nothing either way so
; it's declared unconditionally like everything else here. ---
net_stub_last_cmd    = $039d   ; last command byte handed to ult_cmd_start
net_stub_read_done   = $039e   ; 0 until the current "connection"'s one
                                 ; canned SOCK_READ response has been sent

; --- DEC$("hex string") scratch (bank 5) - continues right after
; net_stub_read_done. 16-bit accumulator built up one hex digit at a
; time while parsing the quoted argument, plus a digit counter to
; catch overflow (more than 4 hex digits can't fit in 16 bits). ---
hex_acc_lo           = $039f
hex_acc_hi           = $03a0
hex_digit_count      = $03a1

; --- Jet-flyby text reveal/fade state - continues right after
; hex_digit_count. ---
jet_reveal_idx       = $03a2   ; next SHACKMATE letter index (0-9) to
                                 ; reveal as the jet's TAIL reaches it
                                 ; (trailing behind, like skywriting -
                                 ; not the nose/leading edge)
jet_fade_idx         = $03a3   ; next letter index (0-9) currently
                                 ; fading/erasing, left to right
jet_fade_subtick     = $03a4   ; ticks elapsed within jet_fade_idx's own
                                 ; fade sequence (0-6)
jet_x_hi             = $03a5   ; sprite X's 9th bit (persists once set -
                                 ; see jat_fly) - lets the jet actually
                                 ; fly off the right edge of the screen
                                 ; instead of just vanishing at X=255
jet_copy_reveal_idx  = $03a6   ; next copyright-line character index
                                 ; (0-22) to reveal as the jet's tail
                                 ; reaches it - parallel to jet_reveal_
                                 ; idx, same tail-trailing trigger, own
                                 ; index since it's 22 single characters
                                 ; instead of 9 letter-pairs
jet_copy_fade_pos    = $03a7   ; how many copyright characters (0-22)
                                 ; have already been colored/erased by
                                 ; jat_fade's own progress - lets the
                                 ; 22-character copyright line fade out
                                 ; in step with the 9-letter SHACKMATE
                                 ; line instead of needing its own,
                                 ; much longer tick budget
jet_charset_ready    = $03a8   ; 0 until jet_charset_setup's one-time
                                 ; 2KB ROM copy + glyph patch has run
                                 ; once - later calls (the JET command,
                                 ; run again mid-session) skip straight
                                 ; to just re-pointing $D018, since the
                                 ; $2800 data never changes once copied.
                                 ; Explicitly zeroed in cart_start
                                 ; (bank0_content.asm) - RAM isn't
                                 ; guaranteed to power on at 0

; --- RENUM (bank 1) scratch - continues right after jet_charset_ready.
; renum_pval doubles as both the RENUM-argument accumulator (before the
; rebuild starts) and the in-line-reference-parsing accumulator (during
; the rebuild) - the two never run concurrently, same reasoning as
; reusing resident.asm's pdw_lo/pdw_hi as this routine's own *10+digit
; scratch (see bank1_content.asm's renum_x10_plus_digit). ---
renum_start           = $03a9   ; 2 bytes: first new line number
renum_step            = $03ab   ; 2 bytes: increment between lines
renum_curnew          = $03ad   ; 2 bytes: new number for the line
                                  ; currently being rebuilt
renum_pval            = $03af   ; 2 bytes: generic parsed-decimal-value
                                  ; accumulator (see comment above)
renum_newval          = $03b1   ; 2 bytes: renum_lookup's resolved
                                  ; new line number for renum_pval
renum_len             = $03b3   ; 2 bytes: final rebuilt-program length,
                                  ; used only by the RENUM_BUF copy-back

; --- DeviceCmd's own *10+digit scratch (bank 10) - continues right
; after renum_len. Not zero page - no indirect addressing needed. ---
dv_tmp_lo             = $03b5
dv_tmp_hi             = $03b6

; --- RENUM's own zero-page pointers (bank 1) - only ever touched during
; RENUM's own SEI-held, no-nested-BASIC-calls rebuild loop (the one
; exception, real BASIC ROM's LINKPRG at $a533, isn't called until
; after every renum_src/renum_dest/renum_search use is finished - see
; bank1_content.asm), so reusing zero page here is safe on the same
; grounds bank10's scmd_ptr already established: nothing else needs
; these bytes during that specific window. ---
renum_src             = $24     ; 2 bytes: walks the ORIGINAL program
renum_dest            = $26     ; 2 bytes: writes into RENUM_BUF
renum_search          = $28     ; 2 bytes: renum_lookup's own walk,
                                  ; independent of renum_src since a
                                  ; lookup runs while renum_src is
                                  ; mid-line

; --- RENUM's scratch program-rebuild buffer (bank 1) - reuses the same
; $C000-$CFFF window as the DISK category's buffers above (scr_save_buf/
; col_save_buf/misc_save_buf/filename_buf/dir_buffer): safe because only
; one BASIC+ command ever executes at a time (each holds SEI for its
; whole bank_call visit), so RENUM can never actually run concurrently
; with the F1 menu or a DISK command reusing the same bytes. Bounded to
; 4KB rather than open-ended - EasyFlash's ROML window permanently
; occupies $8000-$9FFF while this cartridge is active, so RAMTAS itself
; already caps real BASIC program space below that; a 4KB scratch cap
; is far more likely to be the real constraint for any program small
; enough to type in by hand, and RENUM checks against it explicitly
; (?PROGRAM TOO LARGE FOR RENUM) rather than silently overflowing into
; col_save_buf/dir_buffer's own bytes. ---
RENUM_BUF      = $c000
RENUM_BUF_SIZE = 4096
RENUM_BUF_END  = RENUM_BUF + RENUM_BUF_SIZE

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
; 5 of its nominal 1024 bytes (border/background/text colors, cursor
; column/row), leaving the rest of $C000-$CFFF free; these can't live
; in bank 10's own $8000-$9FFF content area since that's EasyFlash ROM
; at runtime, not writable RAM (same lesson as ram_bank_switch needing
; to run from RAM). ---
filename_buf     = $c900   ; DELETE/RENAME/CD/DLOAD/DSAVE's filename arg
filename2_buf    = $c920   ; RENAME's second (new) name
FILENAME_MAXLEN  = 16      ; real CBM DOS filename length limit
dir_buffer       = $c940   ; DIR's "$" directory-listing load target,
                            ; runs to $cfff (1728 bytes - comfortably
                            ; covers realistic directory sizes)

; --- DIR's per-entry name/type buffers (bank 10) - buffered rather
; than streamed straight to CHROUT so the entry's color (red ".BIN",
; green "PRG", white otherwise) can be decided before any of it is
; printed. Sits in misc_save_buf's otherwise-unused tail ($c800-$c8ff -
; only offsets 0-4 are ever used, for border/background/text color and
; cursor column/row), well clear of filename_buf at $c900. ---
dir_namebuf      = $c810   ; up to FILENAME_MAXLEN (16) bytes
dir_namebuf_len  = $c821
dir_typebuf      = $c822   ; up to 3 bytes (PRG/SEQ/USR/REL)
dir_typebuf_len  = $c826
dir_entry_color  = $c827
dir_name_has_dot = $c828   ; nonzero if the name already contains a "."
                            ; (e.g. "DRYER420PCT.BIN") - such names skip
                            ; the auto-appended ".TYPE" suffix, since
                            ; they already carry their own extension
