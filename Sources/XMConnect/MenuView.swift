import MDRKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var controller: HeadphonesController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if controller.isConnected {
                if controller.state.capabilities.hasNoiseControl { noiseControls }
                if let presets = controller.state.equalizerCapability?.presets, !presets.isEmpty {
                    equalizer(presets)
                }
                if controller.state.capabilities.hasPowerOff {
                    Button("Turn off headphones", action: controller.powerOff)
                }
            }

            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 260)
    }

    private var header: some View {
        HStack {
            Text(controller.device?.name ?? "Not connected")
                .font(.headline)
            Spacer()
            if let battery = batteryText {
                Text(battery).foregroundStyle(.secondary)
            }
        }
    }

    private var batteryText: String? {
        switch controller.state.battery {
        case .single(let level), .cradle(let level): "\(level.percent)%"
        case .leftRight(let left, let right): "\(left.percent)% · \(right.percent)%"
        case nil: nil
        }
    }

    private var noiseControls: some View {
        VStack(alignment: .leading, spacing: 8) {
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
