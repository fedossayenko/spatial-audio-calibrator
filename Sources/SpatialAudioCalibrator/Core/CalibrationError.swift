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

    // MARK: Lifecycle

    // swiftlint:disable:next cyclomatic_complexity
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
                throw DecodingError.dataCorruptedError(
                    forKey: .details,
                    in: container,
                    debugDescription: "Invalid speaker channel"
                )
            }
            self = .noSignal(speaker)
        case "clipping":
            let rawValue = try container.decode(Int.self, forKey: .details)
            guard let speaker = SpeakerChannel(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .details,
                    in: container,
                    debugDescription: "Invalid speaker channel"
                )
            }
            self = .clipping(speaker)
        case "lowSNR":
            let parts = try container.decode(String.self, forKey: .details).split(separator: ",")
            guard
                parts.count == 2,
                let rawValue = Int(parts[0]),
                let speaker = SpeakerChannel(rawValue: rawValue),
                let snr = Float(parts[1])
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .details,
                    in: container,
                    debugDescription: "Invalid lowSNR format"
                )
            }
            self = .lowSNR(speaker, snr)
        case "invalidTiming":
            let rawValue = try container.decode(Int.self, forKey: .details)
            guard let speaker = SpeakerChannel(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .details,
                    in: container,
                    debugDescription: "Invalid speaker channel"
                )
            }
            self = .invalidTiming(speaker)
        case "abnormalRT60":
            let parts = try container.decode(String.self, forKey: .details).split(separator: ",")
            guard
                parts.count == 2,
                let rawValue = Int(parts[0]),
                let speaker = SpeakerChannel(rawValue: rawValue),
                let rt60 = Double(parts[1])
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .details,
                    in: container,
                    debugDescription: "Invalid abnormalRT60 format"
                )
            }
            self = .abnormalRT60(speaker, rt60)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown error type")
        }
    }

    // MARK: Public

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .noHDMIDevice:
            "No HDMI audio device found. Please connect your HDMI audio device and ensure it's selected in System Settings > Sound."
        case let .unsupportedFormat(details):
            "Unsupported audio format: \(details)"
        case let .configurationFailed(reason):
            "Failed to configure audio: \(reason)"
        case let .measurementFailed(reason):
            "Measurement failed: \(reason)"
        case let .processingFailed(reason):
            "Signal processing failed: \(reason)"
        case let .exportFailed(reason):
            "Export failed: \(reason)"
        case .permissionDenied:
            "Permission denied. Please grant microphone access in System Settings > Privacy & Security > Microphone."
        case .deviceBusy:
            "Audio device is busy. Please close other audio applications and try again."
        case .engineNotRunning:
            "Audio engine is not running. Please restart calibration."
        case .noMicrophoneAccess:
            "Microphone access not available. Please check System Settings > Privacy & Security > Microphone."
        case let .noSignal(speaker):
            "No signal detected from \(speaker.displayName). Check speaker connection and volume."
        case let .clipping(speaker):
            "Signal clipped on \(speaker.displayName). Reduce output volume and try again."
        case let .lowSNR(speaker, snr):
            "Signal-to-noise ratio too low on \(speaker.displayName) (\(String(format: "%.1f", snr)) dB). Reduce ambient noise or increase volume."
        case let .invalidTiming(speaker):
            "Invalid timing detected for \(speaker.displayName). Check latency compensation."
        case let .abnormalRT60(speaker, rt60):
            "Abnormal reverberation time (\(String(format: "%.2f", rt60))s) for \(speaker.displayName). Check room acoustics."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noHDMIDevice:
            "Connect HDMI cable and check Audio MIDI Setup for device configuration."
        case .permissionDenied, .noMicrophoneAccess:
            "Open System Settings > Privacy & Security > Microphone and enable access for this application."
        case .deviceBusy:
            "Close all audio applications (music players, video editors, etc.) and restart calibration."
        case .clipping:
            "Lower the output volume in calibration settings and retry."
        case .lowSNR:
            "Ensure quiet environment, increase output volume, or check microphone position."
        default:
            nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeString, forKey: .type)
        if let details = detailsValue {
            try container.encode(details, forKey: .details)
        }
    }

    // MARK: Internal

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type
        case details
    }

    // MARK: Private

    /// Type string for encoding
    private var typeString: String {
        switch self {
        case .noHDMIDevice: "noHDMIDevice"
        case .unsupportedFormat: "unsupportedFormat"
        case .configurationFailed: "configurationFailed"
        case .measurementFailed: "measurementFailed"
        case .processingFailed: "processingFailed"
        case .exportFailed: "exportFailed"
        case .permissionDenied: "permissionDenied"
        case .deviceBusy: "deviceBusy"
        case .engineNotRunning: "engineNotRunning"
        case .noMicrophoneAccess: "noMicrophoneAccess"
        case .noSignal: "noSignal"
        case .clipping: "clipping"
        case .lowSNR: "lowSNR"
        case .invalidTiming: "invalidTiming"
        case .abnormalRT60: "abnormalRT60"
        }
    }

    /// Details value for encoding (if applicable)
    private var detailsValue: Encodable? {
        switch self {
        case let .unsupportedFormat(details): details
        case let .configurationFailed(reason): reason
        case let .measurementFailed(reason): reason
        case let .processingFailed(reason): reason
        case let .exportFailed(reason): reason
        case let .noSignal(speaker): speaker.rawValue
        case let .clipping(speaker): speaker.rawValue
        case let .lowSNR(speaker, snr): "\(speaker.rawValue),\(snr)"
        case let .invalidTiming(speaker): speaker.rawValue
        case let .abnormalRT60(speaker, rt60): "\(speaker.rawValue),\(rt60)"
        case .noHDMIDevice, .permissionDenied, .deviceBusy, .engineNotRunning, .noMicrophoneAccess:
            nil
        }
    }
}
