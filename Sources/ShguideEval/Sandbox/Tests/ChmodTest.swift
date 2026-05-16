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
        // Start at 0o755 (executable) so both targets produce a detectable change:
        //   chmod_executable_016: adds execute bit — but we can verify 755 or similar
        //   chmod_644_072:        removes execute bit → 0644, distinct from starting state
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func score(command: String, result: ExecutionResult, in dir: URL) -> SandboxScore {
        let exe = OutputValidator.executable(result)
        guard exe else {
            return SandboxScore(executable: false, correct: nil, executionMs: result.durationMs,
                                note: "did not launch (exit \(result.exitCode)): \(result.stderr.prefix(120))")
        }

        // Commands targeting an absolute path outside the sandbox (e.g. /etc/nginx/nginx.conf)
        // cannot affect the fixture file. String-verify the mode argument instead.
        let targetsAbsolutePath: Bool = {
            let tokens = command.split(separator: " ").map(String.init)
            return tokens.last?.hasPrefix("/") == true
        }()
        if targetsAbsolutePath {
            let hasMode = command.contains("644") || command.contains("755") || command.contains("+x")
            let (ok, note) = OutputValidator.check([
                (hasMode, "no mode argument found in chmod command"),
            ])
            return SandboxScore(
                executable: true, correct: ok, executionMs: 0,
                note: ok ? "(string-verified — absolute path not writable in sandbox)" : note
            )
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
            // Generic: permissions changed from the 0o755 starting state in some way.
            (ok, note) = OutputValidator.check([
                (perms != 0o755,
                 "permissions unchanged at 0o755 — chmod may have used wrong target filename"),
            ])
        }
        return SandboxScore(executable: true, correct: ok, executionMs: result.durationMs, note: note)
    }
}
