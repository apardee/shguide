import Foundation

public enum PathInventory {
    public static func snapshot(env: [String: String] = ProcessInfo.processInfo.environment) -> Set<String> {
        guard let path = env["PATH"], !path.isEmpty else { return [] }
        let fm = FileManager.default
        var result: Set<String> = []
        for dir in path.split(separator: ":").map(String.init) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries {
                let full = (dir as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
                if fm.isExecutableFile(atPath: full) {
                    result.insert(entry)
                }
            }
        }
        return result
    }
}
