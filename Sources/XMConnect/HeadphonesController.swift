import Foundation
import MDRKit
import MDRSession
import MDRTransport

/// Keeps a session running against whichever paired headset is reachable, and reconnects when the
/// headphones are switched off or walk out of range.
@MainActor
final class HeadphonesController: ObservableObject {
    @Published private(set) var device: MDRDevice?
    @Published private(set) var state = MDRSession.State()

    private var session: MDRSession?
    private var retryDelay: TimeInterval = 2
    private let maximumRetryDelay: TimeInterval = 30

    var isConnected: Bool { state.isReady }

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
        guard let found = RFCOMMConnection.discover().first else { return retry() }

        let session = MDRSession(family: found.family, link: RFCOMMConnection(device: found))
        session.onStateChange = { [weak self] state in
            MainActor.assumeIsolated { self?.state = state }
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
        retryDelay = 2
    }

    private func dropped() {
        session = nil
        device = nil
        state = MDRSession.State()
        retry()
    }

    private func retry() {
        let delay = retryDelay
        retryDelay = min(delay * 2, maximumRetryDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.connect() }
        }
    }
}
