# Development Guide

## Getting Started

### Prerequisites

- **macOS 14.0+** (Sonoma or later)
- **Xcode 15.0+**
- **Apple Silicon Mac** (M1/M2/M3) recommended
- **Apple Developer Account** (for code signing)

### Project Setup

```bash
# Clone the repository
cd ~/Developer
git clone https://github.com/yourusername/spatial-audio-calibrator.git
cd spatial-audio-calibrator

# Open in Xcode
open SpatialAudioCalibrator.xcodeproj

# Or use Swift Package Manager
swift package generate-xcodeproj
```

### Project Structure

```
spatial-audio-calibrator/
├── Package.swift
├── README.md
├── docs/
│   ├── ARCHITECTURE.md
│   ├── HARDWARE.md
│   ├── AUDIO_PIPELINE.md
│   ├── DSP_PIPELINE.md
│   ├── CORE_AUDIO.md
│   ├── MEASUREMENT_PROTOCOL.md
│   ├── API_REFERENCE.md
│   └── DEVELOPMENT.md
├── Sources/
│   └── SpatialAudioCalibrator/
│       ├── App/
│       │   ├── SpatialAudioCalibratorApp.swift
│       │   └── ContentView.swift
│       ├── Core/
│       │   ├── AudioCalibrator.swift
│       │   ├── CalibrationConfig.swift
│       │   └── CalibrationState.swift
│       ├── Engine/
│       │   ├── AudioEngine.swift
│       │   ├── SweepGenerator.swift
│       │   └── LatencyCompensator.swift
│       ├── DSP/
│       │   ├── DeconvolutionEngine.swift
│       │   ├── FFTProcessor.swift
│       │   └── SpectralDivision.swift
│       ├── HAL/
│       │   ├── AudioDeviceManager.swift
│       │   ├── AggregateDevice.swift
│       │   └── ChannelMapper.swift
│       ├── Models/
│       │   ├── ImpulseResponse.swift
│       │   ├── AcousticParameters.swift
│       │   └── SpeakerChannel.swift
│       ├── UI/
│       │   ├── Views/
│       │   ├── ViewModels/
│       │   └── Components/
│       └── Utils/
│           ├── WAVEExporter.swift
│           ├── MathHelpers.swift
│           └── Extensions/
├── Tests/
│   ├── AudioEngineTests.swift
│   ├── SweepGeneratorTests.swift
│   ├── DeconvolutionTests.swift
│   └── IntegrationTests/
├── Assets.xcassets/
└── Config/
    └── default-config.json
```

## Dependencies

### Package.swift

```swift
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
            dependencies: []
        ),
        .testTarget(
            name: "SpatialAudioCalibratorTests",
            dependencies: ["SpatialAudioCalibrator"]
        )
    ]
)
```

### Frameworks Used

| Framework | Purpose |
|-----------|---------|
| `AVFAudio` | AVAudioEngine, audio graph |
| `CoreAudio` | HAL, device management |
| `Accelerate` | vDSP FFT operations |
| `AudioToolbox` | Audio utilities |
| `SwiftUI` | User interface |
| `Combine` | Reactive bindings |

## Building

### Debug Build

```bash
swift build

# Or in Xcode
# Product > Build (⌘B)
```

### Release Build

```bash
swift build -c release

# Release binary location
.build/release/SpatialAudioCalibrator
```

### Xcode Build Settings

Recommended settings for audio applications:

| Setting | Value | Reason |
|---------|-------|--------|
| Optimization Level | `-O` | Balance speed/size |
| Strict Concurrency | Complete | Thread safety |
| Dead Code Stripping | Yes | Smaller binary |
| Debug Information | DWARF with dSYM | Crash analysis |

## Testing

### Unit Tests

```bash
# Run all tests
swift test

# Run specific test
swift test --filter SweepGeneratorTests

# Verbose output
swift test --verbose
```

### Test Categories

```swift
// Audio Engine Tests
final class AudioEngineTests: XCTestCase {
    func testEngineInitialization()
    func testMultichannelFormat()
    func testChannelMapping()
    func testInputTap()
}

// Sweep Generator Tests
final class SweepGeneratorTests: XCTestCase {
    func testSweepGeneration()
    func testFrequencyRange()
    func testPhaseContinuity()
    func testAmplitudeConsistency()
}

// Deconvolution Tests
final class DeconvolutionTests: XCTestCase {
    func testFFTForward()
    func testFFTInverse()
    func testSpectralDivision()
    func testRegularization()
    func testKnownImpulseResponse()
}

// Integration Tests
final class IntegrationTests: XCTestCase {
    func testFullCalibrationSequence()
    func testLatencyCompensation()
}
```

### Performance Tests

```swift
func testFFTPerformance() {
    let processor = FFTProcessor(size: 262144)
    let input = [Float](repeating: 0.5, count: 262144)

    measure {
        for _ in 0..<100 {
            _ = processor.forwardFFT(input)
        }
    }
}
```

## Debugging

### Console Logging

```swift
enum LogLevel {
    case debug, info, warning, error
}

func log(_ level: LogLevel, _ message: String, file: String = #file, line: Int = #line) {
    #if DEBUG
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let filename = (file as NSString).lastPathComponent
    print("[\(timestamp)] [\(level)] \(filename):\(line) - \(message)")
    #endif
}
```

### Audio Debugging

```swift
// Enable Core Audio logging
// Set environment variable: COREAUDIO_DEBUG=1

// Log audio buffer state
func debugBuffer(_ buffer: AVAudioPCMBuffer) {
    print("Buffer frames: \(buffer.frameLength)")
    print("Channels: \(buffer.format.channelCount)")
    if let data = buffer.floatChannelData?[0] {
        let rms = sqrt(data.reduce(0) { $0 + $1 * $1 } / Float(buffer.frameLength))
        print("RMS level: \(20 * log10(rms)) dBFS")
    }
}
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Audio glitching | Buffer too small | Increase buffer size to 1024+ |
| Channel map ignored | Wrong scope | Use `kAudioUnitScope_Output` |
| FFT crashes | Non-power-of-2 | Use `nextPowerOf2()` |
| Memory growth | Leaked buffers | Check render block captures |
| Permission denied | Sandbox | Add microphone entitlement |

## Code Style

### Swift Conventions

```swift
// MARK: - Properties first, then init, then methods

class AudioEngine {
    // MARK: - Properties

    let engine: AVAudioEngine
    private(set) var isRunning = false

    // MARK: - Initialization

    init() throws {
        engine = AVAudioEngine()
        try configureEngine()
    }

    // MARK: - Public Methods

    func start() throws { ... }

    // MARK: - Private Methods

    private func configureEngine() throws { ... }
}
```

### Real-time Safety

```swift
// ❌ WRONG - allocations in render block
sourceNode = AVAudioSourceNode { _, _, frameCount, output in
    var buffer = [Float](repeating: 0, count: Int(frameCount))  // ALLOCATION!
    // ...
}

// ✅ CORRECT - pre-allocated buffers
class SweepGenerator {
    private var phaseAccumulator: Double = 0  // Pre-allocated state

    func render(frameCount: AVAudioFrameCount, output: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        // No allocations, no locks, no Objective-C
        let buffer = UnsafeMutableAudioBufferListPointer(output)
        for i in 0..<Int(frameCount) {
            let sample = Float(sin(phaseAccumulator))
            phaseAccumulator += phaseIncrement
            buffer[0].mData?.assumingMemoryBound(to: Float.self)[i] = sample
        }
        return noErr
    }
}
```

### Documentation

```swift
/// Generates a logarithmic sine sweep for acoustic measurement.
///
/// The sweep traverses from `startFrequency` to `endFrequency` exponentially,
/// spending equal time in each octave. This property ensures balanced energy
/// distribution and enables harmonic distortion separation during deconvolution.
///
/// - Parameters:
///   - startFrequency: Lower frequency bound (default: 20 Hz)
///   - endFrequency: Upper frequency bound (default: 20000 Hz)
///   - duration: Total sweep duration in seconds
///   - sampleRate: Output sample rate (default: 48000 Hz)
///
/// - Note: This class must be used in a real-time safe context.
///         Do not allocate memory or acquire locks in `render()`.
class SweepGenerator { ... }
```

## Performance Optimization

### Profiling

```bash
# Time profiler
instruments -t "Time Profiler" .build/debug/SpatialAudioCalibrator

# Allocations
instruments -t "Allocations" .build/debug/SpatialAudioCalibrator

# Audio profiling
instruments -t "Audio" .build/debug/SpatialAudioCalibrator
```

### Optimization Tips

1. **Pre-allocate all buffers** - No allocations in render path
2. **Use SIMD** - vDSP is already optimized for Apple Silicon
3. **Avoid bridging** - Stay in Swift/C, avoid Objective-C
4. **Cache calculations** - Pre-compute constants
5. **Batch operations** - Single vDSP calls over loops

### Memory Budget

| Component | Size | Notes |
|-----------|------|-------|
| FFT buffers | ~2 MB | 2 × 262,144 × 4 bytes |
| Recording buffer | ~2.5 MB | 7 sec × 48 kHz × 4 bytes |
| Engine overhead | ~1 MB | AVAudioEngine internal |
| **Total** | **~6 MB** | Target < 10 MB |

## Release Checklist

- [ ] All tests passing
- [ ] Code signed with Developer ID
- [ ] Notarized by Apple
- [ ] Version number updated
- [ ] Release notes prepared
- [ ] Documentation updated

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

### Pull Request Guidelines

- Include tests for new functionality
- Update documentation
- Follow existing code style
- Keep PRs focused (one feature per PR)
