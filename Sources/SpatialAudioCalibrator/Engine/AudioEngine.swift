import AVFAudio
import CoreAudio
import Foundation

/// Manages the AVAudioEngine graph for multichannel audio playback and recording.
///
/// This class handles:
/// - 5.1 surround output configuration
/// - Channel mapping for speaker isolation
/// - Sweep signal playback
/// - Microphone input recording
public final class AudioEngine {
    // MARK: Lifecycle

    // MARK: - Initialization

    /// Create engine with specified output device
    /// - Parameter outputDeviceID: Optional specific output device to use
    public init(outputDeviceID: AudioDeviceID? = nil) throws {
        self.outputDeviceID = outputDeviceID

        try configureEngine()
        try measureLatency()
    }

    deinit {
        stop()
        removeInputTap()
    }

    // MARK: Public

    /// The underlying AVAudioEngine instance
    public let engine = AVAudioEngine()

    /// Whether the engine is currently running
    public private(set) var isRunning = false

    /// Output audio format (5.1 surround at 48kHz)
    public private(set) var outputFormat: AVAudioFormat?

    /// Current latency information
    public private(set) var latencyInfo: BufferConfiguration?

    /// Input audio format from microphone
    public var inputFormat: AVAudioFormat? {
        engine.inputNode.outputFormat(forBus: 0)
    }

    /// Check if sweep is currently playing
    public var isSweepPlaying: Bool {
        sweepGenerator?.running ?? false
    }

    /// Check if currently recording
    public var isCurrentlyRecording: Bool {
        recordingLock.lock()
        defer { recordingLock.unlock() }
        return isRecording
    }

    /// Set the output audio device
    public func setOutputDevice(_ deviceID: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var id = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &id
        )

        if status != noErr {
            throw CalibrationError.configurationFailed(
                "Failed to set output device: \(AudioDeviceManager.errorMessage(status))"
            )
        }

        outputDeviceID = deviceID

        // Configure device for 5.1 output
        if !AudioDeviceManager.configure51Surround(deviceID) {
            // Not critical - some devices don't support this
            // swiftlint:disable:next no_print_statements
            print("Warning: Could not set 5.1 channel layout on device")
        }
    }

    // MARK: - Engine Control

    /// Start the audio engine
    public func start() throws {
        guard !isRunning else { return }

        try engine.start()
        isRunning = true
    }

    /// Stop the audio engine
    public func stop() {
        sweepGenerator?.stop()
        engine.stop()
        isRunning = false
    }

    // MARK: - Channel Mapping

    /// Set channel map to route signal to a specific speaker
    public func setChannelMap(target: SpeakerChannel) throws {
        guard let audioUnit = engine.outputNode.audioUnit else {
            throw CalibrationError.configurationFailed("Could not get output AudioUnit")
        }

        // Build channel map array
        // Index = destination channel, Value = source channel (-1 = mute)
        var channelMap: [Int32] = [-1, -1, -1, -1, -1, -1]
        channelMap[target.rawValue] = 0 // Route mono source (channel 0) to target

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Output,
            0,
            &channelMap,
            UInt32(MemoryLayout<Int32>.size * channelMap.count)
        )

        if status != noErr {
            throw CalibrationError.configurationFailed(
                "Failed to set channel map: \(AudioDeviceManager.errorMessage(status))"
            )
        }
    }

    /// Mute all output channels
    public func muteAll() throws {
        guard let audioUnit = engine.outputNode.audioUnit else {
            throw CalibrationError.configurationFailed("Could not get output AudioUnit")
        }

        var channelMap: [Int32] = [-1, -1, -1, -1, -1, -1]

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Output,
            0,
            &channelMap,
            UInt32(MemoryLayout<Int32>.size * channelMap.count)
        )

        if status != noErr {
            throw CalibrationError.configurationFailed(
                "Failed to mute channels: \(AudioDeviceManager.errorMessage(status))"
            )
        }
    }

    // MARK: - Sweep Playback

    /// Configure sweep parameters
    public func configureSweep(
        startFrequency: Double,
        endFrequency: Double,
        duration: Double,
        amplitude: Float
    ) {
        sweepGenerator = SweepGenerator(
            startFrequency: startFrequency,
            endFrequency: endFrequency,
            duration: duration,
            sampleRate: 48000,
            amplitude: amplitude
        )
    }

    /// Start sweep playback
    public func startSweep() {
        sweepGenerator?.reset()
        sweepGenerator?.start()
    }

    /// Stop sweep playback
    public func stopSweep() {
        sweepGenerator?.stop()
    }

    // MARK: - Input Recording

    /// Install tap on input node for recording
    public func installInputTap(bufferSize: AVAudioFrameCount = 4096) throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Validate input format
        guard inputFormat.sampleRate > 0 else {
            throw CalibrationError.noMicrophoneAccess
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer)
        }
    }

    /// Remove input tap
    public func removeInputTap() {
        engine.inputNode.removeTap(onBus: 0)
    }

    /// Start recording
    public func startRecording() {
        recordingLock.lock()
        defer { recordingLock.unlock() }

        recordingBuffer.removeAll(keepingCapacity: true)
        recordingStartTime = AVAudioTime(hostTime: mach_absolute_time())
        isRecording = true
    }

    /// Stop recording and return captured samples
    public func stopRecording() -> [Float] {
        recordingLock.lock()
        defer { recordingLock.unlock() }

        isRecording = false
        return recordingBuffer
    }

    /// Get current recording buffer without stopping
    public func getRecordedBuffer() -> [Float] {
        recordingLock.lock()
        defer { recordingLock.unlock() }

        return recordingBuffer
    }

    // MARK: - Latency Compensation

    /// Compensate recording for measured latency
    public func compensateLatency(_ recording: [Float]) -> [Float] {
        guard let latency = latencyInfo else { return recording }

        let latencySamples = Int(latency.totalLatency)

        // Remove latency samples from beginning of recording
        guard latencySamples < recording.count else { return [] }

        return Array(recording.dropFirst(latencySamples))
    }

    // MARK: Private

    /// Sweep generator instance
    private var sweepGenerator: SweepGenerator?

    /// Source node for sweep playback
    private var sourceNode: AVAudioSourceNode?

    /// Configured output device ID
    private var outputDeviceID: AudioDeviceID?

    // MARK: - Recording State

    private var recordingBuffer: [Float] = []
    private var isRecording = false
    private var recordingStartTime: AVAudioTime?
    private let recordingLock = NSLock()

    // MARK: - Configuration

    private func configureEngine() throws {
        // Define 5.1 surround format
        guard
            let channelLayout = AVAudioChannelLayout(
                layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A
            )
        else {
            throw CalibrationError.configurationFailed("Failed to create 5.1 channel layout")
        }

        let format = AVAudioFormat(
            standardFormatWithSampleRate: 48000,
            channelLayout: channelLayout
        )

        outputFormat = format

        // Set output device if specified
        if let deviceID = outputDeviceID {
            try setOutputDevice(deviceID)
        }

        // Create sweep generator
        sweepGenerator = SweepGenerator(
            startFrequency: 20,
            endFrequency: 20000,
            duration: 5.0,
            sampleRate: 48000,
            amplitude: 0.8
        )

        // Create source node with 5.1 format
        guard sweepGenerator != nil else {
            throw CalibrationError.configurationFailed("Failed to create sweep generator")
        }

        sourceNode = AVAudioSourceNode(
            format: format
        ) { [weak self] _, _, frameCount, outputBufferList in
            guard let self, let generator = sweepGenerator else {
                return noErr
            }
            return generator.render(frameCount: frameCount, outputBufferList: outputBufferList)
        }

        guard let sourceNode else {
            throw CalibrationError.configurationFailed("Failed to create source node")
        }

        // Attach and connect nodes
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)

        // Prepare engine
        engine.prepare()
    }

    private func measureLatency() throws {
        guard let deviceID = outputDeviceID ?? AudioDeviceManager.getDefaultOutputDevice() else {
            throw CalibrationError.noHDMIDevice
        }

        guard let config = AudioDeviceManager.getBufferConfiguration(deviceID) else {
            throw CalibrationError.configurationFailed("Failed to get buffer configuration")
        }

        latencyInfo = config
    }

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        recordingLock.lock()
        defer { recordingLock.unlock() }

        guard isRecording else { return }

        // Get first channel data
        guard let channelData = buffer.floatChannelData?[0] else { return }

        // Copy samples to recording buffer
        let frameCount = Int(buffer.frameLength)
        recordingBuffer.append(
            contentsOf: UnsafeBufferPointer(start: channelData, count: frameCount)
        )
    }
}

// MARK: - System Status

/// System status information for calibration
public struct SystemStatus {
    public let outputDevice: AudioDeviceInfo?
    public let inputDevice: AudioDeviceInfo?
    public let hasHDMI: Bool
    public let supports51: Bool
    public let latencySamples: UInt32
    public let latencyMs: Double
    public let microphoneAccess: Bool

    public var isReady: Bool {
        outputDevice != nil && microphoneAccess
    }

    public var issues: [String] {
        var problems: [String] = []

        if outputDevice == nil {
            problems.append("No output device found")
        }

        if !hasHDMI {
            problems.append("No HDMI device detected - using default output")
        }

        if !supports51 {
            problems.append("Output device may not support 5.1 surround")
        }

        if !microphoneAccess {
            problems.append("Microphone access required for recording")
        }

        return problems
    }
}
