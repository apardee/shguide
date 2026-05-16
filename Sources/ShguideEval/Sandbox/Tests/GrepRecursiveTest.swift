import Foundation

/// grep_recursive_003
///
/// Goal: "search recursively for the word TODO in source files"
///
/// Fixture: a small source tree where two files contain "TODO" and one is clean.
/// A correct command must report the files with TODO and exclude the clean file.
struct GrepRecursiveTest: SandboxTestCase {
    let rowIDs = ["grep_recursive_003", "search_ambig_107"]

    func setup(in dir: URL) throws {
        let src = try SandboxFixtures.makeDirectory(name: "src", in: dir)
        let lib = try SandboxFixtures.makeDirectory(name: "src/lib", in: dir)
        _ = lib
        try SandboxFixtures.makeTextFile(
            name: "main.swift",
            content: "// TODO: fix this bug\nlet x = 1\n",
            in: src
        )
        let srcLib = src.appending(path: "lib")
        try SandboxFixtures.makeTextFile(
            name: "utils.swift",
            content: "func helper() {\n    // TODO: implement me\n}\n",
            in: srcLib
        )
        try SandboxFixtures.makeTextFile(
            name: "clean.swift",
            content: "let y = 2 // no todos here\n",
            in: src
        )
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            // grep exits 1 when no matches — that is still "launched"
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }
        let out = result.stdout
        let (ok, note) = OutputValidator.check([
            (out.contains("main.swift") || out.contains("utils.swift"),
             "neither main.swift nor utils.swift appeared in output"),
            (!out.contains("clean.swift"),
             "clean.swift (no TODO) appeared in output"),
        ])
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
