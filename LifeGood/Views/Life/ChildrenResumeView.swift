import SwiftUI

struct ChildrenResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore

    private var children: [FamilyMember] {
        lifeStore.familyMembers
            .filter { $0.role == .son || $0.role == .daughter }
            .sorted { ($0.birthday ?? .distantPast) < ($1.birthday ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(children) { child in
                    childSection(child)
                }
            }
            .listStyle(.insetGrouped)
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
        }
    }

    private func childSection(_ child: FamilyMember) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: child.role == .son ? "figure.child" : "figure.child")
                    .font(.system(size: 32))
                    .foregroundStyle(child.role == .son ? .blue : .pink)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if !child.chineseName.isEmpty {
                            Text(child.chineseName).font(.headline)
                        }
                        Text(child.role.rawValue)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(child.role == .son ? Color.blue.opacity(0.12) : Color.pink.opacity(0.12))
                            .foregroundStyle(child.role == .son ? .blue : .pink)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if !child.englishName.isEmpty {
                        Text(child.englishName).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)

            if let bd = child.birthday {
                HStack {
                    Label("出生日期", systemImage: "birthday.cake")
                    Spacer()
                    Text(formatDate(bd)).foregroundStyle(.secondary)
                }
                HStack {
                    Label("年齡", systemImage: "clock")
                    Spacer()
                    Text(ageString(from: bd)).foregroundStyle(.secondary)
                }
            }

            let derived = lifeStore.familyDerivedMilestones
                .filter { $0.title.contains(childDisplayName(child)) }
            if !derived.isEmpty {
                ForEach(derived) { m in
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(m.title)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(childDisplayName(child))
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
