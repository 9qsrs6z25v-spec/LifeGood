import SwiftUI
import Charts
import UIKit
import CoreLocation

// [v25.534] 房屋卡片各區的畫面。全部是「吃 HouseCardData＋closure」的純畫面：
// - 字與數字都在 HouseCardData.build 算好，這裡只排版、上色；點了要做什麼一律交給 HouseCardActions
//   （外殼 RealEstateDetailView 實作，付費也在那裡擋，這裡不碰 store）。
// - 每一區自己判斷「整區不出現」（body 什麼都不畫），外殼照順序放進 VStack 就好。
// - 展開、再看 N 筆、選中的階梯這些只影響顯示的狀態放各區自己的 @State；換房時外殼用 .id(estateId) 整個重建，自然歸零。
// - 卡片上不做左滑、不做「複製」：點一下＝編輯，長按＝選單（編輯、刪除），VoiceOver 用 accessibilityActions。
// - 分類色、長條色：淺色照樣稿，深色另訂一組（對卡片底至少 3:1），都收在 HCColors。
// - body 一律拆成小 func／小 struct：v25.531 曾因 body 型別檢查逾時壞過一次。

// MARK: - 共用介面（外殼照這裡的名字呼叫，不要改）

/// 白卡外框、格子底色：股票卡片那一套本來就是通用的，換個名字給房子用（不動 StockCardViews.swift）
typealias FinanceCardChrome = StockCardChrome      // 白卡外框（StockCardViews.swift，不改原檔）
typealias FinanceCardTile = StockCardTile          // 格子底色等

/// 卡片內可以捲到的位置（ScrollViewReader 的 id）
enum HouseAnchor: String, Hashable { case top, checks, mortgage, living, rental, ledger, info, floors, photos, utilities, elevator }

/// 卡片上每一個「點了要做事」的地方。畫面只呼叫，外殼負責付費檢查、確認框、打開編輯頁。
struct HouseCardActions {
    var scrollTo: (HouseAnchor) -> Void = { _ in }
    var setLedgerFilter: (HouseLedgerFilter) -> Void = { _ in }
    var edit: (HouseEditFocus) -> Void = { _ in }                 // 打開編輯頁並捲到那一欄
    var fixCheck: (HouseCheck) -> Void = { _ in }
    var openSegment: (HouseFacts.Segment) -> Void = { _ in }
    var deleteSegment: (HouseFacts.Segment) -> Void = { _ in }
    var addSegment: () -> Void = {}
    var addLedger: (HouseLedgerAddKind) -> Void = { _ in }
    var openLedger: (HouseLedgerEvent) -> Void = { _ in }
    var deleteLedger: (HouseLedgerEvent) -> Void = { _ in }
    var openExpense: (UUID) -> Void = { _ in }                    // 保險列、家電
    var openUtility: (UtilityPayment?) -> Void = { _ in }          // nil＝新增
    var openElevator: (ElevatorMaintenance?) -> Void = { _ in }    // nil＝新增
    var showPhotos: (CutePhotoDraft) -> Void = { _ in }
    /// [v25.534] 「＋ 記一筆」選單要在打開前就擋付費：沒付費時外殼給 false，選單換成普通按鈕、按了呼叫 askPremium。
    /// 預設 true（匯出、預覽不用管）；外殼的 addLedger 本身也還會再擋一次
    var canEdit: Bool = true
    var askPremium: () -> Void = {}
}

fileprivate extension HouseCardActions {
    /// 格子、圖例上的 HouseTap 交給對應的動作（帳本篩選要先切再捲過去，使用者才看得到切了什麼）
    func handle(_ tap: HouseTap) {
        switch tap {
        case .none:
            break
        case .scrollToMortgage:
            scrollTo(.mortgage)
        case .ledgerFilter(let f):
            setLedgerFilter(f)
            scrollTo(.ledger)
        case .edit(let focus):
            edit(focus)
        }
    }
}

// MARK: - 換房列

/// 換房列的一顆膠囊
struct FinanceSwitcherItem: Identifiable, Equatable {
    let id: UUID
    let title: String          // 已截短（MoneyBoardText.short(_, max: 6)）
    let trailing: String       // 「▲30%」「賣 ▲18%」；可空字串
    let tone: MoneyTone
}

/// 釘在最上面的一排：同一組（持有中／已售出）的每一間，點了就換。樣子照 StockSwitcherStrip，選中的自動捲到中間。
struct FinanceSwitcherStrip: View {
    let items: [FinanceSwitcherItem]
    let selected: UUID
    let onSelect: (UUID) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.id) { item in
                        Button {
                            onSelect(item.id)
                        } label: {
                            pill(item, on: item.id == selected, pal: pal)
                        }
                        .buttonStyle(MoneyPressStyle())
                        .id(item.id)
                        .accessibilityAddTraits(item.id == selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, id in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func pill(_ item: FinanceSwitcherItem, on: Bool, pal: TripBoardPalette) -> some View {
        let fill = on ? HCColors.pick(0x1D2B55, 0x3B4F8F, pal) : pal.cellFill
        let ink = on ? Color.white : pal.ink
        return HStack(spacing: 6) {
            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
            if !item.trailing.isEmpty {
                Text(item.trailing)
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(trailingColor(item.tone, on: on, pal: pal))
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(fill, in: Capsule())
        .overlay(Capsule().stroke(on ? Color.clear : pal.cellStroke, lineWidth: 0.75))
        .shadow(color: on ? Color.clear : pal.cellShadow, radius: 3, x: 0, y: 1)
    }

    /// 選中的膠囊是深藍底：漲跌字改用調亮的 FF8A8A／6EE7A8，不然紅綠壓在深藍上看不清楚
    private func trailingColor(_ tone: MoneyTone, on: Bool, pal: TripBoardPalette) -> Color {
        guard on else { return tone.color(pal) }
        switch tone {
        case .up: return Color(tb: 0xFF8A8A)
        case .down, .good: return Color(tb: 0x6EE7A8)
        default: return Color.white.opacity(0.85)
        }
    }
}

// MARK: - 看板

/// 看板（天空＋這一間的剖面）＋下面的房貸進度格、膠囊。
/// 外框照 MoneyBoardCard（同一個圓角設定、同一個 MoneyBoardChrome），但頭部要整個換成 data 的摘要給 VoiceOver 唸，
/// MoneyBoardCard 只收 MoneyBoardHeader 型別、外面掛不上 accessibility 修飾，所以這裡自己組同樣的外框。
struct HouseCardBoard: View {
    let data: HouseCardData
    var onTapProgress: (() -> Void)? = nil   // nil：進度格不能點（匯出用）

    @Environment(\.colorScheme) private var scheme
    /// 只讀「圓角」（同 MoneyBoardCard：看板不吃英雄卡的漸層與 KPI 樣式）
    @ObservedObject private var heroStyle = HeroStyleStore.shared

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let corner = CGFloat(heroStyle.value(.corner, .realEstate))
        VStack(alignment: .leading, spacing: 0) {
            header(pal)
            if hasBelow {
                below(pal)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
        }
        .modifier(MoneyBoardChrome(pal: pal, corner: corner))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var hasBelow: Bool {
        data.progress != nil || data.paidOffLine != nil || !data.chips.isEmpty
    }

    private func header(_ pal: TripBoardPalette) -> some View {
        let b = data.board
        let tint: Color? = b.capsuleTone == MoneyTone.neutral ? nil : b.capsuleTone.color(pal)
        let bigTone: MoneyTone? = b.bigTone == MoneyTone.neutral ? nil : b.bigTone
        let line: Text? = b.line.runs.isEmpty ? nil : HCText.line(b.line, pal: pal)
        return MoneyBoardHeader(
            date: b.date,
            dateIcon: b.dateIcon,
            capsule: b.capsule,
            capsuleIcon: b.capsuleIcon,
            capsuleTint: tint,
            label: b.label,
            big: b.big,
            bigTone: bigTone,
            line: line,
            greeting: b.greeting,
            scene: .house(FinHouseScene(model: data.scene)),
            band: 132,
            seed: data.seed)
            // 整個頭部一個 VoiceOver 元素，唸 data 組好的那一句（風景本來就 accessibilityHidden）
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(b.accessibilityText)
    }

    private func below(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let p = data.progress {
                progress(p, pal: pal)
            }
            if let line = data.paidOffLine {
                paidOff(line, pal: pal)
            }
            if !data.chips.isEmpty {
                MoneyBoardChips(chips: data.chips, pal: pal)
            }
        }
    }

    /// 房貸進度格：看板上唯一能點的地方（捲到房貸區）
    @ViewBuilder
    private func progress(_ p: HouseProgressData, pal: TripBoardPalette) -> some View {
        if let onTapProgress {
            Button(action: onTapProgress) {
                HCProgressCell(p: p, pal: pal, tappable: true)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下捲到房貸")
        } else {
            HCProgressCell(p: p, pal: pal, tappable: false)
        }
    }

    /// 全部繳完：進度格換成一行
    private func paidOff(_ line: String, pal: TripBoardPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MoneyTone.good.color(pal))
            Text(line)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.ink)
            Spacer(minLength: 0)
        }
        .padding(12)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .combine)
    }
}

/// 房貸進度：左端第一期、右端繳完；過去的那段紫色、未來灰；段和段的交界細刻度；今天一顆圓點。
/// 骨架照 StockPricePosition（12pt 留白＋TripBoardCellChrome、44pt 高的軌道、18pt 小牌子），牌子太近時推開。
private struct HCProgressCell: View {
    let p: HouseProgressData
    let pal: TripBoardPalette
    var tappable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow
            GeometryReader { geo in
                track(width: geo.size.width)
            }
            .frame(height: 44)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.left)
                Spacer(minLength: 4)
                Text(p.right)
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(pal.label)
            if !p.note.isEmpty {
                Text(p.note)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(pal.inkDate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.title)
        .accessibilityValue(p.accessibilityText)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(p.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.ink)
            Spacer(minLength: 8)
            Text(p.range)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(pal.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(pal.label)
            }
        }
    }

    private func track(width w: CGFloat) -> some View {
        let inset: CGFloat = 9
        let usable = max(1, w - inset * 2)
        let f = CGFloat(min(1, max(0, p.fraction)))
        let xDot = inset + usable * f
        let xEnd = inset + usable
        let trackY: CGFloat = 33
        let deep = MoneyBoardSky.ridgeCost(dark: pal.dark)
        let dotColor = p.notStarted ? pal.label : deep
        let centers = pillCenters(width: w, dot: xDot, dotText: p.dotPill, end: xEnd, endText: p.endPill)
        let fillStart = inset - 4
        return ZStack {
            Capsule()
                .fill(pal.progressTrack)
                .frame(width: usable + 8, height: 6)
                .position(x: w / 2, y: trackY)
            if f > 0 {
                Capsule()
                    .fill(LinearGradient(colors: [deep.opacity(0.4), deep], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, xDot - fillStart), height: 6)
                    .position(x: (fillStart + xDot) / 2, y: trackY)
            }
            ForEach(p.ticks, id: \.id) { t in
                Capsule()
                    .fill(HCColors.tick(pal))
                    .frame(width: 1.5, height: 12)
                    .position(x: inset + usable * CGFloat(t.fraction), y: trackY)
            }
            Circle()
                .fill(dotColor)
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .frame(width: 15, height: 15)
                .shadow(color: dotColor.opacity(0.35), radius: 3, x: 0, y: 1)
                .position(x: xDot, y: trackY)
            pill(p.dotPill, fill: p.notStarted ? HCColors.pick(0x7A86A8, 0x5A6585, pal) : HCColors.pick(0x1D2B55, 0x3B4F8F, pal))
                .position(x: centers.dot, y: 9)
            pill(p.endPill, fill: HCColors.pick(0x177A44, 0x2E9E66, pal))
                .position(x: centers.end, y: 9)
        }
    }

    private func pill(_ s: String, fill: Color) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(fill, in: Capsule())
    }

    /// 牌子的寬度（估的：中文一個字約 10.5pt、數字約 6pt，加左右留白；同 StockPricePosition）
    private func pillWidth(_ s: String) -> CGFloat {
        s.unicodeScalars.reduce(CGFloat(14)) { $0 + ($1.isASCII ? 6.2 : 10.5) }
    }

    /// 「今天」和「繳完」各自先夾在格子裡（「繳完」掛在最右端，一定會被往左推）；
    /// 兩塊靠太近才往兩邊推開，推出邊緣就整組挪回來。不能一開始就整組挪：兩塊離很遠時，
    /// 「繳完」貼右邊被推回來，會連「今天」一起推出左邊。
    private func pillCenters(width w: CGFloat, dot: CGFloat, dotText: String, end: CGFloat,
                             endText: String) -> (dot: CGFloat, end: CGFloat) {
        let wa = pillWidth(dotText)
        let wb = pillWidth(endText)
        var a = min(max(dot, wa / 2), w - wa / 2)
        var b = min(max(end, wb / 2), w - wb / 2)
        let need = (wa + wb) / 2 + 6
        if b - a < need {
            let mid = (a + b) / 2
            a = mid - need / 2
            b = mid + need / 2
            if b + wb / 2 > w {
                let shift = b + wb / 2 - w
                a -= shift
                b -= shift
            }
            if a - wa / 2 < 0 {
                let shift = wa / 2 - a
                a += shift
                b += shift
            }
        }
        return (dot: a, end: b)
    }
}

// MARK: - 要確認

/// 會讓數字算錯的資料問題：一件一列，右邊一顆按鈕（付費、確認都在外殼的 fixCheck 裡）。一件都沒有時整區不出現。
struct HouseChecksSection: View {
    let data: HouseCardData
    let actions: HouseCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !data.checks.isEmpty {
            content(TripBoardPalette(scheme))
        }
    }

    private func content(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HCHeader(title: "要確認", trailing: data.checksTrailing)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(data.checks.enumerated()), id: \.element.id) { i, c in
                    if i > 0 {
                        Divider().padding(.leading, 44)
                    }
                    row(c, pal: pal)
                }
            }
            .modifier(FinanceCardChrome())
        }
    }

    private func row(_ c: HouseCheck, pal: TripBoardPalette) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: c.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(MoneyTone.warn.color(pal))
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(c.message)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                actions.fixCheck(c)
            } label: {
                Text(c.button)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(pal.hint)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 11)
                    .frame(minHeight: 30)
                    .background(pal.hint.opacity(0.12), in: Capsule())
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel(c.accessibilityLabel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - 房貸

/// 房貸區：格子、兩句話、月付階梯圖、段落清單、「＋ 加一段」。完全沒有房貸段時整區不出現。
/// forExport：分享圖用，拿掉所有按鈕、提示、點選。
struct HouseMortgageSection: View {
    let data: HouseCardData
    let actions: HouseCardActions
    var forExport: Bool = false

    @Environment(\.colorScheme) private var scheme
    /// 階梯圖手指正在按的日期（chartXSelection；放開就變回 nil）
    @State private var rawSelection: Date? = nil
    /// 最後點過的那一段：圖下說明換成那段的字（放開後也留著）
    @State private var pickedStepId: UUID? = nil
    /// 對應的段落列亮一下
    @State private var flashId: UUID? = nil
    @State private var flashToken = 0

    var body: some View {
        if let m = data.mortgage {
            section(m, pal: TripBoardPalette(scheme))
                .onChange(of: rawSelection) { _, date in
                    pick(date, in: m.steps)
                }
        }
    }

    private func section(_ m: HouseMortgageData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HCHeader(title: "房貸", trailing: m.trailing)
            card(m, pal: pal)
        }
    }

    private func card(_ m: HouseMortgageData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let note = m.soldNote {
                soldNote(note, pal: pal)
            }
            if !m.tiles.isEmpty {
                HCTileGrid(tiles: m.tiles, pal: pal, onTap: tileTap)
            }
            if let hint = m.principalHint, !forExport {
                hintButton(hint, pal: pal)
            }
            sentences(m, pal: pal)
            if showChartHeader(m) {
                chartHeader(m, pal: pal)
            }
            if m.showChart {
                chartBlock(m, pal: pal)
            }
            rowsBlock(m, pal: pal)
            if let foot = m.footnote {
                Text(foot)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    /// 「借款本金」格可以點（打開編輯頁那一欄）；匯出時不能點
    private var tileTap: ((HouseTap) -> Void)? {
        if forExport { return nil }
        let a = actions
        return { tap in a.handle(tap) }
    }

    private func soldNote(_ text: String, pal: TripBoardPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(pal.label)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func hintButton(_ text: String, pal: TripBoardPalette) -> some View {
        Button {
            actions.edit(.loanPrincipal)
        } label: {
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(pal.hint)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
    }

    @ViewBuilder
    private func sentences(_ m: HouseMortgageData, pal: TripBoardPalette) -> some View {
        if m.totalLine != nil || m.interestLine != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let line = m.totalLine {
                    HCSentence(line: line, pal: pal)
                }
                if let line = m.interestLine {
                    HCSentence(line: line, pal: pal)
                }
            }
        }
    }

    private func showChartHeader(_ m: HouseMortgageData) -> Bool {
        m.showChart || (!data.isSold && !forExport)
    }

    /// 「每個月要繳多少」＋右邊綠色「＋ 加一段」（賣掉的房子、匯出時不放按鈕）
    private func chartHeader(_ m: HouseMortgageData, pal: TripBoardPalette) -> some View {
        let title = m.showChart ? "每個月要繳多少" : "段落"
        let canAdd = !data.isSold && !forExport
        return HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(pal.label)
            Spacer(minLength: 8)
            if canAdd {
                Button {
                    actions.addSegment()
                } label: {
                    HCGreenPill(title: "加一段")
                }
                .buttonStyle(MoneyPressStyle())
                .accessibilityLabel("加一段房貸")
            }
        }
    }

    private func chartBlock(_ m: HouseMortgageData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .center, spacing: 6) {
            HCStairsChart(m: m, pal: pal, interactive: !forExport, selection: $rawSelection)
            Text(caption(m))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private func caption(_ m: HouseMortgageData) -> String {
        guard let id = pickedStepId, let s = m.steps.first(where: { $0.id == id }) else { return m.chartCaption }
        return s.caption
    }

    private func rowsBlock(_ m: HouseMortgageData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(m.rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 {
                    Divider().padding(.leading, 48)
                }
                rowItem(r, pal: pal)
            }
        }
    }

    /// 點一下＝編輯這段；長按＝編輯／刪除（刪除的確認在外殼）。不做左滑、不做複製。
    @ViewBuilder
    private func rowItem(_ r: HouseMortgageData.Row, pal: TripBoardPalette) -> some View {
        if forExport {
            HCSegmentRow(row: r, pal: pal, lit: false)
        } else {
            Button {
                actions.openSegment(r.segment)
            } label: {
                HCSegmentRow(row: r, pal: pal, lit: flashId == r.id)
            }
            .buttonStyle(MoneyPressStyle())
            .contextMenu {
                Button {
                    actions.openSegment(r.segment)
                } label: {
                    Label("編輯這段", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    actions.deleteSegment(r.segment)
                } label: {
                    Label("刪除這段", systemImage: "trash")
                }
            }
            .accessibilityLabel(r.accessibilityText)
            .accessibilityAction(named: "編輯") { actions.openSegment(r.segment) }
            .accessibilityAction(named: "刪除") { actions.deleteSegment(r.segment) }
        }
    }

    // MARK: 點階梯圖

    private func pick(_ date: Date?, in steps: [HouseMortgageData.Step]) {
        guard let date, let step = Self.step(at: date, in: steps) else { return }
        if pickedStepId != step.id {
            pickedStepId = step.id
        }
        flash(step.id)
    }

    /// 段落列亮一下就退掉：手指一直在圖上拖時會一直延長，放開後約一秒退掉
    private func flash(_ id: UUID) {
        flashToken += 1
        let token = flashToken
        if flashId != id {
            withAnimation(.easeOut(duration: 0.15)) { flashId = id }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard flashToken == token else { return }
            withAnimation(.easeOut(duration: 0.4)) { flashId = nil }
        }
    }

    /// 按到的日期落在哪一段：同時在繳（疊起來）取最上面那塊；落在兩段中間的空檔取最近的一段
    private static func step(at date: Date, in steps: [HouseMortgageData.Step]) -> HouseMortgageData.Step? {
        let containing = steps.filter { $0.start <= date && date <= $0.end }
        if let top = containing.max(by: { $0.yEnd < $1.yEnd }) { return top }
        func distance(_ s: HouseMortgageData.Step) -> TimeInterval {
            if date < s.start { return s.start.timeIntervalSince(date) }
            return date.timeIntervalSince(s.end)
        }
        return steps.min(by: { distance($0) < distance($1) })
    }
}

/// 月付階梯圖（Swift Charts，高 140）：每段一塊，寬＝第一期到最後一期、高＝每月金額；已繳實心、未繳淡色；今天一條虛線
private struct HCStairsChart: View {
    let m: HouseMortgageData
    let pal: TripBoardPalette
    let interactive: Bool
    @Binding var selection: Date?

    var body: some View {
        if interactive {
            chart
                .chartXSelection(value: $selection)
        } else {
            chart
        }
    }

    private var top: Double { max(m.chartMax, 1) * 1.45 }

    private var domain: ClosedRange<Date> {
        let end = m.chartEnd > m.chartStart ? m.chartEnd : m.chartStart.addingTimeInterval(86_400 * 31)
        return m.chartStart...end
    }

    private var chart: some View {
        Chart {
            ForEach(m.steps, id: \.id) { s in
                stepMarks(s)
            }
            if let today = m.today {
                todayMark(today)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...top)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(axisLabel(d))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("每個月要繳多少")
        .accessibilityValue(m.steps.map(\.caption).joined(separator: "；"))
    }

    @ChartContentBuilder
    private func stepMarks(_ s: HouseMortgageData.Step) -> some ChartContent {
        RectangleMark(xStart: .value("開始", s.start), xEnd: .value("結束", s.end),
                      yStart: .value("底", s.yStart), yEnd: .value("頂", s.yEnd))
            .foregroundStyle(HCColors.stairLeft(pal))
            .cornerRadius(2)
            .annotation(position: .top, spacing: 2) {
                annotationLabel(s.annotation)
            }
        if let paid = s.paidUntil {
            RectangleMark(xStart: .value("開始", s.start), xEnd: .value("已繳到", paid),
                          yStart: .value("底", s.yStart), yEnd: .value("頂", s.yEnd))
                .foregroundStyle(HCColors.stairPaid(pal))
                .cornerRadius(2)
        }
    }

    @ChartContentBuilder
    private func todayMark(_ today: Date) -> some ChartContent {
        RuleMark(x: .value("今天", today), yStart: .value("底", 0.0), yEnd: .value("頂", top * 0.82))
            .foregroundStyle(HCColors.pick(0x1D2B55, 0xC9D3F0, pal))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                todayPill
            }
    }

    private func annotationLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(HCColors.pick(0x4A3AA8, 0xD9CCFF, pal))
            .lineLimit(1)
            .fixedSize()
    }

    private var todayPill: some View {
        Text("今天")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .frame(height: 15)
            .background(HCColors.pick(0x1D2B55, 0x3B4F8F, pal), in: Capsule())
    }

    /// 刻度：最左邊寫第一期的年月（「2026/4」），其他寫年份；離左端太近的年份不寫，免得疊在一起
    private var axisValues: [Date] {
        let start = m.chartStart
        let span = max(1, domain.upperBound.timeIntervalSince(start))
        var out: [Date] = [start]
        for d in m.axisDates where d > start && d <= domain.upperBound {
            if d.timeIntervalSince(start) / span < 0.12 { continue }
            out.append(d)
        }
        return out
    }

    private func axisLabel(_ d: Date) -> String {
        abs(d.timeIntervalSince(m.chartStart)) < 1 ? HouseCardFormat.ym(d) : String(HouseCardFormat.year(d))
    }
}

/// 段落清單的一列：28pt 圓、標題、「2026/4 – 2031/3・60 期」、右邊每期金額、最下一行看狀態
private struct HCSegmentRow: View {
    let row: HouseMortgageData.Row
    let pal: TripBoardPalette
    let lit: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HCSegmentBadge(status: row.status, text: row.badge, pal: pal)
            details
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(highlight, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(Color.primary)
        .contentShape(Rectangle())
    }

    private var highlight: Color {
        lit ? HCColors.stairPaid(pal).opacity(0.14) : Color.clear
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.title)
                    .font(.subheadline.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Text(row.amount)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Text(row.range)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if row.isUnlinked || row.termMissing {
                tags
            }
            status
        }
    }

    private var tags: some View {
        HStack(spacing: 6) {
            if row.isUnlinked {
                HCMiniTag(text: "沒連到記帳", color: pal.label)
            }
            if row.termMissing {
                HCMiniTag(text: "期數沒填", color: MoneyTone.warn.color(pal))
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if row.status == .paying {
            HStack(spacing: 8) {
                Text(row.statusText)
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(HCColors.payingBlue)
                if let f = row.progress {
                    HCThinBar(fraction: f, color: HCColors.payingBlue, track: pal.progressTrack)
                }
                if let next = row.nextText {
                    Text(next)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            Text(row.statusText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(row.status == .done ? MoneyTone.good.color(pal) : pal.label)
        }
    }
}

/// 段落列左邊的圓：繳款中藍底白字、還沒開始灰框、已繳完綠勾、已停止（或賣出時結清）灰底
private struct HCSegmentBadge: View {
    let status: HouseMortgageData.Status
    let text: String
    let pal: TripBoardPalette

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().stroke(stroke, lineWidth: 1.5)
            label
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var label: some View {
        if status == .done {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.white)
        } else {
            Text(text)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var fill: Color {
        switch status {
        case .paying: return HCColors.payingBlue
        case .done: return Color(tb: 0x1F9D57)
        case .stopped, .soldSettled: return HCColors.pick(0x7A86A8, 0x6D7EAB, pal)
        case .notStarted: return Color.clear
        }
    }

    private var stroke: Color {
        status == .notStarted ? HCColors.pick(0xC9D1E2, 0x5A6585, pal) : Color.clear
    }

    private var ink: Color {
        status == .notStarted ? pal.label : Color.white
    }
}

// MARK: - 每個月住這裡

/// 住在這裡每個月到底花多少：分段長條＋可以點的圖例（利息／還本金→房貸區；其他→帳本「持有」）。
/// HouseCardData 已經把「整區不出現」（已售出、三樣都是 0）算成 living == nil。
struct HouseLivingSection: View {
    let data: HouseCardData
    let actions: HouseCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let l = data.living {
            content(l, pal: TripBoardPalette(scheme))
        }
    }

    private func content(_ l: HouseLivingData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HCHeader(title: "每個月住這裡", trailing: l.trailing)
            card(l, pal: pal)
        }
    }

    private func card(_ l: HouseLivingData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            headline(l)
            HCStackBar(parts: bars(l, pal: pal), height: 12, pal: pal)
            legend(l, pal: pal)
            if let s = l.summary {
                HCSentence(line: s, pal: pal)
            }
            if let hint = l.splitHint {
                splitButton(hint, pal: pal)
            }
            if let first = l.firstYearHint {
                firstYearNote(first, pal: pal)
            }
            Text(l.footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    /// 「平均每月」小字＋「約 NT$4.5萬」大字（字是 data 組好的那一句，只是拆成兩種大小）
    private func headline(_ l: HouseLivingData) -> some View {
        let prefix = "平均每月"
        let split = l.headline.hasPrefix(prefix)
        let big = split ? String(l.headline.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) : l.headline
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if split {
                Text(prefix)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(big)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private func bars(_ l: HouseLivingData, pal: TripBoardPalette) -> [HCBarPart] {
        l.parts.map { p in HCBarPart(id: p.id, value: p.value, color: HCColors.living(p.kind, pal: pal)) }
    }

    private func legend(_ l: HouseLivingData, pal: TripBoardPalette) -> some View {
        ChipFlowLayout(spacing: 12) {
            ForEach(l.parts, id: \.id) { p in
                legendButton(p, pal: pal)
            }
        }
    }

    private func legendButton(_ p: HouseLivingData.Part, pal: TripBoardPalette) -> some View {
        Button {
            actions.handle(p.tap)
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(HCColors.living(p.kind, pal: pal))
                    .frame(width: 8, height: 8)
                Text(p.label)
                    .foregroundStyle(pal.label)
                Text(p.valueText)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .foregroundStyle(pal.ink)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel(p.legend)
        .accessibilityHint(HCText.hint(p.tap))
    }

    private func splitButton(_ text: String, pal: TripBoardPalette) -> some View {
        Button {
            actions.edit(.loanPrincipal)
        } label: {
            HStack(spacing: 4) {
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(pal.hint)
            .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
    }

    private func firstYearNote(_ text: String, pal: TripBoardPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(MoneyTone.warn.color(pal))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 出租

/// 只在出租時出現：三格、金色「租金付掉房貸」進度條、每月實際多收還是倒貼。沒有可以點的地方。
struct HouseRentalSection: View {
    let data: HouseCardData

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let r = data.rental {
            content(r, pal: TripBoardPalette(scheme))
        }
    }

    private func content(_ r: HouseRentalData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HCHeader(title: "出租", trailing: r.trailing)
            VStack(alignment: .leading, spacing: 12) {
                if !r.tiles.isEmpty {
                    HCTileGrid(tiles: r.tiles, pal: pal)
                }
                if let f = r.coverFraction {
                    cover(f, text: r.coverText, pal: pal)
                }
                if !r.line.runs.isEmpty {
                    HCSentence(line: r.line, pal: pal)
                }
            }
            .padding(14)
            .modifier(FinanceCardChrome())
        }
    }

    /// 同股利卡「拿回成本」的金色條（最多畫到 100%）
    private func cover(_ fraction: Double, text: String?, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let text {
                Text(text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MoneyTone.warn.color(pal))
            }
            HCGoldBar(fraction: fraction)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 我的帳本

/// 帳本卡 1（總表）：3×2 格、到今天總共付了、四段長條＋圖例、兩句話。不含區塊標題（匯出時單獨放一張）。
struct HouseLedgerSummaryCard: View {
    let data: HouseCardData
    let actions: HouseCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let l = data.ledger
        let a = actions
        VStack(alignment: .leading, spacing: 14) {
            HCTileGrid(tiles: l.tiles, pal: pal, onTap: { tap in a.handle(tap) })
            if !l.isEmpty {
                totals(l, pal: pal)
            }
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    private func totals(_ l: HouseLedger, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(l.totalLabel)
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 8)
                Text(l.totalText)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            HCStackBar(parts: bars(l, pal: pal), height: 10, pal: pal)
            legend(l, pal: pal)
            if let line = l.mineLine {
                HCSentence(line: line, pal: pal)
            }
            if let line = l.sellLine {
                HCSentence(line: line, pal: pal)
            }
        }
    }

    private func bars(_ l: HouseLedger, pal: TripBoardPalette) -> [HCBarPart] {
        l.parts.map { p in HCBarPart(id: p.bucket.legendTitle, value: p.value, color: HCColors.bucket(p.bucket, pal: pal)) }
    }

    /// 值 0 的段不寫圖例（長條本來就不畫它）
    private func legend(_ l: HouseLedger, pal: TripBoardPalette) -> some View {
        let shown = l.parts.filter { $0.value > 0 }
        return ChipFlowLayout(spacing: 12) {
            ForEach(shown, id: \.id) { p in
                MoneyLegendItem(mark: .swatch, color: HCColors.bucket(p.bucket, pal: pal), text: p.legend, pal: pal)
            }
        }
    }
}

/// 帳本裡一列要怎麼畫（年份組頭、一筆紀錄、「再看 N 筆」）；攤平成一串才放得進 LazyVStack
private enum HCLedgerLine: Identifiable {
    case year(HouseLedgerYear, expanded: Bool)
    case row(HouseLedgerEvent, divider: Bool)
    case more(year: Int, hidden: Int)

    var id: String {
        switch self {
        case .year(let y, _): return "y-\(y.year)"
        case .row(let e, _): return "r-" + e.id
        case .more(let year, _): return "m-\(year)"
        }
    }
}

/// 我的帳本：區塊標題＋卡 1（總表）＋卡 2（紀錄：「＋ 記一筆」、篩選膠囊、依年份分組的時間軸）
struct HouseLedgerSection: View {
    let data: HouseCardData
    @Binding var filter: HouseLedgerFilter
    let actions: HouseCardActions

    @Environment(\.colorScheme) private var scheme
    /// 使用者點過的年份（預設今年展開、往年收起；點一下反過來）
    @State private var toggledYears: Set<Int> = []
    /// 按過「再看 N 筆」的年份
    @State private var moreYears: Set<Int> = []

    /// 每組先列幾筆
    private static let preview = 8

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            HCHeader(title: "我的帳本", trailing: data.ledger.headerTrailing)
            HouseLedgerSummaryCard(data: data, actions: actions)
            records(pal)
        }
    }

    // MARK: 卡 2

    private func records(_ pal: TripBoardPalette) -> some View {
        let ledger = data.ledger
        let lines = flatten(ledger.years(for: filter))
        return VStack(alignment: .leading, spacing: 0) {
            recordsTop(ledger, pal: pal)
            if ledger.isEmpty {
                emptyText(ledger.emptyHint ?? "")
            } else {
                filterRow(pal)
                if lines.isEmpty {
                    emptyText("這一類還沒有紀錄")
                }
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines, id: \.id) { line in
                    lineView(line, pal: pal)
                }
            }
            Color.clear.frame(height: 8)
        }
        .modifier(FinanceCardChrome())
    }

    /// 「紀錄・79 筆」＋綠色「＋ 記一筆」選單
    private func recordsTop(_ ledger: HouseLedger, pal: TripBoardPalette) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(ledger.recordsTitle)
                .font(.subheadline.weight(.bold))
            Spacer(minLength: 8)
            addMenu
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    /// [v25.534] 付費在選單打開前就擋：沒付費時不是選單，是一顆按了只跳付費說明的按鈕
    @ViewBuilder
    private var addMenu: some View {
        if actions.canEdit {
            Menu {
                ForEach(HouseLedgerAddKind.allCases, id: \.id) { kind in
                    Button {
                        actions.addLedger(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.icon)
                    }
                }
            } label: {
                HCGreenPill(title: "記一筆")
            }
            .accessibilityLabel("記一筆")
        } else {
            Button {
                actions.askPremium()
            } label: {
                HCGreenPill(title: "記一筆")
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel("記一筆")
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }

    // MARK: 篩選

    private func filterRow(_ pal: TripBoardPalette) -> some View {
        let current = filter
        let chips = data.ledger.filters.filter { Self.showsChip($0, current: current) }
        return ChipFlowLayout(spacing: 6) {
            ForEach(chips, id: \.id) { chip in
                chipButton(chip, pal: pal)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    /// 一列都沒有的類別不放膠囊（「全部」和正在選的那顆一定放）
    private static func showsChip(_ chip: HouseLedgerFilterChip, current: HouseLedgerFilter) -> Bool {
        if chip.filter == .all || chip.filter == current { return true }
        return chip.rowCount > 0
    }

    private func chipButton(_ chip: HouseLedgerFilterChip, pal: TripBoardPalette) -> some View {
        let on = chip.filter == filter
        let fill = on ? HCColors.pick(0x0B1B45, 0x3B4F8F, pal) : FinanceCardTile.fill(pal)
        return Button {
            withAnimation(.easeOut(duration: 0.25)) { filter = chip.filter }
        } label: {
            Text(chip.text)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(on ? Color.white : pal.label)
                .padding(.horizontal, 11)
                .frame(minHeight: 28)
                .background(fill, in: Capsule())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: 年份時間軸

    private func flatten(_ years: [HouseLedgerYear]) -> [HCLedgerLine] {
        // 今年沒有紀錄（例如去年買的、今年還沒記）時，最新的那一年展開，免得整本都收著
        let anyCurrent = years.contains { $0.isCurrent }
        var out: [HCLedgerLine] = []
        for (i, y) in years.enumerated() {
            let byDefault = y.isCurrent || (!anyCurrent && i == 0)
            let open = byDefault != toggledYears.contains(y.year)
            out.append(.year(y, expanded: open))
            guard open else { continue }
            let all = moreYears.contains(y.year)
            let shown = all ? y.events : Array(y.events.prefix(Self.preview))
            for (k, e) in shown.enumerated() {
                out.append(.row(e, divider: k > 0))
            }
            let hidden = y.events.count - shown.count
            if hidden > 0 {
                out.append(.more(year: y.year, hidden: hidden))
            }
        }
        return out
    }

    @ViewBuilder
    private func lineView(_ line: HCLedgerLine, pal: TripBoardPalette) -> some View {
        switch line {
        case .year(let y, let expanded):
            yearHeader(y, expanded: expanded, pal: pal)
        case .row(let e, let divider):
            VStack(spacing: 0) {
                if divider {
                    Divider().padding(.leading, 76)
                }
                ledgerRow(e)
            }
        case .more(let year, let hidden):
            moreButton(year: year, hidden: hidden, pal: pal)
        }
    }

    /// 組頭「2026 年・79 筆」＋右邊小計；點一下展開／收起
    private func yearHeader(_ y: HouseLedgerYear, expanded: Bool, pal: TripBoardPalette) -> some View {
        let parts = Self.splitTitle(y.title)
        let state: String = expanded ? "已展開" : "已收起"
        let hint: String = expanded ? "點兩下收起" : "點兩下展開"
        return Button {
            withAnimation(.easeOut(duration: 0.25)) { toggleYear(y.year) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.heavy))
                    .frame(width: 12)
                Text(parts.left)
                Spacer(minLength: 8)
                Text(parts.right)
                    .monospacedDigit()
            }
            .font(.footnote.weight(.heavy))
            .foregroundStyle(pal.label)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(y.title)
        .accessibilityValue(state)
        .accessibilityHint(hint)
    }

    private func toggleYear(_ year: Int) {
        if toggledYears.contains(year) {
            toggledYears.remove(year)
        } else {
            toggledYears.insert(year)
        }
    }

    /// 「2026 年・79 筆・NT$862.6萬」→ 左「2026 年・79 筆」、右「NT$862.6萬」（最後一個「・」後面是小計）
    private static func splitTitle(_ t: String) -> (left: String, right: String) {
        guard let r = t.range(of: "・", options: .backwards) else { return (left: t, right: "") }
        return (left: String(t[..<r.lowerBound]), right: String(t[r.upperBound...]))
    }

    private func moreButton(year: Int, hidden: Int, pal: TripBoardPalette) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 14)
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    _ = moreYears.insert(year)
                }
            } label: {
                Text("再看 \(hidden) 筆")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.hint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 點一下＝打開（外殼依 source 決定開哪個編輯頁）；長按＝編輯／刪除。年列不能刪（canDelete）。
    private func ledgerRow(_ e: HouseLedgerEvent) -> some View {
        Button {
            actions.openLedger(e)
        } label: {
            HouseLedgerRowView(event: e)
        }
        .buttonStyle(MoneyPressStyle())
        .contextMenu {
            rowMenu(e)
        }
        .accessibilityActions {
            rowAccessibility(e)
        }
    }

    @ViewBuilder
    private func rowMenu(_ e: HouseLedgerEvent) -> some View {
        Button {
            actions.openLedger(e)
        } label: {
            Label(Self.openTitle(e), systemImage: Self.openIcon(e))
        }
        if e.canDelete {
            Button(role: .destructive) {
                actions.deleteLedger(e)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func rowAccessibility(_ e: HouseLedgerEvent) -> some View {
        Button(Self.openTitle(e)) { actions.openLedger(e) }
        if e.canDelete {
            Button("刪除") { actions.deleteLedger(e) }
        }
    }

    /// 房貸年列點了是捲到房貸區，選單寫「看房貸」比「編輯」準
    private static func openTitle(_ e: HouseLedgerEvent) -> String {
        if case .mortgageYear = e.source { return "看房貸" }
        return "編輯"
    }

    private static func openIcon(_ e: HouseLedgerEvent) -> String {
        if case .mortgageYear = e.source { return "building.columns" }
        return "pencil"
    }
}

/// 帳本的一列（匯出逐筆也用它，所以只吃 event、不讀任何 EnvironmentObject）：
/// 52pt 日期塊、32pt 分類色圓裡一個字、標題與細字、右邊金額；沒連到記帳多一個灰色小標
struct HouseLedgerRowView: View {
    let event: HouseLedgerEvent

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let e = event
        HStack(alignment: .center, spacing: 10) {
            dateBlock(e)
            Text(e.mark.glyph)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(HCColors.mark(e.mark, pal: pal), in: Circle())
                .accessibilityHidden(true)
            texts(e)
            Spacer(minLength: 6)
            amount(e, pal: pal)
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(e.accessibilityText)
    }

    private func dateBlock(_ e: HouseLedgerEvent) -> some View {
        VStack(spacing: 0) {
            Text(e.dayText)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .monospacedDigit()
            Text(e.monthText)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 52)
    }

    private func texts(_ e: HouseLedgerEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(e.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !e.detail.isEmpty {
                Text(e.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private func amount(_ e: HouseLedgerEvent, pal: TripBoardPalette) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(e.amountText)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
            if e.isUnlinked {
                HCMiniTag(text: "沒連到記帳", color: pal.label)
            }
        }
    }
}

// MARK: - 房屋資料

/// 資料卡的一列：左邊標籤（寬 84）、右邊值靠右（樣子照 StockInfoCard）；accessory 是右邊的小圖示（›、展開）
struct FinanceInfoRow: View {
    let label: String
    let value: Text
    var accessory: String? = nil
    var labelWidth: CGFloat = 84

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            value
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
            if let accessory {
                Image(systemName: accessory)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 一串資料列，列和列之間細線（同 StockInfoCard）；外框由呼叫端決定。
/// 每列自己決定能不能點（地址是選單、權狀可展開、保險可點），所以收的是已經包好的畫面。
struct FinanceInfoRows: View {
    struct Row: Identifiable {
        let id: String
        let content: AnyView
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                if i > 0 {
                    Divider().padding(.leading, 14)
                }
                row.content
            }
        }
    }
}

/// 房屋資料：衛星小圖、地址（選單：複製／在地圖打開）、類型、坪數、單價、購入、估值、屋齡、所有權人、
/// 權狀（可展開）、保險（點了打開那筆記帳）、售出、備註。永遠顯示，沒有值的列 HouseCardData 已經不放。
/// 分享圖片不輸出這一區（門牌、權狀、所有權人、衛星圖都在這裡）。
struct HouseInfoSection: View {
    let estate: RealEstate
    let data: HouseCardData
    let actions: HouseCardActions

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var geocoder = RealEstateGeocoder.shared
    @State private var deedsOpen = false
    /// 查座標是哪一間發出去的：換房後舊的結果不寫回來
    @State private var geoRequestId: UUID? = nil
    /// 座標查好、可以畫衛星圖的那一間
    @State private var geoEstateId: UUID? = nil

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let info = data.info
        VStack(alignment: .leading, spacing: 10) {
            HCHeader(title: "房屋資料", trailing: info.trailing)
            VStack(alignment: .leading, spacing: 0) {
                satellite(info, pal: pal)
                FinanceInfoRows(rows: infoRows(info, pal: pal))
                hintRow(info.hint, pal: pal)
            }
            .modifier(FinanceCardChrome())
        }
        .task(id: geocodeAddress ?? "") {
            await loadCoordinate()
        }
    }

    /// 跟列表卡同一個查法（縣市＋地址，沒填地址用建物門牌），衛星圖才會是同一張
    private var geocodeAddress: String? {
        RealEstateGeocoder.address(of: estate)
    }

    private func loadCoordinate() async {
        guard let address = geocodeAddress else { return }
        let requestedId = estate.id
        geoRequestId = requestedId
        if geocoder.coordinate(for: address) == nil {
            await geocoder.resolve(address)
        }
        guard !Task.isCancelled, geoRequestId == requestedId else { return }
        geoEstateId = requestedId
    }

    // MARK: 衛星小圖

    @ViewBuilder
    private func satellite(_ info: HouseInfoData, pal: TripBoardPalette) -> some View {
        if geoEstateId == estate.id, let address = geocodeAddress, let c = geocoder.coordinate(for: address) {
            Button {
                openMaps(info.addressQuery ?? address)
            } label: {
                satelliteLabel(address: address, latitude: c.latitude, longitude: c.longitude, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel("衛星空照")
            .accessibilityHint("點兩下在地圖打開")
            Divider().padding(.leading, 14)
        }
    }

    /// MoneyPanel 的衛星快照是 120×132：照原尺寸放，才不會放大變糊
    private func satelliteLabel(address: String, latitude: Double, longitude: Double, pal: TripBoardPalette) -> some View {
        HStack(spacing: 12) {
            MoneyPanel(theme: .finHome, seed: data.seed, monogram: nil, badge: nil, photoURL: nil,
                       latitude: latitude, longitude: longitude, place: TripPlaceName.parse(address), width: 120)
                .frame(width: 120, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("衛星空照")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primary)
                Text("點一下在地圖打開")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "map.fill")
                .font(.subheadline)
                .foregroundStyle(pal.hint)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    // MARK: 各列

    private func infoRows(_ info: HouseInfoData, pal: TripBoardPalette) -> [FinanceInfoRows.Row] {
        info.rows.map { r in
            FinanceInfoRows.Row(id: r.id, content: rowView(r, info: info, pal: pal))
        }
    }

    private func rowView(_ r: HouseInfoData.Row, info: HouseInfoData, pal: TripBoardPalette) -> AnyView {
        switch r.kind {
        case .plain:
            return AnyView(FinanceInfoRow(label: r.label, value: Text(r.value)))
        case .address:
            return AnyView(addressRow(r, query: info.addressQuery ?? r.value))
        case .deeds:
            return AnyView(deedsRow(r, deeds: info.deeds, pal: pal))
        case .insurance(let id):
            return AnyView(insuranceRow(r, expenseId: id))
        case .warning:
            return AnyView(warningRow(r, pal: pal))
        case .note:
            return AnyView(noteRow(r))
        }
    }

    /// 點地址：選單「複製」「在地圖打開」
    private func addressRow(_ r: HouseInfoData.Row, query: String) -> some View {
        Menu {
            Button {
                UIPasteboard.general.string = r.value
            } label: {
                Label("複製", systemImage: "doc.on.doc")
            }
            Button {
                openMaps(query)
            } label: {
                Label("在地圖打開", systemImage: "map")
            }
        } label: {
            FinanceInfoRow(label: r.label, value: Text(r.value), accessory: "ellipsis.circle")
        }
        .accessibilityHint("點兩下可以複製，或在地圖打開")
    }

    /// 權狀：「土地 1 份・建物 1 份」點了展開坐落、地號、建號、門牌、用途、面積
    private func deedsRow(_ r: HouseInfoData.Row, deeds: [HouseInfoData.DeedBlock], pal: TripBoardPalette) -> some View {
        let icon: String = deedsOpen ? "chevron.up" : "chevron.down"
        let state: String = deedsOpen ? "已展開" : "已收起"
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.25)) { deedsOpen.toggle() }
            } label: {
                FinanceInfoRow(label: r.label, value: Text(r.value), accessory: icon)
            }
            .buttonStyle(.plain)
            .accessibilityValue(state)
            if deedsOpen {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(deeds, id: \.id) { block in
                        deedBlock(block, pal: pal)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    private func deedBlock(_ b: HouseInfoData.DeedBlock, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(b.title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(pal.label)
            ForEach(b.rows, id: \.id) { row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    Text(row.value)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FinanceCardTile.fill(pal), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 保險：有連到記帳的點了打開那一筆（付費在外殼擋）
    @ViewBuilder
    private func insuranceRow(_ r: HouseInfoData.Row, expenseId: UUID?) -> some View {
        if let id = expenseId {
            Button {
                actions.openExpense(id)
            } label: {
                FinanceInfoRow(label: r.label, value: Text(r.value), accessory: "chevron.right")
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下打開這張保單的記帳")
        } else {
            FinanceInfoRow(label: r.label, value: Text(r.value))
        }
    }

    private func warningRow(_ r: HouseInfoData.Row, pal: TripBoardPalette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(r.value)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(MoneyTone.warn.color(pal))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private func noteRow(_ r: HouseInfoData.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(r.value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    /// 只有購入、估值兩列時的「補上地址、坪數、樓層 → 編輯」
    @ViewBuilder
    private func hintRow(_ hint: String?, pal: TripBoardPalette) -> some View {
        if let hint {
            Divider().padding(.leading, 14)
            Button {
                actions.edit(.address)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                    Text(hint)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(pal.hint)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(MoneyPressStyle())
        }
    }

    private func openMaps(_ query: String) {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=" + q) else { return }
        openURL(url)
    }
}

// MARK: - 水電瓦斯

/// 水電瓦斯：每個表一列（主表在前、額外的表接後面），右邊最近一期；「看全部 N 筆」；右上角「＋」一直都在。
/// 收據圖示是列旁邊的另一顆按鈕（不包在列按鈕裡），點了用 CutePhotoViewer 看全部照片。
struct HouseUtilitiesSection: View {
    let estate: RealEstate
    let data: HouseCardData
    let actions: HouseCardActions

    @Environment(\.colorScheme) private var scheme
    @State private var showAll = false

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let u = data.utilities
        let a = actions
        VStack(alignment: .leading, spacing: 10) {
            HCHeader(title: "水電瓦斯", trailing: u.trailing, addLabel: "記一筆水電費",
                     onAdd: { a.openUtility(nil) })
            card(u, pal: pal)
        }
    }

    @ViewBuilder
    private func card(_ u: HouseUtilitiesData, pal: TripBoardPalette) -> some View {
        if u.isEmpty {
            emptyCard(pal)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(u.meters.enumerated()), id: \.element.id) { i, m in
                    if i > 0 {
                        Divider().padding(.leading, 62)
                    }
                    meterRow(m, u: u, pal: pal)
                }
                if !u.payments.isEmpty {
                    paymentsBlock(u, pal: pal)
                }
            }
            .modifier(FinanceCardChrome())
        }
    }

    /// 沒有表號也沒有繳費：不整區藏起來，縮成一行可以記第一筆
    private func emptyCard(_ pal: TripBoardPalette) -> some View {
        Button {
            actions.openUtility(nil)
        } label: {
            HStack(spacing: 8) {
                Text("＋ 記第一筆水電費（表號在「編輯」填）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.hint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .modifier(FinanceCardChrome())
    }

    // MARK: 表

    private func meterRow(_ m: HouseUtilitiesData.Meter, u: HouseUtilitiesData, pal: TripBoardPalette) -> some View {
        let hint: String = m.latest == nil ? "點兩下記一筆" : "點兩下打開最近一期"
        return HStack(spacing: 8) {
            Button {
                actions.openUtility(m.latest)
            } label: {
                meterLabel(m, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .contextMenu {
                meterMenu(m)
            }
            .accessibilityHint(hint)
            if let p = m.latest, m.latestPhotoCount > 0 {
                receiptButton(p, count: m.latestPhotoCount, amountText: latestAmount(p, in: u), pal: pal)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func meterLabel(_ m: HouseUtilitiesData.Meter, pal: TripBoardPalette) -> some View {
        let tint = HCColors.utility(m.type, pal: pal)
        let sub = [m.name, m.owner, m.userNumber].filter { !$0.isEmpty }.joined(separator: "・")
        return HStack(spacing: 12) {
            Image(systemName: m.type.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                meterTitle(m)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            latestView(m, pal: pal)
        }
        .foregroundStyle(Color.primary)
        .contentShape(Rectangle())
    }

    /// 「電號 01-2345-67-8」：號碼用等寬字
    private func meterTitle(_ m: HouseUtilitiesData.Meter) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(m.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if !m.number.isEmpty {
                Text(m.number)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    @ViewBuilder
    private func latestView(_ m: HouseUtilitiesData.Meter, pal: TripBoardPalette) -> some View {
        if let t = m.latestText {
            HStack(spacing: 3) {
                Text(t)
                    .font(.subheadline.weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text("記一筆")
                .font(.caption.weight(.bold))
                .foregroundStyle(pal.hint)
        }
    }

    /// 長按表號可以複製
    @ViewBuilder
    private func meterMenu(_ m: HouseUtilitiesData.Meter) -> some View {
        if !m.number.isEmpty {
            Button {
                UIPasteboard.general.string = m.number
            } label: {
                Label("複製" + m.title, systemImage: "doc.on.doc")
            }
        }
        if m.latest != nil {
            Button {
                actions.openUtility(m.latest)
            } label: {
                Label("打開最近一期", systemImage: "pencil")
            }
        } else {
            Button {
                actions.openUtility(nil)
            } label: {
                Label("記一筆", systemImage: "plus")
            }
        }
    }

    private func latestAmount(_ p: UtilityPayment, in u: HouseUtilitiesData) -> String {
        u.payments.first(where: { $0.id == p.id })?.amountText ?? MoneyFormat.short(p.amount)
    }

    // MARK: 全部繳費

    private func paymentsBlock(_ u: HouseUtilitiesData, pal: TripBoardPalette) -> some View {
        let title: String = showAll ? "收起" : (u.showAllTitle ?? "看全部")
        return VStack(alignment: .leading, spacing: 0) {
            if showAll {
                ForEach(u.payments, id: \.id) { p in
                    Divider().padding(.leading, 14)
                    paymentRow(p, pal: pal)
                }
            }
            Divider().padding(.leading, 14)
            Button {
                withAnimation(.easeOut(duration: 0.25)) { showAll.toggle() }
            } label: {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.hint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func paymentRow(_ p: HouseUtilitiesData.Payment, pal: TripBoardPalette) -> some View {
        let payment = p.payment
        return HStack(spacing: 8) {
            Button {
                actions.openUtility(payment)
            } label: {
                paymentLabel(p, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .contextMenu {
                Button {
                    actions.openUtility(payment)
                } label: {
                    Label("編輯", systemImage: "pencil")
                }
            }
            .accessibilityAction(named: "編輯") { actions.openUtility(payment) }
            if p.photoCount > 0 {
                receiptButton(payment, count: p.photoCount, amountText: p.amountText, pal: pal)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func paymentLabel(_ p: HouseUtilitiesData.Payment, pal: TripBoardPalette) -> some View {
        let type = p.payment.type
        let tint = HCColors.utility(type, pal: pal)
        // 電費的字改用 A65300／FFC14D（白底上的 .yellow 看不清楚）；水、瓦斯用一般的灰字
        let typeInk: Color = type == .electricity ? tint : Color.secondary
        return HStack(spacing: 10) {
            Image(systemName: type.icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(p.dateText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(p.typeText)
                .font(.subheadline)
                .foregroundStyle(typeInk)
            Spacer(minLength: 6)
            Text(p.amountText)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(Color.primary)
        .contentShape(Rectangle())
    }

    private func receiptButton(_ p: UtilityPayment, count: Int, amountText: String, pal: TripBoardPalette) -> some View {
        Button {
            actions.showPhotos(Self.draft(p, amountText: amountText))
        } label: {
            HCPhotoBadge(count: count, pal: pal)
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel("看收據照片，\(count) 張")
    }

    /// 全部收據照片（不再只看第一張）；水電一律看 photoFileNames
    private static func draft(_ p: UtilityPayment, amountText: String) -> CutePhotoDraft {
        let urls = p.photoFileNames.map { UtilityPayment.photosDirectory.appendingPathComponent($0) }
        let note = p.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [amountText, note].filter { !$0.isEmpty }
        return CutePhotoDraft(urls: urls, title: p.type.rawValue + " 繳費", note: parts.joined(separator: "・"),
                              date: p.date, kind: .utility(p.type))
    }
}

// MARK: - 電梯保養

/// 電梯保養：一句話（上次、平均間隔、下次大約；超過時注意色）、新到舊先列 3 筆、「看全部」、右上角「＋」。
/// 沒勾「有電梯」時 HouseCardData 給 nil，整區不出現。
struct HouseElevatorSection: View {
    let estate: RealEstate
    let data: HouseCardData
    let actions: HouseCardActions

    @Environment(\.colorScheme) private var scheme
    @State private var showAll = false

    private static let preview = 3

    var body: some View {
        if let e = data.elevator {
            content(e, pal: TripBoardPalette(scheme))
        }
    }

    private func content(_ e: HouseElevatorData, pal: TripBoardPalette) -> some View {
        let a = actions
        return VStack(alignment: .leading, spacing: 10) {
            HCHeader(title: "電梯保養", trailing: e.trailing, addLabel: "記一次電梯保養",
                     onAdd: { a.openElevator(nil) })
            card(e, pal: pal)
        }
    }

    private func card(_ e: HouseElevatorData, pal: TripBoardPalette) -> some View {
        let shown = showAll ? e.records : Array(e.records.prefix(Self.preview))
        return VStack(alignment: .leading, spacing: 0) {
            HCSentence(line: e.line, pal: pal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            if e.records.isEmpty {
                Divider().padding(.leading, 14)
                firstButton(pal)
            }
            ForEach(shown, id: \.id) { r in
                Divider().padding(.leading, 14)
                recordRow(r, pal: pal)
            }
            if e.records.count > Self.preview {
                Divider().padding(.leading, 14)
                moreButton(total: e.records.count, pal: pal)
            }
        }
        .modifier(FinanceCardChrome())
    }

    private func firstButton(_ pal: TripBoardPalette) -> some View {
        Button {
            actions.openElevator(nil)
        } label: {
            HStack(spacing: 6) {
                Text("＋ 記第一次保養")
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(pal.hint)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
    }

    private func recordRow(_ r: HouseElevatorData.Record, pal: TripBoardPalette) -> some View {
        let record = r.record
        return HStack(spacing: 8) {
            Button {
                actions.openElevator(record)
            } label: {
                recordLabel(r)
            }
            .buttonStyle(MoneyPressStyle())
            .contextMenu {
                Button {
                    actions.openElevator(record)
                } label: {
                    Label("編輯", systemImage: "pencil")
                }
            }
            .accessibilityLabel(r.dateText + " 保養")
            .accessibilityAction(named: "編輯") { actions.openElevator(record) }
            if r.photoCount > 0 {
                Button {
                    actions.showPhotos(Self.draft(record))
                } label: {
                    HCPhotoBadge(count: r.photoCount, pal: pal)
                }
                .buttonStyle(MoneyPressStyle())
                .accessibilityLabel("看保養照片，\(r.photoCount) 張")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func recordLabel(_ r: HouseElevatorData.Record) -> some View {
        HStack(spacing: 12) {
            Text(r.dateText)
                .font(.subheadline.weight(.heavy))
                .monospacedDigit()
            Text("保養")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(Color.primary)
        .contentShape(Rectangle())
    }

    private func moreButton(total: Int, pal: TripBoardPalette) -> some View {
        let title = showAll ? "收起" : "看全部 \(total) 次"
        return Button {
            withAnimation(.easeOut(duration: 0.25)) { showAll.toggle() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(pal.hint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 保養照片全部看（不再只看第一張）
    private static func draft(_ m: ElevatorMaintenance) -> CutePhotoDraft {
        let urls = m.photoFileNames.map { ElevatorMaintenance.photoURL(for: $0) }
        return CutePhotoDraft(urls: urls, title: "電梯保養", note: "", date: m.date, kind: .elevator)
    }
}

// MARK: - 這個檔案裡共用的小零件

/// 區塊標題（MoneySectionHeader）＋需要時右邊一顆綠色「＋」（MoneySectionHeader 本身沒有按鈕槽）
private struct HCHeader: View {
    let title: String
    var trailing: String? = nil
    var addLabel: String? = nil
    var onAdd: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MoneySectionHeader(title: title, trailing: trailing)
                .accessibilityAddTraits(.isHeader)
            if let onAdd {
                HCAddButton(label: addLabel ?? "新增", action: onAdd)
            }
        }
    }
}

/// 區塊標題右邊的綠色小「＋」
private struct HCAddButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Color(tb: 0x1F9D57), in: Circle())
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel(label)
    }
}

/// 綠色膠囊「＋ 記一筆」「＋ 加一段」（同股票帳本的 177A44 膠囊）
private struct HCGreenPill: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "plus")
            .font(.caption.weight(.heavy))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(Color(tb: 0x177A44), in: Capsule())
    }
}

/// 灰色／注意色小標（「沒連到記帳」「期數沒填」）
private struct HCMiniTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// 列旁邊的照片小圖示＋張數（點了看全部照片）
private struct HCPhotoBadge: View {
    let count: Int
    let pal: TripBoardPalette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "photo.on.rectangle")
            Text("\(count)")
        }
        .font(.caption.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(pal.hint)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(pal.hint.opacity(0.12), in: Capsule())
    }
}

/// 白卡裡的一句話（HouseLine：金額粗體、上色）
private struct HCSentence: View {
    let line: HouseLine
    let pal: TripBoardPalette

    var body: some View {
        HCText.line(line, pal: pal)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 3×2 格（樣子照股票帳本的六格）；可以點的格子小字後面多一個 ›
private struct HCTileGrid: View {
    let tiles: [HouseTile]
    let pal: TripBoardPalette
    var onTap: ((HouseTap) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // 超大字時三欄擠不下「還有 39 年 5 個月」，改兩欄
        let count = typeSize.isAccessibilitySize ? 2 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tiles, id: \.id) { t in
                cell(t)
            }
        }
    }

    @ViewBuilder
    private func cell(_ t: HouseTile) -> some View {
        if let onTap, HCText.isTappable(t.tap) {
            Button {
                onTap(t.tap)
            } label: {
                HCTile(tile: t, pal: pal, tappable: true)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint(HCText.hint(t.tap))
        } else {
            HCTile(tile: t, pal: pal, tappable: false)
        }
    }
}

private struct HCTile: View {
    let tile: HouseTile
    let pal: TripBoardPalette
    let tappable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tile.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(tile.value)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(HCColors.ink(tile.valueTone, pal: pal, fallback: Color.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            subLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(FinanceCardTile.fill(pal), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subLine: some View {
        HStack(spacing: 2) {
            Text(tile.sub.isEmpty ? " " : tile.sub)
                .font(.caption2)
                .foregroundStyle(HCColors.ink(tile.subTone, pal: pal, fallback: Color.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 分段長條的一段
private struct HCBarPart: Identifiable {
    let id: String
    let value: Double
    let color: Color
}

/// 分段長條（同股票「含息總報酬」那條：2pt 間隔、每段最少 2pt、外面裁成膠囊）；數字靠圖例的字唸，條本身不給讀
private struct HCStackBar: View {
    let parts: [HCBarPart]
    let height: CGFloat
    let pal: TripBoardPalette

    var body: some View {
        let positive = parts.filter { $0.value > 0 }
        let sum = positive.reduce(0.0) { $0 + $1.value }
        return GeometryReader { geo in
            bar(positive, sum: sum, width: geo.size.width)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func bar(_ list: [HCBarPart], sum: Double, width: CGFloat) -> some View {
        let gaps = CGFloat(max(0, list.count - 1)) * 2
        let usable = max(0, width - gaps)
        return ZStack(alignment: .leading) {
            Capsule().fill(pal.progressTrack)
            if sum > 0 {
                HStack(spacing: 2) {
                    ForEach(list, id: \.id) { p in
                        Rectangle()
                            .fill(p.color)
                            .frame(width: max(2, usable * CGFloat(p.value / sum)))
                    }
                }
                .clipShape(Capsule())
            }
        }
    }
}

/// 段落列「第 7／60 期」旁邊的細進度條
private struct HCThinBar: View {
    let fraction: Double
    let color: Color
    let track: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(color)
                    .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(minWidth: 40, maxWidth: .infinity)
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// 金色進度條（同股利卡「拿回成本」）
private struct HCGoldBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(tb: 0xE8A317, 0.16))
                Capsule()
                    .fill(LinearGradient(colors: [Color(tb: 0xFFD36B), Color(tb: 0xE89A12)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// HouseLine 轉成 Text、HouseTap 的提示字
private enum HCText {
    /// 一段一段接成一個 Text（粗體用 heavy、tone 上色）；用插值接，不串一長串 +
    static func line(_ line: HouseLine, pal: TripBoardPalette) -> Text {
        var out: Text? = nil
        for run in line.runs {
            let next = piece(run, pal: pal)
            if let prev = out {
                out = Text("\(prev)\(next)")
            } else {
                out = next
            }
        }
        return out ?? Text(verbatim: "")
    }

    private static func piece(_ run: HouseRun, pal: TripBoardPalette) -> Text {
        var t = Text(verbatim: run.text)
        if run.bold {
            t = t.fontWeight(.heavy)
        }
        if let tone = run.tone {
            t = t.foregroundStyle(tone.color(pal))
        }
        return t
    }

    static func isTappable(_ tap: HouseTap) -> Bool {
        switch tap {
        case .none: return false
        default: return true
        }
    }

    /// VoiceOver 的提示（點了會去哪裡）
    static func hint(_ tap: HouseTap) -> String {
        switch tap {
        case .none: return ""
        case .scrollToMortgage: return "點兩下捲到房貸"
        case .ledgerFilter(let f): return "點兩下在帳本只看「" + f.title + "」"
        case .edit: return "點兩下打開編輯頁"
        }
    }
}

/// 房屋卡片的顏色。淺色照樣稿；深色另訂（分類圓對卡片底至少 3:1、白字仍讀得到；長條、階梯對卡片底至少 3:1）。
private enum HCColors {
    static func pick(_ light: UInt32, _ dark: UInt32, _ pal: TripBoardPalette) -> Color {
        Color(tb: pal.dark ? dark : light)
    }

    /// 帳本 32pt 圓：價 6B4BE0、費 8A5CF6、裝 14A3A3、家 2F9BD8、修 E07A2E、清 8E9BBE、電 A65300、稅 C9590F、
    /// 保 E0457A、其 9AA3B5、貸 2F7FE8、固 5B6CC9。深色只把對深色卡片底不到 4:1 的調亮（價、費、電、稅、固）。
    static func mark(_ m: HouseLedgerMark, pal: TripBoardPalette) -> Color {
        switch m {
        case .price: return pick(0x6B4BE0, 0x856BE5, pal)
        case .fee: return pick(0x8A5CF6, 0x8E62F6, pal)
        case .renovation: return pick(0x14A3A3, 0x14A3A3, pal)
        case .furniture: return pick(0x2F9BD8, 0x2F9BD8, pal)
        case .repair: return pick(0xE07A2E, 0xE07A2E, pal)
        case .cleaning: return pick(0x8E9BBE, 0x8E9BBE, pal)
        case .utility: return pick(0xA65300, 0xC76300, pal)
        case .tax: return pick(0xC9590F, 0xD05C0F, pal)
        case .insurance: return pick(0xE0457A, 0xE0457A, pal)
        case .other: return pick(0x9AA3B5, 0x9AA3B5, pal)
        case .mortgage: return pick(0x2F7FE8, 0x2F7FE8, pal)
        case .fixed: return pick(0x5B6CC9, 0x6979CE, pal)
        }
    }

    /// 帳本總表四段：自備款紫、已繳房貸藍、一次性青、持有灰藍
    static func bucket(_ b: HouseLedgerBucket, pal: TripBoardPalette) -> Color {
        switch b {
        case .purchase: return pick(0x6B4BE0, 0xB79CFF, pal)
        case .mortgage: return pick(0x2F7FE8, 0x7DB2FF, pal)
        case .oneTime: return pick(0x14A3A3, 0x3FD0CF, pal)
        case .holding: return pick(0x8E9BBE, 0xA9B6D9, pal)
        }
    }

    /// 每個月住這裡：利息暖橘、還本金紫、房貸（分不出利息時）藍、固定費用靛、水電青、稅費保險藍灰、維修清潔其他琥珀
    static func living(_ k: HouseLivingData.Kind, pal: TripBoardPalette) -> Color {
        switch k {
        case .interest: return pick(0xF39A1E, 0xFFAD5C, pal)
        case .principal: return pick(0x6B4BE0, 0xB79CFF, pal)
        case .mortgage: return pick(0x2F7FE8, 0x7DB2FF, pal)
        case .fixed: return pick(0x5B6CC9, 0x9DA9FF, pal)
        case .utility: return pick(0x14A3A3, 0x3FD0CF, pal)
        case .taxInsurance: return pick(0x8E9BBE, 0xA9B6D9, pal)
        case .upkeep: return pick(0xE8A317, 0xFFC14D, pal)
        }
    }

    /// 水藍、電琥珀（字也用這個：A65300／FFC14D）、瓦斯橘
    static func utility(_ t: UtilityType, pal: TripBoardPalette) -> Color {
        switch t {
        case .water: return pick(0x2F7FE8, 0x7DB2FF, pal)
        case .electricity: return pick(0xA65300, 0xFFC14D, pal)
        case .gas: return pick(0xE07A2E, 0xFFA366, pal)
        }
    }

    /// 階梯圖：已繳實心藍紫、未繳淡色（深色的淡色也要對卡片底 3:1，所以不能只調透明度）
    static func stairPaid(_ pal: TripBoardPalette) -> Color { pick(0x6B4BE0, 0xB79CFF, pal) }
    static func stairLeft(_ pal: TripBoardPalette) -> Color { pick(0xD9CFFA, 0x6F64A8, pal) }

    /// 進度格的段交界細刻度
    static func tick(_ pal: TripBoardPalette) -> Color {
        pal.dark ? Color.white.opacity(0.32) : Color(tb: 0xA9B6D3)
    }

    /// 繳款中那一段的藍（白字在上面深淺色都讀得到）
    static let payingBlue = Color(tb: 0x2F7FE8)

    /// 格子大數字、小字的顏色：nil 或 neutral 用呼叫端給的一般字色
    static func ink(_ tone: MoneyTone?, pal: TripBoardPalette, fallback: Color) -> Color {
        guard let tone, tone != .neutral else { return fallback }
        return tone.color(pal)
    }
}
