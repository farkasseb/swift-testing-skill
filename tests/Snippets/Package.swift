// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Snippets",
    platforms: [.macOS(.v15)],
    targets: [.testTarget(name: "SnippetTests")]
)
