import AppKit
@preconcurrency import ApplicationServices
import IOKit.hidsystem

enum MediaControlCommand {
    case previous
    case playPause
    case next

    fileprivate var keyCode: Int32 {
        switch self {
        case .playPause: NX_KEYTYPE_PLAY
        case .next: NX_KEYTYPE_NEXT
        case .previous: NX_KEYTYPE_PREVIOUS
        }
    }
}

enum MediaControlError: LocalizedError {
    case accessibilityRequired
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            "Allow XM6 Controller in System Settings > Privacy & Security > Accessibility, then try again."
        case .eventCreationFailed:
            "macOS could not create the media-control event."
        }
    }
}

enum MediaControlService {
    static func send(_ command: MediaControlCommand) throws {
        guard AXIsProcessTrusted() else {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            throw MediaControlError.accessibilityRequired
        }

        try post(command.keyCode, keyDown: true)
        try post(command.keyCode, keyDown: false)
    }

    private static func post(_ keyCode: Int32, keyDown: Bool) throws {
        let keyState = keyDown ? 0x0a : 0x0b
        let data1 = (Int(keyCode) << 16) | (keyState << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyState << 8)),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent else {
            throw MediaControlError.eventCreationFailed
        }
        event.post(tap: .cghidEventTap)
    }
}
