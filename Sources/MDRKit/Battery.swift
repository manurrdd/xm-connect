public enum MDRChargingState: UInt8 {
    case notCharging = 0x00
    case charging = 0x01
    case unknown = 0x02
    case charged = 0x03

    init(raw: UInt8) {
        self = MDRChargingState(rawValue: raw) ?? .unknown
    }
}

public struct MDRBatteryLevel: Equatable {
    public let percent: Int
    public let charging: MDRChargingState

    public init(percent: Int, charging: MDRChargingState) {
        self.percent = percent
        self.charging = charging
    }
}

public enum MDRBattery: Equatable {
    case single(MDRBatteryLevel)
    case leftRight(left: MDRBatteryLevel, right: MDRBatteryLevel)
    case cradle(MDRBatteryLevel)

    public init?(payload: [UInt8], family: MDRProtocolFamily) {
        let replies: Set<UInt8> = family == .v1 ? [0x11, 0x13] : [0x23, 0x25]
        guard payload.count >= 4, replies.contains(payload[0]) else { return nil }

        // The threshold variants repeat the layout with a trailing byte this ignores; they are
        // announced by v2 devices only.
        switch payload[1] {
        case 0x00, 0x08:
            self = .single(MDRBatteryLevel(percent: Int(payload[2]), charging: .init(raw: payload[3])))
        case 0x01, 0x09:
            guard payload.count >= 6 else { return nil }
            self = .leftRight(
                left: MDRBatteryLevel(percent: Int(payload[2]), charging: .init(raw: payload[3])),
                right: MDRBatteryLevel(percent: Int(payload[4]), charging: .init(raw: payload[5]))
            )
        case 0x02, 0x0A:
            self = .cradle(MDRBatteryLevel(percent: Int(payload[2]), charging: .init(raw: payload[3])))
        default:
            return nil
        }
    }
}
