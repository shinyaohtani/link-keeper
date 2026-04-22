import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController!
    private var preferencesWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        setupMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = MainWindowController()
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController.saveState()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Preferences

    @objc private func showPreferences(_ sender: Any?) {
        if let preferencesWindow = preferencesWindow {
            preferencesWindow.makeKeyAndOrderFront(nil)
            return
        }
        let vc = PreferencesViewController()
        let window = NSWindow(contentViewController: vc)
        window.title = "設定"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 360, height: 100))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        preferencesWindow = window
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // === LinkKeeper メニュー ===
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "LinkKeeper について",
                                   action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "設定…",
                                   action: #selector(showPreferences(_:)),
                                   keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "LinkKeeper を終了",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // === ファイル ===
        let fileMenu = NSMenu(title: "ファイル")

        fileMenu.addItem(NSMenuItem(title: "ブラウザからキャプチャ",
                                    action: #selector(OutlineViewController.captureFromFrontmostBrowser(_:)),
                                    keyEquivalent: "d"))

        let captureSubmenu = NSMenu()
        for browser in BrowserCapture.installedBrowsers() {
            let item = NSMenuItem(title: "\(browser.name) からキャプチャ",
                                  action: #selector(OutlineViewController.captureFromBrowser(_:)),
                                  keyEquivalent: "")
            item.representedObject = browser
            captureSubmenu.addItem(item)
        }
        let captureMenuItem = NSMenuItem(title: "キャプチャ元を選択…", action: nil, keyEquivalent: "")
        captureMenuItem.submenu = captureSubmenu
        fileMenu.addItem(captureMenuItem)

        fileMenu.addItem(NSMenuItem(title: "クリップボードのURLから作成",
                                    action: #selector(OutlineViewController.pasteURLAsBookmark(_:)),
                                    keyEquivalent: "V"))  // Cmd+Shift+V

        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "新規フォルダ",
                                    action: #selector(OutlineViewController.newFolder(_:)),
                                    keyEquivalent: "n"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "ウィンドウを閉じる",
                                    action: #selector(NSWindow.performClose(_:)),
                                    keyEquivalent: "w"))

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // === 編集 ===
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(NSMenuItem(title: "取り消す",
                                    action: Selector(("undo:")),
                                    keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "やり直す",
                                    action: Selector(("redo:")),
                                    keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "カット",
                                    action: #selector(NSText.cut(_:)),
                                    keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "コピー",
                                    action: #selector(NSText.copy(_:)),
                                    keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "ペースト",
                                    action: #selector(NSText.paste(_:)),
                                    keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "URLを貼り付けてブックマーク作成",
                                    action: #selector(OutlineViewController.pasteURLAsBookmark(_:)),
                                    keyEquivalent: "V"))  // Cmd+Shift+V
        editMenu.addItem(NSMenuItem(title: "削除",
                                    action: #selector(OutlineViewController.deleteSelectedItems(_:)),
                                    keyEquivalent: "\u{08}"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "すべてを選択",
                                    action: #selector(NSText.selectAll(_:)),
                                    keyEquivalent: "a"))

        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "情報を編集…",
                                    action: #selector(OutlineViewController.editSelectedBookmark(_:)),
                                    keyEquivalent: "e"))
        editMenu.addItem(NSMenuItem(title: "名前を変更",
                                    action: #selector(OutlineViewController.renameFromMenu(_:)),
                                    keyEquivalent: "\r"))

        // カラーラベルサブメニュー
        editMenu.addItem(.separator())
        let colorMenuItem = NSMenuItem(title: "カラーラベル", action: nil, keyEquivalent: "")
        // delegate で動的に構築するため、初期メニューはプレースホルダー
        colorMenuItem.submenu = OutlineViewController.buildColorTagMenu()
        editMenu.addItem(colorMenuItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // === 表示 ===
        let viewMenu = NSMenu(title: "表示")
        viewMenu.addItem(NSMenuItem(title: "フローティング切替",
                                    action: #selector(MainWindowController.toggleFloating(_:)),
                                    keyEquivalent: "f"))

        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
