---
title: Under the hood
parent: index
status: published
summary: Contributor map for the protocol engine, vendored codecs, and evidence harness.
---

# Serious machinery. Frozen protocol.

The repo is one binary, one vendored codec/audio tree, and one opt-in demo:

| Location | Owns |
|---|---|
| `src/main.zig` | CLI: `join`, `check-wav`, flag parsing |
| `src/net.zig` | TCP plus the 5-byte message framing |
| `src/proto.zig` | Every message type in and out |
| `src/auth.zig` | The double-SHA1 auth reply |
| `src/session.zig` | Login FSM, interval engine, downloads, chat, live wiring |
| `src/audio.zig` | miniaudio shim, ring buffers, rate conversion |
| `src/vorbis.zig` | stb_vorbis decode, libvorbis encode |
| `src/wav.zig` | WAV writer and RMS/peak analysis |
| `src/buf.zig`, `src/clock.zig`, `src/log.zig` | Buffers, monotonic time, transcript writer |
| `vendor/` | Pinned upstream codec/audio sources |
| `tools/refpeer.cpp` | Headless driver of the reference client core |
| `demo/run_demo.sh` | The four-scenario acceptance harness |
| `docs/PROTOCOL.md` | The wire spec, written against the C++ tree |

- [[contributors/architecture|Architecture]]: how the single-threaded session fits together.
- [[contributors/vendoring|Vendoring]]: pins, provenance, and how to bump a dependency.
- [[contributors/testing|Testing and CI]]: byte-golden tests, the platform matrix, and the demo.

This is a protocol conformance client, not a product. Keep it small enough
that one person can still read every line.
