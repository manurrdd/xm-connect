import MDRKit

/// A general-setting slot the device exposes as a switch, under the name it publishes.
public struct MDRSetting: Equatable, Identifiable {
    public let slot: UInt8
    public let name: String
    public var isOn: Bool

    public var id: UInt8 { slot }
}

/// What a connected headset can actually do, taken from the function ids it announces and,
/// where the family provides one, its noise-control capability reply.
public struct MDRCapabilities: Equatable {
    public var batteries: [MDRBatteryKind] = []
    public var hasNoiseCancelling = false
    public var hasAmbientSound = false
    public var hasEqualizer = false
    public var hasPowerOff = false
    public var supportsWindReduction = false
    public var supportsFocusOnVoice = false
    public var ambientSteps = 20
    /// General-setting slots the device announced. What each one holds is only known once its
    /// capability reply arrives.
    public var settingSlots: [UInt8] = []
    public var hasUpscaling = false

    public var hasNoiseControl: Bool { hasNoiseCancelling || hasAmbientSound }

    public init() {}

    init(functions: [UInt8], family: MDRProtocolFamily) {
        let announced = Set(functions)

        switch family {
        case .v1:
            hasNoiseCancelling = announced.contains(0x62) || announced.contains(0x61)
            hasAmbientSound = announced.contains(0x62) || announced.contains(0x63)
            hasEqualizer = announced.contains(0x51) || announced.contains(0x53)
            hasPowerOff = announced.contains(0x21)
            batteries = V1Command.batteryFunctions.filter { announced.contains($0.id) }.map(\.kind)
            settingSlots = V1Command.generalSettingSlots.filter(announced.contains)
            hasUpscaling = announced.contains(0xE2)
        case .v2:
            let variant = functions.compactMap(V2NoiseVariant.forFunction).first
            hasNoiseCancelling = variant?.supportsNoiseCancelling ?? false
            hasAmbientSound = variant != nil
            supportsWindReduction = variant?.supportsWindReduction ?? false
            hasEqualizer = announced.contains(0x50) || announced.contains(0x52) || announced.contains(0x53)
            hasPowerOff = announced.contains(0x23)
            batteries = V2Command.batteryFunctions.filter { announced.contains($0.id) }.map(\.kind)
            settingSlots = V2Command.generalSettingSlots.filter(announced.contains)
        }

        // A device announcing the same layout twice, with and without threshold, must not be
        // queried for it twice.
        batteries = batteries.reduce(into: []) { unique, kind in
            if !unique.contains(kind) { unique.append(kind) }
        }
    }

    mutating func refine(with capability: V1NoiseCapability) {
        supportsWindReduction = capability.ncSettingType == 0x02
        supportsFocusOnVoice = capability.ambientModes.contains { $0.id == 0x01 }
        ambientSteps = capability.ambientModes.map(\.steps).max() ?? ambientSteps
    }
}
