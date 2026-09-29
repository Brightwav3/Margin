// swift-tools-version:6.0
import PackageDescription

// MarginCore builds on Linux and macOS. MarginUI (SwiftUI) is macOS-only.
var products: [Product] = [
    .library(name: "MarginCore", targets: ["MarginCore"]),
]

var targets: [Target] = [
    .target(
        name: "MarginCore",
        path: "Sources/MarginCore"
    ),
    .testTarget(
        name: "MarginCoreTests",
        dependencies: ["MarginCore"],
        path: "Tests/MarginCoreTests"
    ),
    .testTarget(
        name: "ConformanceTests",
        dependencies: ["MarginCore"],
        path: "Tests/Conformance"
    ),
]

#if os(macOS)
products.append(.library(name: "MarginUI", targets: ["MarginUI"]))
products.append(.library(name: "MarginPlatform", targets: ["MarginPlatform"]))
targets.append(
    .target(
        name: "MarginUI",
        dependencies: ["MarginCore"],
        path: "Sources/MarginUI",
        resources: [.copy("Resources/Fonts"), .copy("Resources/lucide-icons.json"), .copy("Resources/LICENSE-lucide.txt")]
    )
)
// Debug tool: renders a gallery screen to PNG (scripts/snap.sh).
targets.append(
    .executableTarget(
        name: "margin-snap",
        dependencies: ["MarginUI"],
        path: "Sources/MarginSnap"
    )
)
targets.append(
    .testTarget(
        name: "MarginUITests",
        dependencies: ["MarginUI"],
        path: "Tests/MarginUITests"
    )
)
// macOS platform services (global hotkey, ...). Not built on Linux.
targets.append(
    .target(
        name: "MarginPlatform",
        dependencies: ["MarginCore"],
        path: "App/Platform"
    )
)
#endif

let package = Package(
    name: "Margin",
    platforms: [.macOS("27.0")],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
