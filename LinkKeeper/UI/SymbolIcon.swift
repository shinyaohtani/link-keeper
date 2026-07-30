import AppKit

/// SF Symbol をラスター画像にレンダリングする値型。
/// SF Symbols は内部余白があるため、高さ基準でフィルして favicon と同じ見た目サイズにする。
struct SymbolIcon {
    let name: String
    let color: NSColor
    let size: CGFloat

    var image: NSImage {
        let canvas = NSImage(size: NSSize(width: size, height: size))
        canvas.lockFocus()
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .medium)) {
            let symSize = symbol.size
            let scale = size / symSize.height
            let drawW = symSize.width * scale
            let drawRect = NSRect(x: (size - drawW) / 2, y: 0, width: drawW, height: size)
            symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            color.set()
            NSRect(origin: .zero, size: NSSize(width: size, height: size)).fill(using: .sourceAtop)
        }
        canvas.unlockFocus()
        canvas.isTemplate = false
        return canvas
    }
}
