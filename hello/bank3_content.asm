; Bank 3 content: SPRITES category (SPRITE/SPRITEON/SPRITEOFF/
; SPRITECOLOR). All stubs for now - each prints its own name via a
; small inline loop (see resident.asm's print_stub_suffix comment for
; why), then the shared print_stub_suffix tail. Real logic (direct
; VIC-register POKE sequences: $07F8 pointer, $D015 enable, $D027+
; color, $D000/$D001 position) comes later.

; --- Fixed-slot jump table entries for this bank (slots.asm) ---
!fill SLOT_SPRITE-*, $ff
        jmp     SpriteCmd
!fill SLOT_SPRITEON-*, $ff
        jmp     SpriteOnCmd
!fill SLOT_SPRITEOFF-*, $ff
        jmp     SpriteOffCmd
!fill SLOT_SPRITECOLOR-*, $ff
        jmp     SpriteColorCmd

; Reserved slot-table range continues to $80FF regardless of how many
; slots this bank actually fills in.
!fill BANK_CONTENT_START-*, $ff

*=BANK_CONTENT_START

SpriteCmd
        ldx     #0
sprite_print_loop
        lda     sprite_name,x
        beq     sprite_print_done
        jsr     $ffd2
        inx
        bne     sprite_print_loop
sprite_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
SpriteOnCmd
        ldx     #0
spriteon_print_loop
        lda     spriteon_name,x
        beq     spriteon_print_done
        jsr     $ffd2
        inx
        bne     spriteon_print_loop
spriteon_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
SpriteOffCmd
        ldx     #0
spriteoff_print_loop
        lda     spriteoff_name,x
        beq     spriteoff_print_done
        jsr     $ffd2
        inx
        bne     spriteoff_print_loop
spriteoff_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic
SpriteColorCmd
        ldx     #0
spritecolor_print_loop
        lda     spritecolor_name,x
        beq     spritecolor_print_done
        jsr     $ffd2
        inx
        bne     spritecolor_print_loop
spritecolor_print_done
        jsr     print_stub_suffix
        jmp     bank_return_basic

sprite_name
        !text   "SPRITE"
        !byte   0
spriteon_name
        !text   "SPRITEON"
        !byte   0
spriteoff_name
        !text   "SPRITEOFF"
        !byte   0
spritecolor_name
        !text   "SPRITECOLOR"
        !byte   0
