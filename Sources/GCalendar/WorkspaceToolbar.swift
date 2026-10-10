import SwiftUI

/// Shared production composition, also hosted by synthetic native toolbar tests.
struct WorkspaceToolbar: ToolbarContent {
    let isCalendar: Bool
    @Binding var searchText: String
    let focusRequest: Int
    @Binding var searchFocused: Bool
    let isSyncing: Bool
    let mutationInFlight: Bool
    let moveDate: (Int) -> Void
    let goToToday: () -> Void
    let refresh: () -> Void
    let openSettings: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if isCalendar {
                Button { moveDate(-1) } label: { Image(systemName: "chevron.left") }.help("Назад").accessibilityLabel("Предыдущий период")
                Button { goToToday() } label: { Text("Сегодня") }
                Button { moveDate(1) } label: { Image(systemName: "chevron.right") }.help("Вперёд").accessibilityLabel("Следующий период")
            }
        }
        ToolbarItem(placement: .automatic) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.textSecondary)
                WorkspaceSearchField(text: $searchText,
                                     label: isCalendar ? "Поиск событий" : "Поиск задач",
                                     focusRequest: focusRequest,
                                     onFocusChange: { searchFocused = $0 })
                    .frame(width: 180)
                    .accessibilityLabel(isCalendar ? "Поиск событий" : "Поиск задач")
                    .accessibilityIdentifier("workspace-search-field")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Очистить поиск")
                        .help("Очистить поиск")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(searchFocused ? AppTheme.accent : AppTheme.outline.opacity(0.4), lineWidth: searchFocused ? 2 : 1)
                .allowsHitTesting(false).accessibilityHidden(true))
            // Tasks puts search at the capsule edge; keep its own outline inside it.
            .padding(.horizontal, isCalendar ? 0 : 8)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { refresh() } label: {
                if isSyncing { ProgressView().controlSize(.small) }
                else { Label("Синхронизировать", systemImage: "arrow.clockwise") }
            }
            .disabled(isSyncing || mutationInFlight)
            .help("Обновить Calendar и Tasks")
        }
        ToolbarItem(placement: .automatic) {
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Настройки")
                .help("Настройки")
        }
    }
}
