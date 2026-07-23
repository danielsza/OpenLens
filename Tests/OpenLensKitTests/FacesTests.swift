import XCTest
import CoreGraphics
import ImageIO
@testable import OpenLensKit

final class FacesTests: XCTestCase {

    private func makePNG(_ url: URL) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 20, height: 15, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.6, green: 0.6, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 15))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        _ = CGImageDestinationFinalize(dest)
    }

    func testNoFacesDBMeansEmpty() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-face0-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("f-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: src) }
        try makePNG(src)
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        _ = try writer.importImage(at: src, intoProject: project)
        let lib = try ApertureLibrary(url: libURL)
        let photo = try XCTUnwrap(try lib.photos().first)
        XCTAssertTrue(lib.detectedFaces(for: photo).isEmpty)
    }

    func testReadsFaceRectAndName() throws {
        let libURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLens-face1-\(UUID().uuidString).aplibrary")
        defer { try? FileManager.default.removeItem(at: libURL) }
        let created = try ApertureLibraryCreator.createLibrary(at: libURL, firstProjectNamed: "P")
        let project = try XCTUnwrap(created.projects().first?.id)
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("f-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: src) }
        try makePNG(src)
        let writer = ApertureLibraryWriter(libraryURL: libURL, allowWrites: true)
        _ = try writer.importImage(at: src, intoProject: project)
        let lib0 = try ApertureLibrary(url: libURL)
        let photo = try XCTUnwrap(try lib0.photos().first)

        // Author a Faces.db in Aperture's schema with one named face at
        // (0.2..0.6 x, bottom-origin 0.3..0.7 y).
        let facesDB = try SQLiteDatabase(
            path: libURL.appendingPathComponent("Database/apdb/Faces.db").path,
            readOnly: false, create: true)
        try facesDB.execute("""
            CREATE TABLE RKDetectedFace(modelId INTEGER PRIMARY KEY, uuid varchar,
              masterUuid varchar, faceKey INTEGER, faceIndex INTEGER,
              topLeftX REAL, topLeftY REAL, topRightX REAL, topRightY REAL,
              bottomLeftX REAL, bottomLeftY REAL, bottomRightX REAL, bottomRightY REAL,
              confidence REAL, rejected INTEGER, "ignore" INTEGER)
            """)
        try facesDB.execute("CREATE TABLE RKFaceName(modelId INTEGER PRIMARY KEY, faceKey INTEGER, name varchar)")
        try facesDB.execute("""
            INSERT INTO RKDetectedFace VALUES (1, 'FACE1', ?, 7, 0,
                0.2, 0.7,  0.6, 0.7,  0.2, 0.3,  0.6, 0.3,  0.9, 0, 0)
            """, [.text(photo.master.id)])
        try facesDB.execute("INSERT INTO RKFaceName VALUES (1, 7, 'Babcia')")

        let lib = try ApertureLibrary(url: libURL)
        let faces = lib.detectedFaces(for: photo)
        XCTAssertEqual(faces.count, 1)
        let f = try XCTUnwrap(faces.first)
        XCTAssertEqual(f.name, "Babcia")
        XCTAssertEqual(f.rect.minX, 0.2, accuracy: 0.001)
        XCTAssertEqual(f.rect.minY, 0.3, accuracy: 0.001)   // 1 - 0.7 top-origin
        XCTAssertEqual(f.rect.width, 0.4, accuracy: 0.001)
        XCTAssertEqual(f.rect.height, 0.4, accuracy: 0.001)
    }
}
