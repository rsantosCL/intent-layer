#!/usr/bin/env bash
# PostToolUse hook for Write|Edit operations on intent-layer files.
# Runs the validator on the owning node's directory after an edit, then
# injects any errors into context. Silently exits if the file is not an
# intent artifact, belongs to a blocklisted directory without a downlink,
# or validation passes.

set -u

input=$(cat)
f=$(echo "$input" | jq -r '.tool_input.file_path // ""')
[[ -z "$f" ]] && exit 0

basename=$(basename -- "$f")
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname -- "$0")/.." && pwd)}"

# Returns 0 if $1 (absolute path) is a downlink target in any ancestor CLAUDE.md.
_is_downlinked() {
    local d
    d=$(dirname -- "$1")
    while :; do
        if [[ -f "$d/CLAUDE.md" ]]; then
            local rel="${1#"$d/"}"
            grep -qF "]: $rel" "$d/CLAUDE.md" 2>/dev/null && return 0
        fi
        local parent
        parent=$(dirname -- "$d")
        [[ "$parent" == "$d" ]] && break
        d="$parent"
    done
    return 1
}

# Classify the file: accept CLAUDE.md and offload files, reject everything else.
if [[ "$basename" != "CLAUDE.md" ]]; then
    naming_json="$plugin_root/skills/intent-layer/references/offload-naming.json"
    [[ -r "$naming_json" ]] || exit 0

    # Skip blocklisted directories unless the file is explicitly downlinked.
    if jq -e --arg p "$f" '
      (.blocklisted_dirs // []) as $dirs |
      ($p | split("/") | any(.[]; . as $c | $dirs | index($c) != null))
    ' "$naming_json" > /dev/null 2>&1; then
        _is_downlinked "$f" || exit 0
    fi

    OFFLOAD_NAME_REGEX=$(jq -r '.offload_name_regex' "$naming_json")
    jq -e --arg n "$basename" '.blocklisted | index($n) != null' "$naming_json" > /dev/null 2>&1 && exit 0
    [[ "$basename" =~ $OFFLOAD_NAME_REGEX ]] || exit 0
fi

validator="$plugin_root/bin/validate-intent-layer"
[[ -f "$validator" ]] || exit 0

# Walk up from the file's directory to find the nearest ancestor that contains
# a CLAUDE.md. Validate from there so the validator can check downlinks and
# orphans relative to the owning node, even when the edited file is an offload
# under a subdirectory (e.g. docs/).
validate_dir=$(dirname -- "$f")
if [[ "$basename" != "CLAUDE.md" ]]; then
    cur=$(dirname -- "$f")
    while :; do
        if [[ -f "$cur/CLAUDE.md" ]]; then
            validate_dir="$cur"
            break
        fi
        parent=$(dirname -- "$cur")
        [[ "$parent" == "$cur" ]] && break
        cur="$parent"
    done
fi

output=$(python3 "$validator" --json "$validate_dir" 2>&1)
exit_code=$?

[[ $exit_code -eq 0 ]] && exit 0

# Output that isn't JSON means the tool failed, not the layer — a usage error,
# a missing interpreter, a traceback. Stay silent rather than blame the edit.
parsed=$(printf '%s' "$output" | jq -e '.' 2>/dev/null) || exit 0

error_count=$(printf '%s' "$parsed" | jq '.summary.errors // 0')
[[ "$error_count" -eq 0 ]] && exit 0

# Build a readable error summary (errors only; warnings are for the :validate
# command, not for post-edit noise).
errors=$(printf '%s' "$parsed" | jq -r '
  [
    (.files[] | select((.issues | map(select(.level == "error")) | length) > 0) |
      .path + ":",
      (.issues[] | select(.level == "error") | "  [error] " + .message)
    ),
    (.orphans[]? | .path + ": " + .message)
  ] | join("\n")
' 2>/dev/null)

[[ -z "$errors" ]] && exit 0

jq -n \
  --arg content "$errors" \
  --arg path "$f" \
  '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: (
        "INTENT LAYER VALIDATION FAILED after writing " + $path + ".\n\nErrors:\n" + $content + "\n\nFix all errors above before continuing."
      )
    }
  }'
