# intent-layer

A Claude Code plugin that creates and maintains CLAUDE.md **intent nodes** across your repositories — giving AI agents institutional knowledge at every semantic boundary so they never fumble in the dark.

Includes a skill, enforcement hooks, a slash-command validator, and an optional standalone CLI validator.

## Install

Two supported paths. Pick one per machine; don't mix them in the same repo.

### Option 1 — marketplace plugin (recommended)

```text
/plugin marketplace add rsantosCL/intent-layer
```

The skill and hooks are then active in **every** repo you open — no per-project setup. Enablement is stored in your settings, not in the plugin, so there is no way to ship it default-off.

To switch it off for one repo, add to that repo's `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "intent-layer@intent-layer": false
  }
}
```

This repo does exactly that, so the working tree is what it enforces on itself.

### Option 2 — clone

For repos that must carry their own copy (no marketplace access, CI that runs the validator, a team that wants the skill checked in). Two scripts, two jobs:

```sh
git clone https://github.com/rsantosCL/intent-layer
cd intent-layer

./link-cli.sh                 # machine-level: symlink bin/* into ~/.local/bin
./vendorize.sh ../my-repo     # repo-level: install skill + hooks + commands
```

`link-cli.sh` touches no repo — it only puts `validate-intent-layer` on your `PATH` for CI, pre-commit hooks, and shell use. It symlinks rather than copies, so a `git pull` here updates the tool everywhere. Undo with `./link-cli.sh --unlink`.

`vendorize.sh` copies an explicit file manifest into `../my-repo/.claude/`, adding no tracking files of its own. Settings are merged into two files, split by who each one is for:

- **`settings.json`** (shared, committed) — the two hook entries, merged without disturbing the repo's own hooks. Every contributor needs these.
- **`settings.local.json`** (personal, git-ignored) — `enabledPlugins: {"intent-layer@intent-layer": false}`. This only matters if you *also* have the marketplace plugin installed: without it both copies are active in that repo, every hook fires twice, and two skills answer to the same name.

```sh
./vendorize.sh --dry-run ../my-repo   # report what would change
./vendorize.sh ../my-repo             # sync — safe to re-run after every pull
./vendorize.sh --uninstall ../my-repo # remove files and both settings entries
```

Re-runs match each destination file against this repo's history to tell an out-of-date copy (overwritten silently) from a file edited in place (flagged `!`, and the sync stops unless you pass `--force`); nothing is written into the target to track it. Commit the resulting `.claude/` changes in the consuming repo. See `VENDORING.md` for the ownership rules.

## Usage

| Command | What it does |
|---|---|
| `/intent-layer:intent-layer` (plugin) · `/intent-layer` (direct) | Auto-detect: create from scratch or sync after changes |
| `/intent-layer:create` | Build the intent layer from scratch (leaf-first) |
| `/intent-layer:update` | Sync nodes after a branch, PR, or staged diff |
| `/intent-layer:validate` | Validate all nodes and offload files, report issues |

The skill invocation syntax differs by install method: as a marketplace plugin the skill is namespaced `/intent-layer:intent-layer`; vendored into a project's `.claude/skills/`, it's just `/intent-layer`.

### How auto-detect works

The skill reads the context — existing nodes? recent diff? — and decides whether to run Create or Update mode. The explicit `:create` and `:update` commands are preferred when you already know which mode you need.

## Enforcement hooks

Both install paths register the same two hooks — the plugin via `plugin.json`, a vendored install via the target repo's `.claude/settings.json`:

- **PreToolUse (Write|Edit)** — injects `non-negotiable-rules.md` + `size-rules.md` into context before the agent writes any CLAUDE.md node or offload file.
- **PostToolUse (Write|Edit)** — after any write to a CLAUDE.md or offload file, runs the validator and injects errors into context so they're fixed immediately.

Both exit silently for every other file, so they cost nothing in repos where the intent layer isn't in use.

## CLI validator

Once `./link-cli.sh` has run, the validator is on your `PATH` for use outside Claude Code — CI pipelines, pre-commit hooks, shell scripts:

```sh
validate-intent-layer [--json|--jsonl] [directory]
```

In a vendored repo it's also available without installing anything:

```sh
python3 .claude/bin/validate-intent-layer --json .
```

See `docs/validate-intent-layer.md` for full validator documentation.
