import SwiftUI
import UIKit
import MapKit
import CoreLocation

// MARK: - 跑步即時紀錄（v25.352）
//
// 開始後邊跑邊畫路徑，顯示距離、時間、配速與爬升。結束後轉成一筆訓練存進健康頁。
// 背景定位有開，鎖屏或切到別的 App 仍會繼續記；狀態列會出現藍色指示條。
//
// [v25.551] 地圖自己掌鏡、線即時畫：
// • 一打開就放在手機記得的上一個位置（沒有就上一趟紀錄的起點，再沒有就台北車站 3 公里＋「正在找你的位置…」），
//   遠近用這種運動記住的值（健走 400／跑步 600／登山 800／騎車 1,200 公尺起）。
//   不再用「跟著使用者、退路自動」的鏡頭：還沒定位時自動框景會先拉到整個台灣。
// • 每收到一筆定位，鏡頭 1 秒線性移到藍點（不到 2 公尺不挪、一次跳 200 公尺以上不做動畫）；
//   兩指縮放記住遠近；手指拖走就停跟，出現「回到我身邊」，跑步中 10 秒沒再碰就自己回來；
//   「看整條路」把這一趟整條線框進畫面。手指最近拉到 150 公尺、最遠 20 公里（看整條路時放寬，
//   長的騎車路線才框得進來），不能轉、不能傾斜。
// • 拿掉系統的定位鈕：按了會變成系統自己跟隨，跟我們每秒設的鏡頭互搶，
//   拖走、縮放的判斷也會亂掉；改成自己的「回到我身邊」。指北針、比例尺設成一直顯示
//   （系統預設只在旋轉、縮放時才出現；看比例尺才知道 600 公尺剛不剛好）。
// • 配速秒數四捨五入（6'09.9" 寫 6'10"，跟手錶一樣）。
// • 線依暫停切段（暫停那段不畫成直線），外圈白邊、淡色底圖；線頭由 RunTracker.segments 接到藍點。
// • GPS 燈分四級：沒有位置權限（灰，附「去設定打開」）／定位中（黃）／普通（淺綠）／良好（綠）。
//   （[v25.552] 多一級「精確位置關著」，見下面）
// • 開始前選的運動用 @AppStorage 記住；開始後標題、存檔一律讀 tracker.sport（按「隱藏」再回來也對）。
// • 存檔：date＝按開始那一刻、endedAt＝最後一次按暫停那一刻；先關畫面，下一個 runloop 才交出去寫 store。
//
// [v25.552] 記錄完整＋同一套數字（健康 v2）：
// • 存檔只走 WorkoutFacts.makeSession（跟救回中途存檔同一支）：先用完整的點算每公里分段，再簡化路線
//   （5 公里 889 → 約 228 點；地圖、Apple 健康的路線照樣畫得出來），運動種類、來源、暫停、估的大卡一起填。
// • 太短（10 公尺內而且 30 秒內）不再默默關掉：按「完成」先問「這一趟只有 12 秒、0.00 公里，要存嗎？」
//   〔不存〕＝放棄這一趟、〔還是存〕＝照常存。問的時候記錄器還停在暫停，什麼都沒丟。
// • GPS 燈多一級「精確位置關著，畫不出路線」（橘）＋「打開精確位置」：Info.plist 有說明字就跳系統框
//   「這一次給精確位置」，沒有（或這個畫面已經跳過一次系統框——含按開始時記錄器自己請的那次——還是關著）
//   就帶去設定；跑步中橘字也改說精確位置。
// • 格式全部轉呼叫 WorkoutFormat（一套寫法）：時間不到一小時寫「8:42」不再「08:42」；配速 6'11"。
// • 騎車那格改寫時速（「21.5」），距離 10 公里以上一位小數（「12.6」）。

struct RunTrackingView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = RunTracker.shared

    /// 結束後把成果交出去（呼叫端負責存檔與寫回 Apple 健康）
    let onFinish: (WorkoutSession) -> Void

    /// 地圖鏡頭：init 就算好開場位置
    @State private var camera: MapCameraPosition
    /// 開始前選的運動（記在 UserDefaults，下次打開還是它）；開始後一律讀 tracker.sport
    @AppStorage(RunSport.lastSportKey) private var pickedSport: RunSport = .run
    @State private var showDiscardAlert = false
    /// 鏡頭跟著你；手指拖走就 false
    @State private var following = true
    /// 正在「看整條路」：手指怎麼動都不記遠近、不自動回來
    @State private var wholeRoute = false
    /// 跟著你時鏡頭離地多遠（公尺）；兩指縮放後改這個，也記進這種運動
    @State private var followDistance: Double
    /// 上一次置中的位置：不到 2 公尺不挪、跳超過 200 公尺不做動畫
    @State private var lastCenter: CLLocation?
    /// 拖走後 10 秒自己回來
    @State private var autoReturn: Task<Void, Never>?
    /// 第一次收到定位時直接跳過去（不做動畫）
    @State private var placed = false
    /// 量到的面板高度：地圖下緣讓出這麼多，藍點才會在面板上方那塊地圖的中間
    @State private var panelHeight: CGFloat = 240
    /// [v25.552] 太短的一趟按「完成」時問的那句；nil＝沒在問
    @State private var shortPrompt: String?
    /// [v25.552] 這個畫面已經跳過一次「這一次給精確位置」的系統框（按鈕、或按開始時記錄器自己請的）；
    /// 還是關著再按就帶去設定（按了沒反應比帶去設定糟）。拿到精確位置就歸零
    @State private var preciseAsked = false

    private let accent = Color(red: 0.20, green: 0.78, blue: 0.45)

    /// [v25.551] 開場鏡頭在這裡就算好：手機記得的上一個位置＋這種運動記住的遠近；
    /// 手機不記得就先放台北車站 3 公里（onAppear 再試上一趟紀錄的起點）
    @MainActor
    init(onFinish: @escaping (WorkoutSession) -> Void) {
        self.onFinish = onFinish
        let shared = RunTracker.shared
        let sport = shared.isActive ? shared.sport : RunSport.remembered
        let distance = sport.rememberedFollowDistance
        _followDistance = State(initialValue: distance)
        let known = shared.lastKnownCoordinate
        let center = known ?? RouteMath.fallbackCenter
        let startDistance: Double = known == nil ? 3_000 : distance
        let start = MapCameraPosition.camera(MapCamera(centerCoordinate: center, distance: startDistance))
        _camera = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mapLayer
                    .ignoresSafeArea(edges: .top)
                if showFindingHint {
                    findingHint
                }
                bottomStack
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tracker.isActive ? "隱藏" : "關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if tracker.isActive {
                        Button("放棄", role: .destructive) { showDiscardAlert = true }
                            .foregroundStyle(.red)
                    }
                }
            }
            .alert("放棄這一趟？", isPresented: $showDiscardAlert) {
                Button("放棄", role: .destructive) { tracker.cancel(); dismiss() }
                Button("繼續記錄", role: .cancel) { }
            } message: {
                Text("已經記錄的距離與路徑會直接丟掉，無法復原。")
            }
            .onAppear { appear() }
            .onDisappear { disappear() }
        }
    }

    /// 開始前「開始運動」；開始後是這一趟的運動（讀記錄器，按隱藏再回來也對）
    private var navTitle: String {
        tracker.isActive ? tracker.sport.rawValue : "開始運動"
    }

    /// 現在算哪一種運動：開始後讀記錄器，開始前讀選擇器
    private var currentSport: RunSport {
        tracker.isActive ? tracker.sport : pickedSport
    }

    // MARK: 地圖

    private var mapLayer: some View {
        Map(position: $camera,
            bounds: cameraBounds,
            interactionModes: [.pan, .zoom]) {                          // 不給轉、不給傾斜：北方朝上
            UserAnnotation()
            ForEach(liveSegments) { s in                                // 記錄器算好的段，只算一次
                MapPolyline(coordinates: s.coordinates)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: s.coordinates)
                    .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let start = liveStart {
                Annotation("起點", coordinate: start) {
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(accent, lineWidth: 4))
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))   // 淡色、不顯示店家，線最清楚
        .mapControls {                                                            // 不放系統定位鈕（會搶鏡頭）
            MapCompass()
            MapScaleView()
        }
        .mapControlVisibility(.visible)                                           // 指北針、比例尺一直顯示（預設只在旋轉、縮放時才出現）
        .safeAreaPadding(.bottom, panelHeight)                                   // 藍點放在面板上方那塊地圖的中間
        .onChange(of: tracker.fixSerial) { follow() }
        .onMapCameraChange(frequency: .onEnd) { ctx in cameraEnded(ctx) }
    }

    /// 手指最近拉到 150 公尺、最遠 20 公里（拉不到整個台灣）。
    /// 「看整條路」時放寬到 400 公里：騎 40 公里來回的線外框就超過 20 公里，鏡頭被夾在 20 公里會框不進來
    private var cameraBounds: MapCameraBounds {
        MapCameraBounds(minimumDistance: 150, maximumDistance: wholeRoute ? 400_000 : 20_000)
    }

    /// 地圖上的線：只畫正在記錄的這一趟。
    /// 上一趟按完成後 tracker.points 還留著，下次打開、還沒開始前不要把舊線畫出來。
    private var liveSegments: [RouteSegment] {
        tracker.isActive ? tracker.segments : []
    }

    /// 這一趟的起點（還沒開始、或還沒存到第一點就沒有）
    private var liveStart: CLLocationCoordinate2D? {
        guard tracker.isActive, let p = tracker.points.first else { return nil }
        return CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
    }

    /// 還沒收到任何定位（權限被拒、精確位置關著時由 GPS 燈說明，這裡不重複）
    private var showFindingHint: Bool {
        tracker.lastCoordinate == nil && !gpsDenied && !tracker.reducedAccuracy
    }

    private var findingHint: some View {
        Label("正在找你的位置…", systemImage: "location.magnifyingglass")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color(.separator).opacity(0.2), lineWidth: 0.75))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            .allowsHitTesting(false)
    }

    // MARK: 地圖按鈕＋面板

    private var bottomStack: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if showMapButtons {
                mapButtons
                    .padding(.horizontal, 12)
            }
            controlPanel
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { h in
                    if abs(h - panelHeight) > 0.5 { panelHeight = h }
                }
        }
    }

    /// 這一趟有兩點以上才能「看整條路」
    private var canShowWholeRoute: Bool {
        tracker.isActive && tracker.points.count >= 2
    }

    private var showMapButtons: Bool {
        canShowWholeRoute || !following
    }

    private var mapButtons: some View {
        HStack(spacing: 8) {
            if canShowWholeRoute {
                mapCapsule("看整條路", icon: "arrow.up.left.and.arrow.down.right", active: wholeRoute) {
                    toggleWholeRoute()
                }
            }
            if !following {
                mapCapsule("回到我身邊", icon: "location.fill", active: false) {
                    returnToMe()
                }
            }
        }
    }

    private func mapCapsule(_ title: String, icon: String, active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color(.separator).opacity(0.2), lineWidth: 0.75))
                .foregroundStyle(active ? accent : Color.primary)
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
    }

    /// 面板＋「太短要存嗎？」提示框。
    /// [v25.552] 這個提示框掛在面板上，「放棄這一趟？」掛在 NavigationStack 的內容上：同一個 view 不疊兩個 .alert
    private var controlPanel: some View {
        panelCard
            .alert(shortPrompt ?? "", isPresented: showShortBinding) {
                Button("不存", role: .destructive) { discardShort() }
                Button("還是存") { finish() }
            }
    }

    private var panelCard: some View {
        VStack(spacing: 14) {
            if !tracker.isActive {
                sportPicker
            }

            VStack(spacing: 10) {
                statsRow
                gpsRow
            }

            if let t = waitingHint {
                Label(t, systemImage: "location.magnifyingglass")
                    .font(.caption).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            buttons
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(.separator).opacity(0.2), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    /// 跑步中、還畫不出線時的橘字。[v25.552] 精確位置關著：每一筆定位誤差 1～3 公里都被丟掉，
    /// 只記得到時間，直接說原因（不然一直寫「訊號還沒好」，使用者以為等一下就好）
    private var waitingHint: String? {
        guard tracker.phase == .running else { return nil }
        if tracker.reducedAccuracy { return "精確位置關著：打開才畫得出路線（現在只記時間）" }
        if tracker.waitingForFix { return "訊號還沒好，可以先出發；好了才開始畫線" }
        return nil
    }

    /// 「太短要存嗎？」提示框開著沒有（關掉時清掉那句）
    private var showShortBinding: Binding<Bool> {
        Binding(get: { shortPrompt != nil }, set: { if !$0 { shortPrompt = nil } })
    }

    private var sportPicker: some View {
        Picker("運動", selection: $pickedSport) {
            ForEach(RunSport.allCases) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: pickedSport) { sportChanged() }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(distanceCellText, "公里")
            divider
            statCell(Self.clockText(tracker.elapsed), "時間")
            divider
            paceCell
            divider
            statCell(String(format: "%.0f", tracker.elevationGainM), "爬升 m")
        }
    }

    /// [v25.552] 距離格：兩位小數（「3.42」）；騎車 10 公里以上一位（「12.6」）
    private var distanceCellText: String {
        WorkoutFormat.preciseKmNumber(tracker.distanceMeters / 1000, sport: WorkoutSport(currentSport))
    }

    /// [v25.552] 第三格：騎車寫時速（騎車不看配速），其他照舊寫配速
    @ViewBuilder
    private var paceCell: some View {
        if currentSport == .bike {
            statCell(bikeSpeedText, "時速")
        } else {
            statCell(Self.paceText(tracker.paceMinPerKm), "配速")
        }
    }

    /// 平均時速（公里）＝距離 ÷ 移動時間；跟配速一樣 50 公尺內不算（一開騎 GPS 一跳就是 80 公里/時）
    private var bikeSpeedText: String {
        guard tracker.distanceMeters > 50 else { return "—" }
        let v = WorkoutFormat.speedKmh(km: tracker.distanceMeters / 1000, minutes: tracker.elapsed / 60)
        return v.map { WorkoutFormat.speedNumber($0) } ?? "—"
    }

    private var divider: some View {
        Rectangle().fill(Color(.separator).opacity(0.3)).frame(width: 0.75, height: 30)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: GPS 燈

    /// 每 2 秒重看一次：開始前站著不動、收不到新定位時畫面不會重畫，燈要自己退回「定位中…」
    private var gpsRow: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            gpsRowContent
        }
        .onChange(of: tracker.reducedAccuracy) { _, reduced in
            if !reduced { preciseAsked = false }      // [v25.552] 給了：之後系統收回「這一次」的授權時，又可以跳系統框
        }
    }

    private var gpsRowContent: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gpsColor)
                .frame(width: 8, height: 8)
            Text(gpsText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            gpsFixButton
            Spacer(minLength: 0)
        }
    }

    /// 燈旁邊的藍字：沒有位置權限「去設定打開」；[v25.552] 精確位置關著「打開精確位置」
    @ViewBuilder
    private var gpsFixButton: some View {
        switch gpsLevel {
        case .denied:
            gpsLink("去設定打開") { openSettings() }
        case .imprecise:
            gpsLink("打開精確位置") { openPrecise() }
        case .searching, .fair, .good:
            EmptyView()
        }
    }

    private func gpsLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.blue)
            .buttonStyle(.plain)
            .lineLimit(1)
            .fixedSize()
    }

    /// [v25.552] imprecise：有位置權限、但「精確位置」關著（誤差 1～3 公里，每一筆都被丟掉，畫不出線）
    private enum GPSLevel { case denied, imprecise, searching, fair, good }

    private var gpsDenied: Bool {
        tracker.authorization == .denied || tracker.authorization == .restricted
    }

    /// 10 秒內收過定位（隧道、橋下太久沒收到就回到黃燈）。
    /// 暫停中記錄器把定位關了（省電），燈停在按暫停時的樣子，不要變成「定位中…」嚇人
    private var gpsFresh: Bool {
        if tracker.phase == .paused { return true }
        return (tracker.secondsSinceFix ?? .infinity) <= 10
    }

    private var gpsLevel: GPSLevel {
        if gpsDenied { return .denied }
        if tracker.reducedAccuracy { return .imprecise }
        guard let acc = tracker.gpsAccuracy, gpsFresh else { return .searching }
        if acc <= 10 { return .good }
        if acc <= 20 { return .fair }
        return .searching
    }

    private var gpsText: String {
        let meters = tracker.gpsAccuracy.map { Int($0.rounded()) } ?? 0
        switch gpsLevel {
        case .denied: return "沒有位置權限"
        case .imprecise: return "精確位置關著，畫不出路線"
        case .good: return "GPS 良好・誤差 \(meters) 公尺"
        case .fair: return "GPS 普通・誤差 \(meters) 公尺"
        case .searching:
            if tracker.gpsAccuracy != nil, gpsFresh { return "定位中…（誤差 \(meters) 公尺）" }
            return "定位中…"
        }
    }

    private var gpsColor: Color {
        switch gpsLevel {
        case .denied: return .gray
        case .imprecise: return .orange
        case .searching: return .yellow
        case .fair: return Color(red: 0.55, green: 0.85, blue: 0.45)
        case .good: return accent
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// [v25.552] 精確位置關著：打包出來的 Info.plist 有說明字（RunTracker.canAskPreciseLocation）就請系統
    /// 「這一次給精確位置」；沒有說明字（呼叫系統會沒反應）、或這個畫面已經跳過一次系統框還是關著，就帶去設定
    /// （設定 → LifeGood → 位置 → 精確位置）。答案由記錄器的授權回呼收，燈跟著 reducedAccuracy 自己變
    private func openPrecise() {
        if tracker.canAskPreciseLocation, !preciseAsked {
            preciseAsked = true
            tracker.requestPreciseLocation()
        } else {
            openSettings()
        }
    }

    // MARK: 按鈕

    @ViewBuilder
    private var buttons: some View {
        switch tracker.phase {
        case .idle:
            Button {
                startRun()
            } label: {
                Label("開始", systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(accent, in: Capsule())
            .foregroundStyle(.white)
        case .running:
            HStack(spacing: 12) {
                Button {
                    tracker.pause()
                } label: {
                    Label("暫停", systemImage: "pause.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .background(Color(.tertiarySystemFill), in: Capsule())
            }
        case .paused:
            HStack(spacing: 12) {
                Button {
                    resumeRun()
                } label: {
                    Label("繼續", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .background(Color(.tertiarySystemFill), in: Capsule())
                Button {
                    finishTapped()
                } label: {
                    Label("完成", systemImage: "checkmark")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .background(accent, in: Capsule())
                .foregroundStyle(.white)
            }
        }
    }

    /// 開始：運動已經由 @AppStorage 記住；不擋開始（沒權限也能按，只記時間）
    private func startRun() {
        // [v25.552] 精確位置關著時，記錄器按開始會自己跳一次系統框（RunTracker.start）：算這個畫面問過了，
        // 使用者在那個框按「不允許」之後，燈旁的「打開精確位置」直接帶去設定（系統未必再跳框，不會按了沒反應）
        if tracker.canAskPreciseLocation { preciseAsked = true }
        tracker.start(sport: pickedSport)
        autoReturn?.cancel()
        autoReturn = nil
        following = true
        wholeRoute = false
        lastCenter = nil
        recenter(animated: false)
    }

    /// 繼續：暫停前把地圖拖走了，繼續之後一樣 10 秒沒再碰就自己回來
    private func resumeRun() {
        tracker.resume()
        if !following, !wholeRoute { scheduleAutoReturn() }
    }

    // MARK: 跟隨

    /// 每收到一筆定位（fixSerial 加一）呼叫
    private func follow() {
        if !placed, tracker.lastCoordinate != nil {                 // 第一次定到位：直接跳過去
            placed = true
            if following, !wholeRoute { recenter(animated: false) }
            return
        }
        guard following, !wholeRoute, !camera.positionedByUser else { return }
        recenter(animated: true)
    }

    /// 把鏡頭放回藍點（用這種運動的遠近）。
    /// animated：跟隨用的 1 秒線性；不到 2 公尺不挪（免得抖），一次跳超過 200 公尺（出隧道）不做動畫。
    /// glide：按「回到我身邊」、縮放完、10 秒自己回來、換運動，0.4 秒滑回來。
    private func recenter(animated: Bool, glide: Bool = false) {
        guard let c = tracker.lastKnownCoordinate else { return }
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        if animated, !glide, let lc = lastCenter, here.distance(from: lc) < 2 { return }
        let jump = lastCenter.map { here.distance(from: $0) > 200 } ?? true
        lastCenter = here
        let pos = MapCameraPosition.camera(MapCamera(centerCoordinate: c, distance: followDistance))
        if glide {
            withAnimation(.easeInOut(duration: 0.4)) { camera = pos }
        } else if animated && !jump {
            withAnimation(.linear(duration: 1)) { camera = pos }
        } else {
            camera = pos
        }
    }

    /// 手指動完地圖（拖、捏、點兩下）。我們自己設的鏡頭（positionedByUser == false）、看整條路時略過。
    private func cameraEnded(_ ctx: MapCameraUpdateContext) {
        guard camera.positionedByUser, !wholeRoute, let c = tracker.lastKnownCoordinate else { return }
        let d = min(max(ctx.camera.distance, 150), 20_000)
        // 遠近變了 10% 以上就記住（就算中心也被拖走了）；存的時候夾 150～5,000
        if abs(d - followDistance) > followDistance * 0.1 {
            followDistance = d
            currentSport.rememberFollowDistance(d)
        }
        let center = CLLocation(latitude: ctx.camera.centerCoordinate.latitude,
                                longitude: ctx.camera.centerCoordinate.longitude)
        let me = CLLocation(latitude: c.latitude, longitude: c.longitude)
        if center.distance(from: me) < d * 0.15 {                   // 只是縮放：繼續跟、重新置中
            autoReturn?.cancel()
            autoReturn = nil
            following = true
            lastCenter = nil
            recenter(animated: true, glide: true)
        } else {                                                    // 拖走了
            following = false
            scheduleAutoReturn()
        }
    }

    /// 跑步中 10 秒沒再碰就自己回來；暫停中、看整條路、還沒開始都不自動回
    private func scheduleAutoReturn() {
        autoReturn?.cancel()
        autoReturn = nil
        guard tracker.phase == .running, !wholeRoute else { return }
        autoReturn = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            guard tracker.phase == .running, !wholeRoute, !following else { return }
            following = true
            lastCenter = nil
            recenter(animated: true, glide: true)
        }
    }

    private func returnToMe() {
        autoReturn?.cancel()
        autoReturn = nil
        following = true
        wholeRoute = false
        lastCenter = nil
        recenter(animated: true, glide: true)
    }

    /// 「看整條路」：框住這一趟整條線；再按一次就回到你身邊
    private func toggleWholeRoute() {
        if wholeRoute { returnToMe(); return }
        guard let b = RouteMath.bounds(tracker.points) else { return }
        autoReturn?.cancel()
        autoReturn = nil
        wholeRoute = true
        following = false
        let region = MKCoordinateRegion(center: b.center,
                                        latitudinalMeters: b.spanMeters,
                                        longitudinalMeters: b.spanMeters)
        // 下一個 runloop 才移鏡頭：先讓地圖拿到放寬的最遠距離（cameraBounds），長的騎車路線才不會被夾在 20 公里
        DispatchQueue.main.async {
            guard wholeRoute else { return }                        // 連按兩下：已經回到你身邊了
            withAnimation(.easeInOut(duration: 0.4)) {
                camera = .region(region)
            }
        }
    }

    /// 開始前換運動：換成那種運動記住的遠近，回到你身邊
    private func sportChanged() {
        guard !tracker.isActive else { return }
        followDistance = pickedSport.rememberedFollowDistance
        autoReturn?.cancel()
        autoReturn = nil
        following = true
        wholeRoute = false
        lastCenter = nil
        recenter(animated: true, glide: true)
    }

    // MARK: 生命週期

    private func appear() {
        tracker.prepare()                                           // 先定位（藍點、GPS 燈），也先問「動作與健身」
        // 手機不記得位置：先放在上一趟紀錄的起點（舊紀錄只有起點 1 點也算）；
        // 都沒有就留在台北車站 3 公里＋「正在找你的位置…」
        if !tracker.isActive, tracker.lastKnownCoordinate == nil, let start = lastRouteStart() {
            camera = .camera(MapCamera(centerCoordinate: start, distance: followDistance))
        }
    }

    private func disappear() {
        autoReturn?.cancel()
        autoReturn = nil
        tracker.stopPreparing()                                     // 只有沒在記錄時才真的關定位
    }

    /// 最近一筆有路線（至少起點）的紀錄的起點
    private func lastRouteStart() -> CLLocationCoordinate2D? {
        var best: (date: Date, point: RoutePoint)?
        for s in lifeStore.workouts {
            guard let p = s.exercises.first(where: { !$0.route.isEmpty })?.route.first else { continue }
            if let b = best, b.date >= s.date { continue }
            best = (date: s.date, point: p)
        }
        guard let b = best else { return nil }
        return CLLocationCoordinate2D(latitude: b.point.lat, longitude: b.point.lon)
    }

    // MARK: 完成

    /// [v25.552]「完成」：10 公尺內而且 30 秒內＝太短，先問（judge §4.1 第 13 列；跟救回中途存檔的
    /// RunCheckpoint.isTooShort 同一條線）。問的時候記錄器還停在暫停，什麼都沒丟
    private func finishTapped() {
        guard tracker.distanceMeters <= 10, tracker.elapsed <= 30 else { finish(); return }
        shortPrompt = shortPromptText
    }

    /// 「這一趟只有 12 秒、0.00 公里，要存嗎？」（秒數跟面板上的時間一樣往下取整）
    private var shortPromptText: String {
        let seconds = WorkoutFormat.wholeSeconds(tracker.elapsed.rounded(.down))
        let km = WorkoutFormat.preciseKmNumber(tracker.distanceMeters / 1000)
        return "這一趟只有 \(seconds) 秒、\(km) 公里，要存嗎？"
    }

    /// 太短〔不存〕：跟「放棄這一趟」一樣（記錄器 cancel 會連中途存檔一起刪）
    private func discardShort() {
        tracker.cancel()
        dismiss()
    }

    private func finish() {
        let r = tracker.finish()
        // [v25.552] 存檔組裝只有一支（救回中途存檔也走它）：先用完整的點算每公里分段，再簡化路線
        // （5 公里 889 → 約 228 點），運動種類、來源 .app、暫停、真正結束時間、估的大卡一起填。
        // date＝按開始那一刻、endedAt＝最後一次按暫停那一刻（v25.551）照舊，在 makeSession 裡
        let session = WorkoutFacts.makeSession(from: r, bodyWeightKg: lifeStore.latestBodyWeightKg)
        // 先關畫面、下一個 runloop 才交出去寫 store（同 VehicleEditors 的寫法）：
        // 在關 sheet 的那次畫面更新裡同步改 @Published store，真機會閃退
        let handOff = onFinish
        dismiss()
        DispatchQueue.main.async { handOff(session) }
    }

    // MARK: 格式

    // [v25.552] 三支都轉呼叫 WorkoutFormat（一套寫法），簽章不變

    /// 「3.42」（兩位小數）
    static func distanceText(_ meters: Double) -> String {
        WorkoutFormat.preciseKmNumber(meters / 1000)
    }
    /// 「8:42」「1:05:12」：跑步中往下取整（碼錶），不到一小時不再補前面的 0（以前「08:42」）
    static func clockText(_ t: TimeInterval) -> String {
        WorkoutFormat.clock(seconds: t.rounded(.down))
    }
    /// 「6'11"」：秒數四捨五入（[v25.551]：6'09.9" 寫 6'10"）；算不出來「—」
    static func paceText(_ minPerKm: Double?) -> String {
        WorkoutFormat.pace(minPerKm)
    }
}

// MARK: - 已存路徑的靜態地圖

struct RouteMapView: View {
    let route: [RoutePoint]
    var height: CGFloat = 170
    var accent: Color = Color(red: 0.20, green: 0.78, blue: 0.45)

    /// [v25.551] 依暫停切段：段與段之間不連線（舊資料沒有段號，整條一段）
    private var segs: [RouteSegment] { RouteMath.segments(route) }

    var body: some View {
        Group {
            if let b = RouteMath.bounds(route), route.count >= 2 {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: b.center,
                    latitudinalMeters: b.spanMeters,
                    longitudinalMeters: b.spanMeters))
                ) {
                    ForEach(segs) { s in
                        MapPolyline(coordinates: s.coordinates)
                            .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    if let f = route.first {
                        Annotation("起", coordinate: CLLocationCoordinate2D(latitude: f.lat, longitude: f.lon)) {
                            Circle().fill(.white).frame(width: 11, height: 11)
                                .overlay(Circle().stroke(accent, lineWidth: 3))
                        }
                    }
                    if let l = route.last {
                        Annotation("終", coordinate: CLLocationCoordinate2D(latitude: l.lat, longitude: l.lon)) {
                            Circle().fill(accent).frame(width: 11, height: 11)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
            } else {
                EmptyView()
            }
        }
    }
}
