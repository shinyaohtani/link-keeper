import Foundation
import AppKit

/// Web ページから取得した情報
struct PageInfo {
    var title: String?
    var faviconData: Data?
}

/// URL からページタイトルとファビコンを取得する値型。
struct PageLookup {
    let urlString: String

    func result(completion: @escaping (PageInfo) -> Void) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(PageInfo()) }
            return
        }

        var info = PageInfo()
        let group = DispatchGroup()

        group.enter()
        fetchTitle(url: url) { title in
            info.title = title
            group.leave()
        }

        group.enter()
        fetchFavicon(url: url) { data in
            info.faviconData = data
            group.leave()
        }

        group.notify(queue: .main) {
            completion(info)
        }
    }

    // MARK: - Title

    private func fetchTitle(url: URL, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                completion(nil)
                return
            }
            completion(HtmlTitle(html: html).value)
        }.resume()
    }

    // MARK: - Favicon

    private func fetchFavicon(url: URL, completion: @escaping (Data?) -> Void) {
        guard let host = url.host, let scheme = url.scheme else {
            completion(nil)
            return
        }
        let directURL = URL(string: "\(scheme)://\(host)/favicon.ico")!
        fetchFaviconData(from: directURL) { data in
            if let data = data {
                completion(data)
                return
            }
            guard let fallbackURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32") else {
                completion(nil)
                return
            }
            self.fetchFaviconData(from: fallbackURL, completion: completion)
        }
    }

    private func fetchFaviconData(from url: URL, completion: @escaping (Data?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let data = data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  NSImage(data: data) != nil else {
                completion(nil)
                return
            }
            completion(FaviconImage(rawData: data).resized)
        }.resume()
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
              let png = rep.representation(using: .png, properties: [:]) else {
            return rawData
        }
        return png
    }
}
