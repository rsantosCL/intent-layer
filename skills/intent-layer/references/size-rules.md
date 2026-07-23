# Intent Layer — Size Rules

Hard rules for `node` and `offload file` sizing. Terms defined in `non-negotiable-rules.md`.

## Token estimation

Estimate tokens as byte count ÷ ratio (1 token ≈ 3.5 English chars, per Anthropic's glossary):

| Content type | Ratio | Use for |
| --- | --- | --- |
| Prose (`.md`, `.txt`, `.rst`) | 3.5 | Per-node cap |
| Whitespace-heavy code (`.py`, `.rb`, `.sh`, `.zsh`, `.lua`, `.hs`, `.ex`, `.yml`) | 3.0 | Source-size triage |
| Punctuation-heavy code (`.c`, `.cpp`, `.rs`, `.go`, `.java`, `.cs`, `.ts`, `.swift`, `.kt`, `.scala`, `.json`) | 2.5 | Source-size triage |

Default 3.0 for unlisted extensions.

## When to create a node

No source-size floor. Create a node only when ALL three hard reasons are met:

1. **Rule compliance.** The node will satisfy `non-negotiable-rules.md`, `intent-node-structure.md`, and the per-node cap below.
2. **Local-only relevance.** The content makes sense only for this directory and its sub-directories; it would not be useful at a higher vantage point.
3. **Doesn't fit in the closest ancestor.** Folding into the ancestor node — or one of its offload files — would exceed the cap, dilute scope, or mix directory-specific detail with cross-cutting context.

When all three hold, prefer a colocated node over an offload file one level up.

A directory that fails any reason does not get a node. Move its content up; create an offload file in the ancestor if needed.

For very large directories (>50k source tokens), apply the test per sub-directory rather than producing one oversized parent.

## Per-node cap

Every node stays under ~1,000 tokens. Aim for 300–500 — shorter is better. Over the cap → offload to an offload file (below), downlinked from the node with a one-line note on when to read it.

**Root-node exception:** the project root node may go up to ~2,000 tokens. It loads in every session, LCA placement funnels shared facts into it, and offloading a project-wide invariant risks it never being loaded. The higher cap is a ceiling, not a target — aim for under 1,000, and apply the same offload discipline beyond that.

## Offload files

- **No size cap.**
- **Same structure as a node** (`intent-node-structure.md`).
- **May downlink to other offload files or nodes, but never has its own offload files** — is uncapped, so overflow is not possible.
- **Naming: ALL-CAPS, hyphen-separated, topic-specific.** Examples: `MODULE-DETAILS.md`, `LOAD-ORDER.md`, `MIGRATION-GUIDE.md`. Never `README.md`, `OVERVIEW.md`, `INDEX.md`, or other generic names — `README.md` is reserved for human-facing docs.
