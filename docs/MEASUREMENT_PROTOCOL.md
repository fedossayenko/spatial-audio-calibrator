# Measurement Protocol

## Calibration Procedure

This document outlines the complete acoustic measurement workflow for the LG S70TY 5.1.1 spatial audio system.

## Pre-Measurement Checklist

### Environment Setup

```
□ Room is quiet (ambient noise < 40 dB SPL)
□ No active HVAC or fans
□ All other audio sources muted
□ Windows/doors closed to minimize external noise
□ Furniture and objects in stable positions
□ Primary listening position identified
```

### Hardware Verification

```
□ HDMI cable connected to soundbar (direct preferred)
□ Soundbar powered on and configured for LPCM passthrough
□ SPT8-S rear satellites paired and positioned
□ Mac audio output set to HDMI device
□ Microphone access granted to application
□ 5.1 channel layout confirmed in Audio MIDI Setup
```

### Software Configuration

```swift
struct CalibrationConfig {
    // Sweep parameters
    let startFrequency: Double = 20      // Hz
    let endFrequency: Double = 20000     // Hz
    let sweepDuration: Double = 5.0      // seconds
    let sampleRate: Double = 48000       // Hz

    // Recording parameters
    let preSweepSilence: Double = 0.5    // seconds before sweep
    let postSweepSilence: Double = 2.0   // seconds after sweep (for reverb tail)

    // Processing parameters
    let fftSize: Int = 262144            // 2^18 for ~5.5s
    let regularizationThreshold: Float = -60  // dB

    // Output parameters
    let outputAmplitude: Float = 0.8     // 0-1 normalized
}
```

## Measurement Sequence

### Phase 1: System Initialization

```
┌─────────────────────────────────────────────────────────────┐
│                    INITIALIZATION                            │
├─────────────────────────────────────────────────────────────┤
│  1. Detect HDMI audio device                                │
│  2. Verify 5.1 channel support                              │
│  3. Configure output format (48kHz, 5.1)                    │
│  4. Create aggregate device (HDMI + Microphone)             │
│  5. Initialize AVAudioEngine                                │
│  6. Measure round-trip latency                              │
│  7. Install input tap for recording                         │
│  8. Verify signal path (brief test tone)                    │
└─────────────────────────────────────────────────────────────┘
```

### Phase 2: Speaker-by-Speaker Measurement

```
┌─────────────────────────────────────────────────────────────┐
│              MEASUREMENT LOOP (Per Speaker)                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  FOR EACH speaker IN [FL, FR, C, LFE, RL, RR]:              │
│                                                              │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ 1. Set channel map to isolate target speaker        │  │
│    │    channelMap = [-1, -1, -1, -1, -1, -1]           │  │
│    │    channelMap[targetIndex] = 0                      │  │
│    └─────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          v                                   │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ 2. Prepare sweep generator                          │  │
│    │    - Reset phase accumulator                        │  │
│    │    - Set duration and frequency range               │  │
│    └─────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          v                                   │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ 3. Start recording buffer                           │  │
│    │    - Clear previous recording                       │  │
│    │    - Set start timestamp                            │  │
│    └─────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          v                                   │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ 4. Play logarithmic sweep                           │  │
│    │    - 20 Hz → 20 kHz exponential chirp               │  │
│    │    - Duration: 5 seconds                            │  │
│    └─────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          v                                   │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ 5. Continue recording for reverb tail               │  │
│    │    - Additional 2 seconds post-sweep                │  │
│    └─────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          v                                   │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ 6. Stop recording                                   │  │
│    │    - Compensate for measured latency                │  │
│    │    - Trim pre-sweep silence                         │  │
│    └─────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          v                                   │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ 7. Perform spectral deconvolution                   │  │
│    │    - FFT(recording) / FFT(excitation)               │  │
│    │    - Regularized division                           │  │
│    │    - Inverse FFT                                    │  │
│    │    - Normalize amplitude                            │  │
│    └─────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          v                                   │
│    ┌─────────────────────────────────────────────────────┐  │
│    │ 8. Store impulse response for speaker               │  │
│    │    - Save to disk                                   │  │
│    │    - Calculate acoustic parameters                  │  │
│    └─────────────────────────────────────────────────────┘  │
│                                                              │
│  NEXT speaker                                                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Speaker Order

For the LG S70TY + SPT8-S system, measure in this order:

| Order | Speaker | Channel Index | Notes |
|-------|---------|---------------|-------|
| 1 | Front Left | 0 | Soundbar left driver |
| 2 | Front Right | 1 | Soundbar right driver |
| 3 | Center | 2 | Soundbar center/up-firing |
| 4 | LFE | 3 | Wireless subwoofer |
| 5 | Rear Left | 4 | SPT8-S left satellite |
| 6 | Rear Right | 5 | SPT8-S right satellite |

## Signal Analysis

### Real-time Monitoring

During measurement, display:

```swift
struct MeasurementProgress {
    let currentSpeaker: String
    let speakerIndex: Int
    let totalSpeakers: Int
    let sweepProgress: Double      // 0.0 - 1.0
    let currentFrequency: Double   // Hz
    let inputLevel: Float          // dBFS
}
```

### Post-Measurement Analysis

For each impulse response, calculate:

```swift
struct SpeakerAnalysis {
    let speakerName: String

    // Time domain
    let peakAmplitude: Float
    let peakTime: Double           // milliseconds
    let peakSample: Int

    // Frequency domain
    let frequencyResponse: [(frequency: Double, magnitude: Double)]
    let phaseResponse: [(frequency: Double, phase: Double)]

    // Room acoustics
    let rt60: Double               // Reverberation time (seconds)
    let earlyDecay: Double         // EDT (seconds)
    let clarityC80: Double         // C80 (dB)
    let definitionD50: Double      // D50 (ratio)

    // Anomalies
    let hasClipping: Bool
    let hasNoise: Bool
    let noiseFloor: Double         // dB
}
```

## Quality Validation

### Automatic Checks

```swift
func validateMeasurement(_ analysis: SpeakerAnalysis) -> [ValidationError] {
    var errors: [ValidationError] = []

    // Check for clipping
    if analysis.peakAmplitude > 0.95 {
        errors.append(.clipping(analysis.speakerName))
    }

    // Check signal-to-noise ratio
    let snr = analysis.peakAmplitude - Float(analysis.noiseFloor)
    if snr < 40 {
        errors.append(.lowSNR(analysis.speakerName, snr))
    }

    // Check for valid impulse
    if analysis.peakTime < 0 {
        errors.append(.invalidTiming(analysis.speakerName))
    }

    // Check RT60 reasonableness
    if analysis.rt60 < 0.1 || analysis.rt60 > 5.0 {
        errors.append(.abnormalRT60(analysis.speakerName, analysis.rt60))
    }

    return errors
}

enum ValidationError {
    case clipping(String)
    case lowSNR(String, Float)
    case invalidTiming(String)
    case abnormalRT60(String, Double)
    case noSignal(String)
}
```

### Manual Review Criteria

After automated validation, review:

1. **Impulse Response Shape**
   - Clean direct sound peak
   - Exponential decay envelope
   - No obvious artifacts or spikes

2. **Frequency Response**
   - Expected roll-off at extremes
   - No unusual notches or peaks
   - LFE has expected low-pass characteristic

3. **Consistency Between Speakers**
   - Similar RT60 across speakers
   - Comparable noise floors
   - Symmetrical responses for stereo pairs (L/R, RL/RR)

## Data Export

### Impulse Response Files

Export each measured impulse response as:

```
exports/
├── YYYY-MM-DD_HH-MM/
│   ├── front_left.wav
│   ├── front_right.wav
│   ├── center.wav
│   ├── lfe.wav
│   ├── rear_left.wav
│   ├── rear_right.wav
│   ├── analysis.json
│   └── config.json
```

### WAV Format

```swift
struct WAVEExport {
    let sampleRate: UInt32 = 48000
    let bitsPerSample: UInt16 = 32
    let numChannels: UInt16 = 1
    let audioFormat: UInt16 = 3  // IEEE float
}
```

### Analysis JSON

```json
{
  "measurementDate": "2025-03-10T14:30:00Z",
  "systemInfo": {
    "soundbar": "LG S70TY",
    "rearSpeakers": "LG SPT8-S",
    "macModel": "MacBookPro18,3",
    "macOSVersion": "14.3.0"
  },
  "config": {
    "startFrequency": 20,
    "endFrequency": 20000,
    "sweepDuration": 5.0,
    "sampleRate": 48000
  },
  "speakers": {
    "front_left": {
      "peakAmplitude": 0.72,
      "peakTime": 12.5,
      "rt60": 0.34,
      "clarityC80": 2.1,
      "definitionD50": 0.45
    }
  }
}
```

## Repeat Measurements

### When to Re-measure

- SNR below 40 dB
- Clipping detected
- Unexpected frequency response anomalies
- Measurement interrupted
- Environmental noise during capture

### Averaging Multiple Measurements

For improved accuracy:

```swift
func averageImpulseResponses(_ impulses: [[Float]]) -> [Float] {
    guard !impulses.isEmpty else { return [] }

    let length = impulses.map { $0.count }.max() ?? 0
    var averaged = [Float](repeating: 0, count: length)
    var counts = [Float](repeating: 0, count: length)

    for impulse in impulses {
        for i in 0..<min(impulse.count, length) {
            averaged[i] += impulse[i]
            counts[i] += 1
        }
    }

    vDSP_vdiv(counts, 1, averaged, 1, &averaged, 1, vDSP_Length(length))

    return averaged
}
```

## Microphone Calibration

### Built-in Microphone Limitations

The MacBook Pro internal microphone has:

- **Non-flat frequency response** (~±10 dB variation)
- **High-pass filter** (typically -3 dB @ 80-100 Hz)
- **Directional characteristics** (MEMS array)
- **Cabinet resonances** (laptop chassis effects)

### For Production Use

For accurate absolute measurements:

1. Use external measurement microphone (e.g., miniDSP UMIK-1)
2. Apply calibration file to recorded signals
3. Position microphone at listening position
4. Use proper mic stand (not laptop surface)

### Microphone Calibration File Application

```swift
func applyMicrophoneCalibration(
    recording: [Float],
    calibrationFile: MicrophoneCalibration,
    sampleRate: Double
) -> [Float] {
    // FFT the recording
    // Divide by calibration magnitude at each frequency
    // Inverse FFT
    // Return calibrated recording
}

struct MicrophoneCalibration {
    let frequencies: [Double]
    let magnitudes: [Double]  // dB
    let phases: [Double]      // degrees
}
```
