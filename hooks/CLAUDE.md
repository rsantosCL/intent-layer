# Hooks

## Purpose & Scope

Four hook scripts — two active, two parked — enforcing intent-layer rules at edit time. Responsible for rule injection and post-edit validation only — never creates or edits CLAUDE.md content (the skill handles that).

## Entry Points & Contracts

**`intent-layer-preload.sh`** (PreToolUse, Write|Edit) — Injects `non-negotiable-rules.md` + `size-rules.md` into agent context before any write to a CLAUDE.md or offload file. Silently exits (no output) for all other files — any stdout would block the agent's write.

**`intent-layer-validate.sh`** (PostToolUse, Write|Edit) — After any write to a CLAUDE.md or offload file, runs `bin/validate-intent-layer --json` on the owning node's directory and injects errors into context via `hookSpecificOutput.additionalContext`. Silently exits on pass, non-intent files, or when no CLAUDE.md is found in the ancestor chain. Runs the validator as a direct subprocess (not via the Bash tool), so it never triggers a permission prompt.

**`intent-layer-stop.sh`** (parked) — Stop hook using `claude -p --model haiku` to detect stale nodes. Removed from `plugin.json` due to ~30s latency. Re-wire there to restore staleness detection.

**`intent-layer-list.sh`** (parked) — Helper for the stop hook; only useful when the stop hook is active.

## Usage Patterns

Both active hooks resolve `offload-naming.json` from `${CLAUDE_PLUGIN_ROOT}/skills/intent-layer/references/` (falling back to `$(dirname "$0")/..` for non-plugin installs). Changes to naming rules propagate automatically.

Preload and validate share the same file classifier: intent artifacts (CLAUDE.md + offload-named files matching `offload_name_regex`) are in scope; everything else is silently ignored. Both apply the same blocklisted-directory bypass via `_is_downlinked()`.

**Directory blocklist exception:** both active hooks use a `_is_downlinked()` helper that walks ancestor directories looking for a Markdown link definition (`]: relative/path`) in any `CLAUDE.md`. Files under `blocklisted_dirs` (e.g. `.venv/`, `node_modules/`, `docs/`) are skipped by default, but if `_is_downlinked` finds the file is explicitly downlinked from an ancestor node, the block is bypassed and the file is treated as a normal intent artifact. This means deliberately placing an offload file under `docs/` and downlinking it works correctly.

**Validate hook walk-up:** `intent-layer-validate.sh` walks up from the edited file's directory to find the nearest ancestor containing a `CLAUDE.md` before running the validator. This ensures offload files placed under subdirectories (e.g. `docs/`) are validated against their true owning node rather than their immediate directory.

## Anti-patterns

- **Don't emit any output from preload for non-intent files.** Even a blank line is treated as hook output by Claude Code and will block the write operation.
- **Don't switch stop hook to `type: agent`.** As of Claude Code 2.1.142, `type: agent` hooks silently no-op (`hasOutput: false`). The `claude -p` subprocess workaround adds ~30s latency but actually works. Revisit `type: agent` after a Claude Code update before re-wiring the stop hook.
- **The heredoc in stop.sh uses `read -r -d ''`, not `$(cat <<'EOF')`** — bash 3.2 has a parser bug where apostrophes inside `$(cat <<'DELIM')` open phantom single-quoted regions that misparse later backticks.
