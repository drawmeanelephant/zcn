---
title: zcn
status: published
summary: A clean-room NINJAM client in Zig. Real audio, a frozen wire protocol, no C++.
---

<p class="eyebrow">Field manual / zcn</p>

# One interval behind.<br>Right on time. {#welcome .hero-heading}

A from-scratch NINJAM client written in Zig. It speaks the frozen wire
protocol to an unmodified reference server, moves real audio in both
directions, and leaves a paper trail for every claim it makes.

<div class="home-actions">
<a href="getting-started.html">Join your first session</a>
<a href="guides/demo.html">Watch it prove itself</a>
</div>

<div class="specimen-card">
<div class="specimen-card__header">One build. Zero C++.</div>
<div class="specimen-card__body">

```bash
zig build -Doptimize=ReleaseSafe
zig-out/bin/zcn join --host 127.0.0.1:2049 --user alice --pass secret \
  --source tone:440:0.5 --duration 30 --out-dir dump
```

No NINJAM sources, no package manager, no runtime dependency beyond libc and
the system audio frameworks.

</div>
</div>

## Pick your channel

<div class="feature-grid">
<div class="feature-card"><span class="edition-card__tag">01 / Wire</span><h3 id="a-second-opinion">A second opinion on the wire</h3><p>Handshake, auth, interval engine, chat, keepalives — implemented from the spec, checked against the reference server.</p><a href="guides/session.html">Join a session</a></div>
<div class="feature-card"><span class="edition-card__tag">02 / Live</span><h3 id="mic-in-mix-out">Mic in, mix out</h3><p>One duplex device feeds the uplink and plays the decoded peer mix, measured as samples cross the ring boundary.</p><a href="guides/live-audio.html">Go live</a></div>
<div class="feature-card"><span class="edition-card__tag">03 / Proof</span><h3 id="every-claim-transcripted">Every claim, transcripted</h3><p>Machine-readable RESULT lines, dumped WAVs, energy assertions, and a silence negative control that cannot fake a pass.</p><a href="guides/demo.html">See the evidence</a></div>
</div>

## The spec is frozen. The client is not C++.

zcn is a protocol conformance client, not a product. It exists so the NINJAM
wire protocol can be checked against an implementation that was not written by
the same hand as the reference. There is no UI, no mixer, no DAW ambitions —
about 3,500 lines of Zig 0.17 plus vendored codec and audio sources.

In NINJAM, everyone plays "now" and everyone else hears it one interval later.
Being deliberately behind is the protocol. Doing it byte-correctly is the job.
