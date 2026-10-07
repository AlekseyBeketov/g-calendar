import AppKit
import SwiftUI

/// The toolbar owns its field editor; focus requests target this exact control.
struct WorkspaceSearchField: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let focusRequest: Int
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("workspace-search-field")
        context.coordinator.lastFocusRequest = focusRequest
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = label
        field.setAccessibilityLabel(label)
        if field.stringValue != text { field.stringValue = text }
        guard context.coordinator.lastFocusRequest != focusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window, window.attachedSheet == nil else { return }
            window.makeFirstResponder(field)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: WorkspaceSearchField
        var lastFocusRequest = 0
        init(_ parent: WorkspaceSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.onFocusChange(true) }
        func controlTextDidEndEditing(_ notification: Notification) { parent.onFocusChange(false) }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            parent.text = ""
            textView.string = ""
            (control as? NSTextField)?.stringValue = ""
            return true
        }
    }
}
