import Foundation

/// ブックマークまたはフォルダを表すノード。
/// children が non-nil ならフォルダ、nil ならブックマーク。
class BookmarkNode: Codable {
    let id: UUID
    var title: String
    var urlString: String?
    var faviconData: Data?
    var dateAdded: Date
    var colorTag: Int  // 0=none, 1=red, 2=orange, 3=yellow, 4=green, 5=blue, 6=purple, 7=gray
    var children: [BookmarkNode]?
    var isExpanded: Bool

    /// ブラウザで開いた全日時履歴
    var accessHistory: [Date]
    /// 編集した全日時履歴（タイトル変更、URL変更、カラー変更等）
    var editHistory: [Date]

    var isFolder: Bool { children != nil }

    /// 最終アクセス日時
    var lastAccessed: Date? { accessHistory.last }
    /// 最終編集日時
    var lastEdited: Date? { editHistory.last }
    /// アクセス回数
    var accessCount: Int { accessHistory.count }

    init(title: String, urlString: String? = nil, isFolder: Bool = false) {
        self.id = UUID()
        self.title = title
        self.urlString = isFolder ? nil : urlString
        self.faviconData = nil
        self.dateAdded = Date()
        self.colorTag = 0
        self.children = isFolder ? [] : nil
        self.isExpanded = false
        self.accessHistory = []
        self.editHistory = []
    }

    // MARK: - History Recording

    func recordAccess() {
        accessHistory.append(Date())
    }

    func recordEdit() {
        editHistory.append(Date())
    }

    // MARK: - Codable (既存データとの後方互換性)

    enum CodingKeys: String, CodingKey {
        case id, title, urlString, faviconData, dateAdded, colorTag
        case children, isExpanded, accessHistory, editHistory
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        urlString = try c.decodeIfPresent(String.self, forKey: .urlString)
        faviconData = try c.decodeIfPresent(Data.self, forKey: .faviconData)
        dateAdded = try c.decode(Date.self, forKey: .dateAdded)
        colorTag = try c.decode(Int.self, forKey: .colorTag)
        children = try c.decodeIfPresent([BookmarkNode].self, forKey: .children)
        isExpanded = try c.decode(Bool.self, forKey: .isExpanded)
        // 既存データにフィールドがない場合は空配列
        accessHistory = try c.decodeIfPresent([Date].self, forKey: .accessHistory) ?? []
        editHistory = try c.decodeIfPresent([Date].self, forKey: .editHistory) ?? []
    }
}
