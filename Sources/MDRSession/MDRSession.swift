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
    private var settingTypes: V1NoiseSettingTypes?
    private var noiseVariant: UInt8?

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
            guard let settingTypes else { return }
            enqueue(V1Command.setNoise(mode, settingTypes: settingTypes))
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
        case .data, .dataNo2:
            try? link.send(MDRFrame(type: .ack, sequence: frame.sequence ^ 1, payload: []))
            apply(frame.payload)
            sendNext()
        }
    }

    private func apply(_ payload: [UInt8]) {
        if let functions = MDRSupportFunctions(payload: payload, family: family)?.ids {
            state.capabilities = MDRCapabilities(functions: functions, family: family)
            noiseVariant = functions.compactMap(V2Command.noiseVariant(forFunction:)).first
            capabilityQueries().forEach(enqueue)
        }

        if let capability = V1NoiseCapability(payload: payload) {
            settingTypes = V1NoiseSettingTypes(capability)
            state.capabilities.refine(with: capability)
        }

        switch family {
        case .v1:
            if let noise = V1NoiseControl(payload: payload) {
                settingTypes = V1NoiseSettingTypes(noise)
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

        if let battery = MDRBattery(payload: payload, family: family) {
            state.battery = battery
        }
    }

    private func capabilityQueries() -> [[UInt8]] {
        var queries: [[UInt8]] = []
        let capabilities = state.capabilities

        switch family {
        case .v1:
            if capabilities.hasNoiseControl {
                queries.append(V1Command.noiseCapability())
                queries.append(V1Command.noise())
            }
            if capabilities.hasEqualizer {
                queries.append(V1Command.equalizerCapability())
                queries.append(V1Command.equalizer())
            }
            queries += capabilities.batteries.map(V1Command.battery)
        case .v2:
            if let noiseVariant { queries.append(V2Command.noise(variant: noiseVariant)) }
            if capabilities.hasEqualizer {
                queries.append(V2Command.equalizerCapability())
                queries.append(V2Command.equalizer())
            }
            queries += capabilities.batteries.map(V2Command.battery)
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
