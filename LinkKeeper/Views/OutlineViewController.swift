import AppKit

class OutlineViewController: NSViewController {
    private(set) var outlineView: LinkKeeperOutlineView!
    private var scrollView: NSScrollView!
    let store: BookmarkStore

    static let bookmarkUTI = NSPasteboard.PasteboardType("com.linkkeeper.bookmark-id")
    private static let expandedKey = "LinkKeeper.expandedNodeIDs"

    init(store: BookmarkStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: - View Lifecycle

    override func loadView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        outlineView = LinkKeeperOutlineView()
        outlineView.autosaveName = "LinkKeeperOutline"
        outlineView.autosaveTableColumns = true
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.allowsColumnReordering = false
        outlineView.allowsColumnResizing = true
        outlineView.indentationPerLevel = 16
        outlineView.rowHeight = 24
        outlineView.intercellSpacing = NSSize(width: 0, height: 1)

        // Title column (main column with outline disclosure)
        let titleCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TitleColumn"))
        titleCol.title = "Name"
        titleCol.minWidth = 120
        titleCol.resizingMask = [.userResizingMask, .autoresizingMask]
        outlineView.addTableColumn(titleCol)
        outlineView.outlineTableColumn = titleCol

        // Date column
        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("DateColumn"))
        dateCol.title = "Date Added"
        dateCol.width = 100
        dateCol.minWidth = 70
        dateCol.maxWidth = 160
        dateCol.resizingMask = .userResizingMask
        outlineView.addTableColumn(dateCol)

        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClickAction(_:))

        // Drag & drop registration
        outlineView.registerForDraggedTypes([
            Self.bookmarkUTI,
            .URL,
            .string,
            .init("public.url"),
            .init("public.url-name"),
            .init("WebURLsWithTitlesPboardType"),
        ])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

        scrollView.documentView = outlineView
        self.view = scrollView

        restoreExpandedState()
        repairUrlTitles()
    }

    // MARK: - Double Click -> Open in Default Browser

    @objc private func doubleClickAction(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? BookmarkNode else { return }

        if node.isFolder {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else if let urlStr = node.urlString, let url = URL(string: urlStr) {
            node.recordAccess()
            store.save()
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Undo-aware Operations

    private func reloadUI() {
        outlineView.reloadData()
        restoreExpandedState()
        store.save()
    }

    func performInsert(_ node: BookmarkNode, into parent: BookmarkNode?, at index: Int, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { target in
            target.performRemove(node, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        store.insertNode(node, into: parent, at: index)
        reloadUI()
    }

    func performRemove(_ node: BookmarkNode, actionName: String) {
        let parent = store.parent(of: node)
        let index = store.index(of: node, in: parent) ?? 0
        undoManager?.registerUndo(withTarget: self) { target in
            target.performInsert(node, into: parent, at: index, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        store.removeNode(node)
        reloadUI()
    }

    func performMove(_ node: BookmarkNode, toParent: BookmarkNode?, toIndex: Int, actionName: String) {
        let oldParent = store.parent(of: node)
        let oldIndex = store.index(of: node, in: oldParent) ?? 0
        undoManager?.registerUndo(withTarget: self) { target in
            target.performMove(node, toParent: oldParent, toIndex: oldIndex, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        store.removeNode(node)
        store.insertNode(node, into: toParent, at: min(toIndex, store.children(of: toParent).count))
        reloadUI()
    }

    // MARK: - Actions

    @objc func newFolder(_ sender: Any?) {
        let selectedRow = outlineView.selectedRow
        var targetParent: BookmarkNode?
        var insertIndex: Int

        if selectedRow >= 0, let selectedNode = outlineView.item(atRow: selectedRow) as? BookmarkNode {
            if selectedNode.isFolder {
                targetParent = selectedNode
                insertIndex = selectedNode.children?.count ?? 0
            } else {
                targetParent = store.parent(of: selectedNode)
                insertIndex = (store.index(of: selectedNode, in: targetParent) ?? 0) + 1
            }
        } else {
            targetParent = nil
            insertIndex = store.rootNodes.count
        }

        let folder = BookmarkNode(title: "新規フォルダ", isFolder: true)
        performInsert(folder, into: targetParent, at: insertIndex, actionName: "新規フォルダ")

        if let targetParent = targetParent {
            outlineView.expandItem(targetParent)
        }

        let row = outlineView.row(forItem: folder)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            DispatchQueue.main.async {
                if let cellView = self.outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? BookmarkCellView {
                    cellView.beginEditing()
                }
            }
        }
    }

    // MARK: - Browser Capture

    /// デフォルトブラウザ（設定 or 自動検出）から URL をキャプチャしてブックマーク追加
    @objc func captureFromFrontmostBrowser(_ sender: Any?) {
        // デフォルトブラウザが設定されていればそれを使う
        if let defaultID = PreferencesViewController.defaultBrowserBundleID,
           let browser = BrowserCapture.browsers.first(where: { $0.bundleID == defaultID }) {
            if let page = BrowserCapture.capture(from: browser) {
                insertCapturedPage(page)
                return
            }
            let alert = NSAlert()
            alert.messageText = "\(browser.name) からURLを取得できませんでした"
            alert.informativeText = "\(browser.name) が起動していてページが表示されていることを確認してください。"
            alert.runModal()
            return
        }
        // 自動検出
        guard let result = BrowserCapture.captureFromFrontmostBrowser() else {
            let alert = NSAlert()
            alert.messageText = "ブラウザからURLを取得できませんでした"
            alert.informativeText = "ブラウザが起動していてページが表示されていることを確認してください。"
            alert.runModal()
            return
        }
        insertCapturedPage(result.page)
    }

    /// 指定ブラウザから URL をキャプチャしてブックマーク追加
    @objc func captureFromBrowser(_ sender: NSMenuItem) {
        guard let browser = sender.representedObject as? BrowserCapture.BrowserDef else { return }
        guard let page = BrowserCapture.capture(from: browser) else {
            let alert = NSAlert()
            alert.messageText = "\(browser.name) からURLを取得できませんでした"
            alert.informativeText = "\(browser.name) が起動していてページが表示されていることを確認してください。"
            alert.runModal()
            return
        }
        insertCapturedPage(page)
    }

    private func insertCapturedPage(_ page: CapturedPage) {
        let selectedRow = outlineView.selectedRow
        var targetParent: BookmarkNode?
        var insertIndex: Int

        if selectedRow >= 0, let selectedNode = outlineView.item(atRow: selectedRow) as? BookmarkNode {
            if selectedNode.isFolder {
                targetParent = selectedNode
                insertIndex = selectedNode.children?.count ?? 0
            } else {
                targetParent = store.parent(of: selectedNode)
                insertIndex = (store.index(of: selectedNode, in: targetParent) ?? 0) + 1
            }
        } else {
            targetParent = nil
            insertIndex = store.rootNodes.count
        }

        let node = BookmarkNode(title: page.title, urlString: page.url)
        performInsert(node, into: targetParent, at: insertIndex, actionName: "ブックマーク追加")

        let row = outlineView.row(forItem: node)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        // favicon を非同期取得
        PageInfoFetcher.fetch(for: page.url) { [weak self] info in
            guard let self = self else { return }
            if let data = info.faviconData {
                node.faviconData = data
                self.store.save()
                let r = self.outlineView.row(forItem: node)
                if r >= 0 {
                    self.outlineView.reloadData(forRowIndexes: IndexSet(integer: r),
                                                 columnIndexes: IndexSet(integer: 0))
                }
            }
        }
    }

    /// 確認ダイアログ付き削除（Delete キーから呼ばれる）
    func confirmAndDeleteSelectedItems() {
        let selectedRows = outlineView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        let nodes = selectedRows.compactMap { outlineView.item(atRow: $0) as? BookmarkNode }
        guard !nodes.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        if nodes.count == 1 {
            alert.messageText = "「\(nodes[0].title)」を削除しますか？"
        } else {
            alert.messageText = "\(nodes.count) 個の項目を削除しますか？"
        }
        alert.informativeText = "この操作は「取り消す」(Cmd+Z) で元に戻せます。"
        alert.addButton(withTitle: "削除")
        alert.addButton(withTitle: "キャンセル")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        deleteItems(nodes)
    }

    /// メニューからの削除（確認なし、Undo 可能）
    @objc func deleteSelectedItems(_ sender: Any?) {
        let selectedRows = outlineView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }
        let nodes = selectedRows.compactMap { outlineView.item(atRow: $0) as? BookmarkNode }
        deleteItems(nodes)
    }

    private func deleteItems(_ nodes: [BookmarkNode]) {
        guard !nodes.isEmpty else { return }
        undoManager?.beginUndoGrouping()
        for node in nodes {
            performRemove(node, actionName: "削除")
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("削除")
    }

    // MARK: - Paste URL as New Bookmark

    @objc func pasteURLAsBookmark(_ sender: Any?) {
        let pb = NSPasteboard.general
        var urlString: String?

        // クリップボードから URL を取得
        if let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           str.hasPrefix("http://") || str.hasPrefix("https://") {
            urlString = str
        } else if let str = pb.string(forType: .URL)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            urlString = str
        }

        guard let url = urlString, !url.isEmpty else {
            NSSound.beep()
            return
        }

        let domain = URL(string: url)?.host ?? url
        let node = BookmarkNode(title: "", urlString: url)

        showCreateDialog(for: node, defaultTitle: domain)
    }

    private func showCreateDialog(for node: BookmarkNode, defaultTitle: String) {
        node.title = defaultTitle
        let editVC = BookmarkEditViewController(node: node, mode: .create)
        editVC.onSave = { [weak self] in
            guard let self = self else { return }

            let selectedRow = self.outlineView.selectedRow
            var targetParent: BookmarkNode?
            var insertIndex: Int
            if selectedRow >= 0, let sel = self.outlineView.item(atRow: selectedRow) as? BookmarkNode {
                if sel.isFolder {
                    targetParent = sel
                    insertIndex = sel.children?.count ?? 0
                } else {
                    targetParent = self.store.parent(of: sel)
                    insertIndex = (self.store.index(of: sel, in: targetParent) ?? 0) + 1
                }
            } else {
                targetParent = nil
                insertIndex = self.store.rootNodes.count
            }

            self.performInsert(node, into: targetParent, at: insertIndex, actionName: "ブックマーク追加")

            let row = self.outlineView.row(forItem: node)
            if row >= 0 {
                self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }

            // favicon を非同期取得
            if let urlStr = node.urlString {
                PageInfoFetcher.fetch(for: urlStr) { [weak self] info in
                    guard let self = self else { return }
                    if let data = info.faviconData {
                        node.faviconData = data
                        self.store.save()
                        let r = self.outlineView.row(forItem: node)
                        if r >= 0 {
                            self.outlineView.reloadData(forRowIndexes: IndexSet(integer: r),
                                                         columnIndexes: IndexSet(integer: 0))
                        }
                    }
                }
            }
        }
        let window = NSWindow(contentViewController: editVC)
        window.title = "ブックマークを作成"
        window.styleMask = [.titled, .closable]
        view.window?.beginSheet(window)
    }

    func beginEditingSelectedItem() {
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        if let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? BookmarkCellView {
            cellView.beginEditing()
        }
    }

    // MARK: - Context Menu

    func contextMenu(for row: Int) -> NSMenu {
        let menu = NSMenu()

        if row >= 0, let node = outlineView.item(atRow: row) as? BookmarkNode {
            if !node.isFolder, let urlStr = node.urlString, URL(string: urlStr) != nil {
                // Open in browsers
                let browsers = BrowserHelper.installedBrowsers()
                for browser in browsers {
                    let item = NSMenuItem(title: "\(browser.name) で開く",
                                          action: #selector(openInBrowserAction(_:)),
                                          keyEquivalent: "")
                    item.representedObject = BrowserOpenInfo(node: node, browser: browser)
                    item.target = self
                    menu.addItem(item)
                }
                if !browsers.isEmpty {
                    menu.addItem(.separator())
                }
            }

            // カラーラベル
            let colorItem = NSMenuItem(title: "カラーラベル", action: nil, keyEquivalent: "")
            colorItem.submenu = Self.buildColorTagMenu(target: self, currentTag: node.colorTag)
            menu.addItem(colorItem)

            menu.addItem(.separator())

            let editItem = NSMenuItem(title: "情報を編集…",
                                       action: #selector(editContextAction(_:)),
                                       keyEquivalent: "")
            editItem.representedObject = node
            editItem.target = self
            menu.addItem(editItem)

            let renameItem = NSMenuItem(title: "名前を変更",
                                        action: #selector(renameAction(_:)),
                                        keyEquivalent: "")
            renameItem.target = self
            menu.addItem(renameItem)

            let deleteItem = NSMenuItem(title: "削除",
                                        action: #selector(deleteSelectedItems(_:)),
                                        keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
        }

        menu.addItem(.separator())
        let newFolderItem = NSMenuItem(title: "新規フォルダ",
                                       action: #selector(newFolder(_:)),
                                       keyEquivalent: "")
        newFolderItem.target = self
        menu.addItem(newFolderItem)

        return menu
    }

    @objc private func openInBrowserAction(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? BrowserOpenInfo,
              let urlStr = info.node.urlString,
              let url = URL(string: urlStr) else { return }
        info.node.recordAccess()
        store.save()
        BrowserHelper.open(url: url, with: info.browser)
    }

    @objc func setColorTagAction(_ sender: NSMenuItem) {
        let tag = sender.tag
        let selectedRows = outlineView.selectedRowIndexes
        for row in selectedRows {
            if let node = outlineView.item(atRow: row) as? BookmarkNode {
                node.colorTag = tag
                node.recordEdit()
            }
        }
        store.save()
        outlineView.reloadData()
    }

    @objc private func editContextAction(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? BookmarkNode else { return }
        showEditDialog(for: node)
    }

    @objc private func renameAction(_ sender: Any?) {
        beginEditingSelectedItem()
    }

    @objc func renameFromMenu(_ sender: Any?) {
        beginEditingSelectedItem()
    }

    /// ブックマーク編集ダイアログを表示
    @objc func editSelectedBookmark(_ sender: Any?) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? BookmarkNode else { return }
        showEditDialog(for: node)
    }

    func showEditDialog(for node: BookmarkNode) {
        let editVC = BookmarkEditViewController(node: node)
        editVC.onSave = { [weak self] in
            guard let self = self else { return }
            self.store.save()
            self.outlineView.reloadData()
            self.restoreExpandedState()
        }
        let window = NSWindow(contentViewController: editVC)
        window.title = node.isFolder ? "Edit Folder" : "Edit Bookmark"
        window.styleMask = [.titled, .closable]
        view.window?.beginSheet(window)
    }

    // MARK: - Repair URL Titles

    /// タイトルがURLのままのブックマークを検出し、ページタイトルを再取得する
    private func repairUrlTitles() {
        repairUrlTitles(in: store.rootNodes)
    }

    private func repairUrlTitles(in nodes: [BookmarkNode]) {
        for node in nodes {
            if let children = node.children {
                repairUrlTitles(in: children)
            }
            guard !node.isFolder,
                  let urlStr = node.urlString,
                  node.title == urlStr || node.title.hasPrefix("http://") || node.title.hasPrefix("https://") else {
                continue
            }
            // タイトルをまずドメインに置き換え
            if let host = URL(string: urlStr)?.host {
                node.title = host
            }
            // ページタイトルを非同期で取得して上書き
            PageInfoFetcher.fetch(for: urlStr) { [weak self] info in
                guard let self = self else { return }
                var changed = false
                if let pageTitle = info.title {
                    node.title = pageTitle
                    changed = true
                }
                if node.faviconData == nil, let data = info.faviconData {
                    node.faviconData = data
                    changed = true
                }
                if changed {
                    self.store.save()
                    let row = self.outlineView.row(forItem: node)
                    if row >= 0 {
                        self.outlineView.reloadData(forRowIndexes: IndexSet(integer: row),
                                                     columnIndexes: IndexSet(integer: 0))
                    }
                }
            }
        }
        store.save()
        outlineView.reloadData()
    }

    // MARK: - Expanded State Persistence

    func saveExpandedState() {
        var expandedIDs: [String] = []
        collectExpandedIDs(nodes: store.rootNodes, into: &expandedIDs)
        UserDefaults.standard.set(expandedIDs, forKey: Self.expandedKey)
    }

    private func collectExpandedIDs(nodes: [BookmarkNode], into ids: inout [String]) {
        for node in nodes {
            if node.isFolder {
                node.isExpanded = outlineView.isItemExpanded(node)
                if node.isExpanded {
                    ids.append(node.id.uuidString)
                }
                if let children = node.children {
                    collectExpandedIDs(nodes: children, into: &ids)
                }
            }
        }
    }

    private func restoreExpandedState() {
        guard let ids = UserDefaults.standard.stringArray(forKey: Self.expandedKey) else { return }
        let idSet = Set(ids)
        expandNodes(store.rootNodes, matching: idSet)
    }

    private func expandNodes(_ nodes: [BookmarkNode], matching idSet: Set<String>) {
        for node in nodes {
            if node.isFolder {
                if idSet.contains(node.id.uuidString) || node.isExpanded {
                    outlineView.expandItem(node)
                }
                if let children = node.children {
                    expandNodes(children, matching: idSet)
                }
            }
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension OutlineViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? BookmarkNode {
            return node.children?.count ?? 0
        }
        return store.rootNodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? BookmarkNode {
            return node.children![index]
        }
        return store.rootNodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? BookmarkNode else { return false }
        return node.isFolder
    }

    // MARK: Drag Source

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? BookmarkNode else { return nil }
        let pbItem = NSPasteboardItem()
        pbItem.setString(node.id.uuidString, forType: Self.bookmarkUTI)
        if let urlStr = node.urlString {
            pbItem.setString(urlStr, forType: .string)
            pbItem.setString(urlStr, forType: .init("public.url"))
            pbItem.setString(node.title, forType: .init("public.url-name"))
        }
        return pbItem
    }

    // MARK: Drag Validation

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let pb = info.draggingPasteboard

        // Internal move
        if pb.availableType(from: [Self.bookmarkUTI]) != nil {
            // Dropping ON an item
            if index == NSOutlineViewDropOnItemIndex {
                guard let target = item as? BookmarkNode, target.isFolder else {
                    return []
                }
                // Prevent dropping into own descendants
                let draggedIDs = pb.pasteboardItems?.compactMap({
                    $0.string(forType: Self.bookmarkUTI).flatMap(UUID.init(uuidString:))
                }) ?? []
                for id in draggedIDs {
                    if let node = store.findNode(by: id), store.isDescendant(target, of: node) {
                        return []
                    }
                }
            } else if let target = item as? BookmarkNode, !target.isFolder {
                return []
            }
            return .move
        }

        // External URL drop
        if pb.availableType(from: [.init("public.url"), .URL, .string]) != nil {
            if index == NSOutlineViewDropOnItemIndex {
                if let target = item as? BookmarkNode, !target.isFolder {
                    return []
                }
            }
            return .copy
        }

        return []
    }

    // MARK: Drop Accept

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                     item: Any?, childIndex index: Int) -> Bool {
        let pb = info.draggingPasteboard
        let targetParent = item as? BookmarkNode
        let targetIndex = index == NSOutlineViewDropOnItemIndex
            ? store.children(of: targetParent).count
            : index

        // Internal move
        if let items = pb.pasteboardItems,
           items.first?.string(forType: Self.bookmarkUTI) != nil {
            let draggedIDs = items.compactMap {
                $0.string(forType: Self.bookmarkUTI).flatMap(UUID.init(uuidString:))
            }
            let nodes = draggedIDs.compactMap { store.findNode(by: $0) }
            guard !nodes.isEmpty else { return false }

            undoManager?.beginUndoGrouping()
            // 各ノードの元位置を記録してから移動
            var insertIdx = targetIndex
            for node in nodes {
                let oldParent = store.parent(of: node)
                let oldIndex = store.index(of: node, in: oldParent) ?? 0
                store.removeNode(node)
                let clampedIdx = min(insertIdx, store.children(of: targetParent).count)
                store.insertNode(node, into: targetParent, at: clampedIdx)
                // Undo: 元の位置に戻す
                undoManager?.registerUndo(withTarget: self) { target in
                    target.performMove(node, toParent: oldParent, toIndex: oldIndex, actionName: "移動")
                }
                insertIdx = clampedIdx + 1
            }
            undoManager?.endUndoGrouping()
            undoManager?.setActionName("移動")

            reloadUI()
            return true
        }

        // External URL drop
        return acceptExternalDrop(info: info, targetParent: targetParent, targetIndex: targetIndex)
    }

    private func acceptExternalDrop(info: NSDraggingInfo, targetParent: BookmarkNode?, targetIndex: Int) -> Bool {
        let pb = info.draggingPasteboard

        // Try to get URLs from pasteboard
        var urls: [(url: String, title: String?)] = []

        // Try reading URLs with class
        if let pasteboardURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] {
            for nsurl in pasteboardURLs {
                if let urlStr = nsurl.absoluteString {
                    urls.append((url: urlStr, title: nil))
                }
            }
        }

        // If no URLs found, try string
        if urls.isEmpty, let str = pb.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                urls.append((url: trimmed, title: nil))
            }
        }

        guard !urls.isEmpty else { return false }

        // Try to get title from pasteboard
        let pbTitle = pb.string(forType: .init("public.url-name"))

        undoManager?.beginUndoGrouping()
        var insertIdx = targetIndex
        for urlInfo in urls {
            let domain = URL(string: urlInfo.url)?.host ?? urlInfo.url
            let title = urlInfo.title ?? pbTitle ?? domain
            let node = BookmarkNode(title: title, urlString: urlInfo.url)
            performInsert(node, into: targetParent, at: insertIdx, actionName: "ドロップ")
            insertIdx += 1

            // ページタイトルとファビコンを非同期取得
            PageInfoFetcher.fetch(for: urlInfo.url) { [weak self] info in
                guard let self = self else { return }
                var changed = false
                if pbTitle == nil && urlInfo.title == nil, let pageTitle = info.title {
                    node.title = pageTitle
                    changed = true
                }
                if let faviconData = info.faviconData {
                    node.faviconData = faviconData
                    changed = true
                }
                if changed {
                    self.store.save()
                    DispatchQueue.main.async {
                        let row = self.outlineView.row(forItem: node)
                        if row >= 0 {
                            self.outlineView.reloadData(forRowIndexes: IndexSet(integer: row),
                                                         columnIndexes: IndexSet(integer: 0))
                        }
                    }
                }
            }
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("ドロップ")
        return true
    }
}

// MARK: - NSOutlineViewDelegate

extension OutlineViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? BookmarkNode, let column = tableColumn else { return nil }

        if column.identifier.rawValue == "TitleColumn" {
            let cellID = NSUserInterfaceItemIdentifier("BookmarkCell")
            let cellView: BookmarkCellView
            if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? BookmarkCellView {
                cellView = reused
            } else {
                cellView = BookmarkCellView()
                cellView.identifier = cellID
            }
            cellView.configure(with: node)
            cellView.onTitleEdited = { [weak self] newTitle in
                node.title = newTitle
                node.recordEdit()
                self?.store.save()
            }
            return cellView
        }

        if column.identifier.rawValue == "DateColumn" {
            let cellID = NSUserInterfaceItemIdentifier("DateCell")
            let cellView: NSTableCellView
            if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
                cellView = reused
            } else {
                cellView = NSTableCellView()
                let tf = NSTextField()
                tf.isBordered = false
                tf.drawsBackground = false
                tf.isEditable = false
                tf.isSelectable = false
                tf.font = NSFont.systemFont(ofSize: 11)
                tf.textColor = .secondaryLabelColor
                tf.lineBreakMode = .byTruncatingTail
                tf.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(tf)
                cellView.textField = tf
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                    tf.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                ])
                cellView.identifier = cellID
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            cellView.textField?.stringValue = formatter.string(from: node.dateAdded)
            return cellView
        }

        return nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }
}

// MARK: - Color Tag Menu Builder

extension OutlineViewController {
    /// カラードット付きのカラーラベルメニューを構築する（コンテキストメニュー・メインメニュー共通）
    static func buildColorTagMenu(target: AnyObject? = nil, currentTag: Int = -1) -> NSMenu {
        let menu = NSMenu()
        let defs: [(String, NSColor?)] = [
            ("なし",   nil),
            ("レッド",   .systemRed),
            ("オレンジ", .systemOrange),
            ("イエロー", .systemYellow),
            ("グリーン", .systemGreen),
            ("ブルー",   .systemBlue),
            ("パープル", .systemPurple),
            ("グレイ",   .systemGray),
        ]
        for (i, (name, color)) in defs.enumerated() {
            let item = NSMenuItem(title: name,
                                  action: #selector(OutlineViewController.setColorTagAction(_:)),
                                  keyEquivalent: "")
            item.tag = i
            item.target = target
            if i == currentTag { item.state = .on }
            if let color = color {
                item.image = colorDotImage(color: color, size: 12)
            }
            menu.addItem(item)
        }
        return menu
    }

    private static func colorDotImage(color: NSColor, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

// MARK: - Helper Types

private struct BrowserOpenInfo {
    let node: BookmarkNode
    let browser: BrowserInfo
}
