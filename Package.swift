// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Orbit", targets: ["Orbit"]),
    ],
    targets: [
        // Pure, AppKit-free logic (timeline, geometry, project file). Fully unit tested.
        .target(name: "OrbitCore"),
        // The menu bar app: capture toolbar, camera bubble, recorder, editor.
        .executableTarget(name: "Orbit", dependencies: ["OrbitCore"]),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"]),
    ],
    swiftLanguageModes: [.v5]
)
