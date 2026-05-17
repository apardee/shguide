import Darwin
import Foundation

// Globals for SIGINT recovery — only one carousel runs at a time.
private nonisolated(unsafe) var _carouselTtyFd: Int32 = -1
private nonisolated(unsafe) var _carouselOrigTermios = termios()
private nonisolated(unsafe) var _carouselOrigTermiosSaved = false

private func _carouselSIGINT(_: Int32) {
    if _carouselOrigTermiosSaved {
        var orig = _carouselOrigTermios
        tcsetattr(_carouselTtyFd, TCSAFLUSH, &orig)
    }
    if _carouselTtyFd >= 0 {
        // Show cursor via raw write (signal-safe)
        let seq = "\u{1B}[?25h\n"
        _ = seq.withCString { Darwin.write(_carouselTtyFd, $0, strlen($0)) }
    }
    signal(SIGINT, SIG_DFL)
    raise(SIGINT)
}

public enum Carousel {

    /// Shows a single-suggestion browser. Returns the selected suggestion, or nil if dismissed.
    /// This call blocks the calling thread — invoke from a detached Task.
    public static func run(suggestions: [AnnotatedSuggestion], ansi: ANSI) -> AnnotatedSuggestion? {
        guard !suggestions.isEmpty else { return nil }
        guard let tty = fopen("/dev/tty", "r+") else { return nil }
        defer { fclose(tty) }
        let fd = fileno(tty)

        // Save original terminal state.
        var original = termios()
        tcgetattr(fd, &original)
        _carouselTtyFd = fd
        _carouselOrigTermios = original
        _carouselOrigTermiosSaved = true

        // Enable raw mode: no echo, no canonical (line-buffered) mode.
        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
        withUnsafeMutableBytes(of: &raw.c_cc) { buf in
            buf[Int(VMIN)] = 1
            buf[Int(VTIME)] = 0
        }
        tcsetattr(fd, TCSAFLUSH, &raw)

        let prevSIGINT = signal(SIGINT, _carouselSIGINT)
        defer {
            signal(SIGINT, prevSIGINT)
            _carouselOrigTermiosSaved = false
            _carouselTtyFd = -1
            tcsetattr(fd, TCSAFLUSH, &original)
            fputs("\u{1B}[?25h", tty)  // always restore cursor visibility
            fflush(tty)
        }

        fputs("\u{1B}[?25l", tty)  // hide cursor
        fflush(tty)

        let width = terminalWidth()
        var index = 0
        var lineCount = render(suggestions: suggestions, index: index, ansi: ansi, tty: tty, width: width)

        while true {
            var buf = [UInt8](repeating: 0, count: 8)
            let n = read(fd, &buf, 8)
            guard n > 0 else { break }

            switch parseKey(buf, n) {
            case .next:
                let next = (index + 1) % suggestions.count
                guard next != index else { break }
                index = next
                clearLines(lineCount, tty: tty)
                lineCount = render(suggestions: suggestions, index: index, ansi: ansi, tty: tty, width: width)

            case .prev:
                let prev = (index - 1 + suggestions.count) % suggestions.count
                guard prev != index else { break }
                index = prev
                clearLines(lineCount, tty: tty)
                lineCount = render(suggestions: suggestions, index: index, ansi: ansi, tty: tty, width: width)

            case .select:
                clearLines(lineCount, tty: tty)
                return suggestions[index]

            case .dismiss:
                clearLines(lineCount, tty: tty)
                return nil
            }
        }
        return nil
    }

    // MARK: - Private

    private enum Key { case next, prev, select, dismiss }

    private static func parseKey(_ buf: [UInt8], _ n: Int) -> Key {
        if buf[0] == 0x1B {
            // Arrow keys: ESC [ <letter>
            if n >= 3 && buf[1] == 0x5B {
                switch buf[2] {
                case 0x43, 0x42: return .next  // right, down
                case 0x44, 0x41: return .prev  // left, up
                default: break
                }
            }
            return .dismiss  // lone ESC
        }
        switch buf[0] {
        case 13, 10:               return .select   // Enter / LF
        case 9:                    return .next     // Tab → cycle forward
        case UInt8(ascii: "l"):    return .next     // vim-right
        case UInt8(ascii: "h"):    return .prev     // vim-left
        case UInt8(ascii: "q"), UInt8(ascii: "Q"): return .dismiss
        case 3:                    return .dismiss  // Ctrl-C (signal handler also fires)
        default:                   return .dismiss  // unknown: do nothing
        }
    }

    @discardableResult
    private static func render(
        suggestions: [AnnotatedSuggestion],
        index: Int,
        ansi: ANSI,
        tty: UnsafeMutablePointer<FILE>,
        width: Int
    ) -> Int {
        let s = suggestions[index]
        let total = suggestions.count

        let cmdStr: String = {
            switch s.risk {
            case .destructive: return ansi.red(s.command) + "  " + ansi.red("[destructive]")
            case .caution:     return ansi.yellow(s.command)
            case .safe:        return ansi.bold(s.command)
            }
        }()
        let histTag = s.fromHistory ? "  " + ansi.cyan("[history]") : ""

        var lines: [String] = []

        // Command line
        lines.append("  \(ansi.green("❯"))  \(cmdStr)\(histTag)")
        // Explanation
        lines.append("     \(ansi.dim(truncated(s.explanation, to: width - 6)))")
        // Spacer
        lines.append("")

        // Dots + navigation
        if total > 1 {
            let dots = (0..<total).map { i in
                i == index ? ansi.cyan("◆") : ansi.dim("◇")
            }.joined(separator: " ")
            lines.append("  \(dots)   \(ansi.dim("← → cycle  ·  ↵ select  ·  q quit"))")
        } else {
            lines.append("  \(ansi.dim("↵ to select  ·  q to quit"))")
        }

        fputs(lines.joined(separator: "\n"), tty)
        fflush(tty)
        return lines.count
    }

    private static func clearLines(_ count: Int, tty: UnsafeMutablePointer<FILE>) {
        // Cursor is at the end of the last rendered line.
        // Clear it, then move up and clear each preceding line.
        fputs("\r\u{1B}[2K", tty)
        for _ in 1..<count {
            fputs("\u{1B}[A\r\u{1B}[2K", tty)
        }
        fflush(tty)
    }

    private static func terminalWidth() -> Int {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0 {
            return Int(ws.ws_col)
        }
        return 80
    }

    private static func truncated(_ str: String, to width: Int) -> String {
        guard str.count > width else { return str }
        return String(str.prefix(width - 1)) + "…"
    }
}
