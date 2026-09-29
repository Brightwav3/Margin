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
targets.append(
    .target(
        name: "MarginUI",
        dependencies: ["MarginCore"],
        path: "Sources/MarginUI"
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
