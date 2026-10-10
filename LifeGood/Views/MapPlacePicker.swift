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

struct MapPlacePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 打開時要停在哪裡（這一站已有的座標、或上一站的、或使用者位置）
    let initialCoordinate: CLLocationCoordinate2D?
    /// 回傳挑到的地點（名稱、地址、座標、電話）
    let onPick: (PickedPlace) -> Void
    /// 主色。各畫面各有自己的色系（旅遊紫、飲食橘…），預設沿用旅遊的
    var accent: Color = TripDayPalette.color(0)

    @StateObject private var locationProvider = LocationProvider.shared

    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var address = ""
    @State private var suggestedName: String?
    @State private var isResolving = false
    /// 在地圖上點到的那一點。有值時就用它，不看畫面中央的準心。
    ///
    /// ⚠️ 不用 Map(selection:) 那套：MapSelection 是 iOS 18 才有的，這個 App
    ///    最低支援 iOS 17（送審時整包編不過就是卡在這裡）。改成自己接點擊：
    ///    MapReader 把畫面座標換成經緯度，再就近找一筆地標，效果一樣而且 iOS 17 可用。
    @State private var tapped: TappedPoint?
    /// 正在找手指按到的是哪個地標
    @State private var isPickingPOI = false
    /// 畫面上下大約涵蓋幾公尺（用來換算點擊的容許誤差）
    @State private var visibleMeters: Double = 1_000

    /// [v25.431] 搜尋地名／店名，選中就把地圖飛過去。
    ///
    /// 沒有它的時候，要選一個遠方的地點只能一路拖、一路縮——
    /// 規劃國外行程時尤其難用（從台灣拖到福岡）。
    @StateObject private var searchCompleter = RestaurantSearchCompleter()
    @State private var query = ""
    @State private var searchDebounce: Task<Void, Never>?
    @State private var isJumping = false
    @FocusState private var searchFocused: Bool

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

    /// 沒有任何線索時的起點：台北車站。總比落在大西洋上好。
    private static let fallbackCenter = CLLocationCoordinate2D(latitude: 25.0478,
                                                              longitude: 121.5170)

    init(initialCoordinate: CLLocationCoordinate2D?,
         accent: Color = TripDayPalette.color(0),
         onPick: @escaping (PickedPlace) -> Void) {
        self.initialCoordinate = initialCoordinate
        self.accent = accent
        self.onPick = onPick
        let start = initialCoordinate
            ?? LocationProvider.shared.lastLocation?.coordinate
            ?? Self.fallbackCenter
        _center = State(initialValue: start)
        // 已經有座標就貼近一點（在微調），沒有就拉遠一點（在找地方）
        let span = initialCoordinate == nil ? 0.05 : 0.004
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: start,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mapLayer
                infoCard
            }
            .overlay(alignment: .top) { searchOverlay }
            .navigationTitle("在地圖上選位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
            }
            .onAppear {
                locationProvider.requestIfNeeded()
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
            }
            .onDisappear { searchDebounce?.cancel() }
            // 點到別的地標、或挪動地圖之後，都要重查一次地址
            .task(id: resolveKey) { await resolve(pickedCoordinate) }
        }
    }

    private var mapLayer: some View {
        // MapReader 才拿得到「畫面上的點 → 經緯度」的換算（iOS 17 就有）
        MapReader { proxy in
            ZStack {
                Map(position: $position) {
                    UserAnnotation()
                    if let tapped {
                        Annotation(tapped.name ?? "選取的位置", coordinate: tapped.coordinate) {
                            selectedMarker
                        }
                    }
                }
                // POI 這裡要開著：使用者是靠地標認位置的，全部關掉就只剩一片空白底圖
                .mapStyle(.standard(pointsOfInterest: .all))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    center = context.region.center
                    // 記下目前看到多大範圍，決定「點下去算是點到哪個地標」的容許距離
                    visibleMeters = context.region.span.latitudeDelta * 111_000
                    // 搜尋建議以目前看到的範圍為優先：在福岡看地圖時打「7-11」
                    // 該先給福岡的，不是台北的
                    searchCompleter.setRegion(context.region)
                    // 距離也跟著重新量：地圖挪到哪，「多遠」就是從那裡算起。
                    // 移動不到 200 公尺不會重算（見 setReference）。
                    searchCompleter.setReference(
                        CLLocation(latitude: context.region.center.latitude,
                                   longitude: context.region.center.longitude))
                }
                // 拖曳與縮放是拖／捏的手勢，單點不會被地圖吃掉，所以可以直接接
                .onTapGesture { screenPoint in
                    // 點地圖就是不想再打字了，鍵盤先收起來
                    searchFocused = false
                    guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    Task { await pickPOI(at: coordinate) }
                }
                .ignoresSafeArea(edges: .bottom)

                // 已經點過地圖就不要再畫準心——兩個「我選的是這裡」會互相打架
                if tapped == nil { crosshair }
            }
        }
    }

    // MARK: 搜尋

    /// 疊在地圖上方的搜尋列。做成疊層而不是把地圖往下推：
    /// 地圖看得越大越好找，而搜尋列多數時候只是待在那裡不動。
    private var searchOverlay: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("搜尋地名、店名或地址", text: $query)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
                    .onSubmit { jumpToFirstResult() }
                if isJumping {
                    ProgressView().scaleEffect(0.6)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                        searchCompleter.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)

            if !searchCompleter.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(searchCompleter.results.prefix(6).enumerated()),
                            id: \.offset) { index, r in
                        if index > 0 {
                            Divider().padding(.leading, 12)
                        }
                        Button { jump(to: r) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle")
                                    .font(.system(size: 12)).foregroundStyle(accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    MarqueeText(r.title)
                                        .font(.subheadline).foregroundStyle(.primary)
                                    if !r.subtitle.isEmpty {
                                        Text(r.subtitle)
                                            .font(.caption2).foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                PlaceDistanceBadge(
                                    meters: searchCompleter.distance(for: r),
                                    icon: "scope")
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .contentShape(Rectangle())
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
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
            center = coordinate
            let name = item.name?.trimmingCharacters(in: .whitespaces)
            tapped = TappedPoint(coordinate: coordinate,
                                 name: (name?.isEmpty ?? true) ? nil : name,
                                 phone: item.phoneNumber)
            withAnimation(.easeInOut(duration: 0.35)) {
                position = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)))
            }
            query = ""
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
        let tolerance = min(400, max(30, visibleMeters * 0.03))
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
        }
        // [v25.472] 這個地點的照片整組帶進去
        .sheet(item: $viewingPhoto) { wrapper in
            PhotoLightbox(urls: shots.map(\.url), current: wrapper.url)
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

    @State private var showPicker = false

    var body: some View {
        Group {
            Button {
                showPicker = true
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
        .sheet(isPresented: $showPicker) {
            MapPlacePickerSheet(initialCoordinate: startCoordinate, accent: accent) { picked in
                onPick(picked)
            }
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
