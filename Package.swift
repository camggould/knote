// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "knote",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "knote", targets: ["knote"]),
        .executable(name: "knote-mcp", targets: ["knote-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "KnoteVector"
        ),
        .target(
            name: "KnoteEmbeddings"
        ),
        .target(
            name: "KnoteCore",
            dependencies: [
                "KnoteVector",
                "KnoteEmbeddings",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "knote",
            dependencies: ["KnoteCore", "KnoteEmbeddings", "KnoteVector"]
        ),
        .executableTarget(
            name: "knote-mcp",
            dependencies: ["KnoteCore", "KnoteEmbeddings", "KnoteVector"]
        ),
        .testTarget(
            name: "KnoteCoreTests",
            dependencies: [
                "KnoteCore", "KnoteEmbeddings", "KnoteVector",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
