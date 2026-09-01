import AppKit
import SwiftUI

/// Reports when the menu bar panel opens and closes.
///
/// `onDisappear` is not delivered when a `MenuBarExtra` panel closes, so the window's own key
/// notifications are what the session lifetime hangs on.
struct PanelVisibility: NSViewRepresentable {
    let onOpen: () -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.observe(view.window, onOpen: onOpen, onClose: onClose)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        func observe(_ window: NSWindow?, onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
            guard let window, window !== self.window else { return }
            stop()
            self.window = window

            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                    onOpen()
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
                    onClose()
                },
            ]
        }

        private func stop() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        deinit {
            stop()
        }
    }
}
