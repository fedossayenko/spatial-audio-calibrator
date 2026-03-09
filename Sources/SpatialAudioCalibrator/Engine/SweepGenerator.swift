import AVFAudio
import Foundation

/// Generates logarithmic sine sweeps for acoustic measurement.
///
/// The sweep traverses from `startFrequency` to `endFrequency` exponentially,
/// spending equal time in each octave. This property ensures balanced energy
/// distribution and enables harmonic distortion separation during deconvolution.
///
/// - Note: This class must be used in a real-time safe context.
///         Do not allocate memory or acquire locks in `render()`.
public final class SweepGenerator {

    // MARK: - Parameters

    /// Lower frequency bound (Hz)
    public let startFrequency: Double

    /// Upper frequency bound (Hz)
    public let endFrequency: Double

    /// Total sweep duration (seconds)
    public let duration: Double

    /// Output sample rate (Hz)
    public let sampleRate: Double

    /// Output amplitude (0-1)
    public let amplitude: Float

    // MARK: - Pre-calculated Constants

    /// Ratio of end to start frequency
    private let frequencyRatio: Double

    /// Pre-computed phase constant for efficiency
    private let phaseConstant: Double

    // MARK: - State (must be accessed atomically in render block)

    /// Current time position in seconds
    private var currentTime: Double = 0

    /// Whether sweep is currently playing
    private var isRunning: Bool = false

    /// Lock for thread-safe state access
    private let stateLock = NSLock()

    // MARK: - Initialization

    public init(
        startFrequency: Double = 20,
        endFrequency: Double = 20000,
        duration: Double = 5.0,
        sampleRate: Double = 48000,
        amplitude: Float = 0.8
    ) {
        self.startFrequency = startFrequency
        self.endFrequency = endFrequency
        self.duration = duration
        self.sampleRate = sampleRate
        self.amplitude = amplitude

        // Pre-calculate constants for real-time efficiency
        self.frequencyRatio = endFrequency / startFrequency
        self.phaseConstant = (2 * Double.pi * startFrequency * duration) / log(frequencyRatio)
    }

    // MARK: - Control

    /// Start sweep generation from beginning
    public func start() {
        stateLock.lock()
        defer { stateLock.unlock() }

        currentTime = 0
        isRunning = true
    }

    /// Stop sweep generation
    public func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }

        isRunning = false
    }

    /// Reset to beginning without stopping
    public func reset() {
        stateLock.lock()
        defer { stateLock.unlock() }

        currentTime = 0
    }

    // MARK: - State Queries

    /// Whether sweep is currently running
    public var running: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning
    }

    /// Current progress (0.0 - 1.0)
    public var currentProgress: Double {
        stateLock.lock()
        defer { stateLock.unlock() }
        return min(currentTime / duration, 1.0)
    }

    /// Current instantaneous frequency (Hz)
    public var currentFrequency: Double {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard currentTime < duration else { return endFrequency }

        let normalizedTime = currentTime / duration
        return startFrequency * pow(frequencyRatio, normalizedTime)
    }

    // MARK: - Render

    /// Real-time render callback for AVAudioSourceNode.
    ///
    /// - Important: This method MUST be allocation-free for real-time safety.
    ///              Do not allocate memory, acquire locks, or call Objective-C.
    ///
    /// - Parameters:
    ///   - frameCount: Number of frames to render
    ///   - outputBufferList: Output buffer list to fill
    /// - Returns: OSStatus indicating success or failure
    public func render(
        frameCount: AVAudioFrameCount,
        outputBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        // Quick check without lock
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

        // Get current time atomically
        var localTime = currentTime
        let localDuration = duration
        let localRatio = frequencyRatio
        let localPhaseConstant = phaseConstant
        let localAmplitude = amplitude
        let invSampleRate = 1.0 / sampleRate

        // Generate samples
        var finishedFrame: Int? = nil

        for frame in 0..<Int(frameCount) {
            let t = localTime + Double(frame) * invSampleRate

            // Check if we've exceeded duration
            if t >= localDuration {
                finishedFrame = frame
                break
            }

            // Calculate instantaneous phase
            let normalizedTime = t / localDuration
            let phase = localPhaseConstant * (exp(normalizedTime * log(localRatio)) - 1)

            // Generate sample
            let sample = localAmplitude * Float(sin(phase))

            // Write to all channels
            for ch in 0..<channelCount {
                let data = bufferList[ch].mData?.assumingMemoryBound(to: Float.self)
                data?[frame] = sample
            }
        }

        // Handle sweep completion
        if let finishFrame = finishedFrame {
            // Fill remaining frames with silence
            for ch in 0..<channelCount {
                let data = bufferList[ch].mData?.assumingMemoryBound(to: Float.self)
                for f in finishFrame..<Int(frameCount) {
                    data?[f] = 0
                }
            }
            isRunning = false
        }

        // Update time for next buffer
        currentTime = min(localTime + Double(frameCount) * invSampleRate, duration)

        return noErr
    }

    // MARK: - Pre-generation

    /// Pre-generate the entire sweep as a buffer.
    ///
    /// Use this for testing or when real-time generation isn't needed.
    public func generateBuffer() -> [Float] {
        let sampleCount = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: sampleCount)

        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            let normalizedTime = t / duration
            let phase = phaseConstant * (exp(normalizedTime * log(frequencyRatio)) - 1)
            samples[i] = amplitude * Float(sin(phase))
        }

        return samples
    }
}
