---
title: Architecture
parent: contributors/index
status: published
summary: One poll loop drives the network and the device; nothing else runs.
---

# One loop to feed them all

zcn is deliberately single-threaded: one `poll` loop in `src/session.zig`
drives the socket, the interval clock, and the live device. There are no
worker threads to reason about — if two things disagree, the transcript
shows the order it happened in.

## The shape of a session

1. `main.zig` parses flags and hands a session config to `session.zig`.
2. `net.zig` opens TCP with `TCP_NODELAY` and frames every message as
   `type byte + u32le size + payload` (≤ 16384).
3. The server's challenge arrives first; `auth.zig` answers with the
   double-SHA1 reply, and local channels are declared.
4. Steady state: each interval, `vorbis.zig` encodes the local source into
   per-channel Ogg streams for upload, while downloads are stb_vorbis
   decoded to PCM — to WAV files always, and to the output ring when live.
5. `wav.zig` buffers s16le dumps in memory and writes once at close;
   `log.zig` mirrors every event to stderr and `--transcript`.

## Deliberate choices

- **No NINJAM C++ code.** The Zig sources are a clean-room implementation
  of `docs/PROTOCOL.md`; the C++ tree is only ever ground truth, consulted
  through `tools/refpeer.cpp` at demo time.
- **Framing tolerates the wire.** Partial frames return `WouldBlock` and
  buffered bytes are drained before the next poll; malformed steady-state
  frames are dropped and logged instead of killing the session.
- **Bounded memory.** Decoded PCM is capped by the protocol's interval
  ceiling, and channel IDs above 32 are ignored — a hostile or buggy peer
  cannot make the client grow without limit.
- **Hand-rolled primitives.** `buf.zig` avoids `std` container API churn;
  Zig release churn is the project's main maintenance risk.

## What changes it

- **A protocol change** — update `docs/PROTOCOL.md` first, then
  `src/proto.zig`; the unit tests are byte-golden against the spec's worked
  transcript.
- **A new Zig release** — `build.zig` and `std.Io` usage; CI is the
  tripwire.
- **A server behaviour change** — `demo/run_demo.sh` should fail, with the
  transcript showing where.
