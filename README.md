# intent-layer

A Claude Code plugin that creates and maintains CLAUDE.md **intent nodes** across your repositories — giving AI agents institutional knowledge at every semantic boundary so they never fumble in the dark.

Includes a skill, enforcement hooks, a slash-command validator, and an optional standalone CLI validator.

## Install the plugin

```text
/plugin marketplace add rsantosCL/intent-layer
```

Once installed, the skill and hooks are active in every project automatically — no per-project setup needed.

## Usage

| Command | What it does |
|---|---|
| `/intent-layer:intent-layer` | Auto-detect: create from scratch or sync after changes |
| `/intent-layer:create` | Build the intent layer from scratch (leaf-first) |
| `/intent-layer:update` | Sync nodes after a branch, PR, or staged diff |
| `/intent-layer:validate` | Validate all nodes and offload files, report issues |

### How auto-detect works

Invoking `/intent-layer:intent-layer` reads the context — existing nodes? recent diff? — and decides whether to run Create or Update mode. The explicit `:create` and `:update` commands are preferred when you already know which mode you need.

## Enforcement hooks

The plugin registers two hooks automatically:

- **PreToolUse (Write|Edit)** — injects `non-negotiable-rules.md` + `size-rules.md` into context before the agent writes any CLAUDE.md node or offload file.
- **PostToolUse (Write|Edit)** — after any write to a CLAUDE.md or offload file, runs the validator and injects errors into context so they're fixed immediately.

### Non-plugin install

If you cloned the repo instead of installing as a plugin, add to each project's `.claude/settings.json` (replace `<path-to-repo>` with the absolute path):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"<path-to-repo>/hooks/intent-layer-preload.sh\"",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"<path-to-repo>/hooks/intent-layer-validate.sh\"",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

## Optional CLI install

For use outside Claude Code — CI pipelines, pre-commit hooks, shell scripts:

```sh
git clone https://github.com/rsantosCL/intent-layer
cd intent-layer
./install.sh
```

This symlinks `bin/validate-intent-layer` to `~/.local/bin/validate-intent-layer` and pre-grants the Bash permission needed for the `:validate` command to run without a prompt. Ensure `~/.local/bin` is on your `PATH`.

```sh
validate-intent-layer [--json|--jsonl] [directory]
```

To uninstall:

```sh
./install.sh --uninstall
```

See `docs/validate-intent-layer.md` for full validator documentation.
