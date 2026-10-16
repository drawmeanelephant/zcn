---
title: Commands and defaults
parent: reference/index
status: published
summary: Two commands, the join flag surface, and the RESULT counters.
---

# Command reference

Run from the repository root after `zig build`. `zcn --help` prints the
current usage; flags belong after the command.

## Commands

| Command | Purpose |
|---|---|
| `zcn join --host HOST --user NAME --pass PASS [options]` | Join a session, upload a source, dump decoded peer WAVs |
| `zcn check-wav FILE [--min-rms R]` | Analyze a WAV; exit 1 when RMS < `R` (default `0.001`) |
| `zcn --help` | Usage |

## Join flags

| Flag | Default / behavior |
|---|---|
| `--host HOST[:PORT]` | Required; omitted port defaults to 2049 |
| `--user NAME`, `--pass PASS` | Required; anonymous servers accept any pair |
| `--srate N` | Engine sample rate, 8000–192000 (default 48000) |
| `--channel NAME` | Local channel name; repeatable, max 4 |
| `--source tone:FREQ:AMP\|silence` | `tone:440:0.5`; ignored when `--live` opens a device |
| `--duration S` | `20`; hard cap in `(0, 86400]` |
| `--out-dir DIR` | `dump`; receives decoded peer WAVs |
| `--transcript FILE` | `<out-dir>/transcript.log` |
| `--live` | Capture the local device and play the decoded peer mix |
| `--chat TEXT` | Send one public MSG after joining |
| `--chat-delay S` | `1.5`; `0` sends the message at join |
| `--live-period N` | `480` frames (10 ms at 48 kHz) |
| `--audio-device ID` | System default device |
| `--play-wav FILE` | Dump the post-mix signal handed to the device |

## RESULT counters

The final `RESULT ok=...` line reports, among others:

| Field | Meaning |
|---|---|
| `intervals_uploaded` / `intervals_downloaded` | Complete intervals each way |
| `wav_count` | Decoded peer WAVs written to `--out-dir` |
| `live` | Whether a real device was opened |
| `device`, `dev_srate` | Opened device name and rate |
| `capture_frames`, `capture_starved`, `capture_rms` | What the mic actually delivered |
| `playback_frames`, `playback_rms`, `audio_overruns` | What the mix actually sent to the device |

`ok=true` requires the negotiated intervals both ways with no protocol
errors. With `--live`, silence or starvation shows in the counters — the run
cannot pass on a quiet lie.
