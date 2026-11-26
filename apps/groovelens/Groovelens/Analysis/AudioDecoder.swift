import AVFoundation

enum AudioDecoderError: LocalizedError {
    case noAudioTrack
    case unreadable
    case tooShort
    case protected

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return String(localized: "This file has no audio track.")
        case .unreadable: return String(localized: "This audio format can’t be read.")
        case .tooShort: return String(localized: "The recording is too short to chart — use at least 8 seconds.")
        case .protected: return String(localized: "This song is copy-protected (for example from Apple Music) and can’t be analyzed.")
        }
    }
}

enum AudioDecoder {
    static let analysisRate: Double = 22_050
    static let maxSeconds: Double = 12 * 60

    /// Decodes any audio or video file into mono Float32 PCM at `analysisRate`.
    static func decodeMono(url: URL, maxSeconds: Double = AudioDecoder.maxSeconds) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        if let protected = try? await asset.load(.hasProtectedContent), protected {
            throw AudioDecoderError.protected
        }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw AudioDecoderError.noAudioTrack }

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw AudioDecoderError.unreadable }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: analysisRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioDecoderError.unreadable }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: maxSeconds, preferredTimescale: 600))
        guard reader.startReading() else { throw AudioDecoderError.unreadable }

        var samples: [Float] = []
        samples.reserveCapacity(Int(analysisRate * 240))
        while reader.status == .reading {
            try Task.checkCancellation()
            guard let buffer = output.copyNextSampleBuffer() else { break }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            // Copy out (works for contiguous and non-contiguous block buffers alike).
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            var data = [Float](repeating: 0, count: count)
            let status = data.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size, destination: base)
            }
            if status == kCMBlockBufferNoErr { samples.append(contentsOf: data) }
        }
        if reader.status == .failed { throw AudioDecoderError.unreadable }
        if samples.count < Int(analysisRate * 8) { throw AudioDecoderError.tooShort }
        return samples
    }

    /// For video imports: writes the audio track to an .m4a so playback is full quality.
    static func extractAudio(fromVideo url: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioDecoderError.unreadable
        }
        try? FileManager.default.removeItem(at: destination)
        session.outputURL = destination
        session.outputFileType = .m4a
        await session.export()
        if session.status != .completed {
            throw session.error ?? AudioDecoderError.unreadable
        }
    }

    /// Writes mono Float32 samples as CAF at the analysis rate.
    static func writeCAF(_ samples: [Float], to url: URL, sampleRate: Double = AudioDecoder.analysisRate) throws {
        defer {
            // Stems can be regenerated from the original: exclude them from iCloud backup.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var u = url
            try? u.setResourceValues(values)
        }
        try? FileManager.default.removeItem(at: url)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            throw AudioDecoderError.unreadable
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 65_536
        var start = 0
        while start < samples.count {
            let n = min(chunk, samples.count - start)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { break }
            buffer.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress! + start, count: n)
            }
            try file.write(from: buffer)
            start += n
        }
    }
}
