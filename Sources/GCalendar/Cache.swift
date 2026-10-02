import Foundation

protocol SnapshotStoring: Sendable {
    func load() -> WorkspaceSnapshot?
    func commit(_ snapshot: WorkspaceSnapshot) throws
}

final class MemorySnapshotStore: SnapshotStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: WorkspaceSnapshot?

    init(_ initial: WorkspaceSnapshot? = nil) { value = initial }

    func load() -> WorkspaceSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func commit(_ snapshot: WorkspaceSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        value = snapshot
    }
}

final class FileSnapshotStore: SnapshotStoring, @unchecked Sendable {
    let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) { self.fileURL = fileURL }

    static func applicationDefault(fileManager: FileManager = .default) throws -> FileSnapshotStore {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw GWSFailure.cacheFailure
        }
        return FileSnapshotStore(fileURL: support.appendingPathComponent("g-calendar", isDirectory: true).appendingPathComponent("snapshot.json"))
    }

    func load() -> WorkspaceSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WorkspaceSnapshot.self, from: data)
    }

    func commit(_ snapshot: WorkspaceSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            // Data.write(.atomic) stages a sibling temporary file and renames it over the target.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw GWSFailure.cacheFailure
        }
    }
}

struct GWSExecutableResolver {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let candidates: [URL]

    init(fileManager: FileManager = .default,
         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
         candidates: [URL]? = nil) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.candidates = candidates ?? [
            homeDirectory.appendingPathComponent(".local/bin/gws"),
            URL(fileURLWithPath: "/opt/homebrew/bin/gws"),
            URL(fileURLWithPath: "/usr/local/bin/gws")
        ]
    }

    func resolve(configuredPath: String?) throws -> URL {
        if let configuredPath, !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard configuredPath.hasPrefix("/"), !configuredPath.contains("\0") else { throw GWSFailure.invalidExecutablePath }
            let url = URL(fileURLWithPath: configuredPath).standardizedFileURL
            guard fileManager.isExecutableFile(atPath: url.path) else { throw GWSFailure.executableUnavailable }
            return url
        }
        if let candidate = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) { return candidate }
        throw GWSFailure.executableUnavailable
    }
}

struct LocalTaskMetadata: Codable, Equatable {
    var reminderAt: Date?
    var favorite: Bool
}

protocol LocalMetadataStoring {
    func metadata(for taskID: String) -> LocalTaskMetadata
    func reminderTaskIDs() -> Set<String>
    func set(_ metadata: LocalTaskMetadata, for taskID: String) throws
    func remove(taskID: String) throws
}

final class MemoryLocalMetadataStore: LocalMetadataStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: LocalTaskMetadata] = [:]

    func metadata(for taskID: String) -> LocalTaskMetadata {
        lock.lock(); defer { lock.unlock() }
        return values[taskID] ?? LocalTaskMetadata(reminderAt: nil, favorite: false)
    }

    func reminderTaskIDs() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(values.compactMap { $0.value.reminderAt == nil ? nil : $0.key })
    }

    func set(_ metadata: LocalTaskMetadata, for taskID: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[taskID] = metadata
    }

    func remove(taskID: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: taskID)
    }
}

struct LocalEventReminderRecord: Codable, Equatable {
    let identity: CalendarEventIdentity
    let fireDate: Date
}

protocol LocalEventReminderStoring: Sendable {
    func all() -> [LocalEventReminderRecord]
    func record(for identity: CalendarEventIdentity) -> LocalEventReminderRecord?
    func set(_ record: LocalEventReminderRecord?, for identity: CalendarEventIdentity) throws
}

final class MemoryLocalEventReminderStore: LocalEventReminderStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: LocalEventReminderRecord] = [:]

    func all() -> [LocalEventReminderRecord] {
        lock.lock(); defer { lock.unlock() }
        return records.values.sorted { $0.identity.stableKey < $1.identity.stableKey }
    }

    func record(for identity: CalendarEventIdentity) -> LocalEventReminderRecord? {
        lock.lock(); defer { lock.unlock() }
        return records[identity.stableKey]
    }

    func set(_ record: LocalEventReminderRecord?, for identity: CalendarEventIdentity) throws {
        lock.lock(); defer { lock.unlock() }
        if let record { records[identity.stableKey] = record }
        else { records.removeValue(forKey: identity.stableKey) }
    }
}

final class FileLocalEventReminderStore: LocalEventReminderStoring, @unchecked Sendable {
    private enum DateCodingKeys: String, CodingKey { case referenceSeconds }

    private let fileURL: URL
    private let lock = NSLock()
    private var records: [String: LocalEventReminderRecord]

    init(fileURL: URL) {
        self.fileURL = fileURL
        let decoder = Self.makeDecoder()
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? decoder.decode([String: LocalEventReminderRecord].self, from: data) { records = loaded }
        else { records = [:] }
    }

    func all() -> [LocalEventReminderRecord] {
        lock.lock(); defer { lock.unlock() }
        return records.values.sorted { $0.identity.stableKey < $1.identity.stableKey }
    }

    func record(for identity: CalendarEventIdentity) -> LocalEventReminderRecord? {
        lock.lock(); defer { lock.unlock() }
        return records[identity.stableKey]
    }

    func set(_ record: LocalEventReminderRecord?, for identity: CalendarEventIdentity) throws {
        lock.lock(); defer { lock.unlock() }
        var updated = records
        if let record { updated[identity.stableKey] = record }
        else { updated.removeValue(forKey: identity.stableKey) }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = Self.makeEncoder()
            try encoder.encode(updated).write(to: fileURL, options: .atomic)
            records = updated
        } catch { throw GWSFailure.cacheFailure }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.container(keyedBy: DateCodingKeys.self)
            try container.encode(date.timeIntervalSinceReferenceDate, forKey: .referenceSeconds)
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            if let container = try? decoder.container(keyedBy: DateCodingKeys.self),
               let referenceSeconds = try? container.decode(Double.self, forKey: .referenceSeconds) {
                return Date(timeIntervalSinceReferenceDate: referenceSeconds)
            }
            let container = try decoder.singleValueContainer()
            if let legacyUnixSeconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: legacyUnixSeconds)
            }
            if let legacyValue = try? container.decode(String.self), let date = ISO8601.parse(legacyValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid local event reminder date")
        }
        return decoder
    }
}

final class FileLocalMetadataStore: LocalMetadataStoring {
    private let fileURL: URL
    private let lock = NSLock()
    private var values: [String: LocalTaskMetadata]

    init(fileURL: URL) {
        self.fileURL = fileURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL), let decoded = try? decoder.decode([String: LocalTaskMetadata].self, from: data) {
            values = decoded
        } else { values = [:] }
    }

    func metadata(for taskID: String) -> LocalTaskMetadata {
        lock.lock(); defer { lock.unlock() }
        return values[taskID] ?? LocalTaskMetadata(reminderAt: nil, favorite: false)
    }

    func reminderTaskIDs() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(values.compactMap { taskID, metadata in metadata.reminderAt == nil ? nil : taskID })
    }

    func set(_ metadata: LocalTaskMetadata, for taskID: String) throws {
        lock.lock(); defer { lock.unlock() }
        var updated = values
        updated[taskID] = metadata
        try persist(updated)
        values = updated
    }

    func remove(taskID: String) throws {
        lock.lock(); defer { lock.unlock() }
        var updated = values
        updated.removeValue(forKey: taskID)
        try persist(updated)
        values = updated
    }

    private func persist(_ updated: [String: LocalTaskMetadata]) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(updated).write(to: fileURL, options: .atomic)
        } catch { throw GWSFailure.cacheFailure }
    }
}
