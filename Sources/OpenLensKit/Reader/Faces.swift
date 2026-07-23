import Foundation
import CoreGraphics

/// A face Aperture detected on a photo's master.
public struct DetectedFace: Identifiable, Equatable {
    public let id: String            // uuid
    public let masterUuid: String
    public let confidence: Double
    /// Normalised bounding box in **top-left-origin** unit coordinates
    /// (Aperture stores corners in bottom-left-origin; converted here).
    public let rect: CGRect
    /// The person's name, when the face was named in Aperture.
    public let name: String?
}

public extension ApertureLibrary {

    /// Detected faces for a photo (empty if the library has no Faces.db).
    /// Rejected/ignored detections are filtered out.
    func detectedFaces(for photo: Photo) -> [DetectedFace] {
        let dbPath = url.appendingPathComponent("Database/apdb/Faces.db").path
        guard FileManager.default.fileExists(atPath: dbPath),
              let db = try? SQLiteDatabase(path: dbPath, readOnly: true) else { return [] }

        // Names are keyed by faceKey in RKFaceName (may be absent/empty).
        var names: [Int: String] = [:]
        if let rows = try? db.query("SELECT faceKey, name FROM RKFaceName") {
            for row in rows {
                if let k = row["faceKey"]?.intValue, let n = row["name"]?.stringValue {
                    names[k] = n
                }
            }
        }

        guard let rows = try? db.query("""
            SELECT uuid, masterUuid, faceKey, confidence,
                   topLeftX, topLeftY, topRightX, topRightY,
                   bottomLeftX, bottomLeftY, bottomRightX, bottomRightY
            FROM RKDetectedFace
            WHERE masterUuid = ? AND rejected = 0 AND "ignore" = 0
            ORDER BY faceIndex
            """, [.text(photo.master.id)]) else { return [] }

        return rows.compactMap { row in
            guard let uuid = row["uuid"]?.stringValue else { return nil }
            // Corners can be swapped on rotated photos — take the bounding box
            // of all four corners, whatever their order.
            let xs = ["topLeftX", "topRightX", "bottomLeftX", "bottomRightX"]
                .compactMap { row[$0]?.doubleValue }
            let ys = ["topLeftY", "topRightY", "bottomLeftY", "bottomRightY"]
                .compactMap { row[$0]?.doubleValue }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return nil }
            let w = maxX - minX, h = maxY - minY
            guard w > 0.001, h > 0.001 else { return nil }   // skip degenerate points
            // Bottom-left-origin → top-left-origin.
            let rect = CGRect(x: minX, y: 1.0 - maxY, width: w, height: h)
            return DetectedFace(
                id: uuid,
                masterUuid: row["masterUuid"]?.stringValue ?? "",
                confidence: row["confidence"]?.doubleValue ?? 0,
                rect: rect,
                name: row["faceKey"]?.intValue.flatMap { names[$0] })
        }
    }
}
