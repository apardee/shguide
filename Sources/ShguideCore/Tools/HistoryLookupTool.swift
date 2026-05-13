import Foundation
import FoundationModels

@available(macOS 26.0, *)
public struct HistoryLookupTool: Tool {
    public let name = "historyLookup"
    public let description = "Search the user's shell history for commands matching the given keywords. Use this to surface commands the user has already run that may solve the goal."

    public let history: [String]

    public init(history: [String]) {
        self.history = history
    }

    @Generable
    public struct Arguments {
        @Guide(
            description: "Substrings to look for in history entries. Typically tool names (e.g. \"find\", \"docker\") and operation words (e.g. \"size\", \"prune\").",
            .count(1...8)
        )
        public var keywords: [String]

        @Guide(
            description: "Maximum number of matching history entries to return.",
            .range(1...10)
        )
        public var limit: Int
    }

    public func call(arguments: Arguments) async throws -> String {
        let matches = ShellHistory.match(keywords: arguments.keywords, in: history, limit: arguments.limit)
        guard !matches.isEmpty else { return "no matches" }
        return matches
            .map { "\($0.occurrences)× \($0.command)" }
            .joined(separator: "\n")
    }
}
