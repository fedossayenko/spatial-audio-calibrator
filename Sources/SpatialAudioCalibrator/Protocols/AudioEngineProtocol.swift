import CoreAudio
import Foundation

/// Protocol for audio engine operations.
///
/// This abstraction enables testing without real audio hardware.
/// The production implementation uses AVAudioEngine, while tests can use mocks.
///
/// - Note: This protocol intentionally does not require Sendable conformance
///   because AVAudioEngine is not Sendable and must be used from a single thread/queue.
public protocol AudioEngineProtocol: AnyObject {
    // MARK: - Lifecycle

    /// Initialize the engine with an optional output device
    init(outputDeviceID: AudioDeviceID?) throws

    // MARK: - State

    /// Whether the engine is currently running
    var isRunning: Bool { get }

    /// Whether a sweep is currently playing
    var isSweepPlaying: Bool { get }

    /// Whether currently recording
    var isCurrentlyRecording: Bool { get }

    /// Current latency information
    var latencyInfo: BufferConfiguration? { get }

    // MARK: - Engine Control

    /// Start the audio engine
    func start() throws

    /// Stop the audio engine
    func stop()

    // MARK: - Channel Mapping

    /// Set channel map to route signal to a specific speaker
    func setChannelMap(target: SpeakerChannel) throws

    /// Mute all output channels
    func muteAll() throws

    // MARK: - Sweep Control

    /// Configure sweep parameters
    func configureSweep(
        startFrequency: Double,
        endFrequency: Double,
        duration: Double,
        sampleRate: Double,
        amplitude: Float
    )

    /// Start sweep playback
    func startSweep()

    /// Stop sweep playback
    func stopSweep()

    // MARK: - Recording

    /// Start recording from input
    func startRecording()

    /// Stop recording and return captured samples
    func stopRecording() -> [Float]

    // MARK: - Latency Compensation

    /// Compensate recording for measured latency
    func compensateLatency(_ recording: [Float]) -> [Float]
}

/// Protocol for audio device management operations.
///
/// This abstraction enables testing device enumeration and configuration
/// without requiring actual audio hardware.
public protocol AudioDeviceManaging: Sendable {
    // MARK: - Device Enumeration

    /// Get all audio devices in the system
    func getAllDevices() -> [AudioDeviceID]

    /// Get only output devices
    func getOutputDevices() -> [AudioDeviceID]

    /// Get only input devices
    func getInputDevices() -> [AudioDeviceID]

    /// Find HDMI audio device
    func findHDMIDevice() -> AudioDeviceID?

    /// Get default output device
    func getDefaultOutputDevice() -> AudioDeviceID?

    // MARK: - Device Properties

    /// Get device name
    func getName(_ deviceID: AudioDeviceID) -> String?

    /// Get device UID
    func getUID(_ deviceID: AudioDeviceID) -> String?

    /// Get transport type
    func getTransportType(_ deviceID: AudioDeviceID) -> UInt32?

    /// Get current sample rate
    func getSampleRate(_ deviceID: AudioDeviceID) -> Double?

    /// Check if device is HDMI
    func isHDMI(_ deviceID: AudioDeviceID) -> Bool

    /// Check if device supports specified channel count
    func supportsChannelCount(_ deviceID: AudioDeviceID, count: UInt32) -> Bool

    // MARK: - Configuration

    /// Configure device for 5.1 surround output
    func configure51Surround(_ deviceID: AudioDeviceID) -> Bool

    /// Get buffer configuration for latency calculation
    func getBufferConfiguration(_ deviceID: AudioDeviceID) -> BufferConfiguration?
}
