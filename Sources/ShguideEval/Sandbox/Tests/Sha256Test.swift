import Foundation

/// sha256_file_077
///
/// Goal: "compute a SHA-256 checksum of a file"
///
/// Fixture: a file with known content. A correct command (shasum -a 256,
/// sha256sum, openssl dgst -sha256) must produce a 64-character lowercase
/// hex string in stdout.
struct Sha256Test: SandboxTestCase {
    let rowIDs = ["sha256_file_077"]

    static let fileName = "data.txt"
    static let content  = "hello sandbox\n"

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: Self.fileName, content: Self.content, in: dir)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        // A SHA-256 digest is exactly 64 lowercase hex characters.
        let hexRun = #/\b[0-9a-f]{64}\b/#
        let hasDigest = result.stdout.contains(hexRun)
        let (ok, note) = OutputValidator.check([
            (hasDigest, "no 64-char hex digest found in output — wrong tool, missing flag, or wrong filename"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
