#!/bin/sh
set -eu

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.local/bin/validate-intent-layer"

if [ "${1:-}" = "--uninstall" ]; then
    if [ -L "$TARGET" ]; then
        rm "$TARGET"
        echo "Removed $TARGET"
    else
        echo "Nothing to remove: $TARGET is not a symlink"
    fi
    exit 0
fi

mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_ROOT/bin/validate-intent-layer" "$TARGET"
echo "Installed validate-intent-layer to $TARGET"
echo "Ensure ~/.local/bin is on your PATH."
