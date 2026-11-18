// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "StudyCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "StudyCore", targets: ["StudyCore"])],
    targets: [
        .target(name: "StudyCore", path: "StudyApp/Core"),
        .testTarget(name: "StudyCoreTests", dependencies: ["StudyCore"], path: "Tests")
    ]
)
