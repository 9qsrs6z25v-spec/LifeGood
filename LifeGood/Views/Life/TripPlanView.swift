import SwiftUI
import MapKit
import PhotosUI
import UIKit

// MARK: - 旅遊規劃
//
// [v25.399] 旅遊地圖底部「旅遊規劃」進來的地方。
//
// 三層：行程清單 → 行程時間軸 → 景點編輯。
// 路線距離與時間由 TripRouter 算好存進 TripStop（見那邊的快取說明），
// 所以時間軸重繪不會反覆打 MapKit，離線也看得到上次算過的結果。

/// 跨天行程的分色。
///
/// 第一天沿用旅遊地圖的娛樂紫（整個旅遊模組的主題色），之後每天換一個色系；
/// 超過六天就循環——顏色是用來分段的，不是用來當天數編號的。
enum TripDayPalette {
    static let colors: [Color] = [
        Color(red: 0.68, green: 0.40, blue: 1.00),   // 娛樂紫
        Color(red: 0.00, green: 0.66, blue: 0.62),   // 青
        Color(red: 1.00, green: 0.55, blue: 0.20),   // 橘
        Color(red: 0.93, green: 0.35, blue: 0.55),   // 桃紅
        Color(red: 0.30, green: 0.58, blue: 0.95),   // 藍
        Color(red: 0.42, green: 0.70, blue: 0.28)    // 綠
    ]

    static func color(_ dayIndex: Int) -> Color {
        guard !colors.isEmpty else { return .purple }
        let i = ((dayIndex % colors.count) + colors.count) % colors.count
        return colors[i]
    }
}

struct TripPlanListView: View {
    @EnvironmentObject var lifeStore: LifeStore
    /// 只是為了往下傳給詳細頁（相本要看關聯支出的照片）——
    /// sheet 雖然會繼承環境，但這裡本來就一個一個明著傳，跟著慣例走
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss
    /// [v25.454] 點旅遊的跨裝置通知進來時要打開的那一份行程
    @ObservedObject private var deepLink = DeepLinkRouter.shared

    private let accent = TripDayPalette.color(0)   // 沿用旅遊地圖的娛樂紫

    @State private var openPlanId: UUID?
    @State private var removing: TripPlan?
    @State private var sharing: SharePlanText?

    private struct SharePlanText: Identifiable {
        let id = UUID()
        let text: String
    }
    /// 剛用＋開出來、還沒填任何東西的行程 id。
    /// 不能在 onDismiss 才讀 openPlanId——sheet 關閉時綁定已經先被設成 nil 了。
    @State private var freshPlanId: UUID?

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d (E) HH:mm"; return f
    }()

    private var plans: [TripPlan] {
        lifeStore.tripPlans.sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if plans.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(plans) { plan in
                            planRow(plan)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("旅遊規劃")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newPlan() } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(accent)
                    }
                }
            }
            .sheet(item: Binding(
                get: { openPlanId.map { IDBox(id: $0) } },
                set: { openPlanId = $0?.id }
            ), onDismiss: { discardIfBlank() }) { box in
                TripPlanDetailView(planId: box.id)
                    .environmentObject(lifeStore)
                    .environmentObject(expenseStore)
            }
            .sheet(item: $sharing) { item in
                ShareSheet(items: [item.text])
            }
            .confirmationDialog("刪除行程", isPresented: Binding(
                get: { removing != nil }, set: { if !$0 { removing = nil } }
            ), titleVisibility: .visible, presenting: removing) { plan in
                Button("刪除「\(plan.displayTitle)」", role: .destructive) {
                    lifeStore.deleteTripPlan(id: plan.id)
                    removing = nil
                }
                Button("取消", role: .cancel) { removing = nil }
            } message: { plan in
                Text("這份行程的 \(plan.stops.count) 個景點與所有照片都會一起刪掉，沒辦法復原。")
            }
            // [v25.454] 點旅遊的跨裝置通知進來：直接開到那一份行程。
            // onAppear 接 sheet 剛掀開的情況，onChange 接清單已經開著時又來一則通知。
            .onAppear { openPendingPlan() }
            .onChange(of: deepLink.pendingTripPlanId) { _, _ in openPendingPlan() }
        }
    }

    /// 取走待開的行程 id。找不到那份行程（已被刪掉）就什麼都不做，
    /// 但一樣要取走——留著的話下次進這一頁又會試一次。
    private func openPendingPlan() {
        guard let id = deepLink.takeTripPlan() else { return }
        guard lifeStore.tripPlans.contains(where: { $0.id == id }) else { return }
        // 比照 planRow：這不是剛用＋開出來的空白行程，別讓關閉時的 discardIfBlank 誤刪
        freshPlanId = nil
        openPlanId = id
    }

    private func newPlan() {
        // 預設出發時間用排程時段（整點/半點，過 18:00 則隔天 09:30），與全 App 一致
        let plan = TripPlan(startDate: FiveMinuteDateTimePicker.defaultSchedulingTime())
        lifeStore.upsertTripPlan(plan)
        freshPlanId = plan.id
        openPlanId = plan.id
    }

    /// 剛開的行程如果一個景點、標題、備註都沒有，關掉時就收掉，
    /// 不要在清單上留一排「未命名行程」。有填任何東西就保留。
    private func discardIfBlank() {
        guard let id = freshPlanId else { return }
        freshPlanId = nil
        guard let p = lifeStore.tripPlan(id: id) else { return }
        guard p.stops.isEmpty,
              p.title.trimmingCharacters(in: .whitespaces).isEmpty,
              p.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lifeStore.deleteTripPlan(id: id)
    }

    private func planRow(_ plan: TripPlan) -> some View {
        Button {
            freshPlanId = nil
            openPlanId = plan.id
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.08)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: "map.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(Self.dayFmt.string(from: plan.startDate))
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(planMeta(plan))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { removing = plan } label: {
                Label("刪除", systemImage: "trash")
            }
            Button {
                sharing = SharePlanText(text: TripShare.planText(plan))
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            .tint(.indigo)
        }
    }

    /// 字串在 ViewBuilder 外組好
    private func planMeta(_ plan: TripPlan) -> String {
        var parts = ["\(plan.stops.count) 站"]
        if plan.dayCount > 1 { parts.append("\(plan.dayCount) 天") }
        if plan.overnightCount > 0 { parts.append("住宿 \(plan.overnightCount) 晚") }
        if plan.mustVisitCount > 0 { parts.append("必去 \(plan.mustVisitCount)") }
        parts.append(plan.travelMode.rawValue)
        if plan.totalMeters > 0 { parts.append(TripRouter.distanceText(plan.totalMeters)) }
        if plan.totalSeconds > 0 { parts.append("全程 " + TripRouter.durationText(plan.totalSeconds)) }
        return parts.joined(separator: "・")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                Image(systemName: "map")
                    .font(.system(size: 30, weight: .medium)).foregroundStyle(accent)
            }
            Text("還沒有行程").font(.headline)
            Text("按右上的＋開一份行程，加入景點與停留時間，\n系統會自動排出時間軸並算出每段路的距離與時間。")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 行程時間軸

struct TripPlanDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    /// [v25.424] 相本要把「掛在這趟旅遊上的變動支出」照片也收進來
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let planId: UUID

    private let accent = TripDayPalette.color(0)

    @State private var editingStop: TripStop?
    /// 要插在哪個位置（nil＝加在最後）
    /// 新增景點要插在哪個位置。
    ///
    /// ⚠️ 刻意走 .sheet(item:) 而不是 .sheet(isPresented:) 搭一個另外的 @State 位置。
    ///    v25.399～25.405 是後者，結果「在這之後插入景點」每次都插到最後面：
    ///    sheet 的 content 閉包在讀位置時，拿到的是**寫入生效前**的那份快照
    ///    （按下按鈕那一刻兩個 @State 一起寫，開關那個生效了、位置那個還沒），
    ///    於是 insertAt 一律是 nil，也就是「加在最後」。
    ///    把位置放進 item 裡，它就跟 presentation 綁在同一次寫入，不可能讀到舊的。
    private struct StopInsertion: Identifiable {
        let id = UUID()
        /// nil＝加在最後
        let at: Int?
    }
    @State private var insertion: StopInsertion?
    /// 點路段打開的那一段的位置（index＝目的地那一站）
    @State private var legDetail: LegBox?
    /// 要分享的文字。一樣走 .sheet(item:)，內容跟著 item 一起進去
    @State private var sharing: ShareText?
    /// [v25.441] 分享這一站的圖片
    @State private var sharingStopImage: ShareStopImage?
    @State private var isExportingStop = false

    struct ShareStopImage: Identifiable {
        let id = UUID()
        let url: URL
    }
    @State private var showImageExport = false
    @State private var showAlbum = false
    /// [v25.451] 行前準備清單（要帶去的／要帶回來的）
    @State private var showChecklist = false
    /// 打開景點卡的那一站
    @State private var openingStopId: UUID?
    @State private var viewingPhoto: IdentifiableURL?

    private struct LegBox: Identifiable {
        let id = UUID()
        let index: Int
    }
    private struct ShareText: Identifiable {
        let id = UUID()
        let text: String
    }
    @State private var showSettings = false
    @State private var isRouting = false
    @State private var removingStop: TripStop?
    @State private var showMap = false

    init(planId: UUID) {
        self.planId = planId
    }

    private var plan: TripPlan? { lifeStore.tripPlan(id: planId) }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"; return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"; return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if let p = plan {
                    ScrollView {
                        VStack(spacing: 14) {
                            summaryCard(p)
                            if p.stops.isEmpty {
                                emptyStops
                            } else {
                                timelineCard(p)
                            }
                            if p.stops.contains(where: { !$0.photoFileNames.isEmpty }) {
                                albumButton(p)
                            }
                            // [v25.464] 這趟的花費。使用者回報：記了幾筆花費，
                            // 旅遊規劃項目裡完全看不到。
                            expenseCard(p)
                            addButton(p)
                            // Apple 規定：顯示了 WeatherKit 的資料就必須標示出處
                            if showsAnyWeather(p) {
                                WeatherAttributionRow()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical)
                    }
                } else {
                    // 行程在別處被刪掉了
                    Color.clear.onAppear { dismiss() }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(plan?.displayTitle ?? "行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if (plan?.stops.count ?? 0) >= 2 {
                        Button { showMap = true } label: {
                            Image(systemName: "map").foregroundStyle(accent)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let p = plan, !p.stops.isEmpty {
                        Menu {
                            Button {
                                sharing = ShareText(text: TripShare.planText(p))
                            } label: {
                                Label("分享文字行程", systemImage: "text.alignleft")
                            }
                            Button {
                                showImageExport = true
                            } label: {
                                Label("分享成圖片…", systemImage: "photo")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(accent)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("設定") { showSettings = true }.bold()
                }
            }
            .sheet(isPresented: $showSettings) {
                if let p = plan {
                    TripPlanSettingsSheet(plan: p).environmentObject(lifeStore)
                }
            }
            .sheet(item: $insertion) { ins in
                TripStopEditorSheet(planId: planId, editing: nil, insertAt: ins.at)
                    .environmentObject(lifeStore)
            }
            .sheet(item: $editingStop) { stop in
                TripStopEditorSheet(planId: planId, editing: stop, insertAt: nil)
                    .environmentObject(lifeStore)
            }
            .sheet(isPresented: $showMap) {
                if let p = plan {
                    TripRouteMapSheet(plan: p).environmentObject(lifeStore)
                }
            }
            .sheet(item: $legDetail) { box in
                if let p = plan {
                    TripLegDetailSheet(plan: p, index: box.index)
                        .environmentObject(lifeStore)
                }
            }
            .sheet(item: $sharing) { item in
                ShareSheet(items: [item.text])
            }
            .sheet(item: $sharingStopImage) { item in
                ShareSheet(items: [item.url])
            }
            .sheet(isPresented: $showImageExport) {
                if let p = plan { TripPlanImageExportSheet(plan: p) }
            }
            .sheet(isPresented: $showChecklist) {
                TripChecklistSheet(planId: planId)
                    .environmentObject(lifeStore)
            }
            .sheet(isPresented: $showAlbum) {
                if let p = plan {
                    // 共用地圖相簿模板（旅遊／美食／醫療地圖與兒女相簿都是它）
                    MapAlbumSheet(
                        title: p.displayTitle + " 的相本",
                        accent: accent,
                        emptyTitle: "這趟還沒有照片",
                        emptyHint: "在景點編輯裡加照片，這裡就會依景點分組整理成相本；記帳時把變動支出關聯到這趟旅遊，那些照片也會一起進來。",
                        groupNoun: "景點",
                        items: albumItems(p))
                }
            }
            .sheet(item: $viewingPhoto) { wrapper in
                PhotoLightbox(url: wrapper.url)
            }
            .sheet(item: Binding(
                get: { openingStopId.map { IDBox(id: $0) } },
                set: { openingStopId = $0?.id }
            )) { box in
                TripStopCardView(planId: planId, stopId: box.id)
                    .environmentObject(lifeStore)
                    .environmentObject(expenseStore)
            }
            .confirmationDialog("刪除景點", isPresented: Binding(
                get: { removingStop != nil }, set: { if !$0 { removingStop = nil } }
            ), titleVisibility: .visible, presenting: removingStop) { stop in
                Button("刪除「\(stop.displayName)」", role: .destructive) {
                    lifeStore.deleteTripStop(planId: planId, stopId: stop.id)
                    removingStop = nil
                }
                Button("取消", role: .cancel) { removingStop = nil }
            } message: { stop in
                Text(stop.photoFileNames.isEmpty
                     ? "後面幾站的時間會跟著往前移。"
                     : "這一站的 \(stop.photoFileNames.count) 張照片會一起刪掉，後面幾站的時間會跟著往前移。")
            }
            // 進來就把缺的路線補齊；只算指紋對不上的段落，所以不會每次都整條重打
            .task(id: routeTaskKey) { await recalculate() }
        }
    }

    /// 觸發重算的條件指紋：站的順序／座標／交通方式任一改變就重跑。
    /// 各段自己指定的交通方式也要算進來——只改某一段的方式時，
    /// 行程預設值沒變，漏掉就不會重算那一段。
    private var routeTaskKey: String {
        guard let p = plan else { return "-" }
        return p.travelMode.rawValue + "|" + p.stops.map { s in
            let c = (s.latitude.map { String(format: "%.5f", $0) } ?? "-")
                + "," + (s.longitude.map { String(format: "%.5f", $0) } ?? "-")
            return s.id.uuidString.prefix(8) + ":" + c
                + ":" + (s.legModeOverride?.rawValue ?? "-")
        }.joined(separator: ";")
    }

    /// 把「暫時要不到真實路線」的段落清掉重算。
    /// 不能只清快取就等 .task 自己跑——那個的觸發條件是站的順序／座標／交通方式，
    /// 清快取不會讓它改變，所以這裡自己叫一次。
    @MainActor
    private func retryRouting() async {
        lifeStore.retryTripPlanRouting(planId: planId)
        await recalculate()
    }

    @MainActor
    private func recalculate() async {
        guard var p = plan, p.stops.count >= 2 else { return }
        isRouting = true
        defer { isRouting = false }
        let changed = await TripRouter.fillMissingLegs(&p)
        // 算的期間使用者可能又改了行程（插了一站、改了座標）。
        // 直接覆蓋會把那些改動吃掉，所以寫回前先確認指紋還是同一份。
        guard changed, let live = plan,
              live.stops.map(\.id) == p.stops.map(\.id),
              live.stops.map(\.legModeOverride) == p.stops.map(\.legModeOverride),
              live.travelMode == p.travelMode else { return }
        lifeStore.upsertTripPlan(p)
    }

    // MARK: 摘要

    private func summaryCard(_ p: TripPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryHeader(p)
            summaryKpiPanel(p)
            let chips = summaryChips(p)
            if !chips.isEmpty {
                // 會自動換行的版面，擠不下時不會被切掉或折字
                ChipFlowLayout(spacing: 6) {
                    ForEach(chips) { chip in summaryChip(chip) }
                }
            }
            if p.dayCount > 1 { dayLegend(p) }
            summaryNotices(p)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        // 共用英雄卡殼層：漸層、散景圓、玻璃光澤、圓角與光暈都走同一套，
        // 也才能在「設定 › 進階設定 › 卡片設定 › 英雄卡樣式」裡逐卡調整
        .heroCardShell(card: .tripPlan)
        .padding(.horizontal, 16)
    }

    /// [v25.451] 摘要卡右上角那顆。
    ///
    /// 原本只是一塊顯示交通方式的死膠囊，點了沒反應。改成「行前準備」的入口，
    /// 但交通方式仍然留著——那是這張卡上唯一會寫出預設交通方式的地方，
    /// 拿掉等於把一個資訊換成一個功能。所以兩個並存：左邊照舊是交通方式，
    /// 右邊接一個清單圖示與進度，整顆可按。
    private func checklistButton(_ p: TripPlan) -> some View {
        let progress = p.checklistTotalProgress
        return Button {
            showChecklist = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: p.travelMode.icon).font(.system(size: 10, weight: .bold))
                Text(p.travelMode.rawValue).font(.caption.weight(.semibold)).lineLimit(1)
                Rectangle().fill(.white.opacity(0.35))
                    .frame(width: 0.75, height: 11)
                Image(systemName: "checklist").font(.system(size: 10, weight: .bold))
                if progress.total > 0 {
                    Text("\(progress.done)/\(progress.total)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                }
            }
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(.white.opacity(0.22))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 摘要卡：標頭

    private func summaryHeader(_ p: TripPlan) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dayFmt.string(from: p.startDate) + " 出發")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.80))
                Text(p.stops.isEmpty ? "尚未加入景點"
                     : Self.timeFmt.string(from: p.startDate) + " – "
                       + Self.timeFmt.string(from: p.endDate))
                    .heroBigValueFont()
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                // 只寫 14:40 – 15:29 的話，跨天行程看起來像當天來回
                if p.dayCount > 1 && !p.stops.isEmpty {
                    Text("跨 \(p.dayCount) 天，" + Self.dayFmt.string(from: p.endDate) + " 結束")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.80))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 8)
            checklistButton(p)
            .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))
            .foregroundStyle(.white)
        }
    }

    // MARK: 摘要卡：數字

    private struct SummaryMetric: Identifiable {
        /// 同時當標題與識別
        let id: String
        let value: String
        let icon: String
    }

    /// 數字欄位。
    ///
    /// 排成每列三格的面板而不是一列全部攤開：一列塞五、六個時，
    /// 「15 小時 57 分」與「3136.4 km」這種長字串會直接貼在一起看不出分界。
    /// 格與格之間用英雄卡標準的 HeroKpiDivider 隔開。
    private func summaryMetrics(_ p: TripPlan) -> [SummaryMetric] {
        var out: [SummaryMetric] = [
            SummaryMetric(id: "景點", value: "\(p.stops.count) 站",
                          icon: "mappin.and.ellipse")
        ]
        if p.dayCount > 1 {
            out.append(SummaryMetric(id: "天數", value: "\(p.dayCount) 天", icon: "calendar"))
        }
        if p.overnightCount > 0 {
            out.append(SummaryMetric(id: "住宿", value: "\(p.overnightCount) 晚",
                                     icon: "bed.double.fill"))
        }
        // 停留原本直接顯示分鐘數（例：2100 分），到了幾十小時就沒人讀得出來
        out.append(SummaryMetric(
            id: "停留",
            value: p.totalDwellMinutes > 0
                ? TripRouter.durationText(Double(p.totalDwellMinutes) * 60) : "—",
            icon: "clock"))
        out.append(SummaryMetric(
            id: "交通",
            value: p.totalTravelSeconds > 0
                ? TripRouter.durationText(p.totalTravelSeconds) : "—",
            icon: "arrow.triangle.turn.up.right.diamond.fill"))
        out.append(SummaryMetric(
            id: "距離",
            value: p.totalMeters > 0 ? TripRouter.distanceText(p.totalMeters) : "—",
            icon: "ruler"))
        return out
    }

    private func summaryKpiPanel(_ p: TripPlan) -> some View {
        let metrics = summaryMetrics(p)
        return VStack(spacing: 8) {
            summaryKpiRow(Array(metrics.prefix(3)))
            if metrics.count > 3 {
                Rectangle().fill(.white.opacity(0.18))
                    .frame(height: 0.5).padding(.horizontal, 10)
                summaryKpiRow(Array(metrics.dropFirst(3)))
            }
        }
        .padding(.vertical, 10)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// 一列三格。不足三格時補上空白，第二列才會跟第一列切齊。
    private func summaryKpiRow(_ metrics: [SummaryMetric]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 { HeroKpiDivider() }
                HeroKpiCell(label: metric.id, value: metric.value, icon: metric.icon)
            }
            if metrics.count < 3 {
                ForEach(0..<(3 - metrics.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
    }

    // MARK: 摘要卡：標記膠囊

    private struct SummaryChip: Identifiable {
        let id: String
        let icon: String
        let text: String
    }

    /// 交通方式組成與必去標記。住宿改放進上面的數字格子，這裡不重複。
    private func summaryChips(_ p: TripPlan) -> [SummaryChip] {
        var out: [SummaryChip] = []
        if p.hasModeOverride {
            for item in p.modeSegmentCounts {
                out.append(SummaryChip(id: "mode-" + item.mode.rawValue,
                                       icon: item.mode.icon,
                                       text: item.mode.rawValue + " \(item.count) 段"))
            }
        }
        if p.mustVisitCount > 0 {
            out.append(SummaryChip(id: "must", icon: "star.fill",
                                   text: "必去 \(p.mustVisitCount) 站"))
        }
        // 開始打卡之後就顯示進度，沒打卡的行程不用看到這個
        if p.checkedOutCount > 0 {
            out.append(SummaryChip(id: "done", icon: "checkmark.circle.fill",
                                   text: "已完成 \(p.checkedOutCount)/\(p.stops.count) 站"))
        }
        if let currentId = p.currentStopId,
           let here = p.stops.first(where: { $0.id == currentId }) {
            out.append(SummaryChip(id: "here", icon: "mappin.circle.fill",
                                   text: "現在在「" + here.displayName + "」"))
        }
        // [v25.424] 掛在這趟上的變動支出。
        // [v25.466] 原本只加 currencyCode == "NT$" 的那些，理由寫的是「外幣要換算匯率」
        // ——那是誤解：非儲蓄險的支出存檔時就已經用設定裡的匯率換算成台幣了，
        // currencyCode 只記錄當初輸入的幣別。按它篩等於把一筆早就換算好的日圓消費
        // 整筆丟掉，合計因此少算。改走 ExpenseStore.ntdTotal（規則集中在那裡）。
        let linked = expenseStore.expenses.filter { $0.linkedTripPlanId == p.id }
        if expenseStore.ntdTotal(linked) > 0 {
            out.append(SummaryChip(id: "spent", icon: "creditcard.fill",
                                   text: "花費 " + expenseStore.ntdTotalText(linked)))
        }
        return out
    }

    private func summaryChip(_ chip: SummaryChip) -> some View {
        HStack(spacing: 4) {
            Image(systemName: chip.icon).font(.system(size: 9))
            Text(chip.text).font(.system(size: 10, weight: .bold)).lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.white.opacity(0.18), in: Capsule())
    }

    // MARK: 花費（v25.464）

    /// 這趟的花費。
    ///
    /// 在此之前，支出與旅遊的關聯只體現在兩個地方：摘要卡上一顆「花費 NT$x」膠囊、
    /// 以及相本會收進支出的照片。花費本身**從來沒有被列出來過**——使用者記了幾筆，
    /// 回到行程裡什麼也看不到，只能回記帳頁翻。
    ///
    /// 另一半的問題是關聯本身很難發現：記帳表單的「關聯旅遊」只在**進階模式**才出現
    /// （v25.425 的決定，基本模式刻意只留金額/分類/日期），所以用基本模式記的花費
    /// 永遠不會掛上任何一趟。那條路不該改——基本模式的簡潔是它存在的理由——
    /// 改成從旅遊這一端補：把「日期落在這趟期間、但還沒關聯」的花費列出來，一鍵掛上。
    ///
    /// 刻意**不自動**把期間內的花費算進這趟：旅行期間在家附近的加油、網購、房貸
    /// 都落在同一段日期裡，自動歸戶會算出一個錯的旅費。要掛哪幾筆由使用者決定。
    @ViewBuilder
    private func expenseCard(_ p: TripPlan) -> some View {
        let linked = linkedExpenses(p)
        let candidates = candidateExpenses(p)
        if !linked.isEmpty || !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("這趟的花費")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    if !linked.isEmpty {
                        Text(expenseStore.ntdTotalText(linked))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(accent)
                    }
                }

                if linked.isEmpty {
                    Text("還沒有花費掛在這趟上。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(linked) { e in
                        expenseRow(e, plan: p)
                    }
                }

                if !candidates.isEmpty {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                        Text("期間內還有 \(candidates.count) 筆花費沒掛上這趟")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        Spacer()
                        Button("全部掛上") { linkAll(candidates, to: p) }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                    }
                    ForEach(candidates) { e in
                        candidateRow(e)
                    }
                    Text(Self.candidateFootnote)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    /// [v25.465] 指定算在某一站的花費。
    ///
    /// 只算「明確指定了這一站」的，沒指定站別的（記帳表單裡選「整趟（不指定）」）
    /// 不會被攤到任何一站——那是使用者刻意沒分配的，硬塞進某一站只是猜。
    private func stopExpenses(_ stopId: UUID) -> [Expense] {
        expenseStore.expenses.filter {
            $0.linkedTripPlanId == planId && $0.linkedTripStopId == stopId
        }
    }

    /// 這一站的花費金額文字；沒有花費就回 nil（不要在時間欄留一個 NT$0）。
    /// 只有金額、不帶「花費」兩個字——時間欄只有 52pt 寬，前綴會把數字擠到看不清楚。
    private func stopSpendAmount(_ stopId: UUID) -> String? {
        let list = stopExpenses(stopId)
        guard !list.isEmpty, expenseStore.ntdTotal(list) > 0 else { return nil }
        return expenseStore.ntdTotalText(list)
    }

    /// 說明一次寫成單一字串常數，不要在 Text(...) 裡用 + 串接
    private static let candidateFootnote =
        "只列日期落在這趟期間內的變動支出。旅行期間在家附近的加油、網購也會落在"
        + "同一段日期裡，所以不自動掛——要算進這趟的才按＋。"
        + "要移除已經掛上的，到記帳頁編輯那一筆把「關聯旅遊」改掉。"

    /// 掛在這趟上的花費（新到舊）
    private func linkedExpenses(_ p: TripPlan) -> [Expense] {
        expenseStore.expenses
            .filter { $0.linkedTripPlanId == p.id }
            .sorted { $0.date > $1.date }
    }

    /// 日期落在這趟期間、但還沒關聯任何旅遊的變動支出。
    /// 規則與記帳表單的「關聯旅遊」選單一致（AddExpenseView.tripCandidates）。
    private func candidateExpenses(_ p: TripPlan) -> [Expense] {
        let cal = Calendar.current
        let from = cal.startOfDay(for: p.startDate)
        let to = cal.startOfDay(for: p.endDate)
        return expenseStore.expenses
            .filter { e in
                guard e.expenseType == .variable, e.linkedTripPlanId == nil else { return false }
                let day = cal.startOfDay(for: e.date)
                return day >= from && day <= to
            }
            .sorted { $0.date > $1.date }
    }

    private func expenseRow(_ e: Expense, plan: TripPlan) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title.isEmpty ? (e.variableCategory?.rawValue ?? "花費") : e.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Self.dayFmt.string(from: e.date))
                        .font(.caption2).foregroundStyle(.secondary)
                    if let c = e.variableCategory {
                        Text(c.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(accent)
                    }
                    if let sid = e.linkedTripStopId,
                       let stop = plan.stops.first(where: { $0.id == sid }) {
                        Text(stop.displayName)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !e.photoFileNames.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "photo").font(.system(size: 8))
                            Text("\(e.photoFileNames.count)")
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 4)
            // [v25.466] 外幣顯示當初輸入的原幣金額（存檔的 amount 已是台幣等值，
            // 要除回去才是使用者打的數字）。規則集中在 ExpenseStore。
            Text(expenseStore.displayAmountText(e))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
        }
    }

    private func candidateRow(_ e: Expense) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title.isEmpty ? (e.variableCategory?.rawValue ?? "花費") : e.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(Self.dayFmt.string(from: e.date)
                     + (e.variableCategory.map { " · " + $0.rawValue } ?? ""))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Text(expenseStore.displayAmountText(e))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Button {
                link(e, to: planId)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18)).foregroundStyle(accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func link(_ e: Expense, to tripId: UUID) {
        var updated = e
        updated.linkedTripPlanId = tripId
        expenseStore.update(updated)
    }

    private func linkAll(_ list: [Expense], to p: TripPlan) {
        for e in list { link(e, to: p.id) }
    }

    // MARK: 摘要卡：提醒

    /// 進度與警告。統一成「圖示 + 一段文字」的排法，不要每一條各長一個樣子。
    @ViewBuilder
    private func summaryNotices(_ p: TripPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isRouting {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).tint(.white)
                    Text("正在計算路線…")
                        .font(.caption2).foregroundStyle(.white.opacity(0.9))
                }
            } else if p.unroutedLegCount > 0 {
                summaryNotice(icon: "hourglass",
                              text: "有 \(p.unroutedLegCount) 段還沒算出路線")
            }
            if p.retryableLegCount > 0 {
                Button {
                    Task { await retryRouting() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .bold))
                        Text("有 \(p.retryableLegCount) 段沒拿到真實路線，點這裡重新計算")
                            .font(.caption2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if p.unreachableCount > 0 {
                summaryNotice(icon: "exclamationmark.triangle.fill",
                              text: "有 \(p.unreachableCount) 站的指定抵達時間比推算的還早，照這個排法趕不上")
            } else if p.totalIdleSeconds > 300 {
                summaryNotice(icon: "hourglass.bottomhalf.filled",
                              text: "為了等指定時間，中間空著 "
                                  + TripRouter.durationText(p.totalIdleSeconds))
            }
            // [v25.435] 天氣預報只有十天。整趟都還太遠時在這裡講一次就好——
            // 每一站各掛一句「太遠了」只是噪音。
            if weatherOutOfRange(p) {
                summaryNotice(icon: "calendar.badge.clock",
                              text: "天氣預報只有未來 \(TripWeatherStore.forecastDays) 天，這趟還太遠，所以景點上還看不到天氣")
            }
        }
    }

    /// 這趟有沒有任何一站真的顯示得出天氣
    private func showsAnyWeather(_ p: TripPlan) -> Bool {
        p.timeline.contains {
            $0.stop.coordinate != nil && TripWeatherStore.isWithinForecastRange($0.arrival)
        }
    }

    /// 整趟沒有任何一天在預報範圍內
    private func weatherOutOfRange(_ p: TripPlan) -> Bool {
        let slots = p.timeline
        guard !slots.isEmpty,
              slots.contains(where: { $0.stop.coordinate != nil }) else { return false }
        return !slots.contains { TripWeatherStore.isWithinForecastRange($0.arrival) }
    }

    private func summaryNotice(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 12)
            Text(text)
                .font(.caption2).foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    /// 跨天時在摘要卡底下放一條色帶，說明哪個顏色是第幾天
    private func dayLegend(_ p: TripPlan) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<p.dayCount, id: \.self) { d in
                    HStack(spacing: 4) {
                        Circle().fill(TripDayPalette.color(d))
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 0.75))
                        Text(Self.dayLabel(p, dayIndex: d))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                    }
                    .fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.white.opacity(0.16), in: Capsule())
                }
            }
            .padding(.vertical, 1)
        }
        .scrollEdgeFade(width: 14)
    }

    /// 這一天是幾月幾號（星期幾）。字串在 ViewBuilder 外組好。
    private static func dayDateText(_ p: TripPlan, dayIndex: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: dayIndex,
                                         to: p.startDate) ?? p.startDate
        return dayFmt.string(from: date)
    }

    /// 「第 2 天 8/20 (三)」
    private static func dayLabel(_ p: TripPlan, dayIndex: Int) -> String {
        "第 \(dayIndex + 1) 天 " + dayDateText(p, dayIndex: dayIndex)
    }

    /// 離開時間。跨過午夜就加「翌」，否則 09:00 看起來像同一天早上就走了。
    private static func departureText(_ slot: TripPlan.Slot) -> String {
        let t = timeFmt.string(from: slot.departure)
        return Calendar.current.isDate(slot.departure, inSameDayAs: slot.arrival)
            ? t : "翌 " + t
    }

    // MARK: 時間軸

    private func timelineCard(_ p: TripPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                Text("時間軸").font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            let slots = p.timeline
            // 用手上這份 slots 判斷，不要再叫 p.dayCount——那個會把整條時間軸重算一次
            let multiDay = (slots.map(\.dayIndex).max() ?? 0) > 0
            ForEach(slots) { slot in
                // 換日就先插一列日期標頭（只有跨天行程才需要）
                if multiDay && slot.dayIndex != (slot.index == 0 ? -1 : slots[slot.index - 1].dayIndex) {
                    dayHeaderRow(p, dayIndex: slot.dayIndex, isFirst: slot.index == 0)
                }
                // 前一站是過夜的地方 → 它同時也是這一天的第一站，在新的一天開頭再出現一次
                if slot.index > 0, slots[slot.index - 1].stop.isOvernight {
                    overnightResumeRow(slots[slot.index - 1], dayIndex: slot.dayIndex)
                }
                // 第一站前面沒有路段；其餘每一站上面先畫「從上一站過來」那一條
                if slot.index > 0 {
                    legRow(slot, plan: p)
                }
                stopRow(slot)
            }
            Spacer().frame(height: 6)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    /// 換日的分隔列。跨天行程一天一個色系，這一列把顏色與日期講明白。
    private func dayHeaderRow(_ p: TripPlan, dayIndex: Int, isFirst: Bool) -> some View {
        let c = TripDayPalette.color(dayIndex)
        return HStack(spacing: 8) {
            Text("第 \(dayIndex + 1) 天")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(c, in: Capsule())
            Text(Self.dayDateText(p, dayIndex: dayIndex))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c)
            Rectangle().fill(c.opacity(0.22)).frame(height: 0.75)
        }
        .padding(.horizontal, 16)
        .padding(.top, isFirst ? 2 : 10)
        .padding(.bottom, 4)
    }

    /// 時間軸左邊那一欄的寬度。
    ///
    /// [v25.440] 從 42 加寬到 52。指定抵達時間的站會在時間前面多一個鎖，
    /// 42 放不下「🔒 12:40」，於是被折成「12:4 / 0」——一個時間被拆成兩行，
    /// 掃時間軸時特別刺眼。
    ///
    /// ⚠️ 景點列、住宿接續列、路段列三個地方都要用同一個值：連接線與圓點
    ///    靠它對齊在一條垂直線上，改一個沒改另外兩個，整條軸就歪了。
    private static let timeColumnWidth: CGFloat = 52

    /// 住宿的地方在隔天開頭再出現一次：它是當天最後一站，也是隔天的第一站。
    /// 這一列不是另一個景點，只是把「早上從這裡出發」講清楚，所以刻意做得比景點列輕。
    private func overnightResumeRow(_ slot: TripPlan.Slot, dayIndex: Int) -> some View {
        let c = TripDayPalette.color(dayIndex)
        return HStack(alignment: .center, spacing: 10) {
            Text(Self.timeFmt.string(from: slot.departure))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(c)
                .frame(width: Self.timeColumnWidth)
            Image(systemName: "bed.double.fill")
                .font(.system(size: 10)).foregroundStyle(c)
            Text("從「" + slot.stop.displayName + "」出發")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                editingStop = slot.stop
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 13)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(c.opacity(0.05))
    }

    /// 兩站之間的那一段路。點「＋」就從這裡插一站進去。
    private func legRow(_ slot: TripPlan.Slot, plan p: TripPlan) -> some View {
        let c = TripDayPalette.color(slot.dayIndex)
        return HStack(spacing: 10) {
            // 對齊上下的時間欄寬度，讓連接線與圓點在一條垂直線上
            Text("").frame(width: Self.timeColumnWidth)
            Rectangle().fill(c.opacity(0.28))
                .frame(width: 1.5, height: 26)
            HStack(spacing: 5) {
                Image(systemName: slot.mode.icon).font(.system(size: 9, weight: .bold))
                // 這一段被單獨指定過方式就把名稱寫出來，跟預設的那些區分開
                if slot.isModeOverridden {
                    Text(slot.mode.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(c.opacity(0.14)).foregroundStyle(c)
                        .clipShape(Capsule())
                }
                Text(legText(slot)).font(.system(size: 10, weight: .semibold))
                if slot.isEstimated {
                    Text("估").font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.18)).foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                // 指定抵達時間造成的空檔／趕不上，標在路段上（問題出在這一段路）
                if slot.shortfallSeconds > 60 {
                    Text("差 " + TripRouter.durationText(slot.shortfallSeconds) + " 趕不上")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.red.opacity(0.14)).foregroundStyle(.red)
                        .clipShape(Capsule())
                } else if slot.idleSeconds > 300 {
                    Text("等 " + TripRouter.durationText(slot.idleSeconds))
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(.secondary)
            // 這一段可以點開看地圖與真實路線
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Button {
                insertion = StopInsertion(at: slot.index)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14)).foregroundStyle(c)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        // ＋ 那顆自己吃掉點擊，所以整列可點不會跟它打架
        .contentShape(Rectangle())
        .onTapGesture { legDetail = LegBox(index: slot.index) }
    }

    private func legText(_ slot: TripPlan.Slot) -> String {
        guard let secs = slot.travelSeconds else { return "未計算路線" }
        var t = TripRouter.durationText(secs)
        if let m = slot.travelMeters { t += "・" + TripRouter.distanceText(m) }
        return t
    }

    /// 一站。用既有的 ItemRow 模板畫——子地點就是它的摺疊區。
    private func stopRow(_ slot: TripPlan.Slot) -> some View {
        let c = TripDayPalette.color(slot.dayIndex)
        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    // 指定抵達時間的站加一個鎖，跟推算出來的時間區分開
                    if slot.isFixedArrival {
                        Image(systemName: "lock.fill").font(.system(size: 7, weight: .bold))
                    }
                    Text(Self.timeFmt.string(from: slot.arrival))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                // 時間是一個整體，寧可整體縮一點也不要被折成兩行
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(slot.shortfallSeconds > 60 ? Color.red : c)
                Text(Self.departureText(slot))
                    .font(.system(size: 10, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.tertiary)
                // 打卡過的時間是事實，跟排出來的預估分開標示
                if slot.isActualArrival || slot.isActualDeparture {
                    Text("實際")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(c, in: Capsule())
                }
                // [v25.468] 這一站的花費（使用者指定放這裡）。
                //
                // v25.465 原本做成膠囊混在標題上方那一排裡，但那一排講的是「時間與
                // 狀態」（第幾天、指定抵達、必去、比預估早到…），金額擠在中間要找。
                // 時間欄本來就是「這一站的數字」那一欄，花費放這裡一眼就對得起來。
                //
                // 欄寬只有 52pt，所以不寫「花費」兩個字、只放金額，再讓它自己縮。
                if let text = stopSpendAmount(slot.stop.id) {
                    Text(text)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(.green)
                        .padding(.top, 1)
                }
            }
            .frame(width: Self.timeColumnWidth)

            ItemRow(
                chips: stopChips(slot),
                title: slot.stop.displayName,
                preview: stopPreview(slot.stop),
                disclosures: subSpotDisclosures(slot.stop),
                disclosureLabel: "子地點",
                disclosureColor: c,
                // 天氣與照片直接鋪在這一站底下，不用點進去才看得到
                extra: stopExtra(slot),
                // 點整列＝打開景點卡。要去地圖、要編輯、要打卡都在卡片上選——
                // 直接開地圖的話，其他事情就全被擠進「…」選單裡了（v25.421 的教訓）。
                onTap: { openingStopId = slot.stop.id },
                leading: {
                    HStack(spacing: 6) {
                        if showsCheckIn(slot) { checkInButton(slot) }
                        ZStack(alignment: .topTrailing) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [c.opacity(0.9), c.opacity(0.5)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .frame(width: 22, height: 22)
                                Text("\(slot.index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            if slot.stop.isMustVisit {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                                    .padding(1.5)
                                    .background(Circle().fill(Color(.systemBackground)))
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .frame(width: 22, height: 22)
                    }
                },
                accessory: {
                    Menu {
                        Button("打開景點卡") { openingStopId = slot.stop.id }
                        Button("編輯") { editingStop = slot.stop }
                        if slot.stop.checkInState != .notArrived {
                            if slot.stop.actualDwellSeconds != nil {
                                Button("把實際停留寫回預計") {
                                    lifeStore.adoptActualDwell(planId: planId,
                                                               stopId: slot.stop.id)
                                }
                            }
                            Button("清除打卡紀錄") {
                                lifeStore.clearTripStopCheckIn(planId: planId,
                                                               stopId: slot.stop.id)
                            }
                        }
                        Button(slot.stop.isMustVisit ? "取消必去" : "標為必去") {
                            toggleMustVisit(slot.stop.id)
                        }
                        if slot.index > 0 {
                            Menu("這一段怎麼過來") {
                                Button("用行程預設（" + (plan?.travelMode ?? .driving).rawValue + "）") {
                                    setLegMode(slot.stop.id, nil)
                                }
                                ForEach(TripTravelMode.allCases) { m in
                                    Button(m.rawValue) { setLegMode(slot.stop.id, m) }
                                }
                            }
                        }
                        Button("在這之後插入景點") {
                            insertion = StopInsertion(at: slot.index + 1)
                        }
                        Divider()
                        if slot.index > 0 {
                            Button("往前移一站") { move(slot.index, by: -1) }
                        }
                        if slot.index < (plan?.stops.count ?? 0) - 1 {
                            Button("往後移一站") { move(slot.index, by: 1) }
                        }
                        Divider()
                        Button("用 Apple 地圖開啟") { TripShare.openPlaceInMaps(slot.stop) }
                        Button("分享這一站（圖片）") {
                            Task { await shareStopImage(slot.stop) }
                        }
                        Button("分享這一站（文字）") { shareStop(slot.stop) }
                        if !slot.stop.address.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("拷貝地址") {
                                UIPasteboard.general.string =
                                    slot.stop.address.trimmingCharacters(in: .whitespaces)
                            }
                        }
                        Divider()
                        Button("刪除", role: .destructive) { removingStop = slot.stop }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }
            )
        }
        .padding(.horizontal, 16)
    }

    /// 一站底下的照片。橫捲、點開全螢幕看。
    private func photoStrip(_ stop: TripStop) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(stop.photoFileNames, id: \.self) { name in
                    Button {
                        viewingPhoto = IdentifiableURL(url: TripStop.photoURL(name))
                    } label: {
                        AsyncThumbnailView(url: TripStop.photoURL(name),
                                           size: CGSize(width: 76, height: 58))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollEdgeFade(width: 12)
    }

    /// 整趟的相本入口。放在時間軸底下而不是工具列：
    /// 相本是「回頭看」的東西，跟排行程的工具不該擠在同一排。
    private func albumButton(_ p: TripPlan) -> some View {
        // 相本裡看得到幾張就寫幾張——關聯支出的照片也算進來，
        // 不然按鈕寫 8 張、點進去 14 張，只會讓人以為壞了
        let count = albumItems(p).count
        return Button {
            showAlbum = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.08)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                    Image(systemName: "photo.stack")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("這趟的相本")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(count) 張照片・依景點分組，點開看大圖")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    /// 相本要吃的資料。分組字串帶上「第幾天」，依景點分組出來就是照日子與順序排好的。
    private func albumItems(_ p: TripPlan) -> [AlbumPhotoItem] {
        // timeline 是每次取用都重算的，先取一次——下面查站別的分組還要用
        let slots = p.timeline
        var items = slots.flatMap { slot in
            slot.stop.photoFileNames.map { name in
                AlbumPhotoItem(
                    id: name,
                    url: TripStop.photoURL(name),
                    group: (p.dayCount > 1 ? "第 \(slot.dayIndex + 1) 天・" : "")
                        + slot.stop.displayName,
                    date: slot.arrival)
            }
        }
        // [v25.424] 掛在這趟旅遊上的變動支出照片。
        //
        // 檔案照舊留在支出那邊（這裡只是多一個看得到的入口），所以相本裡刪不掉它們——
        // 旅行時拍的收據、餐點、門票跟景點照片本來就是同一批回憶，只是各自有各自的家。
        let indexOfStop = Dictionary(uniqueKeysWithValues:
            p.stops.enumerated().map { ($0.element.id, $0.offset) })
        for e in expenseStore.expenses where e.linkedTripPlanId == p.id {
            guard !e.photoFileNames.isEmpty else { continue }
            let group: String
            if let sid = e.linkedTripStopId, let i = indexOfStop[sid], slots.indices.contains(i) {
                group = (p.dayCount > 1 ? "第 \(slots[i].dayIndex + 1) 天・" : "")
                    + p.stops[i].displayName
            } else {
                group = "旅途中的花費"
            }
            for name in e.photoFileNames {
                items.append(AlbumPhotoItem(
                    // 檔名前面加記號：支出與景點的照片存在不同資料夾，
                    // 萬一撞名，相本的 id 不能跟著撞
                    id: "expense-" + name,
                    url: Expense.photoURL(for: name),
                    group: group,
                    date: e.date))
            }
        }
        return items
    }

    /// 這一站要不要顯示打卡方塊。
    ///
    /// 只在「今天或已經過去的日子」出現：整趟七天二十幾站全部掛一顆方塊只是雜訊，
    /// 而且會讓人以為現在就該按。已經打過卡的一律顯示（才收得回去）。
    private func showsCheckIn(_ slot: TripPlan.Slot) -> Bool {
        if slot.stop.checkInState != .notArrived { return true }
        return Calendar.current.startOfDay(for: slot.arrival)
            <= Calendar.current.startOfDay(for: Date())
    }

    /// 打卡方塊：沒到 → 我到了 → 玩完了 → 回到沒到。
    private func checkInButton(_ slot: TripPlan.Slot) -> some View {
        let c = TripDayPalette.color(slot.dayIndex)
        let state = slot.stop.checkInState
        return Button {
            lifeStore.advanceTripStopCheckIn(planId: planId, stopId: slot.stop.id)
        } label: {
            ZStack {
                Circle()
                    .stroke(state == .notArrived ? Color.secondary.opacity(0.5) : c,
                            lineWidth: 1.6)
                    .frame(width: 22, height: 22)
                switch state {
                case .notArrived:
                    EmptyView()
                case .arrived:
                    // 人在這裡：實心點，跟「已完成」的勾區分開
                    Circle().fill(c).frame(width: 10, height: 10)
                case .departed:
                    Circle().fill(c).frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// 這一站底下要鋪什麼：天氣預報、照片。兩者都沒有就回 nil，不留空位。
    ///
    /// [v25.435] 天氣放在這裡而不是塞進上面的膠囊列：膠囊列是「這一站是什麼」
    /// （第幾天、必去、停留多久），天氣是「那天會怎樣」，兩件事。
    private func stopExtra(_ slot: TripPlan.Slot) -> AnyView? {
        let hasPhotos = !slot.stop.photoFileNames.isEmpty
        let hasWeather = slot.stop.coordinate != nil
            && TripWeatherStore.isWithinForecastRange(slot.arrival)
        guard hasPhotos || hasWeather else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                if hasWeather {
                    // 時間軸是緊湊版，不寫來源那一行——那裡一眼掃過去就好
                    TripWeatherChip(coordinate: slot.stop.coordinate, date: slot.arrival)
                }
                if hasPhotos { photoStrip(slot.stop) }
            }
        )
    }

    private func stopChips(_ slot: TripPlan.Slot) -> [ItemChip] {
        let c = TripDayPalette.color(slot.dayIndex)
        var chips: [ItemChip] = []
        if slot.dayIndex > 0 {
            chips.append(ItemChip(id: "day", text: "第 \(slot.dayIndex + 1) 天",
                                  color: c, icon: "sun.horizon"))
        }
        if slot.isFixedArrival {
            chips.append(ItemChip(id: "fixed",
                                  text: "指定 " + Self.timeFmt.string(from: slot.arrival) + " 抵達",
                                  color: c, icon: "lock.fill"))
        }
        if slot.index == 0 {
            // 第一站前面沒有算過的路段：出發時間到指定抵達之間就是去第一站的路上
            if slot.shortfallSeconds > 60 {
                chips.append(ItemChip(id: "late", text: "指定的時間比出發時間還早",
                                      color: .red, icon: "exclamationmark.triangle.fill"))
            } else if slot.idleSeconds > 60 {
                chips.append(ItemChip(id: "idle",
                                      text: "出發後 " + TripRouter.durationText(slot.idleSeconds) + " 抵達",
                                      color: .secondary, icon: "car.fill"))
            }
        } else if slot.shortfallSeconds > 60 {
            chips.append(ItemChip(id: "late",
                                  text: "推算 " + Self.timeFmt.string(from: slot.estimatedArrival ?? slot.arrival)
                                        + " 才到，差 " + TripRouter.durationText(slot.shortfallSeconds),
                                  color: .red, icon: "exclamationmark.triangle.fill"))
        } else if slot.idleSeconds > 300 {
            chips.append(ItemChip(id: "idle",
                                  text: "比預計早到，空 " + TripRouter.durationText(slot.idleSeconds),
                                  color: .secondary, icon: "hourglass"))
        }
        if slot.stop.isMustVisit {
            chips.append(ItemChip(id: "must", text: "必去", color: .orange, icon: "star.fill"))
        }
        // 打卡之後就用事實說話：實際停留多久、比原本排的早到還是晚到
        if let actual = slot.stop.actualDwellSeconds {
            let planned = Double(max(0, slot.stop.dwellMinutes)) * 60
            var text = "實際停留 " + TripRouter.durationText(actual)
            if planned > 0, abs(actual - planned) >= 300 {
                text += actual > planned
                    ? "（多 " + TripRouter.durationText(actual - planned) + "）"
                    : "（少 " + TripRouter.durationText(planned - actual) + "）"
            }
            chips.append(ItemChip(id: "actualDwell", text: text, color: c, icon: "checkmark.circle.fill"))
        } else if slot.isActualArrival {
            chips.append(ItemChip(id: "here",
                                  text: "已抵達 " + Self.timeFmt.string(from: slot.arrival),
                                  color: c, icon: "mappin.circle.fill"))
        }
        if slot.isActualArrival {
            // 比的是「照前面實際發生的事推算，這一站本來會幾點到」，
            // 所以它衡量的是這一段路＋上一站有沒有拖到，不是整趟累積的落差
            let delta = slot.arrival.timeIntervalSince(slot.plannedArrival)
            if abs(delta) >= 300 {
                chips.append(ItemChip(
                    id: "delta",
                    text: delta > 0
                        ? "比預估晚 " + TripRouter.durationText(delta)
                        : "比預估早 " + TripRouter.durationText(-delta),
                    color: delta > 0 ? .orange : .green,
                    icon: delta > 0 ? "arrow.down.right" : "arrow.up.right"))
            }
        }
        if slot.stop.isOvernight {
            chips.append(ItemChip(id: "night",
                                  text: "過夜・隔天 " + Self.timeFmt.string(from: slot.departure) + " 出發",
                                  color: .indigo, icon: "bed.double.fill"))
        } else {
            chips.append(ItemChip(id: "dwell", text: "停留 \(slot.stop.dwellMinutes) 分",
                                  color: c, icon: "clock"))
        }
        if !slot.stop.photoFileNames.isEmpty {
            chips.append(ItemChip(id: "photo", text: "\(slot.stop.photoFileNames.count) 張",
                                  color: .indigo, icon: "photo"))
        }
        if !slot.stop.subSpots.isEmpty {
            chips.append(ItemChip(id: "sub", text: "子地點 \(slot.stop.subSpots.count)",
                                  color: .teal, icon: "mappin.and.ellipse"))
        }
        if slot.stop.coordinate == nil {
            chips.append(ItemChip(id: "nocoord", text: "未設座標", color: .orange,
                                  icon: "exclamationmark.triangle.fill"))
        }
        // 子地點的分鐘加起來超過母景點的停留時間 → 排程對不上，要講出來
        if slot.stop.subSpotMinutes > slot.stop.dwellMinutes {
            chips.append(ItemChip(id: "over",
                                  text: "子地點共 \(slot.stop.subSpotMinutes) 分，超過停留時間",
                                  color: .red, icon: "exclamationmark.circle.fill"))
        }
        return chips
    }

    private func stopPreview(_ stop: TripStop) -> String? {
        var parts: [String] = []
        let addr = stop.address.trimmingCharacters(in: .whitespaces)
        if !addr.isEmpty { parts.append(addr) }
        let note = stop.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func subSpotDisclosures(_ stop: TripStop) -> [ItemDisclosure] {
        stop.subSpots.map { sub in
            ItemDisclosure(
                id: sub.id.uuidString,
                badge: sub.minutes > 0 ? "\(sub.minutes) 分" : nil,
                title: sub.name.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "未命名子地點" : sub.name,
                body: sub.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "（沒有備註）" : sub.note)
        }
    }

    /// 這一段的交通方式。從時間軸直接改，不必開編輯畫面——
    /// 「這段走過去就好」是排行程時很常做的微調。
    private func setLegMode(_ stopId: UUID, _ mode: TripTravelMode?) {
        guard var p = plan, let i = p.stops.firstIndex(where: { $0.id == stopId }),
              i > 0, p.stops[i].legModeOverride != mode else { return }
        p.stops[i].legModeOverride = mode
        // 這一段要重算：清掉它的快取指紋，.task 會自己補上
        p.stops[i].legStamp = nil
        lifeStore.upsertTripPlan(p)
    }

    /// 必去只是一個開關，不必為它開一次編輯畫面
    private func toggleMustVisit(_ stopId: UUID) {
        lifeStore.toggleTripStopMustVisit(planId: planId, stopId: stopId)
    }

    /// 換順序。往後移要 +2——SwiftUI 的 move(toOffset:) 算的是「移除前的索引」，
    /// 給 index + 1 只會插回原位。
    private func move(_ index: Int, by delta: Int) {
        let dest = delta < 0 ? index - 1 : index + 2
        lifeStore.moveTripStops(planId: planId, from: IndexSet(integer: index), to: dest)
    }

    /// [v25.441] 把這一站做成一張圖再分享。
    /// 地圖快照要等，所以先把旗標打起來擋住重複點擊——這個選單很容易連按。
    @MainActor
    private func shareStopImage(_ stop: TripStop) async {
        guard !isExportingStop, let p = plan else { return }
        isExportingStop = true
        defer { isExportingStop = false }
        // 出圖是同步畫的，先把這一站的天氣抓齊
        if let c = stop.coordinate,
           let when = p.timeline.first(where: { $0.stop.id == stop.id })?.arrival,
           TripWeatherStore.isWithinForecastRange(when) {
            await TripWeatherStore.shared.preload([c])
        }
        let map = await TripImageExporter.stopMapImage(plan: p, stopId: stop.id)
        let card = TripStopShareCard(plan: p, stopId: stop.id, mapImage: map)
        let stamp = TripImageExporter.stampFormatter.string(from: Date())
        guard let url = TripImageExporter.writeJPG(
            card, name: stop.displayName + "_" + stamp) else { return }
        sharingStopImage = ShareStopImage(url: url)
    }

    private func shareStop(_ stop: TripStop) {
        guard let p = plan else { return }
        sharing = ShareText(text: TripShare.stopText(stop, in: p))
    }

    // MARK: 加景點 / 空狀態

    private func addButton(_ p: TripPlan) -> some View {
        Button {
            insertion = StopInsertion(at: nil)
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text(p.stops.isEmpty ? "加入第一個景點" : "在最後加一站")
                        .font(.subheadline.weight(.semibold))
                }
                // 打過卡之後這個時間是從「實際離開」接下去算的，不是原本排的
                if let hint = nextStartHint(p) {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(LinearGradient(colors: [accent, accent.opacity(0.75)],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: accent.opacity(0.28), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    /// 「從『某某』15:40 出發」。字串在 ViewBuilder 外組好。
    private func nextStartHint(_ p: TripPlan) -> String? {
        guard let last = p.timeline.last else { return nil }
        let time = Self.timeFmt.string(from: last.departure)
        let day = Calendar.current.isDate(last.departure, inSameDayAs: last.arrival)
            ? "" : "翌 "
        let prefix = last.isActualDeparture ? "已從" : "從"
        return prefix + "「" + last.stop.displayName + "」" + day + time + " 出發"
    }

    private var emptyStops: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 26)).foregroundStyle(.tertiary)
            Text("還沒有景點")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text("加了兩站以上就會自動算出每段路的距離與交通時間，\n並把抵達與離開時間排成時間軸。")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }
}

// MARK: - 行程設定

struct TripPlanSettingsSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let plan: TripPlan

    @State private var title = ""
    @State private var startDate = Date()
    @State private var mode: TripTravelMode = .driving
    @State private var note = ""
    @State private var loaded = false

    init(plan: TripPlan) { self.plan = plan }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("行程名稱（如 宜蘭兩天一夜）", text: $title)
                    HStack {
                        Text("出發時間")
                        Spacer()
                        FiveMinuteDateTimePicker(selection: $startDate).fixedSize()
                    }
                } header: {
                    Text("基本")
                }
                Section {
                    Picker("交通方式", selection: $mode) {
                        ForEach(TripTravelMode.allCases) { m in
                            Label(m.rawValue, systemImage: m.icon).tag(m)
                        }
                    }
                } header: {
                    Text("交通")
                } footer: {
                    Text(Self.modeFooter(mode))
                }
                Section {
                    TextField("備註", text: $note, axis: .vertical).lineLimit(2...6)
                } header: {
                    Text("備註")
                }
            }
            .navigationTitle("行程設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }.bold()
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                title = plan.title; startDate = plan.startDate
                mode = plan.travelMode; note = plan.note
            }
        }
    }

    /// 字串在 ViewBuilder 外組好
    private static func modeFooter(_ mode: TripTravelMode) -> String {
        var t: String
        switch mode {
        case .driving, .walking:
            t = "開車與步行會向地圖服務要真實路徑，算出來的是實際道路距離與行駛時間"
                + "（依一般路況估算，不含即時路況）。"
        case .transit:
            t = "Apple 不開放大眾運輸的路線計算，所以這個方式是用直線距離乘上迂迴係數估的，"
                + "段落上會標「估」。要精確時間請用地圖開啟該景點查。"
        case .plane:
            t = "飛機沒有路線服務可問，是用大圓距離估的，並加上 120 分鐘固定耗時"
                + "（報到、安檢、登機、下機、等行李），段落上會標「估」。"
        }
        t += "\n\n這裡設的是整趟的預設值。單獨某一段想改成步行或飛機，"
            + "到那一站的編輯畫面裡「怎麼過來」指定即可；沒指定的段落會跟著這個預設值變。"
        return t
    }

    private func save() {
        // 從 store 現撈，不要用打開這張表單那一刻的快照——
        // 使用者可能在這之前才剛加過景點（同 EquipmentEditorSheet v25.385 的教訓）
        guard var live = lifeStore.tripPlan(id: plan.id) else { dismiss(); return }
        live.title = title.trimmingCharacters(in: .whitespaces)
        // 用 setStartDate 而不是直接寫 startDate：換日時各站指定的抵達時間要跟著搬
        live.setStartDate(startDate)
        live.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if live.travelMode != mode {
            live.travelMode = mode
            // 預設方式換了，跟著預設走的那些段落要重算——把它們的快取指紋清掉，
            // 詳情頁的 .task 會自己補算。
            // 被單獨指定過方式的段落不受影響，指紋留著，免得白打一次 MapKit
            //（清成 nil 會讓 fillMissingLegs 認為過期而整段重算）。
            for i in live.stops.indices where live.stops[i].legModeOverride == nil {
                live.stops[i].legStamp = nil
            }
        }
        lifeStore.upsertTripPlan(live)
        dismiss()
    }
}

// MARK: - 景點編輯

struct TripStopEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let planId: UUID
    var editing: TripStop?
    /// 新增時要插在第幾個位置；nil＝加在最後
    var insertAt: Int?

    @State private var name = ""
    @State private var address = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var dwellMinutes = 60
    /// 指定抵達時間（關閉＝由上一站推算）
    @State private var hasArrivalTime = false
    @State private var arrivalTime = Date()
    /// 這一段的交通方式；nil＝用行程的預設
    @State private var legMode: TripTravelMode?
    /// 已經從「住過的地方」挑過了 → 收掉那一區，不要一直擺在那裡
    @State private var lodgingPicked = false
    @State private var isMustVisit = false
    @State private var isOvernight = false
    @State private var checkOutTime = TripStopEditorSheet.defaultCheckOut
    @State private var note = ""
    @State private var photoFileNames: [String] = []
    @State private var subSpots: [TripSubSpot] = []
    /// 正在編哪一個子地點。用推的（navigationDestination）而不是 sheet，
    /// 見 TripSubSpotEditView 的說明。
    @State private var editingSubId: UUID?
    @State private var loaded = false
    @State private var isSaving = false
    /// 新增的照片先記下來，取消時要刪掉——不然按取消也會留下檔案
    @State private var addedPhotos: Set<String> = []

    // 地點搜尋（沿用飲食／就醫紀錄那一套 MKLocalSearchCompleter）
    @StateObject private var completer = RestaurantSearchCompleter()
    @State private var searchDebounce: Task<Void, Never>?

    /// [v25.432] 「欄位裡的字是誰打的」——共用模板，見 MapPlacePicker.swift
    @State private var fill = PlaceFieldFill()

    private let accent = TripDayPalette.color(0)

    init(planId: UUID, editing: TripStop?, insertAt: Int?) {
        self.planId = planId
        self.editing = editing
        self.insertAt = insertAt
    }

    var body: some View {
        NavigationStack {
            // ⚠️ 這個 Form 目前有 9 個直接子元素，SwiftUI 的 ViewBuilder 上限是 10。
            // 還要再加區塊的話，先把相關的幾個 Section 收進一個 @ViewBuilder 屬性裡，
            // 不然會編不過（而且錯誤訊息完全看不出是這個原因）。
            Form {
                Section {
                    TextField("景點名稱", text: $name)
                        .onChange(of: name) { _, newValue in scheduleSearch(newValue) }
                    if !completer.results.isEmpty && latitude == nil {
                        ForEach(Array(completer.results.prefix(5).enumerated()), id: \.offset) { _, r in
                            Button { pick(r) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).font(.subheadline).foregroundStyle(.primary)
                                    if !r.subtitle.isEmpty {
                                        Text(r.subtitle).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("地址", text: $address)
                    MapPlacePickerButton(
                        startCoordinate: mapPickerStart,
                        hasCoordinate: latitude != nil,
                        accent: accent,
                        onPick: { picked, addr, coord in
                            applyPickedLocation(name: picked, address: addr, coordinate: coord)
                        },
                        onClear: { latitude = nil; longitude = nil })
                    if !fill.offer.isEmpty {
                        PlaceOfferRow(offer: fill.offer) {
                            fill.acceptOffer(into: $name, addressField: $address)
                        }
                    }
                } header: {
                    Text("地點")
                } footer: {
                    Text(latitude == nil
                         ? "打名稱會出現搜尋建議，選一個就會帶入地址與座標。搜尋找不到的地方（產業道路邊的景點、沒登記的民宿）用「在地圖上選位置」。沒有座標的景點不會被算進路線距離與時間。"
                         : "有座標才算得出與前後站之間的距離與交通時間。")
                }

                // [v25.405] 住過的地方：同一家飯店不用每次重打
                if showLodgingSection {
                    Section {
                        ForEach(lodgingMatches) { item in
                            lodgingRow(item)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "bed.double.fill").font(.system(size: 10))
                            Text("住過的地方")
                        }
                    } footer: {
                        Text("選一個就會帶入名稱、地址與座標，並自動打開「在這裡過夜」與上次設的退房時刻。打字會跟著篩選。")
                    }
                }

                Section {
                    mustVisitButton
                    Toggle(isOn: $isOvernight) {
                        Label("在這裡過夜", systemImage: "bed.double.fill")
                    }
                    .tint(.indigo)
                    if isOvernight {
                        HStack {
                            Text("隔天出發")
                            Spacer()
                            DatePicker("", selection: $checkOutTime,
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                } header: {
                    Text("標記")
                } footer: {
                    Text(isOvernight
                         ? "這一站會成為當天的最後一站，時間軸在這裡換日；隔天從這裡開始，第一段路的交通時間從你設定的出發時刻算起。過夜的站不用填停留時間。"
                         : "必去的站會標星號，時間不夠要砍站時一眼看得出哪些不能砍。住宿的地方請打開「在這裡過夜」。")
                }

                if !isFirstStop {
                    Section {
                        Picker("交通方式", selection: Binding(
                            get: { legMode?.rawValue ?? "" },
                            set: { legMode = TripTravelMode(rawValue: $0) }
                        )) {
                            Text("用行程預設（" + planDefaultMode.rawValue + "）").tag("")
                            ForEach(TripTravelMode.allCases) { m in
                                Label(m.rawValue, systemImage: m.icon).tag(m.rawValue)
                            }
                        }
                    } header: {
                        Text("怎麼過來")
                    } footer: {
                        Text(legModeFooter)
                    }
                }

                Section {
                    Toggle("指定抵達時間", isOn: $hasArrivalTime)
                        .tint(accent)
                    if hasArrivalTime {
                        HStack {
                            Text("抵達")
                            Spacer()
                            FiveMinuteDateTimePicker(selection: $arrivalTime).fixedSize()
                        }
                    }
                } header: {
                    Text("抵達")
                } footer: {
                    Text(hasArrivalTime
                         ? "時間軸會把這一站固定在這個時間。前一站提早到就顯示成等候；照交通時間根本來不及時會標紅字提醒，但時間軸還是照你指定的排。"
                         : "不指定的話，抵達時間由上一站的離開時間加上路上的交通時間自動推算。餐廳訂位、船班、表演入場這種時間是死的，建議直接指定。")
                }

                if !isOvernight {
                    Section {
                        Stepper(value: $dwellMinutes, in: 0...1440, step: 15) {
                            HStack {
                                Text("停留時間")
                                Spacer()
                                Text("\(dwellMinutes) 分").foregroundStyle(.secondary)
                            }
                        }
                        // 15 分一格對短停留太粗，補幾顆常用值
                        HStack(spacing: 6) {
                            ForEach([30, 60, 90, 120, 180], id: \.self) { m in
                                Button("\(m)分") { dwellMinutes = m }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(dwellMinutes == m ? accent.opacity(0.18)
                                                : Color(.tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(dwellMinutes == m ? accent : .secondary)
                                    .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("停留")
                    }
                }

                TripSubSpotEditor(subSpots: $subSpots, dwellMinutes: dwellMinutes,
                                  accent: accent,
                                  onEdit: { editingSubId = $0 })

                Section {
                    MultiPhotoGallery(
                        fileNames: $photoFileNames,
                        urlFor: { TripStop.photoURL($0) },
                        onSaveImage: { data in
                            guard let n = TripStop.savePhoto(data) else { return nil }
                            addedPhotos.insert(n)
                            return n
                        },
                        onDeleteFile: { n in
                            TripStop.deletePhoto(n)
                            addedPhotos.remove(n)
                        },
                        title: "景點照片")
                } header: {
                    Text("照片")
                }

                Section {
                    TextField("備註（訂位、門票、注意事項…）", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("備註")
                }
            }
            .navigationTitle(editing == nil ? "新增景點" : "編輯景點")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { cancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().scaleEffect(0.7).tint(accent) }
                        Button(editing == nil ? "新增" : "儲存") { save() }
                            .bold()
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                arrivalTime = suggestedArrival
                guard let e = editing else { return }
                name = e.name; address = e.address
                latitude = e.latitude; longitude = e.longitude
                dwellMinutes = e.dwellMinutes; note = e.note
                photoFileNames = e.photoFileNames; subSpots = e.subSpots
                legMode = e.legModeOverride
                isMustVisit = e.isMustVisit
                isOvernight = e.isOvernight
                if let out = e.checkOutTime { checkOutTime = out }
                if let fixed = e.arrivalOverride {
                    hasArrivalTime = true
                    arrivalTime = fixed
                }
            }
            // 掛在 Form（NavigationStack 的根內容）上，不是掛在某一列上——
            // 掛在 List 的列裡會隨著列被回收而失效
            .navigationDestination(item: $editingSubId) { id in
                TripSubSpotEditView(sub: subSpotBinding(id), accent: accent,
                                    parentCoordinate: mapPickerStart)
            }
            .onChange(of: editingSubId) { _, newValue in
                // 返回時把「開了但什麼都沒填」的那一筆收掉，
                // 不然按新增再返回就會留下一列空白
                guard newValue == nil else { return }
                subSpots.removeAll {
                    $0.name.trimmingCharacters(in: .whitespaces).isEmpty
                        && $0.address.trimmingCharacters(in: .whitespaces).isEmpty
                        && $0.note.trimmingCharacters(in: .whitespaces).isEmpty
                }
            }
            .onDisappear { searchDebounce?.cancel() }
        }
    }

    /// 住過的地方要不要出現。
    ///
    /// 已經有座標就代表這一站的地點定下來了（新增時從地圖搜尋挑過、或編輯既有的站），
    /// 這時候再擺一排飯店只會擋路——跟地圖搜尋建議用同一個判斷條件。
    private var showLodgingSection: Bool {
        !lodgingPicked && latitude == nil && !lodgingMatches.isEmpty
    }

    /// 依目前打的字篩選住過的地方；還沒打字就列最近幾筆
    private var lodgingMatches: [LifeStore.LodgingSuggestion] {
        let all = lifeStore.lodgingSuggestions()
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(all.prefix(5)) }
        return all.filter {
            $0.name.lowercased().contains(q) || $0.address.lowercased().contains(q)
        }
    }

    private func lodgingRow(_ item: LifeStore.LodgingSuggestion) -> some View {
        Button {
            applyLodging(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 13)).foregroundStyle(.indigo)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? "未命名住宿" : item.name)
                        .font(.subheadline).foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(Self.lodgingMeta(item))
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if item.useCount > 1 {
                    Text("住過 \(item.useCount) 次")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.13))
                        .foregroundStyle(.indigo)
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 字串在 ViewBuilder 外組好
    private static func lodgingMeta(_ item: LifeStore.LodgingSuggestion) -> String {
        var parts: [String] = []
        if !item.address.isEmpty { parts.append(item.address) }
        if item.latitude == nil { parts.append("沒有座標") }
        parts.append("上次 " + lodgingDateFmt.string(from: item.lastUsed))
        return parts.joined(separator: "・")
    }

    private static let lodgingDateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d"; return f
    }()

    private func applyLodging(_ item: LifeStore.LodgingSuggestion) {
        name = item.name
        address = item.address
        latitude = item.latitude
        longitude = item.longitude
        // 這兩欄是挑進來的、不是使用者打的，記下來——之後若在地圖上重挑一個地方，
        // 才會跟著換掉，而不是卡在這家飯店的名字上
        fill.markFilled(name: item.name, address: item.address)
        isOvernight = true
        if let t = item.checkOutTime { checkOutTime = t }
        // 帶入名稱會觸發地圖搜尋，這裡先把待送出的查詢與既有建議清掉，
        // 免得挑完之後下面又冒出一排地圖建議
        searchDebounce?.cancel()
        completer.queryFragment = ""
        lodgingPicked = true
    }

    private var planDefaultMode: TripTravelMode {
        lifeStore.tripPlan(id: planId)?.travelMode ?? .driving
    }

    /// 這一站是不是整條行程的第一站。第一站前面沒有路段，選交通方式沒有意義
    ///（從家裡到第一站那一段本來就沒在算——要算就把家當成一個景點加進去）。
    private var isFirstStop: Bool {
        guard let plan = lifeStore.tripPlan(id: planId) else { return true }
        if let e = editing { return plan.stops.first?.id == e.id }
        return (insertAt ?? plan.stops.count) == 0
    }

    private var legModeFooter: String {
        let m = legMode ?? planDefaultMode
        var t = "從上一站到這一站要用的方式。不選就跟著行程設定走，改行程預設時這一段也會跟著變。"
        if m == .plane {
            t += "\n\n飛機沒有路線服務可問，是用大圓距離估的，並且加了 120 分鐘的固定耗時"
            + "（報到、安檢、登機、下機、等行李）。不含「去機場的路程」——那段請把機場"
            + "當成一個景點自己排進去。"
        } else if m == .transit {
            t += "\n\nApple 不開放大眾運輸的路線計算，這個方式是用直線距離估的，會標「估」。"
        } else {
            t += "\n\n開車與步行會向地圖服務要真實路徑，算出來的是實際道路距離與行駛時間。"
        }
        return t
    }

    /// 「必去」是一鍵切換，做成整列可點的按鈕而不是右邊那顆小開關——
    /// 這是排行程時最常按的東西。
    private var mustVisitButton: some View {
        Button {
            isMustVisit.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isMustVisit ? "star.fill" : "star")
                    .font(.system(size: 16))
                    .foregroundStyle(isMustVisit ? Color.orange : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("必去").font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(isMustVisit ? "已標記，時間軸上會加星號" : "這一站不能砍的話標一下")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isMustVisit {
                    Text("必去")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 預設退房時刻：早上 9:00（只有時分會被用到）
    static var defaultCheckOut: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    /// 打開「指定抵達時間」時的預設值：就用目前時間軸算出來的抵達時間，
    /// 使用者多半只想微調，不該從今天此刻開始選。
    private var suggestedArrival: Date {
        guard let plan = lifeStore.tripPlan(id: planId) else { return Date() }
        let tl = plan.timeline
        if let e = editing, let slot = tl.first(where: { $0.stop.id == e.id }) {
            return slot.arrival
        }
        // 插在中間：用現在站在那個位置的那一站的抵達時間當起點
        if let at = insertAt, tl.indices.contains(at) { return tl[at].arrival }
        return plan.endDate
    }

    /// 地圖選位置要從哪裡開始看：這一站已有的座標 → 上一站的 → 這份行程最後一個有座標的站。
    /// 都沒有就讓選位置畫面自己退回使用者位置。
    private var mapPickerStart: CLLocationCoordinate2D? {
        if let latitude, let longitude {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        guard let plan = lifeStore.tripPlan(id: planId) else { return nil }
        if let e = editing, let i = plan.stops.firstIndex(where: { $0.id == e.id }), i > 0 {
            if let c = plan.stops[i - 1].coordinate { return c }
        } else if let at = insertAt, at > 0, plan.stops.indices.contains(at - 1) {
            if let c = plan.stops[at - 1].coordinate { return c }
        }
        return plan.stops.last(where: { $0.coordinate != nil })?.coordinate
    }

    /// 依 id 取得陣列裡那一筆的 Binding。
    /// 用 id 而不是 index：編輯期間清單可能被刪改，index 會指到別人身上。
    private func subSpotBinding(_ id: UUID) -> Binding<TripSubSpot> {
        Binding(
            get: { subSpots.first(where: { $0.id == id }) ?? TripSubSpot(id: id) },
            set: { newValue in
                if let i = subSpots.firstIndex(where: { $0.id == id }) {
                    subSpots[i] = newValue
                }
            }
        )
    }

    /// 地圖上挑到一個位置。座標一定跟著換（使用者就是為了定位才來的），
    /// 名稱與地址則看欄位裡現在那個字是誰打的。
    private func applyPickedLocation(name picked: String?, address addr: String,
                                     coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        fill.apply(name: picked, address: addr, into: $name, addressField: $address)
        // 帶入名稱會觸發地圖搜尋建議，這裡先把待送出的查詢與既有建議清掉
        searchDebounce?.cancel()
        completer.queryFragment = ""
        lodgingPicked = true
    }

    private func scheduleSearch(_ q: String) {
        // 打字就打斷搜尋建議的既有選擇（改了名字座標通常也不對了），
        // 但不主動清座標——使用者可能只是修錯字
        searchDebounce?.cancel()
        let text = q.trimmingCharacters(in: .whitespaces)
        // 自己動手改過名字之後，那一列「要不要改用地圖上的」就沒意義了
        fill.userEditedName(text)
        // 名稱清空＝重新開始選地點，「住過的地方」那一區該回來
        if text.isEmpty { lodgingPicked = false }
        guard text.count >= 2 else { completer.queryFragment = ""; return }
        searchDebounce = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { completer.queryFragment = text }
        }
    }

    private func pick(_ r: MKLocalSearchCompletion) {
        // 點建議＝「我要的就是這個」，名稱直接用它的標題，不必問
        fill.adopt(title: r.title, into: $name)
        completer.queryFragment = ""
        // 建議只有文字，要再做一次 MKLocalSearch 才拿得到座標
        Task {
            let req = MKLocalSearch.Request(completion: r)
            guard let item = try? await MKLocalSearch(request: req).start().mapItems.first else { return }
            await MainActor.run {
                let pm = item.placemark
                latitude = pm.coordinate.latitude
                longitude = pm.coordinate.longitude
                fill.apply(name: nil,
                           address: [pm.postalCode, pm.administrativeArea, pm.locality,
                                     pm.thoroughfare, pm.subThoroughfare]
                            .compactMap { $0 }.joined(),
                           into: $name, addressField: $address)
            }
        }
    }

    private func cancel() {
        // 這一次新加的照片沒存檔就不該留在磁碟上
        for n in addedPhotos { TripStop.deletePhoto(n) }
        dismiss()
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        guard var plan = lifeStore.tripPlan(id: planId) else { dismiss(); return }

        var stop = editing ?? TripStop()
        stop.name = name.trimmingCharacters(in: .whitespaces)
        stop.address = address.trimmingCharacters(in: .whitespaces)
        stop.latitude = latitude
        stop.longitude = longitude
        stop.dwellMinutes = max(0, dwellMinutes)
        // 交通方式換了就把這一段的路線快取作廢（下面統一清 legStamp 時會處理，
        // 這裡只負責存值）
        stop.legModeOverride = legMode
        stop.isMustVisit = isMustVisit
        stop.isOvernight = isOvernight
        // 沒開過夜就不要留著退房時刻，免得之後重新打開時帶出上次改過的值
        stop.checkOutTime = isOvernight ? checkOutTime : nil
        stop.arrivalOverride = hasArrivalTime ? arrivalTime : nil
        stop.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        stop.photoFileNames = photoFileNames
        stop.subSpots = subSpots.filter {
            !($0.name.trimmingCharacters(in: .whitespaces).isEmpty
              && $0.note.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        if let idx = plan.stops.firstIndex(where: { $0.id == stop.id }) {
            // 編輯既有：座標可能動過，所以這一段與「下一段」的路線快取都要作廢
            plan.stops[idx] = stop
            plan.stops[idx].legStamp = nil
            if plan.stops.indices.contains(idx + 1) { plan.stops[idx + 1].legStamp = nil }
        } else {
            let at = min(max(insertAt ?? plan.stops.count, 0), plan.stops.count)
            plan.stops.insert(stop, at: at)
            // 插進去只影響「進這一站」與「從這一站出去」兩段，不用整條重算
            plan.stops[at].legStamp = nil
            if plan.stops.indices.contains(at + 1) { plan.stops[at + 1].legStamp = nil }
        }
        // 已經寫進行程的照片不再算「這次新加的」，cancel 的清除邏輯不該碰它們
        addedPhotos.removeAll()
        lifeStore.upsertTripPlan(plan)
        dismiss()
    }
}

// MARK: - 子地點編輯

/// 母景點底下的細項。刻意不給座標（見 TripSubSpot 的說明），
/// 所以這裡只要名稱、分鐘與備註。
struct TripSubSpotEditor: View {
    @Binding var subSpots: [TripSubSpot]
    let dwellMinutes: Int
    let accent: Color
    /// 點一筆要編輯時回報給上層。
    ///
    /// ⚠️ [v25.425] 這裡刻意**不自己** .sheet 出去：這個型別的 body 是一個 Section，
    ///    而 Section 在 Form 裡不是一個能穩定承載 presentation 的宿主——
    ///    一旦 subSpots 改變、Section 被重建，presentation 的來源就失效，
    ///    SwiftUI 會把整串 sheet（連同外面的景點編輯畫面）一起收掉。
    ///    v25.424 的「按下子地點整個編輯畫面自己關掉」就是這樣來的。
    let onEdit: (UUID) -> Void

    var body: some View {
        Section {
            if subSpots.isEmpty {
                Text("還沒有子地點。像老街、園區這種一個景點裡有好幾攤的地方，可以拆進來。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(subSpots) { sub in
                Button { onEdit(sub.id) } label: { row(sub) }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            subSpots.removeAll { $0.id == sub.id }
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
            }
            Button {
                // 先塞一筆空的再推進去編：編輯畫面直接綁著陣列裡的那一筆改，
                // 不用再做一套「暫存 → 按完成寫回」。退出去時上層會把
                // 完全沒填的那筆清掉，所以不會留下空白列。
                let fresh = TripSubSpot()
                subSpots.append(fresh)
                onEdit(fresh.id)
            } label: {
                Label("新增子地點", systemImage: "plus.circle.fill").foregroundStyle(accent)
            }
        } header: {
            HStack(spacing: 6) {
                Text("子地點")
                if !subSpots.isEmpty {
                    Text("\(subSpots.count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(accent.opacity(0.14)).foregroundStyle(accent)
                        .clipShape(Capsule())
                }
            }
        } footer: {
            let total = subSpots.reduce(0) { $0 + max(0, $1.minutes) }
            if total > dwellMinutes {
                Text("子地點加起來 \(total) 分，比這一站的停留時間 \(dwellMinutes) 分還長——時間軸會照停留時間排，記得調整。")
                    .foregroundStyle(.orange)
            } else {
                Text("點一筆可以編名稱、地址與時間；往左滑刪除。子地點不會各自計算路線，時間軸上會收在這一站的摺疊區裡。")
            }
        }
    }

    private func row(_ sub: TripSubSpot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: sub.coordinate == nil ? "circle.dotted" : "mappin.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(sub.coordinate == nil ? Color.secondary : accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.displayName)
                    .font(.subheadline)
                    .foregroundStyle(sub.name.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? .secondary : .primary)
                let addr = sub.address.trimmingCharacters(in: .whitespaces)
                let note = sub.note.trimmingCharacters(in: .whitespaces)
                if !addr.isEmpty {
                    Text(addr).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else if !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if sub.minutes > 0 {
                Text("\(sub.minutes) 分")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// 單一子地點的編輯畫面。
///
/// [v25.424] 為什麼要獨立一個畫面，而不是像以前那樣在清單裡直接打字：
/// 子地點也要能搜尋地點、也要能在地圖上挑位置，而 MKLocalSearchCompleter
/// 一個畫面只能有一個（每一列各養一個會互相蓋掉彼此的結果，還很耗電）。
/// 一次只編一筆，就只需要一個 completer。
///
/// [v25.425] 從 sheet 改成**推進景點編輯畫面的導覽堆疊**。兩個理由：
///   1. 地圖選位置本身還要再開一張 sheet。原本是「景點編輯 sheet →
///      子地點 sheet → 地圖 sheet」三層疊在一起，SwiftUI 疊到第三層就很不穩。
///      改成推進去之後只剩兩層，跟景點自己開地圖選位置是同一個深度。
///   2. 推進去有返回鍵，回上一層還看得到剛編好的那一列，比關掉一張卡片自然。
/// 也因為是推進去的，這裡直接綁著陣列裡的那一筆即時改，沒有「按完成才寫回」
/// 這件事——返回就是保留，跟系統設定那類畫面的習慣一致。
struct TripSubSpotEditView: View {
    @Binding var sub: TripSubSpot
    let accent: Color
    let parentCoordinate: CLLocationCoordinate2D?

    @StateObject private var completer = RestaurantSearchCompleter()
    @State private var searchDebounce: Task<Void, Never>?
    /// [v25.432] 跟景點編輯共用同一個記錄器，見 MapPlacePicker.swift
    @State private var fill = PlaceFieldFill()

    var body: some View {
        Form {
            Section {
                TextField("子地點名稱", text: $sub.name)
                    .onChange(of: sub.name) { _, newValue in scheduleSearch(newValue) }
                if !completer.results.isEmpty && sub.latitude == nil {
                    ForEach(Array(completer.results.prefix(5).enumerated()), id: \.offset) { _, r in
                        Button { pick(r) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(.subheadline).foregroundStyle(.primary)
                                if !r.subtitle.isEmpty {
                                    Text(r.subtitle).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField("地址", text: $sub.address)
                MapPlacePickerButton(
                    startCoordinate: mapPickerStart,
                    hasCoordinate: sub.latitude != nil,
                    accent: accent,
                    subtitle: "老街裡的某一攤、園區裡的某個館，點地圖最快",
                    onPick: { picked, addr, coord in
                        sub.latitude = coord.latitude
                        sub.longitude = coord.longitude
                        fill.apply(name: picked, address: addr,
                                   into: $sub.name, addressField: $sub.address)
                        searchDebounce?.cancel()
                        completer.queryFragment = ""
                    },
                    onClear: { sub.latitude = nil; sub.longitude = nil })
                if !fill.offer.isEmpty {
                    PlaceOfferRow(offer: fill.offer) {
                        fill.acceptOffer(into: $sub.name, addressField: $sub.address)
                    }
                }
            } header: {
                Text("地點")
            } footer: {
                Text("子地點的座標只拿來「用地圖開啟」，不會進路線計算——這一站要走的路一律以母景點為準。")
            }

            Section {
                Stepper(value: $sub.minutes, in: 0...600, step: 10) {
                    HStack {
                        Text("預計停留")
                        Spacer()
                        Text(sub.minutes == 0 ? "未安排" : "\(sub.minutes) 分")
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("備註", text: $sub.note, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("時間與備註")
            } footer: {
                Text("改了就直接存進這一站，返回即可。名稱與地址都留白的話這一筆會自動捨棄。")
            }
        }
        .navigationTitle("子地點")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { searchDebounce?.cancel() }
    }

    private var mapPickerStart: CLLocationCoordinate2D? {
        sub.coordinate ?? parentCoordinate
    }

    private func scheduleSearch(_ q: String) {
        searchDebounce?.cancel()
        let text = q.trimmingCharacters(in: .whitespaces)
        fill.userEditedName(text)
        guard text.count >= 2 else { completer.queryFragment = ""; return }
        searchDebounce = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { completer.queryFragment = text }
        }
    }

    private func pick(_ r: MKLocalSearchCompletion) {
        // 點建議＝「我要的就是這個」，名稱直接用它的標題
        fill.adopt(title: r.title, into: $sub.name)
        completer.queryFragment = ""
        Task {
            let req = MKLocalSearch.Request(completion: r)
            guard let item = try? await MKLocalSearch(request: req).start().mapItems.first else { return }
            await MainActor.run {
                let pm = item.placemark
                sub.latitude = pm.coordinate.latitude
                sub.longitude = pm.coordinate.longitude
                fill.apply(name: nil,
                           address: [pm.postalCode, pm.administrativeArea, pm.locality,
                                     pm.thoroughfare, pm.subThoroughfare]
                            .compactMap { $0 }.joined(),
                           into: $sub.name, addressField: $sub.address)
            }
        }
    }
}

// MARK: - 路線地圖

/// 把整條行程畫在地圖上：編號大頭針 + 路線 + 第幾天的顏色圖例。
///
/// 開車與步行的段落打開地圖時現算真實路徑（實線）；大眾運輸與飛機沒有路線服務可問，
/// 只能畫直線（虛線）。路徑刻意不存進資料裡——一條 polyline 動輒上百個座標點，
/// 每段各存一份會讓行程資料膨脹好幾個數量級，還要跟著 iCloud 同步與備份一起搬。
struct TripRouteMapSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let plan: TripPlan

    /// 已取回的真實路徑，key 是「目的地那一站」的 id（與 legMeters 的歸屬一致）
    @State private var polylines: [UUID: MKPolyline] = [:]
    @State private var isLoading = false
    @State private var loadedLegs = 0
    @State private var routableLegs = 0
    @State private var showLegend = true

    /// 用具名結構而不是 tuple：Swift 的 key path 不支援 tuple 成員（\.coord 會編不過）
    private struct Pin: Identifiable {
        let id: UUID
        let number: Int
        let name: String
        let coord: CLLocationCoordinate2D
        /// 第幾天——大頭針跟時間軸用同一套分色
        let dayIndex: Int
        let isMustVisit: Bool
        let isOvernight: Bool
    }

    /// 一段路。有真實路徑就畫實線，沒有（大眾運輸／飛機／算不出來）就畫虛線直線。
    private struct Segment: Identifiable {
        /// 目的地那一站的 id
        let id: UUID
        let dayIndex: Int
        let mode: TripTravelMode
        let straight: [CLLocationCoordinate2D]
    }

    private var pins: [Pin] {
        plan.timeline.compactMap { slot in
            slot.stop.coordinate.map {
                Pin(id: slot.stop.id, number: slot.index + 1,
                    name: slot.stop.displayName, coord: $0, dayIndex: slot.dayIndex,
                    isMustVisit: slot.stop.isMustVisit,
                    isOvernight: slot.stop.isOvernight)
            }
        }
    }

    /// 相鄰兩站都有座標才成為一段。中間夾著沒座標的站時就跳過那兩段——
    /// 硬把它前後接起來會畫出一條根本不存在的路。
    private var segments: [Segment] {
        let slots = plan.timeline
        guard slots.count >= 2 else { return [] }
        var out: [Segment] = []
        for i in 1..<slots.count {
            guard let a = slots[i - 1].stop.coordinate,
                  let b = slots[i].stop.coordinate else { continue }
            out.append(Segment(id: slots[i].stop.id,
                               dayIndex: slots[i].dayIndex,
                               mode: slots[i].mode,
                               straight: [a, b]))
        }
        return out
    }

    /// 這趟用到的天數（照 timeline 算，指定抵達時間可能把某一站排到更晚）
    private var dayIndices: [Int] {
        Array(Set(plan.timeline.map(\.dayIndex))).sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if pins.count < 2 {
                    VStack(spacing: 10) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 30)).foregroundStyle(.tertiary)
                        Text("至少要有兩個有座標的景點才畫得出路線")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    mapView
                }
            }
            .navigationTitle("行程路線")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if pins.count >= 2 {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                showLegend.toggle()
                            }
                        } label: {
                            Image(systemName: showLegend ? "list.bullet.circle.fill"
                                                         : "list.bullet.circle")
                                .foregroundStyle(TripDayPalette.color(0))
                        }
                    }
                }
            }
            .task { await loadRealRoutes() }
        }
    }

    private var mapView: some View {
        // .automatic 讓地圖自己把所有內容框進畫面——真實路徑繞出去的範圍也會被含進來，
        // 自己算大頭針的外框會把繞路的部分切掉
        Map(initialPosition: .automatic) {
            ForEach(segments) { seg in
                if let poly = polylines[seg.id] {
                    MapPolyline(poly)
                        .stroke(TripDayPalette.color(seg.dayIndex),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round,
                                                   lineJoin: .round))
                } else {
                    // 沒有真實路徑可畫：虛線代表這一段只是把兩點連起來
                    MapPolyline(coordinates: seg.straight)
                        .stroke(TripDayPalette.color(seg.dayIndex).opacity(0.6),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round,
                                                   dash: [7, 5]))
                }
            }
            ForEach(pins) { pin in
                Annotation(pin.name, coordinate: pin.coord) {
                    pinMarker(pin)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            if showLegend { legend }
        }
    }

    private func pinMarker(_ pin: Pin) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle().fill(TripDayPalette.color(pin.dayIndex))
                    .frame(width: 26, height: 26)
                    .shadow(radius: 2)
                if pin.isOvernight {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(pin.number)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            if pin.isMustVisit {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .padding(1.5)
                    .background(Circle().fill(Color(.systemBackground)))
                    .offset(x: 5, y: -5)
            }
        }
        .frame(width: 26, height: 26)
    }

    // MARK: 圖例

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("正在取得真實路線 \(loadedLegs) / \(routableLegs)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            // 天的顏色
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(dayIndices, id: \.self) { d in
                        HStack(spacing: 4) {
                            Capsule().fill(TripDayPalette.color(d))
                                .frame(width: 14, height: 4)
                            Text(dayText(d))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
            }
            // 線的意思與符號
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Capsule().fill(Color.secondary).frame(width: 16, height: 3)
                    Text("實際路徑").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(Color.secondary.opacity(0.6))
                            .frame(width: 4, height: 2.5)
                    }
                    Text("直線估算").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                    Text("住宿").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8)).foregroundStyle(.orange)
                    Text("必去").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if !estimatedModesText.isEmpty {
                Text(estimatedModesText)
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color(.separator).opacity(0.15), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// 「第 2 天 8/20 (三)」。字串在 ViewBuilder 外組好。
    private func dayText(_ dayIndex: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: dayIndex,
                                         to: plan.startDate) ?? plan.startDate
        return "第 \(dayIndex + 1) 天 " + Self.dayFmt.string(from: date)
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"; return f
    }()

    /// 為什麼有些段落是虛線，在圖例裡講清楚，不然使用者會以為是壞掉。
    ///
    /// 要分成兩種：大眾運輸與飛機是**本來就沒有**路線服務可問；開車與步行則是
    /// 這一次沒載到（多半被暫時擋下）。把後者也寫成「沒有路線服務可問」是錯的。
    private var estimatedModesText: String {
        let missing = segments.filter { polylines[$0.id] == nil }
        guard !missing.isEmpty else { return "" }
        var parts: [String] = []
        let noService = Set(missing.filter { !$0.mode.supportsRouting }.map(\.mode))
        if !noService.isEmpty {
            let names = TripTravelMode.allCases.filter { noService.contains($0) }.map(\.rawValue)
            parts.append(names.joined(separator: "、") + "沒有路線服務可問，只能把兩點連起來")
        }
        let failed = missing.filter { $0.mode.supportsRouting }.count
        if failed > 0 {
            parts.append("有 \(failed) 段這次沒載到路線圖（多半是一次查太多被暫時擋下），先用直線代替")
        }
        return "虛線：" + parts.joined(separator: "；")
    }

    // MARK: 取真實路徑

    /// 逐段問 MKDirections 拿路徑。
    ///
    /// 循序做而不是一次全部並行：MKDirections 有速率限制，並行打十幾段很容易整批
    /// 被擋掉，結果全部退回直線，反而更糟。
    @MainActor
    private func loadRealRoutes() async {
        let segs = segments
        let routable = segs.filter { $0.mode.supportsRouting && polylines[$0.id] == nil }
        guard !routable.isEmpty else { return }
        routableLegs = routable.count
        loadedLegs = 0
        isLoading = true
        defer { isLoading = false }

        let slots = plan.timeline
        var requested = false
        for seg in routable {
            guard let i = slots.firstIndex(where: { $0.stop.id == seg.id }), i > 0 else { continue }
            // 每段之間隔一下：連著打十幾段一定會被地圖服務擋下來，
            // 被擋的那幾段就只剩直線可畫（v25.410 算距離時間那邊踩過同一個坑）
            if requested { try? await Task.sleep(nanoseconds: 350_000_000) }
            requested = true
            if let route = await TripRouter.route(from: slots[i - 1].stop,
                                                  to: slots[i].stop, mode: seg.mode) {
                polylines[seg.id] = route.polyline
                // 順手把先前退回估算的數字修正回真實值（同一次查詢，不多打一次網路）
                lifeStore.applyTripRoute(planId: plan.id, stopId: seg.id,
                                         meters: route.distance,
                                         seconds: route.expectedTravelTime)
            }
            loadedLegs += 1
        }
    }
}

// MARK: - 單段路線詳情

/// 點時間軸上兩站之間那一列打開的畫面：這一段的地圖、真實路線與數字。
///
/// 與整條行程的地圖分開做，是因為要看的東西不一樣：整條是看「順序合不合理」，
/// 這裡是看「這一段到底怎麼走、要多久」，所以地圖只框這兩點，數字也攤開講。
struct TripLegDetailSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let plan: TripPlan
    /// 目的地那一站的位置（與 legMeters 的歸屬一致）
    let index: Int

    @State private var polyline: MKPolyline?
    @State private var isLoading = false
    /// 路線圖要不到（多半是連續查太多被暫時擋下）。數字可能是對的，只有線畫不出來。
    @State private var routeShapeFailed = false
    @State private var sharing: ShareText?
    @State private var sharingImage: ShareImageURL?
    @State private var isExporting = false

    private struct ShareText: Identifiable {
        let id = UUID()
        let text: String
    }
    private struct ShareImageURL: Identifiable {
        let id = UUID()
        let url: URL
    }

    init(plan: TripPlan, index: Int) {
        self.plan = plan
        self.index = index
    }

    private var slots: [TripPlan.Slot] { plan.timeline }
    private var to: TripPlan.Slot? {
        slots.indices.contains(index) && index > 0 ? slots[index] : nil
    }
    private var from: TripPlan.Slot? {
        slots.indices.contains(index - 1) ? slots[index - 1] : nil
    }

    private var dayColor: Color { TripDayPalette.color(to?.dayIndex ?? 0) }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if let from, let to {
                    content(from: from, to: to)
                } else {
                    Color.clear.onAppear { dismiss() }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("這一段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            sharing = ShareText(text: TripShare.legText(plan, index: index))
                        } label: {
                            Label("分享文字", systemImage: "text.alignleft")
                        }
                        Button {
                            Task { await shareImage() }
                        } label: {
                            Label("分享成圖片", systemImage: "photo")
                        }
                    } label: {
                        if isExporting {
                            ProgressView().tint(dayColor)
                        } else {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(dayColor)
                        }
                    }
                }
            }
            .sheet(item: $sharing) { item in
                ShareSheet(items: [item.text])
            }
            .sheet(item: $sharingImage) { item in
                ShareSheet(items: [item.url])
            }
            .task { await loadRoute() }
        }
    }

    private func content(from: TripPlan.Slot, to: TripPlan.Slot) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                mapCard(from: from, to: to)
                factsCard(from: from, to: to)
                actionButtons(from: from, to: to)
            }
            .padding(.vertical)
        }
    }

    // MARK: 地圖

    private func mapCard(from: TripPlan.Slot, to: TripPlan.Slot) -> some View {
        ZStack(alignment: .topTrailing) {
            if from.stop.coordinate != nil && to.stop.coordinate != nil {
                Map(initialPosition: .automatic) {
                    if let poly = polyline {
                        MapPolyline(poly)
                            .stroke(dayColor, style: StrokeStyle(lineWidth: 5, lineCap: .round,
                                                                 lineJoin: .round))
                    } else if let a = from.stop.coordinate, let b = to.stop.coordinate {
                        // 還沒拿到（或要不到）真實路徑時先把兩點連起來，虛線表示這不是路
                        MapPolyline(coordinates: [a, b])
                            .stroke(dayColor.opacity(0.6),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round,
                                                       dash: [7, 5]))
                    }
                    if let a = from.stop.coordinate {
                        Annotation(from.stop.displayName, coordinate: a) {
                            endpointMarker(systemName: "figure.walk.departure",
                                           color: TripDayPalette.color(from.dayIndex))
                        }
                    }
                    if let b = to.stop.coordinate {
                        Annotation(to.stop.displayName, coordinate: b) {
                            endpointMarker(systemName: "mappin", color: dayColor)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 260)
                if isLoading {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.6)
                        Text("正在取得真實路線").font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
                } else if routeShapeFailed {
                    // 數字可能是對的（先前算過），只有這次要不到「線的形狀」。
                    // 不講的話畫面會變成「文字說真實路徑、地圖卻是直線」，看起來像壞掉。
                    Button {
                        Task { await loadRoute() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .bold))
                            Text("路線圖沒載到，畫的是直線・重試")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("這一段有景點沒有設座標，畫不出地圖")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .background(Color(.systemBackground))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    private func endpointMarker(systemName: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: 26, height: 26).shadow(radius: 2)
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
        }
    }

    // MARK: 數字

    private func factsCard(from: TripPlan.Slot, to: TripPlan.Slot) -> some View {
        VStack(spacing: 0) {
            endpointRow(label: "從", slot: from, time: from.departure)
            Rectangle().fill(Color(.separator).opacity(0.18))
                .frame(height: 0.5).padding(.leading, 44)
            endpointRow(label: "到", slot: to, time: to.arrival)
            Rectangle().fill(Color(.separator).opacity(0.18))
                .frame(height: 0.5).padding(.leading, 44)
            HStack(spacing: 10) {
                Image(systemName: to.mode.icon)
                    .font(.system(size: 13)).foregroundStyle(dayColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(travelHeadline(to))
                        .font(.subheadline.weight(.semibold))
                    Text(travelDetail(to))
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            // 「要不到路線」是暫時的，給一個重試的入口
            if to.canRetryRouting {
                Rectangle().fill(Color(.separator).opacity(0.18))
                    .frame(height: 0.5).padding(.leading, 44)
                retryRow
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    /// 重試那一列。要不到路線多半是暫時的，不該讓使用者只能看著估算值。
    private var retryRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 13)).foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("這一段沒拿到真實路線")
                    .font(.caption.weight(.semibold))
                Text("多半是一次查太多段被地圖服務暫時擋下（一份行程有幾十段），目前顯示的是直線估算值。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await recompute() }
                } label: {
                    Text(isLoading ? "計算中…" : "重新計算這一段")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
    }

    private func endpointRow(label: String, slot: TripPlan.Slot, time: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(TripDayPalette.color(slot.dayIndex)))
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.stop.displayName)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                let address = slot.stop.address.trimmingCharacters(in: .whitespaces)
                if !address.isEmpty {
                    Text(address).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if slot.stop.coordinate == nil {
                    Text("沒有座標").font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Text(Self.timeFmt.string(from: time))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(TripDayPalette.color(slot.dayIndex))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// 字串在 ViewBuilder 外組好
    private func travelHeadline(_ slot: TripPlan.Slot) -> String {
        guard let s = slot.travelSeconds else { return slot.mode.rawValue + "・未計算路線" }
        var t = slot.mode.rawValue + "・" + TripRouter.durationText(s)
        if let m = slot.travelMeters { t += "・" + TripRouter.distanceText(m) }
        return t
    }

    private func travelDetail(_ slot: TripPlan.Slot) -> String {
        if slot.travelSeconds == nil {
            return "兩端都要有座標才算得出距離與時間。"
        }
        guard slot.isEstimated else {
            return "向地圖服務要到的真實路徑：實際道路距離與行駛時間（依一般路況估算，不含即時路況）。"
        }
        let factor = String(format: "%.2f", slot.mode.straightLineFactor)
        var t: String
        if !slot.mode.supportsRouting {
            t = "\(slot.mode.rawValue)沒有路線服務可問（Apple 不開放），這裡是直線距離乘上迂迴係數 \(factor) 換算的。"
                + "要精確時間請用下面的按鈕開 Apple 地圖查。"
        } else if slot.canRetryRouting {
            t = "這一段暫時沒拿到真實路線，先用直線距離乘上迂迴係數 \(factor) 估算。"
        } else {
            t = "地圖服務找不到這兩點之間的路（例如中間隔著海、或那段路不能用這個方式通過），"
                + "所以用直線距離乘上迂迴係數 \(factor) 估算。"
        }
        if slot.mode.fixedOverheadMinutes > 0 {
            t += "另外加了 \(slot.mode.fixedOverheadMinutes) 分鐘固定耗時"
                + "（報到、安檢、登機、下機、等行李），不含去機場的路程。"
        }
        return t
    }

    // MARK: 按鈕

    private func actionButtons(from: TripPlan.Slot, to: TripPlan.Slot) -> some View {
        VStack(spacing: 10) {
            Button {
                TripShare.openDirectionsInMaps(from: from.stop, to: to.stop, mode: to.mode)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    Text("用 Apple 地圖導航").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(LinearGradient(colors: [dayColor, dayColor.opacity(0.75)],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    TripShare.openPlaceInMaps(to.stop)
                } label: {
                    secondaryLabel(icon: "mappin.circle.fill", text: "看目的地")
                }
                .buttonStyle(.plain)
                Button {
                    sharing = ShareText(text: TripShare.legText(plan, index: index))
                } label: {
                    secondaryLabel(icon: "square.and.arrow.up", text: "分享這一段")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private func secondaryLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(dayColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(dayColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 真實路線

    /// 出圖。地圖不能直接用畫面上那張——ImageRenderer 畫不出 SwiftUI 的 Map
    /// （那是包在 UIViewRepresentable 裡的 UIKit 元件，出圖會變成一塊空白），
    /// 所以另外用 MKMapSnapshotter 做一張，路線與大頭針自己疊上去。
    @MainActor
    private func shareImage() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        // 真實路線還沒回來就先等它（沒有的話圖上會是虛線，跟畫面一致）
        if polyline == nil { await loadRoute() }
        let image = await TripImageExporter.legMapImage(plan: plan, index: index,
                                                        polyline: polyline)
        let card = TripLegShareCard(plan: plan, index: index, mapImage: image)
        let stamp = TripImageExporter.stampFormatter.string(from: Date())
        let name = (to?.stop.displayName ?? "路線") + "_" + stamp
        guard let url = TripImageExporter.writeJPG(card, name: name) else { return }
        sharingImage = ShareImageURL(url: url)
    }

    @MainActor
    private func loadRoute() async {
        guard let from, let to, to.mode.supportsRouting, polyline == nil else { return }
        isLoading = true
        routeShapeFailed = false
        defer { isLoading = false }
        guard let route = await TripRouter.routeWithRetry(from: from.stop, to: to.stop,
                                                          mode: to.mode) else {
            routeShapeFailed = true
            return
        }
        polyline = route.polyline
        // 同一次查詢順手把數字修正回真實值。
        // 這一段先前可能是「排隊查二十幾段時被擋下來」才退回估算的——
        // 線是真的、數字卻是直線估的，那很奇怪，而且使用者已經看到了。
        lifeStore.applyTripRoute(planId: plan.id, stopId: to.stop.id,
                                 meters: route.distance, seconds: route.expectedTravelTime)
    }

    /// 手動重算這一段
    @MainActor
    private func recompute() async {
        guard let to else { return }
        isLoading = true
        defer { isLoading = false }
        polyline = nil
        lifeStore.invalidateTripLeg(planId: plan.id, stopId: to.stop.id)
        await loadRoute()
    }
}

// MARK: - 行前準備（v25.451）

/// 兩份清單：出門前要帶的東西、要帶回來的伴手禮。
///
/// 為什麼合在一張畫面而不是兩個入口：它們是同一件事的頭尾——出發前打勾「帶了」，
/// 回程前打勾「買了」。分成兩個地方只會讓人回程時忘記還有一份。
///
/// 清單刻意不跟景點綁：伴手禮常常是「回程在機場買」，硬要掛在某一站上反而要先
/// 決定在哪買，那是本末倒置。
struct TripChecklistSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let planId: UUID
    /// 從哪一份打開（摘要卡那顆按鈕預設開「帶去」）
    var initialKind: TripChecklistKind = .packing

    @State private var kind: TripChecklistKind = .packing
    @State private var newName = ""
    @State private var editing: TripChecklistItem?
    @State private var loaded = false
    @FocusState private var addFieldFocused: Bool

    private var plan: TripPlan? { lifeStore.tripPlan(id: planId) }
    private var items: [TripChecklistItem] { plan?.checklist(kind) ?? [] }
    private let accent = TripDayPalette.color(0)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $kind) {
                        ForEach(TripChecklistKind.allCases) { k in
                            Label(k.title, systemImage: k.icon).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                Section {
                    // 新增欄固定在清單最上面：打包時是連續輸入好幾條，
                    // 每加一條都要捲到底找按鈕會很煩
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(accent)
                        TextField(kind == .packing ? "要帶什麼？" : "要帶什麼回來？",
                                  text: $newName)
                            .focused($addFieldFocused)
                            .submitLabel(.done)
                            .onSubmit { addItem() }
                        if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("加入") { addItem() }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(accent)
                        }
                    }
                } footer: {
                    Text("打完直接按鍵盤的完成就會加進去，可以一條接一條打。點已經加入的項目可以改數量、給誰、備註。")
                }

                Section {
                    if items.isEmpty {
                        Text(kind.emptyHint)
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in row(item) }
                            .onDelete { idx in
                                for i in idx { deleteItem(items[i]) }
                            }
                            .onMove { from, to in
                                lifeStore.moveTripChecklistItems(planId: planId, kind: kind,
                                                                 from: from, to: to)
                            }
                    }
                } header: {
                    header
                } footer: {
                    if doneCount > 0 {
                        Button("清掉已經打勾的 \(doneCount) 條") {
                            lifeStore.clearDoneTripChecklistItems(planId: planId, kind: kind)
                        }
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("行前準備")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            .sheet(item: $editing) { item in
                TripChecklistItemEditor(planId: planId, kind: kind, item: item)
                    .environmentObject(lifeStore)
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                kind = initialKind
            }
        }
    }

    private var doneCount: Int { items.filter(\.isDone).count }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.icon).font(.system(size: 10))
            Text(kind.title)
            Spacer()
            if !items.isEmpty {
                Text("\(doneCount) / \(items.count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.14), in: Capsule())
            }
        }
    }

    private func row(_ item: TripChecklistItem) -> some View {
        HStack(spacing: 10) {
            Button {
                lifeStore.toggleTripChecklistItem(planId: planId, kind: kind, itemId: item.id)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(item.isDone ? Color.green : accent)
            }
            .buttonStyle(.plain)

            Button {
                editing = item
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.titleWithQuantity)
                        .font(.subheadline)
                        .strikethrough(item.isDone, color: .secondary)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                    let detail = detailText(item)
                    if !detail.isEmpty {
                        Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(item.isDone ? 0.65 : 1)
    }

    /// 字串在 ViewBuilder 外組好
    private func detailText(_ item: TripChecklistItem) -> String {
        var parts: [String] = []
        let who = item.forWhom.trimmingCharacters(in: .whitespaces)
        if !who.isEmpty { parts.append("給 " + who) }
        let note = item.note.trimmingCharacters(in: .whitespaces)
        if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: "・")
    }

    private func addItem() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        lifeStore.addTripChecklistItem(planId: planId, kind: kind,
                                       TripChecklistItem(name: name))
        newName = ""
        // 連續輸入：加完游標留在原地，不要每加一條都要再點一次欄位
        addFieldFocused = true
    }

    private func deleteItem(_ item: TripChecklistItem) {
        lifeStore.deleteTripChecklistItem(planId: planId, kind: kind, itemId: item.id)
    }
}

/// 單一條的細節：數量、給誰、備註。
/// 主清單只放名稱與打勾——打包時要的是快，細節點進來再說。
struct TripChecklistItemEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let planId: UUID
    let kind: TripChecklistKind
    let item: TripChecklistItem

    @State private var name = ""
    @State private var quantity = 1
    @State private var forWhom = ""
    @State private var note = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名稱", text: $name)
                    Stepper(value: $quantity, in: 1...99) {
                        HStack {
                            Text("數量")
                            Spacer()
                            Text("\(quantity)").foregroundStyle(.secondary)
                        }
                    }
                }
                // 帶出門的東西沒有「給誰」這回事，欄位只在伴手禮出現
                if kind == .souvenir {
                    Section {
                        TextField("例：媽媽、同事、自己", text: $forWhom)
                    } header: {
                        Text("買給誰")
                    }
                }
                Section {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(1...4)
                } header: {
                    Text("備註")
                }
                Section {
                    Button("刪除這一條", role: .destructive) {
                        lifeStore.deleteTripChecklistItem(planId: planId, kind: kind,
                                                          itemId: item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(kind.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }.bold()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = item.name; quantity = max(1, item.quantity)
                forWhom = item.forWhom; note = item.note
            }
        }
    }

    private func save() {
        var edited = item
        edited.name = name.trimmingCharacters(in: .whitespaces)
        edited.quantity = max(1, quantity)
        edited.forWhom = forWhom.trimmingCharacters(in: .whitespaces)
        edited.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        lifeStore.updateTripChecklistItem(planId: planId, kind: kind, edited)
        dismiss()
    }
}
