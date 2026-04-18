import SwiftUI

struct LifeOverviewView: View {
    @EnvironmentObject var store: LifeStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statsCard
                    upcomingSection
                    recentInteractionsSection
                    petSummarySection
                    milestoneTimelineSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("人生總覽")
        }
    }

    // MARK: - 統計卡

    private var statsCard: some View {
        HStack(spacing: 12) {
            statBadge(title: "里程碑", count: store.milestones.count, icon: "trophy.fill", color: .orange)
            statBadge(title: "人脈", count: store.relationships.count, icon: "person.2.fill", color: .blue)
            statBadge(title: "寵物", count: store.pets.count, icon: "pawprint.fill", color: .pink)
            statBadge(title: "待辦", count: store.upcomingSchedules.count, icon: "calendar", color: .green)
        }
        .padding(.horizontal)
    }

    private func statBadge(title: String, count: Int, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text("\(count)").font(.title3.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - 近期行程

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近期行程").font(.headline).padding(.horizontal)

            let upcoming = Array(store.upcomingSchedules.prefix(5))
            if upcoming.isEmpty {
                Text("暫無行程").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(upcoming) { item in
                        HStack {
                            Image(systemName: item.category.icon)
                                .frame(width: 30).foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline)
                                Text(formatDate(item.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !item.location.isEmpty {
                                Text(item.location).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                        if item.id != upcoming.last?.id { Divider().padding(.leading, 50) }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 最近互動

    private var recentInteractionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近互動").font(.headline).padding(.horizontal)

            let recent = Array(store.recentInteractions.prefix(5))
            if recent.isEmpty {
                Text("暫無互動紀錄").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.interaction.id) { index, item in
                        HStack {
                            Image(systemName: item.relationship.group.icon)
                                .frame(width: 30).foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.relationship.name).font(.subheadline)
                                Text(item.interaction.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(formatDate(item.interaction.date)).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                        if index < recent.count - 1 { Divider().padding(.leading, 50) }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 寵物摘要

    private var petSummarySection: some View {
        Group {
            if !store.pets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("我的寵物").font(.headline).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(store.pets) { pet in
                                VStack(spacing: 6) {
                                    Image(systemName: pet.type.icon)
                                        .font(.title2).foregroundStyle(.pink)
                                    Text(pet.name).font(.subheadline.bold())
                                    if let age = pet.age {
                                        Text(String(format: "%.1f 歲", age))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 90)
                                .padding(.vertical, 12)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }

    // MARK: - 里程碑時間軸

    private var milestoneTimelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("人生里程碑").font(.headline).padding(.horizontal)

            let sorted = store.milestones.sorted { $0.date > $1.date }
            let recent = Array(sorted.prefix(5))
            if recent.isEmpty {
                Text("暫無里程碑").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { m in
                        HStack {
                            Image(systemName: m.category.icon)
                                .frame(width: 30).foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).font(.subheadline)
                                Text(m.category.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatDate(m.date)).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                        if m.id != recent.last?.id { Divider().padding(.leading, 50) }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .padding(.horizontal)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date)
    }
}
