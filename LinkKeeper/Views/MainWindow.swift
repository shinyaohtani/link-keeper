import AppKit

/// メインウィンドウ。ツールバー（Liquid Glass）・フローティング・状態復元を管理する。
class MainWindow: NSWindowController, NSWindowDelegate {
    private let store = BookmarkStore()
    private let catalog = BrowserCatalog()
    private var bookmarkList: BookmarkList!
    private var isFloating = false
    private var floatItem: NSToolbarItem?

    private let autosaveName = NSWindow.FrameAutosaveName("LinkKeeperMainWindow")
    private let floatingKey = "LinkKeeper.isFloating"

    init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 2800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = "LinkKeeper"
        w.minSize = NSSize(width: 200, height: 300)
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self

        bookmarkList = BookmarkList(store: store, catalog: catalog)
        w.contentViewController = bookmarkList

        setupToolbar()
        restoreFrame()
        restoreFloating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) { saveState() }

    // MARK: - Floating

    @objc func toggleFloating(_ sender: Any?) {
        isFloating.toggle()
        applyFloating()
        updateFloatIcon()
        UserDefaults.standard.set(isFloating, forKey: floatingKey)
        // ON にした場合は現在の Space に呼び寄せて前面化（既にいた場合も問題なし）
        if isFloating {
            window?.orderFrontRegardless()
            window?.makeKey()
        }
    }

    // MARK: - State

    func saveState() {
        bookmarkList.saveExpandedState()
        store.save()
    }

    @objc private func showSettingsFromMenu(_ sender: Any?) {
        NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
    }

    // MARK: - Private

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "LinkKeeperToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
    }

    private func restoreFrame() {
        guard let w = window else { return }
        let restored = w.setFrameUsingName(autosaveName)
        if !restored || w.frame.width < w.minSize.width || w.frame.height < w.minSize.height {
            if let screen = NSScreen.main {
                let vis = screen.visibleFrame
                let width = min(640, vis.width)
                let height = min(2800, vis.height)
                let x = vis.origin.x + (vis.width - width) / 2
                let y = vis.origin.y + (vis.height - height) / 2
                w.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
            } else { w.center() }
        }
        w.setFrameAutosaveName(autosaveName)
    }

    private func restoreFloating() {
        isFloating = UserDefaults.standard.bool(forKey: floatingKey)
        applyFloating()
        updateFloatIcon()
    }

    private func applyFloating() {
        window?.level = isFloating ? .floating : .normal
        // ピンON: 全 Space に常駐 / ピンOFF: アクティブ化時に自分のいる Space に移動
        window?.collectionBehavior = isFloating
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    private func updateFloatIcon() {
        floatItem?.image = NSImage(systemSymbolName: isFloating ? "pin.fill" : "pin",
                                    accessibilityDescription: "Float")
        floatItem?.toolTip = isFloating ? "フローティング解除" : "常に最前面"
    }
}

// MARK: - NSToolbarDelegate

private let captureID = NSToolbarItem.Identifier("Capture")
private let folderID  = NSToolbarItem.Identifier("NewFolder")
private let floatID   = NSToolbarItem.Identifier("Float")

extension MainWindow: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case captureID: return buildCaptureItem()
        case folderID:  return buildFolderItem()
        case floatID:   return buildFloatItem()
        default: return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [captureID, folderID, floatID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [captureID, folderID, floatID]
    }

    // MARK: - Toolbar Items

    private func buildCaptureItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: captureID)
        item.label = "追加"
        item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        item.target = bookmarkList
        item.action = #selector(BookmarkList.captureFromDefault(_:))
        item.showsIndicator = true
        item.menu = buildCaptureMenu()
        item.toolTip = captureTooltip
        return item
    }

    private var captureTooltip: String {
        let defaultID = UserDefaults.standard.string(forKey: "LinkKeeper.defaultCaptureBrowser")
        guard let id = defaultID, let browser = catalog.browser(for: id) else {
            return "よく使うブラウザが未設定（▼ で設定）"
        }
        return "\(browser.name) から取得（▼ でブラウザ選択）"
    }

    private func buildFolderItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: folderID)
        item.label = "新規フォルダ"
        item.toolTip = "新規フォルダを作成"
        item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "New Folder")
        item.target = bookmarkList
        item.action = #selector(BookmarkList.newFolder(_:))
        return item
    }

    private func buildFloatItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: floatID)
        item.label = "フローティング"
        item.toolTip = isFloating ? "フローティング解除" : "常に最前面"
        item.image = NSImage(systemSymbolName: isFloating ? "pin.fill" : "pin",
                             accessibilityDescription: "Float")
        item.target = self
        item.action = #selector(toggleFloating(_:))
        floatItem = item
        return item
    }

    private func buildCaptureMenu() -> NSMenu {
        let menu = NSMenu()

        // よく使うブラウザから取得
        let defaultID = UserDefaults.standard.string(forKey: "LinkKeeper.defaultCaptureBrowser")
        let defaultBrowser = defaultID.flatMap { catalog.browser(for: $0) }
        let fav = NSMenuItem(title: defaultBrowser != nil
                                ? "よく使うブラウザ(\(defaultBrowser!.name))から取得"
                                : "よく使うブラウザ(未設定)",
                             action: #selector(BookmarkList.captureFromDefault(_:)), keyEquivalent: "")
        fav.target = bookmarkList
        fav.isEnabled = defaultBrowser != nil
        menu.addItem(fav)

        // よく使うブラウザを設定
        let settings = NSMenuItem(title: "よく使うブラウザを設定…",
                                  action: #selector(showSettingsFromMenu(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        // ブラウザ一覧
        for browser in catalog.installed {
            let item = NSMenuItem(title: "\(browser.name) から取得",
                                  action: #selector(BookmarkList.captureFromBrowser(_:)), keyEquivalent: "")
            item.target = bookmarkList
            item.representedObject = BrowserWrapper(browser)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // クリップボードから
        let clip = NSMenuItem(title: "クリップボードのURLから作成",
                              action: #selector(BookmarkList.pasteURLAsBookmark(_:)), keyEquivalent: "")
        clip.target = bookmarkList
        menu.addItem(clip)
        return menu
    }
}
