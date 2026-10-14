import AppKit
import SwiftUI
import Vision

@main
struct AuthorSupportTests {
    @MainActor
    static func main() throws {
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            guard condition() else { fatalError("FAIL: \(message)") }
        }
        func decode(_ data: Data) throws -> [String] {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            request.usesCPUOnly = true
            try VNImageRequestHandler(data: data).perform([request])
            return request.results?.compactMap(\.payloadStringValue) ?? []
        }
        let environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: environment["G_CALENDAR_SUPPORT_RESOURCES"]!)
        let evidence = URL(fileURLWithPath: environment["G_CALENDAR_SUPPORT_EVIDENCE"]!)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let assets = AuthorSupportAssets(directory: directory)
        expect(AuthorSupportProvider.allCases == [.cloudTips, .boosty], "primary provider and segment order")
        expect(AuthorSupportProvider.cloudTips.url.absoluteString == "https://pay.cloudtips.ru/p/bf792932", "exact CloudTips destination")
        expect(AuthorSupportProvider.boosty.url.absoluteString == "https://boosty.to/gcalendar/donate", "exact Boosty donation destination")

        for provider in AuthorSupportProvider.allCases {
            let payloads = try decode(Data(contentsOf: directory.appendingPathComponent(provider.qrFilename)))
            expect(payloads == [provider.qrURL.absoluteString], "\(provider.title) QR matches its declared payload: \(payloads)")
            expect(assets.qr(for: provider) != nil, "\(provider.title) QR is an AppKit image")
            expect(assets.logo(for: provider) != nil, "\(provider.title) logo is packaged")
            expect(assets.qr(for: provider)?.isTemplate == false, "QR retains original colors")
        }

        var opened: [URL] = []
        var copied: [String] = []
        let success = AuthorSupportActions(openURL: { opened.append($0); return true },
                                           copyURL: { copied.append($0); return true })
        let failure = AuthorSupportActions(openURL: { _ in false }, copyURL: { _ in false })
        let state = AuthorSupportState()
        expect(state.provider == .cloudTips, "each new window defaults to CloudTips")
        expect(opened.isEmpty && copied.isEmpty, "creating state never opens a URL or writes clipboard")
        state.open(using: success)
        expect(opened == [AuthorSupportProvider.cloudTips.url], "explicit open targets CloudTips")
        state.copy(using: success)
        expect(copied == [AuthorSupportProvider.cloudTips.url.absoluteString] && state.copied, "copy records success and exact URL")
        state.select(.boosty)
        expect(!state.copied && state.errorMessage == nil, "provider change clears stale feedback")
        state.open(using: success)
        state.copy(using: success)
        expect(opened.last == AuthorSupportProvider.boosty.url, "open follows selected provider")
        expect(copied.last == AuthorSupportProvider.boosty.url.absoluteString, "clipboard follows selected provider")
        state.open(using: failure)
        expect(state.errorMessage != nil, "failed browser open remains recoverable")
        state.copy(using: failure)
        expect(!state.copied && state.errorMessage != nil, "failed clipboard write is not reported as success")
        state.copy(using: success)
        expect(state.copied && state.errorMessage == nil, "retry clears error")
        state.select(.cloudTips)
        expect(state.errorMessage == nil && !state.copied, "switching back resets feedback")
        let missing = AuthorSupportAssets(directory: nil)
        expect(missing.qr(for: .cloudTips) == nil && missing.logo(for: .boosty) == nil, "missing resources safely fall back to links")

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        for scheme in [ColorScheme.light, .dark] {
            for provider in AuthorSupportProvider.allCases {
                let name = "\(provider.rawValue)-\(scheme == .dark ? "dark" : "light")"
                let view = AuthorSupportView(provider: provider, assets: assets, actions: success)
                    .environment(\.colorScheme, scheme)
                    .environment(\.controlActiveState, .active)
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                host.frame = window.contentView!.bounds
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                let size = host.fittingSize
                expect(size.width <= 441 && size.height <= 640, "\(name) content fits the modal")
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    fatalError("Could not create an offscreen bitmap")
                }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = bitmap.representation(using: .png, properties: [:])!
                try data.write(to: evidence.appendingPathComponent("\(name).png"))
                let payloads = try decode(data)
                expect(payloads == [provider.qrURL.absoluteString], "\(name) displayed QR is readable and follows selection")
                expect(opened.count == 2 && copied.count == 3, "offscreen rendering causes no external actions")
            }
        }
        print("PASS author support: \(assertions) assertions; source and rendered QR verified in Light/Dark")
        print("OFFSCREEN_EVIDENCE=\(evidence.path)")
    }
}
