/// Preset and band levels, in the scale the user sees.
///
/// Six-value devices carry Clear Bass first and run from −10 to +10; ten-value devices have no
/// Clear Bass and run from −6 to +6. A reply with any other count carries no band data, which is
/// what a preset-only device reports.
public struct MDREqualizer: Equatable {
    public let preset: UInt8
    public let clearBass: Int?
    public let bands: [Int]

    public init?(payload: [UInt8], family: MDRProtocolFamily) {
        guard payload.count >= 4,
              payload[0] == 0x57 || payload[0] == 0x59,
              payload[1] == family.equalizerInquiredType
        else { return nil }

        let count = Int(payload[3])
        guard payload.count >= 4 + count else { return nil }
        let levels = payload[4..<(4 + count)].map(Int.init)

        preset = payload[2]
        switch count {
        case 6:
            clearBass = levels[0] - 10
            bands = levels.dropFirst().map { $0 - 10 }
        case 10:
            clearBass = nil
            bands = levels.map { $0 - 6 }
        default:
            clearBass = nil
            bands = []
        }
    }
}

extension MDRProtocolFamily {
    var equalizerInquiredType: UInt8 {
        switch self {
        case .v1: 0x01
        case .v2: 0x00
        }
    }
}

func equalizerPresetCommand(_ preset: UInt8, family: MDRProtocolFamily) -> [UInt8] {
    [0x58, family.equalizerInquiredType, preset, 0x00]
}

/// Band levels go on the wire offset into an unsigned range: by ten for six-value devices,
/// by six for ten-value ones.
func equalizerBandsCommand(
    preset: UInt8,
    clearBass: Int?,
    bands: [Int],
    family: MDRProtocolFamily
) -> [UInt8] {
    let levels = (clearBass.map { [$0] } ?? []) + bands
    let offset = levels.count == 10 ? 6 : 10
    let encoded = levels.map { UInt8(min(offset * 2, max(0, $0 + offset))) }
    return [0x58, family.equalizerInquiredType, preset, UInt8(encoded.count)] + encoded
}
