// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpatialAudioCalibrator",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "SpatialAudioCalibrator",
            targets: ["SpatialAudioCalibrator"]
        ),
    ],
    dependencies: [
        // No external dependencies - using only Apple frameworks
    ],
    targets: [
        .executableTarget(
            name: "SpatialAudioCalibrator",
            dependencies: [],
            path: "Sources/SpatialAudioCalibrator",
            swiftSettings: [
                // Swift 6 strict concurrency
                .enableUpcomingFeature("StrictConcurrency"),
                // Enable all Swift 6.0 features
                .enableUpcomingFeature("DisableOutwardActorInference"),
                .enableUpcomingFeature("GlobalConcurrency"),
                // Enable experimental features for better concurrency
                .enableExperimentalFeature("Span"),
                // Warning as error for strict quality
                .unsafeFlags(["-warnings-as-errors"], .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "SpatialAudioCalibratorTests",
            dependencies: ["SpatialAudioCalibrator"],
            path: "Tests/SpatialAudioCalibratorTests",
            swiftSettings: [
                // Swift 6 strict concurrency for tests too
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("DisableOutwardActorInference"),
                .enableUpcomingFeature("GlobalConcurrency"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v6]
)
