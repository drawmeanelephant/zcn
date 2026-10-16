---
title: Sessions and sources
parent: guides/index
status: published
summary: Join a server, choose what you upload, and read what comes back.
---

# Be a good wire citizen

A session is one TCP connection, one authenticated handshake, and then a
steady march of intervals: you upload your audio each interval, the server
re-broadcasts everyone's uploads a bar later, and you decode what comes back.

## Join

```bash
zig-out/bin/zcn join --host 127.0.0.1:2049 --user alice --pass secret \
  --source tone:440:0.5 --duration 30 --out-dir dump
```

`--host` accepts `host`, `host:port` (default port 2049). Registered servers
want real credentials; anonymous servers take any username. Auth is the
protocol's double-SHA1 challenge reply — see [[reference/protocol|the protocol notes]].

## Choose a source

| Source | What it uploads |
|---|---|
| `tone:FREQ:AMP` | A mono sine at `FREQ` Hz, amplitude `0 < AMP ≤ 1` (default `tone:440:0.5`) |
| `silence` | Digital zero — the negative control spelling |
| `--live` | The local capture device; see [[guides/live-audio|Live audio]] |

Uploads are encoded as Ogg Vorbis, one mono VBR stream per local channel,
matching the reference client. `--channel NAME` names a local channel and is
repeatable up to four; `--srate N` sets the engine rate (8000–192000,
default 48000).

## Talk, then listen

`--chat "TEXT"` sends one public message after joining; `--chat-delay S`
controls how long to wait (default 1.5 s, 0 sends immediately). Incoming
chat lands in the transcript.

Everything the client does is logged to stderr and to `--transcript FILE`
(default `<out-dir>/transcript.log`): protocol messages, timings, and
per-interval decode results. Decoded peer audio is dumped to `--out-dir`
as WAV, one file per remote channel per interval.

## Read the RESULT

Every session prints one machine-readable line:

```
RESULT ok=true intervals_uploaded=4 intervals_downloaded=4 wav_count=1
       live=false capture_frames=0 playback_rms=0.000000 ...
```

`ok=true` requires the negotiated number of complete intervals both ways
with no protocol errors. When `--live` is on, the line also carries
`device`, `dev_srate`, `capture_frames`, `capture_starved`, `capture_rms`,
`playback_frames`, `playback_rms`, and `audio_overruns` — measured where
samples cross the ring boundary, not inferred from a clean exit.

## Know the clock

NINJAM does not stream live; it trades intervals. What you play now is heard
by everyone else one interval later, which is why `--duration` counts in
seconds but the transcript counts in intervals. `--duration` is a hard cap
(default 20 s): the client finishes the current interval, drains downloads,
and exits cleanly.
