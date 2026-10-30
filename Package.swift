// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CircleLab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CircleLab",
            path: "Sources/CircleLab"
        )
    ]
)
