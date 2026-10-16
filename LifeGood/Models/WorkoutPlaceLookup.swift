import Foundation
import CoreLocation
import Combine

// MARK: - 跑完反查地點（v25.555，健康 v5；health/judge.md §4.3「地點」、build/v5/brief.md §2）
//
// 跑完存好那一趟之後，用起點反查一次地名（CLGeocoder，iOS 18 可用；iOS 26 才有的 MKReverseGeocodingRequest 不用），
// 例「大佳河濱公園」，寫進那一趟的 place（成果頁 ⑨ 資料「地點」、剛跑完那一條「地點 大佳河濱公園 ✎」）。
// • 存檔時就寫進資料（不是只有畫面上的字）：跟 iCloud 同步、進備份、編輯表單的「地點」看得到。
// • 要網路；查不到（離線、海上、只回門牌號碼、整座島那種大範圍）就不寫，使用者可以自己填。
// • 只查一次、只寫空的：已經有地點（自己填了、別台裝置同步過來）就不動。
// • 寫 store 一律在 await 之後、拿 store 裡最新的那一筆再改（中間可能被改名、同步、寫進 Apple 健康、刪掉）。
// • 分享圖不放地點（judge §5.3、待決定 9）。

@MainActor
final class WorkoutPlaceLookup: ObservableObject {
    static let shared = WorkoutPlaceLookup()

    /// 正在查的那幾趟（剛跑完那一條寫「地點 查詢中…」）
    @Published private(set) var looking: Set<UUID> = []
    /// 查過、沒查到的那幾趟（剛跑完那一條寫「地點 ＋新增」）；App 關掉就忘了
    @Published private(set) var missed: Set<UUID> = []

    private init() {}

    /// 存好一趟之後呼叫（跑步畫面按住結束、救回中途存檔）；store 已經寫好那一趟。
    /// 已經有地點、沒有路線起點、座標壞掉、正在查，都直接返回
    func fill(_ session: WorkoutSession, store: LifeStore) {
        let id = session.id
        guard session.place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !looking.contains(id),
              let p = WorkoutFacts.startPoint(session),
              p.lat.isFinite, p.lon.isFinite, abs(p.lat) <= 90, abs(p.lon) <= 180 else { return }
        looking.insert(id)
        missed.remove(id)
        let location = CLLocation(latitude: p.lat, longitude: p.lon)
        Task { @MainActor in
            let name = await WorkoutPlaceName.lookup(location)
            self.looking.remove(id)
            guard let name else {
                self.missed.insert(id)
                return
            }
            // 拿 store 裡最新的那一筆（中間可能被改名、寫進 Apple 健康）；被刪了、已經有地點就不寫
            guard var latest = store.workouts.first(where: { $0.id == id }),
                  latest.place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            latest.place = name
            store.upsertWorkout(latest)
        }
    }

    /// 自己填了地點（剛跑完那一條 ✎）：不再寫「查詢中…」「＋新增」（還在查的那一次回來時看到已經有地點，不會蓋掉）
    func forget(_ id: UUID) {
        looking.remove(id)
        missed.remove(id)
    }
}

/// [v25.555] 反查地名（純函式＋一次 CLGeocoder；不屬於任何 actor，WorkoutPlaceLookup 在 await 之後才回主執行緒寫 store）
enum WorkoutPlaceName {

    /// 反查一次；查不到回 nil（不丟錯：畫面只差「地點」那一格是空的）
    static func lookup(_ location: CLLocation) async -> String? {
        let marks = try? await CLGeocoder().reverseGeocodeLocation(
            location, preferredLocale: Locale(identifier: "zh_Hant_TW"))
        guard let mark = marks?.first else { return nil }
        return name(of: mark)
    }

    /// 大到當不了地點的名字（同 MapPlacePicker：反查路邊的座標，Apple 很常回整座島）
    static let tooBroad: Set<String> = [
        "臺灣島", "台灣島", "臺灣", "台灣", "Taiwan", "Taiwan Island", "中華民國",
        "本州", "九州", "四國", "北海道", "Honshu", "Kyushu", "Hokkaido"
    ]

    /// 地名：先拿地標（areasOfInterest，例「大佳河濱公園」；不能是行政區、整座島），
    /// 沒有就拿行政區（locality「中山區」，再沒有 subAdministrativeArea）；門牌號碼（CLPlacemark.name 常常就是「9號」）不用。都沒有 nil
    static func name(of p: CLPlacemark) -> String? {
        let admin = [p.country, p.administrativeArea, p.subAdministrativeArea, p.locality, p.subLocality]
            .compactMap { $0 }
        if let area = p.areasOfInterest?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !area.isEmpty, !tooBroad.contains(area), !admin.contains(area) {
            return area
        }
        for raw in [p.locality, p.subAdministrativeArea] {
            if let v = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty, !tooBroad.contains(v) {
                return v
            }
        }
        return nil
    }
}
