import Foundation

/// ブックマークツリーへの Undo 対応の変更操作をまとめた単一窓口。
/// store への挿入・削除・移動を Undo 登録付きで行い、変更のたびに reload を通知する。
/// UndoManager と再描画は所有者（BookmarkList）から注入する。
final class BookmarkTree {
    let store: BookmarkStore
    var reload: (() -> Void)?
    var undoManagerProvider: (() -> UndoManager?)?

    init(store: BookmarkStore) {
        self.store = store
    }

    private var undoManager: UndoManager? { undoManagerProvider?() }

    /// 複数操作を 1 つの Undo グループ・アクション名にまとめる。
    func group(_ actionName: String, _ body: () -> Void) {
        undoManager?.beginUndoGrouping()
        body()
        undoManager?.endUndoGrouping()
        undoManager?.setActionName(actionName)
    }

    /// ノードを挿入し、取り消しに削除を登録する。
    func insert(_ node: BookmarkNode, into parent: BookmarkNode?, at idx: Int, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { $0.remove(node, actionName: actionName) }
        undoManager?.setActionName(actionName)
        store.insertNode(node, into: parent, at: idx)
        reload?()
    }

    /// ノードを削除し、取り消しに元位置への挿入を登録する。
    func remove(_ node: BookmarkNode, actionName: String) {
        let parent = store.parent(of: node)
        let idx = store.index(of: node, in: parent) ?? 0
        undoManager?.registerUndo(withTarget: self) {
            $0.insert(node, into: parent, at: idx, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        store.removeNode(node)
        reload?()
    }

    /// ノードを移動し、取り消しに元位置への移動を登録する。
    func move(_ node: BookmarkNode, into parent: BookmarkNode?, at idx: Int, actionName: String) {
        let oldParent = store.parent(of: node)
        let oldIdx = store.index(of: node, in: oldParent) ?? 0
        undoManager?.registerUndo(withTarget: self) {
            $0.move(node, into: oldParent, at: oldIdx, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        store.removeNode(node)
        store.insertNode(node, into: parent, at: min(idx, store.children(of: parent).count))
        reload?()
    }

    /// 複数ノードを連続位置へ一括移動する（再描画は 1 回）。内部ドラッグ&ドロップ用。
    func moveBatch(_ nodes: [BookmarkNode], into parent: BookmarkNode?, at startIdx: Int, actionName: String) {
        undoManager?.beginUndoGrouping()
        var insertIdx = startIdx
        for node in nodes {
            let oldParent = store.parent(of: node)
            let oldIdx = store.index(of: node, in: oldParent) ?? 0
            store.removeNode(node)
            let clamped = min(insertIdx, store.children(of: parent).count)
            store.insertNode(node, into: parent, at: clamped)
            undoManager?.registerUndo(withTarget: self) {
                $0.move(node, into: oldParent, at: oldIdx, actionName: actionName)
            }
            insertIdx = clamped + 1
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName(actionName)
        reload?()
    }
}
