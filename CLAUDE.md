# Intent Layer Plugin

## Purpose & Scope

Claude Code plugin that ships tooling for creating and maintaining CLAUDE.md intent nodes. Four components: a skill (create/update workflows), enforcement hooks (write-time rule injection, post-turn staleness detection), a standalone CLI validator, and slash commands. This repo is the automation/tooling layer — the intent layer methodology lives in `skills/intent-layer/references/intent-layer-methodology.md`.

## Entry Points & Contracts

**Plugin install:** `/plugin marketplace add rsantosCL/intent-layer` — hooks activate automatically via `.claude-plugin/plugin.json`. Non-plugin install requires manually adding hook entries to each project's `.claude/settings.json` (both paths documented in `README.md`).

**Slash commands:** `:create`, `:update`, `:validate`, `:intent-layer` (auto-detect). Commands in `commands/` are thin dispatchers — each just tells Claude to invoke the skill in a specific mode.

**CLI validator:** `bin/validate-intent-layer` is Python 3.9+ (no extension in the filename), zero third-party deps. `./install.sh` symlinks it to `~/.local/bin/`. See `docs/validate-intent-layer.md` for full design — checks structure, naming, token caps, downlink integrity, and orphan detection.

**Git hooks:** `.gitconfig` sets `core.hooksPath = .git-hooks`. Clones must run `git config --local include.path ../.gitconfig` to activate. `.git-hooks/pre-commit` lints staged files: shellcheck --shell=sh for `install.sh` (strict POSIX), shellcheck --shell=bash + bash -n for all other `.sh`, ruff for `bin/*`, jq for `.json`, rumdl for `.md`. `.shellcheckrc` defaults to bash; the pre-commit hook overrides to sh for `install.sh`. `.rumdl.toml` disables MD013 (long lines are intentional) and MD053 (downlink definitions aren't referenced inline); configures MD041 to recognize `description:` frontmatter in command files.

**Shared naming contract:** `skills/intent-layer/references/offload-naming.json` is the single source of truth for offload file naming rules (regex + blocklist). Consumed by hooks, the validator, and the skill's own enforcement. Change it once, all consumers pick it up — but verify all three still parse correctly.

## Anti-patterns

- **Don't edit `offload-naming.json` without checking all consumers.** Hooks (`hooks/intent-layer-preload.sh`, `hooks/intent-layer-list.sh`), the validator (`bin/validate-intent-layer`), and the preload hook's blocklist check all parse it independently. A schema change breaks three things silently.
- **Don't confuse `plugin.json` with `marketplace.json`.** `plugin.json` wires hooks and is the runtime config. `marketplace.json` is the marketplace listing metadata — it doesn't affect behavior.

## Downlinks

[hooks/CLAUDE.md]: hooks/CLAUDE.md (hook contracts, file partitioning design, known workarounds for Claude Code bugs)
