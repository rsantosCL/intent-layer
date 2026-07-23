# Intent Layer Plugin

## Purpose & Scope

Claude Code plugin that ships tooling for creating and maintaining CLAUDE.md intent nodes. Four components: a skill (create/update workflows), enforcement hooks (write-time rule injection, post-edit validation), a standalone CLI validator, and slash commands. This repo is the automation/tooling layer — the intent layer methodology lives in `skills/intent-layer/references/intent-layer-methodology.md`.

## Entry Points & Contracts

**Plugin install:** `/plugin marketplace add rsantosCL/intent-layer` — hooks activate automatically via `.claude-plugin/plugin.json`. Non-plugin install requires manually adding hook entries to each project's `.claude/settings.json` (both paths documented in `README.md`).

**Slash commands:** `:create`, `:update`, `:validate`, `:intent-layer` (auto-detect). Commands in `commands/` are thin dispatchers — each just tells Claude to invoke the skill in a specific mode.

**CLI validator:** `bin/validate-intent-layer` is Python 3.9+ (no extension in the filename), zero third-party deps. `./install.sh` symlinks it to `~/.local/bin/` and pre-grants `Bash(python3 */validate-intent-layer*)` in `~/.claude/settings.json` so the `:validate` command runs without a permission prompt. See `docs/validate-intent-layer.md` for full design — checks structure, naming, token caps, downlink integrity, and orphan detection. Token caps: `NODE_CAP` (1,000) for most nodes, `ROOT_CAP` (2,000) for the project root. The root is identified by `_is_project_root()` — scan target contains `.git`, or no ancestor directory up to the git/filesystem root has a `CLAUDE.md`. The post-edit hook validates from the edited node's own directory, so this detection prevents a child node from inheriting the root cap.

**Git hooks:** `.gitconfig` sets `core.hooksPath = .git-hooks`. Clones must run `git config --local include.path ../.gitconfig` to activate. `.git-hooks/pre-commit` lints staged files: shellcheck --shell=sh for `install.sh` (strict POSIX), shellcheck --shell=bash + bash -n for all other `.sh`, ruff for `bin/*`, jq for `.json`, rumdl for `.md`. `.shellcheckrc` defaults to bash; the pre-commit hook overrides to sh for `install.sh`. `.rumdl.toml` disables MD013 (long lines are intentional) and MD053 (downlink definitions aren't referenced inline); configures MD041 to recognize `description:` frontmatter in command files.

**Shared naming contract:** `skills/intent-layer/references/offload-naming.json` is the single source of truth for offload file naming rules. Three fields: `offload_name_regex` (valid offload basename pattern), `blocklisted` (reserved basenames like README, TODO), and `blocklisted_dirs` (directory name components to skip entirely, e.g. `.venv`, `node_modules`, `docs`). Consumed by hooks, the validator, and the skill's own enforcement. Change it once, all consumers pick it up — but verify all three still parse correctly.

## Usage Patterns

### Development Setup

This repo self-dogfoods: the installed plugin is disabled here (`.claude/settings.json` sets `enabledPlugins: false`) and the working-tree hooks fire via `$CLAUDE_PROJECT_DIR`. Skill and commands are registered via symlinks — `.claude/skills/intent-layer → skills/intent-layer` and `.claude/commands/intent-layer → commands/`. Any edit to the skill, hooks, or validator is immediately what the session enforces. No extra setup on a fresh clone — `.claude/settings.json` is tracked.

### Intent Layer Navigation

This project has a network of `CLAUDE.md` intent nodes in subdirectories. Each node
contains invariants, contracts, and gotchas not visible from reading the code.

**Before working in, searching in, or making any claim about code in any directory:**

1. Check for a `CLAUDE.md` in that directory and read it if present.
2. Walk up to the project root and read every ancestor `CLAUDE.md` along the path.

Do not rely on auto-loading — nodes are only injected when a file in that directory is
read by the main thread. Explicit reads are required when working in unfamiliar directories
or making claims about code you have not directly visited this session.

**Scope constraint:** The knowledge in each node is valid **only** for that node's
directory and its subdirectories. Do not extrapolate a node's contracts, patterns, or
anti-patterns to sibling directories or parent directories — those areas have their own
nodes and their own rules.

## Anti-patterns

- **Don't edit `offload-naming.json` without checking all consumers.** Active hooks (`hooks/intent-layer-preload.sh`, `hooks/intent-layer-validate.sh`) and the validator (`bin/validate-intent-layer`) all parse it independently. A schema change breaks three things silently.
- **Don't confuse `plugin.json` with `marketplace.json`.** `plugin.json` wires hooks and is the runtime config. `marketplace.json` is the marketplace listing metadata — it doesn't affect behavior.

## Downlinks

[hooks/CLAUDE.md]: hooks/CLAUDE.md (hook contracts, file partitioning design, known workarounds for Claude Code bugs)
