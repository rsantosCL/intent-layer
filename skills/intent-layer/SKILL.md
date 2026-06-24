---
name: intent-layer
description: Create or update CLAUDE.md intent nodes across a repository following the intent layer approach. Use this skill when the user invokes /intent-layer, wants to document a codebase for AI agents, asks to "set up intent layer", "create CLAUDE.md files across the repo", or wants to update CLAUDE.md files after a branch diff, PR, or set of changes. Always use this skill for any intent-layer or CLAUDE.md creation/update workflow — even if the user just says "document this directory" or "update the agent context for this PR".
---

# Intent Layer Skill

This skill creates and maintains the intent layer — nodes and offload files (terms in `references/non-negotiable-rules.md`) — following the methodology in `references/intent-layer-methodology.md`. The goal: give AI agents institutional knowledge at semantic boundaries so they never fumble in the dark.

## Two Modes

Run in **Create** mode to build the intent layer from scratch (leaf-first) for a repo or subdirectory. Run in **Update** mode to sync nodes after code changes (branch, PR, or staged diff).

---

## Core Concepts

**Fractal compression**: Leaf nodes compress raw code into dense context. Parent nodes compress their children's nodes. Each layer stands on already-compressed context from below — a 300-token parent node can cover 200k tokens of underlying code.

**Hierarchical loading / T-shaped view**: When an agent works in a directory, it loads root + all ancestors + the local node. This creates a T-shape: broad project context at the top, specific detail exactly where the agent is working. Write every node assuming ancestors are already in context.

**LCA placement**: When a fact applies to multiple areas, place it in the shallowest node that covers all relevant paths. Shared knowledge lives once — never duplicated across siblings.

---

## Non-Negotiable Rules

Read `references/non-negotiable-rules.md` before any intent-layer work. Terminology (node / offload file / reference / downlink) is defined there, followed by the seven "never do" and seven "always do" rules. These are the most common failure modes and must be respected on every operation.

---

## Size Rules

Read `references/size-rules.md` for the three hard reasons that gate node creation, the per-node cap (~1,000 tokens), and the offload-file conventions. These are limits, not aspirations.

---

## Node Structure

Use the template in `references/intent-node-structure.md` for every node and offload file. Omit sections that genuinely don't apply rather than padding with placeholders. Load this reference when creating or restructuring a node or offload file — pure content edits don't need it.

---

## Enforcement Hook

This skill ships with a `PreToolUse` hook (`hooks/intent-layer-preload.sh`) that injects `references/non-negotiable-rules.md` + `references/size-rules.md` into context every time an agent is about to Write or Edit a node (`CLAUDE.md`) or an offload file (ALL-CAPS hyphenated `TOPIC.md`). Well-known generic ALL-CAPS docs (`README.md`, `CHANGELOG.md`, `LICENSE.md`, `CONTRIBUTING.md`, etc.) are blocklisted.

The naming rules and blocklist are defined once in `references/offload-naming.json` and shared between this hook and `bin/validate-intent-layer`.

**If you installed this as a plugin**, hooks are already active — no per-project setup needed.

**Otherwise**, add the following to each project's `.claude/settings.json` (replace `<path-to-plugin>` with the absolute path to the cloned repo):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"<path-to-plugin>/hooks/intent-layer-preload.sh\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

The hook script silently exits if the target file isn't a `CLAUDE.md` or offload file, or if the rule files are missing — so it's safe to install even in repos where this skill isn't actively used.

Skip this step if the repo already has the entry. Verify with `grep intent-layer-preload .claude/settings.json`.

---

## Create Mode

### Step 0: Discover existing documentation

Before writing anything, scan the target directory for existing documentation:

```bash
find . -maxdepth 4 -type f \( -name "*.md" -o -name "*.rst" -o -name "*.txt" -o -name "*.adoc" -o -name "*.org" \) \
  ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/vendor/*" \
  ! -name "CLAUDE.md" ! -name "CHANGELOG*" ! -name "LICENSE*" 2>/dev/null
```

Also check for `docs/` directories, `README` files, API specs, or architecture docs at any level. Record what you find — these are sources to **link to, not restate**. When an existing doc already explains a workflow, pattern, or contract, the node should say `See docs/guide.md for the step-by-step process` (a prose reference) rather than reproducing it. To pull the doc into the intent layer for auto-loading, promote it to an offload file (node structure, ALL-CAPS `TOPIC.md` name) and add it as a downlink.

### Step 1: Estimate scope

Detect the repo's primary source file extensions, then estimate total size:

```bash
# Detect primary languages by extension frequency
find . -type f ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/vendor/*" \
  | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10

# Then count bytes for the dominant source extensions and estimate tokens (see size-rules.md for ratios)
find . -type f \( -name "*.EXT1" -o -name "*.EXT2" \) | xargs wc -c 2>/dev/null | tail -1
```

If the target is too large (heuristic: >200k tokens of source), **don't just say "it's too big."** Give an actionable breakdown:

1. **Per-subdirectory size breakdown**, excluding test dirs, generated code, and data fixtures:

   ```bash
   for d in */; do
     bytes=$(find "$d" -type f \( -name "*.EXT1" -o -name "*.EXT2" \) \
       ! -path "*/test*/*" ! -path "*/__test*/*" ! -path "*/spec/*" \
       ! -path "*/generated/*" ! -path "*/fixtures/*" \
       | xargs wc -c 2>/dev/null | tail -1 | awk '{print $1}')
     [ -n "$bytes" ] && [ "$bytes" -gt 0 ] && echo "$bytes $d"
   done | sort -rn
   ```

2. **Identify directories that won't get nodes** — subdirectories that fail one of the hard reasons in `references/size-rules.md` will fold into a parent node, or use an offload file there if needed
3. **Note existing documentation** found in Step 0
4. **Recommend a prioritized order** for tackling subdirectories — explain which ones are prerequisites for understanding others and why
5. **Stop and ask** the user which area to start with

Do not use subagents unless the user explicitly requests it.

### Step 2: Identify semantic boundaries, leaf-first

Walk the directory tree bottom-up. A directory warrants a node only when ALL three hard reasons in `references/size-rules.md` are met — rule compliance, local-only relevance, and doesn't-fit-in-ancestor. Useful heuristics when applying those reasons:

- Represents a clear responsibility boundary (its own data layer, business logic, API surface, or public interface)
- Has patterns, invariants, or anti-patterns that aren't visible from reading the code

**Don't skip directories just because they appear to be a thin layer over another.** HTTP handlers, controllers, API routes, CLI entry points, and UI components often have their own contracts worth documenting — auth patterns, validation rules, routing conventions, entitlement guards. Evaluate every candidate against the hard reasons.

Also check for frontend or client-side code directories — they often have their own semantic boundaries, state management patterns, and non-obvious gotchas that deserve nodes.

List the candidate directories and your reasoning to the user before writing anything. Get a thumbs-up or corrections.

### Step 3: Read source carefully

For each candidate, read the structurally significant source files — entry points, core logic, configuration, public interfaces. **Scope your reading**: skip test directories, generated code, and data fixtures. Use byte counts to prioritize which files to read first.

As you read, extract answers to these questions — they force specific, high-signal answers rather than general summaries:

- "In one sentence, what does this area own?"
- "What is explicitly NOT this area's responsibility?"
- "What are the main entry points and public interfaces? What must callers do — or never do — when using them?"
- "What must always be true here? What breaks if violated?"
- "What are the implicit rules that aren't in the code?"
- "What mistakes do new engineers typically make here?"
- "What's the most surprising thing about this code?"
- "What looks deprecated or unused but isn't?"
- "Are there performance, scaling, or data-volume constraints that affect how this area must be used?"
- "What happens when this area's dependencies are slow or unavailable? Are there known failure modes?"
- "How does this connect to sibling and parent modules in non-obvious ways?"

### Step 4: Write leaf nodes

Create `CLAUDE.md` files for the deepest candidates first. Each node must:

- Stay under 1,000 tokens (aim for 300–500 when possible); overflow goes into an offload file (`references/size-rules.md`)
- Capture what the code doesn't express — not a summary of what you can already read
- Follow the structure in `references/intent-node-structure.md`
- Link to existing documentation discovered in Step 0 instead of restating it (prose reference for context-only, or promote to offload file with node structure to pull it into the layer)
- Not repeat what ancestor nodes already cover (remember: ancestors load automatically)

Before moving to parent nodes, validate each leaf against this checklist:

- [ ] Under 1,000 tokens
- [ ] Purpose statement in the first two lines
- [ ] Contracts are explicit ("All DB calls go through `db/client.py`", not "handle carefully")
- [ ] Anti-patterns are from real experience, not hypothetical concerns
- [ ] Downlinks use relative paths
- [ ] Nothing duplicated from ancestor nodes

### Step 5: Write parent nodes (summarize children, not code)

Parent CLAUDE.md files tell the agent: "here's the big picture, here's where to drill down." Three rules:

1. **Summarize child nodes, not raw code** — children are already compressed; don't re-read the source.
2. **Apply LCA placement** — if a fact applies to multiple children, move it up to this node and remove it from the leaves.
3. **Add cross-cutting context** — how children relate to each other, patterns that span multiple areas, and anything that only becomes visible at this level of abstraction.

Include downlinks to child nodes and to offload files (the latter for overflow detail you couldn't fit). Existing docs from Step 0 can be pulled in by promoting them to offload files (restructure to node format, rename to ALL-CAPS `TOPIC.md`); otherwise leave them as prose references, not downlinks.

### Step 6: Report to user

List all created files with their approximate token sizes. For each directory you _considered but skipped_, briefly explain why (below threshold, covered by ancestor, etc.). Ask for review and feedback before considering the work done.

---

## Update Mode

### Step 1: Get the diff

```bash
# Current branch vs main/develop
git diff develop...HEAD --name-only

# Staged changes
git diff --cached --name-only

# Specific PR
gh pr diff <PR-number> --name-only
```

### Step 2: Identify affected nodes

For each changed file, walk up the directory tree and find the nearest node. That node — and its offload files and ancestors — may need updating.

### Step 3: Assess impact — skip aggressively

Before editing anything, ask: do these changes affect the intent layer content in that node's scope?

Update only if:

- A new pattern or anti-pattern emerged
- A contract or invariant changed
- A new entry point was added or removed
- The module's purpose or scope shifted

If the change is a refactor, bug fix, test update, or purely internal implementation detail that doesn't alter observable behavior or contracts — **don't touch the node**.

### Step 4: Check for new or changed documentation

If the diff includes new or modified docs (`.md`, `.rst`, `.txt`, etc.), check whether any node should reference them (prose reference) or pull them into the intent layer (promote to offload file, downlink). If a new doc covers something a node was previously explaining inline, replace the inline content — prose-reference the doc, or promote it.

### Step 5: Update leaf-first, propagate up

Update the most specific (deepest) affected node first. Then check if the change cascades to ancestor nodes — update them only if their summary is now inaccurate.

**Compression must never drop signal.** If a node is over the token cap after an update, do not silently discard existing knowledge to make room. Instead:

1. **Offload** — move detail that is still relevant but lower-priority into a new offload file, downlinked from the node.
2. **Split** — if the directory has grown to the point where a subdirectory now warrants its own node (all three hard reasons in `references/size-rules.md` are met), create it and let the parent summarize it.

Trimming prose to fit is fine when the removed words added no signal. Trimming a contract, invariant, anti-pattern, or entry-point description is never acceptable — that knowledge must go somewhere, even if the node cannot hold it directly.

### Step 6: Report changes

Tell the user which nodes were updated and briefly why. For any node you skipped, explain why it didn't need updating.

---

## What to Capture vs. What to Skip

**Capture:**

- Why a module exists and what problem it was created to solve
- Contracts that must be respected (`always call X before Y`, `this field is nullable but never None in practice because...`)
- Non-obvious patterns (`services never import from views`, `all async tasks must inherit from BaseTask`)
- Anti-patterns that have caused bugs (`don't use Model.objects.all() here — the table has 50M rows`)
- How this area connects to the rest of the system

**Don't capture:**

- What you can read from the code (class names, method signatures, obvious structure)
- Anything already covered in a child node — downlink to it
- Anything already explained in existing docs — prose-reference them, or promote them to offload files and downlink
- Generic best practices that apply project-wide (those belong in the root node if anywhere)

---

## Testing This Skill

See `references/testing-guide.md` for how to evaluate this skill after making changes — includes agent prompt templates, assertion checklists, and comparison methodology.
