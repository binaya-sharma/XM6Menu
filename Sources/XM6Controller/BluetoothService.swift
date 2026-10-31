import Foundation
import IOBluetooth

enum BluetoothService {
    static func sonyHeadphone(battery: Int?) -> SonyHeadphone? {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let matches = devices.filter { isSupportedXM6(name: $0.nameOrAddress) }
        guard let device = matches.sorted(by: { $0.isConnected() && !$1.isConnected() }).first else { return nil }
        return SonyHeadphone(
            name: device.nameOrAddress,
            address: device.addressString,
            isConnected: device.isConnected(),
            batteryPercent: battery
        )
    }

    static func setConnected(address: String, connected: Bool) throws {
        guard let device = IOBluetoothDevice(addressString: address) else { throw BluetoothError.deviceUnavailable }
        let result = connected ? device.openConnection() : device.closeConnection()
        guard result == kIOReturnSuccess else { throw BluetoothError.operationFailed(result) }
    }

    static func isSupportedXM6(name: String) -> Bool {
        let normalized = name.uppercased().replacingOccurrences(of: " ", with: "")
        return normalized.contains("WH-1000XM6") || normalized.contains("WH1000XM6")
    }
}

enum BluetoothError: LocalizedError {
    case deviceUnavailable
    case operationFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: "The paired headphones are no longer available."
        case .operationFailed(let code): "Bluetooth did not complete the request (error \(code))."
        }
    }
}

/// Battery reporting for third-party Bluetooth headphones is not a stable public API on macOS.
/// This reader uses macOS's own read-only system profile and returns nil when no value is exposed.
enum SystemBatteryReader {
    static func read(for deviceName: String) async -> Int? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "mini"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return findBattery(in: root, matching: deviceName)
            } catch { return nil }
        }.value
    }

    private static func findBattery(in value: Any, matching name: String, insideMatch: Bool = false) -> Int? {
        if let dictionary = value as? [String: Any] {
            let values = dictionary.values.map { String(describing: $0).lowercased() }
            let matched = insideMatch || values.contains(where: { $0.contains(name.lowercased()) })
                || dictionary.keys.contains(where: { $0.lowercased().contains(name.lowercased()) })
            if matched {
                for (key, rawValue) in dictionary where key.lowercased().contains("battery") {
                    if let percent = parsePercent(rawValue) { return percent }
                }
            }
            for child in dictionary.values {
                if let percent = findBattery(in: child, matching: name, insideMatch: matched) { return percent }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let percent = findBattery(in: child, matching: name, insideMatch: insideMatch) { return percent }
            }
        }
        return nil
    }

    private static func parsePercent(_ value: Any) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        let digits = String(describing: value).filter(\.isNumber)
        guard let percent = Int(digits), (0...100).contains(percent) else { return nil }
        return percent
    }
}
