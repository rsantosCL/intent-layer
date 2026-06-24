#!/bin/sh
set -eu

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.local/bin/validate-intent-layer"
SETTINGS="$HOME/.claude/settings.json"
# Permission rule that pre-authorizes the :validate command so it runs silently.
PERM_RULE="Bash(python3 */validate-intent-layer*)"

if [ "${1:-}" = "--uninstall" ]; then
    if [ -L "$TARGET" ]; then
        rm "$TARGET"
        echo "Removed $TARGET"
    else
        echo "Nothing to remove: $TARGET is not a symlink"
    fi
    # Remove the pre-granted Bash permission from Claude Code settings.
    if [ -f "$SETTINGS" ]; then
        python3 - "$SETTINGS" "$PERM_RULE" <<'PYEOF'
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
rule = sys.argv[2]
data = json.loads(p.read_text())
allow = data.get("permissions", {}).get("allow", [])
if rule in allow:
    allow.remove(rule)
    p.write_text(json.dumps(data, indent=2) + "\n")
    print(f"Removed Claude Code permission: {rule}")
PYEOF
    fi
    exit 0
fi

mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_ROOT/bin/validate-intent-layer" "$TARGET"
echo "Installed validate-intent-layer to $TARGET"
echo "Ensure ~/.local/bin is on your PATH."

# Pre-grant the Bash permission so the :validate slash command runs without
# prompting. The PostToolUse hook invokes the validator directly as a
# subprocess (not via a Bash tool call), so it is already silent by
# construction; this rule only matters for manual :validate invocations.
if [ -f "$SETTINGS" ]; then
    python3 - "$SETTINGS" "$PERM_RULE" <<'PYEOF'
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
rule = sys.argv[2]
data = json.loads(p.read_text())
perms = data.setdefault("permissions", {})
allow = perms.setdefault("allow", [])
if rule not in allow:
    allow.append(rule)
    p.write_text(json.dumps(data, indent=2) + "\n")
    print(f"Granted Claude Code permission: {rule}")
PYEOF
else
    echo "Note: $SETTINGS not found; run 'claude' once to create it, then re-run install.sh to grant the permission silently."
fi
