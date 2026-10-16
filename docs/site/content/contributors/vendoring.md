---
title: Vendoring
parent: contributors/index
status: published
summary: Pinned upstream sources, refreshed by one script, checked in CI.
---

# Vendored, verifiably

Everything `zcn` links beyond libc and the system audio frameworks lives in
`vendor/` as pinned upstream source — no package manager, no submodule, no
fetch at build time.

## What is vendored

| Source | Role |
|---|---|
| `stb_vorbis.c` | Decode of downloaded peer Ogg streams |
| `libogg` + `libvorbis` | Encode of local channel uploads (matches the reference client's encoder) |
| `miniaudio.h` | The live duplex device (Phase B) |
| `vendor/patches/` | Local deltas applied on top of upstream pins |

`vendor/README.md` records each upstream's license; the vendored files keep
their own notices.

## The pin is the contract

`vendor/refresh-vendor.sh` downloads each pinned upstream and rewrites the
tree; `--check` proves the committed tree still matches those pins:

```bash
bash vendor/refresh-vendor.sh --check   # run in CI on every commit
```

Bumping a dependency is deliberately boring: edit the pin in
`refresh-vendor.sh`, rerun it, rerun `--check`, then `zig build test` and
the demo. If a CVE lands in libvorbis, libogg, stb, or miniaudio, that is
the entire procedure.

## Why not translate-c

`miniaudio.h` is four megabytes of macro soup and does not survive
translate-c, so it is compiled in exactly one C TU
(`vendor/miniaudio_impl.c`) behind a tiny shim in `src/audio.zig`. The same
pattern wraps the Vorbis encoder in `vendor/vorbis_c.h` — Zig calls the
shims, never the macro jungle.
