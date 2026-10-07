import AppKit
import SwiftUI

/// A key-view-loop stop, not an event monitor. Text editors, menus, other controls
/// and attached sheets retain their own responder chain and default commands.
struct TaskKeyboardFocusView: NSViewRepresentable {
    let focusRequest: UUID
    let onFocusChange: (Bool) -> Void
    let onCommand: (TaskKeyboardCommand) -> Void

    func makeNSView(context: Context) -> TaskKeyboardResponderView {
        let view = TaskKeyboardResponderView()
        view.lastFocusRequest = focusRequest
        view.onFocusChange = onFocusChange
        view.onCommand = onCommand
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityIdentifier("task-keyboard-navigation")
        view.setAccessibilityLabel("Список задач. Стрелки — выбор, Return — редактирование, Space — выполнение.")
        return view
    }

    func updateNSView(_ view: TaskKeyboardResponderView, context: Context) {
        view.onFocusChange = onFocusChange
        view.onCommand = onCommand
        guard view.lastFocusRequest != focusRequest else { return }
        view.lastFocusRequest = focusRequest
        // Never move focus into the presenting window while a sheet owns input.
        DispatchQueue.main.async { [weak view] in
            guard let view, let window = view.window, window.isKeyWindow, window.attachedSheet == nil else { return }
            window.makeFirstResponder(view)
        }
    }
}

final class TaskKeyboardResponderView: NSView {
    var lastFocusRequest = UUID()
    var onFocusChange: (Bool) -> Void = { _ in }
    var onCommand: (TaskKeyboardCommand) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.recalculateKeyViewLoop()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { DispatchQueue.main.async { [weak self] in self?.onFocusChange(true) } }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { DispatchQueue.main.async { [weak self] in self?.onFocusChange(false) } }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        guard window?.attachedSheet == nil else { return }
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard window?.firstResponder === self, window?.attachedSheet == nil else { super.keyDown(with: event); return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 48 && modifiers.subtracting(.shift).isEmpty {
            if modifiers.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
            return
        }
        if let command = TaskKeyboardNavigation.command(keyCode: event.keyCode, hasModifiers: !modifiers.isEmpty, isRepeat: event.isARepeat) {
            onCommand(command)
            return
        }
        // Holding Return or Space must not edit/mutate repeatedly or beep.
        if event.isARepeat && modifiers.isEmpty && [36, 76, 49].contains(event.keyCode) { return }
        super.keyDown(with: event)
    }
}
