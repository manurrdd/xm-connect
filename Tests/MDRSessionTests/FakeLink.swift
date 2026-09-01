import MDRKit

/// Stands in for the Bluetooth channel: records what the session sends and lets a test play the
/// part of the headset.
final class FakeLink: MDRLink {
    var onOpen: (() -> Void)?
    var onFrame: ((MDRFrame) -> Void)?
    var onClose: (() -> Void)?

    private(set) var commands: [[UInt8]] = []
    private(set) var acknowledgements = 0
    private(set) var isClosed = false

    func open() throws {
        onOpen?()
    }

    func send(_ frame: MDRFrame) throws {
        switch frame.type {
        case .ack: acknowledgements += 1
        case .data, .dataNo2: commands.append(frame.payload)
        }
    }

    func close() {
        isClosed = true
        onClose?()
    }

    func acknowledge() {
        onFrame?(MDRFrame(type: .ack, sequence: 0, payload: []))
    }

    /// A reply from the device, acknowledged first the way real firmware does.
    func reply(_ payload: [UInt8]) {
        acknowledge()
        onFrame?(MDRFrame(type: .data, sequence: 0, payload: payload))
    }
}
