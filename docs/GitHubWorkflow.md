# GitHub workflow — swift-libxray

*Set up 2026-10-23.* It follows devin-kick's model (issues, milestones as the release plan,
tags as versions) and SimKDSKit's before it. Every row in *Applied* was applied and checked
live with `gh` on 2026-10-23.

## Applied — 2026-10-23

| What | State | How |
|---|---|---|
| Merge method | **Merge commits only**: squash and rebase off; title `MERGE_MESSAGE`, body `PR_TITLE`. Atomic, reviewed commits land as they are | repo API |
| Branch hygiene | `delete_branch_on_merge`, `allow_update_branch`, `allow_auto_merge` on; Projects and Wiki off | repo API |
| Protection | Ruleset `protect main` (id 25722906): `non_fast_forward`, `deletion`, no bypass. Requiring a PR or the CI check is the owner's later call | `gh api repos/laconicman/swift-libxray/rulesets` |
| Topics | swift, swift-package, swiftpm, xray, xray-core, libxray, vless, reality, xhttp, proxy, macos, ios | repo API |
| Vulnerability reporting | Private reporting on; `SECURITY.md` points at it | repo API, `SECURITY.md` |
| Labels | GitHub's `enhancement`, `bug`, `documentation`, plus `breaking`, `engine-asset`, `tech-debt`, `hygiene`, `tests` | `gh label list` |
| Release notes | `.github/release.yml` maps the labels to sections | `.github/release.yml` |
| Milestones | #1 = M0 (`0.1.0`), #2 = M1 (`0.2.0`), each titled with the tag it closes into and described by its done-when | `gh api …/milestones` |
| Issues | #1 TD-2 slim asset (M1), #2 pingBatch (M1), #3 TD-5/TD-6 upstream hooks. Each TD links its issue; the DocC register stays authoritative | `gh issue list` |
| PR template | Local gate, docs touched, asset-tool counts, labels and milestone, free pass, ledger at 0 | `.github/pull_request_template.md` |
| Reviewer steering | `REVIEW.md` (Devin Review) | `REVIEW.md` |
| Dependabot | SwiftPM + Actions, monthly; engine assets stay manual | `.github/dependabot.yml` |
| CI | `swift build` + `swift test` on GitHub's `xcode-27` image, artifact zip + extraction cached per manifest | `.github/workflows/ci.yml` |
| Swift Package Index | `.spi.yml` documents `XrayCore`; list the repo after the first semver tag | `.spi.yml` |
| DeepWiki | README badge placeholder; enable once indexed | `README.md` |

## Habits

**Per PR:**
- Branch `feat/…`, `fix/…` or `chore/…`, from `main`.
- Atomic commits that each build.
- `gh pr create --label <one> --milestone "M<n> · …"`.
- The free pass first: DeepWiki, prospectively.
- Triage the review round; reply in each thread, and push fixes that make the finding false.
- When the reviewer's re-run on the head reads `owed 0 / to re-read 0`, and the owner
  approves: `gh pr merge N --merge --auto`.

**Engine-asset PRs** (a `libxray-vX.Y.Z` bump):
- `swift run libxray-asset-tool <tag>` — its upstream SHA-256 and the produced checksum go
  in the PR body, with the `Upstream/<tag>.json` diff.
- Publish first, bump second: the Release holding the zip exists *before* the manifest's
  `url` can resolve. `url` and `checksum` land in one commit.
- Label `engine-asset`; the version test's expectation moves with the record.

**Closing milestone M_n**, done in the PR that completes it and right after it merges. The
milestone is the one source: its title ends in the tag and its description is the
done-when. Only `number` is typed; M_n is milestone n + 1. Each step runs only if the one
before it succeeded, so a milestone closes only once its release exists. Artifact tags
(`libxray-vX.Y.Z`) are not milestones — they belong to their own Releases and never close
anything.

```bash
number=1                                                # M0
milestone=repos/laconicman/swift-libxray/milestones/$number
title=$(gh api $milestone --jq .title)                  # "M0 · … — 0.1.0"
tag=${title##* — }                                      # "0.1.0": no v prefix (SwiftPM)
done_when=$(gh api $milestone --jq .description)
done_when=${done_when%% Close with tag*}                # drop the closing note
[[ $tag =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] &&               # a title without a tag stops here
git switch main && git pull --ff-only &&
git tag -a "$tag" -m "$done_when" &&
git push origin "$tag" &&
gh release create "$tag" --verify-tag --generate-notes --title "$tag — ${title% — *}" &&
gh api $milestone -X PATCH -f state=closed
```

**Never:**
- poll CI;
- force-push `main`, which the ruleset refuses anyway;
- re-upload or mutate a published `libxray-*` release asset — a checksum pins the bytes, so
  a new zip is a new tag;
- leave a milestone open after its tag.

## Not adopted, and why

| Feature | Why not |
|---|---|
| Squash merges | They would collapse the atomic, reviewed commits that each build |
| Required checks / required PR | Owner's call; CI's first green run comes first |
| Issues for every TD item | Only actionable ones; the DocC register is the record |
| Projects board | Roadmap + milestones + issues already are the board |
| CODEOWNERS / required reviews | One maintainer; Devin Review runs on every push |
