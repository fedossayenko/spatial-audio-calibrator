import Accelerate
import Foundation

/// Extracts Room Impulse Responses from recorded audio using spectral deconvolution.
///
/// The deconvolution process:
/// 1. Zero-pad signals to power-of-2 length
/// 2. Compute FFT of excitation and recording
/// 3. Perform regularized spectral division: H[k] = Y[k] / X[k]
/// 4. Apply inverse FFT to get time-domain impulse response
public final class DeconvolutionEngine {

    // MARK: - Properties

    /// FFT size used for processing
    public private(set) var fftSize: Int

    /// Regularization threshold in dB
    public var regularizationThreshold: Float

    /// FFT processor instance
    private var fftProcessor: FFTProcessor?

    // MARK: - Initialization

    public init(fftSize: Int = 262144, regularizationThreshold: Float = -60) {
        self.fftSize = fftSize
        self.regularizationThreshold = regularizationThreshold
    }

    // MARK: - Processing

    /// Extract impulse response from recording
    /// - Parameters:
    ///   - excitation: Original excitation signal (log sweep)
    ///   - recording: Recorded response
    ///   - sampleRate: Sample rate of the signals
    ///   - speaker: Speaker channel being measured
    /// - Returns: Extracted impulse response
    public func extractImpulseResponse(
        excitation: [Float],
        recording: [Float],
        sampleRate: Double,
        speaker: SpeakerChannel
    ) async throws -> ImpulseResponse {
        try await extractImpulseResponse(
            excitation: excitation,
            recording: recording,
            sampleRate: sampleRate,
            speaker: speaker,
            progress: nil
        )
    }

    /// Extract impulse response with progress callback
    public func extractImpulseResponse(
        excitation: [Float],
        recording: [Float],
        sampleRate: Double,
        speaker: SpeakerChannel,
        progress: ((Double) -> Void)?
    ) async throws -> ImpulseResponse {
        // Calculate required FFT size
        let minLength = excitation.count + recording.count - 1
        let requiredFFTSize = MathHelpers.nextPowerOf2(minLength)

        // Update FFT size if needed
        if fftProcessor == nil || fftProcessor!.fftSize < requiredFFTSize {
            fftSize = max(requiredFFTSize, fftSize)
            fftProcessor = try FFTProcessor(fftSize: fftSize)
        }

        progress?(0.1)

        // Zero-pad signals
        let paddedExcitation = MathHelpers.zeroPad(excitation, targetSize: fftSize)
        let paddedRecording = MathHelpers.zeroPad(recording, targetSize: fftSize)

        progress?(0.2)

        // Forward FFT of excitation
        let (excReal, excImag) = fftProcessor!.forwardFFT(paddedExcitation)

        progress?(0.3)

        // Forward FFT of recording
        let (recReal, recImag) = fftProcessor!.forwardFFT(paddedRecording)

        progress?(0.4)

        // Perform spectral division with regularization
        let (resultReal, resultImag) = spectralDivision(
            recordingReal: recReal,
            recordingImag: recImag,
            excitationReal: excReal,
            excitationImag: excImag
        )

        progress?(0.7)

        // Inverse FFT to get impulse response
        var impulseResponse = fftProcessor!.inverseFFT(real: resultReal, imag: resultImag)

        progress?(0.9)

        // Trim impulse response
        impulseResponse = trimImpulseResponse(impulseResponse)

        progress?(1.0)

        return ImpulseResponse(
            samples: impulseResponse,
            sampleRate: 48000, // Should be passed as parameter
            fftSize: fftSize,
            speaker: .frontLeft // Should be passed as parameter
        )
    }

    // MARK: - Spectral Division

    /// Perform regularized spectral division
    private func spectralDivision(
        recordingReal: [Float],
        recordingImag: [Float],
        excitationReal: [Float],
        excitationImag: [Float]
    ) -> (real: [Float], imag: [Float]) {
        let count = min(
            min(recordingReal.count, recordingImag.count),
            min(excitationReal.count, excitationImag.count)
        )

        var resultReal = [Float](repeating: 0, count: count)
        var resultImag = [Float](repeating: 0, count: count)

        // Calculate magnitude of excitation spectrum for threshold
        var excMagnitude = [Float](repeating: 0, count: count)
        for i in 0..<count {
            excMagnitude[i] = sqrt(excitationReal[i] * excitationReal[i] + excitationImag[i] * excitationImag[i])
        }

        // Find peak magnitude for threshold calculation
        var peakMag: Float = 0
        vDSP_maxv(excMagnitude, 1, &peakMag, vDSP_Length(count))

        // Calculate threshold from peak
        let threshold = peakMag * pow(10, regularizationThreshold / 20)
        let thresholdSquared = threshold * threshold

        // Perform division with regularization
        for i in 0..<count {
            let magX = excMagnitude[i]
            let realY = recordingReal[i]
            let imagY = recordingImag[i]
            let realX = excitationReal[i]
            let imagX = excitationImag[i]

            // Calculate denominator: |X|²
            var denominator = realX * realX + imagX * imagX

            // Apply regularization where magnitude is too low
            if denominator < thresholdSquared {
                denominator += thresholdSquared - denominator
            }

            guard denominator > 0 else { continue }

            // Complex division: Y/X = Y * conj(X) / |X|²
            // conj(X) = realX - i*imagX
            // Y * conj(X) = (realY + i*imagY)(realX - i*imagX)
            //             = realY*realX + imagY*imagX + i(imagY*realX - realY*imagX)
            resultReal[i] = (realY * realX + imagY * imagX) / denominator
            resultImag[i] = (imagY * realX - realY * imagX) / denominator
        }

        return (resultReal, resultImag)
    }

    // MARK: - Utility

    /// Trim impulse response to remove trailing silence
    private func trimImpulseResponse(_ impulse: [Float], threshold: Float = -80) -> [Float] {
        let linearThreshold = pow(10, threshold / 20)

        // Find last sample above threshold
        var lastSignificantSample = impulse.count - 1

        for i in stride(from: impulse.count - 1, through: 0, by: -1) {
            if abs(impulse[i]) > linearThreshold {
                lastSignificantSample = i
                break
            }
        }

        // Add small padding for safety
        let end = min(lastSignificantSample + 100, impulse.count)

        // Also trim leading silence (find first significant sample)
        var firstSignificantSample = 0
        for i in 0..<end {
            if abs(impulse[i]) > linearThreshold {
                firstSignificantSample = i
                break
            }
        }

        // Include a few samples before the first significant one
        let start = max(0, firstSignificantSample - 10)

        return Array(impulse[start..<end])
    }
}
