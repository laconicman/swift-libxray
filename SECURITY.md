# Security

## Scope

This package re-hosts a binary: `LibXray.xcframework`, XTLS/libXray's official Apple cgo
build, re-zipped to the archive-root layout SwiftPM wants and published on this repo's
Releases. It holds no secret of its own, and the library never sends anything anywhere —
Xray traffic is whatever a consumer's config asks for. The security-relevant surface is
*what the artifact is*:

- **Verify the re-hosted asset against upstream.** `Upstream/<tag>.json` records the
  upstream zip's URL, SHA-256 and byte size as fetched, next to the published asset's
  SHA-256 (the value `Package.swift` pins as its checksum) and byte size. To check by hand:
  download `https://github.com/XTLS/libXray/releases/download/<tag>/libxray-apple-cgo.zip`,
  `shasum -a 256` it against the record, then `swift run libxray-asset-tool <tag>` and
  compare the produced asset hash.
- **The only transformation is the zip layout.** Inside the artifact, the xcframework is
  byte-identical to upstream's; `unzip -l` shows it moved from under `libxray-apple-cgo/`
  to the archive root.
- **One Go runtime.** The artifact embeds a Go runtime whose DNS resolver and TLS roots
  behave as upstream built them; `XrayCore` adds no code inside the trust boundary beyond
  the `CGoInvoke`/`CGoFree` envelope, and every answer string is freed exactly once.

Defects in Xray-core or libXray themselves belong to
[XTLS](https://github.com/XTLS/libXray) — report them upstream; note here if the fix needs
an asset bump.

## Reporting

Use GitHub's private vulnerability reporting on this repository (Security → Report a
vulnerability). Please do not open a public issue for something that could expose a proxy
credential — share links carry secrets in cleartext.
