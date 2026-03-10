import Foundation
import XCTest
@testable import SpatialAudioCalibrator

// MARK: - FFTProcessor Tests

final class FFTProcessorTests: XCTestCase {

    // MARK: - Initialization Tests

    func testFFTInitializationWithValidSize() throws {
        // Valid power-of-2 sizes
        for size in [1024, 2048, 4096, 8192, 65536] {
            let processor = try FFTProcessor(fftSize: size)
            XCTAssertEqual(processor.fftSize, size, "FFT size should be \(size)")
        }
    }

    func testFFTInitializationRejectsNonPowerOf2() {
        XCTAssertThrowsError(try FFTProcessor(fftSize: 1000)) { error in
            XCTAssertTrue(error is CalibrationError)
        }
        XCTAssertThrowsError(try FFTProcessor(fftSize: 3000)) { error in
            XCTAssertTrue(error is CalibrationError)
        }
    }

    func testFFTInitializationRejectsTooSmall() {
        XCTAssertThrowsError(try FFTProcessor(fftSize: 512)) { error in
            XCTAssertTrue(error is CalibrationError)
        }
        XCTAssertThrowsError(try FFTProcessor(fftSize: 256)) { error in
            XCTAssertTrue(error is CalibrationError)
        }
    }

    // MARK: - Forward FFT Tests

    func testForwardFFTProducesDCAtBin0() throws {
        let fftSize = 4096
        let processor = try FFTProcessor(fftSize: fftSize)

        // DC signal (constant value)
        let dcSignal = [Float](repeating: 1.0, count: fftSize)
        let (real, imag) = processor.forwardFFT(dcSignal)

        // DC component should be at bin 0
        let dcMagnitude = sqrt(real[0] * real[0] + imag[0] * imag[0])
        XCTAssertGreaterThan(dcMagnitude, 0.9, "DC magnitude should be close to 1.0")

        // Other bins should be near zero
        let acMagnitude = sqrt(real[1] * real[1] + imag[1] * imag[1])
        XCTAssertLessThan(acMagnitude, 0.01, "AC components should be near zero")
    }

    func testForwardFFTOfSineWave() throws {
        let fftSize = 4096
        let sampleRate = 48000.0
        let processor = try FFTProcessor(fftSize: fftSize)

        // Generate sine wave at known frequency
        let frequency = 1000.0 // 1 kHz
        let binIndex = Int(frequency / sampleRate * Double(fftSize))

        var sineWave = [Float](repeating: 0, count: fftSize)
        for i in 0..<fftSize {
            sineWave[i] = Float(sin(2.0 * Double.pi * frequency * Double(i) / sampleRate))
        }

        let (real, imag) = processor.forwardFFT(sineWave)

        // Peak should be at expected bin
        let magnitudes = processor.magnitude(real: real, imag: imag)
        let peakBin = magnitudes.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0

        XCTAssertEqual(peakBin, binIndex, "Peak should be at bin \(binIndex) for \(frequency) Hz")
    }

    func testForwardFFTOfSilence() throws {
        let fftSize = 4096
        let processor = try FFTProcessor(fftSize: fftSize)

        let silence = [Float](repeating: 0, count: fftSize)
        let (real, imag) = processor.forwardFFT(silence)

        // All bins should be zero
        for i in 0..<fftSize {
            XCTAssertLessThan(abs(real[i]), 0.0001, "Real part should be zero at bin \(i)")
            XCTAssertLessThan(abs(imag[i]), 0.0001, "Imaginary part should be zero at bin \(i)")
        }
    }

    // MARK: - Inverse FFT Tests

    func testInverseFFTReconstructsSignal() throws {
        let fftSize = 4096
        let processor = try FFTProcessor(fftSize: fftSize)

        // Original signal - simple sine wave
        var original = [Float](repeating: 0, count: fftSize)
        for i in 0..<fftSize {
            original[i] = Float(sin(2.0 * Double.pi * 440.0 * Double(i) / 48000.0))
        }

        // Forward then inverse FFT
        let (real, imag) = processor.forwardFFT(original)
        let reconstructed = processor.inverseFFT(real: real, imag: imag)

        // Should reconstruct original signal
        for i in 0..<min(100, fftSize) {
            XCTAssertLessThan(
                abs(original[i] - reconstructed[i]),
                0.001,
                "Reconstructed signal should match original at sample \(i)"
            )
        }
    }

    // MARK: - Magnitude/Phase Tests

    func testMagnitudeCalculation() throws {
        let fftSize = 4096
        let processor = try FFTProcessor(fftSize: fftSize)

        // Pure real signal - magnitude should be |real|
        var real = [Float](repeating: 0, count: fftSize)
        var imag = [Float](repeating: 0, count: fftSize)
        real[100] = 0.5

        let magnitudes = processor.magnitude(real: real, imag: imag)
        XCTAssertLessThan(abs(magnitudes[100] - 0.5), 0.001, "Magnitude should be 0.5")

        // Complex signal - magnitude should be sqrt(real^2 + imag^2)
        real[200] = 3.0
        imag[200] = 4.0
        let mags = processor.magnitude(real: real, imag: imag)
        XCTAssertLessThan(abs(mags[200] - 5.0), 0.001, "Magnitude should be 5.0 (3-4-5 triangle)")
    }

    func testPhaseCalculation() throws {
        let fftSize = 4096
        let processor = try FFTProcessor(fftSize: fftSize)

        var real = [Float](repeating: 0, count: fftSize)
        var imag = [Float](repeating: 0, count: fftSize)

        // Phase of 45 degrees (pi/4)
        real[0] = 1.0
        imag[0] = 1.0

        let phases = processor.phase(real: real, imag: imag)
        XCTAssertLessThan(abs(phases[0] - Float.pi / 4), 0.001, "Phase should be pi/4")
    }
}

// MARK: - DeconvolutionEngine Tests

final class DeconvolutionEngineTests: XCTestCase {

    // MARK: - Basic Deconvolution Tests

    func testDeconvolutionOfIdentitySystem() async throws {
        let engine = DeconvolutionEngine(fftSize: 8192)

        // Create excitation signal (simple impulse)
        var excitation = [Float](repeating: 0, count: 4096)
        excitation[0] = 1.0

        // Recording is identical (identity system)
        let recording = excitation

        let ir = try await engine.extractImpulseResponse(
            excitation: excitation,
            recording: recording,
            sampleRate: 48000,
            speaker: .frontLeft
        )

        // Should get impulse at t=0
        XCTAssertGreaterThan(ir.samples.count, 0, "Should have samples")
        XCTAssertEqual(ir.sampleRate, 48000, "Sample rate should match")
        XCTAssertEqual(ir.speaker, .frontLeft, "Speaker should match")

        // Peak should be at or near start
        let peakIndex = ir.samples.enumerated().max(by: { abs($0.element) < abs($1.element) })?.offset ?? -1
        XCTAssertLessThan(peakIndex, 10, "Peak should be near start for identity system")
    }

    func testDeconvolutionPreservesSpeakerInfo() async throws {
        let engine = DeconvolutionEngine(fftSize: 8192)

        var excitation = [Float](repeating: 0, count: 4096)
        excitation[0] = 1.0

        for speaker in SpeakerChannel.allCases {
            let ir = try await engine.extractImpulseResponse(
                excitation: excitation,
                recording: excitation,
                sampleRate: 44100,
                speaker: speaker
            )

            XCTAssertEqual(ir.speaker, speaker, "Speaker should be \(speaker)")
            XCTAssertEqual(ir.sampleRate, 44100, "Sample rate should be 44100")
        }
    }

    func testDeconvolutionWithDifferentSampleRates() async throws {
        let engine = DeconvolutionEngine(fftSize: 8192)

        var excitation = [Float](repeating: 0, count: 4096)
        excitation[0] = 1.0

        for sampleRate in [44100.0, 48000.0, 96000.0] {
            let ir = try await engine.extractImpulseResponse(
                excitation: excitation,
                recording: excitation,
                sampleRate: sampleRate,
                speaker: .center
            )

            XCTAssertEqual(ir.sampleRate, sampleRate, "Sample rate should be \(sampleRate)")
        }
    }

    func testDeconvolutionWithProgress() async throws {
        let engine = DeconvolutionEngine(fftSize: 8192)

        var excitation = [Float](repeating: 0, count: 4096)
        excitation[0] = 1.0

        var progressValues: [Double] = []

        _ = try await engine.extractImpulseResponse(
            excitation: excitation,
            recording: excitation,
            sampleRate: 48000,
            speaker: .frontLeft
        ) { progress in
            progressValues.append(progress)
        }

        // Should have received progress updates
        XCTAssertFalse(progressValues.isEmpty, "Should have progress updates")

        // Progress should be increasing
        for i in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(progressValues[i], progressValues[i - 1], "Progress should increase")
        }

        // Final progress should be 1.0
        XCTAssertEqual(progressValues.last ?? 0, 1.0, accuracy: 0.01, "Final progress should be 1.0")
    }
}

// MARK: - ImpulseResponse Tests

final class ImpulseResponseTests: XCTestCase {

    // MARK: - Initialization Tests

    func testImpulseResponseInitialization() {
        let samples: [Float] = [0, 0.5, 1.0, 0.5, 0]
        let ir = ImpulseResponse(
            samples: samples,
            sampleRate: 48000,
            fftSize: 4096,
            speaker: .frontRight
        )

        XCTAssertEqual(ir.samples.count, 5)
        XCTAssertEqual(ir.sampleRate, 48000)
        XCTAssertEqual(ir.fftSize, 4096)
        XCTAssertEqual(ir.speaker, .frontRight)
        XCTAssertNotNil(ir.id)
        XCTAssertNotNil(ir.measurementDate)
    }

    // MARK: - Computed Properties Tests

    func testDurationCalculation() {
        let samples = [Float](repeating: 0, count: 48000) // 1 second at 48kHz
        let ir = ImpulseResponse(
            samples: samples,
            sampleRate: 48000,
            fftSize: 4096,
            speaker: .center
        )

        XCTAssertEqual(ir.duration, 1.0, accuracy: 0.001, "Duration should be 1.0 seconds")
        XCTAssertEqual(ir.sampleCount, 48000, "Sample count should be 48000")
    }

    // MARK: - Frequency Response Tests

    func testFrequencyResponseReturnsValidData() {
        // Create a simple impulse response
        var samples = [Float](repeating: 0, count: 4096)
        samples[0] = 1.0 // Unit impulse

        let ir = ImpulseResponse(
            samples: samples,
            sampleRate: 48000,
            fftSize: 4096,
            speaker: .frontLeft
        )

        let frequencies = [100.0, 1000.0, 5000.0, 10000.0]
        let response = ir.frequencyResponse(frequencies: frequencies)

        XCTAssertEqual(response.count, frequencies.count, "Should return response for each frequency")

        for (index, result) in response.enumerated() {
            XCTAssertEqual(result.frequency, frequencies[index], "Frequency should match")
            // Magnitude should be a valid number (not NaN or Inf)
            XCTAssertTrue(result.magnitude.isFinite, "Magnitude should be finite")
            XCTAssertTrue(result.phase.isFinite, "Phase should be finite")
        }
    }

    func testFrequencyResponseHandlesEmptySamples() {
        let ir = ImpulseResponse(
            samples: [],
            sampleRate: 48000,
            fftSize: 4096,
            speaker: .center
        )

        let response = ir.frequencyResponse(frequencies: [1000.0])

        XCTAssertEqual(response.count, 1)
        XCTAssertEqual(response[0].magnitude, -100, "Empty samples should return -100 dB")
    }

    func testFrequencyResponseHandlesOutOfNyquistRange() {
        let samples = [Float](repeating: 0, count: 4096)
        let ir = ImpulseResponse(
            samples: samples,
            sampleRate: 48000,
            fftSize: 4096,
            speaker: .center
        )

        // Request frequency above Nyquist (24000 Hz)
        let response = ir.frequencyResponse(frequencies: [30000.0])

        XCTAssertEqual(response[0].magnitude, -100, "Above Nyquist should return -100 dB")
    }

    // MARK: - Analysis Tests

    func testAnalyzeReturnsValidParameters() {
        // Create a synthetic impulse response with known characteristics
        var samples = [Float](repeating: 0, count: 48000)
        samples[0] = 1.0 // Direct sound at t=0

        // Add some decay
        for i in 1..<1000 {
            samples[i] = Float(exp(-Double(i) / 100.0))
        }

        let ir = ImpulseResponse(
            samples: samples,
            sampleRate: 48000,
            fftSize: 65536,
            speaker: .frontLeft
        )

        let params = ir.analyze()

        XCTAssertGreaterThan(params.peakAmplitude, 0.9, "Peak should be near 1.0")
        XCTAssertEqual(params.peakSample, 0, "Peak should be at sample 0")
        XCTAssertGreaterThan(params.rt60, 0, "RT60 should be positive")
        XCTAssertTrue(params.signalToNoiseRatio.isFinite, "SNR should be finite")
    }

    // MARK: - Processing Tests

    func testTrimmedRemovesTrailingSilence() {
        var samples = [Float](repeating: 0, count: 1000)
        samples[0] = 1.0
        samples[1] = 0.5
        samples[2] = 0.1
        // Rest is silence

        let ir = ImpulseResponse(
            samples: samples,
            sampleRate: 48000,
            fftSize: 4096,
            speaker: .center
        )

        let trimmed = ir.trimmed(thresholdDB: -40)

        XCTAssertLessThan(trimmed.samples.count, samples.count, "Trimmed should be shorter")
        XCTAssertGreaterThan(trimmed.samples.count, 0, "Should still have samples")
    }

    func testNormalizedToOne() {
        let samples: [Float] = [0.5, 1.0, 0.5]
        let ir = ImpulseResponse(
            samples: samples,
            sampleRate: 48000,
            fftSize: 4096,
            speaker: .center
        )

        let normalized = ir.normalized()
        let peak = normalized.samples.map { abs($0) }.max() ?? 0

        XCTAssertEqual(peak, 1.0, accuracy: 0.001, "Peak should be 1.0 after normalization")
    }

    // MARK: - Energy Decay Curve Tests

    func testEnergyDecayCurveIsMonotonic() {
        var samples = [Float](repeating: 0, count: 1000)
        samples[0] = 1.0
        for i in 1..<1000 {
            samples[i] = Float(exp(-Double(i) / 100.0))
        }

        let ir = ImpulseResponse(
            samples: samples,
            sampleRate: 48000,
            fftSize: 4096,
            speaker: .center
        )

        let curve = ir.energyDecayCurve()

        // Curve should be monotonically decreasing
        for i in 1..<curve.count {
            XCTAssertLessThanOrEqual(curve[i], curve[i - 1] + 0.001, "Decay curve should be monotonic")
        }
    }
}

// MARK: - WAVEExporter Tests

final class WAVEExporterTests: XCTestCase {

    func testExportCreatesValidWAVFile() throws {
        let samples: [Float] = [0.0, 0.5, 1.0, 0.5, 0.0, -0.5, -1.0, -0.5, 0.0]
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID()).wav")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try WAVEExporter.export(samples: samples, sampleRate: 48000, to: tempURL)

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "WAV file should exist")

        // Verify file has content
        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 44, "File should be larger than WAV header")
    }

    func testWAVHeaderIsCorrect() throws {
        let samples: [Float] = [1.0, 0.0, -1.0, 0.0]
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_header_\(UUID()).wav")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try WAVEExporter.export(samples: samples, sampleRate: 44100, to: tempURL)

        let data = try Data(contentsOf: tempURL)

        // Check RIFF header
        XCTAssertEqual(data[0...3], Data("RIFF".utf8), "Should have RIFF header")

        // Check WAVE format
        XCTAssertEqual(data[8...11], Data("WAVE".utf8), "Should have WAVE format")

        // Check fmt chunk
        XCTAssertEqual(data[12...15], Data("fmt ".utf8), "Should have fmt chunk")

        // Check audio format (3 = IEEE float)
        let audioFormat = data[20...21].withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(audioFormat, 3, "Audio format should be IEEE float (3)")

        // Check sample rate
        let sampleRate = data[24...27].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(sampleRate, 44100, "Sample rate should be 44100")

        // Check data chunk
        XCTAssertEqual(data[36...39], Data("data".utf8), "Should have data chunk")
    }

    func testExportOverwritesExistingFile() throws {
        let samples1: [Float] = [1.0, 1.0, 1.0]
        let samples2: [Float] = [0.0, 0.0, 0.0, 0.0]
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_overwrite_\(UUID()).wav")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // First export
        try WAVEExporter.export(samples: samples1, sampleRate: 48000, to: tempURL)

        // Second export (should overwrite)
        try WAVEExporter.export(samples: samples2, sampleRate: 48000, to: tempURL)

        // Read back and verify it's the second file
        let data = try Data(contentsOf: tempURL)
        let dataSize = data[40...43].withUnsafeBytes { $0.load(as: UInt32.self) }

        // samples2 has 4 floats = 16 bytes
        XCTAssertEqual(Int(dataSize), samples2.count * 4, "Should have second file's data")
    }
}

// MARK: - CalibrationError Tests

final class CalibrationErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertNotNil(CalibrationError.noHDMIDevice.errorDescription)
        XCTAssertNotNil(CalibrationError.permissionDenied.errorDescription)
        XCTAssertNotNil(CalibrationError.lowSNR(.frontLeft, 20.0).errorDescription)
        XCTAssertNotNil(CalibrationError.processingFailed("test").errorDescription)

        // Verify descriptions are user-friendly
        XCTAssertTrue(CalibrationError.noHDMIDevice.errorDescription?.contains("HDMI") ?? false)
        XCTAssertTrue(CalibrationError.permissionDenied.recoverySuggestion?.contains("Settings") ?? false)
    }

    func testCodableRoundTrip() throws {
        let errors: [CalibrationError] = [
            .noHDMIDevice,
            .unsupportedFormat("test format"),
            .configurationFailed("config error"),
            .measurementFailed("measurement error"),
            .processingFailed("processing error"),
            .exportFailed("export error"),
            .permissionDenied,
            .deviceBusy,
            .engineNotRunning,
            .noMicrophoneAccess,
            .noSignal(.frontLeft),
            .clipping(.center),
            .lowSNR(.rearLeft, 35.5),
            .invalidTiming(.rearRight),
            .abnormalRT60(.lfe, 10.0)
        ]

        for originalError in errors {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let data = try encoder.encode(originalError)
            let decoded = try decoder.decode(CalibrationError.self, from: data)

            // Compare error descriptions (easiest way to verify equality)
            XCTAssertEqual(decoded.errorDescription, originalError.errorDescription, "Round trip should preserve error")
        }
    }

    func testRecoverySuggestions() {
        // Errors with recovery suggestions
        XCTAssertNotNil(CalibrationError.noHDMIDevice.recoverySuggestion)
        XCTAssertNotNil(CalibrationError.permissionDenied.recoverySuggestion)
        XCTAssertNotNil(CalibrationError.deviceBusy.recoverySuggestion)
        XCTAssertNotNil(CalibrationError.clipping(.frontLeft).recoverySuggestion)
        XCTAssertNotNil(CalibrationError.lowSNR(.center, 20.0).recoverySuggestion)

        // Errors without specific recovery suggestions
        XCTAssertNil(CalibrationError.engineNotRunning.recoverySuggestion)
        XCTAssertNil(CalibrationError.noSignal(.frontLeft).recoverySuggestion)
    }
}

// MARK: - AcousticParameters Tests

final class AcousticParametersTests: XCTestCase {

    func testAnalyzeSimpleImpulse() {
        // Create a simple impulse response
        var samples = [Float](repeating: 0, count: 48000)
        samples[0] = 1.0
        for i in 1..<4800 { // 100ms decay
            samples[i] = Float(exp(-Double(i) / 500.0))
        }

        let ir = ImpulseResponse(
            samples: samples,
            sampleRate: 48000,
            fftSize: 65536,
            speaker: .frontLeft
        )

        let params = ir.analyze()

        XCTAssertEqual(params.peakAmplitude, 1.0, accuracy: 0.01)
        XCTAssertEqual(params.peakSample, 0)
        XCTAssertEqual(params.peakTime, 0, accuracy: 0.1)
        XCTAssertGreaterThan(params.rt60, 0)
        XCTAssertLessThan(params.rt60, 10) // Should be reasonable
    }

    func testAnalyzeClarityMetrics() {
        // Create impulse with known early/late energy ratio
        var samples = [Float](repeating: 0, count: 48000)
        samples[0] = 1.0

        // Strong early energy (first 50ms = 2400 samples at 48kHz)
        for i in 1..<2400 {
            samples[i] = 0.5 * Float(exp(-Double(i) / 1000.0))
        }

        // Weak late energy
        for i in 2400..<48000 {
            samples[i] = 0.01 * Float(exp(-Double(i - 2400) / 5000.0))
        }

        let ir = ImpulseResponse(
            samples: samples,
            sampleRate: 48000,
            fftSize: 65536,
            speaker: .frontLeft
        )

        let params = ir.analyze()

        // C50 and C80 should be positive (more early than late energy)
        XCTAssertGreaterThan(params.c50, 0, "C50 should be positive with strong early energy")
        XCTAssertGreaterThan(params.c80, 0, "C80 should be positive with strong early energy")

        // D50 should be high (most energy is early)
        XCTAssertGreaterThan(params.d50, 0.5, "D50 should be > 0.5 with strong early energy")
    }
}

// MARK: - Sweep Generator Tests (Existing, kept for reference)

final class SweepGeneratorTests: XCTestCase {

    func testFrequencyRange() async throws {
        let generator = SweepGenerator(
            startFrequency: 20,
            endFrequency: 20000,
            duration: 1.0,
            sampleRate: 48000,
            amplitude: 0.8
        )

        let samples = generator.generateBuffer()

        let expectedCount = Int(1.0 * 48000)
        XCTAssertEqual(samples.count, expectedCount, "Sample count should be \(expectedCount)")

        let peak = samples.map { abs($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(peak, 0.85, "Peak amplitude should not exceed configured amplitude")
        XCTAssertGreaterThanOrEqual(peak, 0.75, "Peak amplitude should be close to configured amplitude")
    }

    func testStartStop() async throws {
        let generator = SweepGenerator(
            startFrequency: 100,
            endFrequency: 1000,
            duration: 0.1,
            sampleRate: 48000
        )

        XCTAssertFalse(generator.running, "Should not be running initially")

        generator.start()
        XCTAssertTrue(generator.running, "Should be running after start")

        generator.stop()
        XCTAssertFalse(generator.running, "Should not be running after stop")
    }

    func testProgress() async throws {
        let generator = SweepGenerator(
            duration: 1.0,
            sampleRate: 48000
        )

        XCTAssertEqual(generator.currentProgress, 0, "Progress should start at 0")

        generator.start()
        XCTAssertTrue(generator.running, "Should be running")

        generator.reset()
        XCTAssertEqual(generator.currentProgress, 0, "Progress should be 0 after reset")
    }
}

// MARK: - Math Helpers Tests

final class MathHelpersTests: XCTestCase {

    func testNextPowerOf2() {
        XCTAssertEqual(MathHelpers.nextPowerOf2(1), 1)
        XCTAssertEqual(MathHelpers.nextPowerOf2(2), 2)
        XCTAssertEqual(MathHelpers.nextPowerOf2(3), 4)
        XCTAssertEqual(MathHelpers.nextPowerOf2(100), 128)
        XCTAssertEqual(MathHelpers.nextPowerOf2(1000), 1024)
        XCTAssertEqual(MathHelpers.nextPowerOf2(100000), 131072)
    }

    func testIsPowerOf2() {
        XCTAssertTrue(MathHelpers.isPowerOf2(1))
        XCTAssertTrue(MathHelpers.isPowerOf2(2))
        XCTAssertTrue(MathHelpers.isPowerOf2(4))
        XCTAssertTrue(MathHelpers.isPowerOf2(1024))
        XCTAssertFalse(MathHelpers.isPowerOf2(3))
        XCTAssertFalse(MathHelpers.isPowerOf2(100))
        XCTAssertFalse(MathHelpers.isPowerOf2(0))
    }

    func testDBConversion() {
        let linear: Float = 1.0
        let db = MathHelpers.linearToDB(linear)
        XCTAssertLessThan(abs(db), 0.001, "0 dB should be 1.0 linear")

        let backToLinear = MathHelpers.dbToLinear(db)
        XCTAssertLessThan(abs(backToLinear - linear), 0.001, "Round trip should be accurate")
    }

    func testRMS() {
        let dcSignal = [Float](repeating: 1.0, count: 100)
        let rms = MathHelpers.rms(dcSignal)
        XCTAssertLessThan(abs(rms - 1.0), 0.001, "RMS of DC signal should be 1.0")

        let silence = [Float](repeating: 0.0, count: 100)
        let silenceRMS = MathHelpers.rms(silence)
        XCTAssertLessThan(abs(silenceRMS), 0.001, "RMS of silence should be 0")
    }

    func testZeroPad() {
        let input: [Float] = [1, 2, 3]
        let padded = MathHelpers.zeroPad(input, targetSize: 10)

        XCTAssertEqual(padded.count, 10, "Should have target size")
        XCTAssertEqual(padded[0], 1, "First element should be preserved")
        XCTAssertEqual(padded[2], 3, "Third element should be preserved")
        XCTAssertEqual(padded[3], 0, "Padded elements should be 0")
    }
}

// MARK: - Calibration Config Tests

final class CalibrationConfigTests: XCTestCase {

    func testDefaultConfigIsValid() {
        let config = CalibrationConfig.default
        let errors = config.validate()
        XCTAssertTrue(errors.isEmpty, "Default config should be valid")
    }

    func testInvalidFrequencyRangeIsCaught() {
        let config = CalibrationConfig(
            startFrequency: 1000,
            endFrequency: 100
        )
        let errors = config.validate()
        XCTAssertFalse(errors.isEmpty, "Should have validation error")
    }

    func testFFTSizeMustBePowerOf2() {
        let config = CalibrationConfig(fftSize: 1000)
        let errors = config.validate()
        XCTAssertFalse(errors.isEmpty, "Should have validation error for non-power-of-2")
    }

    func testTotalRecordingDurationIsCorrect() {
        let config = CalibrationConfig(
            sweepDuration: 5.0,
            preSweepSilence: 0.5,
            postSweepSilence: 2.0
        )
        XCTAssertEqual(config.totalRecordingDuration, 7.5, "Total duration should be 7.5s")
    }
}

// MARK: - Speaker Channel Tests

final class SpeakerChannelTests: XCTestCase {

    func testAllChannelsAreAvailable() {
        let channels = SpeakerChannel.allCases
        XCTAssertEqual(channels.count, 6, "Should have 6 channels for 5.1")
    }

    func testMeasurementOrderIsCorrect() {
        let order = SpeakerChannel.measurementOrder
        XCTAssertEqual(order.first, .frontLeft, "Should start with front left")
        XCTAssertEqual(order.last, .rearRight, "Should end with rear right")
    }

    func testChannelPropertiesAreCorrect() {
        XCTAssertEqual(SpeakerChannel.frontLeft.rawValue, 0)
        XCTAssertEqual(SpeakerChannel.lfe.rawValue, 3)
        XCTAssertEqual(SpeakerChannel.rearRight.shortName, "RR")
    }
}
