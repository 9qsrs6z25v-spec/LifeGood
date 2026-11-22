import SwiftUI
import UIKit
import MapKit
import os

// MARK: - 「在地圖上選位置」的呈現（v25.633）
//
// 使用者回報（25.627 之後）：「地圖畫面中點了上面輸入搜尋欄位，畫面閃一下又回到原地」。
// 地圖原本由表單那一列（MapPlacePickerButton）用 .sheet 開；底下的記帳表單一重排、重繪、
// 回收那一列，SwiftUI 那一側就可能把地圖收掉又重新呈現，焦點跟著丟掉。
// 這一版改成自己蓋一層透明視窗、從那裡用 UIKit 的 pageSheet 往上滑
//（同 CarrierBarcodePresenter、AIQuickVoiceSession 的視窗寫法），底下的表單怎麼動都碰不到它。
//
//   MapPickerPresentation ── 純狀態機（idle／opening／showing／closing＋每一次的 id），
//                            sim_mappicker2.py 的 Presentation 逐行對照
//   MapPickerLog          ── 診斷 log（.debug，接 Mac 的 Console.app 才看得到；不記座標、不記搜尋字）
//   MapPickerPresenter    ── 視窗與 pageSheet（G1）

// MARK: - 狀態機（主控）

/// [v25.633] 呈現的狀態機（純計算，sim_mappicker2.py 的 Presentation 逐行對照）。
/// 一次只開一張；每一次開都有自己的 id，晚到的關閉、晚到的「已經收掉」只認自己那一次。
struct MapPickerPresentation: Equatable {
    enum Phase: Equatable {
        case idle
        /// 按下去了，視窗還在建、sheet 還沒開始滑
        case opening(UUID)
        /// sheet 開著（含往上滑的動畫）
        case showing(UUID)
        /// 按了〔取消〕／〔使用這個位置〕，sheet 正在往下收
        case closing(UUID)
    }

    private(set) var phase: Phase = .idle

    /// 視窗建好後等 sheet 出來最多等幾秒；超過還沒出來，下次按就當成開不成、先收掉
    static let openTimeout: TimeInterval = 2

    var isIdle: Bool { phase == .idle }

    /// 現在這一次的 id；閒著是 nil
    var currentID: UUID? {
        switch phase {
        case .idle: return nil
        case .opening(let id), .showing(let id), .closing(let id): return id
        }
    }

    /// 按下〔在地圖上選位置〕：只有閒著才開，回傳這一次的 id（連點兩下只開一張）
    mutating func requestOpen(_ id: UUID = UUID()) -> UUID? {
        guard phase == .idle else { return nil }
        phase = .opening(id)
        return id
    }

    /// 視窗建好、sheet 開始往上滑
    mutating func didPresent(_ id: UUID) -> Bool {
        guard phase == .opening(id) else { return false }
        phase = .showing(id)
        return true
    }

    /// 〔取消〕／〔使用這個位置〕：開著的那一次才收
    mutating func requestClose(_ id: UUID) -> Bool {
        guard phase == .showing(id) else { return false }
        phase = .closing(id)
        return true
    }

    /// 收掉了（按鈕收完、往下拉、開不成、保險回收）：回 true＝要拆視窗。只認自己那一次
    mutating func didDismiss(_ id: UUID) -> Bool {
        guard currentID == id else { return false }
        phase = .idle
        return true
    }

    /// 下次要開之前：上一次是不是已經卡住了（該當成收掉）。
    /// windowAlive＝透明視窗還在；sheetPresented＝視窗上還呈現著東西；
    /// sinceWindow＝視窗建好到現在幾秒（還沒建是 nil）。
    /// - opening：視窗在、上面什麼都沒有、而且等超過 openTimeout 秒 → 卡住了
    ///   （剛建好、sheet 還沒開始滑的那一瞬間不算，免得把正在開的那張收掉）
    /// - showing／closing：上面什麼都沒有 → 已經不在了（漏接了「收掉了」）
    func needsReclaim(windowAlive: Bool, sheetPresented: Bool,
                      sinceWindow: TimeInterval?) -> Bool {
        switch phase {
        case .idle:
            return false
        case .opening:
            guard windowAlive, !sheetPresented, let t = sinceWindow else { return false }
            return t >= Self.openTimeout
        case .showing, .closing:
            return !sheetPresented
        }
    }
}

// MARK: - 診斷 log（主控）

/// [v25.633] 實機分辨「焦點被自己收掉」還是「畫面被重建」用。等級 .debug：
/// 不會存到手機上，只有接 Mac 開 Console.app（勾「包含除錯訊息」、過濾 MapPicker）才看得到。
/// **不准把座標、搜尋字、地名、地址傳進來**：只記事件名稱、次數、畫面上的 pt。
enum MapPickerLog {
    private static let logger = Logger(subsystem: "LifeGood", category: "MapPicker")

    static func note(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}

// MARK: - 視窗與 pageSheet（G1 實作；present(startCoordinate:accent:onPick:) 這個簽名不准改）

/// [v25.633] 「在地圖上選位置」不再由表單那一列的 .sheet 開（25.627 之後使用者回報「點搜尋列畫面閃一下又回到原地」）。
/// 自己蓋一層透明視窗、從那裡用 UIKit 的 pageSheet 往上滑（同 CarrierBarcodePresenter、AIQuickVoiceSession 的視窗寫法）。
/// 底下的記帳表單怎麼重排、重繪、回收那一列，都收不掉也重建不了這張地圖；只有〔取消〕、〔使用這個位置〕、往下拉會收。
///
/// 視窗層級是 .normal + 1（不用 .alert）：手機條碼、說一句（.alert）照樣蓋得上來；
/// 系統的定位權限對話框在系統自己的視窗，也在最上面。
@MainActor
final class MapPickerPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    static let shared = MapPickerPresenter()

    private var state = MapPickerPresentation()
    private var window: UIWindow?
    /// 蓋上去之前的 key window（收掉後交還，表單的欄位才打得了字）
    private weak var previousKey: UIWindow?
    private var host: UIViewController?
    /// 這一次的進度（以前放在按鈕的 @State；現在跟著視窗走）
    private var session: MapPickerSession?
    /// 視窗建好的時刻（reclaimIfStale 判斷「卡在 opening」用）
    private var windowShownAt: Date?

    private override init() {
        super.init()
    }

    /// 按下〔在地圖上選位置〕。先把表單的鍵盤收掉，下一輪才開（同 25.627 的 open()）
    func present(startCoordinate: CLLocationCoordinate2D?, accent: Color,
                 onPick: @escaping (PickedPlace) -> Void) {
        reclaimIfStale()
        guard let id = state.requestOpen() else {
            MapPickerLog.note("requestOpen 擋下（已經開著）")
            return
        }
        MapPickerLog.note("requestOpen")
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        Task { @MainActor in
            MapPickerPresenter.shared.show(id, startCoordinate, accent, onPick)
        }
    }

    private func show(_ id: UUID, _ start: CLLocationCoordinate2D?, _ accent: Color,
                      _ onPick: @escaping (PickedPlace) -> Void) {
        guard let scene = Self.activeScene() else {
            _ = state.didDismiss(id)
            MapPickerLog.note("開不成：沒有 scene")
            return
        }
        let s = MapPickerSession(initialCoordinate: start)
        let sheet = MapPlacePickerSheet(session: s, accent: accent, onPick: onPick,
                                        onClose: { Task { @MainActor in MapPickerPresenter.shared.close(id) } })
        let h = UIHostingController(rootView: sheet.appStores())
        h.modalPresentationStyle = .pageSheet
        h.presentationController?.delegate = self
        let root = MapPickerRootController()
        let w = MapPickerWindow(windowScene: scene)
        w.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        w.backgroundColor = .clear
        w.rootViewController = root
        previousKey = scene.keyWindow
        session = s
        host = h
        window = w
        windowShownAt = Date()
        root.onFirstAppear = { [weak root] in
            guard let root else { return }
            MapPickerPresenter.shared.rootDidAppear(id, root: root)
        }
        w.makeKeyAndVisible()
    }

    /// 透明底出現了：sheet 往上滑
    private func rootDidAppear(_ id: UUID, root: UIViewController) {
        guard state.didPresent(id), let h = host else { return }
        MapPickerLog.note("present")
        root.present(h, animated: true)
    }

    /// 〔取消〕／〔使用這個位置〕
    func close(_ id: UUID) {
        guard state.requestClose(id), let h = host else {
            MapPickerLog.note("close 擋下")
            return
        }
        MapPickerLog.note("close（按鈕）")
        h.dismiss(animated: true) {
            Task { @MainActor in MapPickerPresenter.shared.teardown(id) }
        }
    }

    /// 往下拉收掉（程式自己 dismiss 不會叫這個）
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let id = state.currentID else { return }
        MapPickerLog.note("didDismiss（往下拉）")
        teardown(id)
    }

    private func teardown(_ id: UUID) {
        guard state.didDismiss(id) else { return }
        MapPickerLog.note("teardown")
        let w = window
        window = nil
        host = nil
        session = nil
        windowShownAt = nil
        w?.isHidden = true
        w?.rootViewController = nil
        let back = previousKey
            ?? Self.activeScene()?.windows.first(where: { !($0 is MapPickerWindow) && !$0.isHidden })
        back?.makeKey()
        previousKey = nil
    }

    /// 保險：上一次卡住了（漏接「收掉了」、或 sheet 一直沒出來）就當成收掉，免得一層透明視窗留在最上面、之後再也開不了
    private func reclaimIfStale() {
        let presented = window?.rootViewController?.presentedViewController != nil
        let since = windowShownAt.map { Date().timeIntervalSince($0) }
        guard state.needsReclaim(windowAlive: window != nil, sheetPresented: presented,
                                 sinceWindow: since),
              let id = state.currentID else { return }
        MapPickerLog.note("reclaimIfStale")
        teardown(id)
    }

    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

/// 透明底：只負責把地圖 sheet 呈現出來
private final class MapPickerRootController: UIViewController {
    var onFirstAppear: (@MainActor () -> Void)?

    override func loadView() {
        let v = UIView()
        v.backgroundColor = .clear
        view = v
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let f = onFirstAppear
        onFirstAppear = nil
        f?()
    }
}

/// 點到透明底本身就穿過去（sheet 還沒滑上來、或萬一卡住時，不會擋住底下的 App）
private final class MapPickerWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        return v === rootViewController?.view ? nil : v
    }
}
