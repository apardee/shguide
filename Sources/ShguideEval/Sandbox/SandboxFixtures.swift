import Foundation

/// Shared helpers for building reproducible test environments inside a temp dir.
enum SandboxFixtures {

    // MARK: - Text files

    static func makeTextFile(name: String, content: String, in dir: URL) throws {
        try content.write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
    }

    // MARK: - Sized files (sparse — no real allocation for large sizes)

    /// Creates a file with exactly `sizeBytes` bytes by seeking and writing one
    /// byte at the final offset. This produces a sparse file on APFS/HFS+,
    /// making even "large" fixtures effectively instant to create.
    static func makeSizedFile(name: String, sizeBytes: Int, in dir: URL) throws {
        let url = dir.appending(path: name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard sizeBytes > 0 else { return }
        let fh = try FileHandle(forWritingTo: url)
        defer { try? fh.close() }
        try fh.seek(toOffset: UInt64(sizeBytes - 1))
        try fh.write(contentsOf: Data([0x00]))
    }

    // MARK: - Directories

    static func makeDirectory(name: String, in dir: URL) throws -> URL {
        let sub = dir.appending(path: name)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        return sub
    }

    // MARK: - Tar archives

    /// Creates a gzipped tar archive at `archiveName` inside `dir`.
    /// `entries` is a mapping of relative path → file content to pack.
    /// The archive is built by writing the entry files to a staging subdir,
    /// running `/usr/bin/tar`, then cleaning up the staging dir.
    static func makeTarGz(archiveName: String, entries: [String: String], in dir: URL) throws {
        let staging = dir.appending(path: "_tar_staging")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        // Write each entry into the staging area, creating any needed subdirs.
        var relPaths: [String] = []
        for (relPath, content) in entries {
            let dest = staging.appending(path: relPath)
            let parentDir = dest.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try content.write(to: dest, atomically: true, encoding: .utf8)
            relPaths.append(relPath)
        }

        // Build the archive with /usr/bin/tar (not sandboxed — this is setup).
        let archivePath = dir.appending(path: archiveName).path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", archivePath, "-C", staging.path] + relPaths
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw FixtureError.tarFailed(archiveName)
        }
    }

    // MARK: - History file

    /// Writes a fake shell history file at `~/.zsh_history` (relative to `dir`,
    /// which is remapped as HOME by the sandbox runner).
    static func makeShellHistory(commands: [String], in dir: URL) throws {
        let lines = commands.enumerated().map { i, cmd in
            ": \(1700000000 + i):0;\(cmd)"   // zsh extended history format
        }
        try makeTextFile(name: ".zsh_history", content: lines.joined(separator: "\n") + "\n", in: dir)
    }

    // MARK: - Error

    enum FixtureError: Error {
        case tarFailed(String)
    }
}
