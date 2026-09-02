// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JieJuLanguage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JieJuLanguage", targets: ["JieJuLanguage"]),
        .executable(name: "JieJuAILab", targets: ["JieJuAILab"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/shinjukunian/Mecab-Swift.git",
            revision: "1f096492e37fc05fc2e7304091f54889974c5368"
        )
    ],
    targets: [
        .target(
            name: "JieJuLanguage",
            dependencies: [
                .product(name: "Mecab-Swift", package: "Mecab-Swift"),
                .product(name: "IPADic", package: "Mecab-Swift")
            ]
        ),
        .executableTarget(name: "JieJuAILab", dependencies: ["JieJuLanguage"]),
        .testTarget(name: "JieJuLanguageTests", dependencies: ["JieJuLanguage", "JieJuAILab"])
    ]
)
