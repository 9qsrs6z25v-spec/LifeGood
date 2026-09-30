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
            .sheet(item: $sharingImage) { item in ShareSheet(items: [item.url]) }
            .sheet(item: $viewingPhoto) { wrapper in PhotoLightbox(url: wrapper.url) }
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
                if !slot.stop.subSpots.isEmpty { subSpotSection(slot.stop) }
                if !slot.stop.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    noteSection(slot.stop)
                }
                photoSection
            }
            .padding(.vertical)
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
                                    date: slot.arrival, compact: false)
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

    /// 照片直接在卡片上加減，不用先進編輯畫面
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MultiPhotoGallery(
                fileNames: photoBinding,
                urlFor: { TripStop.photoURL($0) },
                onSaveImage: { TripStop.savePhoto($0) },
                onDeleteFile: { TripStop.deletePhoto($0) },
                title: "景點照片")
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
