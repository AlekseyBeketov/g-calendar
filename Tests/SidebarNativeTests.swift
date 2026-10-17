import AppKit
import SwiftUI

final class SidebarProbeView: NSView {
    var action: (() -> Void)?
}

struct SidebarFrameProbe: NSViewRepresentable {
    let identifier: String
    let action: () -> Void
    func makeNSView(context: Context) -> SidebarProbeView { SidebarProbeView() }
    func updateNSView(_ view: SidebarProbeView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier("sidebar-probe-" + identifier)
        view.action = action
    }
}

private final class SidebarFixtureState: ObservableObject {
    @Published var lists = false
    @Published var calendars = false
    var openedSettings = 0
}

private struct SidebarFixture: View {
    @ObservedObject var state: SidebarFixtureState
    var body: some View {
        WorkspaceSidebarView(showTaskLists: $state.lists, showCalendars: $state.calendars,
                             openSettings: { state.openedSettings += 1 })
    }
}

@main
struct SidebarNativeTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var assertions = 0
        func expect(_ condition: Bool, _ message: String) {
            guard condition else { fatalError("FAIL sidebar: \(message)") }
            assertions += 1
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let model = WorkspaceViewModel(mode: .demo)
        model.snapshot.calendars = [
            CalendarInfo(id: "personal", title: "Личный календарь", accessRole: "owner", colorHex: "#4285F4"),
            CalendarInfo(id: "work", title: "Рабочие встречи", accessRole: "writer", colorHex: "#EA4335"),
            CalendarInfo(id: "holidays", title: "Праздники России и очень длинное название подписки", accessRole: "reader", colorHex: "#FBBC04"),
            CalendarInfo(id: "football", title: "Футбол", accessRole: "reader", colorHex: "#34A853")
        ]
        model.snapshot.taskLists = ["Backlog", "Рабочие задачи с очень длинным названием", "dev", "Выходные"].enumerated().map {
            TaskList(id: "board-\($0.offset)", title: $0.element, updated: nil)
        }
        model.selectedCalendarID = "personal"
        model.visibleCalendarIDs = ["personal", "work"]
        let state = SidebarFixtureState()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 245, height: 560),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SidebarFixture(state: state).environmentObject(model))
        window.contentView = host
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            host.layoutSubtreeIfNeeded()
        }
        func probe(_ name: String) -> NSView {
            guard let view = descendants(host).first(where: { $0.identifier?.rawValue == "sidebar-probe-" + name }) else {
                fatalError("Missing sidebar probe \(name)")
            }
            return view
        }
        func bounds(_ name: String) -> NSRect {
            let view = probe(name)
            return view.convert(view.bounds, to: host)
        }
        func activate(_ name: String) {
            // Offscreen windows do not receive real pointer activation. Exercise the
            // very same closure supplied to Button (or Toggle binding), without
            // bringing a window front or fabricating native-event coverage.
            let view = probe(name) as! SidebarProbeView
            view.action!()
            settle()
        }
        let evidence = URL(fileURLWithPath: ProcessInfo.processInfo.environment["G_CALENDAR_SIDEBAR_EVIDENCE_DIR"] ?? ".build/g-calendar/sidebar-evidence", isDirectory: true)
        try! FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        for appearance in ["light", "dark"] {
            window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            for width in [205.0, 245.0, 310.0] {
                window.setContentSize(NSSize(width: width, height: 560))
                for section in WorkspaceViewModel.Section.allCases {
                    model.section = section
                    settle()
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: evidence.appendingPathComponent("\(section == .calendar ? "calendar" : "tasks")-\(Int(width))-\(appearance).png"))
                    expect(!window.isVisible, "fixture remains offscreen")
                    for name in ["section-calendar", "section-tasks", "manage", "account"] {
                        let rect = bounds(name)
                        expect(rect.minX >= 0 && rect.maxX <= width && rect.minY >= 0 && rect.maxY <= 560, "\(name) fits at \(width) \(appearance)")
                        expect(rect.height >= 28, "full action target remains usable")
                    }
                    let rowNames = section == .calendar ? ["calendar-personal", "visible-personal", "calendar-holidays", "visible-holidays"] : ["task-all", "task-board-1"]
                    for name in rowNames {
                        let rect = bounds(name)
                        expect(rect.width > 0 && rect.minX >= 8 && rect.maxX <= width - 8, "\(name) fits long names and trailing controls")
                    }
                    if section == .calendar {
                        expect(bounds("calendar-holidays").maxX <= bounds("visible-holidays").minX, "selection never overlaps visibility target")
                        expect(abs(bounds("calendar-personal").height - 36) < 1, "compact 36pt source rows")
                    } else {
                        let visibleCheckboxes = descendants(host).filter {
                            guard $0.identifier?.rawValue.hasPrefix("sidebar-probe-visible-") == true,
                                  !$0.isHiddenOrHasHiddenAncestor, !$0.visibleRect.isEmpty else { return false }
                            return host.visibleRect.intersects($0.convert($0.visibleRect, to: host))
                        }
                        expect(visibleCheckboxes.isEmpty, "tasks have no visible calendar visibility checkboxes")
                    }
                }
            }
        }
        window.setContentSize(NSSize(width: 245, height: 560))
        model.section = .calendar
        settle()
        activate("calendar-work")
        expect(model.selectedCalendarID == "work", "calendar action changes context")
        expect(model.visibleCalendarIDs == ["personal", "work"], "selection does not change visibility")
        activate("visible-personal")
        expect(!model.isCalendarVisible("personal"), "checkbox binding hides only intended calendar")
        expect(model.selectedCalendarID == "work", "visibility does not change creation context")
        activate("manage")
        expect(state.calendars, "calendar plus opens creator")
        activate("section-tasks")
        expect(model.section == .tasks, "navigation action selects tasks")
        activate("task-board-1")
        expect(model.selectedTaskListID == "board-1", "board action selects its list")
        activate("task-all")
        expect(model.selectedTaskListID == nil, "all boards restores nil scope")
        activate("manage")
        expect(state.lists, "tasks plus opens list management")
        activate("account")
        expect(state.openedSettings == 1, "account footer opens settings once")

        for (syncState, title) in [
            (WorkspaceSyncState.updated, "Синхронизировано"), (.syncing, "Синхронизация…"),
            (.stale, "Сохранённые данные"), (.offline, "Нет подключения"),
            (.failed, "Ошибка синхронизации"), (.setupRequired, "Нужна настройка"),
            (.idle, "Ожидание синхронизации")
        ] {
            model.syncState = syncState
            settle()
            expect(!probe("status-" + title).visibleRect.isEmpty, "footer renders true status: \(title)")
        }
        model.syncState = .updated
        model.mutationInFlight = true
        settle()
        expect(!probe("status-Сохранение…").visibleRect.isEmpty, "saving takes precedence over synchronized status")
        model.mutationInFlight = false

        // The account and navigation must stay fixed while many sources scroll.
        model.snapshot.taskLists += (4..<100).map { TaskList(id: "board-\($0)", title: "Список \($0)", updated: nil) }
        settle()
        let account = bounds("account")
        let navigation = bounds("section-calendar")
        let scroll = probe("task-all").enclosingScrollView!
        expect(scroll.documentView!.bounds.height > scroll.contentView.bounds.height, "long source list has a real native scroll document")
        // LazyVStack refines its estimated document height as distant rows appear.
        // Continue to the current native end until the actual last row is visible.
        for _ in 0..<8 {
            let end = scroll.contentView.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: scroll.documentView!.bounds.height), size: scroll.contentView.bounds.size))
            scroll.contentView.scroll(to: end.origin)
            scroll.reflectScrolledClipView(scroll.contentView)
            settle()
            if let last = descendants(host).first(where: { $0.identifier?.rawValue == "sidebar-probe-task-board-99" }),
               !last.visibleRect.isEmpty { break }
        }
        expect(bounds("account") == account && bounds("section-calendar") == navigation, "scroll keeps account and navigation pinned")
        let last = probe("task-board-99")
        expect(!last.visibleRect.isEmpty, "last board is reachable after scrolling")
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: evidence.appendingPathComponent("tasks-long-list.png"))
        window.close()

        // Render the production avatar view with a synthetic image and its fallback.
        let photo = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        photo.setFillColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1)
        photo.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = NSImage(cgImage: photo.makeImage()!, size: NSSize(width: 64, height: 64))
        for dark in [false, true] {
            for hasPhoto in [false, true] {
                let avatarWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 48, height: 48),
                                            styleMask: [.borderless], backing: .buffered, defer: false)
                avatarWindow.isReleasedWhenClosed = false
                avatarWindow.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let avatarHost = NSHostingView(rootView: GoogleAccountAvatar(avatar: hasPhoto ? image : nil)
                    .padding(8).background(AppTheme.canvas))
                avatarWindow.contentView = avatarHost
                avatarHost.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                let pixels = avatarHost.bitmapImageRepForCachingDisplay(in: avatarHost.bounds)!
                avatarHost.cacheDisplay(in: avatarHost.bounds, to: pixels)
                try! pixels.representation(using: .png, properties: [:])!.write(to: evidence.appendingPathComponent("avatar-\(hasPhoto ? "photo" : "fallback")-\(dark ? "dark" : "light").png"))
                let scale = CGFloat(pixels.pixelsWide) / 48
                let center = pixels.colorAt(x: Int(24 * scale), y: Int(24 * scale))!.usingColorSpace(.sRGB)!
                let corner = pixels.colorAt(x: Int(8 * scale), y: Int(8 * scale))!.usingColorSpace(.sRGB)!
                let outside = pixels.colorAt(x: Int(2 * scale), y: Int(2 * scale))!.usingColorSpace(.sRGB)!
                expect(!avatarWindow.isVisible, "avatar fixture remains offscreen")
                expect(avatarHost.bounds.size == NSSize(width: 48, height: 48), "photo and fallback retain the same 32pt footprint")
                expect(abs(corner.redComponent - outside.redComponent) < 0.03 && abs(corner.blueComponent - outside.blueComponent) < 0.03,
                       "avatar is clipped to a circle in both appearances")
                if hasPhoto { expect(center.blueComponent > center.redComponent + 0.5, "actual photo pixels reach the avatar view") }
                avatarWindow.close()
            }
        }
        print("SIDEBAR_UI_ASSERTIONS=\(assertions)")
        print("SIDEBAR_EVIDENCE=\(evidence.path)")
    }
}
