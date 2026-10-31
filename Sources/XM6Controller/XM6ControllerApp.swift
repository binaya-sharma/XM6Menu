import AppKit
import SwiftUI

@main
struct XM6ControllerApp: App {
    @StateObject private var model = HeadphoneModel()

    var body: some Scene {
        MenuBarExtra {
            ControllerPopover()
                .environmentObject(model)
        } label: {
            Label(model.menuBarLabel, systemImage: "s.circle.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

private struct ControllerPopover: View {
    @EnvironmentObject private var model: HeadphoneModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let device = model.sonyDevice {
                deviceCard(device)
            } else {
                emptyState
            }
            Divider()
            listeningLevel
            Divider()
            mediaControls
            Divider()
            outputPicker
            Divider()
            footer
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .task { model.start() }
        .onAppear { model.setPopoverVisible(true) }
        .onDisappear { model.setPopoverVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor).frame(width: 44, height: 44)
                if let image = headerHeadphoneImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                } else {
                    Image(systemName: "headphones")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel("Sony WH-1000XM6")
            VStack(alignment: .leading, spacing: 2) {
                Text("XM6 Controller").font(.headline)
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh devices")
            .accessibilityLabel("Refresh")
            .disabled(model.isLoadingProtocol || model.isChangingNoiseControl)
        }
        .padding(16)
    }

    private var headerHeadphoneImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "XM6ProductRender", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private func deviceCard(_ device: SonyHeadphone) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name).font(.title3.weight(.semibold))
                    Label(device.isConnected ? "Connected" : "Paired", systemImage: device.isConnected ? "checkmark.circle.fill" : "link")
                        .font(.caption)
                        .foregroundStyle(device.isConnected ? .green : .secondary)
                }
                Spacer()
                Button {
                    model.toggleConnection()
                } label: {
                    Group {
                        if model.isChangingConnection {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(device.isConnected ? "Disconnect" : "Connect")
                        }
                    }
                    .frame(width: 72)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.isChangingConnection)
            }

            HStack(spacing: 10) {
                MetricTile(icon: model.batteryIcon, title: "Battery", value: model.isLoadingProtocol ? "Reading…" : model.batteryStatusText)
                MetricTile(icon: "speaker.wave.2.fill", title: "Output", value: model.isSonyOutput ? "Active" : "Inactive")
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Noise Control", systemImage: "waveform.badge.minus")
                    Spacer()
                    if model.isLoadingProtocol {
                        ProgressView().controlSize(.small)
                        Text("Reading…").foregroundStyle(.secondary)
                    } else if model.protocolState.noiseControlMode == nil {
                        Text("Not synced").foregroundStyle(.secondary)
                    } else {
                        Text("Synced").foregroundStyle(.secondary)
                    }
                }
                NoiseControlSelector(
                    selection: model.displayedNoiseControl,
                    isEnabled: model.noiseControlAvailable
                        && !model.isChangingNoiseControl
                        && !model.isLoadingProtocol,
                    action: model.setNoiseControl
                )

                Text(model.displayedNoiseControl?.detail ?? "Choose a listening mode.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.displayedNoiseControl == .ambient {
                    HStack {
                        Text("Ambient level").font(.caption)
                        Slider(value: Binding(
                            get: { Double(model.ambientLevel) },
                            set: { model.ambientLevel = Int($0.rounded()) }
                        ), in: 1...20, step: 1, onEditingChanged: { editing in
                            if !editing { model.setNoiseControl(.ambient) }
                        })
                        Text("\(model.ambientLevel)").font(.caption.monospacedDigit()).frame(width: 20)
                    }
                }
            }
            .font(.caption)
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }

    private var listeningLevel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Listening Level").font(.caption.weight(.semibold))
                Spacer()
                Text(model.outputVolume.map { "\(Int($0 * 100))%" } ?? "Unavailable")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let volume = model.outputVolume {
                HStack(spacing: 9) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { volume }, set: model.setVolume), in: 0...1)
                        .tint(Color.accentColor)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
                if volume >= 0.8 {
                    Label("High output level. Lower it for safer listening.", systemImage: "ear.badge.exclamationmark")
                        .font(.caption).foregroundStyle(.red)
                } else {
                    Text("This is system output volume, not a calibrated dB measurement.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("This output device does not expose volume control to macOS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "headphones.slash").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("No Sony XM headphones found").font(.headline)
            Text("Pair your WH-1000XM6 in System Settings → Bluetooth, then refresh.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var outputPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sound Output").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(model.audioOutputs) { output in
                Button { model.selectOutput(output) } label: {
                    HStack {
                        Image(systemName: output.icon)
                            .frame(width: 20)
                        Text(output.name).lineLimit(1)
                        Spacer()
                        if output.isDefault { Image(systemName: "checkmark").foregroundStyle(.blue) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
        }
        .padding(16)
    }

    private var mediaControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Media").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                mediaButton(.previous, icon: "backward.fill", label: "Previous")
                mediaButton(.playPause, icon: "playpause.fill", label: "Play or Pause")
                mediaButton(.next, icon: "forward.fill", label: "Next")
            }
            .frame(maxWidth: .infinity)
            Label(
                "Requires Accessibility permission to send media keys. The app does not monitor input.",
                systemImage: "hand.raised.fill"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private func mediaButton(_ command: MediaControlCommand, icon: String, label: String) -> some View {
        Button { model.sendMediaControl(command) } label: {
            Image(systemName: icon).frame(width: 32, height: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help(label)
        .accessibilityLabel(label)
    }

    private var footer: some View {
        HStack {
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Open XM6 Controller Settings")
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
        }
        .font(.caption)
        .padding(12)
    }
}

private struct MetricTile: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(.blue).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.medium))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct NoiseControlSelector: View {
    let selection: NoiseControlMode?
    let isEnabled: Bool
    let action: (NoiseControlMode) -> Void

    var body: some View {
        HStack(spacing: 1) {
            ForEach(NoiseControlMode.allCases) { mode in
                Button {
                    action(mode)
                } label: {
                    Text(mode.shortLabel)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == mode ? Color.white : Color.primary)
                .background(selection == mode ? Color.accentColor : Color.clear)
                .disabled(!isEnabled)
                .help(mode.helpText)
                .accessibilityLabel(mode.rawValue)
            }
        }
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .opacity(isEnabled ? 1 : 0.65)
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: HeadphoneModel

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: model.setLaunchAtLogin
                ))
                Text("Start XM6 Controller automatically when you sign in to this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = model.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section("Device") {
                LabeledContent("Headphones", value: model.sonyDevice?.name ?? "Not paired")
                LabeledContent("Connection", value: model.isConnected ? "Connected" : "Disconnected")
                LabeledContent("Battery", value: model.sonyDevice?.batteryText ?? "Unavailable")
            }
            Section("Sony controls") {
                CapabilityRow(name: "Noise cancelling / ambient sound", state: model.noiseControlAvailable ? "Experimental" : "Unavailable", detail: "Uses a local reverse-engineered XM6 Bluetooth protocol; no Sony-supported macOS API exists.")
                CapabilityRow(name: "Equalizer", state: "Unavailable", detail: "Use Sony | Sound Connect; no supported macOS API is available.")
                CapabilityRow(name: "Multipoint", state: "Status only", detail: "macOS can report this Mac’s connection, not manage the headphone’s peer list.")
                CapabilityRow(name: "Wear detection", state: "Unavailable", detail: "Playback sensor events are not exposed through public macOS APIs.")
            }
            Section("Privacy") {
                Text("This app reads locally paired Bluetooth device metadata and the system audio-device list. It does not send device information off your Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
        .onAppear(perform: model.refreshLaunchAtLoginStatus)
    }
}

private struct CapabilityRow: View {
    let name: String
    let state: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(name); Spacer(); Text(state).foregroundStyle(.secondary) }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
