import AppKit

/// ブックマークの編集・新規作成ダイアログ
class BookmarkEditViewController: NSViewController {
    enum Mode {
        case edit
        case create
    }

    private let node: BookmarkNode
    private let mode: Mode
    private var titleField: NSTextField!
    private var urlTextView: NSTextView!
    private var colorPopup: NSPopUpButton!
    private var faviconView: NSImageView!

    var onSave: (() -> Void)?

    init(node: BookmarkNode, mode: Mode = .edit) {
        self.node = node
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // === Header: Favicon + Title ===
        faviconView = NSImageView()
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.imageScaling = .scaleProportionallyUpOrDown
        updateFavicon()
        container.addSubview(faviconView)

        titleField = NSTextField()
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.stringValue = node.title
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        titleField.placeholderString = "タイトルを入力"
        titleField.bezelStyle = .roundedBezel
        container.addSubview(titleField)

        // === URL ===
        let urlLabel = makeLabel("URL")
        container.addSubview(urlLabel)

        let urlScrollView = NSScrollView()
        urlScrollView.translatesAutoresizingMaskIntoConstraints = false
        urlScrollView.hasVerticalScroller = true
        urlScrollView.hasHorizontalScroller = false
        urlScrollView.borderType = .bezelBorder

        urlTextView = NSTextView()
        urlTextView.isEditable = !node.isFolder
        urlTextView.isSelectable = true
        urlTextView.isRichText = false
        urlTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        urlTextView.string = node.urlString ?? ""
        urlTextView.isAutomaticLinkDetectionEnabled = false
        urlTextView.isAutomaticQuoteSubstitutionEnabled = false
        urlTextView.isAutomaticDashSubstitutionEnabled = false
        urlTextView.isAutomaticTextReplacementEnabled = false
        urlTextView.textContainerInset = NSSize(width: 4, height: 4)
        urlTextView.textContainer?.widthTracksTextView = true
        urlTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        if node.isFolder { urlTextView.textColor = .tertiaryLabelColor }

        urlScrollView.documentView = urlTextView
        container.addSubview(urlScrollView)

        // === Date ===
        let dateLabel = makeLabel("追加日")
        container.addSubview(dateLabel)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dateValue = NSTextField(labelWithString: formatter.string(from: node.dateAdded))
        dateValue.translatesAutoresizingMaskIntoConstraints = false
        dateValue.font = NSFont.systemFont(ofSize: 12)
        dateValue.textColor = .secondaryLabelColor
        container.addSubview(dateValue)

        // === Color ===
        let colorLabel = makeLabel("カラー")
        container.addSubview(colorLabel)

        colorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        colorPopup.translatesAutoresizingMaskIntoConstraints = false
        let colorNames = ["なし", "レッド", "オレンジ", "イエロー", "グリーン", "ブルー", "パープル", "グレイ"]
        for name in colorNames { colorPopup.addItem(withTitle: name) }
        colorPopup.selectItem(at: node.colorTag)
        container.addSubview(colorPopup)

        // === Separator ===
        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .separator
        container.addSubview(sep)

        // === Buttons ===
        let cancelButton = NSButton(title: "キャンセル", target: self, action: #selector(cancelAction(_:)))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        container.addSubview(cancelButton)

        let confirmTitle = mode == .create ? "作成" : "保存"
        let confirmButton = NSButton(title: confirmTitle, target: self, action: #selector(saveAction(_:)))
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"
        container.addSubview(confirmButton)

        // === Layout ===
        let pad: CGFloat = 20
        let vGap: CGFloat = 12
        let labelW: CGFloat = 50
        let lineHeight = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).boundingRectForFont.height
        let urlHeight = ceil(lineHeight * 3) + 16

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 480),

            faviconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            faviconView.topAnchor.constraint(equalTo: container.topAnchor, constant: pad),
            faviconView.widthAnchor.constraint(equalToConstant: 40),
            faviconView.heightAnchor.constraint(equalToConstant: 40),

            titleField.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),
            titleField.centerYAnchor.constraint(equalTo: faviconView.centerYAnchor),

            urlLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            urlLabel.topAnchor.constraint(equalTo: faviconView.bottomAnchor, constant: vGap + 6),
            urlLabel.widthAnchor.constraint(equalToConstant: labelW),

            urlScrollView.leadingAnchor.constraint(equalTo: urlLabel.trailingAnchor, constant: 8),
            urlScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),
            urlScrollView.topAnchor.constraint(equalTo: urlLabel.topAnchor, constant: -2),
            urlScrollView.heightAnchor.constraint(equalToConstant: urlHeight),

            dateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            dateLabel.topAnchor.constraint(equalTo: urlScrollView.bottomAnchor, constant: vGap),
            dateLabel.widthAnchor.constraint(equalToConstant: labelW),

            dateValue.leadingAnchor.constraint(equalTo: dateLabel.trailingAnchor, constant: 8),
            dateValue.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),

            colorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            colorLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: vGap),
            colorLabel.widthAnchor.constraint(equalToConstant: labelW),

            colorPopup.leadingAnchor.constraint(equalTo: colorLabel.trailingAnchor, constant: 8),
            colorPopup.centerYAnchor.constraint(equalTo: colorLabel.centerYAnchor),
            colorPopup.widthAnchor.constraint(equalToConstant: 140),

            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),
            sep.topAnchor.constraint(equalTo: colorPopup.bottomAnchor, constant: vGap + 4),

            confirmButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),
            confirmButton.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: vGap),
            confirmButton.widthAnchor.constraint(equalToConstant: 80),

            cancelButton.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: confirmButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),

            confirmButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -pad),
        ])

        self.view = container

        // 新規作成モードではタイトルにフォーカス
        if mode == .create {
            DispatchQueue.main.async {
                self.view.window?.makeFirstResponder(self.titleField)
            }
        }
    }

    private func updateFavicon() {
        if let data = node.faviconData, let img = NSImage(data: data) {
            faviconView.image = img
            faviconView.contentTintColor = nil
        } else if node.isFolder {
            faviconView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            faviconView.contentTintColor = .systemBlue
        } else {
            faviconView.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            faviconView.contentTintColor = .tertiaryLabelColor
        }
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    @objc private func saveAction(_ sender: Any?) {
        let newTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .create && newTitle.isEmpty {
            // 新規作成でタイトル空は許可しない
            NSSound.beep()
            view.window?.makeFirstResponder(titleField)
            return
        }
        if !newTitle.isEmpty { node.title = newTitle }
        if !node.isFolder {
            let newURL = urlTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newURL.isEmpty { node.urlString = newURL }
        }
        node.colorTag = colorPopup.indexOfSelectedItem
        if mode == .edit { node.recordEdit() }
        onSave?()
        dismiss()
    }

    @objc private func cancelAction(_ sender: Any?) {
        dismiss()
    }

    private func dismiss() {
        if let sheet = view.window, let parent = sheet.sheetParent {
            parent.endSheet(sheet)
        } else {
            view.window?.close()
        }
    }
}
