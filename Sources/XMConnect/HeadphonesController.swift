import Foundation
import MDRKit
import MDRSession
import MDRTransport

/// Owns the session while the menu is open.
///
/// A headset accepts one control session at a time, so holding the channel for as long as the app
/// runs locks Sony's own phone app out. It is also not this app's place to bring a headset online:
/// a headset that is paired but disconnected is left alone rather than connected behind the user's
/// back.
@MainActor
final class HeadphonesController: ObservableObject {
    @Published private(set) var device: MDRDevice?
    @Published private(set) var state = MDRSession.State()
    /// Set when the headset is paired but not connected to this Mac, which is a different thing
    /// for the user to fix than not finding one at all.
    @Published private(set) var isOffline = false

    private var session: MDRSession?
    private var handshakeTimeout: DispatchWorkItem?
    private var release: DispatchWorkItem?
    private var isActive = false
    private var isConnecting = false
    private var retryDelay: TimeInterval = 2

    private let handshakeDeadline: TimeInterval = 8
    private let maximumRetryDelay: TimeInterval = 8
    /// Long enough to survive closing and reopening the menu, short enough that the phone app is
    /// usable again straight after.
    private let releaseDelay: TimeInterval = 5

    var isConnected: Bool { state.isReady }

    func menuOpened() {
        release?.cancel()
        release = nil
        isActive = true
        retryDelay = 2
        connect()
    }

    func menuClosed() {
        isActive = false
        let release = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.teardown() }
        }
        self.release = release
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseDelay, execute: release)
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
        guard isActive, session == nil, !isConnecting else { return }
        isConnecting = true

        let devices = RFCOMMConnection.discover()
        guard let found = devices.first(where: \.isConnected) else {
            isOffline = !devices.isEmpty
            isConnecting = false
            return retry()
        }
        isOffline = false

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

    /// A channel that opens but never finishes the handshake sends no close callback, so giving up
    /// has to happen here or the session stays half alive and blocks every later attempt.
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
        teardown()
        retry()
    }

    private func teardown() {
        handshakeTimeout?.cancel()
        handshakeTimeout = nil
        isConnecting = false

        // Detached before closing so the session's own close does not call back in here.
        let closing = session
        closing?.onStateChange = nil
        closing?.onClose = nil
        session = nil
        closing?.close()

        device = nil
        state = MDRSession.State()
    }

    private func retry() {
        guard isActive else { return }

        let delay = retryDelay
        retryDelay = min(delay * 2, maximumRetryDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.connect() }
        }
    }
}
