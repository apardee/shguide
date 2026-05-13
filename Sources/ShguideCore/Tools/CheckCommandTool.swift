import Foundation
import FoundationModels

@available(macOS 26.0, *)
public struct CheckCommandTool: Tool {
    public let name = "checkCommand"
    public let description = "Check whether a command-line tool exists and is executable on this macOS system. Use this before suggesting an unusual or non-default tool."

    public let availableBinaries: Set<String>

    public init(availableBinaries: Set<String>) {
        self.availableBinaries = availableBinaries
    }

    @Generable
    public struct Arguments {
        @Guide(description: "Bare command name to look up. Do not include flags, arguments, or paths. Example: \"rg\", not \"rg --help\".")
        public var name: String
    }

    public func call(arguments: Arguments) async throws -> String {
        let name = arguments.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/"), !name.contains(" ") else {
            return "invalid name"
        }
        if availableBinaries.contains(name) {
            return "available"
        }
        return "not found"
    }
}
