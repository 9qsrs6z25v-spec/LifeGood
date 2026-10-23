import SwiftUI

// MARK: - [v25.575] 定期轉帳的畫面（transfer/judge.md §4.2、§4.4、§4.5、§4.6；transfer/build/v1a/brief.md §6 G4）
//
// 主控開檔（骨架：三張表單的名字、參數、外框已經定好，別組照這三個名字打開）；G4 實作裡面。
// • WealthTransferRuleForm：新增一條定期轉帳（要訂閱：打開的地方擋）。
// • WealthTransferRulePage：點一條彈出的規則頁（看不用訂閱；刪除要訂閱，裡面擋；〔結束〕不用）。
// • WealthTransferPeriodSheet：點一期彈出的小表單（不用訂閱：改這一期、這期不轉、沒轉成、今天補轉、復原都是記下銀行真的發生了什麼）。
// 打開的地方一律 .sheet(item:) { … .appStores() }；三張都自己掛 WealthPrivacyCurtain(armed: true)、presentationDetents。
// 數字一律讀 lifeStore.wealthFacts(expense:finance:)（transferRule／transferPeriods／transferPeriod／transferShortage），
// 不自己再算一份存摺上、夠不夠扣；寫 store 一律先 dismiss（或關掉小 sheet）、下一個 runloop 才叫 LifeStore（store 先抓進區域常數）。
//
// G4 實作（v1a；v1b 以後的〔從哪一期起改〕〔更早…〕〔暫停〕〔改金額或帳戶〕、表單提示與「轉完約剩」預覽都不在這裡）：
// • 新增表單：從（只列有台幣那一格的帳戶）、到（＋「不在 App 裡的人」帶去記帳新增固定支出，這裡什麼都不存）、每次轉多少（台幣到元）、
//   每月（1～31 日＋最後一天；29～31 多一列〔當月最後一天〕〔下個月 1 號〕）／每週（一…日）、從哪一期開始算（今天剛好是那一期：
//   兩邊今天都沒對過存摺＝兩選一、有一邊對過＝三選一，預設〔今天這期不算〕）、銀行那邊設到哪天（不設／到哪天／共幾次）、誰轉、名字、備註、
//   最下面「接下來：」三個日子。存檔：名字、備註像帳號先問〔只留後 4 碼〕→ 記帳裡像同一筆的一筆一筆問「是同一筆嗎？」→ dismiss → 下一個 runloop 寫。
// • 規則頁：頭（週期、金額、從 → 到、起訖）、還沒定下來的（沒轉成）→ 接下來 3 期 → 以前的（最近 6 期）→〔看更多〕；〔結束〕三個選項；
//   〔刪除這條定期轉帳〕（要訂閱；有以前的期問〔結束就好〕〔全部刪掉〕，影響照每個帳戶最近一次對存摺算）。
// • 一期小表單：照那一期的狀態給按鈕（judge §4.5、brief §6 G4 C 的表）；〔改這一期〕日子不能跨過前後一期、〔今天補轉〕不早於原本那天。
// • 遮住（財富頁右上眼睛）：規則頁、一期小表單的金額寫 ••••（新增表單是自己打的數字，照常顯示）。

// MARK: - 共用的字

/// 定期轉帳三張畫面共用的字（只在主執行緒叫）
private enum WealthTransferUIText {
    /// 「11/8（日）」；不是今年「2027/1/8（五）」
    static func day(_ d: Date, today: Date) -> String {
        let cal = WealthCal.calendar
        if cal.component(.year, from: d) == cal.component(.year, from: today) {
            return WealthFormat.monthDayWeek(d)
        }
        return WealthFormat.ymd(d) + "（" + WealthTransferText.weekdayName(d) + "）"
    }

    /// 「11/14」；不是今年「2027/1/8」
    static func shortDay(_ d: Date, today: Date) -> String {
        let cal = WealthCal.calendar
        if cal.component(.year, from: d) == cal.component(.year, from: today) {
            return WealthFormat.monthDay(d)
        }
        return WealthFormat.ymd(d)
    }

    /// 列上的金額「20,000」（遮住「••••」）
    static func amount(_ v: Double, code: String, masked: Bool) -> String {
        masked ? "••••" : WealthFormat.plain(v, code: code)
    }

    /// VoiceOver 的日子「11 月 6 日」
    static func spokenDay(_ d: Date) -> String {
        let c = WealthCal.calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }

    /// VoiceOver 的金額「20,000 元」（遮住「金額已遮住」）
    static func spokenAmount(_ v: Double, code: String, masked: Bool) -> String {
        masked ? "金額已遮住" : WealthFormat.plain(v, code: code) + " 元"
    }

    /// 帳戶「薪轉（台新銀行）」；沒有暱稱（名字就是銀行名）只寫一次；找不到＝fallback
    static func accountLabel(_ id: UUID?, fallback: String, facts: WealthFacts) -> String {
        guard let a = facts.account(id) else { return fallback }
        let bank = a.bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        if bank.isEmpty || bank == a.name { return a.name }
        return a.name + "（" + bank + "）"
    }
}

/// 一期的狀態字顏色（不用紅綠：紅綠在理財是漲跌）
private enum WealthTransferUITone {
    case normal, warn, strike, muted
}

/// 一期的狀態字（規則頁每一列、一期小表單的頭共用；brief §6 G4 B-3）
private struct WealthTransferUIStatus {
    let text: String
    let tone: WealthTransferUITone
    /// 預計那期轉完會不夠：橘字「可能轉不過去」（自己轉的「轉之前要先補錢」）
    let warn: String?

    static func of(_ p: WealthTransferPeriod, manual: Bool, short: Bool, today: Date) -> WealthTransferUIStatus {
        // 還沒到、轉完會不夠：橘字（補轉排在以後的也一樣）
        let w: String? = (short && p.state == .planned) ? (manual ? "轉之前要先補錢" : "可能轉不過去") : nil
        if p.status == .redo && (p.state == .planned || p.state == .done) {
            let text = "沒轉成・" + WealthTransferUIText.shortDay(p.day, today: today) + " 補轉"
            return WealthTransferUIStatus(text: text, tone: .normal, warn: w)
        }
        switch p.state {
        case .planned:
            return WealthTransferUIStatus(text: p.edited ? "預計・這期改過" : "預計", tone: .normal, warn: w)
        case .done:
            return WealthTransferUIStatus(text: p.edited ? "已轉・這期改過" : "已轉", tone: .normal, warn: nil)
        case .skipped:
            return WealthTransferUIStatus(text: "這期不轉", tone: .strike, warn: nil)
        case .failed:
            return WealthTransferUIStatus(text: "沒轉成", tone: .warn, warn: nil)
        case .paused:
            return WealthTransferUIStatus(text: "暫停", tone: .muted, warn: nil)
        case .broken:
            return WealthTransferUIStatus(text: "帳戶找不到，不算", tone: .muted, warn: nil)
        }
    }

    /// 一行寫完「預計・可能轉不過去」
    var line: String {
        guard let w = warn else { return text }
        return text + "・" + w
    }

    var spoken: String {
        guard let w = warn else { return text }
        return text + "，" + w
    }

    var color: Color {
        switch tone {
        case .normal, .strike, .muted: return Color.secondary
        case .warn: return Color.orange
        }
    }
}

/// 規則頁一列＝一期
private struct WealthTransferUIRow: Identifiable {
    /// 那一期原本的日子「2026-11-06」
    let key: String
    let dayText: String
    let amountText: String
    let status: WealthTransferUIStatus
    let spoken: String

    var id: String { key }

    static func make(_ p: WealthTransferPeriod, facts: WealthFacts, manual: Bool, masked: Bool) -> WealthTransferUIRow {
        let today = facts.today
        let short: Bool = p.state == .planned && facts.transferShortage(p.ruleId, key: p.key) != nil
        let st = WealthTransferUIStatus.of(p, manual: manual, short: short, today: today)
        let spoken = WealthTransferUIText.spokenDay(p.day) + "，"
            + WealthTransferUIText.spokenAmount(p.amount, code: p.fromCode, masked: masked) + "，" + st.spoken
        return WealthTransferUIRow(key: p.key, dayText: WealthTransferUIText.day(p.day, today: today),
                                   amountText: WealthTransferUIText.amount(p.amount, code: p.fromCode, masked: masked),
                                   status: st, spoken: spoken)
    }
}

/// 一列：日子、金額、狀態字
private struct WealthTransferUIRowView: View {
    let row: WealthTransferUIRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.dayText)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            Text(row.amountText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.primary)
            WealthTransferUIStatusLabel(status: row.status)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
        .accessibilityAddTraits(.isButton)
    }
}

/// 狀態字（這期不轉＝刪除線；可能轉不過去＝第二行橘字）
private struct WealthTransferUIStatusLabel: View {
    let status: WealthTransferUIStatus

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(status.text)
                .strikethrough(status.tone == .strike)
                .font(.caption)
                .foregroundStyle(status.color)
            if let w = status.warn {
                Text(w)
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
        .frame(minWidth: 64, alignment: .trailing)
    }
}

/// 一期小表單、規則頁的一顆按鈕（右邊灰字說明；〔看整條〕帶 ›）
private struct WealthTransferUIActionRow: View {
    let title: String
    var detail: String? = nil
    var chevron: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                if let d = detail {
                    Text(d)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
    }
}

/// 新增表單「今天剛好是那一期」的一個選項（一列一顆，Form 一列裡不放兩顆按鈕）
private struct WealthTransferUIChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 新增表單〔共幾次〕那一列：打數字或按 ±（1～240）
private struct WealthTransferUITimesRow: View {
    @Binding var text: String

    private var value: Binding<Int> {
        Binding(get: { Swift.min(Swift.max(Int(self.text) ?? 1, 1), 240) },
                set: { self.text = String($0) })
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("共幾次")
            Spacer(minLength: 8)
            TextField("12", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
            Text("次")
                .foregroundStyle(Color.secondary)
            Stepper("共幾次", value: value, in: 1...240)
                .labelsHidden()
        }
    }
}

/// 名字、備註像帳號：〔只留後 4 碼〕〔不是帳號，照存〕（judge §4.2、§4.12；樣稿②-8 b）
private struct WealthTransferUIAccountAsk: ViewModifier {
    @Binding var tail: String?
    let onMask: () -> Void
    let onKeep: () -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { self.tail != nil }, set: { if !$0 { self.tail = nil } })
    }

    private var message: String {
        "結尾 " + (tail ?? "") + "。App 不存完整帳號。"
    }

    func body(content: Content) -> some View {
        content.alert("這串數字看起來像帳號", isPresented: isPresented) {
            Button("只留後 4 碼") { onMask() }
            Button("不是帳號，照存") { onKeep() }
        } message: {
            Text(message)
        }
    }
}

// MARK: - A. 新增表單

/// 「到」選單的一項
private enum WealthTransferUITarget: Hashable {
    /// 還沒選
    case unpicked
    case account(UUID)
    /// 不在 App 裡的人（家人、房東…）：帶去記帳新增固定支出
    case outside
}

/// 今天剛好是那一期：算不算
private enum WealthTransferUITodayChoice: Hashable {
    /// 今天這期不算（從下一期起）——預設
    case skip
    /// 今天這期要算／存摺上已經有了
    case count
    /// 還沒，今天會轉（今天對過存摺的那一邊記 late）
    case late
}

/// 銀行那邊設到哪天
private enum WealthTransferUIEnd: Hashable {
    case noEnd, byDate, byCount
}

/// 記帳那筆「是同一筆嗎？」的答案
private enum WealthTransferUIAnswer {
    /// 是：記帳那筆從下一期起結束（收入：從下個月起結束）
    case endItem
    /// 是，但記帳照記（那筆加進「這筆不算」）
    case keepButExclude
    /// 不是，兩筆都要（關掉也是）
    case keepBoth
}

/// 帶去記帳新增固定支出（巢狀 sheet 的 item）
private struct WealthTransferUIExpenseAsk: Identifiable {
    let id = UUID()
    let preset: AddExpensePreset
}

/// 存檔時「記帳裡的『轉玉山存錢』…跟這條是同一筆嗎？」（一次問一筆；樣稿②-8 a）
private struct WealthTransferUIMatchDialog: ViewModifier {
    let asking: WealthTransferMatch?
    /// 每期多少「20,000」（固定支出那句小字用）
    let amountText: String
    let onAnswer: (WealthTransferMatch, WealthTransferUIAnswer) -> Void
    let onClose: () -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { self.asking != nil }, set: { if !$0 { self.onClose() } })
    }

    private func message(_ m: WealthTransferMatch) -> String? {
        guard m.kind == .expense else { return nil }
        return "本月還能花每月會多 " + amountText + "——那是你存起來的錢，不是多出來能花的"
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(asking?.question ?? "", isPresented: isPresented,
                                   titleVisibility: .visible, presenting: asking) { m in
            if m.kind == .expense {
                Button("是：記帳那筆從下一期起結束") { onAnswer(m, .endItem) }
                Button("是，但記帳照記（還能花先扣掉）") { onAnswer(m, .keepButExclude) }
                Button("不是，兩筆都要") { onAnswer(m, .keepBoth) }
            } else {
                Button("是：那筆收入從下個月起結束") { onAnswer(m, .endItem) }
                Button("不是") { onAnswer(m, .keepBoth) }
            }
            Button("取消", role: .cancel) { onAnswer(m, .keepBoth) }
        } message: { m in
            if let line = message(m) {
                Text(line)
            }
        }
    }
}

/// 新增一條定期轉帳。fromId：「從」帶好這個帳戶（nil＝WealthFacts.defaultTransferFromId：月薪入帳的那個帳戶）
struct WealthTransferRuleForm: View {
    var fromId: UUID? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var loaded = false
    /// 今天 00:00（打開時從 facts 抓一次）
    @State private var today: Date = WealthCal.day(Date())
    /// 「從」「到」可以選的（沒收起來的銀行、含定存帳戶；v1 只列有台幣那一格的）
    @State private var choices: [WealthFormAccountChoice] = []
    /// 有被濾掉的外幣帳戶（選單下面一行小字）
    @State private var hidesForeign = false
    /// 今天對過存摺的帳戶（今天剛好是那一期：兩選一或三選一）
    @State private var anchoredToday: Set<UUID> = []
    @State private var from: UUID?
    @State private var target: WealthTransferUITarget = .unpicked
    @State private var amountText = ""
    @State private var cycle: WealthTransferCycle = .monthly
    /// 每月幾日 1～31；32＝最後一天（存 day 31、short nil）
    @State private var monthDay = 1
    /// 選 29～31 日：沒有這天的月份〔下個月 1 號〕（false＝〔當月最後一天〕）
    @State private var shortNext = false
    /// 每週星期幾（Calendar 的 1 日…7 六）
    @State private var weekday = 1
    @State private var todayChoice: WealthTransferUITodayChoice = .skip
    @State private var endMode: WealthTransferUIEnd = .noEnd
    @State private var endDate = Date()
    @State private var timesText = "12"
    @State private var manual = false
    @State private var name = ""
    @State private var memo = ""
    @State private var isSaving = false
    /// 名字、備註像帳號的那串數字的後 4 碼（存檔前先問）
    @State private var accountTail: String?
    /// 組好、還沒存的那一條（問「是同一筆嗎？」的時候放這裡）
    @State private var pendingRule: WealthTransferRule?
    @State private var matchQueue: [WealthTransferMatch] = []
    @State private var asking: WealthTransferMatch?
    @State private var endExpenses: [WealthTransferMatch] = []
    @State private var endIncomes: [WealthTransferMatch] = []
    @State private var excludeExpenses: [UUID] = []
    @State private var expenseAsk: WealthTransferUIExpenseAsk?

    /// 每週〔一〕…〔日〕（Calendar 的 weekday）
    private static let weekdayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]
    private static let weekdayNames: [String] = ["日", "一", "二", "三", "四", "五", "六"]

    // MARK: 算出來的（打字不重算 facts，只算日子）

    private var tomorrow: Date { WealthCal.addDays(1, to: today) }

    private var toId: UUID? {
        if case .account(let id) = target { return id }
        return nil
    }

    private var isOutside: Bool { target == .outside }

    private var toChoices: [WealthFormAccountChoice] { choices.filter { $0.id != from } }

    private func choiceName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return choices.first { $0.id == id }?.name
    }

    /// 每次轉多少（台幣到元；< 1 元＝nil）
    private var amountValue: Double? {
        guard let v = WealthFormText.number(amountText) else { return nil }
        let r = v.rounded()
        return r >= 1 ? r : nil
    }

    private var storedDay: Int { Swift.min(Swift.max(monthDay, 1), 31) }

    private var showsShortRow: Bool { cycle == .monthly && monthDay >= 29 && monthDay <= 31 }

    private var storedShort: String? { (showsShortRow && shortNext) ? "next" : nil }

    private func firstPeriod(onOrAfter d: Date) -> Date? {
        WealthTransferSchedule.firstDate(cycle: cycle, day: storedDay, short: storedShort, weekday: weekday,
                                         onOrAfter: d)
    }

    /// 照週期、哪天：今天（含）以後第一期
    private var firstFromToday: Date? { firstPeriod(onOrAfter: today) }

    private var todayIsPeriod: Bool {
        guard let d = firstFromToday else { return false }
        return WealthCal.dayKey(d) == WealthCal.dayKey(today)
    }

    /// 今天這期不算時的下一期
    private var nextAfterToday: Date? { firstPeriod(onOrAfter: tomorrow) }

    private var fromAnchored: Bool {
        guard let f = from else { return false }
        return anchoredToday.contains(f)
    }

    private var toAnchored: Bool {
        guard let t = toId else { return false }
        return anchoredToday.contains(t)
    }

    /// 有一邊今天對過存摺＝三選一
    private var threeChoice: Bool { fromAnchored || toAnchored }

    /// 第一期（存成 startKey）：今天剛好是那一期，選〔不算〕＝下一期
    private var startDay: Date? {
        if todayIsPeriod {
            return todayChoice == .skip ? nextAfterToday : today
        }
        return firstFromToday
    }

    /// 只有日子的規則（設到哪天、接下來三個日子用；還沒選帳戶也算得出來）
    private var scheduleRule: WealthTransferRule? {
        guard let s = startDay else { return nil }
        let monthly = cycle == .monthly
        return WealthTransferRule(cycle: cycle.rawValue, day: monthly ? storedDay : nil,
                                  short: monthly ? storedShort : nil,
                                  startKey: WealthTransferSchedule.key(of: s))
    }

    private var timesValue: Int {
        let n = Int(timesText.trimmingCharacters(in: .whitespaces)) ?? 1
        return Swift.min(Swift.max(n, 1), 240)
    }

    /// 銀行設到哪天換成的最後一期（不設＝nil；〔到哪天〕比第一期早也是 nil，見 endInvalid）
    private var lastPeriod: Date? {
        guard let r = scheduleRule else { return nil }
        switch endMode {
        case .noEnd: return nil
        case .byDate: return WealthTransferSchedule.lastDate(r, onOrBefore: endDate)
        case .byCount: return WealthTransferSchedule.nthDate(r, times: timesValue)
        }
    }

    /// 〔到哪天〕比第一期早（擋存檔＋紅字）
    private var endInvalid: Bool { endMode == .byDate && scheduleRule != nil && lastPeriod == nil }

    /// 「共 24 次：最後一次 2027/4/9（五）」
    private var endLine: String? {
        guard endMode != .noEnd else { return nil }
        if endInvalid { return "比第一期還早：請選第一期以後的日子" }
        guard var r = scheduleRule, let last = lastPeriod else { return nil }
        r.endKey = WealthTransferSchedule.key(of: last)
        let n = WealthTransferSchedule.originalDates(r, through: last).count
        return "共 \(n) 次：最後一次 " + WealthTransferUIText.day(last, today: today)
    }

    /// 最下面「接下來：11/8（日）、12/8（二）、2027/1/8（五）」
    private var previewLine: String? {
        guard var r = scheduleRule else { return nil }
        if let last = lastPeriod { r.endKey = WealthTransferSchedule.key(of: last) }
        let list = WealthTransferSchedule.originalDates(r, through: WealthCal.addDays(400, to: today))
        let texts: [String] = list.prefix(3).map { WealthTransferUIText.day($0, today: today) }
        guard !texts.isEmpty else { return nil }
        return "接下來：" + texts.joined(separator: "、")
    }

    private var saveDisabled: Bool {
        guard let f = from, let t = toId, f != t, amountValue != nil, startDay != nil else { return true }
        return endInvalid
    }

    private var namePlaceholder: String {
        (choiceName(from) ?? "薪轉") + " → " + (choiceName(toId) ?? "房貸扣款")
    }

    private var todayQuestion: String {
        let d = WealthFormat.monthDay(today)
        if cycle == .weekly {
            return "今天（\(d)）剛好是週" + WealthTransferText.weekdayName(today) + "，這期呢？"
        }
        return "今天（\(d)）剛好是轉帳那天，這期呢？"
    }

    /// 「薪轉、零用錢今天都對過存摺」（三選一才有）
    private var todayFooter: String? {
        guard threeChoice else { return nil }
        var names: [String] = []
        if fromAnchored, let n = choiceName(from) { names.append(n) }
        if toAnchored, let n = choiceName(toId) { names.append(n) }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: "、") + (names.count > 1 ? "今天都對過存摺" : "今天對過存摺")
    }

    /// 〔今天這期不算（從下一期 10/30 起）〕
    private var skipLabel: String {
        guard let n = nextAfterToday else { return "今天這期不算（從下一期起）" }
        return "今天這期不算（從下一期 " + WealthTransferUIText.shortDay(n, today: today) + " 起）"
    }

    private var startText: String {
        guard let s = startDay else { return "—" }
        let t = WealthTransferUIText.day(s, today: today)
        return WealthCal.dayKey(s) == WealthCal.dayKey(today) ? "今天 " + t : t
    }

    private var outsideText: String {
        if cycle == .weekly {
            return "記帳的固定支出沒有每週：請改每月，或把對方的帳戶也加進 App"
        }
        let f = choiceName(from) ?? "轉出的帳戶"
        return "轉給家人、房東是花掉的錢，請記在記帳的固定支出（從 " + f + " 扣），這樣本月還能花、稅務才對。"
            + "記帳的固定支出會照記帳的顯示設定出現在小工具『接下來要繳』和手錶（主畫面小工具照隱藏金額）。"
    }

    private var footerText: String {
        if isOutside { return "這裡什麼都不存。" }
        return "App 不會幫你轉錢，只照你在銀行的設定算進兩個帳戶。銀行那邊改了，這裡也要改。"
    }

    private var amountForDialog: String {
        WealthFormat.grouped(amountValue ?? 0, decimals: 0)
    }

    // MARK: 畫面

    var body: some View {
        NavigationStack {
            Form {
                accountsSection
                amountSection
                cycleSection
                if isOutside {
                    outsideSection
                } else {
                    if todayIsPeriod {
                        todaySection
                    }
                    startSection
                    endSection
                    whoSection
                    nameSection
                    previewSection
                }
                footerSection
            }
            .navigationTitle("新增定期轉帳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "存檔", isSaving: isSaving, disabled: saveDisabled,
                                  onCancel: { dismiss() }, onSave: { requestSave() })
            }
            .modifier(WealthTransferUIAccountAsk(tail: $accountTail,
                                                 onMask: { proceed(mask: true) },
                                                 onKeep: { proceed(mask: false) }))
            .modifier(WealthTransferUIMatchDialog(asking: asking, amountText: amountForDialog,
                                                  onAnswer: { m, a in answer(m, a) },
                                                  onClose: { closeAsk() }))
            .sheet(item: $expenseAsk, onDismiss: { closeAfterExpense() }) { ask in
                AddExpenseView(expenseType: .fixed, preset: ask.preset)
                    .modifier(WealthPrivacyCurtain(armed: true))
                    .appStores()
            }
            .onAppear { load() }
            .onChange(of: from) { _, _ in fromChanged() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var accountsSection: some View {
        Section {
            Picker("從", selection: $from) {
                ForEach(choices) { c in
                    Text(c.label).tag(c.id as UUID?)
                }
            }
            Picker("到", selection: $target) {
                Text("選一個").tag(WealthTransferUITarget.unpicked)
                ForEach(toChoices) { c in
                    Text(c.label).tag(WealthTransferUITarget.account(c.id))
                }
                Text("不在 App 裡的人（家人、房東…）").tag(WealthTransferUITarget.outside)
            }
        } header: {
            WealthFormHeader(title: "從哪轉到哪", icon: "arrow.left.arrow.right", color: .blue)
        } footer: {
            if hidesForeign {
                Text("外幣帳戶之後的版本才能選")
            }
        }
    }

    private var amountSection: some View {
        Section {
            HStack {
                Text("NT$").foregroundStyle(Color.secondary)
                TextField("每次轉多少", text: $amountText)
                    .keyboardType(.numberPad)
            }
        } header: {
            WealthFormHeader(title: "每次轉多少", icon: "dollarsign.circle", color: .blue)
        }
    }

    private var cycleSection: some View {
        Section {
            Picker("多久一次", selection: $cycle) {
                Text("每月").tag(WealthTransferCycle.monthly)
                Text("每週").tag(WealthTransferCycle.weekly)
            }
            .pickerStyle(.segmented)
            if cycle == .monthly {
                monthDayRows
            } else {
                Picker("星期幾", selection: $weekday) {
                    ForEach(Self.weekdayOrder, id: \.self) { w in
                        Text(Self.weekdayNames[w - 1]).tag(w)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            WealthFormHeader(title: "多久一次、哪天", icon: "calendar", color: .blue)
        } footer: {
            if showsShortRow {
                Text("玉山、郵局是當月最後一天；國泰世華是下個月 1 號（11 月那期會在 12/1）")
            }
        }
    }

    @ViewBuilder
    private var monthDayRows: some View {
        Picker("每月幾日", selection: $monthDay) {
            ForEach(1...31, id: \.self) { d in
                Text("\(d) 日").tag(d)
            }
            Text("最後一天").tag(32)
        }
        if showsShortRow {
            Picker("沒有這天的月份", selection: $shortNext) {
                Text("當月最後一天").tag(false)
                Text("下個月 1 號").tag(true)
            }
        }
    }

    private var outsideSection: some View {
        Section {
            Text(outsideText)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if cycle == .monthly {
                Button("給家人（孝親費）") { openExpense(.other) }
                Button("付房租（報稅可扣）") { openExpense(.rent) }
                Button("其他") { openExpense(.other) }
            }
        } header: {
            WealthFormHeader(title: "轉給不在 App 裡的人", icon: "person.2", color: .orange)
        }
    }

    private var todaySection: some View {
        Section {
            if threeChoice {
                WealthTransferUIChoiceRow(title: "存摺上已經有了", selected: todayChoice == .count) {
                    todayChoice = .count
                }
                WealthTransferUIChoiceRow(title: "還沒，今天會轉", selected: todayChoice == .late) {
                    todayChoice = .late
                }
            } else {
                WealthTransferUIChoiceRow(title: "今天這期要算（已經轉了，或今天晚點會轉）",
                                          selected: todayChoice != .skip) {
                    todayChoice = .count
                }
            }
            WealthTransferUIChoiceRow(title: skipLabel, selected: todayChoice == .skip) {
                todayChoice = .skip
            }
        } header: {
            Text(todayQuestion)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .textCase(nil)
        } footer: {
            if let line = todayFooter {
                Text(line)
            }
        }
    }

    private var startSection: some View {
        Section {
            HStack {
                Text(todayIsPeriod ? "第一期" : "下一期")
                Spacer(minLength: 8)
                Text(startText)
                    .foregroundStyle(Color.accentColor)
            }
        } header: {
            WealthFormHeader(title: "從哪一期開始算進 App", icon: "flag", color: .blue)
        } footer: {
            Text("今天以前的期不算，不會一次多出好幾期。")
        }
    }

    private var endSection: some View {
        Section {
            Picker("銀行那邊設到哪天", selection: $endMode) {
                Text("不設").tag(WealthTransferUIEnd.noEnd)
                Text("到哪天").tag(WealthTransferUIEnd.byDate)
                Text("共幾次").tag(WealthTransferUIEnd.byCount)
            }
            .pickerStyle(.segmented)
            if endMode == .byDate {
                DatePicker("到哪天", selection: $endDate, in: today..., displayedComponents: .date)
            } else if endMode == .byCount {
                WealthTransferUITimesRow(text: $timesText)
            }
            if let line = endLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(endInvalid ? Color.red : Color.secondary)
            }
        } header: {
            WealthFormHeader(title: "銀行那邊設到哪天", icon: "calendar.badge.clock", color: .blue)
        } footer: {
            Text("銀行的預約轉帳多半有期限（玉山 1 年、上海商銀最多 12 筆…）")
        }
    }

    private var whoSection: some View {
        Section {
            Picker("誰轉", selection: $manual) {
                Text("銀行會自動轉").tag(false)
                Text("我自己轉").tag(true)
            }
            .pickerStyle(.segmented)
        } header: {
            WealthFormHeader(title: "誰轉", icon: "person", color: .blue)
        } footer: {
            Text("現在一律當作那天轉了；之後的版本起，自己轉的那天早上 9 點會提醒你")
        }
    }

    private var nameSection: some View {
        Section {
            HStack(spacing: 8) {
                Text("名字")
                TextField(namePlaceholder, text: $name)
                    .multilineTextAlignment(.trailing)
            }
            TextField("備註（選填）", text: $memo)
        } header: {
            WealthFormHeader(title: "名字、備註（選填）", icon: "text.alignleft", color: .blue)
        } footer: {
            Text("別打完整帳號")
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let line = previewLine {
            Section {
                Text(line)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footerSection: some View {
        Section {
            Text(footerText)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
        }
    }

    // MARK: 帶入

    private func load() {
        guard !loaded else { return }
        loaded = true
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let t = facts.today
        today = t
        // v1 只列有台幣那一格的帳戶（只有外幣的帳戶選了會多長出一格台幣）
        let all = WealthFormAccountChoice.banks(facts, including: fromId, includeFixed: true)
        let ntd = all.filter { $0.codes.contains("NT$") }
        choices = ntd
        hidesForeign = all.count > ntd.count
        let todayKey = WealthCal.dayKey(t)
        var anchored = Set<UUID>()
        for a in facts.banks {
            if let d = a.lastAnchorDate, WealthCal.dayKey(d) == todayKey { anchored.insert(a.id) }
        }
        anchoredToday = anchored
        // 帶進來的帳戶 → 月薪入帳的那個（defaultTransferFromId）→ 第一個；帶進來的是只有外幣的帳戶（被濾掉）時照樣往下找
        let wanted: [UUID] = [fromId, facts.defaultTransferFromId].compactMap { $0 }
        from = wanted.first(where: { w in ntd.contains(where: { $0.id == w }) }) ?? ntd.first?.id
        let cal = WealthCal.calendar
        monthDay = cal.component(.day, from: t)
        weekday = cal.component(.weekday, from: t)
        endDate = WealthCal.addMonths(12, to: t)
    }

    /// 換了「從」：跟「到」同一個帳戶就把「到」清掉
    private func fromChanged() {
        if let f = from, toId == f { target = .unpicked }
    }

    // MARK: 不在 App 裡的人：帶去記帳

    /// 〔給家人（孝親費）〕〔付房租（報稅可扣）〕〔其他〕：記帳新增固定支出（每月、日子、扣款帳戶、金額帶好；名稱空著）
    private func openExpense(_ category: FixedCategory) {
        let preset = AddExpensePreset(fixedCategory: category, recurrence: .monthly, date: firstFromToday,
                                      paymentBankId: from, amount: amountValue)
        expenseAsk = WealthTransferUIExpenseAsk(preset: preset)
    }

    /// 記帳那張關掉（存了或取消）：這張表一起關
    private func closeAfterExpense() {
        let close = dismiss
        DispatchQueue.main.async { close() }
    }

    // MARK: 存檔

    /// 組好要存的那一條（name、memo 已經去空白、遮好；空＝nil）
    private func makeRule(name: String?, memo: String?) -> WealthTransferRule? {
        guard var r = scheduleRule, let f = from, let t = toId, f != t, let v = amountValue, !endInvalid else {
            return nil
        }
        r.mode = manual ? "manual" : nil
        r.segments = [WealthTransferSegment(fromKey: "", fromId: f, toId: t, amount: v)]
        r.name = name
        r.memo = memo
        if let last = lastPeriod { r.endKey = WealthTransferSchedule.key(of: last) }
        // 〔還沒，今天會轉〕：今天這期算，今天對過存摺的那一邊排在對存摺後面
        if todayIsPeriod && todayChoice == .late && threeChoice {
            let k = WealthTransferSchedule.key(of: today)
            r.notes = [k: WealthTransferNote(lateOut: fromAnchored ? true : nil,
                                             lateIn: toAnchored ? true : nil,
                                             updatedAt: Date())]
        }
        return r
    }

    /// 存檔鈕：名字、備註有像帳號的數字先問；沒有就往下走
    private func requestSave() {
        guard !isSaving, !saveDisabled else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tail = WealthTransferText.accountLikeTail(n) ?? WealthTransferText.accountLikeTail(m) {
            accountTail = tail
            return
        }
        proceed(mask: false)
    }

    /// mask：〔只留後 4 碼〕＝名字、備註裡像帳號的每一串換成「••8901」。接著找記帳裡像同一筆的，一筆一筆問
    private func proceed(mask: Bool) {
        guard !isSaving else { return }
        let n0 = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let m0 = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = mask ? WealthTransferText.maskAccountLike(n0) : n0
        let m = mask ? WealthTransferText.maskAccountLike(m0) : m0
        guard let rule = makeRule(name: n.isEmpty ? nil : n, memo: m.isEmpty ? nil : m) else { return }
        isSaving = true
        if mask {
            name = n
            memo = m
        }
        pendingRule = rule
        endExpenses = []
        endIncomes = []
        excludeExpenses = []
        let found = WealthTransferMatcher.matches(
            rule: rule, fromName: choiceName(from) ?? "別的帳戶", toName: choiceName(toId) ?? "別的帳戶",
            expenses: expenseStore.expenses, incomes: expenseStore.incomes,
            excluded: Set(lifeStore.wealthBook.excludedExpenses ?? []))
        matchQueue = found
        askNext()
    }

    /// 下一筆要問的（等上一個框收好再跳）；問完了就存
    private func askNext() {
        guard !matchQueue.isEmpty else {
            finish()
            return
        }
        let next = matchQueue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.asking = next
        }
    }

    /// 「是同一筆嗎？」的一顆按鈕
    private func answer(_ m: WealthTransferMatch, _ a: WealthTransferUIAnswer) {
        guard asking?.id == m.id else { return }
        switch a {
        case .endItem:
            if m.kind == .expense {
                endExpenses.append(m)
            } else {
                endIncomes.append(m)
            }
        case .keepButExclude:
            excludeExpenses.append(m.itemId)
        case .keepBoth:
            break
        }
        asking = nil
        askNext()
    }

    /// 框被關掉（沒按任何一顆）＝兩筆都留、照存
    private func closeAsk() {
        guard let m = asking else { return }
        DispatchQueue.main.async {
            if self.asking?.id == m.id { self.answer(m, .keepBoth) }
        }
    }

    /// 先關表單，下一個 runloop 才寫：存規則＋「是同一筆嗎？」答〔是〕的那幾筆
    private func finish() {
        guard let rule = pendingRule else { return }
        pendingRule = nil
        let life = lifeStore
        let expense = expenseStore
        let ends: [WealthTransferMatch] = endExpenses
        let incomes: [WealthTransferMatch] = endIncomes
        let excluded: [UUID] = excludeExpenses
        dismiss()
        DispatchQueue.main.async {
            life.saveTransferRule(rule)
            for m in ends {
                life.endRecurring(expenseIds: [m.itemId], on: m.endDay, expense: expense)
            }
            for id in excluded {
                life.excludeExpenseFromWealth(id)
            }
            for m in incomes {
                life.endRecurringIncome(m.itemId, on: m.endDay, expense: expense)
            }
        }
    }
}

// MARK: - B. 規則頁

/// 規則頁點一期（巢狀 sheet 的 item）
private struct WealthTransferUIPeriodPick: Identifiable {
    let key: String
    var id: String { key }
}

/// 規則頁的確認框：〔結束〕或〔刪除〕（一個畫面一個 confirmationDialog）
private enum WealthTransferUIRuleAsk: Identifiable {
    case end, delete
    var id: Int { self == .end ? 0 : 1 }
}

/// 規則頁要畫的（一次從 facts 組好；body 只畫）
private struct WealthTransferUIRuleModel {
    /// 你取的名字；空＝「薪轉 → 存錢」
    let title: String
    /// 「每月 6 日」
    let cycleText: String
    /// 「NT$20,000」（遮住 NT$ ••••）
    let amountText: String
    /// 「薪轉（台新）→ 存錢（玉山）・銀行會自動轉」
    let accountsLine: String
    /// 「2026/11/6 起・沒有設結束日」／「已結束：最後一次 2026/12/6」
    let rangeLine: String
    let memo: String?
    let isRunning: Bool
    let pending: [WealthTransferUIRow]
    let upcoming: [WealthTransferUIRow]
    let past: [WealthTransferUIRow]
    let hasMore: Bool
    /// 〔結束〕：今天（含）以前最近一期、下一期
    let lastPastKey: String?
    let lastPastLabel: String
    let nextKey: String?
    let nextLabel: String
    /// 〔刪除〕：以前算進去的期數、全部刪掉的影響
    let pastCount: Int
    let deleteMessage: String
    let spoken: String

    static func make(facts: WealthFacts, ruleId: UUID, masked: Bool, showMore: Bool) -> WealthTransferUIRuleModel? {
        guard let t = facts.transferRule(ruleId) else { return nil }
        let today = facts.today
        let periods = facts.transferPeriods(ruleId, through: WealthCal.addDays(400, to: today))
        let manual = t.isManual
        // 還沒定下來的：過了日子、沒轉成（最近 6 期，新到舊）
        let failedList: [WealthTransferPeriod] = periods.filter { $0.state == .failed && $0.original <= today }
        let pendingList: [WealthTransferPeriod] = Array(failedList.reversed().prefix(6))
        let pendingKeys = Set(pendingList.map { $0.key })
        // 接下來：實際那天在今天以後（含這期不轉的）
        let futureAll: [WealthTransferPeriod] = periods
            .filter { $0.day > today && !pendingKeys.contains($0.key) }
            .sorted { $0.day < $1.day }
        let futureKeys = Set(futureAll.map { $0.key })
        // 以前的：其他今天（含）以前的，新到舊
        let pastAll: [WealthTransferPeriod] = periods
            .filter { !pendingKeys.contains($0.key) && !futureKeys.contains($0.key) && ($0.original <= today || $0.day <= today) }
            .sorted { $0.day > $1.day }
        let upLimit = showMore ? 15 : 3
        let pastLimit = showMore ? 18 : 6
        let hasMore = !showMore && (futureAll.count > upLimit || pastAll.count > pastLimit)
        let pending = pendingList.map { WealthTransferUIRow.make($0, facts: facts, manual: manual, masked: masked) }
        let upcoming = futureAll.prefix(upLimit).map { WealthTransferUIRow.make($0, facts: facts, manual: manual, masked: masked) }
        let past = pastAll.prefix(pastLimit).map { WealthTransferUIRow.make($0, facts: facts, manual: manual, masked: masked) }

        let amountText = masked ? WealthFormat.masked : WealthFormat.money(t.amount, code: t.code)
        let fromLabel = WealthTransferUIText.accountLabel(t.fromId, fallback: t.fromName, facts: facts)
        let toLabel = WealthTransferUIText.accountLabel(t.toId, fallback: t.toName, facts: facts)
        let accountsLine = fromLabel + " → " + toLabel + "・" + (manual ? "我自己轉" : "銀行會自動轉")
        let memoTrimmed = (t.rule.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let lastPastKey: String? = t.isEnded ? nil : t.lastPast.map { WealthTransferSchedule.key(of: $0) }
        var lastPastLabel = ""
        if let d = t.lastPast {
            lastPastLabel = "最後一次是 " + WealthTransferUIText.shortDay(d, today: today) + "（最近轉的那一期）"
        }
        let nextKey: String? = t.next?.key
        var nextLabel = ""
        if let n = t.next {
            nextLabel = "下一期 " + WealthTransferUIText.shortDay(n.original, today: today) + " 轉完再停"
        }
        let counted: [WealthTransferPeriod] = periods.filter { $0.counts && $0.day <= today }
        let spoken = t.title + "，" + t.cycleText + "，"
            + WealthTransferUIText.spokenAmount(t.amount, code: t.code, masked: masked) + "，" + accountsLine

        return WealthTransferUIRuleModel(
            title: t.title, cycleText: t.cycleText, amountText: amountText, accountsLine: accountsLine,
            rangeLine: makeRangeLine(t), memo: memoTrimmed.isEmpty ? nil : memoTrimmed, isRunning: !t.isEnded,
            pending: pending, upcoming: Array(upcoming), past: Array(past), hasMore: hasMore,
            lastPastKey: lastPastKey, lastPastLabel: lastPastLabel, nextKey: t.isEnded ? nil : nextKey,
            nextLabel: nextLabel, pastCount: counted.count,
            deleteMessage: makeDeleteMessage(counted, facts: facts, masked: masked), spoken: spoken)
    }

    /// 「2026/11/6 起・沒有設結束日」「2026/11/6 起・銀行設到 2027/4/9」；已結束「已結束：最後一次 2026/12/6（零用錢收起來時結束）」
    static func makeRangeLine(_ t: WealthFacts.TransferRule) -> String {
        if t.isEnded {
            if let f = t.firstDay, let l = t.lastDay, l < f { return "已結束：一期都不算" }
            guard let l = t.lastDay else { return "已結束" }
            var why = ""
            if t.rule.endedBy == "accountHidden" {
                let who: String = t.toHidden ? t.toName : (t.fromHidden ? t.fromName : "帳戶")
                why = "（" + who + "收起來時結束）"
            } else if t.rule.endedBy == "accountDeleted" {
                why = "（帳戶刪掉時結束）"
            }
            return "已結束：最後一次 " + WealthFormat.ymd(l) + why
        }
        let start: String = t.firstDay.map { WealthFormat.ymd($0) + " 起・" } ?? ""
        guard let l = t.lastDay else { return start + "沒有設結束日" }
        return start + "銀行設到 " + WealthFormat.ymd(l)
    }

    /// 〔全部刪掉〕的影響：照每個帳戶最近一次對存摺算（對存摺以前的期不影響今天的數字）。
    /// 轉出那邊拿掉＝今天多、轉入那邊拿掉＝今天少（「薪轉今天多 50,000、存錢少 50,000」）
    static func makeDeleteMessage(_ counted: [WealthTransferPeriod], facts: WealthFacts, masked: Bool) -> String {
        guard !counted.isEmpty else { return "這條還沒有轉過的期，刪掉不影響今天的數字。" }
        var delta: [UUID: Double] = [:]
        var order: [UUID] = []
        for p in counted {
            if let f = p.fromId, afterAnchor(p.day, late: p.lateOut, account: facts.account(f)) {
                if delta[f] == nil { order.append(f) }
                delta[f, default: 0] += p.amount
            }
            if let t = p.toId, afterAnchor(p.day, late: p.lateIn, account: facts.account(t)) {
                if delta[t] == nil { order.append(t) }
                delta[t, default: 0] -= p.toAmount
            }
        }
        var parts: [String] = []
        for id in order {
            guard let v = delta[id], Swift.abs(v) > 0.5, let a = facts.account(id) else { continue }
            let lead: String = parts.isEmpty ? a.name + "今天" : a.name
            let word: String = v > 0 ? "多" : "少"
            let num: String = masked ? "" : " " + WealthFormat.plain(Swift.abs(v), code: "NT$")
            parts.append(lead + word + num)
        }
        let head = "全部刪掉的話，以前 \(counted.count) 期也拿掉"
        if parts.isEmpty { return head + "（都在對存摺以前，今天的數字不變）。" }
        return head + "：" + parts.joined(separator: "、") + "。"
    }

    /// 這一期這一邊在那個帳戶最近一次對存摺之後（從沒對過＝都算；同一天記了 late＝在對存摺之後）。帳戶找不到＝不算
    static func afterAnchor(_ day: Date, late: Bool, account: WealthFacts.Account?) -> Bool {
        guard let a = account else { return false }
        guard let anchor = a.lastAnchorDate else { return true }
        let d = WealthCal.day(day)
        let x = WealthCal.day(anchor)
        return d > x || (d == x && late)
    }
}

/// 規則頁的頭
private struct WealthTransferUIRuleHeader: View {
    let model: WealthTransferUIRuleModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.cycleText)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.title)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(model.amountText)
                        .font(.title3.weight(.bold).monospacedDigit())
                }
                Text(model.accountsLine)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.rangeLine)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                if let memo = model.memo {
                    Text(memo)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.spoken + "，" + model.rangeLine)
        }
    }
}

/// 規則頁的〔結束〕〔刪除〕確認框
private struct WealthTransferUIRuleDialog: ViewModifier {
    @Binding var ask: WealthTransferUIRuleAsk?
    let model: WealthTransferUIRuleModel
    /// 最後一期（nil＝〔設錯了，一期都不算〕）
    let onEnd: (String?) -> Void
    let onDelete: () -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { self.ask != nil }, set: { if !$0 { self.ask = nil } })
    }

    private var title: String {
        switch ask {
        case .end?: return "最後一次是哪一期？"
        case .delete?: return "刪除「" + model.title + "」？"
        case nil: return ""
        }
    }

    private func message(_ a: WealthTransferUIRuleAsk) -> String {
        switch a {
        case .end: return "以前的期照算；銀行那邊請到銀行 App 取消預約轉帳。"
        case .delete: return model.deleteMessage
        }
    }

    @ViewBuilder
    private var endButtons: some View {
        if let k = model.lastPastKey {
            Button(model.lastPastLabel) { onEnd(k) }
        }
        if let k = model.nextKey {
            Button(model.nextLabel) { onEnd(k) }
        }
        Button("設錯了，一期都不算") { onEnd(nil) }
    }

    @ViewBuilder
    private var deleteButtons: some View {
        if model.pastCount > 0 {
            if model.isRunning, let k = model.lastPastKey {
                Button("結束就好（以前 \(model.pastCount) 期照算）") { onEnd(k) }
            }
            Button("全部刪掉（以前 \(model.pastCount) 期也拿掉）", role: .destructive) { onDelete() }
        } else {
            Button("刪除", role: .destructive) { onDelete() }
        }
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible,
                                   presenting: ask) { a in
            switch a {
            case .end:
                endButtons
            case .delete:
                deleteButtons
            }
            Button("取消", role: .cancel) {}
        } message: { a in
            Text(message(a))
        }
    }
}

/// 一條定期轉帳的規則頁
struct WealthTransferRulePage: View {
    let ruleId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WealthMask.storageKey) private var masked = false

    @State private var showMore = false
    @State private var openPeriod: WealthTransferUIPeriodPick?
    @State private var ask: WealthTransferUIRuleAsk?
    @State private var showPremium = false

    private var model: WealthTransferUIRuleModel? {
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        return WealthTransferUIRuleModel.make(facts: facts, ruleId: ruleId, masked: masked, showMore: showMore)
    }

    private var pastTitle: String { showMore ? "以前的" : "以前的（最近 6 期）" }

    var body: some View {
        NavigationStack {
            page(model)
                .navigationTitle("定期轉帳")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .premiumLockAlert(isPresented: $showPremium)
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    @ViewBuilder
    private func page(_ m: WealthTransferUIRuleModel?) -> some View {
        if let m {
            List {
                WealthTransferUIRuleHeader(model: m)
                periodSections(m)
                actionSection(m)
            }
            .modifier(WealthTransferUIRuleDialog(ask: $ask, model: m,
                                                 onEnd: { k in end(k) },
                                                 onDelete: { delete() }))
            .sheet(item: $openPeriod) { p in
                WealthTransferPeriodSheet(ruleId: ruleId, periodKey: p.key, fromRulePage: true)
                    .appStores()
            }
        } else {
            List {
                Text("這條定期轉帳已經刪了")
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    @ViewBuilder
    private func periodSections(_ m: WealthTransferUIRuleModel) -> some View {
        if !m.pending.isEmpty {
            Section {
                rows(m.pending)
            } header: {
                Text("還沒定下來的")
            } footer: {
                Text("銀行沒轉成的期：點進去〔今天補轉〕或〔復原〕")
            }
        }
        if !m.upcoming.isEmpty {
            Section {
                rows(m.upcoming)
            } header: {
                Text("接下來")
            }
        }
        if !m.past.isEmpty {
            Section {
                rows(m.past)
            } header: {
                Text(pastTitle)
            }
        }
        if m.hasMore {
            Section {
                Button("看更多") { showMore = true }
            }
        }
    }

    private func rows(_ list: [WealthTransferUIRow]) -> some View {
        ForEach(list) { r in
            Button {
                openPeriod = WealthTransferUIPeriodPick(key: r.key)
            } label: {
                WealthTransferUIRowView(row: r)
            }
        }
    }

    private func actionSection(_ m: WealthTransferUIRuleModel) -> some View {
        Section {
            if m.isRunning {
                Button("結束") { ask = .end }
            }
            Button("刪除這條定期轉帳", role: .destructive) { tapDelete() }
        } footer: {
            Text("App 不會幫你轉錢；在這裡改，銀行 App 那邊也要改。")
        }
    }

    // MARK: 寫（先關這一頁，下一個 runloop 才寫）

    /// 〔刪除〕要訂閱（看、〔結束〕不用）
    private func tapDelete() {
        guard subscription.isPremium else {
            showPremium = true
            return
        }
        ask = .delete
    }

    /// 〔結束〕：最後一期＝key（nil＝一期都不算）；不擋訂閱
    private func end(_ key: String?) {
        let life = lifeStore
        let id = ruleId
        dismiss()
        DispatchQueue.main.async {
            life.endTransferRule(id, lastKey: key)
        }
    }

    /// 〔全部刪掉〕〔刪除〕：墓碑（要訂閱，tapDelete 已經擋）
    private func delete() {
        guard subscription.isPremium else {
            showPremium = true
            return
        }
        let life = lifeStore
        let id = ruleId
        dismiss()
        DispatchQueue.main.async {
            life.deleteTransferRule(id)
        }
    }
}

// MARK: - C. 一期小表單

/// 一期小表單打開規則頁（巢狀 sheet 的 item）
private struct WealthTransferUIRulePick: Identifiable {
    let ruleId: UUID
    var id: UUID { ruleId }
}

/// 〔改這一期〕〔今天補轉〕展開的兩欄
private enum WealthTransferUIPeriodEdit: Hashable {
    /// 改這一期（日子不能跨過前後一期）
    case change
    /// 今天補轉（不早於原本那天；狀態存 redo）
    case redo
}

/// 一期現在給哪幾顆按鈕（brief §6 G4 C-2 的表）
private enum WealthTransferUIPeriodButtons: Equatable {
    /// 還沒到（含可能轉不過去）
    case planned
    /// 已轉（自動轉〔沒轉成〕；自己轉〔這期不轉〕）
    case done
    /// 沒轉成：〔今天補轉〕〔復原〕
    case failed
    /// 補轉：〔改這一期〕〔復原〕
    case redo
    /// 這期不轉：〔銀行還是轉了〕／〔還是要轉〕
    case skipped
    /// 暫停、壞掉：只有字
    case textOnly
}

/// 一期小表單要畫的（一次從 facts 組好）
private struct WealthTransferUIPeriodModel {
    let key: String
    /// 「定期轉帳・薪轉 → 存錢」
    let caption: String
    /// 「11/6（五）」
    let dayText: String
    let amountText: String
    let status: WealthTransferUIStatus
    /// 第一行橘字「11/13 薪轉預估只有 1,400，銀行可能轉不過去」
    let warnLine: String?
    let buttons: WealthTransferUIPeriodButtons
    let manual: Bool
    let today: Date
    let original: Date
    let day: Date
    let amount: Double
    /// 這一段原本每期多少（〔改這一期〕打一樣的＝不存金額）
    let segmentAmount: Double?
    /// 註記原本的狀態字（〔改這一期〕照留；不認得的字也照留）
    let rawStatus: String?
    /// 〔改這一期〕日子的範圍：前一期原本的日子＋1 天…後一期原本的日子−1 天
    let lower: Date
    let upper: Date
    /// 〔知道了〕：轉出帳戶第一筆不夠扣就是這一期時，要確認那一條的 key
    let ackKey: String?
    let spoken: String

    /// 頭那一塊念的一句（有橘字就接在後面）
    var spokenAll: String {
        guard let w = warnLine else { return spoken }
        return spoken + "，" + w
    }

    /// 「請先到銀行 App 取消 11/13 那一筆；…」
    var cancelMessage: String {
        "請先到銀行 App 取消 " + WealthTransferUIText.shortDay(original, today: today)
            + " 那一筆；沒取消的話，你先補了錢銀行就會照轉。"
    }

    func range(for mode: WealthTransferUIPeriodEdit) -> ClosedRange<Date> {
        switch mode {
        case .redo:
            let hi = WealthCal.addDays(366, to: Swift.max(today, original))
            return original...hi
        case .change:
            return lower...upper
        }
    }

    func editTitle(_ mode: WealthTransferUIPeriodEdit) -> String {
        mode == .redo ? "補轉那天" : "這期哪天"
    }

    /// 補轉那期按〔改這一期〕也是改補轉（狀態留 redo），標題照按的那顆寫
    func editHeader(_ mode: WealthTransferUIPeriodEdit) -> String {
        (mode == .redo && buttons != .redo) ? "今天補轉" : "改這一期"
    }

    func editFooter(_ mode: WealthTransferUIPeriodEdit) -> String {
        switch mode {
        case .redo:
            return "日子不能早於原本那天（" + WealthTransferUIText.shortDay(original, today: today) + "）；補轉那天兩邊才算。"
        case .change:
            return "日子不能跨過前後一期（" + WealthTransferUIText.shortDay(lower, today: today) + "～"
                + WealthTransferUIText.shortDay(upper, today: today) + "）；只改這一期，以後的照舊。"
        }
    }

    /// acknowledged：要確認那一條已經按過〔知道了〕（WealthBook.isDismissed）：按過就不再給〔知道了〕
    static func make(facts: WealthFacts, ruleId: UUID, key: String, masked: Bool,
                     acknowledged: (String) -> Bool) -> WealthTransferUIPeriodModel? {
        guard let t = facts.transferRule(ruleId), let p = facts.transferPeriod(ruleId, key: key) else { return nil }
        let today = facts.today
        let manual = t.isManual
        let shortage: WealthShortage? = p.state == .planned ? facts.transferShortage(ruleId, key: key) : nil
        let status = WealthTransferUIStatus.of(p, manual: manual, short: shortage != nil, today: today)

        let buttons: WealthTransferUIPeriodButtons
        if p.status == .redo && (p.state == .planned || p.state == .done) {
            buttons = .redo
        } else {
            switch p.state {
            case .planned: buttons = .planned
            case .done: buttons = .done
            case .failed: buttons = .failed
            case .skipped: buttons = .skipped
            case .paused, .broken: buttons = .textOnly
            }
        }

        // 「11/13 薪轉預估只有 1,400，銀行可能轉不過去」（自己轉「…，轉之前要先補錢」；遮住不寫數字）
        var warnLine: String? = nil
        if let s = shortage {
            let fromName = facts.account(p.fromId)?.name ?? t.fromName
            let tail = manual ? "，轉之前要先補錢" : "，銀行可能轉不過去"
            let head: String = WealthTransferUIText.shortDay(s.date, today: today) + " " + fromName
            let middle: String = masked ? "預估不夠" : "預估只有 " + WealthFormat.plain(s.before, code: s.code)
            warnLine = head + middle + tail
        }

        // 〔知道了〕：轉出帳戶第一筆不夠扣（要確認那一條）就是這一期才有
        var ackKey: String? = nil
        if shortage != nil, let f = p.fromId, let first = facts.account(f)?.shortage,
           first.transferRuleId == ruleId, first.periodKey == key {
            let k = WealthCheck.shortageId(accountId: f, day: first.date)
            if !acknowledged(k) { ackKey = k }
        }

        // 〔改這一期〕不能跨過前後一期（第一期、最後一期那一邊放寬到差不多一個週期）
        let around = facts.transferPeriods(ruleId, through: WealthCal.addDays(62, to: Swift.max(p.original, today)))
        var prev: Date? = nil
        var next: Date? = nil
        if let i = around.firstIndex(where: { $0.key == key }) {
            if i > 0 { prev = around[i - 1].original }
            if i + 1 < around.count { next = around[i + 1].original }
        }
        let gap = t.rule.cycleKind == .weekly ? 6 : 27
        let lo: Date = prev.map { WealthCal.addDays(1, to: $0) } ?? WealthCal.addDays(-gap, to: p.original)
        let hi: Date = next.map { WealthCal.addDays(-1, to: $0) } ?? WealthCal.addDays(gap, to: p.original)

        let amountText = masked ? WealthFormat.masked : WealthFormat.money(p.amount, code: p.fromCode)
        let dayText = WealthTransferUIText.day(p.day, today: today)
        let spoken = WealthTransferUIText.spokenDay(p.day) + "，" + t.title + "，"
            + WealthTransferUIText.spokenAmount(p.amount, code: p.fromCode, masked: masked) + "，" + status.spoken

        return WealthTransferUIPeriodModel(
            key: key, caption: "定期轉帳・" + t.title, dayText: dayText, amountText: amountText, status: status,
            warnLine: warnLine, buttons: buttons, manual: manual, today: today, original: p.original, day: p.day,
            amount: p.amount, segmentAmount: t.rule.segment(at: key)?.amount, rawStatus: t.rule.notes?[key]?.status,
            lower: Swift.min(lo, p.original), upper: Swift.max(hi, p.original), ackKey: ackKey, spoken: spoken)
    }
}

/// 一期小表單的頭：「定期轉帳・薪轉 → 存錢」「11/6（五）　20,000」狀態字、橘字
private struct WealthTransferUIPeriodHeader: View {
    let model: WealthTransferUIPeriodModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.caption)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.dayText)
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 8)
                    Text(model.amountText)
                        .font(.title3.weight(.bold).monospacedDigit())
                }
                Text(model.status.text)
                    .strikethrough(model.status.tone == .strike)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.status.color)
                if let w = model.warnLine {
                    Text(w)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.spokenAll)
        }
    }
}

/// 一期的小表單。periodKey：那一期原本的日子「2026-11-06」。fromRulePage：從規則頁點進來的（〔看整條〕＝關掉回規則頁）
struct WealthTransferPeriodSheet: View {
    let ruleId: UUID
    let periodKey: String
    var fromRulePage: Bool = false

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WealthMask.storageKey) private var masked = false

    /// 展開的兩欄（nil＝按鈕）
    @State private var editing: WealthTransferUIPeriodEdit?
    @State private var amountText = ""
    @State private var pickedDay = Date()
    /// 〔銀行這期取消了〕先跳「App 不會幫你取消」
    @State private var askCancel = false
    @State private var openRule: WealthTransferUIRulePick?

    private var model: WealthTransferUIPeriodModel? {
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let book = lifeStore.wealthBook
        return WealthTransferUIPeriodModel.make(facts: facts, ruleId: ruleId, key: periodKey, masked: masked,
                                                acknowledged: { book.isDismissed($0) })
    }

    /// 打的金額（台幣到元；< 1 元＝nil，存鈕灰）
    private var editAmount: Double? {
        guard let v = WealthFormText.number(amountText) else { return nil }
        let r = v.rounded()
        return r >= 1 ? r : nil
    }

    var body: some View {
        NavigationStack {
            page(model)
                .navigationTitle("這一期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    @ViewBuilder
    private func page(_ m: WealthTransferUIPeriodModel?) -> some View {
        if let m {
            List {
                WealthTransferUIPeriodHeader(model: m)
                if let mode = editing {
                    editSection(m, mode: mode)
                } else if m.buttons != .textOnly {
                    buttonSection(m)
                }
                Section {
                    Text("這裡改的只是 App 的紀錄；銀行那邊要取消或改，請到銀行 App。")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
            .alert("App 不會幫你取消", isPresented: $askCancel) {
                Button("取消好了") { setStatus(WealthTransferStatus.skip.rawValue) }
                Button("先不要", role: .cancel) {}
            } message: {
                Text(m.cancelMessage)
            }
            .sheet(item: $openRule) { r in
                WealthTransferRulePage(ruleId: r.ruleId)
                    .appStores()
            }
        } else {
            List {
                Text("這一期找不到了（這條定期轉帳可能已經刪了）")
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    @ViewBuilder
    private func buttonSection(_ m: WealthTransferUIPeriodModel) -> some View {
        Section {
            switch m.buttons {
            case .planned:
                WealthTransferUIActionRow(title: "改這一期", detail: "金額、日子") { startEdit(m, mode: .change) }
                if m.manual {
                    WealthTransferUIActionRow(title: "這期不轉") { setStatus(WealthTransferStatus.skip.rawValue) }
                } else {
                    WealthTransferUIActionRow(title: "銀行這期取消了") { askCancel = true }
                }
                if m.ackKey != nil {
                    WealthTransferUIActionRow(title: "知道了", detail: "不再出現在要確認") { acknowledge(m) }
                }
                wholeRuleRow
            case .done:
                WealthTransferUIActionRow(title: "改這一期", detail: "金額、日子") { startEdit(m, mode: .change) }
                if m.manual {
                    WealthTransferUIActionRow(title: "這期不轉") { setStatus(WealthTransferStatus.skip.rawValue) }
                } else {
                    WealthTransferUIActionRow(title: "沒轉成", detail: "不夠錢、銀行維護") {
                        setStatus(WealthTransferStatus.failed.rawValue)
                    }
                }
                wholeRuleRow
            case .failed:
                WealthTransferUIActionRow(title: "今天補轉", detail: "日子預設今天、金額照那期") { startEdit(m, mode: .redo) }
                WealthTransferUIActionRow(title: "復原") { setStatus(nil) }
            case .redo:
                WealthTransferUIActionRow(title: "改這一期", detail: "金額、補轉那天") { startEdit(m, mode: .redo) }
                WealthTransferUIActionRow(title: "復原") { setStatus(nil) }
            case .skipped:
                WealthTransferUIActionRow(title: m.manual ? "還是要轉" : "銀行還是轉了") { setStatus(nil) }
            case .textOnly:
                EmptyView()
            }
        }
    }

    private var wholeRuleRow: some View {
        WealthTransferUIActionRow(title: "看整條", chevron: true) { openWholeRule() }
    }

    private func editSection(_ m: WealthTransferUIPeriodModel, mode: WealthTransferUIPeriodEdit) -> some View {
        Section {
            HStack {
                Text("NT$").foregroundStyle(Color.secondary)
                TextField("這期轉多少", text: $amountText)
                    .keyboardType(.numberPad)
            }
            DatePicker(m.editTitle(mode), selection: $pickedDay, in: m.range(for: mode), displayedComponents: .date)
            Button("存") { saveEdit(m, mode: mode) }
                .disabled(editAmount == nil)
            Button("取消") { editing = nil }
        } header: {
            Text(m.editHeader(mode))
        } footer: {
            Text(m.editFooter(mode))
        }
    }

    // MARK: 按鈕

    private func startEdit(_ m: WealthTransferUIPeriodModel, mode: WealthTransferUIPeriodEdit) {
        amountText = WealthFormText.editable(m.amount)
        let range = m.range(for: mode)
        // 〔今天補轉〕預設今天（不早於原本那天）；其他照現在那天
        let start: Date = m.buttons == .failed ? Swift.max(m.today, m.original) : m.day
        pickedDay = Swift.min(Swift.max(start, range.lowerBound), range.upperBound)
        editing = mode
    }

    /// 〔存〕：那一期的註記（金額跟這一段原本一樣＝不存；日子等於原本那天＝不存）
    private func saveEdit(_ m: WealthTransferUIPeriodModel, mode: WealthTransferUIPeriodEdit) {
        guard let v = editAmount else { return }
        let range = m.range(for: mode)
        let picked = Swift.min(Swift.max(WealthCal.day(pickedDay), range.lowerBound), range.upperBound)
        let pickedKey = WealthTransferSchedule.key(of: picked)
        let dayKey: String? = pickedKey == m.key ? nil : pickedKey
        var same = false
        if let s = m.segmentAmount, Swift.abs(s - v) < 0.5 { same = true }
        let amount: Double? = same ? nil : v
        let status: String? = mode == .redo ? WealthTransferStatus.redo.rawValue : m.rawStatus
        let life = lifeStore
        let rid = ruleId
        let key = periodKey
        dismiss()
        DispatchQueue.main.async {
            life.setTransferNote(ruleId: rid, key: key, status: status, dayKey: dayKey, amount: amount)
        }
    }

    /// 〔銀行這期取消了〕〔這期不轉〕"skip"、〔沒轉成〕"failed"、〔復原〕〔銀行還是轉了〕〔還是要轉〕nil
    private func setStatus(_ status: String?) {
        let life = lifeStore
        let rid = ruleId
        let key = periodKey
        dismiss()
        DispatchQueue.main.async {
            life.setTransferStatus(ruleId: rid, key: key, status: status)
        }
    }

    /// 〔知道了〕：這期不再出現在要確認（記進帳本 dismissed）
    private func acknowledge(_ m: WealthTransferUIPeriodModel) {
        guard let k = m.ackKey else { return }
        let life = lifeStore
        dismiss()
        DispatchQueue.main.async {
            life.dismissWealthCheck(k)
        }
    }

    /// 〔看整條〕：從規則頁點進來的＝關掉回去；不然疊一張規則頁
    private func openWholeRule() {
        if fromRulePage {
            dismiss()
        } else {
            openRule = WealthTransferUIRulePick(ruleId: ruleId)
        }
    }
}
