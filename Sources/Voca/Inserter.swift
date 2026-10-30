import AppKit

enum Inserter {
    /// Pastes text into the focused app, then puts the user's clipboard back.
    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let d = item.data(forType: type) { copy.setData(d, forType: type) } }
            return copy
        }
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for isDown in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: isDown)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }

        // Slow apps (Electron, browsers) read the clipboard late; restoring too early pastes the old contents.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            pb.clearContents()
            if !saved.isEmpty { pb.writeObjects(saved) }
        }
    }
}
