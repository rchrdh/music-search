// swift-tools-version: 5.9
import PackageDescription

// This package compiles the platform-agnostic search engine (the same files the
// iOS app uses, under MusicSearch/Engine) plus a command-line tool for refining
// recommendation quality off-device. It is independent of the Xcode app project.
let package = Package(
    name: "MusicSearchCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "MusicSearchCore", targets: ["MusicSearchCore"]),
        .executable(name: "musicsearch-eval", targets: ["musicsearch-eval"]),
    ],
    targets: [
        .target(
            name: "MusicSearchCore",
            path: "MusicSearch/Engine"
        ),
        .executableTarget(
            name: "musicsearch-eval",
            dependencies: ["MusicSearchCore"],
            path: "eval",
            exclude: ["README.md", "sample-albums.json"]
        ),
        .testTarget(
            name: "MusicSearchCoreTests",
            dependencies: ["MusicSearchCore"],
            path: "Tests/MusicSearchCoreTests"
        ),
    ]
)
