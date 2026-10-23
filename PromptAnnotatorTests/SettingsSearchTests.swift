import XCTest
@testable import PromptAnnotator

final class SettingsSearchTests: XCTestCase {
    func testCatalogIncludesEveryPage() {
        let pages = Set(SettingsSearch.catalog.filter { $0.kind == .page }.map(\.page))
        XCTAssertEqual(pages, Set(SettingsPage.tabOrder))
        XCTAssertEqual(SettingsPage.tabOrder.count, 8)
    }

    func testSettingTitleJumpsToGeneral() {
        let hits = SettingsSearch.search(
            query: "Launch at login",
            sessions: [],
            modelTitles: []
        )
        XCTAssertEqual(hits.first?.page, .configuration)
        XCTAssertEqual(hits.first?.highlightTitle, "Launch at login")
        XCTAssertEqual(hits.first?.kind, .setting)
    }

    func testThemeAndIslandJumpToAppearance() {
        let theme = SettingsSearch.search(query: "System, Light, Dark", sessions: [], modelTitles: [])
        XCTAssertEqual(theme.first?.page, .appearance)
        XCTAssertEqual(theme.first?.highlightTitle, "Theme")

        let island = SettingsSearch.search(query: "Recording window", sessions: [], modelTitles: [])
        XCTAssertEqual(island.first?.page, .appearance)
        XCTAssertEqual(island.first?.highlightTitle, "Recording window")
    }

    func testChangeRecordingShortcutJumpsToHome() {
        let hits = SettingsSearch.search(
            query: "Change recording shortcut",
            sessions: [],
            modelTitles: []
        )
        XCTAssertEqual(hits.first?.page, .home)
        XCTAssertEqual(hits.first?.highlightTitle, "Change recording shortcut")
    }

    func testModelTitleMatches() {
        let hits = SettingsSearch.search(
            query: "Balanced",
            sessions: [],
            modelTitles: SpeechModelChoice.all.map(\.title)
        )
        XCTAssertTrue(hits.contains(where: { $0.kind == .model && $0.title == "Balanced" }))
    }

    func testHistorySnippetHighlightsNeedle() {
        let session = SessionSummary(
            id: "s1",
            url: URL(fileURLWithPath: "/tmp/s1"),
            started: nil,
            ended: nil,
            tiles: 0,
            words: 4,
            model: "small.en",
            transcript: "Thanks for watching the demo today",
            preview: "Thanks for watching"
        )
        let match = HistorySearch.firstMatch(in: session, query: "watching")
        XCTAssertNotNil(match)
        XCTAssertTrue(match!.snippet.localizedCaseInsensitiveContains("watching"))
        let range = match!.range
        let snippet = match!.snippet as NSString
        XCTAssertEqual(snippet.substring(with: range).lowercased(), "watching")
    }

    func testScorePrefersTitlePrefix() {
        let prefix = SettingsSearch.score(haystacks: ["Appearance", "theme"], needle: "App")
        let contains = SettingsSearch.score(haystacks: ["Launch at login", "open"], needle: "App")
        XCTAssertNotNil(prefix)
        XCTAssertGreaterThan(prefix!, contains ?? 0)
    }

    func testBlankQueryReturnsStarterCatalog() {
        let hits = SettingsSearch.search(query: "  ", sessions: [], modelTitles: [])
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.kind == .page || $0.kind == .setting })
    }
}
