import AppKit
import Foundation
import UniformTypeIdentifiers

enum TaskBoardDragDropTypes {
    // A task uses JSON data while a board uses plain text. Distinct registered
    // types let nested drop targets route the payload without guessing from view state.
    static let task = UTType.json
    static let board = UTType.plainText
}

struct TaskDragSession {
    let token = UUID()
    let task: GoogleTask

    var payload: String { "g-calendar-task:\(token.uuidString)" }
}

@MainActor
enum TaskBoardDropHandler {
    static func itemProvider(for session: TaskDragSession) -> NSItemProvider {
        let provider = NSItemProvider()
        let payload = Data("\"\(session.payload)\"".utf8)
        provider.registerDataRepresentation(forTypeIdentifier: TaskBoardDragDropTypes.task.identifier,
                                            visibility: .ownProcess) { completion in
            completion(payload, nil)
            return nil
        }
        return provider
    }

    static func boardItemProvider(for payload: String) -> NSItemProvider {
        NSItemProvider(object: payload as NSString)
    }

    /// Resolves the in-process payload asynchronously and revalidates its session and model state on the main actor.
    static func acceptTaskDrop(providers: [NSItemProvider], session: TaskDragSession?,
                               activeSession: @escaping () -> TaskDragSession?,
                               resolveCurrentTask: @escaping (GoogleTask) -> GoogleTask?,
                               onMove: @escaping (GoogleTask) -> Void) -> Bool {
        guard let session, resolveCurrentTask(session.task) != nil,
              let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(TaskBoardDragDropTypes.task.identifier) else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: TaskBoardDragDropTypes.task.identifier) { data, _ in
            guard let data, (try? JSONDecoder().decode(String.self, from: data)) == session.payload else { return }
            DispatchQueue.main.async {
                guard activeSession()?.token == session.token,
                      let currentTask = resolveCurrentTask(session.task) else { return }
                onMove(currentTask)
            }
        }
        return true
    }
}
