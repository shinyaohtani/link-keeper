import Foundation
import AppKit

struct PageInfo {
    var title: String?
    var faviconData: Data?
}

enum PageInfoFetcher {
    /// URL からページタイトルとファビコンを非同期取得する。完了ハンドラはメインスレッドで呼ばれる。
    static func fetch(for urlString: String, completion: @escaping (PageInfo) -> Void) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(PageInfo()) }
            return
        }

        var result = PageInfo()
        let group = DispatchGroup()

        // 1. HTML からタイトル抽出
        group.enter()
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { group.leave() }
            guard let data = data,
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                return
            }
            result.title = extractTitle(from: html)
        }.resume()

        // 2. ファビコン取得（バックグラウンドスレッドで完了を待つ）
        group.enter()
        fetchFavicon(for: urlString) { data in
            result.faviconData = data
            group.leave()
        }

        // 両方完了後にメインスレッドで返す
        group.notify(queue: .main) {
            completion(result)
        }
    }

    // MARK: - Favicon（コールバックをバックグラウンドスレッドで呼ぶ版）

    private static func fetchFavicon(for urlString: String, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: urlString),
              let host = url.host,
              let scheme = url.scheme else {
            completion(nil)
            return
        }

        let faviconURL = URL(string: "\(scheme)://\(host)/favicon.ico")!
        URLSession.shared.dataTask(with: faviconURL) { data, response, _ in
            if let data = data,
               let http = response as? HTTPURLResponse,
               http.statusCode == 200,
               NSImage(data: data) != nil {
                completion(resizedFaviconData(data))
                return
            }
            // Fallback: Google S2
            guard let googleURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32") else {
                completion(nil)
                return
            }
            URLSession.shared.dataTask(with: googleURL) { data, response, _ in
                if let data = data,
                   let http = response as? HTTPURLResponse,
                   http.statusCode == 200,
                   NSImage(data: data) != nil {
                    completion(resizedFaviconData(data))
                } else {
                    completion(nil)
                }
            }.resume()
        }.resume()
    }

    // MARK: - Helpers

    private static func extractTitle(from html: String) -> String? {
        guard let startRange = html.range(of: "<title", options: .caseInsensitive) else { return nil }
        guard let tagClose = html.range(of: ">", options: [], range: startRange.upperBound..<html.endIndex) else { return nil }
        guard let endRange = html.range(of: "</title>", options: .caseInsensitive, range: tagClose.upperBound..<html.endIndex) else { return nil }

        let title = String(html[tagClose.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")

        return title.isEmpty ? nil : title
    }

    private static func resizedFaviconData(_ data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let size = NSSize(width: 32, height: 32)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        guard let tiff = newImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return data
        }
        return png
    }
}
