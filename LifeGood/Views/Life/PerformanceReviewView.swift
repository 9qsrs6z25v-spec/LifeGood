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
    /// [v25.372] 排名分數占比的輸入字串（存進 ballot.rankSharePercent）
    @State private var shareText = ""
    @State private var shareSaveTask: Task<Void, Never>?

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
            .onChange(of: year) { _, _ in flushDraft(); reload() }
            .onChange(of: selfGradeIdRaw) { _, _ in reload() }
            .onDisappear { flushDraft() }
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
                    Text(groupFootnote(group))
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

    /// 每組底下的說明。[v25.372] 單人組沒得拖，講法要不一樣。
    private func groupFootnote(_ group: PerformanceRankGroup) -> String {
        let n = group.entries.count
        if n <= 1 {
            return "這個職等在這一課只有 1 個人，沒有比較對象，直接算第 1 名、基礎分 1 分，"
                + "再乘上你的權重 ×\(weightText)。"
        }
        return "長按拖曳調整名次。第 1 名 \(n) 分，往下每名少 1 分，再乘上你的權重 ×\(weightText)。"
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
            // [v25.372] 排名分數在最終評分裡該占幾成
            HStack {
                Text("排名分數占比")
                Spacer()
                TextField("0", text: $shareText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .onChange(of: shareText) { _, newValue in
                        let cleaned = Self.cleanedPercent(newValue)
                        if cleaned != newValue { shareText = cleaned }
                        ballot?.rankSharePercent = Double(cleaned) ?? 0
                        saveDraftDebounced()
                    }
                Text("%").foregroundStyle(.secondary)
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
            Text(shareFootnote)
        }
    }

    /// 占比欄的說明。字串在 ViewBuilder 外組好再進 Text。
    private var shareFootnote: String {
        var parts: [String] = [Self.shareExplain]
        if isSelf {
            parts.append("你的職等決定這張票的權重；在「部門職等」頁可以調整各職等的績效權重。")
        } else if raterGrade == nil {
            parts.append("這位同仁還沒設定職等，權重以 ×1 計算。可在部屬編輯頁補上職等。")
        }
        return parts.joined(separator: "\n")
    }

    private static let shareExplain =
        "「排名分數占比」是你認為互評排名該占最終評分幾成。年度實際採用的是所有已送出票的加權平均"
        + "（依各自的職等權重）：例如 31 職等(×1) 填 20%、32 職等(×2) 填 10%，"
        + "平均就是 (20×1＋10×2)/3 ＝ 13.3%，剩下的 86.7% 由主動性與潛力的平均分數補上。"

    /// 只留數字與一個小數點，並夾在 0～100
    private static func cleanedPercent(_ raw: String) -> String {
        var out = ""
        var seenDot = false
        for ch in raw {
            if ch.isNumber { out.append(ch) }
            else if (ch == "." || ch == "。") && !seenDot && !out.isEmpty { out.append("."); seenDot = true }
        }
        guard let v = Double(out) else { return out }
        if v > 100 { return "100" }
        return out
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
                 ? "排名在「同課 × 同職等」的組內進行。目前還沒有任何部屬可以排，請先在部屬編輯頁補上部門與職等。"
                 : "\(raterName)所在的課裡找不到可以排名的人。")
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
        let b = lifeStore.performanceBallotSynced(year: year, raterId: raterId,
                                                  raterGradeId: raterGradeId)
        ballot = b
        // 0 顯示成空字串：欄位空著比擺一個 0 更像「還沒填」
        shareText = b.rankSharePercent > 0 ? Self.percentText(b.rankSharePercent) : ""
    }

    /// 占比欄改動時存草稿（比照拖曳排序：中途離開不會白填）。
    /// 每敲一個字就寫一次會連帶跑一次完整存檔，所以節流到停止輸入 500ms 後才寫。
    private func saveDraftDebounced() {
        shareSaveTask?.cancel()
        shareSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let b = ballot else { return }
            lifeStore.upsertPerformanceBallot(b)
        }
    }

    /// 離開畫面時把還在防抖視窗裡的草稿補存一次，不然剛打的占比會消失
    private func flushDraft() {
        shareSaveTask?.cancel()
        shareSaveTask = nil
        guard let b = ballot else { return }
        lifeStore.upsertPerformanceBallot(b)
    }

    private static func percentText(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
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
    /// [v25.349] 課別選擇要記住，不必每次都從「全部課別」重選。空字串＝全部
    @AppStorage("perf_summary_dept") private var deptFilterRaw: String = ""
    @State private var expanded: Set<UUID> = []
    /// [v25.372] 占比來源明細是否展開
    @State private var shareOpen = false

    private var deptFilter: UUID? {
        // 記住的課別若已被刪掉就自動回到「全部課別」，不會卡在空清單
        get {
            guard !deptFilterRaw.isEmpty, let id = UUID(uuidString: deptFilterRaw),
                  lifeStore.departments.contains(where: { $0.id == id }) else { return nil }
            return id
        }
        nonmutating set { deptFilterRaw = newValue?.uuidString ?? "" }
    }

    private var scores: [PerformanceScore] { lifeStore.performanceScores(year: year) }

    private var pending: [(id: UUID, name: String)] { lifeStore.performancePendingRaters(year: year) }

    /// [v25.372] 這一年實際採用的占比（排名 vs 綜合分數）
    private var share: PerformanceShare { lifeStore.performanceShare(year: year) }

    private var submittedCount: Int {
        lifeStore.performanceBallots.filter { $0.year == year && $0.isSubmitted }.count
    }

    /// 本頁是嵌在人才矩陣的 ScrollView 裡，所以自己不再包一層 ScrollView
    /// （巢狀垂直捲動會讓手勢互搶、滑動變得很奇怪）。
    var body: some View {
        // 單次計算，避免 body 內多處重複跑加總
        // （[v25.372] 加總現在還要掃被標註／兼任／議程三份全庫，更不能算兩遍）
        let all = scores
        let secs = lifeStore.performanceGradeSections(scores: all, deptId: deptFilter)
        var shownCount = 0
        for sec in secs { shownCount += sec.scores.count }
        return VStack(alignment: .leading, spacing: 14) {
            controls
            if all.isEmpty {
                emptyState
            } else {
                summaryHeader(shownCount: shownCount)
                if secs.isEmpty {
                    Text("這個課別在 \(String(year)) 年沒有排名資料")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 26)
                } else {
                    ForEach(secs) { section in
                        gradeHeader(section)
                        ForEach(Array(section.scores.enumerated()), id: \.element.id) { idx, score in
                            scoreCard(score, rank: idx + 1)
                        }
                    }
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

    // MARK: 職等分段標題

    private func gradeHeader(_ section: PerformanceGradeSection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [.orange, .orange.opacity(0.35)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Text(section.label).font(.subheadline.weight(.bold))
                Text("\(section.scores.count) 人")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.13)).foregroundStyle(.orange)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.6))
                Spacer()
                if let w = section.weight {
                    Text("權重 ×\(pointsText(w))")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            // [v25.373] 講清楚這個職等的 100 分是拿什麼當基準換算的
            if let basisLine = gradeBasisLine(section) {
                Text(basisLine)
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .padding(.leading, 12)
            }
        }
        .padding(.top, 6)
    }

    /// 正規化基準說明。基準取整個職等（不分課別），所以切換課別篩選不會讓分數跳動。
    private func gradeBasisLine(_ section: PerformanceGradeSection) -> String? {
        guard let s = section.scores.first, s.rankBasis > 0 || s.overallBasis > 0 else { return nil }
        return "100 分基準：排名 " + pointsText(s.rankBasis)
            + "、綜合 " + pointsText(s.overallBasis) + "（本職等最高，不分課別）"
    }

    // MARK: 看板

    private func summaryHeader(shownCount: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                statCell(value: "\(submittedCount)", label: "已送出票", color: .green)
                statCell(value: "\(pending.count)", label: "尚未送出", color: pending.isEmpty ? .secondary : .orange)
                statCell(value: "\(shownCount)", label: "被評分人數", color: .blue)
            }
            // [v25.372] 第二列：這一年實際採用的兩個占比
            HStack(spacing: 10) {
                statCell(value: percentText(share.rankPercent) + "%",
                         label: "排名平均占比", color: .orange)
                statCell(value: percentText(share.overallPercent) + "%",
                         label: "總分占比", color: .purple)
            }
            shareBreakdown
        }
    }

    /// 占比從哪來：每張票填了多少 × 權重
    @ViewBuilder
    private var shareBreakdown: some View {
        let votes = share.votes
        if !votes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        shareOpen.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "percent")
                            .font(.system(size: 10, weight: .bold))
                        Text(shareSummaryLine)
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Image(systemName: shareOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(share.isConfigured ? Color.orange : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if shareOpen {
                    Divider().padding(.vertical, 7)
                    ForEach(votes) { v in shareVoteRow(v) }
                    Divider().padding(.vertical, 7)
                    HStack {
                        Text("加權平均").font(.caption.weight(.bold))
                        Spacer()
                        Text(shareFormulaLine)
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.14), lineWidth: 0.75))
        }
    }

    private func shareVoteRow(_ v: PerformanceShareVote) -> some View {
        HStack(spacing: 8) {
            Text(v.raterName)
                .font(.caption.weight(.semibold))
                .frame(width: 68, alignment: .leading)
                .lineLimit(1)
            Text(v.raterGradeLabel)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.indigo.opacity(0.10)).foregroundStyle(.indigo)
                .clipShape(Capsule())
            Spacer()
            Text(shareVoteLine(v))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    /// 字串在 ViewBuilder 外組好（本專案有型別檢查逾時的前科）
    private var shareSummaryLine: String {
        guard share.isConfigured else {
            return "還沒有人填排名分數占比 → 目前 100% 採用排名分數（與舊版相同）"
        }
        return "占比來源：\(share.votes.count) 張票加權平均 → 排名 "
            + percentText(share.rankPercent) + "%"
    }

    private func shareVoteLine(_ v: PerformanceShareVote) -> String {
        percentText(v.percent) + "% × " + pointsText(v.weight)
    }

    private var shareFormulaLine: String {
        let numerator = share.votes.reduce(0.0) { $0 + $1.weighted }
        return percentText(numerator) + " ÷ " + pointsText(share.weightSum)
            + " = " + percentText(share.rankPercent) + "%"
    }

    private func percentText(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
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
        let isOpen = expanded.contains(score.personId)
        // 副標一次組好再交給 Text：串在 Text(...) 裡的字串相加會讓型別檢查爆掉
        let metaText = metaLine(deptName: deptName, score: score)
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
                        Text(metaText)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // [v25.373] 正規化分數 / 未正規化分數。
                    // 正規化是每個職等各自做的，第一名一律 100 分，跨職等比不出高低；
                    // 右邊那個原始值才看得出低職等的人實際做了多少事。
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(pointsText(score.finalScore))
                                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.orange)
                            Text("/")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            Text(pointsText(score.rawFinalScore))
                                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text("正規化 / 原始")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Divider().padding(.vertical, 8)
                // [v25.372] 最終分數怎麼組出來的
                finalBreakdown(score)
                Divider().padding(.vertical, 8)
                Text("排名分數的來源")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    .padding(.bottom, 2)
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

    /// [v25.372] 最終分數的組成。[v25.373] 兩段分數先在同職等內正規化到 100 分再加權。
    private func finalBreakdown(_ score: PerformanceScore) -> some View {
        VStack(spacing: 5) {
            breakdownRow(label: "排名分數", raw: score.total, basis: score.rankBasis,
                         normalized: score.normalizedRank, sharePercent: share.rankPercent,
                         product: score.normalizedRank * share.rank, color: .orange)
            breakdownRow(label: "綜合分數", raw: score.overallScore, basis: score.overallBasis,
                         normalized: score.normalizedOverall, sharePercent: share.overallPercent,
                         product: score.normalizedOverall * share.overall, color: .purple)
            if !score.hasOverall {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9)).foregroundStyle(.orange)
                    Text("已不在部屬清單裡，算不出目前的綜合分數，這一項以 0 計。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            Divider().padding(.vertical, 2)
            HStack {
                Text("最終分數（正規化）").font(.caption.weight(.bold))
                Spacer()
                Text(pointsText(score.finalScore))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.orange)
            }
            HStack {
                Text("未正規化").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(rawFormulaLine(score))
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    /// 一段分數：原始值 →（同職等最高分當 100）正規化值 × 占比
    private func breakdownRow(label: String, raw: Double, basis: Double,
                              normalized: Double, sharePercent: Double,
                              product: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .frame(width: 68, alignment: .leading)
                Text(breakdownFormula(value: normalized, sharePercent: sharePercent))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text(pointsText(product))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            Text(normalizeLine(raw: raw, basis: basis, normalized: normalized))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.leading, 76)
        }
    }

    /// 字串在 ViewBuilder 外組好（本專案有型別檢查逾時的前科）
    private func breakdownFormula(value: Double, sharePercent: Double) -> String {
        pointsText(value) + " × " + percentText(sharePercent) + "%"
    }

    private func normalizeLine(raw: Double, basis: Double, normalized: Double) -> String {
        guard basis > 0 else { return "本職等沒有可用的基準，正規化後為 0" }
        return "原始 " + pointsText(raw) + " ÷ 本職等最高 " + pointsText(basis)
            + " × 100 = " + pointsText(normalized)
    }

    private func rawFormulaLine(_ score: PerformanceScore) -> String {
        pointsText(score.total) + " × " + percentText(share.rankPercent) + "% + "
            + pointsText(score.overallScore) + " × " + percentText(share.overallPercent)
            + "% = " + pointsText(score.rawFinalScore)
    }

    /// 名次列的副標：職等已經是分段標題，這裡只補課別、票數與平均名次
    private func metaLine(deptName: String?, score: PerformanceScore) -> String {
        var parts: [String] = []
        if let deptName, !deptName.isEmpty { parts.append(deptName) }
        parts.append("\(score.sources.count) 票")
        parts.append(String(format: "平均第 %.1f 名", score.averageRank))
        // [v25.372] 右側大字已經換成最終分數，把兩個來源分數補在這裡才看得出怎麼來的
        parts.append("排名 " + pointsText(score.total))
        parts.append("綜合 " + pointsText(score.overallScore))
        return parts.joined(separator: "・")
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
            Text(Self.scoringNote)
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

    /// 計分說明：整段寫成單一字串常數，不要在 Text(...) 裡用 + 串接
    private static let scoringNote = "計分三段。①「排名分數」：排名在「同課 × 同職等」的組內進行，某組 N 人時第 1 名基礎分 N、往下每名少 1 分，再乘上評分者職等的績效權重後加總；該職等只有 1 個人時直接算第 1 名、基礎分 1 分。②「正規化」：排名分數與綜合分數（主動性與潛力的平均）的量級差很多，直接加權會讓占比形同虛設，所以兩者各自在同一個職等內除以該職等的最高分再乘 100——每個職等的第一名都是 100 分。基準取整個職等、不分課別，切換課別篩選不會讓分數跳動。③「最終分數」＝正規化排名 × 排名平均占比 ＋ 正規化綜合 ×（1 − 占比）；占比是每張票各自填的百分比再依評分者職等權重取加權平均。每一列右邊顯示「正規化 / 原始」兩個數字：正規化後每個職等的第一名都是 100，跨職等比不出高低，要看低職等實際做了多少事就看原始值。同職等內組人數不同時，人多的組基礎分上限較高，正規化後仍會略占優勢。"

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
