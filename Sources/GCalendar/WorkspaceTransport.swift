import Foundation
import CryptoKit
import Combine
import AppKit

struct GoogleOAuthProfile: Codable {
    let configuration: GoogleOAuthClientConfiguration
    let credential: GoogleOAuthCredential
}

struct WorkspaceTransportContext: @unchecked Sendable {
    enum Kind: String, CaseIterable { case gws, rest }
    let kind: Kind
    let identity: String?
    let directory: URL
    let runner: GWSProcessRunning
    let setupProblem: String?
    var recoveryOnly = false
    var journalURL: URL { directory.appendingPathComponent("pending-verification.json") }
    var reminderEnabledKey: String { identity.map { "restLocalRemindersEnabled." + $0 } ?? "localRemindersEnabled" }
    func factory(configuredGWSPath: String) throws -> GWSCommandFactory {
        if kind == .rest {
            guard identity != nil, setupProblem == nil else { throw GoogleRESTFailure.setupRequired }
            var factory = GWSCommandFactory.googleREST(); factory.contextIdentity = identity; return factory
        }
        return GWSCommandFactory(executableURL: try GWSExecutableResolver().resolve(configuredPath: configuredGWSPath.isEmpty ? nil : configuredGWSPath))
    }
    static func namespace(clientID: String, subject: String) -> String {
        SHA256.hash(data: Data((clientID + "\u{0}" + subject).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static var applicationDirectory: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent("g-calendar", isDirectory: true)
    }
    static func durableSwitchAllowed(in directory: URL = applicationDirectory) -> Bool {
        if MutationJournal(fileURL: directory.appendingPathComponent("pending-verification.json")).isBlocked { return false }
        let rest = directory.appendingPathComponent("rest", isDirectory: true)
        guard FileManager.default.fileExists(atPath: rest.path) else { return true }
        guard let profiles = try? FileManager.default.contentsOfDirectory(at: rest, includingPropertiesForKeys: nil) else { return false }
        return profiles.allSatisfy { !MutationJournal(fileURL: $0.appendingPathComponent("pending-verification.json")).isBlocked }
    }
    static func load(defaults: UserDefaults, secrets: GoogleSecretStoring = GoogleKeychainSecretStore(), http: GoogleHTTPClient = GoogleURLSessionHTTPClient(), applicationDirectory: URL = Self.applicationDirectory) -> Self {
        let requested = Kind(rawValue: defaults.string(forKey: "requestedGoogleTransport") ?? "gws") ?? .gws
        let oldKind = Kind(rawValue: defaults.string(forKey: "activeGoogleTransport") ?? "gws") ?? .gws
        let oldIdentity = defaults.string(forKey: "activeGoogleRESTIdentity")
        var config: GoogleOAuthClientConfiguration?, credential: GoogleOAuthCredential?
        var problem: String?
        do {
            config = try secrets.read("configuration").map { try JSONDecoder().decode(GoogleOAuthClientConfiguration.self, from: $0) }
            credential = try secrets.read("credential").map { try JSONDecoder().decode(GoogleOAuthCredential.self, from: $0) }
        } catch { problem = GoogleRESTFailure.authentication.errorDescription }
        let newIdentity: String?
        if let config, let credential, config.clientID == credential.clientID { newIdentity = namespace(clientID: config.clientID, subject: credential.subject) } else { newIdentity = nil }
        let changing = requested != oldKind || (requested == .rest && newIdentity != oldIdentity)
        if changing && !durableSwitchAllowed(in: applicationDirectory) {
            // Fail closed in the previously active profile, without accepting
            // newly requested credentials or starting any network operation.
            let directory = oldKind == .gws ? applicationDirectory : applicationDirectory.appendingPathComponent("rest/" + (oldIdentity ?? "setup"), isDirectory: true)
            var recoveryRunner: GWSProcessRunning = oldKind == .gws ? FoundationProcessRunner() : UnavailableGoogleRESTRunner()
            var recoveryProblem: String? = MutationRecoveryFailure.pendingVerification.errorDescription
            if oldKind == .rest, let oldIdentity {
                let profile: GoogleOAuthProfile?
                if newIdentity == oldIdentity, let config, let credential { profile = GoogleOAuthProfile(configuration: config, credential: credential) }
                else { profile = try? secrets.read("profile." + oldIdentity).flatMap { try JSONDecoder().decode(GoogleOAuthProfile.self, from: $0) } }
                if let profile, profile.configuration.clientID == profile.credential.clientID,
                   namespace(clientID: profile.configuration.clientID, subject: profile.credential.subject) == oldIdentity {
                    recoveryRunner = GoogleRESTRunner(http: http, tokens: GoogleAccessTokenProvider(configuration: profile.configuration, credential: profile.credential, http: http))
                    recoveryProblem = nil
                }
            }
            return Self(kind: oldKind, identity: oldIdentity, directory: directory, runner: recoveryRunner, setupProblem: recoveryProblem, recoveryOnly: true)
        }
        if requested == .gws {
            defaults.set("gws", forKey: "activeGoogleTransport")
            return Self(kind: .gws, identity: nil, directory: applicationDirectory, runner: FoundationProcessRunner(), setupProblem: nil)
        }
        defaults.set("rest", forKey: "activeGoogleTransport"); defaults.set(newIdentity, forKey: "activeGoogleRESTIdentity")
        guard let config, let credential, let identity = newIdentity, problem == nil else {
            return Self(kind: .rest, identity: nil, directory: applicationDirectory.appendingPathComponent("rest/setup", isDirectory: true), runner: UnavailableGoogleRESTRunner(), setupProblem: problem ?? GoogleRESTFailure.setupRequired.errorDescription)
        }
        let token = GoogleAccessTokenProvider(configuration: config, credential: credential, http: http)
        return Self(kind: .rest, identity: identity, directory: applicationDirectory.appendingPathComponent("rest/" + identity, isDirectory: true), runner: GoogleRESTRunner(http: http, tokens: token), setupProblem: nil)
    }
}

private struct UnavailableGoogleRESTRunner: GWSProcessRunning {
    func run(_ invocation: ProcessInvocation) throws -> ProcessResult { throw GoogleRESTFailure.setupRequired }
}

@MainActor
final class GoogleTransportSettings: ObservableObject {
    @Published private(set) var requested: WorkspaceTransportContext.Kind
    @Published private(set) var status = ""
    @Published private(set) var signingIn = false
    @Published private(set) var requiresRestart = false
    let active: WorkspaceTransportContext.Kind
    private let secrets: GoogleSecretStoring
    private let defaults: UserDefaults
    private let http: GoogleHTTPClient
    private var cancelledSignIn = false
    private var listener: GoogleLoopbackListener?
    private var configuration: GoogleOAuthClientConfiguration?
    init(active: WorkspaceTransportContext.Kind, defaults: UserDefaults, secrets: GoogleSecretStoring = GoogleKeychainSecretStore(), http: GoogleHTTPClient = GoogleURLSessionHTTPClient()) {
        self.active = active; self.defaults = defaults; self.secrets = secrets; self.http = http
        requested = WorkspaceTransportContext.Kind(rawValue: defaults.string(forKey: "requestedGoogleTransport") ?? "gws") ?? .gws
        do {
            if let data = try secrets.read("configuration") { configuration = try JSONDecoder().decode(GoogleOAuthClientConfiguration.self, from: data) }
            status = try secrets.read("credential") == nil ? "Вход не выполнен." : "Google аккаунт подключён. Изменения применяются после перезапуска."
        } catch { status = GoogleRESTFailure.authentication.errorDescription ?? "Ошибка Keychain." }
    }
    private func allowed(_ blocked: Bool) throws {
        guard !blocked, !signingIn, WorkspaceTransportContext.durableSwitchAllowed() else { throw MutationRecoveryFailure.pendingVerification }
    }
    private func archiveCurrentProfile() throws {
        guard let configuration, let data = try secrets.read("credential") else { return }
        let credential = try JSONDecoder().decode(GoogleOAuthCredential.self, from: data)
        guard credential.clientID == configuration.clientID else { throw GoogleRESTFailure.authentication }
        let identity = WorkspaceTransportContext.namespace(clientID: configuration.clientID, subject: credential.subject)
        try secrets.write(JSONEncoder().encode(GoogleOAuthProfile(configuration: configuration, credential: credential)), key: "profile." + identity)
    }
    func request(_ kind: WorkspaceTransportContext.Kind, blocked: Bool) {
        do { try allowed(blocked); requiresRestart = requiresRestart || kind != active; requested = kind; defaults.set(kind.rawValue, forKey: "requestedGoogleTransport"); status = "Транспорт применится после перезапуска." }
        catch { status = MutationRecoveryFailure.pendingVerification.errorDescription ?? "Изменение заблокировано." }
    }
    func importDesktopJSON(_ data: Data, blocked: Bool) {
        do {
            try allowed(blocked)
            let config = try GoogleOAuthClientConfiguration.imported(data)
            try archiveCurrentProfile()
            // A different client cannot inherit the previous client's refresh token.
            if config.clientID != configuration?.clientID { try secrets.write(nil, key: "credential") }
            try secrets.write(JSONEncoder().encode(config), key: "configuration"); configuration = config; requiresRestart = true
            status = "Desktop OAuth JSON импортирован. Выполните вход; изменения применяются после перезапуска."
        } catch { status = (error as? LocalizedError)?.errorDescription ?? "Импорт OAuth не выполнен." }
    }
    func signOut(blocked: Bool) {
        do { try allowed(blocked); try archiveCurrentProfile(); try secrets.write(nil, key: "credential"); requiresRestart = true; status = "Вход удалён. Перезапустите приложение." }
        catch { status = (error as? LocalizedError)?.errorDescription ?? "Выход заблокирован." }
    }
    func cancelSignIn() { cancelledSignIn = true; listener?.cancel(); status = "Отмена входа…" }
    func signIn(blocked: Bool, stillAllowed: @escaping @MainActor () -> Bool) {
        do { try allowed(blocked) } catch { status = MutationRecoveryFailure.pendingVerification.errorDescription ?? "Вход заблокирован."; return }
        guard let configuration else { status = GoogleRESTFailure.setupRequired.errorDescription ?? "Импортируйте JSON."; return }
        cancelledSignIn = false; signingIn = true; status = "Ожидается вход в системном браузере…"
        let listener = GoogleLoopbackListener(); self.listener = listener
        let http = http, secrets = secrets
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<GoogleOAuthCredential, Error>
            do {
                let pkce = try GooglePKCE.create()
                let (code, redirect) = try listener.receive(state: pkce.state) { redirect in
                    let url = GoogleOAuthEndpoint.authorizationURL(config: configuration, pkce: pkce, redirect: redirect)
                    DispatchQueue.main.async { if self?.signingIn == true && self?.cancelledSignIn == false { NSWorkspace.shared.open(url) } }
                }
                var values = ["grant_type": "authorization_code", "client_id": configuration.clientID, "code": code, "redirect_uri": redirect.absoluteString, "code_verifier": pkce.verifier]
                if let secret = configuration.clientSecret { values["client_secret"] = secret }
                let token = try GoogleOAuthEndpoint.token(http, values: values)
                guard let scope = token["scope"] as? String, Set(scope.split(separator: " ").map(String.init)).isSuperset(of: GoogleOAuthEndpoint.scopes),
                      let refresh = token["refresh_token"] as? String, !refresh.isEmpty else { throw GoogleRESTFailure.authentication }
                let subject = try GoogleOAuthEndpoint.subject(http: http, token: token["access_token"] as! String)
                result = .success(GoogleOAuthCredential(clientID: configuration.clientID, subject: subject, refreshToken: refresh, grantedScopes: scope.split(separator: " ").map(String.init)))
            } catch { result = .failure(error) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.signingIn = false; self.listener = nil
                do {
                    let credential = try result.get()
                    guard !self.cancelledSignIn else { throw GoogleRESTFailure.cancelled }
                    guard stillAllowed(), WorkspaceTransportContext.durableSwitchAllowed() else { throw MutationRecoveryFailure.pendingVerification }
                    guard let currentData = try secrets.read("configuration"),
                          let current = try? JSONDecoder().decode(GoogleOAuthClientConfiguration.self, from: currentData),
                          current.clientID == configuration.clientID, current.clientSecret == configuration.clientSecret else { throw GoogleRESTFailure.authentication }
                    try self.archiveCurrentProfile()
                    try secrets.write(JSONEncoder().encode(credential), key: "credential")
                    self.requiresRestart = true
                    self.status = "Google аккаунт подключён. Перезапустите приложение для применения."
                } catch { self.status = (error as? LocalizedError)?.errorDescription ?? "Вход не выполнен." }
            }
        }
    }
}

struct NamespacedReminderScheduler: ReminderScheduling {
    let base: ReminderScheduling
    let namespace: String
    func identifier(_ value: String) -> String { "g-calendar.rest." + namespace + "." + value }
    func permission() async -> ReminderPermission { await base.permission() }
    func requestPermission() async throws -> Bool { try await base.requestPermission() }
    func schedule(_ value: ReminderRequest) async throws {
        try await base.schedule(ReminderRequest(identifier: identifier(value.identifier), taskID: value.taskID, title: value.title, fireDate: value.fireDate))
    }
    func schedule(_ value: EventReminderRequest) async throws {
        try await base.schedule(EventReminderRequest(identifier: identifier(value.identifier), identity: value.identity, title: value.title, fireDate: value.fireDate))
    }
    func cancel(identifier value: String) async { await base.cancel(identifier: identifier(value)) }
}
