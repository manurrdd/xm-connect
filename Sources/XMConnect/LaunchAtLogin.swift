import ServiceManagement

/// Registering asks the system, which may hold the request until the user approves it in Settings.
/// Pending counts as on: the app is registered, and showing it off would invite a second attempt.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = Self.isRegistered
    }

    func refresh() {
        isEnabled = Self.isRegistered
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Left to the refresh below: whatever the system ended up doing is what gets shown.
        }
        refresh()
    }

    private static var isRegistered: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: true
        default: false
        }
    }
}
