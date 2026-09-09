import SwiftUI

// MARK: - 績效互評（年度同儕排名）
//
// [v25.348] 使用者定義的計分規則：
//   1. 排名在「同課 × 同職等」的組內進行，評分者自己也在組內（含自評）。
//   2. 某組 N 人 → 第 1 名基礎分 N、第 2 名 N-1 …… 第 N 名 1 分。
//   3. 基礎分 × **評分者職等的權重**（職等越高票越重），全部評分者加總即為年度總分。
//
// 權重掛在評分者身上，所以同一組（人數固定）由不同人評，基礎分一樣、加權後不同。
// 例：32 職等組 3 人 → 第一名基礎分 3；31 職等(權重1)投＝3 分、32 職等(權重2)投＝6 分。

/// 評分票編輯器：拖曳排序，一個職等組一份清單。
/// raterId 傳 PerformanceBallot.selfRaterId 代表「我」。
struct PerformanceBallotView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let raterId: UUID
    /// 由呼叫端指定的初始年度（預設今年）
    var initialYear: Int = Calendar.current.component(.year, from: Date())

    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var ballot: PerformanceBallot?
    /// 我自己評分時要選的職等（決定權重）；部屬評分者直接用他自己的職等
    @AppStorage("perf_self_grade_id") private var selfGradeIdRaw = ""
    @State private var showGradePicker = false
    @State private var loaded = false

    private var isSelf: Bool { raterId == PerformanceBallot.selfRaterId }

    private var raterGradeId: UUID? {
        if isSelf { return UUID(uuidString: selfGradeIdRaw) }
        return lifeStore.subordinates.first(where: { $0.id == raterId })?.gradeTitleId
    }

    private var raterGrade: GradeTitle? {
        raterGradeId.flatMap { id in lifeStore.gradeTitles.first(where: { $0.id == id }) }
    }

    private var raterName: String {
        if isSelf { return lifeStore.profile.chineseName.isEmpty ? "我" : lifeStore.profile.chineseName }
        let s = lifeStore.subordinates.first(where: { $0.id == raterId })
        return (s?.name.isEmpty == false ? s!.name : "未命名")
    }

    /// 可選年度：有票的年度 ∪ 今年，再往前補兩年，方便回填去年
    private var yearOptions: [Int] {
        let thisYear = Calendar.current.component(.year, from: Date())
        var set = Set(lifeStore.performanceYears)
        set.formUnion([thisYear, thisYear - 1, thisYear - 2])
        return set.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let b = ballot, !b.groups.isEmpty {
                    ballotList(b)
                } else {
                    emptyState
                }
            }
            .navigationTitle(isSelf ? "我的績效評分" : "\(raterName)的評分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if ballot?.groups.isEmpty == false {
                        Button(ballot?.isSubmitted == true ? "更新" : "送出") { submit() }
                            .bold().foregroundStyle(.green)
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                year = initialYear
                reload()
            }
            .onChange(of: year) { _, _ in reload() }
            .onChange(of: selfGradeIdRaw) { _, _ in reload() }
        }
    }

    // MARK: - 主體

    private func ballotList(_ b: PerformanceBallot) -> some View {
        List {
            headerSection(b)
            ForEach(Array(b.groups.enumerated()), id: \.element.id) { gi, group in
                Section {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { idx, entry in
                        entryRow(entry, rank: idx + 1, groupSize: group.entries.count)
                    }
                    .onMove { from, to in move(groupIndex: gi, from: from, to: to) }
                } header: {
                    groupHeader(group)
                } footer: {
                    Text("長按拖曳調整名次。第 1 名 \(group.entries.count) 分，往下每名少 1 分，"
                         + "再乘上你的權重 ×\(weightText)。")
                }
            }
            noteSection(b)
        }
        .environment(\.editMode, .constant(.active))
        .listStyle(.insetGrouped)
    }

    private var weightText: String {
        let w = raterGrade?.weightValue ?? 1
        return w == w.rounded() ? String(format: "%.0f", w) : String(format: "%.1f", w)
    }

    private func headerSection(_ b: PerformanceBallot) -> some View {
        Section {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.orange.opacity(0.22), .orange.opacity(0.08)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 42, height: 42)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(raterName).font(.subheadline.weight(.bold))
                    HStack(spacing: 6) {
                        Text(raterGrade?.displayLabel ?? "未設職等")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.12)).foregroundStyle(.indigo)
                            .clipShape(Capsule())
                        Text("權重 ×\(weightText)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14)).foregroundStyle(.orange)
                            .clipShape(Capsule())
                        if b.isSubmitted {
                            Text("已送出")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.green.opacity(0.14)).foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                }
                Spacer()
            }
            Picker("年度", selection: $year) {
                ForEach(yearOptions, id: \.self) { y in Text("\(String(y)) 年").tag(y) }
            }
            if isSelf {
                Picker("我的職等（決定權重）", selection: $selfGradeIdRaw) {
                    Text("未設定（權重 ×1）").tag("")
                    ForEach(lifeStore.gradeTitles) { g in
                        Text("\(g.displayLabel)　×\(g.weightValue == g.weightValue.rounded() ? String(format: "%.0f", g.weightValue) : String(format: "%.1f", g.weightValue))")
                            .tag(g.id.uuidString)
                    }
                }
            }
        } footer: {
            if isSelf {
                Text("你的職等決定這張票的權重；在「部門職等」頁可以調整各職等的績效權重。")
            } else if raterGrade == nil {
                Text("這位同仁還沒設定職等，權重以 ×1 計算。可在部屬編輯頁補上職等。")
            }
        }
    }

    private func groupHeader(_ group: PerformanceRankGroup) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [.orange, .orange.opacity(0.55)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 14)
            Text(group.title).font(.subheadline.weight(.bold))
            Spacer()
            Text("\(group.entries.count) 人")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.orange.opacity(0.13)).foregroundStyle(.orange)
                .clipShape(Capsule())
        }
    }

    private func entryRow(_ entry: PerformanceRankEntry, rank: Int, groupSize: Int) -> some View {
        let base = groupSize - rank + 1
        let points = Double(base) * (raterGrade?.weightValue ?? 1)
        let isMe = entry.id == raterId
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rankColor(rank).opacity(rank <= 3 ? 0.18 : 0.10))
                    .frame(width: 30, height: 30)
                Text("\(rank)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(rankColor(rank))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.name).font(.subheadline.weight(.semibold))
                    if isMe {
                        Text("自己")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.blue.opacity(0.14)).foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                Text("基礎 \(base) 分 × 權重 = \(pointsText(points)) 分")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(pointsText(points))
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 2)
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .orange
        case 2: return .gray
        case 3: return .brown
        default: return .secondary
        }
    }

    private func pointsText(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private func noteSection(_ b: PerformanceBallot) -> some View {
        Section {
            TextField("備註（選填，只有你看得到）", text: Binding(
                get: { ballot?.note ?? "" },
                set: { ballot?.note = $0 }
            ), axis: .vertical)
            .lineLimit(2...5)
            if b.isSubmitted, let at = b.submittedAt {
                HStack {
                    Text("送出時間").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.stampFmt.string(from: at)).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("備註")
        } footer: {
            Text("送出後仍然可以再調整並「更新」；分數會即時反映在人才矩陣的「評分加總」頁。")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 34)).foregroundStyle(.tertiary)
            Text("沒有可以排名的組別")
                .font(.subheadline.weight(.semibold))
            Text(isSelf
                 ? "排名在「同課 × 同職等」的組內進行，每組至少要 2 個人。請先在部屬編輯頁補上部門與職等。"
                 : "\(raterName)所在的課裡，同職等的人不足 2 位，因此沒有需要排名的組別。")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Picker("年度", selection: $year) {
                ForEach(yearOptions, id: \.self) { y in Text("\(String(y)) 年").tag(y) }
            }
            .pickerStyle(.segmented).padding(.horizontal, 40).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private static let stampFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()

    // MARK: - 動作

    private func reload() {
        ballot = lifeStore.performanceBallotSynced(year: year, raterId: raterId,
                                                   raterGradeId: raterGradeId)
    }

    private func move(groupIndex: Int, from: IndexSet, to: Int) {
        guard var b = ballot, b.groups.indices.contains(groupIndex) else { return }
        b.groups[groupIndex].entries.move(fromOffsets: from, toOffset: to)
        ballot = b
        // 拖一次就存一次草稿：中途離開不會白排
        lifeStore.upsertPerformanceBallot(b)
    }

    private func submit() {
        guard var b = ballot else { return }
        b.submittedAt = Date()
        // 送出時把評分者職等與權重凍結成快照，日後升職不會改寫這一年的分數
        b.raterName = raterName
        b.raterGradeId = raterGradeId
        b.raterGradeLabel = raterGrade?.displayLabel ?? ""
        b.raterWeight = raterGrade?.weightValue ?? 1
        lifeStore.upsertPerformanceBallot(b)
        ballot = b
        dismiss()
    }
}

// MARK: - 評分加總（人才矩陣第三分頁）

/// 年度總排名 + 每個人的分數來源。可依課別篩選；已轉出／離職的人分數照樣保留。
struct PerformanceSummaryView: View {
    @EnvironmentObject var lifeStore: LifeStore

    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var deptFilter: UUID?     // nil = 全部課別
    @State private var expanded: Set<UUID> = []

    private var scores: [PerformanceScore] { lifeStore.performanceScores(year: year) }

    /// 依課別篩選後的名次（名次以篩選後的清單重新編號）
    private var shown: [PerformanceScore] {
        guard let deptFilter else { return scores }
        return scores.filter { s in
            lifeStore.subordinates.first(where: { $0.id == s.personId })?.departmentId == deptFilter
        }
    }

    private var pending: [(id: UUID, name: String)] { lifeStore.performancePendingRaters(year: year) }

    private var submittedCount: Int {
        lifeStore.performanceBallots.filter { $0.year == year && $0.isSubmitted }.count
    }

    /// 本頁是嵌在人才矩陣的 ScrollView 裡，所以自己不再包一層 ScrollView
    /// （巢狀垂直捲動會讓手勢互搶、滑動變得很奇怪）。
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
            if scores.isEmpty {
                emptyState
            } else {
                summaryHeader
                ForEach(Array(shown.enumerated()), id: \.element.id) { idx, score in
                    scoreCard(score, rank: idx + 1)
                }
                footnote
            }
        }
        .padding(.horizontal)
    }

    // MARK: 控制列

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("年度", selection: $year) {
                ForEach(lifeStore.performanceYears, id: \.self) { y in Text("\(String(y)) 年").tag(y) }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    deptChip(nil, label: "全部課別")
                    ForEach(lifeStore.departments) { d in
                        deptChip(d.id, label: d.name.isEmpty ? d.code : d.name)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.top, 8)
    }

    private func deptChip(_ id: UUID?, label: String) -> some View {
        let on = deptFilter == id
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { deptFilter = id }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(on ? Color.orange.opacity(0.16) : Color(.tertiarySystemFill),
                            in: Capsule())
                .foregroundStyle(on ? Color.orange : Color.secondary)
                .overlay(Capsule().stroke(on ? Color.orange.opacity(0.3) : .clear, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    // MARK: 看板

    private var summaryHeader: some View {
        HStack(spacing: 10) {
            statCell(value: "\(submittedCount)", label: "已送出票", color: .green)
            statCell(value: "\(pending.count)", label: "尚未送出", color: pending.isEmpty ? .secondary : .orange)
            statCell(value: "\(shown.count)", label: "被評分人數", color: .blue)
        }
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.14), lineWidth: 0.75))
    }

    // MARK: 每個人

    private func scoreCard(_ score: PerformanceScore, rank: Int) -> some View {
        let sub = lifeStore.subordinates.first(where: { $0.id == score.personId })
        let deptName = sub?.departmentId
            .flatMap { id in lifeStore.departments.first(where: { $0.id == id })?.name }
        let gradeLabel = sub?.gradeTitleId
            .flatMap { id in lifeStore.gradeTitles.first(where: { $0.id == id })?.displayLabel }
        let isOpen = expanded.contains(score.personId)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    if isOpen { expanded.remove(score.personId) } else { expanded.insert(score.personId) }
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(rankColor(rank).opacity(rank <= 3 ? 0.18 : 0.10))
                            .frame(width: 34, height: 34)
                        Text("\(rank)")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(rankColor(rank))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(score.name).font(.subheadline.weight(.bold))
                            if sub == nil {
                                Text("已轉出")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                                    .background(Color(.tertiarySystemFill))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                        }
                        Text([deptName, gradeLabel].compactMap { $0 }.joined(separator: "・")
                             + "・\(score.sources.count) 票・平均第 "
                             + String(format: "%.1f", score.averageRank) + " 名")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(pointsText(score.total))
                        .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.orange)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Divider().padding(.vertical, 8)
                ForEach(score.sources.sorted { $0.points > $1.points }) { src in
                    sourceRow(src)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
    }

    private func sourceRow(_ src: PerformanceScoreSource) -> some View {
        HStack(spacing: 8) {
            Text(src.raterName)
                .font(.caption.weight(.semibold))
                .frame(width: 68, alignment: .leading)
                .lineLimit(1)
            Text("第 \(src.rank)/\(src.groupSize) 名")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.blue.opacity(0.10)).foregroundStyle(.blue)
                .clipShape(Capsule())
            Text("\(src.base) × \(pointsText(src.weight))")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Text(pointsText(src.points))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 3)
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !pending.isEmpty {
                Text("尚未送出：" + pending.map(\.name).joined(separator: "、"))
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("計分：排名在「同課 × 同職等」的組內進行，某組 N 人時第 1 名基礎分 N、"
                 + "往下每名少 1 分，再乘上評分者職等的績效權重後加總。"
                 + "各課人數不同、基礎分上限就不同，跨課比較僅供參考。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy")
                .font(.system(size: 34)).foregroundStyle(.tertiary)
            Text("\(String(year)) 年還沒有已送出的評分票")
                .font(.subheadline.weight(.semibold))
            Text("在部屬總覽的獎盃按鈕填自己的評分，或在部屬卡片右上角的獎盃按鈕代填該同仁的評分；送出後這裡就會出現總排名。")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .orange
        case 2: return .gray
        case 3: return .brown
        default: return .secondary
        }
    }

    private func pointsText(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}
