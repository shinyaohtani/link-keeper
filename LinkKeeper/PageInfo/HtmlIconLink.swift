import Foundation

/// HTML から <link rel="icon"> / <link rel="shortcut icon"> の href を抽出する値型。
/// 大きいサイズを優先し、複数候補を返す。
struct HtmlIconLink {
    let html: String
    let baseURL: URL

    /// 解決済み favicon URL 候補（大きいサイズ優先）
    var hrefs: [URL] {
        // <link ... rel="...icon..." ... href="..." ...> をすべて抽出
        let pattern = "<link\\b[^>]*rel\\s*=\\s*[\"'][^\"']*icon[^\"']*[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        var candidates: [(url: URL, size: Int)] = []
        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let tag = String(html[matchRange])
            guard let href = extractAttribute("href", from: tag),
                  let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL
            else { continue }
            let size = extractSize(from: tag)
            candidates.append((url: resolved, size: size))
        }

        // 大きいサイズ優先でソート、同サイズはドキュメント順
        candidates.sort { $0.size > $1.size }
        return candidates.map(\.url)
    }

    private func extractAttribute(_ name: String, from tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag)
        else { return nil }
        return String(tag[range])
    }

    private func extractSize(from tag: String) -> Int {
        guard let sizes = extractAttribute("sizes", from: tag) else { return 0 }
        if sizes.lowercased() == "any" { return 9999 }
        // "32x32", "192x192" などからピクセル数を抽出
        let parts = sizes.lowercased().split(separator: "x")
        return Int(parts.first ?? "0") ?? 0
    }
}
