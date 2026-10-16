#!/usr/bin/env bash
# Hardware-free execution of the documented commands: help text, WAV energy
# analysis on the committed demo evidence, and the silence negative control.
# No server, audio device, or network is touched.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=${ZCN_BIN:-"$ROOT/zig-out/bin/zcn"}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/zcn-doc-examples.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
"$BIN" --help > help.txt 2>&1
grep -q "zcn join" help.txt
EVIDENCE_WAV=$(ls "$ROOT"/demo/evidence/*/sample-decoded-peer-1s.wav | head -1)
"$BIN" check-wav "$EVIDENCE_WAV" --min-rms 0.05
SILENCE_WAV=$(ls "$ROOT"/demo/evidence/*/negative-control-silence.wav | head -1)
if "$BIN" check-wav "$SILENCE_WAV" --min-rms 0.05; then
  echo "silence negative control unexpectedly passed" >&2
  exit 1
fi
echo "Documentation examples and silence negative control pass (no device opened)."
