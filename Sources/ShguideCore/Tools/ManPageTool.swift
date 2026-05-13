import Foundation
import FoundationModels

@available(macOS 26.0, *)
public struct ManPageTool: Tool {
    public let name = "manPage"
    public let description = "Read the NAME and SYNOPSIS sections of a command's man page on this system. Use this when unsure of a flag's exact spelling or meaning."

    public let availableBinaries: Set<String>

    public init(availableBinaries: Set<String>) {
        self.availableBinaries = availableBinaries
    }

    @Generable
    public struct Arguments {
        @Guide(description: "Bare command name whose man page should be read. No flags, no paths.")
        public var name: String
    }

    public func call(arguments: Arguments) async throws -> String {
        let name = arguments.name.trimmingCharacters(in: .whitespaces)
        // Defensive validation — we run /usr/bin/man via Process, no shell, but still reject anything weird.
        guard ManPageTool.isSafeName(name) else { return "invalid name" }
        guard availableBinaries.contains(name) else { return "not found" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/man")
        process.arguments = [name]
        var env = ProcessInfo.processInfo.environment
        env["MANPAGER"] = "cat"
        env["PAGER"] = "cat"
        env["LESS"] = ""
        env["MANWIDTH"] = "100"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return "error: \(error.localizedDescription)"
        }
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return "empty" }
        let text = String(decoding: data, as: UTF8.self)
        return ManPageTool.extractNameAndSynopsis(text, limit: 800)
    }

    static func isSafeName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        for scalar in name.unicodeScalars {
            // Allow letters, digits, ., _, -, +
            let ok = CharacterSet.alphanumerics.contains(scalar)
                || scalar == "." || scalar == "_" || scalar == "-" || scalar == "+"
            if !ok { return false }
        }
        return true
    }

    static func extractNameAndSynopsis(_ text: String, limit: Int) -> String {
        // man output is groff-rendered with backspace overstrike for bold. Strip overstrike.
        let cleaned = stripOverstrike(text)
        let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false)
        var collected: [String] = []
        var inSection = false
        for rawLine in lines {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "NAME" || trimmed == "SYNOPSIS" {
                inSection = true
                collected.append(trimmed)
                continue
            }
            if inSection {
                if trimmed.isEmpty {
                    collected.append("")
                    continue
                }
                // A new header is uppercase-only and non-indented.
                if !line.hasPrefix(" ") && trimmed == trimmed.uppercased() && trimmed.count >= 3
                   && trimmed.allSatisfy({ $0.isLetter || $0 == " " }) {
                    if trimmed == "DESCRIPTION" { break }
                    if !["NAME", "SYNOPSIS"].contains(trimmed) { break }
                }
                collected.append(line)
            }
        }
        var output = collected.joined(separator: "\n")
        if output.count > limit {
            let cut = output.index(output.startIndex, offsetBy: limit)
            output = String(output[..<cut]) + "…"
        }
        return output.isEmpty ? "no NAME/SYNOPSIS section" : output
    }

    static func stripOverstrike(_ text: String) -> String {
        // `man` (via groff) emits sequences like "_\bX" for underline and "X\bX" for bold.
        var out = ""
        out.reserveCapacity(text.count)
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            let next = text.index(after: i)
            if next < text.endIndex, text[next] == "\u{08}" {
                let third = text.index(after: next)
                if third < text.endIndex {
                    out.append(text[third])
                    i = text.index(after: third)
                    continue
                }
            }
            if c != "\u{08}" {
                out.append(c)
            }
            i = next
        }
        return out
    }
}
