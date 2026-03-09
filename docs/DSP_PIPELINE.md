# DSP Pipeline Implementation

## Spectral Deconvolution with vDSP

This document details the implementation of Room Impulse Response (RIR) extraction using Apple's Accelerate framework and vDSP library.

## Mathematical Foundation

### The Convolution Problem

In Linear Time-Invariant (LTI) system theory:

```
y[n] = x[n] * h[n] + q[n]
```

Where:
- `y[n]` = Recorded signal (sweep + room response)
- `x[n]` = Original excitation signal (log sweep)
- `h[n]` = System impulse response (what we want)
- `q[n]` = Additive noise
- `*` = Convolution operator

### The Convolution Theorem

Convolution in time domain = Multiplication in frequency domain:

```
Y[k] = X[k] × H[k]
```

Therefore, to extract H[k]:

```
H[k] = Y[k] / X[k]
```

### Deconvolution Process

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Time Domain │     │ Frequency   │     │ Frequency   │
│ Signals     │ --> │ Domain (FFT)│ --> │ Division    │
│ x[n], y[n]  │     │ X[k], Y[k]  │     │ H[k] = Y/X  │
└─────────────┘     └─────────────┘     └─────────────┘
                                                │
                                                v
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Time Domain │     │ Inverse FFT │     │ Scale       │
│ Impulse     │ <-- │ (IFFT)      │ <-- │ Regularize  │
│ Response    │     │             │     │ Division    │
└─────────────┘     └─────────────┘     └─────────────┘
```

## vDSP Memory Layout

### Split-Complex Format

vDSP requires **split-complex** format for efficient FFT:

```
Standard Interleaved:    [R0, I0, R1, I1, R2, I2, ...]

Split-Complex:           Real: [R0, R1, R2, R3, ...]
                         Imag: [I0, I1, I2, I3, ...]
```

### Data Structures

```swift
import Accelerate

class DSPProcessor {
    // FFT size (power of 2)
    let fftSize: Int

    // Pre-allocated buffers
    var realInput: [Float]
    var imagInput: [Float]
    var realOutput: [Float]
    var imagOutput: [Float]

    // Split-complex structures
    var inputSplitComplex: DSPSplitComplex
    var outputSplitComplex: DSPSplitComplex

    // FFT setup (reusable)
    var fftSetup: vDSP_DFT_Setup?

    init(fftSize: Int) {
        self.fftSize = fftSize

        // Allocate buffers
        realInput = [Float](repeating: 0, count: fftSize)
        imagInput = [Float](repeating: 0, count: fftSize)
        realOutput = [Float](repeating: 0, count: fftSize)
        imagOutput = [Float](repeating: 0, count: fftSize)

        // Create split-complex pointers
        inputSplitComplex = DSPSplitComplex(
            realp: &realInput,
            imagp: &imagInput
        )

        outputSplitComplex = DSPSplitComplex(
            realp: &realOutput,
            imagp: &imagOutput
        )

        // Create DFT setup
        fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .FORWARD
        )
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_Destroy(setup)
        }
    }
}
```

## Zero-Padding Strategy

### Why Zero-Padding?

1. **Power-of-2 requirement** - vDSP FFT requires length = 2^n
2. **Avoid circular convolution** - Prevent wrap-around artifacts
3. **Increase frequency resolution** - Better interpolation

### Required Length

```
N ≥ length(x) + length(y) - 1
N = 2^⌈log₂(length(x) + length(y) - 1)⌉
```

### Implementation

```swift
extension DSPProcessor {

    /// Calculate next power of 2
    static func nextPowerOf2(_ n: Int) -> Int {
        var power = 1
        while power < n {
            power *= 2
        }
        return power
    }

    /// Zero-pad buffer to target size
    func zeroPad(_ input: [Float], targetSize: Int) -> [Float] {
        var output = [Float](repeating: 0, count: targetSize)
        let copyCount = min(input.count, targetSize)
        output[0..<copyCount] = input[0..<copyCount]
        return output
    }

    /// Prepare signals for deconvolution
    func prepareSignals(
        excitation: [Float],
        recording: [Float]
    ) -> (paddedExcitation: [Float], paddedRecording: [Float], fftSize: Int) {

        // Calculate required FFT size
        let minLength = excitation.count + recording.count - 1
        let fftSize = Self.nextPowerOf2(minLength)

        // Zero-pad both signals
        let paddedExcitation = zeroPad(excitation, targetSize: fftSize)
        let paddedRecording = zeroPad(recording, targetSize: fftSize)

        return (paddedExcitation, paddedRecording, fftSize)
    }
}
```

## Forward FFT

### Converting Real to Split-Complex

```swift
extension DSPProcessor {

    /// Convert interleaved real signal to split-complex format
    func realToSplitComplex(_ input: [Float]) -> DSPSplitComplex {
        var real = [Float](repeating: 0, count: input.count)
        var imag = [Float](repeating: 0, count: input.count)

        // For real signals, just copy to real part
        // Imag part stays zero
        vDSP_vfltip(
            input,
            1,
            &real,
            1,
            vDSP_Length(input.count)
        )

        return DSPSplitComplex(realp: &real, imagp: &imag)
    }

    /// Perform forward FFT
    func forwardFFT(input: DSPSplitComplex, output: inout DSPSplitComplex) {
        guard let setup = fftSetup else { return }

        vDSP_DFT_Execute(
            setup,
            input.realp,
            input.imagp,
            output.realp,
            output.imagp
        )

        // Scale for vDSP FFT
        var scale: Float = 1.0 / Float(fftSize)
        vDSP_vsmul(output.realp, 1, &scale, output.realp, 1, vDSP_Length(fftSize))
        vDSP_vsmul(output.imagp, 1, &scale, output.imagp, 1, vDSP_Length(fftSize))
    }
}
```

## Spectral Division

### The Zero-Division Problem

When `|X[k]| ≈ 0`, dividing by it amplifies noise catastrophically:

```
H[k] = Y[k] / X[k] = Y[k] / 0.000001 = HUGE NOISE SPIKES
```

### Wiener Deconvolution / Regularization

Add a regularization parameter λ to prevent division by near-zero:

```
H[k] = Y[k] × X*[k] / (|X[k]|² + λ(k))
```

Where λ(k) is frequency-dependent regularization.

### Implementation

```swift
extension DSPProcessor {

    /// Perform regularized spectral division
    func spectralDivision(
        recordingSpectrum: DSPSplitComplex,
        excitationSpectrum: DSPSplitComplex,
        regularizationThreshold: Float = -60 // dB
    ) -> DSPSplitComplex {

        var resultReal = [Float](repeating: 0, count: fftSize)
        var resultImag = [Float](repeating: 0, count: fftSize)

        // Calculate magnitude of excitation spectrum
        var excitationMagnitude = [Float](repeating: 0, count: fftSize)
        vDSP_zvabs(
            &excitationSpectrum,
            1,
            &excitationMagnitude,
            1,
            vDSP_Length(fftSize)
        )

        // Find peak magnitude for threshold calculation
        var peakMag: Float = 0
        vDSP_maxv(excitationMagnitude, 1, &peakMag, vDSP_Length(fftSize))

        // Calculate threshold from peak
        let threshold = peakMag * pow(10, regularizationThreshold / 20)

        // Perform division with regularization
        for i in 0..<fftSize {
            let magX = excitationMagnitude[i]
            let realY = recordingSpectrum.realp[i]
            let imagY = recordingSpectrum.imagp[i]
            let realX = excitationSpectrum.realp[i]
            let imagX = excitationSpectrum.imagp[i]

            if magX > threshold {
                // Standard complex division: Y/X
                // (a + bi) / (c + di) = ((a+bi)(c-di)) / (c² + d²)
                let denominator = realX * realX + imagX * imagX
                resultReal[i] = (realY * realX + imagY * imagX) / denominator
                resultImag[i] = (imagY * realX - realY * imagX) / denominator
            } else {
                // Apply regularization
                let regularizedDenom = realX * realX + imagX * imagX + threshold * threshold
                resultReal[i] = (realY * realX + imagY * imagX) / regularizedDenom
                resultImag[i] = (imagY * realX - realY * imagX) / regularizedDenom
            }
        }

        return DSPSplitComplex(realp: &resultReal, imagp: &resultImag)
    }
}
```

### Optimized vDSP Version

```swift
extension DSPProcessor {

    /// Optimized spectral division using vDSP
    func spectralDivisionOptimized(
        recordingSpectrum: inout DSPSplitComplex,
        excitationSpectrum: inout DSPSplitComplex,
        threshold: Float
    ) {

        // Calculate |X|² for denominator
        var magnitudeSquared = [Float](repeating: 0, count: fftSize)
        vDSP_zaspec(
            &excitationSpectrum,
            &magnitudeSquared,
            vDSP_Length(fftSize)
        )

        // Apply regularization where magnitude is too low
        var regularization = [Float](repeating: 0, count: fftSize)
        vDSP_vfill([threshold * threshold], &regularization, 1, vDSP_Length(fftSize))

        // Add regularization to denominator
        vDSP_vadd(magnitudeSquared, 1, regularization, 1, magnitudeSquared, 1, vDSP_Length(fftSize))

        // Compute Y * X* (complex conjugate multiplication)
        var numeratorReal = [Float](repeating: 0, count: fftSize)
        var numeratorImag = [Float](repeating: 0, count: fftSize]

        vDSP_zvmul(
            &recordingSpectrum,
            1,
            &excitationSpectrum,
            1,
            DSPSplitComplex(realp: &numeratorReal, imagp: &numeratorImag),
            1,
            vDSP_Length(fftSize),
            1  // Conjugate the second operand
        )

        // Divide by denominator
        vDSP_vsdiv(numeratorReal, 1, magnitudeSquared, &numeratorReal, 1, vDSP_Length(fftSize))
        vDSP_vsdiv(numeratorImag, 1, magnitudeSquared, &numeratorImag, 1, vDSP_Length(fftSize))
    }
}
```

## Inverse FFT

### Converting Back to Time Domain

```swift
extension DSPProcessor {

    /// Perform inverse FFT
    func inverseFFT(input: DSPSplitComplex, output: inout DSPSplitComplex) -> [Float] {
        guard let setup = fftSetup else { return [] }

        // Create inverse DFT setup
        guard let inverseSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .INVERSE
        ) else { return [] }

        defer { vDSP_DFT_Destroy(inverseSetup) }

        // Execute inverse DFT
        vDSP_DFT_Execute(
            inverseSetup,
            input.realp,
            input.imagp,
            output.realp,
            output.imagp
        )

        // Convert split-complex back to real
        var realOutput = [Float](repeating: 0, count: fftSize)

        // For real IFFT output, we only need the real part
        // and must apply proper scaling
        vDSP_vsmul(
            output.realp,
            1,
            [2.0],  // vDSP scales by 1/(2N), we need 1/N
            &realOutput,
            1,
            vDSP_Length(fftSize)
        )

        return realOutput
    }
}
```

## Amplitude Scaling

### The vDSP Scaling Factor

vDSP IFFT produces output scaled by `1/(2N)`. To normalize:

```swift
func normalizeImpulseResponse(_ impulse: [Float]) -> [Float] {
    var normalized = [Float](repeating: 0, count: impulse.count)
    let scaleFactor = 1.0 / Float(2 * impulse.count)

    vDSP_vsmul(
        impulse,
        1,
        [scaleFactor],
        &normalized,
        1,
        vDSP_Length(impulse.count)
    )

    return normalized
}
```

## Complete Deconvolution Pipeline

```swift
class DeconvolutionEngine {

    func extractImpulseResponse(
        excitation: [Float],
        recording: [Float],
        regularizationThreshold: Float = -60
    ) async throws -> ImpulseResponse {

        // 1. Prepare and zero-pad signals
        let (paddedExcitation, paddedRecording, fftSize) = prepareSignals(
            excitation: excitation,
            recording: recording
        )

        // 2. Create processor with correct FFT size
        let processor = DSPProcessor(fftSize: fftSize)

        // 3. Convert to split-complex
        var excSplit = processor.realToSplitComplex(paddedExcitation)
        var recSplit = processor.realToSplitComplex(paddedRecording)

        // 4. Forward FFT both signals
        var excSpectrum = DSPSplitComplex(realp: &processor.realOutput, imagp: &processor.imagOutput)
        processor.forwardFFT(input: excSplit, output: &excSpectrum)

        var recSpectrum = DSPSplitComplex(realp: &processor.realOutput, imagp: &processor.imagOutput)
        processor.forwardFFT(input: recSplit, output: &recSpectrum)

        // 5. Perform spectral division with regularization
        var resultSpectrum = processor.spectralDivision(
            recordingSpectrum: recSpectrum,
            excitationSpectrum: excSpectrum,
            regularizationThreshold: regularizationThreshold
        )

        // 6. Inverse FFT to get impulse response
        var impulseOutput = DSPSplitComplex(
            realp: &processor.realOutput,
            imagp: &processor.imagOutput
        )
        let impulseResponse = processor.inverseFFT(
            input: resultSpectrum,
            output: &impulseOutput
        )

        // 7. Normalize amplitude
        let normalized = normalizeImpulseResponse(impulseResponse)

        // 8. Trim to meaningful length
        let trimmed = trimImpulseResponse(normalized)

        return ImpulseResponse(
            samples: trimmed,
            sampleRate: 48000,
            fftSize: fftSize
        )
    }

    /// Trim impulse response to remove trailing silence
    func trimImpulseResponse(_ impulse: [Float], threshold: Float = -80) -> [Float] {
        // Find last sample above threshold
        let linearThreshold = pow(10, threshold / 20)
        var lastSignificantSample = impulse.count - 1

        for i in stride(from: impulse.count - 1, through: 0, by: -1) {
            if abs(impulse[i]) > linearThreshold {
                lastSignificantSample = i
                break
            }
        }

        // Add small padding for safety
        let end = min(lastSignificantSample + 100, impulse.count)
        return Array(impulse[0..<end])
    }
}
```

## Impulse Response Analysis

### Extracting Acoustic Parameters

```swift
struct AcousticParameters {
    let rt60: Double          // Reverberation time (60 dB decay)
    let edr: Double           // Energy Decay Curve
    let clarity: Double       // C80 clarity index
    let definition: Double    // D50 definition
    let peakAmplitude: Float
    let peakSample: Int
}

extension DeconvolutionEngine {

    func analyzeImpulseResponse(_ impulse: [Float], sampleRate: Double) -> AcousticParameters {
        // Find peak
        var peakAmplitude: Float = 0
        var peakSample = 0

        for (i, sample) in impulse.enumerated() {
            if abs(sample) > peakAmplitude {
                peakAmplitude = abs(sample)
                peakSample = i
            }
        }

        // Calculate squared energy
        let energy = impulse.map { $0 * $0 }

        // Integrate energy (Schroeder backward integration)
        var integratedEnergy = [Double](repeating: 0, count: energy.count)
        var sum = 0.0
        for i in stride(from: energy.count - 1, through: 0, by: -1) {
            sum += Double(energy[i])
            integratedEnergy[i] = sum
        }

        // Normalize
        let maxEnergy = integratedEnergy[0]
        let normalizedEnergy = integratedEnergy.map { 10 * log10($0 / maxEnergy) }

        // RT60: time for 60 dB decay
        let decay60Sample = normalizedEnergy.firstIndex { $0 < -60 } ?? energy.count
        let rt60 = Double(decay60Sample) / sampleRate

        // C80 clarity (ratio of early to late energy)
        let t80Sample = Int(0.08 * sampleRate)
        let earlyEnergy = energy[0..<t80Sample].reduce(0, +)
        let lateEnergy = energy[t80Sample..<energy.count].reduce(0, +)
        let clarity = 10 * log10(earlyEnergy / lateEnergy)

        // D50 definition (early energy / total energy)
        let t50Sample = Int(0.05 * sampleRate)
        let early50Energy = energy[0..<t50Sample].reduce(0, +)
        let totalEnergy = energy.reduce(0, +)
        let definition = early50Energy / totalEnergy

        return AcousticParameters(
            rt60: rt60,
            edr: normalizedEnergy.last ?? 0,
            clarity: clarity,
            definition: definition,
            peakAmplitude: peakAmplitude,
            peakSample: peakSample
        )
    }
}
```

## Performance Optimization

### Using FFT Setup Reuse

```swift
// Pre-create and reuse FFT setups
class FFTSetupPool {
    private var setups: [Int: vDSP_DFT_Setup] = [:]

    func setup(size: Int) -> vDSP_DFT_Setup? {
        if let existing = setups[size] {
            return existing
        }

        let newSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD)
        setups[size] = newSetup
        return newSetup
    }

    deinit {
        for setup in setups.values {
            vDSP_DFT_Destroy(setup)
        }
    }
}
```

### Memory-Efficient Processing

For very long recordings, use overlap-save or overlap-add methods:

```swift
func processChunked(
    excitation: [Float],
    recording: [Float],
    chunkSize: Int = 65536
) -> [Float] {
    // Implementation for processing large files in chunks
    // to avoid excessive memory allocation
}
```
