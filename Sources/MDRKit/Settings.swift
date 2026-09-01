/// What a general-setting slot holds, from the capability reply. The subject arrives as an enum
/// key rather than a label when `isEnumKey` is set, which is what the WH-1000XM4 does.
public struct MDRGeneralSettingInfo: Equatable {
    public let slot: UInt8
    public let subject: String
    public let summary: String
    public let isEnumKey: Bool

    public init?(payload: [UInt8]) {
        guard payload.count >= 4, payload[0] == 0xD1 else { return nil }

        slot = payload[1]
        isEnumKey = payload[2] == 0x02

        var index = 3
        guard let subject = Self.string(in: payload, at: &index),
              let summary = Self.string(in: payload, at: &index)
        else { return nil }
        self.subject = subject
        self.summary = summary
    }

    private static func string(in payload: [UInt8], at index: inout Int) -> String? {
        guard index < payload.count else { return nil }
        let length = Int(payload[index])
        let start = index + 1
        guard start + length <= payload.count else { return nil }
        index = start + length
        return String(decoding: payload[start..<(start + length)], as: UTF8.self)
    }

    /// `TOUCH_PANEL_SETTING` reads as "Touch panel". Keys this project has never seen still come
    /// out readable, which beats a table that has to grow for every model.
    public var displayName: String {
        guard isEnumKey else { return subject }

        let words = subject
            .replacingOccurrences(of: "_SETTING", with: "")
            .split(separator: "_")
            .map { $0.lowercased() }
        guard let first = words.first else { return subject }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }
}

/// The value in a general-setting slot. List-type slots carry an index into the candidates the
/// device offers; boolean ones carry on or off.
public struct MDRGeneralSettingValue: Equatable {
    public let slot: UInt8
    /// Boolean or list. Writes have to carry it back, so it is kept rather than folded away.
    public let settingType: UInt8
    public let isOn: Bool?
    public let index: UInt8?

    public init?(payload: [UInt8]) {
        guard payload.count >= 4, payload[0] == 0xD7 || payload[0] == 0xD9 else { return nil }

        slot = payload[1]
        settingType = payload[2]
        switch payload[2] {
        case 0x01:
            isOn = payload[3] == 0x01
            index = nil
        case 0x02:
            isOn = nil
            index = payload[3]
        default:
            return nil
        }
    }
}

/// DSEE, which the protocol calls upscaling. Off or automatic.
public struct MDRUpscaling: Equatable {
    public let isOn: Bool

    public init?(payload: [UInt8]) {
        guard payload.count >= 4, payload[0] == 0xE7 || payload[0] == 0xE9, payload[1] == 0x02 else {
            return nil
        }
        isOn = payload[3] != 0x00
    }
}
