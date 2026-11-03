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
// G4 實作（v1a；〔暫停〕是 v2；v1b 加的見下面 [v25.577] 那段）：
// • 新增表單：從（只列有台幣那一格的帳戶）、到（＋「不在 App 裡的人」帶去記帳新增固定支出，這裡什麼都不存）、每次轉多少（台幣到元）、
//   每月（1～31 日＋最後一天；29～31 多一列〔當月最後一天〕〔下個月 1 號〕）／每週（一…日）、從哪一期開始算（今天剛好是那一期：
//   兩邊今天都沒對過存摺＝兩選一、有一邊對過＝三選一，預設〔今天這期不算〕）、銀行那邊設到哪天（不設／到哪天／共幾次）、誰轉、名字、備註、
//   最下面「接下來：」三個日子。存檔：名字、備註像帳號先問〔只留後 4 碼〕→ 記帳裡像同一筆的一筆一筆問「是同一筆嗎？」→ dismiss → 下一個 runloop 寫。
// • 規則頁：頭（週期、金額、從 → 到、起訖）、還沒定下來的（沒轉成）→ 接下來 3 期 → 以前的（最近 6 期）→〔看更多〕；〔結束〕三個選項；
//   〔刪除這條定期轉帳〕（要訂閱；有以前的期問〔結束就好〕〔全部刪掉〕，影響照每個帳戶最近一次對存摺算）。
// • 一期小表單：照那一期的狀態給按鈕（judge §4.5、brief §6 G4 C 的表）；〔改這一期〕日子不能跨過前後一期、〔今天補轉〕不早於原本那天。
// • 遮住（財富頁右上眼睛）：規則頁、一期小表單的金額寫 ••••（新增表單是自己打的數字，照常顯示）。
//
// [v25.577] G4 v1b（transfer/build/v1b/brief.md §6 G4；算法、字都是主控的 WealthTransferPlans.swift，這裡只叫）：
// • WealthTransferRuleForm(fromId:editRuleId:preset:)：多兩個有預設的參數（舊的 fromId: 呼叫照樣編得過）。
//   editRuleId＝〔改金額或帳戶〕：同一張表單帶好（從、到、金額＝下一期那一段），存檔先問像帳號 → 改了週期或日子問「從哪天起照新的日子？」
//   〔下一期起〕（splitTransferRule）〔全部都改〕；改了從、到、金額問「從哪一期起改？」〔下一期起〕〔全部都改〕〔選一期…〕（changed(from:)）；
//   其他直接存（updateTransferRule）。不問「是同一筆嗎？」。preset＝〔改成每月定期轉帳〕帶好欄位。
// • 提示（WealthTransferHints）、最下面「11/8 轉完，薪轉約剩 61,400 ✓」（wealthFactsPreview＋WealthTransferPreview）、〔更早…〕的影響
//   （transferEarlyImpact）：欄位停 0.5 秒才算（.task(id:)），結果放 @State，body 不算 facts。
// • 規則頁〔改金額或帳戶〕（要訂閱）、頭下面改過的那一行；一期小表單轉之前已經是負的橘字。
//
// [v25.579] G1 v2 會提醒你（transfer/build/v2/brief.md §6 G1；算法、字、要確認、通知都是主控的 WealthTransferNotices.swift，這裡只叫）：
// • 一期的狀態字：自己轉的先看 manualPhase——「今天要轉」（橘）「轉好了 ✓ 10/31」「當作轉了・等你回答」（橘）「當作轉了」「還沒轉・算在明天」（橘）。
// • 一期小表單：今天要轉〔轉好了〕（展開「實際轉了 NT$…」可改金額）〔改到明天〕〔這期不轉〕；等你回答／當作轉了〔轉了〕〔還沒，算在明天〕〔這期不轉〕〔改這一期〕；
//   還沒轉〔轉好了〕〔這期不轉〕；轉好了〔改這一期〕〔復原〕。〔轉好了〕存檔時兩邊帳戶今天對過存摺先問「今天對存摺的時候，這筆轉了嗎？」
//  （facts.transferReconciledToday → LifeStore.markTransferDone 的 lateOut／lateIn）。
// • 規則頁：還沒定下來的多列自己轉的（今天要轉、等你回答、還沒轉）；頭下面最前面「暫停到 12/24」（rule.pauseInfo）；〔暫停〕小表單（從哪一期起、
//   到哪一期恢復、pauseSummary）／〔恢復…〕（下一期起照轉）；「提醒我」開關（rule.remind）；〔結束〕記 endedBy "user"（WealthTransferNotices.endedByUser）。
// • 新增表單「誰轉」小字換 v2 那句；WealthTransferRenewSheet（要確認〔已經續設〕：銀行那邊設到哪天，改 endKey、endedBy nil）。
// • 這版新的每一顆都不擋訂閱（judge §6）；寫 store 一律先 dismiss（「提醒我」開關不關頁）、下一個 runloop 才叫。不加任何存檔欄位。
//
// [v25.581] G1 v3 以前湊的找出來（transfer/build/v3/brief.md §6 G1；算法、字、key 都是主控的 WealthTransferFinds.swift，這裡只叫）：
// • 新增表單吃要確認 v3〔改成定期轉帳〕〔合成一條定期轉帳〕〔設成每月都轉〕、明細長按〔設成每月〕、單次轉帳表單〔改成定期轉帳〕帶來的 preset：
//   最上面一行 preset.lead（「照記帳的『轉玉山存錢』帶好了；存檔時會問記帳那筆怎麼辦」；v1b〔轉帳過去〕那條路沒有 lead，照舊不出現）。
// • 存檔時「是同一筆嗎？」一定問 preset.matchExpenseId／matchIncomeId 那一筆（WealthTransferMatcher.forcedExpense／forcedIncome：
//   你改了金額、日子也照問，排最前面；支出先、收入後；小字「本月還能花每月會多…」寫記帳那筆自己的金額）；那筆找不到（記帳刪了）＝照 matcher
//   原本的，不多問；早就結束了（forced 回 nil）＝那筆不問（不會把結束日往後延）。
// • 〔不是，兩筆都要〕〔不是〕（不是關掉、〔取消〕）記住：存好後 WealthTransferFinds.notSameKeys → LifeStore.dismissWealthCheck，
//   要確認不會再問同一筆；關掉沒答的照 v1a 說的之後再問。不加任何存檔欄位、不擋訂閱（新增表單打開的地方照舊擋）。
//
// [v25.583] G1 v4 換匯、每兩週、每年、遇六日（transfer/build/v4/brief.md §6 G1；算法、字都是主控的 WealthTransferCycles.swift、
// WealthTransfers.swift、WealthTransferPlans.swift，這裡只叫）：
// • 新增／改表單：〔每月〕〔每週〕〔每兩週〕〔每年〕；每兩週「下一次是哪天」兩選一（這週那天／下週那天，只在新增時）；每年幾月＋幾日
//  （2/29 那種照「沒有這天的月份」）；「遇六日」〔照當天〕〔順延到星期一〕〔提前到星期五〕＋小字（每月、每年一定給；每週、每兩週選六日才給；
//   換匯預設順延，你動過就不跟著換）；「從」「到」外幣帳戶也列（拿掉 v1 的只列台幣）、「到」多「同一個帳戶（換匯）」；轉出幣別、對方幣別；
//   換匯多「對方收到」：一邊是台幣照現在設定的匯率帶好（你沒動過才跟著金額、幣別換），兩邊都外幣空的你填；存了就寫死、不跟匯率。
//   下一期、接下來寫實際那天（挪過的多寫原本那天「11/2（一）（11/1 是星期日，順延）」）。
// • 規則頁：頭的金額兩邊（「NT$9,600 → US$300.00」）、週期後面接「・遇六日順延」；改週期的每一次（facts.transferHistory）＋被接的舊那條
//  「…（新的那條）」〔看新的那條〕；以前那條的期照樣列在「以前的」（點了開那一條的那一期）；每一列金額兩邊（未來的期「約」）；
//   刪除的影響照帳戶＋幣別分開算。
// • 一期小表單：頭的金額兩邊；換匯〔改這一期〕〔今天補轉〕兩個金額（那期銀行實際換多少：LifeStore.setTransferNote(…toAmount:)）、
//   自己轉〔轉好了〕多「對方收到」（markTransferDone(…toAmount:)）；〔改這一期〕日子範圍照週期（editGapDays）。
// • 不加存檔欄位、不擋新的訂閱（新增、〔改金額或帳戶〕照舊在打開的地方擋；〔改這一期〕〔看新的那條〕不擋）；新 sheet 照舊 sheet(item:)＋.appStores()。

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

    /// VoiceOver 的金額「20,000 元」（遮住「金額已遮住」）；[審查修] 外幣不接「元」：「US$300.00」
    static func spokenAmount(_ v: Double, code: String, masked: Bool) -> String {
        if masked { return "金額已遮住" }
        if FinanceRates.isNTD(code) { return WealthFormat.plain(v, code: code) + " 元" }
        return WealthFormat.money(v, code: code)
    }

    /// 帳戶「薪轉（台新銀行）」；沒有暱稱（名字就是銀行名）只寫一次；找不到＝fallback
    static func accountLabel(_ id: UUID?, fallback: String, facts: WealthFacts) -> String {
        guard let a = facts.account(id) else { return fallback }
        let bank = a.bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        if bank.isEmpty || bank == a.name { return a.name }
        return a.name + "（" + bank + "）"
    }

    /// [v25.583] 打的金額：台幣到元（≥ 1）、外幣到 0.01（≥ 0.01）；讀不懂＝nil
    static func parseAmount(_ text: String, code: String) -> Double? {
        guard let v = WealthFormText.number(text) else { return nil }
        if FinanceRates.isNTD(code) {
            let r = v.rounded()
            return r >= 1 ? r : nil
        }
        let r = (v * 100).rounded() / 100
        return r > 0.004 ? r : nil
    }

    /// [v25.583] 輸入框前面的字：台幣「NT$」、外幣「US$」（認不得的「泰銖 」）
    static func prefix(_ code: String) -> String {
        FinanceRates.isNTD(code) ? "NT$" : WealthFormat.foreignPrefix(code)
    }

    /// [v25.583] 「跟這一段一樣」差多少以內算一樣：台幣 0.5 元、外幣 0.005
    static func tolerance(_ code: String) -> Double {
        FinanceRates.isNTD(code) ? 0.5 : 0.005
    }

    /// [v25.583] 句子裡的「11/2（一）（11/1 是星期日，順延）」：照遇六日挪過的那天；沒挪＝只寫那天
    static func shiftedDay(_ original: Date, holiday: WealthTransferHoliday, today: Date) -> String {
        let actual = WealthTransferSchedule.shifted(original, holiday: holiday)
        let text = day(actual, today: today)
        guard WealthCal.dayKey(actual) != WealthCal.dayKey(original) else { return text }
        let how: String = holiday == .prev ? "提前" : "順延"
        return text + "（" + shortDay(original, today: today) + " 是星期" + WealthTransferText.weekdayName(original)
            + "，" + how + "）"
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
        // [v25.579] 自己轉的先看在哪一步（補轉、這期不轉、沒轉成、暫停、壞掉＝nil，照下面畫）
        if manual, let ph = p.manualPhase(today: today), let s = manualStatus(ph, p: p, warn: w, today: today) {
            return s
        }
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

    /// [v25.579] 自己轉那一期的字（judge §4.5 v2 那幾列）；預計＝nil（照 state 畫「預計」）
    private static func manualStatus(_ ph: WealthTransferManualPhase, p: WealthTransferPeriod, warn w: String?,
                                     today: Date) -> WealthTransferUIStatus? {
        switch ph {
        case .upcoming:
            return nil
        case .today:
            return WealthTransferUIStatus(text: "今天要轉", tone: .warn, warn: nil)
        case .done:
            let text = "轉好了 ✓ " + WealthTransferUIText.shortDay(p.day, today: today)
            return WealthTransferUIStatus(text: text, tone: .normal, warn: nil)
        case .waiting:
            return WealthTransferUIStatus(text: "當作轉了・等你回答", tone: .warn, warn: nil)
        case .assumed:
            return WealthTransferUIStatus(text: "當作轉了", tone: .normal, warn: nil)
        case .notYet:
            return WealthTransferUIStatus(text: "還沒轉・算在明天", tone: .warn, warn: w)
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
    /// [v25.583] 那一期是哪一條的（「以前的」也列改週期以前那條的期：點了開那一條的那一期）
    let ruleId: UUID
    /// 那一期原本的日子「2026-11-06」
    let key: String
    let dayText: String
    let amountText: String
    let status: WealthTransferUIStatus
    let spoken: String

    var id: String { ruleId.uuidString + "-" + key }

    /// [v25.583] 金額照兩邊寫：同幣別「20,000」；換匯「約 9,600 → US$300.00」（未來沒改過的期「約」；WealthTransferText.pair）
    static func make(_ p: WealthTransferPeriod, facts: WealthFacts, manual: Bool, masked: Bool) -> WealthTransferUIRow {
        let today = facts.today
        let short: Bool = p.state == .planned && facts.transferShortage(p.ruleId, key: p.key) != nil
        let st = WealthTransferUIStatus.of(p, manual: manual, short: short, today: today)
        let amountText: String = masked ? "••••" : WealthTransferText.pair(p)
        let spokenAmount: String = (p.isExchange && !masked)
            ? WealthTransferText.pair(p, money: true)
            : WealthTransferUIText.spokenAmount(p.amount, code: p.fromCode, masked: masked)
        let spoken = WealthTransferUIText.spokenDay(p.day) + "，" + spokenAmount + "，" + st.spoken
        return WealthTransferUIRow(ruleId: p.ruleId, key: p.key, dayText: WealthTransferUIText.day(p.day, today: today),
                                   amountText: amountText, status: st, spoken: spoken)
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
    /// 關掉、〔取消〕：兩筆都留、照存，不記（要確認之後還會再問）
    case keepBoth
    /// [v25.581] 你按的〔不是，兩筆都要〕〔不是〕：兩筆都留，存好後記住不再問（WealthTransferFinds.notSameKeys）
    case notSame
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
                Button("不是，兩筆都要") { onAnswer(m, .notSame) }
            } else {
                Button("是：那筆收入從下個月起結束") { onAnswer(m, .endItem) }
                Button("不是") { onAnswer(m, .notSame) }
            }
            Button("取消", role: .cancel) { onAnswer(m, .keepBoth) }
        } message: { m in
            if let line = message(m) {
                Text(line)
            }
        }
    }
}

// MARK: - [v25.577] A'. 改金額或帳戶、提示、預覽、〔更早…〕要的小東西（transfer/build/v1b/brief.md §6 G4 A）

/// 表單提示一行（judge §4.2「有才出現」；gray＝只是提示的灰字）
private struct WealthTransferUIHintRow: View {
    let hint: WealthTransferHint

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: hint.gray ? "info.circle" : "lightbulb")
                .font(.caption)
                .foregroundStyle(hint.gray ? Color.secondary : Color.orange)
                .accessibilityHidden(true)
            Text(hint.text)
                .font(hint.gray ? Font.footnote : Font.subheadline)
                .foregroundStyle(hint.gray ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 最下面的預覽一行（warn＝橘字：轉完會不夠）
private struct WealthTransferUIPreviewRow: View {
    let line: WealthTransferPreviewLine

    var body: some View {
        Text(line.text)
            .font(.subheadline)
            .foregroundStyle(line.warn ? Color.orange : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 銀行那邊設到哪天（存檔時照「那一條」的日子換算成最後一期：改日子〔下一期起〕那條照新的日子算）
private enum WealthTransferUIEndSpec {
    case noEnd
    case date(Date)
    case count(Int)

    /// 這一條的最後一期 key；〔到哪天〕比這條第一期還早＝第一期前一天（一期都不算）
    func key(for r: WealthTransferRule) -> String? {
        switch self {
        case .noEnd:
            return nil
        case .date(let d):
            if let last = WealthTransferSchedule.lastDate(r, onOrBefore: d) {
                return WealthTransferSchedule.key(of: last)
            }
            return Self.keyBeforeStart(r)
        case .count(let n):
            return WealthTransferSchedule.nthDate(r, times: n).map { WealthTransferSchedule.key(of: $0) }
        }
    }

    static func keyBeforeStart(_ r: WealthTransferRule) -> String? {
        guard let sk = r.startKey, let s = WealthTransferSchedule.date(fromKey: sk) else { return nil }
        return WealthCal.dayKey(WealthCal.addDays(-1, to: s))
    }
}

/// 〔改金額或帳戶〕打開時的值（比較改了什麼）
private struct WealthTransferUIOriginal {
    let ruleId: UUID
    /// 第一期（startKey）
    let firstDay: Date?
    /// 下一期那一段的從、到、每期多少
    let fromId: UUID?
    let toId: UUID?
    let amount: Double
    /// [v25.583] 下一期那一段的兩個幣別（"NT$" 或外幣代碼）、對方收到多少（同幣別＝nil）
    let fromCode: String
    let toCode: String
    let toAmount: Double?
    let cycle: WealthTransferCycle
    /// 照表單換算的 day（1～31）、short（nil／"next"）、每週星期幾、[v25.583] 每年幾月
    let day: Int
    let short: String?
    let weekday: Int
    let month: Int
    /// [v25.583] 遇六日（不算改日子：只改它＝直接存）
    let holiday: WealthTransferHoliday
}

/// 表單現在的值（編輯存檔、預覽共用；純值，閉包帶著走）
private struct WealthTransferUIFormValues {
    let fromId: UUID
    let toId: UUID
    let amount: Double
    /// [v25.583] 轉出、對方幣別（"NT$" 或外幣代碼）；對方收到多少（換匯才有）
    let fromCode: String
    let toCode: String
    let toAmount: Double?
    let cycle: WealthTransferCycle
    /// 每月（每年）幾日（每週、每兩週＝nil）
    let day: Int?
    let short: String?
    /// [v25.583] 每年幾月（不是每年＝nil）
    let month: Int?
    let weekday: Int
    /// [v25.583] 遇六日（不給那一列＝照當天）
    let holiday: WealthTransferHoliday
    /// nil＝銀行會自動轉；"manual"＝我自己轉
    let mode: String?
    let name: String?
    let memo: String?
    let end: WealthTransferUIEndSpec
    /// 從、到、金額、[v25.583] 幣別、對方收到多少有改的才填（WealthTransferRule.changed(from:_:)）
    let change: WealthTransferSegmentChange
    /// 週期、每月幾日、沒有這天的月份、星期幾、[v25.583] 每年幾月有改（遇六日不算）
    let scheduleChanged: Bool

    /// [v25.583] 兩邊幣別不一樣
    var isExchange: Bool { WealthFacts.norm(fromCode) != WealthFacts.norm(toCode) }

    /// 誰轉、名字、備註、銀行設到哪天（照這一條的日子換算）、[v25.583] 遇六日（整條一起：以前的期也跟著挪）
    func applyCommon(_ r: inout WealthTransferRule) {
        r.mode = mode
        r.name = name
        r.memo = memo
        r.holiday = holiday.raw
        r.endKey = end.key(for: r)
    }

    /// 〔下一期起〕〔全部都改〕（key ""）〔選一期…〕：那一期（含）以後同一個欄位一起改
    func segmentEdited(_ base: WealthTransferRule, from key: String) -> WealthTransferRule {
        var r = base.changed(from: key, change)
        applyCommon(&r)
        return r
    }

    /// 改週期或日子〔全部都改（以前的也照新的日子）〕：同一條換日子，第一期＝新的日子在原本第一期（含）以後的第一期
    func scheduleEditedAll(_ base: WealthTransferRule) -> WealthTransferRule {
        var r = base
        r.cycle = cycle.rawValue
        r.day = day
        r.short = short
        r.month = month
        if let sk = base.startKey, let first = WealthTransferSchedule.date(fromKey: sk),
           let s = WealthTransferSchedule.firstDate(cycle: cycle, day: day ?? 1, short: short, weekday: weekday,
                                                    month: month ?? 1, onOrAfter: first) {
            r.startKey = WealthTransferSchedule.key(of: s)
        }
        if !change.isEmpty { r = r.changed(from: "", change) }
        applyCommon(&r)
        return r
    }

    /// 改週期或日子〔下一期起〕的新的一條（previousId、createdAt 由 LifeStore.splitTransferRule 填）；算不出第一期＝nil。
    /// [v25.583] 段帶兩個幣別、換匯帶對方收到多少；規則帶每年幾月、遇六日（新的那條第一期照它的遇六日找）
    func splitNext(id: UUID, effective: Date) -> WealthTransferRule? {
        guard let s = WealthTransferPlan.splitStart(cycle: cycle, day: day ?? 1, short: short, weekday: weekday,
                                                    month: month ?? 1, holiday: holiday,
                                                    from: effective) else { return nil }
        let seg = WealthTransferSegment(fromKey: "", fromId: fromId, fromCode: WealthTransferExchange.storedCode(fromCode),
                                        toId: toId, toCode: WealthTransferExchange.storedCode(toCode), amount: amount,
                                        toAmount: isExchange ? toAmount : nil)
        var r = WealthTransferRule(id: id, cycle: cycle.rawValue, day: day, short: short, month: month,
                                   startKey: WealthTransferSchedule.key(of: s), mode: mode, holiday: holiday.raw,
                                   segments: [seg], name: name, memo: memo)
        r.endKey = end.key(for: r)
        return r
    }

    /// 只改了誰轉、銀行設到哪天、名字、備註
    func plainEdited(_ base: WealthTransferRule) -> WealthTransferRule {
        var r = base
        applyCommon(&r)
        return r
    }
}

/// 〔改金額或帳戶〕存檔問的一題
private struct WealthTransferUIEditAsk: Identifiable {
    enum Kind {
        /// 改週期或日子：「從哪天起照新的日子？」
        case schedule
        /// 改從、到、金額：「從哪一期起改？」
        case segment
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String?
    /// 〔下一期 2027/1/6 起（以前的照舊）〕；nil＝不出現
    let nextLabel: String?
    /// 改從、到、金額的〔下一期起〕那一期
    let nextKey: String?
    let allLabel: String
}

private enum WealthTransferUIEditAnswer {
    case next, all, pick, cancel
}

/// 〔改金額或帳戶〕存檔問「從哪一期起改？」／「從哪天起照新的日子？」
private struct WealthTransferUIEditDialog: ViewModifier {
    let asking: WealthTransferUIEditAsk?
    let onAnswer: (WealthTransferUIEditAsk, WealthTransferUIEditAnswer) -> Void
    let onClose: () -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { self.asking != nil }, set: { if !$0 { self.onClose() } })
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(asking?.title ?? "", isPresented: isPresented,
                                   titleVisibility: .visible, presenting: asking) { a in
            if let n = a.nextLabel {
                Button(n) { onAnswer(a, .next) }
            }
            Button(a.allLabel) { onAnswer(a, .all) }
            if a.kind == .segment {
                Button("選一期…") { onAnswer(a, .pick) }
            }
            Button("取消", role: .cancel) { onAnswer(a, .cancel) }
        } message: { a in
            if let m = a.message {
                Text(m)
            }
        }
    }
}

/// 〔選一期…〕一列「2026/12/6（日）」
private struct WealthTransferUIPickRow: Identifiable {
    let key: String
    let text: String
    var id: String { key }
}

/// 〔選一期…〕小 sheet 的 item：接下來（舊到新）、以前的（新到舊）
private struct WealthTransferUIPickList: Identifiable {
    let id = UUID()
    let upcoming: [WealthTransferUIPickRow]
    let past: [WealthTransferUIPickRow]

    /// dates：WealthTransferPlan.pickDates（以前最近 24 期＋以後 12 期，舊到新）。
    /// [v25.583] 字、以前／接下來照遇六日挪過的那天（key 照舊是原本的日子）
    static func make(_ dates: [Date], today: Date, holiday: WealthTransferHoliday) -> WealthTransferUIPickList {
        let t = WealthCal.day(today)
        var up: [WealthTransferUIPickRow] = []
        var past: [WealthTransferUIPickRow] = []
        for d in dates {
            let actual = WealthTransferSchedule.shifted(d, holiday: holiday)
            let text = WealthFormat.ymd(actual) + "（" + WealthTransferText.weekdayName(actual) + "）"
            let row = WealthTransferUIPickRow(key: WealthTransferSchedule.key(of: d), text: text)
            if actual > t {
                up.append(row)
            } else {
                past.insert(row, at: 0)
            }
        }
        return WealthTransferUIPickList(upcoming: up, past: past)
    }
}

/// 〔選一期…〕：點一列就用那一期（關掉之後表單才存）
private struct WealthTransferUIPickSheet: View {
    let list: WealthTransferUIPickList
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !list.upcoming.isEmpty {
                    Section {
                        rows(list.upcoming)
                    } header: {
                        Text("接下來")
                    }
                }
                if !list.past.isEmpty {
                    Section {
                        rows(list.past)
                    } header: {
                        Text("以前的")
                    } footer: {
                        Text("選以前的那一期：那一期以後都照新的；對過存摺之前的不影響今天的數字。")
                    }
                }
            }
            .navigationTitle("從哪一期起改？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private func rows(_ items: [WealthTransferUIPickRow]) -> some View {
        ForEach(items) { r in
            Button {
                onPick(r.key)
                dismiss()
            } label: {
                Text(r.text)
                    .foregroundStyle(Color.primary)
            }
        }
    }
}

/// [v25.583] 新增表單看幣別、換匯的三個 onChange（拆成 ViewModifier：表單 body 的修飾器鏈不再加長）
private struct WealthTransferUIFormWatch: ViewModifier {
    /// 「從」、轉出幣別、「到」串起來（變了重挑對方幣別）
    let codesKey: String
    /// 金額、兩個幣別、是不是換匯串起來（變了、你沒動過「對方收到」＝照匯率重帶）
    let exchangeKey: String
    let isExchange: Bool
    let onCodes: () -> Void
    let onAmounts: () -> Void
    let onExchange: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: codesKey) { _, _ in onCodes() }
            .onChange(of: exchangeKey) { _, _ in onAmounts() }
            .onChange(of: isExchange) { _, x in onExchange(x) }
    }
}

/// 新增或改一條定期轉帳。fromId：「從」帶好這個帳戶（nil＝WealthFacts.defaultTransferFromId：月薪入帳的那個帳戶）。
/// [v25.577] editRuleId：〔改金額或帳戶〕（同一張表單；存檔問從哪一期起改；要訂閱：打開的地方擋）。
/// preset：帶好欄位（要確認〔轉帳過去〕小表單的〔改成每月定期轉帳〕；只在新增時看）。
/// [v25.581] preset 也從要確認 v3、明細長按〔設成每月〕、單次轉帳表單〔改成定期轉帳〕來：lead＝表單最上面一行；
/// matchExpenseId／matchIncomeId＝存檔時「是同一筆嗎？」一定問的那一筆
struct WealthTransferRuleForm: View {
    var fromId: UUID? = nil
    var editRuleId: UUID? = nil
    var preset: WealthTransferPreset? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss
    /// 預覽、〔更早…〕的影響遮住時數字寫 ••••（自己打的欄位照常顯示）
    @AppStorage(WealthMask.storageKey) private var masked = false

    @State private var loaded = false
    /// 今天 00:00（打開時從 facts 抓一次）
    @State private var today: Date = WealthCal.day(Date())
    /// 「從」「到」可以選的（沒收起來的銀行、含定存帳戶；[v25.583] 外幣帳戶也列）
    @State private var choices: [WealthFormAccountChoice] = []
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
    /// [v25.581] 「是同一筆嗎？」按了〔不是，兩筆都要〕〔不是〕的那幾筆（存好後記住不再問）
    @State private var notSameMatches: [WealthTransferMatch] = []
    /// [v25.581] 打開時抓的帳戶名字（「是同一筆嗎？」問句裡記帳那筆的扣款、入帳帳戶不在選單裡時用）
    @State private var accountNames: [UUID: String] = [:]
    /// [v25.581] 「是同一筆嗎？」小字的金額（WealthTransferMatch.id → 「20,000」；只放帶來的那筆支出，其他照這條的金額）
    @State private var askAmounts: [String: String] = [:]
    @State private var expenseAsk: WealthTransferUIExpenseAsk?

    // [v25.577] v1b
    /// 〔改金額或帳戶〕打開時的值（nil＝新增）
    @State private var original: WealthTransferUIOriginal? = nil
    /// 要改的那一條找不到（刪掉了）：存檔鈕灰
    @State private var editMissing = false
    /// 預覽用的那一條的 id（新增：排在最後；改日子〔下一期起〕：新的那條）
    @State private var draftId = UUID()
    /// 〔更早…〕展開（DatePicker 選從哪天起）
    @State private var earlyOpen = false
    @State private var earlyDay = Date()
    /// 〔照我選的〕：小框留著、不再催
    @State private var earlyAccepted = false
    /// 停 0.5 秒才算的：提示、最下面的預覽、〔更早…〕的影響（body 不算 facts）
    @State private var hints: [WealthTransferHint] = []
    @State private var previewLines: [WealthTransferPreviewLine] = []
    @State private var early: WealthTransferEarlyImpact? = nil
    /// 〔改金額或帳戶〕存檔：問完才存的值、問的那一題、〔選一期…〕
    @State private var pendingValues: WealthTransferUIFormValues? = nil
    @State private var editAsk: WealthTransferUIEditAsk? = nil
    @State private var pickList: WealthTransferUIPickList? = nil
    @State private var pickedKey: String? = nil

    // [v25.583] v4 換匯、每兩週、每年、遇六日
    /// 轉出、對方幣別（"NT$" 或外幣代碼；WealthFacts.norm 過的）
    @State private var fromCode = "NT$"
    @State private var toCode = "NT$"
    /// 「對方收到」打的字；toAmountTouched＝你動過（不再照匯率自動帶；改的時候一打開就是 true）
    @State private var toAmountText = ""
    @State private var toAmountTouched = false
    /// 遇六日；holidayTouched＝你動過（換匯預設順延不再跟著切；改的時候一打開就是 true）
    @State private var holiday: WealthTransferHoliday = .onDay
    @State private var holidayTouched = false
    /// 每年幾月 1～12（打開時帶今天的月）
    @State private var yearMonth = 1
    /// 每兩週「下一次是哪天」選了〔下週那天〕（只在新增時）
    @State private var biweeklyLater = false
    /// 設定裡的匯率（打開時抓一次；「對方收到」預設照它換，存了就寫死）
    @State private var rates = FinanceRates(rates: [])
    /// 轉出幣別是照哪一個「從」挑的、對方幣別是照哪一組（從、轉出幣別、到）挑的：
    /// 打開時帶好的記在這裡，onChange 看到一樣的就不重挑（不會把〔改金額或帳戶〕帶好的幣別洗掉）
    @State private var fromBasis: UUID? = nil
    @State private var codesBasis = ""

    /// 每週〔一〕…〔日〕（Calendar 的 weekday）
    private static let weekdayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]
    private static let weekdayNames: [String] = ["日", "一", "二", "三", "四", "五", "六"]
    /// [v25.583] 「遇六日」三顆（Picker 用 index 當 tag）
    private static let holidayChoices: [WealthTransferHoliday] = [.onDay, .next, .prev]
    /// [v25.583] 每個月最少幾天（每年那條選 29～31 日時，那個月可能沒有這天才給「沒有這天的月份」）
    private static let minMonthDays: [Int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    /// 〔更早…〕最早可以選幾個月前（20 年；每週的 1,043 期，不到 1,200 期上限）
    private static let earliestMonths = 240

    // MARK: 算出來的（打字不重算 facts，只算日子）

    private var isEditing: Bool { editRuleId != nil }

    private var titleText: String { isEditing ? "改定期轉帳" : "新增定期轉帳" }

    private var tomorrow: Date { WealthCal.addDays(1, to: today) }

    private var toId: UUID? {
        if case .account(let id) = target { return id }
        return nil
    }

    private var isOutside: Bool { target == .outside }

    private var toChoices: [WealthFormAccountChoice] { choices.filter { $0.id != from } }

    /// [v25.583] 那個帳戶的幣別（WealthFacts.norm 過；台幣在前；不在選單＝空的）
    private func codes(of id: UUID?) -> [String] {
        guard let id, let c = choices.first(where: { $0.id == id }) else { return [] }
        return Self.normalized(c.codes)
    }

    /// [v25.583] 同一個帳戶兩格互換（台幣格 → 美金格）
    private var isSameAccount: Bool {
        guard let f = from else { return false }
        return toId == f
    }

    /// [v25.583] 「到」選單多一列「同一個帳戶（換匯）」：從的帳戶有兩個以上幣別（已經選了它的也照列，不會變空白）
    private var offersSameAccount: Bool { codes(of: from).count >= 2 || isSameAccount }

    /// [v25.583] 兩邊幣別不一樣（「到」還沒選、不在 App 裡的人＝不是）
    private var isExchange: Bool {
        guard toId != nil else { return false }
        return WealthFacts.norm(fromCode) != WealthFacts.norm(toCode)
    }

    /// [v25.583] 「轉出幣別」可以選的（現在選的不在帳戶裡也列，不會變空白）
    private var fromCodeChoices: [String] {
        var list = codes(of: from)
        if !list.contains(fromCode) { list.append(fromCode) }
        return list
    }

    /// [v25.583] 「對方幣別」可以選的：到的帳戶的幣別；同一個帳戶＝除了轉出那個
    private var toCodeChoices: [String] {
        guard let t = toId else { return [] }
        let same = isSameAccount
        var list: [String] = codes(of: t).filter { !same || $0 != fromCode }
        if !list.isEmpty && !list.contains(toCode) && !(same && toCode == fromCode) { list.append(toCode) }
        return list
    }

    /// [v25.583] 轉出幣別預設：有台幣＝台幣，不然第一個
    private static func defaultFromCode(_ list: [String]) -> String {
        if list.contains("NT$") { return "NT$" }
        return list.first ?? "NT$"
    }

    /// [v25.583] 對方幣別預設：同一個帳戶＝第一個跟轉出不一樣的；別的帳戶＝有同幣別就同幣別、不然台幣、不然第一個
    private static func defaultToCode(_ list: [String], fromCode fc: String, same: Bool) -> String {
        if same { return list.first(where: { $0 != fc }) ?? (list.first ?? "NT$") }
        if list.contains(fc) { return fc }
        if list.contains("NT$") { return "NT$" }
        return list.first ?? "NT$"
    }

    /// [v25.583] 挑幣別的依據（「從」、轉出幣別、「到」）
    private static func makeCodesKey(from f: UUID?, fromCode fc: String, target t: WealthTransferUITarget) -> String {
        let to: String
        switch t {
        case .unpicked: to = "u"
        case .outside: to = "o"
        case .account(let id): to = id.uuidString
        }
        let head: String = f?.uuidString ?? "-"
        return head + "|" + fc + "|" + to
    }

    private var codesKey: String { Self.makeCodesKey(from: from, fromCode: fromCode, target: target) }

    /// [v25.583] 金額、兩個幣別、是不是換匯（變了、你沒動過「對方收到」＝照匯率重帶）
    private var exchangeKey: String {
        let x: String = isExchange ? "x" : "-"
        return amountText + "|" + fromCode + "|" + toCode + "|" + x
    }

    /// [v25.583] 「對方收到」改的時候記你動過（之後不再照匯率自動帶）
    private var toAmountBinding: Binding<String> {
        Binding(get: { self.toAmountText },
                set: { v in
                    self.toAmountText = v
                    self.toAmountTouched = true
                })
    }

    /// [v25.583] 「遇六日」三顆（index 當 tag）；選了記你動過（換匯預設順延不再跟著切）
    private var holidayBinding: Binding<Int> {
        Binding(get: { Self.holidayChoices.firstIndex(of: self.holiday) ?? 0 },
                set: { i in
                    self.holiday = Self.holidayChoices.indices.contains(i) ? Self.holidayChoices[i] : .onDay
                    self.holidayTouched = true
                })
    }

    /// [v25.583] 給不給「遇六日」那一列：每月、每年一定給；每週、每兩週選星期六、日才給（平日永遠不會遇到六日）
    private var showsHolidayRow: Bool {
        guard !isOutside else { return false }
        switch cycle {
        case .monthly, .yearly: return true
        case .weekly, .biweekly: return weekday == 1 || weekday == 7
        }
    }

    /// [v25.583] 存的遇六日（不給那一列＝照當天）
    private var holidayValue: WealthTransferHoliday { showsHolidayRow ? holiday : .onDay }

    private func choiceName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return choices.first { $0.id == id }?.name
    }

    /// [v25.581] 帳戶名字：選單裡的 → 打開時抓的 → 「別的帳戶」
    private func accountName(_ id: UUID?) -> String {
        if let n = choiceName(id) { return n }
        if let id, let n = accountNames[id] { return n }
        return "別的帳戶"
    }

    /// [v25.581] 表單最上面一行（新增才有；preset 沒帶 lead＝nil）
    private var leadLine: String? {
        guard !isEditing, let line = preset?.lead?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else { return nil }
        return line
    }

    /// 每次轉多少（台幣到元、< 1 元＝nil；[v25.583] 外幣到 0.01）
    private var amountValue: Double? { WealthTransferUIText.parseAmount(amountText, code: fromCode) }

    /// [v25.583] 對方收到多少（照對方幣別：台幣到元、外幣到 0.01）
    private var toAmountValue: Double? { WealthTransferUIText.parseAmount(toAmountText, code: toCode) }

    private var storedDay: Int { Swift.min(Swift.max(monthDay, 1), 31) }

    /// [v25.583] 每月、每年才有「幾日」
    private var isDated: Bool { cycle == .monthly || cycle == .yearly }

    /// 選 29～31 日多一列「沒有這天的月份」；[v25.583] 每年的只在那個月可能沒有這天時給（2/29、4/31；1/31 不給）
    private var showsShortRow: Bool { Self.shortRowShown(cycle: cycle, monthDay: monthDay, month: yearMonth) }

    private static func shortRowShown(cycle c: WealthTransferCycle, monthDay md: Int, month m: Int) -> Bool {
        guard md >= 29 && md <= 31 else { return false }
        switch c {
        case .monthly: return true
        case .yearly:
            let i = Swift.min(Swift.max(m, 1), 12) - 1
            return md > minMonthDays[i]
        case .weekly, .biweekly: return false
        }
    }

    private var storedShort: String? { (showsShortRow && shortNext) ? "next" : nil }

    /// [v25.583] 實際那天在 d（含）以後的第一期（原本的日子；照遇六日挪過的那天比：WealthTransferSchedule.firstScheduled）
    private func firstPeriod(onOrAfter d: Date) -> Date? {
        WealthTransferSchedule.firstScheduled(cycle: cycle, day: storedDay, short: storedShort, weekday: weekday,
                                              month: yearMonth, holiday: holidayValue, onOrAfter: d)
    }

    /// [v25.583] 每兩週選了〔下週那天〕：再加 7 天（只在新增、沒選〔更早…〕時）
    private var biweeklyPushed: Bool { cycle == .biweekly && biweeklyLater && !isEditing && !earlyOpen }

    /// [v25.583] 每兩週「下一次是哪天」兩選一的第一個（這週那天；原本的日子）
    private var biweeklyBase: Date? { firstPeriod(onOrAfter: today) }

    /// 照週期、哪天：今天（含）以後第一期（原本的日子）。[v25.583] 每兩週〔下週那天〕再 +7
    private var firstFromToday: Date? {
        guard let d = firstPeriod(onOrAfter: today) else { return nil }
        return biweeklyPushed ? WealthCal.addDays(7, to: d) : d
    }

    /// 今天剛好是那一期：[v25.583] 第一期**挪過的那天**是今天（每月 1 日提前到星期五、今天 10/30：那期 key 是 11/1）
    private var todayIsPeriod: Bool {
        guard let d = firstFromToday else { return false }
        return WealthCal.dayKey(WealthTransferSchedule.shifted(d, holiday: holidayValue)) == WealthCal.dayKey(today)
    }

    /// 今天這期不算時的下一期（[v25.583] 每兩週＝第一期 +14）
    private var nextAfterToday: Date? {
        if cycle == .biweekly {
            return firstFromToday.map { WealthCal.addDays(14, to: $0) }
        }
        return firstPeriod(onOrAfter: tomorrow)
    }

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

    /// 今天剛好是那一期的問句：新增、沒選〔更早…〕才問（選了更早的，今天那期跟以前的期一樣算）
    private var showsTodaySection: Bool { !isEditing && !earlyOpen && todayIsPeriod }

    /// 週期、每月幾日、沒有這天的月份、星期幾跟打開時不一樣。[v25.583] 每兩週同每週比星期幾；每年多比幾月；遇六日不算
    private func scheduleChanged(_ o: WealthTransferUIOriginal) -> Bool {
        if cycle != o.cycle { return true }
        switch cycle {
        case .weekly, .biweekly:
            return weekday != o.weekday
        case .monthly:
            return storedDay != o.day || storedShort != o.short
        case .yearly:
            return yearMonth != o.month || storedDay != o.day || storedShort != o.short
        }
    }

    /// 第一期（存成 startKey）。新增：〔更早…〕選的那天以後第一期；今天剛好是那一期，選〔不算〕＝下一期。
    /// 改：原本的第一期（改了日子＝新的日子在原本第一期以後的第一期，〔全部都改〕存的就是它）
    private var startDay: Date? {
        if let o = original {
            guard let first = o.firstDay else { return nil }
            guard scheduleChanged(o) else { return first }
            // [審查修] 跟〔全部都改〕存的同一套（WealthTransferUIFormValues.scheduleEditedAll：firstDate、原本的日子），
            // 「共 N 次：最後一次…」、銀行設到哪天才對得上
            return WealthTransferSchedule.firstDate(cycle: cycle, day: storedDay, short: storedShort, weekday: weekday,
                                                    month: yearMonth, onOrAfter: first)
        }
        if isEditing { return nil }
        if earlyOpen { return firstPeriod(onOrAfter: WealthCal.day(earlyDay)) }
        if todayIsPeriod {
            // [v25.583] 今天那期的 key 是原本的日子（提前到今天的那期不是今天的 key）
            return todayChoice == .skip ? nextAfterToday : firstFromToday
        }
        return firstFromToday
    }

    /// 選了〔更早…〕而且第一期在今天（含）以前：下面那個小框
    private var startIsPast: Bool {
        guard !isEditing, earlyOpen, let s = startDay else { return false }
        return s <= today
    }

    private var earlyRange: ClosedRange<Date> {
        WealthCal.addMonths(-Self.earliestMonths, to: today)...today
    }

    /// 只有日子的規則（設到哪天、接下來三個日子用；還沒選帳戶也算得出來）。[v25.583] 每年帶 month、遇六日帶 holiday
    private var scheduleRule: WealthTransferRule? {
        guard let s = startDay else { return nil }
        let dated = isDated
        return WealthTransferRule(cycle: cycle.rawValue, day: dated ? storedDay : nil,
                                  short: dated ? storedShort : nil, month: cycle == .yearly ? yearMonth : nil,
                                  startKey: WealthTransferSchedule.key(of: s), holiday: holidayValue.raw)
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

    /// 存檔時照「那一條」的日子換算（改日子〔下一期起〕的新那條照新的日子）。
    /// 〔共幾次〕存成表單上「共 N 次：最後一次 X」那天：改日子〔下一期起〕的新那條從明天才開始，照次數重數會停得比看到的晚
    private var endSpec: WealthTransferUIEndSpec {
        switch endMode {
        case .noEnd: return .noEnd
        case .byDate: return .date(WealthCal.day(endDate))
        case .byCount:
            if let last = lastPeriod { return .date(last) }
            return .count(timesValue)
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
        // [v25.583] 寫實際那天（遇六日挪過的）
        let actual = WealthTransferSchedule.shifted(last, holiday: holidayValue)
        return "共 \(n) 次：最後一次 " + WealthTransferUIText.day(actual, today: today)
    }

    /// 最下面「接下來：11/8（日）、12/8（二）、2027/1/8（五）」（今天以後的；改的時候不含今天）。
    /// [v25.583] 列**實際那天**（遇六日挪過的：periods 的 day）；每年的往後看 3 年多（lookAheadDays）
    private var previewLine: String? {
        guard var r = scheduleRule else { return nil }
        if let last = lastPeriod { r.endKey = WealthTransferSchedule.key(of: last) }
        let through = WealthCal.addDays(WealthTransferSchedule.lookAheadDays(cycle), to: today)
        let list: [WealthTransferPeriod] = WealthTransferSchedule.periods(r, through: through, today: today)
        let lower: Date = isEditing ? tomorrow : today
        let days: [Date] = list.map { $0.day }.filter { $0 >= lower }
        let texts: [String] = days.prefix(3).map { WealthTransferUIText.day($0, today: today) }
        guard !texts.isEmpty else { return nil }
        return "接下來：" + texts.joined(separator: "、")
    }

    /// [v25.583] 「從」「到」能存：兩個不一樣的帳戶，或同一個帳戶兩個不一樣的幣別（同一個帳戶又同幣別＝擋）
    private var accountsReady: Bool {
        guard let f = from, let t = toId else { return false }
        return f != t || isExchange
    }

    private var saveDisabled: Bool {
        guard !editMissing, accountsReady, amountValue != nil, startDay != nil else { return true }
        // [v25.583] 換匯一定要填對方收到多少
        if isExchange && toAmountValue == nil { return true }
        return endInvalid
    }

    /// 名字的 placeholder「薪轉 → 房貸扣款」；[v25.583] 同一個帳戶「存錢 台幣 → USD」
    private var namePlaceholder: String {
        let f: String = choiceName(from) ?? "薪轉"
        if isSameAccount {
            return WealthTransferText.pairTitle(fromName: f, toName: f, fromCode: fromCode, toCode: toCode,
                                                sameAccount: true)
        }
        return f + " → " + (choiceName(toId) ?? "房貸扣款")
    }

    /// [v25.583] 每兩週同每週「今天（10/23）剛好是週五，這期呢？」；每年同每月；遇六日挪到今天的那期一律「剛好是轉帳那天」
    private var todayQuestion: String {
        let d = WealthFormat.monthDay(today)
        let moved: Bool = firstFromToday.map { WealthCal.dayKey($0) != WealthCal.dayKey(today) } ?? false
        if (cycle == .weekly || cycle == .biweekly) && !moved {
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

    /// 〔今天這期不算（從下一期 10/30 起）〕（[v25.583] 寫實際那天）
    private var skipLabel: String {
        guard let n = nextAfterToday else { return "今天這期不算（從下一期起）" }
        let actual = WealthTransferSchedule.shifted(n, holiday: holidayValue)
        return "今天這期不算（從下一期 " + WealthTransferUIText.shortDay(actual, today: today) + " 起）"
    }

    /// [v25.583] 寫實際那天；挪過的多寫原本那天「11/2（一）（11/1 是星期日，順延）」
    private var startText: String {
        guard let s = startDay else { return "—" }
        let actual = WealthTransferSchedule.shifted(s, holiday: holidayValue)
        let t = WealthTransferUIText.shiftedDay(s, holiday: holidayValue, today: today)
        return WealthCal.dayKey(actual) == WealthCal.dayKey(today) ? "今天 " + t : t
    }

    /// 「第一期」「下一期」
    private var startRowTitle: String { (earlyOpen || todayIsPeriod) ? "第一期" : "下一期" }

    private var startFooter: String {
        if earlyOpen { return "選了以前的日子：以前的期都會出現在明細；只有每個帳戶最近一次對存摺之後的期會動到今天的數字。" }
        return "今天以前的期不算，不會一次多出好幾期。"
    }

    /// 〔改金額或帳戶〕唯讀那一行「2026/11/6」
    private var editFirstText: String {
        guard let d = original?.firstDay else { return "—" }
        return WealthFormat.ymd(d)
    }

    /// [v25.583] 每兩週同每週（記帳的固定支出沒有每兩週）；每年同每月（三顆照給，帶每年）
    private var outsideText: String {
        if cycle == .weekly {
            return "記帳的固定支出沒有每週：請改每月，或把對方的帳戶也加進 App"
        }
        if cycle == .biweekly {
            return "記帳的固定支出沒有每兩週：請改每月，或把對方的帳戶也加進 App"
        }
        let f = choiceName(from) ?? "轉出的帳戶"
        return "轉給家人、房東是花掉的錢，請記在記帳的固定支出（從 " + f + " 扣），這樣本月還能花、稅務才對。"
            + "記帳的固定支出會照記帳的顯示設定出現在小工具『接下來要繳』和手錶（主畫面小工具照隱藏金額）。"
    }

    private var footerText: String {
        if isOutside { return "這裡什麼都不存。" }
        let base = "App 不會幫你轉錢，只照你在銀行的設定算進兩個帳戶。銀行那邊改了，這裡也要改。"
        // [v25.583] 換匯多一句
        return isExchange ? base + "換匯：兩邊金額照你填的，不跟設定的匯率。" : base
    }

    /// [v25.583] 換匯那一格下面的小字：一邊是台幣「等於 1 USD＝32.0。兩邊金額都存在這條規則裡…」；兩邊都外幣「兩邊都是外幣：兩邊金額都你填」
    private var exchangeFooter: String {
        guard FinanceRates.isNTD(fromCode) || FinanceRates.isNTD(toCode) else {
            return "兩邊都是外幣：兩邊金額都你填。"
        }
        let tail = "兩邊金額都存在這條規則裡，設定改匯率也不會變；哪一期銀行實際換多少，點那一期改。"
        guard let v = amountValue, let tv = toAmountValue,
              let line = WealthTransferExchange.rateLine(v, code: fromCode, to: tv, toCode: toCode) else { return tail }
        return line + "。" + tail
    }

    private var amountForDialog: String {
        if let m = asking, let t = askAmounts[m.id] { return t }
        return WealthFormat.grouped(amountValue ?? 0, decimals: 0)
    }

    /// 欄位串起來：變了 0.5 秒才重算提示、預覽、〔更早…〕的影響（打字時不算）
    private var previewKey: String {
        var parts: [String] = [loaded ? "L" : "-", from?.uuidString ?? "-"]
        switch target {
        case .unpicked: parts.append("u")
        case .outside: parts.append("o")
        case .account(let id): parts.append(id.uuidString)
        }
        parts.append(amountText)
        parts.append(cycle.rawValue + "/\(monthDay)/\(weekday)")
        parts.append(shortNext ? "n" : "l")
        // [v25.583] 幣別、對方收到、遇六日、每年幾月、每兩週下一次是哪天
        parts.append(fromCode + ">" + toCode + "=" + toAmountText)
        let holidayPart: String = holidayValue.raw ?? "-"
        let laterPart: String = biweeklyLater ? "b" : "-"
        parts.append(holidayPart + "/\(yearMonth)/" + laterPart)
        parts.append(startDay.map { WealthCal.dayKey($0) } ?? "-")
        switch endMode {
        case .noEnd: parts.append("e0")
        case .byDate: parts.append("e1" + WealthCal.dayKey(endDate))
        case .byCount: parts.append("e2" + timesText)
        }
        parts.append(manual ? "m" : "a")
        // 今天剛好是那一期：〔存摺上已經有了〕〔還沒，今天會轉〕第一期一樣、草稿的註記不一樣
        if showsTodaySection {
            switch todayChoice {
            case .skip: parts.append("ts")
            case .count: parts.append("tc")
            case .late: parts.append("tl")
            }
        } else {
            parts.append("t-")
        }
        parts.append(masked ? "x" : "-")
        parts.append(earlyOpen ? "E" : "-")
        parts.append("\(lifeStore.wealthRevision)")
        return parts.joined(separator: "|")
    }

    // MARK: 畫面

    var body: some View {
        NavigationStack {
            formBody
                .navigationTitle(titleText)
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
                .modifier(formWatch)
                .task(id: previewKey) { await recomputeLater() }
        }
        .modifier(WealthTransferUIEditDialog(asking: editAsk,
                                             onAnswer: { a, x in answerEdit(a, x) },
                                             onClose: { closeEditAsk() }))
        .sheet(item: $pickList, onDismiss: { pickClosed() }) { list in
            WealthTransferUIPickSheet(list: list, onPick: { k in pickedKey = k })
                .appStores()
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    /// [v25.583] 幣別、換匯的三個 onChange
    private var formWatch: WealthTransferUIFormWatch {
        WealthTransferUIFormWatch(codesKey: codesKey, exchangeKey: exchangeKey, isExchange: isExchange,
                                  onCodes: { codesChanged() }, onAmounts: { amountsChanged() },
                                  onExchange: { x in exchangeToggled(x) })
    }

    @ViewBuilder
    private var formBody: some View {
        if editMissing {
            Form {
                Section {
                    Text("這條定期轉帳已經刪了")
                        .foregroundStyle(Color.secondary)
                }
            }
        } else {
            Form {
                if let line = leadLine {
                    leadSection(line)
                }
                accountsSection
                amountSection
                cycleSection
                if isOutside {
                    outsideSection
                } else {
                    if showsHolidayRow {
                        holidaySection
                    }
                    if showsTodaySection {
                        todaySection
                    }
                    if isEditing {
                        editStartSection
                    } else {
                        startSection
                    }
                    endSection
                    whoSection
                    nameSection
                    previewSection
                }
                footerSection
            }
        }
    }

    /// [v25.581] 「照記帳的『轉玉山存錢』帶好了；存檔時會問記帳那筆怎麼辦」
    private func leadSection(_ line: String) -> some View {
        Section {
            Text(line)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// [v25.583] 外幣帳戶也列（拿掉 v1 的「只列有台幣」）；「到」多「同一個帳戶（換匯）」；兩個以上幣別多「轉出幣別」「對方幣別」
    private var accountsSection: some View {
        Section {
            Picker("從", selection: $from) {
                ForEach(choices) { c in
                    Text(c.label).tag(c.id as UUID?)
                }
            }
            fromCodeRow
            Picker("到", selection: $target) {
                Text("選一個").tag(WealthTransferUITarget.unpicked)
                ForEach(toChoices) { c in
                    Text(c.label).tag(WealthTransferUITarget.account(c.id))
                }
                if let f = from, offersSameAccount {
                    Text("同一個帳戶（換匯）").tag(WealthTransferUITarget.account(f))
                }
                if !isEditing && FinanceRates.isNTD(fromCode) {
                    Text("不在 App 裡的人（家人、房東…）").tag(WealthTransferUITarget.outside)
                }
            }
            toCodeRow
        } header: {
            WealthFormHeader(title: "從哪轉到哪", icon: "arrow.left.arrow.right", color: .blue)
        } footer: {
            if isSameAccount && !isExchange {
                Text("同一個帳戶：轉出、對方要選不一樣的幣別")
            }
        }
    }

    /// [v25.583] 「轉出幣別」：從的帳戶有兩個以上幣別才給
    @ViewBuilder
    private var fromCodeRow: some View {
        let list: [String] = fromCodeChoices
        if list.count >= 2 {
            Picker("轉出幣別", selection: $fromCode) {
                ForEach(list, id: \.self) { c in
                    Text(WealthTransferText.codeName(c)).tag(c)
                }
            }
        }
    }

    /// [v25.583] 「對方幣別」：到的帳戶有兩個以上幣別（同一個帳戶＝除了轉出那個）才給
    @ViewBuilder
    private var toCodeRow: some View {
        let list: [String] = toCodeChoices
        if list.count >= 2 {
            Picker("對方幣別", selection: $toCode) {
                ForEach(list, id: \.self) { c in
                    Text(WealthTransferText.codeName(c)).tag(c)
                }
            }
        }
    }

    /// [v25.583] 字頭照轉出幣別（外幣到 0.01）；換匯多一列「對方收到」＋小字
    private var amountSection: some View {
        Section {
            HStack {
                Text(WealthTransferUIText.prefix(fromCode)).foregroundStyle(Color.secondary)
                TextField("每次轉多少", text: $amountText)
                    .keyboardType(FinanceRates.isNTD(fromCode) ? .numberPad : .decimalPad)
            }
            if isExchange {
                toAmountRow
            }
        } header: {
            WealthFormHeader(title: "每次轉多少", icon: "dollarsign.circle", color: .blue)
        } footer: {
            if isExchange {
                Text(exchangeFooter)
            }
        }
    }

    /// [v25.583] 「對方收到　US$〔300〕」（你改了就不再照匯率自動帶）
    private var toAmountRow: some View {
        HStack(spacing: 8) {
            Text("對方收到")
            Spacer(minLength: 8)
            Text(WealthTransferUIText.prefix(toCode)).foregroundStyle(Color.secondary)
            TextField("多少", text: toAmountBinding)
                .keyboardType(FinanceRates.isNTD(toCode) ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 72, maxWidth: 140)
        }
    }

    /// [v25.583] 〔每月〕〔每週〕〔每兩週〕〔每年〕
    private var cycleSection: some View {
        Section {
            Picker("多久一次", selection: $cycle) {
                Text("每月").tag(WealthTransferCycle.monthly)
                Text("每週").tag(WealthTransferCycle.weekly)
                Text("每兩週").tag(WealthTransferCycle.biweekly)
                Text("每年").tag(WealthTransferCycle.yearly)
            }
            .pickerStyle(.segmented)
            cycleRows
            if !isOutside && cycle == .monthly {
                ForEach(hints) { h in
                    WealthTransferUIHintRow(hint: h)
                }
            }
        } header: {
            WealthFormHeader(title: "多久一次、哪天", icon: "calendar", color: .blue)
        } footer: {
            if let line = cycleFooter {
                Text(line)
            }
        }
    }

    /// [v25.583] 每月：幾日；每年：幾月＋幾日；每週：星期幾；每兩週：星期幾＋「下一次是哪天」
    @ViewBuilder
    private var cycleRows: some View {
        switch cycle {
        case .monthly:
            monthDayRows
        case .yearly:
            Picker("每年幾月", selection: $yearMonth) {
                ForEach(1...12, id: \.self) { m in
                    Text("\(m) 月").tag(m)
                }
            }
            monthDayRows
        case .weekly:
            weekdayRow
        case .biweekly:
            weekdayRow
            biweeklyRows
        }
    }

    private var weekdayRow: some View {
        Picker("星期幾", selection: $weekday) {
            ForEach(Self.weekdayOrder, id: \.self) { w in
                Text(Self.weekdayNames[w - 1]).tag(w)
            }
        }
        .pickerStyle(.segmented)
    }

    /// [v25.583] 每兩週「下一次是哪天」兩選一（照銀行 App 上的下一次）：〔今天 10/23（五）〕〔10/30（五）〕；只在新增、沒選〔更早…〕時
    @ViewBuilder
    private var biweeklyRows: some View {
        if !isEditing && !earlyOpen, let d0 = biweeklyBase {
            Text("下一次是哪天（照銀行 App 上的）")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            WealthTransferUIChoiceRow(title: biweeklyLabel(d0), selected: !biweeklyLater) {
                biweeklyLater = false
            }
            WealthTransferUIChoiceRow(title: biweeklyLabel(WealthCal.addDays(7, to: d0)), selected: biweeklyLater) {
                biweeklyLater = true
            }
        }
    }

    /// 「今天 10/23（五）」「10/30（五）」（實際那天）
    private func biweeklyLabel(_ original: Date) -> String {
        let actual = WealthTransferSchedule.shifted(original, holiday: holidayValue)
        let t = WealthTransferUIText.day(actual, today: today)
        return WealthCal.dayKey(actual) == WealthCal.dayKey(today) ? "今天 " + t : t
    }

    /// 「沒有這天的月份」那一列的小字（每年的多一句 2/29）
    private var cycleFooter: String? {
        guard showsShortRow else { return nil }
        let bank = "玉山、郵局是當月最後一天；國泰世華是下個月 1 號"
        if cycle == .yearly {
            return bank + "。每年 2/29：沒有 29 號的年份照「沒有這天的月份」。"
        }
        return bank + "（11 月那期會在 12/1）"
    }

    /// [v25.583] 每年的「幾日」、每月的「每月幾日」
    private var dayPickerTitle: String { cycle == .yearly ? "幾日" : "每月幾日" }

    @ViewBuilder
    private var monthDayRows: some View {
        Picker(dayPickerTitle, selection: $monthDay) {
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

    /// [v25.583] 「遇六日」〔照當天〕〔順延到星期一〕〔提前到星期五〕＋小字（換匯預設順延；你動過就不跟著換）
    private var holidaySection: some View {
        Section {
            Picker("遇六日", selection: holidayBinding) {
                ForEach(Self.holidayChoices.indices, id: \.self) { i in
                    Text(WealthTransferText.holidayLabel(Self.holidayChoices[i])).tag(i)
                }
            }
        } footer: {
            Text(WealthTransferText.holidayFooter)
        }
    }

    private var outsideSection: some View {
        Section {
            Text(outsideText)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if cycle == .monthly || cycle == .yearly {
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
                Text(startRowTitle)
                Spacer(minLength: 8)
                Text(startText)
                    .foregroundStyle(Color.accentColor)
            }
            if earlyOpen {
                DatePicker("從哪天起", selection: $earlyDay, in: earlyRange, displayedComponents: .date)
                    .onChange(of: earlyDay) { _, _ in earlyAccepted = false }
                earlyBox
            } else {
                Button("更早…") { openEarly() }
            }
        } header: {
            WealthFormHeader(title: "從哪一期開始算進 App", icon: "flag", color: .blue)
        } footer: {
            Text(startFooter)
        }
    }

    /// 〔更早…〕選了以前的：「從 2026/1/6 起：以前 10 期都會出現在明細；…」〔改成從下一期起〕〔照我選的〕
    @ViewBuilder
    private var earlyBox: some View {
        if startIsPast, let e = early {
            Text(e.text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            if let d = e.duplicateText {
                Text(d)
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !earlyAccepted {
                Button(earlyResetLabel(e)) { resetEarly() }
                Button("照我選的") { earlyAccepted = true }
            }
        }
    }

    /// 〔改金額或帳戶〕：第一期唯讀
    private var editStartSection: some View {
        Section {
            HStack {
                Text("第一期")
                Spacer(minLength: 8)
                Text(editFirstText)
                    .foregroundStyle(Color.secondary)
            }
        } header: {
            WealthFormHeader(title: "從哪一期開始算進 App", icon: "flag", color: .blue)
        } footer: {
            Text("改了金額、帳戶或日子，存檔時會問從哪一期起改；以前的可以照舊。")
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
            Text("銀行自動轉的，到那天 App 就當作轉了；可能不夠時前一晚提醒你。自己轉的，那天早上 9 點提醒，轉好了按〔轉好了〕。")
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

    /// 最下面：「接下來：…」＋停 0.5 秒才算的「11/8 轉完，薪轉約剩 61,400 ✓」那幾行
    private var previewSection: some View {
        previewBlock(previewLine, lines: previewReady ? previewLines : [])
    }

    /// 欄位還沒填好時不留上一次算的字（[v25.583] 同一個帳戶換匯也算填好）
    private var previewReady: Bool {
        guard accountsReady else { return false }
        return amountValue != nil
    }

    @ViewBuilder
    private func previewBlock(_ line: String?, lines: [WealthTransferPreviewLine]) -> some View {
        if line != nil || !lines.isEmpty {
            Section {
                if let line {
                    Text(line)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(lines) { l in
                    WealthTransferUIPreviewRow(line: l)
                }
            } header: {
                if !lines.isEmpty {
                    Text("照你現在記的算")
                }
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
        var names: [UUID: String] = [:]
        for a in facts.accounts where names[a.id] == nil {
            names[a.id] = a.name
        }
        accountNames = names
        let todayKey = WealthCal.dayKey(t)
        var anchored = Set<UUID>()
        for a in facts.banks {
            if let d = a.lastAnchorDate, WealthCal.dayKey(d) == todayKey { anchored.insert(a.id) }
        }
        anchoredToday = anchored
        let cal = WealthCal.calendar
        monthDay = cal.component(.day, from: t)
        weekday = cal.component(.weekday, from: t)
        yearMonth = cal.component(.month, from: t)
        endDate = WealthCal.addMonths(12, to: t)
        earlyDay = WealthCal.addMonths(-1, to: t)
        rates = FinanceRates(expenseStore)
        if let rid = editRuleId {
            loadEdit(rid, facts: facts)
            return
        }
        // [v25.583] 外幣帳戶也列（v1 只列有台幣那一格的）
        let all = WealthFormAccountChoice.banks(facts, including: fromId, includeFixed: true)
        choices = all
        // 帶進來的帳戶 → 帶好的欄位 → 月薪入帳的那個（defaultTransferFromId）→ 第一個
        let wanted: [UUID] = [fromId, preset?.fromId, facts.defaultTransferFromId].compactMap { $0 }
        let f: UUID? = wanted.first(where: { w in all.contains(where: { $0.id == w }) }) ?? all.first?.id
        from = f
        // [v25.583] 轉出幣別＝那個帳戶的預設（有台幣＝台幣）；帶好的「到」照它挑對方幣別（記住依據：onChange 不重挑）
        let fc: String = Self.defaultFromCode(Self.normalized(all.first(where: { $0.id == f })?.codes ?? []))
        fromCode = fc
        fromBasis = f
        var picked: WealthTransferUITarget = .unpicked
        if let p = preset { picked = applyPreset(p, from: f, choices: all) }
        if case .account(let tid) = picked {
            let list = Self.normalized(all.first(where: { $0.id == tid })?.codes ?? [])
            toCode = Self.defaultToCode(list, fromCode: fc, same: tid == f)
        }
        codesBasis = Self.makeCodesKey(from: f, fromCode: fc, target: picked)
    }

    /// [v25.583] 幣別 WealthFacts.norm 過、不重複（台幣在前照帳戶的順序）
    private static func normalized(_ codes: [String]) -> [String] {
        var out: [String] = []
        for x in codes.map({ WealthFacts.norm($0) }) where !out.contains(x) {
            out.append(x)
        }
        return out
    }

    /// 〔改成每月定期轉帳〕帶好的欄位：到（在選單裡、不是「從」才帶）、金額、多久一次、每月幾日（31＝最後一天）、沒有這天的月份。
    /// [v25.583] 回帶好的「到」（load 照它挑對方幣別）
    @discardableResult
    private func applyPreset(_ p: WealthTransferPreset, from f: UUID?,
                             choices list: [WealthFormAccountChoice]) -> WealthTransferUITarget {
        var picked: WealthTransferUITarget = .unpicked
        if let t = p.toId, t != f, list.contains(where: { $0.id == t }) {
            target = .account(t)
            picked = .account(t)
        }
        if let v = p.amount, v >= 1 {
            amountText = WealthFormText.editable(v.rounded())
        }
        cycle = p.cycle
        if let d = p.day {
            if d >= 31 && p.short != "next" {
                monthDay = 32
                shortNext = false
            } else {
                monthDay = Swift.min(Swift.max(d, 1), 31)
                shortNext = p.short == "next"
            }
        }
        return picked
    }

    /// 〔改金額或帳戶〕：照存著的那一條帶好（從、到、金額＝下一期那一段）；找不到＝「這條定期轉帳已經刪了」
    private func loadEdit(_ rid: UUID, facts: WealthFacts) {
        guard let tr = facts.transferRule(rid) else {
            editMissing = true
            return
        }
        let r = tr.rule
        let cal = WealthCal.calendar
        // 下一期那一段（沒有下一期＝最後一段）；暫停那段的 0 不帶，改帶下一期的金額
        let seg: WealthTransferSegment? = tr.next.flatMap { r.segment(at: $0.key) } ?? r.lastSegment
        let f: UUID? = seg?.fromId ?? tr.fromId
        let to: UUID? = seg?.toId ?? tr.toId
        let segAmount: Double = seg?.amount ?? 0
        let amount: Double = segAmount > 0.004 ? segAmount : tr.amount
        // [v25.583] 兩個幣別、對方收到多少（換匯才有；暫停那段的照下一期）
        // 段裡 nil＝台幣（v1a 的寫法）；沒有段才照 facts 那條
        let fc: String = WealthFacts.norm(seg.map { $0.fromCode ?? "NT$" } ?? tr.code)
        let tc: String = WealthFacts.norm(seg.map { $0.toCode ?? "NT$" } ?? tr.toCode)
        var toAmt: Double? = nil
        if fc != tc {
            if segAmount > 0.004 {
                // [審查修] 段裡沒寫對方收到（舊版改過的換匯段）＝空的、照匯率重帶；不拿 facts 那條的（那是「跟轉出一樣」頂著的數，
                // 9,600 會被當成 US$9,600 帶進來）
                toAmt = seg?.toAmount
            } else if tr.isExchange {
                toAmt = tr.toAmount
            }
        }
        // 選單：[v25.583] 全部的銀行（外幣帳戶也列）＋現在的從、到（不在選單裡手動補；帳戶找不到用名字頂著）
        var list: [WealthFormAccountChoice] = WealthFormAccountChoice.banks(facts, including: f, includeFixed: true)
        Self.appendChoice(f, fallback: tr.fromName, facts: facts, to: &list)
        Self.appendChoice(to, fallback: tr.toName, facts: facts, to: &list)
        choices = list
        from = f
        fromBasis = f
        fromCode = fc
        toCode = tc
        var picked: WealthTransferUITarget = .unpicked
        if let to {
            target = .account(to)
            picked = .account(to)
        }
        codesBasis = Self.makeCodesKey(from: f, fromCode: fc, target: picked)
        amountText = WealthFormText.editable(amount)
        toAmountText = toAmt.map { WealthFormText.editable($0) } ?? ""
        // [審查修] 存著對方收到多少＝當作你動過（改的時候不跟著匯率換）；沒存（同幣別的改成換匯、舊版改過的換匯段）＝照新增的規矩帶匯率
        toAmountTouched = toAmt != nil
        // 週期、每月（每年）幾日（31 且不是下個月 1 號＝最後一天）、每週（每兩週）星期幾（第一期那天）、[v25.583] 每年幾月
        let kind: WealthTransferCycle = r.cycleKind ?? .monthly
        let first: Date? = r.startKey.flatMap { WealthTransferSchedule.date(fromKey: $0) }
        let t = facts.today
        var md: Int = cal.component(.day, from: t)
        var sn = false
        var wd: Int = cal.component(.weekday, from: t)
        var ym: Int = cal.component(.month, from: t)
        switch kind {
        case .monthly, .yearly:
            let d: Int = r.day ?? first.map { cal.component(.day, from: $0) } ?? 1
            if d >= 31 && r.short != "next" {
                md = 32
            } else {
                md = Swift.min(Swift.max(d, 1), 31)
                sn = r.short == "next"
            }
            if kind == .yearly {
                let m: Int = r.month ?? first.map { cal.component(.month, from: $0) } ?? ym
                ym = Swift.min(Swift.max(m, 1), 12)
            }
        case .weekly, .biweekly:
            if let s = first { wd = cal.component(.weekday, from: s) }
        }
        cycle = kind
        monthDay = md
        shortNext = sn
        weekday = wd
        yearMonth = ym
        holiday = r.holidayKind
        holidayTouched = true
        manual = r.isManual
        name = r.name ?? ""
        memo = r.memo ?? ""
        if let ek = r.endKey, let ed = WealthTransferSchedule.date(fromKey: ek) {
            endMode = .byDate
            endDate = ed
        }
        let oDay: Int = Swift.min(Swift.max(md, 1), 31)
        // 跟 storedShort 同一套（每年的那個月一定有這天＝不給那一列、存 nil）
        let oShort: String? = (Self.shortRowShown(cycle: kind, monthDay: md, month: ym) && sn) ? "next" : nil
        original = WealthTransferUIOriginal(ruleId: rid, firstDay: first, fromId: f, toId: to, amount: amount,
                                            fromCode: fc, toCode: tc, toAmount: toAmt, cycle: kind, day: oDay,
                                            short: oShort, weekday: wd, month: ym, holiday: r.holidayKind)
    }

    /// 選單沒有這個帳戶就補一列（帳戶找不到：用規則上的名字）
    private static func appendChoice(_ id: UUID?, fallback: String, facts: WealthFacts,
                                     to list: inout [WealthFormAccountChoice]) {
        guard let id, !list.contains(where: { $0.id == id }) else { return }
        if let a = facts.account(id) {
            let codes: [String] = a.currencies.isEmpty ? ["NT$"] : a.currencies
            list.append(WealthFormAccountChoice(id: a.id, name: a.name, label: a.pickerLabel, codes: codes))
        } else {
            list.append(WealthFormAccountChoice(id: id, name: fallback, label: fallback, codes: ["NT$"]))
        }
    }

    /// 換了「從」：跟「到」同一個帳戶就把「到」清掉。[v25.583] 那個帳戶有兩個以上幣別＝留著（同一個帳戶換匯）；
    /// 轉出幣別換成那個帳戶的預設（有台幣＝台幣，不然第一個）、對方幣別跟著重挑。打開時帶好的（fromBasis 一樣）不動
    private func fromChanged() {
        guard from != fromBasis else { return }
        fromBasis = from
        let list = codes(of: from)
        fromCode = Self.defaultFromCode(list)
        if let f = from, toId == f, list.count < 2 { target = .unpicked }
        codesChanged()
    }

    /// [v25.583] 「從」、轉出幣別、「到」變了：對方幣別重挑（同一個帳戶＝第一個跟轉出不一樣的；別的帳戶＝有同幣別就同幣別、
    /// 不然台幣、不然第一個）。轉出幣別不是台幣時「不在 App 裡的人」拿掉。打開時帶好的、剛挑過的（codesBasis 一樣）不動
    private func codesChanged() {
        if target == .outside && !FinanceRates.isNTD(fromCode) { target = .unpicked }
        let k = codesKey
        guard k != codesBasis else { return }
        codesBasis = k
        guard let t = toId else { return }
        let list: [String] = codes(of: t)
        guard !list.isEmpty else { return }
        toCode = Self.defaultToCode(list, fromCode: fromCode, same: isSameAccount)
    }

    /// [v25.583] 金額、幣別變了：你沒動過「對方收到」＝照現在設定的匯率重帶（一邊是台幣才帶得出來；兩邊都外幣、查不到匯率＝空的）
    private func amountsChanged() {
        guard !toAmountTouched else { return }
        guard isExchange, let v = amountValue,
              let d = WealthTransferExchange.defaultToAmount(v, from: fromCode, to: toCode, rates: rates) else {
            toAmountText = ""
            return
        }
        toAmountText = WealthFormText.editable(d)
    }

    /// [v25.583] 換匯預設〔順延到星期一〕、不是換匯〔照當天〕（你動過「遇六日」就不跟著換）
    private func exchangeToggled(_ x: Bool) {
        guard !holidayTouched else { return }
        holiday = x ? .next : .onDay
    }

    // MARK: 〔更早…〕

    /// 展開 DatePicker（預設一期前：每週 7 天前、每月一個月前；[v25.583] 每兩週 14 天前、每年一年前）
    private func openEarly() {
        switch cycle {
        case .weekly: earlyDay = WealthCal.addDays(-7, to: today)
        case .biweekly: earlyDay = WealthCal.addDays(-14, to: today)
        case .monthly: earlyDay = WealthCal.addMonths(-1, to: today)
        case .yearly: earlyDay = WealthCal.addMonths(-12, to: today)
        }
        earlyAccepted = false
        earlyOpen = true
    }

    /// 〔改成從下一期起〕〔從下一期 11/6 起就好〕：回到預設下一期
    private func resetEarly() {
        earlyOpen = false
        earlyAccepted = false
        early = nil
        todayChoice = .skip
    }

    private func earlyResetLabel(_ e: WealthTransferEarlyImpact) -> String {
        if e.duplicateText != nil, let d = e.nextDay {
            return "從下一期 " + WealthTransferText.dayText(d, today: today) + " 起就好"
        }
        return "改成從下一期起"
    }

    // MARK: 停 0.5 秒才算（提示、預覽、〔更早…〕的影響）

    @MainActor
    private func recomputeLater() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        if Task.isCancelled { return }
        recompute()
    }

    private func recompute() {
        guard loaded, !editMissing, !isOutside, accountsReady, let f = from, let t = toId,
              let draft = draftRule(fromId: f, toId: t) else {
            hints = []
            previewLines = []
            early = nil
            return
        }
        let before = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        if cycle == .monthly {
            hints = WealthTransferHints.make(rule: hintRule(draft), toName: choiceName(t) ?? "",
                                             expenses: expenseStore.expenses, incomes: expenseStore.incomes,
                                             book: lifeStore.wealthBook, today: today)
        } else {
            hints = []
        }
        early = earlyImpact(draft, fromId: f, facts: before)
        previewLines = previewLinesFor(draft, before: before)
    }

    /// [v25.583] 一段：幣別照表單（台幣存 nil，v1a 的寫法）、換匯才帶對方收到多少
    private func makeSegment(fromId f: UUID, toId t: UUID, amount v: Double, toAmount ta: Double?) -> WealthTransferSegment {
        WealthTransferSegment(fromKey: "", fromId: f, fromCode: WealthTransferExchange.storedCode(fromCode), toId: t,
                              toCode: WealthTransferExchange.storedCode(toCode), amount: v,
                              toAmount: isExchange ? ta : nil)
    }

    /// 草稿（預覽、提示、〔更早…〕用）：一段（從、到、金額；還沒打金額＝0）、第一期＝startDay、id＝draftId、createdAt＝現在（排在最後）。
    /// [v25.583] 段帶幣別、對方收到（還沒打＝0：那一邊不算）；規則帶每年幾月、遇六日
    private func draftRule(fromId f: UUID, toId t: UUID) -> WealthTransferRule? {
        guard let s = startDay else { return nil }
        let dated = isDated
        let seg = makeSegment(fromId: f, toId: t, amount: amountValue ?? 0, toAmount: toAmountValue ?? 0)
        var r = WealthTransferRule(id: draftId, cycle: cycle.rawValue, day: dated ? storedDay : nil,
                                   short: dated ? storedShort : nil, month: cycle == .yearly ? yearMonth : nil,
                                   startKey: WealthTransferSchedule.key(of: s), mode: manual ? "manual" : nil,
                                   holiday: holidayValue.raw, segments: [seg], createdAt: Date())
        if let last = lastPeriod { r.endKey = WealthTransferSchedule.key(of: last) }
        // 跟存檔那條一樣：〔還沒，今天會轉〕今天那期排在對存摺後面（不然「轉完約剩」會照對存摺之前算）
        r.notes = lateNotes(now: Date())
        return r
    }

    /// 提示照「下一期」看（改的時候、選了更早的：第一期換成今天以後第一期）
    private func hintRule(_ draft: WealthTransferRule) -> WealthTransferRule {
        guard isEditing || earlyOpen else { return draft }
        var r = draft
        r.startKey = WealthTransferPlan.nextKey(draft, today: today) ?? draft.startKey
        return r
    }

    /// 〔更早…〕第一期在今天（含）以前：照每個帳戶最近一次對存摺算會不會動到今天（手記過的單次轉帳也講）
    private func earlyImpact(_ draft: WealthTransferRule, fromId f: UUID, facts: WealthFacts) -> WealthTransferEarlyImpact? {
        guard startIsPast, amountValue != nil else { return nil }
        let deposits: [BankDeposit] = lifeStore.milestones.first(where: { $0.id == f })?.bankDeposits ?? []
        return facts.transferEarlyImpact(rule: draft, fromDeposits: deposits, masked: masked)
    }

    /// 最下面的預覽：帶著這條（新增的草稿／照存檔的預設答案改好的那條）重算一次（wealthFactsPreview，不走快取）
    private func previewLinesFor(_ draft: WealthTransferRule, before: WealthFacts) -> [WealthTransferPreviewLine] {
        guard amountValue != nil else { return [] }
        var book = lifeStore.wealthTransfers
        let rule: WealthTransferRule
        if let o = original {
            // 名字、備註不影響數字：照存著的（只改名字不重算）
            guard let base = book.rule(o.ruleId),
                  let values = formValues(name: base.name, memo: base.memo) else { return [] }
            if values.scheduleChanged {
                // 預設答案〔下一期起〕：舊的停在明天以前最後一期、新的一條接上；以前一期都沒有＝同一條換日子
                if let lastKey = WealthTransferPlan.splitLastKey(base, from: tomorrow),
                   var next = values.splitNext(id: draftId, effective: tomorrow) {
                    var old = base
                    old.endKey = lastKey
                    old.endedBy = nil
                    book.upsert(old)
                    next.previousId = base.id
                    next.createdAt = Date()
                    book.upsert(next)
                    rule = next
                } else {
                    rule = values.scheduleEditedAll(base)
                    book.upsert(rule)
                }
            } else if !values.change.isEmpty {
                // 預設答案〔下一期起〕
                rule = values.segmentEdited(base, from: WealthTransferPlan.nextKey(base, today: today) ?? "")
                book.upsert(rule)
            } else {
                let plain = values.plainEdited(base)
                if plain == base {
                    return WealthTransferPreview.lines(rule: previewShown(base), before: before, after: before,
                                                       masked: masked)
                }
                rule = plain
                book.upsert(rule)
            }
        } else {
            rule = draft
            book.upsert(draft)
        }
        let after = lifeStore.wealthFactsPreview(transfers: book, expense: expenseStore, finance: financeStore)
        return WealthTransferPreview.lines(rule: previewShown(rule), before: before, after: after, masked: masked)
    }

    /// [裁定修] 改的時候預覽從下一期講起（同「接下來：」那行、hintRule）：今天剛好是一期的話那一期照舊轉，
    /// 預設答案〔下一期起〕改的是下一期以後——不然會寫今天那期（舊的金額）「10/30 轉完，薪轉約剩 …」。
    /// 只換這份拷貝的第一期（同一個 id、key 不變：WealthTransferPreview 找列、找不夠扣照舊對得上）
    private func previewShown(_ r: WealthTransferRule) -> WealthTransferRule {
        guard isEditing, let nk = WealthTransferPlan.nextKey(r, today: today) else { return r }
        var x = r
        x.startKey = nk
        return x
    }

    // MARK: 不在 App 裡的人：帶去記帳

    /// 〔給家人（孝親費）〕〔付房租（報稅可扣）〕〔其他〕：記帳新增固定支出（每月、日子、扣款帳戶、金額帶好；名稱空著）
    private func openExpense(_ category: FixedCategory) {
        // [v25.583] 每年的帶每年
        let rec: Recurrence = cycle == .yearly ? .yearly : .monthly
        let preset = AddExpensePreset(fixedCategory: category, recurrence: rec, date: firstFromToday,
                                      paymentBankId: from, amount: amountValue)
        expenseAsk = WealthTransferUIExpenseAsk(preset: preset)
    }

    /// 記帳那張關掉（存了或取消）：這張表一起關
    private func closeAfterExpense() {
        let close = dismiss
        DispatchQueue.main.async { close() }
    }

    // MARK: 存檔（新增）

    /// 組好要存的那一條（name、memo 已經去空白、遮好；空＝nil）
    private func makeRule(name: String?, memo: String?) -> WealthTransferRule? {
        guard var r = scheduleRule, accountsReady, let f = from, let t = toId, let v = amountValue, !endInvalid else {
            return nil
        }
        // [v25.583] 換匯一定要有對方收到多少（寫死在段裡，不跟設定的匯率）
        let ta: Double? = isExchange ? toAmountValue : nil
        if isExchange && ta == nil { return nil }
        r.mode = manual ? "manual" : nil
        r.segments = [makeSegment(fromId: f, toId: t, amount: v, toAmount: ta)]
        r.name = name
        r.memo = memo
        if let last = lastPeriod { r.endKey = WealthTransferSchedule.key(of: last) }
        if let notes = lateNotes(now: Date()) { r.notes = notes }
        return r
    }

    /// 〔還沒，今天會轉〕：今天這期算，今天對過存摺的那一邊排在對存摺後面（選了〔更早…〕不問這句）。存檔、預覽的草稿共用
    /// [v25.583] key＝第一期**原本的**日子（遇六日挪到今天的那期 key 是原本那天，不是今天）
    private func lateNotes(now: Date) -> [String: WealthTransferNote]? {
        guard showsTodaySection && todayChoice == .late && threeChoice, let s = startDay else { return nil }
        let k = WealthTransferSchedule.key(of: s)
        return [k: WealthTransferNote(lateOut: fromAnchored ? true : nil,
                                      lateIn: toAnchored ? true : nil,
                                      updatedAt: now)]
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

    /// mask：〔只留後 4 碼〕＝名字、備註裡像帳號的每一串換成「••8901」。新增：接著找記帳裡像同一筆的，一筆一筆問；
    /// 改：問從哪一期起改（不問「是同一筆嗎？」）
    private func proceed(mask: Bool) {
        guard !isSaving else { return }
        let n0 = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let m0 = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = mask ? WealthTransferText.maskAccountLike(n0) : n0
        let m = mask ? WealthTransferText.maskAccountLike(m0) : m0
        let nameValue: String? = n.isEmpty ? nil : n
        let memoValue: String? = m.isEmpty ? nil : m
        if isEditing {
            guard !saveDisabled, let values = formValues(name: nameValue, memo: memoValue) else { return }
            isSaving = true
            if mask {
                name = n
                memo = m
            }
            proceedEdit(values)
            return
        }
        guard let rule = makeRule(name: nameValue, memo: memoValue) else { return }
        isSaving = true
        if mask {
            name = n
            memo = m
        }
        pendingRule = rule
        endExpenses = []
        endIncomes = []
        excludeExpenses = []
        notSameMatches = []
        let asked = matchRule(rule)
        let found = WealthTransferMatcher.matches(
            rule: asked, fromName: choiceName(from) ?? "別的帳戶", toName: choiceName(toId) ?? "別的帳戶",
            expenses: expenseStore.expenses, incomes: expenseStore.incomes,
            excluded: Set(lifeStore.wealthBook.excludedExpenses ?? []))
        let queue: [WealthTransferMatch] = withPresetItems(found, rule: asked)
        askAmounts = presetAmounts(queue)
        matchQueue = queue
        askNext()
    }

    /// [v25.581] 要確認 v3 帶來的記帳那一筆（preset.matchExpenseId／matchIncomeId）一定問、排最前面（支出先、收入接在後面；
    /// 你改了金額、日子也照問，matcher 找到的同一筆拿掉）。那筆找不到（記帳刪了，matcher 也找不到）＝照 matcher 原本的；
    /// 早就結束了（forced 回 nil）＝那筆不問（matcher 在 3 天窗裡找到的也拿掉：它的備用結束日會把結束日往後延）
    private func withPresetItems(_ found: [WealthTransferMatch], rule r: WealthTransferRule) -> [WealthTransferMatch] {
        guard let p = preset else { return found }
        var queue: [WealthTransferMatch] = found
        var at = 0
        if let eid = p.matchExpenseId, let e = expenseStore.expenses.first(where: { $0.id == eid }) {
            queue.removeAll { $0.kind == .expense && $0.itemId == eid }
            let payer: String = accountName(e.linkedBankMilestoneId)
            if let m = WealthTransferMatcher.forcedExpense(rule: r, expense: e, payerName: payer) {
                queue.insert(m, at: 0)
                at = 1
            }
        }
        if let iid = p.matchIncomeId, let inc = expenseStore.incomes.first(where: { $0.id == iid }) {
            queue.removeAll { $0.kind == .income && $0.itemId == iid }
            let into: String = accountName(inc.linkedBankMilestoneId)
            if let m = WealthTransferMatcher.forcedIncome(rule: r, income: inc, intoName: into) {
                queue.insert(m, at: Swift.min(at, queue.count))
            }
        }
        return queue
    }

    /// [v25.581] 帶來的那筆支出「是同一筆嗎？」小字的金額＝記帳那筆自己的（你改了金額時跟這條不一樣；記帳那筆結束後還能花多的是它的金額）
    private func presetAmounts(_ queue: [WealthTransferMatch]) -> [String: String] {
        guard let eid = preset?.matchExpenseId,
              let m = queue.first(where: { $0.kind == .expense && $0.itemId == eid }),
              let e = expenseStore.expenses.first(where: { $0.id == eid }) else { return [:] }
        return [m.id: WealthTransferFinds.amountText(e.amount)]
    }

    /// 「是同一筆嗎？」照哪一期問：選了〔更早…〕的照今天以後第一期（〔是：記帳那筆從下一期起結束〕不會把以前好幾個月的記帳一起收掉）
    private func matchRule(_ rule: WealthTransferRule) -> WealthTransferRule {
        guard earlyOpen, let sk = rule.startKey, sk <= WealthCal.dayKey(today),
              let next = WealthTransferPlan.nextKey(rule, today: today) else { return rule }
        var r = rule
        r.startKey = next
        return r
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
        case .notSame:
            notSameMatches.append(m)
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

    /// 先關表單，下一個 runloop 才寫：存規則＋「是同一筆嗎？」答〔是〕的那幾筆＋[v25.581] 答〔不是〕的記住不再問
    private func finish() {
        guard let rule = pendingRule else { return }
        pendingRule = nil
        let life = lifeStore
        let expense = expenseStore
        let ends: [WealthTransferMatch] = endExpenses
        let incomes: [WealthTransferMatch] = endIncomes
        let excluded: [UUID] = excludeExpenses
        let keys: [String] = notSameDismissKeys(ruleId: rule.id)
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
            for k in keys {
                life.dismissWealthCheck(k)
            }
        }
    }

    /// [v25.581] 按了〔不是，兩筆都要〕〔不是〕的那幾筆：要確認不再問的 key（帳本 dismissed；同一個 key 只留一次）
    private func notSameDismissKeys(ruleId: UUID) -> [String] {
        var out: [String] = []
        for m in notSameMatches {
            for k in WealthTransferFinds.notSameKeys(ruleId: ruleId, match: m, preset: preset) where !out.contains(k) {
                out.append(k)
            }
        }
        return out
    }

    // MARK: 存檔（〔改金額或帳戶〕）

    /// 表單現在的值；改的時候 change 只填改了的欄位、scheduleChanged 比打開時的值。從、到、金額沒填好＝nil
    /// [v25.583] 幣別跟打開時不一樣＝change.codes；換匯而且金額、幣別、對方收到多少有一個改了＝change.toAmount（現在填的）
    private func formValues(name: String?, memo: String?) -> WealthTransferUIFormValues? {
        guard accountsReady, let f = from, let t = toId, let v = amountValue else { return nil }
        let exchange = isExchange
        let ta: Double? = exchange ? toAmountValue : nil
        if exchange && ta == nil { return nil }
        let fc = WealthFacts.norm(fromCode)
        let tc = WealthFacts.norm(toCode)
        let dated = isDated
        var change = WealthTransferSegmentChange()
        var schedule = false
        if let o = original {
            if f != o.fromId { change.fromId = f }
            if t != o.toId { change.toId = t }
            if Swift.abs(v - o.amount) >= WealthTransferUIText.tolerance(fc) { change.amount = v }
            let codesMoved: Bool = fc != o.fromCode || tc != o.toCode
            if codesMoved { change.codes = WealthTransferCodes(from: fc, to: tc) }
            if exchange, let x = ta {
                let toMoved: Bool = o.toAmount.map { Swift.abs(x - $0) >= WealthTransferUIText.tolerance(tc) } ?? true
                if change.amount != nil || codesMoved || toMoved { change.toAmount = x }
            }
            schedule = scheduleChanged(o)
        }
        return WealthTransferUIFormValues(
            fromId: f, toId: t, amount: v, fromCode: fc, toCode: tc, toAmount: ta, cycle: cycle,
            day: dated ? storedDay : nil, short: dated ? storedShort : nil,
            month: cycle == .yearly ? yearMonth : nil, weekday: weekday, holiday: holidayValue,
            mode: manual ? "manual" : nil, name: name, memo: memo, end: endSpec, change: change,
            scheduleChanged: schedule)
    }

    /// 看改了什麼：週期或日子＝「從哪天起照新的日子？」（以前一期都沒有就不用問：同一條換日子）；
    /// 從、到、金額＝「從哪一期起改？」；都沒改（誰轉、設到哪天、名字、備註）＝直接存
    private func proceedEdit(_ values: WealthTransferUIFormValues) {
        guard let o = original, let base = lifeStore.wealthTransfers.rule(o.ruleId), base.deletedAt == nil else {
            isSaving = false
            editMissing = true
            return
        }
        pendingValues = values
        let ask: WealthTransferUIEditAsk
        if values.scheduleChanged {
            guard WealthTransferPlan.splitLastKey(base, from: tomorrow) != nil else {
                commitAllSchedule()
                return
            }
            ask = scheduleAsk(values)
        } else if !values.change.isEmpty {
            ask = segmentAsk(base)
        } else {
            commitPlain()
            return
        }
        // 等像帳號那個框收好再跳
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.editAsk = ask
        }
    }

    /// 「從哪天起照新的日子？」〔下一期 2027/1/8 起（以前的照舊）〕〔全部都改（以前的也照新的日子）〕〔取消〕
    private func scheduleAsk(_ values: WealthTransferUIFormValues) -> WealthTransferUIEditAsk {
        let start: Date? = WealthTransferPlan.splitStart(cycle: values.cycle, day: values.day ?? 1, short: values.short,
                                                         weekday: values.weekday, month: values.month ?? 1,
                                                         holiday: values.holiday, from: tomorrow)
        // [v25.583] 寫實際那天（新的那條的遇六日）
        let label: String? = start.map {
            "下一期 " + WealthTransferText.dayText(WealthTransferSchedule.shifted($0, holiday: values.holiday), today: today)
                + " 起（以前的照舊）"
        }
        return WealthTransferUIEditAsk(kind: .schedule, title: "從哪天起照新的日子？",
                                       message: "以前的照舊；銀行 App 那邊也要改。", nextLabel: label, nextKey: nil,
                                       allLabel: "全部都改（以前的也照新的日子）")
    }

    /// 「從哪一期起改？」〔下一期 2027/1/6 起（以前的照舊）〕〔全部都改〕〔選一期…〕〔取消〕
    private func segmentAsk(_ base: WealthTransferRule) -> WealthTransferUIEditAsk {
        let nk: String? = WealthTransferPlan.nextKey(base, today: today)
        // [v25.583] 寫實際那天（這條的遇六日）
        let nd: Date? = nk.flatMap { WealthTransferSchedule.date(fromKey: $0) }
            .map { WealthTransferSchedule.shifted($0, holiday: base.holidayKind) }
        let label: String? = nd.map { "下一期 " + WealthTransferText.dayText($0, today: today) + " 起（以前的照舊）" }
        let past = WealthTransferPlan.pastCount(base, today: today)
        let message: String? = past > 0
            ? "選〔全部都改〕的話以前的 \(past) 期也會變；對過存摺之前的不影響今天的數字。"
            : nil
        return WealthTransferUIEditAsk(kind: .segment, title: "從哪一期起改？", message: message, nextLabel: label,
                                       nextKey: nk, allLabel: "全部都改")
    }

    /// 問的那一題的一顆按鈕
    private func answerEdit(_ a: WealthTransferUIEditAsk, _ x: WealthTransferUIEditAnswer) {
        guard editAsk?.id == a.id else { return }
        editAsk = nil
        if x == .cancel {
            cancelEdit()
            return
        }
        switch a.kind {
        case .schedule:
            if x == .next {
                commitSplit()
            } else if x == .all {
                commitAllSchedule()
            } else {
                cancelEdit()
            }
        case .segment:
            if x == .next {
                commitSegment(a.nextKey ?? "")
            } else if x == .all {
                commitSegment("")
            } else {
                openPick()
            }
        }
    }

    /// 框被關掉（沒按任何一顆）＝取消，回表單
    private func closeEditAsk() {
        guard let a = editAsk else { return }
        DispatchQueue.main.async {
            if self.editAsk?.id == a.id {
                self.editAsk = nil
                self.cancelEdit()
            }
        }
    }

    private func cancelEdit() {
        pendingValues = nil
        isSaving = false
    }

    /// 〔選一期…〕：以前最近 24 期＋以後 12 期（等確認框收好再開）
    private func openPick() {
        guard let o = original, let base = lifeStore.wealthTransfers.rule(o.ruleId) else {
            cancelEdit()
            return
        }
        let list = WealthTransferUIPickList.make(WealthTransferPlan.pickDates(base, today: today), today: today,
                                                 holiday: base.holidayKind)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.pickList = list
        }
    }

    /// 〔選一期…〕關掉：點了一期＝從那一期起改；沒點＝取消
    private func pickClosed() {
        guard let k = pickedKey else {
            if pendingValues != nil { cancelEdit() }
            return
        }
        pickedKey = nil
        commitSegment(k)
    }

    /// 從、到、金額從 key 那一期（含）起改（""＝全部都改）＋誰轉、設到哪天、名字、備註
    private func commitSegment(_ key: String) {
        guard let values = pendingValues, let o = original else {
            cancelEdit()
            return
        }
        pendingValues = nil
        let life = lifeStore
        let id = o.ruleId
        dismiss()
        DispatchQueue.main.async {
            life.updateTransferRule(id) { r in
                r = values.segmentEdited(r, from: key)
            }
        }
    }

    /// 改週期或日子〔全部都改〕：同一條換日子（舊的註記留著，對不上新的日子就沒作用）
    private func commitAllSchedule() {
        guard let values = pendingValues, let o = original else {
            cancelEdit()
            return
        }
        pendingValues = nil
        let life = lifeStore
        let id = o.ruleId
        dismiss()
        DispatchQueue.main.async {
            life.updateTransferRule(id) { r in
                r = values.scheduleEditedAll(r)
            }
        }
    }

    /// 改週期或日子〔下一期起〕：舊的停在明天以前最後一期、新的一條從新的日子明天（含）以後第一期起（previousId 接上）
    private func commitSplit() {
        guard let values = pendingValues, let o = original,
              let base = lifeStore.wealthTransfers.rule(o.ruleId),
              let next = values.splitNext(id: UUID(), effective: tomorrow) else {
            cancelEdit()
            return
        }
        pendingValues = nil
        let lastKey: String? = WealthTransferPlan.splitLastKey(base, from: tomorrow)
        let life = lifeStore
        let oldId = base.id
        dismiss()
        DispatchQueue.main.async {
            life.splitTransferRule(oldId, lastKey: lastKey, next: next)
        }
    }

    /// 只改了誰轉、銀行設到哪天、名字、備註：直接存（沒改＝LifeStore 不寫）
    private func commitPlain() {
        guard let values = pendingValues, let o = original else {
            cancelEdit()
            return
        }
        pendingValues = nil
        let life = lifeStore
        let id = o.ruleId
        dismiss()
        DispatchQueue.main.async {
            life.updateTransferRule(id) { r in
                r = values.plainEdited(r)
            }
        }
    }
}

// MARK: - B. 規則頁

/// 規則頁點一期（巢狀 sheet 的 item）。[v25.583] ruleId：「以前的」也列改週期以前那條的期（開那一條的那一期）
private struct WealthTransferUIPeriodPick: Identifiable {
    let ruleId: UUID
    let key: String
    var id: String { ruleId.uuidString + "-" + key }
}

/// 規則頁疊的表單（巢狀 sheet 的 item；一個 sheet(item:) 開好幾種）：
/// [v25.577]〔改金額或帳戶〕（新增表單的編輯模式）；[v25.579]〔暫停〕（暫停小表單）；[v25.583]〔看新的那條〕（接下去那條的規則頁）
private enum WealthTransferUIRuleSheet: Identifiable {
    case edit(UUID)
    case pause(UUID)
    case successor(UUID)

    var id: String {
        switch self {
        case .edit(let r): return "edit-" + r.uuidString
        case .pause(let r): return "pause-" + r.uuidString
        case .successor(let r): return "successor-" + r.uuidString
        }
    }
}

/// 規則頁的確認框：〔結束〕〔刪除〕、[v25.579]〔恢復…〕（一個畫面一個 confirmationDialog）
private enum WealthTransferUIRuleAsk: Identifiable {
    case end, delete, resume
    var id: Int {
        switch self {
        case .end: return 0
        case .delete: return 1
        case .resume: return 2
        }
    }
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
    /// [v25.577] 改過的那一行灰字：「2027/1/8 起改成每月 8 日（以前每月 6 日）」「2027/1/6 起 25,000（以前 20,000）」
    let changeLines: [String]
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
    // [v25.579] v2
    /// 我自己轉（「還沒定下來的」footer、「提醒我」第二行）
    let isManual: Bool
    /// 「暫停到 12/24」「12/4 起暫停到 12/24」「暫停中」（rule.pauseInfo）；nil＝沒有暫停
    let pauseText: String?
    /// 〔暫停〕：今天以後還有期可以選
    let canPause: Bool
    /// 〔恢復…〕：下一期（WealthTransferPlan.nextKey）與按鈕字「下一期 12/11（五）起照轉」
    let resumeKey: String?
    let resumeLabel: String
    /// 「提醒我」（rule.remind != false）
    let remindOn: Bool
    // [v25.583] v4
    /// 這條是被接的舊那條：接下去那一條（〔看新的那條〕；facts.transferHistory(id).successor）
    let successorId: UUID?

    /// 「還沒定下來的」footer（自己轉的多一句）
    var pendingFooter: String {
        isManual
            ? "沒轉成的：點進去〔今天補轉〕或〔復原〕；自己轉的：點進去〔轉好了〕〔轉了〕〔還沒〕"
            : "銀行沒轉成的期：點進去〔今天補轉〕或〔復原〕"
    }

    /// 「提醒我」第二行
    var remindDetail: String {
        isManual
            ? "那天早上 9 點提醒你轉"
            : "可能轉不過去時前一晚 8 點、銀行設的最後一次前 14 天提醒你"
    }

    /// 〔恢復…〕的說明：「暫停到 12/24；以前暫停的期照舊不算」
    var resumeMessage: String {
        (pauseText ?? "暫停中") + "；以前暫停的期照舊不算"
    }

    static func make(facts: WealthFacts, ruleId: UUID, masked: Bool, showMore: Bool) -> WealthTransferUIRuleModel? {
        guard let t = facts.transferRule(ruleId) else { return nil }
        let today = facts.today
        // [v25.583] 每年的往後看 3 年多（不然「接下來」只有一期）
        let ahead: Int = WealthTransferSchedule.lookAheadDays(t.rule.cycleKind)
        let periods = facts.transferPeriods(ruleId, through: WealthCal.addDays(ahead, to: today))
        let manual = t.isManual
        let history: WealthTransferHistory = facts.transferHistory(ruleId)
        // 還沒定下來的：過了日子、沒轉成＋[v25.579] 自己轉的今天要轉、等你回答、還沒轉（最近 6 期，新到舊）
        let pendingAll: [WealthTransferPeriod] = periods.filter { isPending($0, manual: manual, today: today) }
        let pendingList: [WealthTransferPeriod] = Array(pendingAll.reversed().prefix(6))
        let pendingKeys = Set(pendingList.map { $0.key })
        // 接下來：實際那天在今天以後（含這期不轉的）
        let futureAll: [WealthTransferPeriod] = periods
            .filter { $0.day > today && !pendingKeys.contains($0.key) }
            .sorted { $0.day < $1.day }
        let futureKeys = Set(futureAll.map { $0.key })
        // 以前的：其他今天（含）以前的，新到舊。[v25.583] 改週期以前那幾條今天（含）以前的期照樣列（transferPredecessorPeriods；照 day 排在一起）
        let ownPast: [WealthTransferPeriod] = periods
            .filter { !pendingKeys.contains($0.key) && !futureKeys.contains($0.key) && ($0.original <= today || $0.day <= today) }
        let pastAll: [WealthTransferPeriod] = (ownPast + facts.transferPredecessorPeriods(ruleId))
            .sorted { $0.day > $1.day }
        let upLimit = showMore ? 15 : 3
        let pastLimit = showMore ? 18 : 6
        let hasMore = !showMore && (futureAll.count > upLimit || pastAll.count > pastLimit)
        let pending = pendingList.map { WealthTransferUIRow.make($0, facts: facts, manual: manual, masked: masked) }
        let upcoming = futureAll.prefix(upLimit).map { WealthTransferUIRow.make($0, facts: facts, manual: manual, masked: masked) }
        let past: [WealthTransferUIRow] = pastAll.prefix(pastLimit).map { p in
            // 以前那條的期：「自己轉」照那一條
            let m: Bool = p.ruleId == ruleId ? manual : (facts.transferRule(p.ruleId)?.isManual ?? manual)
            return WealthTransferUIRow.make(p, facts: facts, manual: m, masked: masked)
        }

        // [v25.583] 頭的金額兩邊「NT$9,600 → US$300.00」；週期後面接「・遇六日順延」
        let amountText: String = masked
            ? WealthFormat.masked
            : WealthTransferText.pair(t.amount, code: t.code, to: t.toAmount, toCode: t.toCode, money: true)
        let cycleText: String = t.cycleText + (t.holidayText.map { "・" + $0 } ?? "")
        let accountsLine = makeAccountsLine(t, facts: facts)
        let memoTrimmed = (t.rule.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // [v25.583] 〔結束〕〔恢復…〕的字寫實際那天（遇六日挪過的）；key 照舊原本的日子
        let holiday: WealthTransferHoliday = t.rule.holidayKind
        let lastPastKey: String? = t.isEnded ? nil : t.lastPast.map { WealthTransferSchedule.key(of: $0) }
        var lastPastLabel = ""
        if let d = t.lastPast {
            let actual = WealthTransferSchedule.shifted(d, holiday: holiday)
            lastPastLabel = "最後一次是 " + WealthTransferUIText.shortDay(actual, today: today) + "（最近轉的那一期）"
        }
        let nextKey: String? = t.next?.key
        var nextLabel = ""
        if let n = t.next {
            nextLabel = "下一期 " + WealthTransferUIText.shortDay(n.day, today: today) + " 轉完再停"
        }
        let counted: [WealthTransferPeriod] = periods.filter { $0.counts && $0.day <= today }
        let spokenAmount: String = (t.isExchange && !masked)
            ? WealthTransferText.pair(t.amount, code: t.code, to: t.toAmount, toCode: t.toCode, money: true)
            : WealthTransferUIText.spokenAmount(t.amount, code: t.code, masked: masked)
        let spoken = t.title + "，" + cycleText + "，" + spokenAmount + "，" + accountsLine

        // [v25.579]〔暫停〕〔恢復…〕：暫停中或排好了暫停＝〔恢復…〕（下一期起照轉）；沒有＝〔暫停〕（今天以後還有期才給）
        let pause: WealthTransferPauseInfo? = t.isEnded ? nil : t.rule.pauseInfo(today: today)
        let canPause: Bool = !t.isEnded && !WealthTransferPlan.pauseStarts(t.rule, today: today).isEmpty
        let resumeKey: String? = pause == nil ? nil : WealthTransferPlan.nextKey(t.rule, today: today)
        var resumeLabel = ""
        if let k = resumeKey, let d = WealthTransferSchedule.date(fromKey: k) {
            let actual = WealthTransferSchedule.shifted(d, holiday: holiday)
            resumeLabel = "下一期 " + WealthTransferUIText.day(actual, today: today) + " 起照轉"
        }

        return WealthTransferUIRuleModel(
            title: t.title, cycleText: cycleText, amountText: amountText, accountsLine: accountsLine,
            rangeLine: makeRangeLine(t), changeLines: makeChangeLines(t, history: history, facts: facts, masked: masked),
            memo: memoTrimmed.isEmpty ? nil : memoTrimmed, isRunning: !t.isEnded,
            pending: pending, upcoming: Array(upcoming), past: past, hasMore: hasMore,
            lastPastKey: lastPastKey, lastPastLabel: lastPastLabel, nextKey: t.isEnded ? nil : nextKey,
            nextLabel: nextLabel, pastCount: counted.count,
            deleteMessage: makeDeleteMessage(counted, facts: facts, masked: masked), spoken: spoken,
            isManual: manual, pauseText: pause?.text, canPause: canPause, resumeKey: resumeKey,
            resumeLabel: resumeLabel, remindOn: t.rule.remind != false, successorId: history.successor?.id)
    }

    /// [v25.583] 「薪轉（台新銀行）→ 存錢（玉山銀行）・銀行會自動轉」；同一個帳戶「存錢（玉山銀行）台幣 → USD・…」；
    /// 兩個帳戶換匯，外幣那一邊後面寫幣別「薪轉（台新銀行）→ 存錢（玉山銀行）USD・…」
    static func makeAccountsLine(_ t: WealthFacts.TransferRule, facts: WealthFacts) -> String {
        let mode: String = t.isManual ? "我自己轉" : "銀行會自動轉"
        let fromLabel = WealthTransferUIText.accountLabel(t.fromId, fallback: t.fromName, facts: facts)
        if t.isSameAccount {
            let gap: String = fromLabel.hasSuffix("）") ? "" : " "
            return fromLabel + gap + WealthTransferText.codeName(t.code) + " → " + WealthTransferText.codeName(t.toCode)
                + "・" + mode
        }
        let toLabel = WealthTransferUIText.accountLabel(t.toId, fallback: t.toName, facts: facts)
        guard t.isExchange else { return fromLabel + " → " + toLabel + "・" + mode }
        return codeSide(fromLabel, code: t.code) + " → " + codeSide(toLabel, code: t.toCode) + "・" + mode
    }

    /// 換匯那一邊是外幣：帳戶後面接幣別（「存錢（玉山銀行）USD」「存錢 USD」）；台幣不寫
    private static func codeSide(_ label: String, code: String) -> String {
        guard !FinanceRates.isNTD(code) else { return label }
        return label + (label.hasSuffix("）") ? "" : " ") + code
    }

    /// [v25.579] 還沒定下來的一期：過了日子、沒轉成；自己轉的今天要轉、過了日子等你回答、你說還沒轉（judge §4.4）
    static func isPending(_ p: WealthTransferPeriod, manual: Bool, today: Date) -> Bool {
        if p.state == .failed && p.original <= today { return true }
        guard manual, let ph = p.manualPhase(today: today) else { return false }
        return ph == .today || ph == .waiting || ph == .notYet
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

    /// [v25.577] 頭下面的灰字：改週期或日子接上來的（previousId）「2027/1/8 起改成每月 8 日（以前每月 6 日）」；
    /// 下一期那一段是後來改的「2027/1/6 起 25,000（以前 20,000）」（只寫最近那一次）。
    /// [v25.583] 改週期的每一次都一行（facts.transferHistory：新到舊、日子照年份）；被接的舊那條多「2027/1/8 起改成每月 8 日（新的那條）」
    static func makeChangeLines(_ t: WealthFacts.TransferRule, history: WealthTransferHistory, facts: WealthFacts,
                                masked: Bool) -> [String] {
        var out: [String] = []
        // [v25.579] 最前面：「暫停到 12/24」「12/4 起暫停到 12/24」（還在跑的才有）
        if let p = t.rule.pauseInfo(today: facts.today) {
            out.append(p.text)
        }
        if let line = history.successorLine {
            out.append(line)
        }
        out.append(contentsOf: history.lines)
        if let line = segmentChangeLine(t, facts: facts, masked: masked) {
            out.append(line)
        }
        return out
    }

    /// 下一期（沒有＝今天以後第一期原本的日子）那一段的 fromKey 不是 ""、跟前一段金額不一樣（暫停的段不算）：
    /// 「2027/1/6 起 25,000（以前 20,000）」（遮住「2027/1/6 起改過每期金額」）；金額一樣、帳戶不一樣：「…起改從 國泰世華 轉出」「…起改轉到 存錢」。
    /// [v25.583] 幣別不一樣「2027/1/1 起改轉成 USD」；換匯的段金額一樣、對方收到多少不一樣「2027/1/1 起 US$310.00（以前 US$300.00）」；
    /// 換匯的段金額不一樣寫兩邊「2027/1/1 起 9,800 → US$310.00（以前 9,600 → US$300.00）」
    static func segmentChangeLine(_ t: WealthFacts.TransferRule, facts: WealthFacts, masked: Bool) -> String? {
        let r = t.rule
        guard let nk = t.next?.key ?? WealthTransferPlan.nextKey(r, today: facts.today) else { return nil }
        let segs = r.sortedSegments
        guard let i = segs.lastIndex(where: { ($0.fromKey ?? "") <= nk }), i > 0 else { return nil }
        let cur = segs[i]
        let prev = segs[i - 1]
        guard let fk = cur.fromKey, !fk.isEmpty, let d = WealthTransferSchedule.date(fromKey: fk) else { return nil }
        let a: Double = cur.amount ?? 0
        let b: Double = prev.amount ?? 0
        guard a > 0.004 && b > 0.004 else { return nil }
        let head: String = WealthFormat.ymd(d) + " 起"
        let curFrom: String = WealthFacts.norm(cur.fromCode ?? "NT$")
        let curTo: String = WealthFacts.norm(cur.toCode ?? "NT$")
        let prevFrom: String = WealthFacts.norm(prev.fromCode ?? "NT$")
        let prevTo: String = WealthFacts.norm(prev.toCode ?? "NT$")
        if curTo != prevTo {
            return head + "改轉成 " + WealthTransferText.codeName(curTo)
        }
        if curFrom != prevFrom {
            return head + "改從 " + WealthTransferText.codeName(curFrom) + " 轉出"
        }
        let exchange: Bool = curFrom != curTo
        if Swift.abs(a - b) >= WealthTransferUIText.tolerance(curFrom) {
            if masked { return head + "改過每期金額" }
            let now: String = WealthTransferText.pair(a, code: curFrom, to: cur.toAmount ?? a, toCode: curTo)
            let was: String = WealthTransferText.pair(b, code: prevFrom, to: prev.toAmount ?? b, toCode: prevTo)
            return head + " " + now + "（以前 " + was + "）"
        }
        if exchange, let ta = cur.toAmount, let tb = prev.toAmount,
           Swift.abs(ta - tb) >= WealthTransferUIText.tolerance(curTo) {
            if masked { return head + "改過每期金額" }
            return head + " " + WealthFormat.plain(ta, code: curTo) + "（以前 " + WealthFormat.plain(tb, code: prevTo) + "）"
        }
        if let f = cur.fromId, f != prev.fromId {
            return head + "改從 " + (facts.account(f)?.name ?? "別的帳戶") + " 轉出"
        }
        if let to = cur.toId, to != prev.toId {
            return head + "改轉到 " + (facts.account(to)?.name ?? "別的帳戶")
        }
        return nil
    }

    /// 〔全部刪掉〕的影響：照每個帳戶最近一次對存摺算（對存摺以前的期不影響今天的數字）。
    /// 轉出那邊拿掉＝今天多、轉入那邊拿掉＝今天少（「薪轉今天多 50,000、存錢少 50,000」）。
    /// [v25.583] 照**帳戶＋幣別**分開加（同一個帳戶換匯的兩格不能加在一起）、字照那個幣別；同一個帳戶出現兩個幣別才在名字後面寫幣別
    ///（「存錢台幣今天多 19,200、存錢 USD 少 US$600.00」）
    static func makeDeleteMessage(_ counted: [WealthTransferPeriod], facts: WealthFacts, masked: Bool) -> String {
        guard !counted.isEmpty else { return "這條還沒有轉過的期，刪掉不影響今天的數字。" }
        var delta: [String: Double] = [:]
        var order: [(id: UUID, code: String)] = []
        for p in counted {
            if let f = p.fromId, afterAnchor(p.day, late: p.lateOut, code: p.fromCode, account: facts.account(f)) {
                let k = f.uuidString + "|" + p.fromCode
                if delta[k] == nil { order.append((id: f, code: p.fromCode)) }
                delta[k, default: 0] += p.amount
            }
            if let t = p.toId, afterAnchor(p.day, late: p.lateIn, code: p.toCode, account: facts.account(t)) {
                let k = t.uuidString + "|" + p.toCode
                if delta[k] == nil { order.append((id: t, code: p.toCode)) }
                delta[k, default: 0] -= p.toAmount
            }
        }
        var parts: [String] = []
        for side in order {
            let k = side.id.uuidString + "|" + side.code
            guard let v = delta[k], Swift.abs(v) > WealthTransferUIText.tolerance(side.code),
                  let a = facts.account(side.id) else { continue }
            let twoCodes: Bool = order.filter { $0.id == side.id }.count >= 2
            let named: String = twoCodes ? deleteSideName(a.name, code: side.code) : a.name
            // 結尾是英文代碼（「存錢 USD」）後面空一格再接中文
            let latinEnd: Bool = named.last.map { $0.isASCII && $0.isLetter } ?? false
            let name: String = latinEnd ? named + " " : named
            let lead: String = parts.isEmpty ? name + "今天" : name
            let word: String = v > 0 ? "多" : "少"
            let num: String = masked ? "" : " " + WealthFormat.plain(Swift.abs(v), code: side.code)
            parts.append(lead + word + num)
        }
        let head = "全部刪掉的話，以前 \(counted.count) 期也拿掉"
        if parts.isEmpty { return head + "（都在對存摺以前，今天的數字不變）。" }
        return head + "：" + parts.joined(separator: "、") + "。"
    }

    /// [v25.583] 刪除影響那一句的帳戶名＋幣別：台幣「存錢台幣」、外幣「存錢 USD」
    static func deleteSideName(_ name: String, code: String) -> String {
        FinanceRates.isNTD(code) ? name + "台幣" : name + " " + code
    }

    /// 這一期這一邊在那個帳戶最近一次對存摺之後（從沒對過＝都算；同一天記了 late＝在對存摺之後）。帳戶找不到＝不算。
    /// [驗證修] 看這一邊那個幣別（code）最近一次對存摺：lastAnchorDate 是任何幣別的（外幣帳戶只對了美金那格就會算錯台幣那邊）
    static func afterAnchor(_ day: Date, late: Bool, code: String, account: WealthFacts.Account?) -> Bool {
        guard let a = account else { return false }
        guard let anchor = a.ledger.first(where: { $0.kind == .anchor && WealthFacts.norm($0.code) == code })?.date else {
            return true
        }
        let d = WealthCal.day(day)
        let x = WealthCal.day(anchor)
        return d > x || (d == x && late)
    }
}

/// 規則頁的頭
private struct WealthTransferUIRuleHeader: View {
    let model: WealthTransferUIRuleModel

    private var spokenAll: String {
        ([model.spoken, model.rangeLine] + model.changeLines).joined(separator: "，")
    }

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
                // [審查修] 改週期的歷史可能好幾行：用第幾行當 id（字一樣的兩行不會撞）
                ForEach(Array(model.changeLines.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let memo = model.memo {
                    Text(memo)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenAll)
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
    /// [v25.579]〔恢復…〕：從這一期（含）起照轉
    let onResume: (String) -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { self.ask != nil }, set: { if !$0 { self.ask = nil } })
    }

    private var title: String {
        switch ask {
        case .end?: return "最後一次是哪一期？"
        case .delete?: return "刪除「" + model.title + "」？"
        case .resume?: return "從哪一期起照轉？"
        case nil: return ""
        }
    }

    private func message(_ a: WealthTransferUIRuleAsk) -> String {
        switch a {
        case .end: return "以前的期照算；銀行那邊請到銀行 App 取消預約轉帳。"
        case .delete: return model.deleteMessage
        case .resume: return model.resumeMessage
        }
    }

    /// 〔下一期 12/11（五）起照轉〕（沒有下一期就不給這顆，只剩〔取消〕）
    @ViewBuilder
    private var resumeButtons: some View {
        if let k = model.resumeKey {
            Button(model.resumeLabel) { onResume(k) }
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
            case .resume:
                resumeButtons
            }
            Button("取消", role: .cancel) {}
        } message: { a in
            Text(message(a))
        }
    }
}

/// [v25.579] 規則頁「提醒我」開關的字（兩行：第二行灰字講什麼時候提醒）
private struct WealthTransferUIRemindLabel: View {
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("提醒我")
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// [v25.579]〔暫停〕小表單（judge §4.6；brief §6 G1 C-3）：從哪一期起暫停（今天以後 12 期，第一個＝下一期）、
/// 到哪一期恢復（那期以後 26 期；〔先不設〕＝到你按〔恢復〕）。Picker 用 Int index 當 tag。
/// 存＝dismiss、下一個 runloop LifeStore.pauseTransferRule（金額 0 的一段＋恢復那段，WealthTransferRule.paused）。不擋訂閱
private struct WealthTransferUIPauseSheet: View {
    let ruleId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var loaded = false
    /// 今天 00:00（打開時從 facts 抓一次）
    @State private var today: Date = WealthCal.day(Date())
    /// 打開時那一條（找不到＝刪了）
    @State private var rule: WealthTransferRule? = nil
    /// 「從哪一期起暫停」可以選的（原本的日子）、選的那一個
    @State private var starts: [Date] = []
    @State private var startIndex: Int = 0
    /// 「到哪一期恢復」可以選的（原本的日子）、選的那一個（−1＝先不設）
    @State private var resumes: [Date] = []
    @State private var resumeIndex: Int = -1

    /// 〔先不設（到我按〔恢復〕）〕的 tag
    private static let noResume = -1
    private static let bankNote = "銀行那邊也要暫停：到銀行 App 取消那幾筆預約轉帳。App 不會幫你改銀行。"

    private var selectedStart: Date? {
        starts.indices.contains(startIndex) ? starts[startIndex] : nil
    }

    private var selectedResume: Date? {
        resumes.indices.contains(resumeIndex) ? resumes[resumeIndex] : nil
    }

    private var saveDisabled: Bool { rule == nil || selectedStart == nil }

    /// 「12/4、12/11、12/18 這 3 期不算，12/25 起照轉」＋換行＋銀行那邊也要暫停
    private var footerText: String {
        guard let r = rule, let start = selectedStart else { return Self.bankNote }
        let summary = WealthTransferPlan.pauseSummary(r, from: start, until: selectedResume, today: today)
        return summary + "\n" + Self.bankNote
    }

    /// [v25.583] 字寫實際那天（遇六日挪過的；選的值照舊是原本的日子）
    private func actualDay(_ d: Date) -> String {
        let h: WealthTransferHoliday = rule?.holidayKind ?? .onDay
        return WealthTransferUIText.day(WealthTransferSchedule.shifted(d, holiday: h), today: today)
    }

    /// 「下一期 11/27（五）」「12/4（五）」
    private func startLabel(_ i: Int) -> String {
        guard starts.indices.contains(i) else { return "" }
        let d = actualDay(starts[i])
        return i == 0 ? "下一期 " + d : d
    }

    private func resumeLabel(_ i: Int) -> String {
        guard resumes.indices.contains(i) else { return "" }
        return actualDay(resumes[i])
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("暫停")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("暫停") { save() }
                            .disabled(saveDisabled)
                    }
                }
                .onAppear { load() }
                .onChange(of: startIndex) { _, _ in startChanged() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    @ViewBuilder
    private var content: some View {
        if !loaded {
            Form {}
        } else if rule == nil {
            Form {
                Text("這條定期轉帳已經刪了")
                    .foregroundStyle(Color.secondary)
            }
        } else if starts.isEmpty {
            Form {
                Text("今天以後沒有要轉的期，不用暫停")
                    .foregroundStyle(Color.secondary)
            }
        } else {
            Form {
                startSection
                resumeSection
            }
        }
    }

    private var startSection: some View {
        Section {
            Picker("從哪一期起", selection: $startIndex) {
                ForEach(starts.indices, id: \.self) { i in
                    Text(startLabel(i)).tag(i)
                }
            }
        } header: {
            Text("從哪一期起暫停")
        }
    }

    private var resumeSection: some View {
        Section {
            Picker("到哪一期恢復", selection: $resumeIndex) {
                Text("先不設（到我按〔恢復〕）").tag(Self.noResume)
                ForEach(resumes.indices, id: \.self) { i in
                    Text(resumeLabel(i)).tag(i)
                }
            }
        } header: {
            Text("到哪一期恢復")
        } footer: {
            Text(footerText)
        }
    }

    private func load() {
        guard !loaded else { return }
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let t = facts.today
        today = t
        if let tr = facts.transferRule(ruleId), !tr.isEnded {
            let list = WealthTransferPlan.pauseStarts(tr.rule, today: t)
            rule = tr.rule
            starts = list
            resumes = list.first.map { WealthTransferPlan.pauseResumes(tr.rule, after: $0) } ?? []
            resumeIndex = Self.noResume
        }
        loaded = true
    }

    /// 換了「從哪一期起」：恢復的清單跟著換；原本選的那天不在新的清單裡＝回到〔先不設〕
    private func startChanged() {
        guard let r = rule, let start = selectedStart else { return }
        let old: Date? = selectedResume
        let list = WealthTransferPlan.pauseResumes(r, after: start)
        resumes = list
        if let o = old, let i = list.firstIndex(of: o) {
            resumeIndex = i
        } else {
            resumeIndex = Self.noResume
        }
    }

    /// 〔暫停〕：先關，下一個 runloop 才寫
    private func save() {
        guard rule != nil, let start = selectedStart else { return }
        let fromKey = WealthTransferSchedule.key(of: start)
        let untilKey: String? = selectedResume.map { WealthTransferSchedule.key(of: $0) }
        let life = lifeStore
        let id = ruleId
        dismiss()
        DispatchQueue.main.async {
            life.pauseTransferRule(id, from: fromKey, until: untilKey)
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
    /// [v25.577]〔改金額或帳戶〕、[v25.579]〔暫停〕
    @State private var ruleSheet: WealthTransferUIRuleSheet?

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
        .sheet(item: $ruleSheet) { s in
            ruleSheetView(s)
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
                if m.isRunning {
                    remindSection(m)
                }
                actionSection(m)
            }
            .modifier(WealthTransferUIRuleDialog(ask: $ask, model: m,
                                                 onEnd: { k in end(k) },
                                                 onDelete: { delete() },
                                                 onResume: { k in resume(k) }))
            .sheet(item: $openPeriod) { p in
                // [v25.583] 以前那條的期：開那一條的那一期（〔看整條〕疊那一條的規則頁）
                WealthTransferPeriodSheet(ruleId: p.ruleId, periodKey: p.key, fromRulePage: p.ruleId == ruleId)
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
                Text(m.pendingFooter)
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
                openPeriod = WealthTransferUIPeriodPick(ruleId: r.ruleId, key: r.key)
            } label: {
                WealthTransferUIRowView(row: r)
            }
        }
    }

    /// [v25.579]〔改金額或帳戶〕→〔暫停〕或〔恢復…〕→〔結束〕；刪除（List 的列，不受要確認 2 顆的限制）。
    /// [v25.583] 被接的舊那條最前面〔看新的那條〕（看，不擋訂閱）
    private func actionSection(_ m: WealthTransferUIRuleModel) -> some View {
        Section {
            if let sid = m.successorId {
                WealthTransferUIActionRow(title: "看新的那條", chevron: true) { ruleSheet = .successor(sid) }
            }
            if m.isRunning {
                Button("改金額或帳戶") { tapEdit() }
                if m.pauseText != nil {
                    Button("恢復…") { ask = .resume }
                } else if m.canPause {
                    Button("暫停") { tapPause() }
                }
                Button("結束") { ask = .end }
            }
            Button("刪除這條定期轉帳", role: .destructive) { tapDelete() }
        } footer: {
            Text("App 不會幫你轉錢；在這裡改，銀行 App 那邊也要改。")
        }
    }

    /// [v25.579]「這條要提醒我」（還在跑的才有；judge §4.10）
    private func remindSection(_ m: WealthTransferUIRuleModel) -> some View {
        Section {
            Toggle(isOn: remindBinding(m)) {
                WealthTransferUIRemindLabel(detail: m.remindDetail)
            }
        } header: {
            Text("提醒")
        } footer: {
            Text(remindFooter)
        }
    }

    /// 值讀 model（rule.remind != false）；撥了下一個 runloop 才寫
    private func remindBinding(_ m: WealthTransferUIRuleModel) -> Binding<Bool> {
        let on: Bool = m.remindOn
        return Binding(get: { on }, set: { v in setRemind(v) })
    }

    /// 這支手機的開關關著就講去哪裡開（財富提醒全關／只有定期轉帳關）
    private var remindFooter: String {
        if !WealthReminders.isEnabled {
            return "這支手機的財富提醒關著：設定 › 會議提醒 ›「財富提醒」"
        }
        if !WealthReminders.transfersEnabled {
            return "這支手機的提醒關著：設定 › 會議提醒 ›「定期轉帳提醒（只這台）」"
        }
        return "通知不寫帳戶、銀行和金額。"
    }

    /// 〔改金額或帳戶〕〔暫停〕（每個 case 自己 .appStores()）
    @ViewBuilder
    private func ruleSheetView(_ s: WealthTransferUIRuleSheet) -> some View {
        switch s {
        case .edit(let rid):
            WealthTransferRuleForm(editRuleId: rid)
                .appStores()
        case .pause(let rid):
            WealthTransferUIPauseSheet(ruleId: rid)
                .appStores()
        case .successor(let rid):
            WealthTransferRulePage(ruleId: rid)
                .appStores()
        }
    }

    // MARK: 寫（先關這一頁，下一個 runloop 才寫）

    /// [v25.577]〔改金額或帳戶〕要訂閱：同一張新增表單（存檔時問從哪一期起改；表單自己存、這一頁留著）
    private func tapEdit() {
        guard subscription.isPremium else {
            showPremium = true
            return
        }
        ruleSheet = .edit(ruleId)
    }

    /// [v25.579]〔暫停〕：開暫停小表單（不擋訂閱：同〔結束〕；表單自己存、這一頁留著）
    private func tapPause() {
        ruleSheet = .pause(ruleId)
    }

    /// 〔刪除〕要訂閱（看、〔結束〕不用）
    private func tapDelete() {
        guard subscription.isPremium else {
            showPremium = true
            return
        }
        ask = .delete
    }

    /// 〔結束〕：最後一期＝key（nil＝一期都不算）；不擋訂閱。
    /// [v25.579] 記 endedBy "user"：你按的結束不會被當成「銀行設的最後一次」（要確認、到期通知都不講）
    private func end(_ key: String?) {
        let life = lifeStore
        let id = ruleId
        dismiss()
        DispatchQueue.main.async {
            life.endTransferRule(id, lastKey: key, endedBy: WealthTransferNotices.endedByUser)
        }
    }

    /// [v25.579]〔恢復…〕〔下一期 12/11（五）起照轉〕：key 那一期（含）起照轉；以前暫停的期照舊不算。不擋訂閱
    private func resume(_ key: String) {
        let life = lifeStore
        let id = ruleId
        dismiss()
        DispatchQueue.main.async {
            life.unpauseTransferRule(id, from: key)
        }
    }

    /// [v25.579]「提醒我」：不關頁，下一個 runloop 才寫（rule.remind nil／false）。不擋訂閱
    private func setRemind(_ on: Bool) {
        let life = lifeStore
        let id = ruleId
        DispatchQueue.main.async {
            life.setTransferRemind(id, on: on)
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

/// 〔改這一期〕〔今天補轉〕〔轉好了〕展開的三欄
private enum WealthTransferUIPeriodEdit: Hashable {
    /// 改這一期（日子不能跨過前後一期）
    case change
    /// 今天補轉（不早於原本那天；狀態存 redo）
    case redo
    /// [v25.579] 自己轉〔轉好了〕：只有「實際轉了 NT$…」（日子一律今天；LifeStore.markTransferDone）
    case done
}

/// [v25.579]〔轉好了〕存檔時兩邊帳戶今天對過存摺：先問「今天對存摺的時候，這筆轉了嗎？」（確認框的 item）
private struct WealthTransferUIDoneAsk: Identifiable {
    let id = UUID()
    /// 實際轉了多少（表單打的）
    let amount: Double
    /// 轉出、轉進帳戶今天對過存摺（facts.transferReconciledToday）
    let from: Bool
    let to: Bool
    /// [v25.583] 換匯：對方實際收到多少（表單打的；不是換匯＝nil 照留）
    let toAmount: Double?
}

/// [v25.579]「今天對存摺的時候，這筆轉了嗎？」〔還沒，對完才轉的〕（對過的那一邊記 late）〔轉了，存摺上已經有了〕（那一邊 late 拿掉）〔取消〕
private struct WealthTransferUIDoneDialog: ViewModifier {
    @Binding var ask: WealthTransferUIDoneAsk?
    /// late：true＝〔還沒，對完才轉的〕、false＝〔轉了，存摺上已經有了〕
    let onAnswer: (WealthTransferUIDoneAsk, Bool) -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { self.ask != nil }, set: { if !$0 { self.ask = nil } })
    }

    func body(content: Content) -> some View {
        content.confirmationDialog("今天對存摺的時候，這筆轉了嗎？", isPresented: isPresented,
                                   titleVisibility: .visible, presenting: ask) { a in
            Button("還沒，對完才轉的") { onAnswer(a, true) }
            Button("轉了，存摺上已經有了") { onAnswer(a, false) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("對存摺之後才轉的，App 會把這筆排在對存摺後面，存摺上的數字才對。")
        }
    }
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
    // [v25.579] 自己轉（judge §4.5 v2 那幾列；brief §6 G1 B）
    /// 今天要轉：〔轉好了〕〔改到明天〕〔這期不轉〕〔看整條〕
    case manualToday
    /// 當作轉了・等你回答／當作轉了：〔轉了〕〔還沒，算在明天〕〔這期不轉〕〔改這一期〕〔看整條〕
    case manualWaiting
    /// 還沒轉・算在明天：〔轉好了〕〔這期不轉〕〔看整條〕
    case manualNotYet
    /// 轉好了：〔改這一期〕〔復原〕〔看整條〕
    case manualDone
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
    /// 第一行橘字「11/13 薪轉預估只有 1,400，銀行可能轉不過去」；轉之前已經是負的「11/20 薪轉轉之前已經是 −1,600，銀行可能轉不過去」
    let warnLine: String?
    let buttons: WealthTransferUIPeriodButtons
    let manual: Bool
    let today: Date
    let original: Date
    let day: Date
    let amount: Double
    /// 這一段原本每期多少（〔改這一期〕打一樣的＝不存金額）
    let segmentAmount: Double?
    // [v25.583] 換匯
    /// 兩邊幣別（"NT$" 或外幣代碼）、這期對方收到多少
    let fromCode: String
    let toCode: String
    let toAmount: Double
    /// 這一段原本對方收到多少（段沒寫＝跟轉出一樣，同 LifeStore.markTransferDone）；〔改這一期〕打一樣的＝不存
    let segmentToAmount: Double?
    /// 照遇六日挪過、沒改過日子的那天（〔改這一期〕日子沒動＝不存 dayKey）
    let naturalKey: String
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

    /// [v25.583] 換匯：兩邊幣別不一樣（〔改這一期〕〔今天補轉〕〔轉好了〕多「對方收到」）
    var isExchange: Bool { fromCode != toCode }

    /// 「請先到銀行 App 取消 11/13 那一筆；…」
    var cancelMessage: String {
        "請先到銀行 App 取消 " + WealthTransferUIText.shortDay(original, today: today)
            + " 那一筆；沒取消的話，你先補了錢銀行就會照轉。"
    }

    /// [v25.579]〔改到明天〕：明天沒有跨過下一期才給
    var canMoveToTomorrow: Bool { WealthCal.addDays(1, to: today) <= upper }

    /// 明天的 key（〔改到明天〕存成 dayKey）
    var tomorrowKey: String { WealthTransferSchedule.key(of: WealthCal.addDays(1, to: today)) }

    func range(for mode: WealthTransferUIPeriodEdit) -> ClosedRange<Date> {
        switch mode {
        case .redo:
            let hi = WealthCal.addDays(366, to: Swift.max(today, original))
            return original...hi
        case .change:
            return lower...upper
        case .done:
            // 不放 DatePicker：日子一律今天
            return today...today
        }
    }

    func editTitle(_ mode: WealthTransferUIPeriodEdit) -> String {
        switch mode {
        case .redo: return "補轉那天"
        case .change: return "這期哪天"
        case .done: return "轉好了那天"
        }
    }

    /// 補轉那期按〔改這一期〕也是改補轉（狀態留 redo），標題照按的那顆寫
    func editHeader(_ mode: WealthTransferUIPeriodEdit) -> String {
        switch mode {
        case .redo: return buttons != .redo ? "今天補轉" : "改這一期"
        case .change: return "改這一期"
        case .done: return "轉好了"
        }
    }

    func editFooter(_ mode: WealthTransferUIPeriodEdit) -> String {
        let base: String
        switch mode {
        case .redo:
            base = "日子不能早於原本那天（" + WealthTransferUIText.shortDay(original, today: today) + "）；補轉那天兩邊才算。"
        case .change:
            base = "日子不能跨過前後一期（" + WealthTransferUIText.shortDay(lower, today: today) + "～"
                + WealthTransferUIText.shortDay(upper, today: today) + "）；只改這一期，以後的照舊。"
        case .done:
            base = "今天（" + WealthTransferUIText.shortDay(today, today: today) + "）轉好了；金額跟這期不一樣就改成實際轉的。"
        }
        // [v25.583] 換匯：那一期銀行實際換多少
        guard isExchange else { return base }
        return base + "\n銀行那一期實際換多少（看網銀的換匯明細）；以後的期照規則。"
    }

    /// [v25.579] 自己轉的那幾種按鈕（預計＝nil：照 state 給〔改這一期〕〔這期不轉〕）
    static func manualButtons(_ ph: WealthTransferManualPhase) -> WealthTransferUIPeriodButtons? {
        switch ph {
        case .upcoming: return nil
        case .today: return .manualToday
        case .waiting, .assumed: return .manualWaiting
        case .notYet: return .manualNotYet
        case .done: return .manualDone
        }
    }

    /// 橘字中間那段：「預估只有 1,400」；轉之前已經是負的「轉之前已經是 −1,600」（減號 U+2212）；遮住「預估不夠」「轉之前已經不夠」
    static func warnMiddle(_ s: WealthShortage, masked: Bool) -> String {
        if s.before < -0.5 {
            if masked { return "轉之前已經不夠" }
            return "轉之前已經是 −" + WealthFormat.plain(-s.before, code: s.code)
        }
        if masked { return "預估不夠" }
        return "預估只有 " + WealthFormat.plain(s.before, code: s.code)
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
        // [v25.579] 自己轉的先照在哪一步給（放在補轉前面；補轉、這期不轉、沒轉成、暫停、壞掉的 phase 是 nil，照下面）
        let phase: WealthTransferManualPhase? = manual ? p.manualPhase(today: today) : nil
        if let ph = phase, let b = Self.manualButtons(ph) {
            buttons = b
        } else if p.status == .redo && (p.state == .planned || p.state == .done) {
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
        // [v25.577] 轉之前已經是負的：「11/20 薪轉轉之前已經是 −1,600，銀行可能轉不過去」（同要確認 #10；v1a adjudicate §4-8）
        var warnLine: String? = nil
        if let s = shortage {
            let fromName = facts.account(p.fromId)?.name ?? t.fromName
            let tail = manual ? "，轉之前要先補錢" : "，銀行可能轉不過去"
            let head: String = WealthTransferUIText.shortDay(s.date, today: today) + " " + fromName
            warnLine = head + Self.warnMiddle(s, masked: masked) + tail
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
        // [v25.583] 放寬幾天照週期（每週 6、每兩週 13、每月 27、每年 364）
        let gap: Int = WealthTransferSchedule.editGapDays(t.rule.cycleKind)
        let lo: Date = prev.map { WealthCal.addDays(1, to: $0) } ?? WealthCal.addDays(-gap, to: p.original)
        let hi: Date = next.map { WealthCal.addDays(-1, to: $0) } ?? WealthCal.addDays(gap, to: p.original)

        // [v25.583] 金額兩邊「NT$9,600 → US$300.00」（未來沒改過的期「約」）
        let amountText: String = masked ? WealthFormat.masked : WealthTransferText.pair(p, money: true)
        let dayText = WealthTransferUIText.day(p.day, today: today)
        let spokenAmount: String = (p.isExchange && !masked)
            ? WealthTransferText.pair(p, money: true)
            : WealthTransferUIText.spokenAmount(p.amount, code: p.fromCode, masked: masked)
        let spoken = WealthTransferUIText.spokenDay(p.day) + "，" + t.title + "，" + spokenAmount + "，" + status.spoken
        let seg: WealthTransferSegment? = t.rule.segment(at: key)
        let natural: Date = WealthTransferSchedule.shifted(p.original, holiday: t.rule.holidayKind)

        return WealthTransferUIPeriodModel(
            key: key, caption: "定期轉帳・" + t.title, dayText: dayText, amountText: amountText, status: status,
            warnLine: warnLine, buttons: buttons, manual: manual, today: today, original: p.original, day: p.day,
            amount: p.amount, segmentAmount: seg?.amount, fromCode: p.fromCode, toCode: p.toCode,
            toAmount: p.toAmount, segmentToAmount: seg?.toAmount ?? seg?.amount,
            naturalKey: WealthTransferSchedule.key(of: natural), rawStatus: t.rule.notes?[key]?.status,
            lower: Swift.min(lo, p.original, p.day), upper: Swift.max(hi, p.original, p.day), ackKey: ackKey,
            spoken: spoken)
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
    /// [v25.579]〔轉好了〕存檔時兩邊帳戶今天對過存摺：先問「今天對存摺的時候，這筆轉了嗎？」
    @State private var doneAsk: WealthTransferUIDoneAsk?
    /// [v25.583] 換匯「對方收到」打的字；展開時抓的兩個幣別、是不是換匯（存鈕灰不灰照它算，body 不叫 facts）
    @State private var toAmountText = ""
    @State private var editFromCode = "NT$"
    @State private var editToCode = "NT$"
    @State private var editExchange = false

    private var model: WealthTransferUIPeriodModel? {
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let book = lifeStore.wealthBook
        return WealthTransferUIPeriodModel.make(facts: facts, ruleId: ruleId, key: periodKey, masked: masked,
                                                acknowledged: { book.isDismissed($0) })
    }

    /// 打的金額（台幣到元；< 1 元＝nil，存鈕灰）。[v25.583] 外幣到 0.01
    private var editAmount: Double? { WealthTransferUIText.parseAmount(amountText, code: editFromCode) }

    /// [v25.583] 換匯：對方收到多少（照對方幣別）
    private var editToAmount: Double? { WealthTransferUIText.parseAmount(toAmountText, code: editToCode) }

    /// [v25.583] 存鈕灰：金額沒填好；換匯兩個都要
    private var editSaveDisabled: Bool { editAmount == nil || (editExchange && editToAmount == nil) }

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
        .modifier(WealthTransferUIDoneDialog(ask: $doneAsk, onAnswer: { a, late in answerDone(a, late: late) }))
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
            case .manualToday:
                manualTodayRows(m)
            case .manualWaiting:
                manualWaitingRows(m)
            case .manualNotYet:
                manualNotYetRows(m)
            case .manualDone:
                manualDoneRows(m)
            }
        }
    }

    private var wholeRuleRow: some View {
        WealthTransferUIActionRow(title: "看整條", chevron: true) { openWholeRule() }
    }

    // MARK: [v25.579] 自己轉的按鈕（judge §4.5 v2 那幾列；都不擋訂閱）

    /// 今天要轉：〔轉好了〕（金額可改）〔改到明天〕（明天沒跨過下一期才有）〔這期不轉〕〔看整條〕
    @ViewBuilder
    private func manualTodayRows(_ m: WealthTransferUIPeriodModel) -> some View {
        WealthTransferUIActionRow(title: "轉好了", detail: "金額不一樣可以改") { startEdit(m, mode: .done) }
        if m.canMoveToTomorrow {
            WealthTransferUIActionRow(title: "改到明天") { moveToTomorrow(m) }
        }
        WealthTransferUIActionRow(title: "這期不轉") { setStatus(WealthTransferStatus.skip.rawValue) }
        wholeRuleRow
    }

    /// 當作轉了・等你回答／當作轉了：〔轉了〕（日子照留）〔還沒，算在明天〕〔這期不轉〕〔改這一期〕〔看整條〕
    @ViewBuilder
    private func manualWaitingRows(_ m: WealthTransferUIPeriodModel) -> some View {
        WealthTransferUIActionRow(title: "轉了") { setStatus(WealthTransferStatus.done.rawValue) }
        WealthTransferUIActionRow(title: "還沒，算在明天", detail: "每天往後挪") {
            setStatus(WealthTransferStatus.notYet.rawValue)
        }
        WealthTransferUIActionRow(title: "這期不轉") { setStatus(WealthTransferStatus.skip.rawValue) }
        WealthTransferUIActionRow(title: "改這一期", detail: "金額、日子") { startEdit(m, mode: .change) }
        wholeRuleRow
    }

    /// 還沒轉・算在明天：〔轉好了〕（今天轉的）〔這期不轉〕（〔知道了〕照舊）〔看整條〕
    @ViewBuilder
    private func manualNotYetRows(_ m: WealthTransferUIPeriodModel) -> some View {
        WealthTransferUIActionRow(title: "轉好了", detail: "金額不一樣可以改") { startEdit(m, mode: .done) }
        WealthTransferUIActionRow(title: "這期不轉") { setStatus(WealthTransferStatus.skip.rawValue) }
        if m.ackKey != nil {
            WealthTransferUIActionRow(title: "知道了", detail: "不再出現在要確認") { acknowledge(m) }
        }
        wholeRuleRow
    }

    /// 轉好了：〔改這一期〕（狀態照留 "done"）〔復原〕〔看整條〕
    @ViewBuilder
    private func manualDoneRows(_ m: WealthTransferUIPeriodModel) -> some View {
        WealthTransferUIActionRow(title: "改這一期", detail: "金額、日子") { startEdit(m, mode: .change) }
        WealthTransferUIActionRow(title: "復原", detail: "回到還沒按〔轉好了〕") { setStatus(nil) }
        wholeRuleRow
    }

    private func editSection(_ m: WealthTransferUIPeriodModel, mode: WealthTransferUIPeriodEdit) -> some View {
        Section {
            if mode == .done {
                doneAmountRow
                if editExchange {
                    toAmountRow
                }
                Button("存") { tapSaveDone() }
                    .disabled(editSaveDisabled)
            } else {
                if editExchange {
                    fromAmountRow
                    toAmountRow
                } else {
                    HStack {
                        Text(WealthTransferUIText.prefix(editFromCode)).foregroundStyle(Color.secondary)
                        TextField("這期轉多少", text: $amountText)
                            .keyboardType(FinanceRates.isNTD(editFromCode) ? .numberPad : .decimalPad)
                    }
                }
                DatePicker(m.editTitle(mode), selection: $pickedDay, in: m.range(for: mode), displayedComponents: .date)
                Button("存") { saveEdit(m, mode: mode) }
                    .disabled(editSaveDisabled)
            }
            Button("取消") { editing = nil }
        } header: {
            Text(m.editHeader(mode))
        } footer: {
            Text(m.editFooter(mode))
        }
    }

    /// [v25.583] 換匯「轉出　NT$〔9,600〕」
    private var fromAmountRow: some View {
        HStack(spacing: 8) {
            Text("轉出")
            Spacer(minLength: 8)
            Text(WealthTransferUIText.prefix(editFromCode)).foregroundStyle(Color.secondary)
            TextField("這期轉多少", text: $amountText)
                .keyboardType(FinanceRates.isNTD(editFromCode) ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 72, maxWidth: 140)
        }
    }

    /// [v25.583] 換匯「對方收到　US$〔300〕」（那期銀行實際換多少）
    private var toAmountRow: some View {
        HStack(spacing: 8) {
            Text("對方收到")
            Spacer(minLength: 8)
            Text(WealthTransferUIText.prefix(editToCode)).foregroundStyle(Color.secondary)
            TextField("多少", text: $toAmountText)
                .keyboardType(FinanceRates.isNTD(editToCode) ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 72, maxWidth: 140)
        }
    }

    // MARK: 按鈕

    private func startEdit(_ m: WealthTransferUIPeriodModel, mode: WealthTransferUIPeriodEdit) {
        amountText = WealthFormText.editable(m.amount)
        // [v25.583] 換匯：兩個金額都帶這期的
        editFromCode = m.fromCode
        editToCode = m.toCode
        editExchange = m.isExchange
        toAmountText = m.isExchange ? WealthFormText.editable(m.toAmount) : ""
        let range = m.range(for: mode)
        // 〔今天補轉〕預設今天（不早於原本那天）；其他照現在那天
        let start: Date = m.buttons == .failed ? Swift.max(m.today, m.original) : m.day
        pickedDay = Swift.min(Swift.max(start, range.lowerBound), range.upperBound)
        editing = mode
    }

    /// 〔存〕：那一期的註記（金額跟這一段原本一樣＝不存；日子等於原本那天＝不存）。
    /// [v25.583] 〔改這一期〕日子沒動（＝遇六日挪過的那天）也不存；換匯兩個金額都存（跟這一段一樣的那一個傳 nil：台幣 ±0.5、外幣 ±0.005）
    private func saveEdit(_ m: WealthTransferUIPeriodModel, mode: WealthTransferUIPeriodEdit) {
        guard let v = editAmount else { return }
        let range = m.range(for: mode)
        let picked = Swift.min(Swift.max(WealthCal.day(pickedDay), range.lowerBound), range.upperBound)
        let pickedKey = WealthTransferSchedule.key(of: picked)
        let unmoved: Bool = pickedKey == m.key || (mode == .change && pickedKey == m.naturalKey)
        let dayKey: String? = unmoved ? nil : pickedKey
        var same = false
        if let s = m.segmentAmount, Swift.abs(s - v) < WealthTransferUIText.tolerance(m.fromCode) { same = true }
        let amount: Double? = same ? nil : v
        let status: String? = mode == .redo ? WealthTransferStatus.redo.rawValue : m.rawStatus
        let exchange: Bool = m.isExchange
        var toAmount: Double? = nil
        if exchange {
            guard let tv = editToAmount else { return }
            var sameTo = false
            if let s = m.segmentToAmount, Swift.abs(s - tv) < WealthTransferUIText.tolerance(m.toCode) { sameTo = true }
            toAmount = sameTo ? nil : tv
        }
        let toValue: Double? = toAmount
        let life = lifeStore
        let rid = ruleId
        let key = periodKey
        dismiss()
        DispatchQueue.main.async {
            if exchange {
                life.setTransferNote(ruleId: rid, key: key, status: status, dayKey: dayKey, amount: amount,
                                     toAmount: toValue)
            } else {
                life.setTransferNote(ruleId: rid, key: key, status: status, dayKey: dayKey, amount: amount)
            }
        }
    }

    /// [v25.579]「轉好了」那一欄的金額：「實際轉了　NT$〔5,000〕」（不放 DatePicker：日子一律今天）；[v25.583] 字頭照幣別
    private var doneAmountRow: some View {
        HStack(spacing: 8) {
            Text("實際轉了")
            Spacer(minLength: 8)
            Text(WealthTransferUIText.prefix(editFromCode)).foregroundStyle(Color.secondary)
            TextField("這期轉多少", text: $amountText)
                .keyboardType(FinanceRates.isNTD(editFromCode) ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 72, maxWidth: 140)
        }
    }

    /// [v25.579]「轉好了」〔存〕：兩邊帳戶今天對過存摺（那個幣別）先關這一欄、問一句；沒對過直接存。
    /// [v25.583] 換匯多帶對方收到多少
    private func tapSaveDone() {
        guard let v = editAmount else { return }
        let tv: Double? = editExchange ? editToAmount : nil
        if editExchange && tv == nil { return }
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let rec = facts.transferReconciledToday(ruleId: ruleId, key: periodKey)
        if rec.any {
            editing = nil
            doneAsk = WealthTransferUIDoneAsk(amount: v, from: rec.from, to: rec.to, toAmount: tv)
            return
        }
        saveDone(v, lateOut: nil, lateIn: nil, toAmount: tv)
    }

    /// 「今天對存摺的時候，這筆轉了嗎？」：〔還沒，對完才轉的〕對過的那一邊記 late（true）；〔轉了，存摺上已經有了〕那一邊拿掉（false）；
    /// 沒對過的那一邊 nil（照留）
    private func answerDone(_ a: WealthTransferUIDoneAsk, late: Bool) {
        doneAsk = nil
        let lo: Bool? = a.from ? late : nil
        let li: Bool? = a.to ? late : nil
        saveDone(a.amount, lateOut: lo, lateIn: li, toAmount: a.toAmount)
    }

    /// [v25.579]〔轉好了〕：先關，下一個 runloop 才寫（status "done"、日子今天、金額跟這一段一樣不存——LifeStore.markTransferDone）。
    /// [v25.583] toAmount：換匯對方實際收到多少（nil＝照留；跟這一段一樣 LifeStore 不存）
    private func saveDone(_ v: Double, lateOut: Bool?, lateIn: Bool?, toAmount: Double?) {
        let life = lifeStore
        let rid = ruleId
        let key = periodKey
        dismiss()
        DispatchQueue.main.async {
            life.markTransferDone(ruleId: rid, key: key, day: Date(), amount: v, lateOut: lateOut, lateIn: lateIn,
                                  toAmount: toAmount)
        }
    }

    /// [v25.579]〔改到明天〕：那一期的日子改成明天（狀態照留；金額跟這一段一樣不存、改過的照留）
    private func moveToTomorrow(_ m: WealthTransferUIPeriodModel) {
        var same = false
        if let s = m.segmentAmount, Swift.abs(s - m.amount) < WealthTransferUIText.tolerance(m.fromCode) { same = true }
        let amount: Double? = same ? nil : m.amount
        let status: String? = m.rawStatus
        let dayKey: String = m.tomorrowKey
        let life = lifeStore
        let rid = ruleId
        let key = periodKey
        dismiss()
        DispatchQueue.main.async {
            life.setTransferNote(ruleId: rid, key: key, status: status, dayKey: dayKey, amount: amount)
        }
    }

    /// 〔銀行這期取消了〕〔這期不轉〕"skip"、〔沒轉成〕"failed"、〔復原〕〔銀行還是轉了〕〔還是要轉〕nil；
    /// [v25.579]〔轉了〕"done"（日子照留）、〔還沒，算在明天〕"notYet"
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

// MARK: - [v25.579] D. 銀行那邊設到哪天（要確認〔已經續設〕；transfer/build/v2/brief.md §6 G1-D）
// 主控開的骨架（名字、參數、外框定好：WealthEditors 的 WealthFormSheet.transferRenew 照這個名字打開）；G1 實作裡面。
// 不擋訂閱（同〔結束〕：銀行那邊續設了，App 也要改得了）；寫 store 先 dismiss、下一個 runloop 才叫 LifeStore.updateTransferRule。

/// 一條定期轉帳的「銀行那邊設到哪天」：〔不設〕〔到哪天〕〔共幾次〕（銀行續設之後改結束日）。
/// [v25.579] G1：照新增表單 endSection 同一套（WealthTransferUIEnd、WealthTransferUITimesRow、WealthTransferUIEndSpec）；
/// 〔共幾次〕從這條的第一期起數（v1b 已知限制 8 同一套）。預設：原本有結束日＝〔到哪天〕＋原本那天、沒有＝〔不設〕。
/// 新的最後一期早於今天＝存鈕灰、紅字「要選今天以後」。〔存〕＝dismiss、下一個 runloop updateTransferRule（endKey 換成新的、endedBy nil）。
/// 例：2027/3/26 開、〔共幾次〕48 → endKey 2027-09-24 → 要確認那一條不見、到期通知改成 9/10
struct WealthTransferRenewSheet: View {
    let ruleId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var loaded = false
    /// 今天 00:00（打開時從 facts 抓一次）
    @State private var today: Date = WealthCal.day(Date())
    /// 打開時那一條（找不到＝刪了）
    @State private var rule: WealthTransferRule? = nil
    /// 「『薪轉 → 零用錢』現在設到 2027/4/9（五）」
    @State private var currentLine = ""
    @State private var endMode: WealthTransferUIEnd = .noEnd
    @State private var endDate = Date()
    @State private var timesText = "12"

    private var timesValue: Int {
        let n = Int(timesText.trimmingCharacters(in: .whitespaces)) ?? 1
        return Swift.min(Swift.max(n, 1), 240)
    }

    /// 〔不設〕〔到哪天〕〔共幾次〕照這一條的日子換算
    private var spec: WealthTransferUIEndSpec {
        switch endMode {
        case .noEnd: return .noEnd
        case .byDate: return .date(WealthCal.day(endDate))
        case .byCount: return .count(timesValue)
        }
    }

    /// 新的最後一期（不設＝nil）
    private var newLast: Date? {
        guard let r = rule, let k = spec.key(for: r) else { return nil }
        return WealthTransferSchedule.date(fromKey: k)
    }

    /// 新的最後一期早於今天（〔到哪天〕比今天以後第一期還早、〔共幾次〕太少）：擋存檔＋紅字
    private var endInvalid: Bool {
        guard endMode != .noEnd else { return false }
        guard let d = newLast else { return true }
        return d < today
    }

    private var saveDisabled: Bool { rule == nil || endInvalid }

    /// 「共 48 次：最後一次 2027/9/24（五）」；早於今天「要選今天以後」
    private var endLine: String? {
        guard endMode != .noEnd else { return nil }
        if endInvalid { return "要選今天以後" }
        guard var r = rule, let last = newLast else { return nil }
        r.endKey = WealthTransferSchedule.key(of: last)
        let n = WealthTransferSchedule.originalDates(r, through: last).count
        return "共 \(n) 次：最後一次 " + Self.fullDay(last)
    }

    /// 「2027/4/9（五）」（續設多半跨年：一律寫年）
    private static func fullDay(_ d: Date) -> String {
        WealthFormat.ymd(d) + "（" + WealthTransferText.weekdayName(d) + "）"
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("銀行續設")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("存") { save() }
                            .disabled(saveDisabled)
                    }
                }
                .onAppear { load() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    @ViewBuilder
    private var content: some View {
        if !loaded {
            Form {}
        } else if rule == nil {
            Form {
                Text("這條定期轉帳已經刪了")
                    .foregroundStyle(Color.secondary)
            }
        } else {
            Form {
                Section {
                    Text(currentLine)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                endSection
            }
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
            Text("銀行續設好了再改這裡；App 不會幫你改銀行。")
        }
    }

    /// 打開時帶好：原本有結束日＝〔到哪天〕＋那天（〔共幾次〕先填到那天的次數）；沒有＝〔不設〕
    private func load() {
        guard !loaded else { return }
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let t = facts.today
        today = t
        endDate = WealthCal.addMonths(12, to: t)
        if let tr = facts.transferRule(ruleId) {
            let r = tr.rule
            rule = r
            if let ek = r.endKey, let ed = WealthTransferSchedule.date(fromKey: ek), r.startKey.map({ ek >= $0 }) ?? true {
                endMode = .byDate
                endDate = Swift.max(ed, t)
                let n = WealthTransferSchedule.originalDates(r, through: ed).count
                if n >= 1 { timesText = String(Swift.min(n, 240)) }
                currentLine = "『" + tr.title + "』現在設到 " + Self.fullDay(ed)
            } else {
                currentLine = "『" + tr.title + "』現在沒有設結束日"
            }
        }
        loaded = true
    }

    /// 〔存〕：先關，下一個 runloop 才寫（照存著的那一條最新的日子換算；endedBy 拿掉＝銀行那邊設的）。不擋訂閱
    private func save() {
        guard rule != nil, !endInvalid else { return }
        let s = spec
        let life = lifeStore
        let id = ruleId
        dismiss()
        DispatchQueue.main.async {
            life.updateTransferRule(id) { r in
                r.endKey = s.key(for: r)
                r.endedBy = nil
            }
        }
    }
}
