import Foundation
import MDRKit

/// Runs the conversation with one headset: handshake, capability discovery, the state the device
/// reports, and the commands that change it.
///
/// Commands go out one at a time, each waiting for the device's acknowledgement, which is what the
/// protocol expects. Everything happens on the main queue, where the Bluetooth channel delivers.
public final class MDRSession {
    public struct State: Equatable {
        public var isReady = false
        public var capabilities = MDRCapabilities()
        public var noise: MDRNoiseMode?
        public var equalizer: MDREqualizer?
        public var equalizerCapability: MDREqualizerCapability?
        public var battery: MDRBattery?
        /// Earbud cases report separately, and a device that has one reports both.
        public var caseBattery: MDRBatteryLevel?
        public var settings: [MDRSetting] = []
        public var upscaling: Bool?

        public init() {}
    }

    public private(set) var state = State() {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    public var onStateChange: ((State) -> Void)?
    public var onClose: (() -> Void)?

    public let family: MDRProtocolFamily

    private let link: MDRLink
    private let acknowledgementTimeout: TimeInterval
    private var queue: [[UInt8]] = []
    private var sequence: UInt8 = 0
    private var awaitingAcknowledgement: DispatchWorkItem?
    private var noiseSettingTypes: V1NoiseSettingTypes?
    private var noiseVariant: V2NoiseVariant?
    private var settingNames: [UInt8: String] = [:]
    private var settingTypes: [UInt8: UInt8] = [:]

    public init(family: MDRProtocolFamily, link: MDRLink, acknowledgementTimeout: TimeInterval = 3) {
        self.family = family
        self.link = link
        self.acknowledgementTimeout = acknowledgementTimeout

        link.onOpen = { [weak self] in self?.handshake() }
        link.onFrame = { [weak self] frame in self?.receive(frame) }
        link.onClose = { [weak self] in self?.linkClosed() }
    }

    public func start() throws {
        try link.open()
    }

    public func close() {
        link.close()
    }

    // MARK: - Commands

    public func setNoise(_ mode: MDRNoiseMode) {
        switch family {
        case .v1:
            guard let noiseSettingTypes else { return }
            enqueue(V1Command.setNoise(mode, settingTypes: noiseSettingTypes))
        case .v2:
            guard let noiseVariant else { return }
            enqueue(V2Command.setNoise(mode, variant: noiseVariant))
        }
        // Shown straight away; the device's reply confirms it or corrects it.
        state.noise = mode
    }

    public func setEqualizerPreset(_ preset: UInt8) {
        switch family {
        case .v1: enqueue(V1Command.setEqualizerPreset(preset))
        case .v2: enqueue(V2Command.setEqualizerPreset(preset))
        }
        enqueue(equalizerQuery())
    }

    public func setEqualizerBands(preset: UInt8, clearBass: Int?, bands: [Int]) {
        switch family {
        case .v1: enqueue(V1Command.setEqualizerBands(preset: preset, clearBass: clearBass, bands: bands))
        case .v2: enqueue(V2Command.setEqualizerBands(preset: preset, clearBass: clearBass, bands: bands))
        }
    }

    public func setSetting(slot: UInt8, isOn: Bool) {
        guard let settingType = settingTypes[slot] else { return }
        switch family {
        case .v1:
            enqueue(V1Command.setGeneralSetting(slot: slot, settingType: settingType, isOn: isOn))
            enqueue(V1Command.generalSetting(slot: slot))
        case .v2:
            enqueue(V2Command.setGeneralSetting(slot: slot, settingType: settingType, isOn: isOn))
            enqueue(V2Command.generalSetting(slot: slot))
        }
        if let index = state.settings.firstIndex(where: { $0.slot == slot }) {
            state.settings[index].isOn = isOn
        }
    }

    public func setUpscaling(_ isOn: Bool) {
        guard family == .v1 else { return }
        enqueue(V1Command.setUpscaling(isOn: isOn))
        enqueue(V1Command.audioSetting(0x02))
        state.upscaling = isOn
    }

    /// The device acknowledges and then drops the link, which the caller sees as a close.
    public func powerOff() {
        enqueue(family == .v1 ? V1Command.powerOff() : V2Command.powerOff())
    }

    public func refresh() {
        capabilityQueries().forEach(enqueue)
    }

    // MARK: - Conversation

    private func handshake() {
        switch family {
        case .v1: [V1Command.protocolInfo(), V1Command.supportFunctions()].forEach(enqueue)
        case .v2: [V2Command.protocolInfo(), V2Command.supportFunctions()].forEach(enqueue)
        }
    }

    private func receive(_ frame: MDRFrame) {
        switch frame.type {
        case .ack:
            awaitingAcknowledgement?.cancel()
            awaitingAcknowledgement = nil
            sendNext()
        case .data:
            try? link.send(MDRFrame(type: .ack, sequence: frame.sequence ^ 1, payload: []))
            apply(frame.payload)
            sendNext()
        case .dataNo2:
            // Table 2 rides on its own data type and repeats opcodes with different meanings,
            // including a second support-function list in another id namespace. Acknowledged so
            // the device keeps talking, and otherwise left alone.
            try? link.send(MDRFrame(type: .ack, sequence: frame.sequence ^ 1, payload: []))
            sendNext()
        }
    }

    private func apply(_ payload: [UInt8]) {
        if let functions = MDRSupportFunctions(payload: payload, family: family)?.ids {
            state.capabilities = MDRCapabilities(functions: functions, family: family)
            noiseVariant = functions.compactMap(V2NoiseVariant.forFunction).first
            capabilityQueries().forEach(enqueue)
        }

        if let capability = V1NoiseCapability(payload: payload) {
            noiseSettingTypes = V1NoiseSettingTypes(capability)
            state.capabilities.refine(with: capability)
        }

        switch family {
        case .v1:
            if let noise = V1NoiseControl(payload: payload) {
                noiseSettingTypes = V1NoiseSettingTypes(noise)
                state.noise = noise.mode
            }
        case .v2:
            if let noise = V2NoiseControl(payload: payload) {
                state.noise = noise.mode
            }
        }

        if let capability = MDREqualizerCapability(payload: payload, family: family) {
            state.equalizerCapability = capability
        }

        if let equalizer = MDREqualizer(payload: payload, family: family) {
            state.equalizer = equalizer
        }

        switch MDRBattery(payload: payload, family: family) {
        case .cradle(let level): state.caseBattery = level
        case .some(let battery): state.battery = battery
        case nil: break
        }

        if let info = MDRGeneralSettingInfo(payload: payload, family: family) {
            settingNames[info.slot] = info.displayName
        }

        if let value = MDRGeneralSettingValue(payload: payload, family: family) {
            settingTypes[value.slot] = value.settingType
        }

        if let value = MDRGeneralSettingValue(payload: payload, family: family), let isOn = value.isOn {
            let setting = MDRSetting(
                slot: value.slot,
                name: settingNames[value.slot] ?? "Setting \(value.slot.hex)",
                isOn: isOn
            )
            if let index = state.settings.firstIndex(where: { $0.slot == value.slot }) {
                state.settings[index] = setting
            } else {
                state.settings.append(setting)
            }
        }

        if let upscaling = MDRUpscaling(payload: payload) {
            state.upscaling = upscaling.isOn
        }
    }

    private func capabilityQueries() -> [[UInt8]] {
        var queries: [[UInt8]] = []
        let capabilities = state.capabilities

        switch family {
        case .v1:
            // What the menu shows first is asked for first: every reply is a round trip, and the
            // panel fills in as they land.
            if capabilities.hasNoiseControl {
                queries.append(V1Command.noiseCapability())
                queries.append(V1Command.noise())
            }
            queries += capabilities.batteries.map(V1Command.battery)
            if capabilities.hasEqualizer {
                queries.append(V1Command.equalizerCapability())
                queries.append(V1Command.equalizer())
            }
            queries += capabilities.settingSlots.flatMap {
                [V1Command.generalSettingCapability(slot: $0), V1Command.generalSetting(slot: $0)]
            }
            if capabilities.hasUpscaling { queries.append(V1Command.audioSetting(0x02)) }
        case .v2:
            if let noiseVariant { queries.append(V2Command.noise(variant: noiseVariant)) }
            queries += capabilities.batteries.map(V2Command.battery)
            if capabilities.hasEqualizer {
                queries.append(V2Command.equalizerCapability())
                queries.append(V2Command.equalizer())
            }
            queries += capabilities.settingSlots.flatMap {
                [V2Command.generalSettingCapability(slot: $0), V2Command.generalSetting(slot: $0)]
            }
        }
        return queries
    }

    private func equalizerQuery() -> [UInt8] {
        family == .v1 ? V1Command.equalizer() : V2Command.equalizer()
    }

    private func enqueue(_ payload: [UInt8]) {
        queue.append(payload)
        sendNext()
    }

    private func sendNext() {
        guard awaitingAcknowledgement == nil else { return }
        guard !queue.isEmpty else {
            state.isReady = true
            return
        }

        let payload = queue.removeFirst()
        do {
            try link.send(MDRFrame(type: .data, sequence: sequence, payload: payload))
            sequence ^= 1
            waitForAcknowledgement()
        } catch {
            link.close()
        }
    }

    /// A device that stops acknowledging is gone as far as we are concerned; dropping the link
    /// lets whoever owns the session reconnect instead of queueing commands into the void.
    private func waitForAcknowledgement() {
        let timeout = DispatchWorkItem { [weak self] in self?.link.close() }
        awaitingAcknowledgement = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + acknowledgementTimeout, execute: timeout)
    }

    private func linkClosed() {
        awaitingAcknowledgement?.cancel()
        awaitingAcknowledgement = nil
        queue.removeAll()
        state = State()
        onClose?()
    }
}
