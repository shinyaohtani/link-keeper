import AppKit

/// メインウィンドウ。ツールバー・フローティング・状態復元を管理する。
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
        w.minSize = NSSize(width: 300, height: 400)
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
    }

    // MARK: - State

    func saveState() {
        bookmarkList.saveExpandedState()
        store.save()
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
            } else {
                w.center()
            }
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
        window?.collectionBehavior = isFloating
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.fullScreenAuxiliary]
    }

    private func updateFloatIcon() {
        floatItem?.image = NSImage(systemSymbolName: isFloating ? "pin.fill" : "pin",
                                    accessibilityDescription: "Float")
        floatItem?.toolTip = isFloating ? "フローティング解除" : "常に最前面"
    }
}

// MARK: - NSToolbarDelegate

private let captureID  = NSToolbarItem.Identifier("Capture")
private let folderID   = NSToolbarItem.Identifier("NewFolder")
private let floatID    = NSToolbarItem.Identifier("Float")

extension MainWindow: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case captureID:
            return buildCaptureItem()
        case folderID:
            return buildFolderItem()
        case floatID:
            return buildFloatItem()
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [captureID, folderID, .flexibleSpace, floatID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [captureID, folderID, floatID, .flexibleSpace, .space]
    }

    private func buildCaptureItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: captureID)
        item.label = "追加"
        item.toolTip = "ブラウザからURLをキャプチャ"
        item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        item.target = bookmarkList
        item.action = #selector(BookmarkList.captureFromDefault(_:))
        item.showsIndicator = true
        item.menu = buildCaptureMenu()
        return item
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
        let auto = NSMenuItem(title: "ブラウザから自動取得",
                              action: #selector(BookmarkList.captureFromDefault(_:)), keyEquivalent: "")
        auto.target = bookmarkList
        menu.addItem(auto)
        menu.addItem(.separator())

        for browser in catalog.installed {
            let item = NSMenuItem(title: "\(browser.name) から取得",
                                  action: #selector(BookmarkList.captureFromBrowser(_:)), keyEquivalent: "")
            item.target = bookmarkList
            item.representedObject = BrowserWrapper(browser)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let clip = NSMenuItem(title: "クリップボードのURLから作成",
                              action: #selector(BookmarkList.pasteURLAsBookmark(_:)), keyEquivalent: "")
        clip.target = bookmarkList
        menu.addItem(clip)
        return menu
    }
}

/// NSMenuItem.representedObject は AnyObject なので struct Browser をラップする。
class BrowserWrapper: NSObject {
    let browser: Browser
    init(_ browser: Browser) { self.browser = browser; super.init() }
}
