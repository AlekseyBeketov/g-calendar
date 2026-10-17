import SwiftUI

struct CalendarCreatorView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var local = ViewLocalState()
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionGap) {
            Text("Новый календарь").font(.title2.weight(.semibold))
            Text("Создайте дополнительный календарь в своём аккаунте Google.")
                .foregroundStyle(AppTheme.textSecondary)
            if !model.canCreateCalendars {
                Text("Для создания календарей нужен дополнительный доступ Google. Войдите повторно, затем откройте эту форму снова.")
                    .foregroundStyle(AppTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Button("Предоставить доступ Google") { model.signInToGoogle() }
                    .pointingHandCursor()
                    .disabled(model.mutationsBlocked || !model.googleTransportSettings.canStartSignIn)
                if let error = model.googleTransportSettings.signInError {
                    Text(error).foregroundStyle(AppTheme.overdue)
                }
            }
            EditorField(title: "Название календаря") {
                TextField("Например, Личные планы", text: $local.title)
                    .textFieldStyle(.roundedBorder).focused($titleFocused)
            }.disabled(model.mutationsBlocked)
            Text("Часовой пояс: \(TimeZone.current.identifier)").font(.caption).foregroundStyle(AppTheme.textSecondary)
            if let error = local.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.overdue).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.pointingHandCursor().keyboardShortcut(.cancelAction)
                MutationSaveControl(pendingMutationID: local.pendingMutationID,
                    disabled: !model.canCreateCalendars || local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    save: save, verified: { dismiss() })
            }
        }
        .padding(AppTheme.editorInset).frame(width: 480)
        .fixedSize(horizontal: false, vertical: true).defaultFocus($titleFocused, true)
    }

    private func save() {
        guard model.canCreateCalendars else { return }
        do {
            let invocation = try model.commandFactory().calendarInsert(title: local.title,
                timeZoneID: TimeZone.current.identifier, authorization: .userSave)
            model.performMutation(invocation, onSuccess: { dismiss() }, onFailure: {
                local.errorMessage = $0
                local.pendingMutationID = model.pendingMutation?.id
            })
        } catch { local.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Календарь не создан." }
    }
}
