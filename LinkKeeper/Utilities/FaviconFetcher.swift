import Foundation
import AppKit

enum FaviconFetcher {
    /// URL からファビコンを非同期取得する。完了ハンドラはメインスレッドで呼ばれる。
    static func fetch(for urlString: String, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: urlString),
              let host = url.host,
              let scheme = url.scheme else {
            completion(nil)
            return
        }

        let faviconURL = URL(string: "\(scheme)://\(host)/favicon.ico")!

        let task = URLSession.shared.dataTask(with: faviconURL) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      isValidImage(data) else {
                    // Fallback: try fetching from Google S2 favicon service
                    fetchFromGoogle(host: host, completion: completion)
                    return
                }
                completion(resizedFaviconData(data))
            }
        }
        task.resume()
    }

    private static func fetchFromGoogle(host: String, completion: @escaping (Data?) -> Void) {
        // Use Google's favicon service as fallback
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32") else {
            completion(nil)
            return
        }
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      isValidImage(data) else {
                    completion(nil)
                    return
                }
                completion(resizedFaviconData(data))
            }
        }
        task.resume()
    }

    private static func isValidImage(_ data: Data) -> Bool {
        return NSImage(data: data) != nil
    }

    private static func resizedFaviconData(_ data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let targetSize = NSSize(width: 32, height: 32)

        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()

        guard let tiffData = newImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return data
        }
        return pngData
    }
}
