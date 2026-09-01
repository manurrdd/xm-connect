/// Turns the RFCOMM byte stream into whole frames. Bytes outside a start/end pair are dropped:
/// escaping guarantees neither marker can appear inside a frame body.
public struct MDRFrameReassembler {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func consume(_ bytes: [UInt8]) -> [MDRFrame] {
        buffer.append(contentsOf: bytes)
        var frames: [MDRFrame] = []

        while let start = buffer.firstIndex(of: MDRFraming.startMarker) {
            guard let end = buffer[start...].firstIndex(of: MDRFraming.endMarker) else {
                buffer.removeFirst(start)
                return frames
            }
            if let frame = MDRFraming.unpack(buffer[start...end]) {
                frames.append(frame)
            }
            buffer.removeFirst(end + 1)
        }

        buffer.removeAll(keepingCapacity: true)
        return frames
    }
}
