import Foundation

struct CalendarRangeCacheEntry: Codable, Equatable {
    let coverage: CalendarRangeCoverage
    let calendarIDs: [String]
    var events: [CalendarEvent]
    var fetchedAt: Date
    var lastUsedAt: Date
}

enum CalendarRangeCache {
    static let capacity = 5
    static let metadataTTL: TimeInterval = 15 * 60
    static let rangeTTL: TimeInterval = 5 * 60

    static func entries(in snapshot: WorkspaceSnapshot) -> [CalendarRangeCacheEntry] {
        if let entries = snapshot.calendarRangeEntries { return entries }
        guard let coverage = snapshot.calendarCoverage else { return [] }
        return [CalendarRangeCacheEntry(coverage: coverage, calendarIDs: snapshot.calendars.map(\.id).sorted(),
                                        events: snapshot.events, fetchedAt: snapshot.calendarFetchedAt ?? snapshot.fetchedAt,
                                        lastUsedAt: snapshot.calendarFetchedAt ?? snapshot.fetchedAt)]
    }

    static func metadataIsFresh(in snapshot: WorkspaceSnapshot, now: Date) -> Bool {
        guard let fetched = snapshot.calendarMetadataFetchedAt else { return false }
        return now >= fetched && now.timeIntervalSince(fetched) < metadataTTL
    }

    static func needsRevalidation(fetchedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) >= rangeTTL
    }

    static func activate(range: DateRange, in snapshot: WorkspaceSnapshot, now: Date = Date()) -> WorkspaceSnapshot? {
        var entries = entries(in: snapshot)
        let ids = snapshot.calendars.map(\.id).sorted()
        let candidates = entries.indices.filter { entries[$0].calendarIDs == ids && entries[$0].coverage.covers(range) }
        guard let index = candidates.min(by: {
            let lhs = entries[$0].coverage, rhs = entries[$1].coverage
            if lhs == rhs { return entries[$0].fetchedAt > entries[$1].fetchedAt }
            return lhs.endExclusive.timeIntervalSince(lhs.start) < rhs.endExclusive.timeIntervalSince(rhs.start)
        }) else { return nil }
        entries[index].lastUsedAt = now
        var activated = snapshot
        activated.events = entries[index].events
        activated.calendarCoverage = entries[index].coverage
        activated.calendarFetchedAt = entries[index].fetchedAt
        activated.calendarRangeEntries = bounded(entries, protecting: entries[index].coverage, ids: ids)
        return activated
    }

    static func storing(events: [CalendarEvent], range: DateRange, calendarIDs: [String], fetchedAt: Date,
                        in snapshot: WorkspaceSnapshot) -> WorkspaceSnapshot {
        var entries = entries(in: snapshot)
        let coverage = CalendarRangeCoverage(range: range), ids = calendarIDs.sorted()
        entries.removeAll { $0.calendarIDs == ids && overlaps($0.coverage, coverage) }
        entries.append(CalendarRangeCacheEntry(coverage: coverage, calendarIDs: ids, events: events, fetchedAt: fetchedAt, lastUsedAt: fetchedAt))
        var updated = snapshot
        updated.calendarRangeEntries = bounded(entries, protecting: snapshot.calendarCoverage, ids: snapshot.calendars.map(\.id).sorted())
        if let current = updated.calendarCoverage, !entries.contains(where: { $0.coverage == current && $0.calendarIDs == snapshot.calendars.map(\.id).sorted() }) {
            updated.calendarCoverage = nil
        }
        return updated
    }

    static func replacing(calendarIDs: Set<String>, events: [CalendarEvent], range: DateRange, fetchedAt: Date,
                          in snapshot: WorkspaceSnapshot) throws -> WorkspaceSnapshot {
        var entries = entries(in: snapshot)
        let coverage = CalendarRangeCoverage(range: range), ids = snapshot.calendars.map(\.id).sorted()
        guard let index = entries.firstIndex(where: { $0.coverage == coverage && $0.calendarIDs == ids }) else {
            throw GWSFailure.invalidResponse("targeted_calendar_coverage")
        }
        entries[index].events.removeAll { calendarIDs.contains($0.calendarID) }
        entries[index].events.append(contentsOf: events)
        if calendarIDs == Set(ids) { entries[index].fetchedAt = fetchedAt }
        let replacement = entries[index]
        entries.removeAll { $0.calendarIDs == ids && $0.coverage != coverage && overlaps($0.coverage, coverage) }
        var updated = snapshot
        updated.calendarRangeEntries = entries
        if updated.calendarCoverage == coverage {
            updated.events = replacement.events
            updated.calendarFetchedAt = replacement.fetchedAt
        } else if let current = updated.calendarCoverage, overlaps(current, coverage) {
            updated.calendarCoverage = nil
        }
        return updated
    }

    static func applying(event: CalendarEvent?, identity: CalendarEventIdentity, to snapshot: WorkspaceSnapshot) -> WorkspaceSnapshot {
        var updated = snapshot
        var entries = entries(in: snapshot)
        for index in entries.indices {
            let existing = entries[index].events.firstIndex { $0.calendarID == identity.calendarID && $0.id == identity.eventID }
            entries[index].events.removeAll { $0.calendarID == identity.calendarID && $0.id == identity.eventID }
            if let event, entries[index].calendarIDs.contains(event.calendarID), overlaps(event, coverage: entries[index].coverage) {
                entries[index].events.insert(event, at: min(existing ?? entries[index].events.count, entries[index].events.count))
            }
        }
        updated.calendarRangeEntries = entries
        return updated
    }

    static func overlaps(_ event: CalendarEvent, coverage: CalendarRangeCoverage) -> Bool {
        guard let zone = TimeZone(identifier: coverage.timeZoneID) else { return false }
        let start = event.start.instant ?? event.start.dateOnly?.startOfDay(in: zone)
        let end = event.end.instant ?? event.end.dateOnly?.startOfDay(in: zone)
        guard let start, let end else { return false }
        return start < coverage.endExclusive && end > coverage.start
    }

    private static func overlaps(_ lhs: CalendarRangeCoverage, _ rhs: CalendarRangeCoverage) -> Bool {
        lhs.timeZoneID == rhs.timeZoneID && lhs.start < rhs.endExclusive && lhs.endExclusive > rhs.start
    }

    private static func bounded(_ entries: [CalendarRangeCacheEntry], protecting coverage: CalendarRangeCoverage?, ids: [String]) -> [CalendarRangeCacheEntry] {
        let sorted = entries.sorted {
            let leftProtected = $0.coverage == coverage && $0.calendarIDs == ids
            let rightProtected = $1.coverage == coverage && $1.calendarIDs == ids
            if leftProtected != rightProtected { return leftProtected }
            return $0.lastUsedAt > $1.lastUsedAt
        }
        return Array(sorted.prefix(capacity))
    }
}

// Scheduling intent is local and never persisted. Only foreground completions
// offer neighbours; completing a preload cannot create a recursive chain.
struct CalendarNeighbourPrefetch {
    private var offeredAt: [String: Date] = [:]

    mutating func neighbours(after range: DateRange, calendars: [CalendarInfo], snapshot: WorkspaceSnapshot,
                            now: Date = Date(), firstWeekday: Int = 2) -> [DateRange] {
        // A month is loaded as one complete range; weekly speculation would
        // just fetch an already visible slice and consume an API request.
        guard CalendarDatePolicy.days(in: range).count <= 7 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = range.timeZone
        calendar.firstWeekday = firstWeekday
        guard let week = calendar.dateInterval(of: .weekOfYear, for: range.start),
              let start = calendar.date(byAdding: .day, value: 7, to: week.start),
              let end = calendar.date(byAdding: .day, value: 7, to: week.end),
              let neighbour = try? DateRange(start: start, endExclusive: end, timeZone: range.timeZone),
              CalendarRangeCache.activate(range: neighbour, in: snapshot) == nil else { return [] }
        let key = "\(week.start.timeIntervalSince1970):\(range.timeZone.identifier):\(calendars.map(\.id).sorted().joined(separator: ","))"
        if let offered = offeredAt[key], now.timeIntervalSince(offered) < 60 { return [] }
        offeredAt[key] = now
        if offeredAt.count > 8 {
            for entry in offeredAt.sorted(by: { $0.value > $1.value }).dropFirst(8) { offeredAt.removeValue(forKey: entry.key) }
        }
        return [neighbour]
    }
}
