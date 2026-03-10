import CoreAudio
import Foundation
@testable import SpatialAudioCalibrator
import Testing

/// Integration tests using mock implementations
@Suite("Integration Tests")
struct IntegrationTests {
    // MARK: - AudioCalibrator with Mocks

    @Test("AudioCalibrator initializes with mock device manager")
    @MainActor
    func audioCalibratorInitializesWithMocks() {
        let mockDeviceManager = MockAudioDeviceManager()
        mockDeviceManager.configureFor51HDMI()

        let mockEngineFactory: (AudioDeviceID?) throws -> AudioEngineProtocol = { _ in
            let mockEngine = MockAudioEngine()
            mockEngine.configureForSuccessfulMeasurement()
            return mockEngine
        }

        let calibrator = AudioCalibrator(
            config: .default,
            deviceManager: mockDeviceManager,
            engineFactory: mockEngineFactory
        )

        #expect(calibrator.state == .idle)
    }

    @Test("AudioCalibrator uses mock device manager for HDMI detection")
    @MainActor
    func audioCalibratorUsesMockForHDMIDetection() throws {
        let mockDeviceManager = MockAudioDeviceManager()
        mockDeviceManager.configureFor51HDMI()

        let mockEngineFactory: (AudioDeviceID?) throws -> AudioEngineProtocol = { _ in
            MockAudioEngine()
        }

        let calibrator = AudioCalibrator(
            config: .default,
            deviceManager: mockDeviceManager,
            engineFactory: mockEngineFactory
        )

        // verifySystemConfiguration should use the mock device manager
        let status = try calibrator.verifySystemConfiguration()

        // Verify mock was called
        #expect(mockDeviceManager.findHDMIDeviceCallCount >= 1)

        // Verify HDMI device was found
        #expect(status.hasHDMI == true)
    }

    @Test("AudioCalibrator handles no HDMI scenario")
    @MainActor
    func audioCalibratorNoHDMIScenario() throws {
        let mockDeviceManager = MockAudioDeviceManager()
        mockDeviceManager.configureForNoHDMI()

        let mockEngineFactory: (AudioDeviceID?) throws -> AudioEngineProtocol = { _ in
            MockAudioEngine()
        }

        let calibrator = AudioCalibrator(
            config: .default,
            deviceManager: mockDeviceManager,
            engineFactory: mockEngineFactory
        )

        let status = try calibrator.verifySystemConfiguration()

        #expect(status.hasHDMI == false)
        #expect(mockDeviceManager.findHDMIDeviceCallCount >= 1)
    }

    @Test("MockAudioEngine tracks sweep configuration")
    func mockEngineSweepTracking() {
        let mockEngine = MockAudioEngine()

        mockEngine.configureSweep(
            startFrequency: 100,
            endFrequency: 10000,
            duration: 3.0,
            sampleRate: 48000,
            amplitude: 0.5
        )

        #expect(mockEngine.lastSweepConfig?.startFrequency == 100)
        #expect(mockEngine.lastSweepConfig?.endFrequency == 10000)
        #expect(mockEngine.lastSweepConfig?.duration == 3.0)
        #expect(mockEngine.lastSweepConfig?.sampleRate == 48000)
        #expect(mockEngine.lastSweepConfig?.amplitude == 0.5)
    }

    @Test("MockAudioEngine tracks channel map changes")
    func mockEngineChannelMapTracking() throws {
        let mockEngine = MockAudioEngine()

        try mockEngine.setChannelMap(target: .frontLeft)
        try mockEngine.setChannelMap(target: .center)
        try mockEngine.setChannelMap(target: .rearRight)

        #expect(mockEngine.channelMapHistory.count == 3)
        #expect(mockEngine.channelMapHistory[0] == .frontLeft)
        #expect(mockEngine.channelMapHistory[1] == .center)
        #expect(mockEngine.channelMapHistory[2] == .rearRight)
    }

    @Test("MockAudioEngine simulates recording")
    func mockEngineRecording() {
        let mockEngine = MockAudioEngine()
        mockEngine.recordingResult = [0.1, 0.2, 0.3, 0.4, 0.5]

        mockEngine.startRecording()
        #expect(mockEngine.startRecordingCalled)

        let result = mockEngine.stopRecording()
        #expect(mockEngine.stopRecordingCalled)
        #expect(result == [0.1, 0.2, 0.3, 0.4, 0.5])
    }

    @Test("MockAudioEngine can simulate errors")
    func mockEngineErrorSimulation() {
        let mockEngine = MockAudioEngine()
        mockEngine.errorToThrow = CalibrationError.noHDMIDevice

        #expect(throws: CalibrationError.noHDMIDevice) {
            try mockEngine.start()
        }
    }

    @Test("MockAudioDeviceManager tracks configure51Surround calls")
    func mockDeviceManagerConfigureTracking() {
        let mockManager = MockAudioDeviceManager()
        mockManager.configureFor51HDMI()
        mockManager.configure51Succeeds = true

        let result = mockManager.configure51Surround(100)

        #expect(result == true)
        #expect(mockManager.configure51SurroundCallCount == 1)
        #expect(mockManager.configure51SurroundArguments == [100])
    }

    @Test("MockAudioDeviceManager returns configured sample rates")
    func mockDeviceManagerSampleRates() throws {
        let mockManager = MockAudioDeviceManager()
        mockManager.configureFor51HDMI()

        let hdmiDevice = mockManager.findHDMIDevice()
        #expect(hdmiDevice != nil)

        let sampleRate = try mockManager.getSampleRate(#require(hdmiDevice))
        #expect(sampleRate == 48000)
    }

    // MARK: - Full Calibration Flow Simulation

    @Test("Simulated calibration flow with all mocks")
    @MainActor
    func simulatedCalibrationFlow() throws {
        let mockDeviceManager = MockAudioDeviceManager()
        mockDeviceManager.configureFor51HDMI()

        let mockEngine = MockAudioEngine()
        mockEngine.configureForSuccessfulMeasurement(
            sampleRate: 48000,
            sweepDuration: 5.0
        )

        let mockEngineFactory: (AudioDeviceID?) throws -> AudioEngineProtocol = { _ in
            mockEngine
        }

        let config = CalibrationConfig(
            startFrequency: 20,
            endFrequency: 20000,
            sweepDuration: 5.0,
            sampleRate: 48000,
            fftSize: 8192
        )

        let calibrator = AudioCalibrator(
            config: config,
            deviceManager: mockDeviceManager,
            engineFactory: mockEngineFactory
        )

        // Verify initial state
        #expect(calibrator.state == .idle)

        // Get system status (should use mocks)
        let status = try calibrator.verifySystemConfiguration()
        #expect(status.hasHDMI == true)
        #expect(mockDeviceManager.findHDMIDeviceCallCount >= 1)

        // Verify mock engine is available for use
        #expect(mockEngine.isRunning == false) // Not started yet

        // Simulate what happens when calibration starts
        try mockEngine.start()
        #expect(mockEngine.isRunning == true)
        #expect(mockEngine.startCallCount == 1)
    }

    // MARK: - Edge Cases

    @Test("MockAudioDeviceManager can simulate device failure")
    func mockDeviceFailure() {
        let mockManager = MockAudioDeviceManager()
        mockManager.configureForNoHDMI()

        let hdmiDevice = mockManager.findHDMIDevice()
        #expect(hdmiDevice == nil)

        // Configure51 should still return false for non-existent device
        mockManager.configure51Succeeds = false
        let result = mockManager.configure51Surround(999)
        #expect(result == false)
    }

    @Test("MockAudioEngine latency compensation")
    func mockEngineLatencyCompensation() throws {
        let mockEngine = MockAudioEngine()
        mockEngine.simulatedLatencyInfo = BufferConfiguration(
            bufferSize: 512,
            safetyOffsetOutput: 24,
            safetyOffsetInput: 24,
            streamLatencyOutput: 128,
            streamLatencyInput: 128
        )

        // Create a recording with some samples
        var recording = [Float](repeating: 0.5, count: 1000)

        // Add some leading zeros that should be removed by latency compensation
        let leadingSamples = try Int(#require(mockEngine.simulatedLatencyInfo?.totalLatency))
        recording.insert(contentsOf: [Float](repeating: 0.0, count: leadingSamples), at: 0)

        let compensated = mockEngine.compensateLatency(recording)

        // Compensated recording should be shorter by latency samples
        #expect(compensated.count == 1000)
    }
}
