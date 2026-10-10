import AppKit
import SwiftUI

extension View {
    /// Apply to the action control, before `.disabled`, after its label has its full hit bounds.
    /// Cursor rectangles do not intercept clicks, change focus, or replace native menu behavior.
    func pointingHandCursor() -> some View { modifier(PointingHandCursorModifier()) }
}

private struct PointingHandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.overlay {
            PointerCursorRegion(enabled: isEnabled)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct PointerCursorRegion: NSViewRepresentable {
    let enabled: Bool

    func makeNSView(context: Context) -> PointerCursorRegionView { PointerCursorRegionView() }

    func updateNSView(_ view: PointerCursorRegionView, context: Context) {
        view.actionEnabled = enabled
        view.invalidateRegions()
    }

    static func dismantleNSView(_ view: PointerCursorRegionView, coordinator: ()) {
        view.discardCursorRects()
        view.actionEnabled = false
        view.invalidateRegions()
    }
}

private final class PointerCursorRegionView: NSView {
    var actionEnabled = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard actionEnabled, !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else { return }
        addCursorRect(visibleRect, cursor: .pointingHand)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateRegions()
    }

    override func layout() {
        super.layout()
        invalidateRegions()
    }

    func invalidateRegions() {
        guard let window else { return }
        window.invalidateCursorRects(for: self)
        NativeActionCursorBridge.install(in: window)?.requestRefresh()
    }
}

/// One transparent cursor owner per application window, including attached editor sheets.
/// Covers AppKit controls generated outside a SwiftUI label, such as the sidebar toolbar button
/// and date-picker increment/decrement buttons. Editable text and window drag regions are skipped.
private final class NativeActionCursorBridge: NSView {
    private static let installed = NSMapTable<NSWindow, NativeActionCursorBridge>(keyOptions: .weakMemory, valueOptions: .weakMemory)
    private var actionRects: [NSRect] = []
    private var observations: [NSObjectProtocol] = []
    private var timer: Timer?
    private var refreshQueued = false

    static func install(in window: NSWindow) -> NativeActionCursorBridge? {
        if let existing = installed.object(forKey: window) { return existing }
        guard let frameView = window.contentView?.superview else { return nil }
        let bridge = NativeActionCursorBridge(frame: frameView.bounds)
        bridge.autoresizingMask = [.width, .height]
        frameView.addSubview(bridge, positioned: .above, relativeTo: nil)
        installed.setObject(bridge, forKey: window)
        bridge.observe(window)
        return bridge
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in actionRects { addCursorRect(rect, cursor: .pointingHand) }
    }

    override func layout() {
        super.layout()
        requestRefresh()
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didUpdateNotification] {
            observations.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.requestRefresh()
            })
        }
        observations.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let view = notification.object as? NSView, view.window === self.window else { return }
            self.requestRefresh()
        })
        observations.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.disconnect()
            self?.removeFromSuperview()
        })
        // Native enabled/hidden changes do not necessarily emit a layout notification.
        // The lightweight native tree scan is limited to visible windows; no task-data traversal.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.requestRefresh()
        }
        requestRefresh()
    }

    func requestRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshQueued = false
            self.refreshRects()
        }
    }

    private func refreshRects() {
        guard let frameView = superview, let window else { return }
        if let sheet = window.attachedSheet { Self.install(in: sheet)?.requestRefresh() }
        var rects: [NSRect] = []
        func visit(_ view: NSView) {
            guard view !== self, !view.isHiddenOrHasHiddenAncestor, !view.visibleRect.isEmpty else { return }
            if let control = view as? NSControl {
                // A disabled composite control may still expose enabled implementation subviews.
                guard control.isEnabled else { return }
                if control is NSButton || control is NSSegmentedControl || control is NSStepper || control is NSSwitch {
                    let rect = convert(view.visibleRect, from: view).intersection(visibleRect)
                    if !rect.isEmpty { rects.append(rect) }
                } else if let datePicker = control as? NSDatePicker {
                    collectDateActions(datePicker, into: &rects)
                }
            }
            for child in view.subviews { visit(child) }
        }
        for child in frameView.subviews { visit(child) }
        guard rects != actionRects else { return }
        actionRects = rects
        window.invalidateCursorRects(for: self)
    }

    private func collectDateActions(_ picker: NSDatePicker, into rects: inout [NSRect]) {
        guard let window else { return }
        let clip = convert(picker.visibleRect, from: picker).intersection(visibleRect)
        func visit(_ element: NSAccessibilityProtocol, depth: Int) {
            guard depth < 8 else { return }
            if element.accessibilityRole() == .button && element.isAccessibilityEnabled() {
                let windowRect = window.convertFromScreen(element.accessibilityFrame())
                let rect = convert(windowRect, from: nil).intersection(clip)
                if !rect.isEmpty { rects.append(rect) }
            }
            for child in element.accessibilityChildren() ?? [] {
                if let child = child as? NSAccessibilityProtocol { visit(child, depth: depth + 1) }
            }
        }
        visit(picker, depth: 0)
    }

    private func disconnect() {
        timer?.invalidate()
        timer = nil
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
        observations.removeAll()
        actionRects.removeAll()
        discardCursorRects()
    }

    deinit { disconnect() }
}
