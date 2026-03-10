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
                // Enable experimental features for better concurrency
                .enableExperimentalFeature("Span"),
                // Warning as error for strict quality
                .unsafeFlags(["-warnings-as-errors"], .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "SpatialAudioCalibratorTests",
            dependencies: ["SpatialAudioCalibrator"],
            path: "Tests/SpatialAudioCalibratorTests"
        ),
    ],
    swiftLanguageVersions: [.v6]
)
