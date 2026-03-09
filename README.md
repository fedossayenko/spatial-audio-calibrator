# Spatial Audio Calibrator

## Advanced Acoustic Calibration System for 5.1.1 Spatial Audio on macOS

A precision acoustic calibration tool for modern spatial audio hardware, built with Swift, AVAudioEngine, and Apple's Accelerate framework (vDSP).

### Overview

This application performs discrete acoustic measurement of spatial audio systems by:
- Establishing uncompressed 5.1 LPCM transmission over HDMI
- Isolating individual speaker channels via Core Audio routing
- Synthesizing mathematically precise logarithmic sine sweeps
- Capturing acoustic responses via microphone
- Deriving Room Impulse Responses (RIR) through spectral deconvolution

### Target Hardware

- **Primary**: LG S70TY Soundbar (3.1.1 native configuration)
- **Extended**: LG S70TY + SPT8-S Wireless Rear Satellites (5.1.1 configuration)

### Key Features

- 🔊 Discrete channel isolation for individual speaker measurement
- 📊 Real-time logarithmic sine sweep synthesis
- 🎯 Sample-accurate playback/recording synchronization
- 🧮 Accelerate framework vDSP optimization for FFT operations
- 📐 Regularized spectral division for noise-resistant deconvolution
- ⏱️ Sub-millisecond latency compensation

### System Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon Mac (M1/M2/M3 series)
- HDMI output with eARC support
- Target audio device with multichannel LPCM support

### Project Structure

```
spatial-audio-calibrator/
├── README.md                 # This file
├── docs/
│   ├── ARCHITECTURE.md       # System architecture overview
│   ├── HARDWARE.md           # Hardware interfacing guide
│   ├── AUDIO_PIPELINE.md     # AVAudioEngine implementation
│   ├── DSP_PIPELINE.md       # vDSP signal processing
│   ├── CORE_AUDIO.md         # Core Audio HAL configuration
│   ├── MEASUREMENT_PROTOCOL.md # Calibration procedure
│   ├── API_REFERENCE.md      # Code API documentation
│   └── DEVELOPMENT.md        # Development setup guide
├── src/
│   ├── CoreAudio/           # Core Audio HAL wrappers
│   ├── Engine/              # AVAudioEngine graph
│   ├── DSP/                 # vDSP signal processing
│   ├── Synthesis/           # Signal generators
│   └── UI/                  # SwiftUI interface
├── tests/                    # Unit and integration tests
├── assets/                   # Audio test files, resources
└── config/                   # Configuration files
```

### Quick Start

```bash
# Clone and open in Xcode
open SpatialAudioCalibrator.xcodeproj

# Build and run
# Ensure HDMI audio output is configured for 5.1 surround
```

### Documentation

- [Architecture Overview](docs/ARCHITECTURE.md)
- [Hardware Requirements](docs/HARDWARE.md)
- [Audio Pipeline](docs/AUDIO_PIPELINE.md)
- [DSP Pipeline](docs/DSP_PIPELINE.md)
- [Development Guide](docs/DEVELOPMENT.md)

### License

MIT License - See LICENSE file for details.

### References

- Apple AVAudioEngine Documentation
- Apple Accelerate Framework Guide
- Core Audio Hardware Abstraction Layer
- Room Acoustics and Impulse Response Measurement
