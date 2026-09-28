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
    case plane = "飛機"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .driving: return "car.fill"
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        case .plane: return "airplane"
        }
    }

    /// MapKit 的對應運輸方式。
    /// ⚠️ MKDirections 只做開車與步行。大眾運輸 Apple 不開放路線計算（只允許用
    ///    Maps App 開啟），飛機更是完全沒有——這兩種會走直線估算並在畫面上標「估」。
    ///    這裡回傳 automobile 只是為了讓型別完整，supportsRouting == false 時用不到。
    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .driving, .transit, .plane: return .automobile
        case .walking: return .walking
        }
    }

    /// 能不能問 MKDirections 拿真實路徑
    var supportsRouting: Bool {
        switch self {
        case .driving, .walking: return true
        case .transit, .plane: return false
        }
    }

    /// 直線距離換算時間用的平均時速（km/h）。路線算不出來時的退路。
    var fallbackSpeedKmh: Double {
        switch self {
        case .driving: return 35      // 市區＋郊區混合的保守值
        case .walking: return 4.5
        case .transit: return 25      // 含等車與轉乘的體感速度
        case .plane: return 700       // 巡航 800～900，含爬升下降的平均值
        }
    }

    /// 直線距離要乘的迂迴係數。真實道路幾乎不可能是直線，1.0 會嚴重低估；
    /// 但飛機幾乎就是走大圓航線，乘 1.35 反而會大幅高估。
    var straightLineFactor: Double {
        switch self {
        case .driving: return 1.35
        case .walking: return 1.25    // 人行道繞路比車道少一些
        case .transit: return 1.30
        case .plane: return 1.05      // 航線不是完全直線，但很接近
        }
    }

    /// 與距離無關的固定耗時（分鐘）。
    ///
    /// 飛機的門到門時間裡，飛行本身常常不是最久的部分：報到、安檢、登機、
    /// 下機、等行李加起來兩小時很正常。只算「距離 ÷ 時速」會嚴重低估。
    /// ⚠️ 不含「去機場的路程」——那應該自己排成一段（機場當一個景點）。
    var fixedOverheadMinutes: Int {
        switch self {
        case .plane: return 120
        case .driving, .walking, .transit: return 0
        }
    }

    /// 這個方式算出來的時間是不是一定是估的（不可能有真實路徑）
    var isAlwaysEstimated: Bool { !supportsRouting }
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
    /// 這一段（從**上一站**到這一站）要用的交通方式。nil＝用行程的預設。
    ///
    /// 放在「目的地那一站」上而不是獨立一個 leg 陣列，理由跟 legMeters／legSeconds
    /// 一樣：站一插進來或搬動，覆寫就跟著那一段走，不會對不上。
    var legModeOverride: TripTravelMode?
    /// 必去。排行程時用來標「這一站不能砍」——時間不夠要刪站時，先看沒標的那些。
    var isMustVisit: Bool
    /// 在這裡過夜。
    ///
    /// 標了之後這一站就是當天的最後一站，隔天從這裡開始：離開時間不再用停留分鐘算，
    /// 而是「抵達之後第一個到達的退房時刻」，所以下一站的交通時間是從隔天早上算的。
    var isOvernight: Bool
    /// 退房／隔天出發的時刻（只取時分，日期部分不用）。nil＝早上 9:00。
    /// 只有 isOvernight 才有意義。
    var checkOutTime: Date?
    /// 現場按「我到了」記下的實際抵達時間。
    ///
    /// 有值時時間軸就用它，不用推算的——而且**後面每一站都跟著往前／往後移**，
    /// 因為游標是從這一站的離開時間接下去的。這就是當天邊玩邊打卡的意義：
    /// 早到晚到都會即時反映到後面的行程，不用自己心算。
    var actualArrival: Date?
    /// 現場按「玩完了」記下的實際離開時間。與 actualArrival 一起就得到真正的停留時間。
    var actualDeparture: Date?
    /// 使用者指定的抵達時間。nil＝由上一站的離開時間＋交通時間推算（預設）。
    ///
    /// 有值時時間軸一律照這個時間排：餐廳訂位、船班、表演入場這種「時間是死的」
    /// 的站，推算出來的時間沒有意義。推算時間比它早就顯示成等候、比它晚就標來不及。
    var arrivalOverride: Date?
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
    /// true＝上面那個估算是「路線服務當下要不到」才退回來的（開車／步行），
    /// 不是這個交通方式本來就沒有路線可問（大眾運輸／飛機）。
    ///
    /// 這兩件事以前混在 legIsEstimated 一個旗標裡，結果是：連續查二十幾段被服務
    /// 暫時擋下 → 全部退回估算 → 指紋也一起寫下去 → 之後再也不會重試，
    /// 那些段落就永遠是估算值。分開之後，這一種下次打開行程會自動再試一次。
    var legNeedsRetry: Bool

    init(id: UUID = UUID(), name: String = "", address: String = "",
         latitude: Double? = nil, longitude: Double? = nil,
         dwellMinutes: Int = 60, legModeOverride: TripTravelMode? = nil,
         actualArrival: Date? = nil, actualDeparture: Date? = nil,
         isMustVisit: Bool = false,
         isOvernight: Bool = false, checkOutTime: Date? = nil,
         arrivalOverride: Date? = nil, note: String = "",
         photoFileNames: [String] = [], subSpots: [TripSubSpot] = [],
         legMeters: Double? = nil, legSeconds: Double? = nil,
         legStamp: String? = nil, legIsEstimated: Bool = false,
         legNeedsRetry: Bool = false) {
        self.id = id; self.name = name; self.address = address
        self.latitude = latitude; self.longitude = longitude
        self.dwellMinutes = dwellMinutes
        self.legModeOverride = legModeOverride
        self.actualArrival = actualArrival; self.actualDeparture = actualDeparture
        self.isMustVisit = isMustVisit
        self.isOvernight = isOvernight; self.checkOutTime = checkOutTime
        self.arrivalOverride = arrivalOverride
        self.note = note
        self.photoFileNames = photoFileNames; self.subSpots = subSpots
        self.legMeters = legMeters; self.legSeconds = legSeconds
        self.legStamp = legStamp; self.legIsEstimated = legIsEstimated
        self.legNeedsRetry = legNeedsRetry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        address = (try? c.decode(String.self, forKey: .address)) ?? ""
        latitude = try? c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try? c.decodeIfPresent(Double.self, forKey: .longitude)
        dwellMinutes = (try? c.decode(Int.self, forKey: .dwellMinutes)) ?? 60
        legModeOverride = try? c.decodeIfPresent(TripTravelMode.self, forKey: .legModeOverride)
        actualArrival = try? c.decodeIfPresent(Date.self, forKey: .actualArrival)
        actualDeparture = try? c.decodeIfPresent(Date.self, forKey: .actualDeparture)
        isMustVisit = (try? c.decodeIfPresent(Bool.self, forKey: .isMustVisit)) ?? false
        isOvernight = (try? c.decodeIfPresent(Bool.self, forKey: .isOvernight)) ?? false
        checkOutTime = try? c.decodeIfPresent(Date.self, forKey: .checkOutTime)
        arrivalOverride = try? c.decodeIfPresent(Date.self, forKey: .arrivalOverride)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        photoFileNames = (try? c.decodeIfPresent([String].self, forKey: .photoFileNames)) ?? []
        subSpots = (try? c.decodeIfPresent([TripSubSpot].self, forKey: .subSpots)) ?? []
        legMeters = try? c.decodeIfPresent(Double.self, forKey: .legMeters)
        legSeconds = try? c.decodeIfPresent(Double.self, forKey: .legSeconds)
        legStamp = try? c.decodeIfPresent(String.self, forKey: .legStamp)
        legIsEstimated = (try? c.decodeIfPresent(Bool.self, forKey: .legIsEstimated)) ?? false
        legNeedsRetry = (try? c.decodeIfPresent(Bool.self, forKey: .legNeedsRetry)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, address, latitude, longitude, dwellMinutes
        case legModeOverride, isMustVisit, isOvernight, checkOutTime, arrivalOverride, note
        case actualArrival, actualDeparture
        case photoFileNames, subSpots, legMeters, legSeconds, legStamp, legIsEstimated
        case legNeedsRetry
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

    /// 現場打卡走到哪一步了
    enum CheckInState {
        /// 還沒到
        case notArrived
        /// 已經到了，還在這裡
        case arrived
        /// 玩完離開了
        case departed
    }

    var checkInState: CheckInState {
        if actualDeparture != nil { return .departed }
        if actualArrival != nil { return .arrived }
        return .notArrived
    }

    /// 真正待了多久（秒）。兩個時間都打卡了才有值。
    var actualDwellSeconds: Double? {
        guard let a = actualArrival, let d = actualDeparture, d > a else { return nil }
        return d.timeIntervalSince(a)
    }

    /// 退房時刻是幾點幾分（從午夜起算的分鐘）。沒設就是早上 9:00。
    var checkOutMinutesOfDay: Int {
        guard let t = checkOutTime else { return 9 * 60 }
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        return min(24 * 60 - 5, max(0, (c.hour ?? 9) * 60 + (c.minute ?? 0)))
    }

    /// 抵達之後「第一個」遇到的退房時刻。
    ///
    /// 晚上 21:00 入住、退房 09:00 → 隔天早上 09:00。
    /// 但凌晨 01:00 才入住的話，同一天早上的 09:00 就是退房時間，不該再往後推一天。
    static func nextCheckOut(after arrival: Date, minutesOfDay: Int) -> Date {
        let cal = Calendar.current
        let out = cal.startOfDay(for: arrival)
            .addingTimeInterval(Double(minutesOfDay) * 60)
        guard out <= arrival else { return out }
        return cal.date(byAdding: .day, value: 1, to: out)
            ?? out.addingTimeInterval(24 * 3600)
    }

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

    /// 改出發時間。
    ///
    /// 換的是「哪一天」時，各站指定的抵達時間跟著平移同樣的天數、鐘點不變；
    /// 只是同一天內提早或延後出發就不動它們——餐廳訂位 18:00 不會因為你早出門
    /// 就變成 17:30，那是兩件不同的事。
    mutating func setStartDate(_ newValue: Date) {
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: startDate),
                                      to: cal.startOfDay(for: newValue)).day ?? 0
        startDate = newValue
        guard days != 0 else { return }
        for i in stops.indices {
            guard let a = stops[i].arrivalOverride else { continue }
            stops[i].arrivalOverride = cal.date(byAdding: .day, value: days, to: a)
        }
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
        /// 這一段的估算是路線服務當下要不到才退回來的，可以重算
        let canRetryRouting: Bool
        /// 這一段實際用的交通方式（第一站沒有路段，放行程預設值佔位）
        let mode: TripTravelMode
        /// 這一段是使用者針對這段另外指定的方式，不是行程預設
        let isModeOverridden: Bool
        /// 抵達時間是使用者指定的，不是推算的
        let isFixedArrival: Bool
        /// 抵達／離開是現場打卡的實際時間，不是排出來的
        let isActualArrival: Bool
        let isActualDeparture: Bool
        /// 沒有打卡的話這一站原本會排在幾點（打卡後用來比對早到還是晚到）
        let plannedArrival: Date
        /// 推算出來的抵達時間（有指定時間時才有值，用來比對來不來得及）
        let estimatedArrival: Date?
        /// 指定時間比推算的晚 → 中間的空檔（秒）
        let idleSeconds: Double
        /// 指定時間比推算的早 → 趕不上，差幾秒
        let shortfallSeconds: Double
        /// 第幾天（0＝出發當天）。跨天行程用這個分色。
        let dayIndex: Int
    }

    /// 第 index 站「進來那一段」實際用的交通方式。第 0 站沒有路段，回傳預設值。
    func effectiveMode(at index: Int) -> TripTravelMode {
        guard stops.indices.contains(index) else { return travelMode }
        return stops[index].legModeOverride ?? travelMode
    }

    /// 整條時間軸。沒有路線資料的段落交通時間算 0——寧可把它顯示成「未計算」，
    /// 也不要偷偷塞一個猜的數字進總時長裡。
    var timeline: [Slot] {
        var out: [Slot] = []
        var cursor = startDate
        let cal = Calendar.current
        let firstDay = cal.startOfDay(for: startDate)
        for (i, stop) in stops.enumerated() {
            let secs: Double? = i == 0 ? nil : stop.legSeconds
            if let s = secs { cursor = cursor.addingTimeInterval(s) }
            let estimated = cursor
            // 指定了抵達時間就照那個排，游標跟著跳過去——
            // 使用者說「我 13:00 會到」，時間軸就該長那樣，推算值只拿來比對來不來得及。
            let planned: Date
            var idle = 0.0, shortfall = 0.0
            if let fixed = stop.arrivalOverride {
                planned = fixed
                let delta = fixed.timeIntervalSince(estimated)
                if delta >= 0 { idle = delta } else { shortfall = -delta }
            } else {
                planned = estimated
            }
            // 現場打卡過的，一律以實際時間為準：它比任何推算都準，
            // 而且後面每一站都會跟著它重排（游標從這一站的離開時間接下去）。
            let arrival = stop.actualArrival ?? planned
            // 已經打卡抵達的站，「來不來得及」已成定局，不用再顯示預測的落差
            if stop.actualArrival != nil { idle = 0; shortfall = 0 }
            // 過夜的站不用停留分鐘算離開時間——沒有人會用分鐘去填一個晚上。
            // 隔天早上退房才離開，所以下一站的交通時間自然是從隔天算起。
            let departure: Date
            if let actualOut = stop.actualDeparture {
                departure = actualOut
            } else if stop.isOvernight {
                departure = TripStop.nextCheckOut(after: arrival,
                                                  minutesOfDay: stop.checkOutMinutesOfDay)
            } else {
                departure = arrival.addingTimeInterval(Double(max(0, stop.dwellMinutes)) * 60)
            }
            let day = cal.dateComponents([.day], from: firstDay,
                                         to: cal.startOfDay(for: arrival)).day ?? 0
            out.append(Slot(id: stop.id, index: i, stop: stop,
                            arrival: arrival, departure: departure,
                            travelSeconds: secs,
                            travelMeters: i == 0 ? nil : stop.legMeters,
                            isEstimated: i == 0 ? false : stop.legIsEstimated,
                            canRetryRouting: i > 0 && stop.legNeedsRetry,
                            mode: effectiveMode(at: i),
                            isModeOverridden: i > 0 && stop.legModeOverride != nil,
                            isFixedArrival: stop.arrivalOverride != nil && stop.actualArrival == nil,
                            isActualArrival: stop.actualArrival != nil,
                            isActualDeparture: stop.actualDeparture != nil,
                            plannedArrival: planned,
                            estimatedArrival: stop.arrivalOverride == nil ? nil : estimated,
                            idleSeconds: idle, shortfallSeconds: shortfall,
                            dayIndex: max(0, day)))
            cursor = departure
        }
        return out
    }

    var endDate: Date { timeline.last?.departure ?? startDate }

    /// 這份行程橫跨幾天（1＝當天來回）。跨天時時間軸會分色分段。
    var dayCount: Int {
        let tl = timeline
        // 最後一站不一定是天數最大的那一站（指定抵達時間可以把某一站排到更晚），
        // 所以取最大值而不是看最後一筆
        let byArrival = tl.map(\.dayIndex).max() ?? 0
        // 最後一站是過夜時，行程其實延到隔天早上退房才結束，那一天也要算進來
        let cal = Calendar.current
        let byEnd = cal.dateComponents([.day],
                                       from: cal.startOfDay(for: startDate),
                                       to: cal.startOfDay(for: tl.last?.departure ?? startDate)).day ?? 0
        return max(byArrival, max(0, byEnd)) + 1
    }

    /// 指定的抵達時間比推算的還早（來不及）的站數
    var unreachableCount: Int {
        timeline.filter { $0.shortfallSeconds > 60 }.count
    }

    /// 因為等固定時間而空著的總秒數。
    ///
    /// 第一站不算：它前面沒有計算過的路段，出發時間到第一站指定抵達時間之間的空檔
    /// 就是「去第一站的路上」，那不是在等，是在移動。
    var totalIdleSeconds: Double {
        timeline.dropFirst().reduce(0.0) { $0 + $1.idleSeconds }
    }

    /// 總時長（秒）＝最後一站離開 − 出發
    var totalSeconds: Double { endDate.timeIntervalSince(startDate) }
    /// 總停留（分鐘）。過夜的站不算——那一站的「停留」是一個晚上，
    /// 把它加進來只會讓這個數字失去意義。
    var totalDwellMinutes: Int {
        stops.filter { !$0.isOvernight }.reduce(0) { $0 + max(0, $1.dwellMinutes) }
    }

    /// 一種交通方式用了幾段。用具名結構而不是 tuple：Swift 的 key path 不支援 tuple 成員。
    struct ModeSegmentCount: Identifiable {
        let mode: TripTravelMode
        let count: Int
        var id: String { mode.rawValue }
    }

    /// 各種交通方式各幾段（只算有算出結果的段落）。摘要卡用來顯示混合了哪些方式。
    var modeSegmentCounts: [ModeSegmentCount] {
        var counts: [TripTravelMode: Int] = [:]
        for i in stops.indices where i > 0 {
            guard stops[i].legSeconds != nil else { continue }
            counts[effectiveMode(at: i), default: 0] += 1
        }
        return TripTravelMode.allCases.compactMap { mode in
            counts[mode].map { ModeSegmentCount(mode: mode, count: $0) }
        }
    }

    /// 有幾段是「路線服務當下要不到」才退回估算的（可以重算）
    var retryableLegCount: Int {
        stops.dropFirst().filter { $0.legNeedsRetry }.count
    }

    /// 把真實路線的結果寫進第 index 段。開地圖時順手把先前退回估算的段落修正回來。
    /// 回傳有沒有真的改到東西。
    @discardableResult
    mutating func applyRoute(meters: Double, seconds: Double, at index: Int) -> Bool {
        guard stops.indices.contains(index), index > 0 else { return false }
        let wasEstimated = stops[index].legIsEstimated
        // 差一公尺就重寫沒有意義，但只要原本是估算的就一定要換掉
        if !wasEstimated, let old = stops[index].legMeters,
           abs(old - meters) < 1, let oldS = stops[index].legSeconds,
           abs(oldS - seconds) < 1 {
            return false
        }
        stops[index].legMeters = meters
        stops[index].legSeconds = seconds
        stops[index].legIsEstimated = false
        stops[index].legNeedsRetry = false
        stops[index].legStamp = TripPlan.stamp(from: stops[index - 1], to: stops[index],
                                               mode: effectiveMode(at: index))
        return true
    }

    /// 有沒有任何一段被單獨指定過交通方式
    var hasModeOverride: Bool { stops.dropFirst().contains { $0.legModeOverride != nil } }

    /// 已經打卡離開的站數（當天進度）
    var checkedOutCount: Int { stops.filter { $0.actualDeparture != nil }.count }
    /// 目前人在哪一站（已抵達還沒離開）
    var currentStopId: UUID? {
        stops.first { $0.actualArrival != nil && $0.actualDeparture == nil }?.id
    }

    /// 標了必去的站數
    var mustVisitCount: Int { stops.filter(\.isMustVisit).count }
    /// 過夜幾晚
    var overnightCount: Int { stops.filter(\.isOvernight).count }
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
            if cur.legStamp != TripPlan.stamp(from: stops[i - 1], to: cur,
                                              mode: effectiveMode(at: i)) { n += 1 }
        }
        return n
    }

    /// 路線快取的指紋：兩端座標 + 交通方式。任一改變就代表要重算。
    ///
    /// 前面那個版本號是給「計算方式本身改了」時用的搬遷把手：改了它，
    /// 所有既有的快取都會對不上而重算一次。
    /// v2（25.410）：修掉「一次查太多段被擋下來後，估算值被永久記住」的問題，
    ///               既有行程需要重算才能拿回真實路線。
    private static let stampVersion = "v2"

    static func stamp(from: TripStop, to: TripStop, mode: TripTravelMode) -> String {
        func c(_ s: TripStop) -> String {
            guard let la = s.latitude, let lo = s.longitude else { return "-" }
            return String(format: "%.5f,%.5f", la, lo)
        }
        return stampVersion + "|" + c(from) + ">" + c(to) + "|" + mode.rawValue
    }
}

// MARK: - 路線計算

/// 算兩站之間的距離與時間。
///
/// 先用 MKDirections 問真實路線；失敗（沒網路、算不出路、或是大眾運輸——
/// Apple 不開放大眾運輸的路線計算）就退回直線距離 × 迂迴係數 ÷ 平均時速，
/// 並把結果標成「估算」讓畫面說清楚。
enum TripRouter {

    struct Leg {
        let meters: Double
        let seconds: Double
        let isEstimated: Bool
        /// 估算是「當下要不到」造成的（之後該再試），不是這個方式本來就沒有路線
        let needsRetry: Bool
    }

    /// 連續查詢之間的間隔。
    ///
    /// MKDirections 對短時間內的大量請求會直接擋（MKError.loadingThrottled）。
    /// 二十幾站的行程一次排隊打完，後面幾乎都會被擋下來退回估算——
    /// v25.399～25.409 的行程就是這樣整片變成「估」的。
    private static let pacingNanos: UInt64 = 400_000_000
    /// 被擋下來之後等久一點再試一次
    private static let retryNanos: UInt64 = 1_500_000_000

    /// 算一段。兩端都要有座標，否則回 nil（呼叫端顯示「未設座標」）。
    /// 問路線用的請求。leg() 與 routePolyline() 共用，免得兩邊的條件走鐘。
    private static func request(from a: CLLocationCoordinate2D,
                               to b: CLLocationCoordinate2D,
                               mode: TripTravelMode) -> MKDirections.Request {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        req.transportType = mode.mkTransportType
        req.requestsAlternateRoutes = false
        return req
    }

    /// 只要路線的形狀（地圖畫線用），不要距離與時間。
    ///
    /// 刻意**不**存進資料裡：一條 polyline 動輒上百個座標點，每一段各存一份會讓
    /// 行程資料膨脹好幾個數量級，還要跟著 iCloud 同步與完整備份一起搬。
    /// 打開地圖時現算、只放在畫面的記憶體裡就好。
    static func routePolyline(from: TripStop, to: TripStop,
                              mode: TripTravelMode) async -> MKPolyline? {
        await route(from: from, to: to, mode: mode)?.polyline
    }

    /// 要路線，被擋下來就等一下再試。
    ///
    /// 畫面上的地圖跟算距離時間走的是同一個服務，處境也一樣：剛開完整份行程的
    /// 路線圖、或剛補算完二十幾段，接著點開單一段落時很容易被擋。
    /// 只試一次的話，會出現「數字是真實路徑、地圖卻畫直線」這種對不起來的畫面。
    static func routeWithRetry(from: TripStop, to: TripStop, mode: TripTravelMode,
                               attempts: Int = 3) async -> MKRoute? {
        for attempt in 0..<max(1, attempts) {
            if attempt > 0 {
                // 每次等久一點：被擋下來時馬上再打通常還是被擋
                try? await Task.sleep(nanoseconds: retryNanos * UInt64(attempt))
            }
            if Task.isCancelled { return nil }
            if let route = await route(from: from, to: to, mode: mode) { return route }
        }
        return nil
    }

    static func leg(from: TripStop, to: TripStop, mode: TripTravelMode) async -> Leg? {
        guard let a = from.coordinate, let b = to.coordinate else { return nil }

        var retryable = false
        if mode.supportsRouting {
            let req = request(from: a, to: b, mode: mode)
            do {
                if let route = try await MKDirections(request: req).calculate().routes.first {
                    return Leg(meters: route.distance, seconds: route.expectedTravelTime,
                               isEstimated: false, needsRetry: false)
                }
            } catch {
                retryable = isTemporary(error)
            }
        }
        // 退路：直線 × 迂迴係數，再加上與距離無關的固定耗時（飛機的報到安檢登機）。
        //
        // needsRetry 只有在「錯誤是暫時的」時才成立（見 isTemporary）：
        // 被擋下來或沒網路會再試，真的沒路可走（開車跨海）與大眾運輸／飛機則是最終答案。
        let straight = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        let meters = straight * mode.straightLineFactor
        let seconds = meters / 1000 / mode.fallbackSpeedKmh * 3600
            + Double(mode.fixedOverheadMinutes) * 60
        return Leg(meters: meters, seconds: seconds, isEstimated: true,
                   needsRetry: retryable)
    }

    /// 這個錯誤是暫時的嗎？
    ///
    /// 被擋下來（一次查太多段）、伺服器忙、網路斷線 → 等一下再試就會好。
    /// 「找不到路線」與「找不到地點」則是真的沒有路可走——開車跨海就是這一類，
    /// 那種再試一百次也一樣，標成可重試只會每次打開行程都白打一輪網路。
    private static func isTemporary(_ error: Error) -> Bool {
        guard let mkError = error as? MKError else { return true }
        return mkError.code != .directionsNotFound && mkError.code != .placemarkNotFound
    }

    /// 要完整的路線物件（距離、時間、形狀都在裡面）。
    /// 地圖畫線與「把先前退回估算的數字修正回來」共用同一次查詢，不要各打一次。
    static func route(from: TripStop, to: TripStop, mode: TripTravelMode) async -> MKRoute? {
        guard mode.supportsRouting,
              let a = from.coordinate, let b = to.coordinate else { return nil }
        return try? await MKDirections(request: request(from: a, to: b, mode: mode))
            .calculate().routes.first
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
        /// 這一輪有沒有真的打過網路（決定要不要在下一段之前先等一下）
        var requested = false
        for i in 1..<plan.stops.count {
            let prev = plan.stops[i - 1]
            let cur = plan.stops[i]
            // 每一段各自的交通方式：使用者可以只把某一段改成步行或飛機
            let mode = plan.effectiveMode(at: i)
            let want = TripPlan.stamp(from: prev, to: cur, mode: mode)
            // 兩端都有座標才算；缺座標的段落把舊快取清掉，畫面才不會顯示對不上的數字
            guard prev.coordinate != nil, cur.coordinate != nil else {
                if plan.stops[i].legMeters != nil || plan.stops[i].legSeconds != nil {
                    plan.stops[i].legMeters = nil
                    plan.stops[i].legSeconds = nil
                    plan.stops[i].legStamp = nil
                    plan.stops[i].legIsEstimated = false
                    plan.stops[i].legNeedsRetry = false
                    changed = true
                }
                continue
            }
            // 指紋對得上就跳過——除非上次是「當下要不到」才退回估算的，那種要再試
            if cur.legStamp == want && !cur.legNeedsRetry { continue }

            // 連續請求之間隔一下。不隔的話二十幾段一次打完，後面幾乎全被擋下來。
            if requested { try? await Task.sleep(nanoseconds: pacingNanos) }
            requested = true

            var result = await leg(from: prev, to: cur, mode: mode)
            // 被擋下來時等久一點再試一次；兩次都失敗才認了（留著 needsRetry 下次再說）
            if result?.needsRetry == true {
                try? await Task.sleep(nanoseconds: retryNanos)
                if let second = await leg(from: prev, to: cur, mode: mode),
                   !second.needsRetry {
                    result = second
                }
            }
            guard let leg = result else { continue }
            plan.stops[i].legMeters = leg.meters
            plan.stops[i].legSeconds = leg.seconds
            plan.stops[i].legStamp = want
            plan.stops[i].legIsEstimated = leg.isEstimated
            plan.stops[i].legNeedsRetry = leg.needsRetry
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
