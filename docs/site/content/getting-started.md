---
title: Start here
parent: index
status: published
summary: Build once, join a session with a synthetic source, and verify the WAVs.
---

# Join your first session

Start with a synthetic source. It proves the protocol path works end to end
without requiring a microphone, a speaker, or a forgiving audience.

## 1. Get the source

Install [Zig 0.17.0](https://ziglang.org/download/) and Git on macOS, Linux,
or Windows. Run these commands in a terminal:

```bash
git clone https://github.com/drawmeanelephant/zcn.git
cd zcn
zig version
zig build test
zig build -Doptimize=ReleaseSafe
```

`zig version` should print `0.17.0`. The build installs one executable,
`zig-out/bin/zcn`. The Ogg/Vorbis, stb_vorbis, and miniaudio sources are
vendored; there is no dependency fetch step.

## 2. Point it at a server

You need a `ninjamsrv` to talk to. The easiest correct one is the reference
server the demo builds for you (see [[guides/demo|the demo guide]]); any
running NINJAM server works the same way.

```bash
zig-out/bin/zcn join --host 127.0.0.1:2049 --user alice --pass secret \
  --source tone:440:0.5 --duration 30 --out-dir dump --chat "hello"
```

`--source tone:440:0.5` uploads a 440 Hz sine at half amplitude — audible,
predictable, and easy to verify on the far side. `--source silence` is the
negative control spelling. Anonymous servers accept any `--user` with an
empty or arbitrary `--pass`.

## 3. Verify what came back

Decoded peer audio lands in `--out-dir` as WAV files, one per remote channel
per interval. `check-wav` measures signal energy and exits non-zero on
silence:

```bash
zig-out/bin/zcn check-wav dump/*.wav --min-rms 0.05
```

The session ends with one machine-readable `RESULT` line and a full
transcript at `--transcript` (default `<out-dir>/transcript.log`). Every
audio number in the result is measured on the session thread, so a silent
run cannot masquerade as a passing one.

## 4. Choose your level of commitment

- [[guides/session|Sessions and sources]]: channels, sample rates, chat, and the interval engine.
- [[guides/live-audio|Live audio]]: swap the tone for a real microphone and speakers.
- [[reference/cli|Command reference]]: every flag, every default.
