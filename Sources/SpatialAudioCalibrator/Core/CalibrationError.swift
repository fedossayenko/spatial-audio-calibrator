import Foundation

/// Errors that can occur during the calibration process.
public enum CalibrationError: Error, LocalizedError, Codable {
    /// No HDMI audio device found
    case noHDMIDevice

    /// Audio format not supported by device
    case unsupportedFormat(String)

    /// Failed to configure audio hardware
    case configurationFailed(String)

    /// Measurement failed for specific reason
    case measurementFailed(String)

    /// DSP processing failed
    case processingFailed(String)

    /// Export operation failed
    case exportFailed(String)

    /// User denied microphone permission
    case permissionDenied

    /// Audio device is busy with another application
    case deviceBusy

    /// Audio engine is not running
    case engineNotRunning

    /// Microphone access not available
    case noMicrophoneAccess

    /// No signal detected during measurement
    case noSignal(SpeakerChannel)

    /// Signal clipped during recording
    case clipping(SpeakerChannel)

    /// Signal-to-noise ratio too low
    case lowSNR(SpeakerChannel, Float)

    /// Invalid measurement timing
    case invalidTiming(SpeakerChannel)

    /// Abnormal reverberation time
    case abnormalRT60(SpeakerChannel, Double)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .noHDMIDevice:
            return "No HDMI audio device found. Please connect your HDMI audio device and ensure it's selected in System Settings > Sound."
        case .unsupportedFormat(let details):
            return "Unsupported audio format: \(details)"
        case .configurationFailed(let reason):
            return "Failed to configure audio: \(reason)"
        case .measurementFailed(let reason):
            return "Measurement failed: \(reason)"
        case .processingFailed(let reason):
            return "Signal processing failed: \(reason)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .permissionDenied:
            return "Permission denied. Please grant microphone access in System Settings > Privacy & Security > Microphone."
        case .deviceBusy:
            return "Audio device is busy. Please close other audio applications and try again."
        case .engineNotRunning:
            return "Audio engine is not running. Please restart calibration."
        case .noMicrophoneAccess:
            return "Microphone access not available. Please check System Settings > Privacy & Security > Microphone."
        case .noSignal(let speaker):
            return "No signal detected from \(speaker.displayName). Check speaker connection and volume."
        case .clipping(let speaker):
            return "Signal clipped on \(speaker.displayName). Reduce output volume and try again."
        case .lowSNR(let speaker, let snr):
            return "Signal-to-noise ratio too low on \(speaker.displayName) (\(String(format: "%.1f", snr)) dB). Reduce ambient noise or increase volume."
        case .invalidTiming(let speaker):
            return "Invalid timing detected for \(speaker.displayName). Check latency compensation."
        case .abnormalRT60(let speaker, let rt60):
            return "Abnormal reverberation time (\(String(format: "%.2f", rt60))s) for \(speaker.displayName). Check room acoustics."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noHDMIDevice:
            return "Connect HDMI cable and check Audio MIDI Setup for device configuration."
        case .permissionDenied, .noMicrophoneAccess:
            return "Open System Settings > Privacy & Security > Microphone and enable access for this application."
        case .deviceBusy:
            return "Close all audio applications (music players, video editors, etc.) and restart calibration."
        case .clipping:
            return "Lower the output volume in calibration settings and retry."
        case .lowSNR:
            return "Ensure quiet environment, increase output volume, or check microphone position."
        default:
            return nil
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type
        case details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "noHDMIDevice":
            self = .noHDMIDevice
        case "unsupportedFormat":
            let details = try container.decode(String.self, forKey: .details)
            self = .unsupportedFormat(details)
        case "configurationFailed":
            let reason = try container.decode(String.self, forKey: .details)
            self = .configurationFailed(reason)
        case "measurementFailed":
            let reason = try container.decode(String.self, forKey: .details)
            self = .measurementFailed(reason)
        case "processingFailed":
            let reason = try container.decode(String.self, forKey: .details)
            self = .processingFailed(reason)
        case "exportFailed":
            let reason = try container.decode(String.self, forKey: .details)
            self = .exportFailed(reason)
        case "permissionDenied":
            self = .permissionDenied
        case "deviceBusy":
            self = .deviceBusy
        case "engineNotRunning":
            self = .engineNotRunning
        case "noMicrophoneAccess":
            self = .noMicrophoneAccess
        case "noSignal":
            let rawValue = try container.decode(Int.self, forKey: .details)
            guard let speaker = SpeakerChannel(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(forKey: .details, in: container, debugDescription: "Invalid speaker channel")
            }
            self = .noSignal(speaker)
        case "clipping":
            let rawValue = try container.decode(Int.self, forKey: .details)
            guard let speaker = SpeakerChannel(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(forKey: .details, in: container, debugDescription: "Invalid speaker channel")
            }
            self = .clipping(speaker)
        case "lowSNR":
            let parts = try container.decode(String.self, forKey: .details).split(separator: ",")
            guard parts.count == 2,
                  let rawValue = Int(parts[0]),
                  let speaker = SpeakerChannel(rawValue: rawValue),
                  let snr = Float(parts[1]) else {
                throw DecodingError.dataCorruptedError(forKey: .details, in: container, debugDescription: "Invalid lowSNR format")
            }
            self = .lowSNR(speaker, snr)
        case "invalidTiming":
            let rawValue = try container.decode(Int.self, forKey: .details)
            guard let speaker = SpeakerChannel(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(forKey: .details, in: container, debugDescription: "Invalid speaker channel")
            }
            self = .invalidTiming(speaker)
        case "abnormalRT60":
            let parts = try container.decode(String.self, forKey: .details).split(separator: ",")
            guard parts.count == 2,
                  let rawValue = Int(parts[0]),
                  let speaker = SpeakerChannel(rawValue: rawValue),
                  let rt60 = Double(parts[1]) else {
                throw DecodingError.dataCorruptedError(forKey: .details, in: container, debugDescription: "Invalid abnormalRT60 format")
            }
            self = .abnormalRT60(speaker, rt60)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown error type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .noHDMIDevice:
            try container.encode("noHDMIDevice", forKey: .type)
        case .unsupportedFormat(let details):
            try container.encode("unsupportedFormat", forKey: .type)
            try container.encode(details, forKey: .details)
        case .configurationFailed(let reason):
            try container.encode("configurationFailed", forKey: .type)
            try container.encode(reason, forKey: .details)
        case .measurementFailed(let reason):
            try container.encode("measurementFailed", forKey: .type)
            try container.encode(reason, forKey: .details)
        case .processingFailed(let reason):
            try container.encode("processingFailed", forKey: .type)
            try container.encode(reason, forKey: .details)
        case .exportFailed(let reason):
            try container.encode("exportFailed", forKey: .type)
            try container.encode(reason, forKey: .details)
        case .permissionDenied:
            try container.encode("permissionDenied", forKey: .type)
        case .deviceBusy:
            try container.encode("deviceBusy", forKey: .type)
        case .engineNotRunning:
            try container.encode("engineNotRunning", forKey: .type)
        case .noMicrophoneAccess:
            try container.encode("noMicrophoneAccess", forKey: .type)
        case .noSignal(let speaker):
            try container.encode("noSignal", forKey: .type)
            try container.encode(speaker.rawValue, forKey: .details)
        case .clipping(let speaker):
            try container.encode("clipping", forKey: .type)
            try container.encode(speaker.rawValue, forKey: .details)
        case .lowSNR(let speaker, let snr):
            try container.encode("lowSNR", forKey: .type)
            try container.encode("\(speaker.rawValue),\(snr)", forKey: .details)
        case .invalidTiming(let speaker):
            try container.encode("invalidTiming", forKey: .type)
            try container.encode(speaker.rawValue, forKey: .details)
        case .abnormalRT60(let speaker, let rt60):
            try container.encode("abnormalRT60", forKey: .type)
            try container.encode("\(speaker.rawValue),\(rt60)", forKey: .details)
        }
    }
}
