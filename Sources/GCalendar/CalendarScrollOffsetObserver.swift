import AppKit
import SwiftUI

/// Own the native clips rather than infer their ancestry through SwiftUI hosting views.
/// The hour axis is structurally outside horizontal scrolling; all vertical movement
/// and header/day horizontal movement use the same observed native clip bounds.
struct CalendarNativeScrollableGrid: NSViewRepresentable {
    let axis: AnyView
    let headers: AnyView
    let days: AnyView
    let axisWidth: CGFloat
    let headerHeight: CGFloat
    let documentWidth: CGFloat
    let documentHeight: CGFloat
    let initialVerticalOffset: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> CalendarScrollRegionsView { CalendarScrollRegionsView() }

    func updateNSView(_ view: CalendarScrollRegionsView, context: Context) {
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        view.configure(axis: AnyView(axis.environment(\.colorScheme, colorScheme)),
                       headers: AnyView(headers.environment(\.colorScheme, colorScheme)),
                       days: AnyView(days.environment(\.colorScheme, colorScheme)),
                       axisWidth: axisWidth, headerHeight: headerHeight,
                       documentWidth: documentWidth, documentHeight: documentHeight,
                       initialVerticalOffset: initialVerticalOffset)
    }

    static func dismantleNSView(_ view: CalendarScrollRegionsView, coordinator: ()) { view.disconnect() }
}

final class CalendarScrollRegionsView: NSView {
    let axisScroll = NSScrollView()
    let headerScroll = NSScrollView()
    let daysScroll = NSScrollView()
    private let axisHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let headerHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let daysHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var observations: [NSObjectProtocol] = []
    private var synchronizing = false
    private var hasInitialOffset = false
    private var axisWidth: CGFloat = 44
    private var headerHeight: CGFloat = 100
    private var documentWidth: CGFloat = 1000
    private var documentHeight: CGFloat = 1160
    private var initialVerticalOffset: CGFloat = 384
    private let columnGap: CGFloat = 10

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for scroll in [axisScroll, headerScroll, daysScroll] {
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.contentView.postsBoundsChangedNotifications = true
            addSubview(scroll)
            observations.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                       object: scroll.contentView, queue: .main) { [weak self, weak scroll] _ in
                MainActor.assumeIsolated {
                    guard let self, let scroll, !self.synchronizing else { return }
                    DemoPerformanceProbe.shared.measureScrollSynchronization { self.synchronize(from: scroll) }
                }
            })
        }
        axisScroll.documentView = axisHost
        headerScroll.documentView = headerHost
        daysScroll.documentView = daysHost
        daysScroll.hasVerticalScroller = true
        daysScroll.hasHorizontalScroller = true
        // Headers accept horizontal wheel/AX scrolling without an extra scroller row.
        headerScroll.hasHorizontalScroller = false
        headerScroll.hasVerticalScroller = false
        axisScroll.hasHorizontalScroller = false
        axisScroll.hasVerticalScroller = false
        axisScroll.setAccessibilityLabel("Шкала времени")
        headerScroll.setAccessibilityLabel("Дни недели и события на весь день")
        daysScroll.setAccessibilityLabel("Календарная сетка со временем")
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    func configure(axis: AnyView, headers: AnyView, days: AnyView,
                   axisWidth: CGFloat, headerHeight: CGFloat,
                   documentWidth: CGFloat, documentHeight: CGFloat, initialVerticalOffset: CGFloat) {
        self.axisWidth = axisWidth
        self.headerHeight = headerHeight
        self.documentWidth = documentWidth
        self.documentHeight = documentHeight
        self.initialVerticalOffset = initialVerticalOffset
        axisHost.rootView = AnyView(axis.frame(width: axisWidth, height: documentHeight, alignment: .topLeading))
        headerHost.rootView = AnyView(headers.frame(width: documentWidth, height: headerHeight, alignment: .topLeading))
        daysHost.rootView = AnyView(days.frame(width: documentWidth, height: documentHeight, alignment: .topLeading))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let oldOrigin = daysScroll.contentView.bounds.origin
        synchronizing = true
        let contentX = axisWidth + columnGap
        let daysWidth = max(0, bounds.width - contentX)
        let timedHeight = max(0, bounds.height - headerHeight)
        headerScroll.frame = NSRect(x: contentX, y: 0, width: daysWidth, height: headerHeight)
        axisScroll.frame = NSRect(x: 0, y: headerHeight, width: axisWidth, height: timedHeight)
        daysScroll.frame = NSRect(x: contentX, y: headerHeight, width: daysWidth, height: timedHeight)
        axisHost.frame = NSRect(x: 0, y: 0, width: axisWidth, height: documentHeight)
        headerHost.frame = NSRect(x: 0, y: 0, width: documentWidth, height: headerHeight)
        daysHost.frame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        let origin: NSPoint
        if !hasInitialOffset && timedHeight > 0 && daysWidth > 0 {
            hasInitialOffset = true
            origin = NSPoint(x: 0, y: initialVerticalOffset)
        } else { origin = oldOrigin }
        setOrigin(origin, on: daysScroll)
        synchronizing = false
        synchronize(from: daysScroll)
    }

    private func setOrigin(_ requested: NSPoint, on scroll: NSScrollView) {
        guard let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let point = NSPoint(x: max(0, min(requested.x, max(0, document.frame.width - clip.bounds.width))),
                            y: max(0, min(requested.y, max(0, document.frame.height - clip.bounds.height))))
        if clip.bounds.origin != point { clip.scroll(to: point) }
        scroll.reflectScrolledClipView(clip)
    }

    private func synchronize(from source: NSScrollView) {
        guard !synchronizing else { return }
        synchronizing = true
        defer { synchronizing = false }
        let dayOrigin = daysScroll.contentView.bounds.origin
        let x = source === headerScroll ? headerScroll.contentView.bounds.minX : dayOrigin.x
        let y = source === axisScroll ? axisScroll.contentView.bounds.minY : dayOrigin.y
        setOrigin(NSPoint(x: x, y: y), on: daysScroll)
        let settledOrigin = daysScroll.contentView.bounds.origin
        setOrigin(NSPoint(x: settledOrigin.x, y: 0), on: headerScroll)
        setOrigin(NSPoint(x: 0, y: settledOrigin.y), on: axisScroll)
    }

    func disconnect() {
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
        observations.removeAll()
    }

    deinit { disconnect() }
}
