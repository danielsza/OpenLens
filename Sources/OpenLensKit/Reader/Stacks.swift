import Foundation

public extension ApertureLibrary {

    /// All stacks, with ordered member version uuids and the collapsed "pick".
    func stacks() throws -> [Stack] {
        let content = try libraryDB.query("""
            SELECT stackUuid, versionUuid, orderNumber
            FROM RKStackContent
            ORDER BY stackUuid, orderNumber
            """)
        guard !content.isEmpty else { return [] }

        // pick per stack (RKStackState.albumPick references the pick version).
        var picks: [String: String] = [:]
        let states = try libraryDB.query("SELECT stackUuid, albumPick FROM RKStackState")
        for row in states {
            if let s = row["stackUuid"]?.stringValue,
               let p = row["albumPick"]?.stringValue, !p.isEmpty {
                picks[s] = p
            }
        }

        var ordered: [String] = []                 // preserve first-seen order
        var members: [String: [String]] = [:]
        for row in content {
            guard let s = row["stackUuid"]?.stringValue,
                  let v = row["versionUuid"]?.stringValue else { continue }
            if members[s] == nil { ordered.append(s) }
            members[s, default: []].append(v)
        }
        return ordered.map { Stack(id: $0, versionUuids: members[$0] ?? [],
                                   pickVersionUuid: picks[$0]) }
    }

    /// Photos for a given stack, in stack order.
    func photos(inStack stack: Stack) throws -> [Photo] {
        let byId = Dictionary(uniqueKeysWithValues: try photos().map { ($0.id, $0) })
        return stack.versionUuids.compactMap { byId[$0] }
    }
}
