import Foundation

let alias = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let bookmark = CFURLCreateBookmarkDataFromAliasRecord(kCFAllocatorDefault, alias as CFData) else {
    fatalError("Finder background alias is not a valid alias record")
}
var stale = false
let resolved = try URL(resolvingBookmarkData: bookmark.takeRetainedValue() as Data,
                       options: [.withoutUI, .withoutMounting], relativeTo: nil,
                       bookmarkDataIsStale: &stale)
let expected = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
guard resolved.standardizedFileURL == expected, FileManager.default.fileExists(atPath: expected.path) else {
    fatalError("Finder background does not resolve inside its own mounted image")
}
print("PASS Finder resolves its embedded background on the mounted image")
