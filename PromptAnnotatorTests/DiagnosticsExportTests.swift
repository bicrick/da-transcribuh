import XCTest
@testable import PromptAnnotator

final class DiagnosticsExportTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testAppendRotatesPastCapAndKeepsOneGeneration() throws {
        let url = dir.appendingPathComponent("app.log")
        let line = String(repeating: "x", count: 99) + "\n"
        for _ in 0..<35 { AppLog.append(line, to: url, maxBytes: 1_000) }
        let size = { (u: URL) in (try FileManager.default.attributesOfItem(atPath: u.path)[.size] as! NSNumber).intValue }
        let rotated = URL(fileURLWithPath: url.path + ".1")
        XCTAssertLessThanOrEqual(try size(url), 1_000)
        XCTAssertLessThanOrEqual(try size(rotated), 1_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + ".1.1"))
    }

    func testCrashReportsFilterByNameExtensionAndAge() throws {
        let fm = FileManager.default
        let names = ["da transcribuh-2026-10-01-010101.ips", "PromptAnnotator-2026-10-02.crash",
                     "Safari-2026-10-01.ips", "da transcribuh notes.txt", "da transcribuh-old.ips"]
        for name in names { fm.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data("x".utf8)) }
        let old = Date().addingTimeInterval(-DiagnosticsExporter.crashMaxAge - 3_600)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: dir.appendingPathComponent("da transcribuh-old.ips").path)
        let found = DiagnosticsExporter.crashReports(in: [dir, dir.appendingPathComponent("missing")], now: Date())
            .map(\.lastPathComponent).sorted()
        XCTAssertEqual(found, ["PromptAnnotator-2026-10-02.crash", "da transcribuh-2026-10-01-010101.ips"])
    }

    func testRedactedDefaultsDropsSecretsAndSummarizesBlobs() {
        let lines = DiagnosticsExporter.redactedDefaults([
            "openAIAPIKey": "sk-should-not-appear",
            "hotkeyChord": "⌥Space",
            "historyLimit": 50,
            "blob": Data(count: 4_000),
            "longText": String(repeating: "a", count: 500),
        ])
        let joined = lines.joined(separator: "\n")
        XCTAssertFalse(joined.contains("sk-should-not-appear"))
        XCTAssertTrue(joined.contains("openAIAPIKey = <redacted>"))
        XCTAssertTrue(joined.contains("hotkeyChord = ⌥Space"))
        XCTAssertTrue(joined.contains("blob = <4000 bytes>"))
        XCTAssertTrue(joined.contains("longText = <500 chars>"))
    }

    func testBuildWritesZipWithSummaryLogsAndCrashes() throws {
        let fm = FileManager.default
        let logs = dir.appendingPathComponent("logs"), crashes = dir.appendingPathComponent("crashes")
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        try fm.createDirectory(at: crashes, withIntermediateDirectories: true)
        try "hello\n".write(to: logs.appendingPathComponent("app.log"), atomically: true, encoding: .utf8)
        try "boom".write(to: crashes.appendingPathComponent("da transcribuh-1.ips"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("out.zip")
        try DiagnosticsExporter.build(at: zip, systemSummary: "summary\n", sources: .init(
            logFiles: [logs.appendingPathComponent("app.log"), logs.appendingPathComponent("errors.log")],
            crashFolders: [crashes],
            unifiedLog: { "unified\n" }
        ))
        let list = Process()
        list.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        list.arguments = ["-Z1", zip.path]
        let pipe = Pipe()
        list.standardOutput = pipe
        try list.run()
        list.waitUntilExit()
        let entries = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(entries.contains("out/system.txt"), entries)
        XCTAssertTrue(entries.contains("out/app.log"), entries)
        XCTAssertTrue(entries.contains("out/unified-log.txt"), entries)
        XCTAssertTrue(entries.contains("out/crash-reports/da transcribuh-1.ips"), entries)
        XCTAssertFalse(entries.contains("errors.log"), entries)
    }

    func testDefaultFileNameIsStable() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 23; parts.hour = 14; parts.minute = 5
        let date = Calendar.current.date(from: parts)!
        XCTAssertEqual(DiagnosticsExporter.defaultFileName(date: date), "da transcribuh diagnostics 2026-10-23-1405.zip")
    }
}
