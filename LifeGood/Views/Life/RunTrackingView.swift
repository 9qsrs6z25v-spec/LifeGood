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
// • 開始前選的運動用 @AppStorage 記住；開始後標題、存檔一律讀 tracker.sport（按「隱藏」再回來也對）。
// • 存檔：date＝按開始那一刻、endedAt＝最後一次按暫停那一刻；先關畫面，下一個 runloop 才交出去寫 store。

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

    /// 還沒收到任何定位（權限被拒時由 GPS 燈說明，這裡不重複）
    private var showFindingHint: Bool {
        tracker.lastCoordinate == nil && !gpsDenied
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

    private var controlPanel: some View {
        VStack(spacing: 14) {
            if !tracker.isActive {
                sportPicker
            }

            VStack(spacing: 10) {
                statsRow
                gpsRow
            }

            if tracker.waitingForFix && tracker.phase == .running {
                Label("訊號還沒好，可以先出發；好了才開始畫線", systemImage: "location.magnifyingglass")
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
            statCell(Self.distanceText(tracker.distanceMeters), "公里")
            divider
            statCell(Self.clockText(tracker.elapsed), "時間")
            divider
            statCell(Self.paceText(tracker.paceMinPerKm), "配速")
            divider
            statCell(String(format: "%.0f", tracker.elevationGainM), "爬升 m")
        }
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
            if gpsDenied {
                Button("去設定打開") { openSettings() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.blue)
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private enum GPSLevel { case denied, searching, fair, good }

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
        guard let acc = tracker.gpsAccuracy, gpsFresh else { return .searching }
        if acc <= 10 { return .good }
        if acc <= 20 { return .fair }
        return .searching
    }

    private var gpsText: String {
        let meters = tracker.gpsAccuracy.map { Int($0.rounded()) } ?? 0
        switch gpsLevel {
        case .denied: return "沒有位置權限"
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
        case .searching: return .yellow
        case .fair: return Color(red: 0.55, green: 0.85, blue: 0.45)
        case .good: return accent
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
                    finish()
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

    private func finish() {
        let r = tracker.finish()
        guard r.distanceKm > 0.01 || r.movingMinutes > 0.5 else { dismiss(); return }   // 太短照舊（v2 改成先問）
        let exercise = WorkoutExercise(
            name: r.sport.rawValue, kind: .cardio, reps: 0, sets: 0, loadType: .none,
            loadKg: 0, distanceKm: r.distanceKm, durationMinutes: r.movingMinutes,
            route: r.route, elevationGainM: r.elevation)
        let session = WorkoutSession(
            date: r.startedAt,                          // 按開始那一刻（原本「現在減運動時間」，暫停過就錯）
            title: r.sport.rawValue,
            exercises: [exercise],
            durationMinutes: r.movingMinutes,
            endedAt: r.endedAt)                         // 最後一次按暫停那一刻
        // 先關畫面、下一個 runloop 才交出去寫 store（同 VehicleEditors 的寫法）：
        // 在關 sheet 的那次畫面更新裡同步改 @Published store，真機會閃退
        let handOff = onFinish
        dismiss()
        DispatchQueue.main.async { handOff(session) }
    }

    // MARK: 格式

    static func distanceText(_ meters: Double) -> String {
        String(format: "%.2f", meters / 1000)
    }
    static func clockText(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }
    static func paceText(_ minPerKm: Double?) -> String {
        guard let p = minPerKm, p.isFinite, p > 0, p < 60 else { return "—" }
        // [v25.551] 秒數四捨五入（原本無條件捨去：6'09.9" 寫成 6'09"；6'59.6" 進位成 7'00"）
        let total = Int((p * 60).rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
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
