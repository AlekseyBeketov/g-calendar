import SwiftUI

struct GoogleOnboardingView: View {
    let isSigningIn: Bool
    let canSignIn: Bool
    let statusMessage: String?
    let errorMessage: String?
    let onSignIn: () -> Void
    let onCancel: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Text("Шаг 1 из 2")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Capsule()
                            .fill(AppTheme.outline.opacity(0.35))
                            .frame(width: 190, height: 7)
                            .overlay(alignment: .leading) {
                                Capsule().fill(AppTheme.accent).frame(width: 95, height: 7)
                            }
                            .accessibilityHidden(true)
                        Text("Войдите в Google")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 22)
                        Text("Чтобы показывать ваши события и задачи, g-calendar подключится к аккаунту Google.")
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 520)
                    }
                    .padding(.bottom, 28)

                    VStack(spacing: 12) {
                        permissionCard(
                            symbol: "calendar",
                            title: "Календари",
                            description: "Просмотр и управление событиями в приложении."
                        )
                        permissionCard(
                            symbol: "checklist",
                            title: "Задачи",
                            description: "Просмотр и изменение задач в одном месте."
                        )
                    }
                    .padding(.bottom, 24)

                    Button(action: onSignIn) {
                        HStack(spacing: 14) {
                            Image("GoogleSignInLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                            Text("Войти через Google")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color(hex: "#1F1F1F") ?? AppTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(hex: "#747775") ?? AppTheme.outline, lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .pointingHandCursor()
                    .buttonStyle(.plain)
                    .disabled(isSigningIn || !canSignIn)
                    .frame(maxWidth: 470)
                    .accessibilityIdentifier("google-onboarding-sign-in")
                    .help("Откроется защищённая страница Google в браузере")

                    if isSigningIn {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(statusMessage ?? "Ожидаем подтверждения в браузере…")
                                .font(.callout)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Отменить") { onCancel() }
                                .pointingHandCursor()
                        }
                        .padding(.top, 18)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("google-onboarding-progress")
                    } else if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(AppTheme.overdue)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 470, alignment: .leading)
                            .padding(.top, 16)
                            .accessibilityIdentifier("google-onboarding-error")
                    } else if let statusMessage {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 470)
                            .padding(.top, 16)
                    } else {
                        Text("После входа загрузим ваши календари и задачи.")
                            .font(.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.top, 16)
                    }

                    Text("Пароль вводится на стороне Google. Доступ можно отозвать в настройках аккаунта.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 470)
                        .padding(.top, 16)

                    Button("Настроить другой способ подключения", action: onOpenSettings)
                        .pointingHandCursor()
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(AppTheme.accent)
                        .padding(.top, 22)
                        .accessibilityIdentifier("google-onboarding-other-transport")
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.vertical, 36)
            }
            .scrollIndicators(.hidden)
        }
        .background(AppTheme.canvas)
        .accessibilityIdentifier("google-onboarding")
    }

    private func permissionCard(symbol: String, title: String, description: String) -> some View {
        HStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 58, height: 58)
                .background(AppTheme.selection, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.outline.opacity(0.3), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}
