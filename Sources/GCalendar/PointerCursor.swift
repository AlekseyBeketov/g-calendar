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

final class PointerCursorRegionView: NSView {
    var actionEnabled = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var actionCursorRect: NSRect {
        guard actionEnabled, !isHiddenOrHasHiddenAncestor else { return .zero }
        return visibleRect.intersection(bounds)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let rect = actionCursorRect
        if !rect.isEmpty { addCursorRect(rect, cursor: .pointingHand) }
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
final class NativeActionCursorBridge: NSView {
    private static let installed = NSMapTable<NSWindow, NativeActionCursorBridge>(keyOptions: .weakMemory, valueOptions: .weakMemory)
    private var actionRects: [NSRect] = []
    private var observations: [NSObjectProtocol] = []
    private var timer: Timer?
    private var pendingRefresh: DispatchWorkItem?
    private var disconnected = false
    private var eventMonitor: Any?
    private var cursorUpdateQueued = false
    private var ownsHandCursor = false
    private var acceptedMouseMovedEvents = false
    private(set) var scanCount = 0
    private(set) var lastVisitedViewCount = 0
    private(set) var lastVisitedAccessibilityCount = 0
    var debugActionRects: [NSRect] { actionRects }

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
        acceptedMouseMovedEvents = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        // SwiftUI can overwrite cursor rectangles while dispatching a hover event.
        // Apply the window's action cursor afterwards, without consuming the event.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .cursorUpdate, .mouseExited]) { [weak self] event in
            if let self, event.window === self.window { self.queueCursorUpdate() }
            return event
        }
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

    private func queueCursorUpdate() {
        guard !disconnected, !cursorUpdateQueued else { return }
        cursorUpdateQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cursorUpdateQueued = false
            guard !self.disconnected, let window = self.window,
                  window.isVisible, NSApp.isActive, window.attachedSheet == nil,
                  NSEvent.pressedMouseButtons == 0 else { return }
            let point = window.mouseLocationOutsideOfEventStream
            let bridgePoint = self.convert(point, from: nil)
            // Preserve the field editor and native controls that implement editing.
            var hit = window.contentView.flatMap { $0.hitTest($0.convert(point, from: nil)) }
            var isText = false
            var isNativeOnly = false
            while let view = hit {
                if let text = view as? NSTextView, text.isEditable || text.isSelectable { isText = true }
                if let text = view as? NSTextField, text.isEditable || text.isSelectable { isText = true }
                if view is NSScroller || ((view as? NSControl)?.isEnabled == false) { isNativeOnly = true }
                hit = view.superview
            }
            let actionable = !isText && !isNativeOnly && self.visibleRect.contains(bridgePoint)
                && self.actionRects.contains { $0.contains(bridgePoint) }
            if actionable {
                NSCursor.pointingHand.set()
                self.ownsHandCursor = true
            } else if self.ownsHandCursor {
                // Only undo our cursor; retain a cursor already chosen by AppKit.
                if NSCursor.current.isEqual(NSCursor.pointingHand) {
                    (isText ? NSCursor.iBeam : NSCursor.arrow).set()
                }
                self.ownsHandCursor = false
            }
        }
    }

    func requestRefresh() {
        guard !disconnected, pendingRefresh == nil else { return }
        // First request owns a short fixed window. Every request in that window
        // is reflected by the final tree/AX geometry read, without starvation.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.disconnected else { return }
            self.pendingRefresh = nil
            self.refreshRects()
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40), execute: work)
    }

    private func refreshRects() {
        guard let frameView = superview, let window else { return }
        if let sheet = window.attachedSheet { Self.install(in: sheet)?.requestRefresh() }
        scanCount += 1
        lastVisitedViewCount = 0
        lastVisitedAccessibilityCount = 0
        var rects: [NSRect] = []
        func visit(_ view: NSView) {
            lastVisitedViewCount += 1
            guard view !== self, !view.isHiddenOrHasHiddenAncestor, !view.visibleRect.isEmpty else { return }
            if let region = view as? PointerCursorRegionView {
                let rect = convert(region.actionCursorRect, from: region).intersection(visibleRect)
                if !rect.isEmpty { rects.append(rect) }
            }
            if let control = view as? NSControl {
                // A disabled composite control may still expose enabled implementation subviews.
                guard control.isEnabled else { return }
                if control is NSButton || control is NSSegmentedControl || control is NSStepper || control is NSSwitch {
                    // On macOS 14+, visibleRect may extend beyond bounds when drawing is not clipped.
                    let rect = convert(view.visibleRect.intersection(view.bounds), from: view).intersection(visibleRect)
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
        let clip = convert(picker.visibleRect.intersection(picker.bounds), from: picker).intersection(visibleRect)
        func visit(_ element: NSAccessibilityProtocol, depth: Int) {
            lastVisitedAccessibilityCount += 1
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
        disconnected = true
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        window?.acceptsMouseMovedEvents = acceptedMouseMovedEvents
        pendingRefresh?.cancel()
        pendingRefresh = nil
        timer?.invalidate()
        timer = nil
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
        observations.removeAll()
        actionRects.removeAll()
        discardCursorRects()
    }

    deinit { disconnect() }
}
