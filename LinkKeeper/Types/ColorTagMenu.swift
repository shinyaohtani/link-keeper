import AppKit

/// カラーラベルメニューを構築する値型。コンテキストメニュー・メインメニューで共用。
struct ColorTagMenu {
    let currentTag: Int
    let target: AnyObject?
    let action: Selector

    var menu: NSMenu {
        let menu = NSMenu()
        let defs: [(String, NSColor?)] = [
            ("なし",   nil),
            ("レッド",   .systemRed),
            ("オレンジ", .systemOrange),
            ("イエロー", .systemYellow),
            ("グリーン", .systemGreen),
            ("ブルー",   .systemBlue),
            ("パープル", .systemPurple),
            ("グレイ",   .systemGray),
        ]
        for (idx, (name, color)) in defs.enumerated() {
            let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
            item.tag = idx
            item.target = target
            if idx == currentTag { item.state = .on }
            if let color = color { item.image = colorDot(color) }
            menu.addItem(item)
        }
        return menu
    }

    private func colorDot(_ color: NSColor) -> NSImage {
        let s: CGFloat = 12
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: s, height: s)).fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
