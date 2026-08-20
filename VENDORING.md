# Vendoring

## Purpose & Scope

Read before changing `vendorize.sh`, its manifest, or the layout it writes — and before syncing a hand-vendored repo. Covers the ownership model and how a naive copy breaks a consuming repo. Not a file list: the manifest lives in `vendorize.sh`, and duplicating it here is how it goes stale.

## Entry Points & Contracts

`./vendorize.sh [--dry-run] [--force] [--with-parked] <path-to-repo>` copies the manifest into `<repo>/.claude/` and merges settings; `--uninstall` reverses both. Idempotent — re-run after every `git pull` here.

**Layout is load-bearing.** `bin/` and `skills/` must stay siblings under `.claude/`: the binaries resolve `Path(__file__).resolve().parent.parent / "skills/intent-layer/references/offload-naming.json"`, and the hooks fall back to `$(dirname "$0")/..` for it. The install runs `validate-intent-layer --help`, which loads that JSON at import, so drift fails loudly.

**This repo's history is the sync's memory.** A destination differing from the current copy is hashed and looked up across every revision of that path: content this repo published is a stale vendored copy (overwrite freely), content it never published was edited in place (stop and ask). Nothing is written into the target to track this, so a hand-copied repo classifies as accurately as a vendored one. Hence a **shallow clone** calls every differing file diverged — the safe reading — and files vendored from **uncommitted** work are in no revision, so the next sync reports them diverged.

**Vendored variants are copies, never transforms.** `vendored/validate.md` ships as `commands/intent-layer/validate.md`, addressing `.claude/bin/` directly where a vendored install always keeps the validator; `commands/validate.md` probes all three layouts. A file transformed mid-copy would match no revision and read diverged on every sync. Variants stay outside `commands/`, which the plugin publishes wholesale. Pre-commit fails if the two drift below the reporting instructions.

**Settings split by audience.** `settings.json` takes the hook wiring — repo facts every contributor needs, so it's committed. `settings.local.json` takes `enabledPlugins["intent-layer@intent-layer"] = false`, which matters only to someone who *also* has the marketplace plugin: without it both copies run, every hook fires twice, and two skills answer to one name. That's a personal collision, not a property of the repo. Cost of the split: a teammate who later installs the plugin adds the key themselves, and the install warns if the repo doesn't git-ignore `settings.local.json` — committing it would impose one person's setup on everyone.

## Usage Patterns

Ownership decides what a sync may delete:

| Path under `.claude/` | Owner | Sync may |
| --- | --- | --- |
| `skills/intent-layer/`, `commands/intent-layer/` | this plugin | wipe and replace — how upstream deletions propagate |
| `bin/`, `hooks/`, `settings.json` | shared with the repo | add and overwrite listed files only |

Never vendored: `link-cli.sh`, `vendorize.sh`, `docs/`, `.git-hooks/`, `.gitconfig`, `.claude-plugin/`, the lint configs, `hooks/CLAUDE.md`.

## Anti-patterns

- **Don't express the manifest as a glob over the destination.** `.claude/bin/intent-layer-*` looks safe and isn't: `bin/` and `hooks/` are shared, and a repo's own tooling can carry any name — the `intent-layer-` prefix included. Ownership is the explicit list in `vendorize.sh`, never a name pattern.
- **Don't clear `.claude/hooks/` or `.claude/bin/` before copying.** Repos keep their own scripts there — ycharts has `post-edit-lint-python.sh` and `post-edit-lint-js.sh`.
- **Don't overwrite `settings.json`.** It carries the repo's own hooks and permissions; the merge keys on each hook script's basename appearing anywhere in a `command`, so a hand-wired repo is recognised and left alone rather than duplicated.
- **Don't push past a `!` diverged line without diffing.** The destination matches neither this repo nor what the last sync wrote. `--force` discards those edits; port anything worth keeping upstream first.
