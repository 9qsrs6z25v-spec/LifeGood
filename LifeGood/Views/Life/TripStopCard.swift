import SwiftUI
import MapKit

// MARK: - 景點卡（v25.423）
//
// 時間軸點一站打開的地方。v25.421 一度改成直接開 Apple 地圖，但那等於把
// 「看內容」「編輯」「打卡」「加照片」全擠進一顆「…」選單裡；改回先開卡片，
// 要去地圖、要編輯、要打卡都從卡片上選——跟固定支出卡、部屬卡、名片卡同一個模式。
//
// 版型比照全 App 的詳情卡：英雄卡標頭（走共用殼層，顏色用當天的色系）+ 數個
// 圓角資訊區塊 + 右上角編輯。所有資料一律從 store 現撈，編輯完回來自動是新的。

struct TripStopCardView: View {
    @EnvironmentObject var lifeStore: LifeStore
    /// [v25.465] 記帳時可以把花費指定「算在哪一站」，這一站要看得到自己的花費
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let planId: UUID
    let stopId: UUID

    @State private var showEdit = false
    @State private var showLegDetail = false
    @State private var sharing: ShareText?
    /// [v25.441] 分享改以圖片為主：一張卡片傳出去，對方不用裝這個 App 也看得懂。
    /// 文字留在選單裡——要把地址連結貼進訊息時還是文字方便。
    @State private var sharingImage: ShareImageURL?
    @State private var isExporting = false

    private struct ShareImageURL: Identifiable {
        let id = UUID()
        let url: URL
    }
    @State private var viewingPhoto: IdentifiableURL?
    @State private var confirmClearCheckIn = false
    /// [v25.515] 花費列可以直接點開編輯：看不出哪一筆是什麼的時候，
    /// 點一下就能補「備註」。原本這張卡完全沒有進得去那一筆的路。
    @State private var editingExpense: Expense?

    private struct ShareText: Identifiable {
        let id = UUID()
        let text: String
    }

    init(planId: UUID, stopId: UUID) {
        self.planId = planId
        self.stopId = stopId
    }

    // MARK: 資料

    private var plan: TripPlan? { lifeStore.tripPlan(id: planId) }
    private var slot: TripPlan.Slot? {
        plan?.timeline.first { $0.stop.id == stopId }
    }
    private var stop: TripStop? { slot?.stop }
    private var dayColor: Color { TripDayPalette.color(slot?.dayIndex ?? 0) }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"; return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"; return f
    }()

    /// 照片直接綁到 store：在卡片上加減照片就等於改那一站，不用先進編輯畫面
    private var photoBinding: Binding<[String]> {
        Binding(
            get: { stop?.photoFileNames ?? [] },
            set: { lifeStore.updateTripStopPhotos(planId: planId, stopId: stopId,
                                                  fileNames: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let slot {
                    content(slot)
                } else {
                    // 這一站被刪掉了（可能在別的畫面刪的）
                    Color.clear.onAppear { dismiss() }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("景點")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Menu {
                            Button {
                                Task { await shareImage() }
                            } label: {
                                Label("分享成圖片", systemImage: "photo")
                            }
                            Button {
                                if let p = plan, let s = stop {
                                    sharing = ShareText(text: TripShare.stopText(s, in: p))
                                }
                            } label: {
                                Label("分享文字", systemImage: "text.alignleft")
                            }
                        } label: {
                            if isExporting {
                                ProgressView().tint(dayColor)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        Button("編輯") { showEdit = true }.bold()
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                if let s = stop {
                    TripStopEditorSheet(planId: planId, editing: s, insertAt: nil)
                        .environmentObject(lifeStore)
                }
            }
            .sheet(isPresented: $showLegDetail) {
                if let p = plan, let slot {
                    TripLegDetailSheet(plan: p, index: slot.index)
                        .environmentObject(lifeStore)
                }
            }
            .sheet(item: $sharing) { item in ShareSheet(items: [item.text]) }
            // [v25.515] 不明確注入環境：AddExpenseView 要 ExpenseStore／FinanceStore／
            // LifeStore 三個，而這張卡只拿得到其中兩個，注入兩個反而會漏掉第三個。
            // sheet 會繼承 App 根的環境——TripExpenseSheet 的編輯 sheet 就是這樣用的。
            .sheet(item: $editingExpense) { e in
                AddExpenseView(expenseType: e.expenseType, editingExpense: e)
            }
            .sheet(item: $sharingImage) { item in ShareSheet(items: [item.url]) }
            // [v25.472] 這一站的照片整組帶進去，左右滑得動
            .sheet(item: $viewingPhoto) { wrapper in
                PhotoLightbox(urls: (stop?.photoFileNames ?? []).map { TripStop.photoURL($0) },
                              current: wrapper.url)
            }
            .confirmationDialog("清除打卡紀錄", isPresented: $confirmClearCheckIn,
                                titleVisibility: .visible) {
                Button("清除", role: .destructive) {
                    lifeStore.clearTripStopCheckIn(planId: planId, stopId: stopId)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("抵達與離開的時間都會被清掉，這一站的時間會回到排程推算的結果，後面幾站也會跟著回去。")
            }
        }
    }

    /// 把這一站做成一張圖再分享。
    /// 地圖快照要等，所以按下去先轉圈——不然使用者會以為沒反應而連按好幾下。
    @MainActor
    private func shareImage() async {
        guard !isExporting, let p = plan else { return }
        isExporting = true
        defer { isExporting = false }
        // 出圖是同步畫的，先把這一站的天氣抓齊，不然圖上那一列會憑空消失
        if let c = stop?.coordinate, let when = slot?.arrival,
           TripWeatherStore.isWithinForecastRange(when) {
            await TripWeatherStore.shared.preload([c])
        }
        let map = await TripImageExporter.stopMapImage(plan: p, stopId: stopId)
        let card = TripStopShareCard(plan: p, stopId: stopId, mapImage: map)
        let stamp = TripImageExporter.stampFormatter.string(from: Date())
        let name = (stop?.displayName ?? "景點") + "_" + stamp
        guard let url = TripImageExporter.writeJPG(card, name: name) else { return }
        sharingImage = ShareImageURL(url: url)
    }

    private func content(_ slot: TripPlan.Slot) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                hero(slot)
                checkInSection(slot)
                timingSection(slot)
                weatherSection(slot)
                if slot.index > 0 { legSection(slot) }
                placeSection(slot)
                // [v25.465] 兩個「有才顯示」的區塊收進 Group：加上花費那一節之後
                // 這裡剛好是 ViewBuilder 的 10 個子項上限，再加一個就會編譯失敗，
                // 而那個錯誤訊息完全看不出是數量問題。先留出空間。
                Group {
                    if !slot.stop.subSpots.isEmpty { subSpotSection(slot.stop) }
                    if !slot.stop.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        noteSection(slot.stop)
                    }
                }
                expenseSection(slot.stop)
                photoSection
            }
            .padding(.vertical)
            // [v25.481] 同上：景點卡也有膠囊列與照片條，一樣只能上下捲
            .scrollVerticalOnly()
        }
    }

    // MARK: 標頭

    private func hero(_ slot: TripPlan.Slot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headerCaption(slot))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(slot.stop.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("\(slot.index + 1)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.white.opacity(0.22)))
                    .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 0.75))
            }
            HStack(spacing: 6) {
                heroChip(Self.timeFmt.string(from: slot.arrival) + " – "
                         + Self.timeFmt.string(from: slot.departure),
                         icon: "clock")
                // [v25.435] 必去改成直接可按的一顆。
                //
                // 以前要標必去得走「…」選單或進編輯畫面——但「這站到底要不要去」
                // 是排行程時反覆改的一件事，藏在兩層下面就不會有人用。
                // 現在亮著＝必去，點一下切換，狀態與動作是同一個東西。
                mustVisitButton(slot)
                if slot.stop.isOvernight { heroChip("過夜", icon: "bed.double.fill") }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        // 共用英雄卡殼層，但顏色改用「這一站在第幾天」的色系：
        // 卡片打開時的第一眼就該跟時間軸上那一列是同一個顏色。
        .heroCardShell(card: .tripPlan,
                       runtimeColors: [dayColor, dayColor.opacity(0.62)])
        .padding(.horizontal, 16)
    }

    /// 必去切換鈕。用 emoji 而不是 SF Symbol：⭐️ 在深色漸層上本來就是彩色的，
    /// 不用再處理 symbolRenderingMode；沒選取時用灰階的 ☆ 對比也夠明顯。
    private func mustVisitButton(_ slot: TripPlan.Slot) -> some View {
        let on = slot.stop.isMustVisit
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                lifeStore.toggleTripStopMustVisit(planId: planId, stopId: stopId)
            }
        } label: {
            HStack(spacing: 4) {
                Text(on ? "⭐️" : "☆")
                    .font(.system(size: on ? 11 : 13))
                Text("必去")
                    .font(.system(size: 11, weight: .bold))
            }
            .fixedSize()
            .foregroundStyle(.white.opacity(on ? 1 : 0.7))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.white.opacity(on ? 0.30 : 0.14), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(on ? 0.5 : 0.2), lineWidth: 0.75))
            .scaleEffect(on ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "取消必去" : "標為必去")
    }

    private func heroChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 11, weight: .bold)).lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.white.opacity(0.20), in: Capsule())
    }

    /// 字串在 ViewBuilder 外組好
    private func headerCaption(_ slot: TripPlan.Slot) -> String {
        var parts: [String] = []
        if let p = plan, p.dayCount > 1 { parts.append("第 \(slot.dayIndex + 1) 天") }
        parts.append(Self.dayFmt.string(from: slot.arrival))
        return parts.joined(separator: "・")
    }

    // MARK: 打卡

    /// 三個狀態排成一列，現在在哪一段一眼看得到。
    /// 直接點想要的狀態，不用像時間軸那顆小圓圈一樣要按好幾下繞過去。
    private func checkInSection(_ slot: TripPlan.Slot) -> some View {
        sectionBox(title: "現在的狀態", icon: "checkmark.circle") {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    stateButton(.notArrived, "還沒到", "circle", slot)
                    stateButton(.arrived, "已抵達", "mappin.circle.fill", slot)
                    stateButton(.departed, "玩完離開", "checkmark.circle.fill", slot)
                }
                if slot.stop.checkInState != .notArrived {
                    VStack(spacing: 0) {
                        if let a = slot.stop.actualArrival {
                            field("實際抵達", Self.timeFmt.string(from: a))
                        }
                        if let d = slot.stop.actualDeparture {
                            hairline
                            field("實際離開", Self.timeFmt.string(from: d))
                        }
                        if let actual = slot.stop.actualDwellSeconds {
                            hairline
                            field("實際停留", TripRouter.durationText(actual))
                        }
                    }
                    .background(Color(.tertiarySystemFill).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    HStack(spacing: 10) {
                        if slot.stop.actualDwellSeconds != nil {
                            Button {
                                lifeStore.adoptActualDwell(planId: planId, stopId: stopId)
                            } label: {
                                smallAction("寫回預計停留", icon: "arrow.uturn.left")
                            }
                            .buttonStyle(.plain)
                        }
                        Button { confirmClearCheckIn = true } label: {
                            smallAction("清除打卡", icon: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(checkInHint(slot))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // sectionBox 只管標題列的內距，內容要自己留——
            // 不留的話按鈕與說明文字會貼到卡片圓角上被切掉
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private func stateButton(_ target: TripStop.CheckInState, _ title: String,
                             _ icon: String, _ slot: TripPlan.Slot) -> some View {
        let isOn = slot.stop.checkInState == target
        return Button {
            setState(target, current: slot.stop.checkInState)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isOn ? dayColor.opacity(0.15) : Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isOn ? dayColor : .clear, lineWidth: 1.2))
            .foregroundStyle(isOn ? dayColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    /// 直接跳到指定狀態。store 那邊是「按一下前進一步」的邏輯，
    /// 這裡幫使用者把中間的步驟按完——卡片上點「玩完離開」就該是玩完離開。
    private func setState(_ target: TripStop.CheckInState,
                          current: TripStop.CheckInState) {
        guard target != current else { return }
        switch (current, target) {
        case (.notArrived, .arrived):
            lifeStore.advanceTripStopCheckIn(planId: planId, stopId: stopId)
        case (.notArrived, .departed):
            // 忘了按抵達、玩完才想起來：抵達時間就用排程算出來的那個，
            // 憑空塞現在的時間會讓停留時間變成 0 分，比留著推算值更不準。
            if let planned = slot?.plannedArrival {
                lifeStore.setTripStopCheckIn(planId: planId, stopId: stopId,
                                             arrival: planned, departure: Date())
            } else {
                lifeStore.advanceTripStopCheckIn(planId: planId, stopId: stopId)
                lifeStore.advanceTripStopCheckIn(planId: planId, stopId: stopId)
            }
        case (.arrived, .departed):
            lifeStore.advanceTripStopCheckIn(planId: planId, stopId: stopId)
        case (.arrived, .notArrived), (.departed, .notArrived):
            lifeStore.clearTripStopCheckIn(planId: planId, stopId: stopId)
        case (.departed, .arrived):
            // 收回「離開」，人還在這裡
            lifeStore.setTripStopCheckIn(planId: planId, stopId: stopId,
                                         arrival: stop?.actualArrival ?? Date(),
                                         departure: nil)
        default:
            break
        }
    }

    private func checkInHint(_ slot: TripPlan.Slot) -> String {
        switch slot.stop.checkInState {
        case .notArrived:
            return "到了按「已抵達」、玩完按「玩完離開」，時間軸就會用真正的時間排，後面每一站跟著調整。"
        case .arrived:
            return "已經記下抵達時間。玩完按「玩完離開」就會算出實際停留多久。"
        case .departed:
            return "這一站的時間已經是事實，後面每一站都是從這個離開時間接下去算的。"
        }
    }

    // MARK: 時間

    private func timingSection(_ slot: TripPlan.Slot) -> some View {
        sectionBox(title: "時間", icon: "clock") {
            VStack(spacing: 0) {
                field("抵達", Self.timeFmt.string(from: slot.arrival)
                      + (slot.isActualArrival ? "（實際）"
                         : slot.isFixedArrival ? "（指定）" : "（推算）"))
                hairline
                field("離開", departureText(slot)
                      + (slot.isActualDeparture ? "（實際）" : ""))
                hairline
                if slot.stop.isOvernight {
                    field("停留", "過夜・隔天 "
                          + Self.timeFmt.string(from: slot.departure) + " 出發")
                } else {
                    field("預計停留", "\(slot.stop.dwellMinutes) 分")
                }
                if slot.shortfallSeconds > 60 {
                    hairline
                    warnRow("照推算來不及，差 "
                            + TripRouter.durationText(slot.shortfallSeconds), color: .red)
                } else if slot.idleSeconds > 300 && slot.index > 0 {
                    hairline
                    warnRow("會比指定時間早到，空 "
                            + TripRouter.durationText(slot.idleSeconds), color: .secondary)
                }
            }
        }
    }

    private func departureText(_ slot: TripPlan.Slot) -> String {
        let t = Self.timeFmt.string(from: slot.departure)
        return Calendar.current.isDate(slot.departure, inSameDayAs: slot.arrival)
            ? t : "翌日 " + t
    }

    // MARK: 這一段怎麼來

    private func legSection(_ slot: TripPlan.Slot) -> some View {
        sectionBox(title: "怎麼過來", icon: slot.mode.icon) {
            VStack(spacing: 0) {
                field("交通方式", slot.mode.rawValue
                      + (slot.isModeOverridden ? "（這一段單獨指定）" : ""))
                hairline
                field("交通時間", slot.travelSeconds.map { TripRouter.durationText($0) }
                      ?? "未計算")
                if let m = slot.travelMeters {
                    hairline
                    field("距離", TripRouter.distanceText(m)
                          + (slot.isEstimated ? "（估算）" : ""))
                }
                hairline
                Button { showLegDetail = true } label: {
                    HStack {
                        Text("看這一段的地圖與路線")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(dayColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 地點

    private func placeSection(_ slot: TripPlan.Slot) -> some View {
        sectionBox(title: "地點", icon: "mappin.and.ellipse") {
            VStack(spacing: 0) {
                let address = slot.stop.address.trimmingCharacters(in: .whitespaces)
                if !address.isEmpty {
                    HStack(alignment: .top) {
                        Text("地址").font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(address)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    hairline
                }
                if slot.stop.coordinate == nil {
                    warnRow("沒有座標，這一站不會被算進路線距離與時間", color: .orange)
                    hairline
                }
                HStack(spacing: 10) {
                    Button { TripShare.openPlaceInMaps(slot.stop) } label: {
                        actionButton("用 Apple 地圖開啟", icon: "map.fill", filled: true)
                    }
                    .buttonStyle(.plain)
                    if slot.index > 0, let p = plan,
                       p.stops.indices.contains(slot.index - 1) {
                        Button {
                            TripShare.openDirectionsInMaps(from: p.stops[slot.index - 1],
                                                           to: slot.stop, mode: slot.mode)
                        } label: {
                            actionButton("導航", icon: "arrow.triangle.turn.up.right.diamond.fill",
                                         filled: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: 子地點 / 備註 / 照片

    /// [v25.435] 那天的天氣。
    ///
    /// 只在「有座標」且「日期在預報範圍內」時整塊出現——沒有的話連標題都不要留，
    /// 一個永遠寫著「無法取得」的區塊只會讓人以為壞了。
    @ViewBuilder
    private func weatherSection(_ slot: TripPlan.Slot) -> some View {
        if slot.stop.coordinate != nil,
           TripWeatherStore.isWithinForecastRange(slot.arrival) {
            sectionBox(title: "那天的天氣", icon: "cloud.sun.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    TripWeatherChip(coordinate: slot.stop.coordinate,
                                    date: slot.arrival, compact: false,
                                    placeName: slot.stop.displayName)
                    WeatherAttributionRow()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private func subSpotSection(_ stop: TripStop) -> some View {
        sectionBox(title: "子地點", icon: "list.bullet.indent") {
            VStack(spacing: 0) {
                ForEach(Array(stop.subSpots.enumerated()), id: \.element.id) { index, sub in
                    if index > 0 { hairline }
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(dayColor.opacity(0.35))
                            .frame(width: 6, height: 6).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.displayName)
                                .font(.subheadline.weight(.medium))
                            if !sub.address.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(sub.address).font(.caption2).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !sub.note.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(sub.note).font(.caption2).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        if sub.minutes > 0 {
                            Text("\(sub.minutes) 分")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(dayColor)
                        }
                        // [v25.424] 子地點自己有位置就給一顆地圖鈕。
                        // 只有地址沒座標也能開（TripShare 會退回用地址查）。
                        if sub.coordinate != nil
                            || !sub.address.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button {
                                TripShare.openPlaceInMaps(sub.asPlace)
                            } label: {
                                Image(systemName: "map.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(dayColor)
                                    .frame(width: 26, height: 26)
                                    .background(dayColor.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
        }
    }

    private func noteSection(_ stop: TripStop) -> some View {
        sectionBox(title: "備註", icon: "text.alignleft") {
            Text(stop.note)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
    }

    // MARK: 花費（v25.465）

    /// 指定算在這一站的花費。
    ///
    /// 只列「明確指定了這一站」的。記帳表單的站別選單有一個「整趟（不指定）」，
    /// 那些刻意沒分配的不會被攤到任何一站——硬塞進某一站只是猜，而且會讓每一站
    /// 的數字加起來不等於整趟。沒分配的在行程頁的「這趟的花費」卡上看。
    ///
    /// [v25.515] 原本每一列是 field("10/8 (三) · 站名", 原幣)，三件事一起修：
    /// (1) 英雄卡標頭寫過站名、headerCaption 寫過「第 N 天・M/d (E)」，那一行
    ///     兩段都是上面已經寫過的字，整段沒有一個字是新資訊；
    /// (2) field() 沒有 lineLimit，長站名會把右邊金額擠掉或換行；
    /// (3) 逐列寫原幣、底下合計寫台幣（還縮成「NT$1.4萬」），同一張卡加不起來。
    @ViewBuilder
    private func expenseSection(_ stop: TripStop) -> some View {
        let list = expenseStore.stopRowSorted(
            expenseStore.expenses.filter {
                $0.linkedTripPlanId == planId && $0.linkedTripStopId == stop.id
            })
        if !list.isEmpty {
            let names = suppressedPlaceNames(stop)
            let needNoteHint = stopRowsNeedNoteHint(list, suppressing: names)
            sectionBox(title: "這一站的花費", icon: "creditcard.fill") {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { idx, e in
                        if idx > 0 { hairline }
                        Button {
                            editingExpense = e
                        } label: {
                            HStack(spacing: 10) {
                                StopExpenseRow(expense: e,
                                               suppressing: names,
                                               contextDay: slot?.arrival,
                                               compact: false,
                                               fallbackAccent: dayColor,
                                               store: expenseStore)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if needNoteHint {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 9, weight: .semibold))
                            Text("有幾筆只剩分類名。點那一筆補上「備註」，這裡就分得出哪一筆是什麼。")
                                .font(.caption2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.top, 8)
                    }

                    hairline
                    HStack {
                        Text("合計").font(.subheadline.weight(.semibold))
                        Spacer(minLength: 12)
                        // [v25.515] 從 ntdTotalText 改成完整位數：逐列是完整位數，
                        // 合計縮成「NT$1.4萬」就加不起來。值仍然走 ntdTotal。
                        Text(expenseStore.ntdPlainTotalText(list))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(dayColor)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
            }
        }
    }

    /// 這個畫面已經印過的地點名：這一站 ＋ 同一趟所有站。
    ///
    /// 加上「所有站」是因為記帳表單可能先自動挑了別站、把那一站的名字填進 title，
    /// 使用者之後手改站別時不會再填第二次（fillPlaceFromStop 的
    /// `guard currentPlaceCoordinate == nil`），於是 title 停在另一站的名字。
    private func suppressedPlaceNames(_ stop: TripStop) -> [String] {
        var names = [stop.displayName]
        if let p = plan { names.append(contentsOf: p.stops.map { $0.displayName }) }
        return names
    }

    /// 照片直接在卡片上加減，不用先進編輯畫面
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MultiPhotoGallery(
                fileNames: photoBinding,
                urlFor: { TripStop.photoURL($0) },
                onSaveImage: { TripStop.savePhoto($0) },
                onDeleteFile: { TripStop.deletePhoto($0) },
                title: "景點照片",
                // [v25.483] 這一站的照片是直接寫回 LifeStore 的，所以匯入可以離開
                // 這張卡繼續跑。store 先取出來綁進閉包，不要在匯入結束時才去碰
                // @EnvironmentObject——那時這個 View 早就不在畫面上了。
                onBackgroundCommit: { [store = lifeStore, planId, stopId] names in
                    guard !names.isEmpty else { return }
                    let current = store.tripPlan(id: planId)?
                        .stops.first(where: { $0.id == stopId })?.photoFileNames ?? []
                    store.updateTripStopPhotos(planId: planId, stopId: stopId,
                                               fileNames: current + names)
                })
                .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: 版型零件

    private func sectionBox<Content: View>(title: String, icon: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Capsule()
                    .fill(LinearGradient(colors: [dayColor, dayColor.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: 13)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(dayColor)
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.top, 12)
            content()
        }
        .padding(.bottom, 2)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private var hairline: some View {
        Rectangle().fill(Color(.separator).opacity(0.18))
            .frame(height: 0.5).padding(.leading, 14)
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func warnRow(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func smallAction(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func actionButton(_ text: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            Text(text).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(filled ? .white : dayColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(filled
                    ? AnyShapeStyle(LinearGradient(colors: [dayColor, dayColor.opacity(0.75)],
                                                   startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(dayColor.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


// MARK: - 站內花費清單的一列（v25.515）

/// 兩個現場共用：行程頁的花費氣泡（TripPlanDetailView.stopSpendDetail）與
/// 景點卡的「這一站的花費」（本檔 expenseSection）。
///
/// 為什麼放在這個檔案而不是自成一檔：LifeGood.xcodeproj 是手寫的檔案參照
/// （project.pbxproj 裡一個 PBXFileSystemSynchronizedRootGroup 都沒有，
/// 每個 .swift 要三處手動登錄），新檔沒登錄進去整個 target 編不過。
///
/// 為什麼 store 用 let 傳進來而不是 @EnvironmentObject：這支列會出現在 popover 裡，
/// 而本專案所有 sheet 都是明確注入環境的，那個 .popover 沒有。
/// EnvironmentObject 找不到是 runtime crash 不是編譯錯誤，不值得拿它賭 presentation
/// 層的環境繼承。父層本來就持有 @EnvironmentObject，資料一變父層重算、
/// 這支列跟著重建，所以它不需要自己觀測。
struct StopExpenseRow: View {
    let expense: Expense
    /// 這個畫面已經印過的地點名（這一站 ＋ 同一趟所有站）
    let suppressing: [String]
    /// 這個畫面已經印過的日期；只有這一筆不同天才在副標印 M/d
    var contextDay: Date? = nil
    /// true ＝ 氣泡（寬 288pt，主標與副標各一行）；false ＝ 景點卡（各兩行）
    var compact: Bool = true
    /// 沒有分類時退回的強調色
    var fallbackAccent: Color = .secondary
    let store: ExpenseStore

    @Environment(\.colorScheme) private var scheme

    private static let rowDayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"; return f
    }()

    private var side: CGFloat { compact ? 22 : 26 }

    var body: some View {
        let label = expense.stopRowLabel(suppressing: suppressing)
        let accent = expense.variableCategory?.accentColor ?? fallbackAccent
        let tail = tailText(label)
        let ntd = store.ntdPlainText(of: expense)

        // spacing: 0 ＋ 單一 Spacer(minLength:)：HStack 的 spacing 會加在 Spacer
        // **兩側**各一次，用 spacing 搭 Spacer 會讓寬度預算少扣一倍。
        return HStack(alignment: .top, spacing: 0) {
            leading(accent: accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.primary)
                    .font(label.hasOwnText ? .subheadline.weight(.medium) : .subheadline)
                    .foregroundStyle(label.hasOwnText ? Color.primary : Color.secondary)
                    .lineLimit(compact ? 1 : 2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                if let tail {
                    // 分類名刻意不上色：11pt 的社交金／日用品綠在白底對比不足
                    Text(tail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 8)

            Spacer(minLength: 8)

            // 右欄一律台幣（所以逐列與合計是同一種數字），原幣當註記貼在它底下。
            // 原幣是對帳數字，擺在左欄只是跟「這筆是什麼」搶那一百多 pt。
            VStack(alignment: .trailing, spacing: 1) {
                // [v25.516] 相對字級。v25.515 是絕對 15pt 配會跟著放大的 caption2
                // 註記，系統字放大到 AX 級別時，原幣註記會比它要註記的主金額
                // 又大又寬，視覺層級整個反過來。
                Text(ntd)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if expense.isForeignCurrencyInput {
                    Text(store.displayAmountText(expense))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // [v25.516] 拿掉 layoutPriority(1)。它讓 HStack 先把「理想寬度」給
            // 這一欄，而大字級時這一欄被放大的原幣註記撐寬，結果主標被擠到
            // 只剩兩三個字——跟原本「金額永遠完整、先截主標」的意圖是反的。
            // 金額已經有 lineLimit(1) ＋ minimumScaleFactor 保底，不需要搶寬度。
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel(label, ntd: ntd, tail: tail))
    }

    /// 有照片就直接把第一張當縮圖——同一站幾筆都沒填備註時，
    /// 收據／門票照是唯一真的不一樣、而且最能喚起記憶的東西。
    /// 沒照片才退回分類圖示。
    @ViewBuilder
    private func leading(accent: Color) -> some View {
        if let first = expense.photoFileNames.first {
            StopExpenseThumb(url: Expense.photoURL(for: first), side: side, accent: accent)
        } else {
            RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                .fill(accent.opacity(0.16))
                .frame(width: side, height: side)
                .overlay(
                    // 顏色不獨立傳達資訊：形狀（fork.knife／gamecontroller.fill／
                    // bag.fill）、副標的分類名文字、VoiceOver label，三路各自都
                    // 說得出同一件事。而 accentColor 是寫死 RGB，原色疊在自己
                    // 0.16 的底板上在淺色模式只有 1.5–2.8:1（社交 1.57、飲食 1.91、
                    // 日用品 1.78），低於非文字圖形的 3:1 門檻。壓暗 0.28 後 3.5–7.7:1。
                    // 深色模式不壓（原色對深底本來就 3.4–6.7:1，壓了反而掉）。
                    Image(systemName: expense.categoryIcon)
                        .font(.system(size: side * 0.52, weight: .semibold))
                        .foregroundStyle(accent)
                        .brightness(scheme == .dark ? 0 : -0.28)
                )
                .padding(.top, 1)
        }
    }

    /// 副標：固定順序，只把主標沒用到的補完。缺的不佔位。
    private func tailText(_ l: Expense.StopRowLabel) -> String? {
        var parts: [String] = []
        // 只有不同天才印日期——標頭印的是那一站的到站日，這裡印的是消費日，
        // 隔天才補登的那一筆才是新資訊。
        // 永遠不印時分：同一站每一筆連秒都一樣，而且那是行程推算值不是消費時刻。
        if let d = contextDay,
           !Calendar.current.isDate(expense.date, inSameDayAs: d) {
            parts.append(Self.rowDayFmt.string(from: expense.date))
        }
        if let c = l.category { parts.append(c) }
        if let n = l.note { parts.append(n) }
        if let m = expense.diningMember?.trimmingCharacters(in: .whitespaces), !m.isEmpty {
            parts.append(m)
        }
        // 第一張已經當縮圖了，兩張以上才需要寫數量
        if expense.photoFileNames.count >= 2 {
            parts.append("照片 \(expense.photoFileNames.count)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// VoiceOver 必須把副標與原幣一起唸。合成 label 時漏掉 tail
    /// 會讓 VoiceOver 比改之前**少聽到**東西（原本那幾個 Text 是獨立元素）。
    private func a11yLabel(_ l: Expense.StopRowLabel, ntd: String, tail: String?) -> String {
        var parts: [String] = []
        parts.append(l.hasOwnText ? l.primary : l.primary + "，沒有備註")
        if let tail { parts.append(tail.replacingOccurrences(of: " · ", with: "，")) }
        parts.append(ntd)
        if expense.isForeignCurrencyInput {
            parts.append("原幣 " + store.displayAmountText(expense))
        }
        return parts.joined(separator: "，")
    }
}

/// 花費照片的小縮圖（走全 App 共用的 ThumbnailCache，與房產照片同一支）
private struct StopExpenseThumb: View {
    let url: URL
    let side: CGFloat
    let accent: Color
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
            .fill(accent.opacity(0.16))
            .frame(width: side, height: side)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.3,
                                                    style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: side * 0.46, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 1)
            .accessibilityHidden(true)
            .task(id: url) {
                // [v25.516] 先清空再讀，對齊 ThumbnailImageView 的同型修復：
                // ForEach 的 id 是 Expense.id，換掉第一張照片時這個實例留著
                // 而 url 變了，新圖不在快取、要讀磁碟，那段時間會顯示舊照片。
                image = nil
                image = await ThumbnailCache.shared.thumbnail(for: url, maxPixel: 96)
            }
    }
}

/// 這一批列裡「只剩分類名」的有兩筆以上 → 值得提一句備註。
///
/// ⚠️ 兩個畫面要傳**同一批**（整站全部，不是氣泡上列出的前幾筆），
///    否則同一份資料兩種答案。
/// ⚠️ 條件測的是「主標有沒有使用者自己的字」，不是「備註空不空」——
///    使用者自己打了店名、只是沒填備註的清單一眼就分得出來，不該被嘮叨。
func stopRowsNeedNoteHint(_ list: [Expense], suppressing names: [String]) -> Bool {
    // [v25.516] 測「同一個主標出現兩次以上」，而不是「有兩筆以上沒有自己的字」。
    // 三筆分類各不相同（飲食／娛樂／購物）時每一筆都沒有自己的字，
    // 但那三列圖示不同、字也不同，一眼就分得出來——氣泡那句
    // 「分不出來的那幾筆」在那種情況是錯的。
    let primaries = list.map { $0.stopRowLabel(suppressing: names) }
        .filter { !$0.hasOwnText }
        .map { $0.primary }
    return Dictionary(grouping: primaries, by: { $0 }).values.contains { $0.count >= 2 }
}
