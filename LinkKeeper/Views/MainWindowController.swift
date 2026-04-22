import AppKit

class MainWindowController: NSWindowController, NSWindowDelegate {
    private let store = BookmarkStore()
    private var outlineVC: OutlineViewController!
    private var isFloating = false
    private var floatToolbarItem: NSToolbarItem?

    private static let frameAutosaveName = NSWindow.FrameAutosaveName("LinkKeeperMainWindow")
    private static let floatingKey = "LinkKeeper.isFloating"
    private static let columnWidthKey = "LinkKeeper.dateColumnWidth"

    private static let defaultWidth: CGFloat = 640
    private static let defaultHeight: CGFloat = 2800

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.defaultWidth, height: Self.defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LinkKeeper"
        window.minSize = NSSize(width: 300, height: 400)
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self

        outlineVC = OutlineViewController(store: store)
        window.contentViewController = outlineVC

        setupToolbar()

        // 保存済みフレームを復元。小さすぎる場合はデフォルトにフォールバック
        let restored = window.setFrameUsingName(Self.frameAutosaveName)
        if !restored || window.frame.width < window.minSize.width || window.frame.height < window.minSize.height {
            // デフォルトサイズを画面に収まるよう調整して中央配置
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                let w = min(Self.defaultWidth, visible.width)
                let h = min(Self.defaultHeight, visible.height)
                let x = visible.origin.x + (visible.width - w) / 2
                let y = visible.origin.y + (visible.height - h) / 2
                window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
            } else {
                window.center()
            }
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)

        restoreColumnWidth()
        restoreState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        saveState()
    }

    func windowDidResize(_ notification: Notification) {
        // フレームは autosaveName で自動保存される
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "LinkKeeperToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
    }

    // MARK: - Floating

    @objc func toggleFloating(_ sender: Any?) {
        isFloating.toggle()
        applyFloatingState()
        updateFloatIcon()
        UserDefaults.standard.set(isFloating, forKey: Self.floatingKey)
    }

    private func applyFloatingState() {
        if isFloating {
            window?.level = .floating
            window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            window?.level = .normal
            window?.collectionBehavior = [.fullScreenAuxiliary]
        }
    }

    private func updateFloatIcon() {
        let symbolName = isFloating ? "pin.fill" : "pin"
        floatToolbarItem?.image = NSImage(systemSymbolName: symbolName,
                                          accessibilityDescription: "Float")
        floatToolbarItem?.toolTip = isFloating ? "Disable always-on-top" : "Enable always-on-top"
    }

    // MARK: - State Persistence

    private func restoreState() {
        isFloating = UserDefaults.standard.bool(forKey: Self.floatingKey)
        applyFloatingState()
        updateFloatIcon()
    }

    func saveState() {
        outlineVC.saveExpandedState()
        saveColumnWidth()
        store.save()
    }

    private func saveColumnWidth() {
        guard let dateCol = outlineVC.outlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("DateColumn")) else { return }
        UserDefaults.standard.set(Double(dateCol.width), forKey: Self.columnWidthKey)
    }

    private func restoreColumnWidth() {
        let width = UserDefaults.standard.double(forKey: Self.columnWidthKey)
        if width > 0, let dateCol = outlineVC.outlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("DateColumn")) {
            dateCol.width = CGFloat(width)
        }
    }
}

// MARK: - NSToolbarDelegate

private let floatItemID = NSToolbarItem.Identifier("ToggleFloat")
private let newFolderItemID = NSToolbarItem.Identifier("NewFolder")
private let captureItemID = NSToolbarItem.Identifier("CaptureURL")

extension MainWindowController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case captureItemID:
            let item = NSMenuToolbarItem(itemIdentifier: captureItemID)
            item.label = "Add"
            item.toolTip = "Capture URL from browser"
            item.image = NSImage(systemSymbolName: "plus",
                                 accessibilityDescription: "Add")
            item.target = outlineVC
            item.action = #selector(OutlineViewController.captureFromFrontmostBrowser(_:))
            item.showsIndicator = true
            item.menu = buildCaptureMenu()
            return item
        case newFolderItemID:
            let item = NSToolbarItem(itemIdentifier: newFolderItemID)
            item.label = "New Folder"
            item.toolTip = "Create a new folder"
            item.image = NSImage(systemSymbolName: "folder.badge.plus",
                                 accessibilityDescription: "New Folder")
            item.target = outlineVC
            item.action = #selector(OutlineViewController.newFolder(_:))
            return item
        case floatItemID:
            let item = NSToolbarItem(itemIdentifier: floatItemID)
            item.label = "Float"
            item.toolTip = isFloating ? "Disable always-on-top" : "Enable always-on-top"
            item.image = NSImage(systemSymbolName: isFloating ? "pin.fill" : "pin",
                                 accessibilityDescription: "Float")
            item.target = self
            item.action = #selector(toggleFloating(_:))
            floatToolbarItem = item
            return item
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [captureItemID, newFolderItemID, .flexibleSpace, floatItemID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [captureItemID, newFolderItemID, floatItemID, .flexibleSpace, .space]
    }

    private func buildCaptureMenu() -> NSMenu {
        let menu = NSMenu()

        // 自動検出
        let autoItem = NSMenuItem(title: "ブラウザから自動取得",
                                  action: #selector(OutlineViewController.captureFromFrontmostBrowser(_:)),
                                  keyEquivalent: "")
        autoItem.target = outlineVC
        menu.addItem(autoItem)
        menu.addItem(.separator())

        // インストール済みブラウザ一覧
        for browser in BrowserCapture.installedBrowsers() {
            let item = NSMenuItem(title: "\(browser.name) から取得",
                                  action: #selector(OutlineViewController.captureFromBrowser(_:)),
                                  keyEquivalent: "")
            item.target = outlineVC
            item.representedObject = browser
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // クリップボードから作成
        let clipItem = NSMenuItem(title: "クリップボードのURLから作成",
                                  action: #selector(OutlineViewController.pasteURLAsBookmark(_:)),
                                  keyEquivalent: "")
        clipItem.target = outlineVC
        menu.addItem(clipItem)

        return menu
    }
}
