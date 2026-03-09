import Foundation
import Accelerate

/// Acoustic measurements derived from an impulse response.
///
/// These parameters characterize the room acoustics captured in the
/// impulse response measurement.
public struct AcousticParameters: Codable {
    // MARK: - Time Domain

    /// Peak amplitude of the impulse response (0-1 normalized)
    public let peakAmplitude: Float

    /// Sample index of the peak amplitude
    public let peakSample: Int

    /// Time of peak amplitude in milliseconds
    public let peakTime: Double

    // MARK: - Reverberation

    /// Reverberation time for 60 dB decay (seconds)
    public let rt60: Double

    /// Early Decay Time (seconds) - time for first 10 dB decay extrapolated to 60 dB
    public let edt: Double

    /// Initial Time Delay Gap (milliseconds) - time between direct sound and first reflection
    public let itdg: Double

    // MARK: - Clarity and Definition

    /// Clarity C80 (dB) - ratio of early to late energy (0-80ms vs 80ms-end)
    public let c80: Double

    /// Clarity C50 (dB) - ratio of early to late energy (0-50ms vs 50ms-end)
    public let c50: Double

    /// Definition D50 (ratio 0-1) - early energy / total energy (0-50ms)
    public let d50: Double

    /// Definition D80 (ratio 0-1) - early energy / total energy (0-80ms)
    public let d80: Double

    // MARK: - Frequency Range

    /// Effective low frequency limit (Hz) - frequency where response drops -3dB
    public let effectiveLowFrequency: Double

    /// Effective high frequency limit (Hz) - frequency where response drops -3dB
    public let effectiveHighFrequency: Double

    // MARK: - Quality Metrics

    /// Signal-to-noise ratio (dB)
    public let signalToNoiseRatio: Double

    /// Dynamic range (dB) - difference between peak and noise floor
    public let dynamicRange: Double

    // MARK: - Analysis

    /// Analyze an impulse response to extract acoustic parameters
    public static func analyze(from ir: ImpulseResponse) -> AcousticParameters {
        let samples = ir.samples
        let sampleRate = ir.sampleRate
        let samplePeriod = 1.0 / sampleRate

        // Find peak
        var peakAmplitude: Float = 0
        var peakSample = 0

        for (i, sample) in samples.enumerated() {
            if abs(sample) > peakAmplitude {
                peakAmplitude = abs(sample)
                peakSample = i
            }
        }

        let peakTime = Double(peakSample) * samplePeriod * 1000 // ms

        // Calculate squared energy
        let energy = samples.map { Double($0 * $0) }
        let totalEnergy = energy.reduce(0, +)

        // Energy Decay Curve (Schroeder backward integration)
        var integratedEnergy = [Double](repeating: 0, count: energy.count)
        var sum = 0.0
        for i in stride(from: energy.count - 1, through: 0, by: -1) {
            sum += energy[i]
            integratedEnergy[i] = sum
        }

        let maxEnergy = integratedEnergy.first ?? 1.0
        let normalizedEnergy = integratedEnergy.map { 10 * log10(max($0 / maxEnergy, 1e-10)) }

        // RT60 - find time for 60 dB decay
        let decay60Sample = normalizedEnergy.firstIndex { $0 < -60 } ?? energy.count
        let rt60 = Double(decay60Sample) * samplePeriod

        // EDT - Early Decay Time (extrapolate from -10 dB point)
        let decay10Sample = normalizedEnergy.firstIndex { $0 < -10 } ?? min(energy.count / 10, energy.count - 1)
        let edt = Double(decay10Sample) * samplePeriod * 6 // Extrapolate 10 dB to 60 dB

        // ITDG - Initial Time Delay Gap
        let peakEnergy = energy[peakSample]
        var itdg = 0.0
        for i in (peakSample + 1)..<min(peakSample + Int(0.1 * sampleRate), energy.count) {
            // Look for first significant reflection (> 10% of direct sound)
            if energy[i] > peakEnergy * 0.01 {
                itdg = Double(i - peakSample) * samplePeriod * 1000 // ms
                break
            }
        }

        // C80 Clarity - early (0-80ms) vs late (80ms-end) energy
        let t80Sample = Int(0.08 * sampleRate)
        let early80Energy = energy[0..<min(t80Sample, energy.count)].reduce(0, +)
        let late80Energy = energy[min(t80Sample, energy.count)..<energy.count].reduce(0, +)
        let c80 = late80Energy > 0 ? 10 * log10(max(early80Energy / late80Energy, 1e-10)) : 0

        // C50 Clarity - early (0-50ms) vs late (50ms-end) energy
        let t50Sample = Int(0.05 * sampleRate)
        let early50Energy = energy[0..<min(t50Sample, energy.count)].reduce(0, +)
        let late50Energy = energy[min(t50Sample, energy.count)..<energy.count].reduce(0, +)
        let c50 = late50Energy > 0 ? 10 * log10(max(early50Energy / late50Energy, 1e-10)) : 0

        // D50 Definition - early energy / total energy
        let d50 = totalEnergy > 0 ? early50Energy / totalEnergy : 0

        // D80 Definition - early energy / total energy (0-80ms)
        let d80 = totalEnergy > 0 ? early80Energy / totalEnergy : 0

        // Noise floor estimation (last 10% of samples)
        let noiseStart = Int(Double(samples.count) * 0.9)
        let noiseSamples = Array(samples[noiseStart..<samples.count])
        let noiseRMS = sqrt(noiseSamples.reduce(0) { $0 + Double($1 * $1) } / Double(noiseSamples.count))

        // SNR
        let peakRMS = Double(peakAmplitude)
        let signalToNoiseRatio = 20 * log10(max(peakRMS / max(noiseRMS, 1e-10), 1e-10))

        // Dynamic range
        let noiseFloorDB = 20 * log10(max(noiseRMS, 1e-10))
        let peakDB = 20 * log10(max(peakRMS, 1e-10))
        let dynamicRange = peakDB - noiseFloorDB

        // Effective frequency range (simplified estimation)
        // In practice, this requires FFT analysis
        let effectiveLowFrequency = 20.0 // Placeholder
        let effectiveHighFrequency = 20000.0 // Placeholder

        return AcousticParameters(
            peakAmplitude: peakAmplitude,
            peakSample: peakSample,
            peakTime: peakTime,
            rt60: rt60,
            edt: edt,
            itdg: itdg,
            c80: c80,
            c50: c50,
            d50: d50,
            d80: d80,
            effectiveLowFrequency: effectiveLowFrequency,
            effectiveHighFrequency: effectiveHighFrequency,
            signalToNoiseRatio: signalToNoiseRatio,
            dynamicRange: dynamicRange
        )
    }
}
