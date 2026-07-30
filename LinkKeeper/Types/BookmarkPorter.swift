import Foundation

/// ブックマークの外部フォーマットとの相互変換。
/// - Netscape Bookmark File 形式（一般的なブラウザがエクスポート/インポートに使う HTML）
/// - Markdown テーブル（選択行のコピー用）
enum BookmarkPorter {

    // MARK: - Netscape Bookmark HTML Export

    /// ルートノード群を Netscape Bookmark 形式の HTML 文字列に変換する。
    /// Chrome / Safari / Firefox / Edge などがそのままインポートできる。
    static func exportHTML(_ nodes: [BookmarkNode]) -> String {
        var out = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file. It will be read and overwritten. -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>

        """
        for node in nodes {
            appendNode(node, into: &out, indent: 1)
        }
        out += "</DL><p>\n"
        return out
    }

    private static func appendNode(_ node: BookmarkNode, into out: inout String, indent: Int) {
        let pad = String(repeating: "    ", count: indent)
        let addDate = String(Int(node.dateAdded.timeIntervalSince1970))
        if node.isFolder {
            out += "\(pad)<DT><H3 ADD_DATE=\"\(addDate)\">\(escapeHTML(node.title))</H3>\n"
            out += "\(pad)<DL><p>\n"
            for child in node.children ?? [] {
                appendNode(child, into: &out, indent: indent + 1)
            }
            out += "\(pad)</DL><p>\n"
        } else if let url = node.urlString {
            out += "\(pad)<DT><A HREF=\"\(escapeHTML(url))\" ADD_DATE=\"\(addDate)\">\(escapeHTML(node.title))</A>\n"
        }
    }

    // MARK: - Netscape Bookmark HTML Import

    /// Netscape Bookmark 形式の HTML をパースしてトップレベルのノード配列を返す。
    static func importHTML(_ html: String) -> [BookmarkNode] {
        let root = BookmarkNode(title: "", isFolder: true)
        var stack: [BookmarkNode] = [root]
        var pendingFolder: BookmarkNode?

        let ns = html as NSString
        let full = NSRange(location: 0, length: ns.length)
        tokenRegex.enumerateMatches(in: html, range: full) { match, _, _ in
            guard let match = match else { return }
            let token = ns.substring(with: match.range)
            let lower = token.lowercased()

            if lower.hasPrefix("<dl") {
                if let folder = pendingFolder {
                    stack.append(folder)
                    pendingFolder = nil
                }
                return
            }
            if lower.hasPrefix("</dl") {
                if stack.count > 1 { stack.removeLast() }
                pendingFolder = nil
                return
            }

            // <H3> = フォルダ
            if let attrs = group(match, 1, in: ns), let text = group(match, 2, in: ns) {
                let folder = BookmarkNode(title: decodeHTML(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                                          isFolder: true)
                if let date = addDate(in: attrs) { folder.dateAdded = date }
                folder.isExpanded = true
                stack.last?.children?.append(folder)
                pendingFolder = folder
                return
            }

            // <A> = ブックマーク
            if let attrs = group(match, 3, in: ns), let text = group(match, 4, in: ns) {
                guard let href = href(in: attrs) else { return }
                let node = BookmarkNode(title: decodeHTML(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                                        urlString: decodeHTML(href))
                if let date = addDate(in: attrs) { node.dateAdded = date }
                stack.last?.children?.append(node)
                return
            }
        }
        return root.children ?? []
    }

    // MARK: - Markdown Table

    /// ヘッダとセル行から Markdown テーブル文字列を生成する。
    static func markdownTable(header: [String], rows: [[String]]) -> String {
        var lines: [String] = []
        lines.append("| " + header.joined(separator: " | ") + " |")
        lines.append("| " + header.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in rows {
            lines.append("| " + row.map(escapeCell).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    /// テーブルセル内の `|` と改行をエスケープ/除去する。
    static func escapeCell(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    // MARK: - Helpers

    /// <DL>/</DL>/<H3>…</H3>/<A>…</A> をドキュメント出現順に取り出す正規表現。
    private static let tokenRegex: NSRegularExpression = {
        let pattern = "<DL[^>]*>|</DL[^>]*>|<H3([^>]*)>(.*?)</H3>|<A([^>]*)>(.*?)</A>"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }()

    private static let addDateRegex = try! NSRegularExpression(pattern: "ADD_DATE=\"?(\\d+)\"?", options: [.caseInsensitive])
    private static let hrefRegex = try! NSRegularExpression(pattern: "HREF=\"([^\"]*)\"", options: [.caseInsensitive])

    private static func group(_ match: NSTextCheckingResult, _ idx: Int, in ns: NSString) -> String? {
        guard idx < match.numberOfRanges else { return nil }
        let r = match.range(at: idx)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
    }

    private static func addDate(in attrs: String) -> Date? {
        let ns = attrs as NSString
        guard let m = addDateRegex.firstMatch(in: attrs, range: NSRange(location: 0, length: ns.length)),
              let secs = TimeInterval(ns.substring(with: m.range(at: 1))) else { return nil }
        return Date(timeIntervalSince1970: secs)
    }

    private static func href(in attrs: String) -> String? {
        let ns = attrs as NSString
        guard let m = hrefRegex.firstMatch(in: attrs, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func decodeHTML(_ s: String) -> String {
        guard s.contains("&") else { return s }
        return s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
