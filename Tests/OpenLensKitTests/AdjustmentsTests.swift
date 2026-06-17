import XCTest
@testable import OpenLensKit

final class AdjustmentsTests: XCTestCase {

    private func openTestLibrary() throws -> ApertureLibrary {
        guard let path = ProcessInfo.processInfo.environment["OPENLENS_TEST_LIBRARY"] else {
            throw XCTSkip("Set OPENLENS_TEST_LIBRARY to run adjustment tests.")
        }
        return try ApertureLibrary(url: URL(fileURLWithPath: path))
    }

    func testReadsAdjustmentsForEditedPhoto() throws {
        let lib = try openTestLibrary()
        // The fixture's first photo has Exposure + White Balance.
        guard let edited = try lib.photos().first(where: { $0.version.hasAdjustments }) else {
            throw XCTSkip("No edited photos in this library")
        }
        let adj = try lib.adjustments(for: edited)
        XCTAssertFalse(adj.isEmpty)
        // Ordered by index.
        XCTAssertEqual(adj.map { $0.index }, adj.map { $0.index }.sorted())
        let names = try lib.enabledAdjustmentNames(for: edited)
        XCTAssertTrue(names.contains("Exposure"))
        XCTAssertTrue(names.contains("White Balance"))
    }

    func testNumericParametersFromPlainPlist() throws {
        let lib = try openTestLibrary()
        guard let edited = try lib.photos().first(where: { $0.version.hasAdjustments }) else {
            throw XCTSkip("No edited photos")
        }
        let exposure = try XCTUnwrap(
            try lib.adjustments(for: edited).first { $0.type == .exposure })
        let params = exposure.numericParameters()
        XCTAssertEqual(params["inputEV"] ?? 0, 0.5, accuracy: 0.0001)
    }

    func testTypeMappingAndDisplayNames() {
        XCTAssertEqual(AdjustmentType(rawName: "RKExposureAdjustment"), .exposure)
        XCTAssertEqual(AdjustmentType(rawName: "RKCropOperation"), .crop)
        XCTAssertEqual(AdjustmentType(rawName: "RKWhiteBalanceAdjustment").displayName, "White Balance")
        // Unknown names get a cleaned-up display name.
        XCTAssertEqual(AdjustmentType(rawName: "RKFooBarAdjustment").displayName, "FooBar")
    }
}
