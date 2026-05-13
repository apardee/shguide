import Foundation

public enum DestructivePolicy {
    /// First-token binary names that are inherently destructive.
    public static let dangerousBinaries: Set<String> = [
        "rm", "dd", "shred",
        "mkfs", "mkfs.hfs", "mkfs.apfs", "mkfs.ext4",
        "diskutil", "fdisk", "parted", "newfs", "newfs_apfs", "newfs_hfs",
        "shutdown", "reboot", "halt", "poweroff",
        "kill", "pkill", "killall",
    ]

    /// Substring patterns that are destructive regardless of leading binary.
    static let dangerousPatterns: [String] = [
        "rm -rf /",
        "rm -rf ~",
        "rm -rf $HOME",
        ":(){:|:&};:",                // fork bomb
        "> /dev/sd",
        "> /etc/",
        "of=/dev/sd",
        "of=/dev/disk",
        "chmod -R 777",
        "chown -R",
        "xargs rm",                   // pipelines feeding rm
        "xargs -I",                   // common xargs-rm idiom; trips on `xargs -I {} rm`
        "| rm ",
        "|rm ",
    ]

    /// Decide if a command should be flagged destructive.
    public static func isDestructive(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        for pat in dangerousPatterns where trimmed.contains(pat) {
            return true
        }
        // Split by pipes / && / ; and check each segment's first token.
        let separators: CharacterSet = CharacterSet(charactersIn: "|;&")
        for raw in trimmed.components(separatedBy: separators) {
            let seg = raw.trimmingCharacters(in: .whitespaces)
            guard let first = seg.split(whereSeparator: { $0.isWhitespace }).first else { continue }
            let name = String(first)
            if dangerousBinaries.contains(name) {
                return true
            }
        }
        return false
    }

    /// Resolve the *effective* risk by combining the model's self-label with our own check.
    public static func effectiveRisk(command: String, modelLabel: String) -> Risk {
        let modelRisk = Risk(modelLabel: modelLabel)
        if isDestructive(command) { return .destructive }
        return modelRisk
    }
}
