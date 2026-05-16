import Foundation

/// json_extract_023
///
/// Goal: "extract the value of the name field from a json file"
///
/// Canonical commands (all are pipe-or-tool patterns):
///   jq -r '.name' data.json
///   python3 -c "import json,sys; print(json.load(open('data.json'))['name'])"
///   cat data.json | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])"
///
/// Fixture: a JSON file with a known "name" value.
/// Scoring checks stdout contains that value regardless of which tool
/// the model chose. If jq is not installed the command exits non-zero;
/// python3 is always available and is accepted as equally correct.
struct JsonExtractTest: SandboxTestCase {
    let rowIDs = ["json_extract_023"]

    static let fileName    = "data.json"
    static let nameValue   = "alice"
    static let fileContent = #"{"name": "alice", "age": 30, "active": true}"#

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: Self.fileName, content: Self.fileContent + "\n", in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        // jq exits 5 when not installed; python3 exits 0. Both are valid tools.
        // Treat "not installed" (exit 127 or jq-specific exit 5) as an executable
        // failure rather than a model error.
        let notInstalled = result.exitCode == 127
            || (result.exitCode == 5 && result.stderr.contains("jq"))
        if notInstalled {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "tool not installed (exit \(result.exitCode)) — jq may be unavailable in sandbox PATH")
        }

        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let (ok, note) = OutputValidator.check([
            (result.stdout.contains(Self.nameValue),
             "'\(Self.nameValue)' not in output — wrong field extracted, wrong filename, or syntax error"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
