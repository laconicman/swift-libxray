# Review Guidelines

swift-libxray re-hosts XTLS/libXray's official cgo artifact and wraps its `CGoInvoke` JSON
API in `XrayCore`. `Sources/XrayCore/XrayCore.docc/Design.md` is authoritative; check
changes against it.

## Critical Areas

- Flag a `CGoInvoke` answer that is not copied with `String(cString:)` before `CGoFree`, or
  a path in `Sources/XrayCore/Invoke.swift` where a non-null answer escapes `CGoFree` —
  error envelopes included.
- Flag anything `nonisolated` on `XrayCore`, or an engine call that bypasses the actor: one
  Go runtime exists per process, and the actor is its only door.
- Require `url` and `checksum` in `Package.swift`'s `.binaryTarget` to change together, and
  a matching `Upstream/<tag>.json` in the same PR — written by `libxray-asset-tool`, never
  by hand.
- Flag a public signature in `Sources/XrayCore/` that names a `LibXray` type, or a
  `public import LibXray` anywhere: the engine is an implementation detail.
- Flag an untyped `throws` on a public `XrayCore` member; it must be `throws(XrayError)`,
  with the engine's message verbatim — never `String(describing:)` of a response payload.

## Conventions

- Flag test code that opens a non-loopback connection: the suite is offline — `NWListener`
  echo servers, converted configs with invented credentials, never a real server.
- Flag a version assertion not updated alongside an `Upstream/` record or `url`/`checksum`
  bump: `versionMatchesEngineAsset` pins the artifact's provenance.
- Require `XrayError` thrown paths to keep `stage` honest: `encode` for envelope
  construction, `invoke` for `success:false`/nil answers, `decode` for unreadable responses.

## Anti-patterns to Flag

- Flag hand-edits to `Upstream/*.json` or re-zips done outside `libxray-asset-tool`.
- Reject `try!` and force unwraps outside `Tests/`, except `URL(string:)!` on a literal
  constant.
- Flag a config string built with interpolated credentials printed or logged anywhere —
  share links carry secrets in cleartext.

## Ignore

- Skip `Upstream/*.json` field order/formatting when the PR says the tool regenerated it.
- Skip `Package.resolved`; the library does not commit it.
