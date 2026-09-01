public enum MDRBatteryKind: UInt8, CaseIterable {
    case single = 0x00
    case leftRight = 0x01
    case cradle = 0x02
}

public enum MDRNoiseMode: Equatable {
    case off
    /// `windReduction` picks the single-microphone mode. Only v1 devices that report dual/single/off
    /// can express it; the v2 payloads have no field for it and ignore the flag.
    case noiseCancelling(windReduction: Bool)
    case ambient(level: Int, focusOnVoice: Bool)
}

/// The setting types a device reported, to be written back unchanged. Models and firmware
/// revisions disagree on the values, so they are read from the device rather than assumed.
public struct V1NoiseSettingTypes: Equatable {
    public let nc: UInt8
    public let asm: UInt8

    public init(_ capability: V1NoiseCapability) {
        nc = capability.ncSettingType
        asm = capability.asmSettingType
    }

    public init(_ state: V1NoiseControl) {
        nc = state.ncSettingType
        asm = state.asmSettingType
    }
}

/// Legacy table (WH-1000XM4 and older).
public enum V1Command {
    /// The combined noise cancelling and ambient sound inquiry, the only one these devices use.
    public static let noiseInquiredType: UInt8 = 0x02

    public static func protocolInfo() -> [UInt8] { [0x00, 0x00] }
    public static func supportFunctions() -> [UInt8] { [0x06, 0x00] }
    public static func noiseCapability() -> [UInt8] { [0x60, noiseInquiredType] }
    public static func noise() -> [UInt8] { [0x66, noiseInquiredType] }
    public static func battery(_ kind: MDRBatteryKind) -> [UInt8] { [0x10, kind.rawValue] }
    public static func equalizer() -> [UInt8] { [0x56, MDRProtocolFamily.v1.equalizerInquiredType] }
    public static func equalizerCapability() -> [UInt8] { equalizerCapabilityCommand(family: .v1) }

    /// Announced function ids and the battery layout each one enables.
    public static let batteryFunctions: [(id: UInt8, kind: MDRBatteryKind)] = [
        (0x11, .single), (0x15, .leftRight), (0x18, .cradle),
    ]

    public static func setNoise(_ mode: MDRNoiseMode, settingTypes: V1NoiseSettingTypes) -> [UInt8] {
        let ncValue: UInt8
        let ambientId: UInt8
        let ambientLevel: UInt8

        switch mode {
        case .off:
            (ncValue, ambientId, ambientLevel) = (0x00, 0x00, 0x00)
        case .noiseCancelling(let windReduction):
            (ncValue, ambientId, ambientLevel) = (windReduction ? 0x01 : 0x02, 0x00, 0x00)
        case .ambient(let level, let focusOnVoice):
            (ncValue, ambientId, ambientLevel) = (0x00, focusOnVoice ? 0x01 : 0x00, clampLevel(level))
        }

        // 0x11 is adjustment complete, which is what the devices themselves report after a change.
        let effect: UInt8 = mode == .off ? 0x00 : 0x11
        return [0x68, noiseInquiredType, effect, settingTypes.nc, ncValue, settingTypes.asm, ambientId, ambientLevel]
    }

    public static func setEqualizerPreset(_ preset: UInt8) -> [UInt8] {
        equalizerPresetCommand(preset, family: .v1)
    }

    public static func setEqualizerBands(preset: UInt8, clearBass: Int?, bands: [Int]) -> [UInt8] {
        equalizerBandsCommand(preset: preset, clearBass: clearBass, bands: bands, family: .v1)
    }

    public static func powerOff() -> [UInt8] { [0x22, 0x00, 0x01] }

    /// The settings that sit behind a general-setting slot, a system inquiry or the audio table.
    /// Which of them a device has is announced as a function id; what each one holds has to be
    /// read from the device.
    public static func generalSettingCapability(slot: UInt8) -> [UInt8] { [0xD0, slot, 0x01] }
    public static func generalSetting(slot: UInt8) -> [UInt8] { [0xD6, slot] }
    public static func systemSetting(_ type: UInt8) -> [UInt8] { [0xF6, type] }
    public static func audioSetting(_ type: UInt8) -> [UInt8] { [0xE6, type] }

    /// The setting type the device reported has to come back with the value. Without it the
    /// WH-1000XM4 acknowledges the write and changes nothing.
    public static func setGeneralSetting(slot: UInt8, settingType: UInt8, isOn: Bool) -> [UInt8] {
        [0xD8, slot, settingType, isOn ? 0x01 : 0x00]
    }

    /// 0x00 selects the automatic mode, which is the only alternative to off.
    public static func setUpscaling(isOn: Bool) -> [UInt8] {
        [0xE8, 0x02, 0x00, isOn ? 0x01 : 0x00]
    }

    public static let generalSettingSlots: [UInt8] = [0xD1, 0xD2, 0xD3]

    /// Announced function ids that map onto a system inquiry.
    public static let systemFunctions: [(id: UInt8, inquiry: UInt8)] = [
        (0xF1, 0x01),  // vibrator
        (0xF2, 0x02),  // power saving mode
        (0xF3, 0x03),  // playback control by wearing
        (0xF4, 0x04),  // auto power off
        (0xF5, 0x05),  // speak-to-chat
        (0xF6, 0x06),  // assignable controls
    ]
}

/// Table used from the WH-1000XM5 onwards.
public enum V2Command {
    public static func protocolInfo() -> [UInt8] { [0x00, 0x00] }
    public static func supportFunctions() -> [UInt8] { [0x06, 0x00] }
    public static func noise(variant: UInt8) -> [UInt8] { [0x66, variant] }
    public static func battery(_ kind: MDRBatteryKind) -> [UInt8] { [0x22, kind.rawValue] }
    public static func equalizer() -> [UInt8] { [0x56, MDRProtocolFamily.v2.equalizerInquiredType] }
    public static func equalizerCapability() -> [UInt8] { equalizerCapabilityCommand(family: .v2) }

    /// Announced function ids and the battery layout each one enables. The second row is the same
    /// three layouts reported with a low-battery threshold appended.
    public static let batteryFunctions: [(id: UInt8, kind: MDRBatteryKind)] = [
        (0x20, .single), (0x21, .leftRight), (0x22, .cradle),
        (0x28, .single), (0x29, .leftRight), (0x2A, .cradle),
    ]

    /// Wire variant to use with `noise(variant:)` and `setNoise`, from the announced function id.
    public static func noiseVariant(forFunction id: UInt8) -> UInt8? {
        switch id {
        case 0x6B: 0x17
        case 0x6D: 0x19
        case 0x67: 0x22
        default: nil
        }
    }

    public static func setNoise(_ mode: MDRNoiseMode, variant: UInt8) -> [UInt8] {
        let effect: UInt8 = mode == .off ? 0x00 : 0x01
        var ambientMode: UInt8 = 0x00
        var focusOnVoice: UInt8 = 0x00
        var level: UInt8 = 0x00
        if case .ambient(let requested, let voice) = mode {
            (ambientMode, focusOnVoice, level) = (0x01, voice ? 0x01 : 0x00, clampLevel(requested))
        }

        // 0x01 is value-changed, which every variant carries after the inquiry byte.
        switch variant {
        case 0x22:
            // Ambient-only devices: no noise cancelling, so no mode byte either.
            return [0x68, variant, 0x01, effect, focusOnVoice, level]
        case 0x19:
            // Trailing bytes turn noise adaptation off at standard sensitivity.
            return [0x68, variant, 0x01, effect, ambientMode, focusOnVoice, level, 0x00, 0x00]
        default:
            return [0x68, variant, 0x01, effect, ambientMode, focusOnVoice, level]
        }
    }

    public static func setEqualizerPreset(_ preset: UInt8) -> [UInt8] {
        equalizerPresetCommand(preset, family: .v2)
    }

    public static func setEqualizerBands(preset: UInt8, clearBass: Int?, bands: [Int]) -> [UInt8] {
        equalizerBandsCommand(preset: preset, clearBass: clearBass, bands: bands, family: .v2)
    }

    public static func powerOff() -> [UInt8] { [0x24, 0x03, 0x01] }
}

private func clampLevel(_ level: Int) -> UInt8 {
    UInt8(min(20, max(1, level)))
}
