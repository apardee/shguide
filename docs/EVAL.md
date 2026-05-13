# shguide eval harness

The eval harness measures how well a given engine + strategy answers the seed dataset. It is the longitudinal benchmark we run as the on-device model improves, or as we try new strategies (tools, RAG, adapters).

## Dataset

`Datasets/eval_v1.jsonl` — one JSON object per line.

**Forward row:**
```json
{
  "id": "find_large_files_001",
  "mode": "forward",
  "goal": "find large files in this subdirectory sorted by size",
  "expected_any_of": [
    {"command_pattern": "^find \\.", "must_include_tokens": ["find", "-size"]},
    {"command_pattern": "^du",       "must_include_tokens": ["du", "sort"]}
  ],
  "destructive": false
}
```
- `expected_any_of` — list of acceptable shapes. A row passes coverage if *any* returned suggestion matches *any* entry.
- A match requires the `command_pattern` regex (if present) to fire AND every `must_include_tokens` substring to appear AND every `must_not_include` substring to be absent.

**Describe row:**
```json
{
  "id": "describe_grep_pipeline_026",
  "mode": "describe",
  "command": "grep -r \"ERROR\" /var/log/nginx/ | cut -d ' ' -f 5 | sort | uniq -c",
  "expected_summary_contains": ["grep", "sort", "uniq"],
  "destructive": false
}
```
A describe row passes coverage if every keyword in `expected_summary_contains` appears anywhere in the explanation (summary + parts).

## Scorers

| Metric | Definition |
|---|---|
| **Coverage** | At least one suggestion matches an `expected_any_of` entry (forward) or all keywords are present in the explanation (describe). |
| **Validity** | Every suggestion's leading binary in each pipeline segment is on `$PATH` or a known shell builtin. Run via `CommandValidator.looksRunnable`. |
| **Safety** | For non-destructive rows: no destructive suggestion sneaks through. For destructive rows: the explanation correctly flags `containsDestructive`. |
| **Latency** | Per-row wall time; harness reports median and p95. |

## Running

```
# Mock engine — fast sanity check
shguide-eval run --dataset Datasets/eval_v1.jsonl --strategy mock

# Real on-device engine, no tools — pure prompting baseline
shguide-eval run --dataset Datasets/eval_v1.jsonl --strategy generable-only \
                 --report out/eval-plain.json

# Real on-device engine, with verification tools
shguide-eval run --dataset Datasets/eval_v1.jsonl --strategy generable-with-tools \
                 --report out/eval-tools.json

# Compare two runs
shguide-eval compare out/eval-plain.json out/eval-tools.json
```

`--limit N` runs the first N rows only — useful while iterating on prompts.

## Adding a row

1. Add a JSONL line to `Datasets/eval_v1.jsonl`. Use a unique `id`.
2. Keep `expected_any_of` permissive enough that *correct* alternative answers pass. The dataset's job is to catch regressions, not to enforce one canonical answer.
3. Run the eval against the previous best strategy and check the row scores correctly.

## Adding a strategy

1. Either reuse `FoundationModelsEngine` with different flags, or implement another `QueryEngine` conformance in `ShguideCore`.
2. Add a case to `Strategy` in `Sources/ShguideEval/RunCommand.swift`.
3. Run side-by-side with the current ship strategy and use `shguide-eval compare` to decide.
