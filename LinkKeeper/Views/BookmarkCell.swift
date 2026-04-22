import AppKit

/// ブックマーク行のセル。アイコン + タイトル（編集可能）。
class BookmarkCell: NSTableCellView {
    let iconView = NSImageView()
    let titleField = NSTextField()
    private let iconSize: CGFloat = 18

    var onTitleEdited: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with node: BookmarkNode) {
        titleField.stringValue = node.title
        iconView.contentTintColor = nil
        if node.isFolder {
            iconView.image = SymbolIcon(name: "folder.fill", color: .systemBlue, size: iconSize).image
        } else if let data = node.faviconData, let img = NSImage(data: data) {
            iconView.image = img
        } else {
            iconView.image = SymbolIcon(name: "globe", color: .secondaryLabelColor, size: iconSize).image
        }
        applyColorTag(node.colorTag)
    }

    func beginEditing() {
        titleField.isEditable = true
        titleField.isSelectable = true
        window?.makeFirstResponder(titleField)
    }

    // MARK: - Private

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        addSubview(iconView)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.focusRingType = .none
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.font = NSFont.systemFont(ofSize: 13)
        titleField.delegate = self
        addSubview(titleField)

        imageView = iconView
        textField = titleField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func applyColorTag(_ tag: Int) {
        wantsLayer = true
        let colors: [NSColor] = [
            .clear, .systemRed, .systemOrange, .systemYellow,
            .systemGreen, .systemBlue, .systemPurple, .systemGray,
        ]
        let color = tag < colors.count ? colors[tag] : .clear
        layer?.backgroundColor = (color == .clear ? NSColor.clear : color.withAlphaComponent(0.15)).cgColor
    }

    private func endEditing() {
        titleField.isEditable = false
        titleField.isSelectable = false
    }
}

// MARK: - NSTextFieldDelegate

extension BookmarkCell: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        let title = titleField.stringValue
        endEditing()
        guard !title.isEmpty else { return }
        onTitleEdited?(title)
    }
}
