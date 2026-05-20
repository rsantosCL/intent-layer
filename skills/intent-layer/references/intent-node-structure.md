# Intent Layer — Required Structure

Every node and offload file must follow this structure (terms in `non-negotiable-rules.md`). `## Purpose & Scope` is required. Omit other sections that genuinely don't apply — don't pad with placeholders.

```markdown
# [Area Name]

## Purpose & Scope

What this area handles, and explicitly what it does NOT handle.

## Entry Points & Contracts

Main APIs, interfaces, or entry points agents will interact with. Invariants callers must respect.

## Usage Patterns

Canonical examples of correct usage. How to work with this area the right way.

## Anti-patterns

What to avoid and why. Include gotchas that have caused real bugs.

## Downlinks

Link definitions for child nodes and offload files. The parenthesized title describes what each covers or when to read it:

[subdir/CLAUDE.md]: subdir/CLAUDE.md (what it covers)
[TOPIC.md]: TOPIC.md (when to read it, what it explains)
```
