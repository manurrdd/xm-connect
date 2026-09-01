/// System inquiries that behave as a switch.
public enum MDRSystemSwitch: UInt8, CaseIterable {
    case pauseWhenRemoved = 0x03
    case speakToChat = 0x05

    /// The function id a device announces when it has this setting.
    public var function: UInt8 {
        switch self {
        case .pauseWhenRemoved: 0xF3
        case .speakToChat: 0xF5
        }
    }

    public var name: String {
        switch self {
        case .pauseWhenRemoved: "Pause when removed"
        case .speakToChat: "Speak-to-Chat"
        }
    }
}

public struct MDRSystemSwitchState: Equatable {
    public let setting: MDRSystemSwitch
    public let isOn: Bool

    public init?(payload: [UInt8]) {
        guard payload.count >= 4,
              payload[0] == 0xF7 || payload[0] == 0xF9,
              let setting = MDRSystemSwitch(rawValue: payload[1]),
              payload[2] == 0x00  // on/off, the only setting type these carry
        else { return nil }

        self.setting = setting
        isOn = payload[3] == 0x01
    }
}

/// When the headset powers itself down. The last two are modes rather than delays, and a device
/// keeps the chosen delay while one of them is active.
public enum MDRAutoPowerOff: UInt8, CaseIterable {
    case afterFiveMinutes = 0x00
    case afterThirtyMinutes = 0x01
    case afterOneHour = 0x02
    case afterThreeHours = 0x03
    case whenRemoved = 0x10
    case never = 0x11

    public var name: String {
        switch self {
        case .afterFiveMinutes: "After 5 minutes"
        case .afterThirtyMinutes: "After 30 minutes"
        case .afterOneHour: "After 1 hour"
        case .afterThreeHours: "After 3 hours"
        case .whenRemoved: "When removed"
        case .never: "Never"
        }
    }

    public var isDelay: Bool { rawValue < 0x10 }
}

public struct MDRAutoPowerOffState: Equatable {
    public let active: MDRAutoPowerOff
    /// The delay the device goes back to when a mode is turned off again.
    public let selectedDelay: MDRAutoPowerOff

    public init?(payload: [UInt8]) {
        guard payload.count >= 5,
              payload[0] == 0xF7 || payload[0] == 0xF9,
              payload[1] == 0x04,
              payload[2] == 0x01,
              let active = MDRAutoPowerOff(rawValue: payload[3]),
              let selected = MDRAutoPowerOff(rawValue: payload[4])
        else { return nil }

        self.active = active
        selectedDelay = selected
    }
}
