# Design

The load-bearing decisions, why they were made, and what was rejected.

## Overview

One decision per subsection. This article is authoritative: when a code comment and this
document disagree, this document wins. Milestones live in <doc:Roadmap>, known compromises
in <doc:TechDebt>.

The decisions draw on a spike run 2026-10-23 on macOS 26.6 (arm64, Swift 6.4): the official
`libxray-apple-cgo.zip` was linked into a SwiftPM executable and its JSON API exercised end
to end — including a `mixed` inbound proxying a real `URLSession` fetch, and a
`sockopt.interface`-bound freedom outbound. The spike's measurements are cited below.

### The official cgo build, re-zipped, re-hosted

The engine is `XTLS/libXray`'s own Apple artifact — `go build -buildmode=c-archive` per
slice, lipo'd per SDK, five slices (macos-arm64_x86_64, ios-arm64,
ios-arm64_x86_64-simulator, tvos-arm64, tvos-arm64_x86_64-simulator). Two things had to
change for SwiftPM, and exactly two:

- **Layout.** The upstream zip nests `LibXray.xcframework/` under `libxray-apple-cgo/`;
  `binaryTarget` wants it at the archive root, so it is re-zipped (`zip -r -X`, the spike's
  command — reproducible: it re-hashes identically on re-run).
- **Host.** The re-zip has to live somewhere a manifest can pin — this repo's Releases,
  under artifact tags `libxray-vX.Y.Z` that semver resolution ignores. Pinning our own copy
  also insulates consumers from upstream re-tagging or deleting an asset (their release
  workflow marks releases prerelease); the checksum guards the content either way. The
  provenance record is `Upstream/<tag>.json`, written only by `libxray-asset-tool` —
  upstream publishes no checksums, so this record *is* the provenance (TD-1).

*Rejected:*

- **Building Xray-core from source:** a Go toolchain and a gomobile-style pipeline in the
  consumer's build graph; the official build is already the upstream's product.
- **dima-u's wrappers.** `dima-u/SwiftyXrayCore` 1.1.0 (2025-12-26) bundles Xray 25.10.15
  with Outline's tun2socks in one gomobile framework; `dima-u/SwiftyXrayKit` 2.0.0
  (2026-05-13) depends on `dima-u/libXray-apple` `v26.3.27-ios`, a fork built on a patched
  Xray-core (`dima-u/Xray-core-apple`) so the TUN inbound works over a `SOCK_STREAM`
  socketpair inside the iOS Network Extension sandbox. Both exist to solve the
  packet-tunnel problem; this package has none and tracks the unmodified upstream.
- **Committing the xcframework:** ~297 MB unpacked, ~101 MB zipped — past GitHub's 100 MB
  file limit anyway; Git LFS is not an option (SwiftPM doesn't run the smudge filter).
- **A macOS-only slim asset now:** the fat artifact costs the 101 MB download and cache —
  the consumer binary is unaffected, since the linker pulls only the needed arch out of the
  macOS slice. Slimming is on the roadmap; correctness of the full artifact came first.

### One actor over one Go runtime

The artifact exports `CGoInvoke` / `CGoFree` and nothing else: every API call is a JSON
envelope `{"apiVersion":3,"method":…,"payload":…}` in, `{success,data,error}` out. The Go
runtime is process-global — there is exactly one engine, and ``XrayCore/shared`` is the
only door to it. The actor both serializes calls and reads as what it is: a scarce,
stateful resource, not a value.

`Invoke.call` owns the C boundary once: `withCString` + `UnsafeMutablePointer(mutating:)`
for the non-const `char *` parameter (upstream copies it into a Go string on entry), a
`String(cString:)` copy out, `CGoFree` on every non-null answer including error envelopes.
Envelope parsing is `JSONSerialization` (the response shape is a contract, not a schema);
`data` is re-serialised to `Data` and decoded per-method into tiny `Decodable` structs.
Nothing nonisolated exists on the actor.

*Rejected:*

- **Free functions over the C API:** every caller would re-learn the free/copy rule and the
  envelope grammar; one funnel makes the rules structural.
- **`Codable` for the envelope:** `data` is `Any` — sometimes an object, sometimes `{}`,
  sometimes null — so a dynamic pass is the honest model.
- **Callback/async API:** `CGoInvoke` is synchronous and fast (see next section); wrapping
  it in a callback shape would simulate asynchrony it doesn't have.

### Synchronous calls are honest calls

Measured on the spike (debug build, ContinuousClock): the first `CGoInvoke` in a process
costs 16 ms (Go runtime cold start); `getFreePorts` 2.9 ms; `testXray` 0.4 ms; `runXray`
1.4 ms and `stopXray` 0.1 ms on every later call. These are microseconds-to-milliseconds —
blocking the actor's executor for them is correct, and pretending otherwise would only add
a dispatch hop.

The one asymmetry that matters is `runXray`: it *returns* in ~1 ms, but the core finishes
starting ~350 ms later — the spike's first inbound accept came ~350 ms after `run`. `run`
documents this; there is no readiness signal in the API (TD-5), so callers probe the
inbound port.

### The flat outbound shape is a contract

`convertShareLinksToXrayJson` does not emit the classic Xray outbound (`vnext`/`users`). It
emits the flat shape — `settings:{address, port, id, encryption:"none"}`,
`realitySettings.password` for `pbk`, `shortId` for `sid`, `spiderX` for `spx`,
`xhttpSettings` only when `path`/`mode` are present, `#fragment` → `tag` and never
`sendThrough`. The suite splices a converted outbound into a full config and passes it
through `testXray`, so a format regression fails a test, not a proxy session.

`convertShareLinks` returns the raw `Data` instead of a typed outbound: the shape is
Xray's, it evolves with the engine, and the caller splices it verbatim into a config it
already owns. Typing it would buy a shadow model to keep in sync.

### Typed errors, three stages

Every method throws `XrayError` (`throws(XrayError)`) with the method name, the stage —
`encode` (envelope construction), `invoke` (the engine answered `success:false`, or
`CGoInvoke` returned nil), `decode` (the response couldn't be read) — and the engine's
message verbatim. `stage` is what a caller branches on; `message` is what a human reads.

### Platforms and linking

`platforms` are the artifact's own floors, not ours: macOS 13.0 (the slice's `go.o` says
13.0; its Go objects say 12.0 and the linker takes the max — the upstream's advertised 12.0
is wrong) and iOS 15.0. The xcframework's tvOS slices stay undeclared: no consumer, and an
undeclared floor is more honest than an unverified one.

Linking needs exactly one extra input: `.linkedLibrary("resolv")`, for Go's cgo resolver
(`res_9_ninit`/`nsearch`/`nclose`, the only undefined symbols a consumer link reported on
macOS 26). The archive's `Sec*`/`CF*` references resolve through the SDK without flags —
found empirically, hence TD-4.

*Rejected:* declaring tvOS/watchOS floors on slices nobody built against; and a
`systemLibrary` shim for resolv, which the single linker line already covers.

## See Also

- <doc:Roadmap>
- <doc:TechDebt>
