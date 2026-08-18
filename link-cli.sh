#!/bin/sh
# Symlinks this repo's CLI tools onto $PATH for use outside Claude Code, and
# pre-grants the Claude Code permission the :validate command needs. Machine
# level — this installs nothing into any repo. Putting the skill, hooks, and
# commands into a repo is a separate job; see vendorize.sh.
#
# Usage: ./link-cli.sh [--unlink]
set -eu

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"
# Permission rule that pre-authorizes the :validate command so it runs silently.
PERM_RULE="Bash(python3 */validate-intent-layer*)"

if [ "${1:-}" = "--unlink" ]; then
    for src in "$REPO_ROOT"/bin/*; do
        [ -f "$src" ] || continue
        target="$BIN_DIR/$(basename "$src")"
        if [ -L "$target" ]; then
            rm "$target"
            echo "Removed $target"
        else
            echo "Nothing to remove: $target is not a symlink"
        fi
    done
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

mkdir -p "$BIN_DIR"
for src in "$REPO_ROOT"/bin/*; do
    [ -f "$src" ] || continue
    # Symlink, not copy: the tools resolve their own path back to this clone to
    # find skills/intent-layer/references/offload-naming.json, so a pull updates
    # both the tool and the rules it reads.
    ln -sf "$src" "$BIN_DIR/$(basename "$src")"
    echo "Linked $(basename "$src") -> $BIN_DIR/$(basename "$src")"
done
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
    echo "Note: $SETTINGS not found; run 'claude' once to create it, then re-run link-cli.sh to grant the permission silently."
fi
