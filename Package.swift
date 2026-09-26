// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Mozaic",
    defaultLocalization: "en",
    platforms: [
        .macOS("15.4"),
    ],
    products: [
        .executable(
            name: "Mozaic",
            targets: ["Mozaic"]
        ),
        .executable(
            name: "api-explorer",
            targets: ["APIExplorer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
    ],
    targets: [
        // Main app executable
        .executableTarget(
            name: "Mozaic",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: [
                "Resources/AppIcon.icon",
                "Resources/mozaic.icns",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .process("Resources/Localizable.xcstrings"),
                .process("Resources/Mozaic.sdef"),
                .copy("Extensions"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        // API Explorer CLI tool
        .executableTarget(
            name: "APIExplorer",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Unit tests
        .testTarget(
            name: "MozaicTests",
            dependencies: ["Mozaic"],
            // Tests for Apple-Intelligence-powered features are excluded
            // because the underlying APIs are macOS 26+ only and Swift
            // Testing's `@Test` / `@Suite` macros do not compose with
            // `@available(macOS 26, *)`.
            exclude: [
                "AIErrorHandlerTests.swift",
                "AIToolTests.swift",
                "CommandBarViewModelTests.swift",
                "CommandExecutorTests.swift",
                "CommandIntentParserTests.swift",
                "FoundationModelsOptimizedPromptIntegrationTests.swift",
                "FoundationModelsPromptLibraryTests.swift",
                "FoundationModelsServiceTests.swift",
                "FoundationModelsTests.swift",
                "MusicIntentIntegrationTests.swift",
                "MusicIntentTests.swift",
            ],
            resources: [
                .process("Fixtures"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
