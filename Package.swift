// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sleep-preventer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "sleep-preventer",
            targets: ["sleep-preventer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "sleep-preventer",
            path: "Sources",
            exclude: ["Info.plist", "sleep-preventer.entitlements"]
        )
    ]
)
