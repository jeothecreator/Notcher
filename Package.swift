// swift-tools-version:5.9
import PackageDescription

// NotcherCore holds every game engine and all of the meta systems (scores,
// achievements, daily challenges). It only depends on Foundation, so it builds
// and is tested on any platform. The Notcher app target (AppKit + SwiftUI) is
// macOS-only.
var targets: [Target] = [
    .target(
        name: "NotcherCore",
        path: "Sources/NotcherCore"
    ),
    .testTarget(
        name: "NotcherCoreTests",
        dependencies: ["NotcherCore"],
        path: "Tests/NotcherCoreTests"
    ),
]

var products: [Product] = [
    .library(name: "NotcherCore", targets: ["NotcherCore"]),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "Notcher",
        dependencies: ["NotcherCore"],
        path: "Sources/Notcher"
    )
)
products.append(.executable(name: "Notcher", targets: ["Notcher"]))
#endif

let package = Package(
    name: "Notcher",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
