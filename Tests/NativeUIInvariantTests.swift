import AppKit
import SwiftUI

@main
struct NativeUIInvariantTests {
    static func main() {
        _ = NSApplication.shared
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError("FAIL native-ui: \(name)") }
            assertions += 1
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }

        // An offscreen fixture window, never ordered front and never contains user data.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = document
        let grid = CalendarScrollRegionsView(frame: document.bounds)
        document.addSubview(grid)
        func configureGrid() {
            grid.configure(axis: AnyView(Color.clear), headers: AnyView(Color.clear), days: AnyView(Color.clear),
                           axisWidth: 44, headerHeight: 100, documentWidth: 1800, documentHeight: 1200,
                           initialVerticalOffset: 384)
            grid.layoutSubtreeIfNeeded()
            settle()
        }
        configureGrid()
        expect(grid.daysScroll.documentView?.isFlipped == true, "hosting document starts at top")
        expect(grid.daysScroll.contentView.bounds.minY == 384, "initial native 08:00 anchor")
        expect(grid.axisScroll.contentView.bounds.minY == 384, "initial axis vertical alignment")
        grid.daysScroll.contentView.scroll(to: NSPoint(x: 640, y: 480))
        grid.daysScroll.reflectScrolledClipView(grid.daysScroll.contentView)
        settle()
        expect(grid.headerScroll.contentView.bounds.minX == 640, "header follows native horizontal clip")
        expect(grid.axisScroll.frame.minX == 0 && grid.axisScroll.contentView.bounds.minX == 0, "axis structurally fixed horizontally")
        expect(grid.axisScroll.contentView.bounds.minY == 480, "axis follows native vertical clip")
        grid.headerScroll.contentView.scroll(to: .zero)
        settle()
        expect(grid.daysScroll.contentView.bounds.minX == 0, "header reverse scroll moves timed days")
        grid.axisScroll.contentView.scroll(to: NSPoint(x: 0, y: 700))
        settle()
        expect(grid.daysScroll.contentView.bounds.minY == 700, "axis wheel movement moves timed days")
        configureGrid()
        expect(grid.daysScroll.contentView.bounds.minY == 700, "state update preserves manual vertical scroll")
        expect(grid.headerScroll.frame.maxY == grid.daysScroll.frame.minY, "headers stay outside vertical clip")
        grid.disconnect()
        grid.daysScroll.contentView.scroll(to: NSPoint(x: 300, y: 500))
        settle()
        expect(grid.headerScroll.contentView.bounds.minX == 0 && grid.axisScroll.contentView.bounds.minY == 700,
               "dismantled native sync stops observing")

        let responder = TaskKeyboardResponderView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        document.addSubview(responder)
        var commands: [TaskKeyboardCommand] = []
        responder.onCommand = { commands.append($0) }
        expect(window.makeFirstResponder(responder), "workspace accepts native focus")
        func event(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], repeated: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                            isARepeat: repeated, keyCode: keyCode)!
        }
        responder.keyDown(with: event(125))
        responder.keyDown(with: event(36))
        responder.keyDown(with: event(49))
        expect(commands == [.next, .edit, .toggleCompletion], "scoped native keyboard commands")
        responder.keyDown(with: event(49, repeated: true))
        expect(commands.count == 3, "held completion does not repeat mutation")
        responder.keyDown(with: event(125, modifiers: .command))
        expect(commands.count == 3, "modified arrows remain native commands")
        let field = NSTextField(frame: NSRect(x: 0, y: 100, width: 200, height: 24))
        document.addSubview(field)
        expect(window.makeFirstResponder(field), "text editor retains native focus")
        responder.keyDown(with: event(49))
        expect(commands.count == 3, "workspace does not handle text-editor keys")
        var searchValue = "fixture"
        let search = WorkspaceSearchField(text: Binding(get: { searchValue }, set: { searchValue = $0 }),
                                          label: "Поиск задач", focusRequest: 0, onFocusChange: { _ in })
        let coordinator = WorkspaceSearchField.Coordinator(search)
        let editor = NSTextView()
        editor.string = "fixture"
        expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))),
               "search handles Escape without workspace mutation")
        expect(searchValue.isEmpty && editor.string.isEmpty && field.stringValue.isEmpty, "search Escape clears binding and editor")
        expect(!coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))),
               "search retains other native text commands")
        window.close()
        print("PASS native-clip-observation-and-scoped-keyboard")
        print("NATIVE_UI_ASSERTIONS=\(assertions)")
    }
}
