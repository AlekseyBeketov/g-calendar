import SwiftUI

struct DiagnosticsSettingsSection: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @AppStorage(AppDiagnostics.preferenceKey) private var enabled = true
    @StateObject private var local = ViewLocalState()

    var body: some View {
        SettingsSection(title: "Диагностика и логи") {
            VStack(alignment: .leading, spacing: AppTheme.fieldGap) {
                Toggle("Сохранять логи на этом Mac", isOn: Binding(get: { enabled }, set: {
                    enabled = $0
                    AppDiagnostics.shared.setEnabled($0)
                })).pointingHandCursor().disabled(model.launchMode != .normal)
                Text("Логи не отправляются разработчику и не используются для аналитики. Их можно приложить при обращении с проблемой, чтобы точнее определить причину ошибки. Хранятся до 7 дней, занимают не более 4 МБ; названия событий, задач и данные входа не записываются.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Открыть папку логов") {
                        do {
                            try FileManager.default.createDirectory(at: AppDiagnostics.directory, withIntermediateDirectories: true,
                                                                   attributes: [.posixPermissions: 0o700])
                            if !NSWorkspace.shared.open(AppDiagnostics.directory) { local.localMessage = "Не удалось открыть папку логов." }
                        } catch { local.localMessage = "Не удалось открыть папку логов." }
                    }.pointingHandCursor().disabled(model.launchMode != .normal)
                    Button(local.isSaving ? "Очищаем…" : "Очистить логи") {
                        local.isSaving = true
                        AppDiagnostics.shared.clear { success in
                            DispatchQueue.main.async {
                                local.isSaving = false
                                local.localMessage = success ? "Логи очищены." : "Не удалось очистить логи. Попробуйте ещё раз."
                            }
                        }
                    }.pointingHandCursor().disabled(local.isSaving || model.launchMode != .normal)
                }
                if let message = local.localMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
