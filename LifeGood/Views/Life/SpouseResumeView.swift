import SwiftUI

struct SpouseResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore

    private var spouse: FamilyMember? {
        lifeStore.familyMembers.first { $0.role == .spouse }
    }

    /// 變動支出中，diningMember 含有配偶名字的紀錄
    private var spouseExpenses: [Expense] {
        guard let s = spouse, !s.chineseName.isEmpty else { return [] }
        let target = s.chineseName
        return expenseStore.expenses
            .filter { $0.expenseType == .variable }
            .filter { e in
                guard let raw = e.diningMember, !raw.isEmpty else { return false }
                let names = raw.split(separator: "、").map { String($0).trimmingCharacters(in: .whitespaces) }
                return names.contains(target)
            }
            .sorted { $0.date > $1.date }
    }

    private var spouseExpenseTotal: Double {
        spouseExpenses.reduce(0) { $0 + $1.amount }
    }

    /// 變動支出 .social 中將配偶列為收受人的紀錄
    private var spouseGifts: [Expense] {
        guard let s = spouse, !s.chineseName.isEmpty else { return [] }
        let target = s.chineseName
        return expenseStore.expenses
            .filter { $0.expenseType == .variable && $0.variableCategory == .social }
            .filter { e in
                guard let raw = e.socialRecipient, !raw.isEmpty else { return false }
                let names = raw.components(separatedBy: CharacterSet(charactersIn: ",、，"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                return names.contains(target)
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if let s = spouse {
                    profileSection(s)
                    marriageSection(s)
                    milestoneSection
                    giftSection
                    expenseSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("配偶履歷")
        }
    }

    @ViewBuilder
    private var giftSection: some View {
        if !spouseGifts.isEmpty {
            ResumeGiftSection(gifts: spouseGifts, recipientName: spouse?.chineseName ?? "配偶")
        }
    }

    private func profileSection(_ s: FamilyMember) -> some View {
        Section("個人資料") {
            HStack {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 4) {
                    if !s.chineseName.isEmpty {
                        Text(s.chineseName).font(.title3.weight(.semibold))
                    }
                    if !s.englishName.isEmpty {
                        Text(s.englishName).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func marriageSection(_ s: FamilyMember) -> some View {
        Section("婚姻紀錄") {
            if let md = s.marriageDate {
                HStack {
                    Label("結婚日期", systemImage: "calendar.badge.checkmark")
                    Spacer()
                    Text(formatDate(md)).foregroundStyle(.secondary)
                }
                HStack {
                    Label("結婚年數", systemImage: "clock")
                    Spacer()
                    let years = Calendar.current.dateComponents([.year, .month], from: md, to: Date())
                    Text("\(years.year ?? 0) 年 \(years.month ?? 0) 月").foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Label("結婚日期", systemImage: "calendar")
                    Spacer()
                    Text("未填寫").foregroundStyle(.tertiary)
                }
            }
            if s.isDivorced {
                HStack {
                    Label("已離婚", systemImage: "heart.slash")
                        .foregroundStyle(.red)
                    Spacer()
                    if let dd = s.divorceDate {
                        Text(formatDate(dd)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var milestoneSection: some View {
        Section("相關里程碑") {
            let derived = lifeStore.familyDerivedMilestones
                .filter { $0.category == .marriage }
                .sorted { $0.date > $1.date }
            if derived.isEmpty {
                Text("尚無相關里程碑").font(.subheadline).foregroundStyle(.tertiary)
            } else {
                ForEach(derived) { m in
                    HStack {
                        Image(systemName: m.title.contains("結婚") ? "heart.fill" : "heart.slash.fill")
                            .foregroundStyle(m.title.contains("結婚") ? .pink : .gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).font(.subheadline)
                            Text(formatDate(m.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 消費

    @ViewBuilder
    private var expenseSection: some View {
        Section {
            if spouseExpenses.isEmpty {
                Text("尚無共同消費紀錄")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                HStack {
                    Label("總計", systemImage: "sum")
                    Spacer()
                    Text(formatCurrency(spouseExpenseTotal))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                ForEach(spouseExpenses.prefix(20)) { e in
                    expenseRow(e)
                }
                if spouseExpenses.count > 20 {
                    Text("還有 \(spouseExpenses.count - 20) 筆…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("消費")
        } footer: {
            Text("變動支出中將「\(spouse?.chineseName ?? "配偶")」加入人員的紀錄會自動同步到此。")
        }
    }

    private func expenseRow(_ e: Expense) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: e.variableCategory?.icon ?? "questionmark.circle")
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title.isEmpty ? (e.variableCategory?.rawValue ?? "未分類") : e.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(formatDate(e.date)).font(.caption2).foregroundStyle(.tertiary)
                    if let cat = e.variableCategory {
                        Text(cat.rawValue).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let raw = e.diningMember, !raw.isEmpty {
                        Text(raw).font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Text(formatCurrency(e.amount))
                .font(.subheadline.bold())
                .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: d)
    }
}
