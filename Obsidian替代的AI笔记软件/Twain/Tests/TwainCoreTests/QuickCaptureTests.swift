import XCTest
@testable import TwainCore

final class QuickCaptureTests: XCTestCase {
    // Thursday 2026-10-01 10:00 in Shanghai.
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 10))! }

    func parse(_ s: String) -> QuickCapture { QuickCapture.parse(s, now: now, calendar: cal) }

    func testRelativeDaysAndTime() {
        let c = parse("明天下午3点 给@小林 发回归清单 #发布 [[Q4 路线图]]")
        XCTAssertEqual(c.due, "2026-10-02")
        XCTAssertEqual(c.time, "15:00")
        XCTAssertEqual(c.title, "给@小林 发回归清单 #发布 [[Q4 路线图]]")
        XCTAssertEqual(c.markdown, "- [ ] 15:00 给@小林 发回归清单 #发布 [[Q4 路线图]] 📅 2026-10-02")
        XCTAssertEqual(c.tokens.map(\.kind), [.date, .time, .person, .tag, .link])
        XCTAssertEqual(c.tokens.last?.label, "Q4 路线图")
    }

    func testWeekdays() {
        XCTAssertEqual(parse("周五交报告").due, "2026-10-02")
        XCTAssertEqual(parse("周三交报告").due, "2026-10-07")   // already past this week
        XCTAssertEqual(parse("下周一 复盘").due, "2026-10-05")
        XCTAssertEqual(parse("下周日 复盘").due, "2026-10-11")
        XCTAssertEqual(parse("周四").due, "2026-10-01")
    }

    func testDates() {
        XCTAssertEqual(parse("10月8日发布").due, "2026-10-08")
        XCTAssertEqual(parse("9月3号 回顾").due, "2027-09-03")
        XCTAssertEqual(parse("15号前交").due, "2026-10-15")
        XCTAssertEqual(parse("2026-12-24 平安夜").due, "2026-12-24")
        XCTAssertEqual(parse("12/24 买礼物").due, "2026-12-24")
        XCTAssertEqual(parse("12/24 买礼物").title, "买礼物")
    }

    func testTimeAlone() {
        XCTAssertEqual(parse("下午4点半 开会").due, "2026-10-01")
        XCTAssertEqual(parse("下午4点半 开会").time, "16:30")
        XCTAssertEqual(parse("9:30 站会").due, "2026-10-02")   // passed today
        XCTAssertNil(parse("这篇有3点建议").time)
        XCTAssertNil(parse("这篇有3点建议").due)
    }

    func testNothingRecognised() {
        let c = parse("想一想 issue #12的 [[ 写法")
        XCTAssertNil(c.due)
        XCTAssertEqual(c.markdown, "- [ ] 想一想 issue #12的 [[ 写法")
        XCTAssertTrue(parse("   ").isEmpty)
    }

    func testHashInsideLinkIsNotATag() {
        let c = parse("看 [[笔记#小节]]")
        XCTAssertEqual(c.tokens.map(\.kind), [.link])
    }
}
