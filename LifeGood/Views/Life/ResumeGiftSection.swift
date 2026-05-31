import SwiftUI

/// 履歷頁通用：列出某人收到的禮金紀錄，依社交子分類分組顯示。
struct ResumeGiftSection: View {
    let gifts: [Expense]
    let recipientName: String

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
            HStack {
                Label("總計", systemImage: "gift.fill")
                    .foregroundStyle(.pink)
                Spacer()
                Text(formatCurrency(totalAmount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.pink)
            }
            ForEach(byCategory, id: \.sub) { group in
                DisclosureGroup {
                    ForEach(group.items.prefix(20)) { exp in
                        giftRow(exp)
                    }
                    if group.items.count > 20 {
                        Text("還有 \(group.items.count - 20) 筆…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: group.sub.icon)
                            .foregroundStyle(.pink)
                            .frame(width: 22)
                        Text(group.sub.rawValue)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(group.items.count) 筆")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(formatCurrency(group.items.reduce(0) { $0 + $1.amount }))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text("收到的禮金")
        } footer: {
            Text("變動支出分類選「社交」並把「\(recipientName)」加入收受人，會自動同步到此區塊。")
        }
    }

    private func giftRow(_ e: Expense) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                if !e.title.isEmpty {
                    Text(e.title).font(.subheadline.weight(.medium)).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(formatDate(e.date)).font(.caption2).foregroundStyle(.tertiary)
                    if let payer = e.diningMember, !payer.isEmpty {
                        Text("付款：\(payer)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Text(formatCurrency(e.amount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}
