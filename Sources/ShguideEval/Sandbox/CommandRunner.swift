import Foundation
import Darwin
import System
import Subprocess
import ShguideCore

/// Runs a shell command inside a Seatbelt (sandbox-exec) sandbox.
///
/// Uses the Swift Subprocess package instead of Foundation.Process to avoid
/// the inherited-pipe-write-end problem: Foundation.Process retains its copy
/// of the stdout/stderr pipe write-ends after the child starts, which causes
/// `readDataToEndOfFile()` to block forever on commands that don't produce
/// output (zip, tar, unzip). Subprocess manages pipe lifetimes automatically.
///
/// Defense layers applied in order:
/// 1. `DestructivePolicy` — rejects known-destructive commands before launch.
/// 2. Seatbelt profile — file writes confined to `dir`; network access
///    controlled by `networkPolicy`.
/// 3. Task-cancellation timeout — subprocess receives SIGKILL after `timeout`.
enum CommandRunner {

    static let defaultTimeout: TimeInterval = 10.0

    // MARK: - Public API

    static func runAsync(
        _ command: String,
        in dir: URL,
        networkPolicy: SandboxNetworkPolicy = .none,
        timeout: TimeInterval = defaultTimeout
    ) async -> ExecutionResult {
        if DestructivePolicy.isDestructive(command) {
            return .blocked("destructive command blocked by policy")
        }

        let allowedIPs   = resolveNetworkPolicy(networkPolicy)
        let sandboxDirPath = canonicalPath(dir.path)
        let profile      = seatbeltProfile(sandboxDir: sandboxDirPath, allowedIPs: allowedIPs)

        let start = Date()

        do {
            let record = try await withProcessTimeout(seconds: timeout) {
                // `run` here is the free function from the Subprocess module.
                // `input: .none` closes stdin automatically — no /dev/null dance needed.
                try await run(
                    .path(FilePath("/usr/bin/sandbox-exec")),
                    arguments: ["-p", profile, "/bin/sh", "-c", command],
                    environment: .custom([
                        "PATH"  : "/usr/bin:/bin:/usr/sbin:/sbin",
                        "HOME"  : sandboxDirPath,
                        "TMPDIR": sandboxDirPath,
                        "TERM"  : "dumb",
                        "LANG"  : "en_US.UTF-8",
                    ]),
                    workingDirectory: FilePath(sandboxDirPath),
                    input: .none,
                    output: .string(limit: 4 * 1024 * 1024),
                    error:  .string(limit: 64 * 1024)
                )
            }

            let elapsed  = Int(Date().timeIntervalSince(start) * 1000)
            let stdout   = record.standardOutput ?? ""
            let stderr   = record.standardError  ?? ""

            // Map TerminationStatus to the Int32 exit code our callers expect.
            let exitCode: Int32
            switch record.terminationStatus {
            case .exited(let code):  exitCode = code
            case .signaled:          exitCode = -1  // process was killed by a signal
            }

            return ExecutionResult(
                stdout: stdout, stderr: stderr,
                exitCode: exitCode, timedOut: false, durationMs: elapsed
            )
        } catch is TimedOutError {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            // withProcessTimeout cancelled the task — Subprocess sends SIGKILL.
            return ExecutionResult(stdout: "", stderr: "", exitCode: -1, timedOut: true, durationMs: elapsed)
        } catch {
            return ExecutionResult(stdout: "", stderr: error.localizedDescription, exitCode: -1, timedOut: false, durationMs: 0)
        }
    }

    // MARK: - Timeout

    private struct TimedOutError: Error {}

    /// Runs `body` and cancels it (triggering SIGKILL on any live subprocess)
    /// if it does not complete within `seconds`.
    private static func withProcessTimeout<T: Sendable>(
        seconds: TimeInterval,
        body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimedOutError()
            }
            defer { group.cancelAll() }
            // Returns the result of whichever task finishes first.
            // If the timeout fires first, TimedOutError propagates.
            return try await group.next()!
        }
    }

    // MARK: - Path canonicalization

    /// Returns the real (symlink-resolved) absolute path via POSIX realpath(3).
    /// On macOS /var → /private/var, so Seatbelt profile subpath rules must
    /// use the canonical form to match what the kernel sees.
    private static func canonicalPath(_ path: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buf) != nil else { return path }
        return buf.withUnsafeBytes {
            String(validating: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
        } ?? path
    }

    // MARK: - Network policy resolution

    private static func resolveNetworkPolicy(_ policy: SandboxNetworkPolicy) -> [String] {
        switch policy {
        case .none:                   return []
        case .outboundToHosts(let h): return h.flatMap { resolveHost($0) }
        }
    }

    private static func resolveHost(_ hostname: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family   = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>? = nil
        guard getaddrinfo(hostname, nil, &hints, &res) == 0, let head = res else { return [] }
        defer { freeaddrinfo(head) }

        var ips: [String] = []
        var cur: UnsafeMutablePointer<addrinfo>? = head
        while let node = cur {
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            switch node.pointee.ai_family {
            case AF_INET:
                var sin = node.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET6_ADDRSTRLEN))
                ips.append(buf.withUnsafeBytes { String(validating: $0.prefix(while: { $0 != 0 }), as: UTF8.self) } ?? "")
            case AF_INET6:
                var sin6 = node.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                inet_ntop(AF_INET6, &sin6.sin6_addr, &buf, socklen_t(INET6_ADDRSTRLEN))
                ips.append(buf.withUnsafeBytes { String(validating: $0.prefix(while: { $0 != 0 }), as: UTF8.self) } ?? "")
            default:
                break
            }
            cur = node.pointee.ai_next
        }
        return ips.filter { !$0.isEmpty }
    }

    // MARK: - Seatbelt profile

    private static func seatbeltProfile(sandboxDir: String, allowedIPs: [String]) -> String {
        let networkStanza: String
        if allowedIPs.isEmpty {
            networkStanza = "(deny network*)"
        } else {
            var lines: [String] = [#"(allow network-outbound (remote udp "*:53"))"#]
            for ip in allowedIPs {
                lines.append(#"(allow network-outbound (remote ip "\#(ip)"))"#)
            }
            lines.append("(deny network-inbound)")
            networkStanza = lines.joined(separator: "\n        ")
        }

        return """
        (version 1)
        (allow default)

        ; Confine all file writes to the isolated temp directory.
        (deny file-write* (subpath "/"))
        (allow file-write* (subpath "\(sandboxDir)"))

        ; Always allow writes to the standard output/error devices.
        (allow file-write-data
            (literal "/dev/null")
            (literal "/dev/stdout")
            (literal "/dev/stderr"))

        ; Network — conditionally open based on test requirements.
        \(networkStanza)
        """
    }
}

// MARK: - ExecutionResult helpers

extension ExecutionResult {
    static func blocked(_ reason: String) -> ExecutionResult {
        ExecutionResult(stdout: "", stderr: reason, exitCode: -1, timedOut: false, durationMs: 0)
    }

    /// True if the command started and ran without a launcher-level error or
    /// timeout. Allows exit codes like 1 (diff with differences, grep with no
    /// matches) — individual tests interpret those.
    var launched: Bool {
        !timedOut && exitCode != -1 && exitCode != 127
    }
}
