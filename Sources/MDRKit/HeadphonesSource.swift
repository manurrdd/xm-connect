/// A headset the app could talk to, described without reference to any Bluetooth type so the
/// layers above can be exercised without a radio.
public struct HeadphonesDescription: Equatable {
    public let name: String
    public let address: String
    public let family: MDRProtocolFamily
    /// Whether it is connected to this machine right now. Opening a channel to one that is not
    /// makes the system connect it, which is not the app's decision to make.
    public let isConnected: Bool

    public init(name: String, address: String, family: MDRProtocolFamily, isConnected: Bool) {
        self.name = name
        self.address = address
        self.family = family
        self.isConnected = isConnected
    }
}

public protocol HeadphonesSource {
    func discover() -> [HeadphonesDescription]
    func link(to headphones: HeadphonesDescription) throws -> MDRLink
}
