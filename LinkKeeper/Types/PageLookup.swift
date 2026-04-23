import Foundation
import AppKit

/// Web ページから取得した情報
struct PageInfo {
    var title: String?
    var faviconData: Data?
}

/// URL からページタイトルとファビコンを取得する値型。
/// HTML spec 準拠の favicon 解決アルゴリズム:
///   1. HTML を取得し <link rel="icon"> の href を解析
///   2. フォールバック: origin の /favicon.ico
///   3. 最終フォールバック: Google S2 favicon API
struct PageLookup {
    let urlString: String

    func result(completion: @escaping (PageInfo) -> Void) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(PageInfo()) }
            return
        }
        fetchHTML(url: url) { html in
            var info = PageInfo()
            info.title = html.flatMap { HtmlTitle(html: $0).value }

            let iconHrefs = html.flatMap { HtmlIconLink(html: $0, baseURL: url).hrefs } ?? []
            self.resolveFavicon(candidates: iconHrefs, pageURL: url) { data in
                info.faviconData = data
                DispatchQueue.main.async { completion(info) }
            }
        }
    }

    // MARK: - HTML Fetch

    private func fetchHTML(url: URL, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
            else { completion(nil); return }
            completion(html)
        }.resume()
    }

    // MARK: - Favicon Resolution

    /// 候補 URL を順に試し、最初に有効な画像が取れたものを採用。
    /// 全候補失敗 → origin /favicon.ico → Google S2
    private func resolveFavicon(candidates: [URL], pageURL: URL, completion: @escaping (Data?) -> Void) {
        tryNextCandidate(candidates: candidates, idx: 0) { data in
            if let data = data { completion(data); return }
            // フォールバック 1: origin /favicon.ico
            let origin = self.originURL(of: pageURL)
            self.downloadFavicon(from: origin) { data in
                if let data = data { completion(data); return }
                // フォールバック 2: Google S2
                guard let host = pageURL.host,
                      let googleURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
                else { completion(nil); return }
                self.downloadFavicon(from: googleURL, completion: completion)
            }
        }
    }

    private func tryNextCandidate(candidates: [URL], idx: Int, completion: @escaping (Data?) -> Void) {
        guard idx < candidates.count else { completion(nil); return }
        downloadFavicon(from: candidates[idx]) { data in
            if let data = data { completion(data) }
            else { self.tryNextCandidate(candidates: candidates, idx: idx + 1, completion: completion) }
        }
    }

    private func downloadFavicon(from url: URL, completion: @escaping (Data?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, NSImage(data: data) != nil else {
                completion(nil); return
            }
            completion(FaviconImage(rawData: data).resized)
        }.resume()
    }

    private func originURL(of url: URL) -> URL {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = "/favicon.ico"
        return components.url ?? url
    }
}

// MARK: - HtmlTitle

/// HTML 文字列から <title> を抽出する値型。
private struct HtmlTitle {
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

// MARK: - HtmlIconLink

/// HTML から <link rel="icon"> / <link rel="shortcut icon"> の href を抽出する値型。
/// 大きいサイズを優先し、複数候補を返す。
private struct HtmlIconLink {
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

// MARK: - FaviconImage

/// ファビコン画像データを 32x32 にリサイズする値型。
private struct FaviconImage {
    let rawData: Data

    var resized: Data? {
        guard let image = NSImage(data: rawData) else { return nil }
        let size = NSSize(width: 32, height: 32)
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        canvas.unlockFocus()
        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return rawData }
        return png
    }
}
