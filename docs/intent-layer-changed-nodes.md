# intent-layer-changed-nodes

Resolves the files changed against a base ref to the intent-layer node that owns each one — the executable form of Update Mode Step 2 in `skills/intent-layer/SKILL.md`. Intended for CI: it produces the pre-filtered work list a staleness check reviews, so the check reads only the nodes a pull request can actually have invalidated.

It answers "which nodes might this diff have made stale?" It does not judge staleness, and it does not validate anything — that is `bin/validate-intent-layer`.

## Usage

```text
intent-layer-changed-nodes --base <ref> [--json]
```

`--base` is required and takes any ref git accepts; the diff is `<ref>...HEAD`. The repository root comes from `git rev-parse --show-toplevel`, so the tool runs from any subdirectory. Exits 1 with a message on stderr when git fails — usually an unknown base ref, or a shallow clone with no merge-base.

## Output

One line per covered file, repo-relative on both sides:

```text
app/service.py -> app/CLAUDE.md
app/NESTED-OFFLOAD.md -> app/CLAUDE.md
CLAUDE.md -> CLAUDE.md
```

`--json` emits `[{"file": ..., "node": ...}, ...]` instead.

**Empty output means nothing in the diff is covered** — not that the tool failed. A CI caller should treat empty as "skip the review" and still report a pass, and must not conflate it with a crash: run the tool under `set -e` so a non-zero exit is distinguishable from no matches.

## Resolution rules

**Walk-up.** Each changed file resolves to the nearest `CLAUDE.md` at or above its directory, stopping at the repo root.

**Renames are split.** The diff uses `git diff --no-renames`, so a rename becomes a delete plus an add and both paths resolve independently. Without it git reports only the destination, and the node that still documents the departed file is never opened — the case that node most needs review for.

**Covered-subtree rule.** The root node never owns a file by walk-up. Every path walks up to root, so honoring it would match every pull request and make the gate worthless. Root enters scope only two ways: the root `CLAUDE.md` is edited directly, or an offload file that root downlinks is edited.

**Offloads resolve like any other file.** Editing an offload can leave its node inconsistent, so it maps to its owning node rather than being skipped.

**Blocklisted directories, with a downlink override.** Files under `blocklisted_dirs` from `skills/intent-layer/references/offload-naming.json` (`docs/`, `node_modules/`, `.venv/`, …) are skipped — unless a node downlinks the file, in which case it is a real intent artifact and resolves normally. This mirrors the `_is_downlinked()` bypass in `hooks/intent-layer-preload.sh`; without it CI and edit-time enforcement would disagree about what counts as an intent-layer file.

**Generic docs are never intent-layer files.** Basenames in the shared `blocklisted` list (`README.md`, `TODO.md`, …) are dropped before anything else.

### Deleted nodes are deliberately not reviewed

Removing a node produces no pair — for the node itself, and for the files it used to own. This is intentional, not a gap: whether an area still warrants a node is the code owners' decision, and the staleness check that consumes this output is typically blocking. Putting deletions in scope would let a reviewer veto a deliberate removal.

A deleted root `CLAUDE.md` is skipped on the same grounds, rather than being reported as owning itself and pointing the reader at a file that no longer exists.

The structural consequences of a deletion are still caught, by `bin/validate-intent-layer` rather than here: a parent that still downlinks the removed node fails with a broken downlink, and an offload left behind is warned as an orphan.

## Design

**Shared naming rules.** `offload-naming.json` is resolved as `../skills/intent-layer/references/offload-naming.json` from the script's own **resolved** path, exactly as `bin/validate-intent-layer` does — so a `~/.local/bin` symlink still finds the rules in the clone, and `bin/` must stay a sibling of `skills/` in any vendored layout.

**Downlink parsing** is deliberately laxer than the validator's: `^\[[^\]]+\]:\s*(\S+)` captures the target and ignores the description, because resolution only needs to know which paths a node claims. Enforcing that a description exists is the validator's job.

**Paths are compared resolved.** Downlink targets are resolved against the node's own directory before comparison, so `../` in a downlink works.

## Dependencies

Python 3.9+ standard library only, and `git` on `PATH`. No third-party packages.
