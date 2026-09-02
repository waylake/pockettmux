// swift-tools-version: 6.0
// PocketTmuxKit — code shared by the iPhone app, the Mac app and pockettmuxd.
//
//   PocketTmuxKit    pure Swift, iOS + macOS: wire protocol, tmux parsers, pairing
//   PocketTmuxAgent  macOS only: the agent (WebSocket server + tmux control client)
import PackageDescription

let package = Package(
    name: "PocketTmuxKit",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [
        .library(name: "PocketTmuxKit", targets: ["PocketTmuxKit"]),
        .library(name: "PocketTmuxAgent", targets: ["PocketTmuxAgent"])
    ],
    targets: [
        .target(name: "PocketTmuxKit"),
        .target(
            name: "PocketTmuxAgent",
            dependencies: ["PocketTmuxKit"],
            linkerSettings: [.linkedFramework("IOKit", .when(platforms: [.macOS]))]
        ),
        .testTarget(name: "PocketTmuxKitTests", dependencies: ["PocketTmuxKit"]),
        .testTarget(name: "PocketTmuxAgentTests", dependencies: ["PocketTmuxAgent"])
    ]
)
