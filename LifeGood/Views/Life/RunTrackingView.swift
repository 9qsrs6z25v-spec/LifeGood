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
// • 開始前選的運動用 @AppStorage 記住；開始後標題、存檔一律讀 tracker.sport（按「收起」再回來也對）。
// • 存檔：date＝按開始那一刻、endedAt＝最後一次按暫停那一刻；下一個 runloop 才交出去寫 store。
//
// [v25.552] 記錄完整＋同一套數字（健康 v2）：
// • 存檔只走 WorkoutFacts.makeSession（跟救回中途存檔同一支）：先用完整的點算每公里分段，再簡化路線
//   （5 公里 889 → 約 228 點；地圖、Apple 健康的路線照樣畫得出來），運動種類、來源、暫停、估的大卡一起填。
// • 太短（10 公尺內而且 30 秒內）不再默默關掉：先問「這一趟只有 12 秒、0.00 公里，要存嗎？」
//   〔不存〕＝放棄這一趟、〔還是存〕＝照常存。問的時候記錄器停在暫停，什麼都沒丟。
// • GPS 燈多一級「精確位置關著，畫不出路線」（橘）＋「打開精確位置」：Info.plist 有說明字就跳系統框
//   「這一次給精確位置」，沒有（或這個畫面已經跳過一次系統框——含按開始時記錄器自己請的那次——還是關著）
//   就帶去設定；跑步中橘字也改說精確位置。
// • 格式全部轉呼叫 WorkoutFormat（一套寫法）：時間不到一小時寫「8:42」不再「08:42」；配速 6'11"。
// • 騎車那格改寫時速（「21.5」），距離 10 公里以上一位小數（「12.6」）。
//
// [v25.555] 健康 v5 新跑步畫面（build/v5/brief.md §G2；judge §4.0–4.3、樣稿②-2／②-3、③-B1～B9）：
// • 全螢幕：健康頁用 .fullScreenCover(item:) 打開（往下滑不會收掉）。沒有導覽列：上面一排浮在地圖上的膠囊——
//   左「關閉」（開始前）／「⌄ 收起」（記錄中，記錄器照跑）、中間運動名（開始前）／這一趟的時段名「晨跑」、右「⋯」。
//   指北針、比例尺改成獨立的控制項（同一個 mapScope），排在膠囊下面（不疊在「⋯」上、不受地圖安全區算法影響）。
// • 下面是天空面板（零件在 RunScreenParts.swift，這個檔只管狀態、地圖、流程）：
//   開始前 GPS 燈、四顆運動膠囊、直徑 88 的「開始」、「這週跑了 9.4 公里・目標 20」＋「上一趟：…」；
//   位置還沒問過先出我們的說明卡（prepare(asking: false) 不跳系統框），按〔好〕才問；位置被拒「開始」變灰、不能按。
//   跑步中 GPS 燈（弱時黃燈「GPS 弱・誤差 35 公尺」）、右上「第 4 公里」（騎車「時速 21.4」）、大字公里、
//   三格（左格、中格點了換，每種運動記住；右格固定平均）、這一公里小步道、〔暫停〕〔按住結束〕；
//   暫停：整片灰藍、「已暫停・1:12」一直在走、〔繼續〕〔結束〕。GPS 弱（記錄器 gpsWeak）：面板上方淡黃條。
// • 按開始先倒數 3-2-1（「⋯」可關，全部運動共用）：每秒震一下，「開始！」那一刻才 tracker.start（倒數這 3 秒定位照開著，
//   起點更穩）；點一下＝馬上開始、左上 ✕＝取消。
// • 結束：跑步中按住 1 秒（外圈填滿才算；開著 VoiceOver 改成點了先問「結束這一趟？」）、暫停中點一下〔結束〕。
//   太短（10 公尺內而且 30 秒內）跑步中先暫停再問。存檔順序不能改：tracker.finish → makeSession(…sessions:)
//   （名字存檔時就取好）→ 下一個 runloop：onFinish（呼叫端同步寫 store、排 Apple 健康）→ 反查地點 → 最後才把
//   同一個全螢幕換成 WorkoutDetailView(justFinished: true)（成果頁一打開就找得到那一趟），不 dismiss。
//   換之前那一瞬間先換成成果頁的底色（不然面板會閃一下開始前的樣子）。
// • 地圖：運動色線（跑步橘）＋白邊（深色深藍邊）、起點白圈運動色邊、每整公里一塊白底小牌（騎車只畫 5 的倍數）；
//   跑步中一律單色。兩指縮放改跟「上一次程式設的鏡頭中心」比（sim_v5 §9：手指離藍點遠時捏，以前 36% 被當成拖走）。
//   地圖上下讓出的安全區量真正的位置（上面那排膠囊的下緣、面板上緣到螢幕底），藍點放在中間那塊地圖的正中。
// • 螢幕保持亮著（「⋯」，每種運動各記，騎車預設開）：只在這個畫面開著、正在記錄（含暫停）、還沒換成果頁時關掉自動鎖定；
//   收起、跑完、放棄、太短不存都設回來。

struct RunTrackingView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @StateObject private var tracker = RunTracker.shared
    /// [v25.555] 指北針、比例尺跟地圖同一個 scope（獨立放在上面那排膠囊下面）
    @Namespace private var mapScope

    /// 結束後把成果交出去（呼叫端負責存檔與寫回 Apple 健康）。
    /// [v25.555] 結束後下一個 runloop 呼叫一次、呼叫端同步寫好 store；這個畫面不 dismiss，自己換成成果頁
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
    /// 上一次程式設的鏡頭中心：不到 2 公尺不挪、跳超過 200 公尺不做動畫；[v25.555] 兩指縮放也跟它比
    @State private var lastCenter: CLLocation?
    /// 拖走後 10 秒自己回來
    @State private var autoReturn: Task<Void, Never>?
    /// 第一次收到定位時直接跳過去（不做動畫）
    @State private var placed = false
    /// [v25.552] 太短的一趟結束時問的那句；nil＝沒在問
    @State private var shortPrompt: String?
    /// [v25.552] 這個畫面已經跳過一次「這一次給精確位置」的系統框（按鈕、或按開始時記錄器自己請的）；
    /// 還是關著再按就帶去設定（按了沒反應比帶去設定糟）。拿到精確位置就歸零
    @State private var preciseAsked = false

    /// [v25.555] 存好的那一趟：有值就整個畫面換成成果頁（剛跑完）
    @State private var finishedId: UUID?
    /// [v25.555] 按下結束、還沒換成成果頁的那一瞬間（記錄器已經回到 idle，面板不要閃回開始前的樣子）
    @State private var ending = false
    /// [v25.555] 上面那排膠囊的下緣（螢幕座標）：地圖上面讓出這麼多
    @State private var topBarBottom: CGFloat = 0
    /// [v25.555] 面板上緣（GPS 弱提示條下面，螢幕座標）
    @State private var panelTop: CGFloat = 0
    /// [v25.555] 地圖下緣（螢幕座標，＝螢幕底）：地圖下面讓出「面板上緣到螢幕底」這麼多
    @State private var screenBottom: CGFloat = 0
    /// [v25.555] 倒數：3、2、1；0＝「開始！」；nil＝沒在倒數
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    /// [v25.555] 說明卡按過〔好〕（之後就算系統框被關掉、還是 notDetermined，也不再擋開始前面板）
    @State private var permissionAsked = false
    /// [v25.555] 開始前面板下面那兩行（onAppear、換運動時算一次，不在 body 算）
    @State private var intro: RunIntro?
    /// [v25.555] 「⋯」裡倒數開關的鏡像（選單打勾即時更新）
    @State private var countdownOn = RunSport.countdownOn
    /// [v25.555] 切「螢幕保持亮著」時加一：讓 shouldKeepAwake、選單的勾重算
    @State private var keepAwakeTick = 0
    /// [v25.555] 點三格換內容時加一：讓格子重算（選擇記在 RunSport.cellChoice）
    @State private var cellTick = 0
    /// [v25.555] 開著 VoiceOver 時點「結束」：先問
    @State private var endConfirm = false

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

    /// [v25.555] 跑完存好：同一個全螢幕換成成果頁（剛跑完）；左上「完成」＝成果頁的 dismiss，關掉整個全螢幕
    var body: some View {
        if let id = finishedId {
            WorkoutDetailView(sessionId: id, justFinished: true)
        } else if ending {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        } else {
            runScreen
        }
    }

    private var runScreen: some View {
        ZStack {
            mapLayer
            overlayStack
            if let n = countdown {
                RunCountdownOverlay(value: n, onSkip: { skipCountdown() }, onCancel: { cancelCountdown() })
            }
        }
        .mapScope(mapScope)
        .onAppear { appear() }
        .onDisappear { disappear() }
        .onChange(of: shouldKeepAwake) { _, on in
            UIApplication.shared.isIdleTimerDisabled = on
        }
        .onChange(of: pickedSport) { sportChanged() }
        .onChange(of: tracker.reducedAccuracy) { _, reduced in
            if !reduced { preciseAsked = false }      // [v25.552] 給了：之後系統收回「這一次」的授權時，又可以跳系統框
        }
        .onChange(of: tracker.phase) { old, new in phaseChanged(old, new) }   // [v25.556] 鎖定畫面按〔繼續〕也會到
    }

    /// 現在算哪一種運動：開始後讀記錄器，開始前讀選擇器
    private var currentSport: RunSport {
        tracker.isActive ? tracker.sport : pickedSport
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    /// 運動色（跑步橘 EB6834）：線、起點、小步道條頭、說明卡的圖示
    private var sportTint: Color {
        WorkoutPalette.sport(WorkoutSport(currentSport), dark: scheme == .dark)
    }

    // MARK: 地圖

    private static let casingStroke = StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
    private static let lineStroke = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)

    private var mapLayer: some View {
        Map(position: $camera,
            bounds: cameraBounds,
            interactionModes: [.pan, .zoom],                                // 不給轉、不給傾斜：北方朝上
            scope: mapScope) {
            UserAnnotation()
            ForEach(liveSegments) { s in                                    // 記錄器算好、切好塊的段，只算一次
                MapPolyline(coordinates: s.coordinates)
                    .stroke(lineCasing, style: Self.casingStroke)
                MapPolyline(coordinates: s.coordinates)
                    .stroke(sportTint, style: Self.lineStroke)
            }
            ForEach(liveMarkers) { m in                                     // 每整公里一塊白底小牌
                Annotation("", coordinate: m.coordinate) {
                    RunKmPill(km: m.km)
                }
            }
            if let start = liveStart {
                Annotation("", coordinate: start) {
                    RunStartDot(tint: sportTint)
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))   // 淡色、不顯示店家，線最清楚
        .mapControls { }                                                          // 不放系統的控制項（定位鈕會搶鏡頭；指北針、比例尺另外放）
        .safeAreaPadding(.top, mapTopInset)                                       // 上面那排膠囊
        .safeAreaPadding(.bottom, mapBottomInset)                                 // 藍點放在面板上方那塊地圖的中間
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY
        } action: { y in
            if abs(y - screenBottom) > 0.5 { screenBottom = y }
        }
        .onChange(of: tracker.fixSerial) { follow() }
        .onMapCameraChange(frequency: .onEnd) { ctx in cameraEnded(ctx) }
    }

    /// 線外圈：淺色白邊；深色地圖深藍邊（judge §3.14）
    private var lineCasing: Color {
        scheme == .dark ? WorkoutPalette.casing(dark: true) : Color.white
    }

    /// 地圖上面讓出的高度（還沒量到時先用一般手機的值）
    private var mapTopInset: CGFloat {
        topBarBottom > 0 ? topBarBottom + 6 : 104
    }

    /// 地圖下面讓出的高度＝面板上緣到螢幕底（面板延伸到 Home 指示條那一塊）
    private var mapBottomInset: CGFloat {
        guard screenBottom > 0, panelTop > 0, screenBottom > panelTop else { return 300 }
        return screenBottom - panelTop
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

    /// [v25.555] 每整公里的小牌：記錄中才畫；騎車只畫 5 的倍數
    private var liveMarkers: [RunKmMarker] {
        guard tracker.isActive else { return [] }
        if tracker.sport == .bike { return tracker.kmMarkers.filter { $0.km % 5 == 0 } }
        return tracker.kmMarkers
    }

    /// 這一趟的起點（還沒開始、或還沒存到第一點就沒有）
    private var liveStart: CLLocationCoordinate2D? {
        guard tracker.isActive, let p = tracker.points.first else { return nil }
        return CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
    }

    /// 還沒收到任何定位（權限被拒、精確位置關著時由 GPS 燈說明，這裡不重複）。
    /// 說明卡還沒按〔好〕時也不畫：那時還沒問位置、根本沒在找（prepare(asking: false) 不開定位），面板正寫著「需要你的位置」
    private var showFindingHint: Bool {
        tracker.lastCoordinate == nil && !gpsDenied && !tracker.reducedAccuracy && !showPermissionCard
    }

    /// 指北針、比例尺：還在找位置、沒有位置權限、說明卡還沒按〔好〕時不畫（樣稿③-B1／B2）
    private var showMapControls: Bool {
        !showFindingHint && !gpsDenied && !showPermissionCard
    }

    // MARK: 上面那排膠囊

    /// 上面那排、下面的地圖按鈕＋面板（字最大到 xxxLarge：膠囊、按鈕是固定高度的浮層）
    private var overlayStack: some View {
        VStack(spacing: 0) {
            topArea
            Spacer(minLength: 0)
            dock
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var topArea: some View {
        VStack(spacing: 8) {
            topBar
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).maxY
                } action: { y in
                    if abs(y - topBarBottom) > 0.5 { topBarBottom = y }
                }
            if showFindingHint {
                RunFindingCapsule()
            } else if showMapControls {
                mapControlsRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    /// 左「關閉」／「⌄ 收起」、中間標題、右「⋯」。「放棄這一趟？」掛在這一排（面板上掛「太短要存嗎？」，同一個 view 不疊兩個 .alert）
    private var topBar: some View {
        HStack(spacing: 8) {
            closeButton
                .frame(maxWidth: .infinity, alignment: .leading)
            RunFloatingCapsule(title: titleText, style: .title)
                .accessibilityAddTraits(.isHeader)
            moreMenu
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .alert("放棄這一趟？", isPresented: $showDiscardAlert) {
            Button("放棄", role: .destructive) { abandon() }
            Button("繼續記錄", role: .cancel) { }
        } message: {
            Text("已經記錄的距離與路徑會直接丟掉，無法復原。")
        }
    }

    /// 開始前運動名「跑步」；記錄中這一趟的時段名「晨跑」（跟健康頁記錄中條同一支 timeOfDayName）
    private var titleText: String {
        guard tracker.isActive else { return pickedSport.rawValue }
        return WorkoutFacts.timeOfDayName(WorkoutSport(tracker.sport), start: tracker.activeStartedAt ?? Date())
    }

    private var closeTitle: String { tracker.isActive ? "收起" : "關閉" }

    private var closeIcon: String? { tracker.isActive ? "chevron.down" : nil }

    private var closeHint: String { tracker.isActive ? "回到健康頁，這一趟照樣記錄" : "" }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            RunFloatingCapsule(title: closeTitle, icon: closeIcon, style: .bar)
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityHint(closeHint)
    }

    private var moreMenu: some View {
        Menu {
            moreMenuItems
        } label: {
            RunFloatingCircle(icon: "ellipsis")
        }
        .accessibilityLabel("更多")
    }

    /// 開始前：倒數開關、螢幕保持亮著；記錄中：螢幕保持亮著、放棄這一趟（紅字，要確認）
    @ViewBuilder
    private var moreMenuItems: some View {
        if tracker.isActive {
            Toggle("螢幕保持亮著", isOn: keepAwakeBinding)
            Divider()
            Button(role: .destructive) {
                showDiscardAlert = true
            } label: {
                Label("放棄這一趟", systemImage: "trash")
            }
        } else {
            Toggle("倒數 3、2、1", isOn: countdownBinding)
            Toggle("螢幕保持亮著", isOn: keepAwakeBinding)
        }
    }

    private var countdownBinding: Binding<Bool> {
        Binding(get: { countdownOn }, set: { on in
            RunSport.setCountdown(on)
            countdownOn = on
        })
    }

    /// 這種運動的「螢幕保持亮著」（記錄中是這一趟的運動，開始前是選的運動）
    private var keepAwakeBinding: Binding<Bool> {
        Binding(get: { keepAwakeTick >= 0 && currentSport.keepAwake }, set: { on in
            currentSport.setKeepAwake(on)
            keepAwakeTick += 1
        })
    }

    /// 指北針、比例尺（一直顯示）
    private var mapControlsRow: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            MapScaleView(anchorEdge: .trailing, scope: mapScope)
            MapCompass(scope: mapScope)
        }
        .mapControlVisibility(.visible)
    }

    // MARK: 地圖按鈕＋面板

    private var dock: some View {
        VStack(spacing: 0) {
            if showMapButtons {
                mapButtons
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
            panel
        }
    }

    /// 這一趟有兩點以上才能「看整條路」
    private var canShowWholeRoute: Bool {
        tracker.isActive && tracker.points.count >= 2
    }

    private var showMapButtons: Bool {
        canShowWholeRoute || !following
    }

    /// 左「看整條路」、右「回到我身邊」（樣稿③-B3／B4）
    private var mapButtons: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if canShowWholeRoute {
                Button {
                    toggleWholeRoute()
                } label: {
                    RunFloatingCapsule(title: "看整條路", icon: "arrow.up.left.and.arrow.down.right",
                                       style: wholeRoute ? .mapSelected : .map)
                }
                .buttonStyle(MoneyPressStyle())
                .accessibilityAddTraits(wholeRoute ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
            if !following {
                returnColumn
            }
        }
    }

    private var returnColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                returnToMe()
            } label: {
                RunFloatingCapsule(title: "回到我身邊", icon: "location.fill", style: .mapLink)
            }
            .buttonStyle(MoneyPressStyle())
            if showAutoReturnHint {
                RunHintTag(text: "10 秒後自己回來")
            }
        }
    }

    /// 跑步中、沒在看整條路時才會自己回來（暫停中不回）
    private var showAutoReturnHint: Bool {
        tracker.phase == .running && !wholeRoute && !following
    }

    /// 天空面板＋「太短要存嗎？」提示框。
    /// 面板內容的位置量下來（減掉面板上方的留白）＝面板上緣：地圖下面讓出到這裡（GPS 弱提示條不算，條出現時地圖不跳）
    private var panel: some View {
        RunSkyPanel(paused: tracker.phase == .paused, clouds: tracker.isActive ? 1 : 2, strip: weakStripText) {
            panelContent
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).minY
                } action: { y in
                    let top = y - RunScreenMetrics.panelTopPadding
                    if abs(top - panelTop) > 0.5 { panelTop = top }
                }
        }
        .alert(shortPrompt ?? "", isPresented: showShortBinding) {
            Button("不存", role: .destructive) { abandon() }
            Button("還是存") { finishNow() }
        } message: {
            Text("不存的話，這一趟就不會出現在紀錄裡。")
        }
    }

    /// 回傳 AnyView：面板裡塞了十幾種東西，在這裡把型別抹掉（坑 #6：深層泛型在 runtime demangle 時爆棧）
    private var panelContent: AnyView {
        tracker.isActive ? AnyView(livePanel) : AnyView(startPanel)
    }

    /// 「太短要存嗎？」提示框開著沒有（關掉時清掉那句）
    private var showShortBinding: Binding<Bool> {
        Binding(get: { shortPrompt != nil }, set: { if !$0 { shortPrompt = nil } })
    }

    /// GPS 弱提示條（樣稿③-B6）：跑步中、記錄器說弱；還在等第一個好定位（橘字）、精確位置關著、沒有權限時燈自己說，不畫
    private var weakStripText: String? {
        guard tracker.phase == .running, tracker.gpsWeak, !tracker.waitingForFix,
              !tracker.reducedAccuracy, !gpsDenied else { return nil }
        return "GPS 訊號弱，距離可能少算"
    }

    // MARK: 開始前面板（樣稿②-2、③-B1／B2）

    private var startPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                gpsCapsule
                Spacer(minLength: 0)
            }
            if showPermissionCard {
                RunPermissionCard(tint: sportTint) { askLocation() }
                    .padding(.top, 12)
            } else {
                RunSportPicker(selected: pickedSport) { s in pickedSport = s }
                    .padding(.top, 12)
                RunStartCircle(enabled: canStart) { startTapped() }
                    .padding(.top, 18)
                RunIntroLines(week: introWeek, second: introSecond)
                    .padding(.top, 16)
            }
        }
    }

    /// 位置還沒問過、還沒按過說明卡的〔好〕
    private var showPermissionCard: Bool {
        !tracker.isActive && tracker.authorization == .notDetermined && !permissionAsked
    }

    /// 位置被拒：「開始」變灰、不能按（沒有位置就沒有路線；補記用「＋」）
    private var canStart: Bool { !gpsDenied }

    private var introWeek: String { intro?.week ?? "" }

    /// 第二行：沒有權限、還在找位置時換成一句說明（樣稿③-B1／B2），其他時候是上一趟
    private var introSecond: String? {
        if gpsDenied { return "沒有位置權限，記不了路線" }
        if gpsLevel == .searching { return "可以先按開始出發，訊號好了才開始畫線" }
        return intro?.last
    }

    // MARK: 跑步中面板（樣稿②-3、③-B3～B7、B9）

    private var livePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                gpsCapsule
                Spacer(minLength: 0)
                RunNumberText.text(rightTitle, numberColor: pal.ink)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(pal.ink)
                    .lineLimit(1)
            }
            RunLiveReadout(number: bigNumber, unit: "公里")
                .padding(.top, 6)
            if tracker.phase == .paused {
                pausedLine
            }
            cellsRow
                .padding(.top, 8)
            if let hint = waitingHint {
                waitingLabel(hint)
                    .padding(.top, 8)
            }
            if tracker.phase == .running {
                legTrail
                    .padding(.top, 14)
            }
            liveButtons
                .padding(.top, 16)
        }
    }

    /// 右上：跑走登山「第 4 公里」；騎車「時速 21.4」（最近 10 秒）
    private var rightTitle: String {
        if tracker.sport == .bike {
            return "時速 " + (tracker.recentSpeedKmh.map { WorkoutFormat.speedNumber($0) } ?? "—")
        }
        return WorkoutFacts.legTitle(tracker.legProgress)
    }

    /// 大字「3.42」（騎車 10 公里以上「12.6」）
    private var bigNumber: String {
        WorkoutFormat.preciseKmNumber(tracker.distanceMeters / 1000, sport: WorkoutSport(tracker.sport))
    }

    /// 「已暫停・1:12」：暫停中記錄器不發布，自己每秒重畫
    private var pausedLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            RunNumberText.text(pausedText(at: ctx.date), numberColor: pal.ink)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(pal.label)
        }
        .padding(.top, 2)
    }

    /// 暫停多久（往下取整，跟碼錶一樣）
    private func pausedText(at now: Date) -> String {
        let since = tracker.pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return "已暫停・" + WorkoutFormat.clock(seconds: since.rounded(.down))
    }

    /// 跑步中、還畫不出線時的橘字。[v25.552] 精確位置關著：每一筆定位誤差 1～3 公里都被丟掉，
    /// 只記得到時間，直接說原因（不然一直寫「訊號還沒好」，使用者以為等一下就好）
    private var waitingHint: String? {
        guard tracker.phase == .running else { return nil }
        if tracker.reducedAccuracy { return "精確位置關著：打開才畫得出路線（現在只記時間）" }
        if tracker.waitingForFix { return "訊號還沒好，可以先出發；好了才開始畫線" }
        return nil
    }

    /// 橘字（看板「等一下」那個橘：天空底上比系統橘清楚）
    private func waitingLabel(_ text: String) -> some View {
        Label(text, systemImage: "location.magnifyingglass")
            .font(.caption.weight(.semibold))
            .foregroundStyle(pal.waiting)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 這一公里小步道（暫停時不畫）
    private var legTrail: some View {
        let p = tracker.legProgress
        let sport = WorkoutSport(tracker.sport)
        let theme = MoneyArtTheme.of(sport)
        return RunLegTrail(fraction: p.fraction, colors: [theme.topColor, theme.bottomColor], tint: sportTint,
                           icon: sport.icon, text: WorkoutFacts.legText(p, sport: sport),
                           spoken: legSpoken(p, sport: sport))
    }

    /// 小步道給 VoiceOver 唸的：「第 4 公里走了 420 公尺，用了 2 分 40 秒」；騎車「這 5 公里騎了 2.6 公里」
    private func legSpoken(_ p: RunLegProgress, sport: WorkoutSport) -> String {
        if sport == .bike {
            return "這 5 公里騎了 " + String(format: "%.1f", max(0, p.doneMeters) / 1000) + " 公里"
        }
        var s = WorkoutFacts.legTitle(p) + "走了 \(WorkoutFormat.wholeSeconds(p.doneMeters.rounded(.down))) 公尺"
        if let sec = p.seconds {
            s += "，用了 " + Self.spokenClock(WorkoutFormat.clock(seconds: sec))
        }
        return s
    }

    /// 跑步中〔暫停〕〔按住結束〕；暫停中〔繼續〕〔結束〕（點一下就結束）。
    /// 「結束這一趟？」（VoiceOver）掛在跑步中這一排（面板掛「太短要存嗎？」，同一個 view 不疊兩個 .alert）
    @ViewBuilder
    private var liveButtons: some View {
        if tracker.phase == .paused {
            HStack(spacing: 12) {
                RunPanelButton(title: "繼續", icon: "play.fill", style: .green) { resumeRun() }
                RunPanelButton(title: "結束", icon: "stop.fill", style: .white) { finishTapped() }
            }
        } else {
            HStack(spacing: 12) {
                RunPanelButton(title: "暫停", icon: "pause.fill", style: .white) { tracker.pause() }
                RunHoldToFinishButton(onFinish: { holdFinished() }, onAsk: { endConfirm = true })
            }
            .alert("結束這一趟？", isPresented: $endConfirm) {
                Button("結束") { confirmEnd() }
                Button("繼續記錄", role: .cancel) { }
            }
        }
    }

    // MARK: 三格（judge §4.2；點左格、中格換內容，依運動記住）

    /// 格子的內容
    private enum LiveCell {
        case moving, clock, total, recent, climb, kcal, speed, average
    }

    /// 每秒重畫（暫停中記錄器不發布，現在時刻、總時間也要走）。
    /// .animation(nil, value: cellTick)：body 直接讀 cellTick，點了格子馬上重畫（暫停中不用等下一秒），換字不做動畫
    private var cellsRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            RunStatRow(cells: liveCells, onTap: { slot in cycleCell(slot) })
        }
        .animation(nil, value: cellTick)
    }

    private var liveCells: [RunStatCellData] {
        let sport = tracker.sport
        guard cellTick >= 0 else { return [] }
        return [cellData(slotKinds(0, sport: sport), slot: 0, sport: sport),
                cellData(slotKinds(1, sport: sport), slot: 1, sport: sport),
                fixedCell(sport)]
    }

    /// 左格、中格輪流的三種：左格 時間／現在時刻／總時間；中格 跑走 這一公里／爬升／大卡、登山 爬升／這一公里／大卡、
    /// 騎車 時速／爬升／大卡
    private func slotKinds(_ slot: Int, sport: RunSport) -> [LiveCell] {
        if slot == 0 { return [.moving, .clock, .total] }
        switch sport {
        case .run, .walk: return [.recent, .climb, .kcal]
        case .hike: return [.climb, .recent, .kcal]
        case .bike: return [.speed, .climb, .kcal]
        }
    }

    private func cellData(_ kinds: [LiveCell], slot: Int, sport: RunSport) -> RunStatCellData {
        let choice = min(max(sport.cellChoice(slot), 0), kinds.count - 1)
        let kind = kinds[choice]
        let next = kinds[(choice + 1) % kinds.count]
        let value = cellValue(kind)
        let label = cellLabel(kind, sport: sport)
        return RunStatCellData(value: value, label: label,
                               spoken: label + " " + spokenValue(kind, value),
                               hint: "點兩下換成" + cellLabel(next, sport: sport))
    }

    /// 右格（固定）：平均配速；騎車平均時速
    private func fixedCell(_ sport: RunSport) -> RunStatCellData {
        let value = cellValue(.average)
        let label = cellLabel(.average, sport: sport)
        return RunStatCellData(value: value, label: label, spoken: label + " " + spokenValue(.average, value), hint: nil)
    }

    private func cellValue(_ kind: LiveCell) -> String {
        switch kind {
        case .moving: return WorkoutFormat.clock(seconds: tracker.elapsed.rounded(.down))
        case .clock: return WorkoutFormat.time(Date())
        case .total: return WorkoutFormat.clock(seconds: totalSeconds.rounded(.down))
        case .recent: return WorkoutFormat.pace(tracker.recentPaceMinPerKm)
        case .climb: return WorkoutFormat.climb(tracker.elevationGainM)
        case .kcal: return kcalText
        case .speed: return tracker.recentSpeedKmh.map { WorkoutFormat.speedNumber($0) } ?? "—"
        case .average: return tracker.sport == .bike ? bikeSpeedText : WorkoutFormat.pace(tracker.paceMinPerKm)
        }
    }

    private func cellLabel(_ kind: LiveCell, sport: RunSport) -> String {
        switch kind {
        case .moving: return "時間"
        case .clock: return "現在時刻"
        case .total: return "總時間"
        case .recent: return "這一公里"
        case .climb: return "爬升"
        case .kcal: return "大卡"
        case .speed: return "時速"
        case .average:
            switch sport {
            case .bike: return "平均時速"
            case .hike: return "平均配速"
            case .run, .walk: return "平均"
            }
        }
    }

    /// 給 VoiceOver 的值：「6 分 20 秒」「21 分 5 秒」「13 公尺」「約 220 大卡」「21.4 公里」
    private func spokenValue(_ kind: LiveCell, _ value: String) -> String {
        guard value != "—" else { return "還沒有數字" }
        switch kind {
        case .moving, .total: return Self.spokenClock(value)
        case .recent: return Self.spokenPace(value)
        case .average: return tracker.sport == .bike ? value + " 公里" : Self.spokenPace(value)
        case .speed: return value + " 公里"
        case .climb: return value.replacingOccurrences(of: " m", with: " 公尺")
        case .kcal: return value + " 大卡"
        case .clock: return value
        }
    }

    /// 總時間（含暫停）＝現在 − 按開始那一刻
    private var totalSeconds: Double {
        guard let s = tracker.activeStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(s))
    }

    /// 「約 220」（大卡格的值；單位在標籤）；沒有體重、不到 1 分鐘「—」
    private var kcalText: String {
        guard let k = WorkoutFacts.liveKcal(sport: WorkoutSport(tracker.sport), km: tracker.distanceMeters / 1000,
                                            movingSeconds: tracker.elapsed,
                                            bodyWeightKg: lifeStore.latestBodyWeightKg) else { return "—" }
        return WorkoutFormat.kcal(k, estimated: true).replacingOccurrences(of: " 大卡", with: "")
    }

    /// 平均時速（公里）＝距離 ÷ 移動時間；跟配速一樣 50 公尺內不算（一開騎 GPS 一跳就是 80 公里/時）
    private var bikeSpeedText: String {
        guard tracker.distanceMeters > 50 else { return "—" }
        let v = WorkoutFormat.speedKmh(km: tracker.distanceMeters / 1000, minutes: tracker.elapsed / 60)
        return v.map { WorkoutFormat.speedNumber($0) } ?? "—"
    }

    /// 點左格（0）、中格（1）：換下一種，記在這種運動
    private func cycleCell(_ slot: Int) {
        guard slot == 0 || slot == 1 else { return }
        let sport = tracker.sport
        sport.setCellChoice(slot, (sport.cellChoice(slot) + 1) % 3)
        cellTick += 1
    }

    /// 「21:05」→「21 分 5 秒」、「1:05:12」→「1 小時 5 分 12 秒」
    static func spokenClock(_ text: String) -> String {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return "\(parts[0]) 小時 \(parts[1]) 分 \(parts[2]) 秒"
        case 2: return "\(parts[0]) 分 \(parts[1]) 秒"
        default: return text
        }
    }

    /// 「6'20"」→「6 分 20 秒」
    static func spokenPace(_ text: String) -> String {
        let parts = text.replacingOccurrences(of: "\"", with: "").split(separator: "'").compactMap { Int($0) }
        guard parts.count == 2 else { return text }
        return "\(parts[0]) 分 \(parts[1]) 秒"
    }

    // MARK: GPS 燈

    /// 每 2 秒重看一次：開始前站著不動、收不到新定位時畫面不會重畫，燈要自己退回「定位中…」
    private var gpsCapsule: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            RunGPSCapsule(color: gpsColor, text: gpsText, link: gpsLinkTitle) { gpsLinkTapped() }
        }
    }

    /// [v25.552] imprecise：有位置權限、但「精確位置」關著（誤差 1～3 公里，每一筆都被丟掉，畫不出線）。
    /// [v25.555] weak：跑步中記錄器說 GPS 弱（誤差超過 20 公尺連 10 秒、或 10 秒收不到）
    private enum GPSLevel { case denied, imprecise, weak, searching, fair, good }

    private var gpsDenied: Bool {
        tracker.authorization == .denied || tracker.authorization == .restricted
    }

    /// 10 秒內收過定位（隧道、橋下太久沒收到就回到黃燈）。
    /// 暫停中定位是低精度、記錄器不改燈的誤差（v25.556），燈停在按暫停時的樣子，不要變成「定位中…」嚇人
    private var gpsFresh: Bool {
        if tracker.phase == .paused { return true }
        return (tracker.secondsSinceFix ?? .infinity) <= 10
    }

    private var gpsLevel: GPSLevel {
        if gpsDenied { return .denied }
        if tracker.reducedAccuracy { return .imprecise }
        if tracker.gpsWeak { return .weak }
        guard let acc = tracker.gpsAccuracy, gpsFresh else { return .searching }
        if acc <= 10 { return .good }
        if acc <= 20 { return .fair }
        return .searching
    }

    /// 開始前寫完整「GPS 良好・誤差 5 公尺」；記錄中寫短的「GPS 良好」；弱時「GPS 弱・誤差 35 公尺」（沒有新的誤差數字寫「GPS 弱」）
    private var gpsText: String {
        let meters = tracker.gpsAccuracy.map { WorkoutFormat.wholeSeconds($0) } ?? 0
        let hasMeters = tracker.gpsAccuracy != nil && gpsFresh
        let short = tracker.isActive
        switch gpsLevel {
        case .denied: return "沒有位置權限"
        case .imprecise: return "精確位置關著，畫不出路線"
        case .weak: return hasMeters ? "GPS 弱・誤差 \(meters) 公尺" : "GPS 弱"
        case .good: return short ? "GPS 良好" : "GPS 良好・誤差 \(meters) 公尺"
        case .fair: return short ? "GPS 普通" : "GPS 普通・誤差 \(meters) 公尺"
        case .searching:
            if !short, hasMeters { return "定位中…（誤差 \(meters) 公尺）" }
            return "定位中…"
        }
    }

    private var gpsColor: Color {
        switch gpsLevel {
        case .denied: return .gray
        case .imprecise: return .orange
        case .weak, .searching: return Color(tb: 0xF5B400)
        case .fair: return Color(red: 0.55, green: 0.85, blue: 0.45)
        case .good: return WorkoutPalette.go
        }
    }

    /// 燈旁邊的藍字：沒有位置權限「去設定打開」；[v25.552] 精確位置關著「打開精確位置」
    private var gpsLinkTitle: String? {
        switch gpsLevel {
        case .denied: return "去設定打開"
        case .imprecise: return "打開精確位置"
        case .weak, .searching, .fair, .good: return nil
        }
    }

    private func gpsLinkTapped() {
        switch gpsLevel {
        case .denied: openSettings()
        case .imprecise: openPrecise()
        case .weak, .searching, .fair, .good: break
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

    // MARK: 開始（倒數 3-2-1，judge §4.1 第 5 列）

    /// 按「開始」：倒數開著就先倒數，關著直接開始。位置被拒時按不到（圓鈕 disabled），這裡再擋一次
    private func startTapped() {
        guard !tracker.isActive, countdown == nil, canStart else { return }
        if RunSport.countdownOn {
            beginCountdown()
        } else {
            startRun()
        }
    }

    /// 3 → 2 → 1 →「開始！」每秒震一下；「開始！」那一刻才 tracker.start，0.6 秒後蓋層收掉
    private func beginCountdown() {
        countdownTask?.cancel()
        countdown = 3
        haptic()
        countdownTask = Task { @MainActor in
            for next in [2, 1, 0] {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, countdown != nil else { return }
                if next == 0 { startRun() }
                countdown = next
                haptic()
            }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            countdown = nil
            countdownTask = nil
        }
    }

    /// 點蓋層任何地方：還在數就馬上開始；已經「開始！」就只收掉蓋層
    private func skipCountdown() {
        let counting = (countdown ?? 0) > 0
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        if counting {
            haptic()
            startRun()
        }
    }

    /// 左上 ✕：不開始
    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// 真的開始：運動已經由 @AppStorage 記住
    private func startRun() {
        guard !tracker.isActive else { return }
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

    /// 繼續（畫面上的〔繼續〕）。[v25.556] 暫停前把地圖拖走時的「10 秒自己回來」改由 phaseChanged 排
    /// （鎖定畫面、靈動島的〔繼續〕也要排；這裡再排一次會排兩次）
    private func resumeRun() {
        tracker.resume()
    }

    /// [v25.556] 從暫停回到跑步（畫面上的〔繼續〕、鎖定畫面／靈動島的〔繼續〕都會到這裡）：
    /// 暫停前把地圖拖走了，一樣 10 秒沒再碰就自己回來
    private func phaseChanged(_ old: RunTracker.Phase, _ new: RunTracker.Phase) {
        guard old == .paused, new == .running, !following, !wholeRoute else { return }
        scheduleAutoReturn()
    }

    /// 說明卡〔好〕：這時才跳系統的位置框（之後還有「動作與健身」框）
    private func askLocation() {
        permissionAsked = true
        tracker.prepare(asking: true)
    }

    // MARK: 螢幕保持亮著（judge §4.0）

    /// 這個畫面開著、正在記錄（含暫停）、還沒換成成果頁、這種運動開著
    private var shouldKeepAwake: Bool {
        finishedId == nil && !ending && tracker.isActive && tracker.sport.keepAwake && keepAwakeTick >= 0
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
    /// [v25.555] 跟「上一次程式設的鏡頭中心」比（還沒設過才跟藍點比；sim_v5 §9）：
    /// 遠近變了 10% 以上、中心挪不到 0.6 × max(新遠近, 舊遠近) ＝縮放（記住遠近、繼續跟、滑回藍點）；
    /// 遠近沒變、挪不到 0.15 × 遠近＝手抖（繼續跟）；其他＝拖走（停跟、10 秒自己回來）。
    /// 以前跟藍點比：手指離藍點遠的地方捏，鏡頭中心跟著手指跑，36% 被當成拖走
    private func cameraEnded(_ ctx: MapCameraUpdateContext) {
        guard camera.positionedByUser, !wholeRoute else { return }
        let d = min(max(ctx.camera.distance, 150), 20_000)
        let before = followDistance
        let center = CLLocation(latitude: ctx.camera.centerCoordinate.latitude,
                                longitude: ctx.camera.centerCoordinate.longitude)
        let me = tracker.lastKnownCoordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        guard let anchor = lastCenter ?? me else { return }
        let moved = center.distance(from: anchor)
        let zoomed = abs(d - before) > before * 0.1
        if zoomed {
            followDistance = d
            currentSport.rememberFollowDistance(d)                  // 存的時候夾 150～5,000
        }
        if (zoomed && moved < max(d, before) * 0.6) || moved < d * 0.15 {
            keepFollowing()
        } else {                                                    // 拖走了
            following = false
            scheduleAutoReturn()
        }
    }

    /// 縮放完、手抖：繼續跟、滑回藍點
    private func keepFollowing() {
        autoReturn?.cancel()
        autoReturn = nil
        following = true
        lastCenter = nil
        recenter(animated: true, glide: true)
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

    /// 開始前換運動：換成那種運動記住的遠近，回到你身邊；下面兩行換成那種運動的
    private func sportChanged() {
        refreshIntro()
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
        // [v25.555] 位置還沒問過：先不跳任何系統框（面板出說明卡，按〔好〕才問）；其他照舊先定位、先問「動作與健身」
        tracker.prepare(asking: tracker.authorization != .notDetermined)
        refreshIntro()
        // 手機不記得位置：先放在上一趟紀錄的起點（舊紀錄只有起點 1 點也算）；
        // 都沒有就留在台北車站 3 公里＋「正在找你的位置…」
        if !tracker.isActive, tracker.lastKnownCoordinate == nil, let start = lastRouteStart() {
            camera = .camera(MapCamera(centerCoordinate: start, distance: followDistance))
        }
        UIApplication.shared.isIdleTimerDisabled = shouldKeepAwake   // 「回到跑步」：照這種運動的設定
    }

    /// 收起、關掉、換成成果頁都會到這裡：倒數取消、自動鎖定設回來
    private func disappear() {
        autoReturn?.cancel()
        autoReturn = nil
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        tracker.stopPreparing()                                     // 只有沒在記錄時才真的關定位
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// 開始前面板下面兩行（這週幾公里、上一趟）
    private func refreshIntro() {
        intro = WorkoutFacts.runIntro(lifeStore.workouts, prefs: lifeStore.workoutPrefs, sport: WorkoutSport(pickedSport))
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

    // MARK: 結束（judge §4.1 第 13 列、§4.3「先存再看」）

    /// 按住滿 1 秒、VoiceOver 確認框〔結束〕。太短（10 公尺內而且 30 秒內，同 RunCheckpoint.isTooShort）：先停住時間再問
    private func holdFinished() {
        // VoiceOver 確認框是 0.35 秒後才走到這裡：那之間已經結束、放棄了就不再問「太短要存嗎？」
        guard tracker.isActive, finishedId == nil, !ending else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard tracker.distanceMeters <= 10, tracker.elapsed <= 30 else { finishNow(); return }
        tracker.pause()
        shortPrompt = shortPromptText
    }

    /// VoiceOver「結束這一趟？」〔結束〕：等提示框收完再走（太短時還要再跳一個提示框）
    private func confirmEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            holdFinished()
        }
    }

    /// 暫停中「結束」（點一下就結束）。[v25.552] 太短先問；問的時候記錄器還停在暫停，什麼都沒丟
    private func finishTapped() {
        guard tracker.distanceMeters <= 10, tracker.elapsed <= 30 else { finishNow(); return }
        shortPrompt = shortPromptText
    }

    /// 「這一趟只有 12 秒、0.00 公里，要存嗎？」（秒數跟面板上的時間一樣往下取整）
    private var shortPromptText: String {
        let seconds = WorkoutFormat.wholeSeconds(tracker.elapsed.rounded(.down))
        let km = WorkoutFormat.preciseKmNumber(tracker.distanceMeters / 1000)
        return "這一趟只有 \(seconds) 秒、\(km) 公里，要存嗎？"
    }

    /// 放棄這一趟、太短〔不存〕：記錄器 cancel（連中途存檔一起刪）、自動鎖定設回來、關掉畫面
    private func abandon() {
        tracker.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        dismiss()
    }

    /// 存檔（順序不能改，brief §1-6）：tracker.finish → makeSession（名字存檔時取好：同一個起點沿用改過的名字，不然照時段）
    /// → 下一個 runloop：onFinish（呼叫端同步寫 store、排 Apple 健康）→ 反查地點（store 已經有那一趟）→ 最後才換成成果頁
    /// （成果頁一打開就找 store 裡的那一趟，找不到 0.6 秒後會自己關掉）。
    /// [v25.552] 存檔組裝只有一支（救回中途存檔也走它）：先用完整的點算每公里分段，再簡化路線（地圖、Apple 健康的路線照樣有）
    private func finishNow() {
        guard tracker.isActive, finishedId == nil, !ending else { return }   // 連按兩次只存一次
        let r = tracker.finish()
        let session = WorkoutFacts.makeSession(from: r, bodyWeightKg: lifeStore.latestBodyWeightKg,
                                               sessions: lifeStore.workouts)
        UIApplication.shared.isIdleTimerDisabled = false
        ending = true
        let handOff = onFinish
        let store = lifeStore
        DispatchQueue.main.async {
            handOff(session)                                        // 呼叫端同步寫好 store
            WorkoutPlaceLookup.shared.fill(session, store: store)
            finishedId = session.id                                 // 同一個全螢幕換成成果頁（剛跑完）
        }
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
