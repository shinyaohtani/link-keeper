import AppKit

/// ブックマークの右クリックメニューを構築する値型。
struct ContextMenu {
    let node: BookmarkNode?
    let catalog: BrowserCatalog
    let target: AnyObject

    var menu: NSMenu {
        let menu = NSMenu()
        guard let node = node else {
            appendNewFolder(to: menu)
            return menu
        }
        appendBrowserItems(to: menu, for: node)
        appendColorTag(to: menu, for: node)
        appendEditItems(to: menu)
        menu.addItem(.separator())
        appendNewFolder(to: menu)
        return menu
    }

    // MARK: - Private

    private func appendBrowserItems(to menu: NSMenu, for node: BookmarkNode) {
        guard !node.isFolder, let urlStr = node.urlString, URL(string: urlStr) != nil else { return }
        for browser in catalog.installed {
            let item = NSMenuItem(title: "\(browser.name) で開く",
                                  action: #selector(BookmarkList.openInBrowser(_:)), keyEquivalent: "")
            item.representedObject = OpenRequest(node: node, browser: browser)
            item.target = target
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    private func appendColorTag(to menu: NSMenu, for node: BookmarkNode) {
        let item = NSMenuItem(title: "カラーラベル", action: nil, keyEquivalent: "")
        item.submenu = ColorTagMenu(currentTag: node.colorTag)
            .menu(target: target, action: #selector(BookmarkList.setColorTagAction(_:)))
        menu.addItem(item)
        menu.addItem(.separator())
    }

    private func appendEditItems(to menu: NSMenu) {
        let edit = NSMenuItem(title: "情報を編集…",
                              action: #selector(BookmarkList.editContextItem(_:)), keyEquivalent: "")
        edit.target = target
        menu.addItem(edit)

        let rename = NSMenuItem(title: "名前を変更",
                                action: #selector(BookmarkList.renameFromMenu(_:)), keyEquivalent: "")
        rename.target = target
        menu.addItem(rename)

        let delete = NSMenuItem(title: "削除",
                                action: #selector(BookmarkList.deleteSelectedItems(_:)), keyEquivalent: "")
        delete.target = target
        menu.addItem(delete)
    }

    private func appendNewFolder(to menu: NSMenu) {
        let item = NSMenuItem(title: "新規フォルダ",
                              action: #selector(BookmarkList.newFolder(_:)), keyEquivalent: "")
        item.target = target
        menu.addItem(item)
    }
}

/// 「ブラウザで開く」リクエスト。NSMenuItem.representedObject に格納。
class OpenRequest: NSObject {
    let node: BookmarkNode
    let browser: Browser
    init(node: BookmarkNode, browser: Browser) {
        self.node = node
        self.browser = browser
        super.init()
    }
}
