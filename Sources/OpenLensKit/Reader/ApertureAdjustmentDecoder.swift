import Foundation

/// A decoded legacy Aperture edit operation (from `RKImageAdjustment.data`).
///
/// Format (reverse-engineered from a real 68k-photo library): an
/// NSKeyedArchiver archive whose root dictionary carries
/// `DGOperationIdentifier`, `DGOperationDisplayName`, `enabled`, and an
/// `inputKeys` dictionary of parameters (`inputEV`, `inputTemperature`,
/// `inputTint`, crop origin/size, …).
public struct ApertureEditOperation: Identifiable, Equatable {
    public let id: String                 // adjustment row uuid
    public let identifier: String         // e.g. "RKExposureOperation"
    public let displayName: String        // e.g. "Exposure"
    public let enabled: Bool
    /// Numeric parameters from `inputKeys` (bools become 0/1).
    public let parameters: [String: Double]

    /// Parameters worth showing to a person (drops bookkeeping keys).
    public var displayParameters: [(name: String, value: Double)] {
        parameters
            .filter { key, _ in
                !key.contains("LegacyVersion") && !key.contains("AutoCalculator")
                    && !key.contains("WaitingForAuto") && !key.contains("UseAutoCalculated")
                    && !key.contains("IsDefaults") && key != "inputColorType"
                    && key != "inputConstrainTag" && key != "inputConstrainOrientation"
                    && key != "inputConstrainRatio"
            }
            .map { (String($0.dropFirst("input".count)), $1) }   // inputEV -> EV
            .sorted { $0.0 < $1.0 }
    }
}

/// Decodes Aperture's NSKeyedArchiver adjustment blobs without needing the
/// original DG* classes (unknown classes are substituted with a stub).
public enum ApertureAdjustmentDecoder {

    public static func decode(uuid: String, data: Data) -> ApertureEditOperation? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        let delegate = StubbingDelegate()
        unarchiver.delegate = delegate
        defer { unarchiver.finishDecoding() }
        guard let root = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
                as? [String: Any] else { return nil }

        let identifier = root["DGOperationIdentifier"] as? String
            ?? root["DGOperationClassName"] as? String ?? "Unknown"
        let display = root["DGOperationDisplayName"] as? String ?? identifier
        let enabled = (root["enabled"] as? Bool) ?? true

        var params: [String: Double] = [:]
        if let inputs = root["inputKeys"] as? [String: Any] {
            for (key, value) in inputs {
                if let number = value as? NSNumber {
                    params[key] = number.doubleValue
                }
            }
        }
        return ApertureEditOperation(id: uuid, identifier: identifier,
                                     displayName: display, enabled: enabled,
                                     parameters: params)
    }

    /// Substitutes a stub for any archived class we don't link (e.g. NSColor
    /// when AppKit isn't loaded, or Aperture's own DG* classes).
    private final class StubbingDelegate: NSObject, NSKeyedUnarchiverDelegate {
        func unarchiver(_ unarchiver: NSKeyedUnarchiver,
                        cannotDecodeObjectOfClassName name: String,
                        originalClasses classNames: [String]) -> AnyClass? {
            DecodeStub.self
        }
    }

    @objc(OLDecodeStub) private final class DecodeStub: NSObject, NSCoding {
        override init() { super.init() }
        required init?(coder: NSCoder) { super.init() }
        func encode(with coder: NSCoder) {}
    }
}

public extension ApertureLibrary {
    /// Fully decoded legacy Aperture edits for a photo (excludes OpenLens's
    /// own `OLAdjustmentsV1` rows and empty RAW-decode defaults).
    func decodedApertureAdjustments(for photo: Photo) -> [ApertureEditOperation] {
        guard tableExists("RKImageAdjustment") else { return [] }
        guard let rows = try? libraryDB.query("""
            SELECT uuid, data FROM RKImageAdjustment
            WHERE versionUuid = ? AND name != ? AND data IS NOT NULL
            ORDER BY adjIndex
            """, [.text(photo.version.id), .text(Self.olAdjustmentName)]) else { return [] }
        return rows.compactMap { row in
            guard let uuid = row["uuid"]?.stringValue,
                  let data = row["data"]?.dataValue,
                  let op = ApertureAdjustmentDecoder.decode(uuid: uuid, data: data) else {
                return nil
            }
            // Hide the ubiquitous empty "RAW Fine Tuning" default stamps.
            if op.identifier == "RKRawDecodeOperation" && op.parameters.isEmpty { return nil }
            return op
        }
    }
}
