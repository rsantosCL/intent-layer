# validate-intent-layer

Validates the intent layer (nodes and offload files — terms in `skills/intent-layer/references/non-negotiable-rules.md`) under a directory tree. Checks structural correctness, naming, token budgets, downlink integrity, and orphaned files — exits non-zero on any error.

## Usage

```text
validate-intent-layer [--json|--jsonl] [directory]
validate-intent-layer --help
```

Defaults to the current directory. The path is resolved to an absolute path at startup so all internal comparisons are stable regardless of how the script was invoked. `--json` and `--jsonl` are mutually exclusive; omitting both produces human-readable text output. `--help` prints usage and flag descriptions then exits 0.

## Output

### Text mode (default)

The output is a single depth-first tree rooted at the root `CLAUDE.md`. Every file — nodes and offload files alike — is rendered with a `●` prefix. The root node is flush-left; all children use `├─`/`└─` connectors and indent with `│  `/`   ` continuation strings. Nesting is unbounded. Orphan files appear in the tree under their nearest ancestor node, marked `⚠` in yellow with the reason in parentheses.

**Child ordering:** subdirectory children first (alphabetical), then same-directory files (alphabetical). This matches the convention used by `tree` and most file browsers.

Node token counts are colored via a truecolor gradient (Gruvbox anchors via `gradient_error_color` from `zsh/conf.d/colors.sh`): pure green below 50% of the cap, interpolating to yellow at 70%, then to red at `TOKEN_WARN_PCT`% (default 90), staying red above. Offload file token counts are uncolored and suffixed with `(offload)`.

Issues (`✖` errors in red, `⚠` warnings in yellow) are printed after the file header. When a file has children, its issue lines use a `│` prefix to continue the tree line; otherwise `   `.

A compact summary line closes the output: `N errors · N warnings · PASS/FAIL`. Colors are suppressed when stdout is not a terminal.

Exit code is 0 (PASS) if there are zero errors, 1 (FAIL) otherwise. Warnings do not affect the exit code.

### `--jsonl` mode

Emits one JSON object per line as files are processed (streaming). Record types:

- `{"type":"start","target":"<abs-path>"}` — first line
- `{"type":"file","path":"…","kind":"node"|"offload","tokens":N,"token_pct":N,"issues":[…]}` — one per file visited
- `{"type":"orphan","message":"…"}` — one per orphan found
- `{"type":"summary","pass":true|false,"errors":N,"warnings":N}` — last line

### `--json` mode

Emits a single JSON document after all processing completes:

```json
{
  "target": "<abs-path>",
  "summary": { "pass": true|false, "errors": N, "warnings": N },
  "files": [ { "path": "…", "kind": "node"|"offload", "tokens": N, "token_pct": N, "issues": […] } ],
  "orphans": [ { "message": "…" } ]
}
```

Each issue object: `{"level":"error"|"warn","message":"…"}`. Both machine modes suppress all human-readable output.

## Checks

### Per-file (every intent-layer file: nodes and offload files)

- **H1 heading** (error) — every file must open with a `# Title` line.
- **Purpose & Scope** (error) — `## Purpose & Scope` section must be present. Required by `intent-node-structure.md`; both nodes and offload files follow node structure.

### Per-file (nodes only)

- **Token cap** (error if >1000, warning if ≥`TOKEN_WARN_PCT`% of 1,000) — token count is estimated as `byte_count / 3.5`. `TOKEN_WARN_PCT` (default 90, i.e. ≥900 tokens) is a top-level constant that also drives the gradient red threshold, so both stay in sync. The 1,000-token hard cap and 3.5 ratio for English prose come from `skills/intent-layer/references/size-rules.md`. Offload files are uncapped.
- **AGENTS.md coexistence** (error) — checked only at the project root. A root `CLAUDE.md` and `AGENTS.md` must not coexist; this rule does not apply to subdirectories.

### Per-file (offload files only)

- **Naming convention** (error) — filename must match `$OFFLOAD_NAME_REGEX` from `skills/intent-layer/references/offload-naming.json` (ALL-CAPS, hyphen-separated, ending in `.md`). Examples: `MODULE-DETAILS.md`, `LOAD-ORDER.md`, `MIGRATION-GUIDE.md`.
- **Reserved/generic-name blocklist** (error) — names matching `is_blocklisted_name` from the same shared file (`README.md`, `CHANGELOG.md`, `LICENSE.md`, `CONTRIBUTING.md`, `OVERVIEW.md`, `INDEX.md`, `NOTICE.md`, `AUTHORS.md`, `SECURITY.md`, `MAINTAINERS.md`, `GOVERNANCE.md`, `AGENTS.md`, `COPYING.md`, `INSTALL.md`, `HISTORY.md`, `TODO.md`, `FAQ.md`, `SKILL.md`) are reserved for human-facing or tooling docs. The same rules are used by the `PreToolUse` hook at `hooks/intent-layer-preload.sh`.

### Downlinks

Downlinks live in the `## Downlinks` section as bare link definitions:

```markdown
[path/to/file.md]: path/to/file.md (description of what it covers and when to read it)
```

Every non-blank line in `## Downlinks` must match this format. Prose references elsewhere in the file (backtick-quoted paths) are informational only — they carry no existence contract and are not validated.

For each downlink line:

- **Invalid format** (error) — non-blank line does not match the link-definition syntax.
- **Missing description** (error) — the parenthesized title is absent. Every downlink must describe what the target covers and when to read it.
- **Non-.md target** (warning) — target path does not end in `.md`. Only `.md` files are intent-layer members.
- **Broken downlink** (error) — target path does not exist on disk.
- **Recursive descent** — if the target is a `.md` file within TARGET, `check_node` is called on it. This is how offload files get validated with the per-file checks above.

### Orphan check

Runs after all nodes are processed. Two separate scans feed the same output section, which is suppressed entirely if both scans find nothing.

**Node orphans** — every non-root `CLAUDE.md` walks up its directory ancestry to find the nearest ancestor node. If that ancestor's `## Downlinks` section does not contain either the child's relative path or its directory name followed by `/CLAUDE.md`, the child is warned as not referenced. Only the `## Downlinks` section is checked — prose backtick mentions in node body text carry no contract and do not suppress orphan detection.

**Unlinked .md files** — a `find` pass collects every `.md` file under TARGET except `CLAUDE.md` files and files under `.git/` or `.claude/`. Paths matching `<claude-dir>/<machinery>/` are then filtered out (see below). The remaining set is narrowed to files that *look* like intended offload files: basename matches `$OFFLOAD_NAME_REGEX` and is NOT in `is_blocklisted_name` (both from `offload-naming.json`). Any remaining file not in the `seen` set is warned as not downlinked from any node. Files outside the offload-naming convention (e.g., `README.md`, `bootstrap.md`) are not flagged — they aren't intent-layer candidates by the rules. Prose references (backtick mentions) do NOT add files to `seen` — only proper downlinks do.

#### Claude machinery exclusion

Files inside `<claude-dir>/<machinery>/` are skipped from the unlinked-file scan because they hold agent runtime content (skill definitions, agent definitions, custom commands, hook scripts) loaded by Claude Code directly, not by the intent-layer hierarchy.

- `<claude-dir>` — `.claude` or any directory whose name contains the substring `claude` (e.g., `claude/`, `my-claude-config/`).
- `<machinery>` — one of `skills`, `agents`, `commands`, `hooks`, `plans`, `memory`, `plugins`.

Files in these directories that are explicitly downlinked from a node remain validated normally — the visited-set logic above marks them before the exclusion runs.

## Design

### visited and seen sets

Two associative arrays with distinct roles:

- **`visited`** — recursion guard for `check_node`. Set on entry to `check_node` and checked at the top of the function for short-circuit. Never written outside `check_node`. Keeping this separate from `seen` is what prevents a prose-mention pass from accidentally short-circuiting a later recursive descent into the same file.
- **`seen`** — orphan-check input. Set when a `.md` file inside TARGET is resolved as a downlink in `## Downlinks` or entered by `check_node`. Prose references (backtick mentions) do not add to `seen` — references carry no existence contract. The unlinked-file scan flags any `.md` file absent from `seen` (and not in a Claude machinery directory) as not downlinked from any node.

### Recursion strategy

`check_node` is recursive but bounded in practice: the graph of downlinks is shallow (node → offload file → done; offload files own no offloads of their own per `size-rules.md`) and the `visited` guard prevents cycles. There is no explicit depth limit.

The function sets no globals that need restoration across recursive calls. Output is depth-first. Children are sorted with subdirectory entries first, same-directory files second, each group alphabetical. Orphans for a given node are merged into the same sorted list and rendered with `⚠` instead of `●`; they are leaf entries (no further recursion, since orphans are not in `node_data`).

### Token estimation

Byte count divided by 3.5 (implemented as `chars * 10 / 35` for integer arithmetic) estimates Claude tokens for English prose. The 3.5 ratio comes from Anthropic's glossary (<https://docs.anthropic.com/en/docs/about-claude/glossary>) and is codified in `skills/intent-layer/references/size-rules.md`. It avoids spawning a tokenizer and is fast enough for any repo size.

### Downlink regex

Each non-blank line in `## Downlinks` is matched against:

```text
^\[([^\]]+)\]:\s*(\S+)(?:\s+["'(](.+?)["')])?$
```

Group 1 = label, group 2 = target path, group 3 = description (title). The title delimiters `"`, `'`, and `(…)` are all accepted per CommonMark. A line that matches but has an empty group 3 triggers the missing-description error rather than the invalid-format error, so the message is actionable.

## Dependencies

- `/usr/bin/python3` — Apple Command Line Tools (Python 3.9+). No third-party packages.
- No external tools, no network access.
