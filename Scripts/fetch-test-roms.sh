#!/usr/bin/env bash
# Downloads public emulator conformance ROMs (Blargg's tests, nestest and the
# acid2 PPU tests) into Tests/NotcherCoreTests/External. They are only used by
# the test suite and preview renders, never shipped.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=Tests/NotcherCoreTests/External
mkdir -p "$DEST/gb" "$DEST/nes"

fetch() {
  [[ -s "$2" ]] && return 0
  curl -fsSL --retry 3 -o "$2" "$1"
  echo "▸ $(basename "$2")"
}

GB=https://raw.githubusercontent.com/retrio/gb-test-roms/master
fetch "$GB/cpu_instrs/cpu_instrs.gb" "$DEST/gb/cpu_instrs.gb"
fetch "$GB/instr_timing/instr_timing.gb" "$DEST/gb/instr_timing.gb"
fetch "$GB/mem_timing/mem_timing.gb" "$DEST/gb/mem_timing.gb"
fetch https://github.com/mattcurrie/dmg-acid2/releases/download/v1.0/dmg-acid2.gb "$DEST/gb/dmg-acid2.gb"
fetch https://github.com/mattcurrie/cgb-acid2/releases/download/v1.1/cgb-acid2.gbc "$DEST/gb/cgb-acid2.gbc"

NES=https://raw.githubusercontent.com/christopherpow/nes-test-roms/master
fetch "$NES/other/nestest.nes" "$DEST/nes/nestest.nes"
fetch "$NES/other/nestest.log" "$DEST/nes/nestest.log"
fetch "$NES/instr_test-v5/official_only.nes" "$DEST/nes/official_only.nes"
