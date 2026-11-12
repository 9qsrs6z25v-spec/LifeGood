//
//  UtilityTrendView.swift
//  LifeGood
//
//  [v25.621] 全頁「水電趨勢」（只有金額；judge_utility C12）。
//  - 資料全部在 UtilityTrendData.swift：HouseCardData.build 算好 UtilityTrendSource（全頁不重跑帳本），
//    這頁只在 .task(id: source) 與換選擇（onChange(of: picks)）時叫 UtilityTrendPage.build 算 @State screen；body 只讀 screen。
//  - 閃退規則：NavigationStack 裡只包一層 AnyView(scroller)；卡全部 fileprivate struct（不准泛型 card<Content>）；
//    圖沿用 UtilityTrendChart（height 200）；這頁不寫任何 store；改一期用自己的 sheet(item:)＋.appStores()。
//

import SwiftUI

/// 打開全頁（HouseSheet.utilityTrend）：每次新的 id；initialType＝小圖正在看的那一種
struct UtilityTrendRequest: Identifiable, Equatable {
    let id = UUID()
    let initialType: UtilityType?
}

/// 全頁打開一期：每次新的 id（同一期連點兩次也是新的 sheet）
struct UtilityEditTarget: Identifiable {
    let id = UUID()
    let estateId: UUID
    let payment: UtilityPayment
}

/// 全頁「水電趨勢」。外殼只管：選擇、算畫面（rebuild）、打開一期、付費、關閉
struct UtilityTrendView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let request: UtilityTrendRequest
    /// card?.utilities.trendSource；nil＝房子已經刪了（RealEstateDetailView 會把卡片清掉）
    let source: UtilityTrendSource?

    /// 全部的字與數字：只在 rebuild() 裡算
    @State private var screen: UtilityTrendScreen? = nil
    @State private var picks: UtilityTrendPicks
    /// 手指點到的那一期（UtilityTrendPoint.key）；rebuild 後不在了清掉（N7）
    @State private var pickedKey: String? = nil
    @State private var editing: UtilityEditTarget? = nil
    @State private var showPremium = false
    @State private var goneNotice = false

    init(request: UtilityTrendRequest, source: UtilityTrendSource?) {
        self.request = request
        self.source = source
        _picks = State(initialValue: UtilityTrendPicks(kind: request.initialType ?? .electricity, meterId: nil, allRange: false))
    }

    var body: some View {
        NavigationStack {
            AnyView(scroller)
        }
        .sheet(item: $editing) { t in
            UtilityPaymentEditor(estateId: t.estateId, editing: t.payment)
                .appStores()
        }
        .premiumLockAlert(isPresented: $showPremium)
        .alert("這一期已經在別台刪了", isPresented: $goneNotice) {
            Button("好", role: .cancel) {}
        } message: {
            Text("另一台裝置已經把這一期刪掉了，圖和列表會跟著更新。")
        }
        .task(id: source) { rebuild() }
        .onChange(of: picks) { _, _ in rebuild() }
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    private var navTitle: String { screen?.navTitle ?? "水電趨勢" }

    private var scroller: some View {
        ScrollView {
            content
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("關閉") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if source == nil {
            gone
        } else if let s = screen {
            page(s)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        }
    }

    /// 房子在別台被刪了（source == nil）：一行字＋關閉
    private var gone: some View {
        VStack(spacing: 14) {
            Text("這間房子已經刪了")
            Button("關閉") { dismiss() }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func page(_ s: UtilityTrendScreen) -> some View {
        // 一層 if 一張卡（不巢狀 if/else：AnyView(scroller) 那段 ≤ 14）；kinds 空的時 panel／detail／stats 都是 nil
        VStack(alignment: .leading, spacing: 18) {
            if let e = s.emptyText {
                Text(e)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !s.kinds.isEmpty {
                UTPickerBar(kinds: s.kinds, meters: s.meterChoices, quantityText: s.quantityText, picks: $picks)
            }
            if let p = s.panel {
                UTChartCard(panel: p, showsRangeToggle: s.showsRangeToggle, pal: pal,
                            allRange: $picks.allRange, pickedKey: $pickedKey)
            }
            if let d = s.detail(for: pickedKey) {
                UTDetailCard(detail: d, canEdit: subscription.isPremium, onOpen: open)
            }
            if let st = s.stats {
                UTStatsCard(stats: st)
            }
            if !s.payments.isEmpty {
                UTPaymentList(payments: s.payments, previewPayments: s.previewPayments, showAllTitle: s.showAllTitle,
                              trailing: s.paymentsTrailing, pal: pal, onOpen: open)
            }
            if !s.hints.isEmpty {
                UTHints(lines: s.hints)
            }
        }
        .padding(16)
    }

    /// 只有這裡算畫面（.task(id: source)、換選擇時）。不寫任何 store；FinanceStore 只讀房名（M2 那行）
    private func rebuild() {
        guard let src = source else {
            screen = nil
            return
        }
        var names: [UUID: String] = [:]
        for re in store.realEstates {
            names[re.id] = re.name
        }
        let s = UtilityTrendPage.build(src, picks: picks, estateNames: names, cal: Calendar.current)
        screen = s
        if let k = pickedKey, s.details[k] == nil {
            pickedKey = nil
        }
        if s.picks != picks {
            picks = s.picks
        }
    }

    /// 〔打開這一期〕、點列：先擋付費；打開那一刻用 paymentId 取「現在的」那一期（別台刪了就說）
    private func open(_ pid: UUID) {
        guard subscription.isPremium else {
            showPremium = true
            return
        }
        guard let src = source,
              let estate = store.realEstates.first(where: { $0.id == src.estateId }),
              let p = estate.utilityPayments.first(where: { $0.id == pid }) else {
            goneNotice = true
            return
        }
        editing = UtilityEditTarget(estateId: src.estateId, payment: p)
    }
}

// MARK: - 選擇列

/// 種類 segmented（Text，不放 Label）＋量（v2 只寫「金額」）＋兩個表以上才有表 Picker
fileprivate struct UTPickerBar: View {
    let kinds: [UtilityType]
    let meters: [UtilityMeterChoice]
    let quantityText: String
    @Binding var picks: UtilityTrendPicks

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("種類", selection: $picks.kind) {
                ForEach(kinds, id: \.self) { t in
                    Text(t.rawValue)
                        .tag(t)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                Text(quantityText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if meters.count >= 2 {
                    meterPicker
                }
            }
        }
    }

    private var meterPicker: some View {
        Picker("表", selection: $picks.meterId) {
            Text("全部的表")
                .tag(String?.none)
            ForEach(meters) { m in
                Text(m.name)
                    .tag(Optional(m.id))
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - 圖

/// 圖（UtilityTrendChart height 200）＋圖例＋說明行；資料超過 2 年右上角〔全部〕／〔近 2 年〕
fileprivate struct UTChartCard: View {
    let panel: UtilityTrendPanel
    let showsRangeToggle: Bool
    let pal: TripBoardPalette
    @Binding var allRange: Bool
    @Binding var pickedKey: String?

    private var rangeTitle: String { allRange ? "近 2 年" : "全部" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(panel.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if showsRangeToggle {
                    rangeButton
                }
            }
            chartArea(panel)
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    private var rangeButton: some View {
        Button(rangeTitle) { allRange.toggle() }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    @ViewBuilder
    private func chartArea(_ p: UtilityTrendPanel) -> some View {
        if let chart = p.chart {
            UtilityTrendChart(chart: chart, pal: pal, height: 200, pickedKey: $pickedKey)
            if !p.legend.isEmpty {
                UtilityTrendLegend(rows: p.legend, type: p.type, pal: pal)
            }
            Text(p.caption(for: pickedKey))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            // 超過 3 個表（只在「全部的表」）：「還有 1 個表沒畫」（跟小圖同一句）
            if let n = p.hiddenMeterNote {
                Text(n)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        } else {
            Text(p.pending ?? p.defaultCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let h = p.pendingHint {
                Text(h)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 這一期

/// 點到的那期（沒點是最近一期）：「9/20 繳」NT$1,590、約每月、比較、表、收據；〔打開這一期〕要付費
fileprivate struct UTDetailCard: View {
    let detail: UtilityTrendDetail
    let canEdit: Bool
    let onOpen: (UUID) -> Void

    private var lockIcon: String { canEdit ? "square.and.pencil" : "lock.fill" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "這一期")
            content(detail)
        }
    }

    private func content(_ d: UtilityTrendDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(d.head)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(d.amountText)
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(d.line)
            ForEach(d.facts) { f in
                UTStatRow(line: f)
            }
            footer(d)
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    @ViewBuilder
    private func footer(_ d: UtilityTrendDetail) -> some View {
        if let pid = d.paymentId {
            Button {
                onOpen(pid)
            } label: {
                Label("打開這一期（看收據、修改）", systemImage: lockIcon)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        } else if let n = d.sourceNote {
            Text(n)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// 兩欄一列（明細、統計共用）
fileprivate struct UTStatRow: View {
    let line: UtilityStatLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(line.value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 近 12 個月

/// 近 12 個月：合計（N 期）、每期平均、最高、最低；每年合計那一行（或兩個完整年度以上的「全年」）
fileprivate struct UTStatsCard: View {
    let stats: UtilityTrendStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: stats.title)
            content(stats)
        }
    }

    private func content(_ s: UtilityTrendStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = s.emptyText {
                Text(e)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(s.lines) { l in
                UTStatRow(line: l)
            }
            if let n = s.yearNote {
                Text(n)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !s.years.isEmpty {
                Divider()
                ForEach(s.years) { l in
                    UTStatRow(line: l)
                }
            }
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }
}

// MARK: - 全部繳費

/// 新到舊、全部種類；先列 24 筆＋「看全部 N 筆」，展開用 LazyVStack。分隔線在這裡畫（列 struct 少一層）
fileprivate struct UTPaymentList: View {
    let payments: [UtilityPaymentLine]
    let previewPayments: [UtilityPaymentLine]
    let showAllTitle: String?
    let trailing: String
    let pal: TripBoardPalette
    let onOpen: (UUID) -> Void
    @State private var expanded = false

    private var shown: [UtilityPaymentLine] { expanded ? payments : previewPayments }
    private var moreTitle: String? { expanded ? nil : showAllTitle }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "全部繳費", trailing: trailing)
            VStack(spacing: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { l in
                        if l.divider {
                            Divider()
                                .padding(.leading, 14)
                        }
                        UTPaymentRow(line: l, pal: pal, onOpen: onOpen)
                    }
                }
                if let t = moreTitle {
                    Divider()
                    Button {
                        expanded = true
                    } label: {
                        Text(t)
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(MoneyPressStyle())
                }
            }
            .modifier(FinanceCardChrome())
        }
    }
}

/// 一列：「2026/11/10・電費」、小字（表、在記帳記的）、收據圖示、金額；房子水電那一期才是按鈕
fileprivate struct UTPaymentRow: View {
    let line: UtilityPaymentLine
    let pal: TripBoardPalette
    let onOpen: (UUID) -> Void

    var body: some View {
        if let pid = line.paymentId {
            Button {
                onOpen(pid)
            } label: {
                label
            }
            .buttonStyle(MoneyPressStyle())
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.ink)
                if let sub = line.subText {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if line.photoCount > 0 {
                Image(systemName: "photo.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(line.amountText)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(pal.ink)
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityText)
    }
}

// MARK: - 頁尾灰字

/// 有才出現、每條一行灰字（固定支出、出租、賣出、M1、M2、S4b、週期改變）
fileprivate struct UTHints: View {
    let lines: [UtilityHintLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { h in
                Text(h.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
