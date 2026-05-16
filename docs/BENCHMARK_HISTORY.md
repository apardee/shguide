# Benchmark History

## Methodology

Commands are evaluated by actually running them inside a Seatbelt sandbox and checking the result — not by static pattern matching. Each test case sets up a fixture environment (files, directories, archives), executes the model-generated command with a 10-second timeout, then validates the output or filesystem state against known-good expectations.

### Metrics

| Metric | Description |
|---|---|
| **Executable rate** | Fraction of trials where the command launched and ran without a timeout or launch error. Exit codes like 1 (e.g. `diff` finding differences, `grep` with no matches) are treated as normal. |
| **Correct rate** | Fraction of trials where the command's output or side effects matched the test expectation — correct files created, correct text in stdout, correct count, etc. |

### Dataset

`Datasets/eval_v2.jsonl` — 125 rows, 62 of which have sandbox test cases covering file discovery, text search and processing, filesystem operations, archives, checksums, encoding, disk usage, process inspection, networking (string-verified), and compound commands.

Each row is run with 2 seeds (independent trials). Results below aggregate across both seeds.

### Running the eval

```sh
shguide-eval run \
  --dataset Datasets/eval_v2.jsonl \
  --model <model> \
  --output .output/run.jsonl \
  --seeds 2

shguide-eval sandbox-score \
  --input .output/run.jsonl \
  --report .output/report.json
```

---

## Results

| Date | Model | Prompt | Executable | Correct | Notes |
|---|---|---|---|---|---|
| 2026-05-16 | claude-sonnet-4-6 | v2 | 100% | 98.4% | Acting as query engine; 2 genuine failures (wrong tool/syntax) |
| 2026-05-16 | foundation-models | v2 | 92.7% | 40.0% | On-device Apple Intelligence; tools called but results not incorporated |

### Claude Sonnet 4.6 — 98.4% correct

Used as a reference ceiling: Sonnet 4.6 was prompted with each goal and its answers were scored through the same sandbox. 98.4% is essentially the ceiling for the current test suite — the 2 failures are a genuinely wrong command (`cut` with a tab delimiter on space-delimited data) and a broken sed arithmetic expansion, both correct FAILs.

### Foundation Models — 40% correct

Apple's on-device model, running locally. The main failure patterns:

- **`<placeholder>` left in commands** — `mkdir -p <directory>`, `cp -r <source> <destination>`, `tail -n 50 <file>` — the model uses template-style placeholders even when the command would work with a concrete example or `.`
- **Wrong tool** — `wc -l` for word count, `find -name 'TODO'` for searching file *content*, `df -h` for per-directory disk usage, `cat f | cat f` for diff
- **Missing filename** — `grep -i error` and `sort | uniq -c` with no file argument, reading from empty stdin
- **macOS flag differences** — `sha256sum` (Linux only; macOS uses `shasum -a 256`), `sed -i` without the required `''` empty-string argument on BSD sed, `tar -xvf` (extracts) instead of `tar -tf` (lists)
- **Inverted time signs** — `find . -mtime +1` finds files *older* than 1 day; `-mtime -1` is *newer*

Tool use (checkCommand, manPage) is disabled in the default configuration. The model does call the tools correctly but does not incorporate the results — `checkCommand("sha256sum")` returns "not found" and the model suggests it anyway. Enabling tools also caused a 14% increase in decode errors and 3× latency with no accuracy gain.
