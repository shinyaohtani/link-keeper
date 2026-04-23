import AppKit

/// ブラウザを表す値型。URL を開く・最前面タブの情報を取得する責務を持つ。
struct Browser {
    let name: String
    let bundleID: String
    let scriptKind: ScriptKind

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    func open(url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
    }

    var frontPage: CapturedPage? {
        let source = scriptKind.captureScript(appName: name)
        guard let raw = ScriptResult(source: source).value else { return nil }
        return CapturedPage(parsing: raw)
    }
}

// MARK: - ScriptKind

extension Browser {
    enum ScriptKind {
        case safari
        case chromium
        case systemEvents

        func captureScript(appName: String) -> String {
            switch self {
            case .safari:    return safariScript(appName)
            case .chromium:  return chromiumScript(appName)
            case .systemEvents: return systemEventsScript(appName)
            }
        }

        private func safariScript(_ app: String) -> String {
            """
            tell application "\(app)"
                if (count of windows) > 0 then
                    set pageURL to URL of current tab of front window
                    set pageTitle to name of current tab of front window
                    return pageURL & linefeed & pageTitle
                end if
            end tell
            """
        }

        private func chromiumScript(_ app: String) -> String {
            """
            tell application "\(app)"
                if (count of windows) > 0 then
                    set pageURL to URL of active tab of front window
                    set pageTitle to title of active tab of front window
                    return pageURL & linefeed & pageTitle
                end if
            end tell
            """
        }

        private func systemEventsScript(_ app: String) -> String {
            """
            set oldClip to ""
            try
                set oldClip to the clipboard as text
            end try
            set the clipboard to ""
            tell application "System Events"
                if not (exists process "\(app)") then return ""
                tell process "\(app)"
                    set frontmost to true
                end tell
            end tell
            delay 0.3
            set windowTitle to ""
            tell application "System Events"
                tell process "\(app)"
                    try
                        set windowTitle to name of front window
                    end try
                end tell
            end tell
            tell application "System Events"
                keystroke "l" using command down
                delay 0.2
                keystroke "a" using command down
                delay 0.1
                keystroke "c" using command down
                delay 0.3
            end tell
            set pageURL to ""
            try
                set pageURL to the clipboard as text
            end try
            tell application "System Events"
                key code 53
            end tell
            try
                set the clipboard to oldClip
            end try
            return pageURL & linefeed & windowTitle
            """
        }
    }
}

// MARK: - ScriptResult (AppleScript 実行)

struct ScriptResult {
    let source: String

    var value: String? {
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

// MARK: - CapturedPage

struct CapturedPage {
    let url: String
    let title: String

    init(url: String, title: String) {
        self.url = url
        self.title = title
    }

    init?(parsing raw: String) {
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 2 else { return nil }

        var urlPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let titlePart = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !urlPart.isEmpty else { return nil }

        if !urlPart.hasPrefix("http://") && !urlPart.hasPrefix("https://") {
            urlPart = "https://\(urlPart)"
        }

        self.url = urlPart
        self.title = titlePart.isEmpty ? urlPart : titlePart
    }
}

/// struct Browser を NSMenuItem.representedObject に渡すためのラッパー。
class BrowserWrapper: NSObject {
    let browser: Browser
    init(_ browser: Browser) { self.browser = browser; super.init() }
}
