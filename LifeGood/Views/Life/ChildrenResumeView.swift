import SwiftUI

struct ChildrenResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var viewingChild: FamilyMember?

    private var children: [FamilyMember] {
        lifeStore.familyMembers
            .filter { $0.role == .son || $0.role == .daughter }
            .sorted { ($0.birthday ?? .distantPast) < ($1.birthday ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(children) { child in
                        childCard(child)
                            .onTapGesture { viewingChild = child }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .overlay {
                if children.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "figure.2.and.child.holdinghands")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("尚無兒女資料").font(.headline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("兒女履歷")
            .sheet(item: $viewingChild) { child in
                ChildDetailView(child: child)
            }
        }
    }

    private func childCard(_ child: FamilyMember) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.child.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(child.role == .son ? Color.blue : Color.pink)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(childDisplayName(child)).font(.headline)
                    Text(child.role.rawValue)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((child.role == .son ? Color.blue : Color.pink).opacity(0.12))
                        .foregroundStyle(child.role == .son ? Color.blue : Color.pink)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if let bd = child.birthday {
                    Text("\(formatDate(bd)) · \(ageString(from: bd))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    recordBadge(child, .vaccination)
                    recordBadge(child, .allergy)
                    recordBadge(child, .growth)
                    recordBadge(child, .medical)
                    recordBadge(child, .education)
                    recordBadge(child, .hobby)
                    recordBadge(child, .memorable)
                }
                .padding(.top, 2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private func recordBadge(_ child: FamilyMember, _ type: ChildRecordType) -> some View {
        let count = child.childRecords.filter { $0.type == type }.count
        if count > 0 {
            HStack(spacing: 2) {
                Image(systemName: type.icon)
                Text("\(count)")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(colorFor(type))
        }
    }

    private func colorFor(_ type: ChildRecordType) -> Color {
        switch type {
        case .vaccination: return .blue
        case .allergy: return .red
        case .growth: return .green
        case .medical: return .orange
        case .education: return .purple
        case .hobby: return .pink
        case .memorable: return .yellow
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
        if y > 0 { return "\(y) 歲 \(m) 個月" }
        return "\(m) 個月"
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: d)
    }
}
