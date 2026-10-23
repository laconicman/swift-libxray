# TechDebt

Numbered register of known compromises. Code references an item as `TODO(TD-n)`.

## Overview

Each item states its **Cost** (what it hurts today) and **Discharge** (the change that
retires it). Status: **open** or **discharged**; ids are never reused.

### TD-1 — upstream publishes no checksums — *open*

XTLS/libXray's releases carry no hashes, signatures or SBOM. Our chain is therefore
self-made: `libxray-asset-tool` hashes the upstream zip as downloaded and the re-zipped
asset as produced, and commits both to `Upstream/<tag>.json`; the release notes repeat them;
`Package.swift` pins the checksum.

**Cost:** a tampered or corrupted upstream zip is detected only by comparing the recorded
hash against a second download — which the tool does not do (it downloads once). The record
proves what *was* fetched, not that upstream still serves it.

**Discharge:** upstream starts signing or checksumming; until then, a re-run of the tool
that reports a *different* upstream SHA-256 for the same tag is the alarm — re-verify
before trusting it.

### TD-2 — the asset carries slices macOS consumers don't need — *open*, [#1](https://github.com/laconicman/swift-libxray/issues/1)

The published zip is all five slices (~101 MB zipped, ~297 MB unpacked): iOS device,
iOS simulator and both tvOS slices ride along for a macOS CLI.

**Cost:** every consumer and CI run pays the 101 MB download and SwiftPM's cache for
slices it never links — the linker pulls only the needed arch out of the macOS slice
either way, so the consumer binary is unaffected. (The ~39 MB figure in early notes was
the ios-arm64 *archive* size, not binary cost.)

**Discharge:** ship a parallel macOS-only slim asset under its own artifact tag
(`libxray-macos-vX.Y.Z`); `libxray-asset-tool` already produces the zip — add a slice
filter. Roadmap, *Later*.

### TD-3 — the asset tool shells out to unzip and zip — *open*

`libxray-asset-tool` runs `/usr/bin/unzip` and `/usr/bin/zip` via `Process` rather than
reading the archives itself. Deliberate: the re-zip must match the spike's verified command
byte for byte, and a Foundation-level archiver would re-decide metadata the checksum
depends on.

**Cost:** macOS-only maintainer tool (fine — it is one), and the zip's directory
timestamps are whatever `zip` writes, so the checksum depends on `zip`'s output, not on a
canonical form we control.

**Discharge:** none needed while `zip` output stays deterministic across runs — verified
twice on v26.10.21 (same sha256). If it ever differs, pin the format inside the tool
instead of trusting the CLI.

### TD-4 — `-lresolv` was found empirically — *open*

The link needs `res_9_ninit`/`nsearch`/`nclose` and nothing else, discovered by building,
not documented upstream. The archive also references `Sec*`/`CF*` symbols, which resolved
through the SDK without explicit frameworks — on this toolchain, for this link.

**Cost:** an engine bump could pull archive objects that need more (a Security.framework
flag, say) and the failure would surface at a consumer's link, not ours.

**Discharge:** none beyond the build catching it — the cost is one linker flag added to
`linkerSettings` when it happens.

### TD-5 — `runXray` has no readiness signal — *open*, [#3](https://github.com/laconicman/swift-libxray/issues/3)

`run` returns in ~1 ms while the core finishes starting ~350 ms later (measured
2026-10-23): the API answers success before the inbounds listen. `getXrayState` flips true
immediately, so it can't serve as a barrier either.

**Cost:** every consumer re-implements "poll the inbound socket" — the test suite's
`waitForAccept` is the reference.

**Discharge:** upstream adds a readiness method or `runXray` blocks until listening; or
this package grows an opt-in `run(configJSON:awaitingInbound:)` that polls a named inbound.

### TD-6 — Xray logs to stderr, no API — *open*, [#3](https://github.com/laconicman/swift-libxray/issues/3)

The core writes its banner and per-connection `accepted` lines straight to stderr; the JSON
API exposes no log stream and no level control beyond the config's `log` block.

**Cost:** a consumer that owns stderr (an MCP stdio server, say) must silence Xray in the
config (`"access":"none"`, `"loglevel"`) or capture the descriptor itself.

**Discharge:** upstream grows a log callback or file redirect. Nothing to patch around
here — fd redirection would hide Xray's own crash output too.

## See Also

- <doc:Design>
- <doc:Roadmap>
