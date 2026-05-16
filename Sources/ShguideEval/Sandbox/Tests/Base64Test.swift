import Foundation

/// base64_encode_file_078 / base64_decode_079
///
/// Encode fixture: a file containing "hello". A correct `base64 input.txt`
/// or `base64 < input.txt` must produce output that is valid base64 and
/// decodes back to "hello".
///
/// Decode fixture: a file containing the base64 encoding of "hello\n".
/// A correct `base64 -d encoded.txt` or `base64 --decode` must produce
/// "hello" in stdout.
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
