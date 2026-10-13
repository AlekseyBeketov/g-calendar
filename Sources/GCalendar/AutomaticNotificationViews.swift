import SwiftUI

struct AutomaticEventReminderSummary: View {
    let event: CalendarEvent?
    let calendar: CalendarInfo?

    private var explanation: String {
        guard let event else { return "После сохранения уведомления планируются автоматически по настройкам Google Calendar." }
        guard !event.isAllDay else { return "События на весь день не вызывают уведомлений." }
        guard let settings = event.reminders else { return "Настройки напоминаний ещё не загружены из Google. Они появятся после синхронизации." }
        let reminders = settings.useDefault ? calendar?.defaultReminders : settings.overrides
        guard let reminders else { return "Настройки календаря ещё не загружены из Google." }
        let minutes = Set(reminders.filter { $0.method == "popup" }.map(\.minutes)).sorted()
        guard !minutes.isEmpty else { return "В Google для этого события нет всплывающих напоминаний." }
        return minutes.map { $0 == 0 ? "В момент начала" : "За \($0) мин. до начала" }.joined(separator: "; ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Уведомления Google Calendar").font(.callout.weight(.medium))
            Text(explanation).font(.caption).foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
