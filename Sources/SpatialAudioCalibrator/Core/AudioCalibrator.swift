import AVFAudio
@preconcurrency import Combine
import Foundation

/// Main orchestrator for the acoustic calibration process.
///
/// This class coordinates:
/// - Audio engine management
/// - Speaker-by-speaker measurement
/// - Impulse response extraction
/// - Results aggregation and export
@MainActor
public final class AudioCalibrator: ObservableObject {
    // MARK: Lifecycle

    // MARK: - Initialization

    public init(config: CalibrationConfig = .default) {
        self.config = config
        deconvolutionEngine = DeconvolutionEngine(
            fftSize: config.fftSize,
            regularizationThreshold: config.regularizationDB
        )
        sweepGenerator = SweepGenerator(
            startFrequency: config.startFrequency,
            endFrequency: config.endFrequency,
            duration: config.sweepDuration,
            sampleRate: config.sampleRate,
            amplitude: config.outputAmplitude
        )
    }

    // MARK: Public

    // MARK: - Published Properties

    /// Current calibration state
    @Published public var state: CalibrationState = .idle

    /// Current measurement progress
    @Published public var progress: CalibrationProgress?

    /// Current speaker analysis results
    @Published public var currentAnalysis: AcousticParameters?

    /// Last error that occurred
    @Published public var error: CalibrationError?

    /// System status after verification
    @Published public var systemStatus: SystemStatus?

    // MARK: - Configuration

    /// Calibration configuration
    public var config: CalibrationConfig

    // MARK: - Results

    /// Completed measurements
    public private(set) var measurements: [SpeakerMeasurement] = []

    // MARK: - System Verification

    /// Verify system configuration and return status
    public func verifySystemConfiguration() throws -> SystemStatus {
        state = .verifying

        do {
            // Check for HDMI device
            let hdmiDevice = AudioDeviceManager.findHDMIDevice()
            let outputDeviceID = hdmiDevice ?? AudioDeviceManager.getDefaultOutputDevice()

            // Get device info
            let outputDevice = outputDeviceID.flatMap { AudioDeviceInfo(deviceID: $0) }

            // Check microphone access
            let microphoneAccess = checkMicrophoneAccess()

            // Get latency info
            var latencySamples: UInt32 = 0
            var latencyMs: Double = 0
            if let deviceID = outputDeviceID, let bufferConfig = AudioDeviceManager.getBufferConfiguration(deviceID) {
                latencySamples = bufferConfig.totalLatency
                latencyMs = bufferConfig.latencyMs(at: config.sampleRate)
            }

            let status = SystemStatus(
                outputDevice: outputDevice,
                inputDevice: nil, // TODO: Get actual input device
                hasHDMI: hdmiDevice != nil,
                supports51: outputDeviceID.flatMap { AudioDeviceManager.supportsChannelCount($0, count: 6) } ?? false,
                latencySamples: latencySamples,
                latencyMs: latencyMs,
                microphoneAccess: microphoneAccess
            )

            systemStatus = status
            state = .ready

            return status
        } catch {
            self.error = error as? CalibrationError ?? .configurationFailed(error.localizedDescription)
            state = .error(self.error!)
            throw error
        }
    }

    // MARK: - Calibration

    /// Start full calibration sequence
    public func startCalibration() async throws {
        guard state == .ready else {
            throw CalibrationError.engineNotRunning
        }

        measurements.removeAll()
        error = nil

        do {
            // Initialize audio engine
            try initializeEngine()

            // Measure each speaker in order
            for (index, speaker) in SpeakerChannel.measurementOrder.enumerated() {
                progress = CalibrationProgress(
                    currentSpeakerIndex: index,
                    totalSpeakers: SpeakerChannel.allCases.count,
                    currentSpeaker: speaker,
                    measurementProgress: 0
                )

                let measurement = try await measureSpeaker(speaker)
                measurements.append(measurement)
                currentAnalysis = measurement.analysis
            }

            state = .completed
            progress = nil
        } catch {
            self.error = error as? CalibrationError ?? .measurementFailed(error.localizedDescription)
            state = .error(self.error!)
            throw error
        }
    }

    /// Measure a single speaker
    public func measureSpeaker(_ speaker: SpeakerChannel) async throws -> SpeakerMeasurement {
        guard let engine = audioEngine else {
            throw CalibrationError.engineNotRunning
        }

        state = .measuring(speaker)

        // Set channel map for target speaker
        try engine.setChannelMap(target: speaker)

        // Generate excitation signal
        let excitation = sweepGenerator.generateBuffer()

        // Start engine
        try engine.start()

        // Start recording
        engine.startRecording()

        // Play sweep
        sweepGenerator.start()

        // Wait for sweep + recording margin
        let totalDuration = config.totalRecordingDuration
        try await Task.sleep(nanoseconds: UInt64(totalDuration * 1_000_000_000))

        // Stop recording
        let recording = engine.stopRecording()
        sweepGenerator.stop()
        engine.stop()

        state = .processing(speaker)

        // Compensate for latency
        let compensatedRecording = engine.compensateLatency(recording)

        // Extract impulse response
        let impulseResponse = try deconvolutionEngine.extractImpulseResponse(
            excitation: excitation,
            recording: compensatedRecording,
            sampleRate: config.sampleRate,
            speaker: speaker
        ) { [weak self] p in
            Task { @MainActor [weak self] in
                self?.progress = CalibrationProgress(
                    currentSpeakerIndex: self?.progress?.currentSpeakerIndex ?? 0,
                    totalSpeakers: SpeakerChannel.allCases.count,
                    currentSpeaker: speaker,
                    measurementProgress: p
                )
            }
        }

        // Create measurement result
        return SpeakerMeasurement(
            speaker: speaker,
            impulseResponse: impulseResponse,
            recordingDuration: totalDuration,
            snr: impulseResponse.analyze().signalToNoiseRatio
        )
    }

    /// Stop current calibration
    public func stopCalibration() {
        sweepGenerator.stop()
        audioEngine?.stop()
        audioEngine?.stopRecording()
        state = .idle
        progress = nil
    }

    // MARK: - Export

    /// Export results to specified directory
    public func exportResults(to url: URL) throws {
        guard !measurements.isEmpty else {
            throw CalibrationError.exportFailed("No measurements to export")
        }

        // Create directory
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let exportDir = url.appendingPathComponent(timestamp)

        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Export each impulse response
        for measurement in measurements {
            let filename = measurement.speaker.shortName.lowercased()
            let wavURL = exportDir.appendingPathComponent("\(filename).wav")
            try measurement.impulseResponse.exportWAV(to: wavURL)
        }

        // Export analysis JSON
        let analysisURL = exportDir.appendingPathComponent("analysis.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        // Create serializable analysis data
        let analysisDict = measurements.map { measurement in
            [
                "speaker": measurement.speaker.shortName,
                "peakAmplitude": Double(measurement.analysis.peakAmplitude),
                "peakTime": measurement.analysis.peakTime,
                "rt60": measurement.analysis.rt60,
                "edt": measurement.analysis.edt,
                "c80": measurement.analysis.c80,
                "c50": measurement.analysis.c50,
                "snr": Double(measurement.snr),
                "isValid": measurement.isValid
            ]
        }

        let analysisData = try JSONSerialization.data(
            withJSONObject: analysisDict,
            options: [.prettyPrinted, .sortedKeys]
        )
        try analysisData.write(to: analysisURL)

        // Export config
        let configURL = exportDir.appendingPathComponent("config.json")
        let configData = try encoder.encode(config)
        try configData.write(to: configURL)
    }

    // MARK: Private

    // MARK: - Private Properties

    private var audioEngine: AudioEngine?
    private var deconvolutionEngine: DeconvolutionEngine
    private var sweepGenerator: SweepGenerator

    private func checkMicrophoneAccess() -> Bool {
        // Check actual microphone permission status
        let permission = AVAudioApplication.shared.recordPermission
        guard permission == .granted else {
            return false
        }

        // Also verify input devices are available
        return !AudioDeviceManager.getInputDevices().isEmpty
    }

    private func initializeEngine() throws {
        state = .initializing

        // Find output device
        guard let deviceID = AudioDeviceManager.findHDMIDevice() ?? AudioDeviceManager.getDefaultOutputDevice() else {
            throw CalibrationError.noHDMIDevice
        }

        // Configure 5.1 output
        AudioDeviceManager.configure51Surround(deviceID)

        // Create audio engine
        audioEngine = try AudioEngine(outputDeviceID: deviceID)
    }
}
