import SwiftUI
import Charts

// MARK: - 健康（v25.351 建立，v25.352 加入 Apple 健康聯動與跑步路徑）
//
// 入口在人生分頁「財富」的右邊，有健康里程碑或健身紀錄才出現。
// 內容：
//   1. 即時紀錄橫幅（跑步進行中時）
//   2. 看板：本月訓練次數、本月訓練量、連續週數、累計次數
//   3. Apple 健康聯動開關與同步
//   4. 綜效曲線：兩筆以上才畫，可切總訓練量／總次數／單一動作與期間
//   5. 動作統計、訓練紀錄（含路徑地圖）、健康里程碑
//
// 訓練量＝總次數（每組次數 × 組數）× 等效負荷。負荷是「自身體重」時帶入健康檔案
// 最近一次的體重；沒有體重紀錄就不灌進總量（見 WorkoutExercise.volume）。
//
// HealthKit 沒有組數／次數／負荷的欄位，所以重訓明細只留在本 App，寫回去的只有
// 時間、距離與熱量——畫面上有明講，不要讓使用者以為明細會同步。
//
// [v25.551] 即時紀錄橫幅寫運動名（「騎車・記錄中」）；訓練紀錄的爬升 10 公尺以上才顯示；
// 舊版記錄、路線只存到起點的那幾筆，下面多一行灰字說明。
//
// [v25.552] 健康 v2：數字和字全部讀一套（WorkoutFacts／WorkoutFormat）——週一開始、西曆，連續週數照週一算；
// 配速一律 6'11"、騎車寫時速；清單距離一位小數「5.2 公里」；大卡沒量到的用 MET 表估、寫「約 340 大卡」；
// 手錶的「走路」併進健走、「健行」併進登山（動作統計同一列）。刪除先問；右上「＋」改成選運動的選單
// （補記一趟跑步／健走／騎車／登山、記一次重訓）；上次跑到一半被關掉、還沒存的那一趟，最上面有一張救回卡
// （RunRecoveryCenter）；寫進 Apple 健康改用共用的 WorkoutHealthWriter（救回的那一趟也走同一支）。

struct HealthView: View {
    @EnvironmentObject var lifeStore: LifeStore

    private struct WorkoutEditorRequest: Identifiable {
        let id = UUID()
        let session: WorkoutSession?
        /// [v25.552] 「＋」選單選的運動（表單一打開就選好）；編輯是 nil
        var sport: WorkoutSport? = nil
    }

    /// [v25.552] 清單一列的膠囊（字先在 routeChips 組好，body 只畫）
    private struct ChipItem: Identifiable {
        let text: String
        let icon: String
        var id: String { icon + text }
    }

    /// [v25.552] 「＋」選單裡補記的四種有氧（重訓另外一顆）
    private static let logSports: [WorkoutSport] = [.run, .walk, .bike, .hike]

    @StateObject private var health = HealthKitManager.shared
    @StateObject private var tracker = RunTracker.shared
    /// [v25.552] 上次跑到一半被關掉、還沒存的那幾趟（App 一打開就 scan；這頁最上面一張卡）
    @ObservedObject private var recovery = RunRecoveryCenter.shared

    /// [v25.532] 要新增還是編輯哪一筆，跟「打開」綁在一起（sheet(item:)）：以前先改 editing 再打開，
    /// 表單有時會帶到改之前的舊值——按某一筆的「編輯」卻打開空白的新增，或上一次編輯的那一筆。
    @State private var editorRequest: WorkoutEditorRequest?
    @State private var showRun = false
    @State private var syncing = false
    @State private var syncMessage: String?
    /// [v25.388] 複製訓練後的短暫提示（複製出來的那一筆是「現在」，會直接跳到清單最上面，
    /// 使用者若是在下面幾筆按的複製，新的那一列可能根本不在畫面上，不講一聲會以為沒反應）
    @State private var copiedNote: String?
    @State private var copiedNoteTask: Task<Void, Never>?
    /// [v25.552] 按了「刪除」、等確認的那一筆（以前一按就刪、沒有復原）
    @State private var deleteTarget: WorkoutSession?
    /// [v25.552] 救回卡按了「丟掉」、等確認的那一趟
    @State private var discardTarget: RunCheckpoint?
    /// 上次同步時間，決定要往回抓多久（第一次抓 90 天）
    @AppStorage("health_hk_last_sync") private var lastSyncEpoch: Double = 0
    @AppStorage("health_hk_enabled") private var hkEnabled = false
    @State private var curveMode: CurveMode = .volume
    @State private var selectedExercise: String = ""
    @State private var range: HealthRange = .halfYear
    @State private var rawSelectedDate: Date?

    private let accent = Color(red: 0.20, green: 0.78, blue: 0.45)

    enum CurveMode: String, CaseIterable, Identifiable {
        case volume = "總訓練量"
        case reps = "總次數"
        case exercise = "單一動作"
        var id: String { rawValue }
    }

    enum HealthRange: String, CaseIterable, Identifiable {
        case quarter = "近 3 月"
        case halfYear = "近半年"
        case year = "近一年"
        case all = "全部"
        var id: String { rawValue }

        var from: Date? {
            let cal = Calendar.current, now = Date()
            switch self {
            case .quarter: return cal.date(byAdding: .month, value: -3, to: now)
            case .halfYear: return cal.date(byAdding: .month, value: -6, to: now)
            case .year: return cal.date(byAdding: .year, value: -1, to: now)
            case .all: return nil
            }
        }
    }

    // MARK: 資料

    private var bodyWeight: Double? { lifeStore.latestBodyWeightKg }
    private var sessions: [WorkoutSession] { lifeStore.workoutsByDateDesc }

    private var inRange: [WorkoutSession] {
        guard let from = range.from else { return sessions }
        return sessions.filter { $0.date >= from }
    }

    private var healthMilestones: [LifeMilestone] {
        lifeStore.milestones.filter { $0.category == .health }.sorted { $0.date > $1.date }
    }

    /// [v25.552] 本月：西曆（WorkoutFacts.calendar），手機設民國曆也一樣
    private var thisMonth: [WorkoutSession] {
        let cal = WorkoutFacts.calendar
        let now = Date()
        return sessions.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
    }

    private var monthVolume: Double {
        thisMonth.compactMap { $0.totalVolume(bodyWeightKg: bodyWeight) }.reduce(0, +)
    }

    /// [v25.552] 從本週往回數，連續有運動的週數：一套數字（週一開始；1 分鐘以上或有重訓動作才算；
    /// 這週還沒動從上週數）。以前用手機地區設定的週，週六騎車、週日跑步可能被拆成兩週
    private var streakWeeks: Int { WorkoutFacts.streakWeeks(sessions) }

    /// [v25.552] 動作統計、單一動作曲線用的名字：有氧用運動種類（手錶的「走路」和 App 的「健走」同一列），
    /// 重訓用動作名稱。「其他有氧」（游泳、橢圓機、划船機、跳繩…）照名字分開，不全部併成一列「其他有氧」
    /// （不然游泳和划船機的「最長 X 公里」會混在一起）
    private func statName(_ e: WorkoutExercise) -> String {
        let n = e.name.trimmingCharacters(in: .whitespaces)
        guard e.kind == .cardio else { return n }
        let sport = e.resolvedSport
        if sport == .other, !n.isEmpty { return n }
        return sport.displayName
    }

    /// [v25.552] 清單上動作的名字：有氧沒填名字、或是手錶的舊名（「走路」「健行」）寫運動種類（「健走」「登山」）
    private func exerciseLabel(_ e: WorkoutExercise) -> String {
        let n = e.name.trimmingCharacters(in: .whitespaces)
        if e.kind == .cardio, n.isEmpty || n == "走路" || n == "健行" { return e.resolvedSport.displayName }
        return n.isEmpty ? e.kind.rawValue : n
    }

    /// [v25.552] 清單上一趟的名字：手錶舊名「走路」「健行」寫成「健走」「登山」，其他照 displayTitle
    private func sessionTitle(_ s: WorkoutSession) -> String {
        let t = s.displayTitle
        if t == "走路" || t == "健行", s.primarySport.isCardio { return s.primarySport.displayName }
        return t
    }

    /// 曲線資料點
    private struct CurvePoint: Identifiable {
        let date: Date
        let value: Double
        let label: String
        var id: Date { date }
    }

    private var curvePoints: [CurvePoint] {
        let asc = inRange.sorted { $0.date < $1.date }
        switch curveMode {
        case .volume:
            return asc.compactMap { s in
                guard let v = s.totalVolume(bodyWeightKg: bodyWeight), v > 0 else { return nil }
                return CurvePoint(date: s.date, value: v, label: s.displayTitle)
            }
        case .reps:
            return asc.compactMap { s in
                let r = s.totalReps
                guard r > 0 else { return nil }
                return CurvePoint(date: s.date, value: Double(r), label: s.displayTitle)
            }
        case .exercise:
            guard !selectedExercise.isEmpty else { return [] }
            return asc.flatMap { s in
                s.exercises.filter { statName($0) == selectedExercise }.compactMap { e -> CurvePoint? in
                    if let v = e.volume(bodyWeightKg: bodyWeight), v > 0 {
                        return CurvePoint(date: s.date, value: v, label: e.summary(bodyWeightKg: bodyWeight))
                    }
                    if e.kind == .cardio, e.distanceKm > 0 {
                        return CurvePoint(date: s.date, value: e.distanceKm, label: e.summary(bodyWeightKg: bodyWeight))
                    }
                    if e.kind == .strength, e.totalReps > 0 {   // [v25.552] 舊資料有氧留著的次數不畫（單位是公里）
                        return CurvePoint(date: s.date, value: Double(e.totalReps), label: e.summary(bodyWeightKg: bodyWeight))
                    }
                    return nil
                }
            }
        }
    }

    private var curveUnit: String {
        switch curveMode {
        case .volume: return "公斤"
        case .reps: return "下"
        case .exercise:
            guard let first = latestExercise(named: selectedExercise) else { return "" }
            if first.kind == .cardio { return "公里" }
            return first.loadType == .none ? "下" : "公斤"
        }
    }

    /// [v25.552] 最近一次叫這個名字（statName）的動作（sessions 是新到舊）
    private func latestExercise(named name: String) -> WorkoutExercise? {
        guard !name.isEmpty else { return nil }
        for s in sessions {
            if let e = s.exercises.first(where: { statName($0) == name }) { return e }
        }
        return nil
    }

    /// [v25.552] 單一動作的選項：用 statName 數次數，多到少、同次數照字（以前讀 LifeStore 的原始名字，「走路」「健走」分兩個）
    private var exerciseNames: [String] {
        var counts: [String: Int] = [:]
        for s in sessions {
            for e in s.exercises {
                let n = statName(e)
                if !n.isEmpty { counts[n, default: 0] += 1 }
            }
        }
        let sorted = counts.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            return a.key < b.key
        }
        return sorted.map { $0.key }
    }

    private var selectedPoint: CurvePoint? {
        guard let raw = rawSelectedDate else { return nil }
        return curvePoints.min { a, b in
            abs(a.date.timeIntervalSince(raw)) < abs(b.date.timeIntervalSince(raw))
        }
    }

    // MARK: 主體

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tracker.isActive { liveBanner }
                    if let cp = recovery.pending.first { recoveryCard(cp) }
                    summaryCard
                    healthKitCard
                    if sessions.count >= 2 {
                        curveSection
                    } else if !sessions.isEmpty {
                        hintCard("再記一次訓練就會出現綜效曲線",
                                 detail: "兩筆以上才看得出變化，目前只有 \(sessions.count) 筆。")
                    }
                    if !sessions.isEmpty { exerciseRanking }
                    sessionSection
                    if !healthMilestones.isEmpty { milestoneSection }
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("健康")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRun = true } label: {
                        Image(systemName: tracker.isActive ? "location.fill" : "figure.run")
                            .foregroundStyle(tracker.isActive ? accent : Color.accentColor)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    addMenu
                }
            }
            .sheet(item: $editorRequest) { request in
                WorkoutEditorView(session: request.session, initialSport: request.sport) { saved in
                    lifeStore.upsertWorkout(saved)
                    let store = lifeStore
                    Task { await WorkoutHealthWriter.push(saved, store: store) }
                }
                .environmentObject(lifeStore)
                .appStores()
            }
            .sheet(isPresented: $showRun) {
                RunTrackingView { session in
                    lifeStore.upsertWorkout(session)
                    let store = lifeStore
                    Task { await WorkoutHealthWriter.push(session, store: store) }
                }
                .environmentObject(lifeStore)
                .appStores()
            }
            // [v25.552] 保險：App 一打開已經 scan 過（LifeGoodApp），這裡重複呼叫什麼都不做
            .task { await RunRecoveryCenter.shared.scan() }
            // 離開頁面時把還在倒數的提示收掉，不要留一個醒著的 Task
            .onDisappear {
                copiedNoteTask?.cancel()
                copiedNoteTask = nil
                copiedNote = nil
            }
        }
    }

    // MARK: 看板

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(thisMonth.count)")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("次／本月").font(.subheadline.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                if let last = sessions.first {
                    Text("最近 " + WorkoutFormat.date(last.date))
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.18), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.75))
                        .foregroundStyle(.white)
                }
            }
            HStack(spacing: 10) {
                kpiCell(title: "本月訓練量", value: monthVolume > 0 ? volumeText(monthVolume) : "—", icon: "scalemass.fill")
                kpiCell(title: "連續週數", value: streakWeeks > 0 ? "\(streakWeeks) 週" : "—", icon: "flame.fill")
                kpiCell(title: "累計訓練", value: "\(sessions.count) 次", icon: "figure.strengthtraining.traditional")
            }
        }
        .padding(16)
        .background(
            ZStack {
                LinearGradient(colors: [accent, accent.opacity(0.62)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.white.opacity(0.12)).frame(width: 130).offset(x: 120, y: -54)
                Circle().fill(Color.white.opacity(0.08)).frame(width: 78).offset(x: -110, y: 44)
                Circle().fill(Color.white.opacity(0.07)).frame(width: 55).offset(x: 66, y: 40)
                LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: accent.opacity(0.45), radius: 14, y: 7)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private func kpiCell(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.75))
                Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 即時紀錄橫幅

    private var liveBanner: some View {
        Button { showRun = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text(liveTitle)
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                    Text(liveText)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Text("回到畫面").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(LinearGradient(colors: [.orange, .orange.opacity(0.75)],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// [v25.551] 橫幅標題：「騎車・記錄中」／「騎車・已暫停」（運動種類在記錄器裡，按隱藏再回來也對）
    private var liveTitle: String {
        tracker.sport.rawValue + "・" + (tracker.phase == .paused ? "已暫停" : "記錄中")
    }

    /// 橫幅上的即時數字：字串先組好再進 Text。[v25.552] 一套寫法：「3.42 公里・21:05」（騎車 10 公里以上一位小數；
    /// 時間往下取整，跟跑步畫面的碼錶一樣）
    private var liveText: String {
        let km = WorkoutFormat.preciseKmNumber(tracker.distanceMeters / 1000, sport: WorkoutSport(tracker.sport))
        let clock = WorkoutFormat.clock(seconds: tracker.elapsed.rounded(.down))
        return km + " 公里・" + clock
    }

    // MARK: 救回卡（[v25.552] 上次跑到一半被關掉、還沒存的那一趟）

    /// 白卡：問句＋〔存下來〕〔丟掉〕。存下來跟按完成同一條路（RunRecoveryCenter.save → WorkoutFacts.makeSession）；
    /// 丟掉先問一次。提示框掛在這張卡上（跟刪除的提示框不在同一個 view）
    private func recoveryCard(_ cp: RunCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(cp.prompt())
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let more = recoveryMoreText {
                        Text(more).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button { RunRecoveryCenter.shared.save(cp, store: lifeStore) } label: {
                    recoveryButtonLabel("存下來", filled: true)
                }
                .buttonStyle(.plain)
                Button { discardTarget = cp } label: {
                    recoveryButtonLabel("丟掉", filled: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .alert("丟掉這一趟？", isPresented: discardBinding, presenting: discardTarget) { c in
            Button("丟掉", role: .destructive) { RunRecoveryCenter.shared.discard(c) }
            Button("取消", role: .cancel) { }
        } message: { _ in
            Text("丟掉就找不回來了。")
        }
    }

    /// 還有第二趟以上沒存時的灰字
    private var recoveryMoreText: String? {
        let n = recovery.pending.count
        return n > 1 ? "還有 \(n - 1) 趟沒存" : nil
    }

    private var discardBinding: Binding<Bool> {
        Binding(get: { discardTarget != nil }, set: { if !$0 { discardTarget = nil } })
    }

    /// 救回卡的按鈕字：存下來＝綠底白字、丟掉＝灰底
    private func recoveryButtonLabel(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(filled ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(filled ? accent : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }

    // MARK: 「＋」選單（[v25.552] 先選運動，表單一打開就是那一種）

    private var addMenu: some View {
        Menu {
            ForEach(Self.logSports) { s in
                Button { editorRequest = WorkoutEditorRequest(session: nil, sport: s) } label: {
                    Label("補記一趟" + s.displayName, systemImage: s.icon)
                }
            }
            Divider()
            Button { editorRequest = WorkoutEditorRequest(session: nil, sport: .strength) } label: {
                Label("記一次重訓", systemImage: "dumbbell.fill")
            }
        } label: {
            Image(systemName: "plus")
        }
    }

    // MARK: Apple 健康

    private var healthKitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 15)).foregroundStyle(.pink)
                Text("Apple 健康").font(.subheadline.weight(.bold))
                Spacer()
                if health.isAvailable {
                    Toggle("", isOn: Binding(
                        get: { hkEnabled },
                        set: { on in
                            hkEnabled = on
                            if on { Task { await health.requestAuthorization(); await syncFromHealthKit() } }
                        }))
                        .labelsHidden()
                        .tint(accent)
                }
            }
            if !health.isAvailable {
                Text("這台裝置不支援「健康」App。").font(.caption).foregroundStyle(.secondary)
            } else if hkEnabled {
                Text("體重、血壓、心率與訓練會與 Apple 健康互通。HealthKit 沒有「組數／次數／負荷」的欄位，所以重訓明細只留在這個 App，寫回去的只有時間、距離與熱量。")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        Task { await syncFromHealthKit() }
                    } label: {
                        Label(syncing ? "同步中…" : "立即同步", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.bold))
                    }
                    .disabled(syncing)
                    if lastSyncEpoch > 0 {
                        Text("上次 " + Self.shortDate.string(from: Date(timeIntervalSince1970: lastSyncEpoch)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let msg = syncMessage {
                    Text(msg).font(.caption2).foregroundStyle(accent)
                }
                if let err = health.lastError {
                    Text(err).font(.caption2).foregroundStyle(.red)
                }
            } else {
                Text("打開後可以把 Apple 健康的體重、血壓與 Apple Watch 的訓練帶進來，這裡記的訓練也會寫回去計入體能訓練圓環。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
    }

    /// 從 Apple 健康抓體重、血壓與訓練回來
    private func syncFromHealthKit() async {
        guard hkEnabled, health.isAvailable, !syncing else { return }
        syncing = true
        syncMessage = nil
        defer { syncing = false }

        let since = lastSyncEpoch > 0
            ? Date(timeIntervalSince1970: lastSyncEpoch)
            : Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date.distantPast

        var addedWeights = 0
        var addedVitals = 0
        var addedWorkouts = 0

        var profile = lifeStore.healthProfile
        let cal = Calendar.current

        // 體重：同一天已經有體重紀錄就不重複加
        let weights = await health.fetchBodyMass(since: since)
        for w in weights {
            let hasSameDay = profile.measurements.contains {
                $0.weightKg != nil && cal.isDate($0.date, inSameDayAs: w.date)
            }
            guard !hasSameDay else { continue }
            profile.measurements.append(HealthMeasurement(date: w.date, weightKg: w.kg,
                                                          note: "來自 Apple 健康"))
            addedWeights += 1
        }
        // 血壓／心率：同一分鐘已經有就跳過
        let vitals = await health.fetchVitals(since: since)
        for v in vitals {
            let exists = profile.measurements.contains {
                abs($0.date.timeIntervalSince(v.date)) < 60 && $0.hasBloodPressure
            }
            guard !exists else { continue }
            profile.measurements.append(HealthMeasurement(date: v.date, weightKg: nil,
                                                          systolic: v.systolic, diastolic: v.diastolic,
                                                          heartRate: v.heartRate, note: "來自 Apple 健康"))
            addedVitals += 1
        }
        if profile.heightCm == 0, let h = await health.fetchLatestHeightCm(), h > 0 {
            profile.heightCm = h
        }
        if addedWeights > 0 || addedVitals > 0 || profile.heightCm != lifeStore.healthProfile.heightCm {
            profile.measurements.sort { $0.date > $1.date }
            lifeStore.updateHealthProfile(profile)
        }

        // 訓練：已經匯入過的 UUID 不再重複
        let known = Set(lifeStore.workouts.compactMap(\.healthKitUUID))
        let imported = await health.fetchWorkouts(since: since, excluding: known)
        for w in imported {
            let minutes = w.end.timeIntervalSince(w.start) / 60
            guard minutes >= 1 else { continue }
            let ex = WorkoutExercise(
                name: w.activityName,
                kind: w.isCardio ? .cardio : .strength,
                reps: 0, sets: 0, loadType: .none, loadKg: 0,
                distanceKm: w.distanceKm, durationMinutes: minutes,
                route: w.route, elevationGainM: 0,
                note: w.isCardio ? "" : "來自 Apple 健康，組數次數請自行補上",
                sport: w.sport)                       // [v25.552] 手錶的運動種類（走路＝健走、健行＝登山）
            let session = WorkoutSession(
                date: w.start, title: w.activityName, exercises: [ex],
                durationMinutes: minutes, place: "", note: "",
                healthKitUUID: w.uuid, activeEnergyKcal: w.energyKcal,
                source: .watch)                       // [v25.552] 從 Apple 健康帶進來的
            lifeStore.upsertWorkout(session)
            addedWorkouts += 1
        }

        lastSyncEpoch = Date().timeIntervalSince1970
        syncMessage = syncSummary(weights: addedWeights, vitals: addedVitals, workouts: addedWorkouts)
    }

    private func syncSummary(weights: Int, vitals: Int, workouts: Int) -> String {
        var parts: [String] = []
        if weights > 0 { parts.append("體重 \(weights) 筆") }
        if vitals > 0 { parts.append("血壓 \(vitals) 筆") }
        if workouts > 0 { parts.append("訓練 \(workouts) 筆") }
        return parts.isEmpty ? "已是最新，沒有新資料" : "已帶入 " + parts.joined(separator: "、")
    }

    // [v25.552] 寫回 Apple 健康搬到共用的 WorkoutHealthWriter.push（RunRecovery.swift）：
    // 救回中途存檔也要寫；寫好的編號存回「最新的那一筆」（等待中被編輯過不會蓋回舊的）。

    // MARK: 複製訓練

    /// [v25.388] 把一筆訓練原封不動複製一份到現在，省得同一套菜單每次重打。
    ///
    /// 帶過去的是「訓練內容」：標題、每個動作（名稱／類型／次數／組數／負荷／距離／時間／
    /// 備註）、整場時間、場地、備註。
    ///
    /// ⚠️ 刻意**不**帶的是「那一次實際量到的東西」——把它們複製過來等於憑空捏造一筆
    ///    根本沒發生過的數據：
    ///    • healthKitUUID：那是 Apple 健康的去重鍵。複製過去等於宣稱這兩筆是同一場訓練，
    ///      下次同步的 known 集合會把新的這筆誤判成已匯入，而且寫回去也會打架。
    ///    • route / elevationGainM：GPS 路徑是那天真的跑過的那條路，套到今天是假的。
    ///    • activeEnergyKcal：量出來的熱量，不是你打算做的事。
    ///    這幾個欄位都留給 WorkoutSession／WorkoutExercise 的預設值（nil／空陣列／0）。
    ///
    /// 每個動作也都會拿到新的 id——沿用舊 id 的話同一個 id 會同時存在於兩筆紀錄裡，
    /// ForEach 與各種以 id 比對的地方都會開始出怪事。
    ///
    /// [v25.552] 運動種類（sport）是「內容」，一起帶；每公里分段、路線、爬升、量到的大卡、暫停仍不帶。
    /// 複製出來的算手動補記（source = .manual），大卡照新的距離時間用 MET 表估好存回（約 xx 大卡）。
    private func duplicate(_ s: WorkoutSession) {
        var copy = WorkoutSession(
            date: Date(),
            title: s.title,
            exercises: s.exercises.map { e in
                WorkoutExercise(name: e.name, kind: e.kind,
                                reps: e.reps, sets: e.sets,
                                loadType: e.loadType, loadKg: e.loadKg,
                                distanceKm: e.distanceKm,
                                durationMinutes: e.durationMinutes,
                                note: e.note,
                                sport: e.sport)
            },
            durationMinutes: s.durationMinutes,
            place: s.place,
            note: s.note
        )
        copy.source = .manual
        WorkoutFacts.applyKcalEstimate(&copy, bodyWeightKg: bodyWeight)
        let saved = copy
        let store = lifeStore
        store.upsertWorkout(saved)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // 與編輯畫面存檔同一條路：使用者若開著 Apple 健康同步，新的一筆一樣寫回去
        Task { await WorkoutHealthWriter.push(saved, store: store) }

        copiedNoteTask?.cancel()
        let label = sessionTitle(saved)
        withAnimation(.easeOut(duration: 0.2)) {
            copiedNote = "已複製「\(label)」到現在，新的一筆排在清單最上面。"
        }
        copiedNoteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { copiedNote = nil }
        }
    }

    // MARK: 綜效曲線

    private var curveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("綜效曲線", count: curvePoints.count)
            Picker("模式", selection: $curveMode) {
                ForEach(CurveMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)

            if curveMode == .exercise {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(exerciseNames, id: \.self) { n in
                            chip(n, isSelected: selectedExercise == n) { selectedExercise = n }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HealthRange.allCases) { r in
                        chip(r.rawValue, isSelected: range == r) { range = r }
                    }
                }
                .padding(.vertical, 1)
            }

            if curvePoints.count >= 2 {
                chartBody
                    .frame(height: 210)
                Text(curveNote)
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(curveMode == .exercise && selectedExercise.isEmpty
                     ? "選一個動作看它的進步曲線"
                     : "這個條件下不足兩筆，換個期間或模式試試")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .onAppear { if selectedExercise.isEmpty { selectedExercise = exerciseNames.first ?? "" } }
    }

    private var curveNote: String {
        switch curveMode {
        case .volume:
            if bodyWeight == nil {
                return "訓練量＝總次數 × 負荷。目前健康檔案還沒有體重紀錄，「自身體重」的動作不計入總量——到醫療地圖補一筆體重就會納入。"
            }
            return "訓練量＝總次數 × 負荷；自身體重的動作以健康檔案最近體重 \(WorkoutExercise.kgText(bodyWeight ?? 0)) 計算。"
        case .reps:
            return "只算重量訓練的總次數（每組次數 × 組數），不受負荷影響。"
        case .exercise:
            return "同一個動作的每次表現：有負荷算訓練量、有氧算距離、其餘算總次數。"
        }
    }

    private var chartBody: some View {
        Chart {
            ForEach(curvePoints) { p in
                AreaMark(x: .value("日期", p.date, unit: .day), y: .value(curveUnit, p.value))
                    .foregroundStyle(LinearGradient(colors: [accent.opacity(0.20), accent.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("日期", p.date, unit: .day), y: .value(curveUnit, p.value))
                    .foregroundStyle(accent)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                PointMark(x: .value("日期", p.date, unit: .day), y: .value(curveUnit, p.value))
                    .foregroundStyle(accent)
                    .symbolSize(26)
            }
            if let sel = selectedPoint {
                RuleMark(x: .value("選取", sel.date, unit: .day))
                    .foregroundStyle(accent.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        selectionCard(sel)
                    }
                PointMark(x: .value("選取", sel.date, unit: .day), y: .value(curveUnit, sel.value))
                    .foregroundStyle(accent)
                    .symbolSize(80)
            }
        }
        .chartXSelection(value: $rawSelectedDate)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(axisText(v)) }
                }
            }
        }
    }

    private func selectionCard(_ p: CurvePoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.shortDate.string(from: p.date)).font(.caption2.weight(.bold))
            Text(axisText(p.value) + " " + curveUnit)
                .font(.caption.weight(.bold)).foregroundStyle(accent)
            Text(p.label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.25), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
        .frame(maxWidth: 180)
    }

    // MARK: 動作排行

    private struct ExerciseStat: Identifiable {
        let name: String
        let times: Int
        let sets: Int
        let reps: Int
        let volume: Double
        let best: String
        var id: String { name }
    }

    /// [v25.552] 用 statName 分組：有氧照運動種類（手錶的「走路」和 App 的「健走」同一列），重訓照動作名稱。
    /// 組數、次數只算重量訓練型態的（舊資料裡從重訓切成有氧、留著次數組數的不再被算進來）
    private var exerciseStats: [ExerciseStat] {
        var grouped: [String: [WorkoutExercise]] = [:]
        for s in sessions {
            for e in s.exercises {
                let n = statName(e)
                if !n.isEmpty { grouped[n, default: []].append(e) }
            }
        }
        return grouped.map { name, items in
            let strength = items.filter { $0.kind == .strength }
            let vol = items.compactMap { $0.volume(bodyWeightKg: bodyWeight) }.reduce(0, +)
            let bestLoad = strength.compactMap { $0.loadType == .weight ? $0.loadKg : nil }.max()
            let bestReps = strength.map(\.reps).max() ?? 0
            let bestDist = items.map(\.distanceKm).max() ?? 0
            var best = ""
            if let bl = bestLoad, bl > 0 { best = "最重 " + WorkoutExercise.kgText(bl) }
            else if bestDist > 0 { best = "最長 " + WorkoutFormat.km(bestDist) }
            else if bestReps > 0 { best = "單組最多 \(bestReps) 下" }
            return ExerciseStat(name: name, times: items.count,
                                sets: strength.reduce(0) { $0 + max(0, $1.sets) },
                                reps: strength.reduce(0) { $0 + $1.totalReps },
                                volume: vol, best: best)
        }
        .sorted { a, b in
            if a.times != b.times { return a.times > b.times }
            return a.name < b.name
        }
    }

    private var exerciseRanking: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("動作統計", count: exerciseStats.count)
            ForEach(exerciseStats) { st in
                Button {
                    curveMode = .exercise
                    selectedExercise = st.name
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.08)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(accent.opacity(0.20), lineWidth: 0.75))
                            Text("\(st.times)")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            // [v25.520] 動作名稱過長改一行跑馬燈（原本會折成多行）
                            MarqueeText(st.name).font(.subheadline.weight(.bold))
                            Text(statMeta(st))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if st.volume > 0 {
                            Text(volumeText(st.volume))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(accent)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
    }

    // MARK: 訓練紀錄

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("訓練紀錄", count: sessions.count)
            if let note = copiedNote {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(accent)
                    Text(note)
                        .font(.caption2.weight(.medium)).foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .transition(.opacity)
            }
            if sessions.isEmpty {
                emptyState
            } else {
                ForEach(sessions) { s in
                    sessionRow(s)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        // [v25.552] 刪除先問（以前一按就刪、沒有復原）。v2 只刪 LifeGood 這一筆；連 Apple 健康一起刪是 v4
        .alert(deleteTitle, isPresented: deleteBinding, presenting: deleteTarget) { s in
            Button("刪除", role: .destructive) { deleteNow(s) }
            Button("取消", role: .cancel) { }
        } message: { s in
            Text(deleteMessage(s))
        }
    }

    // MARK: 刪除確認（[v25.552]）

    /// 「刪除 10/15 跑步 5.2 公里？」
    private var deleteTitle: String {
        guard let s = deleteTarget else { return "" }
        return "刪除 " + WorkoutFormat.monthDay(s.date) + " " + sessionTitle(s) + distancePart(s) + "？"
    }

    /// 「 5.2 公里」；沒有距離是空的
    private func distancePart(_ s: WorkoutSession) -> String {
        let km = s.totalDistanceKm
        return km > 0 ? " " + WorkoutFormat.km(km) : ""
    }

    private func deleteMessage(_ s: WorkoutSession) -> String {
        s.healthKitUUID != nil
            ? "只刪 LifeGood 這一筆；Apple 健康裡的那一筆不會刪。"
            : "刪掉就找不回來了。"
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    /// 提示框關掉那一次畫面更新先過，下一輪主執行緒才寫 store
    private func deleteNow(_ s: WorkoutSession) {
        let store = lifeStore
        let id = s.id
        DispatchQueue.main.async { store.deleteWorkout(id: id) }
    }

    private func sessionRow(_ s: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(spacing: 1) {
                    Text(Self.dayOnly.string(from: s.date))
                        .font(.system(size: 15, weight: .black, design: .rounded))
                    Text(Self.monthOnly.string(from: s.date))
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .frame(width: 38)
                VStack(alignment: .leading, spacing: 2) {
                    // [v25.520] 訓練名稱過長改一行跑馬燈（原本會折成多行）
                    MarqueeText(sessionTitle(s)).font(.subheadline.weight(.bold))
                    let meta = sessionMeta(s)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let v = s.totalVolume(bodyWeightKg: bodyWeight), v > 0 {
                    Text(volumeText(v))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
                Menu {
                    Button("編輯") { editorRequest = WorkoutEditorRequest(session: s) }
                    Button("複製到現在") { duplicate(s) }
                    Divider()
                    Button("刪除", role: .destructive) { deleteTarget = s }   // [v25.552] 先問
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                }
            }
            ForEach(s.exercises) { e in
                HStack(spacing: 7) {
                    // [v25.552] 圖示照運動種類（健走是走路的人、騎車是單車、登山是登山的人）
                    Image(systemName: e.resolvedSport.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(e.kind == .strength ? accent : Color.blue)
                        .frame(width: 15)
                    // [v25.520] 動作名稱過長改一行跑馬燈（原本會折成多行）
                    MarqueeText(exerciseLabel(e))
                        .font(.caption.weight(.semibold))
                    Text(e.summary(bodyWeightKg: bodyWeight))
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer()
                }
                .padding(.leading, 46)
            }
            if !s.note.isEmpty {
                Text(s.note).font(.caption2).foregroundStyle(.secondary).padding(.leading, 46)
            }
            if let ex = s.firstRouteExercise {
                RouteMapView(route: ex.route, accent: accent)
                    .padding(.leading, 46)
                HStack(spacing: 8) {
                    ForEach(routeChips(s, ex)) { c in
                        routeChip(c.text, c.icon)
                    }
                    Spacer()
                }
                .padding(.leading, 46)
            } else if s.isLegacyRouteMissing {
                Text("這一趟是舊版記錄的，路線沒有存到；距離和時間大致是對的。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.leading, 46)
            }
            if s.healthKitUUID != nil {
                HStack(spacing: 4) {
                    Image(systemName: "heart.text.square.fill").font(.system(size: 9))
                    Text("已與 Apple 健康同步").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.pink.opacity(0.85))
                .padding(.leading, 46)
            }
            Divider()
        }
    }

    // MARK: 健康里程碑

    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("健康里程碑", count: healthMilestones.count)
            ForEach(healthMilestones) { m in
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.pink.opacity(0.14)).frame(width: 30, height: 30)
                        Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(.pink)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        // [v25.520] 里程碑標題過長改一行跑馬燈（原本會折成多行）
                        MarqueeText(m.title.isEmpty ? "未命名" : m.title).font(.subheadline.weight(.semibold))
                        Text(milestoneMeta(m))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
    }

    // MARK: 小元件

    /// [v25.552] 有路線那一趟的膠囊（一套寫法）：「5.2 公里」、「配速 6'11"」（騎車「時速 21.5」）、
    /// 「爬升 18 m」（只有 App 記、有路線的才知道；不到 10 公尺不顯示）、「402 大卡」／「約 340 大卡」
    private func routeChips(_ s: WorkoutSession, _ ex: WorkoutExercise) -> [ChipItem] {
        let sport = ex.resolvedSport
        var out: [ChipItem] = [ChipItem(text: WorkoutFormat.km(ex.distanceKm), icon: sport.icon)]
        if sport == .bike {
            if let v = WorkoutFormat.speedKmh(km: ex.distanceKm, minutes: ex.durationMinutes) {
                out.append(ChipItem(text: "時速 " + WorkoutFormat.speedNumber(v), icon: "speedometer"))
            }
        } else if let p = ex.paceMinPerKm {
            out.append(ChipItem(text: "配速 " + WorkoutFormat.pace(p), icon: "speedometer"))
        }
        if let c = WorkoutFacts.climb(ex, in: s), c >= 10 {
            out.append(ChipItem(text: "爬升 " + WorkoutFormat.climb(c), icon: "mountain.2.fill"))
        }
        if let k = WorkoutFacts.kcal(s, bodyWeightKg: bodyWeight) {
            out.append(ChipItem(text: WorkoutFormat.kcal(k.kcal, estimated: k.estimated), icon: "flame.fill"))
        }
        return out
    }

    private func routeChip(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(accent.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(accent.opacity(0.2), lineWidth: 0.6))
        .foregroundStyle(accent)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.4)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 15)
            Text(title).font(.subheadline.weight(.bold))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(accent.opacity(0.13), in: Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                .foregroundStyle(accent)
            Spacer()
        }
    }

    private func chip(_ text: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() }
        } label: {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(isSelected ? accent.opacity(0.16) : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(isSelected ? accent : Color.secondary)
                .overlay(Capsule().stroke(isSelected ? accent.opacity(0.3) : .clear, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    private func hintCard(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.bold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("還沒有訓練紀錄").font(.subheadline.weight(.semibold))
            Text("右上角「＋」補記一趟跑步、健走、騎車、登山或一次重訓；跑者圖示可以開始記錄，跑完路線會畫在這裡。")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // 下面三個副標都先在一般函式裡組好字串再交給 Text：
    // 在 ViewBuilder 內用 ?: 與 + 串接字串陣列很容易讓型別檢查逾時（見 v25.350）。
    private func statMeta(_ st: ExerciseStat) -> String {
        var parts: [String] = []
        if st.sets > 0 { parts.append("\(st.sets) 組") }
        if st.reps > 0 { parts.append("\(st.reps) 下") }
        if !st.best.isEmpty { parts.append(st.best) }
        return parts.joined(separator: "・")
    }

    /// [v25.552] 一套寫法：「河濱・32:10」、「38:40・約 120 大卡」、「健身房・45 分鐘・3 個動作・約 220 大卡」。
    /// 有氧寫移動時間「32:10」（以前「32 分鐘」砍掉秒）；重訓寫合計「45 分鐘」；兩個動作以上才寫「N 個動作」；
    /// 有路線的大卡在膠囊上，這裡不重複
    private func sessionMeta(_ s: WorkoutSession) -> String {
        var parts: [String] = []
        if !s.place.isEmpty { parts.append(s.place) }
        if s.primarySport == .strength {
            if s.durationMinutes > 0 { parts.append(WorkoutFormat.total(minutes: s.durationMinutes)) }
        } else {
            let m = WorkoutFacts.movingMinutes(s)
            if m > 0 { parts.append(WorkoutFormat.clock(minutes: m)) }
        }
        if s.exercises.count > 1 { parts.append("\(s.exercises.count) 個動作") }
        if s.firstRouteExercise == nil, let k = WorkoutFacts.kcal(s, bodyWeightKg: bodyWeight) {
            parts.append(WorkoutFormat.kcal(k.kcal, estimated: k.estimated))
        }
        return parts.joined(separator: "・")
    }

    private func milestoneMeta(_ m: LifeMilestone) -> String {
        var parts: [String] = [Self.shortDate.string(from: m.date)]
        if !m.note.isEmpty { parts.append(m.note) }
        return parts.joined(separator: "・")
    }

    private func volumeText(_ v: Double) -> String {
        if v >= 10000 { return String(format: "%.1f 噸", v / 1000) }
        return String(format: "%.0f kg", v)
    }
    private func axisText(_ v: Double) -> String {
        if curveUnit == "公斤" && v >= 10000 { return String(format: "%.1f 噸", v / 1000) }
        return v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    // [v25.552] 日期固定西曆＋zh_TW：手機設民國曆不會變「115/10/12」
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "yyyy/M/d"
        return f
    }()
    static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "d"
        return f
    }()
    static let monthOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M月"
        return f
    }()
}
