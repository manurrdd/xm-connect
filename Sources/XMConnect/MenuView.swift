import MDRKit
import MDRSession
import XMConnectCore
import SwiftUI

/// The controls themselves, shown both in the menu bar panel and in a window.
struct ControlsView: View {
    @ObservedObject var controller: HeadphonesController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if controller.hasReading {
                connected.disabled(!controller.isLive)
            } else {
                searching
            }
        }
    }

    private var searching: some View {
        VStack(spacing: 8) {
            Image(systemName: "headphones")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(controller.isOffline ? "Headphones not connected" : "Looking for headphones")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
        }
    }

    @ViewBuilder
    private var controls: some View {
        header

        if controller.state.capabilities.hasNoiseControl {
            noiseControls
        }

        if let presets = controller.state.equalizerCapability?.presets, !presets.isEmpty {
            equalizer(presets)
        }

        if hasDeviceSettings {
            Divider()
            deviceSettings
        }

        if controller.state.capabilities.hasPowerOff {
            Button("Turn off headphones", action: controller.powerOff)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(controller.device?.name ?? "")
                .font(.headline)
            Spacer()
            battery
        }
    }

    @ViewBuilder
    private var battery: some View {
        if let text = batteryText {
            HStack(spacing: 3) {
                if isCharging {
                    Image(systemName: "bolt.fill").imageScale(.small)
                }
                Text(text)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var batteryText: String? {
        var parts: [String] = []
        switch controller.state.battery {
        case .single(let level), .cradle(let level): parts.append("\(level.percent)%")
        case .leftRight(let left, let right): parts.append("\(left.percent)% · \(right.percent)%")
        case nil: break
        }
        if let caseLevel = controller.state.caseBattery {
            parts.append("case \(caseLevel.percent)%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var isCharging: Bool {
        let levels: [MDRBatteryLevel]
        switch controller.state.battery {
        case .single(let level), .cradle(let level): levels = [level]
        case .leftRight(let left, let right): levels = [left, right]
        case nil: levels = []
        }
        return (levels + [controller.state.caseBattery].compactMap { $0 }).contains { $0.charging == .charging }
    }

    private var noiseControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: noiseSelection) {
                Text("Off").tag(NoiseSelection.off)
                if controller.state.capabilities.hasNoiseCancelling {
                    Text("Cancelling").tag(NoiseSelection.noiseCancelling)
                }
                if controller.state.capabilities.supportsWindReduction {
                    Text("Wind").tag(NoiseSelection.windReduction)
                }
                if controller.state.capabilities.hasAmbientSound {
                    Text("Ambient").tag(NoiseSelection.ambient)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if case .ambient(let level, let focusOnVoice) = controller.state.noise {
                Slider(
                    value: Binding(
                        get: { Double(level) },
                        set: { controller.setNoise(.ambient(level: Int($0), focusOnVoice: focusOnVoice)) }
                    ),
                    in: 1...Double(controller.state.capabilities.ambientSteps),
                    step: 1
                )

                if controller.state.capabilities.supportsFocusOnVoice {
                    Toggle("Focus on voice", isOn: Binding(
                        get: { focusOnVoice },
                        set: { controller.setNoise(.ambient(level: level, focusOnVoice: $0)) }
                    ))
                }
            }
        }
    }

    private func equalizer(_ presets: [MDREqualizerCapability.Preset]) -> some View {
        Picker("Equalizer", selection: Binding(
            get: { controller.state.equalizer?.preset ?? presets[0].id },
            set: { controller.setEqualizerPreset($0) }
        )) {
            ForEach(presets, id: \.id) { preset in
                Text(preset.displayName).tag(preset.id)
            }
        }
    }

    private var hasDeviceSettings: Bool {
        !controller.state.settings.isEmpty
            || !controller.state.systemSwitches.isEmpty
            || controller.state.upscaling != nil
            || controller.state.autoPowerOff != nil
    }

    private var deviceSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(controller.state.settings) { setting in
                Toggle(setting.name, isOn: Binding(
                    get: { setting.isOn },
                    set: { controller.setSetting(slot: setting.slot, isOn: $0) }
                ))
            }

            ForEach(MDRSystemSwitch.allCases, id: \.rawValue) { setting in
                if let isOn = controller.state.systemSwitches[setting] {
                    Toggle(setting.name, isOn: Binding(
                        get: { isOn },
                        set: { controller.setSystemSwitch(setting, isOn: $0) }
                    ))
                }
            }

            if let upscaling = controller.state.upscaling {
                Toggle("DSEE", isOn: Binding(
                    get: { upscaling },
                    set: { controller.setUpscaling($0) }
                ))
            }

            if let autoPowerOff = controller.state.autoPowerOff {
                Picker("Power off", selection: Binding(
                    get: { autoPowerOff.active },
                    set: { controller.setAutoPowerOff($0) }
                )) {
                    ForEach(MDRAutoPowerOff.allCases, id: \.rawValue) { value in
                        Text(value.name).tag(value)
                    }
                }
            }
        }
    }

    private var noiseSelection: Binding<NoiseSelection> {
        Binding(
            get: { NoiseSelection(controller.state.noise) },
            set: { controller.setNoise($0.mode(ambientLevel: currentAmbientLevel)) }
        )
    }

    private var currentAmbientLevel: Int {
        if case .ambient(let level, _) = controller.state.noise { return level }
        return controller.state.capabilities.ambientSteps
    }
}

struct MenuView: View {
    @ObservedObject var controller: HeadphonesController
    @StateObject private var launchAtLogin = LaunchAtLogin()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ControlsView(controller: controller)

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 268)
        .background(PanelVisibility(
            onOpen: {
                launchAtLogin.refresh()
                controller.acquire()
            },
            onClose: controller.relinquish
        ))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: launchAtLogin.set
            ))
            .toggleStyle(.checkbox)
            .font(.callout)

            Spacer()

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: XMConnectApp.windowID)
            } label: {
                Image(systemName: "macwindow")
            }
            .help("Open window")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit")
            .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .foregroundStyle(.secondary)
    }
}

struct WindowView: View {
    @ObservedObject var controller: HeadphonesController

    var body: some View {
        ControlsView(controller: controller)
            .padding(20)
            .frame(width: 300)
            .onAppear(perform: controller.acquire)
            .onDisappear(perform: controller.relinquish)
    }
}

private enum NoiseSelection: Hashable {
    case off, noiseCancelling, windReduction, ambient

    init(_ mode: MDRNoiseMode?) {
        switch mode {
        case .noiseCancelling(let wind): self = wind ? .windReduction : .noiseCancelling
        case .ambient: self = .ambient
        default: self = .off
        }
    }

    func mode(ambientLevel: Int) -> MDRNoiseMode {
        switch self {
        case .off: .off
        case .noiseCancelling: .noiseCancelling(windReduction: false)
        case .windReduction: .noiseCancelling(windReduction: true)
        case .ambient: .ambient(level: ambientLevel, focusOnVoice: false)
        }
    }
}
