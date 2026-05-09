import XCTest
@testable import SMCKit

final class SMCKitTests: XCTestCase {

    func testKeyEncoding() {
        // "FNum" = 0x464E756D
        XCTAssertEqual(SMCKey("FNum").raw, 0x464E_756D)
        XCTAssertEqual(SMCKey("F0Ac").description, "F0Ac")
        XCTAssertEqual(SMCKey("F0Md").description, "F0Md")
    }

    func testTypeEncoding() {
        XCTAssertEqual(SMCType.flt.description,  "flt ")
        XCTAssertEqual(SMCType.ui8.description,  "ui8 ")
        XCTAssertEqual(SMCType.sp78.description, "sp78")
    }

    func testSP78Decoding() {
        // sp78: 25.5 °C = 0x1980 (25 << 8 | 0x80)
        let bytes: [UInt8] = [0x19, 0x80]
        let v = SMCValue.raw(.sp78, bytes)
        XCTAssertEqual(v.asDouble!, 25.5, accuracy: 0.001)
    }

    func testSP78NegativeDecoding() {
        // -1.0 °C = 0xFF00
        let bytes: [UInt8] = [0xFF, 0x00]
        let v = SMCValue.raw(.sp78, bytes)
        XCTAssertEqual(v.asDouble!, -1.0, accuracy: 0.001)
    }

    func testFloatDecoding() {
        // 1234.5f → little-endian bytes
        var f: Float = 1234.5
        let bytes = withUnsafeBytes(of: &f) { Array($0) }
        let v = SMCValue.float(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        XCTAssertEqual(v.asDouble!, 1234.5, accuracy: 0.001)
    }
}
