/// Which command tables the device has enabled. Only v2 reports this; v1 answers with the
/// version alone and always speaks table 1.
public struct MDRTableSupport: Equatable {
    public let table1: Bool
    public let table2: Bool
}

public struct MDRProtocolInfo: Equatable {
    public let version: Int
    public let tables: MDRTableSupport?

    public init?(payload: [UInt8], family: MDRProtocolFamily) {
        guard payload.count >= 2, payload[0] == 0x01, payload[1] == 0x00 else { return nil }

        switch family {
        case .v1:
            guard payload.count >= 4 else { return nil }
            version = Int(payload[2]) << 8 | Int(payload[3])
            tables = nil
        case .v2:
            guard payload.count >= 8 else { return nil }
            version = Int(payload[2]) << 24 | Int(payload[3]) << 16 | Int(payload[4]) << 8 | Int(payload[5])
            tables = MDRTableSupport(table1: payload[6] == 0, table2: payload[7] == 0)
        }
    }
}

/// Function ids the device announces, which is what decides the controls it can offer.
public struct MDRSupportFunctions: Equatable {
    public let ids: [UInt8]

    public init?(payload: [UInt8], family: MDRProtocolFamily) {
        guard payload.count >= 3, payload[0] == 0x07, payload[1] == 0x00 else { return nil }

        // v1 lists one byte per function; v2 pairs every id with a priority byte, which is unused.
        let stride = family == .v1 ? 1 : 2
        let count = Int(payload[2])
        guard payload.count >= 3 + count * stride else { return nil }
        ids = (0..<count).map { payload[3 + $0 * stride] }
    }
}
