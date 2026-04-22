import AppKit

struct BrowserInfo {
    let name: String
    let bundleIdentifier: String
    let path: String
}

enum BrowserHelper {
    private static let knownBrowsers: [(name: String, bundleID: String)] = [
        ("ChatGPT Atlas", "com.openai.atlas"),
        ("Safari", "com.apple.Safari"),
        ("Google Chrome", "com.google.Chrome"),
        ("Firefox", "org.mozilla.firefox"),
        ("Microsoft Edge", "com.microsoft.edgemac"),
        ("Brave Browser", "com.brave.Browser"),
        ("Arc", "company.thebrowser.Browser"),
        ("Opera", "com.operasoftware.Opera"),
        ("Vivaldi", "com.vivaldi.Vivaldi"),
    ]

    /// インストール済みブラウザの一覧を返す
    static func installedBrowsers() -> [BrowserInfo] {
        var result: [BrowserInfo] = []
        for browser in knownBrowsers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) {
                result.append(BrowserInfo(
                    name: browser.name,
                    bundleIdentifier: browser.bundleID,
                    path: url.path
                ))
            }
        }
        return result
    }

    /// 指定ブラウザで URL を開く
    static func open(url: URL, with browser: BrowserInfo) {
        let config = NSWorkspace.OpenConfiguration()
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        }
    }
}
