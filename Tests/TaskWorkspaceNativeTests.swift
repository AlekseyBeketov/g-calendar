import AppKit
import SwiftUI

// Compiled only by test-task-workspace-ui.sh. Production builds omit the probes.
struct TaskBoardFrameProbe: NSViewRepresentable {
    let identifier: String
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier("probe-" + identifier)
    }
}

@main
struct TaskWorkspaceNativeTests {
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor static func main() {
        _ = NSApplication.shared
        var assertions = 0
        func expect(_ condition: Bool, _ message: String) {
            guard condition else { print("FAIL task-workspace: \(message)"); exit(1) }
            assertions += 1
        }
        func settle(_ host: NSView) {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            host.layoutSubtreeIfNeeded()
        }
        let model = WorkspaceViewModel(mode: .demo)
        model.section = .tasks
        model.selectedTaskListID = nil
        model.snapshot.taskLists = (0..<8).map { TaskList(id: "board-\($0)", title: "Synthetic board \($0)", updated: nil) }
        model.snapshot.tasks = model.snapshot.taskLists.flatMap { list in
            (0..<5).map { GoogleTask(id: "\(list.id)-\($0)", taskListID: list.id,
                                   title: "Synthetic task with enough text to wrap", notes: nil, due: nil,
                                   completed: false, deleted: false, updated: nil) }
        }
        model.presentationDefaults.set(TaskWorkspacePresentation.columns.rawValue, forKey: "taskWorkspacePresentation")
        // Never ordered front; contains synthetic data and uses demo-only stores.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1900, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: RootView().environmentObject(model).defaultAppStorage(model.presentationDefaults))
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 1900, height: 800)
        settle(host)

        for mode in [TaskWorkspacePresentation.columns, .list, .columns] {
            model.presentationDefaults.set(mode.rawValue, forKey: "taskWorkspacePresentation")
            for width in [1900.0, 1600.0, 1350.0, 1100.0, 900.0, 1600.0] {
                window.setContentSize(NSSize(width: width, height: 800))
                settle(host)
                let views = descendants(host)
                let viewport = views.first { $0.identifier?.rawValue == "probe-workspace-viewport" }!
                let viewportFrame = viewport.convert(viewport.bounds, to: host)
                let first = views.first { $0.identifier?.rawValue == "probe-board-0" }
                let columns = TaskWorkspaceLayout.usesColumnBoard(presentation: mode, availableWidth: Double(viewportFrame.width))
                expect((first != nil) == columns, "mode and width select the intended column/list presentation")
                guard let first, let scroll = first.enclosingScrollView else { continue }
                let frame = scroll.convert(scroll.bounds, to: host)
                expect(frame.minX >= viewportFrame.minX && frame.maxX <= viewportFrame.maxX + 1,
                       "native horizontal viewport cannot extend under the sidebar")
                expect(abs(scroll.contentView.constrainBoundsRect(NSRect(origin: NSPoint(x: -10000, y: 0), size: scroll.contentView.bounds.size)).minX) < 1,
                       "leftmost scroll position is zero without compensating sidebar insets")
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
                settle(host)
                let firstFrame = first.convert(first.bounds, to: host)
                expect(firstFrame.minX >= viewportFrame.minX && firstFrame.maxX <= viewportFrame.maxX,
                       "entire first board remains reachable at the left edge")
                let end = scroll.contentView.constrainBoundsRect(NSRect(origin: NSPoint(x: 10000, y: 0), size: scroll.contentView.bounds.size))
                scroll.contentView.scroll(to: end.origin)
                scroll.reflectScrolledClipView(scroll.contentView)
                settle(host)
                let last = descendants(host).first { $0.identifier?.rawValue == "probe-board-7" }!
                let lastFrame = last.convert(last.bounds, to: host)
                expect(lastFrame.minX >= viewportFrame.minX && lastFrame.maxX <= viewportFrame.maxX,
                       "entire last board remains reachable at the right edge")
                print("PASS task-columns width=\(Int(width)) viewport=\(frame) first=\(firstFrame)")
            }
        }
        window.close()
        print("TASK_WORKSPACE_UI_ASSERTIONS=\(assertions)")
    }
}
