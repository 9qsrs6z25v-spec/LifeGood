import SwiftUI

struct FamilyView: View {
    @EnvironmentObject var store: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingMember: FamilyMember?
    @State private var showPremiumAlert = false

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
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 36)).foregroundStyle(.secondary)
                            Text("尚無家庭成員").font(.subheadline).foregroundStyle(.secondary)
                            Text("點右上角 + 或在履歷頁面新增")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("家庭成員") {
                        ForEach(store.familyMembers) { member in
                            memberRow(member)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if subscription.isPremium { editingMember = member }
                                    else { showPremiumAlert = true }
                                }
                        }
                        .onDelete { offsets in
                            guard subscription.isPremium else { showPremiumAlert = true; return }
                            let items = offsets.map { store.familyMembers[$0] }
                            items.forEach { store.deleteFamilyMember($0) }
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

    private func memberRow(_ member: FamilyMember) -> some View {
        HStack {
            Image(systemName: member.role.icon)
                .font(.title3).foregroundStyle(.pink)
                .frame(width: 36, height: 36)
                .background(Color.pink.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(member.chineseName).font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(member.displayRoleLabel)
                    if !member.englishName.isEmpty {
                        Text("- \(member.englishName)")
                    }
                    if let spouse = spouseDisplayName(for: member) {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("配偶 \(spouse)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            if let bd = member.birthday {
                Text(formatDate(bd)).font(.caption).foregroundStyle(.secondary)
            } else if member.role == .spouse, let md = member.marriageDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("結 \(formatDate(md))").font(.caption2).foregroundStyle(.secondary)
                    if member.isDivorced, let dd = member.divorceDate {
                        Text("離 \(formatDate(dd))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }

    /// 取得 member 配偶的顯示名稱（依 spouseId 解析）
    private func spouseDisplayName(for member: FamilyMember) -> String? {
        guard let id = member.spouseId,
              let spouse = store.familyMembers.first(where: { $0.id == id }) else { return nil }
        let name = spouse.chineseName.isEmpty ? spouse.englishName : spouse.chineseName
        return name.isEmpty ? nil : name
    }
}
