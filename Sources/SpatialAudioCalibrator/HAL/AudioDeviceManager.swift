import CoreAudio
import Foundation

/// Low-level Core Audio HAL device management.
///
/// Provides static methods for enumerating, querying, and configuring
/// audio devices using the Core Audio Hardware Abstraction Layer.
public enum AudioDeviceManager {

    // MARK: - Device Enumeration

    /// Get all audio devices in the system
    public static func getAllDevices() -> [AudioDeviceID] {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Get size first
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )

        guard status == noErr else {
            logError("Failed to get device list size: \(status)")
            return []
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        guard status == noErr else {
            logError("Failed to get device list: \(status)")
            return []
        }

        return deviceIDs
    }

    /// Get only output devices
    public static func getOutputDevices() -> [AudioDeviceID] {
        getAllDevices().filter { deviceID in
            getStreamCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput) > 0
        }
    }

    /// Get only input devices
    public static func getInputDevices() -> [AudioDeviceID] {
        getAllDevices().filter { deviceID in
            getStreamCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput) > 0
        }
    }

    /// Find HDMI audio device
    public static func findHDMIDevice() -> AudioDeviceID? {
        getOutputDevices().first { deviceID in
            isHDMI(deviceID)
        }
    }

    /// Get default output device
    public static func getDefaultOutputDevice() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &size,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    // MARK: - Device Properties

    /// Get device name
    public static func getName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var nameCFString: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &size,
            &nameCFString
        )

        return status == noErr ? (nameCFString as String) : nil
    }

    /// Get device unique identifier
    public static func getUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uidCFString: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &size,
            &uidCFString
        )

        return status == noErr ? (uidCFString as String) : nil
    }

    /// Get transport type (HDMI, USB, Built-in, etc.)
    public static func getTransportType(_ deviceID: AudioDeviceID) -> UInt32? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &size,
            &transportType
        )

        return status == noErr ? transportType : nil
    }

    /// Get current sample rate
    public static func getSampleRate(_ deviceID: AudioDeviceID) -> Float64? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &size,
            &sampleRate
        )

        return status == noErr ? sampleRate : nil
    }

    /// Set sample rate
    @discardableResult
    public static func setSampleRate(_ deviceID: AudioDeviceID, rate: Float64) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate = rate
        let size = UInt32(MemoryLayout<Float64>.size)

        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            size,
            &sampleRate
        )

        if status != noErr {
            logError("Failed to set sample rate: \(errorMessage(status))")
        }

        return status == noErr
    }

    /// Get output channel count
    public static func getChannelCount(_ deviceID: AudioDeviceID) -> UInt32? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var channels: [UInt32] = [0, 0]
        var size = UInt32(MemoryLayout<UInt32>.size * 2)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &size,
            &channels
        )

        guard status == noErr else { return nil }

        // Try to get actual channel count from stream
        return getStreamCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
    }

    /// Check if device is HDMI
    public static func isHDMI(_ deviceID: AudioDeviceID) -> Bool {
        guard let transportType = getTransportType(deviceID) else { return false }
        return transportType == kAudioDeviceTransportTypeHDMI
    }

    /// Check if device supports specified channel count
    public static func supportsChannelCount(_ deviceID: AudioDeviceID, count: UInt32) -> Bool {
        guard let layout = getChannelLayout(deviceID) else { return false }

        if layout.mChannelLayoutTag == kAudioChannelLayoutTag_UseChannelDescriptions {
            return layout.mNumberChannelDescriptions >= count
        }

        let channelsInTag = AudioChannelLayoutTag_GetNumberOfChannels(layout.mChannelLayoutTag)
        return channelsInTag >= count
    }

    // MARK: - Channel Layout

    /// Get current channel layout
    public static func getChannelLayout(_ deviceID: AudioDeviceID) -> AudioChannelLayout? {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelLayout,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize
        )

        guard status == noErr else { return nil }

        var layout = AudioChannelLayout()
        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &layout
        )

        return status == noErr ? layout : nil
    }

    /// Configure device for 5.1 surround output
    @discardableResult
    public static func configure51Surround(_ deviceID: AudioDeviceID) -> Bool {
        var channelLayout = AudioChannelLayout()
        channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_5_1_A

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelLayout,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let size = UInt32(MemoryLayout<AudioChannelLayout>.size)
        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            size,
            &channelLayout
        )

        if status != noErr {
            logError("Failed to set 5.1 channel layout: \(errorMessage(status))")
        }

        return status == noErr
    }

    // MARK: - Buffer Configuration

    /// Get buffer configuration for latency calculation
    public static func getBufferConfiguration(_ deviceID: AudioDeviceID) -> BufferConfiguration? {
        var config = BufferConfiguration(
            bufferSize: 0,
            safetyOffsetOutput: 0,
            safetyOffsetInput: 0,
            streamLatencyOutput: 0,
            streamLatencyInput: 0
        )

        var size = UInt32(MemoryLayout<UInt32>.size)

        // Buffer size
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &config.bufferSize)

        // Output safety offset
        propertyAddress.mSelector = kAudioDevicePropertySafetyOffset
        propertyAddress.mScope = kAudioDevicePropertyScopeOutput
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &config.safetyOffsetOutput)

        // Input safety offset
        propertyAddress.mScope = kAudioDevicePropertyScopeInput
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &config.safetyOffsetInput)

        // Output stream latency
        propertyAddress.mSelector = kAudioStreamPropertyLatency
        propertyAddress.mScope = kAudioDevicePropertyScopeOutput
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &config.streamLatencyOutput)

        // Input stream latency
        propertyAddress.mScope = kAudioDevicePropertyScopeInput
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &config.streamLatencyInput)

        return config
    }

    // MARK: - Stream Helpers

    /// Get stream count for a device
    public static func getStreamCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)

        return propertySize / UInt32(MemoryLayout<AudioStreamID>.size)
    }

    // MARK: - Error Handling

    /// Convert OSStatus to human-readable error message
    public static func errorMessage(_ status: OSStatus) -> String {
        switch status {
        case kAudioHardwareNoError:
            return "No error"
        case kAudioHardwareNotRunningError:
            return "Hardware not running"
        case kAudioHardwareUnspecifiedError:
            return "Unspecified error"
        case kAudioHardwareUnknownPropertyError:
            return "Unknown property"
        case kAudioHardwareBadPropertySizeError:
            return "Bad property size"
        case kAudioHardwareIllegalOperationError:
            return "Illegal operation"
        case kAudioHardwareBadDeviceError:
            return "Bad device"
        case kAudioHardwareBadStreamError:
            return "Bad stream"
        case kAudioHardwareUnsupportedOperationError:
            return "Unsupported operation"
        case kAudioDeviceUnsupportedFormatError:
            return "Unsupported format"
        case kAudioDevicePermissionsError:
            return "Permission denied"
        default:
            return "Unknown error: \(status)"
        }
    }

    private static func logError(_ message: String) {
        #if DEBUG
        // swiftlint:disable:next no_print_statements
        print("[AudioDeviceManager] \(message)")
        #endif
    }
}

// MARK: - Buffer Configuration

/// Audio buffer and latency information
public struct BufferConfiguration: Codable {
    public var bufferSize: UInt32
    public var safetyOffsetOutput: UInt32
    public var safetyOffsetInput: UInt32
    public var streamLatencyOutput: UInt32
    public var streamLatencyInput: UInt32

    /// Total round-trip latency in samples
    public var totalLatency: UInt32 {
        bufferSize + safetyOffsetOutput + streamLatencyOutput + safetyOffsetInput + streamLatencyInput
    }

    /// Latency in milliseconds at 48kHz
    public var latencyMs: Double {
        Double(totalLatency) / 48000.0 * 1000.0
    }

    /// Latency in milliseconds at specified sample rate
    public func latencyMs(at sampleRate: Double) -> Double {
        Double(totalLatency) / sampleRate * 1000.0
    }
}

// MARK: - Device Info

/// Convenient device information struct
public struct AudioDeviceInfo: Codable, Identifiable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    public let transportType: UInt32
    public let sampleRate: Double?
    public let channelCount: UInt32?
    public let isHDMI: Bool
    public let isInput: Bool
    public let isOutput: Bool

    public init?(deviceID: AudioDeviceID) {
        self.id = deviceID

        guard let name = AudioDeviceManager.getName(deviceID),
              let uid = AudioDeviceManager.getUID(deviceID) else {
            return nil
        }

        self.name = name
        self.uid = uid
        self.transportType = AudioDeviceManager.getTransportType(deviceID) ?? 0
        self.sampleRate = AudioDeviceManager.getSampleRate(deviceID)
        self.channelCount = AudioDeviceManager.getChannelCount(deviceID)
        self.isHDMI = AudioDeviceManager.isHDMI(deviceID)
        self.isInput = AudioDeviceManager.getStreamCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput) > 0
        self.isOutput = AudioDeviceManager.getStreamCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput) > 0
    }

    public var transportTypeName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "Built-in"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort:
            return "DisplayPort"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeBluetooth:
            return "Bluetooth"
        case kAudioDeviceTransportTypeAirPlay:
            return "AirPlay"
        case kAudioDeviceTransportTypeVirtual:
            return "Virtual"
        default:
            return "Unknown"
        }
    }
}
