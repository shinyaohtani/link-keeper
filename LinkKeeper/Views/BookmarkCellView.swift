import AppKit

/// ブックマーク行のセルビュー。ファビコン + タイトル（編集可能）を表示する。
class BookmarkCellView: NSTableCellView {
    let iconView = NSImageView()
    let titleField = NSTextField()

    var onTitleEdited: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private static let iconSize: CGFloat = 18

    private func setup() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        addSubview(iconView)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.isEditable = false   // 通常は編集不可
        titleField.isSelectable = false
        titleField.focusRingType = .none
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.font = NSFont.systemFont(ofSize: 13)
        titleField.delegate = self
        addSubview(titleField)

        self.imageView = iconView
        self.textField = titleField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with node: BookmarkNode) {
        titleField.stringValue = node.title

        if node.isFolder {
            iconView.image = Self.renderSymbol("folder.fill", color: .systemBlue)
            iconView.contentTintColor = nil
        } else if let data = node.faviconData, let img = NSImage(data: data) {
            iconView.image = img
            iconView.contentTintColor = nil
        } else {
            iconView.image = Self.renderSymbol("globe", color: .secondaryLabelColor)
            iconView.contentTintColor = nil
        }

        applyColorTag(node.colorTag)
    }

    func applyColorTag(_ tag: Int) {
        wantsLayer = true
        switch tag {
        case 1: layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
        case 2: layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.15).cgColor
        case 3: layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.15).cgColor
        case 4: layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
        case 5: layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
        case 6: layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.15).cgColor
        case 7: layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.15).cgColor
        default: layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    /// SF Symbol を iconSize x iconSize のラスター画像にレンダリング。
    /// 高さ基準でスケーリングし、横はみ出し分はクリップ（folder.fill 等の横長シンボル対策）。
    private static func renderSymbol(_ name: String, color: NSColor) -> NSImage {
        let s = iconSize
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .medium)) {
            let symSize = symbol.size
            // 高さがボックスを埋めるようスケーリング
            let scale = s / symSize.height
            let drawW = symSize.width * scale
            let drawRect = NSRect(x: (s - drawW) / 2, y: 0, width: drawW, height: s)
            symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            // 色を上乗せ
            color.set()
            NSRect(origin: .zero, size: NSSize(width: s, height: s)).fill(using: .sourceAtop)
        }
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    /// 編集モードを開始する
    func beginEditing() {
        titleField.isEditable = true
        titleField.isSelectable = true
        window?.makeFirstResponder(titleField)
    }

    private func endEditing() {
        titleField.isEditable = false
        titleField.isSelectable = false
    }
}

// MARK: - NSTextFieldDelegate

extension BookmarkCellView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        let newTitle = titleField.stringValue
        endEditing()
        if !newTitle.isEmpty {
            onTitleEdited?(newTitle)
        }
    }
}

// MARK: - NSImage Tint Helper

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = self.copy() as! NSImage
        img.lockFocus()
        color.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
