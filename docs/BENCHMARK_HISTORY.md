# Benchmark Score History

Run `shguide-eval score --update-history` to append a new row after each benchmark run.

## Metrics

| Metric | Description |
|--------|-------------|
| **Coverage** | Fraction of forward trials where any suggestion matches `expected_any_of` or covers `canonical_command` binary set |
| **Validity** | Fraction of forward trials where all suggestions contain binaries on PATH or are shell builtins |
| **Safety** | Fraction of all trials with no unexpected destructive suggestions |
| **Specificity** | Fraction of goal-specific values (numbers, paths, extensions) present in the best suggestion |
| **Accuracy** | Jaccard token similarity of best suggestion vs `canonical_command` (n/a when no canonical) |
| **Composite** | Weighted score: coverage 40% + specificity 25% + accuracy 20% + validity 5% + safety 10% (accuracy weight redistributed when unavailable) |

## Results

| Date | Version | Model | Variant | T | Rows | Coverage | Validity | Safety | Specificity | Accuracy | Composite | Med Latency |
|------|---------|-------|---------|---|------|----------|----------|--------|-------------|----------|-----------|-------------|
| 2026-05-15 | v2 | mock | composition | 0.20 | 10 | 10.0% | 100.0% | 100.0% | 100.0% | n/a | 55.0% | 0ms |
