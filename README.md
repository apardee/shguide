# shguide

A macOS CLI that turns plain English into shell commands — and explains commands you don't recognize. It runs entirely on-device using Apple's Foundation Models (Apple Intelligence), so nothing leaves your machine.

```
$ shguide find large files in this subdirectory sorted by size
1. find . -type f -size +500M -ls | sort -k7 -rn
   Find files larger than 500 MB and list them sorted biggest first.
2. du -sh * | sort -rh | head -20
   Show disk usage of all items in the current directory, largest first.

Select [1-2, q]: 1
✓ copied: find . -type f -size +500M -ls | sort -k7 -rn
```

```
$ shguide --describe 'grep -r "ERROR" /var/log/nginx | wc -l'
Counts the number of lines containing "ERROR" in all nginx log files.

1. grep -r "ERROR" /var/log/nginx
   Recursively searches all files under /var/log/nginx for the string "ERROR".
2. | wc -l
   Pipes the results to wc -l to count the matching lines.
```

## Requirements

- macOS 26 Tahoe on Apple silicon
- Apple Intelligence enabled (System Settings → Apple Intelligence & Siri)
- Swift 6.2+ / Xcode 26

## Build

```sh
swift build -c release
.build/release/shguide --help
```

## Usage

```sh
shguide <goal>                     # Suggest 1–4 commands for a goal
shguide --describe '<command>'     # Explain what a command does (quote pipelines)
shguide --history <goal>           # Also surface matches from your shell history
shguide --include-destructive ...  # Show rm/dd/etc. too, flagged in red
shguide --json <goal>              # Machine-readable JSON output
shguide --config                   # Print env info and model availability
```

Select a suggestion with the number keys. It's copied to your clipboard — paste it into your terminal when you're ready to run it.

## Limitations (read this)

**The model gets things wrong a meaningful fraction of the time**, and understanding why helps you use it safely.

### It runs on an on-device model trained for general tasks

Apple's Foundation Models weren't specifically trained on shell commands. The model knows roughly what `find`, `grep`, and `tar` do, but it doesn't reliably know:

- **macOS-specific flag differences** — BSD tools (the ones that ship with macOS) often have different flags than their Linux equivalents. `sed -i 's/foo/bar/g' file` works on Linux but silently fails on macOS; you need `sed -i '' 's/foo/bar/g' file`. The model doesn't always know this.
- **Which tools are actually installed** — it sometimes suggests Linux-only commands like `sha256sum` that don't exist on macOS (the equivalent is `shasum -a 256`).
- **Precise flag meanings** — it sometimes uses `-mtime +1` when you need `-mtime -1` (the sign matters), or reaches for `wc -l` (line count) when you asked for word count (`wc -w`).

In sandbox evaluations against ~60 real tasks, the model produces a correct, runnable command roughly **40% of the time** without tools. With tools that look up binaries and man pages enabled, the rate doesn't improve much — the model calls the tools but doesn't always incorporate what they return.

### What this means in practice

- **Always read the command before running it.** shguide copies to clipboard so you can inspect before executing. Never paste something you don't understand into a terminal with elevated privileges.
- **It's better at common patterns than edge cases.** `find . -name "*.log"`, `grep -r "TODO" .`, `chmod +x script.sh` — high confidence. Complex pipelines, flag-heavy operations, or anything macOS-specific — treat suggestions as a starting point, not ground truth.
- **Destructive commands are hidden by default.** `rm`, `dd`, `mkfs`, and similar are filtered out unless you pass `--include-destructive`. When shown, they're flagged in red. See [docs/SAFETY.md](docs/SAFETY.md) for the full policy.
- **Describe mode is more reliable than suggest mode.** Explaining a known command (`--describe`) is an easier task for the model than generating one from scratch. If you have a command you don't recognize, describe mode is a good bet.

## Evaluation

The repo includes a sandbox-based eval harness that actually runs generated commands in an isolated environment and checks whether they produce correct output. Results above come from that harness.

```sh
# Run the model against a dataset and score the results
shguide-eval run --dataset Datasets/eval_v2.jsonl --output out/run.jsonl
shguide-eval sandbox-score --input out/run.jsonl --report out/report.json
```

See [docs/EVAL.md](docs/EVAL.md) for details on how the eval works.

