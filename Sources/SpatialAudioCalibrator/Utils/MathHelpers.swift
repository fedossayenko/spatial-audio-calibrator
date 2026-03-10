import Foundation

/// Mathematical helper functions for audio processing
public enum MathHelpers {
    /// Calculate the next power of 2 greater than or equal to n
    public static func nextPowerOf2(_ n: Int) -> Int {
        guard n > 0 else { return 1 }
        var power = 1
        while power < n {
            power *= 2
        }
        return power
    }

    /// Check if a number is a power of 2
    public static func isPowerOf2(_ n: Int) -> Bool {
        n > 0 && (n & (n - 1)) == 0
    }

    /// Convert decibels to linear amplitude
    public static func dbToLinear(_ db: Float) -> Float {
        pow(10, db / 20)
    }

    /// Convert linear amplitude to decibels
    public static func linearToDB(_ linear: Float) -> Float {
        20 * log10(max(linear, 1e-10))
    }

    /// Calculate RMS (Root Mean Square) of samples
    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }

    /// Calculate peak amplitude of samples
    public static func peak(_ samples: [Float]) -> Float {
        samples.map { abs($0) }.max() ?? 0
    }

    /// Normalize samples to peak amplitude of 1.0
    public static func normalize(_ samples: [Float]) -> [Float] {
        let peakValue = peak(samples)
        guard peakValue > 0 else { return samples }
        return samples.map { $0 / peakValue }
    }

    /// Zero-pad array to target size
    public static func zeroPad(_ input: [Float], targetSize: Int) -> [Float] {
        var output = [Float](repeating: 0, count: targetSize)
        let copyCount = min(input.count, targetSize)
        output[0..<copyCount] = input[0..<copyCount]
        return output
    }

    /// Generate a Hamming window of specified length
    public static func hammingWindow(length: Int) -> [Float] {
        guard length > 0 else { return [] }
        return (0..<length).map { i in
            Float(0.54 - 0.46 * cos(2.0 * Double.pi * Double(i) / Double(length - 1)))
        }
    }

    /// Generate a Hann window of specified length
    public static func hannWindow(length: Int) -> [Float] {
        guard length > 0 else { return [] }
        return (0..<length).map { i in
            Float(0.5 * (1.0 - cos(2.0 * Double.pi * Double(i) / Double(length - 1))))
        }
    }

    /// Linear interpolation between two values
    public static func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }

    /// Clamp a value to a range
    public static func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.min(Swift.max(value, min), max)
    }
}
