#!/usr/bin/env bash
# shellcheck shell=bash
# Stop hook orchestrator for the intent-layer verifier.
#
# Flow:
#   1. Read Stop hook input JSON from stdin, extract `transcript_path`.
#   2. Run sibling `intent-layer-list.sh` against the transcript to
#      enumerate intent-relevant files edited this turn (filtered through
#      the ignore set, paired with their owning CLAUDE.md via walk-up).
#   3. If nothing relevant, exit silently — Claude Code treats no output
#      as implicit approve.
#   4. Otherwise invoke `claude -p --model haiku` with a prompt embedding
#      the file list and the canonical decision rules. Haiku reads diffs
#      and the owning nodes / offload files, judges, and emits a Stop
#      decision JSON.
#   5. Strip any markdown fences from Haiku's output (it sometimes wraps
#      JSON despite instructions), validate, and forward as the hook's
#      stdout. Claude Code parses it as the Stop verdict.
#
# WORKAROUND: this hook is `type: "command"` rather than the cleaner
# `type: "agent"` (agentic verifier) because the latter silently no-ops in
# Claude Code 2.1.142 — the hook fires (`hookCount: 1`, `hookErrors: []`)
# but `hasOutput: false` and `preventedContinuation: false`. Even a prompt
# that unconditionally returns `{"decision":"block"}` never propagates a
# verdict. Revisit `type: "agent"` after a Claude Code update; the
# verifier abstraction would let us drop the `claude -p` sub-session and
# its ~30s of added latency per editing Stop.

set -u

input=$(cat)

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""')
[[ -z "$transcript" ]] && exit 0
[[ ! -f "$transcript" ]] && exit 0

script_dir="$(cd "$(dirname -- "$0")" && pwd)"
list_script="$script_dir/intent-layer-list.sh"
[[ -x "$list_script" ]] || exit 0

file_list=$(bash "$list_script" "$transcript" 2>/dev/null)
[[ -z "$file_list" ]] && exit 0

# NOTE: heredoc assigned via `read -r -d ''` (not `$(cat <<'EOF' ... EOF)`)
# to work around a bash 3.2 parser bug: inside $(...), the parser does not
# fully honor a quoted heredoc delimiter, so an apostrophe in the body
# (e.g. "node's") opens a phantom single-quoted region that mis-parses
# later backticks (e.g. line 93's `_fence_re`) as command substitution.
IFS= read -r -d '' prompt <<'EOF' || true
You are the intent-layer Stop verifier. Decide whether the edits the main agent made this turn require updating CLAUDE.md or one of its offload files before allowing the Stop. Verdict only — do not edit any files.

The pre-filtered list of intent-relevant files edited this turn (each line: `<file> -> <owning CLAUDE.md>`):

__FILE_LIST__

For each listed file:
1. Read the uncommitted diff: `git diff HEAD -- <file>`.
2. Read the owning node (the CLAUDE.md path on the right of the arrow).
3. From the node's `## Dependencies & Downlinks` section, find any offload files (backtick-quoted paths to `.md` files with ALL-CAPS, hyphen-separated names like `MODULE-DETAILS.md`). Read each offload that could plausibly be affected.
4. For each section of the node and each offload, ask explicitly: "Does this change introduce, remove, or contradict something documented (or that should be documented) here?"

Explicit triggers — these ARE intent-affecting → BLOCK:
- New top-level file or directory not covered by the owning node's directory roles / directory map.
- New shared helper / utility / function exposed to other modules and not listed under documented helpers.
- New module type, category, or convention outside an established pattern documented in the node.
- File deletion or rename when the owning node references the file (downlinks would go stale).
- Adding, removing, or contradicting an invariant, hidden contract, or anti-pattern stated in the node or an offload.
- New anti-pattern worth documenting (e.g., "don't X — it breaks Y").

NOT intent-affecting — these are safe → APPROVE:
- Adding a file INSIDE an existing documented category that already follows the established pattern.
- Pure refactors with no behavioral change.
- Typo fixes, formatting, comment polish.
- Line-level implementation tweaks (logic inside a function, algorithm changes).
- Dependency version bumps that don't change documented contracts.

Approval requires positive evidence the change fits one of the safe categories. When unsure, BLOCK.

Output exactly one JSON object to stdout. No commentary, no markdown, no code fences, no leading or trailing whitespace.
- If any change is intent-affecting:
  {"decision":"block","reason":"Intent-affecting changes detected this turn. Edit <owning node and/or its offload files> directly before stopping. Affected: <files>. Trigger: <which explicit trigger fired>. Invoke /intent-layer only if a structural restructure or a new offload file is needed."}
- Otherwise:
  {"decision":"approve"}
EOF

prompt="${prompt//__FILE_LIST__/$file_list}"

output=$(printf '%s' "$prompt" | claude -p \
    --model haiku \
    --allowedTools 'Read,Grep,Bash,Glob' \
    2>/dev/null || true)

# Haiku sometimes wraps JSON in markdown fences despite the explicit
# "no code fences" instruction. Strip fence lines, then verify the result
# parses as a Stop decision before forwarding.
# shellcheck disable=SC2016
_fence_re='^[[:space:]]*[`]{3}[[:alpha:]]*[[:space:]]*$'
clean=$(printf '%s\n' "$output" | sed -E "/$_fence_re/d")
printf '%s' "$clean" | jq -e '.decision' >/dev/null 2>&1 || exit 0
printf '%s' "$clean"
