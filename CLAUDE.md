# shguide — codebase context

On-device shell command assistant for macOS. Users type a goal in plain English; the app generates 1–4 shell commands using Apple's Foundation Models (Apple Intelligence), displays them in an interactive carousel, and places the selected command on the shell prompt (via shell integration) or the clipboard. A `--describe` mode takes a command and explains it.

Runs entirely on-device. Requires macOS 26 Tahoe, Apple Intelligence enabled, and Apple silicon.

## Project layout

```
Sources/
  shguide/          CLI entrypoint (ShguideCommand.swift)
  ShguideCore/      Shared library — engine protocol, prompts, tools, validators, render
  ShguideEval/      Eval harness CLI (shguide-eval)
Datasets/           JSONL eval datasets (eval_v2.jsonl is the active one)
docs/               EVAL.md, BENCHMARK_HISTORY.md, SAFETY.md
```

## ShguideCore architecture

**`QueryEngine` protocol** (`QueryEngine.swift`) — the single seam between the app and the model. Two methods:
- `forward(goal:context:)` → `[AnnotatedSuggestion]`
- `describe(command:context:)` → `ForwardExplanation`

**`InvocationContext`** carries per-request environment: shell name, macOS version, binaries on PATH, shell history matches, and whether destructive suggestions are allowed.

**`FoundationModelsEngine`** — the real engine. Uses `LanguageModelSession` from the `FoundationModels` framework with `@Generable` structured output types (`SuggestionList`, `Explanation` in `Schema.swift`). Temperature defaults to 0.2.

**`MockEngine`** — fast hardcoded fallback used in tests and CI where Apple Intelligence isn't available.

**Prompts** (`Prompts.swift`) — single unified prompt; no variants. The system prompt tells the model to use BSD coreutils, call tools to verify binaries and flags, produce complete runnable commands, and use `.` for the current directory. Do not add prompt variants or A/B flags here — that experiment was run and removed.

**Tools** (`Tools/`) — three tools the model can call during generation:
- `CheckCommandTool` — checks if a binary is on PATH
- `ManPageTool` — reads the NAME and SYNOPSIS sections of a man page
- `HistoryLookupTool` — searches the user's shell history by keyword

Tools are enabled in the live CLI (`foundation-models+tools`). In eval they degrade quality — the model calls them correctly but ignores results, while the extra context causes more decode failures. See BENCHMARK_HISTORY.md for details.

**Safety** (`Environment/DestructivePolicy.swift`) — two-layer check: dangerous binary names + dangerous substring patterns. Applied after generation; destructive suggestions are dropped unless `--include-destructive` is set.

**Validation** (`Validation/CommandValidator.swift`) — `looksRunnable` checks that every leading binary in a pipeline is on PATH or is a shell builtin. Applied post-generation to filter invalid suggestions.

**Render** (`Render/`) — terminal output:
- `ANSI.swift` — color/bold escape codes with a no-op fallback for non-TTY output.
- `Spinner.swift` — `withSpinner(label:enabled:_:)` animates a braille spinner on stderr while awaiting the model. Visible in both direct and `$(...)` invocations.
- `Carousel.swift` — interactive single-suggestion browser. Opens `/dev/tty` directly so it works inside `$(...)` command substitution (stdout is a pipe, but the terminal UI still appears). Raw-mode key handling: ← → cycle, Enter select, q/Escape dismiss. Restores terminal state and cursor visibility on all exit paths including SIGINT.
- `Menu.swift` — renders the full numbered list; used for non-TTY/piped output and `--describe`.

## Eval harness (ShguideEval)

Two subcommands:

**`shguide-eval run`** — calls the engine against dataset rows, writes raw JSONL (one line per row, all seeds bundled). Key options: `--model`, `--seeds`, `--only-ids`, `--limit`.

**`shguide-eval sandbox-score`** — reads raw JSONL, finds matching `SandboxTestCase` for each row, runs the command inside a Seatbelt sandbox, scores the result. Emits a JSON report with per-row `executable` and `correct` rates.

### Sandbox architecture

Each `SandboxTestCase` (`Sandbox/SandboxTestCase.swift`) implements:
- `rowIDs` — which eval rows this test covers
- `setup(in:)` — creates fixture files/dirs in a temp dir
- `prepareCommand(_:)` — optionally rewrites the command (e.g. redirect absolute paths to sandbox-relative ones, swap network targets to loopback)
- `score(command:result:in:)` — validates output or filesystem state

Commands run via `CommandRunner` (`Sandbox/CommandRunner.swift`) using the Swift `Subprocess` package (not `Foundation.Process` — `Process` had a pipe write-end lifetime bug causing zip/tar to hang). The Seatbelt profile uses `(allow default)` + `(deny file-write* subpath "/")` + `(allow file-write* subpath sandboxDir)` + `(deny network*)`. The sandbox dir path is canonicalised with `realpath` before embedding in the profile to handle the `/var` → `/private/var` symlink.

Test cases and the registry are in `Sandbox/Tests/` and `Sandbox/SandboxRegistry.swift`.

## Shell integration

`--shell-init <shell>` prints a shell function definition (named `shguide`) that wraps the binary. Users add `eval "$(shguide --shell-init zsh)"` to their `.zshrc`.

The key mechanism: the wrapper calls the binary via `$(...)` command substitution. During that call, stdout is a pipe (captured by the shell), but stderr and `/dev/tty` still reach the terminal — so the spinner (stderr) and carousel (`/dev/tty`) are fully visible. After selection, `print(picked.command)` writes to stdout, which the wrapper captures into `$cmd`. The wrapper then injects it into the shell's readline buffer:

- **zsh**: `print -z -- "$cmd"` — places the command in the ZLE buffer; appears on the prompt ready to edit/run.
- **bash**: `history -s -- "$cmd"` — no readline-inject API exists for regular bash functions; ↑ recall is the best available.
- **fish**: `commandline -- "$cmd"` — sets the interactive input buffer directly.

The binary path is resolved with `realpath` at `--shell-init` time and hardcoded into the function body, so the wrapper works regardless of whether `shguide` is on PATH. The function shadows the binary name; callers can bypass with `command shguide ...` or `\shguide ...`.

Clipboard copy still runs after selection as a fallback for sessions without the wrapper.

## Key design decisions worth knowing

- **No `Foundation.Process` in the sandbox runner** — replaced with Swift `Subprocess` package to fix pipe write-end lifetime issues that caused timeouts on zip/unzip/tar commands.
- **`(allow default)` Seatbelt profile** — deny-default crashes libc startup (SIGABRT). Allow-default + selective deny achieves the same security goals without the crash.
- **`realpath` on sandbox dir** — required because macOS symlinks `/var` → `/private/var`; Seatbelt profile `subpath` rules must match the kernel-resolved path.
- **Tools are wired but disabled in eval** — the Foundation Models engine calls tools correctly, but tool results don't influence the structured output generation. Enable with `--model foundation-models+tools` for the live CLI; avoid in eval.
- **No prompt variants** — eight variants were built and evaluated. The gains were marginal and the complexity wasn't worth it. There's now one prompt.
- **Eval scores ~40% correct for the on-device model** — placeholder arguments, wrong tool selection, and macOS/BSD flag differences are the primary failure modes. See BENCHMARK_HISTORY.md.

## Running things

```sh
# Build
swift build

# Run the CLI
.build/debug/shguide find large files in this directory

# Set up shell integration for the current session (zsh)
eval "$(.build/debug/shguide --shell-init zsh)"
shguide find large files in this directory   # now lands on the prompt

# Quick eval (mock engine, first 10 rows)
.build/debug/shguide-eval run \
  --dataset Datasets/eval_v2.jsonl \
  --model mock \
  --output .output/quick.jsonl \
  --limit 10
.build/debug/shguide-eval sandbox-score \
  --input .output/quick.jsonl

# Full eval (real model, 2 seeds)
.build/debug/shguide-eval run \
  --dataset Datasets/eval_v2.jsonl \
  --model foundation-models \
  --output .output/run.jsonl \
  --seeds 2
.build/debug/shguide-eval sandbox-score \
  --input .output/run.jsonl \
  --report .output/report.json \
  --verbose
```

## What not to do

- Don't add prompt variants or `--prompt-variant` flags — that experiment is done.
- Don't use `Foundation.Process` with `Pipe()` in the sandbox runner — the pipe write-end isn't closed before `readDataToEndOfFile()`, causing hangs. Use `Subprocess`.
- Don't use `(deny default)` in the Seatbelt profile — it crashes libc.
- Don't add `expected_any_of` or `canonical_command` fields to eval rows — the old static scoring is gone. Correctness is determined by running commands in the sandbox.
- Don't execute the selected command from within shguide — it would run in a subshell, so `cd`, `export`, aliases, and shell history wouldn't affect the parent shell. The shell integration approach (print to stdout, inject via `print -z`) is the right mechanism.
