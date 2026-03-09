// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpatialAudioCalibrator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SpatialAudioCalibrator",
            targets: ["SpatialAudioCalibrator"]
        )
    ],
    dependencies: [
        // No external dependencies - using only Apple frameworks
    ],
    targets: [
        .executableTarget(
            name: "SpatialAudioCalibrator",
            dependencies: [],
            path: "Sources/SpatialAudioCalibrator"
        ),
        .testTarget(
            name: "SpatialAudioCalibratorTests",
            dependencies: ["SpatialAudioCalibrator"],
            path: "Tests/SpatialAudioCalibratorTests"
        )
    ]
)
