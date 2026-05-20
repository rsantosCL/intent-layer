#!/usr/bin/env bash
# PreToolUse hook for Write|Edit operations on intent-layer files.
# Forces intent-layer operative rules into context before the agent edits or
# creates a node (CLAUDE.md) or an offload file (ALL-CAPS TOPIC.md). Silently
# exits if the target isn't an intent-layer file, the repo can't be located,
# or the rule files are missing.

input=$(cat)
f=$(echo "$input" | jq -r '.tool_input.file_path // ""')

basename=$(basename -- "$f")

# Fast path: anything other than CLAUDE.md must match the shared offload-naming
# rules. The shared file lives next to this hook in the skill's references dir.
if [[ "$basename" != "CLAUDE.md" ]]; then
    plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname -- "$0")/.." && pwd)}"
    naming_json="$plugin_root/skills/intent-layer/references/offload-naming.json"
    [[ -r "$naming_json" ]] || exit 0

    OFFLOAD_NAME_REGEX=$(jq -r '.offload_name_regex' "$naming_json")
    jq -e --arg n "$basename" '.blocklisted | index($n) != null' "$naming_json" > /dev/null 2>&1 && exit 0
    [[ "$basename" =~ $OFFLOAD_NAME_REGEX ]] || exit 0
fi

plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname -- "$0")/.." && pwd)}"
refs_dir="$plugin_root/skills/intent-layer/references"

[[ -f "$refs_dir/non-negotiable-rules.md" && -f "$refs_dir/size-rules.md" ]] || exit 0

rules=$(cat "$refs_dir/non-negotiable-rules.md" "$refs_dir/size-rules.md")

jq -n \
  --arg content "$rules" \
  --arg path "$f" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: (
        "ENFORCED: about to Write/Edit " + $path + ". intent-layer rules MUST be followed. Operative rules follow.\n\nIf you are creating a new node/offload file or adding/removing sections in an existing one, you MUST also read skills/intent-layer/references/intent-node-structure.md for the required template before proceeding.\n\n---\n\n" + $content
      )
    }
  }'
