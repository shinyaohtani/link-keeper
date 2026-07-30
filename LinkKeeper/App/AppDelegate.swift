import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: MainWindow!
    private var settingsWindow: NSWindow?
    private let catalog = BrowserCatalog()

    func applicationWillFinishLaunching(_ notification: Notification) {
        setupMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainWindow = MainWindow()
        mainWindow.showWindow(nil)
        mainWindow.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindow.saveState()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Settings

    @objc func showSettings(_ sender: Any?) {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); return }
        let vc = SettingsPanel()
        let w = NSWindow(contentViewController: vc)
        w.title = "設定"
        w.styleMask = [.titled, .closable]
        w.setContentSize(NSSize(width: 360, height: 100))
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        settingsWindow = w
    }

    // MARK: - Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(buildAppMenu())
        mainMenu.addItem(buildFileMenu())
        mainMenu.addItem(buildEditMenu())
        mainMenu.addItem(buildViewMenu())
        NSApp.mainMenu = mainMenu
    }

    private func buildAppMenu() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "LinkKeeper について",
                                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "設定…", action: #selector(showSettings(_:)), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "LinkKeeper を終了",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private func buildFileMenu() -> NSMenuItem {
        let menu = NSMenu(title: "ファイル")
        menu.addItem(NSMenuItem(title: "ブラウザからキャプチャ",
                                action: #selector(BookmarkList.captureFromDefault(_:)), keyEquivalent: "d"))
        menu.addItem(buildCaptureSubmenu())
        menu.addItem(NSMenuItem(title: "クリップボードのURLから作成",
                                action: #selector(BookmarkList.pasteURLAsBookmark(_:)), keyEquivalent: "V"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "新規フォルダ",
                                action: #selector(BookmarkList.newFolder(_:)), keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "ブックマークをインポート…",
                                action: #selector(BookmarkList.importBookmarks(_:)), keyEquivalent: "I"))
        menu.addItem(NSMenuItem(title: "ブックマークをエクスポート…",
                                action: #selector(BookmarkList.exportBookmarks(_:)), keyEquivalent: "E"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "ウィンドウを閉じる",
                                action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private func buildEditMenu() -> NSMenuItem {
        let menu = NSMenu(title: "編集")
        menu.addItem(NSMenuItem(title: "取り消す", action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "やり直す", action: Selector(("redo:")), keyEquivalent: "Z"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "削除",
                                action: #selector(BookmarkList.deleteSelectedItems(_:)), keyEquivalent: "\u{08}"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "情報を見る",
                                action: #selector(BookmarkList.editSelectedBookmark(_:)), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "名前を変更",
                                action: #selector(BookmarkList.renameFromMenu(_:)), keyEquivalent: "\r"))
        menu.addItem(.separator())
        let colorItem = NSMenuItem(title: "カラーラベル", action: nil, keyEquivalent: "")
        colorItem.submenu = ColorTagMenu(currentTag: -1)
            .menu(target: nil, action: #selector(BookmarkList.setColorTagAction(_:)))
        menu.addItem(colorItem)
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private func buildViewMenu() -> NSMenuItem {
        let menu = NSMenu(title: "表示")
        let toggle = NSMenuItem(title: "フローティング切替",
                                action: #selector(toggleFloatingFromMenu(_:)),
                                keyEquivalent: "f")
        toggle.target = self
        menu.addItem(toggle)
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    /// メニューバーから呼ばれるフローティング切替。
    /// 別 Space にウィンドウがあって key window でない状況でも、
    /// AppDelegate を直接ターゲットにすることでメニューが有効になる。
    @objc func toggleFloatingFromMenu(_ sender: Any?) {
        mainWindow?.toggleFloating(sender)
    }

    private func buildCaptureSubmenu() -> NSMenuItem {
        let sub = NSMenu()
        for browser in catalog.installed {
            let item = NSMenuItem(title: "\(browser.name) からキャプチャ",
                                  action: #selector(BookmarkList.captureFromBrowser(_:)), keyEquivalent: "")
            item.representedObject = BrowserWrapper(browser)
            sub.addItem(item)
        }
        let item = NSMenuItem(title: "キャプチャ元を選択…", action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }
}
