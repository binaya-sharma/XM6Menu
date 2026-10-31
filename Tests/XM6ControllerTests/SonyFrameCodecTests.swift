import XCTest
@testable import XM6Controller

final class SonyFrameCodecTests: XCTestCase {
    func testFrameRoundTripAndEscaping() throws {
        let payload: [UInt8] = [0x22, 0x00, 0x3c, 0x3d, 0x3e]
        let encoded = SonyFrameCodec.encode(payload: payload, sequence: 1)
        XCTAssertEqual(try SonyFrameCodec.decode(encoded), SonyFrame(type: 0x0c, sequence: 1, payload: payload))
    }

    func testFrameRoundTripWithMultiByteLength() throws {
        let payload = Array(repeating: UInt8(0x5a), count: 300)
        let encoded = SonyFrameCodec.encode(payload: payload, sequence: 0)
        XCTAssertEqual(try SonyFrameCodec.decode(encoded).payload, payload)
    }

    func testRejectsBadChecksum() {
        var encoded = SonyFrameCodec.encode(payload: [0x66, 0x19], sequence: 0)
        encoded[encoded.count - 2] ^= 0xff
        XCTAssertThrowsError(try SonyFrameCodec.decode(encoded))
    }

    func testRejectsTruncatedAndLengthMismatchedFrames() {
        XCTAssertThrowsError(try SonyFrameCodec.decode([0x3e, 0x0c, 0x00, 0x3c]))

        var encoded = SonyFrameCodec.encode(payload: [0x22, 0x00], sequence: 0)
        encoded[6] = 0x03
        encoded[encoded.count - 2] = encoded[1..<(encoded.count - 2)].reduce(0, &+)
        XCTAssertThrowsError(try SonyFrameCodec.decode(encoded))
    }

    func testDiscoveryAllowsOnlyWH1000XM6() {
        XCTAssertTrue(BluetoothService.isSupportedXM6(name: "WH-1000XM6"))
        XCTAssertTrue(BluetoothService.isSupportedXM6(name: "WH1000XM6"))
        XCTAssertTrue(BluetoothService.isSupportedXM6(name: "Sony WH-1000XM6"))
        XCTAssertFalse(BluetoothService.isSupportedXM6(name: "WH-1000XM5"))
        XCTAssertFalse(BluetoothService.isSupportedXM6(name: "WH-1000XM4"))
        XCTAssertFalse(BluetoothService.isSupportedXM6(name: "XM6 Controller"))
    }
}
