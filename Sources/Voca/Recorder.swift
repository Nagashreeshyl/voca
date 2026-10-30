import AVFoundation

final class Recorder {
    /// Measured on real recordings: speech peaks at -14…-25 dB, a silent clip at -56 dB.
    static let silenceDB: Float = -40
    private var recorder: AVAudioRecorder?
    private(set) var peakDB: Float = -160

    func start() -> Bool {
        // Lossless 16 kHz mono PCM: what Whisper uses internally, so no codec artifacts (~1.9 MB per minute).
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("voca-\(UUID().uuidString).wav")
        guard let r = try? AVAudioRecorder(url: file, settings: settings) else { return false }
        r.isMeteringEnabled = true
        recorder = r
        peakDB = -160
        return r.record()
    }

    /// 0...1 loudness for the waveform animation; also tracks the loudest moment for the silence check.
    func level() -> CGFloat {
        guard let r = recorder else { return 0 }
        r.updateMeters()
        let db = r.averagePower(forChannel: 0) // -160...0
        peakDB = max(peakDB, db)
        return CGFloat(max(0, min(1, (db + 50) / 45)))
    }

    /// Returns the file and its duration, or nil (and deletes the file) when nothing louder than silence was heard.
    func stop() -> (URL, TimeInterval)? {
        guard let r = recorder else { return nil }
        let duration = r.currentTime
        r.stop()
        recorder = nil
        if peakDB < Self.silenceDB {
            r.deleteRecording()
            return nil
        }
        return (r.url, duration)
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
    }
}
