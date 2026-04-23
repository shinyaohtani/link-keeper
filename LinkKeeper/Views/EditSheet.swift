import AppKit

/// ブックマークの編集・新規作成シートダイアログ。
class EditSheet: NSViewController {
    enum Mode { case edit, create }

    private let node: BookmarkNode
    private let mode: Mode
    private var titleField: NSTextField!
    private var urlTextView: NSTextView!
    private var colorPopup: NSPopUpButton!
    private var faviconView: NSImageView!

    var onSave: (() -> Void)?
    var onFaviconReload: ((_ node: BookmarkNode, _ completion: @escaping () -> Void) -> Void)?

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
        buildHeader(in: container)
        let urlScrollView = buildURLField(in: container)
        let dateValue = buildDateRow(in: container, below: urlScrollView)
        let sep = buildColorRow(in: container, below: dateValue)
        buildButtons(in: container, below: sep)
        self.view = container
        focusTitleIfCreate()
    }

    // MARK: - Actions

    @objc private func saveAction(_ sender: Any?) {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .create && title.isEmpty {
            NSSound.beep()
            view.window?.makeFirstResponder(titleField)
            return
        }
        if !title.isEmpty { node.title = title }
        if !node.isFolder {
            let url = urlTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.isEmpty { node.urlString = url }
        }
        node.colorTag = colorPopup.indexOfSelectedItem
        if mode == .edit { node.recordEdit() }
        onSave?()
        dismiss()
    }

    @objc private func reloadFavicon(_ sender: NSButton) {
        sender.isEnabled = false
        sender.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)
        onFaviconReload?(node) { [weak self] in
            guard let self = self else { return }
            self.updateFavicon()
            sender.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            sender.isEnabled = true
        }
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

    // MARK: - View Building

    private func buildHeader(in container: NSView) {
        faviconView = NSImageView()
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.imageScaling = .scaleProportionallyUpOrDown
        updateFavicon()
        container.addSubview(faviconView)

        // favicon リロードボタン（フォルダ以外）
        let reloadBtn = NSButton()
        reloadBtn.translatesAutoresizingMaskIntoConstraints = false
        reloadBtn.bezelStyle = .accessoryBarAction
        reloadBtn.isBordered = false
        reloadBtn.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload favicon")
        reloadBtn.imagePosition = .imageOnly
        reloadBtn.toolTip = "ファビコンを再取得"
        reloadBtn.target = self
        reloadBtn.action = #selector(reloadFavicon(_:))
        reloadBtn.isHidden = node.isFolder
        container.addSubview(reloadBtn)

        titleField = NSTextField()
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.stringValue = node.title
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        titleField.placeholderString = "タイトルを入力"
        titleField.bezelStyle = .roundedBezel
        container.addSubview(titleField)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 480),
            faviconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            faviconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            faviconView.widthAnchor.constraint(equalToConstant: 40),
            faviconView.heightAnchor.constraint(equalToConstant: 40),
            reloadBtn.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 2),
            reloadBtn.bottomAnchor.constraint(equalTo: faviconView.bottomAnchor),
            reloadBtn.widthAnchor.constraint(equalToConstant: 20),
            reloadBtn.heightAnchor.constraint(equalToConstant: 20),
            titleField.leadingAnchor.constraint(equalTo: reloadBtn.trailingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            titleField.centerYAnchor.constraint(equalTo: faviconView.centerYAnchor),
        ])
    }

    private func buildURLField(in container: NSView) -> NSScrollView {
        let label = makeLabel("URL")
        container.addSubview(label)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

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
        scrollView.documentView = urlTextView
        container.addSubview(scrollView)

        let lineH = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).boundingRectForFont.height
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: faviconView.bottomAnchor, constant: 18),
            label.widthAnchor.constraint(equalToConstant: 50),
            scrollView.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: label.topAnchor, constant: -2),
            scrollView.heightAnchor.constraint(equalToConstant: ceil(lineH * 3) + 16),
        ])
        return scrollView
    }

    private func buildDateRow(in container: NSView, below anchor: NSView) -> NSTextField {
        let label = makeLabel("追加日")
        container.addSubview(label)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let value = NSTextField(labelWithString: formatter.string(from: node.dateAdded))
        value.translatesAutoresizingMaskIntoConstraints = false
        value.font = NSFont.systemFont(ofSize: 12)
        value.textColor = .secondaryLabelColor
        container.addSubview(value)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: anchor.bottomAnchor, constant: 12),
            label.widthAnchor.constraint(equalToConstant: 50),
            value.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            value.centerYAnchor.constraint(equalTo: label.centerYAnchor),
        ])
        return value
    }

    @discardableResult
    private func buildColorRow(in container: NSView, below anchor: NSView) -> NSBox {
        let label = makeLabel("カラー")
        container.addSubview(label)

        colorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        colorPopup.translatesAutoresizingMaskIntoConstraints = false
        for name in ["なし", "レッド", "オレンジ", "イエロー", "グリーン", "ブルー", "パープル", "グレイ"] {
            colorPopup.addItem(withTitle: name)
        }
        colorPopup.selectItem(at: node.colorTag)
        container.addSubview(colorPopup)

        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .separator
        container.addSubview(sep)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: anchor.bottomAnchor, constant: 12),
            label.widthAnchor.constraint(equalToConstant: 50),
            colorPopup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            colorPopup.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            colorPopup.widthAnchor.constraint(equalToConstant: 140),
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            sep.topAnchor.constraint(equalTo: colorPopup.bottomAnchor, constant: 16),
        ])
        return sep
    }

    private func buildButtons(in container: NSView, below sep: NSView) {
        let cancel = NSButton(title: "キャンセル", target: self, action: #selector(cancelAction(_:)))
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        container.addSubview(cancel)

        let confirm = NSButton(title: mode == .create ? "作成" : "保存",
                               target: self, action: #selector(saveAction(_:)))
        confirm.translatesAutoresizingMaskIntoConstraints = false
        confirm.bezelStyle = .rounded
        confirm.keyEquivalent = "\r"
        container.addSubview(confirm)

        NSLayoutConstraint.activate([
            confirm.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            confirm.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 12),
            confirm.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            confirm.widthAnchor.constraint(equalToConstant: 80),
            cancel.trailingAnchor.constraint(equalTo: confirm.leadingAnchor, constant: -8),
            cancel.centerYAnchor.constraint(equalTo: confirm.centerYAnchor),
            cancel.widthAnchor.constraint(equalToConstant: 80),
        ])
    }

    // MARK: - Helpers

    private func updateFavicon() {
        faviconView.contentTintColor = nil
        if let data = node.faviconData, let img = NSImage(data: data) {
            faviconView.image = img
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
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    private func focusTitleIfCreate() {
        guard mode == .create else { return }
        DispatchQueue.main.async { self.view.window?.makeFirstResponder(self.titleField) }
    }
}
