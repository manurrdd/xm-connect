import Foundation
import IOBluetooth
import MDRKit

struct MDRDevice {
    let description: HeadphonesDescription
    let bluetoothDevice: IOBluetoothDevice
}

/// Finds paired headsets over classic Bluetooth and opens channels to them.
public struct RFCOMMSource: HeadphonesSource {
    public init() {}

    public func discover() -> [HeadphonesDescription] {
        RFCOMMConnection.discover().map(\.description)
    }

    public func link(to headphones: HeadphonesDescription) throws -> MDRLink {
        guard let device = RFCOMMConnection.discover()
            .first(where: { $0.description.address == headphones.address })
        else { throw RFCOMMError.noDeviceFound }
        return RFCOMMConnection(device: device)
    }
}

public enum RFCOMMError: Error, CustomStringConvertible {
    case noDeviceFound
    case noChannelID
    case openFailed(IOReturn)
    case notOpen

    public var description: String {
        switch self {
        case .noDeviceFound: "no paired device exposes an MDR service"
        case .noChannelID: "the service record carries no RFCOMM channel"
        case .openFailed(let status): "could not open the channel (IOReturn \(status))"
        case .notOpen: "the channel is not open"
        }
    }
}

/// Classic Bluetooth RFCOMM link to a headset, over the service that identifies its protocol
/// family. Everything runs on the main run loop, which is where IOBluetooth delivers its callbacks.
final class RFCOMMConnection: NSObject, MDRLink {
    let device: MDRDevice

    var onOpen: (() -> Void)?
    var onFrame: ((MDRFrame) -> Void)?
    var onClose: (() -> Void)?

    private var channel: IOBluetoothRFCOMMChannel?
    private var reassembler = MDRFrameReassembler()

    init(device: MDRDevice) {
        self.device = device
    }

    /// Paired devices exposing an MDR service, v2 first. Model names are never consulted: the
    /// service the headset answers to is what determines the command table.
    static func discover() -> [MDRDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }

        return paired.compactMap { device in
            guard let family = MDRProtocolFamily.allCases.first(where: {
                device.getServiceRecord(for: $0.sdpUUID) != nil
            }) else { return nil }

            return MDRDevice(
                description: HeadphonesDescription(
                    name: device.name ?? "unknown",
                    address: device.addressString ?? "unknown",
                    family: family,
                    isConnected: device.isConnected()
                ),
                bluetoothDevice: device
            )
        }
    }

    func open() throws {
        guard let record = device.bluetoothDevice.getServiceRecord(for: device.description.family.sdpUUID) else {
            throw RFCOMMError.noDeviceFound
        }

        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            throw RFCOMMError.noChannelID
        }

        var opened: IOBluetoothRFCOMMChannel?
        let status = device.bluetoothDevice.openRFCOMMChannelAsync(
            &opened, withChannelID: channelID, delegate: self
        )
        guard status == kIOReturnSuccess else { throw RFCOMMError.openFailed(status) }
        channel = opened
    }

    func send(_ frame: MDRFrame) throws {
        guard let channel else { throw RFCOMMError.notOpen }
        var bytes = MDRFraming.pack(frame)
        let status = channel.writeSync(&bytes, length: UInt16(bytes.count))
        guard status == kIOReturnSuccess else { throw RFCOMMError.openFailed(status) }
    }

    func close() {
        channel?.close()
        channel = nil
    }
}

extension RFCOMMConnection: IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        guard status == kIOReturnSuccess else {
            onClose?()
            return
        }
        onOpen?()
    }

    func rfcommChannelData(
        _ channel: IOBluetoothRFCOMMChannel!,
        data pointer: UnsafeMutableRawPointer!,
        length: Int
    ) {
        let bytes = Array(UnsafeRawBufferPointer(start: pointer, count: length))
        for frame in reassembler.consume(bytes) {
            onFrame?(frame)
        }
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        self.channel = nil
        onClose?()
    }
}

private extension MDRProtocolFamily {
    var sdpUUID: IOBluetoothSDPUUID {
        withUnsafeBytes(of: serviceUUID.uuid) { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: $0.count) }
    }
}
