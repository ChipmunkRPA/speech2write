// swift-tools-version: 6.2
// Speech2Write — an open-source CPA Automation fork of FluidVoice.
// Built with plain SwiftPM (Command Line Tools only, no Xcode). Swift settings
// below mirror the upstream Xcode project's build settings:
//   SWIFT_VERSION = 5.0, SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor,
//   SWIFT_APPROACHABLE_CONCURRENCY = YES, MemberImportVisibility upcoming feature.

import PackageDescription

let package = Package(
    name: "FluidVoice",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        // Supply-chain pinning (SR-5829 REQ-3): remote dependencies use their
        // public upstream repositories and are pinned to exact revisions.
        .package(url: "https://github.com/altic-dev/FluidAudio.git", revision: "72625bbccf9f6c797a540a1f1cb66a4cb60753eb"),
        // Vendored locally: upstream uses SwiftUI @Entry/#Preview macros whose
        // compiler plugins ship only with full Xcode (not Command Line Tools).
        .package(path: "Vendor/DynamicNotchKit"),
        .package(url: "https://github.com/ejbills/mediaremote-adapter.git", revision: "cf30c4f1af29b5829d859f088f8dbdf12611a046"),
    ],
    targets: [
        .executableTarget(
            name: "FluidVoice",
            dependencies: [
                .product(name: "FluidAudio", package: "fluidaudio"),
                "DynamicNotchKit",
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter"),
            ],
            path: "Sources/Fluid",
            exclude: ["Assets.xcassets", "Resources"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("InferSendableFromCaptures"),
                .enableUpcomingFeature("DisableOutwardActorInference"),
                .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
            ]
        ),
        .testTarget(
            name: "FluidVoiceTests",
            dependencies: ["FluidVoice"],
            path: "Tests/FluidVoiceTests"
        ),
    ]
)
