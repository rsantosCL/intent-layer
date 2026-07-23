# Intent Layer — Non-Negotiable Rules

Rules that MUST hold for every intent-layer create/update. See `intent-layer-methodology.md` for philosophy and `../SKILL.md` for the workflow.

## Terminology

- **Node** — a `CLAUDE.md` file. See `size-rules.md` (cap) and `intent-node-structure.md` (required sections).
- **Offload file** — a non-`CLAUDE.md` `.md` downlinked from a node to hold detail beyond the node's cap. See `size-rules.md` for sizing, naming, and downlink rules; `intent-node-structure.md` for structure.
- **Reference** — a backtick-quoted file mention. NOT part of the intent layer; no existence contract.
- **Downlink** — a link definition (`[path]: path (description)`) under `## Downlinks`. Target must exist.

The **intent layer** is exactly the set of nodes and offload files reachable via downlinks from the root node. Promoting a reference into the intent layer means adding it as a downlink (and ensuring it has node structure). Demoting means removing the downlink.

## Never do these

1. **Don't dump everything into one root node.** A 15k-token root adds burden, not signal.
2. **Don't repeat what's in code.** Capture only what code cannot express — invariants, hidden contracts, anti-patterns.
3. **Don't repeat existing docs.** Downlink to them; never restate.
4. **Don't organize for human readers.** Write for token-limited agents with no institutional memory.
5. **Don't let nodes drift.** Intent-affecting changes update the node in the same commit. Stale nodes are worse than no nodes.
6. **Don't create nodes for everything.** Only where the three hard reasons in `size-rules.md` are met.
7. **Don't create duplicate root nodes.** `CLAUDE.md` and `AGENTS.md` must not coexist at the project root.

## Always do these

1. **Aggressive compression — never at the cost of signal.** Distill into the minimum high-signal tokens. If compacting further would drop a contract, invariant, or anti-pattern, offload instead (`size-rules.md`); if unsure whether something is signal, ask the user.
2. **Progressive disclosure via downlinks.** A file is part of the intent layer only if it is downlinked (and has node structure). Prose mentions are references, not commitments — promote them to downlinks to pull them in.
3. **Hidden knowledge.** Surface what senior engineers know by heart but isn't in the code.
4. **Leaf-first.** Write deepest nodes first; parents summarize children, not raw code.
