// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "xm-connect",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MDRKit"),
        .target(name: "MDRTransport", dependencies: ["MDRKit"]),
        .target(name: "MDRSession", dependencies: ["MDRKit"]),
        .executableTarget(name: "xmprobe", dependencies: ["MDRKit", "MDRTransport"]),
        .executableTarget(name: "XMConnect", dependencies: ["MDRKit", "MDRSession", "MDRTransport"]),
        .testTarget(name: "MDRKitTests", dependencies: ["MDRKit"]),
        .testTarget(name: "MDRSessionTests", dependencies: ["MDRSession"]),
    ]
)
