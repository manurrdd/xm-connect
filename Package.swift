// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "xm-connect",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MDRKit"),
        .target(name: "MDRTransport", dependencies: ["MDRKit"]),
        .target(name: "MDRSession", dependencies: ["MDRKit"]),
        .target(name: "XMConnectCore", dependencies: ["MDRKit", "MDRSession"]),
        .executableTarget(name: "xmprobe", dependencies: ["MDRKit", "MDRTransport"]),
        .executableTarget(name: "XMConnect", dependencies: ["XMConnectCore", "MDRTransport"]),
        .testTarget(name: "MDRKitTests", dependencies: ["MDRKit"]),
        .testTarget(name: "MDRSessionTests", dependencies: ["MDRSession"]),
        .testTarget(name: "XMConnectCoreTests", dependencies: ["XMConnectCore"]),
    ]
)
