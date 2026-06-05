import SwiftUI

// MARK: - 美化紀錄（ChildrenResumeView）
// [2026-06] 本次美化方向：
//   1. childCard → 左側 4pt 藍/粉依性別漸層強調條 + 44pt LinearGradient 漸層圖示圓 + 陰影，
//      對齊 FamilyView.memberRow / StockView.stockCard 卡片規格
//   2. 角色膠囊 → 從 RoundedRectangle(cornerRadius:4) 升級為 Capsule，
//      padding 從 (.horizontal,6)(.vertical,2) 統一為 (.horizontal,7)(.vertical,2.5)，
//      對齊 VehicleView / SavingsInsuranceView vehicleCard 膠囊規格
//   3. 生日資訊 → 日期加圖示膠囊徽章，年齡文字改為彩色膠囊（對齊 SpouseResumeView.marriageRow 規格）
//   4. recordBadge → 從純文字圖示升級為微型彩色膠囊（帶半透明背景），資訊密度與可讀性提升
//   5. 空狀態 → 雙層脈衝光環 + 漸層底圓 + 圖示 + 說明文字，
//      對齊 FamilyView.emptyMembersPlaceholder / VariableExpenseView.emptyStateView 規格
//   6. 卡片列表 → 交錯淡入 + 向上進場動畫（cardsAppeared），對齊 FamilyView membersAppeared 規格
//   7. DateFormatter 改為靜態共用實例，避免每次 render 重新分配

struct ChildrenResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var viewingChild: FamilyMember?
    @State private var cardsAppeared = false
    @State private var emptyIconPulse = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private var children: [FamilyMember] {
        lifeStore.familyMembers
            .filter { $0.role == .son || $0.role == .daughter }
            .sorted { ($0.birthday ?? .distantPast) < ($1.birthday ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if children.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { idx, child in
                            childCard(child)
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 18)
                                .animation(
                                    .spring(response: 0.45, dampingFraction: 0.82)
                                        .delay(0.06 * Double(idx)),
                                    value: cardsAppeared
                                )
                                .onTapGesture { viewingChild = child }
                        }
                    }
                    .padding(16)
                    .onAppear {
                        withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.05)) {
                            cardsAppeared = true
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("兒女履歷")
            .sheet(item: $viewingChild) { child in
                ChildDetailView(child: child)
            }
        }
    }

    // MARK: - 兒女卡片（左側強調條 + 漸層圖示圓）

    private func childCard(_ child: FamilyMember) -> some View {
        let isSon = child.role == .son
        let accent: Color = isSon ? .blue : Color(red: 0.96, green: 0.35, blue: 0.60)

        return HStack(spacing: 0) {
            // 左側 4pt 漸層強調條
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.trailing, 14)

            HStack(spacing: 12) {
                // 44pt 漸層圖示圓
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: accent.opacity(0.22), radius: 6, x: 0, y: 3)
                    Image(systemName: isSon ? "figure.child" : "figure.child")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }

                childCardInfo(child, accent: accent)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 2)
            }
            .padding(.vertical, 12)
            .padding(.trailing, 14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.10), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    // MARK: - 兒女卡片：中央資訊欄（姓名 / 生日 / 徽章）

    @ViewBuilder
    private func childCardInfo(_ child: FamilyMember, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            childCardNameRow(child, accent: accent)
            if let bd = child.birthday {
                childCardBirthdayRow(bd, accent: accent)
            }
            let badges = recordBadges(for: child)
            if !badges.isEmpty {
                childCardBadgesRow(badges)
            }
        }
    }

    private func childCardNameRow(_ child: FamilyMember, accent: Color) -> some View {
        HStack(spacing: 6) {
            Text(childDisplayName(child))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(child.role.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(accent.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private func childCardBirthdayRow(_ bd: Date, accent: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "birthday.cake.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(accent.opacity(0.70))
            Text(Self.dateFormatter.string(from: bd))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(ageString(from: bd))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(accent.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    private func childCardBadgesRow(_ badges: [(type: ChildRecordType, count: Int)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(badges, id: \.type) { item in
                    recordBadge(type: item.type, count: item.count)
                }
            }
        }
    }

    // MARK: - 紀錄徽章（微型彩色膠囊）

    /// 一次掃描算出各類紀錄筆數（取代原本 7 個 inline filter，降低 body 型別檢查負擔），
    /// 依固定顯示順序回傳「筆數 > 0」的類別。
    private func recordBadges(for child: FamilyMember) -> [(type: ChildRecordType, count: Int)] {
        var counts: [ChildRecordType: Int] = [:]
        for r in child.childRecords { counts[r.type, default: 0] += 1 }
        let order: [ChildRecordType] = [.vaccination, .allergy, .growth, .medical, .education, .hobby, .memorable]
        return order.compactMap { t in
            let n = counts[t] ?? 0
            return n > 0 ? (type: t, count: n) : nil
        }
    }

    private func recordBadge(type: ChildRecordType, count: Int) -> some View {
        let c = colorFor(type)
        return HStack(spacing: 3) {
            Image(systemName: type.icon)
                .font(.system(size: 9, weight: .medium))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(c)
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .background(c.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(c.opacity(0.20), lineWidth: 0.5))
    }

    // MARK: - 空狀態（雙層脈衝光環 + 漸層底圓）

    private var emptyState: some View {
        let accent = Color(red: 0.96, green: 0.35, blue: 0.60)
        return VStack(spacing: 24) {
            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（延遲 0.3s）
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.60 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 漸層底圓
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.14), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(accent.opacity(0.22), lineWidth: 1.2))
                Image(systemName: "figure.2.and.child.holdinghands")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(accent.opacity(0.70))
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
            }

            VStack(spacing: 8) {
                Text("尚無兒女資料")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("在家庭頁面新增兒子或女兒後顯示於此")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Helpers

    private func colorFor(_ type: ChildRecordType) -> Color {
        switch type {
        case .vaccination: return .blue
        case .allergy:     return .red
        case .growth:      return .green
        case .medical:     return .orange
        case .education:   return .purple
        case .hobby:       return .pink
        case .memorable:   return Color(red: 0.95, green: 0.70, blue: 0.12)
        }
    }

    private func childDisplayName(_ child: FamilyMember) -> String {
        if !child.chineseName.isEmpty { return child.chineseName }
        if !child.englishName.isEmpty { return child.englishName }
        return child.role.rawValue
    }

    private func ageString(from birthday: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: birthday, to: Date())
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        if y > 0 { return "\(y) 歲 \(m) 月" }
        return "\(m) 個月"
    }
}
