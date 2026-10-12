import Foundation

extension InvariantTests {
    private static func orderedTask(_ id: String, position: String? = nil, parent: String? = nil,
                                    title: String? = nil, due: String? = nil, completed: Bool = false,
                                    board: String = "synthetic-board") -> GoogleTask {
        GoogleTask(id: id, taskListID: board, title: title ?? id, notes: "Synthetic notes",
                   due: due.flatMap(DateOnly.init(rawValue:)), completed: completed, deleted: false,
                   updated: nil, position: position, parent: parent)
    }

    private static func taskObject(_ task: GoogleTask) -> [String: Any] {
        var object: [String: Any] = ["id": task.id, "title": task.title,
                                   "status": task.completed ? "completed" : "needsAction", "deleted": task.deleted]
        if let notes = task.notes { object["notes"] = notes }
        if let due = task.due { object["due"] = due.description + "T00:00:00.000Z" }
        if let position = task.position { object["position"] = position }
        if let parent = task.parent { object["parent"] = parent }
        return object
    }

    static func testTaskBoardOrder() throws {
        let boards = ["a", "b", "c"].map { TaskList(id: $0, title: $0, updated: nil) }
        var preferences = TaskWorkspacePreferences(sortModes: ["a": .date])
        try check(preferences.orderedBoards(boards) == boards, "initial board order follows the server without losing boards")
        try check(preferences.moveBoard("a", toward: "c", in: boards) && preferences.boardOrder == ["b", "c", "a"], "dragging toward last moves the source to the target index")
        try check(preferences.moveBoard("a", toward: "b", in: boards) && preferences.boardOrder == ["a", "b", "c"], "dragging toward first moves the source to the target index")
        let before = preferences
        try check(!preferences.moveBoard("foreign", toward: "a", in: boards) && preferences == before, "unknown drag identity cannot mutate saved order")
        try check(!preferences.moveBoard("a", toward: "a", in: boards) && preferences == before, "self drop is a no-op")
        preferences.boardOrder = ["c", "gone", "c", "a"]
        let newBoard = TaskList(id: "d", title: "d", updated: nil)
        let current = [boards[0], boards[2], newBoard]
        try check(preferences.orderedBoards(current).map(\.id) == ["c", "a", "d"], "deleted boards and duplicate saved IDs are omitted, new boards append")
        let suite = "board-order-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        preferences.save(to: defaults, key: "account-a")
        let restored = TaskWorkspacePreferences.load(from: defaults, key: "account-a")
        try check(restored.orderedBoards(current).map(\.id) == ["c", "a", "d"] && restored.sortMode(for: "a") == .date, "restart preserves ordering and board sorting together")
        try check(TaskWorkspacePreferences.load(from: defaults, key: "account-b").boardOrder.isEmpty, "board order stays isolated by workspace")
        let legacy = try JSONDecoder().decode(TaskWorkspacePreferences.self, from: Data("{\"sortModes\":{\"a\":\"date\"}}".utf8))
        try check(legacy.boardOrder.isEmpty && legacy.sortMode(for: "a") == .date, "old sorting preferences migrate without losing selections")
    }

    static func testTaskDateGroups() throws {
        let today = DateOnly(rawValue: "2026-10-12")!
        let tasks = [orderedTask("later", due: "2026-11-01"), orderedTask("old", due: "2026-10-11"),
                     orderedTask("today-b", due: "2026-10-12"), orderedTask("today-a", due: "2026-10-12"),
                     orderedTask("tomorrow", due: "2026-10-13"), orderedTask("undated"), orderedTask("done", due: "2026-10-11", completed: true)]
        let groups = TaskOrdering.dateGroups(tasks, today: today)
        try check(groups.map(\.id) == ["overdue", "date:2026-10-12", "date:2026-10-13", "date:2026-11-01", "undated", "completed"], "date groups are chronological, sparse and stable")
        try check(groups[0].isOverdue && groups[1].isToday && groups[1].title == "Сегодня" && groups[2].title == "Завтра", "date group semantics and relative labels")
        try check(groups[1].tasks.map(\.id) == ["today-a", "today-b"] && groups.last?.tasks.map(\.id) == ["done"], "same-date ties and completed isolation")
        try check(groups.flatMap(\.tasks).count == tasks.count && Set(groups.flatMap(\.tasks).map(\.id)).count == tasks.count, "date grouping retains each identity once")
        let shifted = TaskOrdering.dateGroups(tasks, today: today.adding(days: 1)!)
        try check(shifted.first?.tasks.count == 3 && shifted.first(where: { $0.id == "date:2026-10-13" })?.isToday == true, "day rollover updates overdue scope and today without changing date identity")
        try check(TaskOrdering.dateGroups([], today: today).isEmpty, "empty scopes create no empty date headers")
        let newYear = TaskOrdering.dateGroups([orderedTask("next-year", due: "2027-01-01")], today: DateOnly(rawValue: "2026-12-31")!)
        try check(newYear.first?.title == "Завтра", "tomorrow handles month and year rollover")
    }

    static func testTaskOrdering() throws {
        let old = Data("{\"id\":\"old\",\"taskListID\":\"board\",\"title\":\"Old cache\",\"completed\":false,\"deleted\":false}".utf8)
        let legacy = try JSONDecoder().decode(GoogleTask.self, from: old)
        try check(legacy.position == nil && legacy.parent == nil, "old cache must decode without new fields")
        let child = orderedTask("child", position: "100", parent: "parent")
        let parent = orderedTask("parent", position: "200")
        let first = orderedTask("first", position: "100")
        let complete = orderedTask("complete", position: "000", completed: true)
        let otherBoard = orderedTask("other", position: "000", parent: "parent", board: "another-board")
        try check(TaskOrdering.sorted([child, parent, complete, first], mode: .manual).map(\.id) == ["first", "parent", "child", "complete"],
                  "manual order must use sibling positions, preserve tree and put completed last")
        try check(TaskOrdering.sorted([parent, first, orderedTask("legacy")], mode: .manual).map(\.id) == ["parent", "first", "legacy"],
                  "partially legacy sibling positions must preserve deterministic cache order")
        try check(TaskOrdering.siblings(child, in: [child, parent, otherBoard]).map(\.id) == ["child"], "siblings must respect exact board and parent")
        try check(TaskOrdering.previousForMove(parent, before: first, in: [parent, first]) == nil, "moving to sibling head omits previous")
        let last = orderedTask("last", position: "300")
        try check(TaskOrdering.previousForMove(first, before: last, in: [first, parent, last])?.id == parent.id,
                  "predecessor must come from full sibling order with moved task removed")
        let cycle = [orderedTask("a", position: "1", parent: "b"), orderedTask("b", position: "2", parent: "a")]
        try check(TaskOrdering.sorted(cycle, mode: .manual).count == 2, "cyclic cache trees must terminate without hiding tasks")
        let largeTree = (0..<4000).map { index in
            orderedTask("large-\(index)", position: String(format: "%020d", index), parent: index == 0 ? nil : "large-\(index - 1)")
        }
        try check(TaskOrdering.sorted(Array(largeTree.reversed()), mode: .manual).map(\.id) == largeTree.map(\.id),
                  "deep large trees must traverse iteratively with parent-first order")
        let dated = [orderedTask("none"), orderedTask("later", due: "2026-10-13"), orderedTask("earlier", due: "2026-10-12"),
                     orderedTask("done", due: "2026-01-01", completed: true)]
        try check(TaskOrdering.sorted(dated, mode: .date).map(\.id) == ["earlier", "later", "none", "done"], "date order must be ascending, nil last, completed last")
        let names = [orderedTask("b", title: "Task 10"), orderedTask("a", title: "Task 2"), orderedTask("c", title: "Task 2")]
        try check(TaskOrdering.sorted(names, mode: .title).map(\.id) == ["a", "c", "b"], "title uses natural sorting and ID tie-break")
        let decoded = try GoogleTask.decode(taskObject(child), taskListID: child.taskListID)
        try check(decoded.position == child.position && decoded.parent == child.parent, "Google task decoder must retain ordering metadata")
        let suite = "task-ordering-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = TaskWorkspacePreferences()
        preferences.setSortMode(.title, for: "synthetic-board")
        preferences.save(to: defaults, key: "account-a")
        try check(TaskWorkspacePreferences.load(from: defaults, key: "account-a") == preferences,
                  "board sort preferences must round-trip")
        try check(TaskWorkspacePreferences.load(from: defaults, key: "account-b").sortMode(for: "synthetic-board") == .manual,
                  "scoped preference keys must remain isolated")
        let empty = try JSONDecoder().decode(TaskWorkspacePreferences.self, from: Data("{}".utf8))
        try check(empty.sortModes.isEmpty && TaskSortMode.allCases.map(\.title) == ["Свой порядок", "Дата", "Название"], "preferences migrate absent modes and expose Russian labels")
    }

    static func testTaskReorder() throws {
        let factory = GWSCommandFactory(executableURL: executable)
        let first = orderedTask("first", position: "100")
        let moving = orderedTask("moving", position: "200")
        let last = orderedTask("last", position: "300")
        let head = try factory.taskReorder(task: moving, previous: nil, authorization: .userSave)
        try check(head.operation == .taskReorder && Array(head.arguments.prefix(3)) == ["tasks", "tasks", "move"] && head.expectedTask == moving,
                  "reorder must have unique recovery operation and native move command")
        try check(Set(params(head).keys) == ["task", "tasklist"] && !head.arguments.contains("--json"), "head move omits parent/previous/destination/body")
        let after = try factory.taskReorder(task: moving, previous: first, authorization: .userSave)
        try check(params(after)["previous"] as? String == first.id, "after move must include exact predecessor")
        let child = orderedTask("child", position: "100", parent: "parent")
        let childHead = try factory.taskReorder(task: child, previous: nil, authorization: .userSave)
        try check(params(childHead)["parent"] as? String == "parent", "child move must retain parent")
        for previous in [moving, child, orderedTask("foreign", board: "another-board"), orderedTask("completed", completed: true)] {
            try expectForbidden({ _ = try factory.taskReorder(task: moving, previous: previous, authorization: .userSave) }, "invalid reorder predecessor")
        }
        try expectForbidden({ _ = try factory.taskReorder(task: moving, previous: nil, authorization: .cancelled) }, "cancelled reorder")
        let rest = try GWSCommandFactory.googleREST().taskReorder(task: child, previous: nil, authorization: .userSave)
        let request = try GoogleRESTRequestBuilder().build(rest)
        try check(request.httpMethod == "POST" && request.httpBody == nil && request.url?.path == "/tasks/v1/lists/synthetic-board/tasks/child/move",
                  "REST reorder uses tasks.move with no body")
        try check(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "parent", value: "parent")) == true,
                  "REST query preserves parent")
        var bad = rest
        bad = ProcessInvocation(executableURL: bad.executableURL, arguments: ["tasks", "tasks", "move", "--params", "{\"tasklist\":\"board\",\"task\":\"child\",\"destinationTasklist\":\"foreign\"}"],
                                operation: .taskReorder, timeout: 20, outputLimit: 4096)
        try expectForbidden({ _ = try GoogleRESTRequestBuilder().build(bad) }, "reorder REST must reject cross-board query")
        try check(WorkspaceRefreshScope.afterVerifiedMutation(.taskReorder) == .tasks && PendingMutation(invocation: head).resourceID == moving.id,
                  "reorder must have known recovery identity and task refresh scope")

        for scenario in ["head", "after", "wrong-order", "changed-parent", "changed-title", "completed", "deleted", "missing-position", "page-failure"] {
            let invocation = scenario == "after" ? after : head
            var actual = moving
            actual.position = scenario == "after" ? "150" : (scenario == "wrong-order" ? "200" : "050")
            if scenario == "changed-parent" { actual.parent = "foreign-parent" }
            if scenario == "changed-title" { actual.title = "Changed" }
            if scenario == "completed" { actual.completed = true }
            if scenario == "deleted" { actual.deleted = true }
            if scenario == "missing-position" { actual.position = nil }
            let actualTask = actual
            let runner = FakeProcessRunner { call in
                guard call.operation == .tasksList else { throw GWSFailure.forbiddenOperation }
                if Self.params(call)["pageToken"] == nil {
                    return response(try JSONSerialization.data(withJSONObject: ["items": [taskObject(actualTask)], "nextPageToken": "page-two"]))
                }
                if scenario == "page-failure" { throw GWSFailure.timedOut("synthetic-page") }
                return response(try JSONSerialization.data(withJSONObject: ["items": [taskObject(first), taskObject(last)]]))
            }
            do {
                let result = try GWSMutationService(runner: runner).verifyAccepted(invocation, response: Data(), reader: GWSReadClient(factory: factory, runner: runner))
                try check(["head", "after"].contains(scenario) && result.isReadBackVerified, "only complete desired ordering may verify")
            } catch {
                try check(!["head", "after"].contains(scenario), "matching reorder must verify")
            }
            try check(runner.invocations.filter { $0.operation == .tasksList }.count == 2, "readback must collect all sibling pages")
        }
        var ready = false
        let recoveryRunner = FakeProcessRunner { call in
            if call.operation == .taskReorder { return response(Data()) }
            if call.operation == .taskGet { return response(try JSONSerialization.data(withJSONObject: taskObject(moving))) }
            guard call.operation == .tasksList else { throw GWSFailure.forbiddenOperation }
            var task = moving
            task.position = ready ? "050" : "200"
            return response(try JSONSerialization.data(withJSONObject: ["items": [taskObject(first), taskObject(task), taskObject(last)]]))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("task-reorder-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = MutationJournal(fileURL: directory.appendingPathComponent("pending.json"))
        let reader = GWSReadClient(factory: factory, runner: recoveryRunner)
        do {
            _ = try RecoverableMutationService(runner: recoveryRunner, journal: journal).perform(head, reader: reader)
            throw TestFailure(description: "wrong adjacency must leave pending reorder")
        } catch GWSFailure.mutationNotVerified {}
        try check(journal.pending?.operation == .taskReorder && journal.pending?.resourceID == moving.id, "uncertain reorder retains exact ID without response")
        ready = true
        let resumed = MutationJournal(fileURL: directory.appendingPathComponent("pending.json"))
        let result = try RecoverableMutationService(runner: recoveryRunner, journal: resumed).recheck(reader: reader)
        try check(result.isReadBackVerified && !resumed.isBlocked && recoveryRunner.invocations.filter { $0.operation == .taskReorder }.count == 1,
                  "restart recovery only re-reads and never resubmits move")
        for changedResource in ["task-parent", "previous-parent", "previous-completed", "missing-task"] {
            let runner = FakeProcessRunner { call in
                guard call.operation == .taskGet else { throw GWSFailure.forbiddenOperation }
                let id = Self.params(call)["task"] as? String
                if id == moving.id && changedResource == "missing-task" { return response(Data(), code: 404, stderr: "404 not found") }
                var actual = id == moving.id ? moving : first
                if (id == moving.id && changedResource == "task-parent") || (id == first.id && changedResource == "previous-parent") {
                    actual.parent = "another-parent"
                }
                if id == first.id && changedResource == "previous-completed" { actual.completed = true }
                return response(try JSONSerialization.data(withJSONObject: taskObject(actual)))
            }
            let journal = MutationJournal(fileURL: nil)
            do {
                _ = try RecoverableMutationService(runner: runner, journal: journal).perform(after, reader: GWSReadClient(factory: factory, runner: runner))
                throw TestFailure(description: "remote parent/status changes must block reordering before write")
            } catch GWSFailure.mutationNotVerified {}
            try check(!journal.isBlocked && runner.invocations.allSatisfy { $0.operation == .taskGet },
                      "reorder preflight failure must not journal or submit a write")
        }
    }

    static func testCompletedTaskDelete() throws {
        let factory = GWSCommandFactory(executableURL: executable)
        let completed = orderedTask("completed", parent: "parent", completed: true)
        let invocation = try factory.completedTaskDelete(task: completed, authorization: .confirmedDelete)
        try check(invocation.expectedTask == completed && !invocation.arguments.contains("--json"), "completed delete snapshot stays local")
        try check(try factory.taskDelete(task: completed, authorization: .confirmedDelete).expectedTask == nil, "normal delete must retain existing behavior")
        try expectForbidden({ _ = try factory.completedTaskDelete(task: orderedTask("active"), authorization: .confirmedDelete) }, "active task is not a completed-delete candidate")
        for scenario in ["reopened", "missing", "changed-parent", "success", "delete-unverified"] {
            var writes = 0
            let runner = FakeProcessRunner { call in
                if call.operation == .taskDelete { writes += 1; return response(Data()) }
                guard call.operation == .taskGet else { throw GWSFailure.forbiddenOperation }
                if scenario == "missing" || (writes > 0 && scenario != "delete-unverified") {
                    return response(Data(), code: 404, stderr: "404 not found")
                }
                var current = completed
                if scenario == "reopened" { current.completed = false }
                if scenario == "changed-parent" { current.parent = "another-parent" }
                return response(try JSONSerialization.data(withJSONObject: taskObject(current)))
            }
            let journal = MutationJournal(fileURL: nil)
            let reader = GWSReadClient(factory: factory, runner: runner)
            do {
                let result = try RecoverableMutationService(runner: runner, journal: journal).perform(invocation, reader: reader)
                try check(scenario == "success" && result == .resourceDeleted && !journal.isBlocked, "completed delete must confirm exact absence")
            } catch GWSFailure.mutationNotVerified {
                try check(scenario != "success", "completed delete successful readback must verify")
            }
            let preflightFailed = ["reopened", "missing", "changed-parent"].contains(scenario)
            try check(writes == (preflightFailed ? 0 : 1), "failed completed preflight must never write")
            try check(journal.isBlocked == (scenario == "delete-unverified"), "preflight failure must not create journal; uncertain sent delete must retain it")
            try check(runner.invocations.first?.operation == .taskGet && params(runner.invocations.first!)["task"] as? String == completed.id,
                      "preflight must exact-read intended task before write")
        }
    }

    static func testDemoTaskOrdering() throws {
        let adapter = DemoWorkspaceAdapter()
        let snapshot = adapter.snapshot()
        let tasks = snapshot.tasks.filter { !$0.completed && !$0.deleted && $0.taskListID == snapshot.taskLists.first?.id }
        let task = tasks.last!
        let factory = GWSCommandFactory(executableURL: executable)
        try adapter.perform(factory.taskReorder(task: task, previous: nil, authorization: .userSave))
        try check(TaskOrdering.sorted(adapter.snapshot().tasks.filter { $0.taskListID == task.taskListID }, mode: .manual).first?.id == task.id,
                  "demo reorder must update positions and displayed manual ordering")
        try adapter.perform(factory.taskPatch(task: task, title: task.title, notes: task.notes, due: task.due, completed: true, authorization: .userCompletionToggle))
        let completed = adapter.snapshot().tasks.first { $0.id == task.id }!
        let deletion = try factory.completedTaskDelete(task: completed, authorization: .confirmedDelete)
        try adapter.perform(factory.taskPatch(task: completed, title: completed.title, notes: completed.notes, due: completed.due, completed: false, authorization: .userCompletionToggle))
        do {
            try adapter.perform(deletion)
            throw TestFailure(description: "demo reopened task must not be deleted")
        } catch GWSFailure.mutationNotVerified {}
        try check(adapter.snapshot().tasks.contains { $0.id == task.id }, "demo completed-delete preflight must preserve reopened task")
    }
}
