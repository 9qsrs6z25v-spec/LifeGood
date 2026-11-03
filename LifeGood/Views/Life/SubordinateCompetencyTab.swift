import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 部屬卡片〔職能〕分頁（G1 負責；radar/judge.md §4.3、§5、§6、§3.6；radar/build/v1a-1/brief.md §4 G1）
//
// • 由上到下：摘要卡（不寫 0–100）→ 人格特質卡（0 項整張不出現）→ 每個系統一張 → 不用學的系統一行。
// • 看不擋；〔評分〕〔不用學的系統〕〔用範例開始〕〔自己設定〕要訂閱（isPremium／premiumLockAlert）。
// • 已轉出：〔評分〕藏起來、「已轉出，評分留著可以看」；這台的 App 比較舊：〔評分〕藏起來、頂上一行說明。
// • 整頁的數字、字只照 CompetencyMath.tabModel；sheet 一律 sheet(item:)＋.appStores()；dismiss 後寫 store 放下一個 runloop。
// • 這個 View 不包 ScrollView（明細頁外面已經有）；白卡、外距自己加。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G1 換成真的。

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
                           showsOverlayToggle: Self.hasAnyPrevious(m),
                           overlayLabel: Self.overlayLabel(m),
                           showPrevious: $showPrevious,
                           onRate: startRating,
                           onSkip: openSkipSheet,
                           onSetup: openSetup)
        ForEach(m.cards) { card in
            CompetencyChartCard(model: card, showPrevious: showPrevious, onTapAxis: nil)
                .padding(.horizontal)
        }
        if hasSystems {
            CompTabSkippedLine(text: Self.skippedLineText(m.skippedNames),
                               canEdit: canRate,
                               onEdit: openSkipSheet)
        }
    }

    // MARK: 小函式（純；body 不寫長運算式）

    private static func hasAnyPrevious(_ m: CompetencyTabModel) -> Bool {
        m.cards.contains { $0.hasPrevious }
    }

    /// 疊的膠囊「上一次 4/30」（judge §4.3①）；各張卡的上一次不是同一天（或沒有日期）就只寫「上一次」
    private static func overlayLabel(_ m: CompetencyTabModel) -> String {
        let days: Set<String> = Set(m.cards.filter { $0.hasPrevious }.compactMap { $0.legendPrevious })
        guard days.count == 1, let d = days.first else { return "上一次" }
        return "上一次 " + d
    }

    /// 「不用學：（無）」「不用學：Gas System、Chemical System」
    private static func skippedLineText(_ names: [String]) -> String {
        if names.isEmpty { return "不用學：（無）" }
        return "不用學：" + names.joined(separator: "、")
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
}

/// 一格（字級照 FinanceTileView：.caption2 標籤／.headline rounded heavy 數字／.caption2 小字）
private struct CompTabTile: View {
    let label: String
    let value: String
    let valueDim: Bool
    let sub: String?
    let subColor: Color

    /// ↑ 綠、↓ 橘、其他灰
    static func deltaColor(_ text: String?) -> Color {
        guard let t = text else { return Color.secondary }
        if t.hasPrefix("↑") { return Color.green }
        if t.hasPrefix("↓") { return Color.orange }
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
