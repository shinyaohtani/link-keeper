import AppKit

class PreferencesViewController: NSViewController {
    private var browserPopup: NSPopUpButton!
    private static let defaultBrowserKey = "LinkKeeper.defaultCaptureBrowser"

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 100))

        // Label
        let label = NSTextField(labelWithString: "(+) ボタンのデフォルトブラウザ:")
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        // Popup button
        browserPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        browserPopup.translatesAutoresizingMaskIntoConstraints = false

        // 「自動検出」オプション
        browserPopup.addItem(withTitle: "自動検出 (実行中のブラウザ)")
        browserPopup.lastItem?.representedObject = nil

        browserPopup.menu?.addItem(.separator())

        // インストール済みブラウザ
        for browser in BrowserCapture.installedBrowsers() {
            browserPopup.addItem(withTitle: browser.name)
            browserPopup.lastItem?.representedObject = browser.bundleID as NSString
        }

        // 保存済みの設定を復元
        let savedID = UserDefaults.standard.string(forKey: Self.defaultBrowserKey)
        if let savedID = savedID {
            for i in 0..<browserPopup.numberOfItems {
                if let obj = browserPopup.item(at: i)?.representedObject as? NSString,
                   obj as String == savedID {
                    browserPopup.selectItem(at: i)
                    break
                }
            }
        }

        browserPopup.target = self
        browserPopup.action = #selector(browserChanged(_:))
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

    @objc private func browserChanged(_ sender: NSPopUpButton) {
        if let bundleID = sender.selectedItem?.representedObject as? NSString {
            UserDefaults.standard.set(bundleID as String, forKey: Self.defaultBrowserKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultBrowserKey)
        }
    }

    // MARK: - Static Helpers

    static var defaultBrowserBundleID: String? {
        return UserDefaults.standard.string(forKey: defaultBrowserKey)
    }
}
