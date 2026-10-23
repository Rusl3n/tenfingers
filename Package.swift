// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "TenFingers",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "TenFingers", targets: ["TenFingers"])],
    targets: [
        .target(name: "TypingCore", resources: [.process("Resources")]),
        .executableTarget(name: "TenFingers", dependencies: ["TypingCore"]),
        .testTarget(name: "TypingCoreTests", dependencies: ["TypingCore"]),
        .testTarget(name: "TenFingersTests", dependencies: ["TenFingers", "TypingCore"]),
    ]
)
