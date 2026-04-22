import AppKit

/// 既知ブラウザの一覧を管理する値型。
struct BrowserCatalog {
    let browsers: [Browser] = [
        Browser(name: "Safari",          bundleID: "com.apple.Safari",           scriptKind: .safari),
        Browser(name: "Google Chrome",   bundleID: "com.google.Chrome",          scriptKind: .chromium),
        Browser(name: "Microsoft Edge",  bundleID: "com.microsoft.edgemac",      scriptKind: .chromium),
        Browser(name: "Brave Browser",   bundleID: "com.brave.Browser",          scriptKind: .chromium),
        Browser(name: "Arc",             bundleID: "company.thebrowser.Browser",  scriptKind: .chromium),
        Browser(name: "Vivaldi",         bundleID: "com.vivaldi.Vivaldi",        scriptKind: .chromium),
        Browser(name: "Opera",           bundleID: "com.operasoftware.Opera",    scriptKind: .chromium),
        Browser(name: "ChatGPT Atlas",   bundleID: "com.openai.atlas",           scriptKind: .systemEvents),
    ]

    var installed: [Browser] {
        browsers.filter(\.isInstalled)
    }

    var running: [Browser] {
        browsers.filter(\.isRunning)
    }

    func captureFromFrontmost() -> (page: CapturedPage, browser: Browser)? {
        for browser in running {
            if let page = browser.frontPage {
                return (page, browser)
            }
        }
        return nil
    }

    func browser(for bundleID: String) -> Browser? {
        browsers.first { $0.bundleID == bundleID }
    }
}
