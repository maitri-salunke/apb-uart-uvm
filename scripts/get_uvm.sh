#!/usr/bin/env bash
# Fetch the Accellera UVM (IEEE 1800.2-2020, 2020.3.2) kit maintained for Verilator
# by CHIPS Alliance, pinned to the commit this project was verified with.
set -euo pipefail
DEST="$(cd "$(dirname "$0")/.." && pwd)/third_party/uvm-verilator"
REV=5d72b6618acfddece7f09382a032ccbc05862fdc
if [ ! -d "$DEST/.git" ]; then
  git clone https://github.com/chipsalliance/uvm-verilator.git "$DEST"
fi
git -C "$DEST" fetch --depth 1 origin "$REV" 2>/dev/null || true
git -C "$DEST" checkout -q "$REV"
echo "UVM at $DEST ($REV)"
