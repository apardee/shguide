import Foundation

public enum ShellHistory {
    public static func defaultPath(env: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        if let hist = env["HISTFILE"], !hist.isEmpty {
            return URL(fileURLWithPath: (hist as NSString).expandingTildeInPath)
        }
        let home = env["HOME"].map(URL.init(fileURLWithPath:))
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let shell = (env["SHELL"] ?? "").lowercased()
        if shell.hasSuffix("zsh") {
            return home.appendingPathComponent(".zsh_history")
        }
        if shell.hasSuffix("bash") {
            return home.appendingPathComponent(".bash_history")
        }
        // try zsh first as macOS default
        let zsh = home.appendingPathComponent(".zsh_history")
        if FileManager.default.fileExists(atPath: zsh.path) { return zsh }
        let bash = home.appendingPathComponent(".bash_history")
        if FileManager.default.fileExists(atPath: bash.path) { return bash }
        return nil
    }

    public static func load(from url: URL? = nil) -> [String] {
        let url = url ?? defaultPath()
        guard let url else { return [] }
        // History files can contain non-UTF8 bytes (legacy encodings); read as Data and best-effort decode.
        guard let data = try? Data(contentsOf: url) else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        var commands: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            let parsed = parseLine(line)
            if let parsed, !isLikelySecret(parsed) {
                commands.append(parsed)
            }
        }
        return commands
    }

    /// Parse a single history line. zsh extended history is `: <ts>:<dur>;<cmd>`; bash is the plain command.
    static func parseLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix(":") {
            // zsh extended: `: 1700000000:0;ls -la`
            if let semi = trimmed.firstIndex(of: ";") {
                let cmd = String(trimmed[trimmed.index(after: semi)...])
                let stripped = cmd.trimmingCharacters(in: .whitespaces)
                return stripped.isEmpty ? nil : stripped
            }
            return nil
        }
        return trimmed
    }

    static func isLikelySecret(_ command: String) -> Bool {
        let lowered = command.lowercased()
        if lowered.contains("begin ") && lowered.contains("private key") { return true }
        // export FOO=bar is fine, but export TOKEN=... or AWS_SECRET_ACCESS_KEY=... is not.
        let secretKeywords = ["password", "secret", "token", "api_key", "apikey", "access_key", "private_key"]
        if lowered.hasPrefix("export ") || lowered.contains("=") {
            for kw in secretKeywords where lowered.contains(kw) { return true }
        }
        return false
    }

    /// Top-N matches against an `all` list, scored by simple keyword presence + frequency.
    public static func match(keywords: [String], in all: [String], limit: Int) -> [HistoryEntry] {
        let lowKws = keywords.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !lowKws.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for cmd in all {
            let lc = cmd.lowercased()
            let matches = lowKws.reduce(0) { $0 + (lc.contains($1) ? 1 : 0) }
            if matches > 0 {
                counts[cmd, default: 0] += matches
            }
        }
        return counts
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(limit)
            .map { HistoryEntry(command: $0.key, occurrences: $0.value) }
    }
}
