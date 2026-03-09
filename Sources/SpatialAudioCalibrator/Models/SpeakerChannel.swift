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

    public var id: Int { rawValue }

    /// Human-readable display name for UI
    public var displayName: String {
        switch self {
        case .frontLeft: return "Front Left"
        case .frontRight: return "Front Right"
        case .center: return "Center / Up-firing"
        case .lfe: return "Subwoofer (LFE)"
        case .rearLeft: return "Rear Left"
        case .rearRight: return "Rear Right"
        }
    }

    /// Short abbreviation for compact display
    public var shortName: String {
        switch self {
        case .frontLeft: return "FL"
        case .frontRight: return "FR"
        case .center: return "C"
        case .lfe: return "LFE"
        case .rearLeft: return "RL"
        case .rearRight: return "RR"
        }
    }

    /// Core Audio channel label for this speaker
    public var coreAudioLabel: AudioChannelLabel {
        switch self {
        case .frontLeft: return kAudioChannelLabel_Left
        case .frontRight: return kAudioChannelLabel_Right
        case .center: return kAudioChannelLabel_Center
        case .lfe: return kAudioChannelLabel_LFEScreen
        case .rearLeft: return kAudioChannelLabel_LeftSurround
        case .rearRight: return kAudioChannelLabel_RightSurround
        }
    }

    /// Speaker group for organization
    public var group: SpeakerGroup {
        switch self {
        case .frontLeft, .frontRight:
            return .frontStereo
        case .center:
            return .center
        case .lfe:
            return .subwoofer
        case .rearLeft, .rearRight:
            return .rearSurround
        }
    }

    /// Typical measurement order (front to back)
    public static var measurementOrder: [SpeakerChannel] {
        [.frontLeft, .frontRight, .center, .lfe, .rearLeft, .rearRight]
    }
}

/// Speaker group classification
public enum SpeakerGroup: String, CaseIterable, Codable {
    case frontStereo = "Front Stereo"
    case center = "Center"
    case subwoofer = "Subwoofer"
    case rearSurround = "Rear Surround"
}
