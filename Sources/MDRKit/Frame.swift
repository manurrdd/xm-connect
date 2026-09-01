/// Transport-level message types. Devices differ in which of the two data types they emit,
/// so both are accepted when reading.
public enum MDRDataType: UInt8 {
    case ack = 0x01
    case data = 0x0C
    case dataNo2 = 0x0E
}

public struct MDRFrame: Equatable {
    public let type: MDRDataType
    public let sequence: UInt8
    public let payload: [UInt8]

    public init(type: MDRDataType, sequence: UInt8, payload: [UInt8]) {
        self.type = type
        self.sequence = sequence
        self.payload = payload
    }
}
