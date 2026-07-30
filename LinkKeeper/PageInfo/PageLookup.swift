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
