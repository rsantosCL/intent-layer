# Testing the Intent Layer Skill

This guide explains how to evaluate the intent-layer skill after making changes, following the same pattern used in the original development.

## Evaluation Approach

Run the skill (with-skill) and a baseline (without-skill) on the same directories, then compare the outputs. The baseline gets only a one-sentence description of the intent layer approach — no SKILL.md. This reveals what the skill adds over Claude's native judgment.

## Test Directories (YCharts repo)

These directories were chosen to cover three different scenarios:

| Directory | Lines | Tests |
|---|---|---|
| `apps/hypotheticals/` | ~15k | Full create-mode: produces multiple CLAUDE.md files end-to-end |
| `apps/model_portfolios/` | ~150k | Larger create-mode: tests boundary selection, hierarchy, and compression at scale |
| `apps/calculations/` | ~643k | Size detection: should stop, give actionable breakdown, and ask user which subdir to start with |

You can substitute other directories if needed — the key is to have one small, one medium, and one that triggers the "too large" guard.

## How to Run Evals

For each test directory, spawn two agents in parallel — one with-skill, one without. Tell both to output CLAUDE.md content directly in their response (not write to disk) to avoid permission issues with subagents.

Fill in `<skill-path>` with the absolute path to `skills/intent-layer/SKILL.md` in your checkout of this repo, and `<project-dir>` with the absolute path to the project you're evaluating against.

### With-skill agent prompt template

```text
You are running an evaluation of a Claude Code skill. Execute the task and include ALL output directly in your final response message.

## Skill to use
Read `<skill-path>` FIRST, then follow it precisely. Do NOT follow any other skill. Do NOT run permission scans or transcript scans.

## Task
[Create CLAUDE.md intent layer nodes for <directory> in <project-dir>.]

## IMPORTANT: Scope your reading
Do NOT read every file. Focus on structurally significant files (entry points, core logic, config, public interfaces). Skip test files, migrations, fixtures. Use line counts to prioritize.

## Output format
Do NOT write any files to disk. Include everything in your response using this exact format:

FILE: <path>/CLAUDE.md
\```
[full content]
\```

(repeat for each)

SUMMARY:
- path — ~NNN tokens — [reason]
- path — SKIPPED — [reason]

Include full content for every CLAUDE.md you would create.

## Working directory
<project-dir>
```

### Without-skill (baseline) agent prompt template

```text
Execute the following task and include ALL output directly in your final response message.

## Task
[Same task as above.]

The "intent layer approach": place small, focused CLAUDE.md files at semantic boundaries in the codebase. Each captures what that area is for, how to use it safely, and what patterns and pitfalls exist. Parent nodes summarize children, not raw code. No additional skills — use your best judgment.

## IMPORTANT: Scope your reading
Do NOT read every file. Focus on structurally significant files. Skip test files, migrations, fixtures. Use line counts to prioritize.

## Output format
[Same format as above.]

## Working directory
<project-dir>
```

## What to Check (Assertions)

### Create-mode evals (hypotheticals, model_portfolios)

| Assertion | What it checks |
|---|---|
| `at-least-one-node-created` | At least one CLAUDE.md file in output |
| `each-node-under-1k-tokens` | Every CLAUDE.md ≤ ~1,000 tokens (~750 words / ~4,500 chars) |
| `target-compression` | Most nodes in the 300–500 token range |
| `contains-purpose-and-scope` | Every CLAUDE.md has a "Purpose & Scope" section |
| `contains-patterns-or-antipatterns` | Every CLAUDE.md has "Usage Patterns" and/or "Anti-patterns" |
| `parent-has-downlinks` | Parent nodes reference child CLAUDE.md files |
| `no-code-restatement` | Nodes capture invariants/contracts, not class/method listings |
| `views-not-skipped` | HTTP handler / controller directories get nodes when they have auth/routing contracts |
| `frontend-checked` | Frontend/client-side code directories are evaluated as candidates |
| `existing-docs-discovered` | Agent scans for .md/.rst/.txt docs and links to them instead of restating |
| `low-density-dirs-skipped` | Dirs that fail any hard reason in `size-rules.md` don't get their own node (covered in parent, or via an offload file there) |

### Size-detection eval (calculations)

| Assertion | What it checks |
|---|---|
| `no-nodes-created` | Zero CLAUDE.md files created |
| `explicitly-flags-size` | Response says the directory is too large for one session |
| `per-subdir-breakdown` | Response includes a size breakdown per subdirectory |
| `non-node-dirs-identified` | Response names which dirs won't get nodes and why (which hard reason they fail) |
| `existing-docs-found` | Response discovers and mentions existing documentation files |
| `prioritized-recommendations` | Response recommends subdirectories in a prioritized order with rationale |
| `does-not-proceed-blindly` | Agent stops and asks user which area to start with |

## Comparing Results

The key question: **does the skill produce better output than the baseline?**

Things the skill should consistently beat the baseline on:

- **Structure**: proper hierarchy with leaf-first nodes and downlinks (baseline tends toward flat/monolithic files)
- **Token discipline**: nodes in the 300–500 range, never over 1k (baseline often produces single large files)
- **Doc discovery**: scans for and links to existing documentation (baseline sometimes misses this)
- **Completeness**: covers views, frontend, and other "thin layer" directories that baselines skip
- **Size guard**: actionable breakdown with priorities when directory is too large (baseline may be more thorough on individual items but less structured)

Things the baseline may still beat the skill on:

- **Depth**: richer content within individual nodes (more hidden knowledge, more specific invariants)
- **Edge cases**: borderline directory discussions, nuanced skip/include reasoning

If the baseline consistently beats the skill on structure or doc discovery, the skill needs work. If the baseline only beats on depth, the skill is doing its job — depth comes from domain knowledge, not process.

## Workspace Layout

Keep eval results in a directory outside the repo (so they don't pollute git history). Suggested structure:

```text
<workspace-dir>/
├── iteration-1/
│   ├── eval-hypotheticals-create/
│   │   ├── with_skill/
│   │   └── without_skill/
│   ├── eval-model-portfolios-create/
│   │   ├── with_skill/
│   │   └── without_skill/
│   └── eval-calculations-size-detection/
│       ├── with_skill/
│       └── without_skill/
└── iteration-2/
    └── (same structure)
```

Each eval directory contains `timing.json` and either `outputs/` (with CLAUDE.md files) or the content captured from agent result messages.
