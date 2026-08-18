#!/usr/bin/env bash
# Vendor this plugin into a consuming repository that can't install it from the
# marketplace. Copies an explicit file manifest into <repo>/.claude/, wires the
# hooks in settings.json (shared) and disables the marketplace plugin in
# settings.local.json (personal), and records a version stamp so the next sync
# can tell an old vendored copy from a local edit.
#
# Usage: ./vendorize.sh [--dry-run] [--force] [--with-parked] <path-to-repo>
#        ./vendorize.sh --uninstall [--dry-run] <path-to-repo>
#
# Read VENDORING.md before changing the manifest or the ownership rules.
set -euo pipefail

SRC="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_URL="https://github.com/rsantosCL/intent-layer"
PLUGIN_KEY="intent-layer@intent-layer"

# --- manifest ----------------------------------------------------------------
# "<path in this repo>|<path under the consuming repo's .claude/>"
# This list is the contract. Anything absent is repo-local tooling that must not
# be vendored (link-cli.sh, docs/, .git-hooks/, .claude-plugin/, lint configs,
# hooks/CLAUDE.md). Never express it as a glob over the destination — consuming
# repos keep their own files next to these.
MANIFEST=(
    "skills/intent-layer/SKILL.md|skills/intent-layer/SKILL.md"
    "skills/intent-layer/references/intent-layer-methodology.md|skills/intent-layer/references/intent-layer-methodology.md"
    "skills/intent-layer/references/intent-node-structure.md|skills/intent-layer/references/intent-node-structure.md"
    "skills/intent-layer/references/non-negotiable-rules.md|skills/intent-layer/references/non-negotiable-rules.md"
    "skills/intent-layer/references/offload-naming.json|skills/intent-layer/references/offload-naming.json"
    "skills/intent-layer/references/root-intent-layer-block.md|skills/intent-layer/references/root-intent-layer-block.md"
    "skills/intent-layer/references/size-rules.md|skills/intent-layer/references/size-rules.md"
    "skills/intent-layer/references/testing-guide.md|skills/intent-layer/references/testing-guide.md"
    "bin/intent-layer-changed-nodes|bin/intent-layer-changed-nodes"
    "bin/validate-intent-layer|bin/validate-intent-layer"
    "hooks/intent-layer-preload.sh|hooks/intent-layer-preload.sh"
    "hooks/intent-layer-validate.sh|hooks/intent-layer-validate.sh"
    "commands/create.md|commands/intent-layer/create.md"
    "commands/update.md|commands/intent-layer/update.md"
    "commands/validate.md|commands/intent-layer/validate.md"
)

# Parked hooks — only with --with-parked. The stop hook costs ~30s per turn; see
# hooks/CLAUDE.md before enabling it anywhere.
PARKED=(
    "hooks/intent-layer-stop.sh|hooks/intent-layer-stop.sh"
    "hooks/intent-layer-list.sh|hooks/intent-layer-list.sh"
)

# Destinations that must land executable. Some copy paths drop the bit.
EXECUTABLES="bin/intent-layer-changed-nodes bin/validate-intent-layer hooks/intent-layer-preload.sh hooks/intent-layer-validate.sh hooks/intent-layer-stop.sh hooks/intent-layer-list.sh"

# Directories under .claude/ owned wholly by this plugin: safe to wipe before a
# copy, which is how upstream deletions propagate. Everything else under
# .claude/ (bin/, hooks/, commands/, settings.json) is SHARED with the consuming
# repo and is only ever added to.
OWNED_DIRS="skills/intent-layer commands/intent-layer"

# --- helpers -----------------------------------------------------------------

die() {
    printf 'vendorize: %s\n' "$1" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: ./vendorize.sh [--dry-run] [--force] [--with-parked] <path-to-repo>
       ./vendorize.sh --uninstall [--dry-run] <path-to-repo>

  --dry-run       Report what would change; write nothing.
  --force         Overwrite destination files that diverge from upstream.
  --with-parked   Also install the parked stop/list hooks (off by default).
  --uninstall     Remove the vendored files, the stamp, and the settings entries.
EOF
}

sha() {
    if command -v shasum > /dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        sha256sum "$1" | cut -d' ' -f1
    fi
}

TMPDIR_RUN=""
cleanup() {
    [ -z "$TMPDIR_RUN" ] || rm -rf "$TMPDIR_RUN"
}
trap cleanup EXIT

# --- args --------------------------------------------------------------------

DRY_RUN=0
FORCE=0
WITH_PARKED=0
UNINSTALL=0
TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --force) FORCE=1 ;;
        --with-parked) WITH_PARKED=1 ;;
        --uninstall) UNINSTALL=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*) die "unknown flag: $1 (try --help)" ;;
        *)
            [ -z "$TARGET" ] || die "expected one target repo, got a second: $1"
            TARGET="$1"
            ;;
    esac
    shift
done

[ -n "$TARGET" ] || {
    usage >&2
    exit 1
}
[ -d "$TARGET" ] || die "not a directory: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" != "$SRC" ] || die "target is this repo — vendorize into a different repo"

DEST_ROOT="$TARGET/.claude"
SETTINGS="$DEST_ROOT/settings.json"
LOCAL_SETTINGS="$DEST_ROOT/settings.local.json"
STAMP="$DEST_ROOT/.intent-layer-vendor.json"

FILES=("${MANIFEST[@]}")
if [ "$WITH_PARKED" -eq 1 ] || [ "$UNINSTALL" -eq 1 ]; then
    FILES=("${FILES[@]}" "${PARKED[@]}")
fi

# --- settings.json merge / unmerge -------------------------------------------

edit_settings() {
    # $1: install | uninstall | dry-install | dry-uninstall
    #
    # Two files, split by who the setting is for. settings.json gets the hook
    # wiring and the validator permission — facts about the repo that every
    # contributor needs, so they belong in the shared, committed file.
    # settings.local.json gets the plugin disable, which matters only to
    # someone who ALSO has the marketplace plugin installed; that is a personal
    # collision, not a property of the repo.
    python3 - "$SETTINGS" "$LOCAL_SETTINGS" "$1" "$PLUGIN_KEY" <<'PYEOF'
import json
import pathlib
import sys

shared_path = pathlib.Path(sys.argv[1])
local_path = pathlib.Path(sys.argv[2])
mode, plugin_key = sys.argv[3], sys.argv[4]
dry = mode.startswith("dry-")
uninstall = mode.endswith("uninstall")
HOOKS = [
    ("PreToolUse", "intent-layer-preload.sh", 5),
    ("PostToolUse", "intent-layer-validate.sh", 15),
]
RULE = "Bash(python3 */validate-intent-layer*)"


def load(path):
    if not path.exists():
        return {}
    raw = path.read_text().strip()
    try:
        return json.loads(raw) if raw else {}
    except json.JSONDecodeError as exc:
        sys.exit(f"vendorize: {path} is not valid JSON ({exc}); fix it and re-run")


def save(path, data, changes):
    for c in changes:
        print(f"  {path.name}: {c}")
    if not changes:
        print(f"  {path.name}: already correct")
        return
    if dry:
        return
    # An uninstall that empties a file we created leaves no litter behind.
    if not data and uninstall:
        path.unlink(missing_ok=True)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


# --- shared: hook wiring + validator permission ------------------------------
data = load(shared_path)
changes = []
hooks = data.setdefault("hooks", {})

for event, script, timeout in HOOKS:
    entries = hooks.setdefault(event, [])
    # Keyed on the script basename appearing anywhere in the command, so a repo
    # that already wired these by hand (relative path, absolute path, plugin
    # root) is recognised and left alone rather than duplicated.
    present = [
        e
        for e in entries
        if any(script in h.get("command", "") for h in e.get("hooks", []))
    ]
    if uninstall:
        for e in present:
            entries.remove(e)
            changes.append(f"removed {event} -> {script}")
    elif not present:
        entries.append(
            {
                "matcher": "Write|Edit",
                "hooks": [
                    {
                        "type": "command",
                        "command": f'bash "$CLAUDE_PROJECT_DIR/.claude/hooks/{script}"',
                        "timeout": timeout,
                    }
                ],
            }
        )
        changes.append(f"added {event} -> {script}")

allow = data.get("permissions", {}).get("allow", [])
if uninstall:
    if RULE in allow:
        allow.remove(RULE)
        changes.append(f"removed permission {RULE}")
else:
    allow = data.setdefault("permissions", {}).setdefault("allow", [])
    if RULE not in allow:
        allow.append(RULE)
        changes.append(f"added permission {RULE}")

# Drop only the containers this script emptied; leave anything still in use.
for event, _, _ in HOOKS:
    if event in hooks and not hooks[event]:
        del hooks[event]
if "hooks" in data and not data["hooks"]:
    del data["hooks"]
if "permissions" in data:
    if not data["permissions"].get("allow", ["x"]):
        del data["permissions"]["allow"]
    if not data["permissions"]:
        del data["permissions"]

save(shared_path, data, changes)

# --- local: disable the marketplace plugin for this repo ---------------------
# Without this, anyone who has the plugin installed globally runs both copies
# here: every hook fires twice and two skills answer to the same name.
data = load(local_path)
changes = []
enabled = data.get("enabledPlugins", {})

if uninstall:
    if enabled.get(plugin_key) is False:
        del enabled[plugin_key]
        changes.append(f"removed enabledPlugins[{plugin_key}]")
elif enabled.get(plugin_key) is not False:
    data.setdefault("enabledPlugins", {})[plugin_key] = False
    changes.append(f"set enabledPlugins[{plugin_key}] = false")

if "enabledPlugins" in data and not data["enabledPlugins"]:
    del data["enabledPlugins"]

save(local_path, data, changes)
PYEOF
}

# --- uninstall ---------------------------------------------------------------

if [ "$UNINSTALL" -eq 1 ]; then
    printf 'Removing intent-layer from %s\n' "$TARGET"
    for pair in "${FILES[@]}"; do
        dest="${pair##*|}"
        [ -e "$DEST_ROOT/$dest" ] || continue
        printf '  remove .claude/%s\n' "$dest"
        [ "$DRY_RUN" -eq 1 ] || rm -f "$DEST_ROOT/$dest"
    done
    for d in $OWNED_DIRS; do
        [ -d "$DEST_ROOT/$d" ] || continue
        printf '  remove .claude/%s/\n' "$d"
        [ "$DRY_RUN" -eq 1 ] || rm -rf "${DEST_ROOT:?}/$d"
    done
    if [ -e "$STAMP" ]; then
        printf '  remove .claude/.intent-layer-vendor.json\n'
        [ "$DRY_RUN" -eq 1 ] || rm -f "$STAMP"
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        edit_settings "dry-uninstall"
        printf 'Dry run — nothing written.\n'
    else
        edit_settings "uninstall"
        # Shared dirs: reclaim only if this plugin was the last thing in them.
        rmdir "$DEST_ROOT/bin" "$DEST_ROOT/hooks" "$DEST_ROOT/commands" 2> /dev/null || true
        printf 'Done.\n'
    fi
    exit 0
fi

# --- classify ----------------------------------------------------------------
# Every destination is compared against upstream and, where a stamp exists,
# against what this script last wrote there. That distinguishes an older
# vendored copy (safe to overwrite) from an edit made in place (must not be
# clobbered silently).

TMPDIR_RUN="$(mktemp -d)"
STAMP_LIST="$TMPDIR_RUN/stamp"
: > "$STAMP_LIST"

if [ -f "$STAMP" ]; then
    python3 - "$STAMP" > "$STAMP_LIST" <<'PYEOF'
import json
import pathlib
import sys

try:
    data = json.loads(pathlib.Path(sys.argv[1]).read_text())
except (OSError, json.JSONDecodeError):
    sys.exit(0)
for dest, digest in (data.get("files") or {}).items():
    print(f"{dest} {digest}")
PYEOF
fi

stamped_sha() {
    awk -v k="$1" '$1 == k { print $2 }' "$STAMP_LIST"
}

new_files=()
same_count=0
outdated_files=()
diverged_files=()

for pair in "${FILES[@]}"; do
    src="${pair%%|*}"
    dest="${pair##*|}"
    [ -f "$SRC/$src" ] || die "manifest lists a file that is not in this repo: $src"
    if [ ! -e "$DEST_ROOT/$dest" ]; then
        new_files=("${new_files[@]+"${new_files[@]}"}" "$dest")
        continue
    fi
    dest_sha="$(sha "$DEST_ROOT/$dest")"
    stamp_sha="$(stamped_sha "$dest")"
    if [ "$dest_sha" = "$(sha "$SRC/$src")" ]; then
        same_count=$((same_count + 1))
    elif [ -n "$stamp_sha" ] && [ "$dest_sha" = "$stamp_sha" ]; then
        outdated_files=("${outdated_files[@]+"${outdated_files[@]}"}" "$dest")
    else
        diverged_files=("${diverged_files[@]+"${diverged_files[@]}"}" "$dest")
    fi
done

# --- report ------------------------------------------------------------------

VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$SRC/.claude-plugin/plugin.json")"
COMMIT="$(git -C "$SRC" rev-parse HEAD 2> /dev/null || printf 'unknown')"
DIRTY=0
if [ -n "$(git -C "$SRC" status --porcelain 2> /dev/null)" ]; then
    DIRTY=1
    printf 'Warning: this repo has uncommitted changes; the stamp will record them as dirty.\n' >&2
fi

printf 'Vendoring intent-layer %s (%s) into %s\n' "$VERSION" "${COMMIT:0:12}" "$TARGET"
if [ -f "$STAMP" ]; then
    python3 - "$STAMP" <<'PYEOF'
import json
import pathlib
import sys

d = json.loads(pathlib.Path(sys.argv[1]).read_text())
commit = str(d.get("commit"))[:12]
print(f"  installed: {d.get('version')} ({commit}) on {d.get('vendored_at')}")
PYEOF
else
    printf '  installed: no stamp (first sync, or a hand copy predating stamps)\n'
fi
printf '  %d new, %d unchanged, %d outdated, %d diverged\n' \
    "${#new_files[@]}" "$same_count" "${#outdated_files[@]}" "${#diverged_files[@]}"

for f in ${new_files[@]+"${new_files[@]}"}; do printf '  +  .claude/%s\n' "$f"; done
for f in ${outdated_files[@]+"${outdated_files[@]}"}; do printf '  ~  .claude/%s\n' "$f"; done
for f in ${diverged_files[@]+"${diverged_files[@]}"}; do printf '  !  .claude/%s\n' "$f"; done

if [ "${#diverged_files[@]}" -gt 0 ]; then
    cat >&2 <<'EOF'

Files marked ! match neither this repo nor what vendorize.sh last wrote there:
they are local edits, or a hand copy of unknown provenance. Overwriting drops
them. Diff them against this repo, port anything worth keeping upstream, then
re-run.
EOF
    if [ "$FORCE" -eq 1 ]; then
        printf 'Overwriting anyway (--force).\n' >&2
    elif [ "$DRY_RUN" -eq 1 ]; then
        printf 'Dry run: a real run would stop here without --force.\n' >&2
    elif [ -t 0 ]; then
        printf 'Overwrite them? [y/N] '
        read -r reply || reply=""
        case "$reply" in
            [yY]*) ;;
            *) die "aborted" ;;
        esac
    else
        die "refusing to overwrite diverged files; re-run with --force"
    fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
    edit_settings "dry-install"
    printf 'Dry run — nothing written.\n'
    exit 0
fi

# --- copy --------------------------------------------------------------------

# Clearing the wholly-owned directories is how files deleted upstream stop
# shipping. Never do this to bin/ or hooks/ — those are shared.
for d in $OWNED_DIRS; do
    rm -rf "${DEST_ROOT:?}/$d"
done

MANIFEST_LIST="$TMPDIR_RUN/manifest"
: > "$MANIFEST_LIST"

for pair in "${FILES[@]}"; do
    src="${pair%%|*}"
    dest="${pair##*|}"
    mkdir -p "$(dirname -- "$DEST_ROOT/$dest")"
    cp "$SRC/$src" "$DEST_ROOT/$dest"
    case " $EXECUTABLES " in
        *" $dest "*) chmod 755 "$DEST_ROOT/$dest" ;;
        *) chmod 644 "$DEST_ROOT/$dest" ;;
    esac
    printf '%s %s\n' "$dest" "$(sha "$DEST_ROOT/$dest")" >> "$MANIFEST_LIST"
done
printf '  copied %d files into .claude/\n' "${#FILES[@]}"

edit_settings "install"

python3 - "$STAMP" "$VERSION" "$COMMIT" "$DIRTY" "$UPSTREAM_URL" "$MANIFEST_LIST" <<'PYEOF'
import datetime
import json
import pathlib
import sys

stamp, version, commit, dirty, url, listing = sys.argv[1:7]
files = {}
for line in pathlib.Path(listing).read_text().splitlines():
    if line.strip():
        dest, digest = line.rsplit(" ", 1)
        files[dest] = digest
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
pathlib.Path(stamp).write_text(
    json.dumps(
        {
            "source": url,
            "version": version,
            "commit": commit,
            "dirty": dirty == "1",
            "vendored_at": now.isoformat().replace("+00:00", "Z"),
            "files": files,
        },
        indent=2,
    )
    + "\n"
)
PYEOF
printf '  wrote .claude/.intent-layer-vendor.json\n'

# --- verify ------------------------------------------------------------------

printf 'Verifying:\n'
rc=0
for dest in $EXECUTABLES; do
    [ -e "$DEST_ROOT/$dest" ] || continue
    if [ ! -x "$DEST_ROOT/$dest" ]; then
        printf '  FAIL  not executable: .claude/%s\n' "$dest"
        rc=1
    fi
done

# The validator loads offload-naming.json at import, so --help failing means
# bin/ and skills/ did not land as siblings under .claude/.
if python3 "$DEST_ROOT/bin/validate-intent-layer" --help > /dev/null 2>&1; then
    printf '  ok    validator resolves ../skills/intent-layer/references/offload-naming.json\n'
else
    printf '  FAIL  validator cannot resolve offload-naming.json — check the .claude/ layout\n'
    rc=1
fi

if grep -q 'intent-layer-preload.sh' "$SETTINGS" && grep -q 'intent-layer-validate.sh' "$SETTINGS"; then
    printf '  ok    both hooks wired in settings.json (shared)\n'
else
    printf '  FAIL  hooks missing from settings.json\n'
    rc=1
fi

if grep -qF "$PLUGIN_KEY" "$LOCAL_SETTINGS" 2> /dev/null; then
    printf '  ok    marketplace plugin disabled in settings.local.json (personal)\n'
else
    printf '  FAIL  plugin not disabled in settings.local.json\n'
    rc=1
fi

# The disable is a personal collision fix, so it belongs in an ignored file — and
# the rule has to live in the repo. A global ~/.config/git/ignore entry makes
# check-ignore pass on this machine while a teammate's clone happily commits the
# file, so the ignore SOURCE is what matters, not the exit status.
if git -C "$TARGET" rev-parse --git-dir > /dev/null 2>&1; then
    ignore_src="$(git -C "$TARGET" check-ignore -v .claude/settings.local.json 2> /dev/null | cut -d: -f1)"
    case "$ignore_src" in
        "")
            printf '  note  .claude/settings.local.json is not git-ignored — add it to .gitignore\n'
            printf '        so the personal plugin disable is never committed\n'
            ;;
        /* | *.git/info/exclude)
            printf '  note  .claude/settings.local.json is ignored only on this machine (by\n'
            printf '        %s) — add it to the repo'\''s .gitignore so\n' "$ignore_src"
            printf '        teammates cannot commit their own copy\n'
            ;;
        *) printf '  ok    .claude/settings.local.json ignored via %s\n' "$ignore_src" ;;
    esac
fi

[ "$rc" -eq 0 ] || die "verification failed — see above"
printf '  ok    %d files installed\n' "${#FILES[@]}"

cat <<EOF

Done. Commit the .claude/ changes in $(basename -- "$TARGET"), then review that
repo's intent layer:
  python3 .claude/bin/validate-intent-layer $TARGET
EOF
