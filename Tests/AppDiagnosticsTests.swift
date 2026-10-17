import Foundation

extension InvariantTests {
    static func testAppDiagnostics() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-fixture-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = AppDiagnostics(directory: directory, enabled: true, fileLimit: 512)
        let now = Date()
        logger.record(.launch, now: now.addingTimeInterval(-8 * 86400))
        logger.flush()
        for _ in 0..<100 { logger.record(.requestFinished, operation: .eventInsert, outcome: .success, milliseconds: 42, now: now) }
        logger.flush()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        try check(files.count <= 2, "logs rotate within two bounded files and expire old days")
        for file in files {
            let data = try Data(contentsOf: file)
            try check(data.count <= 512, "each rotated log stays bounded")
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
            try check(permissions.intValue & 0o077 == 0, "logs are readable only by the current user")
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
                try check(Set(object.keys).isSubset(of: ["time", "event", "operation", "outcome", "duration_ms"]), "diagnostics schema has no payload/title/id/token fields")
            }
        }
        let before = try files.map { try Data(contentsOf: $0) }
        logger.setEnabled(false)
        logger.record(.mutationStarted, operation: .eventInsert)
        logger.flush()
        try check(try files.map { try Data(contentsOf: $0) } == before, "disabled logging does not append")
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("untouched".utf8).write(to: unrelated)
        let completion = DispatchSemaphore(value: 0)
        logger.clear { _ in completion.signal() }
        try check(completion.wait(timeout: .now() + 2) == .success, "clear completes asynchronously")
        try check(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["keep.txt"], "clear removes only managed logs, including while disabled")
        logger.setEnabled(true)
        let factory = GWSCommandFactory.googleREST()
        let base = FakeProcessRunner { _ in throw GWSFailure.timedOut("private-name-must-not-leak") }
        let runner = DiagnosticProcessRunner(base: base, diagnostics: logger)
        do { _ = try runner.run(factory.readCalendars(pageToken: nil)) } catch {}
        logger.flush()
        let content = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.map { try String(contentsOf: $0) }.joined()
        try check(content.contains("timeout") && !content.contains("private-name"), "transport failure logs retain safe category without error payload")
    }

    static func testAllDaySaveAndTimeoutRecovery() throws {
        var factory = GWSCommandFactory.googleREST()
        factory.contextIdentity = "synthetic-all-day-profile"
        let calendar = CalendarInfo(id: "calendar", title: "Synthetic", accessRole: "owner", timeZoneID: "UTC", colorHex: nil)
        let body: [String: Any] = ["summary": "Synthetic", "start": ["date": "2026-10-17"], "end": ["date": "2026-10-18"]]
        let invocation = try factory.eventInsert(calendar: calendar, body: body, authorization: .userSave)
        let journal = MutationJournal()
        let runner = FakeProcessRunner { call in
            if call.operation == .eventInsert { return ProcessResult(exitCode: 0, stdout: Data(#"{"id":"event"}"#.utf8), stderr: Data()) }
            throw GWSFailure.timedOut("synthetic-get")
        }
        do {
            _ = try RecoverableMutationService(runner: runner, journal: journal).perform(invocation, reader: GWSReadClient(factory: factory, runner: runner))
            throw TestFailure(description: "timed-out verification reported success")
        } catch GWSFailure.timedOut { assertions += 1 }
        try check(journal.pending?.resourceID == "event" && runner.invocations.count == 2, "all-day save timeout retains exact ID and never repeats POST")
        let readBack = FakeProcessRunner { call in
            guard call.operation == .eventGet else { throw TestFailure(description: "recovery repeated write") }
            var resource = body; resource["id"] = "event"
            return ProcessResult(exitCode: 0, stdout: try JSONSerialization.data(withJSONObject: resource), stderr: Data())
        }
        let result = try RecoverableMutationService(runner: readBack, journal: journal).recheck(reader: GWSReadClient(factory: factory, runner: readBack))
        try check(result.isReadBackVerified && !journal.isBlocked, "all-day verification recovery finishes and clears pending state")
    }
}
