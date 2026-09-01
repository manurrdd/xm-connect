import Foundation
import MDRKit
import MDRSession

/// Owns the session while something is showing it.
///
/// A headset accepts one control session at a time, so holding the channel for as long as the app
/// runs locks Sony's own phone app out. It is also not this app's place to bring a headset online:
/// one that is paired but disconnected is left alone rather than connected behind the user's back.
@MainActor
public final class HeadphonesController: ObservableObject {
    public struct Timings {
        public var handshake: TimeInterval = 8
        /// Long enough to survive closing and reopening the menu, short enough that the phone app
        /// is usable again straight after.
        public var release: TimeInterval = 5
        public var retry: TimeInterval = 2
        public var maximumRetry: TimeInterval = 8

        public init() {}
    }

    @Published public private(set) var device: HeadphonesDescription?
    @Published public private(set) var state = MDRSession.State()
    /// Set when the headset is paired but not connected to this machine, which is a different
    /// thing for the user to fix than not finding one at all.
    @Published public private(set) var isOffline = false
    /// Whether a settled session is behind what is on screen. The reading outlives the session, so
    /// reopening shows the last one straight away instead of an empty panel.
    @Published public private(set) var isLive = false

    private let source: HeadphonesSource
    private let timings: Timings

    private var session: MDRSession?
    private var handshakeTimeout: DispatchWorkItem?
    private var release: DispatchWorkItem?
    private var viewers = 0
    private var isConnecting = false
    private var retryDelay: TimeInterval

    public init(source: HeadphonesSource, timings: Timings = Timings()) {
        self.source = source
        self.timings = timings
        retryDelay = timings.retry
    }

    public var hasReading: Bool { state.noise != nil || state.battery != nil }

    /// A view started showing the headset. The session lives while at least one is.
    public func acquire() {
        release?.cancel()
        release = nil
        viewers += 1
        retryDelay = timings.retry
        connect()
    }

    public func relinquish() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }

        let release = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.teardown(keepingReading: true) }
        }
        self.release = release
        DispatchQueue.main.asyncAfter(deadline: .now() + timings.release, execute: release)
    }

    public func setNoise(_ mode: MDRNoiseMode) {
        session?.setNoise(mode)
    }

    public func setEqualizerPreset(_ preset: UInt8) {
        session?.setEqualizerPreset(preset)
    }

    public func setSetting(slot: UInt8, isOn: Bool) {
        session?.setSetting(slot: slot, isOn: isOn)
    }

    public func setSystemSwitch(_ setting: MDRSystemSwitch, isOn: Bool) {
        session?.setSystemSwitch(setting, isOn: isOn)
    }

    public func setAutoPowerOff(_ value: MDRAutoPowerOff) {
        session?.setAutoPowerOff(value)
    }

    public func setUpscaling(_ isOn: Bool) {
        session?.setUpscaling(isOn)
    }

    public func powerOff() {
        session?.powerOff()
    }

    private func connect() {
        guard viewers > 0, session == nil, !isConnecting else { return }
        isConnecting = true

        let found = source.discover()
        guard let headphones = found.first(where: \.isConnected) else {
            isOffline = !found.isEmpty
            isConnecting = false
            // Nothing is there to keep a reading true any more.
            device = nil
            state = MDRSession.State()
            return retry()
        }
        isOffline = false

        let link: MDRLink
        do {
            link = try source.link(to: headphones)
        } catch {
            isConnecting = false
            return retry()
        }

        let session = MDRSession(family: headphones.family, link: link)
        session.onStateChange = { [weak self] state in
            MainActor.assumeIsolated {
                // A fresh session starts blank; the reading on screen stands until it says more.
                if state.noise != nil || state.battery != nil || state.isReady {
                    self?.state = state
                }
                if state.isReady { self?.settled() }
            }
        }
        session.onClose = { [weak self] in
            MainActor.assumeIsolated { self?.dropped() }
        }

        self.session = session
        device = headphones
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
        DispatchQueue.main.asyncAfter(deadline: .now() + timings.handshake, execute: timeout)
    }

    private func settled() {
        handshakeTimeout?.cancel()
        handshakeTimeout = nil
        isConnecting = false
        isLive = true
        retryDelay = timings.retry
    }

    private func dropped() {
        teardown(keepingReading: false)
        retry()
    }

    /// A reading survives letting go of the channel on purpose. It does not survive the headset
    /// dropping off, because then there is nothing to say it is still true.
    private func teardown(keepingReading: Bool) {
        handshakeTimeout?.cancel()
        handshakeTimeout = nil
        isConnecting = false

        // Detached before closing so the session's own close does not call back in here.
        let closing = session
        closing?.onStateChange = nil
        closing?.onClose = nil
        session = nil
        closing?.close()

        isLive = false
        if !keepingReading {
            device = nil
            state = MDRSession.State()
        }
    }

    private func retry() {
        guard viewers > 0 else { return }

        let delay = retryDelay
        retryDelay = min(delay * 2, timings.maximumRetry)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.connect() }
        }
    }
}
