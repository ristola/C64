; Resident kernel - assembled byte-identically into every bank's image
; at a fixed address ($9C00), so it works correctly no matter which bank
; happens to be switched in when it's needed. Two things NEED that
; property and everything else here exists to support them:
;   - irq_hook, wired to $0314/$0315, must be reachable regardless of
;     what bank some earlier BASIC+ command left switched in.
;   - the BASIC-extension dispatcher (wired to $0304-$0309) must be
;     reachable whenever BASIC tokenizes or executes a line, which can
;     happen at any time, same reasoning.
; Bank-specific command bodies (menu_open in Bank 0, ClsCmd/HexCmd in
; Bank 1, and everything future banks add) are NOT here - they're
; reached through the fixed-slot jump table (slots.asm) via bank_call
; below, since this file is assembled separately per bank and can never
; reference another bank's labels directly.

; --- BASIC's own zero page, used here exactly as BASIC itself uses it
; (not our scratch - this is real, live BASIC interpreter state) ---
BAS_ENDCHAR = $08
BAS_COUNT   = $0b
BAS_VALTYP  = $0d
BAS_GARBFL  = $0f
BAS_FORPNT  = $49
BAS_FBUFPT  = $71
BAS_CHRGET  = $73        ; JSR: get next char, advance TXTPTR
BAS_CHRGOT  = $79        ; JSR: re-get current char, don't advance
BAS_TXTPTR  = $7a

; --- fixed BASIC ROM entry points ---
BAS_RESLST   = $a09e     ; stock keyword table (for the tokenizer)
BAS_NEWSTT   = $a7ae     ; resume BASIC's statement loop after a command
BAS_EXECOLD  = $a7ed     ; hand a not-ours token back to stock execution

; --- fixed BASIC token values / addresses used by the tokenizer port ---
BTOK_DATA = $83
BTOK_REM  = $8f
BTOK_PRINT= $99
CHR_QUOTE = $22
LINE_BUF  = $0200        ; where BASIC assembles a typed line before crunching

; --- our new tokens: $CC upward, same free range Simons' BASIC etc.
; used (stock BASIC V2 never assigns tokens past the low $Cx area) ---
CMDSTART = $cc
CMDEND   = $cc           ; CLS=$cc only - the direct single-byte token
                          ; mechanism from Phase 1, kept exactly as-is to
                          ; avoid any regression risk to already-verified
                          ; code. HEX used to be $cd here too, but is
                          ; retired now that HEX$ exists as a proper
                          ; string function (extended token below) -
                          ; freed back up rather than left reserved.

; --- Extended-command escape: BASIC's single-byte token encoding only
; allows 51 new tokens total ($CC-$FE - $FF is a hardcoded sentinel in
; ConvertFromTokens below, and breaks the CMDEND+1 range-check arithmetic
; if used), nowhere near enough for the full N4LDR BASIC+ command
; roadmap. EXTTOK is ONE reserved token that means "an extended command
; follows" - the ACTUAL command is identified by a second byte (a 1-based
; index into ExtTab/ExtBankTab/ExtSlotLoTab below), giving up to 255
; extended commands total instead of 51. CLS/HEX keep their direct
; tokens; every later category (SCREEN's new commands onward) uses this
; mechanism instead. EXTFUNCTOK is the same idea for FUNCTIONS (used
; inside expressions, dispatched via IEVAL below) - a genuinely separate
; token, not just a separate table sharing EXTTOK's index space: LIST
; needs to know, from the token byte alone, whether the follow-up index
; belongs to ExtTab or ExtFuncTab, and a shared 1-based counter across
; two tables would also misindex whichever table doesn't own a given
; entry (hit exactly this bug empirically - a statement-only entry
; ahead of a function-only one in a shared counter made the function
; read one byte past its own 1-entry table, picking up unrelated data
; from the next table in memory and crashing). Two independent tokens
; with two independent 1-based counters avoids both problems. ---
EXTTOK     = $ce
EXTFUNCTOK = $cf

; ============================================================
; Cross-bank call mechanism
; ============================================================

; Switch to bank A, then jump to the address in call_ptr (set by the
; caller beforehand). The old bank goes on the CPU stack, not a side
; variable - that's what makes this correctly reentrant if an IRQ lands
; mid-call and itself needs a nested bank_call (e.g. F1 firing while
; some bank is switched in for an unrelated BASIC+ command): each level
; unwinds in the right order for free, no extra bookkeeping.
; No PHP/PLP here: the old-bank byte PHA pushes below has to survive on
; the stack until bank_return/bank_return_basic pops it, long after this
; routine is gone - a PHP...PLP pair wrapped around that same push would
; have to pop in LIFO order too, i.e. PLP would retrieve the old-bank
; byte instead of the flags it saved, corrupting P with whatever bit
; pattern the bank number happens to be (0 or 1 both clear the I flag,
; silently re-enabling interrupts) while orphaning the real saved flags
; byte on the stack for bank_return[_basic]'s own PLA to misread as the
; old bank instead - confirmed live as the actual cause of the
; supposedly-already-fixed JAM-at-$A005 crash (verified via VICE's
; remote monitor: SEI held for the whole OkNew visit was getting undone
; right here). Both call sites (irq_hook, OkNew) already CLI/SEI exactly
; how they want around their own bank_call/bank_return round trip, so
; there was never anything for this to usefully save in the first place.
bank_call
        sta     bank_tmp
        lda     cur_bank
        sta     resting_bank    ; stash a readable copy of the bank BASIC
                                 ; was actually resting on before this call
                                 ; - cur_bank itself is about to become the
                                 ; TARGET bank, so anything the target
                                 ; command runs (e.g. CARTINFO reading
                                 ; "current bank") would otherwise always
                                 ; see its own bank instead of the real one
        pha
        lda     bank_tmp        ; A was clobbered by "lda cur_bank" above -
        sta     cur_bank        ; reload the real target bank before this
        jsr     ram_bank_switch ; does the actual $DE00 write from RAM -
                                 ; see slots.asm's ram_bank_switch comment
                                 ; for why it can't happen from here
        jmp     (call_ptr)

; Ordinary "JSR bank_call ... RTS" return - pops the old bank pushed
; above, restores it, and RTS resumes whoever JSR'd bank_call.
bank_return
        pla
        sta     bank_tmp
        sta     cur_bank
        jsr     ram_bank_switch
        rts

; For BASIC+ command bodies: the "caller" is BASIC's own statement loop,
; not a JSR we can RTS back into, so resume there directly instead. Pairs
; with OkNew's SEI below: a jiffy IRQ landing while a non-zero bank was
; switched in was empirically confirmed to crash (JAM inside BASIC ROM,
; nowhere near anything this dispatch touches - holding interrupts off
; for the entire Bank 1 visit was the fix, not just narrowing bank_call/
; bank_return_basic's own brief critical sections, which still left gaps
; a jiffy IRQ could land in). Re-enable here, once we're safely back on
; bank 0, before resuming BASIC (which needs its jiffy IRQ running).
bank_return_basic
        pla
        sta     bank_tmp
        sta     cur_bank
        jsr     ram_bank_switch
        cli
        jmp     BAS_NEWSTT

; For BANK <n>: permanently changes which bank BASIC rests on, rather
; than a transient bank_call/bank_return_basic round trip that would
; just restore the OLD resting bank right back (which is exactly what
; happened the first time BankCmd tried to "sta cur_bank / jsr
; ram_bank_switch / jmp bank_return_basic" itself: bank_return_basic's
; own PLA pops the bank OkExt's bank_call pushed - e.g. 0 - and
; restores THAT, silently undoing the switch to whatever bank the user
; asked for). A/Y = the new bank BankCmd already validated. Must be
; resident (not called from bank-specific content) for the exact same
; reason ram_bank_switch itself has to run from RAM, not ROM: a
; bank-specific caller doing its OWN "jsr ram_bank_switch" would have
; the $8000-$9FFF window change out from under its own next instruction
; fetch mid-flight, executing garbage from whatever bank just became
; active instead of its own code - confirmed live as the actual cause
; of a "?SYNTAX ERROR" from typing BANK 3 (traced to a JMP ($0300)
; error dispatch with garbage in X, not a real BASIC parse error at
; all). Tail-jumping into resident code first, THEN switching, keeps
; every subsequent instruction fetch inside the byte-identical resident
; region regardless of which bank just became active - same reasoning
; bank_call/bank_return_basic already rely on.
bank_commit
        sta     cur_bank
        sta     bank_tmp
        jsr     ram_bank_switch
        pla                     ; discard the old resting bank OkExt's
                                 ; bank_call pushed - we're deliberately
                                 ; NOT restoring it, unlike bank_return_basic
        cli
        jmp     BAS_NEWSTT

; For DLOAD only: a successful load replaces the current BASIC program,
; so - unlike every other command - resuming BASIC's ordinary statement
; loop (BAS_NEWSTT) is wrong; there is no "next statement" of a program
; that no longer exists in memory the same way. Real stock LOAD, traced
; live in VICE (breakpoints at $FFD5's call site and its continuation at
; $E178, verified against real BASIC ROM disassembly, not guessed) does
; exactly three things after a successful KERNAL LOAD: set VARTAB ($2D/
; $2E) to the load's returned end address, then JSR $A659 (reset arrays/
; strings), JSR $A533 (recompute STREND/FRETOP from the now-current
; program), then JMP $A480 (BASIC's real post-LOAD continuation, which
; prints READY. and waits) - not BAS_NEWSTT, which is a different entry
; point for resuming an in-progress statement, not for "a whole new
; program just replaced the old one." DLOAD's own command body
; (bank10_content.asm) does the "stx $2D / sty $2E" itself (using the
; end address KERNAL LOAD left in X/Y) since that's a plain zero-page
; write, safe from any bank - this routine only does the part that MUST
; run from resident code: restoring bank 0 before touching any of $A480
; onward, exactly like bank_return_basic's own restore.
bank_return_load
        pla
        sta     bank_tmp
        sta     cur_bank
        jsr     ram_bank_switch
        cli
        jsr     $a659
        jsr     $a533
        jmp     $a480

; Template for the RAM bank-switch trampoline (see slots.asm's
; ram_bank_switch for why this has to run from RAM, not from here).
; Copied into place at $0380 once, by cart_start - Bank 0 is the only
; bank that ever runs at hardware reset, so that's the only place this
; needs to happen.
ram_bank_switch_template
        lda     bank_tmp
        sta     EASYFLASH_BANK
        rts
ram_bank_switch_template_end

; ============================================================
; BASIC extension install
; ============================================================

; Only pokes addresses of routines in THIS file, which sit at the same
; place in every bank - so unlike menu_open/ClsCmd/HexCmd, this needs no
; bank_call, just a plain JSR from irq_hook like any other resident-to-
; resident call.
install_basic_ext
        lda     #<ConvertToTokens
        sta     $0304
        lda     #>ConvertToTokens
        sta     $0305
        lda     #<ConvertFromTokens
        sta     $0306
        lda     #>ConvertFromTokens
        sta     $0307
        lda     #<ExecuteCommand
        sta     $0308
        lda     #>ExecuteCommand
        sta     $0309
        lda     #<EvaluateFunction
        sta     $030a
        lda     #>EvaluateFunction
        sta     $030b

; Relabel BASIC's own cold-start banner, "**** COMMODORE 64 BASIC V2
; ****", from V2 to HAM (SHACKMATE's ham-radio branding standing in for
; the version marker) - verified against a real, unmodified boot's
; actual screen RAM contents (not guessed): "V2" sits at screen offset
; $0444/$0445, with a space at $0446 before the closing "****" that
; "HAM" (one character longer than "V2") absorbs, so nothing after it
; needs to shift. Only safe to do here, this long after cart_start's
; jmp ($a000) - BASIC's own cold start prints this banner as part of
; that jump and would just overwrite the change if done any earlier.
        lda     #$08        ; screen code 'H'
        sta     $0444
        lda     #$01        ; screen code 'A'
        sta     $0445
        lda     #$0d        ; screen code 'M'
        sta     $0446
        rts

; Prints " NOT YET IMPLEMENTED" + newline - the common tail every
; category's placeholder command body prints after its own name. Each
; stub prints its own name first via a tiny inline loop using its own
; compile-time-fixed address (NOT a shared routine taking a runtime
; pointer): $8000-$9FFF is EasyFlash ROM, not RAM, so a shared routine
; can't take a pointer via a self-modified LDA operand or be handed one
; through zero page either (this project's whole $02-$38 zero-page
; range is already claimed - see slots.asm's zp_save_len comment).
; Confirmed empirically: an earlier version of this routine self-
; patched its own "LDA $nnnn,Y" operand from A/Y, and a live breakpoint
; right at that instruction showed the operand still reading the
; unpatched placeholder - the STA into ROM silently did nothing. Only
; the tail (this part) needs to be shared, since it's fixed text with
; no argument - reading ROM works fine, only writing to it doesn't.
print_stub_suffix
        ldx     #0
print_stub_suffix_loop
        lda     stub_suffix,x
        beq     print_stub_suffix_done
        jsr     $ffd2
        inx
        bne     print_stub_suffix_loop
print_stub_suffix_done
        rts
stub_suffix
        !text   " NOT YET IMPLEMENTED"
        !byte   13, 0

; Prints a 16-bit value (A=low, X=high) as decimal, no leading zeros (a
; value of exactly zero still prints a single "0"). 6502 has no divide
; instruction, so this repeatedly subtracts each power of ten a 16-bit
; value can have (up to 65535) from a small table, counting how many
; times each subtracts cleanly - the same idea as a manual long
; division, just widened from bank6_content.asm's original divide-by-10
; single-digit version (promoted here once bank 10's DIR also needed
; decimal printing, for file sizes that can run past 99 blocks - not
; worth a second copy). Callers with an 8-bit value (bank numbers etc.)
; just pass X=0.
print_decimal_word
        sta     pdw_lo
        stx     pdw_hi
        lda     #0
        sta     pdw_started
        ldx     #0
pdw_digit
        lda     #0
        sta     pdw_count
pdw_sub
        lda     pdw_lo
        sec
        sbc     pow10_lo,x
        tay
        lda     pdw_hi
        sbc     pow10_hi,x
        bcc     pdw_digit_done  ; borrow occurred - can't subtract again
        sty     pdw_lo
        sta     pdw_hi
        inc     pdw_count
        jmp     pdw_sub
pdw_digit_done
        cpx     #4
        beq     pdw_force       ; ones place: always prints, never suppressed
        lda     pdw_count
        bne     pdw_force       ; nonzero digit: print it, and mark "started"
        lda     pdw_started
        beq     pdw_skip        ; leading zero, nothing real printed yet
pdw_force
        lda     #1
        sta     pdw_started
        lda     pdw_count
        clc
        adc     #'0'
        jsr     $ffd2
pdw_skip
        inx
        cpx     #5
        bne     pdw_digit
        rts

pow10_lo
        !byte   <10000, <1000, <100, <10, <1
pow10_hi
        !byte   >10000, >1000, >100, >10, >1

; --- Execute: BASIC's statement loop lands here (via the IGONE vector)
; whenever it meets a token it doesn't recognize itself. CHRGET fetches
; that token; if it's in our range, look up which bank implements it and
; bank_call into that bank's fixed slot (CHRGET first, so the command
; body starts with TXTPTR already advanced past its own token, same as
; the original single-bank version). Anything outside our range
; re-fetches the token (CHRGOT, since CHRGET already consumed it) and
; falls through to the real BASIC dispatcher unchanged - that fallback
; is what keeps every existing BASIC keyword working. ---
ExecuteCommand
        jsr     BAS_CHRGET
        jmp     TestCmd         ; JMP, not JSR - neither of TestCmd's own
                                 ; branches ever returns here (OldCmd jumps
                                 ; into BAS_EXECOLD, OkNew jumps into
                                 ; bank_call, which reaches BASIC again via
                                 ; bank_return_basic's own JMP BAS_NEWSTT
                                 ; further down the chain) - a JSR here
                                 ; would leave this return address stranded
                                 ; on the stack forever, the same class of
                                 ; leak just one level up from the
                                 ; jsr/jmp bank_call fix below.
TestCmd
        cmp     #CMDSTART
        bcc     OldCmd
        cmp     #CMDEND+1
        bcc     OkNew
        cmp     #EXTTOK
        beq     OkExt
OldCmd
        jsr     BAS_CHRGOT
        jmp     BAS_EXECOLD
OkNew
        sei                     ; Hold interrupts off for the entire Bank 1
                                 ; visit, not just bank_call/bank_return_
                                 ; basic's own brief critical sections - a
                                 ; jiffy IRQ landing while a non-zero bank
                                 ; is switched in crashed empirically (JAM
                                 ; inside BASIC ROM), even though irq_hook
                                 ; itself is resident/bank-independent.
                                 ; BASIC+ command bodies are quick, atomic
                                 ; operations that don't need reentrancy
                                 ; the way menu_open's GETIN-driven UI loop
                                 ; does (that path deliberately keeps
                                 ; interrupts on throughout, and targets
                                 ; bank 0 - the normal resting bank - not a
                                 ; problem there), so there's no downside
                                 ; to just holding them off for this whole,
                                 ; brief round trip. bank_return_basic
                                 ; re-enables once safely back on bank 0.
        sec
        sbc     #CMDSTART       ; A = token index (0-based)
        tax
        lda     CmdSlotLoTab,x
        sta     call_ptr
        lda     #$80            ; every slot lives in $8010-$80FF
        sta     call_ptr+1
        lda     CmdBankTab,x
        pha
        jsr     BAS_CHRGET
        pla
        jmp     bank_call       ; JMP, not JSR - the command body ends via
                                 ; bank_return_basic, which resumes BASIC
                                 ; directly (JMP BAS_NEWSTT) and never
                                 ; comes back here, so there must be no
                                 ; return address pushed for it to abandon.
                                 ; A JSR here left one stray byte on the
                                 ; stack per command, silently corrupting
                                 ; whatever RTS ran next - that's what was
                                 ; actually behind "CLS reopens the menu"
                                 ; and "HEX locks up": two different
                                 ; garbage jump targets from the same bug.

; one bank number and one slot address per token, in token order
; starting at CMDSTART (index 0 = CLS = $CC, the only direct token now).
CmdBankTab
        !byte   1               ; CLS  -> bank 1
CmdSlotLoTab
        !byte   <SLOT_CLS

; Extended-command dispatch: ExecuteCommand's initial CHRGET already
; consumed EXTTOK itself (that's what TestCmd just matched); one more
; CHRGET both fetches the follow-up index byte's value (1-based, set by
; ConvertToTokens/ExtTab below) AND advances TXTPTR past it, then a
; second CHRGET (mirroring OkNew's own extra one) advances TXTPTR past
; that index byte too, landing at the command's real arguments - same
; shape as OkNew, just one extra byte to consume since the "which
; command" information lives in a second byte instead of being baked
; into the token value itself.
OkExt
        sei
        jsr     BAS_CHRGET      ; A = index byte (1-based)
        sec
        sbc     #1              ; 0-based for table indexing
        tax
        lda     ExtSlotLoTab,x
        sta     call_ptr
        lda     #$80
        sta     call_ptr+1
        lda     ExtBankTab,x
        pha
        jsr     BAS_CHRGET
        pla
        jmp     bank_call

; One bank number and one slot address per extended command, in the
; same order as ExtTab below (index 0 = first ExtTab entry = index byte
; value 1, etc.). Real command bodies are stubs ("NOT YET IMPLEMENTED")
; until each category's actual logic gets built out - see the plan's
; bank map for why each category lives where it does.
; NOTE on ordering: whenever one command name is a prefix of another
; (SPRITEON/SPRITEOFF/SPRITECOLOR all start with SPRITE; BANKS starts
; with BANK), the LONGER name(s) must come first in both this table and
; ExtTab below - the matcher (same shape as ConvertToTokens' NewTab
; search) treats a full match against whatever's tried first as
; complete, so if the shorter "SPRITE" were tried before "SPRITEON",
; typing SPRITEON would tokenize as SPRITE followed by a dangling,
; separately-parsed "ON" (which even happens to itself be a real stock
; BASIC keyword - ON GOTO/ON GOSUB - making the resulting syntax error
; confusing rather than obvious).
ExtBankTab
        !byte   1, 1, 1, 1, 1, 1        ; COLOR BORDER BACKGROUND LOCATE PRINTAT HELP
        !byte   2, 2, 2, 2, 2, 2, 2, 2  ; HIRES MULTI TEXT PLOT LINE BOX CIRCLE PAINT
        !byte   3, 3, 3, 3              ; SPRITEON SPRITEOFF SPRITECOLOR SPRITE
        !byte   5, 5, 5, 5              ; DOKE DUMP FILL MOVE
        !byte   6, 6, 6                 ; CARTINFO BANKS BANK
        !byte   8, 8, 8, 8, 8           ; SOUND VOLUME WAVE ADSR FILTER
        !byte   9, 9, 9                 ; FLASHERASE FLASHLOAD FLASHVERIFY
        !byte   10, 10, 10, 10, 10, 10, 10 ; DIR DEVICE CD DELETE RENAME DLOAD DSAVE
        !byte   11, 11                  ; HTTPGET TELNET
        !byte   0                       ; JET - replays the boot flyby;
                                          ; bank 0, same bank menu_open
                                          ; lives in (see slots.asm's
                                          ; SLOT_JET comment)
        !byte   0                       ; REBOOT - real hardware reset,
                                          ; bank 0 (trivial, no real bank
                                          ; dependency either way)
ExtSlotLoTab
        !byte   <SLOT_COLOR, <SLOT_BORDER, <SLOT_BACKGROUND
        !byte   <SLOT_LOCATE, <SLOT_PRINTAT, <SLOT_HELP
        !byte   <SLOT_HIRES, <SLOT_MULTI, <SLOT_TEXT, <SLOT_PLOT
        !byte   <SLOT_LINE, <SLOT_BOX, <SLOT_CIRCLE, <SLOT_PAINT
        !byte   <SLOT_SPRITEON, <SLOT_SPRITEOFF, <SLOT_SPRITECOLOR, <SLOT_SPRITE
        !byte   <SLOT_DOKE, <SLOT_DUMP, <SLOT_FILL, <SLOT_MOVE
        !byte   <SLOT_CARTINFO, <SLOT_BANKS, <SLOT_BANK
        !byte   <SLOT_SOUND, <SLOT_VOLUME, <SLOT_WAVE, <SLOT_ADSR, <SLOT_FILTER
        !byte   <SLOT_FLASHERASE, <SLOT_FLASHLOAD, <SLOT_FLASHVERIFY
        !byte   <SLOT_DIR, <SLOT_DEVICE, <SLOT_CD, <SLOT_DELETE
        !byte   <SLOT_RENAME, <SLOT_DLOAD, <SLOT_DSAVE
        !byte   <SLOT_HTTPGET, <SLOT_TELNET
        !byte   <SLOT_JET
        !byte   <SLOT_REBOOT

; ============================================================
; Extended-function dispatch (IEVAL, $030A/$030B)
; ============================================================

; BASIC's real expression evaluator (FRMEVL, $AD9E - verified by direct
; disassembly of BASIC ROM in live VICE, not guessed) calls through this
; vector via "JSR $AE83" / "JMP ($030A)" for EVERY term it evaluates,
; not just unrecognized ones - the stock default ($AE86, confirmed via
; reading $0300-$030B's real reset-time contents) handles numbers,
; variables, and stock functions. Since $AE83 reaches us via JSR then
; JMP (a tail call into whatever we install here), we must eventually
; RTS back up through FRMEVL's own call chain ourselves - unlike
; ExecuteCommand's statement path (which resumes BASIC's statement loop
; directly via JMP BAS_NEWSTT and never returns), a function has to
; behave like an ordinary subroutine call that leaves a result behind.
;
; CHRGOT peek first: FRMEVL's own prologue does "DEC TXTPTR" then calls
; straight into this vector, so TXTPTR can be sitting on a space (the
; one right before the real token, since whatever chrget the CALLER
; last did already auto-skipped past it, and DEC rewinds exactly one
; position - straight back onto that same space). CHRGOT's own internal
; logic silently skips past any such space(s) to the next real character
; - that's fine and necessary here, since it's the ONLY way to see past
; the space to check for our own escape token at all (a raw, non-
; skipping peek would see the space and never recognize a function call
; with a leading space as ours - this was tried and would have broken
; the already-working XNUM case). What actually matters is what happens
; on the "not ours" path below.
;
; If it IS ours: consume EXTTOK and the follow-up index byte (same
; shape as OkExt), then JSR (not JMP) into the target bank - the target
; function body ends via bank_return (a plain RTS-based return, NOT
; bank_return_basic's JMP BAS_NEWSTT, since we're not resuming a
; statement loop here) leaving its result in func_result_hi/lo. Once
; back here (right after the JSR, exactly like any ordinary subroutine
; return - bank_call's old-bank byte and this JSR's own return address
; share the same stack in the correct LIFO order, verified against how
; bank_return already works for irq_hook's JSR-based menu_open call),
; $B391 (BASIC ROM's real "build FAC1 from a 16-bit unsigned integer,
; A=high Y=low" routine - found by setting a breakpoint there in live
; VICE and running PRINT PEEK(1), confirming A=0/Y=$37 matched memory
; address 1's real value $37) constructs the numeric result and RTS's
; the rest of the way back up through FRMEVL to whoever's evaluating
; the surrounding expression.
EvaluateFunction
        ldy     #0
        lda     (BAS_TXTPTR),y  ; raw, side-effect-free peek at whatever
                                 ; TXTPTR points at BEFORE our own CHRGOT
                                 ; below - remembers whether it was a
                                 ; space, needed by OldEval below to know
                                 ; whether CHRGOT actually advanced
                                 ; anything (see that comment for why).
        pha
        jsr     BAS_CHRGOT
        cmp     #EXTFUNCTOK
        bne     OldEval
        pla                     ; ours - the saved peek isn't needed
        sei                     ; same hazard OkNew already hit: a jiffy
                                 ; IRQ landing while a non-zero bank is
                                 ; switched in crashed empirically (JAM),
                                 ; even with bank_call/bank_return's own
                                 ; stack-based reentrancy - hold interrupts
                                 ; off for this whole round trip too, not
                                 ; just the statement-dispatch path.
        jsr     BAS_CHRGET      ; A = index byte (1-based)
        sec
        sbc     #1
        tax
        lda     ExtFuncSlotLoTab,x
        sta     call_ptr
        lda     #$80
        sta     call_ptr+1
        lda     ExtFuncBankTab,x
        pha
        jsr     BAS_CHRGET      ; advance past the index byte
        lda     #0
        sta     func_is_string  ; default: numeric result via func_result_
                                 ; hi/lo + $B391 below, unless the target
                                 ; function marks otherwise (see below) -
                                 ; centralized here so every existing
                                 ; numeric stub (JOY*, DEEK, FIND, etc.)
                                 ; needs no change of its own to keep
                                 ; working exactly as before.
        pla
        jsr     bank_call       ; JSR, not JMP - resumes right here once
                                 ; the target function's bank_return RTS's
        cli                     ; safely back on bank 0 - re-enable before
                                 ; handing back to FRMEVL, which needs the
                                 ; jiffy IRQ running for the rest of
                                 ; whatever expression/statement this was
        lda     func_is_string  ; nonzero: the target function is a real
                                 ; string function (HEX$/DEC$ - see bank
                                 ; 5) that already finished its OWN result
                                 ; before returning - real BASIC string
                                 ; results aren't built from func_result_
                                 ; hi/lo + $B391 (that's FAC1, numeric-
                                 ; only); they need VALTYP=$FF plus a
                                 ; proper string descriptor, which only
                                 ; $B47D (allocate)/$B4CA (finalize) know
                                 ; how to build correctly (traced live
                                 ; from BASIC ROM's own CHR$) - so the
                                 ; function body does that part itself,
                                 ; and there's nothing left to do here.
        bne     EvalFuncDone
        lda     func_result_hi
        ldy     func_result_lo
        jmp     $b391           ; build FAC1 and return to FRMEVL's caller
EvalFuncDone
        rts                     ; string result already finalized by the
                                 ; function body - just unwind back to
                                 ; whoever originally JSR'd into $AE83,
                                 ; exactly like $B391's own tail RTS does
                                 ; for the numeric case above.
; Not ours - but simply "jmp $ae86" (the obvious fallback) is wrong:
; $AE86 immediately does its OWN "JSR $0073" (CHRGET, WITH advance) as
; its first action, expecting to find TXTPTR sitting at the untouched,
; just-rewound position FRMEVL left it at. Our OWN CHRGOT above already
; consumed that position (that's the whole point - it's the only way
; to see past a leading space to check for our escape token), so $AE86
; doing its own CHRGET on top advances a SECOND time, skipping the real
; character entirely - confirmed live by tracing "BANK 3" instruction
; by instruction: CHRGOT above correctly read '3', but $AE86's own
; follow-up CHRGET then read the null statement-terminator right after
; it instead, producing a "?SYNTAX ERROR" that had nothing to do with
; BANK's own dispatch (reached correctly) or its argument being invalid
; - it was this vector quietly eating the argument before the real
; evaluator ever saw it. The original fix assumed CHRGOT above is
; ALWAYS idempotent (never advances further) once TXTPTR already sits
; on a real character - true when reached via FRMEVL's normal calling
; convention (which rewinds TXTPTR by one first, onto a space, so our
; CHRGOT's own space-skip supplies the "one CHRGET" of advancement
; $AE86 needs). But NOT every caller of this vector rewinds first -
; confirmed live by tracing "PRINT"HI"" (no space before the quote):
; IEVAL fires here with TXTPTR sitting DIRECTLY on the just-dispatched
; PRINT token itself, no leading space to skip, so CHRGOT really is a
; pure no-op peek that whole time - jumping to $AE8D then left TXTPTR
; completely unadvanced, and the quote-handling code at $AEB9 ended up
; re-examining the PRINT token instead of the character after it,
; producing a "?SYNTAX ERROR" for what should have been a perfectly
; valid quoted string. The raw pre-CHRGOT peek above (pushed to the
; stack) tells us which case we're in: if it WAS a space, CHRGOT's
; skip already did the necessary advancing and a plain re-peek here is
; correct (as before); if it WASN'T, CHRGOT never moved anything and we
; still owe $AE86's own real, advancing CHRGET before jumping to $AE8D.
OldEval
        pla                     ; A = the character TXTPTR pointed at
                                 ; before EvaluateFunction's own CHRGOT
        cmp     #' '
        beq     OldEvalHadSpace
        lda     #$00
        sta     BAS_VALTYP      ; matches $AE86/$AE88's own "assume
                                 ; numeric until proven otherwise" setup
        jsr     BAS_CHRGET      ; real advance - CHRGOT above was a
                                 ; genuine no-op peek, so this is the
                                 ; ONE advance $AE86 itself would do
        jmp     $ae8d
OldEvalHadSpace
        lda     #$00
        sta     BAS_VALTYP
        jsr     BAS_CHRGOT      ; idempotent re-read - CHRGOT above
                                 ; already skipped the space(s), giving
                                 ; the same net advancement a real
                                 ; CHRGET would have
        jmp     $ae8d           ; resume right after $AE86's own CHRGET,
                                 ; reusing ours instead of doing it twice

; One bank number and one slot address per extended function, in the
; same order as ExtFuncTab above (index 0 = ExtFuncTab's first entry,
; matching ExtFuncTab's own independent 1-based counter minus 1 - NOT
; ExtTab's counter, which is why this needed to be a fully separate
; token/table pair rather than sharing ExtTab's index space). HEX$/DEC$
; are stubbed via the plain numeric-result path (func_result_hi/lo +
; $B391) for now, not real string results yet - see their own bank 5
; comments for why.
; Same prefix-ordering rule as ExtBankTab: JOYUP/JOYDOWN/JOYLEFT/
; JOYRIGHT/JOYFIRE must all be tried before plain JOY.
ExtFuncBankTab
        !byte   4, 4, 4, 4, 4, 4   ; JOYUP JOYDOWN JOYLEFT JOYRIGHT JOYFIRE JOY
        !byte   5, 5, 5, 5         ; DEEK FIND HEX$ DEC$
ExtFuncSlotLoTab
        !byte   <SLOT_JOYUP, <SLOT_JOYDOWN, <SLOT_JOYLEFT
        !byte   <SLOT_JOYRIGHT, <SLOT_JOYFIRE, <SLOT_JOY
        !byte   <SLOT_DEEK, <SLOT_FIND, <SLOT_HEXDOLLAR, <SLOT_DECDOLLAR

; ============================================================
; F1 watcher, wedged into the jiffy IRQ (~60Hz) via $0314/$0315
; ============================================================
; f1_state debounces: 0 = idle, 1 = latched (already opened the menu for
; this press, waiting for release before it can retrigger).
;
; On a fresh press, wait for the physical key to come back up before
; doing anything else, while interrupts are still off. This matters
; because $EA31 (the default handler we tail-chain to below) does its
; own fully independent keyboard matrix scan every tick and buffers
; whatever it finds - it has no idea F1 doubles as a hotkey here, so if
; interrupts went straight to CLI + menu_open while the key was still
; physically down, later nested ticks would let $EA31 queue F1's normal
; PETSCII code ($85) into the KERNAL keyboard buffer same as any other
; key, and menu_open's very first GETIN would read it back and dispatch
; straight to the Help stub. Holding SEI through the release wait blocks
; $EA31 entirely, so nothing gets buffered in the first place; draining
; GETIN afterward is just a belt-and-suspenders flush for anything else
; that snuck in.
;
; Once clear, this CLIs and bank_calls into Bank 0's menu_open - blocks
; on GETIN, which only ever fills up because the jiffy IRQ keeps firing,
; so interrupts must stay enabled while it runs (this makes the handler
; reentrant: further jiffy IRQs nest on top of it via the fast path
; below, each one tail-chaining into $EA31 and returning normally, so
; the keyboard buffer, jiffy clock etc. all keep working exactly as they
; would in BASIC - and if one of those nested ticks takes the F1 slow
; path itself, its own nested bank_call unwinds correctly against this
; one because the old bank lives on the CPU stack). save_screen/
; restore_screen and zp_save/zp_restore bracket the call so neither the
; menu's screen nor its zero-page scratch leak into whatever BASIC had
; going. menu_open only returns (via bank_return) when the user backs
; all the way out with RUN/STOP; SEI closes the window back up before
; this (now very stretched-out) IRQ finally tail-chains into $EA31 and
; RTIs back into whatever BASIC was doing when F1 first interrupted it.
irq_hook
        lda     basic_ext_countdown
        beq     irq_ext_checked
        dec     basic_ext_countdown
        bne     irq_ext_checked
        jsr     install_basic_ext
        ; Kick off the boot splash jet flyby now that BASIC's cold
        ; start (which just ran, back in bank0_content.asm) has
        ; settled. tower_anim_start now lives in bank0_content.asm,
        ; not here (see slots.asm's SLOT_TOWER_ANIM_START comment for
        ; why) - reached via bank_call instead of a plain JSR, ending
        ; via bank_return. Safe to bank_call from right here since
        ; irq_hook's own IRQ context already has interrupts hardware-
        ; disabled on entry.
        lda     #<SLOT_TOWER_ANIM_START
        sta     call_ptr
        lda     #>SLOT_TOWER_ANIM_START
        sta     call_ptr+1
        lda     #0              ; Bank 0
        jsr     bank_call
irq_ext_checked

; Boot splash jet-flyby animation: one tick per jiffy, non-blocking
; (this is inside an IRQ - a blocking loop here would freeze the whole
; machine, unlike a menu feature's own delay loops). tower_anim_ticks
; is 0 whenever the animation isn't running, including forever before
; tower_anim_start's first call above; its current value also doubles
; as the fly/hold/fade phase selector jet_anim_tick reads from A.
        lda     tower_anim_ticks
        beq     irq_tower_checked
        jsr     jet_anim_tick
        dec     tower_anim_ticks
        bne     irq_tower_checked
        lda     #$00
        sta     $d015           ; belt-and-suspenders - jet_anim_tick's
                                  ; own hold-phase transition already
                                  ; hides the sprite well before this
        ldx     #$00        ; erase the (static) copyright line too
irq_copy_erase
        lda     #$20        ; space
        sta     JET_COPY_SCREEN,x
        inx
        cpx     #JET_COPY_LEN
        bne     irq_copy_erase
        jsr     jet_charset_revert  ; back to the stock charset - the
                                      ; fade phase's own timing (9
                                      ; letters x 7 ticks = JET_FADE_
                                      ; TICKS exactly) guarantees every
                                      ; SHACKMATE letter is already
                                      ; erased by now too
irq_tower_checked

        jsr     read_f1
        bne     irq_f1_up   ; Z=0 - not pressed
        lda     f1_state
        bne     irq_chain   ; still latched from an earlier tick - ignore
        lda     #$01
        sta     f1_state

irq_wait_release
        jsr     read_f1
        beq     irq_wait_release

irq_flush
        jsr     $ffe4
        bne     irq_flush

        cli
        jsr     save_screen
        jsr     zp_save
        lda     #<SLOT_MENU_OPEN
        sta     call_ptr
        lda     #>SLOT_MENU_OPEN
        sta     call_ptr+1
        lda     #0              ; Bank 0
        jsr     bank_call
        jsr     zp_restore
        jsr     restore_screen
        sei
        jmp     irq_chain
irq_f1_up
        lda     #$00
        sta     f1_state
irq_chain
        jmp     $ea31       ; tail-chain into the default IRQ handler,
                             ; which does its own housekeeping and RTIs

; Reads the physical F1 key straight off the CIA1 keyboard matrix
; (column 0 on $DC00, row bit 4 on $DC01) rather than through
; GETIN/the KERNAL keyboard buffer - that buffer is what BASIC and the
; screen editor read from, so stealing from it here would eat
; keystrokes out from under whatever's running. Returns Z=1 (BEQ taken)
; if F1 is currently held down, Z=0 if not. Trashes A.
read_f1
        lda     #$fe        ; select matrix column 0
        sta     $dc00
        lda     $dc01
        and     #$10        ; row bit 4 = F1
        pha
        lda     #$ff        ; deselect - back to idle column state before
        sta     $dc00       ; $EA31's own scan (below) drives it fresh
        pla
        rts

; --- Boot splash jet-flyby animation ---
; One-time setup (tower_anim_start, jet_charset_setup/revert's own
; charset copy, jet_bold_font, jet_sprite) lives in
; bank0_content.asm now, reached via bank_call from irq_hook - see
; slots.asm's SLOT_TOWER_ANIM_START comment for why. Everything below
; still has to stay resident: jet_anim_tick runs on every jiffy tick
; from irq_hook regardless of which bank happens to be switched in at
; that moment, unlike the one-time setup (which only ever runs at a
; moment cur_bank is still guaranteed 0).
;
; A jet sprite flies left to right across the middle of the screen,
; "painting" each letter into screen memory as its TAIL (not the nose)
; passes that column - trailing behind like a real skywriting exhaust
; trail, not pre-drawing ahead of itself. After a short hold, the text
; fades out (dimming through a few colors before erasing) in the same
; left-to-right order. Single one-way flight, not the earlier bouncing
; icon, so tower_dir_x/tower_dir_y (slots.asm) go unused now; tower_x/
; tower_y/tower_anim_ticks are reused (see slots.asm's own comment).

; Row 11, columns 11-28 (18 cols, centered: (40-18)/2=11) - see
; bank0_content.asm's tower_anim_start for the same constants and the
; full row/column reasoning (kept in sync here since each bank is a
; separate assembly). Color RAM mirrors screen memory 1-for-1 at $D800
; instead of $0400, so the same math applies with that base swapped.
JET_TEXT_SCREEN = $05c3        ; $0400 + 11*40 + 11
JET_TEXT_COLOR  = $d9c3        ; $d800 + 11*40 + 11

; Row 13, columns 9-30 (22 chars) - the copyright line. Revealed
; progressively by jat_fly, same tail-trailing trigger as the
; SHACKMATE letters above, just its own index/threshold table
; (jet_copy_reveal_idx/jet_copy_reveal_x) since it's 22 single
; characters instead of 9 letter-pairs. Not part of the per-letter
; fade sequence (jat_fade) - erased in one shot in irq_hook, alongside
; jet_charset_revert, rather than adding another 22-character staggered
; fade on top of the 9-letter one already there.
JET_COPY_SCREEN = $0611        ; $0400 + 13*40 + 9
JET_COPY_COLOR  = $da11        ; $d800 + 13*40 + 9
JET_COPY_LEN    = 22

; Phase tick budget - tower_anim_ticks counts down from this, and
; jet_anim_tick derives fly/hold/fade from whichever band the current
; count falls in (see that routine). JET_FLY_TICKS/JET_TOTAL_TICKS
; aren't directly used by anything below (only HOLD/FADE feed the
; phase-boundary comparisons) - kept here anyway, matching bank0_
; content.asm's own copy, purely so the numbers in this comment stay
; honest. ~214 jiffies: fly+reveal+off-screen exit (127 ticks), a short
; hold (30 ticks), then the fade wipe (9 letters x 7 ticks/letter = 63
; - not 6, see jat_fade's own comment on that).
JET_FLY_TICKS   = 127
JET_HOLD_TICKS  = 30
JET_FADE_TICKS  = 63
JET_TOTAL_TICKS = JET_FLY_TICKS + JET_HOLD_TICKS + JET_FADE_TICKS

; Reveal-trigger sprite-X thresholds, one per LETTER (not per column),
; left to right. Each threshold is simply that letter's left-half
; column's on-screen X (column 0 lines up with sprite X 24, +8 per
; column - same mapping the old tower_step_x's bounds already used) -
; no nose offset: jat_reveal_loop compares tower_x itself (the sprite's
; left edge, near the TAIL) directly against these, so the letter
; appears once the tail has passed it, not the nose.
jet_reveal_x
        !byte 112, 128, 144, 160, 176, 192, 208, 224, 240

; Character-code PAIRS (left half, right half) for "SHACKMATE", left
; to right - see jet_charset_setup for what $80-$8F actually contain.
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

; Reveal-trigger thresholds for the copyright line, one per character
; (not per letter-pair - this row is normal single-width text), same
; tail-trailing mapping as jet_reveal_x above. The last two are clamped
; to 254 rather than their true 256/264 - both comfortably past where
; jet_x_hi (slots.asm) would otherwise be needed for a correct 9-bit
; comparison here; a character or two revealing a few pixels early is
; not worth the extra wraparound-aware comparison logic.
jet_copy_reveal_x
        !byte 96, 104, 112, 120, 128, 136, 144, 152, 160, 168, 176
        !byte 184, 192, 200, 208, 216, 224, 232, 240, 248, 254, 254

; "(c) 2026 - N4LDR & WD4VA" - see bank0_content.asm's jet_copyright_
; glyph for the one custom character ($90) this needs; everything else
; is standard screen codes.
jet_copyright_text
        !byte $90, $20                       ; (c) + space
        !byte $32, $30, $32, $36             ; 2026
        !byte $20, $2d, $20                  ; " - "
        !byte $0e, $34, $0c, $04, $12        ; N4LDR
        !byte $20, $26, $20                  ; " & "
        !byte $17, $04, $34, $16, $01        ; WD4VA

; One call per jiffy tick from irq_hook, replacing the old tower_step_x/
; tower_step_y bounce pair. A holds tower_anim_ticks' current value on
; entry (irq_hook already loaded it for its own "beq" check just before
; calling here) - that value doubles as the phase selector so no
; separate phase variable is needed.
jet_anim_tick
        cmp     #JET_HOLD_TICKS+JET_FADE_TICKS+1
        bcs     jat_fly         ; remaining > hold+fade -> still flying
        cmp     #JET_FADE_TICKS+1
        bcs     jat_hold_check  ; remaining > fade, <= hold+fade -> hold
        jmp     jat_fade
jat_hold_check
        cmp     #JET_HOLD_TICKS+JET_FADE_TICKS
        bne     jat_hold
        lda     #$00            ; first hold tick - hide the jet and
        sta     $d015           ; force-reveal anything not yet shown
                                  ; (rounding safety net)
jat_force_reveal
        ldx     jet_reveal_idx
        cpx     #9
        beq     jat_force_reveal_copy
        jsr     jet_reveal_letter
        jmp     jat_force_reveal
jat_force_reveal_copy
        ldx     jet_copy_reveal_idx
        cpx     #JET_COPY_LEN
        beq     jat_hold
        jsr     jet_copy_reveal_char
        jmp     jat_force_reveal_copy
jat_hold
        rts

; Reveals SHACKMATE letter X (0-8): writes its bold-font character
; pair (jet_letters) and sets both columns white. Shared by both
; jat_force_reveal (hold-phase safety net) and jat_reveal_loop (normal
; in-flight reveal) - same work either way, just reached differently.
; Trashes A/Y; advances jet_reveal_idx itself.
jet_reveal_letter
        txa
        asl
        tay                     ; Y = letter index * 2 (screen/table
                                  ; offset - each letter is 2 columns)
        lda     jet_letters,y
        sta     JET_TEXT_SCREEN,y
        lda     jet_letters+1,y
        sta     JET_TEXT_SCREEN+1,y
        lda     $d012           ; raster line - cheap, fast-changing
        eor     tower_x         ; entropy source; mixed with the jet's
        and     #$0f            ; own current X so consecutive letters
        bne     jrl_color_ok    ; (revealed on different ticks, at
        lda     #$01            ; different X positions) don't land on
jrl_color_ok                     ; the same value even if the raster
                                  ; line alone repeats. Masked to a
                                  ; color (0-15); landing on black (0)
                                  ; falls back to white rather than
                                  ; re-rolling - a letter needs SOME
                                  ; color right now, not a retry loop
        sta     JET_TEXT_COLOR,y
        sta     JET_TEXT_COLOR+1,y
        inc     jet_reveal_idx
        rts

; Reveals copyright-line character X (0-21): single character, unlike
; jet_reveal_letter's pair - this row is normal single-width text.
; Trashes A; advances jet_copy_reveal_idx itself.
jet_copy_reveal_char
        lda     jet_copyright_text,x
        sta     JET_COPY_SCREEN,x
        lda     #$01            ; white
        sta     JET_COPY_COLOR,x
        inc     jet_copy_reveal_idx
        rts

; Advances tower_x by 3 every tick with NO clamp - once past 255 it
; wraps in ordinary 8-bit arithmetic, so jet_x_hi (slots.asm) latches
; permanently on the first wrap and stays set (via sprite X's MSB bit,
; $D010) so the sprite keeps moving right in real screen terms instead
; of snapping back to the left edge - the jet visibly flies off the
; right side of the screen over JET_FLY_TICKS' back half, rather than
; stopping short and just disappearing. Safe for jat_reveal_loop below
; to keep comparing the wrapped tower_x directly against jet_reveal_x's
; thresholds (max 240): by the time wraparound can happen (tower_x
; would need to reach 256, well past every threshold), jet_reveal_idx
; has already reached 9, so the comparison loop exits immediately
; without ever looking at a wrapped, meaningless value.
jat_fly
        lda     tower_x
        clc
        adc     #3
        sta     tower_x
        sta     $d000
        bcc     jat_fly_no_wrap
        lda     #$01
        sta     jet_x_hi        ; latch - stays set for the rest of
                                  ; this flight once it first wraps
jat_fly_no_wrap
        lda     $d010
        and     #$fe            ; clear sprite 0's X MSB bit, then...
        ora     jet_x_hi        ; ...set it back if we've ever wrapped
        sta     $d010
        lda     tower_x         ; tail-based: compare the sprite's own
                                  ; left edge directly, no nose offset -
                                  ; see jet_reveal_x's own comment
jat_reveal_loop
        ldx     jet_reveal_idx
        cpx     #9
        beq     jat_copy_reveal_loop
        cmp     jet_reveal_x,x
        bcc     jat_copy_reveal_loop  ; tail hasn't reached the next
                                        ; SHACKMATE letter yet - the
                                        ; copyright line's own thresholds
                                        ; are independent, still worth
                                        ; checking this same tick
        pha
        jsr     jet_reveal_letter
        pla
        jmp     jat_reveal_loop
jat_copy_reveal_loop
        ldx     jet_copy_reveal_idx
        cpx     #JET_COPY_LEN
        beq     jat_fly_done
        cmp     jet_copy_reveal_x,x
        bcc     jat_fly_done        ; tail hasn't reached the next copyright
                                  ; character yet
        pha
        jsr     jet_copy_reveal_char
        pla
        jmp     jat_copy_reveal_loop
jat_fly_done
        rts

; Fades the current letter (jet_fade_idx) through a few colors over 6
; ticks, then erases it and moves to the next - strictly left to right,
; one letter at a time (simpler to drive off a single tick counter than
; a true overlapping wipe, and still reads clearly as "fading out left
; to right"). jet_charset_revert (restoring the stock character set)
; happens separately, from irq_hook, once tower_anim_ticks itself
; reaches 0 - JET_FADE_TICKS is exactly 9x6, so the 9th letter's own
; erase always lands on the very last fade tick.
jat_fade
        ldx     jet_fade_idx
        cpx     #9
        beq     jaft_rts        ; all letters already erased
        lda     jet_fade_subtick
        cmp     #6
        beq     jaft_erase
        lsr                     ; color-table index = subtick/2 (0,1,2
                                  ; for subtick 0,2,4 - odd subticks
                                  ; harmlessly repeat the prior color)
        tay
        lda     jet_fade_colors,y
        pha                     ; stash the color - txa/asl below needs A
        txa
        asl
        tay                     ; Y = letter index * 2
        pla
        sta     JET_TEXT_COLOR,y
        sta     JET_TEXT_COLOR+1,y
        jsr     jet_copy_fade_color  ; keep the copyright line's own
                                       ; fade in step with this letter
        jmp     jaft_next
jaft_erase
        txa
        asl
        tay                     ; Y = letter index * 2
        lda     #$20            ; space - erase this letter (both
        sta     JET_TEXT_SCREEN,y   ; columns - plain space is unaffected
        sta     JET_TEXT_SCREEN+1,y ; by the $80-$8F patch either way)
        jsr     jet_copy_fade_erase  ; same - erase this letter's
                                       ; copyright-character batch too
        inc     jet_fade_idx
        lda     #$00
        sta     jet_fade_subtick
        rts
jaft_next
        inc     jet_fade_subtick
jaft_rts
        rts
jet_fade_colors
        !byte $0f, $0c, $0b    ; light gray, medium gray, dark gray

; Cumulative copyright-line character count that should be
; colored/erased by the time SHACKMATE letter N finishes fading
; (index 0-8) - 22 characters spread proportionally across 9 letters
; (round((n+1)*22/9)) so both lines finish fading at exactly the same
; tick, without giving the copyright line its own, much longer 22x7
; tick budget.
copy_fade_targets
        !byte 2, 5, 7, 10, 12, 15, 17, 20, 22

; Colors copyright characters from jet_copy_fade_pos up to this
; letter's own copy_fade_targets entry with A's value (the same color
; jat_fade just applied to the current SHACKMATE letter). Does NOT
; advance jet_copy_fade_pos - only jet_copy_fade_erase does, since
; color changes alone don't mark characters as "done". Trashes A/X/Y.
jet_copy_fade_color
        pha                     ; stash the color
        ldx     jet_fade_idx
        lda     copy_fade_targets,x
        sec
        sbc     jet_copy_fade_pos
        tay                     ; Y = how many chars are newly due
        ldx     jet_copy_fade_pos
        pla                     ; A = color again
jcfc_loop
        cpy     #0
        beq     jcfc_done
        sta     JET_COPY_COLOR,x
        inx
        dey
        jmp     jcfc_loop
jcfc_done
        rts

; Erases (space) copyright characters from jet_copy_fade_pos up to
; this letter's own copy_fade_targets entry, then advances
; jet_copy_fade_pos to that target. Trashes A/X/Y.
jet_copy_fade_erase
        ldx     jet_fade_idx
        lda     copy_fade_targets,x
        sec
        sbc     jet_copy_fade_pos
        tay                     ; Y = how many chars are newly due
        ldx     jet_copy_fade_pos
        lda     #$20            ; space
jcfe_loop
        cpy     #0
        beq     jcfe_done
        sta     JET_COPY_SCREEN,x
        inx
        dey
        jmp     jcfe_loop
jcfe_done
        stx     jet_copy_fade_pos   ; X now holds the new position
        rts

; Reverts $D018 to the stock ROM-shadowed charset - called from
; irq_hook once tower_anim_ticks reaches 0, so normal typed BASIC text
; renders normally again afterward. The charset copy/patch itself
; (jet_charset_setup) and the bold font/sprite data it needs live in
; bank0_content.asm now (see slots.asm's SLOT_TOWER_ANIM_START comment)
; - this one small revert is the only piece of that whole system that
; still has to stay resident, since tower_anim_ticks can reach 0 on any
; tick, when cur_bank could be anything, not just the guaranteed-bank-0
; moment the one-time setup runs at.
jet_charset_revert
        lda     #$15        ; stock default: screen $0400, charset $1000
        sta     $d018
        rts

; Copy zero page $02-$38 to zp_save_buf. Trashes A/X.
zp_save
        ldx     #$00
zp_save_loop
        lda     $02,x
        sta     zp_save_buf,x
        inx
        cpx     #zp_save_len
        bne     zp_save_loop
        rts

; Copy zp_save_buf back to zero page $02-$38. Trashes A/X.
zp_restore
        ldx     #$00
zp_restore_loop
        lda     zp_save_buf,x
        sta     $02,x
        inx
        cpx     #zp_save_len
        bne     zp_restore_loop
        rts

; Screen save/restore for the F1 hotkey path: the menu draws straight
; over whatever BASIC had on screen, so "close the menu" needs to put
; the original text/color/border back, not just leave the menu's last
; screen sitting there. Screen is copied as 4 full 256-byte pages
; ($0400-$07FF) rather than exactly 1000 bytes - the last 24 of those
; include the hardware sprite pointers at $07F8-$07FF, which is
; actually wanted here: the graphics demo repoints sprites, so restoring
; them is part of "restore the basic screen", not overshoot. Also saves/
; restores the cursor's row/column (via PLOT, $FFF0) so BASIC's input
; cursor ends up back exactly where it was, not wherever the menu's own
; printing last left it.
save_screen
        ldx     #$00
save_screen_loop
        lda     $0400,x
        sta     scr_save_buf,x
        lda     $0500,x
        sta     scr_save_buf+$100,x
        lda     $0600,x
        sta     scr_save_buf+$200,x
        lda     $0700,x
        sta     scr_save_buf+$300,x
        lda     $d800,x
        sta     col_save_buf,x
        lda     $d900,x
        sta     col_save_buf+$100,x
        lda     $da00,x
        sta     col_save_buf+$200,x
        lda     $db00,x
        sta     col_save_buf+$300,x
        inx
        bne     save_screen_loop
        lda     $d020
        sta     misc_save_buf
        lda     $d021
        sta     misc_save_buf+1
        lda     $0286        ; current text color (used by $FFD2 for
        sta     misc_save_buf+2   ; whatever gets typed/printed next)
        sec
        jsr     $fff0        ; PLOT (read): X=column, Y=row - the KERNAL's
        stx     misc_save_buf+3   ; own way to read cursor position, rather
        sty     misc_save_buf+4   ; than poking $D3/$D6 directly and hoping
        rts                        ; the internal screen-line pointers ($D1/
                                    ; $D2 etc.) stay consistent on our own

restore_screen
        ldx     #$00
restore_screen_loop
        lda     scr_save_buf,x
        sta     $0400,x
        lda     scr_save_buf+$100,x
        sta     $0500,x
        lda     scr_save_buf+$200,x
        sta     $0600,x
        lda     scr_save_buf+$300,x
        sta     $0700,x
        lda     col_save_buf,x
        sta     $d800,x
        lda     col_save_buf+$100,x
        sta     $d900,x
        lda     col_save_buf+$200,x
        sta     $da00,x
        lda     col_save_buf+$300,x
        sta     $db00,x
        inx
        bne     restore_screen_loop
        lda     misc_save_buf
        sta     $d020
        lda     misc_save_buf+1
        sta     $d021
        lda     misc_save_buf+2
        sta     $0286
        ldx     misc_save_buf+3
        ldy     misc_save_buf+4
        clc
        jsr     $fff0        ; PLOT (set): X=column, Y=row - puts the
        rts                   ; cursor back where BASIC had left it, not
                               ; wherever the menu's own printing left it

; --- Tokenize: BASIC's line-crunch calls here (via ICRNCH) for each
; word in a freshly-typed line. Tries the stock keyword table
; (BAS_RESLST) first so every existing BASIC keyword still works
; exactly as before, then falls through to NewTab for ours. Ported
; closely from a verified working reference implementation
; (github.com/barryw/CustomBasicCommands) rather than reconstructed from
; scratch - this is effectively BASIC's own CRUNCH logic (REM/DATA/quote
; handling and all), extended to also check our own keyword table, and
; reproducing that faithfully is far safer than re-deriving its edge
; cases by hand. ---
ConvertToTokens
        ldx     BAS_TXTPTR
        ldy     #4
        sty     BAS_GARBFL
NextChar
        lda     LINE_BUF,x
        bpl     Normal
        cmp     #$ff
        beq     TakChar
        inx
        bne     NextChar
Normal
        cmp     #' '
        beq     TakChar
        sta     BAS_ENDCHAR
        cmp     #CHR_QUOTE
        beq     GetChar
        bit     BAS_GARBFL
        bvs     TakChar
        cmp     #'?'
        bne     Skip
        lda     #BTOK_PRINT
        bne     TakChar
Skip
        cmp     #'0'
        bcc     Skip1
        cmp     #'<'
        bcc     TakChar
Skip1
        sty     BAS_FBUFPT
        ldy     #0
        sty     BAS_COUNT
        dey
        stx     BAS_TXTPTR
        dex
CmpLoop
        iny
        inx
TestNext
        lda     LINE_BUF,x
        sec
        sbc     BAS_RESLST,y
        beq     CmpLoop
        cmp     #$80
        bne     NextCmd
        ora     BAS_COUNT
TakChar1
        ldy     BAS_FBUFPT
TakChar
        inx
        iny
        sta     LINE_BUF-5,y
        cmp     #0
        beq     End
        sec
        sbc     #':'
        beq     Skip2
        cmp     #BTOK_DATA-':'
        bne     Skip3
Skip2
        sta     BAS_GARBFL
Skip3
        sec
        sbc     #BTOK_REM-':'
        bne     NextChar
        sta     BAS_ENDCHAR
RemLoop
        lda     LINE_BUF,x
        beq     TakChar
        cmp     BAS_ENDCHAR
        beq     TakChar
GetChar
        iny
        sta     LINE_BUF-5,y
        inx
        bne     RemLoop
NextCmd
        ldx     BAS_TXTPTR
        inc     BAS_COUNT
Continue
        iny
        lda     BAS_RESLST-1,y
        bpl     Continue
        lda     BAS_RESLST,y
        bne     TestNext
        beq     NewTok
NotFound
        lda     LINE_BUF,x
        bpl     TakChar1
End
        sta     LINE_BUF-3,y
        dec     BAS_TXTPTR+1
        lda     #$ff
        sta     BAS_TXTPTR
        rts
NewTok
        ldy     #0
        lda     NewTab,y
        bne     NewTest
NewCmp
        iny
        inx
NewTest
        lda     LINE_BUF,x
        sec
        sbc     NewTab,y
        beq     NewCmp
        cmp     #$80
        bne     NextNew
        ora     BAS_COUNT
        bne     TakChar1
NextNew
        ldx     BAS_TXTPTR
        inc     BAS_COUNT
Cont1
        iny
        lda     NewTab-1,y
        bpl     Cont1
        lda     NewTab,y
        bne     NewTest
        beq     ExtTok

; --- Second-tier search, tried only after NewTab misses entirely.
; Identical shape to the NewTab search just above (same CmpLoop/TakChar1
; structure, ExtTab instead of NewTab) but a match emits TWO bytes
; (EXTTOK, ext_count) via TakExtChar instead of one $80|BAS_COUNT byte -
; see EXTTOK's own comment for why. ext_count is 1-based (starts at 1
; for ExtTab's first entry) to match ConvertFromTokens' NewList-style
; loop convention below. ---
ExtTok
        ldy     #0
        lda     #1
        sta     ext_count
        lda     ExtTab,y
        bne     ExtTest
ExtCmp
        iny
        inx
ExtTest
        lda     LINE_BUF,x
        sec
        sbc     ExtTab,y
        beq     ExtCmp
        cmp     #$80
        bne     NextExt
        jmp     TakExtChar
NextExt
        ldx     BAS_TXTPTR
        inc     ext_count
ExtCont
        iny
        lda     ExtTab-1,y
        bpl     ExtCont
        lda     ExtTab,y
        bne     ExtTest
        beq     ExtFuncTok

; Emits (EXTTOK, ext_count) instead of NewTab/BAS_RESLST's single
; $80|count byte, then rejoins the normal per-word scan (NextChar).
TakExtChar
        ldy     BAS_FBUFPT
        inx
        iny
        lda     #EXTTOK
        sta     LINE_BUF-5,y
        iny
        lda     ext_count
        sta     LINE_BUF-5,y
        jmp     NextChar

; --- Third-tier search, tried only after BOTH NewTab and ExtTab miss.
; Identical shape again, ExtFuncTab instead - see EXTFUNCTOK's comment
; for why functions need their own token and counter rather than
; sharing ExtTab's. ---
ExtFuncTok
        ldy     #0
        lda     #1
        sta     ext_count
        lda     ExtFuncTab,y
        bne     ExtFuncTest
ExtFuncCmp
        iny
        inx
ExtFuncTest
        lda     LINE_BUF,x
        sec
        sbc     ExtFuncTab,y
        beq     ExtFuncCmp
        cmp     #$80
        bne     NextExtFunc
        jmp     TakExtFuncChar
NextExtFunc
        ldx     BAS_TXTPTR
        inc     ext_count
ExtFuncCont
        iny
        lda     ExtFuncTab-1,y
        bpl     ExtFuncCont
        lda     ExtFuncTab,y
        bne     ExtFuncTest
        jmp     NotFound        ; beq out of branch range this far down

; Emits (EXTFUNCTOK, ext_count), mirroring TakExtChar above.
TakExtFuncChar
        ldy     BAS_FBUFPT
        inx
        iny
        lda     #EXTFUNCTOK
        sta     LINE_BUF-5,y
        iny
        lda     ext_count
        sta     LINE_BUF-5,y
        jmp     NextChar

; --- Detokenize: BASIC's LIST calls here (via IQPLOP) for every byte
; with the high bit set. $A724/$A6F3/$A6EF are fixed reentry points
; inside BASIC's own LIST routine (verified against the reference
; implementation, not guessed). ---
ConvertFromTokens
        bpl     ListOut
        bit     BAS_GARBFL
        bmi     ListOut
        cmp     #$ff
        beq     ListOut
        cmp     #EXTFUNCTOK
        beq     NewExtFuncList
        cmp     #EXTTOK
        beq     NewExtList
        cmp     #CMDSTART
        bcs     NewList
        jmp     $a724
ListOut
        jmp     $a6f3
NewList
        sec
        sbc     #$cb
        tax
        sty     BAS_FORPNT
        ldy     #$ff
ListNext
        dex
        beq     ListFound
ListLoop
        iny
        lda     NewTab,y
        bpl     ListLoop
        bmi     ListNext
ListFound
        iny
        lda     NewTab,y
        bmi     ListOldEnd
        jsr     $ab47       ; basic.CHAROUT
        bne     ListFound
ListOldEnd
        jmp     $a6ef

; --- Extended commands: Y here still equals whatever it was when the
; stock LIST loop fetched the EXTTOK byte itself (this vector was
; reached via a raw JMP, not a JSR, so we're still inside that calling
; context and Y hasn't been touched since). BAS_FORPNT/$49 is plain
; scratch, NOT something already holding this token's position for us -
; both the stock default detokenizer (verified at $A728, "STY $49"
; right at its own entry) and NewList above ("sty BAS_FORPNT" as its
; first action) save Y themselves, fresh, every single time they
; handle a token; an earlier version of this routine instead did "inc
; BAS_FORPNT" assuming NewList (or a once-per-line save elsewhere at
; $A6E8, for an unrelated purpose) had already left the right value
; there, which produced 2-3x duplicated output when the token wasn't
; the first one on the line - confirmed live by LISTing "10 X=1:
; SPRITEON" and seeing SPRITEON printed three times. Saving Y ourselves
; first, THEN incrementing past the extra index byte we consume beyond
; a plain NewList token, is what actually makes $A6EF's later "LDY $49"
; + single INY land one byte past the index byte instead of on it. ---
NewExtList
        sty     BAS_FORPNT
        iny
        lda     ($5f),y
        tax                     ; X = ext_count value (1-based)
        inc     BAS_FORPNT
        ldy     #$ff
ExtListNext
        dex
        beq     ExtListFound
ExtListLoop
        iny
        lda     ExtTab,y
        bpl     ExtListLoop
        bmi     ExtListNext
ExtListFound
        iny
        lda     ExtTab,y
        bmi     ListOldEnd
        jsr     $ab47
        bne     ExtListFound

; Same as NewExtList just above (including the fresh STY BAS_FORPNT -
; same bug, same fix), but for EXTFUNCTOK/ExtFuncTab.
NewExtFuncList
        sty     BAS_FORPNT
        iny
        lda     ($5f),y
        tax
        inc     BAS_FORPNT
        ldy     #$ff
ExtFuncListNext
        dex
        beq     ExtFuncListFound
ExtFuncListLoop
        iny
        lda     ExtFuncTab,y
        bpl     ExtFuncListLoop
        bmi     ExtFuncListNext
ExtFuncListFound
        iny
        lda     ExtFuncTab,y
        bmi     ListOldEnd
        jsr     $ab47
        bne     ExtFuncListFound

; Keyword table for both the tokenizer and detokenizer above - the
; last character of each name has $80 added to mark the end. Order
; must match CmdBankTab/CmdSlotLoTab; only CLS lives here now (a direct
; single-byte token, $cc) - everything else uses the extended tables
; below instead.
NewTab
        !text   "CL"
        !byte   'S'+$80
        !byte   0

; Extended-command keyword table - same format as NewTab (last char of
; each name has $80 added, list terminated by $00), tried only after
; NewTab misses. Order must match ExtBankTab/ExtSlotLoTab; ext_count
; values are assigned sequentially starting at 1 (not 0 - see EXTTOK's
; comment on why this table's indexing works differently from NewTab's).
ExtTab
        !text   "COLO"
        !byte   'R'+$80
        !text   "BORDE"
        !byte   'R'+$80
        !text   "BACKGROUN"
        !byte   'D'+$80
        !text   "LOCAT"
        !byte   'E'+$80
        !text   "PRINTA"
        !byte   'T'+$80
        !text   "HEL"
        !byte   'P'+$80
        !text   "HIRE"
        !byte   'S'+$80
        !text   "MULT"
        !byte   'I'+$80
        !text   "TEX"
        !byte   'T'+$80
        !text   "PLO"
        !byte   'T'+$80
        !text   "LIN"
        !byte   'E'+$80
        !text   "BO"
        !byte   'X'+$80
        !text   "CIRCL"
        !byte   'E'+$80
        !text   "PAIN"
        !byte   'T'+$80
        !text   "SPRITEO"
        !byte   'N'+$80
        !text   "SPRITEOF"
        !byte   'F'+$80
        !text   "SPRITECOLO"
        !byte   'R'+$80
        !text   "SPRIT"
        !byte   'E'+$80
        !text   "DOK"
        !byte   'E'+$80
        !text   "DUM"
        !byte   'P'+$80
        !text   "FIL"
        !byte   'L'+$80
        !text   "MOV"
        !byte   'E'+$80
        !text   "CARTINF"
        !byte   'O'+$80
        !text   "BANK"
        !byte   'S'+$80
        !text   "BAN"
        !byte   'K'+$80
        !text   "SOUN"
        !byte   'D'+$80
        !text   "VOLUM"
        !byte   'E'+$80
        !text   "WAV"
        !byte   'E'+$80
        !text   "ADS"
        !byte   'R'+$80
        !text   "FILTE"
        !byte   'R'+$80
        !text   "FLASHERAS"
        !byte   'E'+$80
        !text   "FLASHLOA"
        !byte   'D'+$80
        !text   "FLASHVERIF"
        !byte   'Y'+$80
        !text   "DI"
        !byte   'R'+$80
        !text   "DEVIC"
        !byte   'E'+$80
        !text   "C"
        !byte   'D'+$80
        !text   "DELET"
        !byte   'E'+$80
        !text   "RENAM"
        !byte   'E'+$80
        !text   "DLOA"
        !byte   'D'+$80
        !text   "DSAV"
        !byte   'E'+$80
        !text   "HTTPGE"
        !byte   'T'+$80
        !text   "TELNE"
        !byte   'T'+$80
        !text   "JE"
        !byte   'T'+$80
        !text   "REBOO"
        !byte   'T'+$80
        !byte   0

; Extended-FUNCTION keyword table - same format again, own independent
; 1-based indexing (see EXTFUNCTOK's comment for why this can't just be
; more entries in ExtTab above). Order must match ExtFuncBankTab/
; ExtFuncSlotLoTab.
ExtFuncTab
        !text   "JOYU"
        !byte   'P'+$80
        !text   "JOYDOW"
        !byte   'N'+$80
        !text   "JOYLEF"
        !byte   'T'+$80
        !text   "JOYRIGH"
        !byte   'T'+$80
        !text   "JOYFIR"
        !byte   'E'+$80
        !text   "JO"
        !byte   'Y'+$80
        !text   "DEE"
        !byte   'K'+$80
        !text   "FIN"
        !byte   'D'+$80
        !text   "HEX"
        !byte   '$'+$80        ; "HEX$" - terminal '$' is the marked byte
        !text   "DEC"
        !byte   '$'+$80        ; "DEC$" - terminal '$' is the marked byte
        !byte   0
