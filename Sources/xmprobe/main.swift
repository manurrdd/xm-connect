import Foundation
import MDRKit
import MDRTransport

// Diagnostic tool: connects to a paired headset, walks the handshake, and prints every frame in
// both directions. Its output is what device-support reports and protocol test vectors are made of.

private let silenceTimeout: TimeInterval = 4
private let overallTimeout: TimeInterval = 30

final class Probe: NSObject, RFCOMMConnectionDelegate {
    private let connection: RFCOMMConnection
    private var pending: [[UInt8]] = []
    private var sequence: UInt8 = 0
    private var awaitingAck = false
    private let hardDeadline = Date().addingTimeInterval(overallTimeout)
    private var silenceDeadline = Date().addingTimeInterval(silenceTimeout)
    private var finished = false

    init(device: MDRDevice) {
        connection = RFCOMMConnection(device: device)
        super.init()
        connection.delegate = self
    }

    func run() throws {
        print("device   \(connection.device.name)  [\(connection.device.address)]")
        print("protocol \(connection.device.family.rawValue)")
        try connection.open()

        while !finished, Date() < min(hardDeadline, silenceDeadline) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        connection.close()
    }

    func connectionDidOpen(_ connection: RFCOMMConnection) {
        print("channel  open")
        switch connection.device.family {
        case .v1: pending = [V1Command.protocolInfo(), V1Command.supportFunctions()]
        case .v2: pending = [V2Command.protocolInfo(), V2Command.supportFunctions()]
        }
        sendNext()
    }

    func connectionDidClose(_ connection: RFCOMMConnection) {
        print("channel  closed")
        finished = true
    }

    func connection(_ connection: RFCOMMConnection, didReceive frame: MDRFrame) {
        silenceDeadline = Date().addingTimeInterval(silenceTimeout)

        switch frame.type {
        case .ack:
            awaitingAck = false
            sendNext()
        case .data, .dataNo2:
            print("recv     \(frame.payload.hex)")
            report(frame.payload)
            queueFollowUps(frame.payload)
            acknowledge(frame)
            sendNext()
        }
    }

    /// One command at a time: the next one goes out when the device acknowledges the last.
    private func sendNext() {
        guard !awaitingAck, !pending.isEmpty else { return }
        let payload = pending.removeFirst()
        do {
            try connection.send(MDRFrame(type: .data, sequence: sequence, payload: payload))
            print("sent     \(payload.hex)")
            sequence ^= 1
            awaitingAck = true
        } catch {
            print("error    \(error)")
        }
    }

    private func acknowledge(_ frame: MDRFrame) {
        try? connection.send(MDRFrame(type: .ack, sequence: frame.sequence ^ 1, payload: []))
    }

    private func report(_ payload: [UInt8]) {
        let family = connection.device.family

        if let info = MDRProtocolInfo(payload: payload, family: family) {
            let tables = info.tables.map { ", table1 \($0.table1), table2 \($0.table2)" } ?? ""
            print("         version \(info.version)\(tables)")
        }

        if let functions = MDRSupportFunctions(payload: payload, family: family) {
            print("         \(functions.ids.count) functions announced")
            for id in functions.ids {
                print("           \(id.hex)  \(family.functionName(for: id) ?? "unknown")")
            }
        }

        if let noise = V1NoiseControl(payload: payload) {
            print("""
                         effect \(noise.effect.hex), \
                ncSettingType \(noise.ncSettingType.hex), ncValue \(noise.ncValue.hex), \
                asmSettingType \(noise.asmSettingType.hex), asmId \(noise.asmId.hex), \
                level \(noise.asmLevel)
                """)
        }
    }

    /// Queries the device's own capability list makes possible.
    private func queueFollowUps(_ payload: [UInt8]) {
        guard let functions = MDRSupportFunctions(
            payload: payload, family: connection.device.family
        )?.ids else { return }

        switch connection.device.family {
        case .v1:
            if functions.contains(0x62) {
                pending.append(V1Command.noiseCapability())
                pending.append(V1Command.noise())
            }
            if functions.contains(0x51) { pending.append(V1Command.equalizer()) }
            for (id, kind) in V1Command.batteryFunctions where functions.contains(id) {
                pending.append(V1Command.battery(kind))
            }
        case .v2:
            if let variant = functions.compactMap(V2Command.noiseVariant(forFunction:)).first {
                pending.append(V2Command.noise(variant: variant))
            }
            if functions.contains(0x50) || functions.contains(0x52) {
                pending.append(V2Command.equalizer())
            }
            for (id, kind) in V2Command.batteryFunctions where functions.contains(id) {
                pending.append(V2Command.battery(kind))
            }
        }
    }
}

let devices = RFCOMMConnection.discover()
guard let device = devices.first else {
    print("no paired device exposes an MDR service")
    exit(1)
}
if devices.count > 1 {
    print("note     \(devices.count) candidates found, using the first")
}

do {
    try Probe(device: device).run()
} catch {
    print("error    \(error)")
    exit(1)
}
