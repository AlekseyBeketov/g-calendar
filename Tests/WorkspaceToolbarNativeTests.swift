import AppKit
import SwiftUI

private final class ToolbarFixtureState: ObservableObject {
    @Published var text = ""
    @Published var focused = false
    @Published var focusRequest = 0
    @Published var syncing = false
}

private struct ToolbarFixture: View {
    @ObservedObject var state: ToolbarFixtureState
    let isCalendar: Bool
    var body: some View {
        Color.clear.frame(minWidth: 300, minHeight: 180)
            .toolbar {
                WorkspaceToolbar(isCalendar: isCalendar, searchText: $state.text,
                                 focusRequest: state.focusRequest, searchFocused: $state.focused,
                                 isSyncing: state.syncing, mutationInFlight: false,
                                 moveDate: { _ in }, goToToday: {}, refresh: {}, openSettings: {})
            }
    }
}

/// Never orders windows front; the only data is the fixture string below.
/// Private AppKit class names are observation only, never used by production.
enum WorkspaceToolbarNativeTests {
    static func run() -> Int {
        var assertions = 0
        var failures: [String] = []
        var metrics: [String] = []
        func expect(_ condition: Bool, _ name: String) {
            assertions += 1
            if !condition { failures.append(name) }
        }
        func settle(_ window: NSWindow) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            window.contentView?.superview?.layoutSubtreeIfNeeded()
        }
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { descendants($0) }
        }
        func capture(_ toolbar: NSView, _ name: String, _ directory: URL?) -> NSBitmapImageRep? {
            guard let bitmap = toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds) else { return nil }
            toolbar.cacheDisplay(in: toolbar.bounds, to: bitmap)
            if let directory { try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(name).png")) }
            return bitmap
        }
        let directory = ProcessInfo.processInfo.environment["G_CALENDAR_NATIVE_EVIDENCE_DIR"].map { URL(fileURLWithPath: $0) }
        if let directory { try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        for appearance in ["light", "dark", "system"] {
            for width in [900, 700, 600] {
                for isCalendar in [false, true] {
                    let state = ToolbarFixtureState()
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 300),
                                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                          backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.toolbarStyle = .unified
                    window.appearance = appearance == "system" ? nil : NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                    window.contentView = NSHostingView(rootView: ToolbarFixture(state: state, isCalendar: isCalendar))
                    settle(window)
                    let root = window.contentView!.superview!
                    let name = "\(isCalendar ? "calendar" : "tasks")-\(width)-\(appearance)"
                    expect(!window.isVisible, "\(name): fixture stays offscreen")
                    guard let field = descendants(root).compactMap({ $0 as? NSTextField }).first(where: { $0.accessibilityIdentifier() == "workspace-search-field" }) else {
                        // Calendar already moves search into native overflow at 600pt.
                        // Record this existing behavior rather than altering its layout.
                        if isCalendar && width == 600, let toolbar = window.toolbar {
                            expect((toolbar.visibleItems?.count ?? toolbar.items.count) < toolbar.items.count, "\(name): native overflow remains available")
                            metrics.append("\(name) search=overflow items=\(toolbar.items.count) visible=\(toolbar.visibleItems?.count ?? -1)")
                            if let directory, let view = descendants(root).first(where: { String(describing: type(of: $0)) == "NSToolbarView" }),
                               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                                view.cacheDisplay(in: view.bounds, to: bitmap)
                                try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(name)-overflow.png"))
                            }
                        } else { failures.append("\(name): production search field missing") }
                        window.close()
                        continue
                    }
                    expect(!field.isBordered && !field.drawsBackground && field.focusRingType == .none, "\(name): native field remains borderless")
                    expect(field.placeholderString == (isCalendar ? "Поиск событий" : "Поиск задач"), "\(name): placeholder")
                    expect(field.accessibilityLabel() == field.placeholderString, "\(name): accessibility label")
                    for phase in ["empty", "text", "loading", "focus"] {
                        state.text = phase == "empty" ? "" : "Synthetic search"
                        state.syncing = phase == "loading"
                        // Render the production focus outline without requiring a visible/key window.
                        state.focused = phase == "focus"
                        settle(window)
                        guard let field = descendants(root).compactMap({ $0 as? NSTextField }).first(where: { $0.accessibilityIdentifier() == "workspace-search-field" }) else {
                            expect(isCalendar && width < 900 && (window.toolbar?.visibleItems?.count ?? 0) < (window.toolbar?.items.count ?? 0), "\(name)-\(phase): search moves into native overflow")
                            metrics.append("\(name)-\(phase) search=overflow")
                            if let toolbar = descendants(root).first(where: { String(describing: type(of: $0)) == "NSToolbarView" }) { _ = capture(toolbar, "\(name)-\(phase)-overflow", directory) }
                            continue
                        }
                        expect(field.stringValue == state.text, "\(name)-\(phase): binding reaches native field")
                        guard let host = sequence(first: field.superview, next: { $0?.superview }).compactMap({ $0 }).first(where: { String(describing: type(of: $0)).hasPrefix("ToolbarItemHostingView") }),
                              let toolbar = descendants(root).first(where: { String(describing: type(of: $0)) == "NSToolbarView" }),
                              let bitmap = toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds) else {
                            failures.append("\(name)-\(phase): native toolbar render unavailable")
                            continue
                        }
                        toolbar.cacheDisplay(in: toolbar.bounds, to: bitmap)
                        if let directory {
                            try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(name)-\(phase).png"))
                        }
                        let hostBounds = toolbar.convert(host.bounds, from: host)
                        let fieldBounds = toolbar.convert(field.bounds, from: field)
                        var line = "\(name)-\(phase) host=\(hostBounds) field=\(fieldBounds) items=\(window.toolbar?.items.count ?? 0)"
                        // On glass toolbar systems, measure the actual rendered accent outline
                        // against its native enclosing capsule, rather than a model rectangle.
                        if phase == "focus", #available(macOS 26.0, *) {
                            let platter = sequence(first: host.superview, next: { $0?.superview }).compactMap({ $0 }).first { String(describing: type(of: $0)) == "NSToolbarPlatterView" }
                            expect(platter != nil, "\(name): native enclosing capsule exists")
                            if let platter {
                                let capsule = toolbar.convert(platter.bounds, from: platter)
                                let scaleX = CGFloat(bitmap.pixelsWide) / toolbar.bounds.width
                                let scaleY = CGFloat(bitmap.pixelsHigh) / toolbar.bounds.height
                                var xs: [Int] = []
                                var ys: [Int] = []
                                for y in 0..<bitmap.pixelsHigh {
                                    for x in 0..<bitmap.pixelsWide {
                                        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                                        if c.blueComponent > c.redComponent + 0.15 && c.blueComponent > c.greenComponent + 0.08 {
                                            xs.append(x); ys.append(y)
                                        }
                                    }
                                }
                                expect(!xs.isEmpty, "\(name): focus outline present in raster")
                                if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
                                    let pixelBounds = NSRect(x: CGFloat(minX) / scaleX, y: CGFloat(minY) / scaleY,
                                                             width: CGFloat(maxX - minX + 1) / scaleX, height: CGFloat(maxY - minY + 1) / scaleY)
                                    let leftGap = pixelBounds.minX - capsule.minX
                                    line += " capsule=\(capsule) rasterOutline=\(pixelBounds) leftGap=\(leftGap)"
                                    expect(leftGap >= (isCalendar ? 30 : 7), "\(name): rendered search outline clears native capsule (gap=\(leftGap))")
                                    expect(capsule.maxX - pixelBounds.maxX >= 7 && pixelBounds.minY - capsule.minY >= 3 && capsule.maxY - pixelBounds.maxY >= 3, "\(name): raster outline has breathing space inside capsule")
                                    expect(abs(pixelBounds.height - 28) <= 1, "\(name): search outline height preserved")
                                    if isCalendar { expect(abs(hostBounds.width - pixelBounds.width) <= 1, "\(name): Calendar has no added outer inset") }
                                    else { expect(abs(hostBounds.width - pixelBounds.width - 16) <= 1, "\(name): Tasks outer inset is 8pt each side") }
                                }
                            }
                        }
                        metrics.append(line)
                    }
                    state.syncing = false
                    state.text = "Synthetic search"
                    settle(window)
                    guard let field = descendants(root).compactMap({ $0 as? NSTextField }).first(where: { $0.accessibilityIdentifier() == "workspace-search-field" }) else {
                        expect(isCalendar && width < 900, "\(name): only narrow Calendar overflows")
                        window.close()
                        continue
                    }
                    state.focusRequest += 1
                    settle(window)
                    expect(window.firstResponder === field.currentEditor(), "\(name): focus request targets field editor")
                    field.stringValue = "Typed fixture"
                    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
                    settle(window)
                    expect(state.text == "Typed fixture", "\(name): typing updates production binding")
                    let editor = field.currentEditor() as? NSTextView ?? NSTextView()
                    let handled = field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))) ?? false
                    settle(window)
                    expect(handled && state.text.isEmpty && field.stringValue.isEmpty, "\(name): Escape clears search")
                    window.close()
                }
            }
        }
        let report = (metrics + failures.map { "FAIL \($0)" }).joined(separator: "\n") + "\n"
        if let directory { try! report.write(to: directory.appendingPathComponent("bounds.txt"), atomically: true, encoding: .utf8) }
        print(report)
        guard failures.isEmpty else { fatalError("FAIL production-toolbar: \(failures.count) failures; see bounds report") }
        print("PASS production-toolbar-offscreen assertions=\(assertions)")
        return assertions
    }
}
