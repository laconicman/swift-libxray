# Roadmap

Priority-ordered milestones; each lands through pull requests with review rounds. The why
is in <doc:Design>.

## Overview

### Now

- **M0 — the package (0.1.0).** `XrayCore` over the official cgo artifact:
  version / freePorts / convert / test / run / stop / isRunning, typed `XrayError`,
  `libxray-asset-tool` + `Upstream/` provenance, the offline suite, docs and house files.
  *Done when:* `swift build` and `swift test` are green with zero warnings in handwritten
  targets, the asset's provenance is recorded, and consumer `elsewhere` links it.

### Next

- **M1 — reach further into the API (0.2.0).** `pingBatch` (per-config latency without
  owning the engine's lifecycle), iOS build verification against a simulator slice, and the
  upstream-bump workflow exercised once end to end (new tag → tool → record → snippet →
  release), with the byte-reproducible re-zip from TD-3 landing in the same bump; and the
  engine's lifecycle edges pinned by tests — `run` while running, `test(configJSON:)`
  while running, `stop` when already stopped — so consumers can rely on them.

### Later

- A **macOS-only slim asset** (the macOS slice alone instead of five slices in every
  download and cache) — published under a second artifact name so consumers choose; the
  checksum story is already the tool's.
- **tvOS**, if a consumer appears: the slices ship in the artifact today; only the manifest
  floors and a CI lane are missing.
- A **readiness hook** if upstream grows one (TD-5), and a **log hook** if it grows one
  (TD-6) — both are upstream-shaped debts, not ours to patch around.

## See Also

- <doc:Design>
- <doc:TechDebt>
