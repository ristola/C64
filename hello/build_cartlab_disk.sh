#!/bin/bash
# Build cartlab.asm and cartlab_boot.asm, then assemble a bootable D64
# disk image (../build/cartlab_boot.d64) containing BOOT (the splash/
# chain-loader, autostarts via LOAD"*",8,1) followed by CARTLAB (the
# real tool). See cartlab_boot.asm's own header comment for how the
# splash-then-chain-load handoff works.
set -e
cd "$(dirname "$0")"

mkdir -p ../build

acme -f cbm -o ../build/cartlab.prg cartlab.asm
acme -f cbm -o ../build/boot.prg cartlab_boot.asm

rm -f ../build/cartlab_boot.d64
c1541 -format "shackmate,00" d64 ../build/cartlab_boot.d64 \
      -write ../build/boot.prg boot \
      -write ../build/cartlab.prg cartlab

echo "=== Done: build/cartlab_boot.d64 ==="
c1541 -attach ../build/cartlab_boot.d64 -list
