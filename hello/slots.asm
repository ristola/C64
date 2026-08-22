; Shared constants for the bank-switched build: the fixed-slot jump
; table layout, and the RAM addresses used by the resident kernel
; (resident.asm) and the cross-bank call mechanism. Included by both
; resident.asm and every bank's own content file - each bank is a
; separate ACME assembly that never sees another bank's labels, so
; anything that has to be agreed on across banks (slot numbering, RAM
; variable addresses) has to be a shared compile-time constant here,
; not a real address resolved from some other bank's code.

; --- Fixed-slot jump table: $8010 up to BANK_CONTENT_START (below),
; SLOT_COUNT slots x 4 bytes. Every bank reserves this same range at
; the same addresses; a bank only fills in the slots it actually
; implements, each with a plain "JMP <real address>" (3 bytes + 1 pad).
; resident.asm's dispatch tables store (bank, slot) pairs using these
; constants - never a raw label - since that's the only address that's
; guaranteed valid before the slot's own bank is even switched in. ---
; Resident kernel start - the boundary between bank-specific content
; ($8000-RESIDENT_START) and resident.asm (RESIDENT_START-$9FFF,
; identical in every bank - see resident.asm's own header for why).
; Widened four times now as resident.asm grew: 1024 -> 2048 -> 2112 ->
; 2240 -> 2248 bytes (this boundary: $9740 -> $9738 - DOWN, not up: this
; boundary is bank-content's ceiling and resident.asm's floor, so giving
; resident.asm more room means DECREASING this value, not increasing it
; - got this backwards on the first attempt, confirmed by the overflow
; growing from 2 to 10 bytes when tried the wrong direction first). The
; 8 bytes taken for that were for a since-removed "ShortTab" mechanism
; ($/%/back-arrow as bare single-byte tokens) that turned out to be
; unsafe at a much deeper level (see resident.asm's own note where
; EXTTOK/EXTFUNCTOK are defined) and was pulled back out entirely -
; resident.asm now has ~139 bytes of slack before $a000 at this same
; boundary value, deliberately left as-is (not narrowed back) rather
; than re-tune it yet again for a few dozen bytes of bank-content
; headroom nobody's asked for.
RESIDENT_START = $9738

SLOT_BASE = $8010
SLOT_SIZE = 4
SLOT_COUNT = 62              ; bumped from 61 when Bank 16's
                               ; SLOT_SPRITE_EDITOR_DISPATCH needed a
                               ; 62nd slot (see that constant's own
                               ; comment) - every bank content file's
                               ; own "!fill BANK_CONTENT_START-*, $ff" /
                               ; "*=BANK_CONTENT_START" pair picks this
                               ; up automatically, so bumping this one
                               ; constant is the whole change needed
                               ; next time a slot is added.
BANK_CONTENT_START = SLOT_BASE + SLOT_COUNT*SLOT_SIZE

SLOT_MENU_OPEN        = SLOT_BASE + 0*SLOT_SIZE  ; bank 14 - see that
                                                    ; bank's own comment
                                                    ; below; irq_hook
                                                    ; (resident.asm)
                                                    ; bank_calls here
                                                    ; with A=14, not 0
SLOT_CLS              = SLOT_BASE + 1*SLOT_SIZE  ; bank 1

; Slot 3 (gap between SLOT_CLS and SLOT_COLOR) used to hold a C=+RUN/
; STOP auto LOAD"*",8,1+RUN trigger - backed out after confirming live
; (hang, then separately confirmed memory corruption - CstopTypeCmd's
; own 16-character auto-type string overran the real 10-byte keyboard
; buffer into $0281-$0286, corrupting KERNAL variables including the
; current text color at $0286) that a 16-character string doesn't fit
; the keyboard-buffer-injection trick safely without a proper save/
; restore-on-drain mechanism this attempt didn't have. Gap left free
; again for whatever's next - see git history around this comment if
; picking the feature back up, with that fix designed in from the
; start next time.

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

; --- Boot splash one-time setup (bank 0) - tower_anim_start/jet_sprite
; live in bank0_content.asm now, not resident.asm: resident.asm has a
; hard ~2KB budget ($97C0-$9FFF) shared by every bank, and this is
; enough code+data that only ever runs once, at the exact moment
; cur_bank is still guaranteed 0 (right after cold boot, before any
; BASIC extension command could plausibly have run yet), to be worth
; reaching via a one-time bank_call from irq_hook instead of staying
; resident. jet_anim_tick itself (called every subsequent tick, when
; cur_bank could be anything) still has to stay resident - only the
; setup moved. jet_charset_setup/jet_bold_font moved again since, out
; to bank 14 (see SLOT_JET_CHARSET_SETUP below) - tower_anim_start's
; own jet_setup now reaches jet_charset_setup via a nested bank_call
; instead of a plain JSR. ---
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

; --- FastLoader (bank 13) - FastDload's own callable entry point, not
; a BASIC keyword itself: DloadCmd (bank 10) bank_calls into this slot
; instead of running KERNAL_LOAD directly. See bank13_content.asm's own
; header comment for why (skips KERNAL_LOAD's per-call overhead, same
; technique DirCmd already proved out for "$" listings). ---
SLOT_FASTDLOAD        = SLOT_BASE + 58*SLOT_SIZE  ; bank 13

; --- Cart Menu (bank 14) - originally just a home for the 2x-size
; title's 64 new character glyphs (512 bytes) once Bank 0 ran out of
; ROML headroom to hold them alongside everything else already there
; (common.asm/features.asm/bitmap.asm/spriteeditor.asm, plus the boot
; splash). Grew from "font data only" to "the whole F1 Cart Menu" the
; next time Bank 0 filled up again (adding the EXIT item + selection-
; pointer cursor): rather than keep rescuing one oversized piece of
; Bank 0 at a time into ad-hoc homes, common.asm (and everything it
; !source's - features.asm/bitmap.asm/spriteeditor.asm) moved here as a
; whole, leaving Bank 0 with just cart_start/the boot splash - see that
; file's own header comment. jet_charset_setup/jet_bold_font/jet_
; copyright_glyph moved here too, since menu_draw_title (common.asm)
; is jet_charset_setup's other caller and having both copies of that
; routine (one per caller's bank) would just be two things to keep in
; sync instead of one.
;
; This slot is jet_charset_setup's entry point for its ONE cross-bank
; caller - bank0_content.asm's jet_setup, reached via a nested bank_call
; (irq_hook already bank_called into bank 0 for tower_anim_start/JetCmd
; before jet_setup runs). menu_draw_title's own call is same-bank (both
; live in bank 14 now) and doesn't go through this slot at all - see
; jet_charset_setup_xbank's own comment (bank14_content.asm) for why
; the routine needs both a slot-table trampoline AND a plain-RTS entry
; point rather than just one or the other.
;
; Placed right after the FastLoader (still part of the protected
; "system" range, see FIRST_USER_BANK below) rather than tacked onto
; the end, so "bank >= FIRST_USER_BANK" stays a single, simple
; boundary check for any future flash-write tool - the previously-empty
; user-programmable banks shift up by one (14-19 -> 15-20) to make
; room; they had no real content to preserve either way. ---
SLOT_JET_CHARSET_SETUP = SLOT_BASE + 59*SLOT_SIZE  ; bank 14

; --- Menu Features (bank 15) - feat_sid_demo/feat_cia_monitor/feat_
; vic_viewer/feat_memory_viewer/feat_joystick_tester (features.asm,
; plus bitmap.asm which features.asm's own graphics demo calls into
; directly) split off from Bank 14 the moment it turned out common.asm
; + all those files together still didn't fit in one 8K bank even
; after Bank 0's jet_charset_setup moved in too - see bank14_content.
; asm's own header for the numbers. menu_dispatch_num/menu_diag_
; dispatch_num (common.asm) reach every feature here through this ONE
; slot rather than getting a slot each: num_val (already the shared
; "which item" variable both of those dispatch loops use) doubles as
; the argument, set to one of the FEAT_* constants below immediately
; before the bank_call, and feat_dispatch (bank15_content.asm) reads it
; back out to route to the right feat_* routine internally via a plain
; same-bank JSR (or, for FEAT_SPRITE_EDITOR specifically, a NESTED
; bank_call into Bank 16 - see SLOT_SPRITE_EDITOR_DISPATCH below for
; why that one's different). One slot now covers however many feature
; routines Bank 15 ends up holding, current or future, instead of
; needing a new slot (and touching every bank content file's own
; BANK_CONTENT_START boundary again) every time another one gets added.
SLOT_FEAT_DISPATCH    = SLOT_BASE + 60*SLOT_SIZE  ; bank 15

; --- Sprite Editor (bank 16) - relocated out of Bank 15 once the
; CARTRIDGE LAB port needed the room (see FIRST_USER_BANK's own comment
; below for the bank-numbering ripple this caused). Gets its OWN slot
; rather than folding into SLOT_FEAT_DISPATCH's shared-slot pattern:
; that pattern only works when the target bank is already Bank 15 (its
; own feat_dispatch does the internal same-bank routing) - a feature
; living in a genuinely different bank needs its own real bank_call
; target. feat_dispatch's own FEAT_SPRITE_EDITOR case (bank15_content.
; asm) does a nested bank_call here instead of a same-bank JSR;
; resident.asm's bank_call/bank_return are already reentrant/stack-
; based specifically so this kind of nesting is safe. ---
SLOT_SPRITE_EDITOR_DISPATCH = SLOT_BASE + 61*SLOT_SIZE  ; bank 16

; --- %FILENAME (ML load shortcut, bank 10 - same bank as DLOAD/DSAVE/
; DIR it sits alongside). Reuses slot 4, one of a handful of gaps left
; unlabeled between SLOT_COLOR(2)/SLOT_LOCATE(5), SLOT_JOYFIRE(25)/
; SLOT_DUMP(27), and SLOT_MOVE(29)/SLOT_FIND(31) - confirmed genuinely
; free via "grep -rn SLOT_BASE *.asm" outside this file returning
; nothing, meaning no bank content or dispatch table computes a raw
; slot address any way other than through these named constants, so an
; unlabeled gap really is unused, not silent reserved headroom. Chosen
; over a brand new slot past 59 (would have needed slot 62, the first
; one past $80FF - see OkExt/resident.asm's own hardcoded call_ptr+1=
; $80 assumption) purely for resident.asm's own tight budget: giving
; OkExt a real per-entry high-byte table (or even a single-slot special
; case) to handle one slot living on a different page cost more bytes
; than resident.asm had to spare; reusing an in-range gap needs neither. ---
SLOT_MLOAD             = SLOT_BASE + 4*SLOT_SIZE  ; bank 10

FEAT_SID              = 1
FEAT_SPRITE_EDITOR    = 2
FEAT_CIA              = 3
FEAT_VIC              = 4
FEAT_MEMORY           = 5
FEAT_JOYSTICK         = 6
FEAT_EPROM_DUMP       = 7
FEAT_READ_CHIP        = 8
FEAT_BACKUP_EPROM     = 9
FEAT_BANK_SCANNER     = 10  ; CARTRIDGE LAB - bank latch test, ported
                              ; from cartlab.asm's own do_bank_test
FEAT_VERIFY_EPROM     = 11  ; CARTRIDGE LAB - directory-picker verify,
                              ; ported from cartlab.asm's VERIFY/COMPARE
FEAT_LOAD_EPROM       = 12  ; CARTRIDGE LAB - directory-picker load,
                              ; ported from cartlab.asm's LOAD FILE TO RAM
FEAT_SEARCH_ROM       = 13  ; CARTRIDGE LAB - byte-pattern search across
                              ; every physical EPROM bank
;
; install_basic_ext itself does NOT get a slot - unlike menu_open (real
; per-bank content in Bank 14) or ClsCmd/HexCmd (real per-bank content
; in Bank 1), install_basic_ext only pokes $0304-$0309 with addresses of
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
fastload_enabled     = $037e   ; nonzero = DLOAD uses FastDload (bank 13);
                                ; zero = falls back to plain KERNAL_LOAD.
                                ; Set via the F1 Cart Menu's FastLoad
                                ; settings item (common.asm) - no BASIC
                                ; command for this, deliberately (an
                                ; earlier BASIC-command + boot-banner
                                ; version was built and then backed out;
                                ; see git history around this comment).
                                ; RAM only - survives a warm reset (NEW,
                                ; RUN/STOP+RESTORE) but NOT a real power
                                ; cycle or REBOOT, which both reinitialize
                                ; it back to enabled (cart_start) - true
                                ; persistence would need real flash-write
                                ; code, which doesn't exist anywhere in
                                ; this project yet and wasn't worth the
                                ; risk of a first-ever attempt just for
                                ; this toggle.
bank_call_depth      = $037d   ; how many bank_call visits are currently
                                ; nested (0 = none in progress) - separate
                                ; from cur_bank, which tracks WHICH bank is
                                ; resting/active, not WHETHER a dispatch is
                                ; mid-flight. irq_hook checks this (not
                                ; cur_bank) before running the jet
                                ; animation/F1 menu tick: cur_bank alone
                                ; used to double as "is anything unsafe to
                                ; interrupt happening", which meant BANK <n>
                                ; permanently resting somewhere other than 0
                                ; silently froze the animation forever, even
                                ; with nothing actually in progress. The
                                ; real hazard (confirmed live: a jiffy tick
                                ; landing while a nested bank_call was
                                ; genuinely active mid-KERNAL-disk-I/O
                                ; jammed EASYFLASH_BANK) only exists while a
                                ; call is truly in flight, which this
                                ; counts precisely - incremented in
                                ; bank_call, decremented in bank_return/
                                ; bank_return_basic/bank_commit (all four
                                ; below).

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

; --- feat_eprom_dump's own browse state (bank 15) - persists across
; SPACE/N page/bank advances for as long as that screen stays open, so
; it behaves like a real memory browser instead of resetting every
; keypress. Not zero page - no indirect addressing needed here either;
; the actual live read happens through rd_addr/rd_count (resident.asm,
; same physical bytes as features.asm's hd_addr/hd_count) once bank_call
; has switched the target bank in. ---
eprom_bank            = $03b7   ; which bank (0..TOTAL_BANKS-1) is shown
eprom_offset          = $03b8   ; 2 bytes: byte offset into that bank's
                                  ; own $8000-$9FFF window
eprom_read_done       = $03ba   ; 0 until CARTRIDGE LAB's READ CHIP
                                  ; (feat_read_chip) successfully
                                  ; captures a page - EPROM DUMP checks
                                  ; this before offering to browse, per
                                  ; the CARTRIDGE LAB workflow: read
                                  ; first, then dump what was read
pct_acc               = $03bb   ; 2 bytes: feat_backup_eprom's SAVE
                                  ; progress - an 8.8 fixed-point
                                  ; accumulator, not a plain percentage;
                                  ; same technique and reasoning as
                                  ; cartlab.asm's own pct_acc (standalone
                                  ; program, separate zero-page copy -
                                  ; this one isn't zero page since
                                  ; nothing here needs indirect
                                  ; addressing through it)
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

; Total number of banks actually built (0-21, see build_cart.sh's loop) -
; every one gets the full resident kernel regardless of whether it has
; real content yet (bank_driver.asm sources resident.asm unconditionally),
; so any of these is safe to switch to; anything >= this isn't - update
; here when adding another bank.
TOTAL_BANKS = 22

; --- How many banks the CURRENTLY INSTALLED chip actually has - a
; separate question from TOTAL_BANKS above, which is how many banks
; this firmware BUILD defines regardless of what chip it ends up on.
; feat_eprom_dump (features.asm) pages through this many banks, not
; TOTAL_BANKS: on the Phase 0 test board (docs/HARDWARE_PLATFORM.md)
; with its default 27C512 (64KB = exactly 8 banks of 8KB), the bank-
; select latch only has enough real address lines wired for 8 banks -
; paging past bank 7 doesn't reach new content, it just aliases/wraps
; back onto banks 0-7 again. Bump this (8/16/32/64) when a larger chip
; family is actually installed - see the board's own PIN1/PIN31/
; 28PIN-32PIN jumper table for which chip maps to which bank count. No
; way to auto-detect this from software: it depends on which physical
; chip and jumper setting is in the socket right now, not anything the
; C64 side can query (the JEDEC ID that could infer capacity needs 12V
; on A9 for classic 27Cxxx parts - see id_read_chip's own comment,
; features.asm - so it's a real UNKNOWN, not a detectable one, for
; exactly the chip family this constant most needs to be right for).
EPROM_PHYSICAL_BANKS = 8

; pct_acc's per-page step, in 8.8 fixed point: 100*256/(EPROM_PHYSICAL_
; BANKS*64 pages) - same formula and same "exact for 8/16, truncates for
; 32/64" caveat as cartlab.asm's own PCT_STEP (standalone program,
; separate constant - this is bank 15/features.asm's copy).
PCT_STEP = 25600/(EPROM_PHYSICAL_BANKS*64)

; First bank in the genuinely user-programmable range (games, utilities,
; ROM images, custom software - anything a user flashes themselves).
; Banks below this are the protected "system" range (boot/menu, all
; BASIC+ extension categories, the FastLoader, and - eventually - real
; flash-programming logic in bank 9, still stubbed for now): boot ROM
; (0), BASIC extensions (1-11), reserved for the later SERIAL plan (12),
; FastLoader (13), F1 Cart Menu (14), Menu Features (15), Sprite Editor
; (16 - moved here out of Bank 15 once the CARTRIDGE LAB port needed
; the room; kept contiguous with the rest of the system range rather
; than tacked onto the end, same "bank >= FIRST_USER_BANK" single-
; boundary reasoning as every earlier addition here). Bumped from 16 to
; 17 - the user-programmable range simply shrinks by one (17-21 instead
; of 16-21) rather than shifting every other user bank up again; unlike
; the last two times this boundary moved, none of 16-21 had real
; content to preserve, so there's nothing to renumber. This is a
; software-level convention only - EasyFlash's flash chip has no
; wired-up hardware write-protect pin - so it only means anything once
; real flash-write code exists (the still-stubbed CARTRIDGE LAB
; submenu, common.asm) and actually checks against it before writing;
; nothing enforces it yet.
FIRST_USER_BANK = 17

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

; FastDload's (bank 13) own success/failure report back to DloadCmd
; (bank 10) - not the carry flag, since bank_return's own PLA/STA
; sequence (resident.asm) doesn't guarantee carry survives back to the
; caller. 0 = ok, 1 = OPEN failed, 2 = CHKIN failed. Same "only one
; disk command ever runs at a time" reasoning as dir_namebuf etc. above
; makes this reuse-safe.
fastload_error   = $c829

; --- feat_eprom_dump's (bank 15) 128-byte page buffer - resident_copy_
; page (resident.asm) fills this from the target bank's own $8000-$9FFF
; window during a bank_call, since that window shows OUR content again
; the instant bank_return switches back to bank 15. Placed right after
; fastload_error rather than in scr_save_buf/col_save_buf/misc_save_buf's
; own window: unlike DISK's buffers above, this one is live WHILE the F1
; menu is open (it IS an F1 menu screen), the exact window where those
; three buffers hold real, in-use backup data - so it can't share their
; space the way RENUM_BUF safely does. $c82a-$c8ff is free either way
; (DISK commands, whose buffers start at $c900, can't run while the F1
; menu is open, so nothing else competes for it during this screen). ---
eprom_page_buf   = $c82a

; --- id_read_chip's (bank 15, features.asm) RAM landing spot for its
; copied JEDEC-unlock/ID-read routine - has to actually execute from
; RAM, not ROM: issuing the unlock sequence puts the WHOLE flash chip
; (this bank's own code included, since it's the same physical chip)
; into autoselect mode, where reads return ID bytes instead of normal
; instruction bytes, so the CPU can't safely keep fetching its own next
; opcode from $8000-$9FFF while that's happening - verified against
; EasyFlash's own real EAPI driver (eapi-am29f040.s, skoe.de), which
; copies its flash-write code to RAM at $DF80 for the same reason. Right
; after eprom_page_buf's 128 bytes ($c82a-$c8a9), still well clear of
; filename_buf at $c900 - same "F1 menu open, so DISK's buffers can't be
; live right now" reasoning eprom_page_buf's own comment already covers.
id_read_ram      = $c8aa

; --- feat_bank_scanner's (bank 15, features.asm) reference-row scratch -
; bank 0's own first 8 bytes, kept around to compare every later bank
; against. Same "$c82a-$c8ff free during the F1 menu" window eprom_
; page_buf/id_read_ram already use - placed at $c8f0, comfortably past
; id_read_ram's own ~39-byte copied routine (id_read_template) and
; still short of filename_buf at $c900. ---
bt_ref           = $c8f0

; --- VERIFY EPROM / LOAD EPROM TO RAM's (bank 15, features.asm) shared
; directory-picker state - same design as cartlab.asm's own lr_* (LOAD
; FILE TO RAM/VERIFY-COMPARE picker), ported here since the CARTRIDGE
; LAB port needed the same "pick a file from a real directory listing"
; UI. Reuses filename_buf/filename2_buf/dir_buffer's own $c900-$cfff
; window (1792 bytes) - safe on the same "F1 menu open, so DISK's
; buffers can't be live right now" grounds eprom_page_buf/id_read_ram
; already rely on. LR_MAX_FILES is smaller than cartlab.asm's own 64
; (24 here) purely to keep this window's footprint modest next to
; everything else already sharing it. ---
LR_RAW_BUF    = $c900        ; 1024 bytes: raw "$" directory listing
                                ; scratch, same purpose as DISK's own
                                ; dir_buffer (bank 10) - not shared with
                                ; it directly since bank 10 can't run
                                ; while the F1 menu (bank 15) is open,
                                ; but a distinct address avoids any
                                ; confusion between the two
LR_MAX_FILES  = 24
LR_ROWS       = 16           ; visible rows per screen page
LR_NAME_LEN   = 17            ; 16 chars (CBM DOS's own filename limit)
                                ; + 1 null terminator
LR_NAME_TABLE = $cd00         ; LR_MAX_FILES*LR_NAME_LEN = 408 bytes
LR_MODE_LOAD   = 0
LR_MODE_VERIFY = 1
lr_count      = $ce98
lr_cursor     = $ce99
lr_top        = $ce9a
lr_mode       = $ce9b
lr_fn_len     = $ce9c        ; selected entry's name length once copied
                                ; into filename_buf (reused directly for
                                ; this, same buffer DELETE/RENAME/CD/
                                ; DLOAD/DSAVE already use - F1-menu-safe
                                ; on the same grounds as everything else
                                ; in this window)
lr_rd_seen_header = $ce9d    ; lr_read_dir's own "have we skipped the
                                ; disk-name/ID header entry yet" flag
lr_del_cmd    = $ce9e         ; 18 bytes: "S:" (2) + up to 16 chars for
                                ; DEL's own S:name scratch command, same
                                ; layout as cartlab.asm's own lr_del_cmd -
                                ; still well clear of LR_NAME_TABLE's own
                                ; $cd00-$ce98 span and $cfff's own ceiling

; --- SEARCH ROM's (bank 15, features.asm) own scratch, same $c900-$cfff
; window and "F1 menu open" sharing rule as the picker's own state above
; - SEARCH ROM and the picker never run concurrently either. The typed
; hex-digit string itself reuses filename_buf/lr_fn_len directly (see
; feat_search_rom's own comment), so only the converted byte pattern
; needs a home here. ---
sr_pattern    = $ceb0         ; 8 bytes: converted search pattern
sr_pat_len    = $ceb8         ; pattern length in bytes (0 = cancelled)
sr_found      = $ceb9         ; nonzero once any match has been reported
sr_y_save     = $ceba         ; sr_byte_loop's own saved page-index (Y
                                ; gets clobbered by sr_try_match/sr_
                                ; report_match's own print_str calls)
