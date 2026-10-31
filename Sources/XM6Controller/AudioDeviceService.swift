import CoreAudio
import Foundation

enum AudioDeviceService {
    // Audio Hardware Services' virtual-main selector. It maps a single slider to a
    // device's preferred stereo channels when no hardware main-volume element exists.
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766d7663 // 'vmvc'

    static func volume(for id: AudioObjectID) -> Double? {
        if let address = virtualVolumeAddress(for: id), let value = readVolume(id, address: address) {
            return Double(value)
        }
        let values = channelVolumeAddresses(for: id).compactMap { readVolume(id, address: $0) }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +) / Float32(values.count))
    }

    static func setVolume(_ volume: Double, for id: AudioObjectID) throws {
        var value = Float32(min(max(volume, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        if var address = virtualVolumeAddress(for: id) {
            let status = AudioObjectSetPropertyData(id, &address, 0, nil, size, &value)
            guard status == noErr else { throw AudioError.status(status) }
            return
        }

        let addresses = channelVolumeAddresses(for: id)
        guard !addresses.isEmpty else { throw AudioError.volumeUnavailable }
        for var address in addresses {
            let status = AudioObjectSetPropertyData(id, &address, 0, nil, size, &value)
            guard status == noErr else { throw AudioError.status(status) }
        }
    }

    static func outputDevices() -> [AudioOutput] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let defaultID: AudioObjectID? = readUInt32(
            object: system,
            selector: kAudioHardwarePropertyDefaultOutputDevice
        )

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = Array(repeating: AudioObjectID(0), count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutputStreams(id), let name = readString(object: id, selector: kAudioObjectPropertyName) else { return nil }
            let transport = readUInt32(object: id, selector: kAudioDevicePropertyTransportType) ?? 0
            return AudioOutput(id: id, name: name, transport: transport, isDefault: id == defaultID)
        }
        .sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func setDefaultOutput(_ id: AudioObjectID) throws {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = id
        let status = AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value)
        guard status == noErr else { throw AudioError.status(status) }

        // Keep alerts and other system sounds on the same device when macOS permits it.
        address.mSelector = kAudioHardwarePropertyDefaultSystemOutputDevice
        _ = AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value)
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func virtualVolumeAddress(for id: AudioObjectID) -> AudioObjectPropertyAddress? {
        for scope in [kAudioObjectPropertyScopeOutput, kAudioObjectPropertyScopeGlobal] {
            var address = AudioObjectPropertyAddress(
                mSelector: virtualMainVolume,
                mScope: scope,
                mElement: kAudioObjectPropertyElementMain
            )
            if isSettable(id, address: &address), readVolume(id, address: address) != nil { return address }
        }
        return nil
    }

    private static func channelVolumeAddresses(for id: AudioObjectID) -> [AudioObjectPropertyAddress] {
        var addresses: [AudioObjectPropertyAddress] = []
        for scope in [kAudioObjectPropertyScopeOutput, kAudioObjectPropertyScopeGlobal] {
            for element in UInt32(0)...32 {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: scope,
                    mElement: element
                )
                if isSettable(id, address: &address), readVolume(id, address: address) != nil {
                    addresses.append(address)
                }
            }
            if !addresses.isEmpty { break }
        }
        return addresses
    }

    private static func readVolume(_ id: AudioObjectID, address: AudioObjectPropertyAddress) -> Float32? {
        var address = address
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(id, &address),
              AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func isSettable(_ id: AudioObjectID, address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(id, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    private static func readString(object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeUnretainedValue() as String
    }

    private static func readUInt32(object: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}

enum AudioError: LocalizedError {
    case status(OSStatus)
    case volumeUnavailable
    var errorDescription: String? {
        switch self {
        case .status(let status): "macOS could not change the audio setting (error \(status))."
        case .volumeUnavailable: "This output does not expose a writable volume control to macOS."
        }
    }
}
