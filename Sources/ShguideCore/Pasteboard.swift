import Foundation

public enum Pasteboard {
    /// Pipe `value` into pbcopy. Returns true on success.
    @discardableResult
    public static func copy(_ value: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let stdin = Pipe()
        process.standardInput = stdin
        do {
            try process.run()
        } catch {
            return false
        }
        if let data = value.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
