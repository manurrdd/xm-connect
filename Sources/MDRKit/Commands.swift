public enum MDRBatteryKind: UInt8, CaseIterable {
    case single = 0x00
    case leftRight = 0x01
    case cradle = 0x02
}

/// Legacy table (WH-1000XM4 and older).
public enum V1Command {
    /// The combined noise cancelling + ambient sound inquiry, the only one these devices use.
    public static let noiseInquiredType: UInt8 = 0x02

    public static func protocolInfo() -> [UInt8] { [0x00, 0x00] }
    public static func supportFunctions() -> [UInt8] { [0x06, 0x00] }
    public static func noise() -> [UInt8] { [0x66, noiseInquiredType] }
    public static func noiseCapability() -> [UInt8] { [0x60, noiseInquiredType] }
    public static func battery(_ kind: MDRBatteryKind) -> [UInt8] { [0x10, kind.rawValue] }
    public static func equalizer() -> [UInt8] { [0x56, 0x01] }

    /// Announced function ids and the battery layout each one enables.
    public static let batteryFunctions: [(id: UInt8, kind: MDRBatteryKind)] = [
        (0x11, .single), (0x15, .leftRight), (0x18, .cradle),
    ]
}

/// Table used from the WH-1000XM5 onwards.
public enum V2Command {
    public static func protocolInfo() -> [UInt8] { [0x00, 0x00] }
    public static func supportFunctions() -> [UInt8] { [0x06, 0x00] }
    public static func noise(variant: UInt8) -> [UInt8] { [0x66, variant] }
    public static func battery(_ kind: MDRBatteryKind) -> [UInt8] { [0x22, kind.rawValue] }
    public static func equalizer() -> [UInt8] { [0x56, 0x00] }

    /// Announced function ids and the battery layout each one enables. The second row is the
    /// same three layouts reported with a low-battery threshold appended.
    public static let batteryFunctions: [(id: UInt8, kind: MDRBatteryKind)] = [
        (0x20, .single), (0x21, .leftRight), (0x22, .cradle),
        (0x28, .single), (0x29, .leftRight), (0x2A, .cradle),
    ]
}

extension V2Command {
    /// Wire variant to use with `noise(variant:)`, derived from the announced function id.
    public static func noiseVariant(forFunction id: UInt8) -> UInt8? {
        switch id {
        case 0x6B: 0x17
        case 0x6D: 0x19
        case 0x67: 0x22
        default: nil
        }
    }
}
