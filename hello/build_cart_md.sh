#!/bin/bash
# Build a Magic Desk-format cartridge image - for testing on real hardware
# (e.g. the msolajic c64-uni-cart board, MODE jumper set to MAGIC DESK)
# ahead of the custom AM29F040B platform. See docs/HARDWARE_PLATFORM.md's
# "Phase 0: bring-up/test board" section for the verified protocol.
#
# Unlike build_cart.sh (EasyFlash), Magic Desk mode never uses Ultimax or
# ROMH at all - GAME/EXROM are fixed 8K mode by the test board's own
# jumpers, not software-switched. That means romh_boot.asm's whole job
# (bridge "forced Ultimax boot" back to a normal KERNAL reset) doesn't
# apply here: the real KERNAL reset vector runs directly on power-up,
# finds the CBM80 signature already sitting in bank0_content.asm's own
# ROML image (unchanged from the EasyFlash build - that signature was
# never EasyFlash-specific), and jumps straight into cart_start. Bank
# switching is a single write to $DE00 with the bank number in bits 0-6 -
# the exact same address bank_call/ram_bank_switch already write via
# EASYFLASH_BANK (slots.asm), so none of the ROM content differs from the
# EasyFlash build - only how it's packaged.
set -e
cd "$(dirname "$0")"

mkdir -p ../build
rm -f ../build/bank_combined_md.bin

for n in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    echo "=== Bank $n (Magic Desk, ROML only, no ROMH) ==="
    acme -f plain --strict-segments -DBANKNUM=$n -o ../build/bank${n}_md.bin bank_driver.asm

    python3 -c "
import sys
n = $n
roml = open('../build/bank%d_md.bin' % n, 'rb').read()
if len(roml) > 8192:
    sys.exit('bank %d ROML too big: %d bytes' % (n, len(roml)))
roml = roml + bytes([0xff]) * (8192 - len(roml))
with open('../build/bank_combined_md.bin', 'ab') as f:
    f.write(roml)
"
done

echo "=== Package as Magic Desk .crt ==="
cartconv -t md -i ../build/bank_combined_md.bin -o ../build/hello_md.crt -n "SHACKMATE" -l 0x8000 -p

echo "=== Done: build/hello_md.crt ==="
cartconv -f ../build/hello_md.crt
