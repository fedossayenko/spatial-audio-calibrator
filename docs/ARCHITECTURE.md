# System Architecture

## Overview

The Spatial Audio Calibrator is built on a layered architecture that bridges high-level Swift frameworks with low-level C APIs for precise audio control.

```
┌─────────────────────────────────────────────────────────────────┐
│                     SwiftUI Application Layer                    │
├─────────────────────────────────────────────────────────────────┤
│  Calibration Controller  │  Measurement Manager  │  UI Models   │
├─────────────────────────────────────────────────────────────────┤
│                      Business Logic Layer                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Sweep      │  │  Latency     │  │  Deconvolution       │  │
│  │  Generator   │  │  Compensator │  │  Engine              │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                       Audio Engine Layer                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    AVAudioEngine Graph                    │   │
│  │  ┌────────────┐    ┌────────────┐    ┌────────────────┐  │   │
│  │  │ SourceNode │ -> │ MixerNode  │ -> │ OutputNode     │  │   │
│  │  │ (Sweep)    │    │ (Gain)     │    │ (HDMI 5.1)     │  │   │
│  │  └────────────┘    └────────────┘    └────────────────┘  │   │
│  │                                                           │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │ InputNode (Microphone) -> Tap -> Recording Buffer  │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│                     DSP Processing Layer                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  vDSP FFT    │  │ Spectral     │  │ Inverse FFT          │  │
│  │  (Forward)   │  │ Division     │  │ (IFFT)               │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    Core Audio HAL Layer                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ AudioDevice  │  │ Channel Map  │  │ Aggregate Device     │  │
│  │ Configuration│  │ Control      │  │ Management           │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                      Hardware Layer                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ HDMI Output  │  │ Built-in     │  │ External Sound       │  │
│  │ (5.1 LPCM)   │  │ Microphone   │  │ System (LG S70TY)    │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Audio Hardware Manager
Responsible for detecting and configuring HDMI output for multichannel audio.

**Responsibilities:**
- Query available audio devices
- Identify HDMI transport endpoints
- Configure 5.1 channel layout on output device
- Create aggregate devices for clock synchronization

### 2. Channel Router
Manages discrete channel isolation for speaker-by-speaker measurement.

**Responsibilities:**
- Construct channel map arrays
- Apply `kAudioOutputUnitProperty_ChannelMap` to output Audio Unit
- Iterate through speakers systematically

### 3. Sweep Synthesizer
Real-time generation of logarithmic sine sweeps.

**Responsibilities:**
- Calculate instantaneous frequency and phase
- Render samples in real-time audio thread
- Maintain phase continuity across buffer boundaries

### 4. Latency Compensator
Measures and compensates for hardware latency.

**Responsibilities:**
- Query buffer sizes and safety offsets
- Calculate total round-trip latency
- Align recording timestamps with playback

### 5. Deconvolution Engine
Extracts Room Impulse Response from recorded audio.

**Responsibilities:**
- Zero-pad buffers to power-of-2 lengths
- Execute FFT using vDSP
- Perform regularized spectral division
- Apply inverse FFT and scaling

## Data Flow

```
1. Configuration Phase:
   ┌─────────────┐     ┌─────────────────┐     ┌────────────────┐
   │ Detect HDMI │ --> │ Configure 5.1   │ --> │ Create Aggregate│
   │ Device      │     │ Channel Layout  │     │ Device         │
   └─────────────┘     └─────────────────┘     └────────────────┘

2. Measurement Phase (per speaker):
   ┌─────────────┐     ┌─────────────────┐     ┌────────────────┐
   │ Set Channel │ --> │ Generate & Play │ --> │ Record via     │
   │ Map         │     │ Log Sweep       │     │ Microphone     │
   └─────────────┘     └─────────────────┘     └────────────────┘
          │                                            │
          v                                            v
   ┌─────────────────────────────────────────────────────┐
   │              Latency-Compensated Buffer             │
   └─────────────────────────────────────────────────────┘

3. Processing Phase:
   ┌─────────────┐     ┌─────────────────┐     ┌────────────────┐
   │ Zero-Pad    │ --> │ FFT (vDSP)      │ --> │ Spectral       │
   │ Buffers     │     │ Both Signals    │     │ Division       │
   └─────────────┘     └─────────────────┘     └────────────────┘
          │                                            │
          v                                            v
   ┌─────────────┐     ┌─────────────────┐     ┌────────────────┐
   │ Inverse FFT │ --> │ Scale Output    │ --> │ RIR Analysis   │
   │ (vDSP)      │     │ (1/2N)          │     │ & Visualization│
   └─────────────┘     └─────────────────┘     └────────────────┘
```

## Threading Model

```
┌─────────────────────────────────────────────────────────────────┐
│                        Main Thread (UI)                          │
│  - SwiftUI view updates                                          │
│  - User interaction handling                                     │
│  - Calibration state management                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              v
┌─────────────────────────────────────────────────────────────────┐
│                    Audio Thread (Real-time)                      │
│  - AVAudioSourceNode render callback                            │
│  - Sample generation (NO allocations, NO locks)                 │
│  - Direct buffer pointer manipulation                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              v
┌─────────────────────────────────────────────────────────────────┐
│                   Processing Thread (Background)                 │
│  - FFT computation                                               │
│  - Deconvolution processing                                      │
│  - Results analysis                                              │
└─────────────────────────────────────────────────────────────────┘
```

## Memory Management

### Real-time Audio Thread Constraints
- **No allocations**: All buffers pre-allocated before playback
- **No ARC triggers**: Use unsafe pointers and value types
- **No locks**: Use atomic operations for state sharing
- **No Objective-C runtime**: Pure Swift/C calls only

### Buffer Pool Strategy
```swift
// Pre-allocate buffers during initialization
class BufferPool {
    let fftSize: Int = 262144  // 2^18 for ~5s at 48kHz
    var realBuffer: [Float]
    var imagBuffer: [Float]
    var splitComplex: DSPSplitComplex

    init() {
        realBuffer = [Float](repeating: 0, count: fftSize)
        imagBuffer = [Float](repeating: 0, count: fftSize)
        splitComplex = DSPSplitComplex(realp: &realBuffer, imagp: &imagBuffer)
    }
}
```

## Error Handling

| Layer | Error Type | Recovery Strategy |
|-------|------------|-------------------|
| Hardware | Device not found | Prompt user to check connections |
| HAL | Configuration failed | Retry with fallback settings |
| Engine | Graph connection failed | Rebuild audio graph |
| DSP | FFT size exceeded | Chunk processing or reduce buffer |
| Recording | Buffer underrun | Restart measurement |

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| FFT Size | 2^18 (262,144) | ~5.5 seconds at 48kHz |
| Sweep Duration | 5-10 seconds | Configurable |
| Processing Latency | <100ms | Post-recording analysis |
| Memory Footprint | <50MB | Excluding audio buffers |
| CPU Usage (idle) | <1% | Background state |
| CPU Usage (processing) | <30% | During FFT/deconvolution |
