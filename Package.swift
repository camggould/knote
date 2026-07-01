// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "knote",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "knote", targets: ["knote"]),
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
        .testTarget(
            name: "KnoteCoreTests",
            dependencies: ["KnoteCore", "KnoteEmbeddings", "KnoteVector"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
