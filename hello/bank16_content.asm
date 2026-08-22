; Bank 16 content: Sprite Editor (spriteeditor.asm) - relocated out of
; Bank 15 (Menu Features) once the CARTRIDGE LAB port needed the room;
; see slots.asm's SLOT_SPRITE_EDITOR_DISPATCH and FIRST_USER_BANK
; comments for the full story. This bank is part of the protected
; "system" range now, not the user-programmable range it used to be
; the FIRST bank of.
;
; Unlike Bank 15's SLOT_FEAT_DISPATCH (a shared slot with its own
; num_val-driven internal routing, since Bank 15 holds several
; features), this bank holds exactly one feature, so its own slot
; jumps straight to it - no dispatch layer needed here.

; --- Fixed-slot jump table entry for this bank (slots.asm) ---
!fill SLOT_SPRITE_EDITOR_DISPATCH-*, $ff
        jmp     slot_dispatch

; Reserved slot-table range continues to BANK_CONTENT_START regardless
; of how many slots this bank actually fills in.
!fill BANK_CONTENT_START-*, $ff

*=BANK_CONTENT_START

; bank_call reaches the slot above via its own "JMP (call_ptr)" - a
; tail call, not a JSR - so feat_sprite_editor's own plain "rts" (its
; normal exit, spriteeditor.asm's fse_done) can't be reached directly
; from there: bank_call only pushed the OLD bank number (one byte) on
; top of the real JSR-bank_call return address, and a bare RTS would
; pop that single byte as half of a bogus return address instead of
; unwinding it properly. JSR here first (a real call, so feat_sprite_
; editor's own RTS comes back to the very next instruction), then JMP
; bank_return to pop the saved bank byte and return for real - same
; tail every other cross-bank feature in this project already uses
; (see bank15_content.asm's feat_dispatch).
slot_dispatch
        jsr     feat_sprite_editor
        jmp     bank_return

!source "spriteeditor.asm"
