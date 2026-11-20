import SwiftUI

// MARK: - [v25.605 職能雷達 v4b] 給對方看（一對一時把手機轉過去；radar/judge_v4b.md §C1；radar/build/v4b/brief.md §3 G1）
//
// • 〔職能〕分頁右上「…」〔給對方看〕打開：fullScreenCover(item:)＋.appStores()（SubordinateCompetencyTab 那一邊）。
// • 只有這位同仁自己的雷達、橫條、目標線：模型一律照 CompetencyMath.showModel（＝部屬匯出「職能雷達」今天那一份：
//   不疊上一次、目標一律目前職等）。上方小字「給對方看的畫面」、名字職等「王小明・E2」、下面一句「評分日 10/30」。
// • 不顯示：其他人、潛力、主動性、綜合分數、互評、0–100、評分紀錄、總評、評語（§13）、差距清單、任何會改東西的按鈕；
//   點一格沒反應（CompetencyChartCard 的 onTapAxis 傳 nil）。
// • 字大一級（dynamicTypeSize 往上一級，最大到 accessibility2）。右上〔結束〕；interactiveDismissDisabled(true)。
// • iPad（.regular）兩欄（同〔職能〕分頁的固定兩欄），iPhone 一欄。深色模式照系統。
// • 這個檔不寫任何 store；通知、小工具、手錶、鎖定畫面、靈動島一個字都不碰。
// 骨架（主控）：CompetencyShowRequest、CompetencyShowView(subordinateId:) 是跨組契約，不准改；body 由 G1 換成真的。
// 要退回這一件：這個檔連同 pbxproj 四處（A01A／A01B000001001647）拿掉，〔職能〕分頁「…」的〔給對方看〕那幾行拿掉。

/// 〔給對方看〕（fullScreenCover(item:)；每次新的 id）
struct CompetencyShowRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
}

struct CompetencyShowView: View {
    let subordinateId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 整頁的字、卡片（CompetencyMath.showModel；body 只叫一次）
    private var model: CompetencyShowModel {
        let name: String = lifeStore.subordinates.first(where: { $0.id == subordinateId })?.name ?? ""
        return CompetencyMath.showModel(setup: lifeStore.competencySetup,
                                        subordinateId: subordinateId,
                                        name: name,
                                        archivedPerson: OrgMoveIndex.isArchived(subordinateId),
                                        sessions: lifeStore.competencySessions(of: subordinateId),
                                        today: CompetencyMath.dayKey(Date()),
                                        grades: lifeStore.competencyGradeContext(for: subordinateId))
    }

    /// 字大一級（最大 accessibility2；已經比 accessibility2 大的照原樣）
    static func bumped(_ s: DynamicTypeSize) -> DynamicTypeSize {
        let all: [DynamicTypeSize] = DynamicTypeSize.allCases
        guard s < .accessibility2, let i = all.firstIndex(of: s), i + 1 < all.count else { return s }
        return min(all[i + 1], .accessibility2)
    }

    var body: some View {
        let m: CompetencyShowModel = model
        let regular: Bool = horizontalSizeClass == .regular
        return NavigationStack {
            ScrollView {
                CompShowContent(model: m, regular: regular)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("結束") { dismiss() }
                }
            }
        }
        .dynamicTypeSize(CompetencyShowView.bumped(typeSize))
        .interactiveDismissDisabled(true)
    }
}

// MARK: - 畫面（純看；沒有任何會改東西的按鈕）

/// 上方小字、名字職等 → 卡片（iPad 兩欄、iPhone 一欄）→ 評分日
private struct CompShowContent: View {
    let model: CompetencyShowModel
    let regular: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CompShowHeader(title: model.title)
            CompShowCards(cards: model.cards, regular: regular)
            if !model.hasRatings {
                Text("還沒有評分")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let line = model.ratedLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 「給對方看的畫面」＋「王小明・E2」
private struct CompShowHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("給對方看的畫面")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// 每組一張（不疊上一次；點了沒反應）
private struct CompShowCards: View {
    let cards: [CompetencyChartModel]
    let regular: Bool

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    var body: some View {
        if regular {
            LazyVGrid(columns: CompShowCards.columns, spacing: 16) {
                ForEach(cards) { card in
                    CompetencyChartCard(model: card, showPrevious: false, onTapAxis: nil)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(cards) { card in
                    CompetencyChartCard(model: card, showPrevious: false, onTapAxis: nil)
                }
            }
        }
    }
}
