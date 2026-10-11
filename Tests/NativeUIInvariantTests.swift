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
        let cursorButton = NSButton(frame: NSRect(x: 10, y: 10, width: 80, height: 30))
        cursorButton.title = "Synthetic action"
        document.addSubview(cursorButton)
        let cursorBridge = NativeActionCursorBridge.install(in: window)!
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        let scansBeforeBurst = cursorBridge.scanCount
        for offset in 0..<12 {
            cursorButton.frame.origin.x = CGFloat(10 + offset)
            cursorBridge.requestRefresh()
            RunLoop.main.run(until: Date().addingTimeInterval(0.003))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        print("PERF cursor_burst_requests=12 traversals=\(cursorBridge.scanCount - scansBeforeBurst) native_views=\(cursorBridge.lastVisitedViewCount) ax_nodes=\(cursorBridge.lastVisitedAccessibilityCount)")
        fflush(stdout)
        // The production burst is asserted after the hosting regression seam.
        let cursorBurstTraversals = cursorBridge.scanCount - scansBeforeBurst
        let token = CalendarGridContentToken(days: [], calendars: [], timeZoneID: "UTC")
        func configureTokenGrid(_ token: CalendarGridContentToken) {
            grid.configure(axis: AnyView(Color.clear), headers: AnyView(Color.clear), days: AnyView(Color.clear),
                           axisWidth: 44, headerHeight: 100, documentWidth: 1800, documentHeight: 1200,
                           initialVerticalOffset: 384, contentToken: token)
        }
        configureTokenGrid(token)
        let legacyGrid = CalendarScrollRegionsView()
        for _ in 0..<20 {
            legacyGrid.configure(axis: AnyView(Color.clear), headers: AnyView(Color.clear), days: AnyView(Color.clear),
                                 axisWidth: 44, headerHeight: 100, documentWidth: 1800, documentHeight: 1200, initialVerticalOffset: 384)
        }
        let beforeIdentical = grid.rootReplacementCount
        let beforeLayouts = grid.configurationLayoutRequests
        for _ in 0..<20 { configureTokenGrid(token) }
        print("PERF hosting_identical_updates=20 legacy_root_replacements=\(legacyGrid.rootReplacementCount) root_replacements=\(grid.rootReplacementCount - beforeIdentical) layout_requests=\(grid.configurationLayoutRequests - beforeLayouts)")
        fflush(stdout)
        expect(grid.rootReplacementCount == beforeIdentical, "identical explicit content token must skip all host roots")
        expect(grid.configurationLayoutRequests == beforeLayouts, "identical geometry must skip requested layout")
        expect(cursorBurstTraversals <= 3, "cursor burst must coalesce traversals and retain a trailing refresh")
        let finalButtonRect = cursorBridge.convert(cursorButton.visibleRect.intersection(cursorButton.bounds), from: cursorButton)
        expect(cursorBridge.debugActionRects.contains { $0.contains(NSPoint(x: finalButtonRect.midX, y: finalButtonRect.midY)) },
               "coalesced cursor scan retains final button geometry")
        cursorButton.isEnabled = false
        cursorBridge.requestRefresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        expect(!cursorBridge.debugActionRects.contains { $0.contains(NSPoint(x: finalButtonRect.midX, y: finalButtonRect.midY)) }, "disabled native action has no hand region")
        cursorButton.isEnabled = true
        cursorButton.isHidden = true
        cursorBridge.requestRefresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        expect(!cursorBridge.debugActionRects.contains { $0.contains(NSPoint(x: finalButtonRect.midX, y: finalButtonRect.midY)) }, "hidden native action has no hand region")
        cursorButton.isHidden = false
        let textOnly = NSTextField(frame: NSRect(x: 260, y: 220, width: 120, height: 24))
        document.addSubview(textOnly)
        cursorBridge.requestRefresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        let textRect = cursorBridge.convert(textOnly.visibleRect.intersection(textOnly.bounds), from: textOnly)
        expect(!textRect.isEmpty && !cursorBridge.debugActionRects.contains { $0.contains(NSPoint(x: textRect.midX, y: textRect.midY)) },
               "editable native text retains its text cursor region")
        expect(cursorBridge.hitTest(NSPoint(x: finalButtonRect.midX, y: finalButtonRect.midY)) == nil && !cursorBridge.isAccessibilityElement(),
               "native cursor bridge never changes hit testing or accessibility")
        let paddedAction = PointerCursorRegionView(frame: NSRect(x: 180, y: 100, width: 160, height: 44))
        document.addSubview(paddedAction)
        expect(paddedAction.actionCursorRect == paddedAction.bounds,
               "SwiftUI action cursor covers full padded action bounds even when visibleRect is larger")
        let paddedWindowRect = cursorBridge.convert(paddedAction.actionCursorRect, from: paddedAction)
        expect(!paddedWindowRect.contains(NSPoint(x: textRect.midX, y: textRect.midY)),
               "SwiftUI action cursor excludes adjacent editable text")
        paddedAction.actionEnabled = false
        expect(paddedAction.actionCursorRect.isEmpty, "disabled SwiftUI action has no hand cursor region")
        expect(paddedAction.hitTest(.zero) == nil && !paddedAction.isAccessibilityElement(),
               "SwiftUI cursor owner preserves hit testing and accessibility")
        let clippedScroll = NSScrollView(frame: NSRect(x: 20, y: 180, width: 70, height: 30))
        let clippedDocument = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        let clippedButton = NSButton(frame: NSRect(x: 40, y: 0, width: 100, height: 30))
        clippedDocument.addSubview(clippedButton)
        clippedScroll.documentView = clippedDocument
        document.addSubview(clippedScroll)
        cursorBridge.requestRefresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        let clippedAction = cursorBridge.convert(clippedButton.visibleRect.intersection(clippedButton.bounds), from: clippedButton)
        let fullAction = cursorBridge.convert(clippedButton.bounds, from: clippedButton)
        expect(clippedAction.width < fullAction.width && cursorBridge.debugActionRects.contains { $0.contains(NSPoint(x: clippedAction.midX, y: clippedAction.midY)) },
               "clipped native action retains only visible hand region")
        expect(!cursorBridge.debugActionRects.contains { $0.contains(NSPoint(x: fullAction.maxX - 1, y: fullAction.midY)) },
               "cursor owner cannot extend beyond ancestor clipping")
        let changedToken = CalendarGridContentToken(days: [], calendars: [CalendarInfo(id: "c", title: "New title", accessRole: "reader", timeZoneID: "UTC", colorHex: "#112233")], timeZoneID: "UTC")
        configureTokenGrid(changedToken)
        expect(grid.rootReplacementCount == beforeIdentical + 3, "changed calendar title/role/color replaces roots despite unchanged fetched timestamp")
        var changedEnvironment = changedToken
        changedEnvironment.sizeCategory = .accessibilityLarge
        configureTokenGrid(changedEnvironment)
        expect(grid.rootReplacementCount == beforeIdentical + 6, "changed dynamic type replaces native roots")
        changedEnvironment.colorScheme = .dark
        changedEnvironment.localeIdentifier = "ru_RU"
        configureTokenGrid(changedEnvironment)
        expect(grid.rootReplacementCount == beforeIdentical + 9, "changed appearance/locale replaces native roots")
        let changedCalendarEvent = try! CalendarEvent.decode(["id": "same-id", "summary": "Changed in same snapshot timestamp", "start": ["date": "2026-10-01"], "end": ["date": "2026-10-02"]], calendarID: "c")
        let changedDay = CalendarDayContent(day: Date(timeIntervalSince1970: 1), events: [changedCalendarEvent], tasks: [], allDayEventCount: 1)
        let changedData = CalendarGridContentToken(days: [changedDay], calendars: changedEnvironment.calendars, timeZoneID: "UTC")
        configureTokenGrid(changedData)
        expect(grid.rootReplacementCount == beforeIdentical + 12, "changed projected event/filter data replaces roots independently of cache timestamp")
        let replacementOwner = NSObject()
        changedEnvironment.actionOwnerIdentity = ObjectIdentifier(replacementOwner)
        configureTokenGrid(changedEnvironment)
        expect(grid.rootReplacementCount == beforeIdentical + 15, "replaced callback owner invalidates roots and captured actions")
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
        assertions += WorkspaceToolbarNativeTests.run()
        assertions += CalendarTimedCardNativeTests.run()
        let beforeCloseScans = cursorBridge.scanCount
        cursorBridge.requestRefresh()
        window.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        expect(cursorBridge.scanCount == beforeCloseScans, "window close cancels queued cursor scan")
        print("PASS native-clip-observation-and-scoped-keyboard")
        print("NATIVE_UI_ASSERTIONS=\(assertions)")
    }
}
