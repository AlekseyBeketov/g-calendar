import Combine
import Foundation
import SwiftUI

@MainActor
final class ViewLocalState: ObservableObject {
    enum TaskListForm: Identifiable {
        case create
        case edit(TaskList)
        var id: String { switch self { case .create: return "create"; case .edit(let list): return list.id } }
    }

    @Published var showSettings = false
    @Published var searchFocused = false
    @Published var showTaskLists = false
    @Published var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @Published var showingEventEditor = false
    @Published var selectedEvent: CalendarEvent?
    @Published var showingNewTask = false
    @Published var showEditor = false
    @Published var showReminderEditor = false
    @Published var listForm: TaskListForm?
    @Published var title = ""
    @Published var notes = ""
    @Published var start = Date()
    @Published var end = Date().addingTimeInterval(3600)
    @Published var allDay = false
    @Published var timeZoneID = TimeZone.current.identifier
    @Published var dueEnabled = false
    @Published var dueDate = Date()
    @Published var showingDeleteConfirmation = false
    @Published var errorMessage: String?
    @Published var localMessage: String?
    @Published var enabled = false
    @Published var fireDate = Date().addingTimeInterval(3600)
    @Published var reminderStatus: String?
    @Published var pathStatus: String?
    @Published var isSaving = false
    @Published var pendingMutationID: UUID?
    @Published var contextID = ""
    @Published var isHovered = false
    @Published var collapsedGroups: Set<String> = ["Готово"]
    @Published var selectedTaskIdentity: TaskSelectionIdentity?
    @Published var previousVisibleTaskIdentities: [TaskSelectionIdentity] = []
    @Published var keyboardTaskEditor: GoogleTask?
    @Published var taskKeyboardFocused = false
    @Published var taskKeyboardFocusRequest = UUID()
    @Published var taskColumnsVisible = false
    @Published var calendarHorizontalOffset: CGFloat = 0

    init(title: String = "", notes: String = "", start: Date = Date(), end: Date = Date().addingTimeInterval(3600),
         allDay: Bool = false, timeZoneID: String = TimeZone.current.identifier, dueEnabled: Bool = false,
         dueDate: Date = Date(), enabled: Bool = false, fireDate: Date = Date().addingTimeInterval(3600), contextID: String = "") {
        self.title = title
        self.notes = notes
        self.start = start
        self.end = end
        self.allDay = allDay
        self.timeZoneID = timeZoneID
        self.dueEnabled = dueEnabled
        self.dueDate = dueDate
        self.enabled = enabled
        self.fireDate = fireDate
        self.contextID = contextID
    }
}
