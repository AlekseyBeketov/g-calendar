import Foundation
import Security
import CryptoKit
import Network
import AppKit

struct GoogleOAuthClientConfiguration: Codable, Equatable {
    let clientID: String
    let clientSecret: String?

    static let bundleClientIDKey = "GoogleOAuthClientID"
    static var bundled: Self? { bundled(from: Bundle.main.infoDictionary ?? [:]) }

    static func bundled(from infoDictionary: [String: Any]) -> Self? {
        guard let id = infoDictionary[bundleClientIDKey] as? String, isValidClientID(id) else { return nil }
        return Self(clientID: id, clientSecret: nil)
    }

    static func imported(_ data: Data) throws -> Self {
        guard data.count <= 65_536,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let installed = root["installed"] as? [String: Any], root["web"] == nil,
              let id = installed["client_id"] as? String, isValidClientID(id),
              installed["auth_uri"] as? String == "https://accounts.google.com/o/oauth2/auth",
              installed["token_uri"] as? String == "https://oauth2.googleapis.com/token",
              let redirects = installed["redirect_uris"] as? [String], redirects.contains(where: { $0 == "http://localhost" || $0 == "http://127.0.0.1" }) else { throw GoogleRESTFailure.invalidConfiguration }
        return Self(clientID: id, clientSecret: installed["client_secret"] as? String)
    }

    private static func isValidClientID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 1024 && value.hasSuffix(".apps.googleusercontent.com")
    }
}

protocol GoogleSecretStoring: Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data?, key: String) throws
}

final class GoogleMemorySecretStore: GoogleSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func write(_ data: Data?, key: String) throws { lock.lock(); defer { lock.unlock() }; values[key] = data }
}

struct GoogleKeychainSecretStore: GoogleSecretStoring {
    private let service = "com.alexbeketov.gcalendar.google-rest"
    func read(_ key: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw GoogleRESTFailure.authentication }
        return data
    }
    func write(_ data: Data?, key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        if let data {
            let values: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let updated = SecItemUpdate(query as CFDictionary, values as CFDictionary)
            if updated == errSecItemNotFound {
                var item = query; values.forEach { item[$0.key] = $0.value }
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw GoogleRESTFailure.authentication }
            } else if updated != errSecSuccess { throw GoogleRESTFailure.authentication }
        } else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw GoogleRESTFailure.authentication }
        }
    }
}

struct GoogleOAuthCredential: Codable, Equatable {
    let clientID: String
    let subject: String
    let refreshToken: String
    var grantedScopes: [String] = GoogleOAuthEndpoint.scopes
}

struct GooglePKCE: Equatable {
    let verifier: String
    let state: String
    var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    static func create() throws -> Self {
        func random() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw GoogleRESTFailure.authentication }
            return base64URL(Data(bytes))
        }
        return try Self(verifier: random(), state: random())
    }
    static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

struct GoogleOAuthEndpoint {
    static let scopes = ["https://www.googleapis.com/auth/tasks", "https://www.googleapis.com/auth/calendar.events", "https://www.googleapis.com/auth/calendar.calendarlist.readonly", "openid"]
    static func form(_ values: [String: String]) -> Data {
        // Form encoding differs from URL query: literal + must stay percent-encoded.
        let chars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.keys.sorted().map { $0.addingPercentEncoding(withAllowedCharacters: chars)! + "=" + values[$0]!.addingPercentEncoding(withAllowedCharacters: chars)! }.joined(separator: "&").utf8)
    }
    static func authorizationURL(config: GoogleOAuthClientConfiguration, pkce: GooglePKCE, redirect: URL) -> URL {
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        let values = ["client_id": config.clientID, "redirect_uri": redirect.absoluteString, "response_type": "code", "scope": scopes.joined(separator: " "), "code_challenge": pkce.challenge, "code_challenge_method": "S256", "state": pkce.state, "access_type": "offline", "prompt": "consent"]
        url.queryItems = values.keys.sorted().map { URLQueryItem(name: $0, value: values[$0]) }
        return url.url!
    }
    static func callbackCode(_ request: String, port: UInt16, state: String) throws -> String {
        guard request.utf8.count <= 8192, let headerEnd = request.range(of: "\r\n\r\n"), headerEnd.upperBound == request.endIndex else { throw GoogleRESTFailure.authentication }
        let lines = request.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ").map(String.init)
        guard first.count == 3, first[0] == "GET", first[2] == "HTTP/1.1" else { throw GoogleRESTFailure.authentication }
        let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }
        guard hosts.count == 1, hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces) == "127.0.0.1:\(port)",
              first[1].hasPrefix("/oauth/callback?"), let url = URLComponents(string: first[1]), url.path == "/oauth/callback", url.host == nil,
              let items = url.queryItems, Set(items.map(\.name)).count == items.count,
              items.first(where: { $0.name == "state" })?.value == state,
              items.first(where: { $0.name == "error" }) == nil,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw GoogleRESTFailure.authentication }
        return code
    }
    static func token(_ http: GoogleHTTPClient, values: [String: String], deadline: Date = Date().addingTimeInterval(20)) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: max(0.001, deadline.timeIntervalSinceNow))
        request.httpMethod = "POST"; request.httpBody = form(values); request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard deadline.timeIntervalSinceNow > 0 else { throw GWSFailure.timedOut("Google OAuth") }
        let response = try http.send(request, outputLimit: 65_536, cancellation: nil)
        guard response.statusCode == 200, let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              object["token_type"] as? String == "Bearer", let access = object["access_token"] as? String, !access.isEmpty,
              let expires = object["expires_in"] as? Double, expires > 60, expires <= 86_400 else { throw GoogleRESTFailure.authentication }
        if let scope = object["scope"] as? String { guard Set(scope.split(separator: " ").map(String.init)).isSuperset(of: scopes) else { throw GoogleRESTFailure.authentication } }
        else if values["grant_type"] == "authorization_code" { throw GoogleRESTFailure.authentication }
        return object
    }
    static func subject(http: GoogleHTTPClient, token: String, deadline: Date = Date().addingTimeInterval(20)) throws -> String {
        var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!, timeoutInterval: max(0.001, deadline.timeIntervalSinceNow))
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        guard deadline.timeIntervalSinceNow > 0 else { throw GWSFailure.timedOut("Google OAuth") }
        let response = try http.send(request, outputLimit: 65_536, cancellation: nil)
        guard response.statusCode == 200, let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any], let subject = object["sub"] as? String, !subject.isEmpty, subject.utf8.count <= 256 else { throw GoogleRESTFailure.authentication }
        return subject
    }
}

final class GoogleAccessTokenProvider: GoogleAccessTokenProviding, @unchecked Sendable {
    private let condition = NSCondition()
    private var cached: (String, Date)?
    private var refreshing = false
    private var generation = 0
    private var lastFailure: Error?
    private let configuration: GoogleOAuthClientConfiguration
    private let credential: GoogleOAuthCredential
    private let http: GoogleHTTPClient
    init(configuration: GoogleOAuthClientConfiguration, credential: GoogleOAuthCredential, http: GoogleHTTPClient) {
        self.configuration = configuration; self.credential = credential; self.http = http
    }
    func accessToken(forceRefresh: Bool) throws -> String { try accessToken(forceRefresh: forceRefresh, deadline: Date().addingTimeInterval(20)) }
    func accessToken(forceRefresh: Bool, deadline: Date) throws -> String {
        guard !Thread.isMainThread, configuration.clientID == credential.clientID, Set(credential.grantedScopes).isSuperset(of: GoogleOAuthEndpoint.scopes) else { throw GoogleRESTFailure.authentication }
        condition.lock()
        let observedGeneration = generation
        while refreshing {
            if !condition.wait(until: deadline) { condition.unlock(); throw GWSFailure.timedOut("Google OAuth") }
        }
        if generation != observedGeneration, let failure = lastFailure { condition.unlock(); throw failure }
        if let cached, cached.1.timeIntervalSinceNow > 60, !forceRefresh || generation != observedGeneration { condition.unlock(); return cached.0 }
        refreshing = true; lastFailure = nil; condition.unlock()
        do {
            var values = ["grant_type": "refresh_token", "client_id": configuration.clientID, "refresh_token": credential.refreshToken]
            if let secret = configuration.clientSecret { values["client_secret"] = secret }
            let token = try GoogleOAuthEndpoint.token(http, values: values, deadline: deadline)
            let access = token["access_token"] as! String
            // Bind every refreshed access token to the immutable account context.
            guard try GoogleOAuthEndpoint.subject(http: http, token: access, deadline: deadline) == credential.subject else { throw GoogleRESTFailure.authentication }
            condition.lock(); cached = (access, Date().addingTimeInterval(token["expires_in"] as! Double)); refreshing = false; generation += 1; condition.broadcast(); condition.unlock()
            return access
        } catch { condition.lock(); cached = nil; lastFailure = GoogleRESTFailure.authentication; refreshing = false; generation += 1; condition.broadcast(); condition.unlock(); throw error }
    }
}

final class GoogleLoopbackListener: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var cancelled = false
    private let queue = DispatchQueue(label: "g-calendar.oauth.loopback")
    func cancel() { lock.lock(); cancelled = true; let listener = listener, connections = connections; lock.unlock(); listener?.cancel(); connections.forEach { $0.cancel() } }
    private func close(_ connection: NWConnection) {
        connection.cancel(); lock.lock(); connections.removeAll { $0 === connection }; lock.unlock()
    }
    func receive(state: String, open: (URL) throws -> Void) throws -> (String, URL) {
        guard !Thread.isMainThread else { throw GWSFailure.forbiddenOperation }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        lock.lock(); self.listener = listener; let stopped = cancelled; lock.unlock()
        if stopped { throw GoogleRESTFailure.cancelled }
        let ready = DispatchSemaphore(value: 0), completed = DispatchSemaphore(value: 0)
        let resultLock = NSLock(); var code: String?, failure: Error?
        listener.stateUpdateHandler = { status in
            if case .ready = status { ready.signal() }
            if case .failed = status { resultLock.lock(); failure = GoogleRESTFailure.network; resultLock.unlock(); ready.signal(); completed.signal() }
            if case .cancelled = status { completed.signal(); ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, let port = listener.port else { connection.cancel(); return }
            self.lock.lock()
            guard !self.cancelled, self.connections.count < 8 else { self.lock.unlock(); connection.cancel(); return }
            self.connections.append(connection); self.lock.unlock()
            connection.start(queue: self.queue)
            var buffer = Data()
            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - buffer.count) { data, _, done, error in
                    if let data { buffer.append(data) }
                    if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                        let validated = try? GoogleOAuthEndpoint.callbackCode(String(data: buffer, encoding: .utf8) ?? "", port: port.rawValue, state: state)
                        if let validated { resultLock.lock(); if code == nil { code = validated }; resultLock.unlock(); completed.signal() }
                        let status = validated == nil ? "400 Bad Request" : "200 OK"
                        let body = validated == nil ? "Invalid callback." : "Google sign-in complete. You may close this window."
                        let response = Data("HTTP/1.1 \(status)\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".utf8)
                        connection.send(content: response, completion: .contentProcessed { _ in self.close(connection) })
                    } else if done || error != nil || buffer.count >= 8192 { self.close(connection) }
                    else { receive() }
                }
            }
            receive()
        }
        listener.start(queue: queue)
        defer { cancel(); listener.newConnectionHandler = nil; listener.stateUpdateHandler = nil; lock.lock(); self.listener = nil; connections.removeAll(); lock.unlock() }
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else { throw GoogleRESTFailure.network }
        let redirect = URL(string: "http://127.0.0.1:\(port.rawValue)/oauth/callback")!
        try open(redirect)
        guard completed.wait(timeout: .now() + 120) == .success else { throw GoogleRESTFailure.cancelled }
        resultLock.lock(); let result = code, error = failure; resultLock.unlock()
        if let error { throw error }; guard let result else { throw GoogleRESTFailure.cancelled }
        return (result, redirect)
    }
}
