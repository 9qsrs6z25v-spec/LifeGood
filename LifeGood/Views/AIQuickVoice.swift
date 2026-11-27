import SwiftUI
import UIKit

// MARK: - 說一句（小工具 v3）：按一下開始、講完自動停，在哪一頁都能聽
//
// 只屬於「LifeGood」target。由 G1 實作，規格見 scratchpad/widgets/v3/brief.md 的 G1-3。
//
// 控制項「說一句」、記帳台「🎤 說一句」打開 lifegood://add/expense?voice=1&src=widget →
// WidgetLink.apply → DeepLinkRouter.requestVoice() → MainTabView 取走 → AIQuickVoiceSession.shared.begin()。
// 畫面放在自己的 UIWindow（蓋在所有頁面與 sheet 上面）：「請說：午餐 180 刷玉山卡」、即時字、「好了」「取消」；
// 停頓約 1.5 秒或最長 15 秒自動停 → AIExpenseCommitter 解析、存檔 → 跳 App 原本那張提示「已記一筆：午餐」。
// 浮動麥克風的按住講、放開停完全不動（它有自己的 SpeechRecognizer）。
//
// 型別：AIQuickVoiceSession、AIQuickVoiceAutoStop、AIQuickVoicePanel、AIToastCard；檔內小零件 private。
//
// 狀態（AIQuickVoiceSession.Phase）：
//   idle ─begin()→ starting（等前景、訂閱、AI 金鑰、權限、開麥克風）─成功→ listening ─自動停／「好了」→ working（AI 解析＋存檔）
//   starting／listening ─「取消」、App 進背景→ idle
//   任何一步不能用（沒訂閱、沒設定 AI、沒權限、錄音失敗、沒聽到內容）、working 做完 → finished(提示) ─3.5 秒→ idle
// 每一步都帶 token：權限對話框、AI 呼叫都是 await，中間使用者可能按了取消（token 換掉就什麼都不做）。

// MARK: - 自動停的判斷（純邏輯）

/// 說一句什麼時候算講完：字停住 1.5 秒、一個字都沒聽到 8 秒、最長 15 秒
struct AIQuickVoiceAutoStop {
    /// 字停住這麼久＝講完了
    static let silenceSeconds: TimeInterval = 1.5
    /// 最長
    static let maxSeconds: TimeInterval = 15
    /// 一個字都沒聽到（主控定案 3：按了沒講話不用乾等 15 秒）
    static let noSpeechSeconds: TimeInterval = 8
    /// 兩次檢查隔超過這麼久＝主執行緒剛被別的工作卡住（冷啟動時寫快照、同步、排提醒都在主執行緒）。
    /// 辨識器送來的字是排在主執行緒上的 Task，卡住那段時間講的字可能還排在後面沒送到——
    /// 這一次不能當成「字停住了」，等下一次檢查（字已經送到）再判斷，不然會把講到一半的人切掉
    static let stallSeconds: TimeInterval = 0.75

    let startedAt: Date
    private(set) var lastText: String
    private(set) var lastChangeAt: Date
    /// 上一次 observe 的時間
    private(set) var lastObservedAt: Date
    /// 這一次 observe 跟上一次隔太久（見 stallSeconds）
    private(set) var justStalled: Bool

    init(startedAt: Date) {
        self.startedAt = startedAt
        self.lastText = ""
        self.lastChangeAt = startedAt
        self.lastObservedAt = startedAt
        self.justStalled = false
    }

    /// 辨識出來的字（去頭尾空白）跟上次不一樣 → 記下這次的字與時間
    mutating func observe(_ text: String, at now: Date) {
        justStalled = now.timeIntervalSince(lastObservedAt) > Self.stallSeconds
        lastObservedAt = now
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastText else { return }
        lastText = trimmed
        lastChangeAt = now
    }

    /// 超過最長 → 停；剛卡住 → 這次先不停；還沒有字 → 等滿 noSpeechSeconds；有字 → 字停住 silenceSeconds 就停
    func shouldStop(at now: Date) -> Bool {
        let elapsed: TimeInterval = now.timeIntervalSince(startedAt)
        if elapsed >= Self.maxSeconds { return true }
        if justStalled { return false }
        if lastText.isEmpty { return elapsed >= Self.noSpeechSeconds }
        return now.timeIntervalSince(lastChangeAt) >= Self.silenceSeconds
    }
}

// MARK: - 說一句的流程

@MainActor
final class AIQuickVoiceSession: ObservableObject {
    static let shared = AIQuickVoiceSession()

    enum Phase: Equatable {
        case idle
        case starting
        case listening
        case working
        case finished(AIExpenseOutcome)
    }

    @Published private(set) var phase: Phase = .idle
    /// 送去 AI 的那一句（working 時畫面上寫的原句；辨識器停了之後 transcript 可能再被改，所以另存）
    @Published private(set) var heardText: String = ""

    /// 這個 session 自己的辨識器（不跟浮動麥克風的 @StateObject 共用）
    let recognizer: SpeechRecognizer

    /// phase 是 finished 才有（View 用 if let，不用 if case）
    var outcome: AIExpenseOutcome? {
        if case .finished(let o) = phase { return o }
        return nil
    }
    var isStarting: Bool { phase == .starting }
    var isListening: Bool { phase == .listening }
    var isWorking: Bool { phase == .working }
    /// 畫面要畫底部那張卡（暗底＋請說…）
    var showsPanel: Bool { isStarting || isListening || isWorking }

    /// 結果卡留多久（同 MainTabView.aiShowToast 的 3.5 秒）
    private static let resultNanoseconds: UInt64 = 3_500_000_000
    /// 收起來的淡出（同 aiShowToast 的 0.3 秒）
    private static let fadeNanoseconds: UInt64 = 300_000_000
    /// 自動停檢查的間隔
    private static let tickNanoseconds: UInt64 = 250_000_000
    /// 冷啟動時最多等 App 到前景多久（100ms × 30）
    private static let activeWaitSteps = 30

    private var token: UUID?
    private var autoStop = AIQuickVoiceAutoStop(startedAt: Date())
    private var tickTask: Task<Void, Never>?
    private var window: UIWindow?
    private var backgroundObserver: NSObjectProtocol?

    private init() {
        recognizer = SpeechRecognizer()
        // 講到一半回主畫面：取消、不存。不用 willResignActive——權限對話框、拉控制中心都會 resign，那時不能取消。
        // 閉包不抓 self（shared 是單例），也就沒有跨執行緒抓 self 的問題
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                AIQuickVoiceSession.shared.appDidEnterBackground()
            }
        }
    }

    // MARK: 對外

    /// 深連結觸發（MainTabView 取走 pendingVoice 後呼叫）。正在聽／在記帳就不理；
    /// 結果卡還掛著（finished）可以直接再開始一次。拿不到畫面就不聽——不准沒畫面還在錄
    func begin() {
        guard phase == .idle || outcome != nil else { return }
        let t = UUID()
        token = t
        heardText = ""
        Self.dismissKeyboard()
        setPhase(.starting)
        guard showWindow() else {
            token = nil
            phase = .idle
            return
        }
        Task { @MainActor in
            await self.prepare(t)
        }
    }

    /// 「好了」：不等自動停，現在就送出
    func finishNow() {
        guard phase == .listening, let t = token else { return }
        Task { @MainActor in
            await self.complete(t)
        }
    }

    /// 「取消」：準備中、聽的時候才有用（記帳中不能取消，按鈕也不顯示）
    func cancel() {
        guard phase == .starting || phase == .listening else { return }
        stopTicking()
        if recognizer.isRecording { recognizer.stopRecording() }
        close()
    }

    // MARK: 流程

    private func prepare(_ t: UUID) async {
        // 冷啟動、從控制中心按：網址可能比 App 到前景還早一點；權限對話框要在前景才跳得出來
        await waitUntilActive(t)
        guard isCurrent(t, .starting) else { return }

        // 訂閱：冷啟動時付費訂閱的到期日可能還沒讀進來，先讀一次
        let sub = SubscriptionManager.shared
        if !sub.isPremium { await sub.refreshStatus() }
        guard isCurrent(t, .starting) else { return }
        guard sub.isPremium else {
            finish(t, Self.failure("說一句是訂閱功能", "訂閱 LifeGood 之後，就能用 AI 語音記帳。"))
            return
        }
        // 設定頁那一區在「進階設定」裡，標題是「語音 AI 助手」（SettingsView.swift advancedExtraSections）
        guard AISettingsStore.shared.isReady else {
            finish(t, Self.failure("還沒設定 AI 語音記帳", "到「設定 → 進階設定 → 語音 AI 助手」選好服務、填好金鑰，就能說一句記帳。"))
            return
        }

        // 權限（跟浮動麥克風同一句提示）
        let granted = await recognizer.requestAccess()
        guard isCurrent(t, .starting) else { return }
        guard granted else {
            finish(t, Self.failure("無法啟用語音", "請至「設定 → LifeGood」開啟麥克風與語音辨識權限。"))
            return
        }

        do {
            try recognizer.startRecording()
        } catch {
            // 開到一半失敗（音訊引擎起不來）：把開了的 audio session、tap 收乾淨
            recognizer.stopRecording()
            finish(t, Self.failure("錄音失敗", error.localizedDescription))
            return
        }
        // 不支援中文辨識時 startRecording 不丟錯、只是沒開始（AIService.swift SpeechRecognizer.startRecording）
        guard recognizer.isRecording else {
            finish(t, Self.failure("錄音失敗", recognizer.errorMessage ?? "此裝置不支援中文語音辨識"))
            return
        }
        autoStop = AIQuickVoiceAutoStop(startedAt: Date())
        setPhase(.listening)
        startTicking(t)
    }

    /// App 還沒到前景就等一下（最多約 3 秒；等不到也照樣往下走）
    private func waitUntilActive(_ t: UUID) async {
        var steps = 0
        while UIApplication.shared.applicationState != .active && steps < Self.activeWaitSteps {
            try? await Task.sleep(nanoseconds: 100_000_000)
            steps += 1
            guard token == t else { return }
        }
    }

    /// 每 0.25 秒看一次：字停住、沒字太久、太長、辨識器自己停了（出錯）→ 送出。
    /// complete 一定開新的 Task 跑，不在 tickTask 裡 await：complete 會 cancel tickTask，
    /// 被取消的 Task 裡 URLSession 會丟 CancellationError，AI 解析就失敗了
    private func startTicking(_ t: UUID) {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: AIQuickVoiceSession.tickNanoseconds)
                guard let self, self.token == t, self.phase == .listening else { return }
                let now = Date()
                self.autoStop.observe(self.recognizer.transcript, at: now)
                if !self.recognizer.isRecording || self.autoStop.shouldStop(at: now) {
                    Task { @MainActor in
                        await self.complete(t)
                    }
                    return
                }
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// 聽完：停麥克風、交給 AIExpenseCommitter（跟浮動麥克風同一份解析與存檔）
    private func complete(_ t: UUID) async {
        guard isCurrent(t, .listening) else { return }
        stopTicking()
        let text = recognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        recognizer.stopRecording()
        guard !text.isEmpty else {
            finish(t, Self.failure("沒聽到內容", "再按一次「說一句」，說完停一下就好。"))
            return
        }
        heardText = text
        setPhase(.working)
        // [v25.548] 記帳中不擋手：AI 解析、地點查詢等網路請求慢的時候可能等上幾十秒，
        // 跟浮動麥克風一樣讓底下的 App 照常能點；「正在記…」小卡留著、存好換成結果卡
        window?.isUserInteractionEnabled = false
        let outcome = await AIExpenseCommitter.record(text: text, expense: AppStores.expense,
                                                      life: AppStores.life, finance: AppStores.finance)
        guard token == t else { return }
        finish(t, outcome)
    }

    /// 顯示結果卡（跟 App 的 toast 一樣不擋手），3.5 秒後收起來
    private func finish(_ t: UUID, _ outcome: AIExpenseOutcome) {
        guard token == t else { return }
        stopTicking()
        if recognizer.isRecording { recognizer.stopRecording() }
        setPhase(.finished(outcome))
        window?.isUserInteractionEnabled = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: AIQuickVoiceSession.resultNanoseconds)
            guard self.token == t else { return }
            self.close()
        }
    }

    private func appDidEnterBackground() {
        // 記帳中（working）讓它存完
        if phase == .starting || phase == .listening { cancel() }
    }

    /// 收起來：淡出 0.3 秒後藏視窗
    private func close() {
        token = nil
        stopTicking()
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .idle
        }
        hideWindow()
    }

    private func isCurrent(_ t: UUID, _ p: Phase) -> Bool {
        token == t && phase == p
    }

    private func setPhase(_ p: Phase) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            phase = p
        }
    }

    private static func failure(_ title: String, _ detail: String) -> AIExpenseOutcome {
        AIExpenseOutcome(title: title, detail: detail, isError: true)
    }

    // MARK: 視窗（蓋在所有頁面與 sheet 上面）

    private func showWindow() -> Bool {
        if let w = window {
            w.isUserInteractionEnabled = true
            return true
        }
        guard let scene = Self.activeScene() else { return false }
        let host = UIHostingController(rootView: AIQuickVoicePanel(session: self, recognizer: recognizer))
        host.view.backgroundColor = .clear
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert
        w.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
        return true
    }

    /// 先不收手（isUserInteractionEnabled = false），等淡出做完才藏。
    /// 這 0.3 秒內又 begin() 會開新的視窗，舊的照樣在 0.3 秒後藏掉
    private func hideWindow() {
        guard let w = window else { return }
        window = nil
        w.isUserInteractionEnabled = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: AIQuickVoiceSession.fadeNanoseconds)
            w.isHidden = true
        }
    }

    /// [情境驗證補] 鍵盤在系統自己的視窗、層級比 .alert 高：開著新增支出（數字鍵盤）或正在打字時按說一句，
    /// 底部那張卡（「好了」「取消」）會被鍵盤蓋住、按鍵還會打進底下的欄位。先把鍵盤收起來——
    /// 只是收起來（底下那一頁、打到一半的字都還在），跟主控定案 5「不關 sheet」不衝突
    private static func dismissKeyboard() {
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

// MARK: - 畫面

/// 說一句的畫面（UIHostingController 的根）：結果卡在上面（跟 App 的 toast 同位置、同長相），
/// 準備中／聽／記帳中是暗底＋底部一張卡
struct AIQuickVoicePanel: View {
    @ObservedObject var session: AIQuickVoiceSession
    @ObservedObject var recognizer: SpeechRecognizer

    var body: some View {
        ZStack {
            if let outcome = session.outcome {
                AIQuickVoiceResult(outcome: outcome)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if session.showsPanel {
                AIQuickVoiceSheet(model: cardModel,
                                  onCancel: { session.cancel() },
                                  onDone: { session.finishNow() })
                    .transition(.opacity)
            }
        }
    }

    private var cardModel: AIQuickVoiceCardModel {
        AIQuickVoiceCardModel.make(phase: session.phase,
                                   transcript: recognizer.transcript,
                                   heard: session.heardText)
    }
}

/// AI 記帳的結果提示卡（v3 前在 MainTabView.aiToastView 裡，原樣搬出來；浮動麥克風、說一句共用）
struct AIToastCard: View {
    let title: String
    let detail: String
    let isError: Bool

    private var accent: Color { isError ? .orange : .green }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AIToastCardBadge(accent: accent, isError: isError)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.22), lineWidth: 0.75)
        )
        .shadow(color: accent.opacity(0.18), radius: 10, y: 4)
        .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
    }
}

/// 結果卡左邊的漸層圓徽章（原 aiToastView 的 ZStack）
private struct AIToastCardBadge: View {
    let accent: Color
    let isError: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [accent.opacity(0.24), accent.opacity(0.10)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 32, height: 32)
            Circle()
                .stroke(accent.opacity(0.30), lineWidth: 1)
                .frame(width: 32, height: 32)
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(accent)
                .font(.system(size: 15, weight: .semibold))
        }
    }
}

/// 結果卡的位置：跟 MainTabView.aiToastView 一樣（左右 16、上 12、下面 Spacer、不擋手）
private struct AIQuickVoiceResult: View {
    let outcome: AIExpenseOutcome

    var body: some View {
        VStack {
            AIToastCard(title: outcome.title, detail: outcome.detail, isError: outcome.isError)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

/// 卡上要寫的字（在這裡組好，View 只照著畫）
private struct AIQuickVoiceCardModel {
    /// 「請說：午餐 180 刷玉山卡」
    static let prompt = "請說：午餐 180 刷玉山卡"
    /// 「說完停一下就會自動記」
    static let hint = "說完停一下就會自動記"
    /// 記帳中
    static let workingText = "記帳中…"

    var icon: String
    var liveText: String
    var liveIsPlaceholder: Bool
    var isWorking: Bool
    var showsCancel: Bool
    var showsDone: Bool

    static func make(phase: AIQuickVoiceSession.Phase, transcript: String, heard: String) -> AIQuickVoiceCardModel {
        let live = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        switch phase {
        case .listening:
            return AIQuickVoiceCardModel(icon: "waveform",
                                         liveText: live.isEmpty ? "我在聽…" : live,
                                         liveIsPlaceholder: live.isEmpty,
                                         isWorking: false, showsCancel: true, showsDone: true)
        case .working:
            return AIQuickVoiceCardModel(icon: "mic.fill", liveText: heard, liveIsPlaceholder: false,
                                         isWorking: true, showsCancel: false, showsDone: false)
        case .idle, .starting, .finished:
            return AIQuickVoiceCardModel(icon: "mic.fill", liveText: "準備中…", liveIsPlaceholder: true,
                                         isWorking: false, showsCancel: true, showsDone: false)
        }
    }
}

/// 紫色（同 MainTabView.aiMicButton 的漸層 rgb(0.55,0.35,0.95) → rgb(0.40,0.20,0.85)）
private enum AIQuickVoiceStyle {
    static let purple = LinearGradient(
        colors: [Color(red: 0.55, green: 0.35, blue: 0.95),
                 Color(red: 0.40, green: 0.20, blue: 0.85)],
        startPoint: .top, endPoint: .bottom
    )
}

/// 暗底＋底部一張卡
private struct AIQuickVoiceSheet: View {
    let model: AIQuickVoiceCardModel
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // [v25.548] 記帳中不擋手（見 AIQuickVoiceSession），暗底也一起拿掉，免得看起來還被擋住
            Color.black.opacity(model.isWorking ? 0 : 0.35)
                .ignoresSafeArea()
            AIQuickVoiceCard(model: model, onCancel: onCancel, onDone: onDone)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
    }
}

private struct AIQuickVoiceCard: View {
    let model: AIQuickVoiceCardModel
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            AIQuickVoiceMic(icon: model.icon)
            Text(AIQuickVoiceCardModel.prompt)
                .font(.headline)
                .foregroundStyle(.primary)
            AIQuickVoiceLiveText(text: model.liveText, isPlaceholder: model.liveIsPlaceholder)
            AIQuickVoiceStatus(isWorking: model.isWorking)
            AIQuickVoiceButtons(showsCancel: model.showsCancel, showsDone: model.showsDone,
                                onCancel: onCancel, onDone: onDone)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

/// 紫色圓＋麥克風（聽的時候換 waveform）
private struct AIQuickVoiceMic: View {
    let icon: String

    var body: some View {
        ZStack {
            Circle()
                .fill(AIQuickVoiceStyle.purple)
                .frame(width: 64, height: 64)
                .shadow(color: Color.purple.opacity(0.45), radius: 12, y: 4)
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// 即時字（還沒字：「我在聽…」；準備中：「準備中…」；記帳中：原句）
private struct AIQuickVoiceLiveText: View {
    let text: String
    let isPlaceholder: Bool

    private var color: Color { isPlaceholder ? Color.secondary : Color.primary }

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// 小字「說完停一下就會自動記」；記帳中換成轉圈＋「記帳中…」
private struct AIQuickVoiceStatus: View {
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isWorking {
                ProgressView()
                Text(AIQuickVoiceCardModel.workingText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(AIQuickVoiceCardModel.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 「取消」（準備中、聽的時候）、「好了」（聽的時候，紫底白字）；記帳中沒有按鈕
private struct AIQuickVoiceButtons: View {
    let showsCancel: Bool
    let showsDone: Bool
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if showsCancel {
                Button(action: onCancel) {
                    AIQuickVoiceButtonLabel(text: "取消", filled: false)
                }
                .buttonStyle(.plain)
            }
            if showsDone {
                Button(action: onDone) {
                    AIQuickVoiceButtonLabel(text: "好了", filled: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct AIQuickVoiceButtonLabel: View {
    let text: String
    let filled: Bool

    var body: some View {
        if filled {
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(AIQuickVoiceStyle.purple, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        } else {
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
