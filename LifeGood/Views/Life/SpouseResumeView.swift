import SwiftUI

struct SpouseResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore

    private var spouse: FamilyMember? {
        lifeStore.familyMembers.first { $0.role == .spouse }
    }

    var body: some View {
        NavigationStack {
            List {
                if let s = spouse {
                    profileSection(s)
                    marriageSection(s)
                    milestoneSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("配偶履歷")
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

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: d)
    }
}
