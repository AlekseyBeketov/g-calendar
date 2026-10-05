import SwiftUI

struct MutationRecoveryPanel: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @StateObject private var local = ViewLocalState()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath").foregroundStyle(AppTheme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Проверка изменения не завершена").font(.headline)
                Text(model.mutationRecoveryProblem ?? (model.pendingMutation?.resourceID == nil
                     ? "Запрос мог быть принят, но ID не получен. Сверьте результат в Google; повторная запись заблокирована."
                     : "Черновик сохранён на этом Mac. Повторная проверка прочитает точный объект и не отправит изменение ещё раз."))
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if model.pendingMutation != nil || model.mutationRecoveryProblem != nil {
                Button("Черновик") { local.showEditor = true }
                Button(model.mutationInFlight ? "Проверяем…" : "Проверить") { model.recheckPendingMutation() }
                    .disabled(model.pendingMutation?.resourceID == nil || model.mutationInFlight)
            }
        }
        .padding(16)
        .background(AppTheme.warning.opacity(0.09))
        .sheet(isPresented: $local.showEditor) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Неподтверждённое изменение").font(.title2.weight(.semibold))
                EditorBody {
                    VStack(alignment: .leading, spacing: 16) {
                if let record = model.pendingMutation {
                    if !record.draftTitle.isEmpty { Text(record.draftTitle).textSelection(.enabled) }
                    if !record.draftNotes.isEmpty { Text(record.draftNotes).textSelection(.enabled) }
                    Text("Запись не будет повторена. Если точная проверка недоступна, самостоятельно сверьте результат в Google перед снятием блокировки.")
                        .font(.callout).foregroundStyle(AppTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Журнал повреждён. Перед снятием блокировки самостоятельно проверьте последнее изменение в Google. Копия журнала будет сохранена на этом Mac.")
                        .font(.callout).foregroundStyle(AppTheme.warning).fixedSize(horizontal: false, vertical: true)
                }
                    Button("Результат сверён вручную…") { local.showingDeleteConfirmation = true }
                        .disabled(model.mutationInFlight)
                    }
                }
                HStack { Spacer(); Button("Закрыть") { local.showEditor = false }.keyboardShortcut(.cancelAction) }
            }
            .padding(AppTheme.editorInset)
            .frame(width: 460)
            .confirmationDialog("Снять блокировку после ручной сверки?", isPresented: $local.showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Я сверил результат в Google") { model.acknowledgeManuallyReconciledMutation(); local.showEditor = false }
                Button("Отмена", role: .cancel) { }
            } message: {
                Text("Это не автоматическое подтверждение. Убедитесь, что объект уже сохранён или запрос действительно не применён. Приложение не будет повторять прежнюю запись.")
            }
        }
    }
}
