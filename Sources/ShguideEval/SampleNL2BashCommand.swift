import ArgumentParser
import Foundation

struct SampleNL2BashCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sample-nl2bash",
        abstract: "Sample a held-out test set from nl2bash all.nl/all.cm into a shguide-eval JSONL."
    )

    @Option(name: .customLong("nl"), help: "Path to nl2bash all.nl.")
    var nlPath: String

    @Option(name: .customLong("cm"), help: "Path to nl2bash all.cm.")
    var cmPath: String

    @Option(name: .customLong("out"), help: "Output JSONL path.")
    var outPath: String

    @Option(name: .customLong("per-head"), help: "Cap rows per first-binary stratum before global sampling.")
    var perHead: Int = 15

    @Option(name: .customLong("total"), help: "Approximate total rows in the sample.")
    var total: Int = 150

    @Option(name: .customLong("max-cm-length"), help: "Drop rows whose canonical command exceeds this length.")
    var maxCmLength: Int = 80

    @Option(name: .customLong("min-cm-length"), help: "Drop rows whose canonical command is shorter than this.")
    var minCmLength: Int = 4

    @Option(name: .customLong("seed"), help: "Random seed for determinism.")
    var seed: UInt64 = 42

    func run() throws {
        let nl = try String(contentsOfFile: nlPath, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let cm = try String(contentsOfFile: cmPath, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard nl.count == cm.count else {
            throw ValidationError("nl and cm differ in line count: \(nl.count) vs \(cm.count)")
        }

        let placeholderVar = try NSRegularExpression(pattern: #"\$[A-Za-z_]"#)

        var byHead: [String: [PairRef]] = [:]
        var dropped: [String: Int] = [:]
        for (i, pair) in zip(nl, cm).enumerated() {
            let goal = pair.0.trimmingCharacters(in: .whitespaces)
            let canonical = pair.1.trimmingCharacters(in: .whitespaces)
            let reason = filterReason(goal: goal, canonical: canonical, placeholderVar: placeholderVar)
            if let reason {
                dropped[reason, default: 0] += 1
                continue
            }
            guard let head = CommandShape.binaries(in: canonical).first else {
                dropped["no_head", default: 0] += 1
                continue
            }
            byHead[head, default: []].append(PairRef(originalIndex: i, goal: goal, canonical: canonical, head: head))
        }

        var rng = SplitMix64(seed: seed)
        var pool: [PairRef] = []
        for head in byHead.keys.sorted() {
            var bucket = byHead[head]!
            bucket.shuffle(using: &rng)
            pool.append(contentsOf: bucket.prefix(perHead))
        }
        pool.shuffle(using: &rng)
        let chosen = Array(pool.prefix(total)).sorted { ($0.head, $0.originalIndex) < ($1.head, $1.originalIndex) }

        var counters: [String: Int] = [:]
        var lines: [String] = []
        for row in chosen {
            counters[row.head, default: 0] += 1
            let id = "nl2bash_\(row.head)_\(String(format: "%03d", counters[row.head]!))"
            let payload: [String: Any] = [
                "id": id,
                "mode": "forward",
                "goal": row.goal,
                "canonical_command": row.canonical,
                "destructive": false,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            lines.append(String(decoding: data, as: UTF8.self))
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)

        let out = FileHandle.standardError
        out.write(Data("Wrote \(chosen.count) rows to \(outPath)\n".utf8))
        out.write(Data("Per-head distribution (chosen):\n".utf8))
        let dist = chosen.reduce(into: [String: Int]()) { $0[$1.head, default: 0] += 1 }
        for (head, n) in dist.sorted(by: { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }) {
            out.write(Data("  \(head): \(n)\n".utf8))
        }
        out.write(Data("Dropped from corpus:\n".utf8))
        for (reason, n) in dropped.sorted(by: { $0.value > $1.value }) {
            out.write(Data("  \(reason): \(n)\n".utf8))
        }
    }

    private struct PairRef {
        let originalIndex: Int
        let goal: String
        let canonical: String
        let head: String
    }

    private static let shellBuiltinHeads: Set<String> = [
        "read", "set", "unset", "shopt", "source", "alias", "unalias",
        "while", "if", "case", "for", "until", "true", "false", ":",
        "eval", "exec", "export", "declare", "local", "return",
        "function", "echo", // echo is a real binary but as nl2bash "head" it's
                            // almost always a noise row (echoing literals, not a useful suggestion test).
    ]

    private static let headPattern: NSRegularExpression = try! NSRegularExpression(pattern: #"^[a-z][a-z0-9_.-]*$"#)

    private func filterReason(goal: String, canonical: String, placeholderVar: NSRegularExpression) -> String? {
        if goal.isEmpty || canonical.isEmpty { return "empty" }
        if goal.contains("(GNU specific") || goal.contains("(BSD specific") { return "platform_tagged" }
        if canonical.count > maxCmLength { return "cm_too_long" }
        if canonical.count < minCmLength { return "cm_too_short" }
        if canonical.contains("\n") { return "cm_multiline" }
        if canonical.contains("awk '") || canonical.contains("sed '") { return "embedded_script" }
        if canonical.hasPrefix("(") || canonical.hasPrefix("{") { return "subshell_or_group" }
        if canonical.contains("`") { return "legacy_backticks" }
        if canonical.hasPrefix("./") || canonical.hasPrefix(".\\/") { return "script_invocation" }
        // VAR=value or VAR=$(...) — the head ends up inside a substitution, useless as a suggestion row.
        if canonical.range(of: #"^[A-Za-z_][A-Za-z0-9_]*\s*="#, options: .regularExpression) != nil { return "variable_assignment" }
        // Goal looks like a bash command (likely an NL/CM swap row in the source data).
        if goal.range(of: #"^[a-z][a-z0-9_-]*\s+-"#, options: .regularExpression) != nil { return "nl_cm_swap_suspected" }
        let scrubbed = canonical.replacingOccurrences(of: "$(", with: "##SUB##")
        let r = NSRange(scrubbed.startIndex..., in: scrubbed)
        if placeholderVar.firstMatch(in: scrubbed, range: r) != nil { return "shell_var_placeholder" }
        // Drop $0/$1/... positional refs that the previous regex misses.
        if scrubbed.range(of: #"\$\d"#, options: .regularExpression) != nil { return "positional_ref" }
        // Head must look like a real binary name and not a shell builtin/control-flow keyword.
        guard let head = CommandShape.binaries(in: canonical).first else { return "no_head" }
        let headRange = NSRange(head.startIndex..., in: head)
        if Self.headPattern.firstMatch(in: head, range: headRange) == nil { return "head_unparseable" }
        if Self.shellBuiltinHeads.contains(head) { return "shell_builtin_head" }
        return nil
    }
}

// SplitMix64 — small deterministic RNG suitable for sampling.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}
