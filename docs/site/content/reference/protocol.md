---
title: Protocol notes
parent: reference/index
status: published
summary: The frozen NINJAM wire format zcn implements, in one page.
---

# The wire in one page

The full specification is [`docs/PROTOCOL.md`](https://github.com/drawmeanelephant/zcn/blob/main/docs/PROTOCOL.md)
in the repository — reverse-engineered from the C++ tree with `file:line`
citations and an exhaustiveness proof of the message set. This page is the
shape of it.

## Transport and framing

- Plain TCP, default port **2049**, `TCP_NODELAY` on every connection. No
  TLS, no proxy negotiation.
- Every message is a **5-byte header** — 1 type byte + `uint32` LE payload
  size, ≤ 16384 — followed by the payload.
- The server talks first: an auth challenge is pushed the moment the
  connection is accepted.

## Handshake

Auth is a double SHA-1: `inner = SHA1(user ":" pass)`, then
`reply = SHA1(inner || challenge)`. After the reply the client sends its
channel definitions (`SetUsermask`-style local channel info) and the session
enters steady state.

## Steady state

- **Intervals, not streams.** The server broadcasts a per-session BPM/BPI;
  everyone uploads each interval and hears the results one interval later.
- **Uploads** are Ogg Vorbis, one mono VBR stream per local channel —
  `vorbis.zig` drives vendored libvorbis to match the reference encoder.
- **Downloads** arrive as per-channel Ogg streams; `stb_vorbis` decodes them
  to PCM for the WAV dumps and the live mix.
- **Chat** is a plain MSG in both directions; **keepalives** are empty
  messages that must be answered on schedule.

## Where it lives in the tree

| Area | Source | Spec section |
|---|---|---|
| Framing, transport | `src/net.zig` | §1–2 |
| Message payloads | `src/proto.zig` | §5 |
| Auth reply | `src/auth.zig` | §4.3 |
| Login FSM, interval engine, downloads, chat | `src/session.zig` | §4, §6–8 |
| Codec bindings | `src/vorbis.zig` | §6 |
| Live device path | `src/audio.zig` | — |

When the spec and a peer disagree, the transcript in `--transcript` shows
which side blinked first.
