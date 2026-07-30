import Foundation

/// ブラウザの最前面タブから取得したページ（URL とタイトル）を表す値型。
struct CapturedPage {
    let url: String
    let title: String

    init(url: String, title: String) {
        self.url = url
        self.title = title
    }

    /// AppleScript の戻り（1 行目: URL、2 行目以降: タイトル）を解釈する。
    init?(parsing raw: String) {
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 2 else { return nil }

        var urlPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let titlePart = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !urlPart.isEmpty else { return nil }

        if !urlPart.hasPrefix("http://") && !urlPart.hasPrefix("https://") {
            urlPart = "https://\(urlPart)"
        }

        self.url = urlPart
        self.title = titlePart.isEmpty ? urlPart : titlePart
    }
}
