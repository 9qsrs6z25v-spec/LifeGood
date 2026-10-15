import SwiftUI

// MARK: - 健康頁的看板、目標格、開始列、記錄中條、每週目標小表單（v25.553，健康 v3；health/judge.md §3.1–3.3）
//
// 主控先放好型別與 init（G4 的 HealthView 照這幾個簽章呼叫）；長相由 G1 照 build/v3/brief.md §G1 實作。
// 資料都在 HealthPageData（Models/HealthPageData.swift，主控寫好）：這裡只畫，不算。
//
// • HealthBoard：MoneyBoardHeader（band 118、風景 .riverside）＋看板下的目標格（或一行「設一個每週目標 ›」）與膠囊。
//   外框照 VehicleCardBoard 自己組（MoneyBoardChrome＋圓角讀 HeroCard.health）：頭部要蓋成一個 VoiceOver 元素唸資料端組好的那一句。
// • HealthLiveStrip：⓪ 記錄中條。自己看 RunTracker（只有這一條每秒重畫，整頁不重算）；沒在記錄就什麼都不畫。
// • HealthStartRow：② 開始列（大綠鈕＋三顆小膠囊＋一句灰字；Mac 上換一行字）。
// • HealthGoalSheet：每週目標小表單（5～100 公里、5 公里一格的轉盤＋「不設目標」）。
//
// 左右 16pt：HealthBoard、HealthStartRow 不含（照 VehicleCardBoard，呼叫端加）；HealthLiveStrip 自己含（釘在 safeAreaInset 裡）。
// 版面照樣稿①-1／①-3（看板、開始列）、③-A1～A4（四種看板）、③-C6（記錄中條）。

// MARK: - ① 看板

/// ① 看板
struct HealthBoard: View {
    let data: HealthPageData
    /// 點目標格（看板上唯一能按的地方）：打開每週目標小表單。nil＝不能點
    var onGoalTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    /// 只讀「圓角」（同 MoneyBoardCard／VehicleCardBoard：看板不吃英雄卡的漸層與 KPI 樣式）
    @ObservedObject private var heroStyle = HeroStyleStore.shared

    init(data: HealthPageData, onGoalTap: (() -> Void)? = nil) {
        self.data = data
        self.onGoalTap = onGoalTap
    }

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let corner = CGFloat(heroStyle.value(.corner, .health))
        VStack(alignment: .leading, spacing: 0) {
            header(pal)
            if hasBelow {
                below(pal)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
        }
        .modifier(MoneyBoardChrome(pal: pal, corner: corner))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// 只有重訓：沒有目標格也沒有提示列，膠囊也可能是空的 → 整塊不畫（不留 24pt 空白）
    private var hasBelow: Bool {
        data.goal != nil || data.goalPrompt != nil || !data.chips.isEmpty
    }

    private func header(_ pal: TripBoardPalette) -> some View {
        let b = data.board
        let tint: Color? = b.capsuleTone == MoneyTone.neutral ? nil : b.capsuleTone.color(pal)
        let line: Text? = b.line.runs.isEmpty ? nil : FinanceLineText.text(b.line, pal: pal)
        return MoneyBoardHeader(
            date: b.date,
            dateIcon: b.dateIcon,
            capsule: b.capsule,
            capsuleIcon: b.capsuleIcon,
            capsuleTint: tint,
            label: b.label,
            big: b.big,
            line: line,
            greeting: b.greeting,
            scene: .riverside(data.scene),
            band: 118,
            seed: b.seed)
            // 整個頭部一個 VoiceOver 元素，唸資料端組好的那一句（風景本來就 accessibilityHidden）
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(b.accessibilityText)
    }

    private func below(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let g = data.goal {
                goalCell(g, pal: pal)
            }
            if let p = data.goalPrompt {
                promptRow(p, pal: pal)
            }
            if !data.chips.isEmpty {
                MoneyBoardChips(chips: data.chips, pal: pal)
            }
        }
    }

    /// 目標格：看板上唯一能按的地方（onGoalTap 是 nil 就不包 Button）
    @ViewBuilder
    private func goalCell(_ g: HealthGoalData, pal: TripBoardPalette) -> some View {
        if let onGoalTap {
            Button(action: onGoalTap) {
                HealthGoalCell(goal: g, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下改每週目標")
        } else {
            HealthGoalCell(goal: g, pal: pal)
        }
    }

    /// 沒設目標：一行「上週跑了 13.3 公里」＋右邊藍字「設一個每週目標 ›」
    @ViewBuilder
    private func promptRow(_ p: HealthGoalPrompt, pal: TripBoardPalette) -> some View {
        if let onGoalTap {
            Button(action: onGoalTap) {
                HealthGoalPromptRow(prompt: p, pal: pal)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下設定每週目標")
        } else {
            HealthGoalPromptRow(prompt: p, pal: pal)
        }
    }
}

/// 目標格：「這週目標 20 公里」右「73%」／運動色漸層進度條（條頭運動圖示）／「還差 5.4 公里・剩 4 天」
private struct HealthGoalCell: View {
    let goal: HealthGoalData
    let pal: TripBoardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow
            bar
                .frame(height: 22)
            Text(goal.detail)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(detailColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(goal.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(goal.percentText)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(percentColor)
                .lineLimit(1)
        }
    }

    private var bar: some View {
        let theme = MoneyArtTheme.of(goal.sport)
        return TripBoardProgressBar(fraction: goal.fraction,
                                    icon: goal.icon,
                                    colors: [theme.topColor, theme.bottomColor],
                                    track: pal.progressTrack,
                                    iconColor: WorkoutPalette.sport(goal.sport, dark: pal.dark),
                                    halo: pal.progressHalo)
    }

    /// 達標：百分比、第二行用「好」的綠（樣稿③-A3「103%」「達標！多跑了 0.6 公里」）
    private var percentColor: Color {
        goal.reached ? MoneyTone.good.color(pal) : pal.ink
    }

    private var detailColor: Color {
        goal.reached ? MoneyTone.good.color(pal) : pal.label
    }

    /// 「這週目標 20 公里，73%，還差 5.4 公里・剩 4 天」
    private var spoken: String {
        goal.title + "，" + goal.percentText + "，" + goal.detail
    }
}

/// 沒設目標那一行（整行可以按）
private struct HealthGoalPromptRow: View {
    let prompt: HealthGoalPrompt
    let pal: TripBoardPalette

    var body: some View {
        HStack(spacing: 8) {
            Text(prompt.text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(pal.label)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(actionText)
                .font(.footnote.weight(.bold))
                .foregroundStyle(pal.hint)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prompt.text + "，" + prompt.action)
    }

    private var actionText: String { prompt.action + " ›" }
}

// MARK: - ⓪ 記錄中條

/// ⓪ 記錄中條（釘在頁面最上面，safeAreaInset(edge: .top)）
struct HealthLiveStrip: View {
    /// 點了：回到跑步畫面
    let onOpen: () -> Void

    /// 整頁只有這個 view 看記錄器（距離、時間每秒變，只有這一條重畫）；不要把 tracker 傳出去、不在這裡寫任何 store
    @ObservedObject private var tracker = RunTracker.shared
    @Environment(\.colorScheme) private var scheme

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
    }

    var body: some View {
        if tracker.isActive {
            strip(TripBoardPalette(scheme))
        }
    }

    private func strip(_ pal: TripBoardPalette) -> some View {
        Button(action: onOpen) {
            stripBody(pal)
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel(spoken)
        .accessibilityHint("點兩下回到跑步畫面")
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        // 底下的卡片捲上來時從這一條後面過去，不從縫裡露出來
        .background(Color(.systemGroupedBackground))
    }

    private func stripBody(_ pal: TripBoardPalette) -> some View {
        HStack(spacing: 12) {
            TripBoardIconBadge(icon: sport.icon, colors: badgeColors, diameter: 34, dark: pal.dark)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(titleColor(pal))
                    .lineLimit(1)
                Text(detailText)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(detailColor(pal))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("回到跑步 ›")
                .font(.footnote.weight(.bold))
                .foregroundStyle(pal.hint)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TripBoardCellChrome(pal: pal))
        .contentShape(Rectangle())
    }

    // MARK: 字（先在這裡組好，body 不寫長運算式）

    private var sport: WorkoutSport { WorkoutSport(tracker.sport) }

    private var isPaused: Bool { tracker.phase == .paused }

    /// 「晨跑・跑步中」「晚走・健走中」「晨騎・騎車中」；登山名字本身就是「登山」：「登山中」；暫停「晨跑・已暫停」「登山・已暫停」
    private var titleText: String {
        let s = sport
        if s == .hike {
            return isPaused ? "登山・已暫停" : "登山中"
        }
        let name = WorkoutFacts.timeOfDayName(s, start: tracker.activeStartedAt ?? Date())
        if isPaused { return name + "・已暫停" }
        return name + "・" + s.displayName + "中"
    }

    private var kmText: String {
        WorkoutFormat.preciseKmNumber(tracker.distanceMeters / 1000, sport: sport)
    }

    /// 「3.42 公里・21:05」
    private var detailText: String {
        kmText + " 公里・" + WorkoutFormat.clock(seconds: tracker.elapsed.rounded(.down))
    }

    /// VoiceOver：「晨跑・跑步中，3.42 公里，21 分 05 秒」
    private var spoken: String {
        titleText + "，" + kmText + " 公里，" + spokenTime
    }

    private var spokenTime: String {
        let total = WorkoutFormat.wholeSeconds(tracker.elapsed.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = String(format: "%02d", total % 60)
        if h > 0 { return "\(h) 小時 \(m) 分 \(sec) 秒" }
        return "\(m) 分 \(sec) 秒"
    }

    /// 運動色的圓；暫停變灰
    private var badgeColors: [Color] {
        if isPaused { return [Color(tb: 0xC2C6D2), Color(tb: 0x8A92A6)] }
        let theme = MoneyArtTheme.of(sport)
        return [theme.topColor, theme.bottomColor]
    }

    /// 記錄中：提示藍（TripBoardPalette.notice(.info) 的字色，樣稿③-C6）；暫停：灰
    private func titleColor(_ pal: TripBoardPalette) -> Color {
        isPaused ? pal.label : pal.notice(.info).text
    }

    private func detailColor(_ pal: TripBoardPalette) -> Color {
        isPaused ? Color.secondary : pal.ink
    }
}

// MARK: - ② 開始列

/// ② 開始列（記錄中不出現：HealthView 不放它）
struct HealthStartRow: View {
    let data: HealthStartData
    /// 按了哪一種（大鈕是 data.sport，小膠囊是 data.others 裡的那一種）
    let onStart: (WorkoutSport) -> Void

    init(data: HealthStartData, onStart: @escaping (WorkoutSport) -> Void) {
        self.data = data
        self.onStart = onStart
    }

    var body: some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            macNote
        } else {
            VStack(alignment: .leading, spacing: 10) {
                startButton
                bottomRow
            }
        }
    }

    /// Mac 上沒有開始列（不能記路線），換一行灰字
    private var macNote: some View {
        Text("跑步要用 iPhone 記錄；iPhone 記的每一趟都會出現在這裡。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 全寬綠鈕「▶ 開始跑步」（高 54、綠 1F9D57；圓角照樣稿①-1 用膠囊形）
    private var startButton: some View {
        Button {
            onStart(data.sport)
        } label: {
            Label(startTitle, systemImage: "play.fill")
                .font(.headline.weight(.heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background { startPill }
                .contentShape(Capsule())
        }
        .buttonStyle(MoneyPressStyle())
    }

    private var startTitle: String { "開始" + data.sport.displayName }

    /// 綠色膠囊底＋淡淡的綠影子（影子只掛在底上：掛在整顆鈕上，白字也會拖一圈綠影子變糊）
    private var startPill: some View {
        Capsule()
            .fill(WorkoutPalette.go)
            .shadow(color: WorkoutPalette.go.opacity(0.28), radius: 8, x: 0, y: 4)
    }

    /// footnote 的一個中文字寬（跟著動態字級放大），估句子要多寬用
    @ScaledMetric(relativeTo: .footnote) private var em: CGFloat = 13

    /// 一句灰字＋右邊三顆小膠囊。ViewThatFits 照順序挑第一個放得下的：
    /// ① 句子一行、膠囊在右（樣稿①-1）；② 句子折成兩行、膠囊還在右（SE 343pt 的「再跑 5.4 公里這週就達標」）；
    /// ③ 句子在上、膠囊掉到下一行（字放大，或「上一趟：10/12 06:10・河濱晨跑 5.2 公里」這種長句）。
    /// ② 的句子欄至少要有「半句＋2.5 個字」寬才選它，長句不會被截成「…」。
    @ViewBuilder
    private var bottomRow: some View {
        if data.sentence.isEmpty {
            chipFlow
        } else {
            ViewThatFits(in: .horizontal) {
                oneLineRow
                twoLineRow
                stackedRow
            }
        }
    }

    private var oneLineRow: some View {
        HStack(alignment: .center, spacing: 8) {
            sentence
            Spacer(minLength: 6)
            chipRow
                .fixedSize()
        }
    }

    private var twoLineRow: some View {
        HStack(alignment: .center, spacing: 8) {
            sentence
                .frame(idealWidth: twoLineWidth, maxWidth: .infinity, alignment: .leading)
            chipRow
                .fixedSize()
        }
    }

    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sentence
                .frame(maxWidth: .infinity, alignment: .leading)
            chipFlow
        }
    }

    /// 句子折兩行時那一欄要多寬：估整句寬（中文字 1 個字寬、英數空白 0.56）的一半＋2.5 個字（斷行留的空），最少 110
    private var twoLineWidth: CGFloat {
        var units: CGFloat = 0
        for ch in data.sentence.unicodeScalars {
            units += ch.value < 0x80 ? 0.56 : 1
        }
        return max(110, (units / 2 + 2.5) * em)
    }

    private var sentence: some View {
        Text(data.sentence)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var chipFlow: some View {
        ChipFlowLayout(spacing: 6) {
            ForEach(data.others) { s in
                chip(s)
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(data.others) { s in
                chip(s)
            }
        }
    }

    private func chip(_ s: WorkoutSport) -> some View {
        Button {
            onStart(s)
        } label: {
            Label(s.displayName, systemImage: s.icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel("開始" + s.displayName)
    }
}

// MARK: - 每週目標小表單

/// 每週目標小表單（HealthView 用 .sheet(item:) 打開、最外層 .appStores()）。
/// 按「儲存」或「不設目標」：先 dismiss()，下一輪主執行緒才呼叫 onSave（照 WorkoutEditorView.save 的寫法）；
/// 呼叫端的 onSave 直接寫 lifeStore.setWeeklyGoal(_:for:)
struct HealthGoalSheet: View {
    let suggestion: HealthGoalSuggestion
    /// 公里（5～100）；「不設目標」傳 nil
    let onSave: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    /// 轉盤停在哪（5 的倍數，5～100）
    @State private var km: Int

    init(suggestion: HealthGoalSuggestion, onSave: @escaping (Double?) -> Void) {
        self.suggestion = suggestion
        self.onSave = onSave
        // 有目標：目前的目標四捨五入到 5 的倍數；沒有：建議值（資料端已是 5 的倍數）。都夾在 5～100
        let raw = suggestion.current ?? suggestion.suggestedKm
        let five = raw.isFinite ? Int((min(max(raw, 0), 1_000) / 5).rounded()) * 5 : 20
        _km = State(initialValue: min(100, max(5, five)))
    }

    /// 轉盤的選項：5、10、…、100
    private static let choices: [Int] = Array(stride(from: 5, through: 100, by: 5))

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    picker
                } footer: {
                    Text(suggestion.hint)
                }
                if suggestion.current != nil {
                    Section {
                        Button("不設目標", role: .destructive) {
                            finish(nil)
                        }
                    }
                }
            }
            .navigationTitle(suggestion.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        finish(Double(km))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var picker: some View {
        Picker("每週", selection: $km) {
            ForEach(Self.choices, id: \.self) { v in
                Text("\(v) 公里").tag(v)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
    }

    /// 先關掉，下一輪主執行緒才交出去寫 store（坑：dismiss 跟寫 store 同一輪，sheet 收起來那一下會跟整頁重算搶）
    private func finish(_ value: Double?) {
        dismiss()
        let handler = onSave
        DispatchQueue.main.async {
            handler(value)
        }
    }
}
