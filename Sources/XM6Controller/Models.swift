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

enum EqualizerPreset: UInt8, CaseIterable, Identifiable, Sendable {
    case off = 0x00
    case heavy = 0x30
    case clear = 0x31
    case hard = 0x32
    case soft = 0x33
    case custom = 0xa0

    var id: Self { self }

    var label: String {
        switch self {
        case .off: "Off"
        case .heavy: "Heavy"
        case .clear: "Clear"
        case .hard: "Hard"
        case .soft: "Soft"
        case .custom: "Custom Bands"
        }
    }
}

struct EqualizerState: Equatable, Sendable {
    let preset: EqualizerPreset
    let layout: EqualizerLayout?
    let bands: [Int]
}

enum EqualizerLayout: Equatable, Sendable {
    case clearBassFive
    case graphicTen

    var labels: [String] {
        switch self {
        case .clearBassFive:
            ["Clear Bass", "400 Hz", "1 kHz", "2.5 kHz", "6.3 kHz", "16 kHz"]
        case .graphicTen:
            ["31 Hz", "63 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"]
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .clearBassFive: -10...10
        case .graphicTen: -6...6
        }
    }

    var wireOffset: Int {
        switch self {
        case .clearBassFive: 10
        case .graphicTen: 6
        }
    }

    var title: String {
        switch self {
        case .clearBassFive: "6 bands"
        case .graphicTen: "10 bands"
        }
    }
}
