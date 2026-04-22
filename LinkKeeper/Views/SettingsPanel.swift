import AppKit

/// (+) ボタンのデフォルトブラウザを設定するパネル。
class SettingsPanel: NSViewController {
    private let catalog = BrowserCatalog()
    private var browserPopup: NSPopUpButton!
    private let defaultsKey = "LinkKeeper.defaultCaptureBrowser"

    /// 保存されたデフォルトブラウザの bundleID
    var defaultBundleID: String? {
        UserDefaults.standard.string(forKey: defaultsKey)
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 100))

        let label = NSTextField(labelWithString: "(+) ボタンのデフォルトブラウザ:")
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        browserPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        browserPopup.translatesAutoresizingMaskIntoConstraints = false
        browserPopup.addItem(withTitle: "自動検出 (実行中のブラウザ)")
        browserPopup.lastItem?.representedObject = nil
        browserPopup.menu?.addItem(.separator())

        for browser in catalog.installed {
            browserPopup.addItem(withTitle: browser.name)
            browserPopup.lastItem?.representedObject = browser.bundleID as NSString
        }
        restoreSelection()
        browserPopup.target = self
        browserPopup.action = #selector(changed(_:))
        container.addSubview(browserPopup)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            browserPopup.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            browserPopup.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            browserPopup.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
        self.view = container
    }

    @objc private func changed(_ sender: NSPopUpButton) {
        if let id = sender.selectedItem?.representedObject as? NSString {
            UserDefaults.standard.set(id as String, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    private func restoreSelection() {
        guard let savedID = UserDefaults.standard.string(forKey: defaultsKey) else { return }
        for idx in 0..<browserPopup.numberOfItems {
            if (browserPopup.item(at: idx)?.representedObject as? NSString) as String? == savedID {
                browserPopup.selectItem(at: idx)
                return
            }
        }
    }
}
