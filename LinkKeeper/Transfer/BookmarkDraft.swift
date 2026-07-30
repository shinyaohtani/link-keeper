import Foundation

/// Netscape 文書のパース過程で組み立てられる、ブックマークツリーの下書き。
/// <DL> の入れ子をスタックで追跡し、フォルダ/リンクを現在の親へ追加する。
final class BookmarkDraft {
    private let root = BookmarkNode(title: "", isFolder: true)
    private var stack: [BookmarkNode]
    private var pendingFolder: BookmarkNode?

    init() {
        stack = [root]
    }

    /// 組み上がったトップレベルのノード群。
    var nodes: [BookmarkNode] { root.children ?? [] }

    /// <DL> 開始。直前のフォルダがあればその中へ入る。
    func openList() {
        if let folder = pendingFolder {
            stack.append(folder)
            pendingFolder = nil
        }
    }

    /// </DL> 終了。1 階層戻る。
    func closeList() {
        if stack.count > 1 { stack.removeLast() }
        pendingFolder = nil
    }

    func addFolder(title: String, date: Date?) {
        let folder = BookmarkNode(title: title, isFolder: true)
        if let date = date { folder.dateAdded = date }
        folder.isExpanded = true
        stack.last?.children?.append(folder)
        pendingFolder = folder
    }

    func addLink(title: String, url: String, date: Date?) {
        let node = BookmarkNode(title: title, urlString: url)
        if let date = date { node.dateAdded = date }
        stack.last?.children?.append(node)
    }
}
