#!/bin/bash
# Build the 13-bank EasyFlash cartridge image.
#
# Each bank is a separate ACME assembly of bank_driver.asm (content
# $8000-$9BFF + the identical resident kernel at $9C00-$9FFF - see
# resident.asm for why that has to be byte-identical in every bank).
# Only Bank 0 needs real ROMH content: EasyFlash always boots into
# Ultimax mode, which maps ROMH (not the KERNAL) at $E000-$FFFF, so the
# hardware reset vector has to live there - see romh_boot.asm. Banks
# 1-12 never run at reset, so their ROMH half is just $FF filler.
set -e
cd "$(dirname "$0")"

mkdir -p ../build
rm -f ../build/bank_combined.bin

echo "=== ROMH bootstrap (Bank 0 only) ==="
acme -f plain -o ../build/bank0_romh.bin romh_boot.asm
if [ "$(wc -c < ../build/bank0_romh.bin)" -ne 8192 ]; then
    echo "romh_boot.asm did not produce exactly 8192 bytes" >&2
    exit 1
fi

for n in 0 1 2 3 4 5 6 7 8 9 10 11 12; do
    echo "=== Bank $n ROML ==="
    acme -f plain --strict-segments -DBANKNUM=$n -o ../build/bank$n.bin bank_driver.asm

    python3 -c "
import sys
n = $n
roml = open('../build/bank%d.bin' % n, 'rb').read()
if len(roml) > 8192:
    sys.exit('bank %d ROML too big: %d bytes' % (n, len(roml)))
roml = roml + bytes([0xff]) * (8192 - len(roml))

if n == 0:
    romh = open('../build/bank0_romh.bin', 'rb').read()
else:
    romh = bytes([0xff]) * 8192

with open('../build/bank_combined.bin', 'ab') as f:
    f.write(roml)
    f.write(romh)
"
done

echo "=== Package as EasyFlash .crt ==="
# No -b: banks 1-12's ROMH is genuinely empty ($FF filler) in this phase,
# and cartconv correctly omits those chunks rather than writing dead
# space - confirmed by direct comparison against -b, which instead pads
# the whole image out to EasyFlash's full 64-bank/1MB capacity, not
# what we want here.
cartconv -t easy -i ../build/bank_combined.bin -o ../build/hello.crt -n "SHACKMATE" -l 0x8000 -p

echo "=== Done: build/hello.crt ==="
cartconv -f ../build/hello.crt
