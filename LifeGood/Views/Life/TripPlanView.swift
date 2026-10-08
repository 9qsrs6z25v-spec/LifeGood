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

    /// [v25.515] 花費氣泡沒有 ScrollView、也不能被壓縮，大字級要自己減列數
    @Environment(\.dynamicTypeSize) private var typeSize

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
    /// [v25.473] 整趟天氣正在重抓（底下那顆「更新天氣」要轉圈、要擋連按）
    @State private var isRefreshingWeather = false
    /// [v25.475] 時間軸上哪幾天被手動展開／收起（dayIndex → 展開）。
    ///
    /// 只記「使用者點過的」那幾天，沒點過的走預設（過完的日子收起來）。
    /// 不在進來時把預設值灌進這個字典：那樣一旦跨過午夜，昨天就不會自己收起來。
    @State private var dayOpen: [Int: Bool] = [:]
    /// [v25.475] 從某一站的「…」直接記一筆花費
    @State private var addingExpense: StopExpenseTarget?
    /// [v25.479] 正被拖到哪一站上面（畫一條線告訴使用者會放在這裡）
    @State private var dropTargetId: UUID?
    /// [v25.517] 時間軸的卡寬（＝螢幕寬 − 32）。整條量一次，每張卡共用。
    @State private var timelineWidth: CGFloat = 0
    /// [v25.517] 正在被拖的那一站。放置提示線要畫在目標的上面還是下面，
    /// 得先知道被拖的是誰——isTargeted 只給一個 Bool。
    @State private var draggingStopId: UUID?
    /// [v25.517] 當天色拿來寫字前要依深淺色模式處理對比（TripInk）
    @Environment(\.colorScheme) private var colorScheme

    /// 走 .sheet(item:)：要帶的站與日期跟 presentation 綁在同一次寫入，
    /// 不會讀到寫入生效前的舊值（理由同上面 StopInsertion 的註解）。
    private struct StopExpenseTarget: Identifiable {
        let id = UUID()
        let stopId: UUID
        let date: Date
    }

    struct ShareStopImage: Identifiable {
        let id = UUID()
        let url: URL
    }
    @State private var showImageExport = false
    @State private var showAlbum = false
    /// [v25.480] 這趟的花費統計頁
    @State private var showExpenses = false
    /// [v25.451] 行前準備清單（要帶去的／要帶回來的）
    @State private var showChecklist = false
    /// 打開景點卡的那一站
    @State private var openingStopId: UUID?
    /// [v25.518] 看板上點了哪一天（時間軸要捲過去）。
    /// 帶一個新的 id：連點同一天也要再捲一次（只放 Int 的話第二次 onChange 不會觸發）。
    private struct DayJump: Equatable {
        let id = UUID()
        let anchor: String
    }
    @State private var dayJump: DayJump?
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
                    planScroll(p)
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
                            Divider()
                            // [v25.500] 電話是這一版才開始存的，而使用者手上
                            // 那趟行程已經排了三十幾站。一站一站重新挑地點
                            // 才拿得到電話是不合理的，所以給一個整趟補的。
                            Button {
                                Task { await fillMissingPhones() }
                            } label: {
                                Label(fillingPhones ? "正在查電話…" : "補齊所有電話",
                                      systemImage: "phone.badge.plus")
                            }
                            .disabled(fillingPhones)
                        } label: {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(accent)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("設定") { showSettings = true }.bold()
                }
            }
            .overlay(alignment: .bottom) { bannerStrip }
            // [v25.514] 在別的地方把這一站的花費刪光時，招牌會消失（金額回 nil），
            // 但氣泡是掛在那顆按鈕上的——錨點沒了就會留一個沒有主人的氣泡。
            .onChange(of: expenseStore.expenses.count) { _, _ in
                guard let id = spendPopoverStopId else { return }
                if expenseStore.ntdTotal(stopExpenses(id)) <= 0 { spendPopoverStopId = nil }
            }
            .task(id: banner) {
                guard banner != nil else { return }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { banner = nil }
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
                        items: albumItems(p),
                        stats: { TripAlbumStatsPanel(plan: p, items: albumItems(p)) })
                }
            }
            // [v25.480] 這趟的花費：統計 + 明細自成一頁
            .sheet(isPresented: $showExpenses) {
                TripExpenseSheet(planId: planId)
                    .environmentObject(lifeStore)
                    .environmentObject(expenseStore)
            }
            // [v25.475] 從某一站的「…」直接記一筆花費：行程、站別、日期都預填好
            .sheet(item: $addingExpense) { target in
                AddExpenseView(
                    expenseType: .variable,
                    preset: AddExpensePreset(linkedTripPlanId: planId,
                                             linkedTripStopId: target.stopId,
                                             date: target.date))
            }
            // [v25.472] 從時間軸點照片進來（v25.517 起是每張卡左邊的主圖）：
            // 整趟的照片一起帶，左右滑得動
            .sheet(item: $viewingPhoto) { wrapper in
                PhotoLightbox(urls: allStopPhotoURLs, current: wrapper.url)
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

    /// [v25.518] 整頁的捲動區。
    ///
    /// 時間軸（slots）與每一站的城市（places）在這裡算一次，看板與時間軸共用——
    /// 原本兩邊各算各的，看板那邊為了相本張數還會把時間軸重算幾百次（見 albumItems）。
    /// 外面包一層 ScrollViewReader：看板上的日期膠囊點了要捲到時間軸上的那一天。
    private func planScroll(_ p: TripPlan) -> some View {
        let slots = p.timeline
        let places = slots.map { TripPlaceName.parse($0.stop.address) }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard(p, slots: slots, places: places)
                    if p.stops.isEmpty {
                        emptyStops
                    } else {
                        timelineCard(p, slots: slots, places: places)
                    }
                    // [v25.480] 相本與花費改掛在摘要卡的 KPI 上（使用者指定）：
                    // 那兩塊本來是獨立的卡片夾在時間軸與「加一站」之間，
                    // 既是統計也是入口，擺在那裡等於把統計藏在半路上。
                    // 現在它們是摘要卡上可以按的兩格，點開各自是一整頁。
                    addButton(p)
                    // Apple 規定：顯示了 WeatherKit 的資料就必須標示出處
                    if showsAnyWeather(p) {
                        weatherFooter(p)
                    }
                }
                .padding(.vertical)
                // [v25.481] 這一頁只能上下捲（使用者回報整頁會被左右拖）
                .scrollVerticalOnly()
            }
            .onChange(of: dayJump) { _, jump in
                guard let jump else { return }
                // 等這一輪把那一天展開完再捲。日標頭的位置不受它自己那一天展開的影響，
                // 所以不會捲到一半跳掉。
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(jump.anchor, anchor: .top)
                    }
                }
            }
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

    // MARK: 摘要看板（v25.518）

    /// 行程頁最上面的看板（使用者的設計稿）。畫法與版面在 TripSummaryBoard.swift，
    /// 這裡只負責「放什麼」與「按了做什麼」。
    ///
    /// [v25.518] 原本這張卡走共用的英雄卡殼層（.heroCardShell(card: .tripPlan)＋霓虹天際線），
    /// 改成淺色的天空插畫之後就不吃那套漸層與 KPI 樣式了，只跟著「圓角」。
    /// .tripPlan 這個身分還有景點卡（TripStopCard）與花費統計頁（TripStats）在用，
    /// 所以設定頁的那一格留著、改了名字並寫明（HeroStyleKit、SettingsView）。
    ///
    /// 回傳 AnyView：看板裡塞了十幾種東西，在這裡把型別抹掉（深層泛型在 runtime
    /// demangle 時爆棧，設定頁閃退過）。
    private func summaryCard(_ p: TripPlan, slots: [TripPlan.Slot],
                             places: [TripPlaceName.Place?]) -> AnyView {
        let data = boardData(p, slots: slots, places: places)
        let actions = TripBoardActions(
            // [v25.451] 行前準備（交通方式＋清單進度）
            openChecklist: { showChecklist = true },
            // [v25.480] 相本與花費：既是統計也是入口
            openAlbum: { showAlbum = true },
            openExpenses: { showExpenses = true },
            // 「現在在」與「趕不上」展開後的每一站：打開景點卡（sheet，那一天收合著也打得開）
            openStop: { openingStopId = $0 },
            jumpToDay: { jumpToDay($0, slots: slots) },
            retryRouting: { Task { await retryRouting() } })
        return AnyView(
            TripSummaryBoard(data: data, actions: actions)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.horizontal, 16)
        )
    }

    /// 看板要畫的東西，一次算好。
    ///
    /// slots／places 是 planScroll 算好傳進來的（時間軸也用同一份）。這裡刻意不叫
    /// p.unreachableCount、p.totalIdleSeconds、p.endDate 這種每叫一次就把整條時間軸
    /// 重算一遍的屬性，直接從 slots 數。
    /// 還剩幾次重算沒拿掉：p.dayCount、TripDayMath.dayIndex（裡面叫 dayCount）、
    /// albumItems 的 p.dayCount、candidateExpenses 的 p.endDate。天數的規則集中在
    /// TripPlan.dayCount／TripDayMath，不在這裡抄第二份。已經比 v25.517 少很多
    /// （相本原本每張照片重算一次），之後要再省就是讓它們改吃 slots。
    private func boardData(_ p: TripPlan, slots: [TripPlan.Slot],
                           places: [TripPlaceName.Place?]) -> TripBoardData {
        var d = TripBoardData()
        let legs = Array(slots.dropFirst())
        let dayCount = p.dayCount
        let today = TripDayMath.dayIndex(Date(), in: p)
        let city = TripBoardCity.pick(slots: slots, places: places)
        let endDate = slots.last?.departure ?? p.startDate

        // 標頭
        d.seed = Self.boardSeed(p.id)
        d.departText = Self.dayFmt.string(from: p.startDate) + " 出發"
        if !p.stops.isEmpty {
            d.timeStart = Self.timeFmt.string(from: p.startDate)
            d.timeEnd = Self.timeFmt.string(from: endDate)
            // 只寫 14:40 → 15:29 的話，跨天行程看起來像當天來回
            if dayCount > 1 {
                d.spanText = "跨 \(dayCount) 天，" + Self.dayFmt.string(from: endDate) + " 結束"
            }
        }
        d.travelMode = p.travelMode
        let checklist = p.checklistTotalProgress
        d.checklistDone = checklist.done
        d.checklistTotal = checklist.total
        d.scene = TripBoardScene.pick(legModes: legs.map(\.mode), fallback: p.travelMode)
        d.city = city
        d.landmarks = TripLandmark.forBoard(city?.place)

        // 數字格子。停留原本直接寫分鐘數（2100 分），到了幾十小時就沒人讀得出來，所以寫成時長
        let dwellSeconds = Double(p.totalDwellMinutes) * 60
        let travelSeconds = p.totalTravelSeconds
        var stats = [TripBoardStat(kind: .stops, parts: TripBoardValue.count(p.stops.count, "站"),
                                   label: "景點")]
        if dayCount > 1 {
            stats.append(TripBoardStat(kind: .days, parts: TripBoardValue.count(dayCount, "天"),
                                       label: "天數"))
        }
        let nights = p.overnightCount
        if nights > 0 {
            stats.append(TripBoardStat(kind: .nights, parts: TripBoardValue.count(nights, "晚"),
                                       label: "住宿"))
        }
        stats.append(TripBoardStat(kind: .dwell, parts: TripBoardValue.duration(dwellSeconds),
                                   label: "停留"))
        stats.append(TripBoardStat(kind: .travel, parts: TripBoardValue.duration(travelSeconds),
                                   label: "交通"))
        stats.append(TripBoardStat(kind: .distance, parts: TripBoardValue.distance(p.totalMeters),
                                   label: "距離"))
        d.stats = stats

        // 格子右下角的插圖：用這趟自己的資料畫
        var art = TripBoardArt()
        art.landmark = d.landmarks.first
        art.dayCount = dayCount
        art.todayIndex = today
        art.pastDays = (0..<dayCount).filter { isPastDay(p, $0) }.count
        art.stayPhotoURL = Self.stayPhoto(slots, today: today)
        let busy = dwellSeconds + travelSeconds
        art.dwellRatio = busy > 0 ? dwellSeconds / busy : 0
        art.modesUsed = Self.modesByUse(legs)
        art.route = TripBoardRoutePoint.from(slots)
        d.art = art

        // [v25.480] 相本與花費：沒有東西的時候不擺一個 0 占位（點進去是空的只會白跑一趟）
        let album = albumItems(p, slots: slots)
        if !album.isEmpty {
            d.album = TripBoardAlbum(count: album.count, previews: Self.albumPreviews(album))
        }
        let linked = linkedExpenses(p)
        let waiting = candidateExpenses(p).count
        if !linked.isEmpty || waiting > 0 {
            let total = expenseStore.ntdTotalText(linked)
            d.spend = TripBoardSpend(
                parts: TripBoardValue.money(total),
                hint: waiting > 0 ? "還有 \(waiting) 筆待確認" : "\(linked.count) 筆・點開",
                isWaiting: waiting > 0,
                receiptLines: linked.count,
                spoken: total)
        }

        // 行程進度：開始打卡之後才出現（沒打卡的行程不用看到這個）
        let done = p.checkedOutCount
        if done > 0 && !p.stops.isEmpty {
            d.progress = TripBoardProgress(done: done, total: p.stops.count)
        }

        // 膠囊：交通方式的組成（有個別指定過才列，否則每一段都是右上角寫的那個方式）＋必去。
        // 「已完成 N/M 站」搬到行程進度卡（同一個數字寫兩次是雜訊）；
        // 「現在在」改成自己一條、可以點；住宿與花費在格子裡，這裡都不重複。
        var chips: [TripBoardChip] = []
        if p.hasModeOverride {
            for item in p.modeSegmentCounts {
                chips.append(TripBoardChip(id: "mode-" + item.mode.rawValue, icon: item.mode.icon,
                                           text: item.mode.rawValue + " \(item.count) 段",
                                           tone: .mode(item.mode)))
            }
        }
        if p.mustVisitCount > 0 {
            chips.append(TripBoardChip(id: "must", icon: "star.fill",
                                       text: "必去 \(p.mustVisitCount) 站", tone: .must))
        }
        d.chips = chips

        // 現在在哪一站（已抵達、還沒離開）
        if let currentId = p.currentStopId,
           let slot = slots.first(where: { $0.stop.id == currentId }) {
            let place: TripPlaceName.Place? = places.indices.contains(slot.index) ? places[slot.index] : nil
            d.current = TripBoardCurrent(
                stopId: currentId,
                name: slot.stop.displayName,
                photoURL: slot.stop.photoFileNames.first.map { TripStop.photoURL($0) },
                isAirport: Self.isAirport(slot.stop),
                place: place,
                latitude: slot.stop.latitude,
                longitude: slot.stop.longitude)
        }

        // 日期膠囊（跨天才有）
        if dayCount > 1 {
            d.days = (0..<dayCount).map { i in
                TripBoardDay(index: i, title: "第 \(i + 1) 天", date: Self.dayDateText(p, dayIndex: i))
            }
        }
        d.todayIndex = today

        // 提醒：原本的六種一個都沒拿掉
        var n = TripBoardNotices()
        n.isRouting = isRouting
        n.unroutedLegs = p.unroutedLegCount
        n.retryableLegs = p.retryableLegCount
        n.late = slots.filter { $0.shortfallSeconds > 60 }.map { lateItem($0) }
        if n.late.isEmpty {
            // 第一站不算（同 TripPlan.totalIdleSeconds）：出發到第一站之間是在路上，不是在等
            let idle = legs.reduce(0.0) { $0 + $1.idleSeconds }
            if idle > 300 {
                n.idleText = "為了等指定時間，中間空著 " + TripRouter.durationText(idle)
            }
        }
        // [v25.435] 天氣預報只有十天。整趟都還太遠時在這裡講一次就好——
        // 每一站各掛一句「太遠了」只是噪音。
        if Self.weatherOutOfRange(slots) {
            n.weatherText = "天氣預報只有未來 \(TripWeatherStore.forecastDays) 天，這趟還太遠，所以景點上還看不到天氣"
        }
        d.notices = n
        return d
    }

    /// 「趕不上」展開後的一列。字跟時間軸卡片底下那一行同一套（cardFlags）：
    /// 第一站沒有路段可以推算，寫「指定的時間比出發時間還早」。
    private func lateItem(_ slot: TripPlan.Slot) -> TripBoardLate {
        let title = "第 \(slot.index + 1) 站「" + slot.stop.displayName + "」"
        let detail: String
        if slot.index == 0 {
            detail = "指定的時間比出發時間還早"
        } else {
            let est = Self.timeFmt.string(from: slot.estimatedArrival ?? slot.arrival)
            detail = "推算 " + est + " 才到，差 " + TripRouter.durationText(slot.shortfallSeconds)
        }
        return TripBoardLate(stopId: slot.stop.id, title: title, detail: detail)
    }

    /// 看板插畫的種子。同一趟每次打開都是同一座城：UUID 的 hashValue 每次開 App 都不一樣，不能用
    private static func boardSeed(_ id: UUID) -> Int {
        let u = id.uuid
        return Int(u.0) << 8 | Int(u.1)
    }

    /// 住宿格的照片：今晚住的那一站有照片就用它，不然第一個有照片的過夜站。
    /// 都沒有回 nil（畫向量的床）。
    private static func stayPhoto(_ slots: [TripPlan.Slot], today: Int?) -> URL? {
        let stays = slots.filter { $0.stop.isOvernight && !$0.stop.photoFileNames.isEmpty }
        let pick = stays.first(where: { $0.dayIndex == today }) ?? stays.first
        return pick?.stop.photoFileNames.first.map { TripStop.photoURL($0) }
    }

    /// 這趟用到的交通方式，段數多的在前，最多三種（交通格的插圖）
    private static func modesByUse(_ legs: [TripPlan.Slot]) -> [TripTravelMode] {
        var counts: [TripTravelMode: Int] = [:]
        for s in legs { counts[s.mode, default: 0] += 1 }
        let used = TripTravelMode.allCases.filter { (counts[$0] ?? 0) > 0 }
        let sorted = used.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        return Array(sorted.prefix(3))
    }

    /// 相本格右邊疊的照片：只挑景點照片（花費的照片多半是收據），一站一張、新的在前，最多三張。
    /// 一張景點照片都沒有才退到花費的照片。
    private static func albumPreviews(_ items: [AlbumPhotoItem]) -> [URL] {
        let stopPhotos = items.filter { !$0.id.hasPrefix("expense-") }
        let pool = (stopPhotos.isEmpty ? items : stopPhotos).sorted { $0.date > $1.date }
        var seen: Set<String> = []
        var out: [URL] = []
        for item in pool where !seen.contains(item.group) {
            seen.insert(item.group)
            out.append(item.url)
            if out.count == 3 { break }
        }
        return out
    }

    /// 「現在在」的那一站是不是機場（是的話右半邊畫航廈，不是就放這一站的照片）
    private static func isAirport(_ stop: TripStop) -> Bool {
        let text = stop.name + " " + stop.address
        return ["機場", "空港", "航廈", "Airport", "AIRPORT", "airport"].contains { text.contains($0) }
    }

    /// [v25.518] 看板上點了第 d 天：展開那一天、捲到它的日標頭。
    ///
    /// 日期膠囊列的是「第 1 天到最後一天」每一天，但時間軸只有「有站的那幾天」才有
    /// 日標頭（最後一站過夜時的退房日、指定時間跳過的日子都沒有）。點到沒有標頭的那一天，
    /// 捲到它前面最近一個有站的日子——退房日的內容就是前一天那間飯店。
    /// 整趟的站都在同一天（只是最後一站過夜）時沒有日標頭，捲到時間軸的開頭。
    private func jumpToDay(_ d: Int, slots: [TripPlan.Slot]) {
        let days = Set(slots.map(\.dayIndex))
        guard (days.max() ?? 0) > 0 else {
            dayJump = DayJump(anchor: Self.timelineTopAnchor)
            return
        }
        let target = days.filter { $0 <= d }.max() ?? days.min() ?? 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            dayOpen[target] = true
        }
        dayJump = DayJump(anchor: Self.dayAnchor(target))
    }

    private static func dayAnchor(_ d: Int) -> String { "tripday-\(d)" }
    private static let timelineTopAnchor = "tripday-top"

    /// [v25.465] 指定算在某一站的花費。
    ///
    /// 只算「明確指定了這一站」的，沒指定站別的（記帳表單裡選「整趟（不指定）」）
    /// 不會被攤到任何一站——那是使用者刻意沒分配的，硬塞進某一站只是猜。
    private func stopExpenses(_ stopId: UUID) -> [Expense] {
        expenseStore.expenses.filter {
            $0.linkedTripPlanId == planId && $0.linkedTripStopId == stopId
        }
    }

    /// 這一站的花費金額文字；沒有花費就回 nil（不要留一個 NT$0）。
    private func stopSpendAmount(_ stopId: UUID) -> String? {
        let list = stopExpenses(stopId)
        guard !list.isEmpty, expenseStore.ntdTotal(list) > 0 else { return nil }
        // [v25.513] 把 NT$ 拔掉的那一行移除了。
        //
        // v25.504 拔它的理由是「時間欄只有 46pt，八個字塞不下」。金額這一版
        // 已經搬離時間欄（改成右下角的招牌，寬度不再是問題），而那一行讓
        // 這裡成為**全專案唯一**會把 NT$ 改寫成 $ 的地方——同一天的日標頭
        // 寫「NT$1,014」、站上寫「$1,014」，同一個數字兩種寫法。
        return expenseStore.ntdTotalText(list)
    }

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

    /// [v25.473] 時間軸上每一站的天氣膠囊是緊湊版，小到塞不進一顆按鈕
    /// （而且那一列本身可以點開景點，再疊一顆按鈕只會互相搶手勢）。
    /// 所以整趟共用一顆：按一下把這趟所有在預報範圍內的站一起重抓。
    private func weatherFooter(_ p: TripPlan) -> some View {
        VStack(spacing: 6) {
            Button {
                Task { await refreshWeather(p) }
            } label: {
                HStack(spacing: 5) {
                    if isRefreshingWeather {
                        ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(isRefreshingWeather ? "更新天氣中…" : "更新天氣")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(isRefreshingWeather)
            WeatherAttributionRow()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    @MainActor
    private func refreshWeather(_ p: TripPlan) async {
        guard !isRefreshingWeather else { return }
        isRefreshingWeather = true
        defer { isRefreshingWeather = false }
        await TripWeatherStore.shared.refreshAll(
            p.timeline
                .filter { TripWeatherStore.isWithinForecastRange($0.arrival) }
                .compactMap { $0.stop.coordinate })
    }

    /// 這趟有沒有任何一站真的顯示得出天氣
    private func showsAnyWeather(_ p: TripPlan) -> Bool {
        p.timeline.contains {
            $0.stop.coordinate != nil && TripWeatherStore.isWithinForecastRange($0.arrival)
        }
    }

    /// 整趟沒有任何一天在預報範圍內
    private static func weatherOutOfRange(_ slots: [TripPlan.Slot]) -> Bool {
        guard !slots.isEmpty,
              slots.contains(where: { $0.stop.coordinate != nil }) else { return false }
        return !slots.contains { TripWeatherStore.isWithinForecastRange($0.arrival) }
    }

    /// 這一天是幾月幾號（星期幾）。字串在 ViewBuilder 外組好。
    private static func dayDateText(_ p: TripPlan, dayIndex: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: dayIndex,
                                         to: p.startDate) ?? p.startDate
        return dayFmt.string(from: date)
    }

    /// 離開時間。跨過午夜就加「翌」，否則 09:00 看起來像同一天早上就走了。
    private static func departureText(_ slot: TripPlan.Slot) -> String {
        let t = timeFmt.string(from: slot.departure)
        return Calendar.current.isDate(slot.departure, inSameDayAs: slot.arrival)
            ? t : "翌 " + t
    }

    // MARK: 時間軸

    /// 時間軸。
    ///
    /// [v25.517] 一站一張卡（使用者的設計稿）。原本外面包著一張大卡（白底＋
    /// clipShape 圓角 18），每一站在裡面再內縮 16pt，所以一站實際只有
    /// 「螢幕寬 − 64」：440 寬的手機量起來 376pt，375 寬只剩 311pt。
    /// 那層大卡拿掉之後每張卡是「螢幕寬 − 32」，而且外面那層裁切也沒了——
    /// 它會切掉卡片的陰影，也是花費氣泡當初不能自己畫的原因（zIndex 擋不住裁切）。
    ///
    /// [v25.518] slots 與 places（地址切出的城市，每張卡要自己的也要前一站的）由 planScroll
    /// 算好傳進來，看板也用同一份。
    private func timelineCard(_ p: TripPlan, slots: [TripPlan.Slot],
                              places: [TripPlaceName.Place?]) -> some View {
        // 用手上這份 slots 判斷，不要再叫 p.dayCount——那個會把整條時間軸重算一次
        let multiDay = (slots.map(\.dayIndex).max() ?? 0) > 0
        let days = Array(Set(slots.map(\.dayIndex))).sorted()
        // 第一次排版還沒量到寬度：先用「螢幕寬 − 32」頂著（iPhone 直向就是實際卡寬），量到就換掉。
        // 不寫死 361（393 寬手機的卡寬）：375 寬在 xxLarge、430／440 寬在 xxxLarge 時，
        // 量到實際寬度後 stacked 會翻一次，整頁的卡（含天氣膠囊、主圖的 .task）全部
        // 拆掉重建（審查抓到）。
        let metrics = TripCardMetrics(cardWidth: timelineWidth > 0
                                          ? timelineWidth
                                          : UIScreen.main.bounds.width - 32,
                                      typeSize: typeSize)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                Text("時間軸").font(.subheadline.weight(.semibold))
                Spacer()
                if multiDay { dayToggleAllButton(p, days: days) }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 4)
            // [v25.518] 看板的日期膠囊捲過來的位置（整趟沒有日標頭時）
            .id(Self.timelineTopAnchor)

            ForEach(slots) { slot in
                // 換日就先插一列日期標頭（只有跨天行程才需要）
                if multiDay && slot.dayIndex != (slot.index == 0 ? -1 : slots[slot.index - 1].dayIndex) {
                    dayHeaderRow(p, dayIndex: slot.dayIndex,
                                 isFirst: slot.index == 0, slots: slots)
                        // [v25.518] 看板的日期膠囊點了捲到這裡。標頭不管那一天收合或展開都在
                        .id(Self.dayAnchor(slot.dayIndex))
                }
                // [v25.475] 收起來的那一天只留標頭。使用者回報：七天六夜要滑很久
                // 才到得了今天。單日行程沒有標頭可點，所以永遠不收。
                // （收合的那天不建卡，所以主圖、衛星快照也只會在展開的日子觸發）
                if !multiDay || isDayOpen(p, slot.dayIndex) {
                    // 前一站是過夜的地方、而且真的換了一天 → 在新的一天開頭寫「從哪裡出發」。
                    // [v25.517] 補上「換了一天」：凌晨 01:00 才入住時飯店跟下一站同一天，
                    // 原本這一列會緊貼在飯店卡底下，重複一次卡上已經寫的出發時間。
                    if slot.index > 0,
                       slots[slot.index - 1].stop.isOvernight,
                       slots[slot.index - 1].dayIndex != slot.dayIndex {
                        overnightResumeRow(slots[slot.index - 1], dayIndex: slot.dayIndex)
                    }
                    // 原本兩站之間獨立的那一列路段，併進這張卡的右上角
                    stopCard(slot, plan: p, slots: slots, places: places, metrics: metrics)
                }
            }
        }
        // 卡寬量一次、所有卡共用（每張卡各量一次是四十個 GeometryReader）。
        // 差距超過 0.5 才寫入，不會因為小數點來回跳而排版迴圈。
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            if abs(width - timelineWidth) > 0.5 { timelineWidth = width }
        }
        .padding(.horizontal)
    }

    // MARK: 時間軸：把過完的日子收起來（v25.475）

    /// 第 N 天是哪一天（以出發日起算）
    private func dayDate(_ p: TripPlan, _ dayIndex: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dayIndex, to: p.startDate) ?? p.startDate
    }

    /// 這一天已經過完了（整天都在今天之前）。今天不算過去——
    /// 正在走的那一天才是最該看見的那一天。
    private func isPastDay(_ p: TripPlan, _ dayIndex: Int) -> Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: dayDate(p, dayIndex)) < cal.startOfDay(for: Date())
    }

    /// 這一天要不要展開。
    ///
    /// 預設過完的日子收起來、今天與之後展開；使用者點過哪一天就以他的為準。
    /// 預設值是「算出來的」而不是進來時寫進字典的：寫進去的話跨過午夜之後，
    /// 昨天不會自己收起來，而這正是這個功能要解決的事。
    private func isDayOpen(_ p: TripPlan, _ dayIndex: Int) -> Bool {
        dayOpen[dayIndex] ?? !isPastDay(p, dayIndex)
    }

    /// 收起來的那一天，標頭上要寫得出「裡面有什麼」，不然收合等於把東西藏掉。
    private func daySummaryText(_ slots: [TripPlan.Slot], dayIndex: Int) -> String {
        let daySlots = slots.filter { $0.dayIndex == dayIndex }
        var parts = ["\(daySlots.count) 站"]
        let done = daySlots.filter { $0.stop.checkInState == .departed }.count
        if done > 0 { parts.append("已完成 \(done)") }
        return parts.joined(separator: "・")
    }

    /// 這一天總共花了多少。
    ///
    /// [v25.513] 從 daySummaryText 拆出來單獨一格，原因有兩個，都是真機上
    /// 看得到的毛病：
    ///
    /// 1. **它只在收合時出現。** 展開的那一天完全不寫金額，而過完的日子
    ///    預設是收合的——所以行程結束後，每一站的金額不在畫面上（整列
    ///    根本沒被建出來），唯一寫著錢的地方就是收合的日標頭。使用者說
    ///    「當站花費好像不見了」，這才是真正的原因。
    /// 2. **它被截斷成「NT$…」。** 原本整串「9 站・已完成 9・NT$3,480」
    ///    是同一個 Text 配 lineLimit(1)，空間不夠時系統從尾巴切——
    ///    被切掉的正好是金額。
    ///
    /// 現在它是獨立的一格、永遠顯示、而且 fixedSize：寧可讓右邊那條
    /// 地平線短一點，也不能把錢切掉。
    private func daySpendText(_ slots: [TripPlan.Slot], dayIndex: Int) -> String? {
        let spend = slots.filter { $0.dayIndex == dayIndex }
            .flatMap { stopExpenses($0.stop.id) }
        guard expenseStore.ntdTotal(spend) > 0 else { return nil }
        return expenseStore.ntdTotalText(spend)
    }

    /// 標頭右邊那顆：只要還有任何一天是收著的就是「全部展開」，否則「全部收合」。
    private func dayToggleAllButton(_ p: TripPlan, days: [Int]) -> some View {
        let anyClosed = days.contains { !isDayOpen(p, $0) }
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                for d in days { dayOpen[d] = anyClosed }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: anyClosed ? "chevron.down.circle" : "chevron.up.circle")
                    .font(.system(size: 10, weight: .bold))
                Text(anyClosed ? "全部展開" : "全部收合")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 時間軸的藝術元素（v25.505）
    //
    // 規矩跟行程頁最上面那張看板一樣：**藝術元素要跟它待的地方有關係**。
    // 這裡待的是一條時間軸，所以做的是「把線變成一條會發光的軌道」，
    // 不是在列與列之間貼圖案。功能性的清單加裝飾，加的必須是結構本身，
    // 不然就是在資訊上面灑亮粉。

    // [v25.517] 時間軸的主幹線 TimelineRail（v25.503，使用者要的「線條」）拿掉了：
    // 一站一張卡之後，卡片的邊與卡與卡之間的空隙就是分隔，再畫一條穿過每張卡的線
    // 會切過照片。版本紀錄與回覆都講明了，不是默默拿掉。

    /// 日期標頭右邊那條線：城市落在地平線上。
    ///
    /// 原本是一條 0.22 的灰線，把剩下的空間填掉而已。改成一條**由亮到淡**的
    /// 地平線，上面站著幾棟高低不一的小樓——跟看板上那座天際線是同一座城，
    /// 只是遠到剩下輪廓。線與樓一起往右淡出，所以它不會跟右邊的內容打架。
    private struct DayHorizonRule: View {
        let color: Color

        var body: some View {
            Canvas { context, size in
                guard size.width > 8 else { return }
                let baseY = size.height - 2.5

                var line = Path()
                line.move(to: CGPoint(x: 0, y: baseY))
                line.addLine(to: CGPoint(x: size.width, y: baseY))
                context.stroke(line, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.45), color.opacity(0.05)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)),
                               style: StrokeStyle(lineWidth: 0.9))

                // 固定種子：每次重畫都是同一座城，捲動時才不會一直在變
                var random = InkRandom(40127)
                var x: CGFloat = size.width * 0.06
                while x < size.width - 5 {
                    // [v25.507] 寬度與高度的變化都拉大。上一版兩者都太平均，
                    // 看起來像一張長條圖——而長條圖會讓人以為那是資料。
                    // 天際線之所以是天際線，就在於它高低寬窄都不講道理。
                    let w = 1.5 + CGFloat(random.next()) * 6
                    let roll = random.next()
                    let tall = roll > 0.84 ? 1.0 : (roll > 0.5 ? 0.55 : 0.28)
                    let h = 1.5 + CGFloat(tall) * CGFloat(random.next()) * 11
                    // 越往右越淡，跟地平線一起消失在遠方
                    let fade = 1 - Double(x / max(size.width, 1)) * 0.9
                    context.fill(Path(CGRect(x: x, y: baseY - h, width: w, height: h)),
                                 with: .color(color.opacity(0.34 * fade)))
                    // 偶爾一根天線
                    if random.next() > 0.78 {
                        var mast = Path()
                        mast.move(to: CGPoint(x: x + w / 2, y: baseY - h))
                        mast.addLine(to: CGPoint(x: x + w / 2, y: baseY - h - 3))
                        context.stroke(mast, with: .color(color.opacity(0.26 * fade)),
                                       style: StrokeStyle(lineWidth: 0.7))
                    }
                    x += w + 2 + CGFloat(random.next()) * 8
                }
            }
            .frame(height: 15)
            .allowsHitTesting(false)
        }
    }

    /// 換日的分隔列。跨天行程一天一個色系，這一列把顏色與日期講明白。
    /// [v25.475] 整列可點＝收合／展開這一天；收著的時候寫出站數、完成數與花費。
    private func dayHeaderRow(_ p: TripPlan, dayIndex: Int, isFirst: Bool,
                              slots: [TripPlan.Slot]) -> some View {
        let c = TripDayPalette.color(dayIndex)
        let open = isDayOpen(p, dayIndex)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                dayOpen[dayIndex] = !open
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(c)
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text("第 \(dayIndex + 1) 天")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(c, in: Capsule())
                Text(Self.dayDateText(p, dayIndex: dayIndex))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c)
                if !open {
                    Text(daySummaryText(slots, dayIndex: dayIndex))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // [v25.513] 當天花費：收合或展開都顯示，而且 fixedSize——
                // 擠不下時縮的是右邊那條地平線，不是錢。
                if let money = daySpendText(slots, dayIndex: dayIndex) {
                    Text(money)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .fixedSize()
                }
                DayHorizonRule(color: c)
            }
            // [v25.517] 外面沒有那張大卡了：跟卡片左緣對齊，換日前多留一點
            .padding(.horizontal, 4)
            .padding(.top, isFirst ? 4 : 14)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 住宿的地方在隔天開頭再出現一次：它是前一天最後一站，也是今天的第一站。
    ///
    /// [v25.517] 新卡片之後**這一列一定要留**：隔天早上前一天已經過完、預設收合，
    /// 飯店那張卡（寫著大字 07:00）根本沒有被建出來。這一列是今天唯一寫著
    /// 「幾點從哪裡出發」的地方，也是下一張卡右上那段路的起點。
    /// 刻意做成一條細膠囊，不做成卡片（v25.402：「刻意做得比景點列輕」）。
    private func overnightResumeRow(_ slot: TripPlan.Slot, dayIndex: Int) -> some View {
        let c = TripDayPalette.color(dayIndex)
        let ink = TripInk.text(c, colorScheme)
        let time = Self.timeFmt.string(from: slot.departure)
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 10))
                .foregroundStyle(ink)
            Text(time)
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(ink)
            // 不用 Spacer 把鉛筆推到右邊：HStack 的 spacing 會在 Spacer 兩側各加一次
            Text("從「" + slot.stop.displayName + "」出發")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                editingStop = slot.stop
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("修改退房時間")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(c.opacity(0.08), in: Capsule())
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(time + " 從「" + slot.stop.displayName + "」出發")
    }

    private func legText(_ slot: TripPlan.Slot) -> String {
        guard let secs = slot.travelSeconds else { return "未計算路線" }
        var t = TripRouter.durationText(secs)
        if let m = slot.travelMeters { t += "・" + TripRouter.distanceText(m) }
        return t
    }

    // MARK: 時間軸：一站一張卡（v25.517）

    /// 一站。骨架與零件在 TripTimelineCard.swift，這裡只負責「放什麼」。
    ///
    /// 回傳 AnyView：一張卡裡塞了十幾種東西，不在這裡把型別抹掉，
    /// ForEach 底下的泛型型別名稱會長到 runtime demangle 時爆棧（設定頁閃退過）。
    private func stopCard(_ slot: TripPlan.Slot, plan p: TripPlan,
                          slots: [TripPlan.Slot], places: [TripPlaceName.Place?],
                          metrics m: TripCardMetrics) -> AnyView {
        let c = TripDayPalette.color(slot.dayIndex)
        // [v25.513] 一張卡只算一次（這支會跑 expenses.filter 加總）
        let spend = stopSpendAmount(slot.stop.id)
        let place = places.indices.contains(slot.index) ? places[slot.index] : nil
        let prevPlace: TripPlaceName.Place? = (slot.index > 0 && places.indices.contains(slot.index - 1))
            ? places[slot.index - 1] : nil
        let firstOfDay = slot.index == 0 || slots[slot.index - 1].dayIndex != slot.dayIndex
        // 地標只畫在「進入這座城市」的那一站：二十站都在福岡，福岡塔只出現一次
        let entersCity = place != nil && (firstOfDay || prevPlace?.key != place?.key)
        let fliesNext = slots.indices.contains(slot.index + 1) && slots[slot.index + 1].mode == .plane
        // 底帶＝天際線的高度（天際線不往上探，免得透到膠囊排的字後面）：
        // 一般 14；有花費招牌 28（招牌約 19 高、離底 4，跟膠囊排之間留 5）。
        // [v25.518] 第一站原本 26（要放「Have a nice trip!」），那句搬到看板上寫，這裡收回來。
        let band: CGFloat = spend == nil ? 14 : 28
        let card = TripStopCardFrame(
            metrics: m,
            topCapsule: topCapsule(slot, plan: p, color: c),
            hero: AnyView(heroView(slot, color: c)),
            heroOverlay: AnyView(heroOverlay(slot, color: c, place: place,
                                             hasSpend: spend != nil, metrics: m)),
            column: AnyView(cardColumn(slot, color: c, metrics: m)),
            chipRow: chipRow(slot, color: c, place: place, metrics: m),
            skyline: AnyView(TripCardSkyline(
                color: c, seed: slot.index,
                landmarks: entersCity ? TripLandmark.forCity(place?.zh) : [],
                // 下一段要搭飛機才畫（v25.517 第一站也畫，那是配那句手寫字的）
                planeTrail: fliesNext)),
            spendSign: spend.map { AnyView(stopSpendSign(slot, amount: $0, color: c)) },
            bottomBand: band,
            footer: slot.stop.subSpots.isEmpty ? nil : AnyView(
                TripSubSpotList(items: subSpotDisclosures(slot.stop), color: c,
                                isOver: slot.stop.subSpotMinutes > slot.stop.dwellMinutes)),
            // 點整張卡＝打開景點卡（v25.421 的教訓：要去地圖、編輯、打卡都在卡片上選）
            onTap: { openingStopId = slot.stop.id })
        let below = dropLandsBelow(slot)
        return AnyView(
            card
                // 卡與卡之間 12pt：放置提示線畫在這個空隙的正中間
                .padding(.vertical, 6)
                // 空隙也要算放置目標：透明的 padding 不在判定範圍裡，而提示線就畫在這裡——
                // 手指移到線上就進了死區，線消失、放手沒反應（審查抓到）。
                // （點空隙不會誤開景點卡：整卡的 onTapGesture 在裡層的 TripStopCardFrame 上）
                .contentShape(Rectangle())
                // [v25.479] 整張卡是放置目標（含右上的路段膠囊）
                .dropDestination(for: String.self) { items, _ in
                    dropStop(items, onto: slot)
                } isTargeted: { over in
                    if over {
                        dropTargetId = slot.stop.id
                    } else if dropTargetId == slot.stop.id {
                        // 從 A 拖到 B 時，B 的 true 可能比 A 的 false 先到；
                        // 只清自己的，不要把 B 剛設好的清掉
                        dropTargetId = nil
                    }
                }
                .overlay(alignment: below ? .bottom : .top) {
                    dropIndicator(slot, below: below)
                }
        )
    }

    // MARK: 卡片右上：路段膠囊（第一站是「出發」膠囊）

    private func topCapsule(_ slot: TripPlan.Slot, plan p: TripPlan, color c: Color) -> AnyView {
        if slot.index == 0 { return AnyView(departureCapsule(slot, plan: p, color: c)) }
        return AnyView(
            TripLegCapsule(
                icon: slot.mode.icon,
                // [v25.403] 單獨指定過交通方式的段落要分得出來
                modeLabel: slot.isModeOverridden ? slot.mode.rawValue : nil,
                text: legText(slot),
                note: nil,
                // [v25.399／403] 估算的數字一定要標「估」
                isEstimated: slot.isEstimated,
                // 趕不上：整顆轉紅；「推算幾點才到，差多少」寫在狀態面板底下那一行
                isLate: slot.shortfallSeconds > 60,
                color: c,
                art: Self.legArt(slot.mode),
                seed: slot.index,
                a11yLabel: legA11y(slot),
                insertA11yLabel: "在第 \(slot.index + 1) 站前面插入景點",
                onOpen: { legDetail = LegBox(index: slot.index) },
                onInsert: { insertion = StopInsertion(at: slot.index) })
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            // 長按換交通方式（「…」選單裡的「這一段怎麼過來」也還在）
            .contextMenu { legModeMenu(slot) }
        )
    }

    /// 第一站前面沒有路段。那一格不空著：寫「幾點出發」，⊕ 插在第一站前面
    /// （原本做不到——路段的 ⊕ 只出現在第 2 站以後，選單只能插在某站後面）。
    private func departureCapsule(_ slot: TripPlan.Slot, plan p: TripPlan, color c: Color) -> some View {
        let start = Self.timeFmt.string(from: p.startDate)
        let late = slot.shortfallSeconds > 60
        let note: String? = (!late && slot.idleSeconds > 60)
            ? "出發後 " + TripRouter.durationText(slot.idleSeconds) + " 抵達"
            : nil
        var a11y = "行程 " + start + " 出發"
        if late { a11y += "，第一站指定的時間比出發時間還早" }
        if let note { a11y += "，" + note }
        a11y += "。點兩下修改出發時間"
        return TripLegCapsule(
            icon: "flag.fill",
            modeLabel: nil,
            text: "出發 " + start,
            note: note,
            isEstimated: false,
            isLate: late,
            color: c,
            art: .start,
            seed: slot.index,
            a11yLabel: a11y,
            insertA11yLabel: "在第一站前面插入景點",
            // 出發時間在行程設定裡改
            onOpen: { showSettings = true },
            onInsert: { insertion = StopInsertion(at: 0) })
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private static func legArt(_ mode: TripTravelMode) -> TripLegStreetArt.Style {
        switch mode {
        case .walking: return .walk
        case .plane: return .flight
        case .driving, .transit: return .road
        }
    }

    private func legA11y(_ slot: TripPlan.Slot) -> String {
        var parts = ["從上一站" + slot.mode.rawValue]
        parts.append(slot.travelSeconds == nil
                     ? "還沒算出路線"
                     : legText(slot).replacingOccurrences(of: "・", with: "，"))
        if slot.isEstimated { parts.append("時間是估的") }
        if slot.shortfallSeconds > 60 {
            parts.append("差 " + TripRouter.durationText(slot.shortfallSeconds) + " 趕不上")
        } else if slot.idleSeconds > 300 {
            parts.append("到了要等 " + TripRouter.durationText(slot.idleSeconds))
        }
        return parts.joined(separator: "，") + "。點兩下看這一段路線"
    }

    /// 路段膠囊的長按選單：就是「…」裡的「這一段怎麼過來」
    @ViewBuilder
    private func legModeMenu(_ slot: TripPlan.Slot) -> some View {
        Button("用行程預設（" + (plan?.travelMode ?? .driving).rawValue + "）") {
            setLegMode(slot.stop.id, nil)
        }
        ForEach(TripTravelMode.allCases) { mode in
            Button(mode.rawValue) { setLegMode(slot.stop.id, mode) }
        }
        Divider()
        Button("看這一段的路線") { legDetail = LegBox(index: slot.index) }
    }

    // MARK: 卡片左邊：照片

    @ViewBuilder
    private func heroView(_ slot: TripPlan.Slot, color c: Color) -> some View {
        let first = slot.stop.photoFileNames.first.map { TripStop.photoURL($0) }
        let count = slot.stop.photoFileNames.count
        let image = TripHeroImage(photoURL: first,
                                  coordinate: slot.stop.coordinate,
                                  dayColor: c,
                                  pinKey: ((slot.dayIndex % 6) + 6) % 6,
                                  seed: slot.index)
        if let first {
            // 使用者自己的照片：點了開大圖（整趟的照片一起帶，左右滑得動）
            Button {
                viewingPhoto = IdentifiableURL(url: first)
            } label: {
                image
            }
            .buttonStyle(.plain)
            .accessibilityLabel(count > 1 ? "這一站的照片，共 \(count) 張" : "這一站的照片")
            .accessibilityHint("點兩下放大")
        } else if slot.stop.coordinate == nil {
            // 沒有座標：沒有衛星圖、天氣、路線。這一格最有用的事就是叫人去選位置
            Button {
                editingStop = slot.stop
            } label: {
                image
            }
            .buttonStyle(.plain)
            .accessibilityLabel("還沒有設定位置")
            .accessibilityHint("點兩下選位置")
        } else {
            // 衛星快照：純裝飾，點了跟點卡片一樣
            image.accessibilityHidden(true)
        }
    }

    /// 照片上疊的東西：左上序號、左下手寫城市名、「實際入住」、購物車。
    /// （序號、張數、城市名、「實際入住」都不吃點擊，點到它們會落到底下的照片）
    @ViewBuilder
    private func heroOverlay(_ slot: TripPlan.Slot, color c: Color,
                             place: TripPlaceName.Place?, hasSpend: Bool,
                             metrics m: TripCardMetrics) -> some View {
        let tag = checkInTag(slot)
        let photos = slot.stop.photoFileNames.count
        // 衛星快照底部可能有 Apple 地圖的標誌，左下那疊東西要讓開
        let inset: CGFloat = (photos == 0 && slot.stop.coordinate != nil)
            ? TripHeroStore.mapAttributionInset : 0
        if m.stacked {
            ZStack(alignment: .topLeading) {
                HStack(spacing: 4) {
                    TripCardBadge(number: slot.index + 1, color: c,
                                  isMustVisit: slot.stop.isMustVisit)
                    if photos >= 2 { TripPhotoCountTag(count: photos) }
                }
                .padding(8)
                HStack(alignment: .bottom, spacing: 6) {
                    if let tag { TripCheckInTag(text: tag.text, icon: tag.icon, color: c) }
                    cartButton(slot, hasSpend: hasSpend)
                    Spacer(minLength: 8)
                    TripCityScript(place: place, coordinate: slot.stop.coordinate, maxWidth: 150)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8 + inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    TripCardBadge(number: slot.index + 1, color: c,
                                  isMustVisit: slot.stop.isMustVisit)
                    if photos >= 2 { TripPhotoCountTag(count: photos) }
                }
                Spacer(minLength: 6)
                TripCityScript(place: place, coordinate: slot.stop.coordinate,
                               maxWidth: m.photoBottom - 12)
                if let tag {
                    TripCheckInTag(text: tag.text, icon: tag.icon, color: c)
                        .padding(.top, 6)
                }
                // [v25.479] 購物車（使用者指定位置：「實際」下面）。
                // 「實際」變成照片左下的「實際入住」之後，購物車跟著貼在它底下。
                cartButton(slot, hasSpend: hasSpend)
                    .padding(.top, 6)
            }
            .padding(.leading, 8)
            .padding(.top, 8)
            .padding(.bottom, 8 + inset)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    /// 原本時間欄的「實際」：打過卡的時間是事實，跟排出來的分開標示。
    /// 設計稿照片左下的「🛏 實際入住」就是它（這個對應是推測，回覆裡跟使用者確認）。
    private func checkInTag(_ slot: TripPlan.Slot) -> (text: String, icon: String)? {
        if slot.isActualArrival {
            return slot.stop.isOvernight
                ? (text: "實際入住", icon: "bed.double.fill")
                : (text: "實際抵達", icon: "mappin.circle.fill")
        }
        if slot.isActualDeparture { return (text: "實際離開", icon: "figure.walk.departure") }
        return nil
    }

    /// [v25.479] 購物車：記一筆這一站的花費（行程、站別、日期預填）。
    /// 不可以只留在「…」選單裡——v25.479 就是因為藏在選單裡要點兩下才拉出來的。
    private func cartButton(_ slot: TripPlan.Slot, hasSpend: Bool) -> some View {
        Button {
            addingExpense = StopExpenseTarget(stopId: slot.stop.id, date: slot.arrival)
        } label: {
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 12.5, weight: .semibold))
                // 已經有金額時是「再記一筆」，退淡一點不要跟招牌搶
                .foregroundStyle(hasSpend ? Color.green.opacity(0.7) : Color.green)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.45), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.6))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasSpend ? "再記一筆這一站的花費" : "記一筆這一站的花費")
    }

    // MARK: 卡片右欄：標題、地址、備註、狀態面板、提醒

    private func cardColumn(_ slot: TripPlan.Slot, color c: Color,
                            metrics m: TripCardMetrics) -> some View {
        let address = TripCardText.addressWithoutPostal(slot.stop.displayAddress)
        let note = slot.stop.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let flags = cardFlags(slot)
        let noCoordinate = slot.stop.coordinate == nil
        let stopId = slot.stop.id
        let a11yTitle = "第 \(slot.index + 1) 站，" + slot.stop.displayName
            + (slot.stop.isMustVisit ? "，必去" : "")
        return VStack(alignment: .leading, spacing: 0) {
            // 不用 Spacer 把右邊兩顆推過去：HStack 的 spacing 會在 Spacer 兩側各加一次，
            // 白白從標題拿走寬度。標題自己吃掉剩餘寬度。
            // ⚠️ 兩顆圓鈕各 28＋三段 spacing 2 ＝ 60，要跟 TripCardMetrics.titleAccessoryWidth 一致
            HStack(alignment: .top, spacing: 2) {
                // [v25.517] 標題退回右欄（設計稿），**一行、放不下就跑馬燈**
                // （使用者指定：「不做折行，可以用跑馬燈方式」）。
                // 右欄只有兩百出頭 pt，照設計稿折行的話長名字要三行，整張卡跟著變高。
                // 不套 .textCase(.uppercase)：設計稿的大寫是資料本來就大寫，套上去
                // 「Familymart Hakata…」會變全大寫、寬 16.5%。
                TripMarqueeText(text: slot.stop.displayName,
                                font: .subheadline.weight(.semibold),
                                accessibilityText: a11yTitle)
                    .foregroundStyle(.primary)
                    .padding(.top, 3)
                    .accessibilityHint("點兩下打開景點卡")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { openingStopId = stopId }
                reorderHandle(slot)
                stopMenu(slot, color: c)
            }
            if !address.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    // 沒座標就把 📍 換成橘色 ⚠︎（底下那一行講原因）
                    Image(systemName: noCoordinate ? "exclamationmark.triangle.fill" : "mappin")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(noCoordinate ? Color.orange : TripInk.text(c, colorScheme))
                    Text(address)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("地址 " + address)
            }
            // 備註原本跟地址擠在同一段 preview 裡；設計稿只有地址一行，
            // 不另外給它一行的話備註就默默消失了
            if !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            statusPanel(slot, color: c, metrics: m)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.top, 8)
            if !flags.isEmpty {
                TripCardFlagList(flags: flags, dayColor: c)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .padding(.top, 6)
            }
        }
    }

    /// 「✓ 已抵達 23:05 ｜ 🛏 過夜・隔天出發 07:00 ›」。
    /// 原本時間欄的抵達／離開時間、鎖、紅字、打卡圈，與膠囊列的
    /// 「已抵達」「過夜」「停留 N 分」「指定 HH:mm 抵達」都收進這裡。
    private func statusPanel(_ slot: TripPlan.Slot, color c: Color,
                             metrics m: TripCardMetrics) -> TripStatusPanel {
        let ink = TripInk.text(c, colorScheme)
        let arrival = Self.timeFmt.string(from: slot.arrival)
        let late = slot.shortfallSeconds > 60
        let leftLabel = slot.isActualArrival ? "已抵達" : (slot.isFixedArrival ? "指定抵達" : "預計抵達")
        let left = TripStatusPanel.Half(
            glyph: "clock",
            label: leftLabel,
            time: arrival,
            tint: c,
            ink: late ? Color.red : ink,
            showsLock: slot.isFixedArrival,
            a11y: leftLabel + " " + arrival + (late ? "，照推算會趕不上" : ""))

        // 右半的長標籤（「過夜・隔天出發」）只在寬卡、而且字沒放大時用：
        // 440 寬設 xxxLarge 時長標籤會被截（審查抓到）
        let longLabel = m.roomy && typeSize < .xxLarge
        let right: TripStatusPanel.Half
        if slot.isActualDeparture {
            let t = Self.departureText(slot)
            right = TripStatusPanel.Half(glyph: "checkmark", label: "已離開", time: t,
                                         tint: c, ink: ink, showsLock: false,
                                         a11y: "已離開 " + t)
        } else if slot.stop.isOvernight {
            // 「隔天」要照實算：凌晨 01:00 入住、09:00 退房是同一天
            // （原本的「過夜」膠囊寫死「隔天」，那種情況寫錯了）
            let nextDay = !Calendar.current.isDate(slot.departure, inSameDayAs: slot.arrival)
            let t = Self.timeFmt.string(from: slot.departure)
            let label: String
            if nextDay {
                label = longLabel ? "過夜・隔天出發" : "隔天出發"
            } else {
                label = longLabel ? "過夜・退房出發" : "退房出發"
            }
            right = TripStatusPanel.Half(glyph: "bed.double.fill", label: label, time: t,
                                         tint: .indigo, ink: TripInk.indigo(colorScheme),
                                         showsLock: false,
                                         a11y: "過夜，" + (nextDay ? "隔天 " : "") + t + " 出發")
        } else {
            let t = Self.departureText(slot)
            // 沿用原本膠囊的寫法「停留 N 分」：375 寬時右半只剩約 65pt，
            // 「停留 1 小時 30 分」放不下
            let dwell = "停留 \(max(0, slot.stop.dwellMinutes)) 分"
            right = TripStatusPanel.Half(glyph: "hourglass", label: dwell, time: t,
                                         tint: c, ink: ink, showsLock: false,
                                         a11y: dwell + "，" + t + " 離開")
        }

        var checkIn: TripStatusPanel.CheckIn?
        if showsCheckIn(slot) {
            let id = slot.stop.id
            checkIn = TripStatusPanel.CheckIn(state: slot.stop.checkInState,
                                              a11y: checkInA11y(slot),
                                              action: {
                lifeStore.advanceTripStopCheckIn(planId: planId, stopId: id)
            })
        }
        return TripStatusPanel(left: left, right: right,
                               rightDone: slot.isActualDeparture,
                               color: c, checkIn: checkIn)
    }

    private func checkInA11y(_ slot: TripPlan.Slot) -> String {
        switch slot.stop.checkInState {
        case .notArrived: return "打卡：還沒到。點兩下記錄現在抵達"
        case .arrived: return "打卡：已抵達。點兩下記錄現在離開"
        case .departed: return "打卡：已離開。點兩下清除這一站的打卡"
        }
    }

    /// 原本 stopChips 裡**不能消失**的那些，一行一行寫在狀態面板底下。
    /// （stopChips 每一種的去向：fixed→面板左半的鎖；here／night／dwell→面板；
    ///  must→序號圈的星；photo→照片左上的張數；sub→子地點那一列）
    private func cardFlags(_ slot: TripPlan.Slot) -> [TripCardFlag] {
        var out: [TripCardFlag] = []
        if slot.index == 0 {
            if slot.shortfallSeconds > 60 {
                out.append(TripCardFlag(id: "late", icon: "exclamationmark.triangle.fill",
                                        text: "指定的時間比出發時間還早", tone: .red))
            }
        } else if slot.shortfallSeconds > 60 {
            let est = Self.timeFmt.string(from: slot.estimatedArrival ?? slot.arrival)
            out.append(TripCardFlag(id: "late", icon: "exclamationmark.triangle.fill",
                                    text: "推算 " + est + " 才到，差 "
                                        + TripRouter.durationText(slot.shortfallSeconds),
                                    tone: .red))
        } else if slot.idleSeconds > 300 {
            // 跟原本路段上的「等 N」是同一件事（門檻都是 300 秒），合併後只留這一個
            out.append(TripCardFlag(id: "idle", icon: "hourglass",
                                    text: "比預計早到，空 " + TripRouter.durationText(slot.idleSeconds),
                                    tone: .neutral))
        }
        // 打卡之後用事實說話：實際停留多久
        if let actual = slot.stop.actualDwellSeconds {
            let planned = Double(max(0, slot.stop.dwellMinutes)) * 60
            var text = "實際停留 " + TripRouter.durationText(actual)
            // 過夜的站不比多少：停留分鐘對過夜的站沒有意義（離開時間是退房時刻）
            if !slot.stop.isOvernight, planned > 0, abs(actual - planned) >= 300 {
                text += actual > planned
                    ? "（多 " + TripRouter.durationText(actual - planned) + "）"
                    : "（少 " + TripRouter.durationText(planned - actual) + "）"
            }
            out.append(TripCardFlag(id: "actualDwell", icon: "checkmark.circle.fill",
                                    text: text, tone: .day))
        }
        // 比原本推算的早到還是晚到（衡量的是這一段路＋上一站有沒有拖到）
        if slot.isActualArrival {
            let delta = slot.arrival.timeIntervalSince(slot.plannedArrival)
            if abs(delta) >= 300 {
                out.append(TripCardFlag(
                    id: "delta",
                    icon: delta > 0 ? "arrow.down.right" : "arrow.up.right",
                    text: delta > 0
                        ? "比預估晚 " + TripRouter.durationText(delta)
                        : "比預估早 " + TripRouter.durationText(-delta),
                    tone: delta > 0 ? .orange : .green))
            }
        }
        if slot.stop.coordinate == nil {
            let stop = slot.stop
            out.append(TripCardFlag(id: "nocoord", icon: "exclamationmark.triangle.fill",
                                    text: "未設座標：沒有路線、天氣與地圖。點這裡選位置",
                                    tone: .orange,
                                    action: { editingStop = stop }))
        }
        // 子地點的分鐘加起來超過停留時間 → 排程對不上
        if slot.stop.subSpotMinutes > slot.stop.dwellMinutes {
            out.append(TripCardFlag(id: "over", icon: "exclamationmark.circle.fill",
                                    text: "子地點共 \(slot.stop.subSpotMinutes) 分，超過停留時間",
                                    tone: .red))
        }
        return out
    }

    // MARK: 卡片底排：天氣、電話、查看地圖

    private func chipRow(_ slot: TripPlan.Slot, color c: Color,
                         place: TripPlaceName.Place?, metrics m: TripCardMetrics) -> AnyView? {
        let stop = slot.stop
        let hasWeather = stop.coordinate != nil && TripWeatherStore.isWithinForecastRange(slot.arrival)
        let phone = stop.phone?.trimmingCharacters(in: .whitespaces) ?? ""
        let hasPhone = !phone.isEmpty
        let hasMap = stop.coordinate != nil
            || !stop.address.trimmingCharacters(in: .whitespaces).isEmpty
        // 三顆都沒有就整排不建：照片下段也就不內收，曲線一路到底
        guard hasWeather || hasPhone || hasMap else { return nil }
        // 天氣兩行（「25°／15°」＋「福岡・晴時多雲」）只在 430／440 寬：
        // 窄的手機兩行版會把電話或地圖擠出這一排
        let twoLine = hasWeather && m.roomy && !m.stacked
        let height: CGFloat? = twoLine ? 28 : nil
        let openMap = { TripShare.openPlaceInMaps(stop) }
        if m.stacked {
            // 字很大時可以換行（ChipFlowLayout 只會建一份天氣膠囊，不會重複載入）
            return AnyView(
                ChipFlowLayout(spacing: 6) {
                    if hasWeather {
                        TripWeatherChip(coordinate: stop.coordinate, date: slot.arrival,
                                        cityName: place?.zh)
                    }
                    if hasPhone {
                        StopPhoneTag(raw: phone, minHeight: nil) { digits in
                            banner = "已複製 " + digits
                        }
                    }
                    if hasMap {
                        TripMapChip(style: .full, color: c, minHeight: nil, action: openMap)
                    }
                }
            )
        }
        return AnyView(
            HStack(spacing: 6) {
                if hasWeather {
                    // [v25.478] 點了更新這一站的天氣（使用者指定），重試、☂、更新中的回饋都照舊
                    TripWeatherChip(coordinate: stop.coordinate, date: slot.arrival,
                                    twoLine: twoLine, cityName: place?.zh)
                }
                if hasPhone {
                    // [v25.500] 點了複製給車機用的純數字（日本車機用電話找目的地）
                    StopPhoneTag(raw: phone, minHeight: height) { digits in
                        banner = "已複製 " + digits
                    }
                }
                if hasMap {
                    // ⚠️ ViewThatFits 只包這一顆：天氣膠囊自己帶 @StateObject 與 .task，
                    //    放進好幾個候選會被建好幾份、重複載入
                    ViewThatFits(in: .horizontal) {
                        TripMapChip(style: .full, color: c, minHeight: height, action: openMap)
                        TripMapChip(style: .short, color: c, minHeight: height, action: openMap)
                        TripMapChip(style: .icon, color: c, minHeight: height, action: openMap)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    /// 這一站花了多少——掛在右下角那座小城上的招牌（v25.513，使用者指定）。
    ///
    /// **刻意不畫進 Canvas 裡。** 直覺做法是把金額當成霓虹招牌畫在建築上，
    /// 但那條路整條是壞的，三個理由都是硬傷：
    ///
    /// 1. **塞不下。** 那座城最寬的一棟樓只有 25pt 上下，照本專案既有的
    ///    招牌字級公式算，「$1,014」會變成三到六點的字——比現在的 10pt 還小，
    ///    跟「我看不到金額」這個訴求正好相反。
    /// 2. **對比不夠。** 日期色是六個寫死的 sRGB 常數，不分深淺色模式；
    ///    全濃度壓在系統背景上最高只有 3.4:1，連 WCAG AA 都不到。
    /// 3. **讀不到也按不到。** Canvas 的內容不在輔助使用的樹裡，VoiceOver
    ///    唸不出來；而且整個底圖層是 allowsHitTesting(false)。
    ///
    /// 底圖層自己的規矩就是答案：「可以被看見，不可以被讀」。金額是這一列
    /// 唯一非讀不可的數字，它不屬於那一層。所以做成真正的 Text，疊在
    /// **內容之上**（overlay，不是 backdrop），白字壓在當天色的實心牌子上，
    /// 看起來仍然是立在那座城上的一塊招牌。
    ///
    /// [v25.517] 更正：上面原本寫「深淺色模式都過得了對比」，算出來不成立——
    /// 11pt 粗白字壓在原色上只有 2.32（橘）～3.43（紫），11pt 不算大字，要 4.5。
    /// 牌子改用壓暗 40% 的當天色（TripInk.solid），5.8～7.7。
    @ViewBuilder
    private func stopSpendSign(_ slot: TripPlan.Slot, amount: String?,
                               color c: Color) -> some View {
        if let amount {
            let isOpen = spendPopoverStopId == slot.stop.id
            Button {
                spendPopoverStopId = isOpen ? nil : slot.stop.id
            } label: {
                Text(amount)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    // 不用 minimumScaleFactor：牌子跟著字長，字不跟著牌子縮。
                    // 縮過的數字跟畫面上其他數字不一樣大，一看就是擠出來的。
                    .fixedSize()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(TripInk.solid(c))
                    )
                    .shadow(color: c.opacity(0.35), radius: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "這一站花費 \(amount)，明細已展開，點一下收起"
                                       : "這一站花費 \(amount)，點開可以看明細")
            // [v25.514] 用系統 popover，不是自己在列上疊一個氣泡。
            //
            // 自己疊的那條路整條是壞的，而且是幾何問題不是風格問題：
            // 包住所有列的那個 VStack 套了 .clipShape(cornerRadius: 18)
            // （v25.517 一站一張卡之後那層裁切拿掉了，但下面那筆帳還在），
            // 任何溢出卡片的東西都會被裁掉——**zIndex 只排序繪製，擋不住裁切**。
            // 算過：三筆花費的氣泡約 153pt 高，而「只有一站、剛記了午餐」
            // 的那張卡整張才 135pt，氣泡比卡片還高，往上往下都無解。
            //
            // popover 是 presentation 層：不受那層裁切影響、自己翻邊、
            // 自己夾進螢幕、內容過高自己可捲，點外面關閉與 VoiceOver 的
            // modal 行為都是系統給的。代價是箭頭是系統的樣式，不是手繪的尾巴。
            .popover(isPresented: Binding(
                get: { spendPopoverStopId == slot.stop.id },
                set: { spendPopoverStopId = $0 ? slot.stop.id : nil })) {
                stopSpendDetail(slot, color: c)
            }
            // [v25.513 使用者指定「顯示在右下那個建築物上」] 新卡片右下就是線稿天際線
            .padding(.trailing, 10)
            .padding(.bottom, 4)
        }
    }

    /// 點金額跳出來的那張消費清單（v25.514 新增，v25.515 改標籤與版面）。
    ///
    /// v25.514 已經處理掉的三個坑，繼續由共用件守著：外幣逐筆加不起來
    /// （右邊一律寫台幣，原幣當註記）、合計被縮成「NT$1.4萬」
    /// （ExpenseStore.ntdPlainTotalText）、排序跟景點卡不一致
    /// （ExpenseStore.stopRowSorted）。
    ///
    /// [v25.515] 使用者回報「都顯示一樣的名字」。原因是每一行主標直接讀 e.title，
    /// 而記帳表單從某一站進來時會把站名寫進名稱欄（fillPlaceFromStop →
    /// applyMapPickedPlace → placeQuery，非汽車分類的 placeQuery 就是 $title），
    /// 所以同一站每一筆的 title 都是同一個站名——而上面的標頭已經寫過一次了。
    /// 行內改走 Expense.stopRowLabel，站名在行內出現 0 次。
    @ViewBuilder
    private func stopSpendDetail(_ slot: TripPlan.Slot, color c: Color) -> some View {
        let all = expenseStore.stopRowSorted(stopExpenses(slot.stop.id))
        // 大字級時列數跟著減：每列多一行副標，AX 級別會把合計與「看全部」頂出螢幕
        let limit = typeSize >= .accessibility1 ? 3 : (typeSize >= .xxLarge ? 4 : 5)
        let shown = Array(all.prefix(limit))
        let hidden = Array(all.dropFirst(shown.count))
        // 純運算式，不要寫成 var ＋ if：這支是 @ViewBuilder，函式本體裡的 if
        // 會被當成「條件式的 View」去建，而 names.append(...) 回傳 Void 不是 View。
        let names = [slot.stop.displayName] + (plan?.stops.map { $0.displayName } ?? [])
        // 提示列的條件用**整站全部**算，景點卡也是同一批——否則同一份資料兩種答案
        let needNoteHint = stopRowsNeedNoteHint(all, suppressing: names)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(c)
                // [v25.516] 相對字級：寫死 12pt 的話大字級時它會變成整張氣泡最小的字
                Text(slot.stop.displayName)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)

            ForEach(shown) { e in
                StopExpenseRow(expense: e,
                               suppressing: names,
                               contextDay: slot.arrival,
                               compact: true,
                               fallbackAccent: c,
                               store: expenseStore)
                    .padding(.vertical, 5)
            }

            if needNoteHint {
                // 這一行不是常駐的：有寫備註的人永遠看不到它。
                // 它指向「看全部」而不是「下次記帳時」——那張卡的每一列現在
                // 可以點開，當場就補得到備註。氣泡上的列刻意不做可點：
                // popover 上再疊一層 sheet 是在跟 presentation 層賭運氣。
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 9, weight: .semibold))
                    Text("分不出來的那幾筆，點「看全部」補上「備註」就會顯示在這一行")
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            // 沒列出來的也要寫小計，否則列出的那幾筆加不到下面的合計
            if !hidden.isEmpty {
                Text("還有 \(hidden.count) 筆（\(expenseStore.ntdPlainTotalText(hidden))）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            Divider().padding(.vertical, 7)

            HStack {
                Text("合計").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                // 值走 ntdTotal，與招牌（stopSpendAmount）同一個來源
                // [v25.516] 相對字級：寫死 17pt 配會放大的「合計」，大字級時標籤比數字大
                Text(expenseStore.ntdPlainTotalText(all))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(c)
            }

            Button {
                spendPopoverStopId = nil
                openingStopId = slot.stop.id
            } label: {
                HStack(spacing: 4) {
                    Text("看全部").font(.caption.weight(.semibold))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(c)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(14)
        // 250 → 288：窄的時候主標只放得下七、八個中文字，備註一填就被切掉。
        // 上限壓在 288 是因為最小的 iPhone（SE3／13 mini）直向只有 375pt：
        // 288 ＋ 兩側 16pt 安全邊 ＝ 320，氣泡才會指著招牌而不是橫跨整列。
        .frame(width: 288)
        .fixedSize(horizontal: false, vertical: true)
        // 固定寬度沒辦法誠實支援 accessibility 全部級別；夾在 AX2，
        // 配上面的 limit，最壞 3 列 ＋ 提示 ＋ 溢出仍放得下。
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        // iPhone 上預設會退化成 sheet，指定 .popover 才會是真的氣泡
        .presentationCompactAdaptation(.popover)
    }

    /// [v25.479] 拖曳把手（使用者指定：標題右邊的三條線）。
    ///
    /// 只有把手可以拖、不是整張卡：整張卡要能點開景點卡，而且時間軸是捲動的，
    /// 整張可拖會跟捲動搶手勢。長按約一秒把它提起來，拖到想放的位置放開——
    /// 這是系統拖放的既定手感，不是另外做一套。
    ///
    /// 選單裡的「往前移一站／往後移一站」保留：只差一格的時候點一下比拖準得多。
    /// [v25.517] 樣子換成設計稿的灰底圓鈕（24pt，點擊範圍 28）。
    private func reorderHandle(_ slot: TripPlan.Slot) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Color(.tertiarySystemFill), in: Circle())
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            // 短按把手不要跑去開景點卡——它只負責拖
            .onTapGesture { }
            // payload 是 autoclosure：系統真的開始拖的時候才求值，
            // 所以在這裡記下「被拖的是誰」（提示線要靠它決定畫上面還是下面）
            .draggable(dragPayload(slot)) { dragPreview(slot) }
            .accessibilityLabel("拖曳調整順序")
            .accessibilityHint("長按後拖到想放的位置。只差一格時，用「更多動作」的往前移、往後移比較準")
    }

    private func dragPayload(_ slot: TripPlan.Slot) -> String {
        let id = slot.stop.id
        // 不在這個呼叫裡直接寫 @State：萬一系統是在畫面更新途中求值，會變成
        // 「在 view update 時改狀態」。排到下一輪主執行緒。
        DispatchQueue.main.async { draggingStopId = id }
        return id.uuidString
    }

    /// 提起來時跟著手指走的那張小卡
    private func dragPreview(_ slot: TripPlan.Slot) -> some View {
        HStack(spacing: 6) {
            Text("\(slot.index + 1)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(TripInk.solid(TripDayPalette.color(slot.dayIndex))))
            Text(slot.stop.displayName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.systemBackground), in: Capsule())
    }

    /// 放開後會落在目標的上面還是下面。
    ///
    /// [v25.517] 修一個 v25.479 就有的錯：往下拖時 dropStop 用 to + 1，那一站實際落在
    /// 目標的**下面**，但提示線永遠畫在上面——跟「上方會出現一條線告訴你會落在
    /// 哪裡」那句說明不符。現在線畫在它真的會落下的那一側。
    private func dropLandsBelow(_ target: TripPlan.Slot) -> Bool {
        guard let dragging = draggingStopId, dragging != target.stop.id,
              let stops = plan?.stops,
              let from = stops.firstIndex(where: { $0.id == dragging }) else { return false }
        return from < target.index
    }

    /// 拖到這一站上面時，在卡與卡之間的空隙畫一條線：放開會落在這裡。
    ///
    /// [v25.517] 不再貼著卡片頂邊畫：路段併進卡片之後，卡片頂邊就是路段膠囊，
    /// 貼著畫會壓在膠囊上。卡片外面已經沒有裁切，所以畫到卡片外面不會被切掉。
    @ViewBuilder
    private func dropIndicator(_ slot: TripPlan.Slot, below: Bool) -> some View {
        // 懸停在被拖的那一站自己身上不畫線：dropStop 對自己是無效放置，畫了等於騙人
        // （v25.479 就有）。draggingStopId 還是 nil 時照舊畫，不會比原本更糟。
        if dropTargetId == slot.stop.id && draggingStopId != slot.stop.id {
            Capsule()
                .fill(TripDayPalette.color(slot.dayIndex))
                .frame(height: 3)
                .padding(.horizontal, 8)
                // 卡片上下各 6pt 內距，間隙 12pt：線的中心對準間隙正中間
                .offset(y: below ? 1.5 : -1.5)
                .allowsHitTesting(false)
        }
    }

    /// 把拖著的那一站放到目標這一站的位置。
    ///
    /// 回傳 false＝這次放置沒有意義（放回自己身上，或拖進來的根本不是這趟的站——
    /// 放置目標吃的是純文字，別的地方拖一段字進來也會走到這裡）。
    private func dropStop(_ items: [String], onto target: TripPlan.Slot) -> Bool {
        dropTargetId = nil
        draggingStopId = nil
        guard let raw = items.first,
              let draggedId = UUID(uuidString: raw),
              draggedId != target.stop.id,
              let p = plan,
              let from = p.stops.firstIndex(where: { $0.id == draggedId }),
              let to = p.stops.firstIndex(where: { $0.id == target.stop.id })
        else { return false }
        // move(fromOffsets:toOffset:) 的 toOffset 是「插在這個位置之前」，
        // 所以往後搬要 +1 才會落在目標那一站的後面；往前搬不用。
        lifeStore.moveTripStops(planId: planId,
                                from: IndexSet(integer: from),
                                to: to > from ? to + 1 : to)
        return true
    }

    private func stopMenu(_ slot: TripPlan.Slot, color c: Color) -> some View {
        Menu {
            Button("打開景點卡") { openingStopId = slot.stop.id }
            Button("編輯") { editingStop = slot.stop }
            // [v25.475] 使用者要求：在行程頁就能直接記這一站的花費，
            // 不用跳去記帳頁再回頭挑行程與站別。日期帶這一站的抵達
            // 時間（打過卡的話時間軸給的就是實際時間），行程與站別
            // 直接預填，開進去只要填金額。
            Button("記一筆這一站的花費") {
                addingExpense = StopExpenseTarget(stopId: slot.stop.id,
                                                  date: slot.arrival)
            }
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
            // [v25.500] 日本車機用電話找目的地，所以「拷貝電話」跟「拷貝地址」
            // 是同一層的動作，不是藏在聯絡資訊裡的附加功能。
            if let raw = slot.stop.phone,
               !raw.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("拷貝電話（車機導航用）") {
                    let digits = TripPhone.navDigits(raw)
                    UIPasteboard.general.string = digits
                    banner = "已複製 " + digits
                }
                Button("撥打電話") {
                    let dial = TripPhone.dialDigits(raw)
                    if let url = URL(string: "tel://" + dial) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Divider()
            Button("刪除", role: .destructive) { removingStop = slot.stop }
        } label: {
            // [v25.517] 設計稿的圓鈕：當天色 12% 底，24pt，點擊範圍 28
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TripInk.text(c, colorScheme))
                .frame(width: 24, height: 24)
                .background(c.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(c.opacity(0.35), lineWidth: 0.75))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("更多動作")
    }

    /// [v25.472] 這趟所有站的照片，依時間軸順序攤平。
    ///
    /// 用整趟而不是只有那一站：時間軸上照片是一站一張（v25.517 起是卡片左邊的
    /// 主圖，原本是一站一條照片條），但使用者點進去之後
    /// 想往下看的是「接下來的照片」，不是「這一站看完就停住」。順序照時間軸排，
    /// 與畫面上看到的一致。
    private var allStopPhotoURLs: [URL] {
        (plan?.stops ?? []).flatMap { $0.photoFileNames.map { TripStop.photoURL($0) } }
    }

    /// 相本要吃的資料。分組字串帶上「第幾天」，依景點分組出來就是照日子與順序排好的。
    private func albumItems(_ p: TripPlan) -> [AlbumPhotoItem] {
        // timeline 是每次取用都重算的，先取一次——下面查站別的分組還要用
        albumItems(p, slots: p.timeline)
    }

    /// [v25.518] 原本在「每一張照片」的閉包裡叫 p.dayCount，而 dayCount 每叫一次就把整條
    /// 時間軸重算一遍：293 張照片＝重算 293 次，每次 47 站，看板每次重畫都要跑一輪。
    /// 改成迴圈外算一次（結果一模一樣，只是不重算）。
    private func albumItems(_ p: TripPlan, slots: [TripPlan.Slot]) -> [AlbumPhotoItem] {
        let dayPrefix = p.dayCount > 1
        var items = slots.flatMap { slot in
            slot.stop.photoFileNames.map { name in
                AlbumPhotoItem(
                    id: name,
                    url: TripStop.photoURL(name),
                    group: (dayPrefix ? "第 \(slot.dayIndex + 1) 天・" : "")
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
                group = (dayPrefix ? "第 \(slots[i].dayIndex + 1) 天・" : "")
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

    /// 一站的電話（卡片底排中間那顆）。
    ///
    /// 樣式刻意跟天氣膠囊**一模一樣**（10pt 粗體、灰字、tertiarySystemFill
    /// 的膠囊底）：它們並排在同一行，長得不一樣只會讓那一行看起來是拼湊的。
    ///
    /// 顯示用 Apple 分好組的寫法（092-291-0001），複製給車機用的是純數字
    /// （0922910001）——看的人要斷點，機器不要。
    ///
    /// [v25.517] 設計稿在號碼後面畫了一個 ›，但這顆的動作是「複製」不是「進下一層」，
    /// 畫 › 會讓人以為點了會打開什麼，所以不畫。撥打放在長按選單（「…」裡也有）。
    private struct StopPhoneTag: View {
        let raw: String
        /// 底排三顆要一樣高（天氣兩行時是 28）。nil＝照字的高度。
        /// ⚠️ 宣告在 onCopy 前面：呼叫端用尾隨閉包傳 onCopy，參數順序要對得上
        var minHeight: CGFloat? = nil
        let onCopy: (String) -> Void

        var body: some View {
            Button {
                copy()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 9))
                    Text(TripPhone.display(raw))
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                }
                .fixedSize()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .frame(minHeight: minHeight)
                .background(Color(.tertiarySystemFill), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    copy()
                } label: {
                    Label("拷貝電話（車機導航用）", systemImage: "doc.on.doc")
                }
                Button {
                    if let url = URL(string: "tel://" + TripPhone.dialDigits(raw)) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("撥打電話", systemImage: "phone")
                }
            }
            .accessibilityLabel("電話 " + TripPhone.display(raw))
            .accessibilityHint("點兩下拷貝給車機導航用的號碼；長按可以撥打")
        }

        private func copy() {
            let digits = TripPhone.navDigits(raw)
            UIPasteboard.general.string = digits
            onCopy(digits)
        }
    }

    @ViewBuilder
    private var bannerStrip: some View {
        if let banner {
            Text(banner)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    /// 替整趟行程裡還沒有電話的站補上。
    ///
    /// 一次查一站，查完才查下一站：三十幾個 MKLocalSearch 同時打出去會被
    /// Apple 節流，結果是大部分都查不到。慢一點但補得齊。
    ///
    /// 每補一筆就重讀一次行程才寫回去——查詢要花好幾秒，這期間使用者可能
    /// 還在改行程，拿一開始那份舊的整包蓋回去會把他剛做的事抹掉。
    @MainActor
    private func fillMissingPhones() async {
        guard !fillingPhones, let snapshot = plan else { return }
        fillingPhones = true
        defer { fillingPhones = false }

        let targets = snapshot.stops.filter {
            !$0.hasPhone && $0.coordinate != nil
                && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !targets.isEmpty else {
            banner = "每一站都已經有電話了"
            return
        }

        var filled = 0
        for (i, stop) in targets.enumerated() {
            banner = "正在查電話… \(i + 1) / \(targets.count)"
            guard let coordinate = stop.coordinate else { continue }
            guard let found = await TripPhoneLookup.phone(
                name: stop.name.trimmingCharacters(in: .whitespaces),
                coordinate: coordinate) else { continue }
            guard var latest = lifeStore.tripPlan(id: planId),
                  let idx = latest.stops.firstIndex(where: { $0.id == stop.id })
            else { continue }
            latest.stops[idx].phone = found
            lifeStore.upsertTripPlan(latest)
            filled += 1
        }
        // 查不到就說查不到。Apple 地圖沒有的電話，我編不出來。
        banner = filled == 0
            ? "這 \(targets.count) 站都查不到電話"
            : "補上了 \(filled) 支電話（共查 \(targets.count) 站）"
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

    /// [v25.514] 哪一站的花費清單氣泡開著（使用者要求：點金額跳出消費清單）
    @State private var spendPopoverStopId: UUID?

    /// 畫面下方那一行短暫的回饋（複製了什麼、補了幾支電話）。
    /// 沒有回饋的複製等於沒發生——使用者會再按一次，然後懷疑它壞了。
    @State private var banner: String?
    /// 正在替整趟行程補電話
    @State private var fillingPhones = false

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
    /// [v25.500] 電話。在日本這是導航欄位——見 TripStop.phone
    @State private var phone = ""
    /// 正在向 Apple 地圖查這個地方的電話
    @State private var lookingUpPhone = false
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
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.title).font(.subheadline).foregroundStyle(.primary)
                                        if !r.subtitle.isEmpty {
                                            Text(r.subtitle).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    // [v25.499] 距離是從這趟行程的所在地量的，
                                    // 不是從使用者身上——在台北排福岡的行程，
                                    // 「離我 1200 公里」挑不出任何東西。
                                    PlaceDistanceBadge(meters: completer.distance(for: r),
                                                       icon: "mappin")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("地址", text: $address)
                    // [v25.500] 電話。
                    //
                    // 擺在地址正下方，因為在日本它們是同一件事的兩種寫法——
                    // 而且車機只吃得下其中一種。日文地址在車機的鍵盤上幾乎
                    // 打不出來，當地的做法是輸入電話號碼，機器直接定位。
                    HStack(spacing: 8) {
                        TextField("電話（日本車機導航用）", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                        if lookingUpPhone {
                            ProgressView().scaleEffect(0.7)
                        } else if phone.trimmingCharacters(in: .whitespaces).isEmpty,
                                  latitude != nil {
                            // 這一站是以前排的（那時候還不會存電話），
                            // 給一個按鈕現在補回來，不用重新挑一次地點
                            Button("查詢") { lookUpPhone() }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(accent)
                        }
                    }
                    MapPlacePickerButton(
                        startCoordinate: mapPickerStart,
                        hasCoordinate: latitude != nil,
                        accent: accent,
                        onPick: { place in
                            applyPickedLocation(place)
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
                phone = e.phone ?? ""
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
    /// 把搜尋偏向與距離起點一起對準某個座標。
    /// 兩件事一定要一起做：只偏向不算距離，使用者還是不知道選哪個；
    /// 只算距離不偏向，清單裡根本不會出現那個地方。
    private func aimSearch(at coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        completer.setRegion(MKCoordinateRegion(center: coordinate,
                                               latitudinalMeters: 40000,
                                               longitudinalMeters: 40000))
        completer.setReference(CLLocation(latitude: coordinate.latitude,
                                          longitude: coordinate.longitude))
    }

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
    private func applyPickedLocation(_ place: PickedPlace) {
        latitude = place.coordinate.latitude
        longitude = place.coordinate.longitude
        // 地圖上挑到的地標帶電話就收下。已經填過的不覆蓋——
        // 使用者可能自己打了分機或訂位專線。
        if let picked = place.phone, !picked.isEmpty,
           phone.trimmingCharacters(in: .whitespaces).isEmpty {
            phone = picked
        }
        fill.apply(name: place.name, address: place.address,
                   into: $name, addressField: $address)
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
        // [v25.499] 搜尋偏向與距離起點都用**這趟行程所在的地方**
        //（自己的座標 → 上一站 → 行程錨點），不是使用者現在站的地方。
        // 在台北排福岡的行程時，「離我 1200 公里」挑不出任何東西，
        // 而搜「7-11」先跳台北的門市更是直接幫倒忙。
        aimSearch(at: mapPickerStart)
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
                if let found = item.phoneNumber, !found.isEmpty,
                   phone.trimmingCharacters(in: .whitespaces).isEmpty {
                    phone = found
                }
                fill.apply(name: nil,
                           address: TripAddress.tidy(
                            [pm.postalCode, pm.administrativeArea, pm.locality,
                             pm.thoroughfare, pm.subThoroughfare]
                                .compactMap { $0 }.joined()),
                           into: $name, addressField: $address)
            }
        }
    }

    /// 替這一站補上電話。
    ///
    /// 以前排的行程沒有存電話（那時候還沒有這個欄位），而一趟日本行程常常
    /// 有三、四十站，要使用者一站一站重新挑地點是不合理的。這裡用已經存著的
    /// 座標與名稱去問一次 Apple 地圖——它本來就知道，只是以前沒跟它要。
    private func lookUpPhone() {
        guard !lookingUpPhone, let latitude, let longitude else { return }
        let target = name.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        lookingUpPhone = true
        Task {
            let found = await TripPhoneLookup.phone(
                name: target,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            await MainActor.run {
                lookingUpPhone = false
                if let found { phone = found }
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
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        stop.phone = trimmedPhone.isEmpty ? nil : trimmedPhone
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
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).font(.subheadline).foregroundStyle(.primary)
                                    if !r.subtitle.isEmpty {
                                        Text(r.subtitle).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                // 子地點量的是「離這一站多遠」——老街裡的某一攤，
                                // 你要知道的是它離你排的那個點走不走得到。
                                PlaceDistanceBadge(meters: completer.distance(for: r),
                                                   icon: "mappin")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField("地址", text: $sub.address)
                TextField("電話（日本車機導航用）",
                          text: Binding(get: { sub.phone ?? "" },
                                        set: { sub.phone = $0.isEmpty ? nil : $0 }))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                MapPlacePickerButton(
                    startCoordinate: mapPickerStart,
                    hasCoordinate: sub.latitude != nil,
                    accent: accent,
                    subtitle: "老街裡的某一攤、園區裡的某個館，點地圖最快",
                    onPick: { place in
                        sub.latitude = place.coordinate.latitude
                        sub.longitude = place.coordinate.longitude
                        if let picked = place.phone, !picked.isEmpty,
                           (sub.phone ?? "").isEmpty {
                            sub.phone = picked
                        }
                        fill.apply(name: place.name, address: place.address,
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

    /// 見 TripStopEditView.aimSearch
    private func aimSearch(at coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        completer.setRegion(MKCoordinateRegion(center: coordinate,
                                               latitudinalMeters: 40000,
                                               longitudinalMeters: 40000))
        completer.setReference(CLLocation(latitude: coordinate.latitude,
                                          longitude: coordinate.longitude))
    }

    private func scheduleSearch(_ q: String) {
        searchDebounce?.cancel()
        let text = q.trimmingCharacters(in: .whitespaces)
        fill.userEditedName(text)
        guard text.count >= 2 else { completer.queryFragment = ""; return }
        // 子地點搜的是「這一站附近還有什麼」，所以起點是這一站
        aimSearch(at: mapPickerStart)
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
                if let found = item.phoneNumber, !found.isEmpty, (sub.phone ?? "").isEmpty {
                    sub.phone = found
                }
                fill.apply(name: nil,
                           address: TripAddress.tidy(
                            [pm.postalCode, pm.administrativeArea, pm.locality,
                             pm.thoroughfare, pm.subThoroughfare]
                                .compactMap { $0 }.joined()),
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
