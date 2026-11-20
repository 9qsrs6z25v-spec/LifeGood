import SwiftUI
import MapKit
import UIKit

// MARK: - 「在地圖上選位置」共用模板（v25.432）
//
// 這一整套原本長在旅遊規劃裡（TripMapPickerSheet），但「打字搜不到的地方，
// 挪地圖對準就好」不是旅遊獨有的需求——記一筆變動支出時，路邊那攤沒有登記的
// 小吃、產業道路旁的維修廠，一樣搜不到。所以搬出來變成全 App 共用的三件組：
//
//   1. MapPlacePickerSheet  ── 選位置的畫面本身（搜尋、點地標、準心、實景照片）
//   2. MapPlacePickerButton ── 表單裡那一列「在地圖上選位置」＋「已帶入座標／清除」
//   3. PlaceFieldFill       ── 「欄位裡的字是誰打的」的記錄器，決定重選地點時
//                              名稱與地址要不要跟著換（見它自己的說明）
//
// 三件是分開的，因為各畫面的欄位長得不一樣：旅遊是 name/address 兩個 @State，
// 記帳的名稱可能是 title 也可能是 placeName（看分類），地址還是 Optional。
// 硬包成一個元件反而每個呼叫端都要先把自己的欄位扭成它要的形狀。

// MARK: - 在地圖上選位置

/// 文字搜尋找不到的地方（產業道路邊的景點、沒登記的民宿、只知道大概在哪的海灘），
/// 直接在地圖上挪到那個點就好。
///
/// 用「地圖動、準心不動」而不是「點一下放大頭針」：
/// 手指點下去的位置會被自己的手指擋住，挪地圖才能看著目標對準；
/// 而且這個做法不必把畫面座標換算回經緯度，少一個會出錯的環節。
/// 挑到的地點（v25.500）。
///
/// 本來是三個散的參數（名稱、地址、座標）。改成一個結構是因為多了電話——
/// 而且**電話不會是最後一個**：挑一個地方回來，之後還可能要營業時間、
/// 網站、評分。每多一樣就改一次所有呼叫端的函式簽名是沒有盡頭的。
struct PickedPlace {
    /// 地標名稱；nil＝那裡沒有標示，只是一個座標
    var name: String?
    var address: String
    var coordinate: CLLocationCoordinate2D
    /// 電話。日本的車機導航是用電話號碼找目的地的，所以這是導航欄位。
    var phone: String?
}

/// 搜尋建議右邊那一塊距離（v25.499）。
///
/// 使用者回報：「每次都跑出地址沒有距離，導致我常常不知道要選哪個」。
/// 搜一個地名跳出五筆長得幾乎一樣的地址，沒有距離就只能亂猜。
///
/// 六個搜尋清單共用同一個寫法——六種不同的距離格式會讓人以為它們是
/// 六種不同的東西。圖示說明距離是從哪裡量的：location 是「離你」，
/// mappin 是「離這一站」。沒有這個圖示的話，規劃福岡行程時看到
/// 「300 公尺」會不知道是離台北的家三百公尺還是離飯店三百公尺。
struct PlaceDistanceBadge: View {
    let meters: CLLocationDistance?
    /// 量距離的起點：離使用者（預設）還是離某個地點
    var icon: String = "location.fill"

    var body: some View {
        HStack(spacing: 2.5) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(meters.map { RestaurantSearchCompleter.distanceText($0) } ?? "⋯")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        // 還在查的時候先佔住位置：算出來才撐開的話，整列會往旁邊跳一下，
        // 剛好是使用者準備按下去的那一刻
        .frame(minWidth: 52, alignment: .trailing)
        .foregroundStyle(meters == nil ? .tertiary : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(Color(.secondarySystemFill).opacity(meters == nil ? 0.5 : 1)))
        .animation(.easeOut(duration: 0.18), value: meters == nil)
    }
}

// MARK: - 一次「在地圖上選位置」的進度（v25.627）

/// [v25.627] 一次「在地圖上選位置」的進度：鏡頭、搜尋字、點到的點。
///
/// 由〔在地圖上選位置〕那一列在按下去那一刻建立、交給 sheet（sheet(item:) 的 item 就是它）。
/// sheet 的畫面就算被系統重建，也從這裡接著來：不會回到打開時的位置，打到一半的字也不會不見。
/// 以前這些都是 sheet 自己的 @State，畫面一重建就全部回到初值（地圖跳回打開時的中心）。
///
/// 不標 @MainActor（跟 LocationProvider、RestaurantSearchCompleter 一樣）：只在主執行緒上被碰到，
/// 標了反而在 Swift 5 模式下讓 Identifiable 出隔離警告。
/// 判斷用的都是 static 純函式，畫面只負責把結果套上去（sim_mappicker.py 一個函式一個函式對照）。
final class MapPickerSession: ObservableObject, Identifiable {
    let id = UUID()
    /// 打開時要停的地方（已有座標＞使用者位置＞台北車站）
    let start: CLLocationCoordinate2D
    /// 打開時就帶著座標（在微調）；false＝在找地方
    let startedWithCoordinate: Bool
    /// 地圖鏡頭（Map(position:) 綁這個）。使用者挪過之後會被寫成「現在這個鏡頭」，見 shouldWriteBack
    @Published var position: MapCameraPosition
    /// 地圖現在的中心（準心指的那一點）
    @Published var center: CLLocationCoordinate2D
    /// 搜尋列打的字
    @Published var query: String = ""
    /// 在地圖上點到的那一點（或搜尋選中的那一筆）。有值時就用它，不看準心
    @Published var tapped: MapPlacePickerSheet.TappedPoint? = nil
    /// 畫面上下大約涵蓋幾公尺（點擊容許誤差用；不必觸發重繪）
    var visibleMeters: Double = 1_000
    /// 使用者正在打字（焦點在搜尋列）。只有我們自己的動作會把它關掉：
    /// 選了搜尋建議、按鍵盤的搜尋、打字中點地圖、〔取消〕
    var searchActive = false
    /// 畫面重建後把焦點還回去的次數（最多 maxFocusRestores 次，防止「鍵盤 → 重建 → 鍵盤」打轉）
    var focusRestores = 0

    /// 沒有任何線索時的起點：台北車站。總比落在大西洋上好。
    static let fallbackCenter = CLLocationCoordinate2D(latitude: 25.0478, longitude: 121.5170)
    /// 綁定裡記的位置跟地圖現在停的位置差超過這麼多公尺，就算綁定過時
    static let staleMeters: CLLocationDistance = 3
    /// 重建後最多把焦點還回去幾次
    static let maxFocusRestores = 2
    /// 使用者位置超過這麼多秒才重新要一次
    static let locationMaxAge: TimeInterval = 120
    /// 點地圖時，離搜尋層底線、定位鈕這麼近（pt）也不算點地圖
    static let tapMargin: CGFloat = 4

    init(initialCoordinate: CLLocationCoordinate2D?) {
        let start = initialCoordinate
            ?? LocationProvider.shared.lastLocation?.coordinate
            ?? Self.fallbackCenter
        self.start = start
        self.startedWithCoordinate = initialCoordinate != nil
        self.center = start
        // 已經有座標就貼近一點（在微調），沒有就拉遠一點（在找地方）
        let span = initialCoordinate == nil ? 0.05 : 0.004
        self.position = .region(MKCoordinateRegion(
            center: start,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))
    }

    /// 地圖停下來（onMapCameraChange .onEnd）時，要不要把「現在這個鏡頭」寫回 position。
    ///
    /// 使用者挪過（MapKit 回寫的是不帶位置的 positionedByUser），或綁定裡還是舊位置（差超過 3 公尺），
    /// 就寫。畫面若被重建，新的地圖就從這裡開，不會跳回打開時的位置。
    /// 寫進去的就是現在的鏡頭，下一次 onEnd 比對相同就不會再寫，不會打轉。
    /// 按定位鈕之後的 .userLocation 沒有座標、也不是 positionedByUser：不寫，保留「跟著我」。
    static func shouldWriteBack(_ p: MapCameraPosition,
                                cameraCenter c: CLLocationCoordinate2D) -> Bool {
        p.positionedByUser || isStale(p, comparedTo: c)
    }

    /// 綁定裡記的位置跟地圖現在停的位置差超過 3 公尺（＝綁定已經過時）。
    /// 綁定是「跟著使用者位置」或「使用者挪過」這種沒有座標的，就不算過時。
    static func isStale(_ p: MapCameraPosition, comparedTo c: CLLocationCoordinate2D) -> Bool {
        guard let s = p.region?.center ?? p.camera?.centerCoordinate else { return false }
        let a = CLLocation(latitude: s.latitude, longitude: s.longitude)
        let b = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return a.distance(from: b) > staleMeters
    }

    /// 畫面（重新）出現時要不要把焦點還給搜尋列。會記次數，所以每次呼叫只問一次。
    /// 第一次打開時 searchActive 是 false，不會自動跳鍵盤。
    func takeFocusRestore() -> Bool {
        guard searchActive, focusRestores < Self.maxFocusRestores else { return false }
        focusRestores += 1
        return true
    }

    /// 點了地圖要做什麼
    enum TapAction: Equatable {
        /// 正在打字：只收鍵盤，不算選點（第一下是「不打了」）
        case dismissKeyboard
        /// 落在搜尋列、建議清單、定位鈕那一塊：不算點地圖
        case ignore
        /// 選這一點（就近找地標）
        case pick
    }

    /// 點地圖的判斷。p、searchBottom、controlsFrame 都是同一個座標（地圖的左上角＝原點）。
    /// controlsFrame 是 .zero（空的）＝定位鈕收起來了。
    static func tapAction(at p: CGPoint, searchFocused: Bool,
                          searchBottom: CGFloat, controlsFrame: CGRect) -> TapAction {
        if searchFocused { return .dismissKeyboard }
        if p.y <= searchBottom + tapMargin { return .ignore }
        if !controlsFrame.isEmpty,
           controlsFrame.insetBy(dx: -tapMargin, dy: -tapMargin).contains(p) { return .ignore }
        return .pick
    }

    /// 打開地圖時要不要重新要一次使用者位置：沒有位置、或位置超過 2 分鐘才要。
    /// 以前每次打開都要一次，1–2 秒後位置發布，連帶把底下的記帳表單叫醒重繪。
    static func needsLocationRefresh(_ last: CLLocation?, now: Date = Date()) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last.timestamp) > locationMaxAge
    }
}

struct MapPlacePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// [v25.627] 這一次選位置的進度（鏡頭、搜尋字、點到的點）。由〔在地圖上選位置〕那一列建立，
    /// 畫面被重建時從這裡接著來（以前是這個畫面自己的 @State，一重建就回到打開時的位置）
    @ObservedObject private var session: MapPickerSession
    /// 回傳挑到的地點（名稱、地址、座標、電話）
    let onPick: (PickedPlace) -> Void
    /// 主色。各畫面各有自己的色系（旅遊紫、飲食橘…），預設沿用旅遊的
    var accent: Color = TripDayPalette.color(0)

    @State private var address = ""
    @State private var suggestedName: String?
    @State private var isResolving = false
    /// 正在找手指按到的是哪個地標
    @State private var isPickingPOI = false

    /// [v25.431] 搜尋地名／店名，選中就把地圖飛過去。
    ///
    /// 沒有它的時候，要選一個遠方的地點只能一路拖、一路縮——
    /// 規劃國外行程時尤其難用（從台灣拖到福岡）。
    @StateObject private var searchCompleter = RestaurantSearchCompleter()
    @State private var searchDebounce: Task<Void, Never>?
    @State private var isJumping = false
    @FocusState private var searchFocused: Bool

    /// [v25.627] 定位鈕、指北針跟地圖用同一個 scope（照 RunTrackingView），才能排在搜尋列下面
    @Namespace private var mapScope
    /// [v25.627] 搜尋列＋建議清單的底（canvas 座標＝地圖的座標）。點地圖落在這條線以上不算選點
    @State private var searchBottom: CGFloat = 64
    /// [v25.627] 定位鈕＋指北針那一塊（canvas 座標）。收起來時是 .zero
    @State private var controlsFrame: CGRect = .zero
    /// 地圖、資訊卡、搜尋層共用的座標空間。Map 的左上角就是它的原點（Map 只往下延伸）
    private static let canvasSpace = "mapPickerCanvas"

    struct TappedPoint: Equatable {
        let coordinate: CLLocationCoordinate2D
        /// 找到的地標名稱；nil＝那裡沒有地標，只是一個座標
        let name: String?
        /// 這個地標的電話。只有「點到真的地標」或「從搜尋選進來」才有——
        /// 空白處的座標本來就沒有電話可言。
        var phone: String? = nil

        static func == (a: TappedPoint, b: TappedPoint) -> Bool {
            a.name == b.name
                && abs(a.coordinate.latitude - b.coordinate.latitude) < 0.000_001
                && abs(a.coordinate.longitude - b.coordinate.longitude) < 0.000_001
        }
    }

    init(session: MapPickerSession,
         accent: Color = TripDayPalette.color(0),
         onPick: @escaping (PickedPlace) -> Void) {
        _session = ObservedObject(wrappedValue: session)
        self.accent = accent
        self.onPick = onPick
    }

    // [v25.627] 轉接：狀態搬進 session，原本讀這些名字的地方不用改
    private var center: CLLocationCoordinate2D { session.center }
    private var query: String { session.query }
    /// 在地圖上點到的那一點。有值時就用它，不看畫面中央的準心。
    ///
    /// ⚠️ 不用 Map(selection:) 那套：MapSelection 是 iOS 18 才有的，這個 App
    ///    最低支援 iOS 17（送審時整包編不過就是卡在這裡）。改成自己接點擊：
    ///    MapReader 把畫面座標換成經緯度，再就近找一筆地標，效果一樣而且 iOS 17 可用。
    private var tapped: TappedPoint? {
        get { session.tapped }
        nonmutating set { session.tapped = newValue }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mapLayer
                infoCard
            }
            .overlay(alignment: .top) { searchOverlay }
            // [v25.627] 地圖、搜尋層同一個座標空間（點地圖時判斷是不是點在搜尋列那一塊）、
            // 同一個 mapScope（定位鈕、指北針排在搜尋列下面，見 mapControlsColumn）
            .coordinateSpace(.named(Self.canvasSpace))
            .mapScope(mapScope)
            .navigationTitle("在地圖上選位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        session.searchActive = false
                        dismiss()
                    }
                }
            }
            .onAppear { appear() }
            .onDisappear { searchDebounce?.cancel() }
            // 點到別的地標、或挪動地圖之後，都要重查一次地址
            .task(id: resolveKey) { await resolve(pickedCoordinate) }
        }
    }

    private func appear() {
        // [v25.627] 不再每次打開都重新定位（C7）：沒有位置、或位置超過 2 分鐘才要一次。
        // 以前每次都要，1–2 秒後位置發布，連帶把底下的記帳表單叫醒重繪
        let lp = LocationProvider.shared
        if MapPickerSession.needsLocationRefresh(lp.lastLocation) { lp.requestIfNeeded() }
        // 這個畫面要能打地名與地址，不只是店名——預設的 POI-only
        // 會讓「大名 115-30」這種查不到東西
        searchCompleter.setResultTypes([.pointOfInterest, .address])
        // 距離從**地圖現在看的地方**量，不是從使用者身上量。
        // 在台北規劃福岡的行程時，每一筆都是「1200 公里」，
        // 那個數字沒有幫任何人挑到任何東西。
        searchCompleter.setReference(CLLocation(latitude: center.latitude,
                                                longitude: center.longitude))
        searchCompleter.setRegion(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)))
        // [v25.627] 畫面被重建時：打到一半的字接著查、焦點還回去（最多 2 次，防止打轉）
        if !session.query.isEmpty, searchCompleter.results.isEmpty {
            scheduleSearch(session.query)
        }
        if session.takeFocusRestore() {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                searchFocused = true
            }
        }
    }

    private var mapLayer: some View {
        // MapReader 才拿得到「畫面上的點 → 經緯度」的換算（iOS 17 就有）
        MapReader { proxy in
            ZStack {
                Map(position: $session.position, scope: mapScope) {
                    UserAnnotation()
                    if let tapped {
                        Annotation(tapped.name ?? "選取的位置", coordinate: tapped.coordinate) {
                            selectedMarker
                        }
                    }
                }
                // POI 這裡要開著：使用者是靠地標認位置的，全部關掉就只剩一片空白底圖
                .mapStyle(.standard(pointsOfInterest: .all))
                // [v25.627] 不放系統的控制項：系統的定位鈕在右上角，被搜尋列疊住一半，
                // 點搜尋列右邊會按到它（地圖被拉回藍點、也打不了字）。改排在搜尋列下面，見 mapControlsColumn
                .mapControls { }
                .onMapCameraChange(frequency: .onEnd) { context in cameraEnded(context) }
                // 拖曳與縮放是拖／捏的手勢，單點不會被地圖吃掉，所以可以直接接
                .onTapGesture { screenPoint in mapTapped(at: screenPoint, proxy: proxy) }

                // 已經點過地圖就不要再畫準心——兩個「我選的是這裡」會互相打架
                if tapped == nil { crosshair }
            }
            // [v25.627] 從 Map 搬到這裡：地圖和準心用同一塊範圍置中，準心指的就是會被記下來的那一點；
            // 鍵盤出來時兩個都不跟著縮（以前只有 Map 忽略，準心會往上跑半個鍵盤高）
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func cameraEnded(_ context: MapCameraUpdateContext) {
        session.center = context.region.center
        // 記下目前看到多大範圍，決定「點下去算是點到哪個地標」的容許距離
        session.visibleMeters = context.region.span.latitudeDelta * 111_000
        // [v25.627] 鏡頭跟著手指：使用者挪過、或綁定裡還是舊位置，就把「現在這個鏡頭」寫回去。
        // 用 .camera 不用 .region：.region 會把使用者轉過的方向轉回正北
        if MapPickerSession.shouldWriteBack(session.position,
                                            cameraCenter: context.camera.centerCoordinate) {
            session.position = .camera(context.camera)
        }
        // 搜尋建議以目前看到的範圍為優先：在福岡看地圖時打「7-11」
        // 該先給福岡的，不是台北的
        searchCompleter.setRegion(context.region)
        // 距離也跟著重新量：地圖挪到哪，「多遠」就是從那裡算起。
        // 移動不到 200 公尺不會重算（見 setReference）。
        searchCompleter.setReference(
            CLLocation(latitude: context.region.center.latitude,
                       longitude: context.region.center.longitude))
    }

    /// 點了地圖。點的位置是地圖自己的座標（.local），它的原點就是 canvas 的原點，
    /// 所以可以直接跟 searchBottom、controlsFrame 比。
    private func mapTapped(at screenPoint: CGPoint, proxy: MapProxy) {
        let action = MapPickerSession.tapAction(at: screenPoint, searchFocused: searchFocused,
                                                searchBottom: searchBottom,
                                                controlsFrame: controlsFrame)
        switch action {
        case .dismissKeyboard:
            // 正在打字時點地圖：只收鍵盤，不算選點（第一下是「不打了」）
            searchFocused = false
            session.searchActive = false
        case .ignore:
            // 落在搜尋列、建議清單、定位鈕那一塊的點擊不算點地圖
            break
        case .pick:
            guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
            Task { await pickPOI(at: coordinate) }
        }
    }

    // MARK: 搜尋

    /// 疊在地圖上方的搜尋列。做成疊層而不是把地圖往下推：
    /// 地圖看得越大越好找，而搜尋列多數時候只是待在那裡不動。
    private var searchOverlay: some View {
        VStack(spacing: 6) {
            VStack(spacing: 6) {
                searchField
                if !searchCompleter.results.isEmpty { suggestionList }
            }
            // [v25.627] 量出搜尋列＋建議清單的底：點地圖落在這條線以上不算選點
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(Self.canvasSpace)).maxY
            } action: { y in
                searchBottom = y
            }
            if showMapControls { mapControlsColumn }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// [v25.627] 打字中、有建議清單時先把定位鈕收起來，免得又疊到
    private var showMapControls: Bool {
        !searchFocused && searchCompleter.results.isEmpty
    }

    /// [v25.627] 定位鈕、指北針排在搜尋列下面靠右。以前是系統預設的右上角，
    /// 被搜尋列疊住一半，點搜尋列右邊會按到定位鈕，地圖被拉回藍點、也打不了字。
    /// Spacer 那一塊是透明的，不吃點擊，地圖照樣拖得動、點得到。
    private var mapControlsColumn: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                MapUserLocationButton(scope: mapScope)
                MapCompass(scope: mapScope)
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.canvasSpace))
            } action: { r in
                controlsFrame = r
            }
            .onDisappear { controlsFrame = .zero }
        }
        .padding(.top, 2)
    }

    private var searchField: some View {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    // [v25.627] 點放大鏡也算點搜尋列：讓點擊穿到背景那層
                    .allowsHitTesting(false)
                TextField("搜尋地名、店名或地址", text: $session.query)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onChange(of: session.query) { _, newValue in scheduleSearch(newValue) }
                    .onChange(of: searchFocused) { _, focused in
                        // 只記「開始打字」；false 不在這裡清（重建時舊畫面可能先送一個 false）
                        if focused { session.searchActive = true }
                    }
                    .onSubmit {
                        session.searchActive = false
                        jumpToFirstResult()
                    }
                if isJumping {
                    ProgressView().scaleEffect(0.6)
                } else if !query.isEmpty {
                    Button {
                        session.query = ""
                        searchCompleter.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                    // [v25.627] 點到放大鏡、左右留白也算點搜尋列。手勢掛在背景上，
                    // 不是 TextField 的上層，不會跟 TextField 自己的點擊打架
                    .onTapGesture { searchFocused = true }
            }
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
    }

    private var suggestionList: some View {
                VStack(spacing: 0) {
                    ForEach(Array(searchCompleter.results.prefix(6).enumerated()),
                            id: \.offset) { index, r in
                        if index > 0 {
                            Divider().padding(.leading, 12)
                        }
                        Button { jump(to: r) } label: {
                            MapPickerSuggestionLabel(title: r.title, subtitle: r.subtitle,
                                                     meters: searchCompleter.distance(for: r),
                                                     accent: accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.18), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private func scheduleSearch(_ q: String) {
        searchDebounce?.cancel()
        let text = q.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { searchCompleter.clear(); return }
        searchDebounce = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { searchCompleter.queryFragment = text }
        }
    }

    /// 按鍵盤上的搜尋：沒有特別挑就用第一筆。
    /// 打完字直接按搜尋是很自然的動作，不該什麼都沒發生。
    private func jumpToFirstResult() {
        guard let first = searchCompleter.results.first else { return }
        jump(to: first)
    }

    /// 選了一筆搜尋建議：把地圖飛過去，並且直接當成「已經選到這個地標」。
    ///
    /// 只移動鏡頭是不夠的——使用者搜「大分縣福岡事務所」就是要選它，
    /// 飛過去之後還要再點一次才算數的話，等於只做了一半。
    private func jump(to completion: MKLocalSearchCompletion) {
        searchFocused = false
        session.searchActive = false
        isJumping = true
        searchDebounce?.cancel()
        Task { @MainActor in
            // 刻意自己做一次搜尋，不用 completer.resolve()：那個方法把
            // resultTypes 限成 POI（給飲食紀錄用的），拿它來解地址建議會回 nil，
            // 使用者按下去等於沒反應
            let request = MKLocalSearch.Request(completion: completion)
            let item = try? await MKLocalSearch(request: request).start().mapItems.first
            isJumping = false
            guard let item else { return }
            let coordinate = item.placemark.coordinate
            session.center = coordinate
            let name = item.name?.trimmingCharacters(in: .whitespaces)
            tapped = TappedPoint(coordinate: coordinate,
                                 name: (name?.isEmpty ?? true) ? nil : name,
                                 phone: item.phoneNumber)
            withAnimation(.easeInOut(duration: 0.35)) {
                session.position = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)))
            }
            session.query = ""
            searchCompleter.clear()
        }
    }

    private var selectedMarker: some View {
        ZStack {
            Circle().fill(accent).frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
        }
    }

    /// 手指按下去那一點是哪個地標。
    ///
    /// 點擊只會給座標，不會給名稱，所以就近找一筆 POI：容許範圍內最近的那個
    /// 就當成使用者想點的。找不到就只記座標——那裡本來就沒有標示，
    /// 使用者要的就是「這個位置」。
    @MainActor
    private func pickPOI(at coordinate: CLLocationCoordinate2D) async {
        // 先把選取點放到手指按的地方：就算等一下找不到地標，位置也已經是對的
        tapped = TappedPoint(coordinate: coordinate, name: nil)
        isPickingPOI = true
        defer { isPickingPOI = false }

        // 容許誤差跟著縮放走：地圖拉遠時一個手指頭就蓋掉好幾百公尺，
        // 固定 60 公尺會變成怎麼點都點不到；拉近時又不該把隔壁店家吸過來。
        let tolerance = min(400, max(30, session.visibleMeters * 0.03))
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: tolerance)
        guard let response = try? await MKLocalSearch(request: request).start() else { return }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearest = response.mapItems
            .compactMap { item -> (MKMapItem, CLLocationDistance)? in
                guard let location = item.placemark.location else { return nil }
                return (item, location.distance(from: origin))
            }
            .min { $0.1 < $1.1 }
        guard !Task.isCancelled, let nearest, nearest.1 <= tolerance,
              let name = nearest.0.name?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty else { return }
        tapped = TappedPoint(coordinate: nearest.0.placemark.coordinate, name: name,
                             phone: nearest.0.phoneNumber)
    }

    /// 準心固定在畫面正中央：小圓點就是真正會被記下來的那個座標（不位移），
    /// 大頭針往上移自己的高度，讓針尖正好落在圓點上。
    private var crosshair: some View {
        ZStack {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
            Image(systemName: "mappin")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(accent)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .offset(y: -17)
        }
        .allowsHitTesting(false)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: tapped == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(accent)
                MarqueeText(pickedName ?? "這個位置")
                    .font(.subheadline.weight(.semibold))
                if isResolving || isPickingPOI {
                    ProgressView().scaleEffect(0.55)
                }
                Spacer(minLength: 0)
                if tapped != nil {
                    Button("改用準心") { tapped = nil }
                        .font(.caption2.weight(.semibold))
                }
            }
            if let phone = tapped?.phone, !phone.isEmpty {
                // [v25.500] 日本的車機導航是用電話找目的地的——日文地址在車機
                // 的鍵盤上幾乎打不出來。所以挑地點的時候就要看得到電話，
                // 不是存進去之後才發現沒有。
                Label(phone, systemImage: "phone.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
            }
            Text(address.isEmpty
                 ? (isResolving ? "正在查地址…" : "查不到地址，仍然可以用這個座標")
                 : address)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(format: "%.5f, %.5f",
                        pickedCoordinate.latitude, pickedCoordinate.longitude))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            // [v25.431] 照片畫廊收進資訊卡裡，跟名稱、地址擺在一起。
            // 這三樣回答的是同一個問題——「我點到的是不是我想的那個地方」。
            if tapped != nil {
                MapPickerPlaceGallery(coordinate: pickedCoordinate, accent: accent)
            }

            Button {
                onPick(PickedPlace(name: pickedName, address: address,
                                   coordinate: pickedCoordinate,
                                   phone: tapped?.phone))
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(tapped?.name == nil ? "使用這個位置" : "使用這個地標")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(LinearGradient(colors: [accent, accent.opacity(0.75)],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Text(hintText)
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.separator).opacity(0.15), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// 字串在 ViewBuilder 外組好
    private var hintText: String {
        guard let tapped else {
            return "地圖上的店家、景點可以直接點選；沒有標示的地方就挪動地圖把準心對上去。"
                + "查不到地址也沒關係——路線計算靠的是座標。"
        }
        if tapped.name == nil {
            return isPickingPOI
                ? "正在看你點的位置上有沒有標示的店家或景點…"
                : "你點的位置上沒有標示的地標，會直接記下這個座標。想換一個位置就再點一次地圖，"
                    + "或按右上角的「改用準心」回到用準心對位置。"
        }
        return "已選取地圖上的這個地標，名稱與座標都用它的。想改用畫面中央的準心就按右上角的「改用準心」。"
    }

    // MARK: 選到什麼

    /// 最後會被記下來的座標（點過地圖就用那一點，否則用畫面中央的準心）
    private var pickedCoordinate: CLLocationCoordinate2D {
        tapped?.coordinate ?? center
    }

    /// 最後會被帶進景點名稱的字。
    /// 點到的地標最準（那就是 Apple 地圖上寫的店名），反查來的地標名只是退路。
    private var pickedName: String? {
        if let name = tapped?.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return name
        }
        return suggestedName
    }

    /// 反查的觸發條件。用字串而不是座標本身：座標沒有 Equatable，
    /// 而 .task(id:) 需要能比較。
    private var resolveKey: String {
        let c = pickedCoordinate
        return (tapped?.name ?? "-")
            + String(format: "|%.5f,%.5f", c.latitude, c.longitude)
    }

    // MARK: 反查地址

    /// 反查地址。
    ///
    /// 由 .task(id: resolveKey) 單一驅動：id 一變（挪了地圖、點了別的地標）
    /// SwiftUI 就會取消前一個再跑新的，所以開頭這個等待天然就是防抖——
    /// 手指還在挪的時候不會真的去打反查（CLGeocoder 有速率限制，連打會被擋）。
    @MainActor
    private func resolve(_ coordinate: CLLocationCoordinate2D) async {
        isResolving = true
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(
            loc, preferredLocale: Locale(identifier: "zh_Hant_TW")).first
        // 查的期間使用者可能又挪走了，這時候這個結果已經不是在講畫面上那個點
        guard !Task.isCancelled else { return }
        isResolving = false
        guard let placemark else {
            address = ""
            suggestedName = nil
            return
        }
        address = Self.formattedAddress(placemark)
        suggestedName = Self.landmarkName(placemark, address: address)
    }

    /// 組成台灣習慣的地址順序（郵遞區號 縣市 鄉鎮 路 號）
    private static func formattedAddress(_ p: CLPlacemark) -> String {
        [p.postalCode, p.administrativeArea, p.subAdministrativeArea,
         p.locality, p.subLocality, p.thoroughfare, p.subThoroughfare]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            // 同一段字有時會重複出現在兩個欄位（例：locality 與 subAdministrativeArea）
            .reduce(into: [String]()) { acc, s in if !acc.contains(s) { acc.append(s) } }
            .joined()
    }

    /// 大到當不了景點名稱的 areasOfInterest。
    ///
    /// 反查一個路邊的座標時，Apple 很常回「臺灣島」這種整座島等級的名字，
    /// 拿它當景點名稱只會讓使用者的行程出現一站叫「臺灣島」。
    private static let tooBroadAreas: Set<String> = [
        "臺灣島", "台灣島", "臺灣", "台灣", "Taiwan", "Taiwan Island",
        "中華民國", "本州", "九州", "四國", "北海道", "Honshu", "Kyushu", "Hokkaido"
    ]

    /// 可以拿來當景點名稱的地標名。
    ///
    /// CLPlacemark.name 在台灣常常就是門牌號碼本身（「9號」），拿它當名稱只會讓
    /// 景點叫做「9號」，所以只收 areasOfInterest（真正的地標名），
    /// 而且要跟地址不一樣、也不能是行政區或整座島那種大範圍的名字。
    ///
    /// 真正可靠的名稱來源是「使用者自己點的那個地標」（pickedName 會優先用它）；
    /// 這裡只是沒東西可點時的退路，所以寧可回 nil 也不要亂猜一個。
    private static func landmarkName(_ p: CLPlacemark, address: String) -> String? {
        guard let area = p.areasOfInterest?.first?.trimmingCharacters(in: .whitespaces),
              !area.isEmpty, !address.contains(area),
              !tooBroadAreas.contains(area) else { return nil }
        // 跟行政區同名的也不算地標（例：areasOfInterest 給「竹南鎮」）
        let adminNames = [p.country, p.administrativeArea, p.subAdministrativeArea,
                          p.locality, p.subLocality].compactMap { $0 }
        guard !adminNames.contains(area) else { return nil }
        return area
    }
}

/// [v25.627] 搜尋建議的一列（從 MapPlacePickerSheet.suggestionList 切出來，內容、字、間距都沒變）。
/// 切成 struct 是為了讓 MapPlacePickerSheet 的型別巢狀不變深（depth.py 舊帳 33）。
private struct MapPickerSuggestionLabel: View {
    let title: String
    let subtitle: String
    let meters: CLLocationDistance?
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle")
                .font(.system(size: 12)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(title)
                    .font(.subheadline).foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            PlaceDistanceBadge(meters: meters, icon: "scope")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - 選位置時的照片

/// [v25.428] 在地圖上點到一個地方之後，在地圖與資訊卡之間鋪一排照片，
/// 用來確認「我點到的是不是我想的那個地方」。
///
/// 照片有兩種來源，兩種都不是憑空生出來的：
///
///  1. **Apple 的「環視」實景影像**（Look Around）。這是 MapKit 唯一公開提供的
///     實景照片，拍的是那個座標的街景。不是每個地方都有——巷弄、山區、
///     非公開區域常常沒有，沒有就不佔位置。
///  2. **這個 App 裡自己已經有的照片**：以前在 150 公尺內記過的旅遊景點與
///     帶地點的變動支出。「我上次來拍的」比任何官方圖都更幫得上忙。
///
/// ⚠️ Apple 沒有公開「這家店的照片」這種 API——想直接拿到餐廳的美食照是做不到的。
///    所以這裡誠實地只端出拿得到的這兩種，而不是去別的地方抓圖充數。
struct MapPickerPlaceGallery: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore

    let coordinate: CLLocationCoordinate2D
    let accent: Color

    /// 這個 App 自己拍過的一張
    struct LocalShot: Identifiable {
        let id: String
        let url: URL
        let caption: String
    }

    @State private var scene: MKLookAroundScene?
    @State private var lookAroundImage: UIImage?
    @State private var isLoading = false
    @State private var showLookAround = false
    @State private var viewingPhoto: IdentifiableURL?
    /// 附近拍過的照片。放在 @State 而不是 computed：支出可能有好幾千筆，
    /// 每次重繪都掃一遍會讓拖地圖變頓。
    @State private var shots: [LocalShot] = []

    /// 查過的那一點。座標只取到小數第 5 位（約 1 公尺），
    /// 手指抖一下不該重送一次請求。
    private var key: String {
        String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    var body: some View {
        Group {
            if lookAroundImage != nil || !shots.isEmpty || isLoading {
                content
            }
        }
        .task(id: key) { await load() }
        .sheet(isPresented: $showLookAround) {
            LookAroundPreview(initialScene: scene)
                .ignoresSafeArea()
                .appStores()
        }
        // [v25.472] 這個地點的照片整組帶進去
        .sheet(item: $viewingPhoto) { wrapper in
            PhotoLightbox(urls: shots.map(\.url), current: wrapper.url)
                .appStores()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 9, weight: .bold))
                Text(captionLine)
                    .font(.system(size: 10, weight: .semibold))
                if isLoading { ProgressView().scaleEffect(0.45) }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let img = lookAroundImage {
                        Button { showLookAround = true } label: {
                            lookAroundTile(img)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(shots) { shot in
                        Button { viewingPhoto = IdentifiableURL(url: shot.url) } label: {
                            localTile(shot)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .scrollEdgeFade(width: 12)
        }
        // [v25.431] 這一塊現在住在資訊卡裡面，所以不要再自己包一層材質與陰影——
        // 材質疊材質會糊成一片，而卡片外圍的內距已經留好了
        .padding(.vertical, 2)
    }

    /// 字串在 ViewBuilder 外組好
    private var captionLine: String {
        if isLoading && lookAroundImage == nil && shots.isEmpty { return "正在找這裡的實景…" }
        var parts: [String] = []
        if lookAroundImage != nil { parts.append("實景") }
        if !shots.isEmpty { parts.append("我拍過 \(shots.count) 張") }
        return parts.isEmpty ? "這裡沒有可看的照片" : parts.joined(separator: "・")
    }

    private func lookAroundTile(_ img: UIImage) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: img)
                .resizable().scaledToFill()
                .frame(width: 128, height: 84)
                .clipped()
            HStack(spacing: 3) {
                Image(systemName: "binoculars.fill").font(.system(size: 8, weight: .bold))
                Text("環視").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2.5)
            .background(.black.opacity(0.42), in: Capsule())
            .padding(5)
        }
        .frame(width: 128, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(0.35), lineWidth: 0.75))
    }

    private func localTile(_ shot: LocalShot) -> some View {
        VStack(spacing: 3) {
            AsyncThumbnailView(url: shot.url, size: CGSize(width: 84, height: 62))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(shot.caption)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 84)
        }
    }

    // MARK: 取資料

    private func load() async {
        shots = nearbyShots()
        isLoading = true
        defer { isLoading = false }
        lookAroundImage = nil
        scene = nil
        // 沒有實景的地方會回 nil（不是錯誤），拿不到就是沒有，不用重試
        guard let s = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene else {
            return
        }
        // 中途又點了別的地方就不要把舊的縮圖蓋上去
        guard !Task.isCancelled else { return }
        scene = s
        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: 256, height: 168)
        let snapshotter = MKLookAroundSnapshotter(scene: s, options: options)
        guard let snap = try? await snapshotter.snapshot, !Task.isCancelled else { return }
        lookAroundImage = snap.image
    }

    /// 這個座標附近，App 裡已經有照片的地方。
    /// 150 公尺是「走得到、看得見」的距離——再遠就不是同一個地方了。
    private func nearbyShots() -> [LocalShot] {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let radius: CLLocationDistance = 150
        var out: [LocalShot] = []

        for plan in lifeStore.tripPlans {
            for stop in plan.stops where !stop.photoFileNames.isEmpty {
                guard let c = stop.coordinate else { continue }
                guard CLLocation(latitude: c.latitude, longitude: c.longitude)
                    .distance(from: here) <= radius else { continue }
                for n in stop.photoFileNames {
                    out.append(LocalShot(id: "trip-" + n,
                                         url: TripStop.photoURL(n),
                                         caption: stop.displayName))
                }
            }
        }
        for e in expenseStore.expenses where !e.photoFileNames.isEmpty {
            guard let la = e.placeLatitude, let lo = e.placeLongitude else { continue }
            guard CLLocation(latitude: la, longitude: lo).distance(from: here) <= radius else { continue }
            for n in e.photoFileNames {
                out.append(LocalShot(id: "expense-" + n,
                                     url: Expense.photoURL(for: n),
                                     caption: e.placeDisplayName ?? "記過的一筆"))
            }
        }
        // 太多張就只端出前面幾張——這是「確認位置」用的，不是相簿
        return Array(out.prefix(20))
    }
}

// MARK: - 表單裡的那一列

/// 表單裡「在地圖上選位置」那一列，外加座標狀態。
///
/// 抽出來的理由很單純：這一列在旅遊景點、子地點、變動支出三個地方長得一模一樣，
/// 而且以後只會更多。各自複製一份的話，哪天改了說明文字就會有兩種版本並存。
///
/// sheet 由這一列自己開，但**選到什麼交給呼叫端處理**（onPick）——
/// 每個畫面要塞進哪個欄位不一樣，硬要在這裡決定只會多一堆參數。
struct MapPlacePickerButton: View {
    /// 打開地圖時停在哪裡；nil＝用使用者目前位置
    let startCoordinate: CLLocationCoordinate2D?
    /// 目前這一筆有沒有座標（決定要不要顯示「已帶入座標／清除」那一列）
    let hasCoordinate: Bool
    var accent: Color = .accentColor
    var title: String = "在地圖上選位置"
    var subtitle: String = "搜尋找不到的地方，直接挪地圖對準就好"
    /// 選到了
    let onPick: (PickedPlace) -> Void
    /// 按「清除」；nil＝不提供清除
    var onClear: (() -> Void)?

    /// [v25.627] 這一次選位置的進度。有值＝sheet 開著；sheet 重建時從它接著來
    @State private var session: MapPickerSession? = nil
    /// 按下去到下一輪真的打開之間（連點兩下只開一張）
    @State private var opening = false

    var body: some View {
        Group {
            Button {
                open()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 13)).foregroundStyle(accent)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.subheadline).foregroundStyle(.primary)
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // [v25.627] sheet 只掛在這顆按鈕上：以前掛在 Group 上，Group 會把它套到每個子 view，
            // 有座標時（兩列）就變成兩個呈現者綁同一個開關。item 是同一個 session 物件，
            // 父畫面重繪、sheet 被重新呈現都還是同一個，不會回到打開時的位置
            .sheet(item: $session) { s in
                MapPlacePickerSheet(session: s, accent: accent) { picked in
                    onPick(picked)
                }
                .appStores()
            }

            if hasCoordinate {
                HStack {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(accent)
                    Text("已帶入座標").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let onClear {
                        Button("清除") { onClear() }
                            .font(.caption)
                    }
                }
            }
        }
    }

    /// [v25.627] 先把別的輸入框的鍵盤收掉，下一輪才開地圖（跟 v25.612／614 同一個寫法）：
    /// 父畫面收鍵盤、候選清單收起來的那次重排，在地圖出來之前就做完，
    /// 不會跟地圖自己的搜尋列搶鍵盤。
    private func open() {
        guard session == nil, !opening else { return }   // 連點兩下只開一次
        opening = true
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        let s = MapPickerSession(initialCoordinate: startCoordinate)
        DispatchQueue.main.async {
            opening = false
            session = s
        }
    }
}

// MARK: - 欄位裡的字是誰打的

/// 記住「上一次由挑地點自動帶進來的名稱與地址」，決定重選地點時要不要蓋掉。
///
/// [v25.430 起] 為什麼需要它：名稱與地址兩欄如果各用各的規則，就會出現
/// 「重選一個地方，名稱還是舊的、地址卻換成新的」——兩邊指的不是同一個地方，
/// 而畫面上完全看不出來。但一律覆蓋也不行，那會把使用者自己取的名字
///（「阿姨介紹的民宿」）弄丟。
///
/// 所以規則是一句話：**欄位是空的、或裡面還是上一次自動帶進來的那個字，就跟著換；
/// 是使用者自己打的就留著，另外問他要不要改用。**
///
/// 用 Binding 而不是 inout：各畫面的欄位來源不一樣（旅遊是 @State，
/// 記帳的名稱是「看分類決定要寫 title 還是 placeName」的計算 Binding），
/// 只有 Binding 接得住全部。
struct PlaceFieldFill: Equatable {
    private(set) var name = ""
    private(set) var address = ""
    /// 挑到的值跟欄位裡的對不上、而欄位裡那個是使用者自己打的 → 還沒被採用的那部分
    var offer = Offer()

    struct Offer: Equatable {
        var name: String?
        var address: String?
        var isEmpty: Bool { name == nil && address == nil }
    }

    /// 在地圖上挑到一個位置，或搜尋建議回填地址時呼叫。
    mutating func apply(name picked: String?, address addr: String,
                        into nameField: Binding<String>,
                        addressField: Binding<String>) {
        var pending = Offer()

        let n = (picked ?? "").trimmingCharacters(in: .whitespaces)
        if !n.isEmpty {
            let current = nameField.wrappedValue.trimmingCharacters(in: .whitespaces)
            if current.isEmpty || current == name {
                nameField.wrappedValue = n
                name = n
            } else if n != current {
                pending.name = n
            }
        }

        let a = addr.trimmingCharacters(in: .whitespaces)
        if !a.isEmpty {
            let current = addressField.wrappedValue.trimmingCharacters(in: .whitespaces)
            if current.isEmpty || current == address {
                addressField.wrappedValue = a
                address = a
            } else if a != current {
                pending.address = a
            }
        }
        offer = pending
    }

    /// 使用者主動點了搜尋建議：那就是他要的，名稱直接用，不必問。
    mutating func adopt(title: String, into nameField: Binding<String>) {
        nameField.wrappedValue = title
        name = title
        offer = Offer()
    }

    /// 把還沒採用的那部分套上去（使用者按了「改用」）
    mutating func acceptOffer(into nameField: Binding<String>,
                              addressField: Binding<String>) {
        if let n = offer.name { nameField.wrappedValue = n; name = n }
        if let a = offer.address { addressField.wrappedValue = a; address = a }
        offer = Offer()
    }

    /// 使用者自己動手改了名稱之後，那一列「要不要改用地圖上的」就沒意義了
    mutating func userEditedName(_ text: String) {
        if text.trimmingCharacters(in: .whitespaces) != name { offer.name = nil }
    }

    /// 從別的地方整組帶入（例如「住過的地方」），算是挑進來的而不是打進來的
    mutating func markFilled(name n: String, address a: String) {
        name = n
        address = a
        offer = Offer()
    }
}

/// 「地圖上叫⋯，你自己改過所以沒蓋掉」那一列。三個畫面共用。
struct PlaceOfferRow: View {
    let offer: PlaceFieldFill.Offer
    var accent: Color = .orange
    let onAccept: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 13)).foregroundStyle(accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                if let n = offer.name {
                    Text("地圖上叫「" + n + "」").font(.caption).foregroundStyle(.primary)
                }
                if let a = offer.address {
                    Text(a).font(.caption2).foregroundStyle(.primary).lineLimit(2)
                }
                Text("這幾欄你自己改過，所以沒有自動蓋掉；座標已經換成新的了。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("改用") { onAccept() }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(accent)
        }
    }
}
