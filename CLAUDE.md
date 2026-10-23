# swift-libxray — Xray-core for Swift

The official XTLS/libXray Apple cgo build as a SwiftPM binary target, plus `XrayCore`, a
typed actor façade over its `CGoInvoke` JSON API. One library, one maintainer tool
(`libxray-asset-tool`), one offline test suite.

The DocC catalog (`Sources/XrayCore/XrayCore.docc/`) is authoritative for direction:
`Design` (decisions + rejected alternatives) · `Roadmap` (milestones, one GitHub milestone
each) · `TechDebt` (numbered `TD-n` register, each linked to its issue). The spike that
proved the artifact lives **beside** the repo, not in it: `../elsewhere-consults/spikes.md`
and `../elsewhere-consults/spikes/s1-libxray/`. They are context; when they disagree with
Design, Design wins.

## Architecture

`LibXray` (binary target: the official xcframework, re-zipped to the archive root and
re-hosted on this repo's Releases) → `XrayCore` (façade: `Invoke.call` owns the C boundary
and the envelope; the actor serializes the one Go runtime) → consumers (`elsewhere` and
friends). Maintainer tool: `libxray-asset-tool`. Swift 6.4 tools version, Swift 6 language
mode, macOS 13 / iOS 15 floors (the artifact's own, off its LC_BUILD_VERSIONs), with the
Swift 7 upcoming features on every handwritten target. Each choice is reasoned in `Design`.

## Rules specific to this repository

1. **The artifact changes only through `libxray-asset-tool`.** Re-vendor with
   `swift run libxray-asset-tool <tag>`; publish only as a Release on *this* repo under an
   artifact tag `libxray-vX.Y.Z` (semver tags are the package's own). `url` and `checksum`
   in `Package.swift` always change together. `Upstream/*.json` is tool output — never
   hand-edited.
2. **One Go runtime per process; the actor is its only door.** Every engine call goes
   through `XrayCore.shared`; nothing `nonisolated` touches `Invoke`. Every non-null
   `CGoInvoke` answer is copied then `CGoFree`d — including error envelopes.
3. **`LibXray` never appears in the public API.** `InternalImportsByDefault` enforces it;
   Foundation types that do appear (`Data`) come through an explicit `public import`.
4. **Errors are typed.** Every façade method is `throws(XrayError)`; `stage` is what a
   caller branches on, `message` is the engine's text verbatim — never `String(describing:)`
   of a payload.
5. **Zero warnings in handwritten targets.** The binary target itself is exempt (it is not
   compiled).
6. **Tests are offline.** Loopback only — `NWListener` echo servers, never a real server or
   the public internet. The suite is `.serialized` because the lifecycle tests own the one
   engine.
7. **Everything lands via PR, with review rounds.** Atomic commits that each build. Merges
   are **merge commits only** (squash and rebase are off). A ruleset blocks force-push and
   deletion of `main`. The recipes are in `docs/GitHubWorkflow.md`.
8. **One public identity, no AI attribution.** Commits only as
   `laconicman <laconicman@icloud.com>`; check `git log --format='%ae %ce' @{u}..` before a
   push. No `Co-Authored-By` trailer, generated-with footer or sign-off in commits, PR
   bodies, comments or tracked files.

## Author's standing preferences

Clarity over brevity. Prefer a vetted SPM when the dependency is smaller than the problem, and say
so when it is not. Cite sources in prose and code comments. DRY, separation of concerns, low
coupling / high cohesion first. Error types conform to `LocalizedError` with a filled
`errorDescription`. Prefer implicit returns wherever the compiler allows. No magic numbers or
strings: give shared values one named home. Claims are verified, not recalled: look vendor
behavior up (DeepWiki, the spec, the docs) before ruling on it.

## Related skills

`xcframework-distribution` · `swift-package-manager` · `swift-concurrency` ·
`swift-testing-expert` · `software-development-principles` · `swift-file-organization` ·
`devin-review-rules` · `atomic-commits` · `git-branching` · `repo-init`
