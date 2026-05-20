#!/usr/bin/env bash
# shellcheck shell=bash
# Lists files edited by the agent during the current turn (since the most
# recent user prompt), filtered through the intent-layer ignore set and
# paired with their nearest owning CLAUDE.md (walk-up from each file's
# dirname). Invoked by intent-layer-stop.sh so Haiku spends tokens on
# judgment, not enumeration.
#
# Ignore-set partitioning matches intent-layer-preload.sh: this hook (Stop)
# only surfaces source files; CLAUDE.md, offload files (per
# OFFLOAD_NAME_REGEX from ../references/offload-naming.json), and
# is_blocklisted_name basenames are all skipped — the PreToolUse hook
# handles their rules at write time.
#
# Usage:    intent-layer-list.sh <transcript_path>
# Input:    JSONL transcript at <transcript_path> (from Stop hook input).
# Output:   one line per intent-relevant file edited this turn, format
#             <path> -> <owning CLAUDE.md>
#           Empty output ⇒ nothing relevant, Stop should be approved.

transcript="$1"
[[ -z "$transcript" ]] && exit 0
[[ ! -f "$transcript" ]] && exit 0

repo=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo" || exit 0

# Slice the transcript from the most recent user-typed prompt (string
# content, not a tool-result envelope) to the end, then collect file_path
# values from any Write/Edit/MultiEdit/NotebookEdit tool_use in assistant
# messages within that slice. Falls back to the full transcript when no
# user prompt is present (fresh session, unlikely but cheap to handle).
files=$(jq -s -r '
  (([.[] | (.type == "user") and ((.message.content | type) == "string")]) | indices(true)) as $idx
  | (if ($idx | length) > 0 then $idx[-1] else 0 end) as $start
  | .[$start:]
  | [
      .[]
      | select(.type == "assistant")
      | (.message.content // [])
      | if type == "array" then .[] else empty end
      | select(.type == "tool_use" and (.name | IN("Write","Edit","MultiEdit","NotebookEdit")))
      | .input.file_path // empty
    ]
  | unique
  | .[]
' "$transcript" 2>/dev/null)

[[ -z "$files" ]] && exit 0

# Share the offload-naming convention with intent-layer-preload.sh so the
# two hooks partition the file space cleanly:
#   PreToolUse → CLAUDE.md + offload-named .md files (intent artifacts)
#   Stop       → everything else (source code)
# Both hooks skip is_blocklisted_name (README, TODO, SKILL, ...) — generic
# docs that are neither source nor intent artifacts.
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname -- "$0")/.." && pwd)}"
naming_json="$plugin_root/skills/intent-layer/references/offload-naming.json"

OFFLOAD_NAME_REGEX=''
if [[ -r "$naming_json" ]]; then
    OFFLOAD_NAME_REGEX=$(jq -r '.offload_name_regex' "$naming_json")
fi

is_ignored() {
    local basename
    basename=$(basename "$1")

    [[ "$basename" == "CLAUDE.md" ]] && return 0

    if [[ -r "$naming_json" ]]; then
        jq -e --arg n "$basename" '.blocklisted | index($n) != null' "$naming_json" > /dev/null 2>&1 && return 0
    fi

    if [[ -n "${OFFLOAD_NAME_REGEX}" && "$basename" =~ $OFFLOAD_NAME_REGEX ]]; then
        return 0
    fi

    return 1
}

owning_claude_md() {
    local d
    d=$(dirname "$1")
    while :; do
        if [[ -f "$d/CLAUDE.md" ]]; then
            case "$d" in
                .) printf 'CLAUDE.md' ;;
                *) printf '%s/CLAUDE.md' "$d" ;;
            esac
            return 0
        fi
        local parent
        parent=$(dirname "$d")
        [[ "$parent" == "$d" ]] && return 1
        d=$parent
    done
}

while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    # Transcript paths are usually absolute; convert to repo-relative for
    # the ignore-set match and walk-up.
    case "$path" in
        "$repo"/*) path="${path#"$repo"/}" ;;
    esac
    is_ignored "$path" && continue
    owning=$(owning_claude_md "$path") || continue
    printf '%s -> %s\n' "$path" "$owning"
done <<EOF
$files
EOF
