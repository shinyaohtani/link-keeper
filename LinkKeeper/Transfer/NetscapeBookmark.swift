import Foundation

/// Netscape Bookmark 形式（一般的なブラウザがエクスポート/インポートに使う HTML）の
/// ブックマーク文書を表す値型。HTML 文字列こそがこの文書の実体であり、
/// ノード群との相互変換をこの文書自身の振る舞いとして持つ。
struct NetscapeBookmark {
    let html: String

    private static let header = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <!-- This is an automatically generated file. It will be read and overwritten. -->
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DL><p>

    """

    /// 既存の HTML 文書を表す。
    init(html: String) {
        self.html = html
    }

    /// ノード群から Netscape 形式の文書を構成する。
    init(nodes: [BookmarkNode]) {
        var out = Self.header
        for node in nodes {
            out += node.netscapeHTML(indent: 1)
        }
        out += "</DL><p>\n"
        self.html = out
    }

    /// 文書が表すトップレベルのノード群。
    var nodes: [BookmarkNode] {
        // <DL>/</DL>/<H3>…</H3>/<A>…</A> をドキュメント出現順に取り出す。
        let pattern = "<DL[^>]*>|</DL[^>]*>|<H3([^>]*)>(.*?)</H3>|<A([^>]*)>(.*?)</A>"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return [] }

        let draft = BookmarkDraft()
        let ns = html as NSString
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match else { return }
            self.consume(match, in: ns, into: draft)
        }
        return draft.nodes
    }

    /// 1 つのトークンを解釈し、構築中のツリーへ反映する。
    private func consume(_ match: NSTextCheckingResult, in ns: NSString, into draft: BookmarkDraft) {
        let token = ns.substring(with: match.range).lowercased()
        if token.hasPrefix("<dl") { draft.openList(); return }
        if token.hasPrefix("</dl") { draft.closeList(); return }

        if let attrs = match.group(1, in: ns), let text = match.group(2, in: ns) {
            draft.addFolder(title: text.trimmed.htmlUnescaped, date: attrs.addDate)
            return
        }
        if let attrs = match.group(3, in: ns), let text = match.group(4, in: ns), let href = attrs.href {
            draft.addLink(title: text.trimmed.htmlUnescaped, url: href.htmlUnescaped, date: attrs.addDate)
        }
    }
}

// MARK: - BookmarkDraft（パース中に組み立てられるツリー）

// MARK: - BookmarkNode（自身を Netscape HTML 断片へ描画する振る舞い）

private extension BookmarkNode {
    func netscapeHTML(indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        let addDate = String(Int(dateAdded.timeIntervalSince1970))
        guard isFolder else {
            guard let url = urlString else { return "" }
            return "\(pad)<DT><A HREF=\"\(url.htmlEscaped)\" ADD_DATE=\"\(addDate)\">\(title.htmlEscaped)</A>\n"
        }
        var out = "\(pad)<DT><H3 ADD_DATE=\"\(addDate)\">\(title.htmlEscaped)</H3>\n"
        out += "\(pad)<DL><p>\n"
        for child in children ?? [] {
            out += child.netscapeHTML(indent: indent + 1)
        }
        out += "\(pad)</DL><p>\n"
        return out
    }
}

// MARK: - 文字列・正規表現マッチの振る舞い

private extension NSTextCheckingResult {
    /// 指定インデックスのキャプチャ文字列（存在しなければ nil）。
    func group(_ idx: Int, in ns: NSString) -> String? {
        guard idx < numberOfRanges else { return nil }
        let range = self.range(at: idx)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 属性文字列に含まれる ADD_DATE（Unix epoch 秒）を Date として解釈した値。
    var addDate: Date? {
        firstCapture(pattern: "ADD_DATE=\"?(\\d+)\"?")
            .flatMap(TimeInterval.init)
            .map { Date(timeIntervalSince1970: $0) }
    }

    /// 属性文字列に含まれる HREF の値。
    var href: String? {
        firstCapture(pattern: "HREF=\"([^\"]*)\"")
    }

    /// HTML エンティティにエスケープした表現。
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// HTML エンティティを復号した表現。
    var htmlUnescaped: String {
        guard contains("&") else { return self }
        return replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// 与えた正規表現の最初のキャプチャ（グループ1）を返す。大文字小文字は無視。
    func firstCapture(pattern: String) -> String? {
        let ns = self as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
