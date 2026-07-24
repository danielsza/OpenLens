import Foundation

public extension ApertureLibrary {

    /// Creates a Vault-style backup: copies the entire library package into
    /// `directory` as `<name>-vault-<timestamp>.aplibrary`, then verifies the
    /// copy with the consistency checker. Returns the backup URL + its report.
    @discardableResult
    func createVault(in directory: URL) throws -> (url: URL, report: ConsistencyReport) {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = { () -> String in
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
            return f.string(from: Date())
        }()
        let baseName = url.deletingPathExtension().lastPathComponent
        let dest = directory.appendingPathComponent("\(baseName)-vault-\(stamp).aplibrary")
        try fm.copyItem(at: url, to: dest)

        let copy = try ApertureLibrary(url: dest)
        let report = try copy.checkConsistency()
        return (dest, report)
    }
}
