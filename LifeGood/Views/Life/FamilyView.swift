import SwiftUI

// MARK: - 美化紀錄（FamilyView）
// [2026-06] 本次美化方向：
//   1. memberRow：圖示圓升至 44pt + LinearGradient 漸層填色 + 陰影，對齊 ExpenseRow 規格
//   2. memberRow：左側 4pt 角色色彩強調條（依角色分色），增加視覺層次
//   3. memberRow：角色名稱改為彩色膠囊標籤，配偶名稱以粉紅愛心膠囊呈現
//   4. memberRow：日期以小圖示搭配文字呈現（calendar / heart.fill）
//   5. 空狀態：加入雙層脈衝光環 + 漸層圓底，對齊 VariableExpenseView emptyStateView 規格
//   6. Section header：加入粉紅側條 + 成員計數膠囊，對齊 daySectionHeader 規格
//   7. 列表：加入交錯淡入 + 向上進場動畫，對齊 FixedExpenseView 規格

struct FamilyView: View {
    @EnvironmentObject var store: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingMember: FamilyMember?
    @State private var showPremiumAlert = false
    @State private var membersAppeared = false
    @State private var emptyIconPulse = false

    var body: some View {
        NavigationStack {
            // 用同一個 List 把街道圖跟成員清單放在一起；
            // 列表上滑時，街道圖會自然跟著被推上去，給下方項目更多空間。
            List {
                Section {
                    FamilyOverviewMap(
                        myName: store.profile.chineseName,
                        members: store.familyMembers
                    )
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if store.familyMembers.isEmpty {
                    Section {
                        emptyMembersPlaceholder
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section(header: familySectionHeader) {
                        ForEach(Array(store.familyMembers.enumerated()), id: \.element.id) { idx, member in
                            memberRow(member)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if subscription.isPremium { editingMember = member }
                                    else { showPremiumAlert = true }
                                }
                                .opacity(membersAppeared ? 1 : 0)
                                .offset(y: membersAppeared ? 0 : 14)
                                .animation(
                                    .spring(response: 0.45, dampingFraction: 0.82)
                                        .delay(0.05 * Double(idx)),
                                    value: membersAppeared
                                )
                        }
                        .onDelete { offsets in
                            guard subscription.isPremium else { showPremiumAlert = true; return }
                            let items = offsets.map { store.familyMembers[$0] }
                            items.forEach { store.deleteFamilyMember($0) }
                        }
                        .onAppear {
                            withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.05)) {
                                membersAppeared = true
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("家庭")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if subscription.isPremium { showAdd = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddMilestoneView(initialCategory: .family) }
            .sheet(item: $editingMember) { member in AddMilestoneView(editingFamily: member) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - Section Header（帶成員計數膠囊）

    private var familySectionHeader: some View {
        let accent = Color(red: 1.00, green: 0.35, blue: 0.55)
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 14)
            Text("家庭成員")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.75))
            Spacer(minLength: 6)
            Text("\(store.familyMembers.count) 位")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(accent.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
        }
        .textCase(nil)
    }

    // MARK: - 空狀態（雙層脈衝光環 + 漸層圓底）

    private var emptyMembersPlaceholder: some View {
        let accent = Color(red: 1.00, green: 0.35, blue: 0.55)
        return VStack(spacing: 20) {
            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.25), lineWidth: 1.5)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（延遲 0.3s，製造波紋層次）
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.13), lineWidth: 1)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.60 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 主圓底（漸層填色 + 細邊框）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.14), accent.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 82, height: 82)
                    .overlay(
                        Circle().stroke(accent.opacity(0.20), lineWidth: 1.2)
                    )
                Image(systemName: "person.3.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(accent.opacity(0.70))
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
            }

            VStack(spacing: 8) {
                Text("尚無家庭成員")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.65))
                Text("點右上角 + 新增第一位家庭成員")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - 角色配色（依親屬關係分色）

    private func roleAccentColor(_ role: FamilyMemberRole) -> Color {
        switch role {
        case .spouse:
            return Color(red: 1.00, green: 0.35, blue: 0.55)   // 粉紅：配偶
        case .son, .daughter:
            return Color(red: 1.00, green: 0.62, blue: 0.22)   // 橘色：兒女
        case .father, .mother:
            return Color(red: 0.22, green: 0.53, blue: 0.98)   // 藍色：父母
        case .elderBrother, .youngerBrother:
            return Color(red: 0.16, green: 0.74, blue: 0.50)   // 綠色：兄弟
        case .elderSister, .youngerSister:
            return Color(red: 0.68, green: 0.40, blue: 1.00)   // 紫色：姐妹
        case .otherRelative:
            return Color(.secondaryLabel)                        // 灰色：其他親屬
        }
    }

    // MARK: - 成員列（44pt 圖示圓 + 角色色彩強調條 + 膠囊標籤）

    private func memberRow(_ member: FamilyMember) -> some View {
        let accent = roleAccentColor(member.role)
        let displayName = member.chineseName.isEmpty ? member.englishName : member.chineseName

        return HStack(spacing: 0) {
            // 左側角色色彩強調條（4pt，與 FixedExpenseRow 規格一致）
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 8)
                .padding(.trailing, 14)

            HStack(spacing: 12) {
                // 角色圖示圓（44pt + 漸層填色 + 陰影，對齊 ExpenseRow 規格）
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
                    Image(systemName: member.role.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName.isEmpty ? "（未命名）" : displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    // 角色膠囊 + 英文名 + 配偶名
                    HStack(spacing: 5) {
                        Text(member.displayRoleLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(accent.opacity(0.12))
                            .clipShape(Capsule())
                        if !member.englishName.isEmpty && !member.chineseName.isEmpty {
                            Text(member.englishName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let spouse = spouseDisplayName(for: member) {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 8))
                                Text(spouse)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(Color(red: 1.00, green: 0.35, blue: 0.55))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(red: 1.00, green: 0.35, blue: 0.55).opacity(0.10))
                            .clipShape(Capsule())
                        }
                    }
                }

                Spacer(minLength: 4)

                // 右側日期資訊（圖示 + 文字組合）
                VStack(alignment: .trailing, spacing: 3) {
                    if let bd = member.birthday {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(formatDate(bd))
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    } else if member.role == .spouse, let md = member.marriageDate {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                            Text(formatDate(md))
                                .font(.caption2)
                        }
                        .foregroundStyle(Color(red: 1.00, green: 0.35, blue: 0.55).opacity(0.75))
                        if member.isDivorced, let dd = member.divorceDate {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                Text(formatDate(dd))
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 7)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }

    private func spouseDisplayName(for member: FamilyMember) -> String? {
        guard let id = member.spouseId,
              let spouse = store.familyMembers.first(where: { $0.id == id }) else { return nil }
        let name = spouse.chineseName.isEmpty ? spouse.englishName : spouse.chineseName
        return name.isEmpty ? nil : name
    }
}
