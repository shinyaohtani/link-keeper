import AppKit

/// アウトラインのフォルダ展開状態の保存・復元を担う。
/// node.isExpanded を真実の情報源とし、保存時に実際の表示状態へ同期する。
final class OutlineExpansion {
    private let outlineView: NSOutlineView
    private let store: BookmarkStore
    private let key = "LinkKeeper.expandedNodeIDs"

    /// フィルタ表示中かどうか（フィルタ中は表示状態を保存へ反映しない）。
    var isFiltering: () -> Bool = { false }

    init(outlineView: NSOutlineView, store: BookmarkStore) {
        self.outlineView = outlineView
        self.store = store
    }

    /// 現在の展開状態を保存する。フィルタ中でなければ実際の表示状態をモデルへ同期する。
    func save() {
        if !isFiltering() {
            syncFromView(store.rootNodes)
        }
        var ids: [String] = []
        collectIDs(store.rootNodes, into: &ids)
        UserDefaults.standard.set(ids, forKey: key)
    }

    /// 保存済みの展開状態を表示へ復元する（初回起動で保存が無ければ何もしない）。
    func restore() {
        guard UserDefaults.standard.stringArray(forKey: key) != nil else { return }
        apply(store.rootNodes)
    }

    /// 指定フォルダ配下の全子孫フォルダを再帰的に展開する。
    func expandAll(of node: BookmarkNode) {
        guard let children = node.children else { return }
        for child in children where child.isFolder {
            child.isExpanded = true
            outlineView.expandItem(child)
            expandAll(of: child)
        }
    }

    /// 指定フォルダ配下の全子孫フォルダを再帰的に折りたたむ。
    func collapseAll(of node: BookmarkNode) {
        guard let children = node.children else { return }
        for child in children where child.isFolder {
            collapseAll(of: child)
            child.isExpanded = false
            outlineView.collapseItem(child)
        }
    }

    // MARK: - Private

    /// 現在表示中（可視な行）のフォルダについて、実際の開閉状態を node.isExpanded に反映する。
    /// 折りたたまれた親の下に隠れているフォルダは、以前の状態をそのまま保持する。
    private func syncFromView(_ nodes: [BookmarkNode]) {
        for node in nodes where node.isFolder {
            if outlineView.row(forItem: node) >= 0 {
                node.isExpanded = outlineView.isItemExpanded(node)
            }
            if let children = node.children { syncFromView(children) }
        }
    }

    private func collectIDs(_ nodes: [BookmarkNode], into ids: inout [String]) {
        for node in nodes where node.isFolder {
            if node.isExpanded { ids.append(node.id.uuidString) }
            if let children = node.children { collectIDs(children, into: &ids) }
        }
    }

    private func apply(_ nodes: [BookmarkNode]) {
        for node in nodes where node.isFolder {
            if node.isExpanded { outlineView.expandItem(node) }
            if let children = node.children { apply(children) }
        }
    }
}
