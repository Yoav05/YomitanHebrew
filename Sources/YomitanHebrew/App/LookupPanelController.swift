import AppKit
import SwiftUI

@MainActor
final class LookupPanelController {
    private let panel: NSPanel

    init(model: LookupViewModel) {
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Yomitan Hebrew"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 620, height: 430)
        panel.contentViewController = NSHostingController(rootView: LookupView(model: model))
    }

    func show() {
        positionNearPointerIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func positionNearPointerIfNeeded() {
        guard !panel.isVisible else { return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }

        let size = panel.frame.size
        let preferred = NSPoint(x: pointer.x - size.width / 2, y: pointer.y - size.height - 20)
        let x = min(max(preferred.x, visibleFrame.minX), visibleFrame.maxX - size.width)
        let y = min(max(preferred.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
