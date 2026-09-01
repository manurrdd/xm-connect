/// A v2 noise-control variant: which inquiry the device wants and which fields its payload carries.
///
/// Sony names the announced function and the inquiry after the same feature set, which is what the
/// table below pairs up. Three of them appear in recorded sessions; the rest are derived from the
/// message definitions and have never been seen on a device.
public struct V2NoiseVariant: Equatable {
    /// The noise-cancelling field a variant carries, if any.
    enum NoiseField {
        case none
        /// On or off only.
        case onOff
        /// Off, single microphone, or dual.
        case dualSingle
    }

    public let inquiry: UInt8
    let hasModeField: Bool
    let noiseField: NoiseField
    let trailing: [UInt8]

    public var supportsNoiseCancelling: Bool { hasModeField || noiseField != .none }
    public var supportsWindReduction: Bool { noiseField == .dualSingle }

    public static func forFunction(_ id: UInt8) -> V2NoiseVariant? { byFunction[id] }
    public static func forInquiry(_ inquiry: UInt8) -> V2NoiseVariant? {
        byFunction.values.first { $0.inquiry == inquiry }
    }

    private static let byFunction: [UInt8: V2NoiseVariant] = [
        0x64: V2NoiseVariant(inquiry: 0x13, hasModeField: false, noiseField: .onOff, trailing: []),
        0x65: V2NoiseVariant(inquiry: 0x14, hasModeField: false, noiseField: .dualSingle, trailing: []),
        0x68: V2NoiseVariant(inquiry: 0x15, hasModeField: true, noiseField: .dualSingle, trailing: []),
        0x6A: V2NoiseVariant(inquiry: 0x16, hasModeField: true, noiseField: .dualSingle, trailing: []),
        0x6B: V2NoiseVariant(inquiry: 0x17, hasModeField: true, noiseField: .none, trailing: []),
        // The trailing pair turns noise adaptation off at standard sensitivity.
        0x6D: V2NoiseVariant(inquiry: 0x19, hasModeField: true, noiseField: .none, trailing: [0x00, 0x00]),
        0x67: V2NoiseVariant(inquiry: 0x22, hasModeField: false, noiseField: .none, trailing: []),
    ]

    func payload(for mode: MDRNoiseMode) -> [UInt8] {
        var isAmbient = false
        var focusOnVoice: UInt8 = 0x00
        var level: UInt8 = 0x00
        var noise: UInt8 = 0x00

        switch mode {
        case .off:
            break
        case .noiseCancelling(let windReduction):
            noise = noiseField == .onOff ? 0x01 : (windReduction ? 0x01 : 0x02)
        case .ambient(let requested, let voice):
            isAmbient = true
            focusOnVoice = voice ? 0x01 : 0x00
            level = UInt8(min(20, max(1, requested)))
        }

        var bytes: [UInt8] = [0x68, inquiry, 0x01, mode == .off ? 0x00 : 0x01]
        if hasModeField { bytes.append(isAmbient ? 0x01 : 0x00) }
        if noiseField != .none { bytes.append(noise) }
        bytes.append(focusOnVoice)
        bytes.append(level)
        return bytes + trailing
    }

    func mode(from payload: [UInt8]) -> MDRNoiseMode? {
        var index = 4
        guard payload.count > index else { return nil }
        guard payload[3] != 0x00 else { return .off }

        var isAmbient: Bool?
        if hasModeField {
            isAmbient = payload[index] == 0x01
            index += 1
        }

        var windReduction = false
        if noiseField != .none {
            guard payload.count > index else { return nil }
            let noise = payload[index]
            windReduction = noiseField == .dualSingle && noise == 0x01
            if isAmbient == nil { isAmbient = noise == 0x00 }
            index += 1
        }

        guard payload.count > index + 1 else { return nil }
        if isAmbient ?? true {
            return .ambient(level: Int(payload[index + 1]), focusOnVoice: payload[index] == 0x01)
        }
        return .noiseCancelling(windReduction: windReduction)
    }
}
