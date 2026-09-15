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

struct HealthView: View {
    @EnvironmentObject var lifeStore: LifeStore

    @StateObject private var health = HealthKitManager.shared
    @StateObject private var tracker = RunTracker.shared

    @State private var showEditor = false
    @State private var showRun = false
    @State private var editing: WorkoutSession?
    @State private var syncing = false
    @State private var syncMessage: String?
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

    private var thisMonth: [WorkoutSession] {
        let cal = Calendar.current
        return sessions.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    private var monthVolume: Double {
        thisMonth.compactMap { $0.totalVolume(bodyWeightKg: bodyWeight) }.reduce(0, +)
    }

    /// 從本週往回數，連續有訓練的週數
    private var streakWeeks: Int {
        let cal = Calendar.current
        let weeks = Set(sessions.compactMap { s -> Date? in
            cal.dateInterval(of: .weekOfYear, for: s.date)?.start
        })
        guard var cursor = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        // 這週還沒練不算中斷，從上週開始數
        if !weeks.contains(cursor) {
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = prev
        }
        var n = 0
        while weeks.contains(cursor) {
            n += 1
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
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
                s.exercises.filter { $0.name == selectedExercise }.compactMap { e -> CurvePoint? in
                    if let v = e.volume(bodyWeightKg: bodyWeight), v > 0 {
                        return CurvePoint(date: s.date, value: v, label: e.summary(bodyWeightKg: bodyWeight))
                    }
                    if e.kind == .cardio, e.distanceKm > 0 {
                        return CurvePoint(date: s.date, value: e.distanceKm, label: e.summary(bodyWeightKg: bodyWeight))
                    }
                    if e.totalReps > 0 {
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
            guard let first = lifeStore.workoutHistory(exerciseName: selectedExercise).first?.exercise else { return "" }
            if first.kind == .cardio { return "公里" }
            return first.loadType == .none ? "下" : "公斤"
        }
    }

    private var exerciseNames: [String] { lifeStore.workoutExerciseNames() }

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
                    Button { editing = nil; showEditor = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showEditor) {
                WorkoutEditorView(session: editing) { saved in
                    lifeStore.upsertWorkout(saved)
                    Task { await pushToHealthKit(saved) }
                }
                .environmentObject(lifeStore)
            }
            .sheet(isPresented: $showRun) {
                RunTrackingView { session in
                    lifeStore.upsertWorkout(session)
                    Task { await pushToHealthKit(session) }
                }
                .environmentObject(lifeStore)
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
                    Text("最近 " + Self.shortDate.string(from: last.date))
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
                    Text(tracker.phase == .paused ? "已暫停" : "記錄中")
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

    /// 橫幅上的即時數字：字串先組好再進 Text
    private var liveText: String {
        var parts: [String] = []
        parts.append(RunTrackingView.distanceText(tracker.distanceMeters) + " 公里")
        parts.append(RunTrackingView.clockText(tracker.elapsed))
        return parts.joined(separator: "・")
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
                note: w.isCardio ? "" : "來自 Apple 健康，組數次數請自行補上")
            let session = WorkoutSession(
                date: w.start, title: w.activityName, exercises: [ex],
                durationMinutes: minutes, place: "", note: "",
                healthKitUUID: w.uuid, activeEnergyKcal: w.energyKcal)
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

    /// 把新記的訓練寫回 Apple 健康（只有打開聯動、而且還沒寫過的才寫）
    private func pushToHealthKit(_ session: WorkoutSession) async {
        guard hkEnabled, health.isAvailable, session.healthKitUUID == nil else { return }
        guard let uuid = await health.saveWorkout(session, bodyWeightKg: bodyWeight) else { return }
        var s = session
        s.healthKitUUID = uuid
        lifeStore.upsertWorkout(s)
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

    private var exerciseStats: [ExerciseStat] {
        var grouped: [String: [WorkoutExercise]] = [:]
        for s in sessions { for e in s.exercises where !e.name.isEmpty { grouped[e.name, default: []].append(e) } }
        return grouped.map { name, items in
            let vol = items.compactMap { $0.volume(bodyWeightKg: bodyWeight) }.reduce(0, +)
            let bestLoad = items.compactMap { $0.loadType == .weight ? $0.loadKg : nil }.max()
            let bestReps = items.map(\.reps).max() ?? 0
            let bestDist = items.map(\.distanceKm).max() ?? 0
            var best = ""
            if let bl = bestLoad, bl > 0 { best = "最重 " + WorkoutExercise.kgText(bl) }
            else if bestDist > 0 { best = String(format: "最長 %.2f 公里", bestDist) }
            else if bestReps > 0 { best = "單組最多 \(bestReps) 下" }
            return ExerciseStat(name: name, times: items.count,
                                sets: items.reduce(0) { $0 + max(0, $1.sets) },
                                reps: items.reduce(0) { $0 + $1.totalReps },
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
                            Text(st.name).font(.subheadline.weight(.bold))
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
                    Text(s.displayTitle).font(.subheadline.weight(.bold))
                    Text(sessionMeta(s))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let v = s.totalVolume(bodyWeightKg: bodyWeight), v > 0 {
                    Text(volumeText(v))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
                Menu {
                    Button("編輯") { editing = s; showEditor = true }
                    Button("刪除", role: .destructive) { lifeStore.deleteWorkout(id: s.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                }
            }
            ForEach(s.exercises) { e in
                HStack(spacing: 7) {
                    Image(systemName: e.kind.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(e.kind == .strength ? accent : Color.blue)
                        .frame(width: 15)
                    Text(e.name.isEmpty ? e.kind.rawValue : e.name)
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
                    routeChip(String(format: "%.2f 公里", ex.distanceKm), "figure.run")
                    if let p = ex.paceMinPerKm {
                        routeChip("配速 " + RunTrackingView.paceText(p), "speedometer")
                    }
                    if ex.elevationGainM >= 5 {
                        routeChip(String(format: "爬升 %.0f m", ex.elevationGainM), "mountain.2.fill")
                    }
                    if s.activeEnergyKcal > 0 {
                        routeChip(String(format: "%.0f 大卡", s.activeEnergyKcal), "flame.fill")
                    }
                    Spacer()
                }
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
                        Text(m.title.isEmpty ? "未命名" : m.title).font(.subheadline.weight(.semibold))
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
            Text("右上角的「＋」記下一次訓練：先給這次訓練一個名字（例如胸推日），再加動作——伏地挺身 20 下 3 組、自身體重。記滿兩次就會出現綜效曲線。")
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

    private func sessionMeta(_ s: WorkoutSession) -> String {
        var parts: [String] = []
        if !s.place.isEmpty { parts.append(s.place) }
        if s.durationMinutes > 0 { parts.append(WorkoutExercise.minuteText(s.durationMinutes)) }
        parts.append("\(s.exercises.count) 個動作")
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

    static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
    static let dayOnly: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
    static let monthOnly: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M月"; return f
    }()
}
