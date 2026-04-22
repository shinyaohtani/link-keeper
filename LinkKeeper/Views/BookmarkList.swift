import AppKit

/// ブックマークリストのメインビューコントローラ。
class BookmarkList: NSViewController {
    private(set) var outlineView: BookmarkOutline!
    private var scrollView: NSScrollView!
    let store: BookmarkStore
    private let catalog: BrowserCatalog
    private let expandedKey = "LinkKeeper.expandedNodeIDs"
    private let bookmarkUTI = NSPasteboard.PasteboardType("com.linkkeeper.bookmark-id")

    init(store: BookmarkStore, catalog: BrowserCatalog) {
        self.store = store
        self.catalog = catalog
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        outlineView = BookmarkOutline()
        configureOutlineView()
        scrollView.documentView = outlineView
        self.view = scrollView
        restoreExpandedState()
        repairUrlTitles()
    }
}

// MARK: - Undo Operations

extension BookmarkList {
    func performInsert(_ node: BookmarkNode, into parent: BookmarkNode?, at idx: Int, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { $0.performRemove(node, actionName: actionName) }
        undoManager?.setActionName(actionName)
        store.insertNode(node, into: parent, at: idx)
        reloadUI()
    }

    func performRemove(_ node: BookmarkNode, actionName: String) {
        let parent = store.parent(of: node)
        let idx = store.index(of: node, in: parent) ?? 0
        undoManager?.registerUndo(withTarget: self) { $0.performInsert(node, into: parent, at: idx, actionName: actionName) }
        undoManager?.setActionName(actionName)
        store.removeNode(node)
        reloadUI()
    }

    func performMove(_ node: BookmarkNode, toParent: BookmarkNode?, toIdx: Int, actionName: String) {
        let oldParent = store.parent(of: node)
        let oldIdx = store.index(of: node, in: oldParent) ?? 0
        undoManager?.registerUndo(withTarget: self) { $0.performMove(node, toParent: oldParent, toIdx: oldIdx, actionName: actionName) }
        undoManager?.setActionName(actionName)
        store.removeNode(node)
        store.insertNode(node, into: toParent, at: min(toIdx, store.children(of: toParent).count))
        reloadUI()
    }

    private func reloadUI() {
        outlineView.reloadData()
        restoreExpandedState()
        store.save()
    }
}

// MARK: - Actions

extension BookmarkList {
    @objc func newFolder(_ sender: Any?) {
        let (parent, idx) = insertionPoint()
        let folder = BookmarkNode(title: "新規フォルダ", isFolder: true)
        performInsert(folder, into: parent, at: idx, actionName: "新規フォルダ")
        if let parent = parent { outlineView.expandItem(parent) }
        selectAndEdit(folder)
    }

    @objc func captureFromDefault(_ sender: Any?) {
        let settingsPanel = SettingsPanel()
        _ = settingsPanel.view  // load defaults
        if let id = settingsPanel.defaultBundleID,
           let browser = catalog.browser(for: id) {
            guard let page = browser.frontPage else {
                showAlert("\(browser.name) からURLを取得できませんでした",
                          info: "\(browser.name) が起動していてページが表示されていることを確認してください。")
                return
            }
            insertCapturedPage(page)
            return
        }
        guard let result = catalog.captureFromFrontmost() else {
            showAlert("ブラウザからURLを取得できませんでした",
                      info: "ブラウザが起動していてページが表示されていることを確認してください。")
            return
        }
        insertCapturedPage(result.page)
    }

    @objc func captureFromBrowser(_ sender: NSMenuItem) {
        guard let wrapper = sender.representedObject as? BrowserWrapper else { return }
        guard let page = wrapper.browser.frontPage else {
            showAlert("\(wrapper.browser.name) からURLを取得できませんでした",
                      info: "\(wrapper.browser.name) が起動していてページが表示されていることを確認してください。")
            return
        }
        insertCapturedPage(page)
    }

    @objc func pasteURLAsBookmark(_ sender: Any?) {
        let pb = NSPasteboard.general
        let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? pb.string(forType: .URL)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let urlStr = str, urlStr.hasPrefix("http://") || urlStr.hasPrefix("https://") else {
            NSSound.beep()
            return
        }
        let domain = URL(string: urlStr)?.host ?? urlStr
        let node = BookmarkNode(title: domain, urlString: urlStr)
        showCreateSheet(for: node)
    }

    @objc func deleteSelectedItems(_ sender: Any?) {
        let nodes = selectedNodes()
        guard !nodes.isEmpty else { return }
        deleteItems(nodes)
    }

    func confirmAndDeleteSelectedItems() {
        let nodes = selectedNodes()
        guard !nodes.isEmpty else { return }
        let msg = nodes.count == 1 ? "「\(nodes[0].title)」を削除しますか？" : "\(nodes.count) 個の項目を削除しますか？"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = msg
        alert.informativeText = "この操作は「取り消す」(Cmd+Z) で元に戻せます。"
        alert.addButton(withTitle: "削除")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        deleteItems(nodes)
    }

    @objc func editSelectedBookmark(_ sender: Any?) {
        guard let node = selectedNodes().first else { return }
        showEditSheet(for: node)
    }

    @objc func renameFromMenu(_ sender: Any?) { beginEditingSelectedItem() }

    @objc func setColorTagAction(_ sender: NSMenuItem) {
        for node in selectedNodes() {
            node.colorTag = sender.tag
            node.recordEdit()
        }
        store.save()
        outlineView.reloadData()
    }

    func beginEditingSelectedItem() {
        let row = outlineView.selectedRow
        guard row >= 0,
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? BookmarkCell
        else { return }
        cell.beginEditing()
    }
}

// MARK: - Context Menu

extension BookmarkList {
    func contextMenu(for row: Int) -> NSMenu {
        let menu = NSMenu()
        guard row >= 0, let node = outlineView.item(atRow: row) as? BookmarkNode else {
            menu.addItem(NSMenuItem(title: "新規フォルダ", action: #selector(newFolder(_:)), keyEquivalent: ""))
            menu.items.last?.target = self
            return menu
        }
        addBrowserItems(to: menu, for: node)
        addColorTagItem(to: menu, for: node)
        addEditItems(to: menu, for: node)
        menu.addItem(.separator())
        let folderItem = NSMenuItem(title: "新規フォルダ", action: #selector(newFolder(_:)), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)
        return menu
    }

    private func addBrowserItems(to menu: NSMenu, for node: BookmarkNode) {
        guard !node.isFolder, let urlStr = node.urlString, URL(string: urlStr) != nil else { return }
        for browser in catalog.installed {
            let item = NSMenuItem(title: "\(browser.name) で開く",
                                  action: #selector(openInBrowser(_:)), keyEquivalent: "")
            item.representedObject = OpenRequest(node: node, browser: browser)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    private func addColorTagItem(to menu: NSMenu, for node: BookmarkNode) {
        let colorItem = NSMenuItem(title: "カラーラベル", action: nil, keyEquivalent: "")
        colorItem.submenu = ColorTagMenu(
            currentTag: node.colorTag, target: self, action: #selector(setColorTagAction(_:))
        ).menu
        menu.addItem(colorItem)
        menu.addItem(.separator())
    }

    private func addEditItems(to menu: NSMenu, for node: BookmarkNode) {
        let edit = NSMenuItem(title: "情報を編集…", action: #selector(editContextItem(_:)), keyEquivalent: "")
        edit.representedObject = node
        edit.target = self
        menu.addItem(edit)

        let rename = NSMenuItem(title: "名前を変更", action: #selector(renameFromMenu(_:)), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)

        let delete = NSMenuItem(title: "削除", action: #selector(deleteSelectedItems(_:)), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
    }

    @objc private func openInBrowser(_ sender: NSMenuItem) {
        guard let req = sender.representedObject as? OpenRequest,
              let urlStr = req.node.urlString, let url = URL(string: urlStr) else { return }
        req.node.recordAccess()
        store.save()
        req.browser.open(url: url)
    }

    @objc private func editContextItem(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? BookmarkNode else { return }
        showEditSheet(for: node)
    }
}

// MARK: - Sheets

extension BookmarkList {
    func showEditSheet(for node: BookmarkNode) {
        let vc = EditSheet(node: node, mode: .edit)
        vc.onSave = { [weak self] in
            self?.store.save()
            self?.outlineView.reloadData()
            self?.restoreExpandedState()
        }
        let w = NSWindow(contentViewController: vc)
        w.title = node.isFolder ? "フォルダを編集" : "ブックマークを編集"
        w.styleMask = [.titled, .closable]
        view.window?.beginSheet(w)
    }

    private func showCreateSheet(for node: BookmarkNode) {
        let vc = EditSheet(node: node, mode: .create)
        vc.onSave = { [weak self] in
            guard let self = self else { return }
            let (parent, idx) = self.insertionPoint()
            self.performInsert(node, into: parent, at: idx, actionName: "ブックマーク追加")
            self.selectRow(for: node)
            self.fetchPageInfo(for: node)
        }
        let w = NSWindow(contentViewController: vc)
        w.title = "ブックマークを作成"
        w.styleMask = [.titled, .closable]
        view.window?.beginSheet(w)
    }
}

// MARK: - Expanded State

extension BookmarkList {
    func saveExpandedState() {
        var ids: [String] = []
        collectExpanded(store.rootNodes, into: &ids)
        UserDefaults.standard.set(ids, forKey: expandedKey)
    }

    func restoreExpandedState() {
        guard let ids = UserDefaults.standard.stringArray(forKey: expandedKey) else { return }
        expandNodes(store.rootNodes, matching: Set(ids))
    }

    private func collectExpanded(_ nodes: [BookmarkNode], into ids: inout [String]) {
        for node in nodes where node.isFolder {
            node.isExpanded = outlineView.isItemExpanded(node)
            if node.isExpanded { ids.append(node.id.uuidString) }
            if let children = node.children { collectExpanded(children, into: &ids) }
        }
    }

    private func expandNodes(_ nodes: [BookmarkNode], matching ids: Set<String>) {
        for node in nodes where node.isFolder {
            if ids.contains(node.id.uuidString) || node.isExpanded { outlineView.expandItem(node) }
            if let children = node.children { expandNodes(children, matching: ids) }
        }
    }
}

// MARK: - URL Title Repair

extension BookmarkList {
    private func repairUrlTitles() {
        repairNodes(store.rootNodes)
        store.save()
        outlineView.reloadData()
    }

    private func repairNodes(_ nodes: [BookmarkNode]) {
        for node in nodes {
            if let children = node.children { repairNodes(children) }
            guard !node.isFolder, let urlStr = node.urlString,
                  node.title == urlStr || node.title.hasPrefix("http://") || node.title.hasPrefix("https://")
            else { continue }
            if let host = URL(string: urlStr)?.host { node.title = host }
            fetchPageInfo(for: node)
        }
    }
}

// MARK: - Private Helpers

extension BookmarkList {
    private func insertionPoint() -> (parent: BookmarkNode?, idx: Int) {
        let row = outlineView.selectedRow
        guard row >= 0, let sel = outlineView.item(atRow: row) as? BookmarkNode else {
            return (nil, store.rootNodes.count)
        }
        if sel.isFolder { return (sel, sel.children?.count ?? 0) }
        let parent = store.parent(of: sel)
        return (parent, (store.index(of: sel, in: parent) ?? 0) + 1)
    }

    private func selectedNodes() -> [BookmarkNode] {
        outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? BookmarkNode }
    }

    private func deleteItems(_ nodes: [BookmarkNode]) {
        undoManager?.beginUndoGrouping()
        for node in nodes { performRemove(node, actionName: "削除") }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("削除")
    }

    private func insertCapturedPage(_ page: CapturedPage) {
        let (parent, idx) = insertionPoint()
        let node = BookmarkNode(title: page.title, urlString: page.url)
        performInsert(node, into: parent, at: idx, actionName: "ブックマーク追加")
        selectRow(for: node)
        fetchPageInfo(for: node)
    }

    private func fetchPageInfo(for node: BookmarkNode) {
        guard let urlStr = node.urlString else { return }
        PageLookup(urlString: urlStr).result { [weak self] info in
            guard let self = self else { return }
            var changed = false
            if let title = info.title, node.title == URL(string: urlStr)?.host {
                node.title = title
                changed = true
            }
            if let data = info.faviconData {
                node.faviconData = data
                changed = true
            }
            guard changed else { return }
            self.store.save()
            let row = self.outlineView.row(forItem: node)
            guard row >= 0 else { return }
            self.outlineView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        }
    }

    private func selectRow(for node: BookmarkNode) {
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func selectAndEdit(_ node: BookmarkNode) {
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        DispatchQueue.main.async {
            (self.outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? BookmarkCell)?.beginEditing()
        }
    }

    private func showAlert(_ msg: String, info: String) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText = info
        alert.runModal()
    }

    private func configureOutlineView() {
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

        let titleCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TitleColumn"))
        titleCol.title = "Name"
        titleCol.minWidth = 120
        titleCol.resizingMask = [.userResizingMask, .autoresizingMask]
        outlineView.addTableColumn(titleCol)
        outlineView.outlineTableColumn = titleCol

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
        outlineView.doubleAction = #selector(doubleClicked(_:))

        outlineView.registerForDraggedTypes([
            bookmarkUTI, .URL, .string,
            .init("public.url"), .init("public.url-name"), .init("WebURLsWithTitlesPboardType"),
        ])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
    }

    @objc private func doubleClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? BookmarkNode else { return }
        if node.isFolder {
            if outlineView.isItemExpanded(node) { outlineView.collapseItem(node) }
            else { outlineView.expandItem(node) }
        } else if let urlStr = node.urlString, let url = URL(string: urlStr) {
            node.recordAccess()
            store.save()
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension BookmarkList: NSOutlineViewDataSource {
    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? BookmarkNode)?.children?.count ?? store.rootNodes.count
    }

    func outlineView(_ ov: NSOutlineView, child idx: Int, ofItem item: Any?) -> Any {
        (item as? BookmarkNode)?.children?[idx] ?? store.rootNodes[idx]
    }

    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? BookmarkNode)?.isFolder ?? false
    }

    func outlineView(_ ov: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? BookmarkNode else { return nil }
        let pb = NSPasteboardItem()
        pb.setString(node.id.uuidString, forType: bookmarkUTI)
        if let urlStr = node.urlString {
            pb.setString(urlStr, forType: .string)
            pb.setString(urlStr, forType: .init("public.url"))
            pb.setString(node.title, forType: .init("public.url-name"))
        }
        return pb
    }

    func outlineView(_ ov: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex idx: Int) -> NSDragOperation {
        let pb = info.draggingPasteboard
        if pb.availableType(from: [bookmarkUTI]) != nil {
            return validateInternalDrop(item: item, idx: idx, pb: pb)
        }
        if pb.availableType(from: [.init("public.url"), .URL, .string]) != nil {
            return validateExternalDrop(item: item, idx: idx)
        }
        return []
    }

    func outlineView(_ ov: NSOutlineView, acceptDrop info: NSDraggingInfo,
                     item: Any?, childIndex idx: Int) -> Bool {
        let pb = info.draggingPasteboard
        let parent = item as? BookmarkNode
        let targetIdx = idx == NSOutlineViewDropOnItemIndex ? store.children(of: parent).count : idx

        if let items = pb.pasteboardItems, items.first?.string(forType: bookmarkUTI) != nil {
            return acceptInternalDrop(items: items, parent: parent, targetIdx: targetIdx)
        }
        return acceptExternalDrop(pb: pb, parent: parent, targetIdx: targetIdx)
    }

    private func validateInternalDrop(item: Any?, idx: Int, pb: NSPasteboard) -> NSDragOperation {
        if idx == NSOutlineViewDropOnItemIndex {
            guard let target = item as? BookmarkNode, target.isFolder else { return [] }
            let ids = pb.pasteboardItems?.compactMap { $0.string(forType: bookmarkUTI).flatMap(UUID.init) } ?? []
            for id in ids {
                if let node = store.findNode(by: id), store.isDescendant(target, of: node) { return [] }
            }
        } else if let target = item as? BookmarkNode, !target.isFolder {
            return []
        }
        return .move
    }

    private func validateExternalDrop(item: Any?, idx: Int) -> NSDragOperation {
        if idx == NSOutlineViewDropOnItemIndex, let t = item as? BookmarkNode, !t.isFolder { return [] }
        return .copy
    }

    private func acceptInternalDrop(items: [NSPasteboardItem], parent: BookmarkNode?, targetIdx: Int) -> Bool {
        let ids = items.compactMap { $0.string(forType: bookmarkUTI).flatMap(UUID.init) }
        let nodes = ids.compactMap { store.findNode(by: $0) }
        guard !nodes.isEmpty else { return false }

        undoManager?.beginUndoGrouping()
        var insertIdx = targetIdx
        for node in nodes {
            let oldParent = store.parent(of: node)
            let oldIdx = store.index(of: node, in: oldParent) ?? 0
            store.removeNode(node)
            let clamped = min(insertIdx, store.children(of: parent).count)
            store.insertNode(node, into: parent, at: clamped)
            undoManager?.registerUndo(withTarget: self) { $0.performMove(node, toParent: oldParent, toIdx: oldIdx, actionName: "移動") }
            insertIdx = clamped + 1
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("移動")
        reloadUI()
        return true
    }

    private func acceptExternalDrop(pb: NSPasteboard, parent: BookmarkNode?, targetIdx: Int) -> Bool {
        var urls: [(url: String, title: String?)] = []
        if let nsurls = pb.readObjects(forClasses: [NSURL.self]) as? [NSURL] {
            for nsurl in nsurls {
                if let s = nsurl.absoluteString { urls.append((url: s, title: nil)) }
            }
        }
        if urls.isEmpty, let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           str.hasPrefix("http://") || str.hasPrefix("https://") {
            urls.append((url: str, title: nil))
        }
        guard !urls.isEmpty else { return false }

        let pbTitle = pb.string(forType: .init("public.url-name"))
        undoManager?.beginUndoGrouping()
        var insertIdx = targetIdx
        for urlInfo in urls {
            let domain = URL(string: urlInfo.url)?.host ?? urlInfo.url
            let title = urlInfo.title ?? pbTitle ?? domain
            let node = BookmarkNode(title: title, urlString: urlInfo.url)
            performInsert(node, into: parent, at: insertIdx, actionName: "ドロップ")
            insertIdx += 1
            fetchPageInfo(for: node)
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("ドロップ")
        return true
    }
}

// MARK: - NSOutlineViewDelegate

extension BookmarkList: NSOutlineViewDelegate {
    func outlineView(_ ov: NSOutlineView, viewFor col: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? BookmarkNode, let column = col else { return nil }
        if column.identifier.rawValue == "TitleColumn" { return titleCellView(for: node) }
        if column.identifier.rawValue == "DateColumn" { return dateCellView(for: node) }
        return nil
    }

    func outlineView(_ ov: NSOutlineView, shouldSelectItem item: Any) -> Bool { true }

    private func titleCellView(for node: BookmarkNode) -> BookmarkCell {
        let cellID = NSUserInterfaceItemIdentifier("BookmarkCell")
        let cell = outlineView.makeView(withIdentifier: cellID, owner: self) as? BookmarkCell ?? BookmarkCell()
        cell.identifier = cellID
        cell.configure(with: node)
        cell.onTitleEdited = { [weak self] title in
            node.title = title
            node.recordEdit()
            self?.store.save()
        }
        return cell
    }

    private func dateCellView(for node: BookmarkNode) -> NSTableCellView {
        let cellID = NSUserInterfaceItemIdentifier("DateCell")
        if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            let fmt = DateFormatter()
            fmt.dateStyle = .short
            fmt.timeStyle = .short
            reused.textField?.stringValue = fmt.string(from: node.dateAdded)
            return reused
        }
        let cell = NSTableCellView()
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = NSFont.systemFont(ofSize: 11)
        tf.textColor = .secondaryLabelColor
        tf.lineBreakMode = .byTruncatingTail
        cell.addSubview(tf)
        cell.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.identifier = cellID
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        tf.stringValue = fmt.string(from: node.dateAdded)
        return cell
    }
}

// MARK: - Helper Types

private struct OpenRequest {
    let node: BookmarkNode
    let browser: Browser
}
