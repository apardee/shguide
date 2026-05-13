import Foundation

public struct ANSI: Sendable {
    public let enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public static func detect(noColorFlag: Bool, isTTY: Bool) -> ANSI {
        if noColorFlag { return ANSI(enabled: false) }
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return ANSI(enabled: false) }
        return ANSI(enabled: isTTY)
    }

    private func wrap(_ open: String, _ text: String) -> String {
        enabled ? "\(open)\(text)\u{001B}[0m" : text
    }

    public func red(_ text: String) -> String { wrap("\u{001B}[31m", text) }
    public func yellow(_ text: String) -> String { wrap("\u{001B}[33m", text) }
    public func green(_ text: String) -> String { wrap("\u{001B}[32m", text) }
    public func dim(_ text: String) -> String { wrap("\u{001B}[2m", text) }
    public func bold(_ text: String) -> String { wrap("\u{001B}[1m", text) }
    public func cyan(_ text: String) -> String { wrap("\u{001B}[36m", text) }
}
