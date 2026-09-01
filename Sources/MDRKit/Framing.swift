/// Wire format shared by both protocol families:
/// `3E | type | sequence | length (Int32 BE) | payload | checksum | 3C`
public enum MDRFraming {
    public static let startMarker: UInt8 = 0x3E
    public static let endMarker: UInt8 = 0x3C
    private static let escapeMarker: UInt8 = 0x3D
    private static let escapeOffset: UInt8 = 0x10
    private static let headerSize = 6
    private static let overhead = headerSize + 1

    public static func pack(_ frame: MDRFrame) -> [UInt8] {
        var body: [UInt8] = [frame.type.rawValue, frame.sequence]
        let length = UInt32(frame.payload.count)
        body.append(contentsOf: [
            UInt8(truncatingIfNeeded: length >> 24),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length),
        ])
        body.append(contentsOf: frame.payload)
        body.append(checksum(body))
        return [startMarker] + escaping(body) + [endMarker]
    }

    public static func unpack<C: BidirectionalCollection>(_ packed: C) -> MDRFrame? where C.Element == UInt8 {
        guard packed.first == startMarker, packed.last == endMarker,
              let body = unescaping(packed.dropFirst().dropLast()),
              body.count >= overhead,
              let type = MDRDataType(rawValue: body[0]),
              checksum(body.dropLast()) == body[body.count - 1]
        else { return nil }

        let declared = Int(body[2]) << 24 | Int(body[3]) << 16 | Int(body[4]) << 8 | Int(body[5])
        guard declared == body.count - overhead else { return nil }
        return MDRFrame(type: type, sequence: body[1], payload: Array(body[headerSize..<(body.count - 1)]))
    }

    static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(0) { $0 &+ $1 }
    }

    static func escaping(_ bytes: [UInt8]) -> [UInt8] {
        var escaped: [UInt8] = []
        escaped.reserveCapacity(bytes.count)
        for byte in bytes {
            if byte == startMarker || byte == endMarker || byte == escapeMarker {
                escaped.append(escapeMarker)
                escaped.append(byte - escapeOffset)
            } else {
                escaped.append(byte)
            }
        }
        return escaped
    }

    static func unescaping<C: Sequence>(_ bytes: C) -> [UInt8]? where C.Element == UInt8 {
        var plain: [UInt8] = []
        plain.reserveCapacity(bytes.underestimatedCount)
        var pendingEscape = false
        for byte in bytes {
            if pendingEscape {
                let restored = byte &+ escapeOffset
                guard restored == startMarker || restored == endMarker || restored == escapeMarker else {
                    return nil
                }
                plain.append(restored)
                pendingEscape = false
            } else if byte == escapeMarker {
                pendingEscape = true
            } else {
                plain.append(byte)
            }
        }
        return pendingEscape ? nil : plain
    }
}
