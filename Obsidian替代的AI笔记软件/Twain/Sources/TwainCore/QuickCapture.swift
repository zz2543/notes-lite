import Foundation

/// A one-line thought typed into the palette, read as a task: when it is due, its tags, the
/// notes it links to and the people it names. The palette shows each piece as it is recognised
/// and the line lands in the inbox as a Markdown task.
public struct QuickCapture: Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case date, time, tag, link, person }

    /// A recognised piece of the typed text.
    public struct Token: Equatable, Sendable {
        public let kind: Kind
        /// Where it is in the typed text (UTF-16).
        public let range: NSRange
        /// How the palette names it ("10月3日 周六", "15:00", "#发布").
        public let label: String
    }

    public let input: String
    public let tokens: [Token]
    /// The day it is due, "yyyy-MM-dd".
    public let due: String?
    /// The time of day, "HH:mm".
    public let time: String?
    /// The words that remain once the date and time are taken out.
    public let title: String

    /// The task as it is written into the inbox. The time stays in the words and the date goes
    /// last as `📅 yyyy-MM-dd`, the form Obsidian's Tasks plugin reads.
    public var markdown: String {
        var s = "- [ ] "
        if let time { s += time + " " }
        s += title
        if let due { s += " 📅 " + due }
        return s
    }

    public var isEmpty: Bool { title.isEmpty }

    public static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> QuickCapture {
        let ns = input as NSString
        let all = NSRange(location: 0, length: ns.length)
        var tokens: [Token] = []
        var taken: [NSRange] = []
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }

        // Links first: a "#" or "@" inside [[…]] belongs to the link.
        for m in linkRe.matches(in: input, range: all) where free(m.range) {
            tokens.append(Token(kind: .link, range: m.range, label: ns.substring(with: m.range(at: 1))))
            taken.append(m.range)
        }
        for m in tagRe.matches(in: input, range: all) where free(m.range(at: 1)) {
            tokens.append(Token(kind: .tag, range: m.range(at: 1), label: ns.substring(with: m.range(at: 1))))
            taken.append(m.range(at: 1))
        }
        for m in personRe.matches(in: input, range: all) where free(m.range(at: 1)) {
            tokens.append(Token(kind: .person, range: m.range(at: 1), label: ns.substring(with: m.range(at: 1))))
            taken.append(m.range(at: 1))
        }

        let today = calendar.startOfDay(for: now)
        var day: Date?
        var dateRange: NSRange?
        for (re, resolve) in dateRules {
            guard dateRange == nil else { break }
            for m in re.matches(in: input, range: all) where free(m.range) {
                let groups = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
                if let d = resolve(groups, today, calendar) {
                    day = d
                    dateRange = m.range
                    taken.append(m.range)
                    break
                }
            }
        }

        var time: (Int, Int)?
        var timeRange: NSRange?
        for m in timeRe.matches(in: input, range: all) where free(m.range) {
            func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
            guard var h = Int(g(2)), h <= 24 else { continue }
            let part = g(1)
            let minute = g(4) == "半" ? 30 : Int(g(4)) ?? 0
            guard minute < 60 else { continue }
            // "3点" with nothing around it may be "three points" (三点建议): it is a time only
            // with a part of the day, minutes, a colon or a day named elsewhere in the line.
            let end = m.range.location + m.range.length
            let next = end < ns.length ? ns.substring(with: NSRange(location: end, length: 1)) : ""
            if part.isEmpty, g(4).isEmpty, g(3) == "点", dateRange == nil, "要个条项建意内需".contains(next), !next.isEmpty { continue }
            if ["下午", "晚上", "傍晚"].contains(part), h < 12 { h += 12 }
            if part == "中午", h < 6 { h += 12 }
            if h == 24 { h = 0 }
            time = (h, minute)
            timeRange = m.range
            taken.append(m.range)
            break
        }
        // A time without a day is today, or tomorrow once that time has passed.
        if day == nil, let (h, mm) = time {
            let at = calendar.date(bySettingHour: h, minute: mm, second: 0, of: today) ?? today
            day = at < now ? calendar.date(byAdding: .day, value: 1, to: today) : today
        }

        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let label = DateFormatter()
        label.calendar = calendar
        label.timeZone = calendar.timeZone
        label.locale = Locale(identifier: "zh_CN")
        label.dateFormat = "M月d日 EEE"
        if let day, let dateRange { tokens.append(Token(kind: .date, range: dateRange, label: label.string(from: day))) }
        let timeText = time.map { String(format: "%02d:%02d", $0.0, $0.1) }
        if let timeRange, let timeText {
            let prefix = dateRange == nil && day.map { !calendar.isDate($0, inSameDayAs: today) } == true ? "明天 " : ""
            tokens.append(Token(kind: .time, range: timeRange, label: prefix + timeText))
        }

        // The title: the input without the date and time phrases, spaces tidied.
        var title = input
        for r in [dateRange, timeRange].compactMap({ $0 }).sorted(by: { $0.location > $1.location }) {
            title = (title as NSString).replacingCharacters(in: r, with: " ")
        }
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        return QuickCapture(input: input, tokens: tokens.sorted { $0.range.location < $1.range.location },
                            due: day.map(fmt.string(from:)), time: timeText, title: title)
    }

    // MARK: rules

    private static let linkRe = try! NSRegularExpression(pattern: #"\[\[([^\[\]|#]+)(?:[#|][^\]]*)?\]\]"#)
    private static let tagRe = try! NSRegularExpression(pattern: #"(?:^|[\s，。,])(#[^\s#，。,！？!?、；;：:]+)"#)
    private static let personRe = try! NSRegularExpression(pattern: #"(?:^|[\s，。,给和与跟找问])(@[^\s@，。,！？!?、；;：:]+)"#)
    private static let timeRe = try! NSRegularExpression(pattern: #"(上午|早上|中午|下午|晚上|傍晚)?\s*(\d{1,2})(点|:|：)(\d{1,2}|半)?分?"#)

    private static let weekdays: [Character: Int] = ["一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1]

    private typealias Resolve = @Sendable ([String], Date, Calendar) -> Date?

    private static let dateRules: [(NSRegularExpression, Resolve)] = [
        (try! NSRegularExpression(pattern: #"(\d{4})-(\d{1,2})-(\d{1,2})"#), { g, _, cal in
            cal.date(from: DateComponents(year: Int(g[1]), month: Int(g[2]), day: Int(g[3])))
        }),
        (try! NSRegularExpression(pattern: #"大后天|后天|明天|今天|今晚|明早|明晚"#), { g, today, cal in
            let offset = ["今天": 0, "今晚": 0, "明天": 1, "明早": 1, "明晚": 1, "后天": 2, "大后天": 3][g[0]] ?? 0
            return cal.date(byAdding: .day, value: offset, to: today)
        }),
        (try! NSRegularExpression(pattern: #"(下下|下)?(?:周|星期|礼拜)([一二三四五六日天])"#), { g, today, cal in
            guard let target = g[2].first.flatMap({ weekdays[$0] }) else { return nil }
            // Weeks start on Monday here: "周日" is the end of this week, not its start.
            func mondayIndex(_ w: Int) -> Int { (w + 5) % 7 }
            let todayIdx = mondayIndex(cal.component(.weekday, from: today))
            let targetIdx = mondayIndex(target)
            let weeks = g[1] == "下下" ? 2 : g[1] == "下" ? 1 : 0
            var delta = targetIdx - todayIdx + 7 * weeks
            // "周三" said on a Thursday means the coming one.
            if weeks == 0, delta < 0 { delta += 7 }
            return cal.date(byAdding: .day, value: delta, to: today)
        }),
        (try! NSRegularExpression(pattern: #"(\d{1,2})月(\d{1,2})[日号]?"#), { g, today, cal in
            nextOccurrence(month: Int(g[1]), day: Int(g[2]), after: today, cal)
        }),
        (try! NSRegularExpression(pattern: #"(?<![\d/])(\d{1,2})/(\d{1,2})(?![\d/])"#), { g, today, cal in
            nextOccurrence(month: Int(g[1]), day: Int(g[2]), after: today, cal)
        }),
        (try! NSRegularExpression(pattern: #"(?<![\d月])(\d{1,2})[号日]"#), { g, today, cal in
            guard let d = Int(g[1]), (1...31).contains(d) else { return nil }
            var c = cal.dateComponents([.year, .month], from: today)
            c.day = d
            if let date = cal.date(from: c), cal.component(.day, from: date) == d, date >= today { return date }
            c.month = (c.month ?? 1) + 1
            return cal.date(from: c)
        }),
    ]

    private static func nextOccurrence(month: Int?, day: Int?, after today: Date, _ cal: Calendar) -> Date? {
        guard let month, let day, (1...12).contains(month), (1...31).contains(day) else { return nil }
        let year = cal.component(.year, from: today)
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: day)),
              cal.component(.day, from: d) == day else { return nil }
        // A date already past this year means next year's.
        return d < today ? cal.date(from: DateComponents(year: year + 1, month: month, day: day)) : d
    }
}
