# shguide eval harness

The eval harness is a benchmark that measures how well the on-device model answers shell command prompts by actually running the generated commands in a sandbox and checking whether they work.

## Dataset

`Datasets/eval_v2.jsonl` — 125 rows, one JSON object per line.

**Forward row** (natural language → command):
```json
{"id": "find_large_files_001", "mode": "forward", "goal": "find large files in this subdirectory sorted by size"}
```

**Describe row** (command → explanation):
```json
{"id": "describe_grep_pipeline_026", "mode": "describe", "command": "grep -r \"ERROR\" /var/log/nginx/ | cut -d ' ' -f 5 | sort | uniq -c"}
```

That's the whole format. No expected-output patterns — correctness is determined by the sandbox test cases.

## Metrics

| Metric | Definition |
|---|---|
| **Executable rate** | Fraction of trials where the command launched and ran without a timeout or launch error. |
| **Correct rate** | Fraction of trials where the command's output or side effects matched the test expectation. |

See [BENCHMARK_HISTORY.md](BENCHMARK_HISTORY.md) for current results.

## Running

```sh
# Run the model against the dataset
shguide-eval run \
  --dataset Datasets/eval_v2.jsonl \
  --model foundation-models \
  --output .output/run.jsonl \
  --seeds 2

# Score the results through the sandbox
shguide-eval sandbox-score \
  --input .output/run.jsonl \
  --report .output/report.json \
  --verbose
```

**`--model` options:** `foundation-models`, `foundation-models+tools`, `mock`

**`--seeds N`** runs each row N times independently. 2 is enough to spot instability; 1 is fine for a quick pass.

**`--only-ids a,b,c`** runs a subset of rows — useful when iterating on a specific failure.

**`--limit N`** runs the first N rows only.

## How the sandbox works

Each forward row that has a registered test case gets its own isolated temp directory. The test case:

1. **Sets up fixtures** — creates the files, directories, or archives the command is expected to operate on.
2. **Rewrites the command if needed** — e.g. `prepareCommand` redirects `ping` to loopback, or rewrites `/tmp/notes.txt` to the sandbox-relative fixture path.
3. **Runs the command** inside a Seatbelt sandbox (`sandbox-exec`) that confines file writes to the temp directory and blocks network access (except where the test explicitly allows it).
4. **Scores the result** — checks stdout content, filesystem state, or exit code against known expectations.

The sandbox allows reads from anywhere (so `find /var/log` works) but blocks writes outside the temp dir. Commands time out after 10 seconds.

## Adding a dataset row

1. Add a JSONL line to `Datasets/eval_v2.jsonl` with a unique `id`, a `mode`, and either `goal` (forward) or `command` (describe).
2. Optionally add a sandbox test case (see below) so the row gets an execution-based score rather than showing up as `tested: false`.
3. Run `shguide-eval run --only-ids <your-id>` and then `sandbox-score` to verify it behaves as expected.

## Adding a sandbox test case

Test cases live in `Sources/ShguideEval/Sandbox/Tests/`. Each is a Swift struct conforming to `SandboxTestCase`:

```swift
struct MyNewTest: SandboxTestCase {
    let rowIDs = ["my_row_001"]

    func setup(in dir: URL) throws {
        // create fixture files the command should operate on
        try SandboxFixtures.makeTextFile(name: "data.txt", content: "hello\n", in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch: \(result.stderr.prefix(120))")
        }
        let (ok, note) = OutputValidator.check([
            (result.stdout.contains("hello"), "expected 'hello' in output"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
```

Register it in `SandboxRegistry.swift` by adding an instance to the `all` array.

For commands that require network (e.g. ping), set `networkPolicy` to `.outboundToHosts(["hostname"])` — the sandbox resolves hostnames to IPs before applying the Seatbelt profile. For commands that can't run in a sandbox at all (e.g. ICMP requires root), implement `prepareCommand` to rewrite the command to something testable, or score by string inspection only and note the limitation.
