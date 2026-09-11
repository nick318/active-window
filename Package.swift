// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ActiveWindow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ActiveWindow",
            path: "Sources/ActiveWindow"
        )
    ]
)
