# Audio Pipeline Implementation

## AVAudioEngine Architecture

This document details the implementation of the multichannel audio processing graph using AVAudioEngine.

## Engine Graph Topology

```
                    ┌──────────────────────────────────────────┐
                    │              AVAudioEngine                │
                    │                                           │
┌─────────────┐     │  ┌─────────────┐     ┌─────────────────┐ │     ┌─────────────┐
│ Sweep       │     │  │             │     │                 │ │     │ HDMI        │
│ Parameters  │ --> │  │ AVAudio     │ --> │ AVAudioMixer    │ │ --> │ Output      │
│             │     │  │ SourceNode  │     │ Node            │ │     │ (5.1)       │
└─────────────┘     │  │             │     │                 │ │     └─────────────┘
                    │  └─────────────┘     └─────────────────┘ │
                    │         │                                    │
                    │         v                                    │
                    │  ┌─────────────┐                            │
                    │  │ Input Node  │ (Built-in Microphone)      │
                    │  │ + Tap       │                            │
                    │  └─────────────┘                            │
                    │         │                                    │
                    │         v                                    │
                    │  ┌─────────────┐                            │
                    │  │ Recording   │                            │
                    │  │ Buffer      │                            │
                    │  └─────────────┘                            │
                    └──────────────────────────────────────────┘
```

## Initialization

### Creating the Engine with Multichannel Format

```swift
import AVFAudio

class AudioEngine {
    let engine = AVAudioEngine()
    let sourceNode: AVAudioSourceNode
    let mixerNode = AVAudioMixerNode()
    var format: AVAudioFormat!

    init() throws {
        // Define 5.1 surround format
        let channelLayout = AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A
        )!

        format = AVAudioFormat(
            standardFormatWithSampleRate: 48000,
            channelLayout: channelLayout
        )

        // Create source node with 5.1 format output
        sourceNode = AVAudioSourceNode(
            format: format,
            renderBlock: { [weak self] isSilence, timestamp, frameCount, outputBufferList in
                guard let self = self else { return noErr }
                return self.renderSweep(
                    timestamp: timestamp,
                    frameCount: frameCount,
                    outputBufferList: outputBufferList
                )
            }
        )

        // Attach nodes to engine
        engine.attach(sourceNode)
        engine.attach(mixerNode)

        // Connect with explicit 5.1 format
        engine.connect(sourceNode, to: mixerNode, format: format)
        engine.connect(mixerNode, to: engine.outputNode, format: format)

        // Prepare engine
        engine.prepare()
    }
}
```

## Channel Mapping

### The Channel Map Problem

By default, a mono source would be automatically upmixed:

```
Mono Source --> ??? --> 5.1 Output

Default Behavior:
  Mono Channel 0 --> Front Left AND Front Right (panned center)
```

For calibration, we need **discrete isolation**:

```
Mono Source --> Channel Map --> 5.1 Output

Channel Map for Rear Left Only:
  Mono Channel 0 --> Rear Left ONLY
  All others --> Muted (-1)
```

### Implementing Channel Map

```swift
extension AudioEngine {

    /// Channel map indices for 5.1 system
    enum SpeakerChannel: Int, CaseIterable {
        case frontLeft = 0
        case frontRight = 1
        case center = 2
        case lfe = 3
        case rearLeft = 4
        case rearRight = 5

        var label: String {
            switch self {
            case .frontLeft: return "Front Left"
            case .frontRight: return "Front Right"
            case .center: return "Center/Up-firing"
            case .lfe: return "Subwoofer"
            case .rearLeft: return "Rear Left"
            case .rearRight: return "Rear Right"
            }
        }
    }

    /// Set channel map to route mono source to specific speaker
    func setChannelMap(target: SpeakerChannel) -> OSStatus {
        // Get the underlying AudioUnit from output node
        var audioUnit: AudioUnit?
        var propertySize = UInt32(MemoryLayout<AudioUnit>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioOutputUnitProperty_ChannelMap,
            mScope: kAudioUnitScope_Output,
            mElement: 0
        )

        // Build channel map array
        // Index = destination channel, Value = source channel (-1 = mute)
        var channelMap: [Int32] = [-1, -1, -1, -1, -1, -1]
        channelMap[target.rawValue] = 0  // Route mono source (channel 0) to target

        let outputNode = engine.outputNode
        let audioUnitPointer = outputNode.audioUnit

        return AudioUnitSetProperty(
            audioUnitPointer!,
            kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Output,
            0,
            &channelMap,
            UInt32(MemoryLayout<Int32>.size * channelMap.count)
        )
    }

    /// Mute all channels
    func muteAllChannels() -> OSStatus {
        var channelMap: [Int32] = [-1, -1, -1, -1, -1, -1]

        return AudioUnitSetProperty(
            engine.outputNode.audioUnit!,
            kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Output,
            0,
            &channelMap,
            UInt32(MemoryLayout<Int32>.size * channelMap.count)
        )
    }
}
```

## Sweep Synthesis

### Logarithmic Sine Sweep Mathematics

The logarithmic (exponential) sweep spends equal time per octave:

**Instantaneous Frequency:**
```
f(t) = f₁ × (f₂/f₁)^(t/T)
```

Where:
- `f₁` = start frequency (e.g., 20 Hz)
- `f₂` = end frequency (e.g., 20,000 Hz)
- `T` = total sweep duration
- `t` = current time

**Instantaneous Phase:**
```
φ(t) = (2π × f₁ × T / ln(f₂/f₁)) × (e^((t/T) × ln(f₂/f₁)) - 1)
```

### Real-time Synthesis Implementation

```swift
class SweepGenerator {
    // Parameters
    let startFrequency: Double
    let endFrequency: Double
    let duration: Double
    let sampleRate: Double

    // Pre-calculated constants
    private let frequencyRatio: Double
    private let phaseConstant: Double

    // State (must be accessed atomically in render block)
    private var currentTime: Double = 0
    private var phaseAccumulator: Double = 0
    private var isRunning = false

    init(
        startFrequency: Double = 20,
        endFrequency: Double = 20000,
        duration: Double = 5.0,
        sampleRate: Double = 48000
    ) {
        self.startFrequency = startFrequency
        self.endFrequency = endFrequency
        self.duration = duration
        self.sampleRate = sampleRate

        self.frequencyRatio = endFrequency / startFrequency
        self.phaseConstant = (2 * Double.pi * startFrequency * duration) / log(frequencyRatio)
    }

    func start() {
        currentTime = 0
        phaseAccumulator = 0
        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    /// Real-time render function - MUST be allocation-free
    func render(
        frameCount: AVAudioFrameCount,
        outputBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        guard isRunning else {
            // Output silence
            let bufferList = UnsafeMutableAudioBufferListPointer(outputBufferList)
            for buffer in bufferList {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            return noErr
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(outputBufferList)
        let channelCount = Int(bufferList.count)

        // Generate samples
        for frame in 0..<Int(frameCount) {
            // Calculate instantaneous frequency
            let t = currentTime + Double(frame) / sampleRate

            // Guard against exceeding duration
            guard t < duration else {
                isRunning = false
                // Fill remaining with silence
                for ch in 0..<channelCount {
                    let data = bufferList[ch].mData?.assumingMemoryBound(to: Float.self)
                    for f in frame..<Int(frameCount) {
                        data?[f] = 0
                    }
                }
                return noErr
            }

            // Calculate instantaneous phase
            let normalizedTime = t / duration
            let phase = phaseConstant * (exp(normalizedTime * log(frequencyRatio)) - 1)

            // Generate sample
            let sample = Float(sin(phase))

            // Write to all channels (channel map will route appropriately)
            for ch in 0..<channelCount {
                let data = bufferList[ch].mData?.assumingMemoryBound(to: Float.self)
                data?[frame] = sample
            }
        }

        // Update time for next buffer
        currentTime += Double(frameCount) / sampleRate

        return noErr
    }
}
```

### Integration with Source Node

```swift
class AudioEngine {
    private var sweepGenerator: SweepGenerator!

    init() throws {
        // ... engine setup ...

        sweepGenerator = SweepGenerator(
            startFrequency: 20,
            endFrequency: 20000,
            duration: 5.0,
            sampleRate: 48000
        )

        sourceNode = AVAudioSourceNode(
            format: format,
            renderBlock: { [weak self] isSilence, timestamp, frameCount, outputBufferList in
                guard let self = self else { return noErr }
                return self.sweepGenerator.render(
                    frameCount: frameCount,
                    outputBufferList: outputBufferList
                )
            }
        )
    }
}
```

## Input Tap for Recording

### Installing an Audio Tap

```swift
extension AudioEngine {
    func installInputTap(bufferSize: AVAudioFrameCount = 4096) throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install tap to capture microphone audio
        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputFormat
        ) { [weak self] buffer, time in
            self?.processInputBuffer(buffer, time: time)
        }
    }

    private var recordingBuffer: [Float] = []
    private var isRecording = false
    private var recordingStartTime: AVAudioTime?

    func processInputBuffer(_ buffer: AVAudioBuffer, time: AVAudioTime) {
        guard isRecording else { return }

        let audioBuffer = buffer as! AVAudioPCMBuffer

        // Copy samples to recording buffer
        if let channelData = audioBuffer.floatChannelData?[0] {
            recordingBuffer.append(contentsOf: Array(
                UnsafeBufferPointer(
                    start: channelData,
                    count: Int(audioBuffer.frameLength)
                )
            ))
        }
    }

    func startRecording(at time: AVAudioTime) {
        recordingBuffer.removeAll(keepingCapacity: true)
        recordingStartTime = time
        isRecording = true
    }

    func stopRecording() -> [Float] {
        isRecording = false
        return recordingBuffer
    }
}
```

## Latency Measurement

### Querying Hardware Latency

```swift
struct LatencyInfo {
    var outputBufferFrames: UInt32 = 0
    var outputSafetyOffset: UInt32 = 0
    var outputLatency: UInt32 = 0
    var inputSafetyOffset: UInt32 = 0
    var inputLatency: UInt32 = 0
    var totalSampleLatency: UInt32 = 0

    var milliseconds: Double {
        Double(totalSampleLatency) / 48000.0 * 1000.0
    }
}

extension AudioEngine {
    func measureLatency(deviceID: AudioDeviceID) -> LatencyInfo {
        var info = LatencyInfo()

        // Output buffer size
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &info.outputBufferFrames)

        // Output safety offset
        propertyAddress.mSelector = kAudioDevicePropertySafetyOffset
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &info.outputSafetyOffset)

        // Output stream latency
        propertyAddress.mSelector = kAudioStreamPropertyLatency
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &info.outputLatency)

        // Input safety offset
        propertyAddress.mScope = kAudioDevicePropertyScopeInput
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &info.inputSafetyOffset)

        // Input stream latency
        propertyAddress.mSelector = kAudioStreamPropertyLatency
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &info.inputLatency)

        // Calculate total
        info.totalSampleLatency = info.outputBufferFrames
                                + info.outputSafetyOffset
                                + info.outputLatency
                                + info.inputSafetyOffset
                                + info.inputLatency

        return info
    }
}
```

## Timestamp Synchronization

### Using AVAudioTime for Precise Scheduling

```swift
extension AudioEngine {
    /// Schedule sweep playback at a precise future time
    func scheduleSweep(at hostTime: UInt64) {
        let futureTime = AVAudioTime(hostTime: hostTime)

        // Source nodes don't have play(at:), so we use a manual trigger
        // For sample-accurate timing, use the timestamp in the render block

        // Start recording aligned to the same time
        startRecording(at: futureTime)
    }

    /// Calculate when to start based on latency
    func calculatePlaybackTime() -> AVAudioTime {
        let currentTime = AVAudioTime(hostTime: mach_absolute_time())
        let latencySamples = latencyInfo.totalSampleLatency

        // Add latency as offset
        let latencySeconds = Double(latencySamples) / 48000.0

        return currentTime.offset(seconds: latencySeconds + 0.1) // Small buffer
    }
}
```

## Complete Measurement Sequence

```swift
func performMeasurement(for speaker: SpeakerChannel) async throws -> [Float] {
    // 1. Set channel map for target speaker
    setChannelMap(target: speaker)

    // 2. Calculate precise start time
    let startTime = calculatePlaybackTime()

    // 3. Start recording
    startRecording(at: startTime)

    // 4. Start sweep playback
    sweepGenerator.start()

    // 5. Wait for sweep to complete
    try await Task.sleep(nanoseconds: UInt64(sweepGenerator.duration * 1_000_000_000))

    // 6. Stop recording and get buffer
    let recording = stopRecording()

    // 7. Compensate for latency
    let compensatedRecording = compensateLatency(recording)

    return compensatedRecording
}
```
