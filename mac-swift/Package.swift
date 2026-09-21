// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BluerBubblesMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "bluer-bubbles-mac",
            targets: ["BluerBubblesMac"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.0.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "BluerBubblesMac",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
