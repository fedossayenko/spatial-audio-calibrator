import Accelerate
import AVFAudio
import Foundation

/// Exports audio samples as WAV files.
public enum WAVEExporter {
    // MARK: Public

    /// Export audio samples as a 32-bit float WAV file
    public static func export(samples: [Float], sampleRate: Double, to url: URL) throws {
        let fileManager = FileManager.default

        // Delete existing file if present
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        // Create WAV file
        let data = try createWAVData(samples: samples, sampleRate: sampleRate)
        try data.write(to: url)
    }

    // MARK: Private

    private static func createWAVData(samples: [Float], sampleRate: Double) throws -> Data {
        var data = Data()

        let sampleRateValue = UInt32(sampleRate)
        let bitsPerSample: UInt16 = 32
        let numChannels: UInt16 = 1
        let byteRate = UInt32(sampleRateValue * UInt32(numChannels) * UInt32(bitsPerSample / 8))
        let blockAlign = UInt16(numChannels * bitsPerSample / 8)
        let dataSize = UInt32(samples.count * Int(bitsPerSample / 8))

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize)) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16)) { Array($0) }) // Chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(3)) { Array($0) }) // Audio format (3 = IEEE float)
        data.append(contentsOf: withUnsafeBytes(of: numChannels) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRateValue) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize) { Array($0) })

        // Sample data
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample) { Array($0) })
        }

        return data
    }
}
