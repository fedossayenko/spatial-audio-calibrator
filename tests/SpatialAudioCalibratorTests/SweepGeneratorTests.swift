import Testing
import Foundation
@testable import SpatialAudioCalibrator

@Suite("Sweep Generator Tests")
struct SweepGeneratorTests {

    @Test("Generates correct frequency range")
    func testFrequencyRange() async throws {
        let generator = SweepGenerator(
            startFrequency: 20,
            endFrequency: 20000,
            duration: 1.0,
            sampleRate: 48000,
            amplitude: 0.8
        )

        let samples = generator.generateBuffer()

        // Check sample count
        let expectedCount = Int(1.0 * 48000)
        #expect(samples.count == expectedCount, "Sample count should be \(expectedCount), got \(samples.count)")

        // Check amplitude range
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak <= 0.85, "Peak amplitude should not exceed configured amplitude")
        #expect(peak >= 0.75, "Peak amplitude should be close to configured amplitude")
    }

    @Test("Start/Stop works correctly")
    func testStartStop() async throws {
        let generator = SweepGenerator(
            startFrequency: 100,
            endFrequency: 1000,
            duration: 0.1,
            sampleRate: 48000
        )

        #expect(!generator.running, "Should not be running initially")

        generator.start()
        #expect(generator.running, "Should be running after start")

        generator.stop()
        #expect(!generator.running, "Should not be running after stop")
    }

    @Test("Progress tracking works")
    func testProgress() async throws {
        let generator = SweepGenerator(
            duration: 1.0,
            sampleRate: 48000
        )

        #expect(generator.currentProgress == 0, "Progress should start at 0")

        generator.start()
        #expect(generator.running, "Should be running")

        // After reset, should be back at 0
        generator.reset()
        #expect(generator.currentProgress == 0, "Progress should be 0 after reset")
    }
}

@Suite("Math Helpers Tests")
struct MathHelpersTests {

    @Test("Next power of 2 calculation")
    func testNextPowerOf2() {
        #expect(MathHelpers.nextPowerOf2(1) == 1)
        #expect(MathHelpers.nextPowerOf2(2) == 2)
        #expect(MathHelpers.nextPowerOf2(3) == 4)
        #expect(MathHelpers.nextPowerOf2(100) == 128)
        #expect(MathHelpers.nextPowerOf2(1000) == 1024)
        #expect(MathHelpers.nextPowerOf2(100000) == 131072)
    }

    @Test("Is power of 2 check")
    func testIsPowerOf2() {
        #expect(MathHelpers.isPowerOf2(1) == true)
        #expect(MathHelpers.isPowerOf2(2) == true)
        #expect(MathHelpers.isPowerOf2(4) == true)
        #expect(MathHelpers.isPowerOf2(1024) == true)
        #expect(MathHelpers.isPowerOf2(3) == false)
        #expect(MathHelpers.isPowerOf2(100) == false)
        #expect(MathHelpers.isPowerOf2(0) == false)
    }

    @Test("dB conversion")
    func testDBConversion() {
        let linear: Float = 1.0
        let db = MathHelpers.linearToDB(linear)
        #expect(abs(db) < 0.001, "0 dB should be 1.0 linear")

        let backToLinear = MathHelpers.dbToLinear(db)
        #expect(abs(backToLinear - linear) < 0.001, "Round trip should be accurate")
    }

    @Test("RMS calculation")
    func testRMS() {
        let dcSignal = [Float](repeating: 1.0, count: 100)
        let rms = MathHelpers.rms(dcSignal)
        #expect(abs(rms - 1.0) < 0.001, "RMS of DC signal should be 1.0")

        let silence = [Float](repeating: 0.0, count: 100)
        let silenceRMS = MathHelpers.rms(silence)
        #expect(abs(silenceRMS) < 0.001, "RMS of silence should be 0")
    }

    @Test("Zero padding")
    func testZeroPad() {
        let input: [Float] = [1, 2, 3]
        let padded = MathHelpers.zeroPad(input, targetSize: 10)

        #expect(padded.count == 10, "Should have target size")
        #expect(padded[0] == 1, "First element should be preserved")
        #expect(padded[2] == 3, "Third element should be preserved")
        #expect(padded[3] == 0, "Padded elements should be 0")
    }
}

@Suite("Calibration Config Tests")
struct CalibrationConfigTests {

    @Test("Default config is valid")
    func testDefaultValid() {
        let config = CalibrationConfig.default
        let errors = config.validate()
        #expect(errors.isEmpty, "Default config should be valid")
    }

    @Test("Invalid frequency range is caught")
    func testInvalidFrequencyRange() {
        let config = CalibrationConfig(
            startFrequency: 1000,
            endFrequency: 100
        )
        let errors = config.validate()
        #expect(!errors.isEmpty, "Should have validation error")
    }

    @Test("FFT size must be power of 2")
    func testFFTSizeValidation() {
        let config = CalibrationConfig(fftSize: 1000)
        let errors = config.validate()
        #expect(!errors.isEmpty, "Should have validation error for non-power-of-2")
    }

    @Test("Total recording duration is correct")
    func testTotalDuration() {
        let config = CalibrationConfig(
            preSweepSilence: 0.5,
            sweepDuration: 5.0,
            postSweepSilence: 2.0
        )
        #expect(config.totalRecordingDuration == 7.5, "Total duration should be 7.5s")
    }
}

@Suite("Speaker Channel Tests")
struct SpeakerChannelTests {

    @Test("All channels are available")
    func testAllChannels() {
        let channels = SpeakerChannel.allCases
        #expect(channels.count == 6, "Should have 6 channels for 5.1")
    }

    @Test("Measurement order is correct")
    func testMeasurementOrder() {
        let order = SpeakerChannel.measurementOrder
        #expect(order.first == .frontLeft, "Should start with front left")
        #expect(order.last == .rearRight, "Should end with rear right")
    }

    @Test("Channel properties are correct")
    func testChannelProperties() {
        #expect(SpeakerChannel.frontLeft.rawValue == 0)
        #expect(SpeakerChannel.lfe.rawValue == 3)
        #expect(SpeakerChannel.rearRight.shortName == "RR")
    }
}
