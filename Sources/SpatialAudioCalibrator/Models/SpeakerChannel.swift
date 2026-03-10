import CoreAudio

/// Enumeration of supported 5.1 surround speaker channels.
///
/// Channel indices follow the MPEG 5.1-A layout used by Core Audio:
/// - Channels 0-1: Front left/right
/// - Channel 2: Center
/// - Channel 3: LFE (subwoofer)
/// - Channels 4-5: Rear left/right (surround)
public enum SpeakerChannel: Int, CaseIterable, Identifiable, Codable {
    case frontLeft = 0
    case frontRight = 1
    case center = 2
    case lfe = 3
    case rearLeft = 4
    case rearRight = 5

    // MARK: Public

    /// Typical measurement order (front to back)
    public static var measurementOrder: [SpeakerChannel] {
        [.frontLeft, .frontRight, .center, .lfe, .rearLeft, .rearRight]
    }

    public var id: Int {
        rawValue
    }

    /// Human-readable display name for UI
    public var displayName: String {
        switch self {
        case .frontLeft: "Front Left"
        case .frontRight: "Front Right"
        case .center: "Center / Up-firing"
        case .lfe: "Subwoofer (LFE)"
        case .rearLeft: "Rear Left"
        case .rearRight: "Rear Right"
        }
    }

    /// Short abbreviation for compact display
    public var shortName: String {
        switch self {
        case .frontLeft: "FL"
        case .frontRight: "FR"
        case .center: "C"
        case .lfe: "LFE"
        case .rearLeft: "RL"
        case .rearRight: "RR"
        }
    }

    /// Core Audio channel label for this speaker
    public var coreAudioLabel: AudioChannelLabel {
        switch self {
        case .frontLeft: kAudioChannelLabel_Left
        case .frontRight: kAudioChannelLabel_Right
        case .center: kAudioChannelLabel_Center
        case .lfe: kAudioChannelLabel_LFEScreen
        case .rearLeft: kAudioChannelLabel_LeftSurround
        case .rearRight: kAudioChannelLabel_RightSurround
        }
    }

    /// Speaker group for organization
    public var group: SpeakerGroup {
        switch self {
        case .frontLeft, .frontRight:
            .frontStereo
        case .center:
            .center
        case .lfe:
            .subwoofer
        case .rearLeft, .rearRight:
            .rearSurround
        }
    }
}

/// Speaker group classification
public enum SpeakerGroup: String, CaseIterable, Codable {
    case frontStereo = "Front Stereo"
    case center = "Center"
    case subwoofer = "Subwoofer"
    case rearSurround = "Rear Surround"
}
