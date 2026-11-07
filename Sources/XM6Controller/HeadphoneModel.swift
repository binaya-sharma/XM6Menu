import Foundation

@MainActor
final class HeadphoneModel: ObservableObject {
    @Published private(set) var sonyDevice: SonyHeadphone?
    @Published private(set) var audioOutputs: [AudioOutput] = []
    @Published private(set) var outputVolume: Double?
    @Published private(set) var protocolState = XM6ProtocolState()
    @Published private(set) var isChangingNoiseControl = false
    @Published private(set) var isLoadingProtocol = false
    @Published private(set) var selectedNoiseControl: NoiseControlMode?
    @Published var ambientLevel = 10
    @Published private(set) var isChangingConnection = false
    @Published private(set) var launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    @Published private(set) var launchAtLoginError: String?
    @Published var lastError: String?

    private var timer: Timer?
    private var battery: Int?
    private var started = false
    private var isPopoverVisible = false
    private var isSyncingProtocol = false
    private var controlRevision = 0
    private let protocolCoordinator = XM6ProtocolCoordinator()

    var isConnected: Bool { sonyDevice?.isConnected == true }
    var menuBarLabel: String { sonyDevice?.batteryPercent.map { "\($0)%" } ?? "XM6" }
    var statusMessage: String {
        guard let device = sonyDevice else { return "Waiting for paired headphones" }
        return device.isConnected ? "Connected to this Mac" : "Ready to connect"
    }
    var noiseControlAvailable: Bool { isConnected }
    var batteryStatusText: String {
        guard let device = sonyDevice else { return "Not reported" }
        return protocolState.isCharging && device.batteryPercent != nil
            ? "\(device.batteryText) · Charging"
            : device.batteryText
    }
    var batteryIcon: String {
        if protocolState.isCharging { return "battery.100percent.bolt" }
        return switch sonyDevice?.batteryPercent {
        case .some(76...): "battery.100percent"
        case .some(51...): "battery.75percent"
        case .some(26...): "battery.50percent"
        case .some(1...): "battery.25percent"
        default: "battery.0percent"
        }
    }
    var displayedNoiseControl: NoiseControlMode? {
        selectedNoiseControl ?? protocolState.noiseControlMode
    }
    var wearStatusText: String {
        switch protocolState.isWorn {
        case true: "Worn"
        case false: "Not worn"
        case nil: "Not reported"
        }
    }
    var wearStatusIcon: String {
        switch protocolState.isWorn {
        case true: "ear.fill"
        case false: "ear"
        case nil: "ear"
        }
    }
    var isSonyOutput: Bool {
        guard let name = sonyDevice?.name.lowercased() else { return false }
        return audioOutputs.contains { $0.isDefault && ($0.name.lowercased().contains("xm6") || name.contains($0.name.lowercased())) }
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.isPopoverVisible == true else { return }
                self?.refresh(loadBattery: false)
                self?.syncProtocol(showLoading: false, useSystemBatteryFallback: false)
            }
        }
    }

    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        if visible, started { refresh() }
    }

    func refresh(loadBattery: Bool = true) {
        audioOutputs = AudioDeviceService.outputDevices()
        outputVolume = audioOutputs.first(where: \.isDefault).flatMap { AudioDeviceService.volume(for: $0.id) }
        sonyDevice = BluetoothService.sonyHeadphone(battery: battery)
        if sonyDevice?.isConnected != true {
            protocolState = XM6ProtocolState()
            selectedNoiseControl = nil
        }
        guard loadBattery else { return }
        syncProtocol(showLoading: true, useSystemBatteryFallback: true)
    }

    private func syncProtocol(showLoading: Bool, useSystemBatteryFallback: Bool) {
        guard let device = sonyDevice, device.isConnected else { return }
        guard !isSyncingProtocol, !isChangingNoiseControl, !isChangingConnection else { return }
        isSyncingProtocol = true
        if showLoading { isLoadingProtocol = true }
        let startingRevision = controlRevision
        Task {
            defer {
                isSyncingProtocol = false
                if showLoading { isLoadingProtocol = false }
            }
            let direct: XM6ProtocolState?
            do {
                direct = try await protocolCoordinator.readState(address: device.address)
            } catch {
                direct = nil
                if showLoading { lastError = error.localizedDescription }
            }
            let reported: Int?
            if let protocolBattery = direct?.batteryPercent {
                reported = protocolBattery
            } else if useSystemBatteryFallback {
                reported = await SystemBatteryReader.read(for: device.name)
            } else {
                reported = battery
            }
            guard sonyDevice?.address == device.address else { return }
            if let direct, startingRevision == controlRevision, !isChangingNoiseControl {
                protocolState = direct
                selectedNoiseControl = direct.noiseControlMode
                if let level = direct.ambientLevel { ambientLevel = level }
                lastError = nil
            }
            battery = reported
            sonyDevice = BluetoothService.sonyHeadphone(battery: battery)
        }
    }

    func setNoiseControl(_ mode: NoiseControlMode) {
        guard let device = sonyDevice, device.isConnected, !isChangingNoiseControl, !isLoadingProtocol else { return }
        controlRevision += 1
        let previousSelection = selectedNoiseControl ?? protocolState.noiseControlMode
        selectedNoiseControl = mode
        isChangingNoiseControl = true
        lastError = nil
        let requestedLevel = ambientLevel
        Task {
            do {
                let state = try await protocolCoordinator.setNoiseControl(
                    address: device.address,
                    mode: mode,
                    ambientLevel: requestedLevel
                )
                protocolState = state
                selectedNoiseControl = state.noiseControlMode ?? mode
                if let percent = state.batteryPercent { battery = percent }
                sonyDevice = BluetoothService.sonyHeadphone(battery: battery)
            } catch {
                selectedNoiseControl = previousSelection
                lastError = error.localizedDescription
            }
            isChangingNoiseControl = false
        }
    }

    func toggleConnection() {
        guard let device = sonyDevice, !isChangingConnection else { return }
        let targetConnected = !device.isConnected
        isChangingConnection = true
        lastError = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BluetoothService.setConnected(address: device.address, connected: targetConnected)
                }.value

                var confirmed = false
                for _ in 0..<24 {
                    try? await Task.sleep(for: .milliseconds(250))
                    let updatedDevice = BluetoothService.sonyHeadphone(battery: battery)
                    sonyDevice = updatedDevice
                    if updatedDevice?.address == device.address,
                       updatedDevice?.isConnected == targetConnected {
                        confirmed = true
                        break
                    }
                }
                if !confirmed {
                    lastError = "macOS has not confirmed the Bluetooth change yet. Try Refresh."
                }
            } catch {
                lastError = error.localizedDescription
            }
            isChangingConnection = false
            refresh(loadBattery: targetConnected)
        }
    }

    func selectOutput(_ output: AudioOutput) {
        lastError = nil
        do {
            try AudioDeviceService.setDefaultOutput(output.id)
            audioOutputs = AudioDeviceService.outputDevices()
            outputVolume = AudioDeviceService.volume(for: output.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setVolume(_ value: Double) {
        guard let output = audioOutputs.first(where: \.isDefault) else { return }
        do {
            try AudioDeviceService.setVolume(value, for: output.id)
            outputVolume = value
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sendMediaControl(_ command: MediaControlCommand) {
        lastError = nil
        do {
            try MediaControlService.send(command)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            try LaunchAtLoginService.setEnabled(enabled)
        } catch {
            launchAtLoginError = "Could not update Launch at Login: \(error.localizedDescription)"
        }
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
    }
}
