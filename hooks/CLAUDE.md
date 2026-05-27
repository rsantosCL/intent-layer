# Hooks

## Purpose & Scope

Three Claude Code hooks that enforce intent-layer rules at edit time and detect stale nodes after each turn. Responsible for rule injection and staleness detection only — never creates or edits CLAUDE.md content (the skill handles that).

## Entry Points & Contracts

**`intent-layer-preload.sh`** (PreToolUse, Write|Edit) — Injects `non-negotiable-rules.md` + `size-rules.md` into agent context before any write to a CLAUDE.md or offload file. Silently exits (no output) for all other files — any stdout would block the agent's write.

**`intent-layer-stop.sh`** (Stop) — After each turn, checks whether edited source files have stale owning nodes. Shells out to `claude -p --model haiku` to read diffs and judge whether nodes need updating. Returns `{"decision":"block","reason":"..."}` or `{"decision":"approve"}`. Strips markdown fences from Haiku output (it wraps JSON despite instructions not to).

**`intent-layer-list.sh`** — Helper for the stop hook. Parses the turn's transcript JSONL to enumerate files edited by Write/Edit/MultiEdit/NotebookEdit, filters through the ignore set, and pairs each with its owning CLAUDE.md via directory walk-up. Empty output means nothing relevant — stop hook approves silently.

## Usage Patterns

All three hooks resolve `offload-naming.json` from `${CLAUDE_PLUGIN_ROOT}/skills/intent-layer/references/` (falling back to `$(dirname "$0")/..` for non-plugin installs). Changes to naming rules propagate automatically.

Preload and list partition the file space using the same naming rules: preload handles intent artifacts (CLAUDE.md + offload-named files), list/stop handles everything else (source files). This split is deliberate — changing the naming convention in one without the other creates blind spots where edits go unmonitored.

**Directory blocklist exception:** both preload and list share a `_is_downlinked()` helper that walks ancestor directories looking for a Markdown link definition (`]: relative/path`) in any `CLAUDE.md`. Files under `blocklisted_dirs` (e.g. `.venv/`, `node_modules/`, `docs/`) are skipped by default, but if `_is_downlinked` finds the file is explicitly downlinked from an ancestor node, the block is bypassed and the file is treated as a normal intent artifact. This means deliberately placing an offload file under `docs/` and downlinking it works correctly.

## Anti-patterns

- **Don't emit any output from preload for non-intent files.** Even a blank line is treated as hook output by Claude Code and will block the write operation.
- **Don't switch stop hook to `type: agent`.** As of Claude Code 2.1.142, `type: agent` hooks silently no-op (`hasOutput: false`). The `claude -p` subprocess workaround adds ~30s latency but actually works. Revisit after a Claude Code update.
- **The heredoc in stop.sh uses `read -r -d ''`, not `$(cat <<'EOF')`** — bash 3.2 has a parser bug where apostrophes inside `$(cat <<'DELIM')` open phantom single-quoted regions that misparse later backticks.
