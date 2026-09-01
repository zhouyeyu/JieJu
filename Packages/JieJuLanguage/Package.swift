// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JieJuLanguage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JieJuLanguage", targets: ["JieJuLanguage"]),
        .executable(name: "JieJuAILab", targets: ["JieJuAILab"])
    ],
    targets: [
        .target(name: "JieJuLanguage"),
        .executableTarget(name: "JieJuAILab", dependencies: ["JieJuLanguage"]),
        .testTarget(name: "JieJuLanguageTests", dependencies: ["JieJuLanguage", "JieJuAILab"])
    ]
)
