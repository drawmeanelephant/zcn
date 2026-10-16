---
title: Platform support
parent: reference/index
status: published
summary: macOS gets the microphone; everyone gets the wire.
---

# Platform support

| Platform | Build | Live audio | Notes |
|---|---|---|---|
| macOS | `zig build -Doptimize=ReleaseSafe` | yes, verified | Core Audio via miniaudio; the only platform where `--live` is exercised end to end |
| Linux | `-Dtarget=x86_64-linux-musl -Dlive=false` | no backend | Fully static musl binary is a CI artifact; miniaudio's ALSA/PulseAudio/JACK backends are compiled out, so there is nothing to verify |
| Windows | `zig build -Doptimize=ReleaseSafe` | unverified | Builds and tests in CI over winsock2; `--live` compiles but is not exercised |

## The `-Dlive` option

| Option | Default | Meaning |
|---|---|---|
| `-Dlive=true\|false` | `true` for macOS targets, `false` elsewhere | Permit the live device at runtime |

miniaudio is always compiled in; the flag only gates the runtime check in
`session.openLive`. `false` — or a failed device open — falls back to the
synthetic `--source`, so headless and server builds still join sessions
cleanly.

## CI coverage

`.github/workflows/ci.yml` builds and tests on macOS, Linux, and Windows,
verifies `vendor/` against upstream pins, and smoke-tests the binary against
a committed evidence WAV. Linux additionally cross-builds the static musl
binary and asserts it is statically linked.
