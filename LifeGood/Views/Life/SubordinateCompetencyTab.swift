import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 部屬卡片〔職能〕分頁（G1 負責；radar/judge.md §4.3、§5、§6、§3.6；radar/build/v1a-1/brief.md §4 G1）
//
// • 由上到下：摘要卡（不寫 0–100）→ 人格特質卡（0 項整張不出現）→ 每個系統一張 → 不用學的系統一行。
// • 看不擋；〔評分〕〔不用學的系統〕〔用範例開始〕〔自己設定〕要訂閱（isPremium／premiumLockAlert）。
// • 已轉出：〔評分〕藏起來、「已轉出，評分留著可以看」；這台的 App 比較舊：〔評分〕藏起來、頂上一行說明。
// • 整頁的數字、字只照 CompetencyMath.tabModel；sheet 一律 sheet(item:)＋.appStores()；dismiss 後寫 store 放下一個 runloop。
// • 這個 View 不包 ScrollView（明細頁外面已經有）；白卡、外距自己加。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G1 換成真的。
//
// [v25.600 職能雷達 v1a-2] 這一版加的（radar/build/v1a-2/brief.md §4 G1-A；要退回這一件：照 69f6fa6 的這個檔）：
// • 三支 private 小函式搬進 CompetencyMath（tabModel 的 hasAnyPrevious／overlayLabel／skippedLineText；↑↓ 顏色照 deltaDirection）。
// • 只評了一部分、各張卡上一次不是同一天：膠囊下面一行 previousDayText「上一次：人格特質 4/30・Gas System 10/30…」。
// • 點雷達下面橫條那一列 → 那一格的歷史（CompetencyCellHistorySheet；看不擋）。
// • iPad（.regular）雷達卡兩欄（LazyVGrid、每張最寬 360）；iPhone 照舊一欄。
// • 最下面「評分紀錄」白卡 → 點一列打開那一天的明細（CompetencyRecordDetailView；看不擋、改刪在明細頁擋）。
// • §13：每一格的評語不做——這裡一個字的評語都不顯示。

struct SubordinateCompetencyTab: View {
    let subordinateId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager

    /// 摘要卡「疊：上一次」（這台記住；個人方便用）
    @AppStorage("competency.showPrevious") private var showPrevious = true
    @State private var ratingRequest: CompetencyRatingRequest?
    @State private var setupRequest: CompTabSetupRequest?
    @State private var skipRequest: CompTabSkipRequest?
    @State private var showPremiumAlert = false
    /// 剛存好「已儲存 10/30 的評分（12 格）」（3 秒後自己消失）
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?
    // [v25.600 職能雷達 v1a-2] 評分紀錄明細、點一格的歷史（sheet(item:)）；iPad 兩欄。要退回這一件：刪這三行
    @State private var recordRequest: CompetencyRecordRequest?
    @State private var historyRequest: CompetencyCellHistoryRequest?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isArchived: Bool { OrgMoveIndex.isArchived(subordinateId) }

    private var model: CompetencyTabModel {
        CompetencyMath.tabModel(setup: lifeStore.competencySetup,
                                ratings: lifeStore.competencyRatings,
                                subordinateId: subordinateId,
                                archivedPerson: isArchived,
                                sessions: lifeStore.competencySessions(of: subordinateId),
                                today: CompetencyMath.dayKey(Date()))
    }

    var body: some View {
        let m = model
        let archived = isArchived
        let canRate = !archived && !m.readOnly
        return VStack(spacing: 16) {
            CompTabNoticeLines(archived: archived, readOnly: m.readOnly, toast: toastText)
            if m.configured {
                configuredContent(m, canRate: canRate)
            } else {
                CompTabEmptyCard(showsButtons: !m.readOnly, onSample: startSample, onBlank: startBlankSetup)
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $ratingRequest) { r in
            CompetencyRatingSheet(request: r, onSaved: { text in showToast(text) })
                .appStores()
        }
        .sheet(item: $setupRequest) { _ in
            NavigationStack {
                CompetencySetupView(showsDoneButton: true)
            }
            .appStores()
        }
        .sheet(item: $skipRequest) { req in
            CompTabSkipSheet(subordinateId: req.subordinateId, initialSkipped: req.initialSkipped)
                .appStores()
        }
        // [v25.600 職能雷達 v1a-2] 明細、點一格的兩個 sheet 包在一個 modifier 裡（body 的修飾器鏈不再拉長）。要退回這一件：刪這一行
        .modifier(CompTabHistorySheets(recordRequest: $recordRequest, historyRequest: $historyRequest))
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .onDisappear { toastTask?.cancel() }
    }

    // MARK: 設好了：摘要卡、每組一張、不用學的系統

    @ViewBuilder
    private func configuredContent(_ m: CompetencyTabModel, canRate: Bool) -> some View {
        let hasSystems = !lifeStore.competencySetup.activeSystems.isEmpty
        CompTabSummaryCard(summary: m.summary,
                           neverRated: m.neverRated,
                           canRate: canRate,
                           showsSkipItem: canRate && hasSystems,
                           showsOverlayToggle: m.hasAnyPrevious,
                           overlayLabel: m.overlayLabel,
                           previousDayText: m.previousDayText,
                           showPrevious: $showPrevious,
                           onRate: startRating,
                           onSkip: openSkipSheet,
                           onSetup: openSetup)
        cardsBlock(m)
        if hasSystems {
            CompTabSkippedLine(text: m.skippedLineText,
                               canEdit: canRate,
                               onEdit: openSkipSheet)
        }
        // [v25.600 職能雷達 v1a-2] 評分紀錄（judge §4.3④；§13 不顯示評語）。要退回這一件：刪這個 if
        if !m.records.isEmpty {
            CompTabRecordsCard(records: m.records, onOpen: openRecord)
        }
    }

    // MARK: [v25.600 職能雷達 v1a-2] 雷達卡：iPad 兩欄、iPhone 一欄（judge §4.10）。要退回這一件：換回 ForEach＋padding

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    @ViewBuilder
    private func cardsBlock(_ m: CompetencyTabModel) -> some View {
        if isRegularWidth {
            LazyVGrid(columns: CompTabGrid.columns, alignment: .center, spacing: 16) {
                ForEach(m.cards) { card in
                    chartCard(card)
                        .frame(maxWidth: 360)
                }
            }
            .padding(.horizontal)
        } else {
            ForEach(m.cards) { card in
                chartCard(card)
                    .padding(.horizontal)
            }
        }
    }

    /// 一張雷達卡；點下面橫條那一列 → 那一格的歷史（看不擋）
    private func chartCard(_ card: CompetencyChartModel) -> CompetencyChartCard {
        let groupId: UUID = card.id
        return CompetencyChartCard(model: card, showPrevious: showPrevious, onTapAxis: { itemId in
            openHistory(groupId: groupId, itemId: itemId)
        })
    }

    // MARK: 動作（看不擋、動手才擋）

    private func startSample() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        lifeStore.applyCompetencySample()
    }

    private func startBlankSetup() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        lifeStore.startCompetencyBlankSetup()
        setupRequest = CompTabSetupRequest()
    }

    private func startRating() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        ratingRequest = CompetencyRatingRequest(subordinateId: subordinateId)
    }

    private func openSkipSheet() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        let current: Set<UUID> = lifeStore.competencySetup.skippedGroupIds(subordinateId)
        skipRequest = CompTabSkipRequest(subordinateId: subordinateId, initialSkipped: current)
    }

    /// 〔職能項目設定〕看不擋（設定頁裡動手才擋）
    private func openSetup() {
        setupRequest = CompTabSetupRequest()
    }

    /// [v25.600 職能雷達 v1a-2] 點一格的歷史（看不擋；唯讀、已轉出也能看）
    private func openHistory(groupId: UUID, itemId: UUID) {
        historyRequest = CompetencyCellHistoryRequest(subordinateId: subordinateId, groupId: groupId, itemId: itemId)
    }

    /// [v25.600 職能雷達 v1a-2] 評分紀錄一列 → 那一天的明細（看不擋；〔改分數〕〔改日期〕〔刪除〕在明細頁擋）
    private func openRecord(_ dayKey: String) {
        recordRequest = CompetencyRecordRequest(subordinateId: subordinateId, dayKey: dayKey)
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { toastText = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { toastText = nil }
        }
    }
}

// MARK: - sheet 請求（sheet(item:) 用）

/// 打開「職能項目」設定（sheet）
struct CompTabSetupRequest: Identifiable {
    let id = UUID()
}

/// 打開〔不用學的系統〕（打開那一刻的勾選當起點）
struct CompTabSkipRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
    let initialSkipped: Set<UUID>
}

// MARK: - 白卡（跟明細頁其他分頁一樣）

private struct CompTabCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 1))
            .padding(.horizontal)
    }
}

/// 區塊標頭（明細頁的 sectionHeader 是 private，這裡照它的樣子寫一份小的）
private struct CompTabHeader<Trailing: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(color)
                .frame(width: 4, height: 18)
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
            trailing()
        }
    }
}

// MARK: - 頂上一行（已轉出／這台比較舊／剛存好）

private struct CompTabNoticeLines: View {
    let archived: Bool
    let readOnly: Bool
    let toast: String?

    var body: some View {
        if archived || readOnly || toast != nil {
            VStack(alignment: .leading, spacing: 6) {
                if archived {
                    CompTabNoticeRow(icon: "archivebox.fill", text: "已轉出，評分留著可以看", color: .secondary)
                }
                if readOnly {
                    CompTabNoticeRow(icon: "exclamationmark.triangle.fill",
                                     text: "這台的 App 比較舊，評分請在已更新的那台做", color: .orange)
                }
                if let t = toast {
                    CompTabNoticeRow(icon: "checkmark.circle.fill", text: t, color: .green)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }
    }
}

private struct CompTabNoticeRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 還沒設定（空狀態）

private struct CompTabEmptyCard: View {
    let showsButtons: Bool
    let onSample: () -> Void
    let onBlank: () -> Void

    private static let message =
        "人格特質（例：團隊合作、領導力、學習能力）和要學的系統（例：Gas System 的 P&ID、緊急應變、值班技能），"
        + "設好就能幫每位同仁評分、畫雷達。"

    var body: some View {
        VStack(spacing: 14) {
            CompTabSampleArt()
                .frame(width: 120, height: 104)
                .accessibilityHidden(true)
            Text("還沒設定職能項目")
                .font(.headline)
            Text(Self.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showsButtons {
                buttons
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .modifier(CompTabCardStyle())
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onSample) {
                Text("用範例開始")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(Color.white)
                    .background(CompetencyPalette.trait, in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: onBlank) {
                Text("自己設定")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(CompetencyPalette.trait)
                    .background(CompetencyPalette.trait.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}

/// 灰色範例雷達：外圈三角形格線＋裡面一個淡灰三角形
private struct CompTabSampleArt: View {
    var body: some View {
        ZStack {
            CompTabSampleTriangle(scale: 1)
                .stroke(Color(.separator), lineWidth: 1)
            CompTabSampleTriangle(scale: 0.6)
                .stroke(Color(.separator).opacity(0.6), lineWidth: 1)
            CompTabSampleTriangle(scale: 0.75)
                .fill(Color.gray.opacity(0.18))
            CompTabSampleTriangle(scale: 0.75)
                .stroke(Color.gray.opacity(0.55), lineWidth: 1.5)
        }
    }
}

/// 正三角形（頂點在 12 點鐘、順時針），scale 是離中心的比例
struct CompTabSampleTriangle: Shape {
    var scale: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = min(rect.width, rect.height) / 2 * scale
        let cx: CGFloat = rect.midX
        let cy: CGFloat = rect.midY
        var p = Path()
        for i in 0..<3 {
            let a: Double = -Double.pi / 2 + Double(i) * 2 * Double.pi / 3
            let x: CGFloat = cx + radius * CGFloat(cos(a))
            let y: CGFloat = cy + radius * CGFloat(sin(a))
            if i == 0 {
                p.move(to: CGPoint(x: x, y: y))
            } else {
                p.addLine(to: CGPoint(x: x, y: y))
            }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - ① 摘要卡

private struct CompTabSummaryCard: View {
    let summary: CompetencySummaryModel
    let neverRated: Bool
    let canRate: Bool
    let showsSkipItem: Bool
    let showsOverlayToggle: Bool
    let overlayLabel: String
    /// [v25.600 v1a-2] 各張卡上一次不是同一天：「上一次：人格特質 4/30・Gas System 10/30…」（同一天 nil）
    let previousDayText: String?
    @Binding var showPrevious: Bool
    let onRate: () -> Void
    let onSkip: () -> Void
    let onSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CompTabHeader(title: "職能", icon: "graduationcap.fill", color: CompetencyPalette.trait) {
                menu
            }
            Text(summary.lastLine)
                .font(.footnote)
                .foregroundStyle(summary.stale ? Color.orange : Color.secondary)
            tiles
            bottomRow
            previousDayLine
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .modifier(CompTabCardStyle())
    }

    private var menu: some View {
        Menu {
            if showsSkipItem {
                Button(action: onSkip) {
                    Label("不用學的系統", systemImage: "minus.circle")
                }
            }
            Button(action: onSetup) {
                Label("職能項目設定", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(CompetencyPalette.trait)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("職能選項")
    }

    /// 三格：人格特質（nil 不出現）、本職學能（nil 不出現）、已評
    private var tiles: some View {
        HStack(alignment: .top, spacing: 8) {
            if let tv = summary.traitValueText {
                CompTabTile(label: "人格特質", value: tv, valueDim: false,
                            sub: summary.traitDeltaText, subColor: CompTabTile.deltaColor(summary.traitDeltaText))
            }
            if let sv = summary.skillValueText {
                CompTabTile(label: "本職學能", value: sv, valueDim: summary.skillLowCoverage,
                            sub: skillSub, subColor: skillSubColor)
            }
            CompTabTile(label: "已評", value: summary.filledText, valueDim: false,
                        sub: summary.skillFilledText, subColor: Color.secondary)
        }
    }

    /// 覆蓋不到一半：小字寫「只評了 1／9 格」；不然寫「↑0.9」
    private var skillSub: String? {
        summary.skillLowCoverage ? summary.skillCoverageText : summary.skillDeltaText
    }

    private var skillSubColor: Color {
        summary.skillLowCoverage ? Color.secondary : CompTabTile.deltaColor(summary.skillDeltaText)
    }

    private var bottomRow: some View {
        HStack(spacing: 8) {
            if showsOverlayToggle {
                CompTabOverlayToggle(label: overlayLabel, isOn: $showPrevious)
            }
            Spacer(minLength: 8)
            if canRate {
                CompTabRateButton(title: neverRated ? "開始第一次評分" : "評分", action: onRate)
            }
        }
    }

    /// [v25.600 職能雷達 v1a-2] 膠囊下面一行：每張卡自己的上一次日期（疊開著、而且各張不是同一天才有）。要退回這一件：刪這個 var 與上面那一行
    @ViewBuilder
    private var previousDayLine: some View {
        if showsOverlayToggle && showPrevious, let t = previousDayText {
            Text(t)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 一格（字級照 FinanceTileView：.caption2 標籤／.headline rounded heavy 數字／.caption2 小字）
private struct CompTabTile: View {
    let label: String
    let value: String
    let valueDim: Bool
    let sub: String?
    let subColor: Color

    /// ↑ 綠、↓ 橘、其他灰（[v25.600 v1a-2] 方向照 CompetencyMath.deltaDirection；要退回這一件：換回 hasPrefix 那三行）
    static func deltaColor(_ text: String?) -> Color {
        let d: Int = CompetencyMath.deltaDirection(text)
        if d > 0 { return Color.green }
        if d < 0 { return Color.orange }
        return Color.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(valueDim ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub ?? " ")
                .font(.caption2)
                .foregroundStyle(subColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 「疊：〔上一次 ✓〕」
private struct CompTabOverlayToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("疊：")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                isOn.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isOn ? "checkmark" : "circle")
                        .font(.caption2.weight(.bold))
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? CompetencyPalette.trait : Color.secondary)
                .background(isOn ? CompetencyPalette.trait.opacity(0.12) : Color(.tertiarySystemFill), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("疊" + label)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }
}

/// 右下大按鈕〔評分〕／〔開始第一次評分〕
private struct CompTabRateButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(Color.white)
            .background(CompetencyPalette.trait, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - [v25.600 職能雷達 v1a-2] iPad 兩欄、兩個 sheet、評分紀錄白卡（要退回這一件：刪到「不用學的系統那一行」之前）

private enum CompTabGrid {
    /// 固定兩欄（使用者要的是「iPad 兩欄」：人格＋Gas 一排、Slurry＋Chemical 一排）。卡片自己最寬 360、靠上對齊。
    /// [v1a-2 裁定] 原本 .adaptive(minimum: 320)：〔職能〕分頁是推進來全寬時橫放會變 3～4 欄、窄的 sheet 會變 1 欄，所以改成固定兩欄
    static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]
}

/// 評分紀錄明細、點一格的歷史（sheet(item:)＋.appStores()）
private struct CompTabHistorySheets: ViewModifier {
    @Binding var recordRequest: CompetencyRecordRequest?
    @Binding var historyRequest: CompetencyCellHistoryRequest?

    func body(content: Content) -> some View {
        content
            .sheet(item: $recordRequest) { r in
                CompetencyRecordDetailView(subordinateId: r.subordinateId, dayKey: r.dayKey)
                    .appStores()
            }
            .sheet(item: $historyRequest) { r in
                CompetencyCellHistorySheet(subordinateId: r.subordinateId, groupId: r.groupId, itemId: r.itemId)
                    .appStores()
            }
    }
}

/// 最下面「評分紀錄（N）」白卡：每列一天（新的在前），點了開明細。不是 List，所以不做往左滑（刪除在明細頁）。
private struct CompTabRecordsCard: View {
    let records: [CompetencyRecordRow]
    let onOpen: (String) -> Void

    @State private var showAll = false

    private static let firstCount: Int = 6

    private var visible: [CompetencyRecordRow] {
        showAll ? records : Array(records.prefix(Self.firstCount))
    }

    private var hasMore: Bool { !showAll && records.count > Self.firstCount }

    var body: some View {
        let rows: [CompetencyRecordRow] = visible
        let lastId: String? = rows.last?.id
        let more: Bool = hasMore
        return VStack(alignment: .leading, spacing: 6) {
            CompTabHeader(title: "評分紀錄（\(records.count)）", icon: "clock.arrow.circlepath",
                          color: CompetencyPalette.trait) {
                EmptyView()
            }
            .padding(.bottom, 4)
            ForEach(rows) { row in
                CompTabRecordButton(row: row, onOpen: onOpen)
                if row.id != lastId || more {
                    Divider()
                }
            }
            if more {
                CompTabShowAllButton(count: records.count) { showAll = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .modifier(CompTabCardStyle())
    }
}

/// 一列：「10/30（五）・2 次」＋小字「評了 人格・Gas System…」，右邊「12 格」›
private struct CompTabRecordButton: View {
    let row: CompetencyRecordRow
    let onOpen: (String) -> Void

    var body: some View {
        Button {
            onOpen(row.dayKey)
        } label: {
            HStack(spacing: 10) {
                CompTabRecordTexts(row: row)
                Spacer(minLength: 8)
                Text(row.cellCountText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Button 本身就是一個 VoiceOver 元素（念 label、可以按）；這裡只換念的字（不用 .accessibilityElement(children: .ignore)，那會蓋掉按的動作）
        .accessibilityLabel(row.accessibilityText)
        .accessibilityHint("打開那一次的雷達")
    }
}

private struct CompTabRecordTexts: View {
    let row: CompetencyRecordRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text(row.dayText)
                    .font(.subheadline.weight(.semibold))
                if let c = row.countText {
                    Text("・" + c)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(row.groupsText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 超過 6 列：最後一列「看全部（N）」
private struct CompTabShowAllButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("看全部（\(count)）")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CompetencyPalette.trait)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 不用學的系統那一行

private struct CompTabSkippedLine: View {
    let text: String
    let canEdit: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "minus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if canEdit {
                Button(action: onEdit) {
                    Text("改")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CompetencyPalette.system)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("改不用學的系統")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(minHeight: 48)
        .modifier(CompTabCardStyle())
    }
}

// MARK: - 〔不用學的系統〕sheet

private struct CompTabSkipSheet: View {
    let subordinateId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var skipped: Set<UUID>

    init(subordinateId: UUID, initialSkipped: Set<UUID>) {
        self.subordinateId = subordinateId
        _skipped = State(initialValue: initialSkipped)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(lifeStore.competencySetup.activeSystems) { g in
                        Toggle(g.displayName, isOn: learnBinding(g.id))
                    }
                } header: {
                    Text("要學的系統")
                } footer: {
                    Text("勾掉＝那張雷達不出現、分數留著；勾回來分數都在。")
                }
            }
            .navigationTitle("不用學的系統")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                }
            }
        }
    }

    /// 開著＝要學（不在 skipped 裡）
    private func learnBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { !skipped.contains(id) },
            set: { on in
                if on { skipped.remove(id) } else { skipped.insert(id) }
            }
        )
    }

    /// 先 dismiss，下一個 runloop 再寫 store（已停用系統原本勾掉的，照原樣留在 skipped 裡）
    private func save() {
        let result: Set<UUID> = skipped
        let sid: UUID = subordinateId
        let store: LifeStore = lifeStore
        dismiss()
        DispatchQueue.main.async {
            store.setCompetencySkippedSystems(sid, skipped: result)
        }
    }
}
