import Foundation
import MDRKit
import MDRSession
import MDRTransport

/// Keeps a session running against whichever paired headset is reachable, and gets it back after
/// the headphones are switched off, run out of range, or are told to power off from here.
@MainActor
final class HeadphonesController: ObservableObject {
    @Published private(set) var device: MDRDevice?
    @Published private(set) var state = MDRSession.State()

    private var session: MDRSession?
    private var isConnecting = false
    private var handshakeTimeout: DispatchWorkItem?
    private var retryDelay: TimeInterval = 2

    private let handshakeDeadline: TimeInterval = 8
    private let maximumRetryDelay: TimeInterval = 30

    var isConnected: Bool { state.isReady }

    /// Safe to call again: the menu runs it every time it opens.
    func start() {
        connect()
    }

    func setNoise(_ mode: MDRNoiseMode) {
        session?.setNoise(mode)
    }

    func setEqualizerPreset(_ preset: UInt8) {
        session?.setEqualizerPreset(preset)
    }

    func setSetting(slot: UInt8, isOn: Bool) {
        session?.setSetting(slot: slot, isOn: isOn)
    }

    func setUpscaling(_ isOn: Bool) {
        session?.setUpscaling(isOn)
    }

    func powerOff() {
        session?.powerOff()
    }

    private func connect() {
        guard session == nil, !isConnecting else { return }
        isConnecting = true

        guard let found = RFCOMMConnection.discover().first else {
            session = nil
            return retry()
        }

        let session = MDRSession(family: found.family, link: RFCOMMConnection(device: found))
        session.onStateChange = { [weak self] state in
            MainActor.assumeIsolated {
                self?.state = state
                if state.isReady { self?.settled() }
            }
        }
        session.onClose = { [weak self] in
            MainActor.assumeIsolated { self?.dropped() }
        }

        self.session = session
        device = found
        waitForHandshake()

        do {
            try session.start()
        } catch {
            dropped()
        }
    }

    /// A channel that opens but never finishes the handshake leaves the app looking connected and
    /// doing nothing, which is what paired-but-switched-off headphones do. Giving up here cannot
    /// wait for a close callback: an unopened channel never sends one.
    private func waitForHandshake() {
        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dropped() }
        }
        handshakeTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + handshakeDeadline, execute: timeout)
    }

    private func settled() {
        handshakeTimeout?.cancel()
        handshakeTimeout = nil
        isConnecting = false
        retryDelay = 2
    }

    private func dropped() {
        handshakeTimeout?.cancel()
        handshakeTimeout = nil

        // Detached before closing so the session's own close does not call back in here.
        let closing = session
        closing?.onStateChange = nil
        closing?.onClose = nil
        session = nil
        closing?.close()

        device = nil
        state = MDRSession.State()
        retry()
    }

    private func retry() {
        isConnecting = false

        let delay = retryDelay
        retryDelay = min(delay * 2, maximumRetryDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.connect() }
        }
    }
}
