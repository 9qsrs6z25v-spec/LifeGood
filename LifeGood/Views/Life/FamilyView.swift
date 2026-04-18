import SwiftUI

struct FamilyView: View {
    @EnvironmentObject var store: LifeStore
    @State private var showAdd = false
    @State private var editingMember: FamilyMember?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.familyMembers) { member in
                    memberRow(member)
                        .contentShape(Rectangle())
                        .onTapGesture { editingMember = member }
                }
                .onDelete { offsets in
                    let items = offsets.map { store.familyMembers[$0] }
                    items.forEach { store.deleteFamilyMember($0) }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if store.familyMembers.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("尚無家庭成員").font(.headline).foregroundStyle(.secondary)
                        Text("在履歷頁面新增家庭分類即可加入")
                            .font(.subheadline).foregroundStyle(.tertiary)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("家庭")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddMilestoneView(initialCategory: .family) }
            .sheet(item: $editingMember) { member in AddMilestoneView(editingFamily: member) }
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
        }
        .padding(.vertical, 2)
    }
}
