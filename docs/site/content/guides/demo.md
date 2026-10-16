---
title: The end-to-end demo
parent: guides/index
status: published
summary: Two clients, a reference peer, an unmodified server, and a silence trap.
---

# Prove it on a real server

`demo/run_demo.sh` is the acceptance harness. No mocks: it builds the
unmodified reference `ninjamsrv` from a C++ NINJAM checkout and runs real
sessions against it.

```bash
NINJAM_REPO=/path/to/ninjam bash demo/run_demo.sh
```

`NINJAM_REPO` defaults to a sibling `../ninjam` checkout and must be a
[drawmeanelephant/ninjam](https://github.com/drawmeanelephant/ninjam) clone —
the script drives its CMake build, which upstream does not ship. First run
needs cmake, a C++ toolchain, and network access for the reference client's
FetchContent dependencies.

## What it proves

1. **zcn ↔ zcn.** Two instances — registered user `alice` and anonymous
   `bob` — exchange at least three full intervals of audio and chat in both
   directions. Every decoded WAV must beat an RMS floor, with a silence
   negative control.
2. **zcn ↔ reference client.** `tools/refpeer.cpp` is a headless driver of
   the reference client core (`ninjam/njclient.cpp`). The reference client
   must decode zcn's upload; zcn must decode the reference tone to a
   non-silent WAV.
3. **Live audio.** `--live` against the same reference peer: the device must
   really open, real microphone frames must reach the upload (and be decoded
   by the reference client), and the peer mix must reach the output ring —
   mirrored to `--play-wav` and energy-checked. Skipped with a clear message
   when the machine has no usable device.
4. **Multi-channel live.** Two local channels off the same device. Both must
   stream and the reference client must decode real audio on both — the
   end-to-end check that the channels stay aligned.

## What it leaves behind

Each run writes `demo/evidence/<timestamp>/` — transcripts, per-scenario
summaries, the refpeer reports, server log, unit-test output, and WAV
analysis. Only the newest run stays under version control, and committed
WAVs are 1-second excerpts plus the silence negative control: enough to show
the audio was real without carrying recordings in the repo.

The demo is opt-in, not a CI gate — it needs the C++ checkout and a device
for the live scenarios. The standing gate is `zig build test` plus the CI
matrix; see [[contributors/testing|Testing and CI]].
