# Root Intent Layer Block

Injected verbatim into the root node's `## Usage Patterns` section by SKILL.md Create/Update
Mode Step 6. The exact wording is load-bearing — never paraphrase.

```markdown
### Intent Layer Navigation

This project has a network of `CLAUDE.md` intent nodes in subdirectories. Each node
contains invariants, contracts, and gotchas not visible from reading the code.

**Before working in, searching in, or making any claim about code in any directory:**

1. Check for a `CLAUDE.md` in that directory and read it if present.
2. Walk up to the project root and read every ancestor `CLAUDE.md` along the path.

Do not rely on auto-loading — nodes are only injected when a file in that directory is
read by the main thread. Explicit reads are required when working in unfamiliar directories
or making claims about code you have not directly visited this session.

**Scope constraint:** The knowledge in each node is valid **only** for that node's
directory and its subdirectories. Do not extrapolate a node's contracts, patterns, or
anti-patterns to sibling directories or parent directories — those areas have their own
nodes and their own rules.
```

## Why this block is necessary

Auto-loading fires only when the main thread reads a file in a directory — never at session
start, inside subagents, or when an agent infers a module from context instead of visiting it.
The empirically observed hallucination failure mode is always "node not loaded because
directory not visited," never "node loaded with wrong content" — e.g. claiming a class's base
type from vocabulary in a sibling node's text. The block is deliberately short to keep its
per-session token cost negligible.
