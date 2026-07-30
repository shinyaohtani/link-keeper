import AppKit

/// ブックマークリストのメインビューコントローラ。
/// ツリー変更は BookmarkTree、展開状態は OutlineExpansion、外部フォーマット変換は
/// NetscapeBookmark / MarkdownTable に委譲し、本体は UI 組立とアクションの受け口に徹する。
class BookmarkList: NSViewController {
    private(set) var outlineView: BookmarkOutline!
    private var scrollView: NSScrollView!
    private var searchField: NSSearchField!
    private var filter = NodeFilter(query: "")
    let store: BookmarkStore
    let catalog: BrowserCatalog
    private var tree: BookmarkTree!
    private var expansion: OutlineExpansion!
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
        tree = BookmarkTree(store: store)
        tree.reload = { [weak self] in self?.reloadUI() }
        tree.undoManagerProvider = { [weak self] in self?.undoManager }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()
        searchField = makeSearchField()
        container.addSubview(searchField)
        scrollView = makeScrollView()
        container.addSubview(scrollView)
        activateLayout(in: container)
        self.view = container
        setupExpansion()
        repairUrlTitles()
    }

    private func makeSearchField() -> NSSearchField {
        let field = NSSearchField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = "タイトルで絞り込み"
        field.delegate = self
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        return field
    }

    private func makeScrollView() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        outlineView = BookmarkOutline()
        configureOutlineView()
        scroll.documentView = outlineView
        return scroll
    }

    private func activateLayout(in container: NSView) {
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func setupExpansion() {
        expansion = OutlineExpansion(outlineView: outlineView, store: store)
        expansion.isFiltering = { [weak self] in self?.filter.isActive ?? false }
        expansion.restore()
    }

    // MARK: - Reload

    func reloadUI() {
        outlineView.reloadData()
        expansion.restore()
        store.save()
    }

    /// 展開状態を永続化する（ウィンドウを閉じる/終了時に呼ばれる）。
    func saveExpandedState() {
        expansion.save()
    }

    // MARK: - Page Info Lookup（favicon / タイトル補完）

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
        tree.insert(folder, into: parent, at: idx, actionName: "新規フォルダ")
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

// MARK: - Copy / Import / Export

extension BookmarkList {
    private static let tableDateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    /// 選択行を Markdown テーブルとしてクリップボードにコピーする（⌘C）。
    @objc func copy(_ sender: Any?) {
        let nodes = selectedNodes()
        guard !nodes.isEmpty else { NSSound.beep(); return }

        let rows: [[String]] = nodes.map { node in
            [folderPath(of: node),
             node.title,
             node.urlString ?? "",
             Self.tableDateFormat.string(from: node.dateAdded)]
        }
        let table = MarkdownTable(header: ["フォルダ階層", "名称", "URL", "Date Added"], rows: rows)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(table.text, forType: .string)
    }

    /// 全ブックマークを Netscape Bookmark 形式（ブラウザ互換の HTML）でエクスポートする。
    @objc func exportBookmarks(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "bookmarks.html"
        panel.title = "ブックマークをエクスポート"
        panel.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            let document = NetscapeBookmark(nodes: self.store.rootNodes)
            do {
                try document.html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.presentError("エクスポートに失敗しました", error.localizedDescription)
            }
        }
    }

    /// Netscape Bookmark 形式（ブラウザがエクスポートした HTML）をインポートする。
    @objc func importBookmarks(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "ブックマークをインポート"
        panel.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            guard let html = try? String(contentsOf: url, encoding: .utf8) else {
                self.presentError("インポートに失敗しました", "ファイルを読み込めませんでした。")
                return
            }
            let nodes = NetscapeBookmark(html: html).nodes
            guard !nodes.isEmpty else {
                self.presentError("インポートできる項目がありません", "対応形式（Netscape Bookmark HTML）か確認してください。")
                return
            }
            self.insertImported(nodes)
        }
    }

    /// 対象ノードの親フォルダ階層を "親/子" 形式で返す（ルート直下は空文字）。
    private func folderPath(of node: BookmarkNode) -> String {
        var parts: [String] = []
        var current = store.parent(of: node)
        while let folder = current {
            parts.append(folder.title)
            current = store.parent(of: folder)
        }
        return parts.reversed().joined(separator: "/")
    }

    private func insertImported(_ nodes: [BookmarkNode]) {
        let (parent, startIdx) = store.insertionPoint(for: selectedNode())
        var idx = startIdx
        tree.group("インポート") {
            for node in nodes {
                tree.insert(node, into: parent, at: idx, actionName: "インポート")
                idx += 1
            }
        }
        if let parent = parent { outlineView.expandItem(parent) }
    }

    private func presentError(_ message: String, _ info: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
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
            self.tree.insert(node, into: parent, at: idx, actionName: "ブックマーク追加")
            self.lookupAndUpdate(node)
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
        tree.group("削除") {
            for node in nodes { tree.remove(node, actionName: "削除") }
        }
    }

    private func insertCapturedPage(_ page: CapturedPage) {
        let selected = selectedNode()
        let (parent, idx) = store.insertionPoint(for: selected)
        let node = BookmarkNode(title: page.title, urlString: page.url)
        tree.insert(node, into: parent, at: idx, actionName: "ブックマーク追加")
        lookupAndUpdate(node)
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
        addColumns()
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClicked(_:))
        registerDragTypes()
    }

    private func addColumns() {
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
    }

    private func registerDragTypes() {
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
        visibleChildren(of: item as? BookmarkNode).count
    }

    func outlineView(_ ov: NSOutlineView, child idx: Int, ofItem item: Any?) -> Any {
        visibleChildren(of: item as? BookmarkNode)[idx]
    }

    /// フィルタを適用した子ノード配列
    private func visibleChildren(of parent: BookmarkNode?) -> [BookmarkNode] {
        let all = parent?.children ?? store.rootNodes
        return filter.filter(all)
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
        tree.moveBatch(nodes, into: parent, at: targetIdx, actionName: "移動")
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
        var insertIdx = targetIdx
        tree.group("ドロップ") {
            for info in urls {
                let domain = URL(string: info.url)?.host ?? info.url
                let node = BookmarkNode(title: info.title ?? pbTitle ?? domain, urlString: info.url)
                tree.insert(node, into: parent, at: insertIdx, actionName: "ドロップ")
                lookupAndUpdate(node)
                insertIdx += 1
            }
        }
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
    // フィルタ中は永続化しない（フィルタ解除後にユーザーの元の展開状態を復元するため）
    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? BookmarkNode else { return }
        if !filter.isActive { node.isExpanded = true }
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            expansion.expandAll(of: node)
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? BookmarkNode else { return }
        if !filter.isActive { node.isExpanded = false }
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            expansion.collapseAll(of: node)
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

// MARK: - NSSearchField Delegate

extension BookmarkList: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        applyFilter(query: searchField.stringValue)
    }

    /// クリアボタン (×) が押された / 検索終了時にも呼ばれる
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        applyFilter(query: "")
    }

    private func applyFilter(query: String) {
        // 選択中ノードを ID で保存（再ロード後も追跡可能にする）
        let selectedIDs = outlineView.selectedRowIndexes
            .compactMap { outlineView.item(atRow: $0) as? BookmarkNode }
            .map(\.id)

        filter = NodeFilter(query: query)
        outlineView.reloadData()
        if filter.isActive {
            expandFilterMatches()
        } else {
            expansion.restore()
        }

        restoreSelection(selectedIDs)
    }

    /// ノード ID 集合を元に選択を復元。見えていない場合は祖先を展開して可視化。
    private func restoreSelection(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var rows = IndexSet()
        for id in ids {
            guard let node = store.findNode(by: id) else { continue }
            // フィルタ中の場合、フィルタ条件に合わなければ復元しない
            if filter.isActive && !filter.matches(node) { continue }
            ensureVisible(node)
            let row = outlineView.row(forItem: node)
            if row >= 0 { rows.insert(row) }
        }
        if !rows.isEmpty {
            outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        }
    }

    /// 与えられたノードが outlineView 上で可視になるよう祖先フォルダをすべて展開
    private func ensureVisible(_ node: BookmarkNode) {
        var ancestors: [BookmarkNode] = []
        var current: BookmarkNode? = store.parent(of: node)
        while let p = current {
            ancestors.append(p)
            current = store.parent(of: p)
        }
        for ancestor in ancestors.reversed() {
            outlineView.expandItem(ancestor)
        }
    }

    private func expandFilterMatches() {
        let folderIDs = filter.foldersContainingMatch(in: store.rootNodes)
        expandFoldersByID(in: store.rootNodes, matching: folderIDs)
    }

    private func expandFoldersByID(in nodes: [BookmarkNode], matching ids: Set<UUID>) {
        for node in nodes where node.isFolder {
            if ids.contains(node.id) { outlineView.expandItem(node) }
            if let children = node.children { expandFoldersByID(in: children, matching: ids) }
        }
    }
}
