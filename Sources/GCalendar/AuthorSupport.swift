import AppKit
import Combine
import Foundation

enum AuthorSupportProvider: String, CaseIterable, Identifiable {
    case cloudTips = "cloudtips"
    case boosty

    var id: Self { self }
    var title: String { self == .cloudTips ? "CloudTips" : "Boosty" }
    var url: URL {
        switch self {
        case .cloudTips: return URL(string: "https://pay.cloudtips.ru/p/bf792932")!
        case .boosty: return URL(string: "https://boosty.to/gcalendar/donate")!
        }
    }
    var qrFilename: String { "\(rawValue)-qr.png" }
    var logoFilename: String { "\(rawValue)-logo.png" }
    // The owner's original Boosty QR includes the service's QR attribution marker.
    var qrURL: URL {
        self == .boosty ? URL(string: "https://boosty.to/gcalendar/donate?qr=true")! : url
    }
}

@MainActor
struct AuthorSupportActions {
    let openURL: (URL) -> Bool
    let copyURL: (String) -> Bool

    static var live: Self {
        Self(openURL: { NSWorkspace.shared.open($0) }, copyURL: { value in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(value, forType: .string)
        })
    }
}

@MainActor
final class AuthorSupportState: ObservableObject {
    @Published private(set) var provider: AuthorSupportProvider
    @Published private(set) var copied = false
    @Published private(set) var errorMessage: String?

    init(provider: AuthorSupportProvider = .cloudTips) { self.provider = provider }

    func select(_ provider: AuthorSupportProvider) {
        self.provider = provider
        copied = false
        errorMessage = nil
    }

    func open(using actions: AuthorSupportActions) {
        errorMessage = actions.openURL(provider.url)
            ? nil : "Не удалось открыть браузер. Скопируйте ссылку или отсканируйте QR-код."
    }

    func copy(using actions: AuthorSupportActions) {
        copied = actions.copyURL(provider.url.absoluteString)
        errorMessage = copied ? nil : "Не удалось скопировать ссылку. Откройте страницу или отсканируйте QR-код."
    }
}

@MainActor
struct AuthorSupportAssets {
    private let qrImages: [AuthorSupportProvider: NSImage]
    private let logoImages: [AuthorSupportProvider: NSImage]

    init(directory: URL?) {
        var qrImages: [AuthorSupportProvider: NSImage] = [:]
        var logoImages: [AuthorSupportProvider: NSImage] = [:]
        if let directory {
            for provider in AuthorSupportProvider.allCases {
                qrImages[provider] = NSImage(contentsOf: directory.appendingPathComponent(provider.qrFilename))
                logoImages[provider] = NSImage(contentsOf: directory.appendingPathComponent(provider.logoFilename))
            }
        }
        self.qrImages = qrImages
        self.logoImages = logoImages
    }

    static let bundled = Self(directory: Bundle.main.resourceURL?.appendingPathComponent("AuthorSupport"))
    func qr(for provider: AuthorSupportProvider) -> NSImage? { qrImages[provider] }
    func logo(for provider: AuthorSupportProvider) -> NSImage? { logoImages[provider] }
}
