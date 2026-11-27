import SwiftUI
import UIKit

// MARK: - 全螢幕手機條碼（v25.628 barcodewidget；scratchpad/radar/judge_barcodewidget.md §C3、§C4；build/barcodewidget/brief.md）
//
// 只屬於主 App target。主畫面中型、鎖定畫面的「手機條碼」點一下、控制中心〔手機條碼〕按一下 → lifegood://expense/barcode
// → WidgetLink.apply（DeepLinkRouter.swift）→ CarrierBarcodePresenter.shared.show()。
//
// • 蓋一層自己的視窗（同說一句 AIQuickVoiceSession 的做法，windowLevel .alert）：在哪一頁、開著哪一張表單都蓋得上去，
//   〔完成〕後回到原本那一頁，打到一半的字都還在。不切頁、不換 routeToken、不關設定頁。
// • 打開時螢幕調到最亮（1.0），記住原本的亮度；〔完成〕、App 要離開前景（willResignActive：回主畫面、拉控制中心）
//   還原；回前景（didBecomeActive）再調亮。狀態機是 CarrierBrightness（純計算，sim 對照）。
// • 不加 .privacySensitive()：使用者就是要給店員掃。這一頁只有「手機條碼」「/ABC1234」與條碼，沒有金額、名字。
// • 驗證碼（鑰匙圈）不碰：號碼從 EInvoiceSyncManager.carrier?.cardNo 讀、CarrierBarcodeShared.valid 驗過才畫。
//
// 型別：CarrierBrightness（主控）、CarrierBarcodePresenter（主控）、CarrierBarcodeView（G1）＋ G1 的 private 子 View

// MARK: 亮度狀態機（主控；sim_barcodewidget.py 的 Brightness 逐行對照，G1 不准改）

struct CarrierBrightness: Equatable {
    /// 調亮的目標
    static let target: Double = 1.0
    /// 調亮之前的亮度；nil＝現在沒有調亮
    private(set) var saved: Double?

    /// 打開、回前景：還沒記過才記現在的（已經調亮了不再記，免得把 1.0 當成原本的）→ 回傳要設的值
    mutating func raise(current: Double) -> Double {
        if saved == nil {
            saved = current
        }
        return Self.target
    }

    /// 〔完成〕、要離開前景：回傳要還原的值並忘掉；沒調亮過回 nil（什麼都不做）
    mutating func restore() -> Double? {
        guard let value = saved else { return nil }
        saved = nil
        return value
    }
}

// MARK: 視窗（主控）

@MainActor
final class CarrierBarcodePresenter {
    static let shared = CarrierBarcodePresenter()

    /// 冷啟動時最多等 App 到前景多久（100ms × 30，同 AIQuickVoiceSession）
    private static let activeWaitSteps = 30
    private static let stepNanoseconds: UInt64 = 100_000_000

    private var window: UIWindow?
    /// 蓋上去之前的主視窗（〔完成〕後交還 key）
    private weak var previousKey: UIWindow?
    private var brightness = CarrierBrightness()
    /// 正在等前景的那一次（hide() 清掉；連按兩次只蓋一層）
    private var token: UUID?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        // 閉包不抓 self（shared 是單例），同 AIQuickVoiceSession
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification,
                                            object: nil, queue: .main) { _ in
            Task { @MainActor in
                CarrierBarcodePresenter.shared.appWillResignActive()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { _ in
            Task { @MainActor in
                CarrierBarcodePresenter.shared.appDidBecomeActive()
            }
        })
    }

    var isShowing: Bool { window != nil }

    /// 蓋上全螢幕條碼並調亮。已經蓋著就只再調亮一次
    func show() {
        if window != nil {
            raise()
            return
        }
        let t = UUID()
        token = t
        Task { @MainActor in
            for _ in 0..<Self.activeWaitSteps {
                guard self.token == t else { return }
                if let scene = Self.activeScene(), scene.activationState == .foregroundActive {
                    self.present(in: scene)
                    return
                }
                try? await Task.sleep(nanoseconds: Self.stepNanoseconds)
            }
            // 等了 3 秒還不是前景：有場景就照樣蓋上（回前景時 appDidBecomeActive 會調亮）
            guard self.token == t, let scene = Self.activeScene() else { return }
            self.present(in: scene)
        }
    }

    /// 〔完成〕：還原亮度、收掉視窗、交還 key
    func hide() {
        token = nil
        restore()
        guard let w = window else { return }
        window = nil
        w.isHidden = true
        w.rootViewController = nil
        previousKey?.makeKey()
        previousKey = nil
    }

    private func present(in scene: UIWindowScene) {
        token = nil
        guard window == nil else {
            raise()
            return
        }
        Self.dismissKeyboard()
        previousKey = scene.keyWindow
        let root: AnyView = CarrierBarcodeView(onDone: {
            Task { @MainActor in
                CarrierBarcodePresenter.shared.hide()
            }
        }).appStores()
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .white
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert
        w.overrideUserInterfaceStyle = .light
        w.backgroundColor = .white
        w.rootViewController = host
        w.makeKeyAndVisible()
        window = w
        raise()
    }

    private func appWillResignActive() {
        guard window != nil else { return }
        restore()
    }

    private func appDidBecomeActive() {
        guard window != nil else { return }
        raise()
    }

    private func raise() {
        guard let screen = currentScreen() else { return }
        let value = brightness.raise(current: Double(screen.brightness))
        screen.brightness = CGFloat(value)
    }

    private func restore() {
        guard let value = brightness.restore(), let screen = currentScreen() else { return }
        screen.brightness = CGFloat(value)
    }

    private func currentScreen() -> UIScreen? {
        window?.windowScene?.screen ?? Self.activeScene()?.screen
    }

    /// 開著數字鍵盤時，鍵盤的視窗層級比 .alert 高、會蓋住條碼：先收起來（底下打到一半的字都還在）
    private static func dismissKeyboard() {
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

// MARK: - 畫面（G1 實作；init(onDone:) 這個簽名不准改）

struct CarrierBarcodeView: View {
    /// 〔完成〕（CarrierBarcodePresenter 收視窗、還原亮度）
    let onDone: () -> Void
    /// 號碼從 carrier?.cardNo 讀（鑰匙圈的驗證碼讀不到時 carrier 是 nil＝還沒連結）；驗證碼這裡不碰
    @EnvironmentObject private var sync: EInvoiceSyncManager

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .toolbar { doneItem }
        }
    }

    /// 畫得出來的號碼（CarrierBarcodeShared.valid 驗過、Code 39 每個字都編得了）；不行回 nil
    private var drawableText: String? {
        guard let text = CarrierBarcodeShared.valid(sync.carrier?.cardNo), Code39.canEncode(text) else {
            return nil
        }
        return text
    }

    /// 沒連結 → 還沒連結；有號碼但畫不出來 → 請重新連結；否則條碼
    @ViewBuilder
    private var content: some View {
        if sync.carrier?.cardNo == nil {
            CarrierBarcodeEmptyCard(kind: .notLinked)
        } else if let text = drawableText {
            CarrierBarcodeCodeCard(text: text)
        } else {
            CarrierBarcodeEmptyCard(kind: .bad)
        }
    }

    @ToolbarContentBuilder
    private var doneItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("完成") { onDone() }
                .fontWeight(.semibold)
                .tint(Color.black)
        }
    }
}

/// 條碼＋號碼。窄條寬依可用寬度算（留白 10 窄條、貼齊畫素、最多 4 點）；條高約寬的 1/3，橫的放不下就矮一點
private struct CarrierBarcodeCodeCard: View {
    let text: String
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            card(size: geo.size)
        }
    }

    private func layout(width: CGFloat) -> CarrierBarcodeLayout {
        let w = Double(width)
        let s = Double(scale)
        let unit = CarrierBarcodeLayout.unit(fitting: w, text: text, quiet: CarrierBarcodeLayout.fullQuiet,
                                             scale: s, maxUnit: 4)
        return CarrierBarcodeLayout.make(text: text, unit: unit, quiet: CarrierBarcodeLayout.fullQuiet, scale: s)
    }

    private func barHeight(layout: CarrierBarcodeLayout, size: CGSize) -> CGFloat {
        let byWidth: Double = layout.totalWidth / 3
        let byHeight: Double = Double(size.height) - 170
        return CGFloat(max(60, min(byWidth, byHeight)))
    }

    private func card(size: CGSize) -> some View {
        let barcode = layout(width: size.width)
        let height = barHeight(layout: barcode, size: size)
        return VStack(spacing: 16) {
            Text("手機條碼")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.6))
            CarrierBarcodeStrip(layout: barcode, fullColor: true)
                .frame(height: height)
            CarrierBarcodeNumber(text: text)
            Text("條碼下面的號碼店員也可以直接打")
                .font(.footnote)
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .frame(width: size.width, height: size.height)
    }
}

/// 條碼下面的號碼（大、黑、等寬）
private struct CarrierBarcodeNumber: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.black)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// 還沒連結／號碼畫不出來：說明＋〔去設定〕推電子發票設定頁（同一個 NavigationStack，返回後條碼就出現）
private struct CarrierBarcodeEmptyCard: View {
    enum Kind {
        case notLinked
        case bad
    }

    let kind: Kind

    private var title: String {
        switch kind {
        case .notLinked:
            return "還沒連結手機條碼"
        case .bad:
            return "這個手機條碼畫不出來，請到電子發票重新連結"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "barcode")
                .font(.system(size: 44))
                .foregroundStyle(Color.black.opacity(0.35))
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.center)
            if kind == .notLinked {
                Text("連結之後，這裡會出現給店員掃的條碼")
                    .font(.footnote)
                    .foregroundStyle(Color.black.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            NavigationLink {
                EInvoiceSetupView()
            } label: {
                CarrierBarcodeSetupLabel()
            }
        }
        .padding(.horizontal, 24)
    }
}

/// 〔去設定〕：黑底白字膠囊
private struct CarrierBarcodeSetupLabel: View {
    var body: some View {
        Text("去設定")
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black))
    }
}
