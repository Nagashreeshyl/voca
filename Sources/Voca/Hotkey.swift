import AppKit

/// Fn (Globe): hold to talk, double-tap to lock recording on, tap again to stop.
/// Holding Shift at any point during a recording turns it into a question (answer popup instead of typing).
final class Hotkey {
    static let fn: UInt16 = 63
    static let tapMax: TimeInterval = 0.25      // shorter than this = a tap, not a hold
    static let doubleTapGap: TimeInterval = 0.35

    var onStart: () -> Void = {}
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}

    private(set) var locked = false
    private(set) var wantsAnswer = false
    private var isDown = false
    private var downAt: TimeInterval = 0
    private var lastTapUp: TimeInterval?
    private var suppressUp = false
    private var monitors: [Any] = []

    func install() {
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] in self?.handle($0) } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] in self?.handle($0); return $0 } as Any)
    }

    private func handle(_ e: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        if e.type == .keyDown {
            // Fn used as a modifier (e.g. Fn+arrow, Fn+F-keys) is not dictation.
            if isDown && !locked { isDown = false; suppressUp = true; onCancel() }
            return
        }
        if isDown || locked, e.modifierFlags.contains(.shift) { wantsAnswer = true }
        guard e.keyCode == Self.fn else { return }
        if e.modifierFlags.contains(.function) && !isDown {
            down(at: now)
            if e.modifierFlags.contains(.shift) { wantsAnswer = true } // Shift pressed before Fn
        }
        else if !e.modifierFlags.contains(.function) && isDown { up(at: now) }
        else if !e.modifierFlags.contains(.function) && suppressUp { suppressUp = false }
    }

    func down(at now: TimeInterval) {
        isDown = true
        if locked { locked = false; suppressUp = true; onStop(); return }
        let isDouble = lastTapUp.map { now - $0 < Self.doubleTapGap } ?? false
        lastTapUp = nil
        downAt = now
        wantsAnswer = false
        onStart()
        if isDouble { locked = true }
    }

    func up(at now: TimeInterval) {
        isDown = false
        if suppressUp { suppressUp = false; return }
        if locked { return }
        if now - downAt < Self.tapMax { lastTapUp = now; onCancel() } else { onStop() }
    }
}
