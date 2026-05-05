import SwiftUI

struct FamilyView: View {
    @EnvironmentObject var store: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingMember: FamilyMember?
    @State private var showPremiumAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 上方：街道式總覽（永遠顯示，即使空也保留高度）
                FamilyOverviewMap(
                    myName: store.profile.chineseName,
                    members: store.familyMembers
                )
                .frame(height: 320)

                // 下方：成員列表（可點擊編輯、滑動刪除）
                List {
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
                .listStyle(.insetGrouped)
                .overlay {
                    if store.familyMembers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 36)).foregroundStyle(.secondary)
                            Text("尚無家庭成員").font(.subheadline).foregroundStyle(.secondary)
                            Text("點右上角 + 或在履歷頁面新增")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
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
                    Text(member.role.rawValue)
                    if !member.englishName.isEmpty {
                        Text("- \(member.englishName)")
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
}
