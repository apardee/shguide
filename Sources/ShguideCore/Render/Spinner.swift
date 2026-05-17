import Darwin
import Foundation

/// Runs `body` while animating a braille spinner on stderr.
/// The spinner only renders when `enabled` is true (i.e., stderr is a TTY).
public func withSpinner<T: Sendable>(
    label: String,
    enabled: Bool,
    _ body: () async throws -> T
) async rethrows -> T {
    guard enabled else { return try await body() }

    let spinTask = Task.detached {
        let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        var i = 0
        repeat {
            fputs("\r\u{1B}[2m\(frames[i % frames.count])\u{1B}[0m \(label)", Darwin.stderr)
            fflush(Darwin.stderr)
            i += 1
            try? await Task.sleep(nanoseconds: 80_000_000)
        } while !Task.isCancelled
        fputs("\r\u{1B}[2K", Darwin.stderr)
        fflush(Darwin.stderr)
    }

    do {
        let result = try await body()
        spinTask.cancel()
        await spinTask.value
        return result
    } catch {
        spinTask.cancel()
        await spinTask.value
        throw error
    }
}
