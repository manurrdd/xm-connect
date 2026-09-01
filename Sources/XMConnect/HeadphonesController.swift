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

    func powerOff() {
        session?.powerOff()
    }

    private func connect() {
        guard session == nil, !isConnecting else { return }
        isConnecting = true

        guard let found = RFCOMMConnection.discover().first else { return retry() }

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

        do {
            try session.start()
        } catch {
            return retry()
        }

        self.session = session
        device = found
        waitForHandshake()
    }

    /// A channel that opens but never finishes the handshake leaves the app looking connected and
    /// doing nothing, which is what happens when the headphones are paired but switched off.
    private func waitForHandshake() {
        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.session?.close() }
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
        session = nil
        device = nil
        state = MDRSession.State()
        retry()
    }

    private func retry() {
        session = nil
        isConnecting = false

        let delay = retryDelay
        retryDelay = min(delay * 2, maximumRetryDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.connect() }
        }
    }
}
