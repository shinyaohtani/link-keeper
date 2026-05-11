import AppKit

/// ブックマーク行のセル。launch ボタン + アイコン + タイトル（編集可能）。
class BookmarkCell: NSTableCellView {
    let launchButton = NSButton()
    let iconView = NSImageView()
    let titleField = NSTextField()
    private let hStack = NSStackView()
    private let iconSize: CGFloat = 18
    private let launchSize: CGFloat = 16

    var onTitleEdited: ((String) -> Void)?
    var onOpen: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with node: BookmarkNode) {
        titleField.stringValue = node.title
        iconView.contentTintColor = nil
        launchButton.isHidden = node.isFolder
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
        configureLaunchButton()
        configureIconView()
        configureTitleField()

        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.orientation = .horizontal
        hStack.spacing = 4
        hStack.alignment = .centerY
        hStack.addArrangedSubview(launchButton)
        hStack.addArrangedSubview(iconView)
        hStack.addArrangedSubview(titleField)
        addSubview(hStack)

        imageView = iconView
        textField = titleField

        NSLayoutConstraint.activate([
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            hStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            launchButton.widthAnchor.constraint(equalToConstant: launchSize),
            launchButton.heightAnchor.constraint(equalToConstant: launchSize),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
        ])
    }

    private func configureLaunchButton() {
        let cfg = NSImage.SymbolConfiguration(pointSize: launchSize - 2, weight: .regular)
        launchButton.translatesAutoresizingMaskIntoConstraints = false
        launchButton.bezelStyle = .accessoryBarAction
        launchButton.isBordered = false
        launchButton.imagePosition = .imageOnly
        launchButton.image = NSImage(systemSymbolName: "arrow.up.right.circle.fill",
                                     accessibilityDescription: "Open")?
            .withSymbolConfiguration(cfg)
        launchButton.contentTintColor = .secondaryLabelColor
        launchButton.toolTip = "ブラウザで開く"
        launchButton.target = self
        launchButton.action = #selector(launchTapped(_:))
    }

    private func configureIconView() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
    }

    private func configureTitleField() {
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

    @objc private func launchTapped(_ sender: Any?) {
        onOpen?()
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
