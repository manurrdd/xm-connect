/// The eight-byte v1 noise-control payload, kept field by field.
///
/// `ncSettingType`, `asmSettingType` and `asmId` are echoed back unchanged when writing: models
/// and firmware revisions disagree on the values, and the device's own reply is the only reliable
/// source. A WH-1000XM4 reports `02` where two published implementations hardcode `01`.
public struct V1NoiseControl: Equatable {
    public let effect: UInt8
    public let ncSettingType: UInt8
    public let ncValue: UInt8
    public let asmSettingType: UInt8
    public let asmId: UInt8
    public let asmLevel: UInt8

    public init?(payload: [UInt8]) {
        guard payload.count >= 8,
              payload[0] == 0x67 || payload[0] == 0x69,
              payload[1] == V1Command.noiseInquiredType
        else { return nil }
        effect = payload[2]
        ncSettingType = payload[3]
        ncValue = payload[4]
        asmSettingType = payload[5]
        asmId = payload[6]
        asmLevel = payload[7]
    }
}

/// What the device says its noise control can do. The setting types here are the ones a write
/// has to carry, and the ambient list gives the modes and how many levels each one has.
public struct V1NoiseCapability: Equatable {
    public struct AmbientMode: Equatable {
        /// `00` normal, `01` focus on voice.
        public let id: UInt8
        public let steps: Int
    }

    public let ncSettingType: UInt8
    public let ncStep: Int
    public let asmSettingType: UInt8
    public let ambientModes: [AmbientMode]

    public init?(payload: [UInt8]) {
        guard payload.count >= 6,
              payload[0] == 0x61,
              payload[1] == V1Command.noiseInquiredType
        else { return nil }

        let count = Int(payload[5])
        guard payload.count >= 6 + count * 2 else { return nil }

        ncSettingType = payload[2]
        ncStep = Int(payload[3])
        asmSettingType = payload[4]
        ambientModes = (0..<count).map {
            AmbientMode(id: payload[6 + $0 * 2], steps: Int(payload[7 + $0 * 2]))
        }
    }
}
