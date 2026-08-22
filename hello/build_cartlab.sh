#!/bin/bash
# Build the standalone Cartridge Lab program (cartlab.asm) - a plain
# disk-loadable .prg, not part of the SHACKMATE cartridge itself. See
# cartlab.asm's own header comment for why this exists as a separate
# program: it reads a DIFFERENT cartridge (the target EPROM board) than
# whatever's supplying the code that's running, which only works
# cleanly when none of the reading code's own bytes live in the
# $8000-$9FFF window being switched.
set -e
cd "$(dirname "$0")"

mkdir -p ../build

acme -f cbm -o ../build/cartlab.prg cartlab.asm

echo "=== Done: build/cartlab.prg ==="
ls -la ../build/cartlab.prg
