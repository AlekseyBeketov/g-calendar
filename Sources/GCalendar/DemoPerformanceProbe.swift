import AppKit
import Darwin
import Foundation

/// Opt-in synthetic measurements. AppKit update notifications are event-loop markers,
/// not proof of pixel presentation, successful layout or GPU frame rate.
@MainActor
final class DemoPerformanceProbe {
    enum Operation: String, CaseIterable {
        case launch, section, search, range, filter, taskList, form, taskCompletion, appearance, resize, selection, scroll
    }

    static let shared = DemoPerformanceProbe()
    private let interval = 0.020
    private let sampleLimit = 8192
    private let writer = DispatchQueue(label: "g-calendar.demo-performance-writer", qos: .utility)
    private var reportURL: URL?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var lastTick: TimeInterval?
    private var lastReport: TimeInterval = 0
    private var startedAt: TimeInterval = 0
    private var pending: [Operation: TimeInterval] = [:]
    private var measurements: [Operation: Samples] = [:]
    private var schedulingDelay = Samples()
    private var delaysOver50MS = 0
    private var delaysOver100MS = 0
    private var viewport: [String: Double] = [:]

    private struct Samples {
        var count = 0
        var coalesced = 0
        var totalMS = 0.0
        var maximumMS = 0.0
        var recentMS: [Double] = []

        mutating func append(_ value: Double, limit: Int) {
            count += 1
            totalMS += value
            maximumMS = max(maximumMS, value)
            if recentMS.count == limit { recentMS.removeFirst(limit / 2) }
            recentMS.append(value)
        }

        var summary: [String: Any] {
            let sorted = recentMS.sorted()
            func percentile(_ fraction: Double) -> Double {
                guard !sorted.isEmpty else { return 0 }
                return sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * fraction)) - 1))]
            }
            return ["count": count, "coalesced_starts": coalesced, "percentile_sample_count": sorted.count,
                    "mean_ms": count == 0 ? 0 : totalMS / Double(count),
                    "p50_ms": percentile(0.5), "p95_ms": percentile(0.95), "max_ms": maximumMS]
        }
    }

    /// Call before the first window appears. Normal/acceptance modes remain inert.
    @discardableResult
    func startIfRequested(arguments: [String], mode: AppLaunchMode) -> URL? {
        guard mode == .demo, arguments.contains("--demo"), arguments.contains("--profile-ui") else { return nil }
        if let reportURL { return reportURL }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("g-calendar-ui-profile-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(directory.path, 0o700) == 0 else { return nil }
        guard chmod(directory.path, 0o700) == 0 else { try? FileManager.default.removeItem(at: directory); return nil }
        let destination = directory.appendingPathComponent("report.json")
        let descriptor = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { try? FileManager.default.removeItem(at: directory); return nil }
        guard fchmod(descriptor, 0o600) == 0 else {
            Darwin.close(descriptor)
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
        Darwin.close(descriptor)
        reportURL = destination
        startedAt = ProcessInfo.processInfo.systemUptime
        lastTick = startedAt
        pending[.launch] = startedAt
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification,
                                                                 object: nil, queue: .main) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.windowUpdated(window) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                                                 object: nil, queue: .main) { [weak self] notification in
            guard let window = notification.object as? NSWindow, window.isVisible else { return }
            MainActor.assumeIsolated {
                self?.begin(.resize)
                self?.updateViewport(window)
            }
        })
        let sampler = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleSchedulingDelay() }
        }
        sampler.tolerance = 0
        RunLoop.main.add(sampler, forMode: .common)
        timer = sampler
        writeReport()
        print("G_CALENDAR_UI_PROFILE_REPORT=\(destination.path)")
        return destination
    }

    /// Call immediately before the local state mutation, never from View.body.
    func begin(_ operation: Operation) {
        guard reportURL != nil else { return }
        if pending[operation] == nil {
            pending[operation] = ProcessInfo.processInfo.systemUptime
        } else {
            var samples = measurements[operation] ?? Samples()
            samples.coalesced += 1
            measurements[operation] = samples
        }
    }

    /// Clip synchronisation often causes no NSWindow.update at all. Measure the
    /// native handler itself, separately from action-to-window-update markers.
    func measureScrollSynchronization(_ body: () -> Void) {
        guard reportURL != nil else { body(); return }
        let start = ProcessInfo.processInfo.systemUptime
        body()
        var samples = measurements[.scroll] ?? Samples()
        samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000, limit: sampleLimit)
        measurements[.scroll] = samples
    }

    /// Writes a snapshot asynchronously; leaves only the private aggregate for inspection.
    func flush() { if reportURL != nil { writeReport() } }

    private func windowUpdated(_ window: NSWindow) {
        guard window.isVisible, !window.isMiniaturized else { return }
        updateViewport(NSApp.mainWindow ?? window)
        let now = ProcessInfo.processInfo.systemUptime
        for (operation, start) in pending {
            var samples = measurements[operation] ?? Samples()
            samples.append(max(0, (now - start) * 1000), limit: sampleLimit)
            measurements[operation] = samples
        }
        pending.removeAll()
        if now - lastReport >= 1 { writeReport() }
    }

    private func updateViewport(_ window: NSWindow) {
        viewport = ["width_pt": window.contentLayoutRect.width,
                    "height_pt": window.contentLayoutRect.height,
                    "backing_scale": window.backingScaleFactor]
    }

    private func sampleSchedulingDelay() {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastTick = now }
        // Inactive/minimized windows are excluded; elapsed background time is not a stall.
        guard NSApp.isActive, NSApp.windows.contains(where: { $0.isVisible && !$0.isMiniaturized }),
              let previous = lastTick else { return }
        let delay = max(0, (now - previous - interval) * 1000)
        schedulingDelay.append(delay, limit: sampleLimit)
        if delay > 50 { delaysOver50MS += 1 }
        if delay > 100 { delaysOver100MS += 1 }
        if now - lastReport >= 5 { writeReport() }
    }

    private func writeReport() {
        guard let reportURL else { return }
        lastReport = ProcessInfo.processInfo.systemUptime
        var operations: [String: Any] = [:]
        for operation in Operation.allCases {
            if let samples = measurements[operation] { operations[operation.rawValue] = samples.summary }
        }
        let report: [String: Any] = [
            "schema": 2, "mode": "synthetic_demo_only", "elapsed_ms": (lastReport - startedAt) * 1000,
            "measurement": "local_state_action_to_next_visible_AppKit_window_update_notification",
            "scroll_measurement": "native_clip_synchronization_handler_duration_not_pixel_latency",
            "pixel_presentation_measured": false, "gpu_fps_measured": false,
            "operations": operations, "pending_operation_count": pending.count, "viewport": viewport,
            "main_runloop_timer": ["interval_ms": interval * 1000, "tolerance_ms": 0,
                                   "scheduling_delay": schedulingDelay.summary,
                                   "delays_over_50_ms": delaysOver50MS, "delays_over_100_ms": delaysOver100MS]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        writer.async {
            let temporary = reportURL.deletingLastPathComponent().appendingPathComponent(".report-\(UUID().uuidString)")
            let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { return }
            guard fchmod(descriptor, 0o600) == 0 else {
                Darwin.close(descriptor)
                Darwin.unlink(temporary.path)
                return
            }
            let success = data.withUnsafeBytes { buffer -> Bool in
                guard let pointer = buffer.baseAddress else { return true }
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(descriptor, pointer.advanced(by: offset), buffer.count - offset)
                    if written < 0, errno == EINTR { continue }
                    guard written > 0 else { return false }
                    offset += written
                }
                return true
            }
            Darwin.close(descriptor)
            if !success || Darwin.rename(temporary.path, reportURL.path) != 0 { Darwin.unlink(temporary.path) }
        }
    }
}
