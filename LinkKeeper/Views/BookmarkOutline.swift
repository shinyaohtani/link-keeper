import AppKit

/// NSOutlineView サブクラス。スローダブルクリック・右クリックメニュー・キーボードを処理。
class BookmarkOutline: NSOutlineView {

    private var editTimer: Timer?
    private var lastClickedRow: Int = -1

    // MARK: - First Responder

    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if let tf = responder as? NSTextField, tf.isEditable { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }

    // MARK: - Slow Double Click

    override func mouseDown(with event: NSEvent) {
        if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor {
            let pt = editor.convert(event.locationInWindow, from: nil)
            if editor.bounds.contains(pt) {
                editor.mouseDown(with: event)
                return
            }
            window?.makeFirstResponder(self)
        }

        cancelPendingEdit()
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        let wasSelected = row >= 0 && selectedRowIndexes.contains(row)

        super.mouseDown(with: event)

        guard wasSelected, row >= 0, event.clickCount == 1, column(at: point) == 0 else { return }
        lastClickedRow = row
        editTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval + 0.05,
                                         repeats: false) { [weak self] _ in
            guard let self = self,
                  self.lastClickedRow == row,
                  self.selectedRowIndexes.contains(row),
                  let cell = self.view(atColumn: 0, row: row, makeIfNecessary: false) as? BookmarkCell
            else { return }
            cell.beginEditing()
        }
    }

    func cancelPendingEdit() {
        editTimer?.invalidate()
        editTimer = nil
        lastClickedRow = -1
    }

    override func draggingSession(_ session: NSDraggingSession, willBeginAt pt: NSPoint) {
        cancelPendingEdit()
        super.draggingSession(session, willBeginAt: pt)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0 && !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if row < 0 {
            deselectAll(nil)
        }
        return (delegate as? BookmarkList)?.contextMenu(for: row)
    }

    // MARK: - Copy

    /// アウトラインが first responder のときに ⌘C / メニューのコピーを受け取り、
    /// 選択行を Markdown テーブルとしてコピーする。（タイトル編集中はフィールドエディタが処理する）
    @objc func copy(_ sender: Any?) {
        (delegate as? BookmarkList)?.copy(sender)
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(NSText.copy(_:)) {
            return !selectedRowIndexes.isEmpty
        }
        return true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if let fr = window?.firstResponder as? NSTextView, fr.isFieldEditor {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 51 || event.keyCode == 117,
           let list = delegate as? BookmarkList {
            list.confirmAndDeleteSelectedItems()
            return
        }
        if event.keyCode == 36,
           let list = delegate as? BookmarkList {
            list.beginEditingSelectedItem()
            return
        }
        super.keyDown(with: event)
    }
}
