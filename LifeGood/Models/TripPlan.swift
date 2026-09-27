import Foundation
import MapKit

// MARK: - 旅遊規劃
//
// [v25.399] 旅遊地圖的「旅遊規劃」：把要去的景點排成一條時間軸，
// 自動算出站與站之間的距離與交通時間，方便中途插入新景點再看整天會變成怎樣。
//
// 與旅遊地圖既有的「地點清單」是兩回事：那個是**去過**的地方（從娛樂記帳聚合出來的），
// 這個是**要去**的地方。所以自成一份資料，不寄生在支出上。

// MARK: 交通方式

enum TripTravelMode: String, Codable, CaseIterable, Identifiable {
    case driving = "開車"
    case walking = "步行"
    case transit = "大眾運輸"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .driving: return "car.fill"
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        }
    }

    /// MapKit 的對應運輸方式。
    /// ⚠️ MKDirections 不提供大眾運輸的路線計算（Apple 只開放用 Maps App 開啟），
    ///    所以 transit 會退回 automobile 當近似值，並在畫面上標明是估算。
    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .driving, .transit: return .automobile
        case .walking: return .walking
        }
    }

    var supportsRouting: Bool { self != .transit }

    /// 直線距離換算時間用的平均時速（km/h）。路線算不出來時的退路。
    var fallbackSpeedKmh: Double {
        switch self {
        case .driving: return 35      // 市區＋郊區混合的保守值
        case .walking: return 4.5
        case .transit: return 25      // 含等車與轉乘的體感速度
        }
    }
}

// MARK: 子地點

/// 一個景點底下的細項（例：故宮裡的某個展廳、老街上的某幾攤）。
/// 刻意不給它自己的座標——它就在母景點那裡，給座標只會讓路線計算變得沒完沒了。
struct TripSubSpot: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var note: String
    /// 想在這個細項待多久（分鐘）。0＝沒特別安排。
    /// 母景點的停留時間若小於子地點加總，畫面會提醒對不上。
    var minutes: Int

    init(id: UUID = UUID(), name: String = "", note: String = "", minutes: Int = 0) {
        self.id = id; self.name = name; self.note = note; self.minutes = minutes
    }
}

// MARK: 景點

struct TripStop: Identifiable, Codable {
    let id: UUID
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    /// 預計停留時間（分鐘）
    var dwellMinutes: Int
    var note: String
    var photoFileNames: [String]
    var subSpots: [TripSubSpot]

    /// 從**上一站**到這一站的路線快取。
    ///
    /// 存起來的理由：MKDirections 要連網、有速率限制，而時間軸每次重繪都要用到這兩個數字。
    /// 算過就存進來，離線也看得到；站的順序或座標一變就作廢（見 routeStamp）。
    var legMeters: Double?
    var legSeconds: Double?
    /// 算這段路線時的「來源條件指紋」。與現況不符就代表快取過期。
    var legStamp: String?
    /// true＝這段是用直線距離估的（路線服務失敗或大眾運輸），畫面要標示
    var legIsEstimated: Bool

    init(id: UUID = UUID(), name: String = "", address: String = "",
         latitude: Double? = nil, longitude: Double? = nil,
         dwellMinutes: Int = 60, note: String = "",
         photoFileNames: [String] = [], subSpots: [TripSubSpot] = [],
         legMeters: Double? = nil, legSeconds: Double? = nil,
         legStamp: String? = nil, legIsEstimated: Bool = false) {
        self.id = id; self.name = name; self.address = address
        self.latitude = latitude; self.longitude = longitude
        self.dwellMinutes = dwellMinutes; self.note = note
        self.photoFileNames = photoFileNames; self.subSpots = subSpots
        self.legMeters = legMeters; self.legSeconds = legSeconds
        self.legStamp = legStamp; self.legIsEstimated = legIsEstimated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        address = (try? c.decode(String.self, forKey: .address)) ?? ""
        latitude = try? c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try? c.decodeIfPresent(Double.self, forKey: .longitude)
        dwellMinutes = (try? c.decode(Int.self, forKey: .dwellMinutes)) ?? 60
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        photoFileNames = (try? c.decodeIfPresent([String].self, forKey: .photoFileNames)) ?? []
        subSpots = (try? c.decodeIfPresent([TripSubSpot].self, forKey: .subSpots)) ?? []
        legMeters = try? c.decodeIfPresent(Double.self, forKey: .legMeters)
        legSeconds = try? c.decodeIfPresent(Double.self, forKey: .legSeconds)
        legStamp = try? c.decodeIfPresent(String.self, forKey: .legStamp)
        legIsEstimated = (try? c.decodeIfPresent(Bool.self, forKey: .legIsEstimated)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, address, latitude, longitude, dwellMinutes, note
        case photoFileNames, subSpots, legMeters, legSeconds, legStamp, legIsEstimated
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "未命名景點" : n
    }

    /// 子地點的分鐘加總。母景點停留時間比這個短時畫面會提醒。
    var subSpotMinutes: Int { subSpots.reduce(0) { $0 + max(0, $1.minutes) } }

    // MARK: 照片

    static var photosDirectory: URL {
        let dir = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("TripStopPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func photoURL(_ fileName: String) -> URL {
        photosDirectory.appendingPathComponent(fileName)
    }

    /// 存一張照片並回傳檔名。多張照片共用同一個 stop id，所以檔名要再加一段隨機，
    /// 不能只用 id——否則第二張會蓋掉第一張。
    static func savePhoto(_ data: Data) -> String? {
        let data = ImageCompressor.compressForStorage(data)
        let name = "\(UUID().uuidString).jpg"
        guard (try? data.write(to: photoURL(name))) != nil else { return nil }
        PhotoCloudSync.upload(directory: "TripStopPhotos", fileName: name)
        return name
    }

    static func deletePhoto(_ fileName: String) {
        try? FileManager.default.removeItem(at: photoURL(fileName))
        PhotoCloudSync.delete(directory: "TripStopPhotos", fileName: fileName)
    }
}

// MARK: 行程

struct TripPlan: Identifiable, Codable {
    let id: UUID
    var title: String
    /// 出發時間（含時分）。時間軸從這裡開始往後推。
    var startDate: Date
    var travelMode: TripTravelMode
    var note: String
    var stops: [TripStop]

    init(id: UUID = UUID(), title: String = "", startDate: Date = Date(),
         travelMode: TripTravelMode = .driving, note: String = "",
         stops: [TripStop] = []) {
        self.id = id; self.title = title; self.startDate = startDate
        self.travelMode = travelMode; self.note = note; self.stops = stops
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        startDate = (try? c.decode(Date.self, forKey: .startDate)) ?? Date()
        travelMode = (try? c.decode(TripTravelMode.self, forKey: .travelMode)) ?? .driving
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        stops = (try? c.decodeIfPresent([TripStop].self, forKey: .stops)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, startDate, travelMode, note, stops
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { return t }
        if let first = stops.first { return first.displayName + (stops.count > 1 ? " 等 \(stops.count) 站" : "") }
        return "未命名行程"
    }

    // MARK: 時間軸
    //
    // 抵達 = 上一站的離開時間 + 這一段的交通時間；離開 = 抵達 + 停留時間。
    // 第一站沒有交通時間，直接從出發時間開始。

    struct Slot: Identifiable {
        let id: UUID
        let index: Int
        let stop: TripStop
        let arrival: Date
        let departure: Date
        /// 從上一站過來的交通時間／距離（第一站為 nil）
        let travelSeconds: Double?
        let travelMeters: Double?
        let isEstimated: Bool
    }

    /// 整條時間軸。沒有路線資料的段落交通時間算 0——寧可把它顯示成「未計算」，
    /// 也不要偷偷塞一個猜的數字進總時長裡。
    var timeline: [Slot] {
        var out: [Slot] = []
        var cursor = startDate
        for (i, stop) in stops.enumerated() {
            let secs: Double? = i == 0 ? nil : stop.legSeconds
            if let s = secs { cursor = cursor.addingTimeInterval(s) }
            let arrival = cursor
            let departure = arrival.addingTimeInterval(Double(max(0, stop.dwellMinutes)) * 60)
            out.append(Slot(id: stop.id, index: i, stop: stop,
                            arrival: arrival, departure: departure,
                            travelSeconds: secs,
                            travelMeters: i == 0 ? nil : stop.legMeters,
                            isEstimated: i == 0 ? false : stop.legIsEstimated))
            cursor = departure
        }
        return out
    }

    var endDate: Date { timeline.last?.departure ?? startDate }

    /// 總時長（秒）＝最後一站離開 − 出發
    var totalSeconds: Double { endDate.timeIntervalSince(startDate) }
    /// 總停留（分鐘）
    var totalDwellMinutes: Int { stops.reduce(0) { $0 + max(0, $1.dwellMinutes) } }
    /// 總交通時間（秒）；未計算的段落不計入
    var totalTravelSeconds: Double {
        stops.dropFirst().reduce(0.0) { $0 + ($1.legSeconds ?? 0) }
    }
    /// 總距離（公尺）；未計算的段落不計入
    var totalMeters: Double {
        stops.dropFirst().reduce(0.0) { $0 + ($1.legMeters ?? 0) }
    }
    /// 有幾段還沒算出路線（有座標卻沒快取）
    var unroutedLegCount: Int {
        var n = 0
        for i in 1..<max(1, stops.count) {
            let cur = stops[i]
            guard stops[i - 1].coordinate != nil, cur.coordinate != nil else { continue }
            if cur.legStamp != TripPlan.stamp(from: stops[i - 1], to: cur, mode: travelMode) { n += 1 }
        }
        return n
    }

    /// 路線快取的指紋：兩端座標 + 交通方式。任一改變就代表要重算。
    static func stamp(from: TripStop, to: TripStop, mode: TripTravelMode) -> String {
        func c(_ s: TripStop) -> String {
            guard let la = s.latitude, let lo = s.longitude else { return "-" }
            return String(format: "%.5f,%.5f", la, lo)
        }
        return c(from) + ">" + c(to) + "|" + mode.rawValue
    }
}

// MARK: - 路線計算

/// 算兩站之間的距離與時間。
///
/// 先用 MKDirections 問真實路線；失敗（沒網路、算不出路、或是大眾運輸——
/// Apple 不開放大眾運輸的路線計算）就退回直線距離 × 迂迴係數 ÷ 平均時速，
/// 並把結果標成「估算」讓畫面說清楚。
enum TripRouter {

    /// 直線距離要乘的迂迴係數。真實道路幾乎不可能是直線，1.0 會嚴重低估。
    static let detourFactor = 1.35

    struct Leg {
        let meters: Double
        let seconds: Double
        let isEstimated: Bool
    }

    /// 算一段。兩端都要有座標，否則回 nil（呼叫端顯示「未設座標」）。
    static func leg(from: TripStop, to: TripStop, mode: TripTravelMode) async -> Leg? {
        guard let a = from.coordinate, let b = to.coordinate else { return nil }

        if mode.supportsRouting {
            let req = MKDirections.Request()
            req.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
            req.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
            req.transportType = mode.mkTransportType
            req.requestsAlternateRoutes = false
            if let route = try? await MKDirections(request: req).calculate().routes.first {
                return Leg(meters: route.distance, seconds: route.expectedTravelTime,
                           isEstimated: false)
            }
        }
        // 退路：直線 × 迂迴係數
        let straight = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        let meters = straight * detourFactor
        let seconds = meters / 1000 / mode.fallbackSpeedKmh * 3600
        return Leg(meters: meters, seconds: seconds, isEstimated: true)
    }

    /// 把整份行程缺的段落補算齊。
    ///
    /// 只算「指紋對不上」的段落，所以插入一站只會重算它前後兩段，不是整條重打。
    /// 逐段循序做而不是一次全部並行：MKDirections 有速率限制，並行打十幾個
    /// 很容易整批被擋掉，變成全部退回估算值。
    ///
    /// - Returns: 有沒有任何段落被更新（呼叫端用來決定要不要寫回 store）
    static func fillMissingLegs(_ plan: inout TripPlan) async -> Bool {
        guard plan.stops.count >= 2 else { return false }
        var changed = false
        for i in 1..<plan.stops.count {
            let prev = plan.stops[i - 1]
            let cur = plan.stops[i]
            let want = TripPlan.stamp(from: prev, to: cur, mode: plan.travelMode)
            // 兩端都有座標才算；缺座標的段落把舊快取清掉，畫面才不會顯示對不上的數字
            guard prev.coordinate != nil, cur.coordinate != nil else {
                if plan.stops[i].legMeters != nil || plan.stops[i].legSeconds != nil {
                    plan.stops[i].legMeters = nil
                    plan.stops[i].legSeconds = nil
                    plan.stops[i].legStamp = nil
                    plan.stops[i].legIsEstimated = false
                    changed = true
                }
                continue
            }
            if cur.legStamp == want { continue }
            guard let leg = await leg(from: prev, to: cur, mode: plan.travelMode) else { continue }
            plan.stops[i].legMeters = leg.meters
            plan.stops[i].legSeconds = leg.seconds
            plan.stops[i].legStamp = want
            plan.stops[i].legIsEstimated = leg.isEstimated
            changed = true
        }
        return changed
    }

    // MARK: 顯示格式

    static func distanceText(_ meters: Double) -> String {
        meters < 1000
            ? String(format: "%.0f m", meters)
            : String(format: "%.1f km", meters / 1000)
    }

    static func durationText(_ seconds: Double) -> String {
        let mins = Int((seconds / 60).rounded())
        if mins < 60 { return "\(mins) 分" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h) 小時" : "\(h) 小時 \(m) 分"
    }
}
