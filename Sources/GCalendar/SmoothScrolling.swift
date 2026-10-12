import AppKit

/// Smooth only coarse wheels. AppKit retains precise scrolling and momentum ownership.
final class SmoothScrollController {
    private var monitor: Any?
    private var timer: Timer?
    private weak var scrollView: NSScrollView?
    private var horizontal: ScrollInterpolation?
    private var vertical: ScrollInterpolation?
    private var lastOrigin: NSPoint?

    func start() {
        guard monitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                           .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .keyDown]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit {
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func cancel() {
        timer?.invalidate()
        timer = nil
        scrollView = nil
        horizontal = nil
        vertical = nil
        lastOrigin = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .scrollWheel else {
            cancel()
            return event
        }
        guard !event.hasPreciseScrollingDeltas, event.phase.isEmpty, event.momentumPhase.isEmpty,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let window = event.window, window.level.rawValue < NSWindow.Level.popUpMenu.rawValue,
              let root = window.contentView else {
            cancel()
            return event
        }
        let point = root.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        var hit = root.hitTest(point)
        let now = ProcessInfo.processInfo.systemUptime
        while let view = hit {
            if let candidate = view as? NSScrollView,
               beginScroll(in: candidate, event: event, time: now) {
                return nil
            }
            hit = view.superview
        }
        // At an edge preserve native responder forwarding, including nested scroll views.
        cancel()
        return event
    }

    private func beginScroll(in candidate: NSScrollView, event: NSEvent, time: TimeInterval) -> Bool {
        let clip = candidate.contentView
        guard candidate.documentView != nil else { return false }
        if scrollView !== candidate || lastOrigin != clip.bounds.origin {
            cancel()
        }
        let current = clip.bounds.origin
        let dx = -Double(event.scrollingDeltaX * candidate.horizontalLineScroll)
        let dy = Double(event.scrollingDeltaY * candidate.verticalLineScroll) * (clip.isFlipped ? -1 : 1)
        guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else { return false }
        let minimum = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: -1e9, y: -1e9), size: clip.bounds.size)).origin
        let maximum = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 1e9, y: 1e9), size: clip.bounds.size)).origin
        var x = horizontal ?? ScrollInterpolation(value: Double(current.x), time: time)
        var y = vertical ?? ScrollInterpolation(value: Double(current.y), time: time)
        x.retarget(by: dx, at: time, lowerBound: Double(minimum.x), upperBound: Double(maximum.x))
        y.retarget(by: dy, at: time, lowerBound: Double(minimum.y), upperBound: Double(maximum.y))
        let proposed = NSRect(origin: NSPoint(x: x.targetValue, y: y.targetValue), size: clip.bounds.size)
        let target = clip.constrainBoundsRect(proposed).origin
        guard target != current else { return false }
        scrollView = candidate
        horizontal = x
        vertical = y
        lastOrigin = current
        if timer == nil {
            let frameTimer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            timer = frameTimer
            RunLoop.main.add(frameTimer, forMode: .common)
        }
        return true
    }

    private func tick() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let scrollView, scrollView.window != nil, let horizontal, let vertical,
              scrollView.contentView.bounds.origin == lastOrigin else {
            cancel()
            return
        }
        let time = ProcessInfo.processInfo.systemUptime
        let clip = scrollView.contentView
        let proposed = NSRect(origin: NSPoint(x: horizontal.value(at: time), y: vertical.value(at: time)), size: clip.bounds.size)
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scrollView.reflectScrolledClipView(clip)
        lastOrigin = clip.bounds.origin
        if horizontal.isComplete(at: time) && vertical.isComplete(at: time) { cancel() }
    }
}
