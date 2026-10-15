import Foundation
import AppKit
import CryptoKit
import Sparkle

private final class NoNetworkUpdateDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        throw NSError(domain: "g-calendar.update-fixture", code: 1)
    }
}

@main
struct UpdateArchiveTests {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 5, let bundle = Bundle(path: args[1]), let fixture = Bundle(path: args[4]),
              let publicString = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let publicData = Data(base64Encoded: publicString), let signature = Data(base64Encoded: args[3]) else {
            fatalError("Expected app bundle, ZIP and EdDSA signature")
        }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
        let archive = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        guard key.isValidSignature(signature, for: archive) else { fatalError("Authentic update rejected") }
        var changed = archive
        changed[changed.startIndex] ^= 1
        guard !key.isValidSignature(signature, for: changed) else { fatalError("Tampered update accepted") }
        let settings = SPUUpdaterSettings(hostBundle: bundle)
        guard settings.allowsAutomaticUpdates else { fatalError("Automatic updates unavailable") }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let fixtureID = fixture.bundleIdentifier!
        defer { UserDefaults.standard.removePersistentDomain(forName: fixtureID) }
        let blocker = NoNetworkUpdateDelegate()
        let driver = SPUStandardUserDriver(hostBundle: fixture, delegate: nil)
        let updater = SPUUpdater(hostBundle: fixture, applicationBundle: fixture, userDriver: driver, delegate: blocker)
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        try updater.start()
        guard updater.canCheckForUpdates else { fatalError("The configured updater cannot start") }
        print("PASS authentic archive, tampered archive rejection, Sparkle runtime loading and automatic-update availability")
        print("PASS signed-feed updater starts in an isolated ad-hoc app without network or user preferences")
    }
}
