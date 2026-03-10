import Foundation

/// A single point in a frequency response curve.
public struct FrequencyResponsePoint: Codable, Equatable {
    // MARK: Lifecycle

    public init(frequency: Double, magnitude: Double, phase: Double) {
        self.frequency = frequency
        self.magnitude = magnitude
        self.phase = phase
    }

    // MARK: Public

    /// Frequency in Hz
    public let frequency: Double
    /// Magnitude in dB
    public let magnitude: Double
    /// Phase in radians
    public let phase: Double
}

/// Represents a measured Room Impulse Response (RIR).
///
/// The impulse response captures the acoustic characteristics of a speaker
/// in the room, including direct sound, early reflections, and reverberation.
public struct ImpulseResponse: Codable, Identifiable {
    // MARK: Lifecycle

    // MARK: - Initialization

    public init(
        samples: [Float],
        sampleRate: Double,
        fftSize: Int,
        measurementDate: Date = Date(),
        speaker: SpeakerChannel,
        notes: String? = nil
    ) {
        id = UUID()
        self.samples = samples
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.measurementDate = measurementDate
        self.speaker = speaker
        self.notes = notes
    }

    // MARK: Public

    public let id: UUID

    /// Raw audio samples of the impulse response
    public let samples: [Float]

    /// Sample rate of the recording (Hz)
    public let sampleRate: Double

    /// FFT size used for deconvolution
    public let fftSize: Int

    /// Date and time of measurement
    public let measurementDate: Date

    /// Speaker that was measured
    public let speaker: SpeakerChannel

    /// Optional measurement notes
    public var notes: String?

    /// Duration of the impulse response in seconds
    public var duration: Double {
        Double(samples.count) / sampleRate
    }

    /// Number of samples in the impulse response
    public var sampleCount: Int {
        samples.count
    }

    // MARK: - Analysis

    /// Calculate acoustic parameters from this impulse response
    public func analyze() -> AcousticParameters {
        AcousticParameters.analyze(from: self)
    }

    /// Get frequency response at specified frequencies
    /// - Parameter frequencies: Array of frequencies to analyze (Hz)
    /// - Returns: Array of FrequencyResponsePoint containing frequency, magnitude (dB), and phase (radians)
    public func frequencyResponse(
        frequencies: [Double]
    )
        -> [FrequencyResponsePoint]
    {
        // Need enough samples for FFT
        guard !samples.isEmpty else {
            return frequencies.map { FrequencyResponsePoint(frequency: $0, magnitude: -100, phase: 0) }
        }

        // Calculate FFT size (power of 2, at least as large as samples)
        let fftSize = MathHelpers.nextPowerOf2(max(samples.count, 1024))

        // Create FFT processor
        guard let fftProcessor = try? FFTProcessor(fftSize: fftSize) else {
            return frequencies.map { FrequencyResponsePoint(frequency: $0, magnitude: -100, phase: 0) }
        }

        // Zero-pad samples to FFT size
        let paddedSamples = MathHelpers.zeroPad(samples, targetSize: fftSize)

        // Compute FFT
        let (real, imag) = fftProcessor.forwardFFT(paddedSamples)

        // Get magnitude and phase
        let magnitudes = fftProcessor.magnitude(real: real, imag: imag)
        let phases = fftProcessor.phase(real: real, imag: imag)

        // Calculate bin width
        let binWidth = sampleRate / Double(fftSize)
        let nyquist = sampleRate / 2

        // Interpolate to requested frequencies
        return frequencies.map { freq in
            // Clamp to valid range
            guard freq > 0, freq < nyquist else {
                return FrequencyResponsePoint(frequency: freq, magnitude: -100, phase: 0)
            }

            // Find nearest bin
            let bin = Int(freq / binWidth)
            guard bin < magnitudes.count else {
                return FrequencyResponsePoint(frequency: freq, magnitude: -100, phase: 0)
            }

            // Convert magnitude to dB
            let magDB = 20 * log10(max(Double(magnitudes[bin]), 1e-10))

            return FrequencyResponsePoint(frequency: freq, magnitude: magDB, phase: Double(phases[bin]))
        }
    }

    /// Calculate energy decay curve (Schroeder backward integration)
    public func energyDecayCurve() -> [Double] {
        let energy = samples.map { Double($0 * $0) }
        var integrated = [Double](repeating: 0, count: energy.count)

        var sum = 0.0
        for i in stride(from: energy.count - 1, through: 0, by: -1) {
            sum += energy[i]
            integrated[i] = sum
        }

        // Normalize to dB
        let maxEnergy = integrated.first ?? 1.0
        return integrated.map { 10 * log10(max($0 / maxEnergy, 1e-10)) }
    }

    // MARK: - Processing

    /// Return a trimmed version of the impulse response
    public func trimmed(thresholdDB: Float = -80) -> ImpulseResponse {
        let linearThreshold = pow(10, thresholdDB / 20)

        // Find last sample above threshold
        var lastSignificantSample = samples.count - 1
        for i in stride(from: samples.count - 1, through: 0, by: -1) {
            if abs(samples[i]) > linearThreshold {
                lastSignificantSample = i
                break
            }
        }

        // Add small padding for safety
        let end = min(lastSignificantSample + 100, samples.count)
        let trimmedSamples = Array(samples[0 ..< end])

        return ImpulseResponse(
            samples: trimmedSamples,
            sampleRate: sampleRate,
            fftSize: fftSize,
            measurementDate: measurementDate,
            speaker: speaker,
            notes: notes
        )
    }

    /// Normalize to peak amplitude of 1.0
    public func normalized() -> ImpulseResponse {
        let peak = samples.map { abs($0) }.max() ?? 1.0
        guard peak > 0 else { return self }

        let normalizedSamples = samples.map { $0 / peak }

        return ImpulseResponse(
            samples: normalizedSamples,
            sampleRate: sampleRate,
            fftSize: fftSize,
            measurementDate: measurementDate,
            speaker: speaker,
            notes: notes
        )
    }

    // MARK: - Export

    /// Export as WAV file
    public func exportWAV(to url: URL) throws {
        try WAVEExporter.export(samples: samples, sampleRate: sampleRate, to: url)
    }
}

/// Result of a single speaker measurement
public struct SpeakerMeasurement: Codable, Identifiable {
    // MARK: Lifecycle

    public init(
        speaker: SpeakerChannel,
        impulseResponse: ImpulseResponse,
        recordingDuration: Double,
        snr: Double
    ) {
        id = UUID()
        self.speaker = speaker
        self.impulseResponse = impulseResponse
        analysis = impulseResponse.analyze()
        self.recordingDuration = recordingDuration
        self.snr = snr

        // Validate measurement
        var errors: [String] = []

        if analysis.peakAmplitude > 0.95 {
            errors.append("Clipping detected")
        }

        if snr < 40 {
            errors.append("Low SNR: \(String(format: "%.1f", snr)) dB")
        }

        if analysis.rt60 < 0.1 || analysis.rt60 > 5.0 {
            errors.append("Abnormal RT60: \(String(format: "%.2f", analysis.rt60))s")
        }

        isValid = errors.isEmpty
        validationErrors = errors
    }

    // MARK: Public

    public let id: UUID
    public let speaker: SpeakerChannel
    public let impulseResponse: ImpulseResponse
    public let analysis: AcousticParameters
    public let recordingDuration: Double
    public let snr: Double
    public let isValid: Bool
    public let validationErrors: [String]
}
