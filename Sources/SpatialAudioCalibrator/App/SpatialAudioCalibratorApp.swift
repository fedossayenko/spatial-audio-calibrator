import Foundation

/// Spatial Audio Calibrator - Main Entry Point
///
/// A precision acoustic calibration tool for 5.1.1 spatial audio systems.
/// Measures individual speaker responses and extracts Room Impulse Responses
/// using logarithmic sine sweeps and spectral deconvolution.
@main
public struct SpatialAudioCalibratorApp {
    // MARK: Public

    public static func main() {
        print("Spatial Audio Calibrator v1.0.0")
        print("================================\n")

        // List available devices
        listDevices()

        // Run system check
        print("\nSystem Verification")
        print("-------------------")

        let calibrator = AudioCalibrator(config: .default)

        do {
            let status = try calibrator.verifySystemConfiguration()

            print("Output Device: \(status.outputDevice?.name ?? "Not found")")
            print("HDMI Connected: \(status.hasHDMI ? "Yes" : "No")")
            print("5.1 Support: \(status.supports51 ? "Yes" : "No")")
            print("Microphone Access: \(status.microphoneAccess ? "Granted" : "Denied")")
            print("Latency: \(String(format: "%.2f", status.latencyMs)) ms")

            if !status.isReady {
                print("\n⚠️  Issues detected:")
                for issue in status.issues {
                    print("  - \(issue)")
                }
                exit(1)
            }

            print("\n✅ System ready for calibration")
            print("\nTo start calibration, run the GUI application or use the API.")

        } catch {
            print("❌ Verification failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    // MARK: Private

    private static func listDevices() {
        print("Available Audio Devices")
        print("-----------------------\n")

        let outputDevices = AudioDeviceManager.getOutputDevices()
        let inputDevices = AudioDeviceManager.getInputDevices()

        print("Output Devices:")
        for deviceID in outputDevices {
            if let info = AudioDeviceInfo(deviceID: deviceID) {
                let hdmiMarker = info.isHDMI ? " [HDMI]" : ""
                print("  • \(info.name)\(hdmiMarker)")
                print("    Transport: \(info.transportTypeName)")
                if let rate = info.sampleRate {
                    print("    Sample Rate: \(Int(rate)) Hz")
                }
                if let channels = info.channelCount {
                    print("    Channels: \(channels)")
                }
            }
        }

        print("\nInput Devices:")
        for deviceID in inputDevices {
            if let info = AudioDeviceInfo(deviceID: deviceID) {
                print("  • \(info.name)")
                print("    Transport: \(info.transportTypeName)")
            }
        }
    }
}
