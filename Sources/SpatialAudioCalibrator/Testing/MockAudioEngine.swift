import CoreAudio
import Foundation
#if DEBUG
    import XCTest
#endif

/// Mock implementation of AudioEngineProtocol for testing.
///
/// This mock simulates audio engine behavior without requiring actual hardware.
/// It can be configured to:
/// - Simulate various recording responses
/// - Track all method calls for verification
/// - Inject errors for error handling tests
///
/// ## Usage
///
/// ```swift
/// let mockEngine = MockAudioEngine()
/// mockEngine.recordingResult = [Float](repeating: 0.5, count: 48000)
///
/// try mockEngine.start()
/// mockEngine.startRecording()
/// mockEngine.startSweep()
///
/// let recording = mockEngine.stopRecording()
/// XCTAssertEqual(recording.count, 48000)
/// XCTAssertTrue(mockEngine.startRecordingCalled)
/// ```
public final class MockAudioEngine: AudioEngineProtocol, @unchecked Sendable {
    // MARK: Lifecycle

    public init(outputDeviceID: AudioDeviceID? = nil) {
        self.outputDeviceID = outputDeviceID
    }

    // MARK: Public

    // MARK: - Configuration

    /// The device ID passed to init
    public var outputDeviceID: AudioDeviceID?

    /// Simulated recording to return when stopRecording() is called
    public var recordingResult: [Float] = []

    /// Simulated latency info
    public var simulatedLatencyInfo: BufferConfiguration?

    /// Error to throw on next operation (resets after throwing)
    public var errorToThrow: Error?

    // MARK: - State

    public var isRunning: Bool = false
    public var isSweepPlaying: Bool = false
    public var isCurrentlyRecording: Bool = false

    // MARK: - Call Tracking

    public private(set) var startCallCount = 0
    public private(set) var stopCallCount = 0
    public private(set) var startRecordingCalled = false
    public private(set) var stopRecordingCalled = false
    public private(set) var startSweepCalled = false
    public private(set) var stopSweepCalled = false
    public private(set) var configureSweepCalled = false
    public private(set) var setChannelMapCalled = false
    public private(set) var muteAllCalled = false

    /// Last channel map target set
    public private(set) var lastChannelMapTarget: SpeakerChannel?

    /// Last sweep configuration
    public private(set) var lastSweepConfig: (
        startFrequency: Double,
        endFrequency: Double,
        duration: Double,
        sampleRate: Double,
        amplitude: Float
    )?

    /// All channel map targets in order
    public private(set) var channelMapHistory: [SpeakerChannel] = []

    public var latencyInfo: BufferConfiguration? {
        simulatedLatencyInfo
    }

    // MARK: - Engine Control

    public func start() throws {
        if let error = errorToThrow {
            errorToThrow = nil
            throw error
        }
        startCallCount += 1
        isRunning = true
    }

    public func stop() {
        stopCallCount += 1
        isRunning = false
        isSweepPlaying = false
    }

    // MARK: - Channel Mapping

    public func setChannelMap(target: SpeakerChannel) throws {
        if let error = errorToThrow {
            errorToThrow = nil
            throw error
        }
        setChannelMapCalled = true
        lastChannelMapTarget = target
        channelMapHistory.append(target)
    }

    public func muteAll() throws {
        muteAllCalled = true
    }

    // MARK: - Sweep Control

    public func configureSweep(
        startFrequency: Double,
        endFrequency: Double,
        duration: Double,
        sampleRate: Double,
        amplitude: Float
    ) {
        configureSweepCalled = true
        lastSweepConfig = (
            startFrequency: startFrequency,
            endFrequency: endFrequency,
            duration: duration,
            sampleRate: sampleRate,
            amplitude: amplitude
        )
    }

    public func startSweep() {
        startSweepCalled = true
        isSweepPlaying = true
    }

    public func stopSweep() {
        stopSweepCalled = true
        isSweepPlaying = false
    }

    // MARK: - Recording

    public func startRecording() {
        startRecordingCalled = true
        isCurrentlyRecording = true
    }

    public func stopRecording() -> [Float] {
        stopRecordingCalled = true
        isCurrentlyRecording = false
        return recordingResult
    }

    // MARK: - Latency Compensation

    public func compensateLatency(_ recording: [Float]) -> [Float] {
        guard let latency = simulatedLatencyInfo else { return recording }
        let latencySamples = Int(latency.totalLatency)
        guard latencySamples < recording.count else { return [] }
        return Array(recording.dropFirst(latencySamples))
    }

    // MARK: - Test Helpers

    /// Reset all tracking state
    public func reset() {
        startCallCount = 0
        stopCallCount = 0
        startRecordingCalled = false
        stopRecordingCalled = false
        startSweepCalled = false
        stopSweepCalled = false
        configureSweepCalled = false
        setChannelMapCalled = false
        muteAllCalled = false
        lastChannelMapTarget = nil
        lastSweepConfig = nil
        channelMapHistory.removeAll()
        errorToThrow = nil
        isRunning = false
        isSweepPlaying = false
        isCurrentlyRecording = false
    }

    /// Configure for a successful measurement simulation
    public func configureForSuccessfulMeasurement(
        sampleRate: Double = 48000,
        sweepDuration: Double = 5.0
    ) {
        // Simulate latency
        simulatedLatencyInfo = BufferConfiguration(
            bufferSize: 512,
            safetyOffsetOutput: 24,
            safetyOffsetInput: 24,
            streamLatencyOutput: 128,
            streamLatencyInput: 128
        )

        // Generate simulated recording (impulse + noise)
        let sampleCount = Int(sweepDuration * sampleRate)
        var recording = [Float](repeating: 0, count: sampleCount)

        // Add a simulated impulse at the start
        let impulsePosition = 100 // After latency compensation
        for i in 0 ..< 1000 {
            let pos = impulsePosition + i
            if pos < recording.count {
                recording[pos] = Float(exp(-Double(i) / 100.0)) * 0.8
            }
        }

        // Add low-level noise
        for i in 0 ..< recording.count {
            recording[i] += Float.random(in: -0.01 ... 0.01)
        }

        recordingResult = recording
    }
}
