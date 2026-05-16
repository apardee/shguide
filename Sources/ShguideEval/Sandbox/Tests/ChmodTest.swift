import Foundation

/// chmod_executable_016 / chmod_644_072
///
/// Fixture: a shell script with permissions 0o644 (not executable).
/// chmod_executable_016: the model should add the execute bit (chmod +x, 755, etc.)
/// chmod_644_072: the model should set exactly 0644.
///
/// Scoring reads the file's POSIX permissions after the command runs.
struct ChmodTest: SandboxTestCase {
    let rowIDs = ["chmod_executable_016", "chmod_644_072", "chmod_specific_098"]

    static let fileName = "script.sh"

    func setup(in dir: URL) throws {
        let url = dir.appending(path: Self.fileName)
        try SandboxFixtures.makeTextFile(name: Self.fileName, content: "#!/bin/sh\necho hello\n", in: dir)
        // Start at 0o644 — not executable.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }

        let url = dir.appending(path: Self.fileName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let perms = attrs[.posixPermissions] as? Int else {
            return SandboxScore(executable: true, correct: false, executionMs: result.durationMs,
                                note: "could not read permissions of \(Self.fileName) after command ran")
        }

        let wantsExecutable = command.contains("+x") || command.contains("755")
            || command.contains("executable") || command.contains("chmod_executable")
        let wants644 = command.contains("644")

        let (ok, note): (Bool, String)
        if wantsExecutable {
            (ok, note) = OutputValidator.check([
                (perms & 0o111 != 0,
                 "execute bit not set after chmod — got \(String(format:"0o%o", perms))"),
            ])
        } else if wants644 {
            (ok, note) = OutputValidator.check([
                (perms == 0o644,
                 "expected 0o644 but got \(String(format:"0o%o", perms))"),
            ])
        } else {
            // Generic: permissions changed from 0o644 in some way.
            (ok, note) = OutputValidator.check([
                (perms != 0o644 || result.stdout.contains("644"),
                 "permissions unchanged at 0o644 — chmod may have used wrong target filename"),
            ])
        }
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
