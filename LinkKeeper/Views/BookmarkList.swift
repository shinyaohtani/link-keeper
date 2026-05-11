import AppKit

/// ブックマークリストのメインビューコントローラ。
class BookmarkList: NSViewController {
    private(set) var outlineView: BookmarkOutline!
    private var scrollView: NSScrollView!
    let store: BookmarkStore
    let catalog: BrowserCatalog
    private let expandedKey = "LinkKeeper.expandedNodeIDs"
    private let bookmarkUTI = NSPasteboard.PasteboardType("com.linkkeeper.bookmark-id")
    private let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

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

    // MARK: - Undo + Insert with Lookup（統合）

    func performInsert(_ node: BookmarkNode, into parent: BookmarkNode?, at idx: Int, actionName: String, lookup: Bool = false) {
        undoManager?.registerUndo(withTarget: self) { $0.performRemove(node, actionName: actionName) }
        undoManager?.setActionName(actionName)
        store.insertNode(node, into: parent, at: idx)
        reloadUI()
        if lookup { lookupAndUpdate(node) }
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

    func reloadUI() {
        outlineView.reloadData()
        restoreExpandedState()
        store.save()
    }

    // MARK: - Page Info Lookup（1箇所に統合）

    /// favicon を再取得し、Undo 登録する。完了時に completion を呼ぶ。
    func reloadFavicon(for node: BookmarkNode, completion: @escaping () -> Void) {
        guard let urlStr = node.urlString else { completion(); return }
        let oldData = node.faviconData
        PageLookup(urlString: urlStr).result { [weak self] info in
            guard let self = self else { completion(); return }
            guard let newData = info.faviconData else {
                NSSound.beep()
                completion()
                return
            }
            node.faviconData = newData
            self.undoManager?.registerUndo(withTarget: self) { target in
                node.faviconData = oldData
                target.store.save()
                target.reloadUI()
            }
            self.undoManager?.setActionName("ファビコン再取得")
            self.store.save()
            let row = self.outlineView.row(forItem: node)
            if row >= 0 {
                self.outlineView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
            }
            completion()
        }
    }

    func lookupAndUpdate(_ node: BookmarkNode) {
        guard let urlStr = node.urlString else { return }
        PageLookup(urlString: urlStr).result { [weak self] info in
            guard let self = self else { return }
            var changed = false
            if let title = info.title, node.title == node.host { node.title = title; changed = true }
            if let data = info.faviconData { node.faviconData = data; changed = true }
            guard changed else { return }
            self.store.save()
            let row = self.outlineView.row(forItem: node)
            guard row >= 0 else { return }
            self.outlineView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        }
    }
}

// MARK: - Actions

extension BookmarkList {
    @objc func newFolder(_ sender: Any?) {
        let selected = selectedNode()
        let (parent, idx) = store.insertionPoint(for: selected)
        let folder = BookmarkNode(title: "新規フォルダ", isFolder: true)
        folder.isExpanded = true
        performInsert(folder, into: parent, at: idx, actionName: "新規フォルダ")
        if let parent = parent { outlineView.expandItem(parent) }
        outlineView.expandItem(folder)
        selectAndEdit(folder)
    }

    @objc func captureFromDefault(_ sender: Any?) {
        let defaultID = UserDefaults.standard.string(forKey: "LinkKeeper.defaultCaptureBrowser")
        guard let id = defaultID, let browser = catalog.browser(for: id) else {
            let alert = NSAlert()
            alert.messageText = "よく使うブラウザが設定されていません"
            alert.informativeText = "設定画面またはメニューの「よく使うブラウザを設定…」から設定してください。"
            alert.runModal()
            return
        }
        guard let page = browser.frontPage else {
            showCaptureError(browser.name); return
        }
        insertCapturedPage(page)
    }

    @objc func captureFromBrowser(_ sender: NSMenuItem) {
        guard let wrapper = sender.representedObject as? BrowserWrapper else { return }
        guard let page = wrapper.browser.frontPage else {
            showCaptureError(wrapper.browser.name); return
        }
        insertCapturedPage(page)
    }

    @objc func pasteURLAsBookmark(_ sender: Any?) {
        let pb = NSPasteboard.general
        let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? pb.string(forType: .URL)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let urlStr = str, urlStr.hasPrefix("http://") || urlStr.hasPrefix("https://") else {
            NSSound.beep(); return
        }
        let node = BookmarkNode(title: URL(string: urlStr)?.host ?? urlStr, urlString: urlStr)
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
        guard let node = selectedNode() else { return }
        showEditSheet(for: node)
    }

    @objc func renameFromMenu(_ sender: Any?) { beginEditingSelectedItem() }

    @objc func setColorTagAction(_ sender: NSMenuItem) {
        for node in selectedNodes() { node.colorTag = sender.tag; node.recordEdit() }
        store.save()
        outlineView.reloadData()
    }

    @objc func openInBrowser(_ sender: NSMenuItem) {
        guard let req = sender.representedObject as? OpenRequest,
              let urlStr = req.node.urlString, let url = URL(string: urlStr) else { return }
        req.node.recordAccess()
        store.save()
        req.browser.open(url: url)
    }

    @objc func editContextItem(_ sender: NSMenuItem) {
        guard let node = selectedNode() else { return }
        showEditSheet(for: node)
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
        let node = row >= 0 ? outlineView.item(atRow: row) as? BookmarkNode : nil
        return ContextMenu(node: node, catalog: catalog, target: self).menu
    }
}

// MARK: - Sheets

extension BookmarkList {
    func showEditSheet(for node: BookmarkNode) {
        let vc = EditSheet(node: node, mode: .edit)
        vc.onSave = { [weak self] in self?.reloadUI() }
        vc.onFaviconReload = { [weak self] node, completion in
            self?.reloadFavicon(for: node, completion: completion)
        }
        presentSheet(vc, title: node.isFolder ? "フォルダを編集" : "ブックマークを編集")
    }

    private func showCreateSheet(for node: BookmarkNode) {
        let vc = EditSheet(node: node, mode: .create)
        vc.onSave = { [weak self] in
            guard let self = self else { return }
            let selected = self.selectedNode()
            let (parent, idx) = self.store.insertionPoint(for: selected)
            self.performInsert(node, into: parent, at: idx, actionName: "ブックマーク追加", lookup: true)
            self.selectRow(for: node)
        }
        presentSheet(vc, title: "ブックマークを作成")
    }

    private func presentSheet(_ vc: NSViewController, title: String) {
        let w = NSWindow(contentViewController: vc)
        w.title = title
        w.styleMask = [.titled, .closable]
        view.window?.beginSheet(w)
    }
}

// MARK: - Expanded State

extension BookmarkList {
    func saveExpandedState() {
        // node.isExpanded はデリゲートでリアルタイム更新済み。
        // 見えていない下層の状態もモデルに保持されているのでそのまま保存。
        var ids: [String] = []
        collectExpandedIDs(store.rootNodes, into: &ids)
        UserDefaults.standard.set(ids, forKey: expandedKey)
    }

    func restoreExpandedState() {
        guard let ids = UserDefaults.standard.stringArray(forKey: expandedKey) else { return }
        let idSet = Set(ids)
        applyExpandedState(store.rootNodes, matching: idSet)
    }

    private func collectExpandedIDs(_ nodes: [BookmarkNode], into ids: inout [String]) {
        for node in nodes where node.isFolder {
            if node.isExpanded { ids.append(node.id.uuidString) }
            if let children = node.children { collectExpandedIDs(children, into: &ids) }
        }
    }

    private func applyExpandedState(_ nodes: [BookmarkNode], matching ids: Set<String>) {
        // node.isExpanded はデリゲートでリアルタイム更新されている真実の情報源。
        // UserDefaults の ids は前回 saveExpandedState 時の古い状態のため、OR を取ると
        // ユーザーが閉じたフォルダが再展開されるバグになる。node.isExpanded のみ参照する。
        for node in nodes where node.isFolder {
            if node.isExpanded { outlineView.expandItem(node) }
            if let children = node.children { applyExpandedState(children, matching: ids) }
        }
    }

    /// 全子孫を再帰的に展開
    private func expandAllDescendants(of node: BookmarkNode) {
        guard let children = node.children else { return }
        for child in children where child.isFolder {
            child.isExpanded = true
            outlineView.expandItem(child)
            expandAllDescendants(of: child)
        }
    }

    /// 全子孫を再帰的に折りたたみ
    private func collapseAllDescendants(of node: BookmarkNode) {
        guard let children = node.children else { return }
        for child in children where child.isFolder {
            collapseAllDescendants(of: child)
            child.isExpanded = false
            outlineView.collapseItem(child)
        }
    }
}

// MARK: - Private Helpers

extension BookmarkList {
    private func selectedNode() -> BookmarkNode? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? BookmarkNode
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
        let selected = selectedNode()
        let (parent, idx) = store.insertionPoint(for: selected)
        let node = BookmarkNode(title: page.title, urlString: page.url)
        performInsert(node, into: parent, at: idx, actionName: "ブックマーク追加", lookup: true)
        selectRow(for: node)
    }

    private func selectRow(for node: BookmarkNode) {
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func selectAndEdit(_ node: BookmarkNode) {
        selectRow(for: node)
        DispatchQueue.main.async {
            let row = self.outlineView.row(forItem: node)
            guard row >= 0 else { return }
            (self.outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? BookmarkCell)?.beginEditing()
        }
    }

    private func showCaptureError(_ name: String?) {
        let browser = name ?? "ブラウザ"
        let alert = NSAlert()
        alert.messageText = "\(browser) からURLを取得できませんでした"
        alert.informativeText = "\(browser) が起動していてページが表示されていることを確認してください。"
        alert.runModal()
    }

    private func repairUrlTitles() {
        repairNodes(store.rootNodes)
        store.save()
        outlineView.reloadData()
    }

    private func repairNodes(_ nodes: [BookmarkNode]) {
        for node in nodes {
            if let children = node.children { repairNodes(children) }
            guard node.needsTitleRepair else { continue }
            if let host = node.host { node.title = host }
            lookupAndUpdate(node)
        }
    }

    private func configureOutlineView() {
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

        // autosave はカラム追加後に設定（保存済み幅の復元のため）
        outlineView.autosaveName = "LinkKeeperOutline"
        outlineView.autosaveTableColumns = true

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
            if idx == NSOutlineViewDropOnItemIndex, let t = item as? BookmarkNode, !t.isFolder { return [] }
            return .copy
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

    private func acceptInternalDrop(items: [NSPasteboardItem], parent: BookmarkNode?, targetIdx: Int) -> Bool {
        let nodes = items.compactMap { $0.string(forType: bookmarkUTI).flatMap(UUID.init) }
            .compactMap { store.findNode(by: $0) }
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
            for u in nsurls { if let s = u.absoluteString { urls.append((url: s, title: nil)) } }
        }
        if urls.isEmpty, let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           str.hasPrefix("http://") || str.hasPrefix("https://") {
            urls.append((url: str, title: nil))
        }
        guard !urls.isEmpty else { return false }

        let pbTitle = pb.string(forType: .init("public.url-name"))
        undoManager?.beginUndoGrouping()
        var insertIdx = targetIdx
        for info in urls {
            let domain = URL(string: info.url)?.host ?? info.url
            let node = BookmarkNode(title: info.title ?? pbTitle ?? domain, urlString: info.url)
            performInsert(node, into: parent, at: insertIdx, actionName: "ドロップ", lookup: true)
            insertIdx += 1
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
        if column.identifier.rawValue == "TitleColumn" { return titleCell(for: node) }
        if column.identifier.rawValue == "DateColumn" { return dateCell(for: node) }
        return nil
    }

    func outlineView(_ ov: NSOutlineView, shouldSelectItem item: Any) -> Bool { true }

    // 展開/折りたたみ状態をモデルにリアルタイム同期
    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? BookmarkNode else { return }
        node.isExpanded = true
        // Option+Click: 全子孫を展開
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            expandAllDescendants(of: node)
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? BookmarkNode else { return }
        node.isExpanded = false
        // Option+Click: 全子孫を折りたたみ
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            collapseAllDescendants(of: node)
        }
    }

    private func titleCell(for node: BookmarkNode) -> BookmarkCell {
        let cellID = NSUserInterfaceItemIdentifier("BookmarkCell")
        let cell = outlineView.makeView(withIdentifier: cellID, owner: self) as? BookmarkCell ?? BookmarkCell()
        cell.identifier = cellID
        cell.configure(with: node)
        cell.onTitleEdited = { [weak self] title in
            node.title = title; node.recordEdit(); self?.store.save()
        }
        cell.onOpen = { [weak self] in
            guard let urlStr = node.urlString, let url = URL(string: urlStr) else { return }
            node.recordAccess()
            self?.store.save()
            NSWorkspace.shared.open(url)
        }
        return cell
    }

    private func dateCell(for node: BookmarkNode) -> NSTableCellView {
        let cellID = NSUserInterfaceItemIdentifier("DateCell")
        if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            reused.textField?.stringValue = dateFormat.string(from: node.dateAdded)
            return reused
        }
        let cell = NSTableCellView()
        let tf = NSTextField(labelWithString: dateFormat.string(from: node.dateAdded))
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
        return cell
    }
}
