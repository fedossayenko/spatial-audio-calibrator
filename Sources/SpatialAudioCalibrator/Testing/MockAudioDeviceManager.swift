import CoreAudio
import Foundation

/// Mock implementation of AudioDeviceManaging for testing.
///
/// This mock simulates device management without requiring actual hardware.
///
/// ## Usage
///
/// ```swift
/// let mockManager = MockAudioDeviceManager()
/// mockManager.simulatedOutputDevices = [1, 2, 3]
/// mockManager.simulatedHDMIDevice = 2
///
/// let hdmi = mockManager.findHDMIDevice()
/// XCTAssertEqual(hdmi, 2)
/// ```
public final class MockAudioDeviceManager: AudioDeviceManaging, @unchecked Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    // MARK: - Simulated Devices

    /// Simulated list of all devices
    public var simulatedDevices: [AudioDeviceID] = []

    /// Simulated list of output devices
    public var simulatedOutputDevices: [AudioDeviceID] = []

    /// Simulated list of input devices
    public var simulatedInputDevices: [AudioDeviceID] = []

    /// Simulated HDMI device (if any)
    public var simulatedHDMIDevice: AudioDeviceID?

    /// Simulated default output device
    public var simulatedDefaultOutputDevice: AudioDeviceID?

    /// Simulated device names by ID
    public var deviceNames: [AudioDeviceID: String] = [:]

    /// Simulated device UIDs by ID
    public var deviceUIDs: [AudioDeviceID: String] = [:]

    /// Simulated transport types by ID
    public var deviceTransportTypes: [AudioDeviceID: UInt32] = [:]

    /// Simulated sample rates by ID
    public var deviceSampleRates: [AudioDeviceID: Double] = [:]

    /// Simulated channel support by ID
    public var deviceChannelSupport: [AudioDeviceID: Set<UInt32>] = [:]

    /// Simulated buffer configurations by ID
    public var deviceBufferConfigs: [AudioDeviceID: BufferConfiguration] = [:]

    /// Whether configure51Surround succeeds
    public var configure51Succeeds: Bool = true

    // MARK: - Call Tracking

    public private(set) var findHDMIDeviceCallCount = 0
    public private(set) var configure51SurroundCallCount = 0
    public private(set) var configure51SurroundArguments: [AudioDeviceID] = []

    // MARK: - Device Enumeration

    public func getAllDevices() -> [AudioDeviceID] {
        simulatedDevices
    }

    public func getOutputDevices() -> [AudioDeviceID] {
        simulatedOutputDevices
    }

    public func getInputDevices() -> [AudioDeviceID] {
        simulatedInputDevices
    }

    public func findHDMIDevice() -> AudioDeviceID? {
        findHDMIDeviceCallCount += 1
        return simulatedHDMIDevice
    }

    public func getDefaultOutputDevice() -> AudioDeviceID? {
        simulatedDefaultOutputDevice
    }

    // MARK: - Device Properties

    public func getName(_ deviceID: AudioDeviceID) -> String? {
        deviceNames[deviceID]
    }

    public func getUID(_ deviceID: AudioDeviceID) -> String? {
        deviceUIDs[deviceID]
    }

    public func getTransportType(_ deviceID: AudioDeviceID) -> UInt32? {
        deviceTransportTypes[deviceID]
    }

    public func getSampleRate(_ deviceID: AudioDeviceID) -> Double? {
        deviceSampleRates[deviceID]
    }

    public func isHDMI(_ deviceID: AudioDeviceID) -> Bool {
        deviceID == simulatedHDMIDevice
    }

    public func supportsChannelCount(_ deviceID: AudioDeviceID, count: UInt32) -> Bool {
        deviceChannelSupport[deviceID]?.contains(count) ?? false
    }

    // MARK: - Configuration

    public func configure51Surround(_ deviceID: AudioDeviceID) -> Bool {
        configure51SurroundCallCount += 1
        configure51SurroundArguments.append(deviceID)
        return configure51Succeeds
    }

    public func getBufferConfiguration(_ deviceID: AudioDeviceID) -> BufferConfiguration? {
        deviceBufferConfigs[deviceID]
    }

    // MARK: - Test Helpers

    /// Configure mock for a typical 5.1 HDMI setup
    public func configureFor51HDMI() {
        let hdmiDeviceID: AudioDeviceID = 100
        let builtinDeviceID: AudioDeviceID = 50
        let micDeviceID: AudioDeviceID = 200

        simulatedDevices = [builtinDeviceID, hdmiDeviceID, micDeviceID]
        simulatedOutputDevices = [builtinDeviceID, hdmiDeviceID]
        simulatedInputDevices = [builtinDeviceID, micDeviceID]
        simulatedHDMIDevice = hdmiDeviceID
        simulatedDefaultOutputDevice = builtinDeviceID

        deviceNames = [
            builtinDeviceID: "MacBook Pro Speakers",
            hdmiDeviceID: "HDMI Audio Output",
            micDeviceID: "MacBook Pro Microphone",
        ]

        deviceUIDs = [
            builtinDeviceID: "BUILTIN-OUTPUT",
            hdmiDeviceID: "HDMI-OUTPUT",
            micDeviceID: "BUILTIN-INPUT",
        ]

        deviceTransportTypes = [
            builtinDeviceID: kAudioDeviceTransportTypeBuiltIn,
            hdmiDeviceID: kAudioDeviceTransportTypeHDMI,
            micDeviceID: kAudioDeviceTransportTypeBuiltIn,
        ]

        deviceSampleRates = [
            builtinDeviceID: 48000,
            hdmiDeviceID: 48000,
            micDeviceID: 48000,
        ]

        deviceChannelSupport = [
            builtinDeviceID: [2],
            hdmiDeviceID: [2, 6, 8],
        ]

        deviceBufferConfigs = [
            hdmiDeviceID: BufferConfiguration(
                bufferSize: 512,
                safetyOffsetOutput: 24,
                safetyOffsetInput: 24,
                streamLatencyOutput: 128,
                streamLatencyInput: 128
            ),
        ]
    }

    /// Configure mock for a system without HDMI
    public func configureForNoHDMI() {
        let builtinDeviceID: AudioDeviceID = 50

        simulatedDevices = [builtinDeviceID]
        simulatedOutputDevices = [builtinDeviceID]
        simulatedInputDevices = [builtinDeviceID]
        simulatedHDMIDevice = nil
        simulatedDefaultOutputDevice = builtinDeviceID

        deviceNames = [builtinDeviceID: "Built-in Output"]
        deviceUIDs = [builtinDeviceID: "BUILTIN"]
        deviceTransportTypes = [builtinDeviceID: kAudioDeviceTransportTypeBuiltIn]
        deviceSampleRates = [builtinDeviceID: 44100]
        deviceChannelSupport = [builtinDeviceID: [2]]
    }

    /// Reset all simulated state
    public func reset() {
        simulatedDevices.removeAll()
        simulatedOutputDevices.removeAll()
        simulatedInputDevices.removeAll()
        simulatedHDMIDevice = nil
        simulatedDefaultOutputDevice = nil
        deviceNames.removeAll()
        deviceUIDs.removeAll()
        deviceTransportTypes.removeAll()
        deviceSampleRates.removeAll()
        deviceChannelSupport.removeAll()
        deviceBufferConfigs.removeAll()
        configure51Succeeds = true
        findHDMIDeviceCallCount = 0
        configure51SurroundCallCount = 0
        configure51SurroundArguments.removeAll()
    }
}

/// Extension to make BufferConfiguration more testable
public extension BufferConfiguration {
    /// Create a buffer configuration for testing
    init(
        bufferSize: UInt32,
        safetyOffsetOutput: UInt32,
        safetyOffsetInput: UInt32,
        streamLatencyOutput: UInt32,
        streamLatencyInput: UInt32
    ) {
        self.bufferSize = bufferSize
        self.safetyOffsetOutput = safetyOffsetOutput
        self.safetyOffsetInput = safetyOffsetInput
        self.streamLatencyOutput = streamLatencyOutput
        self.streamLatencyInput = streamLatencyInput
    }
}
