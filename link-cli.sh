#!/bin/sh
# Symlinks this repo's CLI tools onto $PATH for use outside Claude Code. Machine
# level — this installs nothing into any repo. Putting the skill, hooks, and
# commands into a repo is a separate job; see vendorize.sh.
#
# Usage: ./link-cli.sh [--unlink]
set -eu

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"

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
