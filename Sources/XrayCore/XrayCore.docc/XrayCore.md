# ``XrayCore``

Xray-core for Swift: the official XTLS/libXray Apple cgo build, wrapped in one actor.

## Overview

`XrayCore` packages `LibXray.xcframework` — XTLS/libXray's unmodified
`buildmode=c-archive` artifact — as a SwiftPM binary target, and puts a typed façade in
front of its `CGoInvoke` JSON API. The artifact embeds one Go runtime per process, so the
actor ``XrayCore/shared`` is its only door: every call is serialized there.

The API mirrors libXray's methods one to one: `xrayVersion`, `getFreePorts`,
`convertShareLinksToXrayJson`, `testXray`, `runXray`, `stopXray`, `getXrayState`. Two
engine behaviors to plan around:

- ``XrayCore/run(configJSON:)`` returns before the inbounds accept (~1 ms call vs ~350 ms
  to accept, measured on macOS 26). Probe the inbound itself before sending traffic.
- Xray writes its log to stderr; the JSON API has no log hook. `"log":{"access":"none"}`
  quiets the per-connection lines.

`convertShareLinks` returns `{"outbounds":[…]}` in the flat shape this core builds:
`settings` carries `{address, port, id, encryption}` directly (no `vnext`), `pbk` lands in
`realitySettings.password`, and the link's `#fragment` becomes the outbound's `tag`.

## Topics

### Essentials

- ``XrayCore``
- ``XrayError``

### Project Direction

- <doc:Design>
- <doc:Roadmap>
- <doc:TechDebt>
