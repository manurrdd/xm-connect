import Foundation
import MDRKit
import MDRTransport

// Diagnostic tool: connects to a paired headset, walks the handshake, and prints every frame in
// both directions. Its output is what device-support reports and protocol test vectors are made of.

private let silenceTimeout: TimeInterval = 4
private let overallTimeout: TimeInterval = 30

enum ProbeAction {
    case setNoise(MDRNoiseMode)
    case powerOff
}

final class Probe {
    private let connection: RFCOMMConnection
    private var pending: [[UInt8]] = []
    private var sequence: UInt8 = 0
    private var awaitingAck = false
    private let hardDeadline = Date().addingTimeInterval(overallTimeout)
    private var silenceDeadline = Date().addingTimeInterval(silenceTimeout)
    private var finished = false

    private let action: ProbeAction?
    private let explore: Bool
    private var settingTypes: V1NoiseSettingTypes?
    private var noiseVariant: V2NoiseVariant?
    private var actionApplied = false

    init(device: MDRDevice, action: ProbeAction?, explore: Bool) {
        self.action = action
        self.explore = explore
        connection = RFCOMMConnection(device: device)
        connection.onOpen = { [weak self] in self?.channelOpened() }
        connection.onFrame = { [weak self] frame in self?.receive(frame) }
        connection.onClose = { [weak self] in self?.channelClosed() }
    }

    func run() throws {
        print("device   \(connection.device.name)  [\(connection.device.address)]")
        print("protocol \(connection.device.family.rawValue)")
        try connection.open()

        while !finished, Date() < min(hardDeadline, silenceDeadline) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        connection.close()

        if action != nil, !actionApplied {
            print("error    the device never reported how to apply that change")
        }
    }

    /// A write needs what the read phase discovers: how this device wants it addressed.
    private func canApply(_ action: ProbeAction) -> Bool {
        switch action {
        case .powerOff: true
        case .setNoise: connection.device.family == .v1 ? settingTypes != nil : noiseVariant != nil
        }
    }

    private func channelOpened() {
        print("channel  open")
        switch connection.device.family {
        case .v1: pending = [V1Command.protocolInfo(), V1Command.supportFunctions()]
        case .v2: pending = [V2Command.protocolInfo(), V2Command.supportFunctions()]
        }
        sendNext()
    }

    private func channelClosed() {
        print("channel  closed")
        finished = true
    }

    private func receive(_ frame: MDRFrame) {
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

    /// One command at a time: the next one goes out when the device acknowledges the last. The
    /// requested change, if any, is applied once the reads have drained and told us how to write it.
    private func sendNext() {
        guard !awaitingAck else { return }
        if pending.isEmpty, let action, !actionApplied, canApply(action) {
            actionApplied = true
            pending = commands(for: action)
        }
        guard !pending.isEmpty else { return }
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

        if let capability = V1NoiseCapability(payload: payload) {
            settingTypes = V1NoiseSettingTypes(capability)
            let modes = capability.ambientModes
                .map { "\($0.id.hex) with \($0.steps) steps" }
                .joined(separator: ", ")
            print("""
                         ncSettingType \(capability.ncSettingType.hex), \
                ncStep \(capability.ncStep), asmSettingType \(capability.asmSettingType.hex)
                         ambient modes: \(modes)
                """)
        }

        if let noise = V1NoiseControl(payload: payload) {
            settingTypes = V1NoiseSettingTypes(noise)
            print("""
                         effect \(noise.effect.hex), \
                ncSettingType \(noise.ncSettingType.hex), ncValue \(noise.ncValue.hex), \
                asmSettingType \(noise.asmSettingType.hex), asmId \(noise.asmId.hex), \
                level \(noise.asmLevel)
                """)
        }

        if let capability = MDREqualizerCapability(payload: payload, family: family) {
            let presets = capability.presets.map { "\($0.id.hex) \($0.name)" }.joined(separator: ", ")
            print("         \(capability.bandCount) bands, \(capability.stepCount) steps")
            print("         presets: \(presets)")
        }

        if let equalizer = MDREqualizer(payload: payload, family: family) {
            let clearBass = equalizer.clearBass.map { "clear bass \($0), " } ?? ""
            print("         preset \(equalizer.preset.hex), \(clearBass)bands \(equalizer.bands)")
        }

        if let battery = MDRBattery(payload: payload, family: family) {
            print("         \(describe(battery))")
        }
    }

    /// Everything else the device announced, asked for raw. What comes back is how the next
    /// feature gets implemented.
    private func exploreV1(_ functions: [UInt8]) {
        for slot: UInt8 in [0xD1, 0xD2, 0xD3] where functions.contains(slot) {
            pending.append(V1Command.generalSettingCapability(slot: slot))
            pending.append(V1Command.generalSetting(slot: slot))
        }
        for (id, inquiry) in V1Command.systemFunctions where functions.contains(id) {
            pending.append(V1Command.systemSetting(inquiry))
        }
        if functions.contains(0xE2) {
            pending.append(V1Command.audioSetting(0x02))
        }
    }

    /// The write, followed by a read that shows what the device made of it.
    private func commands(for action: ProbeAction) -> [[UInt8]] {
        switch (action, connection.device.family) {
        case (.powerOff, .v1):
            return [V1Command.powerOff()]
        case (.powerOff, .v2):
            return [V2Command.powerOff()]
        case (.setNoise(let mode), .v1):
            guard let settingTypes else { return [] }
            return [V1Command.setNoise(mode, settingTypes: settingTypes), V1Command.noise()]
        case (.setNoise(let mode), .v2):
            guard let noiseVariant else { return [] }
            return [V2Command.setNoise(mode, variant: noiseVariant), V2Command.noise(variant: noiseVariant)]
        }
    }

    private func describe(_ battery: MDRBattery) -> String {
        func text(_ level: MDRBatteryLevel) -> String { "\(level.percent)% \(level.charging)" }

        switch battery {
        case .single(let level): return "battery \(text(level))"
        case .leftRight(let left, let right): return "battery left \(text(left)), right \(text(right))"
        case .cradle(let level): return "case battery \(text(level))"
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
            if functions.contains(0x51) {
                pending.append(V1Command.equalizerCapability())
                pending.append(V1Command.equalizer())
            }
            for (id, kind) in V1Command.batteryFunctions where functions.contains(id) {
                pending.append(V1Command.battery(kind))
            }
            if explore { exploreV1(functions) }
        case .v2:
            noiseVariant = functions.compactMap(V2NoiseVariant.forFunction).first
            if let noiseVariant {
                pending.append(V2Command.noise(variant: noiseVariant))
            }
            if functions.contains(0x50) || functions.contains(0x52) {
                pending.append(V2Command.equalizerCapability())
                pending.append(V2Command.equalizer())
            }
            for (id, kind) in V2Command.batteryFunctions where functions.contains(id) {
                pending.append(V2Command.battery(kind))
            }
        }
    }
}

func parseAction(_ arguments: [String]) -> ProbeAction? {
    let focusOnVoice = arguments.contains("--voice")

    for (index, argument) in arguments.enumerated() {
        switch argument {
        case "--noise-off": return .setNoise(.off)
        case "--nc": return .setNoise(.noiseCancelling(windReduction: false))
        case "--wind": return .setNoise(.noiseCancelling(windReduction: true))
        case "--power-off": return .powerOff
        case "--ambient":
            guard let level = arguments.dropFirst(index + 1).first.flatMap(Int.init) else {
                print("usage    --ambient <1-20>")
                exit(1)
            }
            return .setNoise(.ambient(level: level, focusOnVoice: focusOnVoice))
        default: continue
        }
    }
    return nil
}

let devices = RFCOMMConnection.discover()
guard let device = devices.first(where: \.isConnected) else {
    print(devices.isEmpty
        ? "no paired device exposes an MDR service"
        : "the headset is paired but not connected to this Mac")
    exit(1)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    try Probe(
        device: device,
        action: parseAction(arguments),
        explore: arguments.contains("--explore")
    ).run()
} catch {
    print("error    \(error)")
    exit(1)
}
