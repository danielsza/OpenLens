import XCTest
import CoreGraphics
@testable import OpenLensKit

final class AdjustmentGeometryTests: XCTestCase {

    private func data(_ hex: String) -> Data {
        var d = Data(); var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            d.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return d
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func testDecodesRealStraightenOperation() throws {
        let op = try XCTUnwrap(ApertureAdjustmentDecoder.decode(uuid: "s", data: data(Self.straightenHex)))
        XCTAssertEqual(op.identifier, "RKStraightenCropOperation")
        XCTAssertEqual(op.parameters["inputRotation"] ?? 0, -2.068426724137929, accuracy: 0.0001)

        let params = OLAdjustments(approximating: [op])
        XCTAssertEqual(params.straighten, -2.068426724137929, accuracy: 0.0001)
    }

    func testCropRendersToCropRect() {
        var params = OLAdjustments()
        params.cropX = 50; params.cropY = 20
        params.cropWidth = 100; params.cropHeight = 60
        let out = AdjustmentRenderer.apply(params, to: makeImage(width: 200, height: 100),
                                           masterPixelSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(out.width, 100)
        XCTAssertEqual(out.height, 60)
    }

    func testCropScalesForDownsampledRender() {
        var params = OLAdjustments()
        params.cropX = 100; params.cropY = 40
        params.cropWidth = 200; params.cropHeight = 120
        // Render at half size: crop rect should halve too.
        let out = AdjustmentRenderer.apply(params, to: makeImage(width: 200, height: 100),
                                           masterPixelSize: CGSize(width: 400, height: 200))
        XCTAssertEqual(out.width, 100)
        XCTAssertEqual(out.height, 60)
    }

    func testStraightenKeepsDimensions() {
        var params = OLAdjustments()
        params.straighten = 3.5
        let out = AdjustmentRenderer.apply(params, to: makeImage(width: 200, height: 100))
        XCTAssertEqual(out.width, 200)
        XCTAssertEqual(out.height, 100)
    }

    func testOldJSONWithoutGeometryKeysStillDecodes() throws {
        let old = #"{"exposure":0.5,"contrast":1,"saturation":1,"temperature":0,"tint":0,"highlights":0,"shadows":0,"sharpness":0}"#
        let params = try XCTUnwrap(OLAdjustments.decode(Data(old.utf8)))
        XCTAssertEqual(params.exposure, 0.5, accuracy: 0.0001)
        XCTAssertEqual(params.straighten, 0)
        XCTAssertFalse(params.hasCrop)
    }

    private static let straightenHex = "62706C6973743030D40102030405063536582476657273696F6E58246F626A65637473592461726368697665725424746F7012000186A0AF101107081B1C1D1E1F2021272829303132333455246E756C6CD3090A0B0C131A574E532E6B6579735A4E532E6F626A656374735624636C617373A60D0E0F101112800280038004800580068007A61415161718198008800C800D800E800F8010800B59696E7075744B6579735F101844474F7065726174696F6E56657273696F6E4E756D62657257656E61626C65645F101444474F7065726174696F6E436C6173734E616D655F101544474F7065726174696F6E4964656E7469666965725F101644474F7065726174696F6E446973706C61794E616D65D3090A0B22241AA1238009A125800A800B5D696E707574526F746174696F6E23C0008C234F72C230D22A2B2C2D5A24636C6173736E616D655824636C61737365735F10134E534D757461626C6544696374696F6E617279A32C2E2F5C4E5344696374696F6E617279584E534F626A6563741000095F101544475374726169676874656E4F7065726174696F6E5F1019524B5374726169676874656E43726F704F7065726174696F6E5A5374726169676874656E5F100F4E534B657965644172636869766572D1373854726F6F74800100080011001A0023002D00320037004B005100580060006B00720079007B007D007F008100830085008C008E00900092009400960098009A00A400BF00C700DE00F6010F01160118011A011C011E0120012E0137013C014701500166016A0177018001820183019B01B701C201D401D701DC00000000000002010000000000000039000000000000000000000000000001DE"
}
