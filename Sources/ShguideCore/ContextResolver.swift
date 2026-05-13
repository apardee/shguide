import Foundation

public enum ContextResolver {
    public static func resolve(
        includeDestructive: Bool,
        useHistory: Bool,
        useTools: Bool,
        goalKeywords: [String] = [],
        historyMatchLimit: Int = 10
    ) -> (context: InvocationContext, history: [String]) {
        let env = ProcessInfo.processInfo.environment
        let shellPath = env["SHELL"] ?? "/bin/zsh"
        let shellName = (shellPath as NSString).lastPathComponent
        let pathBinaries = PathInventory.snapshot(env: env)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let allHistory: [String] = useHistory ? ShellHistory.load() : []
        let matches: [HistoryEntry] = useHistory
            ? ShellHistory.match(keywords: goalKeywords, in: allHistory, limit: historyMatchLimit)
            : []

        let context = InvocationContext(
            shellName: shellName,
            osVersion: osVersion,
            pathBinaries: pathBinaries,
            historyMatches: matches,
            includeDestructive: includeDestructive,
            useTools: useTools
        )
        return (context, allHistory)
    }

    public static func keywords(from goal: String) -> [String] {
        // Crude extractor: keep tokens >= 3 chars, lowercase, dedupe, drop common stopwords.
        let stop: Set<String> = [
            "the", "and", "for", "with", "from", "into", "this", "that", "have", "has",
            "all", "any", "but", "out", "are", "you", "your", "how", "use", "using",
            "one", "two", "files", "file", "find", "show", "list", "list",
        ]
        let lowered = goal.lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        var seen: Set<String> = []
        var result: [String] = []
        for tok in lowered.components(separatedBy: separators) where tok.count >= 3 && !stop.contains(tok) {
            if seen.insert(tok).inserted {
                result.append(tok)
            }
        }
        return result
    }
}
