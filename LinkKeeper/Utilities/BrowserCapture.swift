import AppKit

struct CapturedPage {
    let url: String
    let title: String
}

enum BrowserCapture {

    // MARK: - Browser Definitions

    enum ScriptType {
        case safari
        case chromium
        case systemEvents
    }

    struct BrowserDef {
        let name: String
        let bundleID: String
        let scriptType: ScriptType
    }

    static let browsers: [BrowserDef] = [
        BrowserDef(name: "Safari",          bundleID: "com.apple.Safari",              scriptType: .safari),
        BrowserDef(name: "Google Chrome",   bundleID: "com.google.Chrome",             scriptType: .chromium),
        BrowserDef(name: "Microsoft Edge",  bundleID: "com.microsoft.edgemac",         scriptType: .chromium),
        BrowserDef(name: "Brave Browser",   bundleID: "com.brave.Browser",             scriptType: .chromium),
        BrowserDef(name: "Arc",             bundleID: "company.thebrowser.Browser",    scriptType: .chromium),
        BrowserDef(name: "Vivaldi",         bundleID: "com.vivaldi.Vivaldi",           scriptType: .chromium),
        BrowserDef(name: "Opera",           bundleID: "com.operasoftware.Opera",       scriptType: .chromium),
        BrowserDef(name: "ChatGPT Atlas",   bundleID: "com.openai.atlas",              scriptType: .systemEvents),
    ]

    // MARK: - Capture

    static func capture(from browser: BrowserDef) -> CapturedPage? {
        let script: String
        switch browser.scriptType {
        case .safari:
            script = safariScript(appName: browser.name)
        case .chromium:
            script = chromiumScript(appName: browser.name)
        case .systemEvents:
            script = systemEventsScript(processName: browser.name)
        }

        guard let result = runAppleScript(script) else { return nil }
        let parts = result.components(separatedBy: "\n")
        guard parts.count >= 2 else { return nil }

        var url = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        // URL が空なら登録しない
        guard !url.isEmpty else { return nil }

        // ドメインのみの場合（http で始まらない）は https:// を補完
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://\(url)"
        }

        return CapturedPage(url: url, title: title.isEmpty ? url : title)
    }

    static func captureFromFrontmostBrowser() -> (page: CapturedPage, browser: BrowserDef)? {
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        for browser in browsers {
            guard runningIDs.contains(browser.bundleID) else { continue }
            if let page = capture(from: browser) {
                return (page, browser)
            }
        }
        return nil
    }

    static func installedBrowsers() -> [BrowserDef] {
        return browsers.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
    }

    // MARK: - AppleScript Templates

    private static func safariScript(appName: String) -> String {
        return """
        tell application "\(appName)"
            if (count of windows) > 0 then
                set pageURL to URL of current tab of front window
                set pageTitle to name of current tab of front window
                return pageURL & linefeed & pageTitle
            end if
        end tell
        """
    }

    private static func chromiumScript(appName: String) -> String {
        return """
        tell application "\(appName)"
            if (count of windows) > 0 then
                set pageURL to URL of active tab of front window
                set pageTitle to title of active tab of front window
                return pageURL & linefeed & pageTitle
            end if
        end tell
        """
    }

    /// AppleScript 非対応ブラウザ用。
    /// Cmd+L → Cmd+C でアドレスバーの完全な URL をクリップボード経由で取得する。
    private static func systemEventsScript(processName: String) -> String {
        return """
        -- クリップボードを退避して空にする
        set oldClip to ""
        try
            set oldClip to the clipboard as text
        end try
        set the clipboard to ""

        -- ブラウザのプロセスを最前面にする（activate ではなく frontmost でウィンドウ順序を維持）
        tell application "System Events"
            if not (exists process "\(processName)") then return ""
            tell process "\(processName)"
                set frontmost to true
            end tell
        end tell
        delay 0.3

        -- ウィンドウタイトル取得（frontmost 化の後に取得）
        set windowTitle to ""
        tell application "System Events"
            tell process "\(processName)"
                try
                    set windowTitle to name of front window
                end try
            end tell
        end tell

        -- Cmd+L でアドレスバーにフォーカス → Cmd+A で全選択 → Cmd+C でコピー
        tell application "System Events"
            keystroke "l" using command down
            delay 0.2
            keystroke "a" using command down
            delay 0.1
            keystroke "c" using command down
            delay 0.3
        end tell

        -- クリップボードから URL を取得
        set pageURL to ""
        try
            set pageURL to the clipboard as text
        end try

        -- Escape でアドレスバーのフォーカスを外す
        tell application "System Events"
            key code 53
        end tell

        -- クリップボードを復元
        try
            set the clipboard to oldClip
        end try

        return pageURL & linefeed & windowTitle
        """
    }

    // MARK: - AppleScript Execution

    private static func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error = error {
            NSLog("AppleScript error: \(error)")
            return nil
        }
        return result?.stringValue
    }
}
