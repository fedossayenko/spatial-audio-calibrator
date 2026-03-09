# Core Audio HAL Configuration

## Low-Level Audio Device Control

This document covers direct Core Audio Hardware Abstraction Layer (HAL) interaction for device configuration, channel mapping, and aggregate device creation.

## Audio Device Properties

### Property Address Structure

```swift
struct AudioObjectPropertyAddress {
    var mSelector: AudioObjectPropertySelector
    var mScope: AudioObjectPropertyScope
    var mElement: AudioObjectPropertyElement
}
```

### Common Property Selectors

| Selector | Purpose |
|----------|---------|
| `kAudioHardwarePropertyDevices` | List all audio devices |
| `kAudioDevicePropertyDeviceName` | Get device name |
| `kAudioDevicePropertyUID` | Get unique identifier |
| `kAudioDevicePropertyTransportType` | Get connection type (HDMI, USB, etc.) |
| `kAudioDevicePropertyBufferFrameSize` | Get/set buffer size |
| `kAudioDevicePropertySafetyOffset` | Get safety offset |
| `kAudioDevicePropertyPreferredChannelLayout` | Set channel layout |
| `kAudioDevicePropertyNominalSampleRate` | Get/set sample rate |
| `kAudioStreamPropertyLatency` | Get stream latency |

### Property Scopes

| Scope | Description |
|-------|-------------|
| `kAudioObjectPropertyScopeGlobal` | Device-wide properties |
| `kAudioObjectPropertyScopeInput` | Input/capture properties |
| `kAudioObjectPropertyScopeOutput` | Output/playback properties |

## Device Enumeration

### Finding Audio Devices

```swift
import CoreAudio

class AudioDeviceManager {

    /// Get all audio devices in the system
    func getAllDevices() -> [AudioDeviceID] {
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

        guard status == noErr else { return [] }

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

        return status == noErr ? deviceIDs : []
    }

    /// Get only output devices
    func getOutputDevices() -> [AudioDeviceID] {
        return getAllDevices().filter { deviceID in
            getStreamCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput) > 0
        }
    }

    /// Get stream count for a device
    func getStreamCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)

        return propertySize / UInt32(MemoryLayout<AudioStreamID>.size)
    }
}
```

### Getting Device Information

```swift
extension AudioDeviceManager {

    /// Get device name
    func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
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
    func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyUID,
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

    /// Get transport type
    func getTransportType(_ deviceID: AudioDeviceID) -> UInt32? {
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

    /// Check if device is HDMI
    func isHDMIDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard let transportType = getTransportType(deviceID) else { return false }
        return transportType == kAudioDeviceTransportTypeHDMI
    }

    /// Get current sample rate
    func getSampleRate(_ deviceID: AudioDeviceID) -> Float64? {
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
    func setSampleRate(_ deviceID: AudioDeviceID, rate: Float64) -> Bool {
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

        return status == noErr
    }
}
```

## Channel Layout Configuration

### Setting 5.1 Channel Layout

```swift
extension AudioDeviceManager {

    /// Configure device for 5.1 surround output
    func configure51Surround(_ deviceID: AudioDeviceID) -> Bool {
        // Method 1: Use predefined layout tag
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

        return status == noErr
    }

    /// Get current channel layout
    func getChannelLayout(_ deviceID: AudioDeviceID) -> AudioChannelLayout? {
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

    /// Check if device supports specified channel count
    func supportsChannelCount(_ deviceID: AudioDeviceID, count: UInt32) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Try to get channel layout and check
        guard let layout = getChannelLayout(deviceID) else { return false }

        if layout.mChannelLayoutTag == kAudioChannelLayoutTag_UseChannelDescriptions {
            return layout.mNumberChannelDescriptions >= count
        }

        // Decode layout tag
        let channelsInTag = AudioChannelLayoutTag_GetNumberOfChannels(layout.mChannelLayoutTag)
        return channelsInTag >= count
    }
}
```

### Available Channel Layout Tags

```swift
extension AudioDeviceManager {

    /// Common surround layout tags
    enum SurroundLayout {
        case stereo
        case quad
        case surround51
        case surround71

        var layoutTag: AudioChannelLayoutTag {
            switch self {
            case .stereo:
                return kAudioChannelLayoutTag_Stereo
            case .quad:
                return kAudioChannelLayoutTag_Quadraphonic
            case .surround51:
                return kAudioChannelLayoutTag_MPEG_5_1_A
            case .surround71:
                return kAudioChannelLayoutTag_MPEG_7_1
            }
        }

        var channelCount: UInt32 {
            switch self {
            case .stereo: return 2
            case .quad: return 4
            case .surround51: return 6
            case .surround71: return 8
            }
        }
    }
}
```

## Aggregate Device Management

### Creating Aggregate Devices

```swift
extension AudioDeviceManager {

    struct AggregateDeviceConfig {
        let name: String
        let uid: String
        let masterDeviceID: AudioDeviceID
        let subDeviceIDs: [AudioDeviceID]
        let isPrivate: Bool = true
    }

    /// Create an aggregate device for synchronized I/O
    func createAggregateDevice(config: AggregateDeviceConfig) -> AudioDeviceID? {
        // Get the audio plug-in
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyPlugInForBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var pluginID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var bundleID = "com.apple.audio.CoreAudio" as CFString

        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &size,
            &pluginID
        )

        guard status == noErr else { return nil }

        // Build sub-device list
        var subDevices: [[String: Any]] = []
        for subID in config.subDeviceIDs {
            if let uid = getDeviceUID(subID) {
                subDevices.append([
                    kAudioSubDeviceUIDKey: uid
                ])
            }
        }

        // Create aggregate device
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: config.name,
            kAudioAggregateDeviceUIDKey: config.uid,
            kAudioAggregateDeviceIsPrivateKey: config.isPrivate,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMasterDeviceKey: config.masterDeviceID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices
        ]

        propertyAddress.mSelector = kAudioPlugInCreateAggregateDevice

        var aggregateDeviceID: AudioDeviceID = 0
        status = AudioObjectGetPropertyData(
            pluginID,
            &propertyAddress,
            UInt32(dict.count),
            dict as CFDictionary,
            &size,
            &aggregateDeviceID
        )

        return status == noErr ? aggregateDeviceID : nil
    }

    /// Destroy an aggregate device
    func destroyAggregateDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioPlugInDestroyAggregateDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            nil
        )

        // Get plug-in ID first
        var pluginID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var getPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyPlugInForBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &getPropertyAddress,
            0,
            nil,
            &size,
            &pluginID
        )

        guard status == noErr else { return false }

        status = AudioObjectGetPropertyData(
            pluginID,
            &propertyAddress,
            0,
            nil,
            &size,
            &deviceID
        )

        return status == noErr
    }
}
```

## Buffer and Latency Configuration

### Querying Buffer Properties

```swift
extension AudioDeviceManager {

    struct BufferConfiguration {
        var bufferSize: UInt32
        var safetyOffsetOutput: UInt32
        var safetyOffsetInput: UInt32
        var streamLatencyOutput: UInt32
        var streamLatencyInput: UInt32
    }

    func getBufferConfiguration(_ deviceID: AudioDeviceID) -> BufferConfiguration? {
        var config = BufferConfiguration(
            bufferSize: 0,
            safetyOffsetOutput: 0,
            safetyOffsetInput: 0,
            streamLatencyOutput: 0,
            streamLatencyInput: 0
        )

        // Buffer size
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
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

    /// Calculate total round-trip latency in samples
    func calculateTotalLatency(_ config: BufferConfiguration) -> UInt32 {
        return config.bufferSize
             + config.safetyOffsetOutput
             + config.streamLatencyOutput
             + config.safetyOffsetInput
             + config.streamLatencyInput
    }
}
```

### Setting Buffer Size

```swift
extension AudioDeviceManager {

    /// Set buffer size (may require elevated permissions)
    func setBufferSize(_ deviceID: AudioDeviceID, frames: UInt32) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var bufferSize = frames
        let size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            size,
            &bufferSize
        )

        return status == noErr
    }

    /// Get available buffer size range
    func getBufferSizeRange(_ deviceID: AudioDeviceID) -> (min: UInt32, max: UInt32)? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &size,
            &range
        )

        return status == noErr ? (UInt32(range.mMinimum), UInt32(range.mMaximum)) : nil
    }
}
```

## Device Notification Callbacks

### Listening for Device Changes

```swift
extension AudioDeviceManager {

    typealias DeviceChangeCallback = (AudioDeviceID, AudioObjectPropertySelector) -> Void

    func registerForDeviceNotifications(
        deviceID: AudioDeviceID,
        callback: @escaping DeviceChangeCallback
    ) -> AudioObjectPropertyListenerBlock? {

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceHasChanged,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listenerBlock: AudioObjectPropertyListenerBlock = { numberAddresses, addresses in
            for i in 0..<Int(numberAddresses) {
                let selector = addresses[i].pointee.mSelector
                callback(deviceID, selector)
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &propertyAddress,
            nil,
            listenerBlock
        )

        return status == noErr ? listenerBlock : nil
    }

    func unregisterDeviceNotifications(
        deviceID: AudioDeviceID,
        listenerBlock: AudioObjectPropertyListenerBlock
    ) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceHasChanged,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            deviceID,
            &propertyAddress,
            nil,
            listenerBlock
        )
    }
}
```

## Error Handling

### Core Audio Error Codes

```swift
extension AudioDeviceManager {

    static func errorMessage(_ status: OSStatus) -> String {
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
}
```
