import SwiftUI

@MainActor
struct AuthorSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: AuthorSupportState
    private let assets: AuthorSupportAssets
    private let actions: AuthorSupportActions

    init(provider: AuthorSupportProvider = .cloudTips,
         assets: AuthorSupportAssets? = nil, actions: AuthorSupportActions? = nil) {
        _state = StateObject(wrappedValue: AuthorSupportState(provider: provider))
        self.assets = assets ?? .bundled
        self.actions = actions ?? .live
    }

    var body: some View {
        VStack(spacing: AppTheme.sectionGap) {
            VStack(spacing: AppTheme.fieldGap) {
                Text("Поддержать автора")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Спасибо, что помогаете развивать g-calendar.")
                    .font(.callout).foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Способ поддержки", selection: Binding(
                get: { state.provider }, set: { state.select($0) }
            )) {
                ForEach(AuthorSupportProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .pointingHandCursor()

            VStack(spacing: AppTheme.sectionGap) {
                if let qr = assets.qr(for: state.provider) {
                    Image(nsImage: qr).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 208, height: 208)
                        .accessibilityLabel("QR-код для поддержки через \(state.provider.title)")
                        .accessibilityHint("Эту же страницу можно открыть кнопкой ниже.")
                } else {
                    Text("QR-код недоступен. Откройте страницу по ссылке ниже.")
                        .font(.callout).foregroundStyle(Color(red: 0.31, green: 0.35, blue: 0.4))
                        .multilineTextAlignment(.center)
                        .frame(width: 208, height: 208)
                }
                providerBrand
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.sectionGap)
            // QR contrast and the original brand colors must survive Dark appearance.
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppTheme.outline.opacity(0.25))
                .allowsHitTesting(false).accessibilityHidden(true))

            Text("Наведите камеру телефона на QR-код")
                .font(.caption).foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: AppTheme.fieldGap) {
                Button {
                    state.open(using: actions)
                } label: {
                    Label("Открыть \(state.provider.title)", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.large)
                .pointingHandCursor()
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Открывает страницу поддержки в браузере.")

                Button {
                    state.copy(using: actions)
                } label: {
                    Text(state.copied ? "Ссылка скопирована" : "Скопировать ссылку")
                        .padding(4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .pointingHandCursor()
                .accessibilityAddTraits(.updatesFrequently)
            }

            if let message = state.errorMessage {
                Text(message).font(.caption).foregroundStyle(AppTheme.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            HStack {
                Spacer()
                Button("Закрыть") { dismiss() }
                    .pointingHandCursor().keyboardShortcut(.cancelAction)
            }
        }
        .padding(AppTheme.editorInset)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(AppTheme.surface)
    }

    private var providerBrand: some View {
        HStack(spacing: 10) {
            if let logo = assets.logo(for: state.provider) {
                Image(nsImage: logo).resizable().scaledToFit()
                    .frame(width: state.provider == .cloudTips ? 160 : 30, height: 36)
            }
            if state.provider == .boosty || assets.logo(for: state.provider) == nil {
                Text(state.provider.title).font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.13, blue: 0.14))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.provider.title)
    }
}
