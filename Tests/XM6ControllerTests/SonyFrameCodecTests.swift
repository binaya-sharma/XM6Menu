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

    func testDecodesWearStatusRepliesAndNotifications() {
        XCTAssertEqual(XM6PayloadDecoder.wearState(from: [0xf3, 0x10, 0x00]), true)
        XCTAssertEqual(XM6PayloadDecoder.wearState(from: [0xf5, 0x10, 0x01, 0x01]), false)
        XCTAssertEqual(XM6PayloadDecoder.wearState(from: [0xf5, 0x10, 0x01, 0x00]), true)
    }

    func testRejectsUnrelatedWearPayloads() {
        XCTAssertNil(XM6PayloadDecoder.wearState(from: [0xf3, 0x11, 0x00]))
        XCTAssertNil(XM6PayloadDecoder.wearState(from: [0xf7, 0x10, 0x00]))
        XCTAssertNil(XM6PayloadDecoder.wearState(from: [0xf3, 0x10]))
    }

    func testDecodesSixBandEqualizerValues() {
        XCTAssertEqual(
            XM6PayloadDecoder.equalizerState(from: [0x57, 0x00, 0xa0, 0x06, 10, 11, 12, 13, 14, 15]),
            EqualizerState(preset: .custom, layout: .clearBassFive, bands: [0, 1, 2, 3, 4, 5])
        )
    }

    func testDecodesTenBandEqualizerValues() {
        XCTAssertEqual(
            XM6PayloadDecoder.equalizerState(
                from: [0x57, 0x00, 0xa0, 0x0a, 6, 7, 5, 6, 8, 6, 4, 6, 9, 6]
            ),
            EqualizerState(
                preset: .custom,
                layout: .graphicTen,
                bands: [0, 1, -1, 0, 2, 0, -2, 0, 3, 0]
            )
        )
    }

    func testRejectsMalformedOrUnknownEqualizerPayloads() {
        XCTAssertNil(XM6PayloadDecoder.equalizerState(from: [0x57, 0x00, 0xa0, 0x02, 10]))
        XCTAssertNil(XM6PayloadDecoder.equalizerState(from: [0x57, 0x00, 0xfe, 0x00]))
        XCTAssertNil(XM6PayloadDecoder.equalizerState(from: [0x58, 0x00, 0x30, 0x00]))
        XCTAssertNil(XM6PayloadDecoder.equalizerState(from: [0x57, 0x00, 0xa0, 0x06, 21, 10, 10, 10, 10, 10]))
        XCTAssertEqual(
            XM6PayloadDecoder.equalizerState(from: [0x59, 0x00, 0x30, 0x00]),
            EqualizerState(preset: .heavy, layout: nil, bands: [])
        )
    }

    func testEncodesEqualizerPresetChanges() {
        let current = EqualizerState(
            preset: .custom,
            layout: .clearBassFive,
            bands: [0, 1, 2, 3, 4, 5]
        )
        XCTAssertEqual(
            XM6PayloadDecoder.equalizerSetPayload(preset: .clear, current: current),
            [0x58, 0x00, 0x31, 0x00]
        )
        XCTAssertEqual(
            XM6PayloadDecoder.equalizerSetPayload(preset: .custom, current: current),
            [0x58, 0x00, 0xa0, 0x06, 10, 11, 12, 13, 14, 15]
        )
        XCTAssertNil(
            XM6PayloadDecoder.equalizerSetPayload(
                preset: .custom,
                current: EqualizerState(preset: .off, layout: nil, bands: [])
            )
        )
    }
}
