import Foundation

struct QuotaWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Double? { usedPercent.map { max(0, min(100, 100 - $0)) } }
    var duration: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return L10n.text("未知周期", "Unknown window") }
        if minutes % 1440 == 0 { return L10n.text("\(minutes / 1440) 天", "\(minutes / 1440) days") }
        if minutes % 60 == 0 { return L10n.text("\(minutes / 60) 小时", "\(minutes / 60) hours") }
        return L10n.text("\(minutes) 分钟", "\(minutes) minutes")
    }
    var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}

struct QuotaBucket: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let planType: String?
}

struct QuotaResponse: Decodable {
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
    var buckets: [(id: String, value: QuotaBucket)] {
        if let map = rateLimitsByLimitId, !map.isEmpty {
            return map.map { (id: $0.key, value: $0.value) }.sorted {
                if $0.id == "codex" { return $1.id != "codex" }
                if $1.id == "codex" { return false }
                return $0.id < $1.id
            }
        }
        return rateLimits.map { [(id: $0.limitId ?? "codex", value: $0)] } ?? []
    }
    var coreWindows: [QuotaWindow] {
        let core = buckets.first(where: { $0.id == "codex" })?.value
        return [core?.primary, core?.secondary].compactMap { $0 }
    }
    var fiveHour: QuotaWindow? { coreWindows.first { $0.windowDurationMins == 300 } }
    var week: QuotaWindow? { coreWindows.first { $0.windowDurationMins == 10080 } }

    var menuRemaining: Double? {
        // Only the core Codex bucket should determine the menu-bar percentage.
        let core = buckets.first(where: { $0.id == "codex" })?.value
        return [core?.primary?.remaining, core?.secondary?.remaining].compactMap { $0 }.min()
    }
}

struct AccountResponse: Decodable {
    struct Account: Decodable {
        let type: String
        let email: String?
        let planType: String?
    }
    let account: Account?
}

struct QuotaSnapshot {
    let quota: QuotaResponse
    let account: AccountResponse.Account
    let fetchedAt: Date
}

struct QuotaError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}


enum MenuStyle: String, CaseIterable, Identifiable {
    case standard, compact, chinese, stacked
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return L10n.text("标准 · 5h 80% | week 60%", "Standard · 5h 80% | week 60%")
        case .compact: return L10n.text("紧凑 · 5h:80% w:60%", "Compact · 5h:80% w:60%")
        case .chinese: return L10n.text("中文 · 5小时 80% · 本周 60%", "Chinese · 5小时 80% · 本周 60%")
        case .stacked: return L10n.text("双排 · 上下排列，节省宽度", "Two lines · saves menu bar space")
        }
    }
    func lines(quota: QuotaResponse?, hideMissing: Bool = false,
               selection: WindowSelection = .both, numbersOnly: Bool = false) -> [String] {
        let windows: [(String, QuotaWindow?)] = [(self == .chinese ? "5小时" : "5h", quota?.fiveHour),
            (self == .chinese ? "本周" : (self == .compact || self == .stacked ? "w" : L10n.text("本周", "week")), quota?.week)]
        return windows.enumerated().compactMap { index, item in
            if !selection.includes(index: index) { return nil }
            let (label, window) = item
            if hideMissing && window?.remaining == nil { return nil }
            let value = window?.remaining.map { "\(Int($0.rounded(.down)))%" } ?? "—"
            return numbersOnly ? value : label + (self == .compact ? ":" : " ") + value
        }
    }
    func text(quota: QuotaResponse?, hideMissing: Bool = false,
              selection: WindowSelection = .both, numbersOnly: Bool = false) -> String {
        let values = lines(quota: quota, hideMissing: hideMissing,
                           selection: selection, numbersOnly: numbersOnly)
        if values.isEmpty { return "—" }
        return values.joined(separator: self == .standard ? " | " : self == .chinese ? " · " : self == .stacked ? "\n" : " ")
    }
}

enum WindowSelection: String, CaseIterable, Identifiable {
    case both, fiveHour, week
    var id: String { rawValue }
    var title: String {
        switch self {
        case .both: return L10n.text("5h 和周额度", "5h and weekly")
        case .fiveHour: return L10n.text("仅 5h", "5h only")
        case .week: return L10n.text("仅周额度", "Weekly only")
        }
    }
    func includes(index: Int) -> Bool {
        switch self {
        case .both: return true
        case .fiveHour: return index == 0
        case .week: return index == 1
        }
    }
}

struct RefreshInterval {
    static func parse(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value == 0 || (10...86400).contains(value) else { return nil }
        return value
    }
}
