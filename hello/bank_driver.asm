; Shared top-level file for every bank's ROML ($8000-$9FFF) build - built
; once per bank (22 banks total: 0-21; see build_cart.sh), with
; -DBANKNUM=n selecting which bank's content gets included. Content
; occupies $8000-BANK_CONTENT_START (slots.asm); the resident kernel
; (resident.asm, identical in every bank) always sits at the fixed
; RESIDENT_START-$9FFF range (slots.asm - 2240 bytes as of this
; writing, widened from 1024, then 2048, then 2112, as the extended-
; command token tables kept growing) so it works regardless of which
; bank happens to be switched in - see resident.asm for why that
; matters.
;
; Bank 0 holds only cart_start and the boot splash now - the F1 Cart
; Menu (common.asm) moved out to Bank 14, and the feature implementations
; it launches (features.asm/bitmap.asm) moved to Bank 15 right after it,
; once it turned out Bank 14 couldn't hold common.asm AND those together
; either - see bank0_content.asm's, bank14_content.asm's, and slots.
; asm's SLOT_JET_CHARSET_SETUP/SLOT_FEAT_DISPATCH comments for the full
; story. spriteeditor.asm moved on again, to its own Bank 16, once the
; CARTRIDGE LAB port needed Bank 15's room back - see slots.asm's SLOT_
; SPRITE_EDITOR_DISPATCH comment. Bank 0 has plenty of headroom again as
; a result. Bank 12 has no content yet (reserved for the later SERIAL
; plan) and falls straight through to the padding below with nothing
; sourced - an all-$FF ROML, matching real erased-flash state. Banks
; 17-21 are the same, deliberately: genuinely empty, user-programmable
; space - see slots.asm's FIRST_USER_BANK comment for the protected/
; user-bank policy this boundary is part of.

*=$8000

!source "slots.asm"

!if BANKNUM = 0 {
        !source "bank0_content.asm"
}
!if BANKNUM = 1 {
        !source "bank1_content.asm"
}
!if BANKNUM = 2 {
        !source "bank2_content.asm"
}
!if BANKNUM = 3 {
        !source "bank3_content.asm"
}
!if BANKNUM = 4 {
        !source "bank4_content.asm"
}
!if BANKNUM = 5 {
        !source "bank5_content.asm"
}
!if BANKNUM = 6 {
        !source "bank6_content.asm"
}
!if BANKNUM = 7 {
        !source "bank7_content.asm"
}
!if BANKNUM = 8 {
        !source "bank8_content.asm"
}
!if BANKNUM = 9 {
        !source "bank9_content.asm"
}
!if BANKNUM = 10 {
        !source "bank10_content.asm"
}
!if BANKNUM = 11 {
        !source "bank11_content.asm"
}
; Bank 12 reserved for the later SERIAL plan - intentionally no content yet.
!if BANKNUM = 13 {
        !source "bank13_content.asm"
}
!if BANKNUM = 14 {
        !source "bank14_content.asm"
}
!if BANKNUM = 15 {
        !source "bank15_content.asm"
}
!if BANKNUM = 16 {
        !source "bank16_content.asm"
}
; Banks 17-21: user-programmable range, intentionally no content.

!if * > RESIDENT_START {
        !error "bank content overflowed into the resident kernel region (RESIDENT_START)"
}
!fill RESIDENT_START-*, $ff
*=RESIDENT_START

!source "resident.asm"

!if * > $a000 {
        !error "resident kernel overflowed the 8K ROML window"
}
