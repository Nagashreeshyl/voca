import Foundation
import Speech

enum Transcriber {
    /// Groq Whisper first; Apple on-device recognition if Groq fails or there is no network.
    static func transcribe(_ file: URL, config: Config) async throws -> (String, String) {
        if !config.groqKey.isEmpty {
            do { return (try await groq(file, key: config.groqKey, model: config.whisperModel, vocabulary: config.vocabulary), "Groq Whisper") }
            catch { NSLog("Voca: Groq STT failed: \(error.localizedDescription)") }
        }
        return (try await apple(file), "on-device")
    }

    static func groq(_ file: URL, key: String, model: String, vocabulary: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!, timeoutInterval: 30)
        let boundary = "voca-\(UUID().uuidString)"
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var fields = [("model", model), ("language", "en"), ("response_format", "verbose_json"), ("temperature", "0")]
        // Whisper's prompt biases spelling toward these words (names, jargon).
        if !vocabulary.isEmpty { fields.append(("prompt", vocabulary)) }
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let mime = file.pathExtension == "wav" ? "audio/wav" : "audio/m4a"
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(try Data(contentsOf: file))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (data, resp) = try await URLSession.shared.upload(for: req, from: body)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw VocaError("HTTP \(code): \(String(decoding: data.prefix(200), as: UTF8.self))") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw VocaError("unexpected Whisper response") }
        return speech(from: obj)
    }

    /// Keeps only segments Whisper believes are speech; drops its classic hallucinations on silence ("Thank you.").
    static func speech(from obj: [String: Any]) -> String {
        guard let segments = obj["segments"] as? [[String: Any]] else {
            return (obj["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Same rule Whisper itself uses to skip silent windows.
        return segments.filter {
            !(($0["no_speech_prob"] as? Double ?? 0) > 0.6 && ($0["avg_logprob"] as? Double ?? 0) < -1)
        }
        .compactMap { $0["text"] as? String }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func apple(_ file: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable
        else { throw VocaError("on-device speech recognition unavailable") }
        let req = SFSpeechURLRecognitionRequest(url: file)
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        req.addsPunctuation = true
        return try await withCheckedThrowingContinuation { cont in
            var done = false
            recognizer.recognitionTask(with: req) { result, error in
                guard !done else { return }
                if let error { done = true; cont.resume(throwing: error) }
                else if let result, result.isFinal { done = true; cont.resume(returning: result.bestTranscription.formattedString) }
            }
        }
    }
}
