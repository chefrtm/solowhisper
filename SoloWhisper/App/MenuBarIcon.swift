import SwiftUI
import AppKit

enum MenuBarIcon {
    static func image(isRecording: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let bars: [(x: CGFloat, height: CGFloat)] = [
                (2, 8),
                (6, 14),
                (10, 10),
                (14, 6)
            ]

            for bar in bars {
                let barRect = NSRect(
                    x: bar.x,
                    y: (rect.height - bar.height) / 2,
                    width: 3,
                    height: bar.height
                )
                let path = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)

                if isRecording {
                    NSColor.black.setFill()
                    path.fill()
                } else {
                    NSColor.black.setStroke()
                    path.lineWidth = 1.2
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
