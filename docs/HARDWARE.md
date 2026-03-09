# Hardware Interfacing

## Overview

This document details the hardware requirements and interfacing protocols for establishing multichannel LPCM transmission between the Mac and the target audio system.

## Target Hardware Configuration

### LG S70TY Soundbar System

| Component | Specification | Role |
|-----------|---------------|------|
| LG S70TY Soundbar | 3.1.1 channels | Front L/C/R + Up-firing Center + Subwoofer |
| LG SPT8-S Rear Speakers | 2.0 channels | Wireless rear L/R satellites |
| **Combined System** | **5.1.1 channels** | Full spatial array |

### Channel Mapping

| Core Audio Index | SMPTE Label | Physical Hardware |
|------------------|-------------|-------------------|
| 0 | `kAudioChannelLabel_Left` | Soundbar Front Left |
| 1 | `kAudioChannelLabel_Right` | Soundbar Front Right |
| 2 | `kAudioChannelLabel_Center` | Soundbar Front Center / Up-firing |
| 3 | `kAudioChannelLabel_LFEScreen` | Wireless Active Subwoofer |
| 4 | `kAudioChannelLabel_LeftSurround` | SPT8-S Rear Left |
| 5 | `kAudioChannelLabel_RightSurround` | SPT8-S Rear Right |

## HDMI LPCM Transmission

### Why LPCM?

Acoustic calibration requires **uncompressed Linear Pulse Code Modulation** to ensure:

1. **No encoding artifacts** - Dolby/DTS encoders introduce psychoacoustic modifications
2. **No dynamic range compression** - Preserve full amplitude range
3. **No spatial virtualization** - Bypass internal upmixing algorithms
4. **Deterministic output** - Exact sample reproduction

### HDMI Bandwidth Considerations

| Format | Channels | Sample Rate | Bit Depth | Data Rate |
|--------|----------|-------------|-----------|-----------|
| Stereo LPCM | 2 | 48 kHz | 16-bit | 1.54 Mbps |
| 5.1 LPCM | 6 | 48 kHz | 24-bit | 6.91 Mbps |
| 5.1 LPCM | 6 | 96 kHz | 24-bit | 13.82 Mbps |
| 7.1 LPCM | 8 | 192 kHz | 24-bit | 36.86 Mbps |

**Note**: Apple Silicon Macs use DisplayPort protocol encapsulated in USB-C/Thunderbolt, with HDMI bandwidth limited to 8 channels at 192 kHz.

## macOS EDID and eARC Challenges

### The EDID Problem

macOS queries the **Extended Display Identification Data (EDID)** of connected devices to determine supported audio formats. Common issues:

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  Mac (HDMI) │ -------> │  TV Display │ -------> │  Soundbar   │
└─────────────┘         └─────────────┘         └─────────────┘
                              │
                              v
                        EDID Response:
                        "I only support
                         2.0 stereo!"

                        (Even though soundbar
                         supports 5.1)
```

### eARC vs ARC

| Feature | ARC | eARC |
|---------|-----|------|
| Bandwidth | 1 Mbps | 37 Mbps |
| Max Channels | 2.0 (compressed) | 7.1 (uncompressed) |
| LPCM Support | No | Yes |
| Dolby TrueHD | No | Yes |
| DTS:X | No | Yes |

### Recommended Connection Topologies

#### Option A: Direct HDMI to Soundbar (Recommended)
```
┌─────────────┐         ┌─────────────┐
│  Mac (HDMI) │ -------> │  Soundbar   │ -----> TV (eARC)
└─────────────┘         │  HDMI IN    │         Passthrough
                        └─────────────┘
```

#### Option B: eARC-Compliant TV Passthrough
```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  Mac (HDMI) │ -------> │  eARC TV    │ -------> │  Soundbar   │
└─────────────┘         │  HDMI 2.1   │  eARC   │  HDMI eARC  │
                        └─────────────┘         └─────────────┘
```

#### Option C: HDMI Audio Extractor
```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  Mac (HDMI) │ -------> │  Audio      │ --HDMI->│  TV Display │
└─────────────┘         │  Extractor  │         └─────────────┘
                        └─────────────┘
                              │
                              v
                         HDMI Audio
                           to Soundbar
```

## Programmatic Device Detection

### Finding HDMI Audio Device

```swift
import CoreAudio

struct AudioDevice {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let isHDMI: Bool
}

func findHDMIDevice() -> AudioDevice? {
    var propertySize: UInt32 = 0
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // Get property size
    AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &propertySize
    )

    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

    AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &propertySize,
        &deviceIDs
    )

    for deviceID in deviceIDs {
        if let transportType = getTransportType(deviceID),
           transportType == kAudioDeviceTransportTypeHDMI {
            return AudioDevice(
                id: deviceID,
                name: getDeviceName(deviceID) ?? "Unknown",
                uid: getDeviceUID(deviceID) ?? "",
                isHDMI: true
            )
        }
    }

    return nil
}
```

### Getting Transport Type

```swift
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
```

## Configuring 5.1 Channel Layout

### Setting Preferred Channel Layout

```swift
func setChannelLayout(deviceID: AudioDeviceID) -> Bool {
    // Define 5.1 channel layout
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
```

### Defining Custom Channel Layout

```swift
func createCustomChannelLayout() -> AudioChannelLayout {
    var layout = AudioChannelLayout()
    layout.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
    layout.mNumberChannelDescriptions = 6

    let labels: [AudioChannelLabel] = [
        kAudioChannelLabel_Left,           // 0: Front Left
        kAudioChannelLabel_Right,          // 1: Front Right
        kAudioChannelLabel_Center,         // 2: Center/Up-firing
        kAudioChannelLabel_LFEScreen,      // 3: Subwoofer
        kAudioChannelLabel_LeftSurround,   // 4: Rear Left
        kAudioChannelLabel_RightSurround   // 5: Rear Right
    ]

    // Initialize channel descriptions
    layout.mChannelDescriptions = (
        AudioChannelDescription(labels[0], 0, 0, []),
        AudioChannelDescription(labels[1], 0, 0, []),
        AudioChannelDescription(labels[2], 0, 0, []),
        AudioChannelDescription(labels[3], 0, 0, []),
        AudioChannelDescription(labels[4], 0, 0, []),
        AudioChannelDescription(labels[5], 0, 0, []),
        // Remaining are unused
    )

    return layout
}
```

## Aggregate Device Creation

### Why Aggregate Devices?

When input (microphone) and output (HDMI) use different hardware clocks:

```
Mac Internal Clock: 48,000.01 Hz
HDMI External Clock: 47,999.98 Hz
                      ↑
                      Drift over time!
```

An **Aggregate Device** forces both to share one clock master.

### Creating an Aggregate Device

```swift
func createAggregateDevice(
    inputDeviceID: AudioDeviceID,
    outputDeviceID: AudioDeviceID
) -> AudioDeviceID? {

    var description = AudioObjectPropertyAddress(
        mSelector: kAudioPlugInCreateAggregateDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // Create aggregate device configuration
    let config: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Spatial Calibrator Aggregate",
        kAudioAggregateDeviceUIDKey: "com.calibrator.aggregate",
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
        kAudioAggregateDeviceMasterDeviceKey: outputDeviceID,  // HDMI as master
        kAudioAggregateDeviceSubDeviceListKey: [
            [kAudioSubDeviceUIDKey: getDeviceUID(inputDeviceID)],
            [kAudioSubDeviceUIDKey: getDeviceUID(outputDeviceID)]
        ]
    ]

    var aggregateID: AudioDeviceID = 0
    var status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &description,
        config.count,
        config as CFDictionary,
        &aggregateID
    )

    return status == noErr ? aggregateID : nil
}
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Stereo only output | TV EDID limitation | Connect directly to soundbar |
| No audio output | HDMI not default device | Set in System Settings > Sound |
| Channel mismatch | Wrong layout tag | Use MPEG_5_1_A tag |
| Clock drift | Separate devices | Create aggregate device |
| Dropout during playback | Buffer too small | Increase buffer size to 1024+ |

### Diagnostic Commands

```bash
# List all audio devices
system_profiler SPAudioDataType

# Check current audio configuration
afplay -l

# Verify HDMI audio support
ffmpeg -f lavfi -i anullsrc -f alsa default
```

### Audio MIDI Setup Verification

1. Open **Audio MIDI Setup** (Applications > Utilities)
2. Check HDMI device shows **6-channel** configuration
3. Verify sample rate matches (48,000 Hz)
4. Confirm channel labels match expected mapping
