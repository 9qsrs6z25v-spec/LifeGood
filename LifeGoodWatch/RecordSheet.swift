import SwiftUI
import WatchKit

// MARK: - 記一筆（手錶 v2，v25.576；watch/judge.md §2.6、§2.17、§2.18、§4.1、§4.2；watch/build/v2/brief.md G3-1）
//
// 只屬於 LifeGoodWatch。RootView 的 sheet(item: model.sheet)（WatchSheet.record）開：② 錢〔＋ 記一筆〕、錶面「＋」。
// 字、規則一律拿 RecordText（View 不拼金額、不算步距）；送不送、復原一律經 RecordOutbox.shared。
//
//   ① 記帳台（RecordText.desk）：頂上「還能花 2.4萬・今天 0 筆」、2×2（一按就記的常記範本；不到 4 個用最常記的分類補）、
//      全寬「🍴 選分類、自己打數字 ›」、範本不到 4 個時最下面「同一筆記 3 次，就會出現在這裡」。整頁可捲（40mm）。
//      • 點範本格＝不換頁、不再問：手錶「叮」、格子綠框綠勾、頂上浮出「✓ 已記 早餐 65〔復原〕」＋外圈 10 秒倒數；
//        3 秒內同一格再點不算（只「喀」一下）；送出後橫幅換成 iPhone 的回話（RecordText.bannerStatus），2.5 秒後收起來
//      • 點分類格 → 直接到金額頁
//      • 沒包／「錢」關掉／包裡沒分類：寫 RecordText 的說明（沒包多〔再試一次〕）
//   ② 選分類（RecordText.categoryChoices）：2×2 最常記的 4 個（吃飯時間「飲食」排第一、綠框）＋「其他分類」一列一個
//   ③ 金額頁（AmountPicker：錶冠、最近 3 個金額、⌨︎ 自己打數字、〔記下來〕）
//   ④ 記好了（RecordDoneView）：「✓ 已記」／「午餐 180・12:10」／〔復原〕＋倒數（只在還沒送出時）／狀態行／小字／〔完成〕。
//      狀態變成最後的字之後 2.5 秒自己回 ② 錢（WatchModel.closeRecord）；〔復原〕＝刪掉手錶上這一筆、回到金額頁（金額照剛剛那筆）
// 10 秒內根本還沒送；〔完成〕、關掉這一頁、手腕放下＝馬上送（RecordOutbox.sendHoldingNow；judge §2.6）。
// 手腕放下：金額「•••」「••••」（RecordText 依 privacy.masksAmounts 組好）、能按的變暗不拿掉（.disabled(dimmed)）。
// 付款方式手錶上不選；外幣、記到旅遊那一站是 v6。

/// 記一筆裡推進去的那幾頁（NavigationStack(path:)）
private enum RecordStep: Hashable {
    /// 選分類（記帳台「選分類、自己打數字 ›」）
    case categories
    /// 金額頁（分類 key：「飲食」）
    case amount(String)
}

/// 記帳台頂上的橫幅
private enum RecordBanner: Equatable {
    /// 點一格記好的那一筆
    case recorded(WatchRecord)
    /// 手錶上寫不進檔（幾乎不會發生）；at＝按的那一下（再按一次也重新數 2.5 秒）
    case failed(Date)
}

/// 橫幅前面那個圖示
private enum RecordBannerTone {
    /// ✓ 綠：記好了、已送到、已收到
    case done
    /// ⌚︎ 琥珀：還沒送到 iPhone，先存在手錶上
    case offline
    /// ! 琥珀：沒記到
    case failed
}

/// 這個檔裡幾頁共用的樣子
private enum RecordLook {
    static let cornerRadius: CGFloat = 12
    static let tileFill = Color.white.opacity(0.14)
    /// 橫幅要蓋住底下那一行：不透明
    static let bannerFill = Color(white: 0.2)
    static let buttonFill = Color.white.opacity(0.16)
    static let moreIcon = Color(watchHex: WatchPalette.meeting)
    static let gridSpacing: CGFloat = 6
    static let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
    /// 手腕放下時能按的變暗（judge §2.17）
    static let dimmedTileOpacity: Double = 0.5
    static let dimmedOpacity: Double = 0.75
}

struct RecordSheet: View {
    @ObservedObject private var model = WatchModel.shared
    @ObservedObject private var outbox = RecordOutbox.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons

    @State private var path: [RecordStep] = []
    /// 記帳台頂上的橫幅（點範本格記好的那一筆）
    @State private var banner: RecordBanner?
    /// 記好了那一頁的那一筆（金額頁〔記下來〕）；有值時整頁換成記好了
    @State private var doneRecord: WatchRecord?
    /// 記好了那一頁按〔復原〕的那一筆：回到金額頁時金額照它，可以改了再記
    @State private var undone: WatchRecord?

    static let title = "記一筆"
    static let failedText = "沒記到，再按一次"
    /// 最後的字出現之後幾秒：橫幅收起來／記好了回 ② 錢（judge §2.6「2.5 秒後自己回 ② 錢」）
    static let closeDelayNanos: UInt64 = 2_500_000_000

    private var privacy: WatchPrivacy {
        model.privacy(dimmed: dimmed, redacted: reasons.contains(.privacy))
    }

    // ⚠️ 外層一定是 ZStack（真的容器）：Group 的修飾器會套到裡面每一個，換成記好了那一頁時
    //    NavigationStack 的 onDisappear 會先跑 → 剛記的那筆馬上被送出去，〔復原〕就沒用了。
    var body: some View {
        ZStack {
            if let r = doneRecord {
                doneView(r)
            } else {
                stack
            }
        }
        .task(id: bannerCloseKey) {
            await closeBannerLater(bannerCloseKey)
        }
        .task(id: doneCloseKey) {
            await closeDoneLater(doneCloseKey)
        }
        .onChange(of: dimmed) { _, isDimmed in
            // 手腕放下＝接受了：還在 10 秒內的馬上送（WatchModel 的 scenePhase .inactive 也會送，重複叫沒關係）
            if isDimmed {
                outbox.sendHoldingNow()
            }
        }
        .onDisappear {
            // 關掉這一頁＝接受了。彈出頁正在收起來：寫待送盒放到下一輪（同 iPhone「dismiss 後寫 store 放下一個 runloop」）
            Task { @MainActor in
                RecordOutbox.shared.sendHoldingNow()
            }
        }
    }

    // MARK: 記帳台＋推進去的頁

    private var stack: some View {
        NavigationStack(path: $path) {
            deskPage
                .navigationDestination(for: RecordStep.self) { step in
                    destination(step)
                }
        }
    }

    private var deskPage: some View {
        RecordDeskPage(desk: RecordText.desk(package: model.package, now: Date(), masked: privacy.masksAmounts),
                       highlightTemplateId: highlightTemplateId,
                       dimmed: dimmed,
                       asking: model.asking,
                       askFailed: model.askFailed,
                       onTile: { tile in tapTile(tile) },
                       onRetry: { model.requestFromPhone() })
            .overlay(alignment: .top) {
                bannerView
                    .scenePadding(.horizontal)
            }
            .navigationTitle(Self.title)
            .containerBackground(Color.black, for: .navigation)
    }

    @ViewBuilder
    private func destination(_ step: RecordStep) -> some View {
        switch step {
        case .categories:
            categoryPage
        case .amount(let key):
            amountPage(key)
        }
    }

    private var categoryPage: some View {
        RecordCategoryPage(choices: RecordText.categoryChoices(package: model.package, now: Date(),
                                                               calendar: Calendar.current),
                           dimmed: dimmed,
                           onPick: { key in path.append(.amount(key)) })
            .navigationTitle(Self.title)
            .containerBackground(Color.black, for: .navigation)
    }

    private func amountPage(_ key: String) -> some View {
        let setup = amountSetup(key)
        return AmountPicker(setup: setup) { amount in
            recordAmount(setup: setup, amount: amount)
        }
        .containerBackground(Color.black, for: .navigation)
    }

    /// 金額頁一打開的樣子；剛在記好了那一頁〔復原〕的同一個分類：金額照那一筆（可以改了再記）
    private func amountSetup(_ key: String) -> RecordAmountSetup {
        var setup = RecordText.amountSetup(categoryKey: key, package: model.package, now: Date(),
                                           calendar: Calendar.current)
        if let u = undone, u.categoryKey == key, u.amountTWD.isFinite, u.amountTWD >= 1,
           u.amountTWD <= Double(RecordText.maxAmount) {
            setup.initialAmount = Int(u.amountTWD.rounded())
        }
        return setup
    }

    // MARK: 記

    /// 點記帳台一格：範本＝馬上記（不換頁）；分類＝到金額頁
    private func tapTile(_ tile: RecordDeskTile) {
        guard tile.kind == .template, let t = tile.template else {
            path.append(.amount(tile.categoryKey))
            return
        }
        let r = RecordText.record(template: t, now: Date())
        switch outbox.add(r) {
        case .added:
            WKInterfaceDevice.current().play(.success)
            banner = .recorded(r)
        case .ignoredDoubleTap:
            // 3 秒內同一格：不記，只「喀」一下
            WKInterfaceDevice.current().play(.click)
        case .failed:
            WKInterfaceDevice.current().play(.failure)
            banner = .failed(Date())
        }
    }

    /// 金額頁〔記下來〕：沒有範本編號（iPhone 填 watch.<編號>）、名稱＝這個時段最常寫的
    private func recordAmount(setup: RecordAmountSetup, amount: Int) {
        // 〔記下來〕連按兩下：第一下已經換成記好了那一頁，第二下不再記（自己打的數字沒有範本編號，待送盒不會擋）
        guard doneRecord == nil else { return }
        let r = RecordText.record(categoryKey: setup.categoryKey, title: setup.recordTitle, amount: amount, now: Date())
        if outbox.add(r) == .added {
            WKInterfaceDevice.current().play(.success)
            undone = nil
            doneRecord = r
        } else {
            WKInterfaceDevice.current().play(.failure)
        }
    }

    // MARK: 橫幅（記帳台）

    /// 剛點的那一格（還沒有最後的字）：格子綠框綠勾（judge §2.6「格子閃綠勾」）
    private var highlightTemplateId: String? {
        guard let b = banner, case .recorded(let r) = b else { return nil }
        if let s = outbox.sendState(of: r.id), s.isFinal {
            return nil
        }
        return r.templateId
    }

    @ViewBuilder
    private var bannerView: some View {
        if let b = banner {
            makeBanner(b)
        }
    }

    private func makeBanner(_ b: RecordBanner) -> RecordBannerView {
        let seconds = RecordOutbox.undoSeconds
        switch b {
        case .failed:
            return RecordBannerView(text: Self.failedText, tone: .failed, undoStart: nil, undoSeconds: seconds,
                                    dimmed: dimmed, onUndo: {})
        case .recorded(let r):
            let state = outbox.sendState(of: r.id)
            var text = RecordText.bannerText(r, package: model.package, masked: privacy.masksAmounts)
            if let s = state, let status = RecordText.bannerStatus(s) {
                text = status
            }
            let undoStart: Date? = Self.isHolding(state) ? r.createdAt : nil
            let tone: RecordBannerTone = Self.isOffline(state) ? .offline : .done
            return RecordBannerView(text: text, tone: tone, undoStart: undoStart, undoSeconds: seconds,
                                    dimmed: dimmed, onUndo: { undoBanner(r) })
        }
    }

    private func undoBanner(_ r: WatchRecord) {
        // 已經送出去（剛好過了 10 秒）回 false：橫幅留著，等 iPhone 的回話
        guard outbox.undo(r.id) else { return }
        banner = nil
    }

    /// 橫幅收起來的計時：最後的字出現（或「沒記到」）才有值；值一變就重新數 2.5 秒。"" ＝不數
    private var bannerCloseKey: String {
        guard let b = banner else { return "" }
        switch b {
        case .failed(let at):
            return "failed-" + String(at.timeIntervalSince1970)
        case .recorded(let r):
            guard let s = outbox.sendState(of: r.id) else { return "gone-" + r.id.uuidString }
            guard s.isFinal else { return "" }
            return r.id.uuidString + "-" + RecordText.statusLine(s)
        }
    }

    private func closeBannerLater(_ key: String) async {
        guard !key.isEmpty else { return }
        try? await Task.sleep(nanoseconds: Self.closeDelayNanos)
        guard !Task.isCancelled, key == bannerCloseKey else { return }
        banner = nil
    }

    private static func isHolding(_ state: RecordSendState?) -> Bool {
        guard let state else { return false }
        return state == .holding
    }

    private static func isOffline(_ state: RecordSendState?) -> Bool {
        guard let state else { return false }
        if case .offline = state {
            return true
        }
        return false
    }

    // MARK: 記好了

    private func doneView(_ r: WatchRecord) -> some View {
        RecordDoneView(line: RecordText.doneLine(r, package: model.package, masked: privacy.masksAmounts),
                       state: outbox.sendState(of: r.id) ?? .holding,
                       undoStart: r.createdAt,
                       undoSeconds: RecordOutbox.undoSeconds,
                       dimmed: dimmed,
                       onUndo: { undoDone(r) },
                       onFinish: { finish() })
    }

    /// 〔復原〕：只刪手錶上這一筆（還沒送出去），回到金額頁（path 還在）
    private func undoDone(_ r: WatchRecord) {
        guard outbox.undo(r.id) else { return }
        undone = r
        doneRecord = nil
    }

    /// 〔完成〕：還在 10 秒內的馬上送、回 ② 錢
    private func finish() {
        outbox.sendHoldingNow()
        model.closeRecord()
    }

    /// 記好了自己收起來的計時：狀態變成最後的字才有值。"" ＝不數
    private var doneCloseKey: String {
        guard let r = doneRecord, let s = outbox.sendState(of: r.id), s.isFinal else { return "" }
        return r.id.uuidString + "-" + RecordText.statusLine(s)
    }

    private func closeDoneLater(_ key: String) async {
        guard !key.isEmpty else { return }
        try? await Task.sleep(nanoseconds: Self.closeDelayNanos)
        guard !Task.isCancelled, key == doneCloseKey else { return }
        model.closeRecord()
    }
}

// MARK: - 記帳台（第一步）

private struct RecordDeskPage: View {
    let desk: RecordDesk
    /// 剛點的那一格（WatchTemplate.id）：綠框綠勾
    let highlightTemplateId: String?
    let dimmed: Bool
    let asking: Bool
    let askFailed: Bool
    let onTile: (RecordDeskTile) -> Void
    let onRetry: () -> Void

    static let moreTitle = "選分類、自己打數字"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RecordLook.gridSpacing) {
                headerText
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
        }
    }

    /// 「還能花 2.4萬・今天 0 筆」（沒包、「錢」關掉時是「記一筆」，跟標題重複，不寫）
    @ViewBuilder
    private var headerText: some View {
        if desk.mode == .normal || desk.mode == .noDesk {
            Text(desk.header)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.dateText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(dimmed ? RecordLook.dimmedOpacity : 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if desk.mode == .normal {
            tileGrid
            moreLink
            hintText
        } else {
            messageText
            if desk.mode == .noPackage {
                WatchRetryButton(asking: asking, failed: askFailed, dimmed: dimmed, action: onRetry)
            }
        }
    }

    private var tileGrid: some View {
        LazyVGrid(columns: RecordLook.columns, spacing: RecordLook.gridSpacing) {
            ForEach(desk.tiles) { tile in
                tileButton(tile)
            }
        }
    }

    private func tileButton(_ tile: RecordDeskTile) -> some View {
        Button {
            onTile(tile)
        } label: {
            RecordTileView(tile: tile, highlighted: isHighlighted(tile), compact: WatchStyle.isCompact)
        }
        .buttonStyle(RecordPressStyle())
        .disabled(dimmed)
        .opacity(dimmed ? RecordLook.dimmedTileOpacity : 1)
    }

    private func isHighlighted(_ tile: RecordDeskTile) -> Bool {
        guard let id = highlightTemplateId, let t = tile.template else { return false }
        return t.id == id
    }

    /// 全寬「🍴 選分類、自己打數字 ›」
    private var moreLink: some View {
        NavigationLink(value: RecordStep.categories) {
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RecordLook.moreIcon)
                Text(Self.moreTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WatchStyle.small)
            }
        }
        .disabled(dimmed)
    }

    /// 範本不到 4 個：「同一筆記 3 次，就會出現在這裡」
    @ViewBuilder
    private var hintText: some View {
        if let hint = desk.hint {
            Text(hint)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(dimmed ? RecordLook.dimmedOpacity : 1)
        }
    }

    /// 沒包／「錢」關掉／包裡沒分類的說明
    @ViewBuilder
    private var messageText: some View {
        if let message = desk.message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(dimmed ? RecordLook.dimmedOpacity : 1)
        }
    }
}

/// 記帳台的一格：左上圖示、右上金額（遮住「•••」；分類格是 ›）、下面名稱一行截尾。46mm 高 58、41mm 以下 50
private struct RecordTileView: View {
    let tile: RecordDeskTile
    /// 剛點的那一格：綠框、圖示換綠勾
    let highlighted: Bool
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 0)
            Text(tile.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: compact ? 50 : 58)
        .background(RecordLook.tileFill, in: RoundedRectangle(cornerRadius: RecordLook.cornerRadius, style: .continuous))
        .overlay {
            border
        }
        .contentShape(RoundedRectangle(cornerRadius: RecordLook.cornerRadius, style: .continuous))
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 2) {
            iconView
            Spacer(minLength: 2)
            trailing
        }
    }

    private var iconView: some View {
        Image(systemName: highlighted ? "checkmark.circle.fill" : tile.icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(highlighted ? WatchStyle.green : Color(watchHex: tile.tint))
    }

    /// 範本格：金額（Title3 20 rounded 等寬）；分類格：›（點了到金額頁）
    @ViewBuilder
    private var trailing: some View {
        if let amount = tile.amountText {
            Text(amount)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchStyle.small)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: RecordLook.cornerRadius, style: .continuous)
            .strokeBorder(highlighted ? WatchStyle.green : Color.clear, lineWidth: 2)
    }
}

/// 按下去縮一點（格子、膠囊用；手錶的 .plain 沒有按下的樣子）
private struct RecordPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - 橫幅「✓ 已記 早餐 65〔復原〕」

private struct RecordBannerView: View {
    /// 「已記 早餐 65」→ 送出後「已送到 iPhone・今天 1 筆」；寫不進檔「沒記到，再按一次」
    let text: String
    let tone: RecordBannerTone
    /// 還在 10 秒內：右邊〔復原〕＋倒數環從這個時間數（record.createdAt）；nil＝沒有〔復原〕
    let undoStart: Date?
    let undoSeconds: TimeInterval
    let dimmed: Bool
    let onUndo: () -> Void

    static let undoTitle = "復原"
    static let ringSize: CGFloat = 38

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            undoButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: Self.ringSize + 10)
        .background(RecordLook.bannerFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var iconName: String {
        switch tone {
        case .done: return "checkmark.circle.fill"
        case .offline: return "applewatch"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch tone {
        case .done: return WatchStyle.green
        case .offline, .failed: return WatchStyle.amber
        }
    }

    @ViewBuilder
    private var undoButton: some View {
        if let start = undoStart {
            Button(action: onUndo) {
                Text(Self.undoTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WatchStyle.primary)
                    .frame(width: Self.ringSize, height: Self.ringSize)
                    .background(RecordLook.buttonFill, in: Circle())
                    .overlay {
                        UndoRing(start: start, seconds: undoSeconds, capsule: false)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(RecordPressStyle())
            .disabled(dimmed)
        }
    }
}

// MARK: - 10 秒倒數環

/// 從 start 起 seconds 秒，綠色外圈從滿到空（每 0.25 秒重畫）
private struct UndoRing: View {
    let start: Date
    let seconds: TimeInterval
    /// true：沿著膠囊按鈕的外框（記好了那一頁）；false：圓（記帳台橫幅）
    let capsule: Bool

    static let tick: TimeInterval = 0.25
    static let lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.periodic(from: start, by: Self.tick)) { context in
            ring(fraction(at: context.date))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 還剩幾成（1 → 0）
    private func fraction(at date: Date) -> CGFloat {
        guard seconds > 0 else { return 0 }
        let left = 1 - date.timeIntervalSince(start) / seconds
        return CGFloat(min(1, max(0, left)))
    }

    @ViewBuilder
    private func ring(_ f: CGFloat) -> some View {
        if capsule {
            Capsule()
                .trim(from: 0, to: f)
                .stroke(WatchStyle.green, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
        } else {
            Circle()
                .trim(from: 0, to: f)
                .stroke(WatchStyle.green, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - 選分類（第二步之一）

private struct RecordCategoryPage: View {
    let choices: RecordCategoryChoices
    let dimmed: Bool
    let onPick: (String) -> Void

    static let othersTitle = "其他分類"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RecordLook.gridSpacing) {
                topGrid
                othersList
                emptyText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
        }
    }

    /// 2×2：最常記的 4 個；吃飯時間的「飲食」綠框
    private var topGrid: some View {
        LazyVGrid(columns: RecordLook.columns, spacing: RecordLook.gridSpacing) {
            ForEach(choices.top) { c in
                Button {
                    onPick(c.key)
                } label: {
                    RecordCategoryTile(category: c, highlighted: c.key == choices.highlightKey,
                                       compact: WatchStyle.isCompact)
                }
                .buttonStyle(RecordPressStyle())
                .disabled(dimmed)
                .opacity(dimmed ? RecordLook.dimmedTileOpacity : 1)
            }
        }
    }

    /// 「其他分類」往下捲（股票、房地產、稅費、節稅 iPhone 早就拿掉了，留在 iPhone）
    @ViewBuilder
    private var othersList: some View {
        if !choices.others.isEmpty {
            Text(Self.othersTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.small)
                .padding(.top, 4)
            ForEach(choices.others) { c in
                Button {
                    onPick(c.key)
                } label: {
                    RecordCategoryRow(category: c)
                }
                .disabled(dimmed)
            }
        }
    }

    /// 包裡一個分類都沒有（iPhone 很久沒打開）
    @ViewBuilder
    private var emptyText: some View {
        if choices.top.isEmpty && choices.others.isEmpty {
            Text(RecordText.noDeskMessage)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 分類色圓形圖示
private struct RecordCategoryIcon: View {
    let icon: String
    let tint: UInt32
    let size: CGFloat

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(Color(watchHex: tint), in: Circle())
    }
}

/// 選分類 2×2 的一格：圓形圖示＋名稱；highlighted 綠框
private struct RecordCategoryTile: View {
    let category: WatchCategory
    let highlighted: Bool
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RecordCategoryIcon(icon: category.icon, tint: category.tint, size: compact ? 22 : 24)
            Spacer(minLength: 0)
            Text(category.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: compact ? 56 : 64)
        .background(RecordLook.tileFill, in: RoundedRectangle(cornerRadius: RecordLook.cornerRadius, style: .continuous))
        .overlay {
            border
        }
        .contentShape(RoundedRectangle(cornerRadius: RecordLook.cornerRadius, style: .continuous))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: RecordLook.cornerRadius, style: .continuous)
            .strokeBorder(highlighted ? WatchStyle.green : Color.clear, lineWidth: 2)
    }
}

/// 「其他分類」的一列
private struct RecordCategoryRow: View {
    let category: WatchCategory

    var body: some View {
        HStack(spacing: 8) {
            RecordCategoryIcon(icon: category.icon, tint: category.tint, size: 22)
            Text(category.title)
                .font(.body)
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 記好了（第三步）

private struct RecordDoneView: View {
    /// 「午餐 180・12:10」（RecordText.doneLine；遮住「午餐 ••••・12:10」）
    let line: String
    let state: RecordSendState
    /// 〔復原〕的倒數從這個時間數（record.createdAt）
    let undoStart: Date
    let undoSeconds: TimeInterval
    let dimmed: Bool
    let onUndo: () -> Void
    let onFinish: () -> Void

    static let doneTitle = "已記"
    static let undoTitle = "復原"
    static let finishTitle = "完成"
    static let buttonHeight: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                titleRow
                lineText
                undoButton
                statusRow
                noteText
                finishButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
        }
    }

    /// 「✓ 已記」（綠，Headline）
    private var titleRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
            Text(Self.doneTitle)
                .font(.headline)
        }
        .foregroundStyle(WatchStyle.green)
        .opacity(dimmed ? RecordLook.dimmedOpacity : 1)
    }

    /// Title3 20 semibold
    private var lineText: some View {
        Text(line)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(WatchStyle.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(dimmed ? RecordLook.dimmedOpacity : 1)
    }

    /// 〔復原〕＋外圈 10 秒倒數：只在還沒送出時（過了按鈕消失）
    @ViewBuilder
    private var undoButton: some View {
        if state == .holding {
            Button(action: onUndo) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text(Self.undoTitle)
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                .background(RecordLook.buttonFill, in: Capsule())
                .overlay {
                    UndoRing(start: undoStart, seconds: undoSeconds, capsule: true)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(RecordPressStyle())
            .disabled(dimmed)
        }
    }

    /// 狀態行（RecordText.statusLine）：前面 iPhone／手錶圖示；先存在手錶上用琥珀
    private var statusRow: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: statusIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 16)
            Text(RecordText.statusLine(state))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(dimmed ? RecordLook.dimmedOpacity : 1)
    }

    private var statusIcon: String {
        switch state {
        case .holding: return "clock"
        case .waiting, .imported, .queued: return "iphone"
        case .offline: return "applewatch"
        }
    }

    private var statusColor: Color {
        switch state {
        case .holding, .waiting: return WatchStyle.small
        case .imported: return WatchStyle.green
        case .queued: return WatchStyle.countdown
        case .offline: return WatchStyle.amber
        }
    }

    /// 「錶面的「已花」幾分鐘內跟上」／「iPhone 在旁邊時自己補送」（Footnote A3B2D9）
    @ViewBuilder
    private var noteText: some View {
        if let note = RecordText.statusNote(state) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(dimmed ? RecordLook.dimmedOpacity : 1)
        }
    }

    /// 〔完成〕＝接受了：還在 10 秒內的馬上送、回 ② 錢
    private var finishButton: some View {
        Button(action: onFinish) {
            Text(Self.finishTitle)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .disabled(dimmed)
        .padding(.top, 2)
    }
}
