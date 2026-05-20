---
description: Validate the intent layer (CLAUDE.md nodes and offload files) under the current directory
---

Run the intent layer validator with JSON output:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/bin/validate-intent-layer" --json .
```

Parse the JSON output and report:

- Summary: pass/fail, error count, warning count
- For each error: file path, what's wrong, and how to fix it
- For each warning: file path and recommendation
- For orphans: which files are unlinked and where they should be downlinked from

If the validator passes with no issues, confirm the intent layer is healthy.
If there are errors, prioritize them and offer to fix the most critical ones first.
