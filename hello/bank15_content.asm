; Bank 15 content: Menu Features. features.asm (SID demo, joystick
; tester, CIA/VIC-II/memory viewers, plus the CARTRIDGE LAB port: BANK
; SCANNER/HEX VIEWER/VERIFY EPROM/LOAD EPROM TO RAM) - split off from
; Bank 14 (the F1 Cart Menu) the moment it turned out common.asm plus
; all the feature files together still didn't fit in one 8K bank, even
; after moving jet_charset_setup in from Bank 0 too - see bank14_
; content.asm's own header for that story. spriteeditor.asm moved on to
; its own bank (16) later, once the CARTRIDGE LAB port needed the room
; back - see slots.asm's SLOT_SPRITE_EDITOR_DISPATCH comment. bitmap.
; asm (and the dead feat_graphics_demo/fgd_compass code that was its
; only caller) was removed outright rather than relocated - it was
; unreachable from any menu, confirmed by grepping the whole project
; for callers before deleting it - freeing that room is what let VERIFY/
; LOAD EPROM TO RAM's picker keep DEL support and made room for SEARCH
; ROM. This bank is part of the protected "system" range - see slots.
; asm's FIRST_USER_BANK comment for the wider policy.
;
; feat_dispatch below is the one cross-bank entry point every routine
; here is reached through - see slots.asm's SLOT_FEAT_DISPATCH comment
; for why a single shared slot (rather than one per routine) was worth
; the small dispatch layer.
;
; num_val/dly_cnt: common.asm's own zero-page scratch declarations,
; redefined here identically (same addresses) since this is a separate
; ACME assembly that never sees common.asm's copy - same duplication
; already used for JET_CHARSET between bank0_content.asm and this file.
; num_val is feat_dispatch's own selector argument (see its comment
; below); dly_cnt is delay's, needed because features.asm's demos call
; it and delay itself doesn't live in common.asm's bank any more either.
num_val = $03
dly_cnt = $02

; --- Fixed-slot jump table entry for this bank (slots.asm) ---
!fill SLOT_FEAT_DISPATCH-*, $ff
        jmp     feat_dispatch

; Reserved slot-table range continues to BANK_CONTENT_START regardless
; of how many slots this bank actually fills in.
!fill BANK_CONTENT_START-*, $ff

*=BANK_CONTENT_START

; num_val (common.asm's shared "which item" variable - set to one of
; slots.asm's FEAT_* constants by the caller immediately before its own
; bank_call, since bank_call itself already needs A for the bank
; number) selects which feature to run. Each routine below still ends
; the same way it always did (jmp bank_return, unchanged) - only how
; it's reached changed, from a same-bank JSR to this cross-bank hop.
feat_dispatch
        lda     num_val
        cmp     #FEAT_SID
        bne     fd1
        jsr     feat_sid_demo
        jmp     bank_return
fd1     cmp     #FEAT_SPRITE_EDITOR
        bne     fd2
        lda     #<SLOT_SPRITE_EDITOR_DISPATCH  ; SLOT_SPRITE_EDITOR_
        sta     call_ptr                          ; DISPATCH is a fixed
        lda     #>SLOT_SPRITE_EDITOR_DISPATCH     ; address (same slot-
        sta     call_ptr+1                        ; table layout in
        lda     #16                                ; every bank), so
        jsr     bank_call                          ; this works exactly
                                                       ; like the resident_
                                                       ; copy_page nested
                                                       ; bank_calls already
                                                       ; elsewhere in this
                                                       ; file - Bank 16
                                                       ; now holds the
                                                       ; Sprite Editor,
                                                       ; see slots.asm
        jmp     bank_return
fd2     cmp     #FEAT_CIA
        bne     fd3
        jsr     feat_cia_monitor
        jmp     bank_return
fd3     cmp     #FEAT_VIC
        bne     fd4
        jsr     feat_vic_viewer
        jmp     bank_return
fd4     cmp     #FEAT_MEMORY
        bne     fd5
        jsr     feat_memory_viewer
        jmp     bank_return
fd5     cmp     #FEAT_JOYSTICK
        bne     fd6
        jsr     feat_joystick_tester
        jmp     bank_return
fd6     cmp     #FEAT_EPROM_DUMP
        bne     fd7
        jsr     feat_eprom_dump
        jmp     bank_return
fd7     cmp     #FEAT_READ_CHIP
        bne     fd8
        jsr     feat_read_chip
        jmp     bank_return
fd8     cmp     #FEAT_BACKUP_EPROM
        bne     fd9
        jsr     feat_backup_eprom
        jmp     bank_return
fd9     cmp     #FEAT_BANK_SCANNER
        bne     fd10
        jsr     feat_bank_scanner
        jmp     bank_return
fd10    cmp     #FEAT_VERIFY_EPROM
        bne     fd11
        jsr     feat_verify_eprom
        jmp     bank_return
fd11    cmp     #FEAT_LOAD_EPROM
        bne     fd12
        jsr     feat_load_eprom
        jmp     bank_return
fd12    cmp     #FEAT_SEARCH_ROM
        beq     +
        jmp     bank_return ; shouldn't happen - callers only ever set
                              ; num_val to one of the FEAT_* constants
+       jsr     feat_search_rom
        jmp     bank_return

; --- Cycle-counting busy-wait delay (~1/60 sec per unit) - identical
; copy of common.asm's own delay, needed here because features.asm's
; demos call it and features.asm no longer shares a bank with common.
; asm's copy. See that copy's own comment (common.asm) for the full
; rationale; unchanged otherwise. ---
delay
        sta     dly_cnt
        txa
        pha
        tya
        pha
dly_unit
        ldy     #$0d
dly_outer
        ldx     #$00
dly_inner
        dex
        bne     dly_inner
        dey
        bne     dly_outer
        dec     dly_cnt
        bne     dly_unit
        pla
        tay
        pla
        tax
        rts

!source "features.asm"
