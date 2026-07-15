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
// [2026-07 v2] 一致性 + 大字自適應細節補強（本元件被 6 個履歷頁共用，此處統一即全 App 一致）：
//   A. giftRow 28pt 圖示圓補 Circle().stroke(accent.opacity(0.20), 0.75pt) 細邊框，
//      對齊本檔總計列（34pt）/ 分類列（32pt）圖示圓皆已有的描邊規格，避免同頁三種圓形只有一種缺邊框。
//   B. 總計 / 分類 / giftRow 三處金額 Text 補 .lineLimit(1) + .minimumScaleFactor(0.65)，
//      家族禮金總額進入「億」量級時可自動縮字不裁切，不會小到無法辨識。
//   C. giftRow 補交錯淡入 + 向上進場動畫（沿用 rowsAppeared 旗標，依攤平後索引 stagger），
//      對齊 SpouseResumeView.milestoneRow / expenseRow 已有的列表進場動畫規格。
//   D. 移除從未被呼叫的 formatCurrency 死碼（金額顯示已全面改用 .ntdWanString）。
// [2026-07 v3] giftRow 左側強調色條：
//   • giftRow 原本圖示圓直接貼齊卡片左緣，同頁其他列式元件（分類/總計）已用漸層 Capsule
//     側條標示層級，giftRow 卻沒有，是本元件最後一處視覺不均衡；補上 3pt 粉紅漸層
//     RoundedRectangle 側條（對齊 header 側條配色，高度貼合列高），
//     讓「總計列 → 分類列 → giftRow」三層級都能一眼辨識屬於同一組禮金清單。
//   • 純視覺加強，未動任何禮金資料或分類邏輯。
// [2026-07 v4] 分類 DisclosureGroup 展開/收合箭頭：
//   • 系統預設箭頭固定灰階，與本元件粉紅主題不一致，且展開時內容是「跳出」沒有淡入；
//     新增 AccentChevronDisclosureGroupStyle 自訂樣式，箭頭改為粉紅主題色、
//     隨展開狀態以 spring 動畫平滑旋轉 90 度，展開內容補上淡入 + 由上滑入的過場，
//     整體與 header/總計/giftRow 的粉紅視覺語言一致。
//   • 純視覺加強，未動任何禮金篩選、分組或金額邏輯，展開/收合狀態行為不變。
//   （下次美化本元件時，可從這裡接著找其他可統一之處）

/// 履歷頁通用：列出某人收到的禮金紀錄，依社交子分類分組顯示。
struct ResumeGiftSection: View {
    let gifts: [Expense]
    let recipientName: String

    // [v2] giftRow 交錯進場動畫旗標
    @State private var rowsAppeared = false

    // 靜態共用格式器，避免每次 render 重新分配昂貴的 DateFormatter
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(accent.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.75))
            }
            .padding(.vertical, 4)

            // 各子分類 DisclosureGroup
            ForEach(byCategory, id: \.sub) { group in
                DisclosureGroup {
                    ForEach(Array(group.items.prefix(20).enumerated()), id: \.element.id) { rowIdx, exp in
                        giftRow(exp)
                            .opacity(rowsAppeared ? 1 : 0)
                            .offset(y: rowsAppeared ? 0 : 10)
                            .animation(
                                .spring(response: 0.44, dampingFraction: 0.82)
                                    .delay(0.03 * Double(min(rowIdx, 12))),
                                value: rowsAppeared
                            )
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
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                    }
                }
                .disclosureGroupStyle(AccentChevronDisclosureGroupStyle(tint: accent))
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
        // onAppear/onDisappear 掛在 Section 本身（而非總計列 HStack）：本元件被嵌入外層 List，
        // 若掛在總計列上，List 延遲載入使該列可能單獨捲出/捲入可視範圍，反覆觸發會讓
        // 所有子分類 giftRow 共用的 rowsAppeared 旗標被重置，捲動時無謂淡出又重播進場動畫。
        // 改掛在 Section 本身，確保只在畫面進出時各觸發一次。
        .onAppear {
            // [v2-C] 觸發 giftRow 交錯進場動畫
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                rowsAppeared = true
            }
        }
        .onDisappear {
            // 重置旗標：切到其他分頁再切回時能重新播放禮金列表進場動畫
            rowsAppeared = false
        }
    }

    // giftRow：3pt 漸層側條 + 28pt 漸層圖示圓 + 日期 Capsule 膠囊 + 付款人 Capsule 標籤
    private func giftRow(_ e: Expense) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // [v3] 左側強調色條，對齊 header 漸層 Capsule 側條配色，統一總計/分類/giftRow 三層級視覺語言
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.85), accent.opacity(0.30)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 28)

            // 28pt 粉紅漸層圖示圓 [v2-A] 補 stroke 細邊框，對齊本檔總計/分類圖示圓描邊規格
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
                Circle()
                    .stroke(accent.opacity(0.20), lineWidth: 0.75)
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
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}

// MARK: - 展開/收合箭頭樣式（[v4] 箭頭改為主題色 + spring 平滑旋轉，內容補淡入滑入過場）
private struct AccentChevronDisclosureGroupStyle: DisclosureGroupStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 0) {
                    configuration.label
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.70))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
