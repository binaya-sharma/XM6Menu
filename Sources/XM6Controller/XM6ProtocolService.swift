import Foundation
import IOBluetooth
import OSLog

enum NoiseControlMode: String, CaseIterable, Identifiable, Sendable {
    case noiseCancelling = "Noise Cancelling"
    case ambient = "Ambient"
    case off = "Off"

    var id: Self { self }

    var shortLabel: String {
        switch self {
        case .noiseCancelling: "ANC"
        case .ambient: "AMB"
        case .off: "OFF"
        }
    }

    var detail: String {
        switch self {
        case .noiseCancelling: "Reduces surrounding noise."
        case .ambient: "Lets outside sound through."
        case .off: "ANC and ambient sound are both off."
        }
    }

    var helpText: String {
        switch self {
        case .noiseCancelling: "Enable active noise cancelling"
        case .ambient: "Enable ambient sound"
        case .off: "Turn off noise cancelling and ambient sound"
        }
    }
}

struct XM6ProtocolState: Equatable, Sendable {
    var batteryPercent: Int?
    var isCharging = false
    var noiseControlMode: NoiseControlMode?
    var ambientLevel: Int?
    var isWorn: Bool?
    var equalizer: EqualizerState?
}

enum XM6ProtocolError: LocalizedError {
    case deviceUnavailable
    case serviceUnavailable
    case channelUnavailable(IOReturn)
    case writeFailed(IOReturn)
    case timedOut
    case invalidFrame
    case unexpectedResponse
    case equalizerUnavailable

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: "The XM6 is no longer available."
        case .serviceUnavailable: "The XM6 control service was not found. Keep audio playing and try again."
        case .channelUnavailable(let code): "Could not open the XM6 control channel (error \(code))."
        case .writeFailed(let code): "Could not send the XM6 command (error \(code))."
        case .timedOut: "The XM6 did not answer the control request."
        case .invalidFrame: "The XM6 returned an invalid control frame."
        case .unexpectedResponse: "The XM6 returned an unexpected control response."
        case .equalizerUnavailable: "The XM6 did not report usable equalizer settings."
        }
    }
}

/// Minimal, local-only implementation of the Sony v2 protocol used by WH-1000XM6.
/// It intentionally supports only battery, noise control, wear status, and equalizer presets;
/// no third-party code runs at runtime.
enum XM6ProtocolService {
    static func readState(address: String) throws -> XM6ProtocolState {
        try withRetry(address: address) { session in
            try session.initialize()
            return try session.readState()
        }
    }

    static func setNoiseControl(address: String, mode: NoiseControlMode, ambientLevel: Int) throws -> XM6ProtocolState {
        try withRetry(address: address) { session in
            try session.initialize()
            try session.setNoiseControl(mode: mode, ambientLevel: ambientLevel)
            return try session.readState()
        }
    }

    static func setEqualizerPreset(
        address: String,
        preset: EqualizerPreset,
        current: EqualizerState
    ) throws -> XM6ProtocolState {
        try withRetry(address: address) { session in
            try session.initialize()
            try session.setEqualizerPreset(preset, current: current)
            return try session.readState()
        }
    }

    private static func withRetry<T>(
        address: String,
        operation: (XM6RFCOMMSession) throws -> T
    ) throws -> T {
        var lastError: Error = XM6ProtocolError.timedOut
        for attempt in 0..<3 {
            do {
                let session = try XM6RFCOMMSession(address: address)
                defer { session.close() }
                return try operation(session)
            } catch {
                lastError = error
                guard isRetryable(error), attempt < 2 else { throw error }
                Thread.sleep(forTimeInterval: 0.25 * Double(attempt + 1))
            }
        }
        throw lastError
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let protocolError = error as? XM6ProtocolError else { return false }
        switch protocolError {
        case .channelUnavailable, .writeFailed, .timedOut, .invalidFrame, .unexpectedResponse:
            return true
        case .deviceUnavailable, .serviceUnavailable, .equalizerUnavailable:
            return false
        }
    }
}

enum XM6PayloadDecoder {
    static func wearState(from payload: [UInt8]) -> Bool? {
        guard payload.count >= 3,
              payload[0] == 0xf3 || payload[0] == 0xf5,
              payload[1] == 0x10 else {
            return nil
        }
        return payload.last == 0x00
    }

    static func equalizerState(from payload: [UInt8]) -> EqualizerState? {
        guard payload.count >= 4,
              payload[0] == 0x57 || payload[0] == 0x59,
              payload[1] == 0x00,
              let preset = EqualizerPreset(rawValue: payload[2]) else {
            return nil
        }
        let count = Int(payload[3])
        guard payload.count >= 4 + count else { return nil }
        let layout: EqualizerLayout?
        switch count {
        case 6: layout = .clearBassFive
        case 10: layout = .graphicTen
        default: layout = nil
        }
        guard let layout else {
            return EqualizerState(preset: preset, layout: nil, bands: [])
        }
        let bands = payload[4..<(4 + count)].map { Int($0) - layout.wireOffset }
        guard bands.allSatisfy(layout.range.contains) else { return nil }
        return EqualizerState(preset: preset, layout: layout, bands: bands)
    }

    static func equalizerSetPayload(
        preset: EqualizerPreset,
        current: EqualizerState
    ) -> [UInt8]? {
        if preset == .custom {
            guard let layout = current.layout,
                  current.bands.count == layout.labels.count,
                  current.bands.allSatisfy(layout.range.contains),
                  current.bands.count <= Int(UInt8.max) else {
                return nil
            }
            let encoded = current.bands.map { UInt8($0 + layout.wireOffset) }
            return [0x58, 0x00, preset.rawValue, UInt8(encoded.count)] + encoded
        }
        return [0x58, 0x00, preset.rawValue, 0x00]
    }
}

/// Serializes access to the XM6's single RFCOMM control service. Concurrent refresh and
/// button requests otherwise compete for the same channel and make the UI appear erratic.
actor XM6ProtocolCoordinator {
    func readState(address: String) throws -> XM6ProtocolState {
        try XM6ProtocolService.readState(address: address)
    }

    func setNoiseControl(address: String, mode: NoiseControlMode, ambientLevel: Int) throws -> XM6ProtocolState {
        try XM6ProtocolService.setNoiseControl(address: address, mode: mode, ambientLevel: ambientLevel)
    }

    func setEqualizerPreset(
        address: String,
        preset: EqualizerPreset,
        current: EqualizerState
    ) throws -> XM6ProtocolState {
        try XM6ProtocolService.setEqualizerPreset(address: address, preset: preset, current: current)
    }
}

struct SonyFrame: Equatable {
    let type: UInt8
    let sequence: UInt8
    let payload: [UInt8]
}

enum SonyFrameCodec {
    static func encode(payload: [UInt8], type: UInt8 = 0x0c, sequence: UInt8) -> [UInt8] {
        let length = UInt32(payload.count)
        var body: [UInt8] = [
            type,
            sequence,
            UInt8(truncatingIfNeeded: length >> 24),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length)
        ]
        body.append(contentsOf: payload)
        body.append(body.reduce(0, &+))
        var escaped: [UInt8] = []
        for byte in body {
            switch byte {
            case 0x3c: escaped.append(contentsOf: [0x3d, 0x2c])
            case 0x3d: escaped.append(contentsOf: [0x3d, 0x2d])
            case 0x3e: escaped.append(contentsOf: [0x3d, 0x2e])
            default: escaped.append(byte)
            }
        }
        return [0x3e] + escaped + [0x3c]
    }

    static func decode(_ framed: [UInt8]) throws -> SonyFrame {
        guard framed.first == 0x3e, framed.last == 0x3c else { throw XM6ProtocolError.invalidFrame }
        var body: [UInt8] = []
        var index = 1
        while index < framed.count - 1 {
            let byte = framed[index]
            if byte == 0x3d {
                index += 1
                guard index < framed.count - 1 else { throw XM6ProtocolError.invalidFrame }
                switch framed[index] {
                case 0x2c: body.append(0x3c)
                case 0x2d: body.append(0x3d)
                case 0x2e: body.append(0x3e)
                default: throw XM6ProtocolError.invalidFrame
                }
            } else {
                body.append(byte)
            }
            index += 1
        }
        guard body.count >= 7 else { throw XM6ProtocolError.invalidFrame }
        let length = Int(body[2]) << 24 | Int(body[3]) << 16 | Int(body[4]) << 8 | Int(body[5])
        guard body.count == length + 7, body.last == body.dropLast().reduce(0, &+) else {
            throw XM6ProtocolError.invalidFrame
        }
        return SonyFrame(type: body[0], sequence: body[1], payload: Array(body[6..<(6 + length)]))
    }
}

private final class XM6RFCOMMSession: NSObject, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.binaya.XM6Controller", category: "XM6Protocol")
    private static let maximumReceiveBufferSize = 64 * 1024
    private static let serviceUUID: [UInt8] = [
        0x95, 0x6c, 0x7b, 0x26, 0xd4, 0x9a, 0x4b, 0xa8,
        0xb0, 0x3f, 0xb1, 0x7d, 0x39, 0x3c, 0xb6, 0xe2
    ]

    private let receiveLock = NSLock()
    private let writeLock = NSLock()
    private var received: [UInt8] = []
    private var channel: IOBluetoothRFCOMMChannel?
    private var sequence: UInt8 = 0
    private var openStatus: IOReturn?
    private var writeStatus: IOReturn?

    init(address: String) throws {
        guard let device = IOBluetoothDevice(addressString: address) else { throw XM6ProtocolError.deviceUnavailable }
        let uuid = Self.serviceUUID.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        guard let record = device.getServiceRecord(for: uuid) else { throw XM6ProtocolError.serviceUnavailable }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { throw XM6ProtocolError.serviceUnavailable }
        Self.logger.info("Opening RFCOMM channel \(channelID, privacy: .public)")
        super.init()
        var opened: IOBluetoothRFCOMMChannel?
        // IOBluetooth's synchronous opener returns kIOReturnError for the XM6 v2 service on
        // current macOS releases. The asynchronous API requires this thread's run loop to be
        // pumped until the delegate reports completion.
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
        guard result == kIOReturnSuccess, let opened else { throw XM6ProtocolError.channelUnavailable(result) }
        channel = opened
        let deadline = Date().addingTimeInterval(5)
        while openStatus == nil, !opened.isOpen(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.05)))
        }
        if let openStatus, openStatus != kIOReturnSuccess {
            close()
            throw XM6ProtocolError.channelUnavailable(openStatus)
        }
        guard opened.isOpen() else {
            close()
            throw XM6ProtocolError.timedOut
        }
        Self.logger.info("RFCOMM open; MTU=\(opened.getMTU(), privacy: .public)")
        // The open-complete callback can arrive just before RFCOMM enables its transmit queue.
        // Pump for the full settling interval. A single RunLoop.run call may return immediately
        // after handling a callback, which previously let button commands write too early.
        pumpRunLoop(for: 0.2)
    }

    func initialize() throws {
        _ = try transact([0x00, 0x00], expecting: 0x01, subtype: nil)
    }

    func readState() throws -> XM6ProtocolState {
        var state = XM6ProtocolState()
        let battery = try transact([0x22, 0x00], expecting: 0x23, subtype: 0x00)
        if battery.count >= 4 {
            state.batteryPercent = min(100, Int(battery[2]))
            state.isCharging = battery[3] == 1
        }
        let noise = try transact([0x66, 0x19], expecting: 0x67, subtype: 0x19)
        if noise.count >= 7, noise[2] == 1 {
            if noise[3] == 0 {
                state.noiseControlMode = .off
            } else if noise[4] == 0 {
                state.noiseControlMode = .noiseCancelling
            } else {
                state.noiseControlMode = .ambient
                state.ambientLevel = max(1, min(20, Int(noise[6])))
            }
        }
        if let wear = try? transact([0xf2, 0x10], expecting: 0xf3, subtype: 0x10) {
            state.isWorn = XM6PayloadDecoder.wearState(from: wear)
        }
        if let equalizer = try? transact([0x56, 0x00], expecting: 0x57, subtype: 0x00) {
            state.equalizer = XM6PayloadDecoder.equalizerState(from: equalizer)
        }
        return state
    }

    func setNoiseControl(mode: NoiseControlMode, ambientLevel: Int) throws {
        let on: UInt8 = mode == .off ? 0 : 1
        let setting: UInt8 = mode == .ambient ? 1 : 0
        let level = UInt8(max(1, min(20, ambientLevel)))
        try sendAndWaitForAck([0x68, 0x17, 0x01, on, setting, 0x00, level])
    }

    func setEqualizerPreset(_ preset: EqualizerPreset, current: EqualizerState) throws {
        guard let payload = XM6PayloadDecoder.equalizerSetPayload(preset: preset, current: current) else {
            throw XM6ProtocolError.equalizerUnavailable
        }
        try sendAndWaitForAck(payload)
        pumpRunLoop(for: 0.1)
    }

    func close() {
        guard let closingChannel = channel else { return }
        _ = closingChannel.close()
        let deadline = Date().addingTimeInterval(1)
        while closingChannel.isOpen(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.05)))
        }
        closingChannel.setDelegate(nil)
        channel = nil
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0, dataLength <= Self.maximumReceiveBufferSize else {
            Self.logger.error("Discarding invalid RFCOMM chunk length=\(dataLength, privacy: .public)")
            return
        }
        let bytes = Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        Self.logger.debug("RX \(bytes.hexString, privacy: .private(mask: .hash))")
        receiveLock.lock()
        received.append(contentsOf: bytes)
        if received.count > Self.maximumReceiveBufferSize {
            let overflow = received.count - Self.maximumReceiveBufferSize
            received.removeFirst(overflow)
            Self.logger.error("Trimmed oversized RFCOMM receive buffer")
        }
        receiveLock.unlock()
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        Self.logger.info("RFCOMM open callback status=\(error, privacy: .public)")
        openStatus = error
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        Self.logger.info("RFCOMM closed by remote")
    }

    func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        refcon: UnsafeMutableRawPointer!,
        status error: IOReturn
    ) {
        recordWriteCompletion(error)
    }

    func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        refcon: UnsafeMutableRawPointer!,
        status error: IOReturn,
        bytesWritten length: Int
    ) {
        recordWriteCompletion(error)
    }

    private func transact(_ payload: [UInt8], expecting command: UInt8, subtype: UInt8?) throws -> [UInt8] {
        try write(SonyFrameCodec.encode(payload: payload, sequence: sequence))
        for _ in 0..<16 {
            let frame = try readFrame()
            if frame.type == 0x01 {
                sequence = frame.sequence
                continue
            }
            try acknowledge(frame)
            if frame.type == 0x0c,
               frame.payload.first == command,
               subtype == nil || (frame.payload.count > 1 && frame.payload[1] == subtype) {
                return frame.payload
            }
        }
        throw XM6ProtocolError.unexpectedResponse
    }

    private func sendAndWaitForAck(_ payload: [UInt8]) throws {
        try write(SonyFrameCodec.encode(payload: payload, sequence: sequence))
        for _ in 0..<16 {
            let frame = try readFrame()
            if frame.type == 0x01 {
                sequence = frame.sequence
                return
            }
            try acknowledge(frame)
        }
        throw XM6ProtocolError.unexpectedResponse
    }

    private func acknowledge(_ frame: SonyFrame) throws {
        guard frame.type == 0x0c || frame.type == 0x0e else { return }
        try write(SonyFrameCodec.encode(payload: [], type: 0x01, sequence: 1 - (frame.sequence & 1)))
    }

    private func write(_ bytes: [UInt8]) throws {
        guard let channel else { throw XM6ProtocolError.deviceUnavailable }
        guard bytes.count <= Int(UInt16.max) else { throw XM6ProtocolError.invalidFrame }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bytes.count, alignment: 1)
        bytes.withUnsafeBytes { source in
            if let baseAddress = source.baseAddress {
                buffer.copyMemory(from: baseAddress, byteCount: bytes.count)
            }
        }
        defer { buffer.deallocate() }

        writeLock.lock()
        writeStatus = nil
        writeLock.unlock()
        let queued = channel.writeAsync(buffer, length: UInt16(bytes.count), refcon: nil)
        Self.logger.debug("TX queued \(bytes.hexString, privacy: .private(mask: .hash)) status=\(queued, privacy: .public)")
        guard queued == kIOReturnSuccess else { throw XM6ProtocolError.writeFailed(queued) }

        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            writeLock.lock()
            let completion = writeStatus
            writeLock.unlock()
            if let completion {
                Self.logger.info("TX completion status=\(completion, privacy: .public)")
                guard completion == kIOReturnSuccess else { throw XM6ProtocolError.writeFailed(completion) }
                return
            }
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.05)))
        }
        channel.close()
        throw XM6ProtocolError.timedOut
    }

    private func recordWriteCompletion(_ status: IOReturn) {
        writeLock.lock()
        writeStatus = status
        writeLock.unlock()
    }

    private func readFrame() throws -> SonyFrame {
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            receiveLock.lock()
            if let start = received.firstIndex(of: 0x3e), start + 1 < received.count,
               let end = received[(start + 1)...].firstIndex(of: 0x3c) {
                let bytes = Array(received[start...end])
                received.removeSubrange(...end)
                receiveLock.unlock()
                return try SonyFrameCodec.decode(bytes)
            }
            receiveLock.unlock()
            // IOBluetooth delivers RFCOMM delegate callbacks on the run loop that opened the channel.
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.05)))
        }
        Self.logger.error("Timed out waiting for frame; bufferedBytes=\(self.received.count, privacy: .public)")
        throw XM6ProtocolError.timedOut
    }

    private func pumpRunLoop(for interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.02)))
        }
    }
}

private extension Array where Element == UInt8 {
    var hexString: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
