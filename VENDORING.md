# Vendoring

## Purpose & Scope

Read this before changing `vendorize.sh`, its manifest, or the layout it writes into a consuming repo — and before syncing a repo that was vendored by hand. Covers the ownership model and the ways a naive copy breaks a consuming repo. Not a file list: the manifest lives in `vendorize.sh` and duplicating it here is how it goes stale.

## Entry Points & Contracts

`./vendorize.sh [--dry-run] [--force] [--with-parked] <path-to-repo>` copies the manifest into `<repo>/.claude/` and merges settings. `--uninstall` reverses both. Both flows are idempotent; re-run after every `git pull` here.

**Layout is load-bearing, not cosmetic.** `bin/` and `skills/` must stay siblings under `.claude/`: both binaries resolve `Path(__file__).resolve().parent.parent / "skills/intent-layer/references/offload-naming.json"`, and both hooks fall back to `$(dirname "$0")/..` for the same file. The install verifies this by running `validate-intent-layer --help`, which loads that JSON at import — it fails loudly if the two directories drift apart.

**This repo's history is the sync's memory.** A destination file that differs from the current copy is hashed and looked up across every revision of that path here: content this repo published is an outdated vendored copy (overwrite freely), content it never published was edited in place (stop and ask). Nothing is written into the target to track this, so a hand-copied repo classifies as accurately as a vendored one. Two consequences: a **shallow clone** of this repo finds no history and calls every differing file diverged, which is the safe reading; and files vendored from **uncommitted** work here are in no revision, so the next sync reports them diverged.

**Vendored variants are copies, never transforms.** `vendored/validate.md` ships as `commands/intent-layer/validate.md` and addresses `.claude/bin/` directly, where a vendored install always keeps the validator; `commands/validate.md` probes all three layouts instead. Rewriting a file mid-copy is not an option — the check above hashes the destination, so a transformed file matches no revision and reads diverged on every sync. Variants also stay outside `commands/`, which the plugin publishes wholesale. Pre-commit fails if the two copies drift below the reporting instructions.

**Settings are split by audience, and the split is deliberate.** `settings.json` gets the hook wiring — repo facts every contributor needs, so it's committed. `settings.local.json` gets `enabledPlugins["intent-layer@intent-layer"] = false`, because that only matters to someone who *also* has the marketplace plugin installed: without it they run both copies here, every hook fires twice, and two skills answer to the same name. That's a personal collision, not a property of the repo. The trade-off is that a teammate who later installs the plugin has to add the key to their own local file; the install prints a note if the repo doesn't git-ignore `settings.local.json`, since committing it would impose one person's setup on everyone.

## Usage Patterns

Ownership decides what a sync may delete:

| Path under `.claude/` | Owner | Sync may |
| --- | --- | --- |
| `skills/intent-layer/`, `commands/intent-layer/` | this plugin | wipe and replace — that is how upstream deletions propagate |
| `bin/`, `hooks/`, `settings.json` | shared with the repo | add and overwrite listed files only |

Repo-local tooling is never vendored: `link-cli.sh`, `vendorize.sh`, `docs/`, `.git-hooks/`, `.gitconfig`, `.claude-plugin/`, the lint configs, and `hooks/CLAUDE.md`.

## Anti-patterns

- **Don't express the manifest as a glob over the destination.** `.claude/bin/intent-layer-*` looks safe and isn't: `.claude/bin/` and `.claude/hooks/` are shared, and a consuming repo's own tooling can carry any name — the `intent-layer-` prefix included. Ownership is the explicit list in `vendorize.sh`, never a name pattern.
- **Don't clear `.claude/hooks/` or `.claude/bin/` before copying.** Consuming repos keep their own scripts alongside these — ycharts has `post-edit-lint-python.sh` and `post-edit-lint-js.sh` in that directory.
- **Don't overwrite `settings.json`.** It carries the repo's own hooks and permissions; the merge is keyed on each hook script's basename appearing anywhere in a `command`, so a repo that wired these by hand is recognised and left alone rather than duplicated.
- **Don't push past a `!` diverged line without diffing.** It means the destination matches neither this repo nor what the last sync wrote. `--force` discards those edits; port anything worth keeping upstream first.
