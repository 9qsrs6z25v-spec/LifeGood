//
//  VehicleCardViews.swift
//  LifeGood
//
//  [v25.540] 載具卡片各區的畫面（照房屋卡 HouseCardViews 的寫法）。全部是「吃 VehicleCardData＋closure」的純畫面：
//  - 字與數字都在 VehicleCardData.build 算好，這裡只排版、上色；點了要做什麼一律交給 VehicleCardActions
//    （外殼 VehicleDetailView 實作，付費、確認框也在那裡擋，這裡不碰 store、不讀 EnvironmentObject——分享圖片用 ImageRenderer 畫）。
//  - 每一區自己判斷「整區不出現」（data 的那一塊是 nil 就不畫），外殼照順序放進 VStack 就好。
//  - 展開、看全部、再看 N 筆、選中的點、年份展開這些只影響顯示的狀態放各區自己的 @State；換車時外殼 .id(vehicleId) 整個重建。
//  - 卡片上不做左滑、不做「複製」：點一下＝打開，長按＝選單（編輯、停止扣款、刪除），VoiceOver 用 accessibilityActions。
//  - 分類色、長條色：淺色照樣稿，深色另訂（對卡片底至少 3:1，白字的分類圓白字也要 3:1），都收在 VCColors。
//  - body 一律拆成小 func／小 struct：v25.531 曾因 body 型別檢查逾時壞過一次。
//

import SwiftUI
import Charts

// MARK: - 共用介面（外殼照這裡的名字呼叫，不要改）

/// 卡片上每一個「點了要做事」的地方。畫面只呼叫，外殼負責付費檢查、確認框、打開編輯頁。
/// 預設值全是空 closure：分享圖片直接用 VehicleCardActions()。
struct VehicleCardActions {
    var scrollTo: (VehicleAnchor) -> Void = { _ in }
    var setLedgerFilter: (VehicleLedgerFilter) -> Void = { _ in }
    var edit: (VehicleEditFocus) -> Void = { _ in }
    var fixCheck: (VehicleCheck, VehicleCheck.Action) -> Void = { _, _ in }
    var openExpense: (UUID) -> Void = { _ in }
    var stopExpense: (UUID) -> Void = { _ in }                       // 接下來、車貸列長按「停止扣款」
    var deleteLoan: (VehicleLoanSectionData.Row) -> Void = { _ in }
    var addLedger: (VehicleLedgerAddKind) -> Void = { _ in }         // ＋ 記一筆／記保險／記稅費／加一筆車貸(.carLoan)／記第一次充電
    var openLedger: (VehicleLedgerEvent) -> Void = { _ in }
    var deleteLedger: (VehicleLedgerEvent) -> Void = { _ in }
    var openAnalytics: () -> Void = {}
    var showPhotos: (CutePhotoDraft) -> Void = { _ in }
    /// 「＋ 記一筆」選單要在打開前就擋付費：沒付費時外殼給 false，選單換成普通按鈕、按了呼叫 askPremium
    var canEdit: Bool = true                                         // false：「＋ 記一筆」換成普通按鈕
    var askPremium: () -> Void = {}
}

fileprivate extension VehicleCardActions {
    /// 格子、圖例、提示列上的 VehicleTap 交給對應的動作（帳本篩選要先切再捲過去，使用者才看得到切了什麼）
    func handle(_ tap: VehicleTap) {
        switch tap {
        case .none:
            break
        case .scrollTo(let anchor):
            scrollTo(anchor)
        case .ledgerFilter(let f):
            setLedgerFilter(f)
            scrollTo(.ledger)
        case .edit(let focus):
            edit(focus)
        case .openExpense(let id):
            openExpense(id)
        case .openAnalytics:
            openAnalytics()
        }
    }
}

extension VehicleTile: FinanceTileContent {
    var isTappable: Bool { VCText.isTappable(tap) }
    var tapHint: String { VCText.hint(tap) }
}

// MARK: - 看板

/// 看板（天空＋這台車的路）＋下面的車貸進度格（或一行）、膠囊。
/// 外框照 MoneyBoardCard（同一個圓角設定、同一個 MoneyBoardChrome），頭部合成一個 VoiceOver 元素唸 data 組好的那一句，
/// 所以跟房屋一樣自己組外框（MoneyBoardCard 只收 MoneyBoardHeader、外面掛不上 accessibility）。
struct VehicleCardBoard: View {
    let data: VehicleCardData
    var scrollTo: ((VehicleAnchor) -> Void)? = nil   // nil：分享圖片（進度格、提示列不能點）

    @Environment(\.colorScheme) private var scheme
    /// 只讀「圓角」（同 MoneyBoardCard：看板不吃英雄卡的漸層與 KPI 樣式）
    @ObservedObject private var heroStyle = HeroStyleStore.shared

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let corner = CGFloat(heroStyle.value(.corner, .vehicle))
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
        data.progress != nil || data.progressNote != nil || !data.chips.isEmpty
    }

    private func header(_ pal: TripBoardPalette) -> some View {
        let b = data.board
        let tint: Color? = b.capsuleTone == MoneyTone.neutral ? nil : b.capsuleTone.color(pal)
        let bigTone: MoneyTone? = b.bigTone == MoneyTone.neutral ? nil : b.bigTone
        let line: Text? = b.line.runs.isEmpty ? nil : FinanceLineText.text(b.line, pal: pal)
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
            scene: .drive(data.scene),
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
            if let note = data.progressNote {
                progressNote(note, pal: pal)
            }
            if !data.chips.isEmpty {
                MoneyBoardChips(chips: data.chips, pal: pal)
            }
        }
    }

    /// 車貸進度格：看板上唯一能點的地方（捲到車貸區），跟房屋的房貸進度格同一個例外
    @ViewBuilder
    private func progress(_ p: FinanceProgressData, pal: TripBoardPalette) -> some View {
        if let scrollTo {
            Button {
                scrollTo(.loan)
            } label: {
                FinanceProgressCell(p: p, pal: pal, tappable: true)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下捲到車貸")
        } else {
            FinanceProgressCell(p: p, pal: pal, tappable: false)
        }
    }

    /// 全部繳完：一行綠勾；沒填年限：一行注意色，點了捲到「要確認」
    @ViewBuilder
    private func progressNote(_ n: VehicleProgressNote, pal: TripBoardPalette) -> some View {
        switch n.kind {
        case .paidOff:
            FinanceDoneRow(icon: "checkmark.seal.fill", text: n.text, tone: .good, pal: pal)
        case .termMissing:
            termMissingRow(n.text, pal: pal)
        }
    }

    @ViewBuilder
    private func termMissingRow(_ text: String, pal: TripBoardPalette) -> some View {
        if let scrollTo {
            Button {
                scrollTo(.checks)
            } label: {
                FinanceDoneRow(icon: "exclamationmark.triangle.fill", text: text, tone: .warn, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下捲到「要確認」")
        } else {
            FinanceDoneRow(icon: "exclamationmark.triangle.fill", text: text, tone: .warn, pal: pal)
        }
    }
}

// MARK: - 要確認

/// 會讓數字算錯的資料問題：一件一列，右邊 1～2 顆按鈕（付費、確認都在外殼的 fixCheck 裡）。一件都沒有時整區不出現。
struct VehicleChecksSection: View {
    let data: VehicleCardData
    let actions: VehicleCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !data.checks.isEmpty {
            content(TripBoardPalette(scheme))
        }
    }

    private func content(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "要確認", trailing: data.checksTrailing)
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

    private func row(_ c: VehicleCheck, pal: TripBoardPalette) -> some View {
        FinanceCheckRow(icon: c.icon, message: c.message, buttons: buttons(c),
                        accessibilityLabel: c.accessibilityLabel, pal: pal)
    }

    private func buttons(_ c: VehicleCheck) -> [FinanceCheckButton] {
        let a = actions
        return c.actions.map { act in
            FinanceCheckButton(title: act.title, action: { a.fixCheck(c, act) })
        }
    }
}

// MARK: - 每月養車

/// 每個月養這台車到底要多少：分段長條＋可以點的圖例（車貸→車貸區；定期、保養、其他→帳本篩選；能源→能源區）、
/// 三句話、注意色提示、「填上總貸款金額 →」。合計 < 1 或已售出時 data.monthly 是 nil，整區不出現。
/// forExport：分享圖用，提示列不能點、不畫「＋ 記保險」和「填上總貸款金額 →」。
struct VehicleMonthlySection: View {
    let data: VehicleCardData
    let actions: VehicleCardActions
    var forExport: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let m = data.monthly {
            content(m, pal: TripBoardPalette(scheme))
        }
    }

    private func content(_ m: VehicleMonthlyData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "每月養車", trailing: VCText.nonEmpty(m.trailing))
            card(m, pal: pal)
        }
    }

    private func card(_ m: VehicleMonthlyData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            headline(m)
            barBlock(m, pal: pal)
            // J223：算不出利率時「長條下」多一行，緊接在長條和圖例下面（它講的就是長條裡合成一段的「車貸」）
            if let hint = m.splitHint, !forExport {
                splitButton(hint, tap: m.splitTap, pal: pal)
            }
            sentences(m, pal: pal)
            hints(m, pal: pal)
            Text(m.footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    /// 「平均每月」小字＋「約 NT$5,200」大字
    private func headline(_ m: VehicleMonthlyData) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("平均每月")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
            Text(m.headline)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    /// 長條＋圖例合成一個 VoiceOver 元素（唸 data 組好的那一句）；圖例能做的事放進 accessibilityActions
    private func barBlock(_ m: VehicleMonthlyData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceStackBar(parts: bars(m, pal: pal), height: 12, pal: pal)
            legend(m, pal: pal)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.accessibilityText)
        .accessibilityActions {
            legendActions(m)
        }
    }

    private func bars(_ m: VehicleMonthlyData, pal: TripBoardPalette) -> [FinanceBarPart] {
        m.parts.map { p in
            FinanceBarPart(id: p.id, value: p.value, color: VCColors.monthly(p.kind, flavor: m.energyFlavor, pal: pal))
        }
    }

    private func legend(_ m: VehicleMonthlyData, pal: TripBoardPalette) -> some View {
        ChipFlowLayout(spacing: 12) {
            ForEach(m.parts, id: \.id) { p in
                FinanceLegendButton(color: VCColors.monthly(p.kind, flavor: m.energyFlavor, pal: pal),
                                    label: p.label, valueText: p.valueText, accessibilityLabel: p.legend,
                                    hint: VCText.hint(p.tap), pal: pal, action: legendAction(p))
            }
        }
    }

    private func legendAction(_ p: VehicleMonthlyData.Part) -> (() -> Void)? {
        if forExport { return nil }
        let a = actions
        let tap = p.tap
        return { a.handle(tap) }
    }

    @ViewBuilder
    private func legendActions(_ m: VehicleMonthlyData) -> some View {
        if !forExport {
            ForEach(m.parts, id: \.id) { p in
                Button(p.label) {
                    actions.handle(p.tap)
                }
            }
        }
    }

    /// ①真正花掉的 ②每公里 ③折舊（有才出現）
    @ViewBuilder
    private func sentences(_ m: VehicleMonthlyData, pal: TripBoardPalette) -> some View {
        if let line = m.realLine {
            FinanceSentence(line: line, pal: pal)
        }
        if let s = m.perKmLine {
            FinanceSentence(line: FinanceLine.text(s), pal: pal)
        }
        if let line = m.depreciationLine {
            FinanceSentence(line: line, pal: pal)
        }
    }

    /// 注意色提示：沒連到保險（旁邊「＋ 記保險 →」）、買車不到一年；晚開始記的提示用灰字
    @ViewBuilder
    private func hints(_ m: VehicleMonthlyData, pal: TripBoardPalette) -> some View {
        if let hint = m.insuranceHint {
            insuranceRow(hint, pal: pal)
        }
        if let hint = m.firstYearHint {
            VCNoteRow(text: hint, warn: true, pal: pal)
        }
        if let hint = m.lateStartHint {
            VCNoteRow(text: hint, warn: false, pal: pal)
        }
    }

    @ViewBuilder
    private func insuranceRow(_ hint: String, pal: TripBoardPalette) -> some View {
        if forExport {
            VCNoteRow(text: hint, warn: true, pal: pal)
        } else {
            Button {
                actions.addLedger(.insurance)
            } label: {
                VCNoteRow(text: hint, warn: true, pal: pal, actionText: "＋ 記保險 →")
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下記一筆保險")
        }
    }

    /// 「在車貸那筆填上總貸款金額，就能分出利息和本金 →」（字裡已經有箭頭）
    private func splitButton(_ text: String, tap: VehicleTap, pal: TripBoardPalette) -> some View {
        Button {
            actions.handle(tap)
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
        .accessibilityHint(VCText.hint(tap))
    }
}

// MARK: - 接下來

/// 要繳的、該保養的：一件一列（跟帳本列同一個樣子），依日期；先列 5 件、「看全部 N 件」原地展開；
/// 只有一次保養時一行灰字；油車、油電沒記稅費時一行提示＋「＋ 記稅費」。已售出或什麼都沒有時 data.upcoming 是 nil。
struct VehicleUpcomingSection: View {
    let data: VehicleCardData
    let actions: VehicleCardActions

    @Environment(\.colorScheme) private var scheme
    @State private var showAll = false

    private static let preview = 5

    var body: some View {
        if let u = data.upcoming {
            content(u, pal: TripBoardPalette(scheme))
        }
    }

    private func content(_ u: VehicleUpcomingData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "接下來", trailing: VCText.nonEmpty(u.trailing))
            card(u, pal: pal)
        }
    }

    private func card(_ u: VehicleUpcomingData, pal: TripBoardPalette) -> some View {
        let shown = showAll ? u.rows : Array(u.rows.prefix(Self.preview))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                if i > 0 {
                    Divider().padding(.leading, 76)
                }
                rowItem(r, pal: pal)
            }
            if u.rows.count > Self.preview {
                Divider().padding(.leading, 14)
                moreButton(total: u.rows.count, pal: pal)
            }
            if let note = u.maintenanceNote {
                if !u.rows.isEmpty {
                    Divider().padding(.leading, 14)
                }
                maintenanceNote(note)
            }
            if let tax = u.taxHint {
                if !u.rows.isEmpty || u.maintenanceNote != nil {
                    Divider().padding(.leading, 14)
                }
                taxRow(tax, pal: pal)
            }
        }
        .modifier(FinanceCardChrome())
    }

    /// 定期、車貸：點一下打開那筆，長按「編輯」「停止扣款」；保養估計：點了捲到帳本「保養・維修」，沒有長按選單
    @ViewBuilder
    private func rowItem(_ r: VehicleUpcomingData.Row, pal: TripBoardPalette) -> some View {
        if let id = r.expenseId {
            rowButton(r, pal: pal)
                .contextMenu {
                    rowMenu(id)
                }
                .accessibilityActions {
                    rowAccessibility(id)
                }
        } else {
            rowButton(r, pal: pal)
        }
    }

    private func rowButton(_ r: VehicleUpcomingData.Row, pal: TripBoardPalette) -> some View {
        Button {
            actions.handle(r.tap)
        } label: {
            VehicleUpcomingRowView(row: r, pal: pal)
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityHint(VCText.hint(r.tap))
    }

    @ViewBuilder
    private func rowMenu(_ id: UUID) -> some View {
        Button {
            actions.openExpense(id)
        } label: {
            Label("編輯", systemImage: "pencil")
        }
        Button {
            actions.stopExpense(id)
        } label: {
            Label("停止扣款", systemImage: "stop.circle")
        }
    }

    @ViewBuilder
    private func rowAccessibility(_ id: UUID) -> some View {
        Button("編輯") { actions.openExpense(id) }
        Button("停止扣款") { actions.stopExpense(id) }
    }

    private func moreButton(total: Int, pal: TripBoardPalette) -> some View {
        let title = showAll ? "收起" : "看全部 \(total) 件"
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

    private func maintenanceNote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }

    /// 稅費提示＋小綠鈕「＋ 記稅費」（付費在外殼 addLedger 擋）
    private func taxRow(_ text: String, pal: TripBoardPalette) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                actions.addLedger(.tax)
            } label: {
                FinanceGreenPill(title: "記稅費")
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel("記稅費")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// 「接下來」的一列：平常就是帳本列（FinanceLedgerRow）；保養超過預計時間時細字換成注意色「已經超過 40 天沒保養」
/// （FinanceLedgerRow 的細字固定灰色，這一種另外照它的尺寸排）
private struct VehicleUpcomingRowView: View {
    let row: VehicleUpcomingData.Row
    let pal: TripBoardPalette

    var body: some View {
        if let overdue = row.overdueText {
            overdueRow(overdue)
        } else {
            FinanceLedgerRow(dayText: row.dayText, monthText: row.monthText, glyph: row.mark.glyph,
                             markColor: VCColors.mark(row.mark, pal: pal), title: row.title, detail: row.detail,
                             amountText: row.amountText, accessibilityText: row.accessibilityText)
        }
    }

    private func overdueRow(_ overdue: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            dateBlock
            Text(row.mark.glyph)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(VCColors.mark(row.mark, pal: pal), in: Circle())
                .accessibilityHidden(true)
            texts(overdue)
            Spacer(minLength: 6)
            Text(row.amountText)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityText)
    }

    private var dateBlock: some View {
        VStack(spacing: 0) {
            Text(row.dayText)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .monospacedDigit()
            Text(row.monthText)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 52)
    }

    private func texts(_ overdue: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(overdue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MoneyTone.warn.color(pal))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

// MARK: - 車貸

/// 車貸區：右上「＋ 加一筆車貸」、格子、提示、兩句話、每筆一列、註腳。沒有任何車貸（含舊鏡像）時 data.loan 是 nil。
/// forExport：分享圖用，拿掉按鈕、提示、點選。
struct VehicleLoanSection: View {
    let data: VehicleCardData
    let actions: VehicleCardActions
    var forExport: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let s = data.loan {
            content(s, pal: TripBoardPalette(scheme))
        }
    }

    private func content(_ s: VehicleLoanSectionData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "車貸", trailing: VCText.nonEmpty(s.trailing))
            card(s, pal: pal)
        }
    }

    /// 分享圖不放「＋ 加一筆車貸」（J277 沒有因為已售出拿掉；帳本「＋ 記一筆」的「車貸」也一直都在）
    private var canAdd: Bool { !forExport }

    private func card(_ s: VehicleLoanSectionData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if canAdd {
                addRow
            }
            if let note = s.soldNote {
                soldNote(note, pal: pal)
            }
            if !s.tiles.isEmpty {
                FinanceTileGrid(tiles: s.tiles, pal: pal, onTap: tileTap)
            }
            if let hint = s.principalHint, !forExport {
                hintButton(hint, tap: s.principalHintTap, pal: pal)
            }
            sentences(s, pal: pal)
            rowsBlock(s, pal: pal)
            if let foot = s.footnote {
                Text(foot)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    /// 卡片右上一顆綠色膠囊「＋ 加一筆車貸」（付費在外殼 addLedger 擋）
    private var addRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                actions.addLedger(.carLoan)
            } label: {
                FinanceGreenPill(title: "加一筆車貸")
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityLabel("加一筆車貸")
        }
    }

    /// 「借款本金」格可以點（打開那筆車貸）；分享圖不能點
    private var tileTap: ((VehicleTile) -> Void)? {
        if forExport { return nil }
        let a = actions
        return { t in a.handle(t.tap) }
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

    /// 「在車貸那筆填上總貸款金額，就能算出還欠多少本金、付了多少利息 →」（字裡已經有箭頭）
    private func hintButton(_ text: String, tap: VehicleTap, pal: TripBoardPalette) -> some View {
        Button {
            actions.handle(tap)
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
        .accessibilityHint(VCText.hint(tap))
    }

    @ViewBuilder
    private func sentences(_ s: VehicleLoanSectionData, pal: TripBoardPalette) -> some View {
        if s.sellLine != nil || s.totalLine != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let line = s.sellLine {
                    FinanceSentence(line: line, pal: pal)
                }
                if let line = s.totalLine {
                    FinanceSentence(line: line, pal: pal)
                }
            }
        }
    }

    @ViewBuilder
    private func rowsBlock(_ s: VehicleLoanSectionData, pal: TripBoardPalette) -> some View {
        if !s.rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(s.rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 {
                        Divider().padding(.leading, 48)
                    }
                    rowItem(r, pal: pal)
                }
            }
        }
    }

    /// 點一下＝打開那筆車貸（舊鏡像捲到「要確認」）；長按＝編輯這筆／停止扣款／刪除這筆（付費、確認在外殼）。不做左滑、不做複製。
    @ViewBuilder
    private func rowItem(_ r: VehicleLoanSectionData.Row, pal: TripBoardPalette) -> some View {
        if forExport {
            VehicleLoanRowView(row: r, pal: pal)
        } else {
            switch r.source {
            case .expense(let id):
                rowButton(r, pal: pal)
                    .contextMenu {
                        rowMenu(r, expenseId: id)
                    }
                    .accessibilityLabel(r.accessibilityText)
                    .accessibilityActions {
                        rowAccessibility(r, expenseId: id)
                    }
            case .legacy:
                rowButton(r, pal: pal)
                    .accessibilityLabel(r.accessibilityText)
                    .accessibilityHint("點兩下捲到「要確認」")
            }
        }
    }

    private func rowButton(_ r: VehicleLoanSectionData.Row, pal: TripBoardPalette) -> some View {
        Button {
            open(r)
        } label: {
            VehicleLoanRowView(row: r, pal: pal)
        }
        .buttonStyle(MoneyPressStyle())
    }

    private func open(_ r: VehicleLoanSectionData.Row) {
        switch r.source {
        case .expense(let id):
            actions.openExpense(id)
        case .legacy:
            actions.scrollTo(.checks)
        }
    }

    @ViewBuilder
    private func rowMenu(_ r: VehicleLoanSectionData.Row, expenseId id: UUID) -> some View {
        Button {
            actions.openExpense(id)
        } label: {
            Label("編輯這筆", systemImage: "pencil")
        }
        if r.canStop {
            Button {
                actions.stopExpense(id)
            } label: {
                Label("停止扣款", systemImage: "stop.circle")
            }
        }
        Button(role: .destructive) {
            actions.deleteLoan(r)
        } label: {
            Label("刪除這筆", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func rowAccessibility(_ r: VehicleLoanSectionData.Row, expenseId id: UUID) -> some View {
        Button("編輯") { actions.openExpense(id) }
        if r.canStop {
            Button("停止扣款") { actions.stopExpense(id) }
        }
        Button("刪除") { actions.deleteLoan(r) }
    }
}

/// 車貸清單的一列（照房屋 HCSegmentRow）：28pt 狀態圓、標題、「2024/10 – 2029/9・60 期」、右邊每期金額、最下一行看狀態
private struct VehicleLoanRowView: View {
    let row: VehicleLoanSectionData.Row
    let pal: TripBoardPalette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VehicleLoanBadge(status: row.status, text: row.badge, pal: pal)
            details
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .foregroundStyle(Color.primary)
        .contentShape(Rectangle())
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
                FinanceMiniTag(text: "沒連到記帳", color: pal.label)
            }
            if row.termMissing {
                FinanceMiniTag(text: "期數沒填", color: MoneyTone.warn.color(pal))
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
                    .foregroundStyle(FinanceCardColors.payingBlue)
                if let f = row.progress {
                    FinanceThinBar(fraction: f, color: FinanceCardColors.payingBlue, track: pal.progressTrack)
                }
                if let next = row.nextText {
                    Text(next)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else if !row.isUnlinked {
            // 沒連到記帳的舊車貸：狀態字跟上面的灰色小標一樣，不重複寫
            Text(row.statusText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(row.status == .done ? MoneyTone.good.color(pal) : pal.label)
        }
    }
}

/// 車貸列左邊的圓：繳款中藍底白字、還沒開始（和沒連到記帳）灰框、已繳完綠勾、已停止（或賣出時結清）灰底
private struct VehicleLoanBadge: View {
    let status: VehicleLoanSectionData.Status
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

    private var outlined: Bool { status == .notStarted || status == .unlinked }

    private var fill: Color {
        switch status {
        case .paying: return FinanceCardColors.payingBlue
        case .done: return Color(tb: 0x1F9D57)
        case .stopped, .soldSettled: return VCColors.pick(0x7A86A8, 0x6D7EAB, pal)
        case .notStarted, .unlinked: return Color.clear
        }
    }

    private var stroke: Color {
        outlined ? VCColors.pick(0xC9D1E2, 0x5A6585, pal) : Color.clear
    }

    private var ink: Color {
        outlined ? pal.label : Color.white
    }
}

// MARK: - 充電／加油／油電

/// 充電（電車）／加油（油車、機車）／油電：格子、最近一次、提示、每度電價點圖、「充電與里程分析 ›」、註腳。
/// 完全沒有紀錄時縮成一行（＋ 記第一次…／都沒填度數 →）；電動機車沒有度數時 data.energy 是 nil。
struct VehicleEnergySection: View {
    let data: VehicleCardData
    let actions: VehicleCardActions

    @Environment(\.colorScheme) private var scheme
    /// 點圖手指正在按的日期（chartXSelection；放開就變回 nil）
    @State private var rawSelection: Date? = nil
    /// 最後點到的那一點：圖下說明換成它的字（放開後也留著）
    @State private var pickedId: UUID? = nil

    var body: some View {
        if let e = data.energy {
            content(e, pal: TripBoardPalette(scheme))
        }
    }

    private func content(_ e: VehicleEnergyData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: e.title, trailing: VCText.nonEmpty(e.trailing))
            card(e, pal: pal)
        }
    }

    @ViewBuilder
    private func card(_ e: VehicleEnergyData, pal: TripBoardPalette) -> some View {
        if let c = e.collapsed {
            collapsedCard(c, pal: pal)
        } else {
            fullCard(e, pal: pal)
        }
    }

    // MARK: 縮成一行

    @ViewBuilder
    private func collapsedCard(_ c: VehicleEnergyData.Collapsed, pal: TripBoardPalette) -> some View {
        switch c {
        case .addFirst(let text, let kind):
            Button {
                actions.addLedger(kind)
            } label: {
                collapsedLabel(text, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .modifier(FinanceCardChrome())
        case .missingKwh(let text, let expenseId):
            missingKwhCard(text, expenseId: expenseId, pal: pal)
        }
    }

    @ViewBuilder
    private func missingKwhCard(_ text: String, expenseId: UUID?, pal: TripBoardPalette) -> some View {
        if let id = expenseId {
            Button {
                actions.openExpense(id)
            } label: {
                collapsedLabel(text, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下打開那筆記帳")
            .modifier(FinanceCardChrome())
        } else {
            collapsedLabel(text, pal: pal)
                .modifier(FinanceCardChrome())
        }
    }

    private func collapsedLabel(_ text: String, pal: TripBoardPalette) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(pal.hint)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    // MARK: 整張卡

    private func fullCard(_ e: VehicleEnergyData, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(e.blocks.enumerated()), id: \.offset) { i, b in
                if i > 0 {
                    Divider()
                }
                blockView(b, pal: pal)
            }
            if e.showsAnalytics {
                analyticsButton(pal)
            }
            if let foot = e.footnote {
                Text(foot)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    private func blockView(_ b: VehicleEnergyData.Block, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let h = b.heading {
                Text(h)
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(pal.label)
                    .accessibilityAddTraits(.isHeader)
            }
            if !b.tiles.isEmpty {
                FinanceTileGrid(tiles: b.tiles, pal: pal, onTap: tileTap)
            }
            if let line = b.latestLine {
                Text(line)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 順序照 J303–317：①格子 ②最近一次 ③點圖 ④沒填度數 → ⑤還沒有家充紀錄
            if let chart = b.chart {
                chartBlock(chart, pal: pal)
            }
            if let pending = b.chartPending {
                Text(pending)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let hint = b.hint {
                hintRow(hint, tap: b.hintTap, pal: pal)
            }
            if let note = b.note {
                VCNoteRow(text: note, warn: false, pal: pal)
            }
        }
    }

    private var tileTap: ((VehicleTile) -> Void)? {
        let a = actions
        return { t in a.handle(t.tap) }
    }

    /// 「還有 2 筆電費沒填度數，沒算進每度電價 →」「加油時多記公升數…→」：點了打開那一筆（字裡已經有箭頭）
    @ViewBuilder
    private func hintRow(_ text: String, tap: VehicleTap, pal: TripBoardPalette) -> some View {
        if VCText.isTappable(tap) {
            Button {
                actions.handle(tap)
            } label: {
                hintLabel(text, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint(VCText.hint(tap))
        } else {
            hintLabel(text, pal: pal)
        }
    }

    private func hintLabel(_ text: String, pal: TripBoardPalette) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(pal.hint)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    // MARK: 每度電價點圖

    private func chartBlock(_ chart: VehicleEnergyData.Chart, pal: TripBoardPalette) -> some View {
        VStack(alignment: .center, spacing: 6) {
            VehicleChargeChart(chart: chart, pal: pal, selection: $rawSelection)
            chartLegend(chart, pal: pal)
            Text(caption(chart))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .onChange(of: rawSelection) { _, date in
            pick(date, in: chart.points)
        }
    }

    /// 家充藍圓、外面橘三角、平均虛線（沒設家充關鍵字時只有一種點）
    private func chartLegend(_ chart: VehicleEnergyData.Chart, pal: TripBoardPalette) -> some View {
        HStack(spacing: 12) {
            if chart.hasHomeKeyword {
                MoneyLegendItem(mark: .swatch, color: VCColors.chartHome(pal), text: "家充", pal: pal)
                MoneyLegendItem(mark: .swatch, color: VCColors.chartAway(pal), text: "外面", pal: pal)
            }
            MoneyLegendItem(mark: .dash, color: pal.label, text: "平均", pal: pal)
        }
        .accessibilityHidden(true)
    }

    private func caption(_ chart: VehicleEnergyData.Chart) -> String {
        guard let id = pickedId, let p = chart.points.first(where: { $0.id == id }) else { return chart.caption }
        return p.caption
    }

    /// 按到的日期落在哪一點：取日期最近的那一次充電
    private func pick(_ date: Date?, in points: [VehicleEnergyData.Point]) {
        guard let date else { return }
        let nearest = points.min { a, b in
            abs(a.date.timeIntervalSince(date)) < abs(b.date.timeIntervalSince(date))
        }
        guard let p = nearest, pickedId != p.id else { return }
        pickedId = p.id
    }

    /// 綠底列「充電與里程分析 ›」（免費）
    private func analyticsButton(_ pal: TripBoardPalette) -> some View {
        Button {
            actions.openAnalytics()
        } label: {
            HStack(spacing: 6) {
                Text("充電與里程分析")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(MoneyTone.good.color(pal))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color(tb: 0x1F9D57, 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityHint("點兩下打開充電與里程分析")
    }
}

/// 每度電價點圖（Swift Charts，高 120）：每次充電一點；有家充關鍵字時家充藍圓、外面橘三角（形狀也不同，色弱分得出來）；
/// 平均一條虛線。整張圖一個 VoiceOver 元素，唸 data 組好的摘要。
private struct VehicleChargeChart: View {
    let chart: VehicleEnergyData.Chart
    let pal: TripBoardPalette
    @Binding var selection: Date?

    var body: some View {
        plot
            .chartXSelection(value: $selection)
            .frame(height: 120)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chart.accessibilityText)
    }

    private var plot: some View {
        Chart {
            ForEach(chart.points) { p in
                point(p)
            }
            averageRule
        }
        .chartYScale(domain: 0...yTop)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(FinanceFormat.ym(d))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
    }

    @ChartContentBuilder
    private func point(_ p: VehicleEnergyData.Point) -> some ChartContent {
        PointMark(x: .value("日期", p.date), y: .value("每度", p.price))
            .foregroundStyle(color(p))
            .symbol(symbol(p))
            .symbolSize(44)
    }

    private var averageRule: some ChartContent {
        RuleMark(y: .value("平均", chart.average))
            .foregroundStyle(pal.label)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    /// 上面留兩成空白，最高那點不會貼著邊
    private var yTop: Double {
        let hi = chart.points.map { $0.price }.max() ?? 0
        return max(hi, chart.average, 1) * 1.2
    }

    /// 沒設家充關鍵字時分不出家充／外面，一律藍圓
    private func isAway(_ p: VehicleEnergyData.Point) -> Bool {
        chart.hasHomeKeyword && !p.isHome
    }

    private func color(_ p: VehicleEnergyData.Point) -> Color {
        isAway(p) ? VCColors.chartAway(pal) : VCColors.chartHome(pal)
    }

    private func symbol(_ p: VehicleEnergyData.Point) -> BasicChartSymbolShape {
        isAway(p) ? BasicChartSymbolShape.triangle : BasicChartSymbolShape.circle
    }
}

// MARK: - 我的帳本

/// 帳本卡 1（總表）：3×2 格、到今天總共付了、分段長條＋圖例、那一句。不含區塊標題（分享圖時單獨放一張）。
struct VehicleLedgerSummaryCard: View {
    let data: VehicleCardData
    let actions: VehicleCardActions
    var forExport: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let l = data.ledger
        VStack(alignment: .leading, spacing: 14) {
            FinanceTileGrid(tiles: tiles(l), pal: pal, onTap: tileTap)
            if !l.isEmpty {
                totals(l, pal: pal)
            }
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    /// 分享圖用 shareTiles（「定期」小字不寫你自己取的名稱，J494）；舊資料沒填時退回 tiles
    private func tiles(_ l: VehicleLedger) -> [VehicleTile] {
        if forExport && !l.shareTiles.isEmpty { return l.shareTiles }
        return l.tiles
    }

    /// 格子點了：買車、估值打開編輯頁；已繳車貸捲到車貸；其他切篩選並捲到紀錄。分享圖不能點
    private var tileTap: ((VehicleTile) -> Void)? {
        if forExport { return nil }
        let a = actions
        return { t in a.handle(t.tap) }
    }

    private func totals(_ l: VehicleLedger, pal: TripBoardPalette) -> some View {
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
            FinanceStackBar(parts: bars(l, pal: pal), height: 10, pal: pal)
            legend(l, pal: pal)
            if let line = l.spentLine {
                FinanceSentence(line: line, pal: pal)
            }
        }
    }

    /// 帳本的「油電」一律同一個名字，顏色照動力：電綠、油橘、油電青綠
    private var flavor: VehicleEnergyFlavor { VCColors.flavor(data.vehicle.powerType) }

    private func bars(_ l: VehicleLedger, pal: TripBoardPalette) -> [FinanceBarPart] {
        let f = flavor
        return l.parts.map { p in
            FinanceBarPart(id: p.bucket.rawValue, value: p.value, color: VCColors.bucket(p.bucket, flavor: f, pal: pal))
        }
    }

    /// 值 0 的段不寫圖例（長條本來就不畫它）
    private func legend(_ l: VehicleLedger, pal: TripBoardPalette) -> some View {
        let shown = l.parts.filter { $0.value > 0 }
        let f = flavor
        return ChipFlowLayout(spacing: 12) {
            ForEach(shown, id: \.id) { p in
                MoneyLegendItem(mark: .swatch, color: VCColors.bucket(p.bucket, flavor: f, pal: pal), text: p.legend, pal: pal)
            }
        }
    }
}

/// 帳本裡一列要怎麼畫（年份組頭、一筆紀錄、「再看 N 筆」）；攤平成一串才放得進 LazyVStack
private enum VCLedgerLine: Identifiable {
    case year(VehicleLedgerYear, expanded: Bool)
    case row(VehicleLedgerEvent, divider: Bool)
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
struct VehicleLedgerSection: View {
    let data: VehicleCardData
    @Binding var filter: VehicleLedgerFilter
    let actions: VehicleCardActions

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
            FinanceCardHeader(title: "我的帳本", trailing: VCText.nonEmpty(data.ledger.headerTrailing))
            VehicleLedgerSummaryCard(data: data, actions: actions)
            records(pal)
        }
    }

    // MARK: 卡 2

    private func records(_ pal: TripBoardPalette) -> some View {
        let ledger = data.ledger
        let lines = flatten(ledger.years(for: filter))
        return VStack(alignment: .leading, spacing: 0) {
            recordsTop(ledger)
            if ledger.isEmpty {
                // J433／樣稿②「剛建好的空車」：卡 2 只有「紀錄」＋「＋ 記一筆」和這一句（買車列已經在卡 1 的格子裡，不另列時間軸）
                emptyText(ledger.emptyHint ?? "")
            } else {
                filterRow(pal)
                if lines.isEmpty {
                    emptyText("這一類還沒有紀錄")
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines, id: \.id) { line in
                        lineView(line, pal: pal)
                    }
                }
            }
            Color.clear.frame(height: 8)
        }
        .modifier(FinanceCardChrome())
    }

    /// 「紀錄・38 筆」＋綠色「＋ 記一筆」選單（沒付費時是一顆普通按鈕）
    private func recordsTop(_ ledger: VehicleLedger) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(ledger.recordsTitle)
                .font(.subheadline.weight(.bold))
            Spacer(minLength: 8)
            addMenu(ledger.addKinds)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func addMenu(_ kinds: [VehicleLedgerAddKind]) -> some View {
        let a = actions
        return FinanceAddMenuPill(title: "記一筆", canEdit: a.canEdit, askPremium: a.askPremium) {
            ForEach(kinds, id: \.id) { kind in
                Button {
                    a.addLedger(kind)
                } label: {
                    Label(kind.title, systemImage: kind.icon)
                }
            }
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
    private static func showsChip(_ chip: VehicleLedgerFilterChip, current: VehicleLedgerFilter) -> Bool {
        if chip.filter == .all || chip.filter == current { return true }
        return chip.rowCount > 0
    }

    private func chipButton(_ chip: VehicleLedgerFilterChip, pal: TripBoardPalette) -> some View {
        let target = chip.filter
        return FinanceFilterChip(text: chip.text, on: target == filter, pal: pal, action: {
            withAnimation(.easeOut(duration: 0.25)) { filter = target }
        })
    }

    // MARK: 年份時間軸

    private func flatten(_ years: [VehicleLedgerYear]) -> [VCLedgerLine] {
        // 今年沒有紀錄（例如去年買的、今年還沒記）時，最新的那一年展開，免得整本都收著
        let anyCurrent = years.contains { $0.isCurrent }
        var out: [VCLedgerLine] = []
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
    private func lineView(_ line: VCLedgerLine, pal: TripBoardPalette) -> some View {
        switch line {
        case .year(let y, let expanded):
            FinanceYearHeader(title: y.title, expanded: expanded, pal: pal, action: {
                withAnimation(.easeOut(duration: 0.25)) { toggleYear(y.year) }
            })
        case .row(let e, let divider):
            VStack(spacing: 0) {
                if divider {
                    Divider().padding(.leading, 76)
                }
                ledgerRow(e, pal: pal)
            }
        case .more(let year, let hidden):
            FinanceMoreButton(hidden: hidden, pal: pal, action: {
                withAnimation(.easeOut(duration: 0.25)) { _ = moreYears.insert(year) }
            })
        }
    }

    private func toggleYear(_ year: Int) {
        if toggledYears.contains(year) {
            toggledYears.remove(year)
        } else {
            toggledYears.insert(year)
        }
    }

    /// 點一下＝打開（外殼依 source 決定開哪個編輯頁）；長按＝編輯／刪除。年列、買車列不能刪（canDelete）。
    /// 收據膠囊是列旁邊的另一顆按鈕（照水電表那一列，不包在列按鈕裡），點了看那筆的全部照片
    private func ledgerRow(_ e: VehicleLedgerEvent, pal: TripBoardPalette) -> some View {
        HStack(spacing: 8) {
            Button {
                actions.openLedger(e)
            } label: {
                VCLedgerRowFactory.row(e, forShare: false, hPadding: 0, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .contextMenu {
                rowMenu(e)
            }
            .accessibilityActions {
                rowAccessibility(e)
            }
            if !e.photoFileNames.isEmpty {
                receiptButton(e, pal: pal)
            }
        }
        .padding(.horizontal, 14)
    }

    private func receiptButton(_ e: VehicleLedgerEvent, pal: TripBoardPalette) -> some View {
        let count = e.photoFileNames.count
        return Button {
            actions.showPhotos(Self.draft(e))
        } label: {
            FinancePhotoBadge(count: count, pal: pal)
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel("看收據照片，\(count) 張")
    }

    /// 那一筆的全部收據照片
    private static func draft(_ e: VehicleLedgerEvent) -> CutePhotoDraft {
        let urls = e.photoFileNames.map { Expense.photoURL(for: $0) }
        return CutePhotoDraft(urls: urls, title: e.title, note: "", date: e.date, kind: .expense)
    }

    @ViewBuilder
    private func rowMenu(_ e: VehicleLedgerEvent) -> some View {
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
    private func rowAccessibility(_ e: VehicleLedgerEvent) -> some View {
        Button(Self.openTitle(e)) { actions.openLedger(e) }
        if e.canDelete {
            Button("刪除") { actions.deleteLedger(e) }
        }
    }

    /// 車貸年列點了是捲到車貸區、定期年列打開那一筆固定支出，選單字照做的事寫
    private static func openTitle(_ e: VehicleLedgerEvent) -> String {
        switch e.source {
        case .loanYear: return "看車貸"
        case .fixedYear: return "打開這筆"
        default: return "編輯"
        }
    }

    private static func openIcon(_ e: VehicleLedgerEvent) -> String {
        switch e.source {
        case .loanYear: return "banknote"
        case .fixedYear: return "doc.text"
        default: return "pencil"
        }
    }
}

/// 帳本的一列（分享圖逐筆也用它，所以只吃 event、不讀任何 EnvironmentObject）。
/// forShare：標題、細字改用 shareTitle／shareDetail（不輸出地點、自己取的名字、里程、備註）。收據膠囊不在這裡（卡片上是列旁邊另一顆按鈕）
struct VehicleLedgerRowView: View {
    let event: VehicleLedgerEvent
    var forShare: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VCLedgerRowFactory.row(event, forShare: forShare, hPadding: 14, pal: TripBoardPalette(scheme))
    }
}

/// 帳本 event → FinanceLedgerRow（卡片上的列和分享圖的列同一套對照）
@MainActor
private enum VCLedgerRowFactory {
    static func row(_ e: VehicleLedgerEvent, forShare: Bool, hPadding: CGFloat, pal: TripBoardPalette) -> FinanceLedgerRow {
        FinanceLedgerRow(dayText: e.dayText, monthText: e.monthText, glyph: e.mark.glyph,
                         markColor: VCColors.mark(e.mark, pal: pal),
                         title: forShare ? e.shareTitle : e.title,
                         detail: forShare ? e.shareDetail : e.detail,
                         amountText: e.amountText, tags: tags(e, pal: pal),
                         accessibilityText: e.accessibilityText, hPadding: hPadding)
    }

    /// 「沒連到記帳」灰色、「自備款不知道」注意色
    static func tags(_ e: VehicleLedgerEvent, pal: TripBoardPalette) -> [FinanceRowTag] {
        var out: [FinanceRowTag] = []
        if e.isUnlinked {
            out.append(FinanceRowTag(text: "沒連到記帳", color: pal.label))
        }
        if let w = e.warnTag {
            out.append(FinanceRowTag(text: w, color: MoneyTone.warn.color(pal)))
        }
        return out
    }
}

// MARK: - 車輛資料

/// 車輛資料：車子、動力、購入、估值（下一行行情參考＋「更新估值 ›」）、里程、家充地點、車主、售出、備註。
/// 永遠顯示，沒有值的列 VehicleCardData 已經不放；只有購入、估值兩列時下面加一行「補上品牌、車主、電池容量 → 編輯」。
/// 分享圖片不輸出這一區（車主、家充地點、里程、備註都在這裡）。
struct VehicleInfoSection: View {
    let data: VehicleCardData
    let actions: VehicleCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let info = data.info
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "車輛資料", trailing: VCText.nonEmpty(info.trailing))
            VStack(alignment: .leading, spacing: 0) {
                FinanceInfoRows(rows: infoRows(info, pal: pal))
                hintRow(info.hint, pal: pal)
            }
            .modifier(FinanceCardChrome())
        }
    }

    private func infoRows(_ info: VehicleInfoData, pal: TripBoardPalette) -> [FinanceInfoRows.Row] {
        info.rows.map { r in
            FinanceInfoRows.Row(id: r.id, content: rowView(r, pal: pal))
        }
    }

    private func rowView(_ r: VehicleInfoData.Row, pal: TripBoardPalette) -> AnyView {
        switch r.kind {
        case .plain:
            return AnyView(plainRow(r, pal: pal))
        case .warning:
            return AnyView(warningRow(r, pal: pal))
        case .note:
            return AnyView(noteRow(r))
        }
    }

    /// 能點的列（估值、電池、家充地點、售出）打開編輯頁捲到那一欄（付費在外殼擋）
    @ViewBuilder
    private func plainRow(_ r: VehicleInfoData.Row, pal: TripBoardPalette) -> some View {
        if VCText.isTappable(r.tap) {
            Button {
                actions.handle(r.tap)
            } label: {
                FinanceInfoRow(label: r.label, value: valueText(r, pal: pal), accessory: "chevron.right")
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint(VCText.hint(r.tap))
        } else {
            FinanceInfoRow(label: r.label, value: valueText(r, pal: pal))
        }
    }

    /// 值；估值列下面接一行灰字行情參考＋藍字「更新估值 ›」（同一列、同一顆按鈕）
    private func valueText(_ r: VehicleInfoData.Row, pal: TripBoardPalette) -> Text {
        let value = Text(r.value)
        guard let detail = r.detail else { return value }
        let note = Text(detail).font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
        guard let action = r.detailAction else { return Text("\(value)\n\(note)") }
        let link = Text(action).font(.caption).fontWeight(.bold).foregroundStyle(pal.hint)
        return Text("\(value)\n\(note)　\(link)")
    }

    @ViewBuilder
    private func warningRow(_ r: VehicleInfoData.Row, pal: TripBoardPalette) -> some View {
        if VCText.isTappable(r.tap) {
            Button {
                actions.handle(r.tap)
            } label: {
                warningLabel(r, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint(VCText.hint(r.tap))
        } else {
            warningLabel(r, pal: pal)
        }
    }

    private func warningLabel(_ r: VehicleInfoData.Row, pal: TripBoardPalette) -> some View {
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
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func noteRow(_ r: VehicleInfoData.Row) -> some View {
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

    /// 「補上品牌、車主、電池容量 → 編輯」（打開編輯頁捲到品牌）
    @ViewBuilder
    private func hintRow(_ hint: String?, pal: TripBoardPalette) -> some View {
        if let hint {
            Divider().padding(.leading, 14)
            Button {
                actions.edit(.brand)
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
}

// MARK: - 這個檔案裡共用的小零件

/// 白卡裡的一行提示：注意色（沒連到保險、買車不到一年）或灰字（晚開始記、還沒有家充紀錄）；
/// actionText 有值時後面接藍字（「＋ 記保險 →」，整行是一顆按鈕，按鈕在呼叫端包）
private struct VCNoteRow: View {
    let text: String
    let warn: Bool
    let pal: TripBoardPalette
    var actionText: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(iconInk)
            sentence
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.semibold))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 圖示跟著字色：灰字提示（晚開始記、還沒有家充紀錄）不掛注意色圖示，免得看起來像警告
    private var iconInk: Color {
        warn ? MoneyTone.warn.color(pal) : Color.secondary
    }

    private var sentence: Text {
        let ink: Color = warn ? MoneyTone.warn.color(pal) : Color.secondary
        let main = Text(text).foregroundStyle(ink)
        guard let actionText else { return main }
        let link = Text(actionText).foregroundStyle(pal.hint)
        return Text("\(main)\(link)")
    }
}

/// VehicleTap 的提示字、能不能點；空字串轉 nil（區塊標題右邊不寫）
private enum VCText {
    static func isTappable(_ tap: VehicleTap) -> Bool {
        if case .none = tap { return false }
        return true
    }

    /// VoiceOver 的提示（點了會去哪裡）
    static func hint(_ tap: VehicleTap) -> String {
        switch tap {
        case .none: return ""
        case .scrollTo(let anchor): return "點兩下捲到「\(anchorName(anchor))」"
        case .ledgerFilter(let f): return "點兩下在帳本只看「\(f.title)」"
        case .edit: return "點兩下打開編輯頁"
        case .openExpense: return "點兩下打開那筆記帳"
        case .openAnalytics: return "點兩下打開充電與里程分析"
        }
    }

    static func anchorName(_ a: VehicleAnchor) -> String {
        switch a {
        case .top: return "看板"
        case .checks: return "要確認"
        case .monthly: return "每月養車"
        case .upcoming: return "接下來"
        case .loan: return "車貸"
        case .energy: return "充電、加油"
        case .ledger: return "我的帳本"
        case .info: return "車輛資料"
        case .photos: return "照片與單據"
        }
    }

    static func nonEmpty(_ s: String) -> String? {
        s.isEmpty ? nil : s
    }
}

/// 載具卡片的顏色。淺色照樣稿（對白卡底至少 3:1）；深色另訂（對深色卡片底至少 3:1）。
/// 分類圓裡是白字，所以分類圓深淺色都不能太亮（白字也要 3:1）；長條、圖例、點圖只要對卡片底 3:1，深色可以調亮。
/// 用 SP/contrast.py 驗過（v540/c_contrast.py）。
private enum VCColors {
    static func pick(_ light: UInt32, _ dark: UInt32, _ pal: TripBoardPalette) -> Color {
        FinanceCardColors.pick(light, dark, pal)
    }

    /// 帳本 32pt 圓：購 6B4BE0、貸 2F7FE8、險 E0457A、稅 C9590F、訂 14A3A3、租 5B6CC9、固 7A86A8、油 DC7428、充 1F9D57、
    /// 停 8290B3、保 4F5BD5、修 2F9BD8、洗 0E8FA8、其 8891A7（停、其、油比樣稿深一點才有 3:1）。深色只把對深色底不到 4.5:1 的調亮
    static func mark(_ m: VehicleLedgerMark, pal: TripBoardPalette) -> Color {
        switch m {
        case .purchase: return pick(0x6B4BE0, 0x856BE5, pal)
        case .loan: return pick(0x2F7FE8, 0x2F7FE8, pal)
        case .insurance: return pick(0xE0457A, 0xE0457A, pal)
        case .tax: return pick(0xC9590F, 0xD05C0F, pal)
        case .subscription: return pick(0x14A3A3, 0x14A3A3, pal)
        case .rent: return pick(0x5B6CC9, 0x6979CE, pal)
        case .fixedOther: return pick(0x7A86A8, 0x7A86A8, pal)
        case .fuel: return pick(0xDC7428, 0xDC7428, pal)
        case .charge: return pick(0x1F9D57, 0x1F9D57, pal)
        case .parking: return pick(0x8290B3, 0x8290B3, pal)
        case .maintenance: return pick(0x4F5BD5, 0x6973DC, pal)
        case .repair: return pick(0x2F9BD8, 0x2F9BD8, pal)
        case .wash: return pick(0x0E8FA8, 0x0E8FA8, pal)
        case .other: return pick(0x8891A7, 0x8891A7, pal)
        }
    }

    /// 帳本「油電」的顏色照動力
    static func flavor(_ p: VehiclePowerType) -> VehicleEnergyFlavor {
        switch p {
        case .electric, .electricMotorcycle: return .electric
        case .gasoline, .motorcycle: return .fuel
        case .hybrid: return .mixed
        }
    }

    /// 能源：電綠、油橘、混合青綠
    static func energy(_ f: VehicleEnergyFlavor, pal: TripBoardPalette) -> Color {
        switch f {
        case .electric: return pick(0x1F9D57, 0x5BD99A, pal)
        case .fuel: return pick(0xDC7428, 0xFFA366, pal)
        case .mixed: return pick(0x14A3A3, 0x3FD0CF, pal)
        }
    }

    static func purple(_ pal: TripBoardPalette) -> Color { pick(0x6B4BE0, 0xB79CFF, pal) }
    static func fixed(_ pal: TripBoardPalette) -> Color { pick(0x6A7AA8, 0xA3B2D9, pal) }
    static func care(_ pal: TripBoardPalette) -> Color { pick(0x4F5BD5, 0x8F9BFF, pal) }
    static func other(_ pal: TripBoardPalette) -> Color { pick(0x8891A7, 0x7E879C, pal) }

    /// 帳本長條：買車紫、車貸藍（跟「貸」同色，免得跟保養的靛分不出來）、定期藍灰、油電照動力、保養・維修靛、停車・洗車・其他灰
    static func bucket(_ b: VehicleLedgerBucket, flavor: VehicleEnergyFlavor, pal: TripBoardPalette) -> Color {
        switch b {
        case .purchase: return purple(pal)
        case .loan: return pick(0x2F7FE8, 0x7DB2FF, pal)
        case .fixed: return fixed(pal)
        case .energy: return energy(flavor, pal: pal)
        case .care: return care(pal)
        case .other: return other(pal)
        }
    }

    /// 每月養車：利息琥珀（跟加油的橘分得開）、還本金／車貸紫、其他同帳本
    static func monthly(_ k: VehicleMonthlyData.Kind, flavor: VehicleEnergyFlavor, pal: TripBoardPalette) -> Color {
        switch k {
        case .interest: return pick(0xBF8000, 0xFFD166, pal)
        case .principal, .loan: return purple(pal)
        case .fixed: return fixed(pal)
        case .energy: return energy(flavor, pal: pal)
        case .care: return care(pal)
        case .other: return other(pal)
        }
    }

    /// 每度電價點圖：家充藍、外面橘
    static func chartHome(_ pal: TripBoardPalette) -> Color { pick(0x2F7FE8, 0x7DB2FF, pal) }
    static func chartAway(_ pal: TripBoardPalette) -> Color { pick(0xDC7428, 0xFFB866, pal) }
}
