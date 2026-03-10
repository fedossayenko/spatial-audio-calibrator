import Foundation

/// Configuration parameters for acoustic measurement.
///
/// This struct defines all adjustable parameters for the calibration process,
/// including sweep generation, recording, and DSP processing settings.
public struct CalibrationConfig: Codable, Sendable {
    // MARK: Lifecycle

    public init(
        startFrequency: Double = 20,
        endFrequency: Double = 20000,
        sweepDuration: Double = 5.0,
        sampleRate: Double = 48000,
        outputAmplitude: Float = 0.8,
        preSweepSilence: Double = 0.5,
        postSweepSilence: Double = 2.0,
        fftSize: Int = 262_144,
        regularizationDB: Float = -60,
        microphoneCalibrationFile: URL? = nil
    ) {
        self.startFrequency = startFrequency
        self.endFrequency = endFrequency
        self.sweepDuration = sweepDuration
        self.sampleRate = sampleRate
        self.outputAmplitude = outputAmplitude
        self.preSweepSilence = preSweepSilence
        self.postSweepSilence = postSweepSilence
        self.fftSize = fftSize
        self.regularizationDB = regularizationDB
        self.microphoneCalibrationFile = microphoneCalibrationFile
    }

    // MARK: Public

    // MARK: - Initialization

    /// Default configuration suitable for most measurements
    public static let `default` = CalibrationConfig(
        startFrequency: 20,
        endFrequency: 20000,
        sweepDuration: 5.0,
        sampleRate: 48000,
        outputAmplitude: 0.8,
        preSweepSilence: 0.5,
        postSweepSilence: 2.0,
        fftSize: 262_144, // 2^18 for ~5.5s at 48kHz
        regularizationDB: -60
    )

    /// Configuration optimized for quick testing
    public static let quickTest = CalibrationConfig(
        startFrequency: 100,
        endFrequency: 10000,
        sweepDuration: 2.0,
        sampleRate: 48000,
        outputAmplitude: 0.5,
        preSweepSilence: 0.2,
        postSweepSilence: 1.0,
        fftSize: 131_072, // 2^17
        regularizationDB: -50
    )

    // MARK: - Sweep Parameters

    /// Lower frequency bound for the logarithmic sweep (Hz)
    public var startFrequency: Double

    /// Upper frequency bound for the logarithmic sweep (Hz)
    public var endFrequency: Double

    /// Total sweep duration in seconds
    public var sweepDuration: Double

    /// Output sample rate (Hz)
    public var sampleRate: Double

    /// Output amplitude normalized to 0-1 range
    public var outputAmplitude: Float

    // MARK: - Recording Parameters

    /// Silence before sweep begins (seconds)
    public var preSweepSilence: Double

    /// Silence after sweep ends for reverb tail capture (seconds)
    public var postSweepSilence: Double

    // MARK: - Processing Parameters

    /// FFT size (must be power of 2)
    public var fftSize: Int

    /// Regularization threshold for spectral division (dB)
    public var regularizationDB: Float

    // MARK: - Microphone Calibration

    /// Optional microphone calibration file for accurate measurements
    public var microphoneCalibrationFile: URL?

    /// Total recording duration including pre/post silence
    public var totalRecordingDuration: Double {
        preSweepSilence + sweepDuration + postSweepSilence
    }

    /// Total number of samples in the recording
    public var totalRecordingSamples: Int {
        Int(totalRecordingDuration * sampleRate)
    }

    /// Number of samples in the sweep
    public var sweepSampleCount: Int {
        Int(sweepDuration * sampleRate)
    }

    // MARK: - Validation

    /// Validates configuration and returns any issues found
    public func validate() -> [ConfigValidationError] {
        var errors: [ConfigValidationError] = []

        if startFrequency <= 0 {
            errors.append(.invalidStartFrequency(startFrequency))
        }

        if endFrequency <= startFrequency {
            errors.append(.invalidFrequencyRange(start: startFrequency, end: endFrequency))
        }

        if endFrequency > sampleRate / 2 {
            errors.append(.endFrequencyExceedsNyquist(endFrequency, sampleRate / 2))
        }

        if sweepDuration <= 0 {
            errors.append(.invalidSweepDuration(sweepDuration))
        }

        if outputAmplitude <= 0 || outputAmplitude > 1 {
            errors.append(.invalidAmplitude(outputAmplitude))
        }

        if !isPowerOfTwo(fftSize) {
            errors.append(.fftSizeNotPowerOfTwo(fftSize))
        }

        if fftSize < 1024 {
            errors.append(.fftSizeTooSmall(fftSize))
        }

        return errors
    }

    // MARK: Private

    private func isPowerOfTwo(_ n: Int) -> Bool {
        MathHelpers.isPowerOf2(n)
    }
}

/// Configuration validation errors
public enum ConfigValidationError: Error, LocalizedError {
    case invalidStartFrequency(Double)
    case invalidFrequencyRange(start: Double, end: Double)
    case endFrequencyExceedsNyquist(Double, Double)
    case invalidSweepDuration(Double)
    case invalidAmplitude(Float)
    case fftSizeNotPowerOfTwo(Int)
    case fftSizeTooSmall(Int)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case let .invalidStartFrequency(freq):
            "Start frequency must be positive (got \(freq) Hz)"
        case let .invalidFrequencyRange(start, end):
            "End frequency (\(end) Hz) must be greater than start frequency (\(start) Hz)"
        case let .endFrequencyExceedsNyquist(freq, nyquist):
            "End frequency (\(freq) Hz) exceeds Nyquist frequency (\(nyquist) Hz)"
        case let .invalidSweepDuration(duration):
            "Sweep duration must be positive (got \(duration) seconds)"
        case let .invalidAmplitude(amp):
            "Amplitude must be in range (0, 1] (got \(amp))"
        case let .fftSizeNotPowerOfTwo(size):
            "FFT size must be a power of 2 (got \(size))"
        case let .fftSizeTooSmall(size):
            "FFT size must be at least 1024 (got \(size))"
        }
    }
}
