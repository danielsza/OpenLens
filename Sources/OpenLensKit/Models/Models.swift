import Foundation

/// A project (or system folder) in an Aperture library.
///
/// Aperture organises everything in `RKFolder`. `folderType == 2` denotes a
/// real user project; `folderType == 1` denotes system/structural folders
/// (Library root, Trash, the "Projects" container, etc.). The tree is encoded
/// in `folderPath`, e.g. "1/2/10/" means root → Projects → this folder.
public struct Project: Identifiable, Hashable {
    public let id: String          // uuid
    public let modelId: Int
    public let name: String
    public let folderType: Int
    public let folderPath: String
    public let parentUuid: String?
    public let versionCount: Int
    public let createDate: Date?

    public var isProject: Bool { folderType == 2 }

    /// Depth in the folder tree, derived from folderPath ("1/2/10/" → 3).
    public var depth: Int {
        folderPath.split(separator: "/").count
    }
}

/// An imported original file ("master"). One master may have several versions.
public struct PhotoMaster: Identifiable, Hashable {
    public let id: String          // uuid
    public let modelId: Int
    public let fileName: String
    public let originalFileName: String?
    /// Path relative to the library's `Masters/` directory.
    public let imagePath: String
    public let projectUuid: String
    public let type: String        // e.g. "IMGT" (image), "VIDT" (video)
    public let isReference: Bool   // true => master lives outside the library
    public let isMissing: Bool
    public let fileSize: Int?
}

/// A non-destructive "version" of a master. This is what the user actually
/// browses and rates. Aperture creates Version-0 (original) and Version-1
/// (the editable current version) per master.
public struct PhotoVersion: Identifiable, Hashable {
    public let id: String          // uuid
    public let modelId: Int
    public let name: String
    public let fileName: String
    public let versionNumber: Int
    public let masterUuid: String
    public let projectUuid: String

    public var rating: Int         // mainRating, 0...5 (Aperture used -1 for reject historically; modern uses isRejected via rating)
    public var isFlagged: Bool
    public var colorLabel: Int     // colorLabelIndex, -1 == none, 0...6 colours
    public let hasAdjustments: Bool
    public let isOriginal: Bool
    public let rotation: Int
    public let isInTrash: Bool
    public let showInLibrary: Bool

    public let imageDate: Date?
    public let masterWidth: Int?
    public let masterHeight: Int?

    /// The stack this version belongs to, if any (`RKVersion.stackUuid`).
    public var stackUuid: String?

    /// Whether the version has any keywords assigned (`RKVersion.hasKeywords`).
    public var hasKeywords: Bool = false
}

/// Combined view used by the UI: a version plus its resolved master.
public struct Photo: Identifiable, Hashable {
    public var id: String { version.id }
    public let version: PhotoVersion
    public let master: PhotoMaster

    public init(version: PhotoVersion, master: PhotoMaster) {
        self.version = version
        self.master = master
    }
}

/// An album (regular or smart). Aperture stores these in `RKAlbum`; membership
/// for regular albums is in `RKAlbumVersion` (which links by `modelId`).
public struct Album: Identifiable, Hashable {
    public let id: String          // uuid
    public let modelId: Int
    public let name: String?
    public let albumType: Int
    public let albumSubclass: Int  // 1 = implicit (project/library), 2 = smart, 3 = regular/import
    public let folderUuid: String?
    public let isMagic: Bool
    public let isInTrash: Bool

    public var displayName: String { name ?? "Untitled Album" }

    /// Internal/smart albums Aperture maintains automatically.
    static let systemNames: Set<String> = [
        "trashAlbum", "allPhotosAlbum", "flaggedAlbum", "rejectedAlbum",
        "lastNMonthsAlbum", "eventFilterBarAlbum", "allPlacedPhotosAlbum"
    ]

    /// True for implicit/smart/automatic albums rather than ones the user made.
    public var isSystem: Bool {
        albumSubclass == 1 || isMagic || Album.systemNames.contains(name ?? "")
    }
}

/// A stack: a group of versions Aperture displays collapsed under one "pick".
/// Membership is in `RKStackContent`; the pick/state is in `RKStackState`.
public struct Stack: Identifiable, Hashable {
    public let id: String                 // stackUuid
    public let versionUuids: [String]     // ordered members
    public let pickVersionUuid: String?   // the version shown when collapsed
    public var count: Int { versionUuids.count }
}

/// A keyword in the (hierarchical) keyword vocabulary (`RKKeyword`).
public struct Keyword: Identifiable, Hashable {
    public let id: String          // uuid
    public let modelId: Int
    public let name: String
    public let parentModelId: Int?
    public let hasChildren: Bool
}

/// Colour labels, matching Aperture's `colorLabelIndex` values.
public enum ColorLabel: Int, CaseIterable {
    case none = -1
    case red = 0
    case orange = 1
    case yellow = 2
    case green = 3
    case blue = 4
    case purple = 5
    case gray = 6

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .gray: return "Gray"
        }
    }
}
