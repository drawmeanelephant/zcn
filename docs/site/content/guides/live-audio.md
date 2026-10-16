---
title: Live audio
parent: guides/index
status: published
summary: One duplex device feeds the uplink and plays the decoded peer mix.
---

# Mic in, mix out

`--live` swaps the synthetic source for the real device: capture frames feed
the upload path, and the decoded peer mix is pushed to the output. One
miniaudio duplex device does both, so capture and playback share a clock.

```bash
zig-out/bin/zcn join --host 127.0.0.1:2049 --user alice --pass secret \
  --live --duration 30 --out-dir dump --play-wav playback-mix.wav
```

## Tune the device

| Flag | Default | What it does |
|---|---|---|
| `--live` | off | Open the local duplex device instead of a synthetic source |
| `--live-period N` | `480` (10 ms at 48 kHz) | Device period in frames |
| `--audio-device ID` | system default | miniaudio device id |
| `--play-wav FILE` | off | Dump the post-mix signal handed to the device |

`--play-wav` is the honest mirror: the exact samples delivered to the output
ring, written to a file you can `check-wav`. If the device never delivers
real audio, that file is silent and the energy check fails — which is the
point.

## More than one channel

Repeat `--channel` to put multiple local channels on the wire:

```bash
zig-out/bin/zcn join --host H --user U --pass P --live \
  --channel voc --channel gtr
```

All local channels share the single capture signal; there is no per-channel
source selection. Two microphones need two devices or a channel mixer, and
that is deliberately out of scope. The demo's fourth scenario exercises this
path end to end: both channels must stream, and the reference client must
decode real audio on *both* — the check that they stay aligned rather than
time-shifting apart.

## When the device says no

Live audio is compiled in everywhere but verified on macOS/Core Audio only —
the Linux builds compile miniaudio's ALSA/PulseAudio/JACK backends out, so
there is no Linux audio backend to exercise. `-Dlive=false` (the default
off macOS) or a failed device open falls back to the synthetic `--source`
with a logged warning, so a headless box still produces a valid session.

Device counters in the `RESULT` line — `capture_frames`, `capture_starved`,
`capture_rms`, `playback_frames`, `playback_rms`, `audio_overruns` — are
measured on the session thread as samples cross the ring boundary. A starved
capture shows up in the numbers, not just in your ears.
