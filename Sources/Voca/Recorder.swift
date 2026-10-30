import AVFoundation

final class Recorder {
    private var recorder: AVAudioRecorder?
    private let file = FileManager.default.temporaryDirectory.appendingPathComponent("voca-recording.m4a")

    func start() -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let r = try? AVAudioRecorder(url: file, settings: settings) else { return false }
        r.isMeteringEnabled = true
        recorder = r
        return r.record()
    }

    /// 0...1 loudness for the waveform animation.
    func level() -> CGFloat {
        guard let r = recorder else { return 0 }
        r.updateMeters()
        let db = r.averagePower(forChannel: 0) // -160...0
        return CGFloat(max(0, min(1, (db + 50) / 45)))
    }

    /// Returns the file and its duration in seconds.
    func stop() -> (URL, TimeInterval)? {
        guard let r = recorder else { return nil }
        let duration = r.currentTime
        r.stop()
        recorder = nil
        return (file, duration)
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
    }
}
