# shguide

A macOS CLI for formulating and explaining shell commands using Apple's on-device Foundation Models.

```
$ shguide find large files in this subdirectory sorted by size
1. find . -type f -size +500M
   List files in the current directory tree larger than 500 megabytes.
2. find . -type f -size +100M -exec du -h {} + | sort -hr
   Find files larger than 100MB and print them human-readable, biggest first.

Select [1-2, q]: 1
✓ copied: find . -type f -size +500M
```

```
$ shguide --describe 'grep -r "ERROR" /var/log/nginx | wc -l'
This command searches for "ERROR" in nginx logs and counts matching lines.

1. grep -r "ERROR" /var/log/nginx
   Recursive grep for the string "ERROR" under /var/log/nginx.
2. | wc -l
   Pipe through wc -l to count the matching lines.
```

## Requirements

- macOS 26 Tahoe on Apple silicon
- Apple Intelligence enabled (System Settings → Apple Intelligence)
- Swift 6.2+ (Xcode 26)

## Build

```
swift build -c release
.build/release/shguide --help
```

## Usage

```
shguide <goal...>                  # Suggest commands
shguide --describe '<command>'     # Explain a command (quote pipelines)
shguide --history <goal>           # Also surface matches from your shell history
shguide --include-destructive ...  # Allow rm/dd/etc., shown in red
shguide --json <goal>              # Machine-readable output
shguide --config                   # Print resolved env and model availability
```

## Safety

Destructive commands (`rm`, `dd`, `mkfs`, …) are hidden by default. See [docs/SAFETY.md](docs/SAFETY.md).

## Evaluation

A Swift-based eval harness measures coverage, validity, safety, and latency on a versioned dataset. See [docs/EVAL.md](docs/EVAL.md).

```
shguide-eval run --dataset Datasets/eval_v1.jsonl --strategy generable-with-tools
```

## Future: model adapters

Once prompt+tools hit a ceiling, we can train a LoRA adapter on the eval dataset. See [docs/ADAPTERS.md](docs/ADAPTERS.md).
