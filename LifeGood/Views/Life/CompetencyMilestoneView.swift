import SwiftUI

// MARK: - [v25.607 職能雷達 v5b] 升職快照明細（G1 負責；radar/judge_v5b.md §C1；radar/build/v5b/brief.md §3 G1）
//
// • 入口：〔職能〕分頁評分紀錄上面「升職」一段點一列（只是看，不擋訂閱）。sheet(item:)＋.appStores()。
// • 上面〔那時｜跟現在比〕：那時＝升職前那一份的唯讀雷達（評分紀錄明細同一種畫法、不疊上一次；目標照那時的職等＝升職前）；
//   跟現在比＝現在的卡片（實線）、灰虛線＝升職前那一份。
// • 現算的（以前的升職、還沒留一份）：標「（現算）」一句＋〔留一份〕（擋訂閱；唯讀、已轉出不出現）。
// • 字、數字、雷達全部照 CompetencyMath.milestoneDetail（LifeStore.competencyMilestoneDetail）；寫入只走
//   LifeStore.keepCompetencyPromotionMilestone。§13：一個字的評語都不顯示。不進匯出、不進網頁版。
// • 字不用「他／她」。通知、小工具、手錶、鎖定畫面、靈動島一個字都不加。
// 骨架（主控）：CompetencyMilestoneRequest、CompetencyMilestoneView(subordinateId:promotionId:) 是跨組契約（〔職能〕分頁在叫），
// 不准改；body 由 G1 換成真的。自己加的型別一律 private、CompMile… 前綴。
// G1（v5b）：body 換成真的——拆成 CompMile… 小 View（那時、跟現在比、現算＋〔留一份〕、iPad 兩欄）；只叫 competencyMilestoneDetail 與
// keepCompetencyPromotionMilestone 兩支，不寫其他 store。
// 要退回這一件：這個檔連同 pbxproj 四處（A01A／A01B000001001650）拿掉，叫它的那幾行拿掉。

/// 打開升職快照明細（sheet(item:)；每次新的 id）
struct CompetencyMilestoneRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
    /// 升職紀錄 id（PromotionRecord.id＝CompetencyPromotionRow.id）
    let promotionId: UUID
}

struct CompetencyMilestoneView: View {
    let subordinateId: UUID
    let promotionId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// 〔那時｜跟現在比〕（只是看，不記住）
    @State private var compareNow = false
    @State private var showPremiumAlert = false
    /// 剛〔留一份〕：「已留一份 7/1 升職前的職能分數」
    @State private var keptLine: String?

    /// 明細（CompetencyMath.milestoneDetail；body 只叫一次；這筆升職不在了 nil）
    private var detail: CompetencyMilestoneDetailModel? {
        lifeStore.competencyMilestoneDetail(of: subordinateId, promotionId: promotionId)
    }

    /// 〔留一份〕：唯讀那台、已轉出不出現（跟〔職能〕分頁同條件）
    private var canKeep: Bool {
        !lifeStore.competencyReadOnly && !OrgMoveIndex.isArchived(subordinateId)
    }

    var body: some View {
        let d: CompetencyMilestoneDetailModel? = detail
        let keep: Bool = canKeep
        return NavigationStack {
            ScrollView {
                CompMileContent(detail: d,
                                keptLine: keptLine,
                                canKeep: keep,
                                compareNow: $compareNow,
                                onKeep: keepMilestone)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("升職前的樣子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    /// 〔留一份〕（擋訂閱）：現算的那一份存起來；不 dismiss，寫完 detail 自己變成不是現算
    private func keepMilestone() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        let row: CompetencyPromotionRow? = lifeStore.competencyPromotionRows(of: subordinateId).first { $0.id == promotionId }
        if lifeStore.keepCompetencyPromotionMilestone(subordinateId, promotionId: promotionId), let r = row {
            keptLine = CompetencyMath.milestoneKeptToast(r, today: CompetencyMath.dayKey(Date()))
        }
    }
}

/// 整頁內容：剛留一份那一行 →〔那時｜跟現在比〕→ 那時／跟現在比 → 現算的一句＋〔留一份〕
private struct CompMileContent: View {
    let detail: CompetencyMilestoneDetailModel?
    let keptLine: String?
    let canKeep: Bool
    @Binding var compareNow: Bool
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let k = keptLine {
                CompMileKeptLine(text: k)
            }
            if let d = detail {
                CompMileModePicker(compareNow: $compareNow)
                if compareNow {
                    CompMileCompareSection(detail: d)
                } else {
                    CompMileThenSection(detail: d)
                }
                if d.computed {
                    CompMileComputedSection(line: d.computedLine, canKeep: canKeep, onKeep: onKeep)
                }
            } else {
                Text("這筆升職紀錄已經不在了")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
    }
}

/// 剛〔留一份〕：一行綠字
private struct CompMileKeptLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.green)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.green)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

/// 〔那時｜跟現在比〕（只是看）
private struct CompMileModePicker: View {
    @Binding var compareNow: Bool

    var body: some View {
        Picker("看哪一種", selection: $compareNow) {
            Text("那時").tag(false)
            Text("跟現在比").tag(true)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }
}

/// 〔那時〕：標題＋資訊行、對不到職等表一行橘字、那時的雷達（不疊上一次；目標照那時的職等）
private struct CompMileThenSection: View {
    let detail: CompetencyMilestoneDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CompMileTitleLines(title: detail.title, lines: detail.infoLines)
            if let note = detail.gradeNote {
                CompMileGradeNote(text: note)
            }
            CompMileGrid(cards: detail.cards, showPrevious: false)
        }
    }
}

/// 〔跟現在比〕：說明一行＋現在的卡片（實線）疊升職前那一份（灰虛線）
private struct CompMileCompareSection: View {
    let detail: CompetencyMilestoneDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(detail.compareExplain)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
            CompMileGrid(cards: detail.compareCards, showPrevious: true)
        }
    }
}

/// 標題「升 E3 前的樣子・7/1」＋資訊行（照評分紀錄明細 CompHistTitleLines 的樣子）
private struct CompMileTitleLines: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            ForEach(Array(lines.enumerated()), id: \.offset) { pair in
                Text(pair.element)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

/// 那時的職稱對不到職等表：一行橘字（不疊目標）
private struct CompMileGradeNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

/// 現算的（還沒留一份）：一句說明＋〔留一份〕（唯讀、已轉出不出現）
private struct CompMileComputedSection: View {
    let line: String?
    let canKeep: Bool
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let l = line {
                Text(l)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canKeep {
                CompMileKeepButton(action: onKeep)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

/// 〔留一份〕（擋訂閱在 CompetencyMilestoneView.keepMilestone）
private struct CompMileKeepButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("留一份")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(CompetencyPalette.trait)
        .accessibilityHint("把升職前的職能分數存下來")
    }
}

/// 雷達卡：iPad（.regular）兩欄、iPhone 一欄；明細只是看（不傳 onTapAxis）
private struct CompMileGrid: View {
    let cards: [CompetencyChartModel]
    let showPrevious: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let columns: [GridItem] = [GridItem(.adaptive(minimum: 300, maximum: 360), spacing: 16)]

    var body: some View {
        if horizontalSizeClass == .regular {
            LazyVGrid(columns: Self.columns, alignment: .center, spacing: 16) {
                ForEach(cards) { card in
                    CompetencyChartCard(model: card, showPrevious: showPrevious)
                }
            }
            .padding(.horizontal)
        } else {
            VStack(spacing: 16) {
                ForEach(cards) { card in
                    CompetencyChartCard(model: card, showPrevious: showPrevious)
                        .padding(.horizontal)
                }
            }
        }
    }
}
