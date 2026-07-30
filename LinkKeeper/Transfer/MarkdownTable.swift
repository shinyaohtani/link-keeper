import Foundation

/// Markdown の表を表す値型。ヘッダと各行のセルを保持し、Markdown テキストへ整形する。
struct MarkdownTable {
    let header: [String]
    let rows: [[String]]

    /// Markdown テーブル形式のテキスト表現。
    var text: String {
        var lines: [String] = []
        lines.append(row(header))
        lines.append(row(header.map { _ in "---" }))
        for cells in rows {
            lines.append(row(cells.map(\.markdownCellEscaped)))
        }
        return lines.joined(separator: "\n")
    }

    private func row(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }
}

// MARK: - String（セルのエスケープはその文字列自身の振る舞い）

private extension String {
    /// Markdown テーブルのセルとして安全な表現（`|`・改行をエスケープ/除去）。
    var markdownCellEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
