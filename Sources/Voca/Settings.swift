import AppKit
import SwiftUI

// Not @State: Command Line Tools ship without the SwiftUI macro plugin.
final class KeysModel: ObservableObject {
    @Published var groq = ""
    @Published var openrouter = ""
    @Published var opencode = ""
    @Published var saved = false
}

struct KeysView: View {
    @ObservedObject var model: KeysModel
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voca API Keys").font(.title2.bold())
                    Text("All providers have free tiers. Keys stay on this Mac.").foregroundStyle(.secondary)
                }
            }
            field("Groq (required)", "gsk_…", "https://console.groq.com/keys", $model.groq,
                  "Speech-to-text and the main AI.")
            field("OpenRouter (optional backup)", "sk-or-…", "https://openrouter.ai/settings/keys", $model.openrouter,
                  "Used when Groq is busy or down.")
            field("OpenCode Zen (optional backup)", "oc_sk_…", "https://opencode.ai/zen", $model.opencode,
                  "Last fallback.")
            HStack {
                if model.saved { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.groq.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func field(_ title: String, _ placeholder: String, _ link: String, _ text: Binding<String>, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Link("Get a key ↗", destination: URL(string: link)!).font(.callout)
            }
            SecureField(placeholder, text: text).textFieldStyle(.roundedBorder)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}

final class KeysWindow {
    private var window: NSWindow?
    private let model = KeysModel()

    func show() {
        let c = Config.load()
        model.groq = c.values["groqKey"] ?? ""
        model.openrouter = c.values["openrouterKey"] ?? ""
        model.opencode = c.values["opencodeKey"] ?? ""
        model.saved = false
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: KeysView(model: model) { [weak self] in self?.save() })
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func save() {
        Config.save(["groqKey": model.groq, "openrouterKey": model.openrouter, "opencodeKey": model.opencode])
        model.saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.window?.close() }
    }
}
