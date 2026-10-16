---
title: Troubleshooting
parent: reference/index
status: published
summary: Auth failures, silent runs, and where the evidence lives.
---

# When the wire pushes back

Everything below is diagnosable from the transcript (`--transcript`, default
`dump/transcript.log`) and the `RESULT` line. Start there before starting a
debugger.

## Join fails before audio

| Symptom | Likely cause |
|---|---|
| Connection refused | Wrong `--host`/`--port`, or the server is not actually `ninjamsrv` |
| `bad port in --host` | Port out of range or trailing garbage after `host:port` |
| Auth rejected | Wrong credentials on a registered server; anonymous servers accept anything |
| Immediate disconnect after auth | Server at user capacity, or a license/agreement message in the transcript |

## A session that "passes" silently

`check-wav` and the `RESULT` counters exist for this exact lie:

- `intervals_downloaded=0` with `ok=false` — the download path stalled; the
  transcript shows whether the server stopped sending or the client stopped
  parsing. Malformed steady-state frames are dropped and logged rather than
  fatal, so look for repeated drop lines.
- `wav_count=0` — no complete remote channel ever decoded; check that the
  peer actually uploaded (their intervals are announced in the transcript).
- `check-wav` exits 1 — the WAV decoded but has no energy. On live runs also
  compare `capture_rms` and `playback_rms` in the `RESULT` line.

## Live audio problems

- `--live` falls back to `--source` with a logged warning when the device
  fails to open — on Linux this is expected, since no audio backend is
  compiled in. See [[reference/platforms|Platform support]].
- `--play-wav` silent while the session sounds fine points at the output
  ring, not the room: the file is written from samples after the mix.
- `audio_overruns` climbing means the device period is too small for the
  machine; raise `--live-period`.

## Environment sanity

- `zig version` must print `0.17.0`; the build pins it.
- `bash vendor/refresh-vendor.sh --check` proves the vendored codec/audio
  tree still matches its upstream pins — run it if codec behaviour is in
  doubt.
