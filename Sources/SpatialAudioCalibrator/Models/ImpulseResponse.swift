import Foundation

/// Represents a measured Room Impulse Response (RIR).
///
/// The impulse response captures the acoustic characteristics of a speaker
/// in the room, including direct sound, early reflections, and reverberation.
public struct ImpulseResponse: Codable, Identifiable {
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

    // MARK: - Computed Properties

    /// Duration of the impulse response in seconds
    public var duration: Double {
        Double(samples.count) / sampleRate
    }

    /// Number of samples in the impulse response
    public var sampleCount: Int {
        samples.count
    }

    // MARK: - Initialization

    public init(
        samples: [Float],
        sampleRate: Double,
        fftSize: Int,
        measurementDate: Date = Date(),
        speaker: SpeakerChannel,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.samples = samples
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.measurementDate = measurementDate
        self.speaker = speaker
        self.notes = notes
    }

    // MARK: - Analysis

    /// Calculate acoustic parameters from this impulse response
    public func analyze() -> AcousticParameters {
        AcousticParameters.analyze(from: self)
    }

    /// Get frequency response at specified frequencies
    public func frequencyResponse(
        frequencies: [Double]
    ) -> [(frequency: Double, magnitude: Double, phase: Double)] {
        // This will be implemented with FFTProcessor
        fatalError("Not implemented yet - requires FFTProcessor")
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
        let trimmedSamples = Array(samples[0..<end])

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
    public let id: UUID
    public let speaker: SpeakerChannel
    public let impulseResponse: ImpulseResponse
    public let analysis: AcousticParameters
    public let recordingDuration: Double
    public let snr: Double
    public let isValid: Bool
    public let validationErrors: [String]

    public init(
        speaker: SpeakerChannel,
        impulseResponse: ImpulseResponse,
        recordingDuration: Double,
        snr: Double
    ) {
        self.id = UUID()
        self.speaker = speaker
        self.impulseResponse = impulseResponse
        self.analysis = impulseResponse.analyze()
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

        self.isValid = errors.isEmpty
        self.validationErrors = errors
    }
}
