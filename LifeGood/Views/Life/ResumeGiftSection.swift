import SwiftUI

// MARK: - 美化紀錄（ResumeGiftSection）
// [2026-06] 本次美化方向：
//   1. Section header：升級為「4pt 粉紅漸層 Capsule 側條 + .subheadline.weight(.bold) 標題
//      + 粉紅計數膠囊徽章 + .textCase(nil)」，對齊 LifeOverviewView.milestoneTimelineSection 標題規格。
//   2. 總計列：34pt 粉紅漸層圖示圓（gift.fill）+ 金額改為粉紅 Capsule 膠囊標籤，
//      對齊 FinanceChartView insuranceSummarySection 彙總列設計語言。
//   3. 分類 DisclosureGroup 標題：加入 32pt LinearGradient 漸層圖示圓（子分類 icon） +
//      粉紅計數膠囊 + 金額以 .ntdWanString 顯示，
//      對齊 IncomeView.incomeRow / CareerView.subCategoryBreakdown 規格。
//   4. giftRow：加入 28pt 粉紅漸層圖示圓 + 日期改為粉紅 Capsule 膠囊徽章 +
//      付款人改為小型 Capsule 標籤，對齊 SpouseResumeView.expenseRow 視覺規格；
//      金額改用 .ntdWanString，支援萬/億量級自動切換，防止長數字溢出。
//   5. 靜態 NumberFormatter / DateFormatter 共用實例，避免每次 render 重新分配（效能優化），
//      對齊 SpouseResumeView / ChildDetailView 靜態格式器設計規格。

/// 履歷頁通用：列出某人收到的禮金紀錄，依社交子分類分組顯示。
struct ResumeGiftSection: View {
    let gifts: [Expense]
    let recipientName: String

    // 靜態共用格式器，避免每次 render 重新分配昂貴的 NumberFormatter/DateFormatter
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    // 粉紅主題色（女/愛情/禮物一致配色）
    private let accent = Color(red: 0.96, green: 0.35, blue: 0.60)

    private var byCategory: [(sub: SocialSubCategory, items: [Expense])] {
        let grouped = Dictionary(grouping: gifts) { $0.socialSubCategory ?? .other }
        return SocialSubCategory.allCases.compactMap { sub in
            if let items = grouped[sub], !items.isEmpty { return (sub, items) }
            return nil
        }
    }

    private var totalAmount: Double {
        gifts.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        Section {
            // 禮金總計列：34pt 漸層圖示圓 + 粉紅 Capsule 金額標籤
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(accent.opacity(0.22), lineWidth: 1))
                    Image(systemName: "gift.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Text("禮金總計")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(totalAmount.ntdWanString)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(accent.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.75))
            }
            .padding(.vertical, 4)

            // 各子分類 DisclosureGroup
            ForEach(byCategory, id: \.sub) { group in
                DisclosureGroup {
                    ForEach(group.items.prefix(20)) { exp in
                        giftRow(exp)
                    }
                    if group.items.count > 20 {
                        Text("還有 \(group.items.count - 20) 筆…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 46)
                    }
                } label: {
                    HStack(spacing: 10) {
                        // 32pt LinearGradient 漸層圖示圓（子分類 icon）
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [accent.opacity(0.20), accent.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(accent.opacity(0.18), lineWidth: 1))
                            Image(systemName: group.sub.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(accent)
                        }

                        Text(group.sub.rawValue)
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        // 計數膠囊 + 金額
                        HStack(spacing: 6) {
                            Text("\(group.items.count) 筆")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(accent.opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(accent.opacity(0.18), lineWidth: 0.6))

                            Text(group.items.reduce(0) { $0 + $1.amount }.ntdWanString)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(accent)
                        }
                    }
                }
            }
        } header: {
            // Capsule 側條 + 標題 + 計數膠囊（對齊 LifeOverviewView section header 規格）
            HStack(spacing: 8) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.50)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 16)
                Text("收到的禮金")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if !gifts.isEmpty {
                    Text("\(gifts.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(accent.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.75))
                }
            }
            .textCase(nil)
        } footer: {
            Text("變動支出分類選「社交」並把「\(recipientName)」加入收受人，會自動同步到此區塊。")
        }
    }

    // giftRow：28pt 漸層圖示圓 + 日期 Capsule 膠囊 + 付款人 Capsule 標籤
    private func giftRow(_ e: Expense) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // 28pt 粉紅漸層圖示圓
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.16), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: "gift")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accent.opacity(0.80))
            }

            VStack(alignment: .leading, spacing: 3) {
                if !e.title.isEmpty {
                    Text(e.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    // 日期改為粉紅 Capsule 膠囊徽章
                    Text(formatDate(e.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent.opacity(0.80))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(accent.opacity(0.08))
                        .clipShape(Capsule())

                    if let payer = e.diningMember, !payer.isEmpty {
                        Text(payer)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 4)

            Text(e.amount.ntdWanString)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 4)
    }

    private func formatCurrency(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}
