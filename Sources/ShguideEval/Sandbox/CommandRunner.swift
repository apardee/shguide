import Foundation
import Darwin
import ShguideCore

/// Runs a shell command inside a Seatbelt (sandbox-exec) sandbox.
///
/// Defense layers, applied in order:
/// 1. `DestructivePolicy` — rejects known-destructive patterns before launch.
/// 2. Seatbelt profile — file writes confined to `dir`; network access
///    controlled by `networkPolicy`; standard system paths are readable.
/// 3. Hard timeout — terminates any runaway process.
enum CommandRunner {

    static let defaultTimeout: TimeInterval = 10.0

    // MARK: - Public API

    /// Blocking. Use `runAsync` from async contexts.
    static func run(
        _ command: String,
        in dir: URL,
        networkPolicy: SandboxNetworkPolicy = .none,
        timeout: TimeInterval = defaultTimeout
    ) -> ExecutionResult {
        if DestructivePolicy.isDestructive(command) {
            return .blocked("destructive command blocked by policy")
        }

        // Resolve hostnames to IPs *before* entering the sandbox so that
        // the profile can allowlist specific addresses.
        let allowedIPs = resolveNetworkPolicy(networkPolicy)

        // Resolve symlinks on the sandbox dir so the Seatbelt profile path
        // matches what the kernel sees. On macOS /var → /private/var, so a
        // path like /var/folders/... would not match the profile without this.
        let sandboxDirPath = canonicalPath(dir.path)

        let profile = seatbeltProfile(sandboxDir: sandboxDirPath, allowedIPs: allowedIPs)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", profile, "/bin/sh", "-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: sandboxDirPath)
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": sandboxDirPath,   // remap HOME so ~/.* mutations go inside the sandbox
            "TMPDIR": sandboxDirPath, // redirect temp file creation
            "TERM": "dumb",
            "LANG": "en_US.UTF-8",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let start = Date()

        do {
            try process.run()
        } catch {
            return ExecutionResult(
                stdout: "", stderr: error.localizedDescription,
                exitCode: -1, timedOut: false, durationMs: 0
            )
        }

        let timedOut = !waitWithTimeout(process: process, seconds: timeout)
        if timedOut { process.terminate() }

        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        ) ?? ""

        return ExecutionResult(
            stdout: stdout, stderr: stderr,
            exitCode: timedOut ? -1 : process.terminationStatus,
            timedOut: timedOut, durationMs: elapsed
        )
    }

    /// Async wrapper — offloads the blocking call to a dedicated thread.
    static func runAsync(
        _ command: String,
        in dir: URL,
        networkPolicy: SandboxNetworkPolicy = .none,
        timeout: TimeInterval = defaultTimeout
    ) async -> ExecutionResult {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(
                    returning: run(command, in: dir, networkPolicy: networkPolicy, timeout: timeout)
                )
            }
            thread.start()
        }
    }

    // MARK: - Path canonicalization

    /// Returns the real (symlink-resolved) absolute path via POSIX realpath(3).
    /// Falls back to the original path if realpath fails (e.g. path does not exist).
    private static func canonicalPath(_ path: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buf) != nil else { return path }
        return buf.withUnsafeBytes { String(validating: $0.prefix(while: { $0 != 0 }), as: UTF8.self) } ?? path
    }

    // MARK: - Network policy resolution

    /// Returns IP address strings for all hosts named in `policy`.
    /// Runs before sandboxing so normal DNS is available.
    private static func resolveNetworkPolicy(_ policy: SandboxNetworkPolicy) -> [String] {
        switch policy {
        case .none:
            return []
        case .outboundToHosts(let hosts):
            return hosts.flatMap { resolveHost($0) }
        }
    }

    /// Resolves a hostname to its IPv4/IPv6 addresses using getaddrinfo.
    private static func resolveHost(_ hostname: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
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
                ips.append(buf.withUnsafeBytes { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) })
            case AF_INET6:
                var sin6 = node.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                inet_ntop(AF_INET6, &sin6.sin6_addr, &buf, socklen_t(INET6_ADDRSTRLEN))
                ips.append(buf.withUnsafeBytes { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) })
            default:
                break
            }
            cur = node.pointee.ai_next
        }
        return ips
    }

    // MARK: - Seatbelt profile

    private static func seatbeltProfile(sandboxDir: String, allowedIPs: [String]) -> String {
        // Strategy: allow everything by default, then selectively deny.
        //
        // A deny-default profile causes SIGABRT during libc/dyld startup because
        // the minimal set of required Mach services and file paths is too large
        // to enumerate portably across macOS versions. The allow-default approach
        // achieves the security goals we actually care about:
        //
        //   • File writes are confined to sandboxDir — everything else is denied.
        //   • Network is blocked (or restricted to specific resolved IPs for tests
        //     that require connectivity).
        //   • Reads are unrestricted, which is acceptable for an eval tool: we are
        //     not trying to prevent data exfiltration, only filesystem mutation and
        //     network side-effects.

        let networkStanza: String
        if allowedIPs.isEmpty {
            networkStanza = "(deny network*)"
        } else {
            // Allow DNS (UDP 53) so the sandboxed process can resolve names.
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

    // MARK: - Timeout

    private static func waitWithTimeout(process: Process, seconds: TimeInterval) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            sem.signal()
        }
        return sem.wait(timeout: .now() + seconds) == .success
    }
}

// MARK: - ExecutionResult helpers

extension ExecutionResult {
    static func blocked(_ reason: String) -> ExecutionResult {
        ExecutionResult(stdout: "", stderr: reason, exitCode: -1, timedOut: false, durationMs: 0)
    }

    /// True if the command started and ran without a launcher-level error or
    /// timeout. Exit codes like 1 (diff with differences, grep with no matches)
    /// are treated as normal — the test's `score` function interprets them.
    var launched: Bool {
        !timedOut && exitCode != -1 && exitCode != 127
    }
}
