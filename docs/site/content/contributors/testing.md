---
title: Testing and CI
parent: contributors/index
status: published
summary: Byte-golden unit tests, a three-OS matrix, and an opt-in live demo.
---

# Tested against the spec, not the mood

## Unit tests

```bash
zig build test
```

`src/tests.zig` pulls in every module. The protocol tests are byte-golden
against the worked transcript in `docs/PROTOCOL.md` — when the spec and the
code disagree, the test says which one moved. WAV, Vorbis, and ring-buffer
behavior are covered the same way.

## The CI matrix

`.github/workflows/ci.yml` runs on macOS, Linux, and Windows:

1. `vendor/refresh-vendor.sh --check` — vendored tree matches upstream pins.
2. `zig build test --summary all`.
3. `zig build -Doptimize=ReleaseSafe`, then `--help` plus a `check-wav`
   smoke against a committed evidence WAV.
4. On Linux: a cross-built `x86_64-linux-musl` binary asserted statically
   linked.

## The demo is the e2e gate — when you ask for it

`demo/run_demo.sh` needs a `drawmeanelephant/ninjam` checkout, a C++
toolchain, and (for scenarios 3–4) a real audio device, so it is opt-in
rather than a per-commit gate. When it runs it proves the four scenarios in
[[guides/demo|the demo guide]] and files the receipts under
`demo/evidence/<timestamp>/`.

## What to run before a PR

- `zig build test` — always.
- `bash vendor/refresh-vendor.sh --check` — when `vendor/` moved.
- `bash docs/test_examples.sh` — when the documented commands changed.
- `NINJAM_REPO=... bash demo/run_demo.sh` — when `src/session.zig`,
  `src/proto.zig`, or `src/net.zig` moved and a server+device are handy.

The binary's own `--help` and the [[reference/cli|command reference]] are
the contract for CLI behavior; docs that disagree with the binary are a
docs bug.
