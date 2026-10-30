import AppKit
import SwiftUI

// MARK: - Listening pill

final class OverlayModel: ObservableObject {
    enum Phase: Equatable { case hidden, listening, thinking, message(icon: String, text: String) }
    static let barCount = 28
    @Published var phase: Phase = .hidden
    @Published var levels = [CGFloat](repeating: 0, count: barCount)
    @Published var locked = false

    func push(_ level: CGFloat) {
        levels.removeFirst()
        levels.append(level)
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        let visible = model.phase != .hidden
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .symbolEffect(.pulse, isActive: model.phase == .thinking)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16)
            if case .message(_, let text) = model.phase {
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1).fixedSize()
                    .frame(height: 28)
            } else {
                Group {
                    if model.phase == .thinking { ThinkingWave() } else { bars }
                }
                .frame(width: 150, height: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(.black.opacity(0.25)), in: .capsule)
        .scaleEffect(visible ? 1 : 0.6)
        .opacity(visible ? 1 : 0)
        .blur(radius: visible ? 0 : 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: visible)
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        switch model.phase {
        case .thinking: "sparkles"
        case .message(let icon, _): icon
        default: model.locked ? "lock.fill" : "mic.fill"
        }
    }

    private var bars: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { i, level in
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .top, endPoint: .bottom))
                    // Taper the edges so the waveform reads as a soft shape.
                    .frame(width: 3, height: 3 + level * 25 * taper(i))
            }
        }
        .animation(.spring(response: 0.16, dampingFraction: 0.55), value: model.levels)
    }

    private func taper(_ i: Int) -> CGFloat {
        let mid = CGFloat(OverlayModel.barCount - 1) / 2
        return 1 - abs(CGFloat(i) - mid) / mid * 0.55
    }
}

/// Flowing sine wave shown while transcribing and thinking.
struct ThinkingWave: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<OverlayModel.barCount, id: \.self) { i in
                    let v = (sin(t * 5 + Double(i) * 0.45) + 1) / 2
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(0.9), .purple.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 3, height: 4 + v * 14)
                        .opacity(0.45 + v * 0.55)
                }
            }
        }
    }
}

final class Overlay {
    let model = OverlayModel()
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 70),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
    }

    func show(_ phase: OverlayModel.Phase) {
        if model.phase == .hidden {
            model.levels = .init(repeating: 0, count: OverlayModel.barCount)
            if let screen = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: screen.midX - panel.frame.width / 2, y: screen.minY + 40))
            }
            panel.orderFrontRegardless()
        }
        model.phase = phase
    }

    /// Briefly shows a status message in the pill.
    func flash(_ icon: String, _ text: String) {
        let phase = OverlayModel.Phase.message(icon: icon, text: text)
        show(phase)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            if model.phase == phase { hide() }
        }
    }

    func hide() {
        model.phase = .hidden
        model.locked = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
            if model.phase == .hidden { panel.orderOut(nil) }
        }
    }
}

// MARK: - Answer popup

struct AnswerView: View {
    let question: String
    let answer: String
    let provider: String
    let close: () -> Void
    // Not @State: Command Line Tools ship without the SwiftUI macro plugin.
    @ObservedObject private var copy = CopyState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(question).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
            }
            ScrollView {
                Text(Self.markdown(answer))
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("via \(provider) · Esc to close").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(answer, forType: .string)
                    copy.copied = true
                } label: { Label(copy.copied ? "Copied" : "Copy", systemImage: copy.copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.glass)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(10)
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

final class CopyState: ObservableObject { @Published var copied = false }

final class AnswerPanel {
    private var panel: NSPanel?
    private var escMonitor: Any?

    func show(question: String, answer: String, provider: String) {
        close()
        let width: CGFloat = 460
        let textHeight = (answer as NSString).boundingRect(
            with: NSSize(width: width - 56, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: [.font: NSFont.systemFont(ofSize: 13)]).height
        let height = min(max(textHeight, 40), 340) + 130

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: AnswerView(question: question, answer: answer, provider: provider) { [weak self] in self?.close() })

        // Open near the mouse, kept on screen.
        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)!.visibleFrame
        let x = min(max(mouse.x - width / 2, screen.minX + 8), screen.maxX - width - 8)
        let y = min(max(mouse.y - height - 16, screen.minY + 8), screen.maxY - height - 8)
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; p.animator().alphaValue = 1 }
        panel = p

        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { DispatchQueue.main.async { self?.close() } }
        }
    }

    func close() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }
}
