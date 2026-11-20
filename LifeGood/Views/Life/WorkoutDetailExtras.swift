import SwiftUI
import Charts

// MARK: - 成果頁的兩區（v25.558，健康 v7b；build/v7b/brief.md §6 G4）
//
// 主控先放好空殼（兩個型別、簽章），G4 填內容；只在 WorkoutDetailView 用，G4 可以改簽章（改了寫進回報）。
//
// • WorkoutDetailHeartSection：⑦ 心率（judge §5.2 ⑦，⑥ 高度和 ⑧ Apple 健康中間）。資料由 WorkoutDetailView 自己的
//   .task(id:) 讀（HealthKitManager.fetchHeartRates → WorkoutFacts.heartSummary；健康頁的 Apple 健康開關開著、裝置能用「健康」才讀，
//   不跳權限框），讀到才把 summary 傳進來（沒有就整區不畫：成果頁的 VStack(spacing: 22) 不會多一格空白）。
//   這裡只畫：「平均 152・最高 171」＋小折線（Charts，同高度那張的寫法）。樣本只放記憶體（不存、不進 iCloud、不進備份）。
// • WorkoutMilestoneCard：這一趟達成的運動里程碑（WorkoutCardData.milestones）＋「要記成人生里程碑嗎？」。
//   剛跑完（justFinished）問一次：〔記成人生里程碑〕〔不用〕；一般模式不問，只有一顆〔記成人生里程碑〕或「已記在人生里程碑」。
//   〔記成人生里程碑〕要訂閱（同「＋」；沒訂閱叫 onNeedPremium）→ 有輸入框的提示框先讓你改字 →〔儲存〕在下一個 runloop 才 store.add
//   （WorkoutFacts.lifeMilestone：健康類、日期＝那一趟、備註預設、sourceKey＝key）。沒有里程碑：整區不畫。
//
// [v25.558] 健康 v7b（build/v7b/brief.md §6 G4-3、G4-4）：G4 填好內容，簽章跟主控空殼一樣（沒改）。
// • 心率：FinanceCardHeader「心率｜次/分」＋白卡：一句「平均 **152**・最高 **171**」（數字是 summary.average／maximum，
//   跟 summary.text 同一句；FinanceSentence 同高度那一句的字級）→ 高 90 的小折線（LineMark、monotone、心率紅 D93545，
//   座標軸照高度那張：橫軸分鐘約 5 格、縱軸左邊約 3 格；縱軸 summary.lowBpm～highBpm，萬一上下顛倒也不會閃退）→
//   灰字「來自 Apple 健康（Apple Watch 或心率裝置量的）；iPhone 自己量不到心率。」。白卡整塊一個 VoiceOver 元素（summary.spoken）。
// • 達成里程碑：FinanceCardHeader「達成里程碑」＋白卡，一個里程碑一列（圖示圓同上面「這趟的收穫」：那一種運動的主題色、
//   連續／次數綠；白色 flag.checkered）＋粗體標題＋小字備註，下面依狀態：記過「✓ 已記在人生里程碑」（綠字）／剛跑完一句問話＋
//   〔記成人生里程碑〕（綠底白字膠囊，FinanceGreenPill 的 177A44）〔不用〕（灰字；只在這一頁收起來）／一般模式一顆綠字〔記成人生里程碑〕。
//   記過沒看 WorkoutFacts.recordedMilestone（sourceKey，或還沒更新的 iPad 存過時「健康類、同一天、同標題或備註」）。
//   提示框整個 view 只有這一個 .alert（掛在白卡上）；〔儲存〕下一個 runloop 再查一次記過沒才 store.add（按兩次不會記兩筆）。
//   字級封頂 xxxLarge（兩顆按鈕一列放得下，同每公里那張）。

// MARK: - ⑦ 心率

/// [健康 v7b] 成果頁 ⑦ 心率（G4 寫）：summary 由 WorkoutDetailView 讀好傳進來
struct WorkoutDetailHeartSection: View {
    let summary: WorkoutHeartSummary

    @Environment(\.colorScheme) private var scheme

    /// 最下面那一行灰字
    static let footnote = "來自 Apple 健康（Apple Watch 或心率裝置量的）；iPhone 自己量不到心率。"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "心率", trailing: "次/分")
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceSentence(line: line, pal: TripBoardPalette(scheme))
            WorkoutDetailHeartChart(summary: summary, color: lineColor)
            Text(Self.footnote)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FinanceCardChrome())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.spoken)
    }

    /// 「平均 **152**・最高 **171**」（同 summary.text；數字粗體、一般字色）
    private var line: FinanceLine {
        FinanceLine(runs: [FinanceRun(text: "平均 "),
                           FinanceRun(text: "\(summary.average)", bold: true),
                           FinanceRun(text: "・最高 "),
                           FinanceRun(text: "\(summary.maximum)", bold: true)])
    }

    /// 心率紅（同健康頁健康里程碑的醫療紅；淺深同一色）
    private var lineColor: Color {
        Color(tb: 0xD93545)
    }
}

/// 心率小折線（同高度那張的寫法：Chart＋座標軸），高 90。VoiceOver 由外面的白卡唸
private struct WorkoutDetailHeartChart: View {
    let summary: WorkoutHeartSummary
    let color: Color

    var body: some View {
        chart
            .chartYScale(domain: yDomain)
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 90)
            .accessibilityHidden(true)
    }

    /// 縱軸（summary 已經取到 5 的倍數）；上下顛倒或一樣時撐開一點（ClosedRange 下限大於上限會閃退）
    private var yDomain: ClosedRange<Double> {
        let lo = min(summary.lowBpm, summary.highBpm)
        let hi = max(summary.lowBpm, summary.highBpm)
        return lo...max(hi, lo + 5)
    }

    /// 橫軸：開始到結束幾分鐘（至少 1）
    private var xDomain: ClosedRange<Double> {
        let m = summary.minutes.isFinite ? summary.minutes : 1
        return 0...max(1, m)
    }

    private var chart: some View {
        Chart {
            ForEach(summary.points) { p in
                LineMark(x: .value("分鐘", p.minute), y: .value("心率", p.bpm))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
        }
    }
}

// MARK: - 達成里程碑

/// [健康 v7b] 成果頁：這一趟達成的運動里程碑＋「要記成人生里程碑嗎？」（G4 寫）
struct WorkoutMilestoneCard: View {
    let milestones: [WorkoutMilestone]
    /// 剛跑完：問一次（〔記成人生里程碑〕〔不用〕）；一般模式不問
    let justFinished: Bool
    /// 沒訂閱按〔記成人生里程碑〕：成果頁的付費說明框（WorkoutDetailView 的 showPremiumAlert）
    let onNeedPremium: () -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.colorScheme) private var scheme
    /// 〔不用〕收起來的（key；只在這一頁，下次打開成果頁是一般模式、不再問）
    @State private var dismissed: Set<String> = []
    /// 提示框正在記的那一個
    @State private var editing: WorkoutMilestone?
    /// 提示框的字（預設＝里程碑標題，可以改）
    @State private var draft = ""
    @State private var asking = false

    /// 剛跑完那一句問話
    static let askText = "要記成人生里程碑嗎？會出現在履歷、人生總覽和我的行事曆。"
    /// 提示框說明的第二行
    static let whereText = "會出現在履歷、人生總覽和我的行事曆。"
    /// 綠底膠囊的綠（同 FinanceGreenPill）
    static let pillGreen = Color(tb: 0x177A44)

    var body: some View {
        if !visible.isEmpty {
            content(TripBoardPalette(scheme))
                .alert("記成人生里程碑", isPresented: $asking) {
                    TextField("例：第一次跑完 10 公里", text: $draft)
                    Button("儲存") { save() }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(messageText)
                }
        }
    }

    // MARK: 資料

    /// 還沒按〔不用〕的（照達成順序）
    private var visible: [WorkoutMilestone] {
        milestones.filter { !dismissed.contains($0.key) }
    }

    /// 提示框說明：「2026/8/23・10.2 公里・1:05:00」＋換行「會出現在履歷、人生總覽和我的行事曆。」
    private var messageText: String {
        guard let m = editing else { return Self.whereText }
        var head = WorkoutFormat.date(m.date)
        if !m.note.isEmpty { head += "・" + m.note }
        return head + "\n" + Self.whereText
    }

    /// 記過了沒（sourceKey；或還沒更新的 iPad 存過：健康類、同一天、同標題或備註）
    private func isRecorded(_ m: WorkoutMilestone) -> Bool {
        WorkoutFacts.recordedMilestone(m, in: lifeStore.milestones) != nil
    }

    /// VoiceOver：「第一次跑完 10 公里，10.2 公里・1:05:00，還沒記成人生里程碑」
    private func spoken(_ m: WorkoutMilestone, recorded: Bool) -> String {
        var parts: [String] = [m.title]
        if !m.note.isEmpty { parts.append(m.note) }
        parts.append(recorded ? "已記在人生里程碑" : "還沒記成人生里程碑")
        return parts.joined(separator: "，")
    }

    /// 圖示圓：同「這趟的收穫」那一列（那一種運動的主題色；連續、次數綠）
    private func badgeColors(_ m: WorkoutMilestone) -> [Color] {
        guard let sport = m.sport else { return [Color(tb: 0x5BD99A), Color(tb: 0x1F9D57)] }
        let t = MoneyArtTheme.of(sport)
        return [t.topColor, t.bottomColor]
    }

    // MARK: 畫

    private func content(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "達成里程碑")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { i, m in
                    if i > 0 {
                        Divider().padding(.leading, 58)
                    }
                    row(m, pal: pal)
                }
            }
            .modifier(FinanceCardChrome())
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func row(_ m: WorkoutMilestone, pal: TripBoardPalette) -> some View {
        let recorded = isRecorded(m)
        return HStack(alignment: .top, spacing: 12) {
            TripBoardIconBadge(icon: m.icon, colors: badgeColors(m), diameter: 32, dark: pal.dark)
            VStack(alignment: .leading, spacing: 8) {
                texts(m, recorded: recorded)
                status(m, recorded: recorded, pal: pal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// 粗體標題＋小字備註（一個 VoiceOver 元素，連「記過沒」一起唸）
    private func texts(_ m: WorkoutMilestone, recorded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(m.title)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !m.note.isEmpty {
                Text(m.note)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(m, recorded: recorded))
    }

    /// 記過「已記在人生里程碑」；沒記、剛跑完：問一次；沒記、一般模式：一顆綠字〔記成人生里程碑〕
    @ViewBuilder
    private func status(_ m: WorkoutMilestone, recorded: Bool, pal: TripBoardPalette) -> some View {
        if recorded {
            recordedLabel(pal)
        } else if justFinished {
            askBlock(m, pal: pal)
        } else {
            recordButton(m, pal: pal, filled: false)
        }
    }

    private func recordedLabel(_ pal: TripBoardPalette) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
            Text("已記在人生里程碑")
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(MoneyTone.good.color(pal))
        .accessibilityHidden(true)
    }

    /// 剛跑完：一句問話＋〔記成人生里程碑〕〔不用〕
    private func askBlock(_ m: WorkoutMilestone, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.askText)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                recordButton(m, pal: pal, filled: true)
                skipButton(m, pal: pal)
            }
        }
    }

    /// 〔記成人生里程碑〕：filled＝綠底白字（剛跑完問的那一次）；不然綠字淡綠底
    private func recordButton(_ m: WorkoutMilestone, pal: TripBoardPalette, filled: Bool) -> some View {
        Button {
            ask(m)
        } label: {
            pill("記成人生里程碑", filled: filled, pal: pal)
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel("記成人生里程碑：" + m.title)
    }

    private func pill(_ title: String, filled: Bool, pal: TripBoardPalette) -> some View {
        let good = MoneyTone.good.color(pal)
        let ink: Color = filled ? Color.white : good
        let fill: Color = filled ? Self.pillGreen : good.opacity(0.12)
        return Text(title)
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(fill, in: Capsule())
    }

    /// 〔不用〕：只在這一頁收起來（不存；下次打開成果頁是一般模式，不再問）
    private func skipButton(_ m: WorkoutMilestone, pal: TripBoardPalette) -> some View {
        Button {
            skip(m)
        } label: {
            Text("不用")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.label)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel("不用記：" + m.title)
    }

    // MARK: 動作

    /// 〔記成人生里程碑〕：要訂閱（同「＋」新增健康里程碑）→ 先改字的提示框
    private func ask(_ m: WorkoutMilestone) {
        guard subscription.isPremium else {
            onNeedPremium()
            return
        }
        draft = m.title
        editing = m
        asking = true
    }

    private func skip(_ m: WorkoutMilestone) {
        withAnimation(.easeInOut(duration: 0.25)) {
            _ = dismissed.insert(m.key)
        }
    }

    /// 〔儲存〕：提示框先收，下一個 runloop 再查一次記過沒才寫（按兩次、別台剛同步過來都不會記兩筆）。
    /// 字是使用者改過的（去頭尾空白；空的用預設標題）；健康類、日期＝那一趟、備註預設、sourceKey＝key（WorkoutFacts.lifeMilestone）
    private func save() {
        guard let m = editing else { return }
        let item = WorkoutFacts.lifeMilestone(m, title: draft)
        let store = lifeStore
        DispatchQueue.main.async {
            guard WorkoutFacts.recordedMilestone(m, in: store.milestones) == nil else { return }
            store.add(item)
        }
    }
}
