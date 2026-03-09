# API Reference

## Core Classes

### `AudioCalibrator`

Main orchestrator for the calibration process.

```swift
class AudioCalibrator: ObservableObject {
    // MARK: - Published Properties

    @Published var state: CalibrationState
    @Published var progress: MeasurementProgress?
    @Published var currentAnalysis: SpeakerAnalysis?
    @Published var error: CalibrationError?

    // MARK: - Configuration

    var config: CalibrationConfig

    // MARK: - Results

    var measurements: [SpeakerMeasurement]

    // MARK: - Initialization

    init(config: CalibrationConfig = .default)

    // MARK: - Public Methods

    /// Check system readiness
    func verifySystemConfiguration() async throws -> SystemStatus

    /// Start full calibration sequence
    func startCalibration() async throws

    /// Measure single speaker
    func measureSpeaker(_ speaker: SpeakerChannel) async throws -> ImpulseResponse

    /// Stop current measurement
    func stopCalibration()

    /// Export results
    func exportResults(to url: URL) async throws
}
```

### `CalibrationConfig`

Configuration parameters for measurement.

```swift
struct CalibrationConfig {
    // Sweep parameters
    var startFrequency: Double      // Default: 20 Hz
    var endFrequency: Double        // Default: 20000 Hz
    var sweepDuration: Double       // Default: 5.0 seconds
    var sampleRate: Double          // Default: 48000 Hz
    var outputAmplitude: Float      // Default: 0.8 (0-1)

    // Recording parameters
    var preSweepSilence: Double     // Default: 0.5 seconds
    var postSweepSilence: Double    // Default: 2.0 seconds

    // Processing parameters
    var fftSize: Int                // Default: 262144 (2^18)
    var regularizationDB: Float     // Default: -60 dB

    // Microphone calibration
    var microphoneCalibrationFile: URL?

    static let `default` = CalibrationConfig()
}
```

### `SpeakerChannel`

Enumeration of supported speaker channels.

```swift
enum SpeakerChannel: Int, CaseIterable, Identifiable {
    case frontLeft = 0
    case frontRight = 1
    case center = 2
    case lfe = 3
    case rearLeft = 4
    case rearRight = 5

    var id: Int { rawValue }

    var displayName: String { get }
    var coreAudioLabel: AudioChannelLabel { get }
    var shortName: String { get }  // "FL", "FR", "C", etc.
}
```

### `CalibrationState`

State machine for calibration process.

```swift
enum CalibrationState: Equatable {
    case idle
    case initializing
    case verifying
    case ready
    case measuring(SpeakerChannel)
    case processing(SpeakerChannel)
    case completed
    case error(CalibrationError)
}
```

---

## Audio Engine

### `AudioEngine`

Manages AVAudioEngine and audio routing.

```swift
class AudioEngine {
    // MARK: - Properties

    var engine: AVAudioEngine { get }
    var isRunning: Bool { get }
    var outputFormat: AVAudioFormat? { get }
    var inputFormat: AVAudioFormat? { get }

    // MARK: - Initialization

    /// Create engine with specified output device
    init(outputDeviceID: AudioDeviceID? = nil) throws

    // MARK: - Configuration

    /// Configure for multichannel output
    func configureMultichannel(channelCount: Int) throws

    /// Set channel map for speaker isolation
    func setChannelMap(_ map: [Int32]) throws

    /// Set channel map for specific speaker
    func routeToSpeaker(_ speaker: SpeakerChannel) throws

    /// Mute all output channels
    func muteAll() throws

    // MARK: - Engine Control

    /// Start audio engine
    func start() throws

    /// Stop audio engine
    func stop()

    // MARK: - Input/Output

    /// Install tap on input node
    func installInputTap(bufferSize: AVAudioFrameCount) throws

    /// Remove input tap
    func removeInputTap()

    /// Get current input buffer
    func getRecordedBuffer() -> [Float]
}
```

### `SweepGenerator`

Generates logarithmic sine sweeps.

```swift
class SweepGenerator {
    // MARK: - Properties

    var startFrequency: Double
    var endFrequency: Double
    var duration: Double
    var sampleRate: Double
    var amplitude: Float

    var isRunning: Bool { get }
    var currentProgress: Double { get }  // 0.0 - 1.0
    var currentFrequency: Double { get }

    // MARK: - Initialization

    init(
        startFrequency: Double = 20,
        endFrequency: Double = 20000,
        duration: Double = 5.0,
        sampleRate: Double = 48000,
        amplitude: Float = 0.8
    )

    // MARK: - Control

    /// Start sweep generation
    func start()

    /// Stop and reset
    func stop()

    /// Reset to beginning
    func reset()

    // MARK: - Render

    /// Render callback for AVAudioSourceNode
    /// IMPORTANT: Must be allocation-free for real-time safety
    func render(
        frameCount: AVAudioFrameCount,
        outputBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus
}
```

---

## DSP Processing

### `DeconvolutionEngine`

Extracts impulse responses from recordings.

```swift
class DeconvolutionEngine {
    // MARK: - Properties

    var fftSize: Int { get }
    var regularizationThreshold: Float { get set }

    // MARK: - Initialization

    init(fftSize: Int = 262144, regularizationThreshold: Float = -60)

    // MARK: - Processing

    /// Extract impulse response from recording
    func extractImpulseResponse(
        excitation: [Float],
        recording: [Float]
    ) async throws -> ImpulseResponse

    /// Process with progress callback
    func extractImpulseResponse(
        excitation: [Float],
        recording: [Float],
        progress: @escaping (Double) -> Void
    ) async throws -> ImpulseResponse
}
```

### `ImpulseResponse`

Represents a measured impulse response.

```swift
struct ImpulseResponse: Codable {
    // MARK: - Properties

    let samples: [Float]
    let sampleRate: Double
    let fftSize: Int
    let measurementDate: Date
    let speaker: SpeakerChannel

    var duration: Double { get }  // seconds
    var sampleCount: Int { get }

    // MARK: - Analysis

    /// Calculate acoustic parameters
    func analyze() -> AcousticParameters

    /// Get frequency response
    func frequencyResponse(
        frequencies: [Double]
    ) -> [(frequency: Double, magnitude: Double, phase: Double)]

    /// Get energy decay curve
    func energyDecayCurve() -> [Double]

    // MARK: - Export

    /// Export as WAV file
    func exportWAV(to url: URL) throws

    /// Trim trailing silence
    func trimmed(thresholdDB: Float = -80) -> ImpulseResponse
}
```

### `AcousticParameters`

Acoustic measurements derived from impulse response.

```swift
struct AcousticParameters: Codable {
    // Time domain
    let peakAmplitude: Float
    let peakSample: Int
    let peakTime: Double  // milliseconds

    // Reverberation
    let rt60: Double       // seconds
    let edt: Double        // Early Decay Time, seconds
    let itdg: Double       // Initial Time Delay Gap, ms

    // Clarity and definition
    let c80: Double        // Clarity C80, dB
    let c50: Double        // Clarity C50, dB
    let d50: Double        // Definition D50, ratio
    let d80: Double        // Definition D80, ratio

    // Frequency range
    let effectiveLowFrequency: Double   // Hz
    let effectiveHighFrequency: Double  // Hz

    // Quality metrics
    let signalToNoiseRatio: Double  // dB
    let dynamicRange: Double        // dB
}
```

---

## Core Audio HAL

### `AudioDeviceManager`

Low-level Core Audio device management.

```swift
class AudioDeviceManager {
    // MARK: - Device Enumeration

    /// Get all audio devices
    static func getAllDevices() -> [AudioDeviceID]

    /// Get output devices only
    static func getOutputDevices() -> [AudioDeviceID]

    /// Get input devices only
    static func getInputDevices() -> [AudioDeviceID]

    /// Find HDMI device
    static func findHDMIDevice() -> AudioDeviceID?

    /// Get default output device
    static func getDefaultOutputDevice() -> AudioDeviceID?

    // MARK: - Device Properties

    static func getName(_ deviceID: AudioDeviceID) -> String?
    static func getUID(_ deviceID: AudioDeviceID) -> String?
    static func getTransportType(_ deviceID: AudioDeviceID) -> UInt32?
    static func getSampleRate(_ deviceID: AudioDeviceID) -> Float64?
    static func getChannelCount(_ deviceID: AudioDeviceID) -> UInt32?
    static func isHDMI(_ deviceID: AudioDeviceID) -> Bool

    // MARK: - Configuration

    static func setSampleRate(_ deviceID: AudioDeviceID, rate: Float64) -> Bool
    static func setChannelLayout(_ deviceID: AudioDeviceID, layout: AudioChannelLayout) -> Bool
    static func setBufferFrameSize(_ deviceID: AudioDeviceID, size: UInt32) -> Bool

    // MARK: - Latency

    static func getBufferConfiguration(_ deviceID: AudioDeviceID) -> BufferConfiguration?
    static func calculateTotalLatency(_ config: BufferConfiguration) -> UInt32

    // MARK: - Aggregate Devices

    static func createAggregateDevice(
        masterID: AudioDeviceID,
        secondaryID: AudioDeviceID,
        name: String
    ) -> AudioDeviceID?

    static func destroyAggregateDevice(_ deviceID: AudioDeviceID) -> Bool
}
```

### `BufferConfiguration`

Audio buffer and latency information.

```swift
struct BufferConfiguration {
    var bufferSize: UInt32
    var safetyOffsetOutput: UInt32
    var safetyOffsetInput: UInt32
    var streamLatencyOutput: UInt32
    var streamLatencyInput: UInt32

    var totalLatency: UInt32 { get }
    var latencyMs: Double { get }  // at 48kHz
}
```

---

## Error Types

### `CalibrationError`

```swift
enum CalibrationError: Error, LocalizedError {
    case noHDMIDevice
    case unsupportedFormat
    case configurationFailed(String)
    case measurementFailed(String)
    case processingFailed(String)
    case exportFailed(String)
    case permissionDenied
    case deviceBusy
    case engineNotRunning
    case noMicrophoneAccess

    var errorDescription: String? { get }
}
```

---

## Protocols

### `SignalProcessor`

Protocol for DSP operations.

```swift
protocol SignalProcessor {
    func process(input: [Float]) -> [Float]
    func reset()
}
```

### `AudioRenderer`

Protocol for audio output.

```swift
protocol AudioRenderer {
    var isPlaying: Bool { get }
    func start()
    func stop()
    func render(frameCount: AVAudioFrameCount, buffer: UnsafeMutablePointer<AudioBufferList>) -> OSStatus
}
```

---

## SwiftUI Views

### `CalibrationView`

Main calibration interface.

```swift
struct CalibrationView: View {
    @StateObject var calibrator: AudioCalibrator

    var body: some View { ... }
}
```

### `MeasurementProgressView`

Shows real-time measurement progress.

```swift
struct MeasurementProgressView: View {
    let progress: MeasurementProgress

    var body: some View { ... }
}
```

### `ImpulseResponseView`

Visualizes measured impulse response.

```swift
struct ImpulseResponseView: View {
    let impulseResponse: ImpulseResponse
    var displayMode: DisplayMode  // .waveform, .spectrum, .waterfall

    var body: some View { ... }
}
```

### `FrequencyResponseView`

Frequency response graph.

```swift
struct FrequencyResponseView: View {
    let response: [(frequency: Double, magnitude: Double)]
    var frequencyRange: ClosedRange<Double> = 20...20000
    var magnitudeRange: ClosedRange<Double> = -60...6

    var body: some View { ... }
}
```
