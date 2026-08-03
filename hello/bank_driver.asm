; Shared top-level file for every bank's ROML ($8000-$9FFF) build - built
; once per bank (13 banks total: 0-12; see build_cart.sh), with
; -DBANKNUM=n selecting which bank's content gets included. Content
; occupies $8000-$97FF; the resident kernel (resident.asm, identical in
; every bank) always sits at the fixed $9800-$9FFF range (2048 bytes -
; widened from the original 1024 once the full extended-command token
; tables pushed past that) so it works regardless of which bank happens
; to be switched in - see resident.asm for why that matters.
;
; Bank 12 has no content yet (reserved for the later SERIAL plan) and
; falls straight through to the padding below with nothing sourced - an
; all-$FF ROML, matching real erased-flash state.

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

!if * > $9800 {
        !error "bank content overflowed into the resident kernel region ($9800)"
}
!fill $9800-*, $ff
*=$9800

!source "resident.asm"

!if * > $a000 {
        !error "resident kernel overflowed the 8K ROML window"
}
