import Foundation

/// タイトル文字列でブックマークノードをフィルタする値型。
/// 大文字小文字を無視。フォルダはタイトル一致 OR 子孫一致で表示。
struct NodeFilter {
    let query: String

    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 与えられた子ノード配列からマッチするものだけを返す
    func filter(_ nodes: [BookmarkNode]) -> [BookmarkNode] {
        guard isActive else { return nodes }
        return nodes.filter { matches($0) }
    }

    /// ノード自身または子孫がマッチするか
    func matches(_ node: BookmarkNode) -> Bool {
        let needle = query.lowercased()
        if node.title.lowercased().contains(needle) { return true }
        guard let children = node.children else { return false }
        return children.contains { matches($0) }
    }

    /// マッチを含むフォルダ ID 一覧（フィルタ時に自動展開するため）
    func foldersContainingMatch(in nodes: [BookmarkNode]) -> Set<UUID> {
        guard isActive else { return [] }
        var ids: Set<UUID> = []
        collect(in: nodes, into: &ids)
        return ids
    }

    private func collect(in nodes: [BookmarkNode], into ids: inout Set<UUID>) {
        for node in nodes where node.isFolder {
            if let children = node.children, children.contains(where: matches) {
                ids.insert(node.id)
            }
            if let children = node.children { collect(in: children, into: &ids) }
        }
    }
}
