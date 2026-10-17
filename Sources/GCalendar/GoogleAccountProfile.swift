import AppKit
import Foundation
import ImageIO

struct GoogleUserInfo {
    let subject: String
    let name: String?
    let picture: String?
}

struct GoogleAccountDisplayProfile {
    let name: String?
    let avatar: NSImage?
}

/// Optional presentation data. Never changes the trusted OAuth subject or blocks sync.
struct GoogleAccountProfileLoader {
    let credential: GoogleOAuthCredential
    let tokens: GoogleAccessTokenProviding
    let http: GoogleHTTPClient
    static let imageByteLimit = 1_048_576

    func load() throws -> GoogleAccountDisplayProfile? {
        guard GoogleOAuthEndpoint.hasProfileScope(credential.grantedScopes) else { return nil }
        guard !Thread.isMainThread else { throw GWSFailure.forbiddenOperation }
        let deadline = Date().addingTimeInterval(20)
        let token = try tokens.accessToken(forceRefresh: false, deadline: deadline)
        let info = try GoogleOAuthEndpoint.userInfo(http: http, token: token, deadline: deadline)
        guard info.subject == credential.subject else { throw GoogleRESTFailure.authentication }
        let name = Self.displayName(info.name)
        var avatar: NSImage?
        if let url = Self.pictureURL(info.picture), deadline.timeIntervalSinceNow > 0 {
            // Public Google image URL: deliberately no Authorization header, cookies,
            // persistent URL cache or redirects (GoogleURLSessionHTTPClient rejects them).
            var request = URLRequest(url: url, timeoutInterval: min(8, deadline.timeIntervalSinceNow))
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            if let response = try? http.send(request, outputLimit: Self.imageByteLimit, cancellation: nil),
               response.statusCode == 200,
               response.headers["content-type"]?.lowercased().hasPrefix("image/") == true {
                avatar = Self.decodeAvatar(response.body)
            }
        }
        return GoogleAccountDisplayProfile(name: name, avatar: avatar)
    }

    static func displayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let name = value.components(separatedBy: .controlCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 256 ? name : nil
    }

    static func pictureURL(_ value: String?) -> URL? {
        guard let value, value.utf8.count <= 4096, let url = URL(string: value),
              url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              host == "googleusercontent.com" || host.hasSuffix(".googleusercontent.com"),
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { return nil }
        return url
    }

    static func decodeAvatar(_ data: Data) -> NSImage? {
        guard !data.isEmpty, data.count <= imageByteLimit,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}
