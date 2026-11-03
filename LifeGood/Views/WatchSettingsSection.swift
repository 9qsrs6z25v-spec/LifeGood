import SwiftUI
import Combine

// MARK: - 設定頁「Apple Watch」段（手錶 v1，v25.574；只屬於主 App；watch/judge.md §2.16、§6.3、§6.5、§6.6；
//         watch/build/v1/brief.md G1-7）
//
// SettingsView 用 disclosureBlock 包它（跟「桌面小工具」同一組；沒配對手錶整段不出現）。
// 這一版的列：
//   • 加入別人的共享時：「這支 iPhone 加入了別人的共享，手錶會看到共享裡的行程」（judge §6.6）
//   • 狀態：「手錶版已安裝・上次送到手錶 09:24・6 KB」／「手錶版已安裝・還沒送過」／沒裝時怎麼裝
//   • 錢（還能花、接下來要繳）［開］：關掉＝iPhone 下一次送包就不放，手錶 ② 錢整頁消失
//   • 會議細節裡的部屬名字［開］：只在手錶 App 抬手看會議細節時；關著＝連送都不送。加入別人共享的 iPhone 沒設定過預設關
//   • 背景建立資料：N 次（給查問題用，judge §5.4）
// [手錶 v2] v25.576（watch/build/v2/brief.md G1-3；judge §2.16、§6.3）：
//   • 手機條碼［關］：預設不送；打開才把「電子發票」連結的手機條碼送到手錶（② 錢左上 🧾 全螢幕給店員掃）。
//     驗證碼在鑰匙圈，永遠不送。還沒連結時小字寫怎麼連結（連結、拿掉時 EInvoiceSyncManager 自己叫 settingsChanged）
//   • 「錢」關掉的小字多一句：手錶上也不能記帳（記帳台、今天記的帳都跟著「錢」走）
// [手錶 v6] v25.578（watch/build/v6/brief.md G1-4；judge §2.16「旅行 [開]」、§6.3）：
//   • 旅行（下一站、打卡、記外幣）［開］：出發前 7 天到回來那天把今天、明天的站送到手錶（④ 旅行、錶面下一場）；
//     關掉＝今天明天的站不送、出發倒數也拿掉（WatchPhoneSettings.sendTrip 同一個鍵；沒設定過＝開）
//   • 小字多一句：旅行只送站名、時間、地址、電話、天氣；不送備註、照片、同行者
// [手錶 v5] v25.582（watch/build/v5/brief.md G1-3；judge §2.16、§8 v5 做好標準 5；brief §1-2、§1-3）：
//   • 手錶版已安裝時多一列「開始跑步時」：每次問／用手錶記／用 iPhone 記（WatchRunStarter.choice，UserDefaults.standard，
//     只這支 iPhone；健康頁「▶ 開始跑步」勾「記住我的選擇」存的同一個；改回「每次問」就又會問）
//   • 那一列的小字：手錶說有一趟沒存成 →「手錶上有 1 趟沒存進 Apple 健康」；不然「手錶上次跑完 06:45」
//     （WatchRunFlags.lastRanAt＝手錶那一趟結束的時間；不同天「10/21 22:10」）；都沒有寫怎麼用。
//     打開這一段、手錶送「我跑完了」「沒存成」（WatchRunFlags.changed）時重讀
//   • 小字多一句：用手錶記時 iPhone 不會多記一筆；手錶跑完會叫 iPhone 馬上帶進健康頁
//   • 第一列照舊「手錶版已安裝・上次送到手錶 09:24・6 KB」；SettingsView.swift 一行不動
// [手錶 v7b] v25.584（watch/build/v7b/brief.md G1；judge §2.16、§6.3；brief 主控定案 7）：
//   • 「智慧型堆疊卡（watchOS 26）」總開關［開］（WatchPhoneSettings.stackCardsKey 同一個鍵；沒設定過＝開）：
//     關掉＝iPhone 下一包 relevanceCards 是 nil，五張卡不浮，「下一場」「已花」「這週跑步」也不自己往上排
//   • 五張卡各自一個開關［開］（WatchRelevanceKind.allCases 的順序：早安、快開會了、卡費快到了、平常跑步的時間、旅途下一站；
//     鍵 WatchRelevanceKind.settingsKey；小字 WatchRelevanceKind.whenText）。總開關關著時五列變暗（.disabled，不拿掉）
//   • 小字一列：「錶面上至少放一格 LifeGood 數字才會自己跟上；只放堆疊的話打開手錶 App 一次就更新」
//   • 新列全收在 stackBlock（ownerToggle 之後、diagnosticsRow 之前；Section 直接子 view 9 個）
//   • 說明多一句：智慧型堆疊卡不寫卡名、卡費金額、部屬名字，也不放天氣；手腕放下時連會議名、站名也不寫
//   • 說明最後那句（v1「錶面上至少放一格 LifeGood，數字才會自己跟上…」）拿掉：跟上面那一列同一句，不在同一段寫兩次（judge §2.16、§3.2）
// [手錶 v7a] v25.585（watch/build/v7a/brief.md G1-3、主控定案 13；judge §2.16、§6.1）：
//   • 「錢」那一列後面多一列「說一句（手錶記帳台第 4 格）」（不是開關；Section 直接子 view 從 9 個變 10 個）：
//     小字寫能不能用、為什麼——「錢」關掉／可以用／要訂閱／先到進階設定設好語音 AI 助手（WatchVoiceRule.ready 跟手錶包同一個判斷）
//   • 訂閱、AI 設定改了這一列跟著換字（SubscriptionManager.shared、AISettingsStore.shared 都 @ObservedObject）；
//     打開這一列、這一列的字換了（訂閱、AI 設定改了）時 WatchExtrasWriter.refreshVoiceReady()（剛設好 AI 回到這頁，手錶下一包馬上跟上）
//   • 說明多一句：你講的那句只送到 iPhone 解析；回手錶的字付款只寫刷卡／現金／轉帳，不寫卡名
// 改了開關：寫 App Group（WatchPhoneSettings 同一組鍵）→ bridge.settingsChanged() 重組重送。

struct WatchSettingsSection: View {
    @ObservedObject var bridge: WatchBridge

    /// 送到手錶：錢（WatchPhoneSettings.sendMoney 同一個鍵；沒設定過＝開）
    @AppStorage(WatchPhoneSettings.sendMoneyKey, store: WidgetShared.defaults) private var sendMoney = true
    /// [v2] 送到手錶：手機條碼（WatchPhoneSettings.sendBarcode 同一個鍵；沒設定過＝關）
    @AppStorage(WatchPhoneSettings.sendBarcodeKey, store: WidgetShared.defaults) private var sendBarcode = false
    /// [v6] 送到手錶：旅行（WatchPhoneSettings.sendTrip 同一個鍵；沒設定過＝開）
    @AppStorage(WatchPhoneSettings.sendTripKey, store: WidgetShared.defaults) private var sendTrip = true
    /// [v2] 電子發票連結、拿掉手機條碼時重畫（手機條碼那一列的小字）
    @ObservedObject private var einvoice = EInvoiceSyncManager.shared
    /// 會議細節裡的部屬名字（沒設定過＝這支 iPhone 不是加入別人的共享就開）
    @State private var showOwnerNames =
        WatchPhoneSettings.showOwnerNames(isShareParticipant: CloudKitManager.shared.isShareParticipant)
    /// [v5] 開始跑步時（每次問／用手錶記／用 iPhone 記）：onAppear 才讀 WatchRunStarter.choice（@MainActor，不在初值碰）
    @State private var runChoice: WatchRunStarter.Choice = .ask
    /// [v5] 手錶說有一趟沒存進 Apple 健康（WatchRunFlags 只碰 UserDefaults、沒有 actor：初值直接讀）
    @State private var runUnsaved = WatchRunFlags.hasUnsaved(now: Date())
    /// [v5] 手錶上次跑完（那一趟結束的時間）
    @State private var runLastRanAt: Date? = WatchRunFlags.lastRanAt
    /// [v7b] 智慧型堆疊卡總開關（WatchPhoneSettings.stackCards 同一個鍵；沒設定過＝開）
    @AppStorage(WatchPhoneSettings.stackCardsKey, store: WidgetShared.defaults) private var stackCards = true
    /// [v7b] 五張卡各自的開關（WatchPhoneSettings.stackKinds 同一組鍵；沒設定過＝開）
    @AppStorage(WatchRelevanceKind.morning.settingsKey, store: WidgetShared.defaults) private var stackMorning = true
    @AppStorage(WatchRelevanceKind.meeting.settingsKey, store: WidgetShared.defaults) private var stackMeeting = true
    @AppStorage(WatchRelevanceKind.cardBill.settingsKey, store: WidgetShared.defaults) private var stackCardBill = true
    @AppStorage(WatchRelevanceKind.usualRun.settingsKey, store: WidgetShared.defaults) private var stackUsualRun = true
    @AppStorage(WatchRelevanceKind.tripStop.settingsKey, store: WidgetShared.defaults) private var stackTripStop = true
    /// [v7a] 說一句那一列：訂閱、AI 設定改了跟著換字
    @ObservedObject private var subscription = SubscriptionManager.shared
    @ObservedObject private var ai = AISettingsStore.shared

    var body: some View {
        Section {
            if CloudKitManager.shared.isShareParticipant {
                shareRow
            }
            statusRow
            if bridge.isWatchAppInstalled {
                runRow
            }
            moneyToggle
            voiceRow
            barcodeToggle
            tripToggle
            ownerToggle
            stackBlock
            diagnosticsRow
        } header: {
            Text("送到手錶的內容")
        } footer: {
            Text(Self.footnote)
        }
    }

    // MARK: 列

    private var shareRow: some View {
        rowLabel(icon: "person.2.fill", color: .orange,
                 title: "這支 iPhone 加入了別人的共享",
                 subtitle: "手錶會看到共享裡的行程")
    }

    private var statusRow: some View {
        rowLabel(icon: "applewatch", color: .indigo,
                 title: bridge.isWatchAppInstalled ? "手錶版已安裝" : "手錶版還沒裝",
                 subtitle: statusSubtitle)
    }

    /// [v5] 開始跑步時：每次問／用手錶記／用 iPhone 記（健康頁「▶ 開始跑步」、跑步畫面〔開始〕照這個走）
    private var runRow: some View {
        Picker(selection: $runChoice) {
            ForEach(WatchRunStarter.Choice.allCases) { c in
                Text(c.title).tag(c)
            }
        } label: {
            rowLabel(icon: "figure.run", color: .orange,
                     title: WatchRunStarter.settingsRowTitle, subtitle: runSubtitle)
        }
        .pickerStyle(.menu)
        .onAppear {
            runChoice = WatchRunStarter.choice
            refreshRunFlags()
        }
        .onChange(of: runChoice) { _, c in
            WatchRunStarter.setChoice(c)
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchRunFlags.changed)) { _ in
            refreshRunFlags()
        }
    }

    private var moneyToggle: some View {
        Toggle(isOn: $sendMoney) {
            rowLabel(icon: "dollarsign.circle.fill", color: .green,
                     title: "錢（還能花、接下來要繳）",
                     subtitle: sendMoney ? "送到手錶" : "不送：手錶上沒有「錢」那一頁，也不能在手錶記帳")
        }
        .tint(.indigo)
        .onChange(of: sendMoney) { _, _ in
            bridge.settingsChanged()
        }
    }

    /// [v7a] 說一句（手錶記帳台第 4 格）：不是開關，只寫能不能用、為什麼（手錶設定 › 記帳台第 4 格才換回常記的那一筆）
    private var voiceRow: some View {
        rowLabel(icon: "mic.fill", color: .purple, title: Self.voiceTitle, subtitle: voiceSubtitle)
            .onAppear {
                WatchExtrasWriter.refreshVoiceReady()
            }
            // 進階設定是推進去的另一頁：設好 AI 返回時這一列不一定再 onAppear；字一換（訂閱、AI 改了）就跟上
            .onChange(of: voiceSubtitle) { _, _ in
                WatchExtrasWriter.refreshVoiceReady()
            }
    }

    /// [v2] 手機條碼（預設關；驗證碼永遠不送）
    private var barcodeToggle: some View {
        Toggle(isOn: $sendBarcode) {
            rowLabel(icon: "barcode", color: .teal, title: "手機條碼", subtitle: barcodeSubtitle)
        }
        .tint(.indigo)
        .onChange(of: sendBarcode) { _, _ in
            bridge.settingsChanged()
        }
    }

    /// [v6] 旅行（預設開；關掉＝手錶上沒有旅行那一頁、也不寫出發倒數）
    private var tripToggle: some View {
        Toggle(isOn: $sendTrip) {
            rowLabel(icon: "airplane", color: .purple,
                     title: "旅行（下一站、打卡、記外幣）",
                     subtitle: sendTrip ? Self.tripOn : Self.tripOff)
        }
        .tint(.indigo)
        .onChange(of: sendTrip) { _, _ in
            bridge.settingsChanged()
        }
    }

    private var ownerToggle: some View {
        Toggle(isOn: $showOwnerNames) {
            rowLabel(icon: "person.fill", color: .blue,
                     title: "會議細節裡的部屬名字",
                     subtitle: Self.ownerSubtitle)
        }
        .tint(.indigo)
        .onChange(of: showOwnerNames) { _, on in
            WatchPhoneSettings.setShowOwnerNames(on)
            bridge.settingsChanged()
        }
    }

    /// [v7b] 智慧型堆疊卡：總開關＋五張卡（WatchRelevanceKind.allCases 的順序）＋那一句。
    /// 每個開關改了都 bridge.settingsChanged()（WatchPhoneSettings 讀同一組鍵，這裡不另外存）
    @ViewBuilder
    private var stackBlock: some View {
        stackMasterToggle
        stackToggle(.morning, isOn: $stackMorning)
            .onChange(of: stackMorning) { _, _ in bridge.settingsChanged() }
        stackToggle(.meeting, isOn: $stackMeeting)
            .onChange(of: stackMeeting) { _, _ in bridge.settingsChanged() }
        stackToggle(.cardBill, isOn: $stackCardBill)
            .onChange(of: stackCardBill) { _, _ in bridge.settingsChanged() }
        stackToggle(.usualRun, isOn: $stackUsualRun)
            .onChange(of: stackUsualRun) { _, _ in bridge.settingsChanged() }
        stackToggle(.tripStop, isOn: $stackTripStop)
            .onChange(of: stackTripStop) { _, _ in bridge.settingsChanged() }
        stackNoteRow
    }

    /// [v7b] 總開關（關掉＝下一包不放卡、三種也不自己往上排）
    private var stackMasterToggle: some View {
        Toggle(isOn: $stackCards) {
            rowLabel(icon: "square.stack.3d.up.fill", color: .teal,
                     title: "智慧型堆疊卡（watchOS 26）",
                     subtitle: stackCards ? Self.stackOn : Self.stackOff)
        }
        .tint(.indigo)
        .onChange(of: stackCards) { _, _ in
            bridge.settingsChanged()
        }
    }

    /// [v7b] 一張卡的開關（總開關關著時變暗、不拿掉；往右縮一點表示在總開關底下）
    private func stackToggle(_ kind: WatchRelevanceKind, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            rowLabel(icon: kind.icon, color: stackColor(kind), title: kind.title, subtitle: kind.whenText)
        }
        .tint(.indigo)
        .disabled(!stackCards)
        .padding(.leading, 12)
    }

    /// [v7b] 「錶面上至少放一格 LifeGood 數字才會自己跟上…」
    private var stackNoteRow: some View {
        Text(Self.stackFaceNote)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// [v7b] 每張卡圖示的色
    private func stackColor(_ kind: WatchRelevanceKind) -> Color {
        switch kind {
        case .morning:  return .orange
        case .meeting:  return .blue
        case .cardBill: return .yellow
        case .usualRun: return .orange
        case .tripStop: return .purple
        }
    }

    /// [v5] 重讀手錶跑步的旗子（打開這一段、WatchRunFlags.changed）
    private func refreshRunFlags() {
        runUnsaved = WatchRunFlags.hasUnsaved(now: Date())
        runLastRanAt = WatchRunFlags.lastRanAt
    }

    private var diagnosticsRow: some View {
        Text(diagnosticsText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// 圖示圓＋標題／小字（SettingsView 的 settingsActionRow 是 private，這裡自己畫一個小的）
    private func rowLabel(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 字

    /// 「上次送到手錶 09:24・6 KB」／「還沒送過」／沒裝時怎麼裝
    private var statusSubtitle: String {
        guard bridge.isWatchAppInstalled else { return Self.installHint }
        guard let at = bridge.lastSentAt else { return "還沒送過" }
        return "上次送到手錶 " + Self.sentTime(at, now: Date()) + "・" + Self.kilobytes(bridge.lastSentBytes)
    }

    /// [v5]「手錶上有 1 趟沒存進 Apple 健康」／「手錶上次跑完 06:45」（不同天「10/21 22:10」）／怎麼用
    private var runSubtitle: String {
        if runUnsaved { return Self.runUnsavedNote }
        if let t = runLastRanAt { return Self.runLastPrefix + Self.sentTime(t, now: Date()) }
        return Self.runHint
    }

    /// [v7a]「錢」關掉／可以用／要訂閱／先設好 AI（跟手錶包 voiceReady 同一個判斷：WatchVoiceRule.ready）
    private var voiceSubtitle: String {
        if !sendMoney { return Self.voiceMoneyOff }
        if WatchVoiceRule.ready(premium: subscription.isPremium, aiReady: ai.isReady) { return Self.voiceReadyText }
        if !subscription.isPremium { return Self.voiceNeedsPremium }
        return Self.voiceNeedsAI
    }

    /// [v2] 還沒連結（或格式不對，不會送）／開著／關著。跟組包看同一個（WatchPhoneSettings.carrierBarcode）；
    /// einvoice 只用來在連結、拿掉時重畫這一列
    private var barcodeSubtitle: String {
        guard WatchPhoneSettings.carrierBarcode != nil else { return Self.barcodeNotLinked }
        return sendBarcode ? Self.barcodeOn : Self.barcodeOff
    }

    /// 「背景建立資料：0 次」；有過的話後面接最近一次「（最近 10/22 03:12）」
    private var diagnosticsText: String {
        let n = AppStoresDiagnostics.count
        let head = "背景建立資料：" + String(n) + " 次"
        guard n > 0, let last = AppStoresDiagnostics.last else { return head }
        return head + "（最近 " + Self.sentTime(last, now: Date()) + "）"
    }

    /// 同一天只寫「09:24」；不同天「10/21 22:10」
    static func sentTime(_ at: Date, now: Date) -> String {
        let time = DayTimelineFormat.time(at)
        if Calendar.current.isDate(at, inSameDayAs: now) { return time }
        return WidgetDateText.shortDate(at) + " " + time
    }

    /// 「6 KB」（無條件進位、最少 1 KB）
    static func kilobytes(_ bytes: Int) -> String {
        String(max(1, (bytes + 1023) / 1024)) + " KB"
    }

    /// 說明一次寫成單一字串常數，不要在 Text(...) 裡用 + 串接
    private static let installHint = "iPhone「Watch」App › 可用的 App › LifeGood〔安裝〕"

    private static let ownerSubtitle = "只在手錶 App 抬手看會議細節時；錶面、通知、手腕放下都不寫"

    private static let barcodeNotLinked = "還沒在「電子發票」連結手機條碼"
    private static let barcodeOn = "送到手錶：② 錢左上 🧾；驗證碼永遠不送"
    private static let barcodeOff = "不送（預設）；驗證碼永遠不送"

    private static let tripOn = "出發前 7 天到回來那天送到手錶；天氣由 iPhone 抓"
    private static let tripOff = "不送：手錶上沒有旅行那一頁、也不寫出發倒數"

    /// [v5] 開始跑步時那一列的小字
    private static let runUnsavedNote = "手錶上有 1 趟沒存進 Apple 健康"
    private static let runLastPrefix = "手錶上次跑完 "
    private static let runHint = "選「用手錶記」：健康頁按開始，手錶自己打開準備頁"

    /// [v7b] 智慧型堆疊卡那幾列的字
    private static let stackOn =
        "早安、快開會了、卡費快到了、平常跑步的時間、旅途下一站到時間自己浮上來；你加進堆疊的下一場、已花、這週跑步也會自己排到上面"
    private static let stackOff = "關掉：卡不會浮上來，下一場、已花、這週跑步也不自己往上排"
    private static let stackFaceNote = "錶面上至少放一格 LifeGood 數字才會自己跟上；只放堆疊的話打開手錶 App 一次就更新"

    /// [v7a] 說一句那一列的字
    private static let voiceTitle = "說一句（手錶記帳台第 4 格）"
    private static let voiceReadyText = "可以用：在手錶上講一句就記好"
    private static let voiceNeedsPremium = "要訂閱 LifeGood 才能用"
    private static let voiceNeedsAI = "先到「進階設定 › 語音 AI 助手」選好服務、填好金鑰"
    private static let voiceMoneyOff = "「錢」關掉時手錶上不能記帳，也不能說一句"

    private static let footnote: String =
        "卡名、卡費金額、存摺、淨資產、部屬請假、完整號碼不會送到手錶。手腕放下時手錶上的金額一律遮起來。"
        + "手機條碼預設不送；發票驗證碼永遠不送。"
        + "旅行只送站名、時間、地址、電話、天氣；不送備註、照片、同行者。"
        + "會議主題會出現在錶面與通知上。"
        + "智慧型堆疊卡不寫卡名、卡費金額、部屬名字，也不放天氣；手腕放下時連會議名、站名也不寫。"
        + "跑步選「用手錶記」時，iPhone 不會多記一筆；手錶跑完會叫 iPhone 馬上帶進健康頁。"
        + "手錶說一句：你講的那句只送到 iPhone 解析；回手錶的字付款只寫刷卡／現金／轉帳，不寫卡名。"
}
