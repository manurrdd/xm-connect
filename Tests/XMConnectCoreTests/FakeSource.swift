import MDRKit

final class FakeLink: MDRLink {
    var onOpen: (() -> Void)?
    var onFrame: ((MDRFrame) -> Void)?
    var onClose: (() -> Void)?

    private(set) var isOpen = false
    private(set) var isClosed = false

    func open() throws {
        isOpen = true
        onOpen?()
    }

    func send(_ frame: MDRFrame) throws {}

    func close() {
        isClosed = true
        onClose?()
    }

    /// Plays a WH-1000XM4 through the handshake far enough for the session to settle.
    func settle() {
        reply([0x01, 0x00, 0x70, 0x00])
        reply([0x07, 0x00, 0x03, 0x62, 0x51, 0x11])
        reply([0x61, 0x02, 0x02, 0x00, 0x01, 0x02, 0x00, 0x14, 0x01, 0x14])
        reply([0x67, 0x02, 0x00, 0x02, 0x00, 0x01, 0x00, 0x14])
        reply([0x11, 0x00, 0x5A, 0x00])
        reply([0x51, 0x01, 0x06, 0x15, 0x01, 0x00, 0x00])
        reply([0x57, 0x01, 0x00, 0x06, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A])
    }

    private func reply(_ payload: [UInt8]) {
        onFrame?(MDRFrame(type: .ack, sequence: 0, payload: []))
        onFrame?(MDRFrame(type: .data, sequence: 0, payload: payload))
    }
}

final class FakeSource: HeadphonesSource {
    var devices: [HeadphonesDescription]
    var failToLink = false

    private(set) var links: [FakeLink] = []

    init(devices: [HeadphonesDescription] = [.connected]) {
        self.devices = devices
    }

    func discover() -> [HeadphonesDescription] {
        devices
    }

    func link(to headphones: HeadphonesDescription) throws -> MDRLink {
        if failToLink { throw LinkFailure() }
        let link = FakeLink()
        links.append(link)
        return link
    }

    struct LinkFailure: Error {}
}

extension HeadphonesDescription {
    static let connected = HeadphonesDescription(
        name: "WH-1000XM4", address: "80-99-e7-8b-c9-36", family: .v1, isConnected: true
    )
    static let offline = HeadphonesDescription(
        name: "WH-1000XM4", address: "80-99-e7-8b-c9-36", family: .v1, isConnected: false
    )
}
