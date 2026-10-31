import Foundation

struct SonyHeadphone: Equatable {
    let name: String
    let address: String
    let isConnected: Bool
    let batteryPercent: Int?

    var batteryText: String {
        batteryPercent.map { "\($0)%" } ?? "Not reported"
    }
}

struct AudioOutput: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let transport: UInt32
    let isDefault: Bool

    var isBluetooth: Bool {
        transport == 0x626C7565 || transport == 0x626C6561 // 'blue' / 'blea'
    }

    var icon: String {
        if isBluetooth { return "headphones" }
        if transport == 0x61697270 { return "airplayaudio" } // 'airp'
        return "speaker.wave.2"
    }
}
