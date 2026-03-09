import Foundation

/// State machine for the calibration process.
///
/// The calibration process follows a linear progression through these states:
/// `idle` → `initializing` → `verifying` → `ready` → `measuring` → `processing` → `completed`
///
/// Any state can transition to `error` if a failure occurs.
public enum CalibrationState: Equatable {
    /// Initial state, no calibration in progress
    case idle

    /// Setting up audio hardware and engine
    case initializing

    /// Verifying system configuration and permissions
    case verifying

    /// Ready to begin calibration
    case ready

    /// Currently measuring a specific speaker
    case measuring(SpeakerChannel)

    /// Processing recorded audio for a speaker
    case processing(SpeakerChannel)

    /// All measurements completed successfully
    case completed

    /// An error occurred during calibration
    case error(CalibrationError)

    // MARK: - Equatable Conformance

    public static func == (lhs: CalibrationState, rhs: CalibrationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.initializing, .initializing),
             (.verifying, .verifying),
             (.ready, .ready),
             (.completed, .completed):
            return true
        case (.measuring(let l), .measuring(let r)):
            return l == r
        case (.processing(let l), .processing(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l.errorDescription == r.errorDescription
        default:
            return false
        }
    }

    // MARK: - Properties

    /// Whether calibration is currently in progress
    public var isActive: Bool {
        switch self {
        case .idle, .ready, .completed, .error:
            return false
        case .initializing, .verifying, .measuring, .processing:
            return true
        }
    }

    /// Current speaker being measured or processed, if any
    public var currentSpeaker: SpeakerChannel? {
        switch self {
        case .measuring(let speaker), .processing(let speaker):
            return speaker
        default:
            return nil
        }
    }

    /// User-friendly description of current state
    public var description: String {
        switch self {
        case .idle:
            return "Ready to begin calibration"
        case .initializing:
            return "Initializing audio system..."
        case .verifying:
            return "Verifying configuration..."
        case .ready:
            return "System ready for calibration"
        case .measuring(let speaker):
            return "Measuring \(speaker.displayName)..."
        case .processing(let speaker):
            return "Processing \(speaker.displayName)..."
        case .completed:
            return "Calibration complete"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
}

/// Progress information for the overall calibration session
public struct CalibrationProgress: Equatable {
    /// Index of current speaker (0-based)
    public let currentSpeakerIndex: Int

    /// Total number of speakers to measure
    public let totalSpeakers: Int

    /// Speaker currently being measured
    public let currentSpeaker: SpeakerChannel

    /// Progress within current measurement (0.0 - 1.0)
    public let measurementProgress: Double

    /// Overall progress across all measurements (0.0 - 1.0)
    public var overallProgress: Double {
        let baseProgress = Double(currentSpeakerIndex) / Double(totalSpeakers)
        let speakerContribution = measurementProgress / Double(totalSpeakers)
        return baseProgress + speakerContribution
    }

    public init(
        currentSpeakerIndex: Int,
        totalSpeakers: Int,
        currentSpeaker: SpeakerChannel,
        measurementProgress: Double = 0
    ) {
        self.currentSpeakerIndex = currentSpeakerIndex
        self.totalSpeakers = totalSpeakers
        self.currentSpeaker = currentSpeaker
        self.measurementProgress = measurementProgress
    }
}
