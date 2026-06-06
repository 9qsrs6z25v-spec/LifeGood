import SwiftUI
import PhotosUI
import MapKit

// MARK: - 美化紀錄（ChildDetailView）
// [2026-06] 本次美化方向：
//   1. headerCard → 升級為漸層英雄卡片（男孩藍 / 女孩粉）：88pt 大圖示圓 + 散景裝飾圓 +
//      姓名 .title2.bold（白色），年齡改為白色 Capsule 膠囊、生日加 calendar 圖示，
//      角色標籤從 RoundedRectangle(cornerRadius:4) 升級為 Capsule；
//      加入 headerAppeared spring 進場動畫（透明度 + Y 位移），對齊 SpouseResumeView heroCard。
//   2. detailTab 切換器 → 從系統 .segmented 升級為 @Namespace + matchedGeometryEffect 自訂 Capsule Pill，
//      日常→藍色（sun.max.fill）、生涯→橘色（star.fill），對齊 RealEstateDetailView.tabPicker 規格。
//   3. dailySection / recordSection header → 加入 Capsule 漸層側條 + 計數膠囊徽章 + .subheadline.semibold 標題 +
//      彩色漸層圖示；Divider 改為 Rectangle fill(separator.opacity(0.20))，
//      對齊 LifeOverviewView.milestoneTimelineSection / OverviewView.categoryBreakdownSection 標題規格。
//   4. dailyRow 圖示 → 從 20pt 純色升級為 30pt LinearGradient 漸層圓（對齊 ExpenseRow 圖示規格）；
//      ml 數值改為彩色膠囊標籤，對齊 ChildrenResumeView.recordBadge 規格。
//   5. recordRow → 圖示升級為 30pt 漸層圓；allergy/vaccination 子標籤從 RoundedRectangle(cornerRadius:3)
//      升級為 Capsule，對齊 ChildrenResumeView / VehicleView vehicleCard 膠囊規格。
//   6. consumptionSection / childGiftsSection header → 加入 Capsule 漸層側條 + 計數膠囊；
//      consumptionRow 圖示升級為 30pt 漸層圓；分類標籤升級為 Capsule 膠囊。
//   7. DateFormatter 改為靜態共用實例，避免每次 render 重新分配，對齊 SpouseResumeView 規格。
//   8. contentAppeared 交錯進場動畫：tab 切換時重置並重播，
//      對齊 CareerView.milestoneListSection / VariableExpenseView.expenseListSections 規格。
//   9. 各卡片加 overlay 細邊框（accent.opacity(0.08) + 0.75pt）+ 雙層陰影，深色模式相容。

struct ChildDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    @State private var addingType: ChildRecordType?
    @State private var editingRecord: ChildRecord?
    @State private var addingDailyType: DailyRecordType?
    @State private var editingDaily: DailyRecord?
    @State private var showPremiumAlert = false

    // 進場動畫旗標
    @State private var headerAppeared = false
    @State private var contentAppeared = false
    // matchedGeometryEffect：tab 切換指示器平滑滑動
    @Namespace private var tabNamespace

    // 靜態 DateFormatter 共用實例（避免每次 render 重新分配）
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f
    }()
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    // 靜態貨幣格式器
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    enum DetailTab: String, CaseIterable {
        case daily = "日常"
        case life = "生涯"
    }
    @State private var detailTab: DetailTab = .life

    init(child: FamilyMember) {
        self.childId = child.id
    }

    private var child: FamilyMember {
        lifeStore.familyMembers.first(where: { $0.id == childId })
            ?? FamilyMember(role: .son)
    }

    private var displayName: String {
        if !child.chineseName.isEmpty { return child.chineseName }
        if !child.englishName.isEmpty { return child.englishName }
        return child.role.rawValue
    }

    private var ageString: String {
        guard let bd = child.birthday else { return "" }
        let c = Calendar.current.dateComponents([.year, .month], from: bd, to: Date())
        let y = c.year ?? 0, m = c.month ?? 0
        return y > 0 ? "\(y) 歲 \(m) 個月" : "\(m) 個月"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                headerAppeared = true
                            }
                        }

                    // 自訂 Capsule Tab 切換器（matchedGeometryEffect 讓指示器平滑滑動）
                    HStack(spacing: 0) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                                    detailTab = tab
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tab == .daily ? "sun.max.fill" : "star.fill")
                                        .font(.caption2)
                                    Text(tab.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 9)
                                .foregroundStyle(detailTab == tab ? .white : .secondary)
                                .background {
                                    if detailTab == tab {
                                        Capsule()
                                            .fill(tabTint(tab))
                                            .matchedGeometryEffect(id: "detailTabIndicator", in: tabNamespace)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .padding(.horizontal)

                    if detailTab == .daily {
                        dailyContent
                    } else {
                        lifeContent
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(displayName) 履歷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
            .sheet(item: $addingType) { type in
                ChildRecordEditorSheet(childId: childId, type: type, editing: nil)
            }
            .sheet(item: $editingRecord) { rec in
                ChildRecordEditorSheet(childId: childId, type: rec.type, editing: rec)
            }
            .sheet(item: $addingDailyType) { type in
                DailyRecordEditorSheet(childId: childId, type: type, editing: nil)
            }
            .sheet(item: $editingDaily) { rec in
                DailyRecordEditorSheet(childId: childId, type: rec.type, editing: rec)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.12)) {
                    contentAppeared = true
                }
            }
            .onChange(of: detailTab) { _, _ in
                contentAppeared = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                    contentAppeared = true
                }
            }
        }
    }

    private func tabTint(_ tab: DetailTab) -> Color {
        switch tab {
        case .daily: return .blue
        case .life: return .orange
        }
    }

    // MARK: - 英雄資訊卡（漸層背景 + 散景裝飾圓）

    private var headerCard: some View {
        let isSon = child.role == .son
        let gradStart: Color = isSon
            ? Color(red: 0.25, green: 0.55, blue: 0.98)
            : Color(red: 0.96, green: 0.38, blue: 0.62)
        let gradEnd: Color = isSon
            ? Color(red: 0.14, green: 0.36, blue: 0.82)
            : Color(red: 0.78, green: 0.20, blue: 0.50)

        return HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                // 角色 + 年齡膠囊
                HStack(spacing: 6) {
                    Text(child.role.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                    if !ageString.isEmpty {
                        Text(ageString)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(.white.opacity(0.16))
                            .clipShape(Capsule())
                    }
                }
                // 姓名
                Text(displayName)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // 生日（calendar 圖示 + 日期文字）
                if let bd = child.birthday {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(Self.dateFormatter.string(from: bd))
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.78))
                }
            }
            Spacer()
            // 右側大圖示圓（雙層同心圓製造層次）
            ZStack {
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 86, height: 86)
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 74, height: 74)
                Image(systemName: "figure.child.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [gradStart, gradEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上散景裝飾圓
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 130, height: 130)
                    .offset(x: 75, y: -50)
                    .blur(radius: 14)
                // 左下補光
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .offset(x: -60, y: 50)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: gradEnd.opacity(0.42), radius: 18, x: 0, y: 9)
        .padding(.horizontal)
    }

    // MARK: - 日常頁面（含交錯進場動畫）

    @ViewBuilder
    private var dailyContent: some View {
        ForEach(Array(DailyRecordType.allCases.enumerated()), id: \.element) { idx, type in
            dailySection(type)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82)
                        .delay(0.05 * Double(idx)),
                    value: contentAppeared
                )
        }
        // 消費（依本人名字連動到變動支出）
        consumptionSection
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 14)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.82)
                    .delay(0.05 * Double(DailyRecordType.allCases.count)),
                value: contentAppeared
            )
        // 收到的禮金（依本人名字連動到 .social 變動支出收受人）
        if !childGifts.isEmpty {
            childGiftsSection
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82)
                        .delay(0.05 * Double(DailyRecordType.allCases.count + 1)),
                    value: contentAppeared
                )
        }
    }

    /// 變動支出 .social 中將兒女列為收受人的紀錄
    private var childGifts: [Expense] {
        let target = child.chineseName
        guard !target.isEmpty else { return [] }
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

    private var childGiftsSection: some View {
        let total = childGifts.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 漸層側條 + 計數膠囊 + 合計
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.pink, Color.pink.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: "gift.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.pink)
                Text("收到的禮金")
                    .font(.subheadline.weight(.semibold))
                Text("\(childGifts.count) 筆")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Color.pink.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.pink.opacity(0.22), lineWidth: 0.6))
                Spacer()
                Text(formatCurrency(total))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.pink)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(SocialSubCategory.allCases) { sub in
                let items = childGifts.filter { $0.socialSubCategory == sub }
                if !items.isEmpty {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.pink.opacity(0.14))
                                .frame(width: 28, height: 28)
                            Image(systemName: sub.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.pink)
                        }
                        Text(sub.rawValue).font(.subheadline)
                        Spacer()
                        Text("\(items.count) 筆")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(formatCurrency(items.reduce(0) { $0 + $1.amount }))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.pink)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    Rectangle()
                        .fill(Color(.separator).opacity(0.20))
                        .frame(height: 0.5)
                        .padding(.leading, 50)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.pink.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }


    private func dailySection(_ type: DailyRecordType) -> some View {
        let accent = dailyColor(type)
        let items = child.dailyRecords.filter { $0.type == type }.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 側條 + 彩色圖示 + 標題 + 計數膠囊 + 新增按鈕
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(type.rawValue)
                    .font(.subheadline.weight(.semibold))
                if !items.isEmpty {
                    Text("\(items.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                Button {
                    if subscription.isPremium { addingDailyType = type }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("尚無記錄")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            } else {
                ForEach(Array(items.prefix(20).enumerated()), id: \.element.id) { idx, rec in
                    Button {
                        if subscription.isPremium { editingDaily = rec }
                        else { showPremiumAlert = true }
                    } label: {
                        dailyRow(rec)
                    }
                    .buttonStyle(.plain)
                    if idx < min(items.count, 20) - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5)
                            .padding(.leading, 50)
                    }
                }
                if items.count > 20 {
                    Text("還有 \(items.count - 20) 筆...")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func dailyRow(_ rec: DailyRecord) -> some View {
        let accent = dailyColor(rec.type)
        return HStack(spacing: 12) {
            // 30pt 漸層圖示圓（對齊 ExpenseRow 規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: rec.type.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                switch rec.type {
                case .milk:
                    HStack(spacing: 6) {
                        if let brand = rec.milkBrand, !brand.isEmpty {
                            Text(brand).font(.subheadline.weight(.medium))
                        }
                        if let ml = rec.mlAmount, ml > 0 {
                            // ml 數值改為彩色膠囊標籤
                            Text("\(Int(ml)) ml")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent)
                                .clipShape(Capsule())
                        }
                    }
                case .food:
                    HStack(spacing: 6) {
                        if let name = rec.foodName, !name.isEmpty {
                            Text(name).font(.subheadline.weight(.medium))
                        }
                        if let ml = rec.mlAmount, ml > 0 {
                            Text("\(Int(ml)) ml")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent)
                                .clipShape(Capsule())
                        }
                    }
                case .sleep:
                    if let end = rec.sleepEnd {
                        let dur = end.timeIntervalSince(rec.date) / 3600
                        Text(String(format: "%@ ~ %@（%.1f 小時）",
                                    Self.timeFormatter.string(from: rec.date),
                                    Self.timeFormatter.string(from: end),
                                    dur))
                            .font(.subheadline.weight(.medium))
                    } else {
                        Text(Self.timeFormatter.string(from: rec.date))
                            .font(.subheadline.weight(.medium))
                    }
                }
                Text(Self.dateTimeFormatter.string(from: rec.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func dailyColor(_ type: DailyRecordType) -> Color {
        switch type {
        case .milk: return .blue
        case .food: return .green
        case .sleep: return .indigo
        }
    }

    // MARK: - 消費（與兒女連動的變動支出）

    private var consumptionExpenses: [Expense] {
        let name = child.chineseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return [] }
        return expenseStore.expenses
            .filter { $0.expenseType == .variable }
            .filter { e in
                guard let raw = e.diningMember, !raw.isEmpty else { return false }
                let names = raw.split(separator: "、").map { String($0).trimmingCharacters(in: .whitespaces) }
                return names.contains(name)
            }
            .sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var consumptionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 漸層側條 + 計數膠囊 + 合計
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                Text("消費")
                    .font(.subheadline.weight(.semibold))
                if consumptionExpenses.count > 0 {
                    Text("\(consumptionExpenses.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.red.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                if !consumptionExpenses.isEmpty {
                    let total = consumptionExpenses.reduce(0) { $0 + $1.amount }
                    Text(formatCurrency(total))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if consumptionExpenses.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(child.chineseName.isEmpty
                         ? "尚未設定姓名，請先填寫中文名字"
                         : "尚無連動的消費紀錄")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            } else {
                ForEach(Array(consumptionExpenses.prefix(20).enumerated()), id: \.element.id) { idx, e in
                    consumptionRow(e)
                    if idx < min(consumptionExpenses.count, 20) - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5)
                            .padding(.leading, 50)
                    }
                }
                if consumptionExpenses.count > 20 {
                    Text("還有 \(consumptionExpenses.count - 20) 筆…")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
            if !child.chineseName.isEmpty {
                Rectangle()
                    .fill(Color(.separator).opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
                Text("變動支出中將「\(child.chineseName)」加入人員會自動同步到此")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func consumptionRow(_ e: Expense) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 30pt 漸層圖示圓
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: e.variableCategory?.icon ?? "questionmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title.isEmpty ? (e.variableCategory?.rawValue ?? "未分類") : e.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Self.shortDateFormatter.string(from: e.date))
                        .font(.caption2).foregroundStyle(.tertiary)
                    if let cat = e.variableCategory {
                        Text(cat.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    if let raw = e.diningMember, !raw.isEmpty {
                        Text(raw).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            Text(formatCurrency(e.amount))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func formatCurrency(_ v: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    // MARK: - 生涯頁面

    @ViewBuilder
    private var lifeContent: some View {
        ForEach(Array(ChildRecordType.allCases.enumerated()), id: \.element) { idx, type in
            recordSection(type)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82)
                        .delay(0.05 * Double(idx)),
                    value: contentAppeared
                )
        }
    }

    // MARK: - 章節（生涯）

    private func recordSection(_ type: ChildRecordType) -> some View {
        let accent = colorFor(type)
        let items = child.childRecords.filter { $0.type == type }.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 漸層側條 + 彩色圖示 + 標題 + 計數膠囊 + 新增按鈕
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(type.rawValue)
                    .font(.subheadline.weight(.semibold))
                if !items.isEmpty {
                    Text("\(items.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                Button {
                    if subscription.isPremium { addingType = type }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("尚無記錄")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, rec in
                    recordRow(rec)
                    if idx < items.count - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5)
                            .padding(.leading, 50)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func recordRow(_ rec: ChildRecord) -> some View {
        let accent = colorFor(rec.type)
        Button {
            if subscription.isPremium { editingRecord = rec }
            else { showPremiumAlert = true }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // 30pt 漸層圖示圓
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                    Image(systemName: rec.type.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(primaryText(rec)).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        if rec.type == .allergy, let sev = rec.severity {
                            // Capsule 標籤（對齊 ChildrenResumeView 規格，取代 RoundedRectangle(cornerRadius:3)）
                            Text(sev.rawValue).font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(severityColor(sev).opacity(0.15))
                                .foregroundStyle(severityColor(sev))
                                .clipShape(Capsule())
                        }
                        if rec.type == .vaccination, let dose = rec.dose, !dose.isEmpty {
                            Text(dose).font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12)).foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    if rec.type == .growth {
                        HStack(spacing: 8) {
                            if let h = rec.heightCm, h > 0 { Text(String(format: "身高 %.1f cm", h)).font(.caption).foregroundStyle(.secondary) }
                            if let w = rec.weightKg, w > 0 { Text(String(format: "體重 %.1f kg", w)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    HStack(spacing: 6) {
                        Text(Self.dateFormatter.string(from: rec.date)).font(.caption2).foregroundStyle(.tertiary)
                        if !rec.detail.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            Text(rec.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }

                // 照片放在 row 右側，依原比例顯示（最大 80×80）
                if rec.photoFileName != nil {
                    let displayURL = rec.sketchURL ?? rec.photoURL
                    if let url = displayURL,
                       let data = try? Data(contentsOf: url),
                       let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 80, maxHeight: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primaryText(_ rec: ChildRecord) -> String {
        rec.type == .growth ? Self.dateFormatter.string(from: rec.date) : (rec.title.isEmpty ? rec.type.rawValue : rec.title)
    }

    private func colorFor(_ type: ChildRecordType) -> Color {
        switch type {
        case .vaccination: return .blue; case .allergy: return .red; case .growth: return .green
        case .medical: return .orange; case .education: return .purple
        case .hobby: return .pink; case .memorable: return .yellow
        }
    }

    private func severityColor(_ s: AllergySeverity) -> Color {
        switch s { case .mild: return .yellow; case .moderate: return .orange; case .severe: return .red }
    }

}

// MARK: - 日常記錄編輯 Sheet

struct DailyRecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let type: DailyRecordType
    var editing: DailyRecord?

    @State private var date = Date()
    @State private var milkBrand = ""
    @State private var mlText = ""
    @State private var foodName = ""
    @State private var sleepEnd = Date()
    @State private var note = ""

    private var canSave: Bool {
        switch type {
        case .milk: return (Double(mlText) ?? 0) > 0
        case .food: return !foodName.trimmingCharacters(in: .whitespaces).isEmpty
        case .sleep: return true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch type {
                case .milk:
                    Section("喝奶記錄") {
                        HStack { Text("時間"); Spacer(); FiveMinuteDateTimePicker(selection: $date).fixedSize() }
                        TextField("奶粉品牌（選填）", text: $milkBrand)
                        HStack { TextField("ml 數", text: $mlText).keyboardType(.numberPad); Text("ml").foregroundStyle(.secondary) }
                    }
                case .food:
                    Section("食物記錄") {
                        HStack { Text("時間"); Spacer(); FiveMinuteDateTimePicker(selection: $date).fixedSize() }
                        TextField("食物名稱", text: $foodName)
                        HStack { TextField("ml 數（選填）", text: $mlText).keyboardType(.numberPad); Text("ml").foregroundStyle(.secondary) }
                    }
                case .sleep:
                    Section("睡眠記錄") {
                        HStack { Text("入睡時間"); Spacer(); FiveMinuteDateTimePicker(selection: $date).fixedSize() }
                        HStack { Text("起床時間"); Spacer(); FiveMinuteDateTimePicker(selection: $sleepEnd, minimumDate: date).fixedSize() }
                        if sleepEnd > date {
                            let hours = sleepEnd.timeIntervalSince(date) / 3600
                            HStack {
                                Text("睡眠時長").foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f 小時", hours)).foregroundStyle(.blue)
                            }
                        }
                    }
                }
                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: { Label("刪除", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯\(type.rawValue)" : "新增\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green).disabled(!canSave)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    private func loadEditing() {
        guard let e = editing else {
            // 新育兒記錄屬「即時紀錄」：預設用當下時間對齊到 5 分鐘，不套排程 09:30 規則
            date = FiveMinuteDateTimePicker.roundedToFiveMinutes(Date())
            sleepEnd = date
            return
        }
        date = e.date
        milkBrand = e.milkBrand ?? ""
        mlText = e.mlAmount.map { $0 > 0 ? String(format: "%.0f", $0) : "" } ?? ""
        foodName = e.foodName ?? ""
        sleepEnd = e.sleepEnd ?? Date()
        note = e.note
    }

    private func save() {
        guard var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        let rec = DailyRecord(
            id: editing?.id ?? UUID(), type: type, date: date,
            milkBrand: type == .milk ? milkBrand.trimmingCharacters(in: .whitespaces) : nil,
            mlAmount: (type == .milk || type == .food) ? Double(mlText) : nil,
            foodName: type == .food ? foodName.trimmingCharacters(in: .whitespaces) : nil,
            sleepEnd: type == .sleep ? sleepEnd : nil,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = member.dailyRecords.firstIndex(where: { $0.id == rec.id }) {
            member.dailyRecords[idx] = rec
        } else {
            member.dailyRecords.append(rec)
        }
        lifeStore.update(member)
        dismiss()
    }

    private func delete() {
        guard let e = editing, var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        member.dailyRecords.removeAll { $0.id == e.id }
        lifeStore.update(member)
        dismiss()
    }
}

// MARK: - 兒女記錄編輯 Sheet

struct ChildRecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let type: ChildRecordType
    var editing: ChildRecord?

    @State private var title = ""
    @State private var detail = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var dose = ""
    @State private var severity: AllergySeverity = .mild

    // 就醫 / 接種院所 自動完成
    @StateObject private var clinicCompleter = RestaurantSearchCompleter()
    @ObservedObject private var locationProvider = LocationProvider.shared
    @FocusState private var detailFieldFocused: Bool
    @State private var clinicSuppressNextUpdate: Bool = false
    @State private var clinicExpandedSuggestions: Bool = false
    @State private var photoFileName: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var sketchMode = true
    @State private var previewImage: UIImage?

    private var canSave: Bool {
        switch type {
        case .growth: return (Double(heightText) ?? 0) > 0 || (Double(weightText) ?? 0) > 0
        default: return !title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch type {
                case .vaccination: vaccinationFields
                case .allergy: allergyFields
                case .growth: growthFields
                case .medical: medicalFields
                case .education: educationFields
                case .hobby: hobbyFields
                case .memorable: memorableFields
                }
                Section("日期") { DatePicker("日期", selection: $date, displayedComponents: .date) }
                Section("備註") { TextField("選填", text: $note, axis: .vertical).lineLimit(2...5) }

                Section("插入圖片") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo")
                            Text(photoFileName == nil ? "選擇圖片" : "更換圖片")
                            Spacer()
                            if photoFileName != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }

                    if photoFileName != nil {
                        Toggle("轉為素描畫", isOn: $sketchMode)
                            .onChange(of: sketchMode) { _, _ in regeneratePreview() }
                    }

                    if let img = previewImage {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if photoFileName != nil {
                        Button(role: .destructive) {
                            if let name = photoFileName { ChildRecord.deletePhoto(name) }
                            photoFileName = nil; previewImage = nil
                        } label: {
                            Label("移除圖片", systemImage: "xmark.circle")
                        }
                    }
                }

                if editing != nil {
                    Section { Button(role: .destructive) { delete() } label: { Label("刪除此記錄", systemImage: "trash") } }
                }
            }
            .navigationTitle(editing != nil ? "編輯\(type.rawValue)" : "新增\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }.bold().foregroundStyle(.green).disabled(!canSave)
                }
            }
            .onAppear { loadEditing() }
            .onChange(of: photoItem) { _ in
                Task {
                    guard let photoItem, let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
                    let recordId = editing?.id ?? UUID()
                    // 原圖永遠保留一份
                    photoFileName = ChildRecord.savePhoto(data, id: recordId)
                    let origImage = UIImage(data: data)
                    // 素描版另存一份
                    if let orig = origImage, let sketched = ChildRecord.applySketchEffect(orig),
                       let sketchData = sketched.jpegData(compressionQuality: 0.85) {
                        _ = ChildRecord.saveSketch(sketchData, id: recordId)
                    }
                    previewImage = sketchMode ? loadSketchOrOrig(recordId) : origImage
                }
            }
        }
    }

    private func loadSketchOrOrig(_ recordId: UUID) -> UIImage? {
        let sketchPath = ChildRecord.photosDirectory.appendingPathComponent("\(recordId.uuidString)_sketch.jpg")
        if let data = try? Data(contentsOf: sketchPath), let img = UIImage(data: data) { return img }
        guard let name = photoFileName,
              let data = try? Data(contentsOf: ChildRecord.photosDirectory.appendingPathComponent(name)),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    private func regeneratePreview() {
        guard let name = photoFileName else { return }
        let recordId = editing?.id ?? UUID()
        let origPath = ChildRecord.photosDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: origPath), let origImage = UIImage(data: data) else { return }

        if sketchMode {
            // 如果素描版不存在就產生
            let sketchPath = ChildRecord.photosDirectory.appendingPathComponent("\(recordId.uuidString)_sketch.jpg")
            if !FileManager.default.fileExists(atPath: sketchPath.path),
               let sketched = ChildRecord.applySketchEffect(origImage),
               let sketchData = sketched.jpegData(compressionQuality: 0.85) {
                _ = ChildRecord.saveSketch(sketchData, id: recordId)
            }
            previewImage = loadSketchOrOrig(recordId)
        } else {
            previewImage = origImage
        }
    }

    private var vaccinationFields: some View {
        Section("疫苗資訊") {
            TextField("疫苗名稱（如：五合一）", text: $title)
            TextField("劑次（如：第 1 劑、追加）", text: $dose)
            clinicAutocompleteField(label: "接種院所（選填）")
        }
    }
    private var allergyFields: some View {
        Section("過敏資訊") {
            TextField("過敏原（如：花生、牛奶）", text: $title)
            Picker("嚴重度", selection: $severity) { ForEach(AllergySeverity.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            TextField("反應描述（如：紅疹、氣喘）", text: $detail, axis: .vertical).lineLimit(1...3)
        }
    }
    private var growthFields: some View {
        Section("成長數據") {
            HStack { TextField("身高", text: $heightText).keyboardType(.decimalPad); Text("cm").foregroundStyle(.secondary) }
            HStack { TextField("體重", text: $weightText).keyboardType(.decimalPad); Text("kg").foregroundStyle(.secondary) }
        }
    }
    private var medicalFields: some View {
        Section("就醫資訊") {
            TextField("症狀/診斷", text: $title)
            clinicAutocompleteField(label: "院所（選填）")
        }
    }

    // MARK: - 院所自動完成（適用於就醫 / 疫苗接種院所）

    @ViewBuilder
    private func clinicAutocompleteField(label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(.red)
                    .frame(width: 18)
                TextField(label, text: $detail)
                    .focused($detailFieldFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !detail.isEmpty {
                    Button {
                        detail = ""
                        clinicExpandedSuggestions = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if detailFieldFocused {
                clinicSuggestionsList
            }
        }
        .onAppear {
            LocationProvider.shared.requestIfNeeded()
            clinicCompleter.setRegion(LocationProvider.shared.searchRegion)
            if !detail.isEmpty { clinicCompleter.queryFragment = detail }
        }
        .onChange(of: detail) { _, newValue in
            if clinicSuppressNextUpdate {
                clinicSuppressNextUpdate = false
                return
            }
            clinicCompleter.queryFragment = newValue
            clinicExpandedSuggestions = false
        }
        .onChange(of: locationProvider.lastLocation) { _, _ in
            clinicCompleter.setRegion(LocationProvider.shared.searchRegion)
            if !detail.isEmpty { clinicCompleter.queryFragment = detail }
        }
    }

    @ViewBuilder
    private var clinicSuggestionsList: some View {
        let all = allClinicSuggestions
        if !all.isEmpty {
            let limit = 20
            let visible = clinicExpandedSuggestions ? all : Array(all.prefix(limit))
            let hiddenCount = max(0, all.count - limit)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { item in
                        Button { applyClinicSuggestion(item) } label: {
                            clinicSuggestionRow(item)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 44)
                    }
                    if !clinicExpandedSuggestions && hiddenCount > 0 {
                        Button {
                            clinicExpandedSuggestions = true
                        } label: {
                            HStack {
                                Image(systemName: "chevron.down.circle.fill").foregroundStyle(.blue)
                                Text("顯示更多 (\(hiddenCount))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.blue)
                                Spacer()
                            }
                            .padding(.vertical, 10).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else if clinicExpandedSuggestions && all.count > limit {
                        Button {
                            clinicExpandedSuggestions = false
                        } label: {
                            HStack {
                                Image(systemName: "chevron.up.circle.fill").foregroundStyle(.secondary)
                                Text("收合")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 10).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func clinicSuggestionRow(_ item: ClinicSuggestion) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(item.iconColor.opacity(0.15)).frame(width: 28, height: 28)
                Image(systemName: item.iconName)
                    .foregroundStyle(item.iconColor)
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// 合併所有小孩過往就醫 / 接種院所 + Apple Maps POI（醫療類）
    private var allClinicSuggestions: [ClinicSuggestion] {
        let q = detail.trimmingCharacters(in: .whitespaces).lowercased()
        var seen: Set<String> = []
        var output: [ClinicSuggestion] = []

        let allRecords: [ChildRecord] = lifeStore.familyMembers.flatMap { $0.childRecords }
        let medicalAndVaccination = allRecords.filter {
            $0.type == .medical || $0.type == .vaccination
        }
        let pastDetails: [String] = medicalAndVaccination
            .map { $0.detail.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for d in pastDetails {
            if !q.isEmpty && !d.lowercased().contains(q) { continue }
            let key = "past|\(d.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            output.append(ClinicSuggestion(
                id: key, source: .past, title: d, subtitle: "", completion: nil
            ))
        }

        for c in clinicCompleter.results {
            let key = "apple|\(c.title.lowercased())|\(c.subtitle.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            output.append(ClinicSuggestion(
                id: key, source: .apple, title: c.title, subtitle: c.subtitle, completion: c
            ))
        }

        return output
    }

    private func applyClinicSuggestion(_ item: ClinicSuggestion) {
        clinicSuppressNextUpdate = true
        switch item.source {
        case .past:
            detail = item.title
        case .apple:
            // Apple Maps 帶「名稱 - 地址」較完整
            if item.subtitle.isEmpty {
                detail = item.title
            } else {
                detail = "\(item.title) - \(item.subtitle)"
            }
        }
        clinicExpandedSuggestions = false
        detailFieldFocused = false
    }
    private var educationFields: some View {
        Section("教育里程碑") { TextField("事件", text: $title); TextField("學校或單位（選填）", text: $detail) }
    }
    private var hobbyFields: some View {
        Section("興趣才藝") { TextField("項目", text: $title); TextField("描述（選填）", text: $detail, axis: .vertical).lineLimit(1...3) }
    }
    private var memorableFields: some View {
        Section("紀念時刻") { TextField("事件", text: $title); TextField("描述（選填）", text: $detail, axis: .vertical).lineLimit(1...3) }
    }

    private func loadEditing() {
        guard let e = editing else { return }
        title = e.title; detail = e.detail; date = e.date; note = e.note
        if let h = e.heightCm, h > 0 { heightText = String(format: "%g", h) }
        if let w = e.weightKg, w > 0 { weightText = String(format: "%g", w) }
        dose = e.dose ?? ""; severity = e.severity ?? .mild
        photoFileName = e.photoFileName
        if e.photoFileName != nil {
            previewImage = sketchMode ? loadSketchOrOrig(e.id) : {
                guard let name = e.photoFileName,
                      let data = try? Data(contentsOf: ChildRecord.photosDirectory.appendingPathComponent(name)) else { return nil }
                return UIImage(data: data)
            }()
        }
    }

    private func save() {
        guard var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        let rec = ChildRecord(
            id: editing?.id ?? UUID(), type: type, date: date,
            title: title.trimmingCharacters(in: .whitespaces), detail: detail.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            heightCm: type == .growth ? Double(heightText) : nil, weightKg: type == .growth ? Double(weightText) : nil,
            dose: type == .vaccination ? dose.trimmingCharacters(in: .whitespaces) : nil,
            severity: type == .allergy ? severity : nil,
            photoFileName: photoFileName
        )
        if let idx = member.childRecords.firstIndex(where: { $0.id == rec.id }) { member.childRecords[idx] = rec }
        else { member.childRecords.append(rec) }
        lifeStore.update(member); dismiss()
    }

    private func delete() {
        guard let e = editing, var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        member.childRecords.removeAll { $0.id == e.id }
        lifeStore.update(member); dismiss()
    }
}

// MARK: - 院所候選資料型別

fileprivate struct ClinicSuggestion: Identifiable {
    enum Source { case past, apple }
    let id: String
    let source: Source
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion?

    var iconName: String {
        source == .past ? "clock.arrow.circlepath" : "cross.case.fill"
    }
    var iconColor: Color {
        source == .past ? .green : .red
    }
}
