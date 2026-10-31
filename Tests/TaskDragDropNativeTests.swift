import AppKit
import Foundation

@main
struct TaskDragDropNativeTests {
    @MainActor private static var assertions = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL task-drag-drop: \(message)") }
        assertions += 1
    }

    @MainActor private static func drainMainRunLoop(for duration: TimeInterval = 0.15) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        let task = GoogleTask(id: "drag-task", taskListID: "source", title: "Synthetic task",
                              notes: "Synthetic notes", due: DateOnly(rawValue: "2026-11-01"),
                              completed: false, deleted: false, updated: nil)
        let session = TaskDragSession(task: task)
        let matchingProvider = TaskBoardDropHandler.itemProvider(for: session)
        var activeSession: TaskDragSession? = session
        var movedTasks: [GoogleTask] = []

        expect(!TaskBoardDropHandler.acceptTaskDrop(providers: [matchingProvider], session: nil,
                                                    activeSession: { activeSession }, resolveCurrentTask: { $0 },
                                                    onMove: { movedTasks.append($0) }),
               "drop without a live drag session is rejected")
        expect(!TaskBoardDropHandler.acceptTaskDrop(providers: [], session: session,
                                                    activeSession: { activeSession }, resolveCurrentTask: { $0 },
                                                    onMove: { movedTasks.append($0) }),
               "drop without a provider is rejected")
        expect(!TaskBoardDropHandler.acceptTaskDrop(providers: [matchingProvider], session: session,
                                                    activeSession: { activeSession }, resolveCurrentTask: { _ in nil },
                                                    onMove: { movedTasks.append($0) }),
               "drop for a removed source task is rejected")

        let accepted = TaskBoardDropHandler.acceptTaskDrop(providers: [matchingProvider], session: session,
                                                           activeSession: { activeSession },
                                                           resolveCurrentTask: { $0.id == task.id ? task : nil },
                                                           onMove: { movedTasks.append($0) })
        expect(accepted, "matching task provider is accepted")
        let delivered = Date().addingTimeInterval(1)
        while movedTasks.isEmpty && Date() < delivered { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        expect(movedTasks == [task], "accepted payload delivers exactly one current task")

        let staleSession = TaskDragSession(task: task)
        let staleProvider = TaskBoardDropHandler.itemProvider(for: staleSession)
        activeSession = session
        var staleMoveCount = 0
        expect(TaskBoardDropHandler.acceptTaskDrop(providers: [matchingProvider], session: session,
                                                   activeSession: { activeSession }, resolveCurrentTask: { $0 },
                                                   onMove: { _ in staleMoveCount += 1 }),
               "provider load can finish after the session changes")
        activeSession = staleSession
        drainMainRunLoop()
        expect(staleMoveCount == 0, "stale drag session cannot move a task")

        activeSession = session
        let wrongProvider = staleProvider
        var wrongMoveCount = 0
        expect(TaskBoardDropHandler.acceptTaskDrop(providers: [wrongProvider], session: session,
                                                   activeSession: { activeSession }, resolveCurrentTask: { $0 },
                                                   onMove: { _ in wrongMoveCount += 1 }),
               "task payload is loaded before move dispatch")
        drainMainRunLoop()
        expect(wrongMoveCount == 0, "payload from a different drag session is ignored")

        let model = WorkspaceViewModel(mode: .demo)
        let original = model.snapshot.tasks.first { $0.id == "demo-task-alternate" }!
        let sourceID = original.taskListID
        let destinationID = "demo-task-list"
        model.moveTaskToBoard(original, destinationTaskListID: sourceID)
        expect(model.snapshot.tasks.first { $0.selectionIdentity == original.selectionIdentity } == original,
               "same-board drop is a no-op")
        model.setTaskSortMode(.date, for: destinationID)
        model.moveTaskToBoard(original, destinationTaskListID: destinationID)
        let moved = model.snapshot.tasks.first { $0.id == original.id }
        expect(moved?.taskListID == destinationID && moved?.title == original.title && moved?.notes == original.notes
               && moved?.due == original.due && moved?.completed == original.completed,
               "cross-board move succeeds when destination sorting is by date")
        model.mutationInFlight = true
        if let moved { model.moveTaskToBoard(moved, destinationTaskListID: sourceID) }
        expect(model.snapshot.tasks.first { $0.id == original.id }?.taskListID == destinationID,
               "blocked mutation state does not change the demo snapshot")
        expect(model.snapshot.tasks.filter { $0.id == original.id }.count == 1
               && !model.snapshot.tasks.contains { $0.selectionIdentity == original.selectionIdentity },
               "successful move removes source membership and does not duplicate the task")

        print("TASK_DRAG_DROP_ASSERTIONS=\(assertions)")
    }
}
