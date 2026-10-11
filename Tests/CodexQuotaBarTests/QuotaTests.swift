import XCTest
@testable import CodexQuotaBar

final class QuotaTests: XCTestCase {
    func decode(_ json: String) throws -> QuotaResponse {
        try JSONDecoder().decode(QuotaResponse.self, from: Data(json.utf8))
    }
    func testMultiBucketWinsAndCoreControlsMenu() throws {
        let quota = try decode(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"special":{"primary":{"usedPercent":100}},"codex":{"primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":41,"windowDurationMins":10080}}}}"#)
        XCTAssertEqual(quota.buckets.map(\.id), ["codex", "special"])
        XCTAssertEqual(quota.menuRemaining, 59)
        XCTAssertEqual(quota.buckets[0].value.primary?.duration, L10n.text("5 小时", "5 hours"))
        XCTAssertEqual(quota.buckets[0].value.secondary?.duration, L10n.text("7 天", "7 days"))
    }
    func testLegacyAndNullValues() throws {
        let quota = try decode(#"{"rateLimits":{"primary":{"usedPercent":null,"resetsAt":null},"secondary":null},"rateLimitsByLimitId":null}"#)
        XCTAssertEqual(quota.buckets.count, 1)
        XCTAssertNil(quota.menuRemaining)
        XCTAssertNil(quota.buckets[0].value.primary?.resetDate)
        XCTAssertNil(try decode("{}").menuRemaining)
    }
    func testClampAndUnixSeconds() throws {
        let quota = try decode(#"{"rateLimits":{"primary":{"usedPercent":120,"resetsAt":1730947200},"secondary":{"usedPercent":-5}}}"#)
        XCTAssertEqual(quota.menuRemaining, 0)
        XCTAssertEqual(quota.buckets[0].value.secondary?.remaining, 100)
        XCTAssertEqual(quota.buckets[0].value.primary?.resetDate?.timeIntervalSince1970, 1730947200)
    }
    func testNonCoreBucketDoesNotImpersonateCore() throws {
        XCTAssertNil(try decode(#"{"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":1}}}}"#).menuRemaining)
    }

    func testWindowLabelsUseDurationNotPosition() throws {
        let quota = try decode(#"{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":10080},"secondary":{"usedPercent":23,"windowDurationMins":300}}}"#)
        XCTAssertEqual(MenuStyle.standard.text(quota: quota), L10n.text("5h 77% | 本周 95%", "5h 77% | week 95%"))
        XCTAssertEqual(MenuStyle.compact.text(quota: quota), "5h:77% w:95%")
    }
    func testMissingFiveHourWindowStaysUnknown() throws {
        let quota = try decode(#"{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":10080}}}"#)
        XCTAssertNil(quota.fiveHour)
        XCTAssertEqual(MenuStyle.standard.text(quota: quota), L10n.text("5h — | 本周 95%", "5h — | week 95%"))
        XCTAssertEqual(MenuStyle.standard.text(quota: nil), L10n.text("5h — | 本周 —", "5h — | week —"))
    }

    func testCompactHiddenAndStackedWindows() throws {
        let one = try decode(#"{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":10080}}}"#)
        XCTAssertEqual(MenuStyle.stacked.text(quota: one, hideMissing: true), "w 95%")
        XCTAssertEqual(MenuStyle.standard.text(quota: one, hideMissing: true), L10n.text("本周 95%", "week 95%"))
        XCTAssertEqual(MenuStyle.stacked.text(quota: nil, hideMissing: true), "—")
        let both = try decode(#"{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":5,"windowDurationMins":10080}}}"#)
        XCTAssertEqual(MenuStyle.stacked.text(quota: both, hideMissing: true), "5h 80%\nw 95%")
    }
    func testSelectedWindowCanShowPercentageWithoutLabel() throws {
        let quota = try decode(#"{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":7,"windowDurationMins":10080}}}"#)
        XCTAssertEqual(MenuStyle.compact.text(quota: quota, selection: .week, numbersOnly: true), "93%")
        XCTAssertEqual(MenuStyle.standard.text(quota: quota, selection: .fiveHour, numbersOnly: true), "80%")
        XCTAssertEqual(MenuStyle.stacked.text(quota: quota, selection: .both, numbersOnly: true), "80%\n93%")
        XCTAssertEqual(MenuStyle.compact.text(quota: quota, selection: .week), "w:93%")
    }
    func testSelectedMissingWindowDoesNotBorrowOtherWindow() throws {
        let quota = try decode(#"{"rateLimits":{"primary":{"usedPercent":7,"windowDurationMins":10080}}}"#)
        XCTAssertEqual(MenuStyle.standard.text(quota: quota, hideMissing: true,
                                               selection: .fiveHour, numbersOnly: true), "—")
        XCTAssertEqual(MenuStyle.standard.text(quota: quota, hideMissing: true,
                                               selection: .week, numbersOnly: true), "93%")
    }
    func testCustomRefreshValidation() {
        XCTAssertEqual(RefreshInterval.parse(" 45 "), 45)
        XCTAssertEqual(RefreshInterval.parse("0"), 0)
        XCTAssertEqual(RefreshInterval.parse("86400"), 86400)
        for invalid in ["-1", "9", "86401", "1.5", "abc", ""] {
            XCTAssertNil(RefreshInterval.parse(invalid))
        }
    }

    /// Exercises actual subprocess pipes, handshake, notifications and cleanup without the network.
    private func withServer(_ script: String, body: (String) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("codex")
        try ("#!/bin/zsh\n" + script).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        try body(file.path)
    }
    func testTransportHandshakeAndNotifications() throws {
        try withServer(#"""
        read -r line
        [[ "$line" == *'initialize'* ]] || exit 2
        print -r -- '{"id":1,"result":{}}'
        read -r line
        [[ "$line" == *'initialized'* ]] || exit 3
        read -r line
        [[ "$line" == *'account/read'* ]] || exit 4
        print -r -- '{"method":"account/updated","params":{}}'
        print -r -- '{"id":2,"result":{"account":{"type":"chatgpt","email":"test@example.com","planType":"pro"}}}'
        read -r line
        [[ "$line" == *'account/rateLimits/read'* ]] || exit 5
        print -r -- '{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300}}}}'
        while read -r line; do :; done
        """#) { path in
            let result = try AppServer(timeout: 5).fetch(customPath: path)
            XCTAssertEqual(result.quota.menuRemaining, 75)
            XCTAssertEqual(result.account.email, "test@example.com")
        }
    }
    func testRPCErrorIsSurfaced() throws {
        try withServer(#"""
        read -r line
        print -r -- '{"id":1,"error":{"code":-32000,"message":"Access denied"}}'
        while read -r line; do :; done
        """#) { path in
            XCTAssertThrowsError(try AppServer(timeout: 5).fetch(customPath: path)) {
                XCTAssertTrue($0.localizedDescription.contains("Access denied"))
            }
        }
    }
    func testTimeoutAndEarlyExit() throws {
        try withServer("while read -r line; do :; done\n") { path in
            let start = Date()
            XCTAssertThrowsError(try AppServer(timeout: 0.15).fetch(customPath: path)) {
                XCTAssertTrue($0.localizedDescription.contains(L10n.text("超时", "Timed out")))
            }
            XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        }
        try withServer("read -r line\nexit 0\n") { path in
            XCTAssertThrowsError(try AppServer(timeout: 5).fetch(customPath: path)) {
                XCTAssertTrue($0.localizedDescription.contains(L10n.text("已退出", "exited")))
            }
        }
    }

    func testLanguageFollowsFirstMacOSPreference() {
        XCTAssertEqual(AppLanguage.preferred(["zh-Hans-CN", "en-US"]), .chinese)
        XCTAssertEqual(AppLanguage.preferred(["zh-Hant-TW"]), .chinese)
        XCTAssertEqual(AppLanguage.preferred(["en-US", "zh-Hans-CN"]), .english)
        XCTAssertEqual(AppLanguage.preferred(["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.preferred([]), .english)
        XCTAssertEqual(L10n.text("中文", "English", language: .chinese), "中文")
        XCTAssertEqual(L10n.text("中文", "English", language: .english), "English")
    }
}
