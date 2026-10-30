import AVFoundation
import CoreAudio

final class Recorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    /// Measured on real recordings: speech peaks at -14…-25 dB, a silent clip at -56 dB.
    static let silenceDB: Float = -40
    /// Measured: a Bluetooth headset mic delivers sound after ~1.3-1.9 s (and drops the headphones to call quality);
    /// the built-in mic after ~0.1 s. So the built-in mic is the default when the Mac has one.
    var useBuiltInMic = true

    private var session: AVCaptureSession?
    private var output: AVCaptureAudioFileOutput?
    private var startedAt = Date()
    private(set) var peakDB: Float = -160
    private var finished: ((URL?) -> Void)?

    static func builtInMic() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
            .devices.first { $0.transportType == Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn) }
    }

    func start() -> Bool {
        let device = (useBuiltInMic ? Self.builtInMic() : nil) ?? AVCaptureDevice.default(for: .audio)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        let session = AVCaptureSession()
        let output = AVCaptureAudioFileOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        // Lossless 16 kHz mono: what Whisper uses internally (~1.9 MB per minute). Set after addOutput, or it's ignored.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        session.startRunning()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voca-\(UUID().uuidString).wav")
        output.startRecording(to: url, outputFileType: .wav, recordingDelegate: self)
        self.session = session
        self.output = output
        startedAt = Date()
        peakDB = -160
        return true
    }

    /// 0...1 loudness for the waveform animation; also tracks the loudest moment for the silence check.
    func level() -> CGFloat {
        guard let ch = output?.connections.first?.audioChannels.first else { return 0 }
        let db = ch.averagePowerLevel
        peakDB = max(peakDB, db)
        return CGFloat(max(0, min(1, (db + 50) / 45)))
    }

    /// Calls back on the main queue with the file and its duration, or nil when nothing louder than silence was heard.
    func stop(_ done: @escaping ((URL, TimeInterval)?) -> Void) {
        let duration = Date().timeIntervalSince(startedAt)
        let silent = peakDB < Self.silenceDB
        finish { url in
            guard let url else { return done(nil) }
            if silent { try? FileManager.default.removeItem(at: url); return done(nil) }
            done((url, duration))
        }
    }

    func cancel() {
        finish { url in if let url { try? FileManager.default.removeItem(at: url) } }
    }

    private func finish(_ then: @escaping (URL?) -> Void) {
        guard let output, output.isRecording else { session?.stopRunning(); session = nil; return then(nil) }
        finished = then
        output.stopRecording() // the file is complete once the delegate fires
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [self] in
            session?.stopRunning()
            session = nil
            self.output = nil
            let ok = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
            finished?(ok ? url : nil)
            finished = nil
        }
    }
}
