import Foundation

/// HTML 文字列から <title> を抽出する値型。
struct HtmlTitle {
    let html: String

    var value: String? {
        guard let start = html.range(of: "<title", options: .caseInsensitive),
              let tagClose = html.range(of: ">", range: start.upperBound..<html.endIndex),
              let end = html.range(of: "</title>", options: .caseInsensitive, range: tagClose.upperBound..<html.endIndex)
        else { return nil }

        let raw = String(html[tagClose.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = raw
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")
        return decoded.isEmpty ? nil : decoded
    }
}
