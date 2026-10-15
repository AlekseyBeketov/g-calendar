import SwiftUI

struct StartupPreferencesView: View {
    @ObservedObject var updates: ApplicationUpdates
    @StateObject private var loginItems = LoginItemSettings()
    let onComplete: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Text("Шаг 2 из 2").font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.textSecondary)
                        Capsule().fill(AppTheme.accent).frame(width: 190, height: 7).accessibilityHidden(true)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 42)).foregroundStyle(AppTheme.success).padding(.top, 12)
                            .accessibilityHidden(true)
                        Text("Почти готово").font(.system(size: 30, weight: .semibold)).foregroundStyle(AppTheme.textPrimary)
                        Text("Настройте g-calendar под себя. Эти параметры всегда можно изменить в настройках.")
                            .foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 14) {
                        preferenceCard(symbol: "arrow.triangle.2.circlepath", title: "Автообновление",
                            description: "Находим новые версии на GitHub, скачиваем и устанавливаем при завершении приложения.") {
                            Toggle("Включить автообновление", isOn: Binding(
                                get: { updates.automaticUpdatesEnabled }, set: { updates.setAutomaticUpdates($0) }))
                                .labelsHidden().toggleStyle(.switch).pointingHandCursor()
                        }
                        preferenceCard(symbol: "power", title: "Запуск при входе",
                            description: "Календарь будет под рукой сразу после входа в macOS.") {
                            Toggle("Запускать при входе в систему", isOn: Binding(
                                get: { loginItems.isRegistered },
                                set: { enabled in Task { await loginItems.setEnabled(enabled) } }))
                                .labelsHidden().toggleStyle(.switch).pointingHandCursor()
                                .disabled(!loginItems.isAvailable || loginItems.isUpdating)
                        }
                    }
                    if let error = loginItems.errorMessage {
                        Text(error).font(.callout).foregroundStyle(AppTheme.overdue).fixedSize(horizontal: false, vertical: true)
                    } else if loginItems.status == .requiresApproval {
                        VStack(spacing: 8) {
                            Text(loginItems.statusMessage).font(.callout).foregroundStyle(AppTheme.textSecondary)
                            Button("Открыть настройки macOS") { loginItems.openSystemSettings() }.pointingHandCursor()
                        }
                    }
                    Button(action: onComplete) {
                        Text("Начать работу").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .pointingHandCursor().buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(loginItems.isUpdating)
                    .accessibilityIdentifier("onboarding-finish")
                    Text("Обновления проверяются по защищённому соединению. Установленные данные и настройки сохраняются.")
                        .font(.caption).foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 64))
                .padding(32)
            }
        }
        .background(AppTheme.canvas)
        .task { loginItems.refresh(isNormalMode: updates.isAvailable) }
        .accessibilityIdentifier("startup-preferences")
    }

    private func preferenceCard<Control: View>(symbol: String, title: String, description: String,
                                             @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(AppTheme.accent)
                .frame(width: 48, height: 48).background(AppTheme.selection, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(AppTheme.textPrimary)
                Text(description).font(.callout).foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control()
        }
        .padding(20)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.outline.opacity(0.35)).allowsHitTesting(false))
    }
}

struct ApplicationUpdateSettingsSection: View {
    @ObservedObject var updates: ApplicationUpdates
    let blocked: Bool

    var body: some View {
        SettingsSection(title: "Обновления приложения") {
            Text(updates.versionDescription).font(.callout).foregroundStyle(AppTheme.textSecondary)
            Toggle("Включить автообновление", isOn: Binding(
                get: { updates.automaticUpdatesEnabled }, set: { updates.setAutomaticUpdates($0) }))
                .pointingHandCursor().disabled(!updates.isAvailable)
            Text("Новые версии с GitHub скачиваются автоматически и устанавливаются при завершении приложения. Проверить обновление вручную можно в любой момент.")
                .font(.caption).foregroundStyle(AppTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Button("Проверить обновления…") { updates.checkForUpdates() }
                .pointingHandCursor().disabled(!updates.isAvailable || blocked || !updates.canCheckForUpdates)
            if let error = updates.errorMessage {
                Text(error).font(.caption).foregroundStyle(AppTheme.overdue).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { updates.refreshPreference() }
    }
}
