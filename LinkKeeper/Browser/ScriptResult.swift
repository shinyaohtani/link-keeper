import AppKit

/// AppleScript のソースを実行し、その戻り値（文字列）を表す値型。
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
