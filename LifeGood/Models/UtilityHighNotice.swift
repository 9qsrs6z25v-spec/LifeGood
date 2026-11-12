import Foundation

// MARK: - [v25.625] 水電 v6（util6）：「水電用得比較多時通知我」——要不要排、排什麼字、identifier（純函式）
//
// judge_utility.md C19「偏高通知」＋「使用者回答 C20」Q2（使用者原話：「要通知，可以寫房子名稱」）；
// radar/build/util6/brief.md；sim_util6.py 一個函式一個函式對照。這一版是唯一准加的一則本機通知。
//
// - 判斷**只沿用 v4**：UtilityTrendBuild.highAlerts（小圖說明行橘字 MoneyTone.warn 的那一支），門檻、公式一個字都不改。
//   只填金額、沒度數或計費期間、天數不到 20、標了估計／補繳／扣減、估計的下一期、沒有基準 → v4 本來就不判斷 → 不發。
// - 只看這間房子這一種「最新的一期」（帳本日期排的最後一筆）；舊期改了不發。賣掉的房子不發。
// - 字只有「一日拾樂這期用電比去年同期多，打開看看」這一種長相：**沒有金額、度數、每天幾度、百分比、表號、電號、地址、
//   任何數字**。房子名稱裡有 0–9、全形 ０–９、$、%（半形、全形）、其他寫法的數字或貨幣符號、像地址，或超過 20 個字 → 改寫「有一間房子」；
//   設定「通知裡不要出現房子名稱」開著也是。基準是最近幾期同季節（沒有去年同期）時寫「比前幾期多」。
// - 排在隔天 20:00（手機的時區）；identifier「utility.high.<房子>.<種類>.<那一期>」：同一期重存＝取代，
//   改成不偏高、刪掉那一期＝取消。同一間房子同一種 30 天內最多一則（UtilityHighNoticeLog，只存這台 UserDefaults、不同步、不進備份）。
// - 鎖定畫面、小工具、手錶錶面、靈動島、Shared/ 一個字都不加（通知本身由 iOS 顯示；iPhone 鎖著時系統會轉到手錶，字一樣）。
// - 這裡不碰通知中心、不碰任何 store；UtilityHighNoticeCenter.swift 才排、才取消。

/// 存了一期之後的判斷
enum UtilityHighVerdict: Equatable {
    /// 這一期不在了（刪了、別台刪了、房子刪了或賣了、算在別間）
    case gone
    /// 不是這間房子這一種最新的一期（舊期改了）
    case notLatest
    /// 是最新的一期，但 v4 沒判斷出偏高（沒度數、沒期間、標了、不到 20 天、沒有基準、沒多到門檻）
    case notHigh
    /// 是最新的一期、v4 判斷偏高；vsLastYear＝基準是去年同期（false＝最近幾期同季節）
    case high(vsLastYear: Bool)
}

/// 一則要排的通知（字已經組好；沒有任何數字）
struct UtilityHighNoticeJob: Equatable {
    /// 「utility.high.<房子 UUID>.<electricity|water|gas>.<那一期 UUID>」
    let identifier: String
    let title: String
    let body: String
    /// 隔天 20:00（手機的時區）
    let fireDate: Date
    let estateId: UUID
    /// 「electricity」「water」「gas」（不用 rawValue 的中文、不用 enum 字串插值）
    let typeCode: String
    let vsLastYear: Bool
}

/// 一間房子一種的紀錄（30 天最多一則用）
struct UtilityHighNoticeMemo: Codable, Equatable {
    /// 還在等的那一則
    var pendingId: String? = nil
    var pendingFire: Date? = nil
    /// 最近一則已經送出去的時間（排的時間到了就算送了）
    var lastFire: Date? = nil
}

/// 本機紀錄（UserDefaults.standard「utility_high_notice_log_v1」；不同步、不進備份）。key＝groupKey
struct UtilityHighNoticeLog: Codable, Equatable {
    var groups: [String: UtilityHighNoticeMemo] = [:]

    static let empty = UtilityHighNoticeLog()
}

/// 這一次要對通知中心做的事（先 remove 再 add）＋做完之後的紀錄
struct UtilityHighNoticePlan: Equatable {
    var remove: [String] = []
    var add: UtilityHighNoticeJob? = nil
    var log: UtilityHighNoticeLog = UtilityHighNoticeLog.empty
}

enum UtilityHighNotice {
    /// identifier 前綴（認得「哪些是水電通知排的」）
    static let prefix = "utility.high."
    /// 設定「水電用得比較多時通知我」（只這台；沒設過＝開）
    static let enabledKey = "utility_high_notice_enabled"
    /// 設定「通知裡不要出現房子名稱」（只這台；沒設過＝關）
    static let hideNameKey = "utility_high_notice_hide_name"
    /// 本機紀錄（UtilityHighNoticeLog 的 JSON）
    static let logKey = "utility_high_notice_log_v1"
    /// userInfo：點了開哪一間（房子 UUID 字串）
    static let estateInfoKey = "lg_utility_estate"
    /// userInfo：哪一種（typeCode）
    static let kindInfoKey = "lg_utility_kind"
    /// userInfo：基準（「lastYear」「recent」）；換「不要出現房子名稱」時重寫內文用
    static let partnerInfoKey = "lg_utility_vs"
    static let partnerLastYear = "lastYear"
    static let partnerRecent = "recent"
    /// 通知中心疊成一組
    static let threadId = "utility"
    /// 標題
    static let title = "水電瓦斯"
    /// 沒有名字可寫時
    static let someHouse = "有一間房子"
    /// 隔天幾點
    static let fireHour = 20
    /// 同一間房子同一種最少隔幾天
    static let minGapDays = 30
    /// 紀錄留多久（已經送了、沒有在等的那一則，超過就清掉）
    static let logKeepDays = 60
    /// 房子名稱最多幾個字（再長多半是地址，改寫「有一間房子」）
    static let maxNameLength = 20

    /// 沒設過＝開（UserDefaults.bool 對不存在的 key 回 false）
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// 沒設過＝關
    static var hidesName: Bool {
        UserDefaults.standard.object(forKey: hideNameKey) as? Bool ?? false
    }

    // MARK: identifier

    static func typeCode(_ t: UtilityType) -> String {
        switch t {
        case .electricity: return "electricity"
        case .water: return "water"
        case .gas: return "gas"
        }
    }

    static func kind(code: String) -> UtilityType? {
        switch code {
        case "electricity": return .electricity
        case "water": return .water
        case "gas": return .gas
        default: return nil
        }
    }

    /// 「utility.high.<房子>.」
    static func estatePrefix(_ estateId: UUID) -> String {
        prefix + estateId.uuidString + "."
    }

    /// 「utility.high.<房子>.<種類>.」（一間房子一種一組）
    static func groupKey(estateId: UUID, type t: UtilityType) -> String {
        estatePrefix(estateId) + typeCode(t) + "."
    }

    /// 「utility.high.<房子>.<種類>.<那一期>」
    static func identifier(estateId: UUID, type t: UtilityType, paymentId: UUID) -> String {
        groupKey(estateId: estateId, type: t) + paymentId.uuidString
    }

    /// identifier 拆回來；不是這個格式 nil
    static func parse(_ identifier: String) -> (estateId: UUID, type: UtilityType, paymentId: UUID)? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let rest = String(identifier.dropFirst(prefix.count))
        let parts: [Substring] = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let e = UUID(uuidString: String(parts[0])),
              let t = kind(code: String(parts[1])),
              let p = UUID(uuidString: String(parts[2])) else { return nil }
        return (estateId: e, type: t, paymentId: p)
    }

    /// 待發清單裡水電通知排的那幾則
    static func ours(_ pending: [String]) -> [String] {
        pending.filter { $0.hasPrefix(prefix) }
    }

    // MARK: 字（沒有任何數字）

    /// 「用電」「用水」「用瓦斯」
    static func usageWord(_ t: UtilityType) -> String {
        switch t {
        case .electricity: return "用電"
        case .water: return "用水"
        case .gas: return "用瓦斯"
        }
    }

    /// 通知裡寫的房子名稱：hide、空的、有數字／金額符號／百分比、像地址、超過 20 個字 → nil（寫「有一間房子」）
    static func shownName(_ raw: String?, hide: Bool) -> String? {
        guard !hide, let raw else { return nil }
        let oneLine: String = raw.components(separatedBy: .newlines).joined(separator: " ")
        let name: String = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maxNameLength else { return nil }
        for s in name.unicodeScalars where forbidden(s) {
            return nil
        }
        guard !looksLikeAddress(name) else { return nil }
        return name
    }

    /// 0–9、全形 ０–９、$、%、＄、％；[G1 補] 其他寫法的數字（①、²、Ⅲ、阿拉伯－印度數字…）、任何貨幣符號（¥、€、￥…）、
    /// ‰、‱、٪、﹪ 也算。國字數字（一、拾、〇）可以
    static func forbidden(_ s: Unicode.Scalar) -> Bool {
        let v: UInt32 = s.value
        if v >= 0x30 && v <= 0x39 { return true }
        if v >= 0xFF10 && v <= 0xFF19 { return true }
        if v == 0x24 || v == 0x25 || v == 0xFF04 || v == 0xFF05 { return true }
        if v == 0x2030 || v == 0x2031 || v == 0x066A || v == 0xFE6A { return true }
        if v == 0x3007 { return false }
        switch s.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber, .currencySymbol:
            return true
        default:
            return false
        }
    }

    /// [G1 補] 像地址（「仁愛路四段一號」「中山北路三段五巷」：國字數字的地址擋不到數字那一關）：
    /// 有「路」「街」「大道」「段」其中一個，又有「號」「巷」「弄」「樓」其中一個 → 不寫名字
    static func looksLikeAddress(_ name: String) -> Bool {
        let road: [String] = ["路", "街", "大道", "段"]
        let unit: [String] = ["號", "巷", "弄", "樓"]
        let hasRoad: Bool = road.contains(where: { name.contains($0) })
        let hasUnit: Bool = unit.contains(where: { name.contains($0) })
        return hasRoad && hasUnit
    }

    /// 「一日拾樂這期用電比去年同期多，打開看看」「有一間房子這期用水比前幾期多，打開看看」。name＝shownName 的結果
    static func body(name: String?, type t: UtilityType, vsLastYear: Bool) -> String {
        let who: String = name ?? someHouse
        let partner: String = vsLastYear ? "比去年同期多" : "比前幾期多"
        return "\(who)這期\(usageWord(t))\(partner)，打開看看"
    }

    /// 換了「不要出現房子名稱」：待發那則的新內文（identifier 認不得 nil）
    static func rewrittenBody(identifier: String, partner: String?, estateName: String?, hide: Bool) -> String? {
        guard let parsed = parse(identifier) else { return nil }
        let name: String? = shownName(estateName, hide: hide)
        return body(name: name, type: parsed.type, vsLastYear: partner == partnerLastYear)
    }

    // MARK: 判斷（只沿用 v4）

    /// 存了 paymentId 那一期之後：rows＝這間房子的水電列（HouseCardData.build 的 trendSource.rows.rows，已經照帳本日期排好）、
    /// asOf＝trendSource.asOf。偏高只認 UtilityTrendBuild.highAlerts（小圖橘字那一支），範圍跟小圖一樣（近 2 年）
    static func verdict(rows: [UtilityRow], paymentId: UUID, asOf: Date, isSold: Bool, cal: Calendar) -> UtilityHighVerdict {
        guard !isSold, let row = rows.last(where: { $0.paymentId == paymentId }), let t = row.type else { return .gone }
        let history: [UtilityRow] = rows.filter { $0.type == t }
        guard let latest = history.last, latest.key == row.key else { return .notLatest }
        let back: Date = cal.date(byAdding: .month, value: -UtilityTrendBuild.rangeMonths, to: asOf) ?? asOf
        let start: Date = cal.startOfDay(for: back)
        let mine: [UtilityRow] = history.filter { cal.startOfDay(for: $0.date) >= start }
        let alerts: [String: String] = UtilityTrendBuild.highAlerts(t, rows: mine, history: history,
                                                                    homeCharges: UtilityHomeCharges.empty, cal: cal)
        guard alerts[row.key] != nil else { return .notHigh }
        return .high(vsLastYear: baselineIsLastYear(row, history: history, cal: cal))
    }

    /// 偏高那期的基準是不是去年同期（跟 highAlerts／judge 同一張表、同一個週期、同一個 baseline；只拿來選字）
    static func baselineIsLastYear(_ row: UtilityRow, history: [UtilityRow], cal: Calendar) -> Bool {
        guard let m = row.meterId else { return false }
        let list: [UtilityRow] = history.filter { $0.meterAssigned && $0.meterId == m }
        guard let idx = list.firstIndex(where: { $0.key == row.key }) else { return false }
        let cycle: Int = UtilityMath.cycleDays(list.map { $0.date }, cal: cal)
        let facts: UtilityJudgeFacts = UtilityTrendBuild.judgeFacts(list, cycle: cycle, cal: cal)
        let ly: Int? = UtilityTrendBuild.lastYearIndex(at: idx, in: list, cycle: cycle, cal: cal)
        let b: UtilityBaseline? = UtilityTrendBuild.baseline(at: idx, lastYear: ly, values: facts.perDay, facts: facts)
        return b?.lastYear ?? false
    }

    // MARK: 排程

    /// 隔天 20:00（cal 的時區）
    static func fireDate(after now: Date, cal: Calendar) -> Date? {
        guard let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return cal.date(bySettingHour: fireHour, minute: 0, second: 0, of: next)
    }

    /// 這一組這次排不排得了：上一則送出到這一則 ≥ 30 個日曆日
    static func allowed(_ memo: UtilityHighNoticeMemo?, fire: Date, cal: Calendar) -> Bool {
        guard let last = memo?.lastFire else { return true }
        return UtilityMath.days(last, fire, cal: cal) >= minGapDays
    }

    /// 紀錄對齊現在：在等的那則時間到了＝送了（記成 lastFire）；時間還沒到、但待發清單裡沒有了＝被拿掉了（不算送了）；
    /// 已經送了、超過 60 天的清掉
    static func settled(_ log: UtilityHighNoticeLog, now: Date, pending: [String], cal: Calendar) -> UtilityHighNoticeLog {
        let live = Set(pending)
        var out = UtilityHighNoticeLog()
        for (k, m) in log.groups {
            var memo: UtilityHighNoticeMemo = m
            if let f = memo.pendingFire {
                if f <= now {
                    let last: Date = memo.lastFire ?? f
                    memo.lastFire = max(last, f)
                    memo.pendingId = nil
                    memo.pendingFire = nil
                } else if let pid = memo.pendingId, live.contains(pid) {
                    // 還在等
                } else {
                    memo.pendingId = nil
                    memo.pendingFire = nil
                }
            } else {
                memo.pendingId = nil
            }
            if memo.pendingId == nil, let last = memo.lastFire, UtilityMath.days(last, now, cal: cal) > logKeepDays {
                memo.lastFire = nil
            }
            if memo.pendingId != nil || memo.lastFire != nil {
                out.groups[k] = memo
            }
        }
        return out
    }

    /// 這幾則被拿掉了（還沒送）：紀錄裡在等的那則清掉，不算送了
    static func forgetting(_ ids: [String], in log: UtilityHighNoticeLog) -> UtilityHighNoticeLog {
        let gone = Set(ids)
        var out = UtilityHighNoticeLog()
        for (k, m) in log.groups {
            var memo: UtilityHighNoticeMemo = m
            if let pid = memo.pendingId, gone.contains(pid) {
                memo.pendingId = nil
                memo.pendingFire = nil
            }
            if memo.pendingId != nil || memo.lastFire != nil {
                out.groups[k] = memo
            }
        }
        return out
    }

    /// 存了（或刪了）一期之後要做的事。type＝存的那一種（刪的時候 nil）；shownName＝shownName 的結果；
    /// enabled＝設定「水電用得比較多時通知我」；pending＝現在待發清單的 identifier
    /// - 這一期自己的（不管哪一種：換了類型的舊那則也算）一律先拿掉
    /// - 最新的一期、不偏高：這間這一種還在等的（舊期的）也拿掉
    /// - 最新的一期、偏高、開著、30 天內沒送過：這間這一種還在等的換成這一則（同一期重存＝取代）
    static func plan(_ v: UtilityHighVerdict, estateId: UUID, paymentId: UUID, type t: UtilityType?,
                     shownName: String?, enabled: Bool, now: Date, cal: Calendar,
                     pending: [String], log given: UtilityHighNoticeLog) -> UtilityHighNoticePlan {
        let log: UtilityHighNoticeLog = settled(given, now: now, pending: pending, cal: cal)
        let ePrefix: String = estatePrefix(estateId)
        let tail: String = "." + paymentId.uuidString
        var remove: [String] = pending.filter { $0.hasPrefix(ePrefix) && $0.hasSuffix(tail) }
        var add: UtilityHighNoticeJob? = nil
        var addGroup: String? = nil
        if let t {
            let group: String = groupKey(estateId: estateId, type: t)
            let groupPending: [String] = pending.filter { $0.hasPrefix(group) }
            switch v {
            case .gone, .notLatest:
                break
            case .notHigh:
                remove += groupPending
            case .high(let vs):
                if enabled, let fire = fireDate(after: now, cal: cal), allowed(log.groups[group], fire: fire, cal: cal) {
                    remove += groupPending
                    let id: String = identifier(estateId: estateId, type: t, paymentId: paymentId)
                    let text: String = body(name: shownName, type: t, vsLastYear: vs)
                    add = UtilityHighNoticeJob(identifier: id, title: title, body: text, fireDate: fire,
                                               estateId: estateId, typeCode: typeCode(t), vsLastYear: vs)
                    addGroup = group
                }
            }
        }
        // 同一則要再排：不先拿掉（同一個 identifier 加進去就是取代）
        var seen = Set<String>()
        var unique: [String] = []
        for id in remove where id != add?.identifier {
            if seen.insert(id).inserted { unique.append(id) }
        }
        var next: UtilityHighNoticeLog = forgetting(unique, in: log)
        if let job = add, let group = addGroup {
            var memo: UtilityHighNoticeMemo = next.groups[group] ?? UtilityHighNoticeMemo()
            memo.pendingId = job.identifier
            memo.pendingFire = job.fireDate
            next.groups[group] = memo
        }
        return UtilityHighNoticePlan(remove: unique, add: add, log: next)
    }

    /// 回到前景：待發的水電通知，那一期已經不在了（刪了、別台刪了、換了種類、房子刪了或賣了）就拿掉
    static func stale(pending: [String], estates: [RealEstate]) -> [String] {
        let byId: [UUID: RealEstate] = Dictionary(estates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String] = []
        for id in ours(pending) {
            guard let p = parse(id), let re = byId[p.estateId], !re.isSold,
                  let payment = re.utilityPayments.first(where: { $0.id == p.paymentId }),
                  payment.type == p.type else {
                out.append(id)
                continue
            }
        }
        return out
    }
}
