import SwiftUI

@main
struct XMConnectApp: App {
    @StateObject private var controller = HeadphonesController()

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller)
        } label: {
            Image(systemName: "headphones")
        }
        .menuBarExtraStyle(.window)
    }
}
