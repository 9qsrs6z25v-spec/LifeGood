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
    @Environment(\.dismiss) private var dismiss

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
                TripPlanDetailView(planId: box.id).environmentObject(lifeStore)
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
        }
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
                            addButton(p)
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
                        Button {
                            sharing = ShareText(text: TripShare.planText(p))
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
                if let p = plan { TripRouteMapSheet(plan: p) }
            }
            .sheet(item: $legDetail) { box in
                if let p = plan {
                    TripLegDetailSheet(plan: p, index: box.index)
                }
            }
            .sheet(item: $sharing) { item in
                ShareSheet(items: [item.text])
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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.dayFmt.string(from: p.startDate) + " 出發 "
                         + Self.timeFmt.string(from: p.startDate))
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                    Text(p.stops.isEmpty ? "尚未加入景點"
                         : Self.timeFmt.string(from: p.startDate) + " – "
                           + Self.timeFmt.string(from: p.endDate))
                        .font(.title3.weight(.bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: p.travelMode.icon).font(.system(size: 10, weight: .bold))
                    Text(p.travelMode.rawValue).font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.75))
            }
            Rectangle().fill(Color.white.opacity(0.20)).frame(height: 0.5)
            HStack(spacing: 0) {
                kpi("景點", "\(p.stops.count)", "站")
                if p.dayCount > 1 { kpi("天數", "\(p.dayCount)", "天") }
                kpi("停留", "\(p.totalDwellMinutes)", "分")
                kpi("交通", p.totalTravelSeconds > 0
                    ? TripRouter.durationText(p.totalTravelSeconds) : "—", "")
                kpi("距離", p.totalMeters > 0
                    ? TripRouter.distanceText(p.totalMeters) : "—", "")
            }
            if p.hasModeOverride { modeMixRow(p) }
            if p.mustVisitCount > 0 || p.overnightCount > 0 { marksRow(p) }
            if p.dayCount > 1 { dayLegend(p) }
            if isRouting {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).tint(.white)
                    Text("正在計算路線…").font(.caption2).foregroundStyle(.white.opacity(0.9))
                }
            } else if p.unroutedLegCount > 0 {
                Text("有 \(p.unroutedLegCount) 段還沒算出路線")
                    .font(.caption2).foregroundStyle(.white.opacity(0.85))
            }
            if p.unreachableCount > 0 {
                Text("⚠️ 有 \(p.unreachableCount) 站的指定抵達時間比推算的還早，照這個排法趕不上")
                    .font(.caption2).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            } else if p.totalIdleSeconds > 300 {
                Text("為了等指定時間，中間空著 " + TripRouter.durationText(p.totalIdleSeconds))
                    .font(.caption2).foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(16)
        .background(
            ZStack {
                LinearGradient(colors: [accent, accent.opacity(0.62)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.white.opacity(0.10)).blur(radius: 18)
                    .frame(width: 140, height: 140).offset(x: 110, y: -52)
                Circle().fill(Color.white.opacity(0.08)).blur(radius: 12)
                    .frame(width: 90, height: 90).offset(x: -118, y: 46)
                LinearGradient(colors: [Color.white.opacity(0.18), .clear],
                               startPoint: .top, endPoint: .center)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }

    /// 有段落被單獨指定過交通方式時，列出整趟混了哪些方式各幾段
    private func modeMixRow(_ p: TripPlan) -> some View {
        HStack(spacing: 6) {
            ForEach(p.modeSegmentCounts) { item in
                HStack(spacing: 3) {
                    Image(systemName: item.mode.icon).font(.system(size: 9))
                    Text("\(item.count) 段").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.white.opacity(0.18), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    /// 必去與住宿的計數。這兩個是排行程時最常看的標記，放在摘要卡上。
    private func marksRow(_ p: TripPlan) -> some View {
        HStack(spacing: 6) {
            if p.mustVisitCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 9))
                    Text("必去 \(p.mustVisitCount) 站").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.white.opacity(0.18), in: Capsule())
            }
            if p.overnightCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "bed.double.fill").font(.system(size: 9))
                    Text("住宿 \(p.overnightCount) 晚").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.white.opacity(0.18), in: Capsule())
            }
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
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.white.opacity(0.16), in: Capsule())
                }
            }
        }
    }

    /// 離開時間。跨過午夜就加「翌」，否則 09:00 看起來像同一天早上就走了。
    private static func departureText(_ slot: TripPlan.Slot) -> String {
        let t = timeFmt.string(from: slot.departure)
        return Calendar.current.isDate(slot.departure, inSameDayAs: slot.arrival)
            ? t : "翌 " + t
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

    private func kpi(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.55)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 9)).foregroundStyle(.white.opacity(0.8))
                }
            }
            Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
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

    /// 住宿的地方在隔天開頭再出現一次：它是當天最後一站，也是隔天的第一站。
    /// 這一列不是另一個景點，只是把「早上從這裡出發」講清楚，所以刻意做得比景點列輕。
    private func overnightResumeRow(_ slot: TripPlan.Slot, dayIndex: Int) -> some View {
        let c = TripDayPalette.color(dayIndex)
        return HStack(alignment: .center, spacing: 10) {
            Text(Self.timeFmt.string(from: slot.departure))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(c)
                .frame(width: 42)
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
            Text("").frame(width: 42)
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
                .foregroundStyle(slot.shortfallSeconds > 60 ? Color.red : c)
                Text(Self.departureText(slot))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 42)

            ItemRow(
                chips: stopChips(slot),
                title: slot.stop.displayName,
                preview: stopPreview(slot.stop),
                disclosures: subSpotDisclosures(slot.stop),
                disclosureLabel: "子地點",
                disclosureColor: c,
                onTap: { editingStop = slot.stop },
                leading: {
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
                },
                accessory: {
                    Menu {
                        Button("編輯") { editingStop = slot.stop }
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
                        Button("分享這一站") { shareStop(slot.stop) }
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
        guard var p = plan, let i = p.stops.firstIndex(where: { $0.id == stopId }) else { return }
        p.stops[i].isMustVisit.toggle()
        lifeStore.upsertTripPlan(p)
    }

    /// 換順序。往後移要 +2——SwiftUI 的 move(toOffset:) 算的是「移除前的索引」，
    /// 給 index + 1 只會插回原位。
    private func move(_ index: Int, by delta: Int) {
        let dest = delta < 0 ? index - 1 : index + 2
        lifeStore.moveTripStops(planId: planId, from: IndexSet(integer: index), to: dest)
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
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text(p.stops.isEmpty ? "加入第一個景點" : "在最後加一站")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(LinearGradient(colors: [accent, accent.opacity(0.75)],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: accent.opacity(0.28), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
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
    @State private var loaded = false
    @State private var isSaving = false
    /// 新增的照片先記下來，取消時要刪掉——不然按取消也會留下檔案
    @State private var addedPhotos: Set<String> = []

    // 地點搜尋（沿用飲食／就醫紀錄那一套 MKLocalSearchCompleter）
    @StateObject private var completer = RestaurantSearchCompleter()
    @State private var searchDebounce: Task<Void, Never>?

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
                    if latitude != nil {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(accent)
                            Text("已帶入座標").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("清除") {
                                latitude = nil; longitude = nil
                            }
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("地點")
                } footer: {
                    Text(latitude == nil
                         ? "打名稱會出現搜尋建議，選一個就會帶入地址與座標。沒有座標的景點不會被算進路線距離與時間。"
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

                TripSubSpotEditor(subSpots: $subSpots, dwellMinutes: dwellMinutes, accent: accent)

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

    private func scheduleSearch(_ q: String) {
        // 打字就打斷搜尋建議的既有選擇（改了名字座標通常也不對了），
        // 但不主動清座標——使用者可能只是修錯字
        searchDebounce?.cancel()
        let text = q.trimmingCharacters(in: .whitespaces)
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
        name = r.title
        completer.queryFragment = ""
        // 建議只有文字，要再做一次 MKLocalSearch 才拿得到座標
        Task {
            let req = MKLocalSearch.Request(completion: r)
            guard let item = try? await MKLocalSearch(request: req).start().mapItems.first else { return }
            await MainActor.run {
                let pm = item.placemark
                latitude = pm.coordinate.latitude
                longitude = pm.coordinate.longitude
                if address.trimmingCharacters(in: .whitespaces).isEmpty {
                    address = [pm.postalCode, pm.administrativeArea, pm.locality,
                               pm.thoroughfare, pm.subThoroughfare]
                        .compactMap { $0 }.joined()
                }
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

    var body: some View {
        Section {
            if subSpots.isEmpty {
                Text("還沒有子地點。像老街、園區這種一個景點裡有好幾攤的地方，可以拆進來。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($subSpots) { $sub in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("子地點名稱", text: $sub.name)
                        Button(role: .destructive) {
                            subSpots.removeAll { $0.id == sub.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    Stepper(value: $sub.minutes, in: 0...600, step: 10) {
                        HStack {
                            Text("預計").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(sub.minutes == 0 ? "未安排" : "\(sub.minutes) 分")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    TextField("備註", text: $sub.note)
                        .font(.caption)
                }
                .padding(.vertical, 2)
            }
            Button {
                subSpots.append(TripSubSpot())
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
                Text("子地點只是這一站底下的細項，不會各自計算路線；時間軸上會收在這一站的摺疊區裡。")
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

    /// 哪些方式本來就畫不出真實路徑，在圖例裡講清楚，不然使用者會以為是壞掉
    private var estimatedModesText: String {
        let modes = Set(segments.filter { polylines[$0.id] == nil }.map(\.mode))
        guard !modes.isEmpty else { return "" }
        let names = TripTravelMode.allCases.filter { modes.contains($0) }.map(\.rawValue)
        return "虛線：" + names.joined(separator: "、") + " 沒有路線服務可問，只能把兩點連起來"
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
        for seg in routable {
            guard let i = slots.firstIndex(where: { $0.stop.id == seg.id }), i > 0 else { continue }
            if let poly = await TripRouter.routePolyline(from: slots[i - 1].stop,
                                                        to: slots[i].stop,
                                                        mode: seg.mode) {
                polylines[seg.id] = poly
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
    @Environment(\.dismiss) private var dismiss

    let plan: TripPlan
    /// 目的地那一站的位置（與 legMeters 的歸屬一致）
    let index: Int

    @State private var polyline: MKPolyline?
    @State private var isLoading = false
    @State private var sharing: ShareText?

    private struct ShareText: Identifiable {
        let id = UUID()
        let text: String
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
                    Button {
                        sharing = ShareText(text: TripShare.legText(plan, index: index))
                    } label: {
                        Image(systemName: "square.and.arrow.up").foregroundStyle(dayColor)
                    }
                }
            }
            .sheet(item: $sharing) { item in
                ShareSheet(items: [item.text])
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
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
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
        if slot.isEstimated {
            var t = polyline == nil
                ? "這是估算值：用直線距離乘上迂迴係數 \(String(format: "%.2f", slot.mode.straightLineFactor)) 換算，"
                    + "不是真實路徑。"
                : "這是估算值，不是真實路徑。"
            if slot.mode.fixedOverheadMinutes > 0 {
                t += "另外加了 \(slot.mode.fixedOverheadMinutes) 分鐘固定耗時"
                    + "（報到、安檢、登機、下機、等行李），不含去機場的路程。"
            }
            if !slot.mode.supportsRouting {
                t += "\(slot.mode.rawValue)沒有路線服務可問，要精確時間請用下面的按鈕開 Apple 地圖查。"
            }
            return t
        }
        return "向地圖服務要到的真實路徑：實際道路距離與行駛時間（依一般路況估算，不含即時路況）。"
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

    @MainActor
    private func loadRoute() async {
        guard let from, let to, to.mode.supportsRouting, polyline == nil else { return }
        isLoading = true
        defer { isLoading = false }
        polyline = await TripRouter.routePolyline(from: from.stop, to: to.stop, mode: to.mode)
    }
}
