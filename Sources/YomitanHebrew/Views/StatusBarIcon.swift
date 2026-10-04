import AppKit

/// A compact template version of the app icon for the macOS menu bar.
/// Template rendering lets the system choose the correct color for light,
/// dark, highlighted, and accessibility appearances.
@MainActor
enum StatusBarIcon {
    static func make() -> NSImage {
        let image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: false
        ) { _ in
            NSColor.black.setStroke()

            let card = NSBezierPath(
                roundedRect: NSRect(x: 4.25, y: 5.25, width: 12, height: 10),
                xRadius: 2.1,
                yRadius: 2.1
            )
            card.lineWidth = 1.35
            card.lineCapStyle = .round
            card.lineJoinStyle = .round
            card.stroke()

            let text = NSBezierPath()
            text.move(to: NSPoint(x: 7.4, y: 11.9))
            text.line(to: NSPoint(x: 13.5, y: 11.9))
            text.move(to: NSPoint(x: 7.4, y: 8.8))
            text.line(to: NSPoint(x: 12.2, y: 8.8))
            text.lineWidth = 1.35
            text.lineCapStyle = .round
            text.stroke()

            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: 1.65, y: 1.3))
            cursor.line(to: NSPoint(x: 1.65, y: 10.25))
            cursor.line(to: NSPoint(x: 8.05, y: 5.3))
            cursor.line(to: NSPoint(x: 5.15, y: 4.75))
            cursor.line(to: NSPoint(x: 6.8, y: 1.85))
            cursor.line(to: NSPoint(x: 5.45, y: 1.05))
            cursor.line(to: NSPoint(x: 3.85, y: 4.0))
            cursor.close()

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            cursor.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.black.setStroke()
            cursor.lineWidth = 1.35
            cursor.lineCapStyle = .round
            cursor.lineJoinStyle = .round
            cursor.stroke()

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = "Yomitan Hebrew"
        return image
    }
}
