import AppKit

/// NSOutlineView サブクラス。
/// スローダブルクリック編集・右クリックメニュー・キーボードショートカットを処理する。
class LinkKeeperOutlineView: NSOutlineView {

    private var editTimer: Timer?
    private var lastClickedRow: Int = -1

    // MARK: - First Responder

    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if let textField = responder as? NSTextField, textField.isEditable {
            return true
        }
        return super.validateProposedFirstResponder(responder, for: event)
    }

    // MARK: - Slow Double Click (Finder-style Rename)

    override func mouseDown(with event: NSEvent) {
        if let fieldEditor = window?.firstResponder as? NSTextView, fieldEditor.isFieldEditor {
            let pointInEditor = fieldEditor.convert(event.locationInWindow, from: nil)
            if fieldEditor.bounds.contains(pointInEditor) {
                fieldEditor.mouseDown(with: event)
                return
            }
            window?.makeFirstResponder(self)
        }

        cancelPendingEdit()

        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        let wasAlreadySelected = clickedRow >= 0 && selectedRowIndexes.contains(clickedRow)

        super.mouseDown(with: event)

        if wasAlreadySelected && clickedRow >= 0 && event.clickCount == 1 {
            let col = column(at: point)
            guard col == 0 else { return }

            lastClickedRow = clickedRow
            editTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval + 0.05,
                                             repeats: false) { [weak self] _ in
                guard let self = self else { return }
                guard self.lastClickedRow == clickedRow,
                      self.selectedRowIndexes.contains(clickedRow) else { return }
                if let cellView = self.view(atColumn: 0, row: clickedRow, makeIfNecessary: false) as? BookmarkCellView {
                    cellView.beginEditing()
                }
            }
        }
    }

    func cancelPendingEdit() {
        editTimer?.invalidate()
        editTimer = nil
        lastClickedRow = -1
    }

    override func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        cancelPendingEdit()
        super.draggingSession(session, willBeginAt: screenPoint)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)

        if clickedRow >= 0 {
            if !selectedRowIndexes.contains(clickedRow) {
                selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }
        } else {
            deselectAll(nil)
        }

        guard let controller = delegate as? OutlineViewController else { return nil }
        return controller.contextMenu(for: clickedRow)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if let fr = window?.firstResponder as? NSTextView, fr.isFieldEditor {
            super.keyDown(with: event)
            return
        }

        // Delete / Backspace → 確認ダイアログ付き削除
        if event.keyCode == 51 || event.keyCode == 117 {
            if let controller = delegate as? OutlineViewController {
                controller.confirmAndDeleteSelectedItems()
                return
            }
        }
        // Enter -> rename
        if event.keyCode == 36 {
            if let controller = delegate as? OutlineViewController {
                controller.beginEditingSelectedItem()
                return
            }
        }
        super.keyDown(with: event)
    }
}
