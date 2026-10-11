// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CodexQuotaBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "CodexQuotaBar"),
        .testTarget(name: "CodexQuotaBarTests", dependencies: ["CodexQuotaBar"])
    ]
)
