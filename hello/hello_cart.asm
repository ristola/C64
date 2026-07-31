; Hello World for Commodore 64 — 8K autostart cartridge image
; Assembler: ACME
; Build: Tasks: Run Task > Build Cartridge Image (or "Build All")

*=$8000

; --- Cartridge autostart header ---
; KERNAL reset routine looks for "CBM80" at $8004 and, if found, jumps
; indirectly through the cold-start vector below instead of booting BASIC.
!word cart_start     ; cold-start vector
!word cart_start     ; NMI vector (just reuse cold-start for this demo)
!byte $c3,$c2,$cd,$38,$30  ; "CBM80" autostart signature (KERNAL checks
                            ; these exact bytes, not plain ASCII "CBM80")

; irq_hook's F1 debounce latch. NOT zero page: on a stock C64 only $02
; and $FB-$FE are genuinely free there (confirmed against the real
; zero-page map after $29 - picked back when this looked like free
; space - turned out to be RESHO, BASIC's floating-point multiply/divide
; scratch, and was quietly corrupting it on every single jiffy tick).
; This flag is never used with indirect addressing, so it doesn't need
; to be zero page at all - ordinary RAM in the datasette buffer (free
; whenever tape isn't in use) is fine. zp_save_buf below claims
; $033C-$0372 (55 bytes); this sits just past that.
f1_state = $0373

; Countdown (in jiffies) until irq_hook installs the BASIC extension
; vectors (basicext.asm) - NOT done directly in cart_start, because
; BASIC's own cold-start routine (triggered below by JMP ($A000))
; initializes those same RAM vectors ($0300-$030B) as part of its own
; setup; installing ours first would just get overwritten the instant
; BASIC finishes booting. Counting down a few jiffies from inside
; irq_hook guarantees the install happens well after that's done -
; BASIC's cold-start finishes almost instantly (just a banner print),
; so even a fraction of a second of margin is generous. 0 = already
; installed, and stays that way.
basic_ext_countdown = $0374

; common.asm/ultimate_sdk.asm/features.asm/bitmap.asm between them use
; zero page $02-$38 as scratch and indirect-addressing pointers (picked
; back when this cart owned the machine permanently and BASIC's own
; zero-page conventions were irrelevant). Now that F1 can drop into the
; menu at any moment - including mid-BASIC-statement - and hand control
; back afterward, that whole range has to be saved before the menu runs
; and restored before returning, or BASIC comes back with corrupted
; TXTTAB/VARTAB/ARYTAB/STREND/FRETOP/MEMSIZ (bitmap.asm's $2b-$38 alone
; covers all six) - which is exactly the "OUT OF MEMORY" this was
; producing. $033C is the datasette buffer, standard free RAM when tape
; isn't in use.
zp_save_buf = $033c
zp_save_len = 55     ; $02-$38 inclusive

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
; screen sitting there. $C000-$CFFF is the standard free RAM hole below
; the KERNAL ROM - unused by BASIC, KERNAL, or anything else here, and
; big enough for a full screen+color backup (unlike zero page, which
; had no room to spare). Screen is copied as 4 full 256-byte pages
; ($0400-$07FF) rather than exactly 1000 bytes - the last 24 of those
; include the hardware sprite pointers at $07F8-$07FF, which is
; actually wanted here: the graphics demo repoints sprites, so restoring
; them is part of "restore the basic screen", not overshoot.
scr_save_buf  = $c000   ; 4 pages: screen $0400-$07FF backup
col_save_buf  = $c400   ; 4 pages: color RAM $D800-$DBFF backup
misc_save_buf = $c800   ; border, background, current text color

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
        rts

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
        rts

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

cart_start
; The cart-autostart check happens right at the top of the KERNAL's reset
; routine — before it initializes the VIC-II/screen editor, CIA/IRQ timers,
; or re-enables interrupts (SEI is still in effect here). Replicate the same
; init calls the KERNAL would normally do before jumping to BASIC, so KERNAL
; text output ($FFD2) and the jiffy clock (used by our delay loop) both work.
        ldx     #$ff
        stx     $d016       ; standard VIC-II init (matches normal boot)
        jsr     $fda3       ; IOINIT - init CIA/SID
        jsr     $fd50       ; RAMTAS - memory test & pointer setup
        jsr     $fd15       ; RESTOR - restore default IRQ/vectors
        jsr     $ff5b       ; CINT  - init screen editor & VIC-II text mode

; Wedge our F1 watcher into the jiffy IRQ chain (RESTOR just reset this
; vector to its default $EA31, so install ours after RESTOR, before CLI —
; otherwise a jiffy IRQ could land mid-write, with the vector pointing
; half at $EA31 and half at irq_hook).
        lda     #<irq_hook
        sta     $0314
        lda     #>irq_hook
        sta     $0315
        lda     #$00
        sta     f1_state

        cli                 ; re-enable interrupts (delay loop needs the jiffy clock)

; Welcome screen: flash the splash banner for ~1 second, then go
; straight on to BASIC below - no menu here. F1 still opens it
; afterward via irq_hook as usual; this is just a startup banner.
        lda     #$00
        sta     $d020
        sta     $d021
        lda     #$93
        jsr     $ffd2
        ldx     #$00
cart_boot_splash
        lda     splash,x
        beq     cart_boot_splash_done
        jsr     $ffd2
        inx
        bne     cart_boot_splash
cart_boot_splash_done
        lda     #60         ; ~1 second (60 jiffies)
        jsr     delay

; Arm the BASIC-extension countdown right here, not back before the
; splash - interrupts (and so irq_hook's countdown) have been running
; since the CLI above, and this whole splash detour has already burned
; ~60 jiffies of it. Arming it that early let the countdown reach 0
; and fire mid-splash, well before BASIC's cold start below even runs -
; which then clobbered our freshly-installed vectors right back to
; stock as part of its own RAM-vector init, so neither CLS nor HEX ever
; survived to see a keystroke. Setting it fresh right before the jump
; means BASIC's cold start (a quick banner print) has long finished by
; the time it counts down again.
        lda     #30
        sta     basic_ext_countdown

; Hand off to BASIC's own cold start exactly like the KERNAL reset
; routine would if it hadn't found a CBM80 signature at all: JSR
; $FDA3/$FD50/$FD15/$FF5B, CLI, JMP ($A000), verified against the real
; KERNAL disassembly at $FCE2-$FCFF. $A000/$A001 hold a vector (not code
; to run directly - JMP $A000 instead of JMP ($A000) executes BASIC
; ROM's raw header bytes as instructions and hangs), which point at
; BASIC's actual cold-start routine - prints the
; "**** COMMODORE 64 BASIC ****" banner and drops into READY. This makes
; the cart transparent from here on: irq_hook stays resident and watches
; for F1.
        jmp     ($a000)

; --- F1 watcher, wedged into the jiffy IRQ (~60Hz) via $0314/$0315 ---
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
; straight to the (unwritten) Help stub. Holding SEI through the release
; wait blocks $EA31 entirely, so nothing gets buffered in the first
; place; draining GETIN afterward is just a belt-and-suspenders flush
; for anything else that snuck in.
;
; Once clear, this CLIs and calls menu_open directly from inside the
; IRQ — menu_open blocks on GETIN, which only ever fills up because the
; jiffy IRQ keeps firing, so interrupts must stay enabled while it runs
; (this makes the handler reentrant: further jiffy IRQs nest on top of
; it via the fast path below, each one tail-chaining into $EA31 and
; returning normally, so the keyboard buffer, jiffy clock etc. all keep
; working exactly as they would in BASIC). save_screen/restore_screen
; and zp_save/zp_restore bracket the call so neither the menu's screen
; nor its zero-page scratch leak into whatever BASIC had going. menu_open
; only returns when the user backs all the way out with RUN/STOP; SEI
; closes the window back up before this (now very stretched-out) IRQ
; finally tail-chains into $EA31 and RTIs back into whatever BASIC was
; doing when F1 first interrupted it.
irq_hook
        lda     basic_ext_countdown
        beq     irq_ext_checked
        dec     basic_ext_countdown
        bne     irq_ext_checked
        jsr     install_basic_ext
irq_ext_checked

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
        jsr     menu_open
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

!source "common.asm"
!source "basicext.asm"
