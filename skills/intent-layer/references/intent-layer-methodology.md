# The Intent Layer

> Source: intent-systems.com/blog/intent-layer — Tyler Brandt, December 2025

---

> **Operative rules.** The article below describes the methodology. The terminology, non-negotiable rules, and numeric thresholds that govern every intent-layer create/update workflow live in this skill's `SKILL.md` and its reference files. Headline rules:
>
> - **Terminology** — *node* (`CLAUDE.md`, capped at ~1,000 tokens), *offload file* (uncapped `.md` with the same structure, named `TOPIC.md` in ALL-CAPS), *reference* (prose mention, not part of the layer), *downlink* (the link itself).
> - **When to create a node** — only when ALL three hard reasons hold: rule compliance, local-only relevance, and doesn't-fit-in-the-closest-ancestor. No source-size floor.
> - **Per-node cap** — every node stays under ~1,000 tokens; aim for 300–500. Overflow → offload file, downlinked.
> - **No duplication** — if a fact lives in ancestor nodes, code, or existing docs, link to it instead of restating.
>
> Read SKILL.md before doing any intent-layer work — the article alone does not contain these operational rules.

---

## Table of Contents

- [The Dark Room](#the-dark-room)
- [Turning On the Lights](#turning-on-the-lights)
- [Is This Just AGENTS.md Files?](#is-this-just-agentsmd-files)
- [How It Works](#how-it-works)
- [Building It](#building-it)
- [Maintenance Flywheel](#maintenance-flywheel)
- [Investment & Payoff](#investment--payoff)

---

## The Dark Room

Your repo has structure—directories, modules, services. But agents interpret all of it through tokens. If you want to reason about what an agent can handle, start thinking in tokens.

- `UserService.java` → 8k tokens
- `src/services/` → 120k tokens
- `billing-service` repo → 2.5M tokens
- Your product across repos → 20–100M tokens

It adds up fast. But that's just file content—agents also need to discover structure: how things connect, where boundaries live, what calls what. They do this by grepping, navigating, reading files. Every step costs tokens too.

Watch what happens when an agent tries to debug a payment validation bug in a 2.5M token codebase: agents explore to discover structure. Every step costs tokens. The context window is finite.

Notice the token breakdown. Some goes to the query, some to exploration overhead (ls, grep), some to relevant code, and some to dead ends—tests that use mocks, docs that are too high-level, files that seemed related but weren't.

That noise isn't just wasted space—it actively degrades quality. Transformers weigh every token against every other token. Irrelevant context doesn't sit inert; it competes for attention, drowning out signal. All of this eats the budget you need to actually implement and test the fix.

Now look at what it missed. The agent followed reasonable leads—read services, checked tests, searched patterns—still missed the config file with the bug. `settlement-policy.yml` lived in `platform-config/` hidden behind an abstraction, not `payment-service/` where the agent looked.

### This is the dark room problem

Every agent starts from zero. Every request is a full onboarding—not just to your task, but to your entire system. And most systems are too large to fit. The agent is fumbling in the dark, learning only by what it bumps into.

But there's a deeper issue: even when the agent does find the right files, code alone doesn't tell the whole story. Why does this abstraction exist? What must never happen here? Where are the real boundaries? That knowledge lives in heads and scattered docs—not in source files.

What if you could give it the map before it starts?

---

## Turning On the Lights

The fix is a thin, hierarchical context system that lives inside your repo: the **Intent Layer**.

The basic unit is the **Intent Node**—a small, opinionated file (`AGENTS.md`, `CLAUDE.md`, or similar) that explains what that area of the system is for, how to use it safely, and what patterns and pitfalls agents need to know there. The exact filename depends on your tooling; the semantics are what matter.

**The key behavior:** if an Intent Node exists in a directory, it covers that directory and all subdirectories, and is automatically included in context whenever an agent works there.

The Intent Layer is the collection of these nodes across your repo—a sparse tree overlaid on your codebase. Not every directory needs a node. You place them at semantic boundaries: where responsibilities shift, contracts matter, or complexity warrants dedicated context.

When an agent enters the repo, the harness auto-loads the root Intent Node. That node contains **downlinks**—pointers to child Intent Nodes covering subsystems. The agent follows these downlinks as it navigates, building up a vertical stack of context before it touches implementation.

### Same Task, Different Outcome

Let's run the payment validation bug again—this time with an Intent Layer in place.

The harness auto-loads the root Intent Node. From there, the agent follows downlinks:

- `AGENTS.md` (root) — global architecture, mentions payment service
- ↳ `services/AGENTS.md` — how services are structured
- ↳ `payment-service/AGENTS.md` — mentions settlement rules live in `platform-config/`
- ↳ `platform-config/AGENTS.md` — describes the rules directory

Before the agent reads a single line of code, it already knows where to look. No guessing. No dead ends.

**16k tokens of Intent Layer context. 16k tokens of relevant code. Bug found.**

Compare that to the Dark Room: 40k+ tokens consumed, mostly on exploration and dead ends, critical file never found.

The agent still does agentic search, but it starts with a **high-signal map** instead of grepping and hoping. It knows the enforcement point. It knows the invariants. It knows what must never happen.

---

## Is This Just AGENTS.md Files?

Yes and no.

If you've used Claude Code, Cursor, or Codex, you've seen `AGENTS.md` or `CLAUDE.md` files. These are Intent Nodes, and yes, the Intent Layer is built from them.

But there's a gap between "we have some AGENTS.md files" and "we have a functional Intent Layer." The difference is analogous to the gap between "we have some tests" and "we have a test suite with meaningful coverage, maintenance infrastructure, and CI pipelines."

**The Intent Layer has two jobs:**

1. **Compress context.** A good Intent Node distills a large area of code into the minimum tokens an agent needs to operate there safely. If your node is 10k tokens for a directory that's 20k tokens of code, you're adding weight, not compressing.

2. **Surface hidden context.** Code doesn't capture everything: invariants that aren't enforced in types, architectural decisions that live in people's heads, "why things are this way," contracts that exist across service boundaries. Intent Nodes make that invisible knowledge visible.

These goals are why building an effective Intent Layer requires real skill in context engineering. It's not a simple optimization problem. You're simultaneously compressing and enriching.

### Naive Approach

- **Dump everything into a single root file** that balloons to 15k+ tokens and overwhelms the context window—adding weight instead of compressing
- **Duplicate what's already in code** instead of capturing what code can't express
- **Structure information for human readers**, not token-limited agents with no institutional memory
- **Drift out of sync** with code within weeks because no one owns maintenance
- **Miss the hierarchical loading behavior** that makes context automatic—or naively duplicate files (`AGENTS.md` + `CLAUDE.md`) without understanding which tools load what

### Done Right

- **Compresses aggressively**—each node distills its area into the minimum high-signal tokens needed
- Places nodes at **semantic boundaries**—where responsibilities shift, contracts matter, or complexity warrants dedicated context
- Uses **downlinks** so agents can drill into detail without loading everything upfront
- Captures **invariants and anti-patterns** that aren't visible in code but that your senior engineers know by heart
- Adapts to **auto-loading behavior** across different tools without unnecessary duplication
- Is created through a **structured capture protocol** that systematically extracts tribal knowledge
- Includes **maintenance automation** so it doesn't rot

The unifying principle is progressive disclosure. Start with the minimum high-signal context, let agents drill into detail as needed. This principle drives the hierarchical structure, the downlinking, the compression, and where each fact belongs.

The methodology matters. An Intent Layer isn't a collection of documentation files. It's a token-efficient context system designed for how agents actually consume information.

---

## How It Works

### What's in a Node

Intent Nodes should be small but dense. Think of them as the highest-signal briefing you'd hand a senior engineer before they touch that area of the codebase.

A healthy Intent Node tends to contain:

**Purpose & Scope**
What this area is responsible for. What it explicitly doesn't do.

**Entry Points & Contracts**
Main APIs, jobs, CLI commands. Invariants like "All outbound calls go through this client" or "This is the only enforcement point for age-based ad policy."

**Usage Patterns**
Canonical examples: "To add a new rule, follow this pattern…"

**Anti-patterns**
Negative examples: "Never call this directly from controllers; go through X."

**Dependencies & Edges**
Which other directories or services it depends on. Downlinks to child Intent Nodes.

**Patterns & Pitfalls**
Things that repeatedly confused agents or humans: "This looks stateless but uses shared mutable state." "This config is overridden at deploy time; don't trust the default."

### File Naming & Auto-Loading

Different agent harnesses auto-load different files:

- **Claude Code** uses `CLAUDE.md`
- **Codex and others** use `AGENTS.md`
- **Cursor** uses rules and skill files

This is why we use the term "Intent Node" rather than a specific filename. The physical filename is determined by your tooling; the content and hierarchy are what matter.

Survey the agent tools your team uses and ensure your Intent Nodes are auto-loaded by all of them. Options include symlinks (e.g., `AGENTS.md → CLAUDE.md`), Cursor rules/skills files, or custom harness configurations.

But be careful not to go overboard duplicating the same content across every filetype. This bloats your Intent Layer and creates drift. Find the minimal solution that covers your tooling.

### Hierarchical Context

The key behavior: when an Intent Node is pulled into context, all of its ancestor nodes are pulled in too. The agent never starts reasoning without the high-level picture.

This gives the agent a **T-shaped view**: broad context at the top, specific detail where it's working. The high-level picture stays in view while the agent explores, making it easier to link disparate areas together and reason about cross-cutting concerns.

Hierarchical loading enables the **Least Common Ancestor optimization**. Shared knowledge lives once at the shallowest node that covers all relevant paths, rather than duplicated in every leaf. This keeps individual nodes small and reduces the overall size of the Intent Layer.

An Intent Node **covers its directory and all subdirectories**. No node in `/services/payment/validators/`? The agent still gets context from `/services/payment/AGENTS.md` above it. Place nodes at semantic boundaries, not every folder—the hierarchy handles coverage without bloating your context budget.

### Downlinks

Sometimes related context lives outside the ancestor chain. A node can include **downlinks** to point agents toward relevant context elsewhere:

**Downlinks to child Intent Nodes:**

```text
## Related Context
- Payment validation rules: `./validators/AGENTS.md`
- Settlement engine: `./settlement/AGENTS.md`
```

**Outlinks to other documentation:**

```text
## Architecture Decisions
- Why we use eventual consistency: `/docs/adrs/004-eventual-consistency.md`
- Payment flow diagram: `/docs/architecture/payment-flow.md`
```

The key principle is progressive disclosure. You don't want to load irrelevant context upfront. Instead, Intent Nodes point to related context that agents can follow if needed. This keeps the initial context load lean while making deeper context discoverable.

---

## Building It

Now the practical part: how this layer actually gets installed on a real, messy repo.

### The Capture Workflow

Chunking the codebase → leaf-first capture with SME interviews → hierarchical summarization.

### Hierarchical Summarization

The Intent Layer gets its compression from one key mechanic:

**When capturing a parent, you summarize child Intent Nodes—not the raw code they cover.**

This creates **fractal compression**. Leaf nodes compress raw code into dense context. Parent nodes compress their children's Intent Nodes. Each layer stands on stable, already-compressed context from below—a 2k token parent node might cover 200k tokens of underlying code.

The payoff is **progressive disclosure at scale**. When an agent enters your repo, it doesn't load everything upfront. It gets the high-level picture first, then follows downlinks into detail only where the task requires it. Context stays lean. Signal stays high. The agent navigates a million-token codebase the way your senior engineers do—by knowing what to ignore.

### Chunking

The goal is optimal token compression. How you carve up the codebase determines how efficiently the Intent Layer compresses your code.

**Chunk size affects compression ratio.** A 2k token file might compress to 1k—poor ratio, lots of overhead. A 64k token chunk of related code might compress to 2-3k—excellent ratio. Aim for the **20k–64k sweet spot**: large enough for meaningful compression, small enough to stay in the model's sharp region.

**Similar code compresses better together.** This is why semantic boundaries matter. Code that shares responsibility, patterns, and vocabulary summarizes more efficiently than disparate code forced into one chunk. Mixed concerns mean worse compression and muddier summaries.

**Disparate areas connect through hierarchy, not concatenation.** When code doesn't belong together, don't force it. Summarize each area into its own Intent Node, then let a parent node draw lightweight connections between them. This is true at capture time (better compression) and at runtime (agents load only what they need).

The result: your Intent Layer mirrors your architecture because that's what compresses best. Semantic boundaries aren't an aesthetic choice—they're an optimization for token efficiency.

### Squeeze Ambiguity

Capture in order of clarity: children before parents, well-understood areas before tangled ones.

**Easy areas first, hard areas last.** By the time you reach the gnarliest parts of your system, you have rich, stable Intent Nodes all around them. Each captured node makes adjacent captures easier—clarity compounds.

**The loop is iterative, not fixed.** For each chunk, the agent analyzes the code along with any accumulated global state, describes what it sees, and asks clarifying questions. The human responds—answering questions, correcting misunderstandings, explaining history and landmines. This continues until both are aligned on the Intent Node content.

**Track what you can't resolve yet.** Anything that can't be answered in the current chunk gets added to shared state:

- **Open questions**: "Is this path still used in production?" — parked until a neighboring chunk provides the answer.
- **Cross-references**: "This relates to billing validation" — tracked until you can determine the right LCA.
- **Tasks**: Dead code candidates, refactors that emerge from the interviews.

For subsequent chunks, the agent sees both the new code and the accumulated state. If an open question can now be resolved, update or remove it. As you move up the tree questions get answered, facts find their homes, and by the time you reach the root, everything resolves into the Intent Layer itself.

### Deduplicate Shared Knowledge

When a fact applies to multiple areas, where does it go?

**Place it in the Least Common Ancestor (LCA)**: the shallowest Intent Node that covers all paths the fact applies to.

Not in both leaf nodes—that's wasteful and will drift. Not in the root—that loads it even in unrelated areas. The LCA loads it exactly when needed: everywhere it's relevant, nowhere it's not.

This is progressive disclosure for cross-cutting knowledge. Shared contracts, configuration patterns, architectural invariants—all follow the same rule. The fact lives in one canonical place. Agents get it when they need it. It can't drift because there's no duplication.

When capturing, ask: "What's the shallowest node where this fact is always relevant?" That's where it belongs.

---

## Maintenance Flywheel

Yes, the Intent Layer needs maintenance. But that maintenance can be automated—and when done right, it doesn't just prevent rot. It continuously improves agent performance.

### Sync Process

On every merge:

1. Detect which files changed.
2. Identify which Intent Nodes cover those changes.
3. For each affected node (leaf-first, working up):
   - Read the diff and the existing node.
   - Re-summarize if behavior changed.
   - Propose updates.
4. Human reviews and merges, like any code change.

This can be done manually by engineers after significant changes. Because the process is mechanical and well-scoped, it's straightforward to build an agent that handles it automatically on every commit or merge.

### Reinforcement Learning

When agents use the Intent Layer, they surface what's missing:

- They hit edge cases: contradictions between code and nodes, undocumented patterns, sharp edges humans learned to step around.
- They propose updates: refined pitfall sections, corrected invariants, suspected dead code flagged for confirmation.
- Those learnings feed back into the layer. Future agents start from a better baseline.

Your codebase becomes a reinforcement learning environment. Agents get finetuned to your system through better context, not expensive model training. Build once. Agents maintain. Each cycle compounds into institutional memory that never forgets and never retires.

---

## Investment & Payoff

With a functional Intent Layer:

- Agents behave like your best engineers—they know the boundaries, invariants, and landmines before they touch code.
- You can run longer tasks, parallelize agents, and operate at a higher level without babysitting.
- Context compounds. Every hard-won explanation is captured once, reused forever.

The cost scales with the benefit. A small repo takes a few hours; a massive monolith takes longer—but the lift is proportionally bigger. Either way, it pays for itself on basically the next feature.

Maintenance is overhead per PR, not a weekly budget—5-10 minutes if manual, or automate it entirely.

The real unlock is agent throughput. A single engineer with a strong Intent Layer can spin up parallel agents, tackle longer-running tasks, and operate like a small team. And once each repo has its own layer, you can federate them—a root node summarizing your entire product surface makes cross-cutting initiatives something agents can actually help with across dozens of repos.
