# Implementation Plan

## Overview

This document outlines the phased implementation strategy for the Spatial Audio Calibrator, following a bottom-up approach from foundational components to the user interface.

## Phase 1: Core Foundation

### 1.1 Project Structure & Package Setup
- [ ] Create `Package.swift` with Swift 5.9, macOS 14 target
- [ ] Set up Sources/SpatialAudioCalibrator directory structure
- [ ] Create Tests directory structure

### 1.2 Models
- [ ] `SpeakerChannel` - Enum for 5.1 speaker channels
- [ ] `CalibrationConfig` - Measurement parameters
- [ ] `CalibrationState` - State machine enum
- [ ] `CalibrationError` - Error types
- [ ] `ImpulseResponse` - RIR data model
- [ ] `AcousticParameters` - Analysis results model
- [ ] `BufferConfiguration` - Latency info model

### 1.3 Core Audio HAL Layer
- [ ] `AudioDeviceManager` - Device enumeration and properties
  - `getAllDevices()`, `getOutputDevices()`, `getInputDevices()`
  - `findHDMIDevice()`, `getDefaultOutputDevice()`
  - `getName()`, `getUID()`, `getTransportType()`, `getSampleRate()`
  - `getChannelCount()`, `isHDMI()`
  - `getBufferConfiguration()`, `calculateTotalLatency()`

**Estimated Time:** 2-3 hours
**Dependencies:** None
**Test Coverage:** Unit tests for device enumeration, property queries

---

## Phase 2: Audio Engine Layer

### 2.1 Signal Generation
- [ ] `SweepGenerator` - Logarithmic sine sweep synthesis
  - Pre-calculated phase constants
  - Real-time render callback (allocation-free)
  - Phase continuity across buffers
  - Start/stop/reset control

### 2.2 Audio Engine
- [ ] `AudioEngine` - AVAudioEngine management
  - 5.1 multichannel format configuration
  - AVAudioSourceNode integration
  - Channel mapping for speaker isolation
  - Input tap for microphone recording
  - Engine start/stop control

### 2.3 Latency Management
- [ ] `LatencyCompensator` - Round-trip latency handling
  - Hardware latency query
  - Recording timestamp alignment
  - Buffer trimming based on latency

**Estimated Time:** 4-6 hours
**Dependencies:** Phase 1 complete
**Test Coverage:**
- Sweep frequency range verification
- Phase continuity tests
- Channel map correctness
- Mock audio engine tests

---

## Phase 3: DSP Processing Layer

### 3.1 FFT Processing
- [ ] `FFTProcessor` - vDSP FFT wrapper
  - Split-complex buffer management
  - Forward FFT
  - Inverse FFT
  - FFT setup reuse for performance

### 3.2 Spectral Operations
- [ ] `SpectralDivision` - Frequency domain operations
  - Zero-padding to power-of-2
  - Regularized spectral division
  - Wiener deconvolution support

### 3.3 Deconvolution Engine
- [ ] `DeconvolutionEngine` - RIR extraction
  - Full deconvolution pipeline
  - Progress callbacks
  - Result trimming
  - Error handling

### 3.4 Acoustic Analysis
- [ ] `AcousticAnalyzer` - RIR analysis
  - RT60 calculation
  - EDT (Early Decay Time)
  - Clarity indices (C50, C80)
  - Definition (D50, D80)
  - Frequency response extraction

**Estimated Time:** 5-7 hours
**Dependencies:** Phase 1 complete (independent of Phase 2)
**Test Coverage:**
- Known impulse response deconvolution
- FFT accuracy verification
- Regularization edge cases
- Acoustic parameter calculation

---

## Phase 4: Business Logic Layer

### 4.1 Main Orchestrator
- [ ] `AudioCalibrator` - Primary coordinator
  - System configuration verification
  - Calibration sequence management
  - Per-speaker measurement
  - Results aggregation
  - Error recovery

### 4.2 Measurement Manager
- [ ] `MeasurementSession` - Single calibration session
  - Session state tracking
  - Progress reporting
  - Results storage

### 4.3 Export Functionality
- [ ] `WAVEExporter` - WAV file export
  - 32-bit float format
  - Metadata embedding
- [ ] `MeasurementExporter` - JSON export
  - Analysis results
  - Configuration snapshot

**Estimated Time:** 3-4 hours
**Dependencies:** Phases 1, 2, 3 complete
**Test Coverage:**
- Full calibration sequence (mocked)
- State transitions
- Export format validation

---

## Phase 5: User Interface Layer

### 5.1 Main Views
- [ ] `ContentView` - Main application view
- [ ] `CalibrationView` - Calibration controls
- [ ] `DeviceSelectionView` - HDMI device picker
- [ ] `MeasurementProgressView` - Real-time progress

### 5.2 Visualization
- [ ] `ImpulseResponseView` - Waveform display
- [ ] `FrequencyResponseView` - Frequency graph
- [ ] `AcousticParametersView` - Metrics display

### 5.3 ViewModels
- [ ] `CalibrationViewModel` - Main UI state
- [ ] `MeasurementViewModel` - Per-measurement state

**Estimated Time:** 4-6 hours
**Dependencies:** Phase 4 complete
**Test Coverage:** SwiftUI preview tests, UI integration tests

---

## Testing Strategy

### Unit Tests
- Each module has corresponding test file
- Mock audio devices for HAL testing
- Known signals for DSP verification

### Integration Tests
- Full measurement sequence with mock hardware
- Deconvolution with synthetic impulse responses
- Export/import round-trip tests

### Performance Tests
- FFT execution time (< 100ms for 2^18)
- Memory footprint (< 50MB target)
- Real-time audio safety (no allocations in render path)

---

## File Structure After Implementation

```
spatial-audio-calibrator/
├── Package.swift
├── README.md
├── docs/
│   └── [existing documentation]
├── Sources/
│   └── SpatialAudioCalibrator/
│       ├── App/
│       │   ├── SpatialAudioCalibratorApp.swift
│       │   └── ContentView.swift
│       ├── Core/
│       │   ├── AudioCalibrator.swift
│       │   ├── CalibrationConfig.swift
│       │   └── CalibrationState.swift
│       ├── Engine/
│       │   ├── AudioEngine.swift
│       │   ├── SweepGenerator.swift
│       │   └── LatencyCompensator.swift
│       ├── DSP/
│       │   ├── DeconvolutionEngine.swift
│       │   ├── FFTProcessor.swift
│       │   └── SpectralDivision.swift
│       ├── HAL/
│       │   ├── AudioDeviceManager.swift
│       │   └── ChannelMapper.swift
│       ├── Models/
│       │   ├── ImpulseResponse.swift
│       │   ├── AcousticParameters.swift
│       │   └── SpeakerChannel.swift
│       ├── UI/
│       │   ├── Views/
│       │   ├── ViewModels/
│       │   └── Components/
│       └── Utils/
│           ├── WAVEExporter.swift
│           └── MathHelpers.swift
└── Tests/
    └── SpatialAudioCalibratorTests/
        ├── AudioEngineTests.swift
        ├── SweepGeneratorTests.swift
        ├── DeconvolutionTests.swift
        └── FFTProcessorTests.swift
```

---

## Current Status

**Phase:** 1 - Core Foundation
**Next Steps:**
1. Create Package.swift
2. Implement SpeakerChannel enum
3. Implement CalibrationConfig
4. Implement AudioDeviceManager

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| HDMI device detection varies by Mac | Test on multiple hardware, provide fallback |
| Channel map not respected | Verify with Audio MIDI Setup, add diagnostics |
| vDSP scaling factors | Use known test signals for verification |
| Real-time audio glitches | Profile with Instruments, enforce allocation-free render |
| Microphone permission denied | Clear error messaging, guide to System Settings |
