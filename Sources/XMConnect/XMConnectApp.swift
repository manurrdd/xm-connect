import MDRTransport
import SwiftUI
import XMConnectCore

@main
struct XMConnectApp: App {
    static let windowID = "controls"

    @StateObject private var controller = HeadphonesController(source: RFCOMMSource())

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller)
        } label: {
            Image(systemName: "headphones")
        }
        .menuBarExtraStyle(.window)

        Window("XM Connect", id: Self.windowID) {
            WindowView(controller: controller)
        }
        .windowResizability(.contentSize)
    }
}
