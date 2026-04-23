import Foundation

class BookmarkStore {
    private(set) var rootNodes: [BookmarkNode] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LinkKeeper")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("bookmarks.json")
        load()
    }

    // MARK: - Persistence

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            rootNodes = try decoder.decode([BookmarkNode].self, from: data)
        } catch {
            NSLog("BookmarkStore load error: \(error)")
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(rootNodes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("BookmarkStore save error: \(error)")
        }
    }

    // MARK: - Tree Queries

    func findNode(by id: UUID) -> BookmarkNode? {
        return findNode(by: id, in: rootNodes)
    }

    private func findNode(by id: UUID, in nodes: [BookmarkNode]) -> BookmarkNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children,
               let found = findNode(by: id, in: children) {
                return found
            }
        }
        return nil
    }

    func parent(of target: BookmarkNode) -> BookmarkNode? {
        return findParent(of: target.id, in: rootNodes, parent: nil)
    }

    private func findParent(of targetID: UUID, in nodes: [BookmarkNode], parent: BookmarkNode?) -> BookmarkNode? {
        for node in nodes {
            if node.id == targetID { return parent }
            if let children = node.children,
               let found = findParent(of: targetID, in: children, parent: node) {
                return found
            }
        }
        return nil
    }

    func children(of parent: BookmarkNode?) -> [BookmarkNode] {
        if let parent = parent {
            return parent.children ?? []
        }
        return rootNodes
    }

    func index(of node: BookmarkNode, in parent: BookmarkNode?) -> Int? {
        let siblings = children(of: parent)
        return siblings.firstIndex(where: { $0.id == node.id })
    }

    // MARK: - Tree Mutations

    func insertNode(_ node: BookmarkNode, into parent: BookmarkNode?, at index: Int) {
        if let parent = parent {
            if parent.children == nil { parent.children = [] }
            let clampedIndex = min(index, parent.children!.count)
            parent.children!.insert(node, at: clampedIndex)
        } else {
            let clampedIndex = min(index, rootNodes.count)
            rootNodes.insert(node, at: clampedIndex)
        }
        save()
    }

    func removeNode(_ node: BookmarkNode) {
        let parent = self.parent(of: node)
        if let parent = parent {
            parent.children?.removeAll { $0.id == node.id }
        } else {
            rootNodes.removeAll { $0.id == node.id }
        }
    }

    func moveNode(_ node: BookmarkNode, to targetParent: BookmarkNode?, at targetIndex: Int) {
        removeNode(node)
        insertNode(node, into: targetParent, at: targetIndex)
    }

    /// 選択ノードに応じた挿入位置を返す
    func insertionPoint(for selected: BookmarkNode?) -> (parent: BookmarkNode?, idx: Int) {
        guard let sel = selected else { return (nil, rootNodes.count) }
        if sel.isFolder { return (sel, sel.children?.count ?? 0) }
        let parent = self.parent(of: sel)
        return (parent, (index(of: sel, in: parent) ?? 0) + 1)
    }

    /// 指定ノードが ancestor の子孫かどうかを判定
    func isDescendant(_ node: BookmarkNode, of ancestor: BookmarkNode) -> Bool {
        if ancestor.id == node.id { return true }
        guard let children = ancestor.children else { return false }
        return children.contains { isDescendant(node, of: $0) }
    }
}
