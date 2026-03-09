import Accelerate
import Foundation

/// FFT processing using vDSP for efficient spectral analysis.
///
/// This class provides forward and inverse FFT operations using
/// Apple's Accelerate framework for optimal performance on Apple Silicon.
public final class FFTProcessor {

    // MARK: - Properties

    /// FFT size (must be power of 2)
    public let fftSize: Int

    /// DFT setup for forward transform
    private var forwardSetup: OpaquePointer!

    /// DFT setup for inverse transform
    private var inverseSetup: OpaquePointer!

    // Pre-allocated buffers
    private var realInput: [Float]
    private var imagInput: [Float]
    private var realOutput: [Float]
    private var imagOutput: [Float]

    // MARK: - Initialization

    public init(fftSize: Int) throws {
        // Validate FFT size
        guard MathHelpers.isPowerOf2(fftSize) else {
            throw CalibrationError.processingFailed("FFT size must be power of 2, got \(fftSize)")
        }

        guard fftSize >= 1024 else {
            throw CalibrationError.processingFailed("FFT size must be at least 1024, got \(fftSize)")
        }

        self.fftSize = fftSize

        // Allocate buffers first
        realInput = [Float](repeating: 0, count: fftSize)
        imagInput = [Float](repeating: 0, count: fftSize)
        realOutput = [Float](repeating: 0, count: fftSize)
        imagOutput = [Float](repeating: 0, count: fftSize)

        // Create DFT setups
        guard let fwdSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .FORWARD
        ) else {
            throw CalibrationError.processingFailed("Failed to create forward DFT setup")
        }
        self.forwardSetup = fwdSetup

        guard let invSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .INVERSE
        ) else {
            vDSP_DFT_DestroySetup(forwardSetup)
            throw CalibrationError.processingFailed("Failed to create inverse DFT setup")
        }
        self.inverseSetup = invSetup
    }

    deinit {
        vDSP_DFT_DestroySetup(forwardSetup)
        vDSP_DFT_DestroySetup(inverseSetup)
    }

    // MARK: - Forward FFT

    /// Perform forward FFT on real input signal
    /// - Parameter input: Real-valued input samples
    /// - Returns: Complex spectrum as split-complex arrays (real, imaginary)
    public func forwardFFT(_ input: [Float]) -> (real: [Float], imag: [Float]) {
        let count = min(input.count, fftSize)

        // Clear and copy buffers
        vDSP_vclr(&realInput, 1, vDSP_Length(fftSize))
        vDSP_vclr(&imagInput, 1, vDSP_Length(fftSize))

        // Copy input to real part
        for i in 0..<count {
            realInput[i] = input[i]
        }

        // Execute forward DFT
        vDSP_DFT_Execute(
            forwardSetup,
            &realInput,
            &imagInput,
            &realOutput,
            &imagOutput
        )

        // Scale by 1/N for proper normalization
        var scale = Float(1.0 / Double(fftSize))
        withUnsafeMutablePointer(to: &scale) { scalePtr in
            vDSP_vsmul(realOutput, 1, scalePtr, &realOutput, 1, vDSP_Length(fftSize))
            vDSP_vsmul(imagOutput, 1, scalePtr, &imagOutput, 1, vDSP_Length(fftSize))
        }

        return (realOutput, imagOutput)
    }

    // MARK: - Inverse FFT

    /// Perform inverse FFT on complex spectrum
    /// - Parameters:
    ///   - real: Real part of spectrum
    ///   - imag: Imaginary part of spectrum
    /// - Returns: Real-valued time domain signal
    public func inverseFFT(real: [Float], imag: [Float]) -> [Float] {
        // Clear and copy buffers
        vDSP_vclr(&realOutput, 1, vDSP_Length(fftSize))
        vDSP_vclr(&imagOutput, 1, vDSP_Length(fftSize))

        for i in 0..<min(real.count, fftSize) {
            realOutput[i] = real[i]
        }
        for i in 0..<min(imag.count, fftSize) {
            imagOutput[i] = imag[i]
        }

        // Execute inverse DFT
        vDSP_DFT_Execute(
            inverseSetup,
            &realOutput,
            &imagOutput,
            &realInput,
            &imagInput
        )

        // Return real part of result
        return realInput
    }

    // MARK: - Utility

    /// Calculate magnitude spectrum from complex spectrum
    public func magnitude(real: [Float], imag: [Float]) -> [Float] {
        let count = min(real.count, imag.count)
        var magnitude = [Float](repeating: 0, count: count)
        var realCopy = real
        var imagCopy = imag

        realCopy.withUnsafeMutableBufferPointer { realPtr in
            imagCopy.withUnsafeMutableBufferPointer { imagPtr in
                magnitude.withUnsafeMutableBufferPointer { magPtr in
                    guard let realBase = realPtr.baseAddress,
                          let imagBase = imagPtr.baseAddress,
                          let magBase = magPtr.baseAddress else { return }

                    var splitComplex = DSPSplitComplex(
                        realp: realBase,
                        imagp: imagBase
                    )

                    vDSP_zvabs(&splitComplex, 1, magBase, 1, vDSP_Length(count))
                }
            }
        }

        return magnitude
    }

    /// Calculate phase spectrum from complex spectrum
    public func phase(real: [Float], imag: [Float]) -> [Float] {
        let count = min(real.count, imag.count)
        var phase = [Float](repeating: 0, count: count)
        var realCopy = real
        var imagCopy = imag

        realCopy.withUnsafeMutableBufferPointer { realPtr in
            imagCopy.withUnsafeMutableBufferPointer { imagPtr in
                phase.withUnsafeMutableBufferPointer { phasePtr in
                    guard let realBase = realPtr.baseAddress,
                          let imagBase = imagPtr.baseAddress,
                          let phaseBase = phasePtr.baseAddress else { return }

                    var splitComplex = DSPSplitComplex(
                        realp: realBase,
                        imagp: imagBase
                    )

                    vDSP_zvphas(&splitComplex, 1, phaseBase, 1, vDSP_Length(count))
                }
            }
        }

        return phase
    }
}
