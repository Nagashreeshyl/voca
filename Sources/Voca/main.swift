import AppKit
import AVFoundation
import Speech
import ServiceManagement

// shortcut: API keys are plaintext in a chmod-600 file (like most CLIs); move them to Keychain if users ask for it.
struct Config {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/voca/config.json")
    static let defaults: [String: String] = [
        "groqKey": "", "openrouterKey": "", "opencodeKey": "",
        "whisperModel": "whisper-large-v3-turbo",
        "groqModel": "openai/gpt-oss-120b",
        "openrouterModel": "openrouter/free",
        "opencodeModel": "deepseek-v4.1-flash-free",
    ]
    let values: [String: String]

    static func load() -> Config {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try? JSONSerialization.data(withJSONObject: defaults, options: [.prettyPrinted, .sortedKeys])
            fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
        let file = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
        return Config(values: defaults.merging(file) { $1 })
    }

    /// Merges values into the config file, keeping other keys and the 600 permissions.
    static func save(_ updates: [String: String]) {
        let merged = load().values.merging(updates.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) { $1 }
        guard let data = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func v(_ k: String) -> String { values[k, default: ""].trimmingCharacters(in: .whitespacesAndNewlines) }
    var groqKey: String { v("groqKey") }
    var whisperModel: String { v("whisperModel") }
    var providers: [Provider] {
        [Provider(name: "Groq", baseURL: "https://api.groq.com/openai/v1", key: v("groqKey"), model: v("groqModel")),
         Provider(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", key: v("openrouterKey"), model: v("openrouterModel")),
         Provider(name: "OpenCode Zen", baseURL: "https://opencode.ai/inference/openai/v1", key: v("opencodeKey"), model: v("opencodeModel"))]
    }
}

enum Mode: String, CaseIterable {
    case auto = "Auto: type or answer"
    case dictation = "Dictation only"
    case raw = "Raw: no AI cleanup"
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotkey = Hotkey()
    private let recorder = Recorder()
    private let overlay = Overlay()
    private let answers = AnswerPanel()
    private let history = History()
    private let keys = KeysWindow()
    private var meterTimer: Timer?
    private var busy = false
    private var lastStatus = "Ready: hold Fn to dictate"

    private var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mode") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        if Config.load().groqKey.isEmpty { keys.show() } // first run
        setIcon("waveform")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        SFSpeechRecognizer.requestAuthorization { _ in }
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        NSLog("Voca: launched, accessibility trusted=\(trusted)")

        hotkey.onStart = { [weak self] in self?.startRecording() }
        hotkey.onStop = { [weak self] in self?.finishRecording() }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        hotkey.install()
    }

    // MARK: Menu (rebuilt each time it opens so history and permissions are current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        history.prune() // the app runs for days, so expire old items whenever the menu opens
        menu.addItem(NSMenuItem(title: lastStatus, action: nil, keyEquivalent: ""))
        if !AXIsProcessTrusted() {
            menu.addItem(item("⚠️ Allow Voca to type (Accessibility)…", #selector(openAccessibility)))
        }
        menu.addItem(.separator())

        if history.entries.isEmpty {
            menu.addItem(NSMenuItem(title: "No dictations yet", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem.sectionHeader(title: "Recent · kept for 24 hours"))
            for e in history.entries.prefix(10) { menu.addItem(historyItem(e)) }
            let failed = history.entries.first { $0.error != nil }
            if let failed {
                menu.addItem(item("Retry Last Failed", #selector(retry(_:)), key: "r", obj: failed.id))
            }
            let more = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
            more.submenu = NSMenu()
            for e in history.entries.dropFirst(10) { more.submenu!.addItem(historyItem(e)) }
            more.submenu!.addItem(.separator())
            more.submenu!.addItem(item("Clear History", #selector(clearHistory)))
            menu.addItem(more)
        }
        menu.addItem(.separator())

        let modeItem = NSMenuItem(title: "Mode: \(mode.rawValue)", action: nil, keyEquivalent: "")
        modeItem.submenu = NSMenu()
        for m in Mode.allCases {
            let i = item(m.rawValue, #selector(setMode(_:)), obj: m.rawValue)
            i.state = m == mode ? .on : .off
            modeItem.submenu!.addItem(i)
        }
        menu.addItem(modeItem)
        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("API Keys…", #selector(openKeys), key: ","))
        let adv = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
        adv.submenu = NSMenu()
        adv.submenu!.addItem(item("Edit Models (JSON)…", #selector(openConfig)))
        adv.submenu!.addItem(item("Show History Folder", #selector(openHistoryFolder)))
        menu.addItem(adv)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Voca", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", obj: Any? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.representedObject = obj
        return i
    }

    private func historyItem(_ e: HistoryEntry) -> NSMenuItem {
        let time = e.date.formatted(date: .omitted, time: .shortened)
        let text = (e.output ?? e.transcript ?? "").replacingOccurrences(of: "\n", with: " ")
        let title = e.error != nil ? "Failed: \(e.error!)" : text
        let i = NSMenuItem(title: "\(time)  \(title.count > 48 ? title.prefix(48) + "…" : title)", action: nil, keyEquivalent: "")
        let symbol = e.error != nil ? "exclamationmark.triangle" : (e.intent == Intent.question.rawValue ? "questionmark.bubble" : "text.cursor")
        i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let sub = NSMenu()
        if e.output != nil {
            if e.intent == Intent.question.rawValue { sub.addItem(item("Show Answer", #selector(showAnswer(_:)), obj: e.id)) }
            sub.addItem(item("Paste Again", #selector(pasteAgain(_:)), obj: e.id))
            sub.addItem(item("Copy", #selector(copyOutput(_:)), obj: e.id))
        }
        if let t = e.transcript, t != e.output { sub.addItem(item("Copy What I Said", #selector(copyTranscript(_:)), obj: e.id)) }
        if FileManager.default.fileExists(atPath: e.audio.path) {
            sub.addItem(item("Retry", #selector(retry(_:)), obj: e.id))
        }
        i.submenu = sub
        return i
    }

    private func entry(_ sender: NSMenuItem) -> HistoryEntry? {
        history.entries.first { $0.id == sender.representedObject as? UUID }
    }

    @objc private func pasteAgain(_ s: NSMenuItem) { if let t = entry(s)?.output { deliver(t) } }
    @objc private func copyOutput(_ s: NSMenuItem) { if let t = entry(s)?.output { copy(t) } }
    @objc private func copyTranscript(_ s: NSMenuItem) { if let t = entry(s)?.transcript { copy(t) } }
    @objc private func showAnswer(_ s: NSMenuItem) {
        if let e = entry(s), let o = e.output { answers.show(question: e.transcript ?? "", answer: o, provider: e.provider ?? "") }
    }
    @objc private func retry(_ s: NSMenuItem) {
        guard !busy, let e = entry(s) else { return }
        // Let the menu close and focus return to the previous app before pasting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.run(e) }
    }
    @objc private func clearHistory() { history.clear() }
    @objc private func setMode(_ s: NSMenuItem) { if let m = Mode(rawValue: s.representedObject as? String ?? "") { mode = m } }
    @objc private func openKeys() { keys.show() }
    @objc private func openConfig() { NSWorkspace.shared.open(Config.url) }
    @objc private func openHistoryFolder() { NSWorkspace.shared.open(History.dir) }
    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { lastStatus = "Launch at Login failed: \(error.localizedDescription)" }
    }

    // MARK: Recording

    private func setIcon(_ symbol: String, tint: NSColor? = nil) {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Voca")
        img?.isTemplate = tint == nil
        statusItem.button?.image = img
        statusItem.button?.contentTintColor = tint
    }

    private func startRecording() {
        guard !busy else { return }
        if Config.load().groqKey.isEmpty { keys.show(); return }
        guard recorder.start() else { return }
        setIcon("mic.fill", tint: .systemRed)
        overlay.show(.listening)
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            overlay.model.push(recorder.level())
            overlay.model.locked = hotkey.locked
        }
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        setIcon("waveform")
    }

    private func cancelRecording() {
        guard meterTimer != nil else { return }
        stopMeter()
        recorder.cancel()
        overlay.hide()
    }

    private func finishRecording() {
        guard meterTimer != nil else { return }
        stopMeter()
        guard let (file, duration) = recorder.stop(), duration > 0.4 else { overlay.hide(); return }
        run(history.add(recording: file))
    }

    /// Transcribe → AI → type or answer. Used for new recordings and retries.
    private func run(_ start: HistoryEntry) {
        var e = start
        busy = true
        overlay.show(.thinking)
        let config = Config.load() // re-read so config edits apply without relaunch
        let mode = self.mode
        Task { @MainActor in
            defer { busy = false; history.update(e) }
            do {
                let (transcript, stt) = try await Transcriber.transcribe(e.audio, config: config)
                guard !transcript.isEmpty else { throw VocaError("heard nothing") }
                e.transcript = transcript
                let r = mode == .raw
                    ? LLMResult(intent: .dictation, text: transcript, provider: "raw")
                    : await LLM.process(transcript, providers: config.providers, forceDictation: mode == .dictation)
                e.output = r.text; e.intent = r.intent.rawValue; e.provider = r.provider; e.error = nil
                lastStatus = "Last: \(r.intent.rawValue) · \(stt) → \(r.provider)"
                overlay.hide()
                switch r.intent {
                case .dictation: deliver(r.text)
                case .question: answers.show(question: transcript, answer: r.text, provider: r.provider)
                }
            } catch {
                e.error = error.localizedDescription
                lastStatus = "Failed: retry from the menu"
                NSSound.beep()
                overlay.flash("exclamationmark.triangle.fill", "Couldn't transcribe. Retry from menu")
            }
        }
    }

    /// Types into the focused app, or copies when Voca isn't allowed to type.
    private func deliver(_ text: String) {
        NSLog("Voca: deliver \(text.count) chars, accessibility trusted=\(AXIsProcessTrusted())")
        if AXIsProcessTrusted() {
            Inserter.insert(text)
        } else {
            copy(text)
            overlay.flash("doc.on.clipboard.fill", "Copied. Allow Accessibility to auto-type")
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum SelfTest {
    static func run() async {
        // JSON parsing
        precondition(LLM.parse(#"{"intent":"dictation","text":"Hello, world."}"#)! == (.dictation, "Hello, world."))
        precondition(LLM.parse("```json\n{\"intent\":\"question\",\"text\":\"Canberra.\"}\n```")! == (.question, "Canberra."))
        precondition(LLM.parse("Sure! {\"intent\":\"QUESTION\",\"text\":\" x \"}")! == (.question, "x"))
        precondition(LLM.parse("no json here") == nil)
        precondition(LLM.parse(#"{"intent":"other","text":"x"}"#) == nil)
        precondition(LLM.parse(#"{"intent":"dictation","text":""}"#) == nil)

        // Provider fallback order
        let ps = [Provider(name: "A", baseURL: "", key: "k", model: ""),
                  Provider(name: "B", baseURL: "", key: "", model: ""),   // no key: skipped
                  Provider(name: "C", baseURL: "", key: "k", model: "")]
        var tried: [String] = []
        let r1 = await LLM.process("hi", providers: ps) { p, _ in
            tried.append(p.name)
            if p.name == "A" { throw VocaError("429") }
            return #"{"intent":"dictation","text":"Hi."}"#
        }
        precondition(tried == ["A", "C"] && r1.provider == "C" && r1.text == "Hi.")
        let r2 = await LLM.process("raw words", providers: ps) { _, _ in "garbage" }
        precondition(r2.provider == "raw" && r2.text == "raw words" && r2.intent == .dictation)

        // Hotkey state machine
        var log: [String] = []
        let h = Hotkey()
        h.onStart = { log.append("start") }; h.onStop = { log.append("stop") }; h.onCancel = { log.append("cancel") }
        h.down(at: 0); h.up(at: 1.0)                                   // hold
        precondition(log == ["start", "stop"]); log = []
        h.down(at: 10); h.up(at: 10.1)                                 // quick tap alone
        precondition(log == ["start", "cancel"]); log = []
        h.down(at: 20); h.up(at: 20.1); h.down(at: 20.3); h.up(at: 20.4) // double tap: locked
        precondition(h.locked && log == ["start", "cancel", "start"]); log = []
        h.down(at: 30); h.up(at: 30.1)                                 // tap to stop locked
        precondition(!h.locked && log == ["stop"])

        print("selftest OK")
    }
}

if CommandLine.arguments.contains("--selftest") {
    Task { await SelfTest.run(); exit(0) }
    dispatchMain()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
