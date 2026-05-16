import Foundation

/// base64_encode_file_078 / base64_decode_079
///
/// macOS `base64` requires `-i file` for file input; positional arguments are
/// not supported (exits 64 with a usage error). `prepareCommand` rewrites
/// positional-arg invocations to use `-i` so the sandbox can actually run them.
///
///   base64 input.txt          → base64 -i input.txt
///   base64 -d encoded.txt     → base64 -d -i encoded.txt
///   base64 -i input.txt       → unchanged (already correct)
///   base64 < input.txt        → unchanged (stdin redirect, works as-is)
///   openssl base64 …          → unchanged (different binary)
struct Base64Test: SandboxTestCase {
    let rowIDs = ["base64_encode_file_078", "base64_decode_079"]

    static let inputFile   = "input.txt"
    static let encodedFile = "encoded.txt"
    // base64("hello\n") = "aGVsbG8K"
    static let encodedContent = "aGVsbG8K\n"

    func setup(in dir: URL) throws {
        try SandboxFixtures.makeTextFile(name: Self.inputFile,   content: "hello\n",          in: dir)
        try SandboxFixtures.makeTextFile(name: Self.encodedFile, content: Self.encodedContent, in: dir)
    }

    // MARK: - macOS syntax normalisation

    /// Rewrites `base64 FILE` → `base64 -i FILE` and
    /// `base64 -d FILE` → `base64 -d -i FILE` for macOS compatibility.
    /// Leaves stdin-redirect forms (`base64 < FILE`) and other binaries alone.
    func prepareCommand(_ command: String) -> String {
        // Only touch invocations of the `base64` binary itself.
        guard command.hasPrefix("base64") || command.contains(" base64 ") else { return command }
        // Already uses -i or stdin redirect — no rewrite needed.
        guard !command.contains("-i"), !command.contains("< "), !command.contains("| base64") else {
            return command
        }

        var tokens = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // Find the last non-flag token — that's the file argument.
        if let fileIdx = tokens.indices.last(where: { !tokens[$0].hasPrefix("-") && tokens[$0] != "base64" }) {
            // Insert -i before the file argument.
            tokens.insert("-i", at: fileIdx)
        }
        return tokens.joined(separator: " ")
    }

    // MARK: - Scoring

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDecodeTask = command.contains("-d") || command.contains("--decode") || command.contains("decode")

        let (ok, note): (Bool, String)
        if isDecodeTask {
            (ok, note) = OutputValidator.check([
                (out.contains("hello"), "decoded output does not contain 'hello' — wrong flag or wrong input file"),
            ])
        } else {
            // Encode: output should be non-empty valid base64 characters.
            let validBase64 = #/^[A-Za-z0-9+/=\n]+$/#
            (ok, note) = OutputValidator.check([
                (!out.isEmpty,              "no output produced — file may not have been read"),
                (out.contains(validBase64), "output does not look like base64 — wrong command or missing filename"),
            ])
        }
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
