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

        // Allocate buffers
        realInput = [Float](repeating: 0, count: fftSize)
        imagInput = [Float](repeating: 0, count: fftSize)
        realOutput = [Float](repeating: 0, count: fftSize)
        imagOutput = [Float](repeating: 0, count: fftSize)
    }

    // MARK: - Forward FFT

    /// Perform forward FFT on real input signal
    /// - Parameter input: Real-valued input samples
    /// - Returns: Complex spectrum as split-complex arrays (real, imaginary)
    public func forwardFFT(_ input: [Float]) -> (real: [Float], imag: [Float]) {
        let count = min(input.count, fftSize)

        // Clear and copy buffers
        realInput.withUnsafeMutableBufferPointer { realPtr in
            imagInput.withUnsafeMutableBufferPointer { imagPtr in
                vDSP_vclr(realPtr.baseAddress!, 1, vDSP_Length(fftSize))
                vDSP_vclr(imagPtr.baseAddress!, 1, vDSP_Length(fftSize))

                // Copy input to real part
                for i in 0..<count {
                    realPtr.baseAddress![i] = input[i]
                }
            }
        }

        // Execute forward FFT using vDSP_DFT_Execute with temporary setup
        // Using DFT which doesn't require setup management
        realOutput.withUnsafeMutableBufferPointer { realOutPtr in
            imagOutput.withUnsafeMutableBufferPointer { imagOutPtr in
                realInput.withUnsafeMutableBufferPointer { realInPtr in
                    imagInput.withUnsafeMutableBufferPointer { imagInPtr in
                        vDSP_DFT_Execute(
                            nil,
                            realInPtr.baseAddress!,
                            imagInPtr.baseAddress!,
                            realOutPtr.baseAddress!,
                            imagOutPtr.baseAddress!,
                            vDSP_Length(fftSize),
                            vDSP_DFT_Forward
                        )

                        // Scale by 1/N for proper normalization
                        var scale = Float(1.0 / Double(fftSize))
                        vDSP_vsmul(realOutPtr.baseAddress!, 1, &scale, realOutPtr.baseAddress!, 1, vDSP_Length(fftSize))
                        vDSP_vsmul(imagOutPtr.baseAddress!, 1, &scale, imagOutPtr.baseAddress!, 1, vDSP_Length(fftSize))
                    }
                }
            }
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
        realOutput.withUnsafeMutableBufferPointer { realOutPtr in
            imagOutput.withUnsafeMutableBufferPointer { imagOutPtr in
                vDSP_vclr(realOutPtr.baseAddress!, 1, vDSP_Length(fftSize))
                vDSP_vclr(imagOutPtr.baseAddress!, 1, vDSP_Length(fftSize))

                for i in 0..<min(real.count, fftSize) {
                    realOutPtr.baseAddress![i] = real[i]
                }
                for i in 0..<min(imag.count, fftSize) {
                    imagOutPtr.baseAddress![i] = imag[i]
                }
            }
        }

        // Execute inverse DFT
        realInput.withUnsafeMutableBufferPointer { realInPtr in
            imagInput.withUnsafeMutableBufferPointer { imagInPtr in
                realOutput.withUnsafeMutableBufferPointer { realOutPtr in
                    imagOutput.withUnsafeMutableBufferPointer { imagOutPtr in
                        vDSP_DFT_Execute(
                            nil,
                            realOutPtr.baseAddress!,
                            imagOutPtr.baseAddress!,
                            realInPtr.baseAddress!,
                            imagInPtr.baseAddress!,
                            vDSP_Length(fftSize),
                            vDSP_DFT_Inverse
                        )
                    }
                }
            }
        }

        // Scale for vDSP IFFT
        var scale = Float(2.0)
        var output = [Float](repeating: 0, count: fftSize)
        vDSP_vsmul(&realInput, 1, &scale, &output, 1, vDSP_Length(fftSize))

        return output
    }

    // MARK: - Utility

    /// Calculate magnitude spectrum from complex spectrum
    public func magnitude(real: [Float], imag: [Float]) -> [Float] {
        let count = min(real.count, imag.count)
        var magnitude = [Float](repeating: 0, count: count)

        real.withUnsafeBufferPointer { realPtr in
            imag.withUnsafeBufferPointer { imagPtr in
                magnitude.withUnsafeMutableBufferPointer { magPtr in
                    guard let realBase = realPtr.baseAddress,
                          let imagBase = imagPtr.baseAddress,
                          let magBase = magPtr.baseAddress else { return }

                    var splitComplex = DSPSplitComplex(
                        realp: UnsafeMutablePointer(mutating: realBase),
                        imagp: UnsafeMutablePointer(mutating: imagBase)
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

        real.withUnsafeBufferPointer { realPtr in
            imag.withUnsafeBufferPointer { imagPtr in
                phase.withUnsafeMutableBufferPointer { phasePtr in
                    guard let realBase = realPtr.baseAddress,
                          let imagBase = imagPtr.baseAddress,
                          let phaseBase = phasePtr.baseAddress else { return }

                    var splitComplex = DSPSplitComplex(
                        realp: UnsafeMutablePointer(mutating: realBase),
                        imagp: UnsafeMutablePointer(mutating: imagBase)
                    )

                    vDSP_zvphas(&splitComplex, 1, phaseBase, 1, vDSP_Length(count))
                }
            }
        }

        return phase
    }
}
