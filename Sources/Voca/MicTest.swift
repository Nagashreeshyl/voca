import AVFoundation

/// Debug: measures how fast the real Recorder hears sound on each mic, writes a report file and exits.
enum MicTest {
    static func run(out: String) -> Never {
        var report = "mic permission: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (3 = granted)\n"
        for builtIn in [false, true] {
            let r = Recorder()
            r.useBuiltInMic = builtIn
            let t0 = Date()
            let ok = r.start()
            while Date().timeIntervalSince(t0) < 4 && r.peakDB <= -100 {
                _ = r.level()
                RunLoop.current.run(until: Date() + 0.01)
            }
            let heard = r.peakDB > -100 ? Date().timeIntervalSince(t0) : -1
            while Date().timeIntervalSince(t0) < 5 { _ = r.level(); RunLoop.current.run(until: Date() + 0.01) } // keep recording
            var file = "none"
            r.stop { res in file = res.map { "\($0.0.path) \(String(format: "%.1f", $0.1))s" } ?? "silent/none" }
            while Date().timeIntervalSince(t0) < 8 && file == "none" { RunLoop.current.run(until: Date() + 0.01) }
            report += String(format: "%@: opened=%@ firstSound=%.2fs file=%@\n", builtIn ? "built-in" : "system default", ok ? "yes" : "no", heard, file)
            sleep(3)
        }
        try? report.write(toFile: out, atomically: true, encoding: .utf8)
        exit(0)
    }
}
