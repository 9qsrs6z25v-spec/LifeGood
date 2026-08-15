import SwiftUI

// MARK: - 兼任職務管理
//
// 「兼任職務」＝與本職並行的額外職務（副理同時兼任氣體化學執行秘書、尾牙負責人）。
// 資料本體是一筆 careerSubCategory == .sideRole 的 LifeMilestone，
// 掛在它底下的 sideRoleTasks / sideRoleMembers / sideRoleMeetings / sideRoleKeyDates
// 就是這個管理頁的四個區塊。
//
// 【為什麼中樞是一個 ManagementFeature case 而不是每筆一個】
// ManagementFeature 是靜態列舉、路由靠 @AppStorage 存的字串，
// 但兼任職務的數量是動態的（可能 0 筆也可能 5 筆）。所以用一個 .sideRole case
// 當中樞入口，中樞裡再用 NavigationLink 進到各筆的管理頁——
// 這是本專案既有的「動態清單 → 詳情頁」模式（部屬列表 → 部屬明細）。
//
// 【關掉開關不會刪資料】
// hasSideRoleWorkspace 需要 sideRoleIsLead && sideRoleWorkspaceEnabled 同時成立。
// 關掉任一個只是讓這筆從中樞消失，四個陣列原封不動。中樞底部的「已停用」區塊
// 會把這些職務列出來，讓「資料還在」是看得見的，而不是一句沒有憑據的承諾。

// MARK: - 格式化

enum SideRoleFormat {
    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let ym: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M"; return f
    }()

    static func date(_ d: Date) -> String { ymd.string(from: d) }

    /// 顯示名稱。沒填名稱時退到里程碑標題，避免整列空白。
    static func displayName(_ role: LifeMilestone) -> String {
        let n = role.sideRoleName?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? role.title : n
    }

    /// 任期字串：「2025/1 – 2025/12」或「2024/3 起」
    static func period(_ role: LifeMilestone) -> String {
        let start = ym.string(from: role.date)
        guard let end = role.sideRoleEndDate else { return "\(start) 起" }
        return "\(start) – \(ym.string(from: end))"
    }

    /// 已擔任多久 / 共擔任多久
    static func duration(_ role: LifeMilestone) -> String {
        let end = role.sideRoleEndDate ?? Date()
        let comps = Calendar.current.dateComponents([.year, .month], from: role.date, to: end)
        let y = max(0, comps.year ?? 0)
        let m = max(0, comps.month ?? 0)
        if y == 0 && m == 0 { return "未滿 1 個月" }
        if y == 0 { return "\(m) 個月" }
        return m == 0 ? "\(y) 年" : "\(y) 年 \(m) 個月"
    }

    /// 列表副標：「主辦單位 · 任期」
    static func subtitle(_ role: LifeMilestone) -> String {
        var parts: [String] = []
        if let org = role.sideRoleOrg?.trimmingCharacters(in: .whitespaces), !org.isEmpty {
            parts.append(org)
        }
        parts.append(period(role))
        return parts.joined(separator: " · ")
    }

    /// 待辦完成度
    static func taskProgress(_ role: LifeMilestone) -> (done: Int, total: Int) {
        let list = role.sideRoleTasks ?? []
        return (list.filter(\.isCompleted).count, list.count)
    }
}

/// 職涯列表用的兼任副標。抽成獨立小 View 而不是塞進 subtitleText 的
/// if/else 鏈裡，是為了不再加深那條鏈的型別推導深度。
struct SideRoleRowSubtitle: View {
    let item: LifeMilestone

    var body: some View {
        HStack(spacing: 5) {
            Text(SideRoleFormat.subtitle(item))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if item.isActiveSideRole {
                Text("在任")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.indigo.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.indigo.opacity(0.25), lineWidth: 0.6))
            }
            if item.hasSideRoleWorkspace {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.indigo.opacity(0.7))
            }
        }
    }
}

// MARK: - 中樞

struct SideRoleHubView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager

    @State private var showAdd = false
    @State private var dormantExpanded = false
    @State private var heroAppeared = false

    private var roles: [LifeMilestone] { lifeStore.sideRoleWorkspaces }
    private var dormant: [LifeMilestone] { lifeStore.dormantSideRoles }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                heroCard
                if roles.isEmpty {
                    emptyState
                } else {
                    ForEach(roles) { role in
                        NavigationLink {
                            SideRoleWorkspaceView(roleId: role.id)
                        } label: {
                            roleCard(role)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
                if !dormant.isEmpty { dormantSection }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("兼任職務")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .disabled(!subscription.isPremium)
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddMilestoneView(initialCategory: .career, initialCareerSub: .sideRole)
            }
        }
    }

    // MARK: 看板

    private var heroCard: some View {
        let active = roles.filter(\.isActiveSideRole).count
        let totalTasks = roles.reduce(0) { $0 + ($1.sideRoleTasks?.count ?? 0) }
        let doneTasks = roles.reduce(0) { $0 + (($1.sideRoleTasks ?? []).filter(\.isCompleted).count) }
        let upcoming = upcomingKeyDateCount
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("兼任職務")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text("\(active) 個在任")
                        .heroBigValueFont()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text("\(roles.count) 個管理頁")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 0) {
                HeroKpiCell(label: "待辦完成", value: "\(doneTasks)/\(totalTasks)",
                            icon: "checklist")
                HeroKpiDivider()
                HeroKpiCell(label: "近 30 天日期", value: "\(upcoming)",
                            icon: "calendar")
                HeroKpiDivider()
                HeroKpiCell(label: "累計紀錄", value: "\(lifeStore.sideRoles.count)",
                            icon: "clock.arrow.circlepath")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .heroCardShell(card: .sideRoleHub)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .opacity(heroAppeared ? 1 : 0)
        .offset(y: heroAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { heroAppeared = true }
        }
        .onDisappear { heroAppeared = false }
    }

    private var upcomingKeyDateCount: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let limit = cal.date(byAdding: .day, value: 30, to: today) else { return 0 }
        return roles.reduce(0) { acc, role in
            acc + (role.sideRoleKeyDates ?? []).filter { $0.date >= today && $0.date <= limit }.count
        }
    }

    // MARK: 職務卡

    private func roleCard(_ role: LifeMilestone) -> some View {
        let progress = SideRoleFormat.taskProgress(role)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.indigo.opacity(0.22), .indigo.opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                        .overlay(Circle().stroke(Color.indigo.opacity(0.22), lineWidth: 0.75))
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.indigo)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(SideRoleFormat.displayName(role))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(SideRoleFormat.subtitle(role))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if role.isActiveSideRole {
                    Text("在任")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 0) {
                miniStat(icon: "checklist", value: "\(progress.done)/\(progress.total)", label: "待辦")
                miniStat(icon: "person.2.fill", value: "\(role.sideRoleMembers?.count ?? 0)", label: "成員")
                miniStat(icon: "text.bubble.fill", value: "\(role.sideRoleMeetings?.count ?? 0)", label: "會議")
                miniStat(icon: "calendar", value: "\(role.sideRoleKeyDates?.count ?? 0)", label: "重要日期")
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func miniStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.indigo.opacity(0.75))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 已停用

    /// 關掉開關的職務如果完全不出現在畫面上，使用者會判定資料遺失並重新輸入，
    /// 那樣「不清除」的保護就白做了。列出來讓「資料還在」是看得見的。
    private var dormantSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    dormantExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("已停用管理頁（\(dormant.count)）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: dormantExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if dormantExpanded {
                ForEach(dormant) { role in
                    let c = role.sideRoleContentCount
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SideRoleFormat.displayName(role))
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("保留 \(c.tasks) 待辦 · \(c.members) 成員 · \(c.meetings) 會議 · \(c.keyDates) 日期")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
                }
                Text("到職涯頁編輯該筆兼任職務、重新開啟「啟用專屬管理頁面」就會回到上面的清單。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(.indigo.opacity(0.5))
            Text("還沒有啟用管理頁的兼任職務")
                .font(.subheadline.weight(.semibold))
            Text("到職涯頁新增一筆「兼任」里程碑，勾選「我是這個職務的主責者」並開啟專屬管理頁面，就會出現在這裡。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - 單一兼任職務的管理頁

struct SideRoleWorkspaceView: View {
    let roleId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager

    @State private var editingTask: SideRoleTask?
    @State private var editingMember: SideRoleMember?
    @State private var editingMeeting: SideRoleMeeting?
    @State private var editingKeyDate: SideRoleKeyDate?
    @State private var showCopyResult: String?
    @State private var showEditRole = false

    /// 資料一律從 store 現查，不快取進 @State——否則在別處編輯後這頁不會更新。
    private var role: LifeMilestone? {
        lifeStore.milestones.first { $0.id == roleId }
    }

    var body: some View {
        // role 是 Optional（可能在別處被刪除）。整頁內容抽成吃非 Optional 的
        // content(_:)，避免每個子區塊各自解包或誤用強制解包。
        Group {
            if let role {
                content(role)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("找不到這個兼任職務")
                        .font(.subheadline.weight(.semibold))
                    Text("它可能已經被刪除了。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 60)
            }
        }
    }

    private func content(_ role: LifeMilestone) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                header(role)
                taskSection(role)
                keyDateSection(role)
                memberSection(role)
                meetingSection(role)
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(SideRoleFormat.displayName(role))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditRole = true } label: { Image(systemName: "square.and.pencil") }
                    .disabled(!subscription.isPremium)
            }
        }
        .sheet(isPresented: $showEditRole) {
            NavigationStack { AddMilestoneView(editing: role) }
        }
        .sheet(item: $editingTask) { t in
            NavigationStack { SideRoleTaskEditor(roleId: roleId, task: t) }
        }
        .sheet(item: $editingMember) { m in
            NavigationStack { SideRoleMemberEditor(roleId: roleId, member: m) }
        }
        .sheet(item: $editingMeeting) { m in
            NavigationStack { SideRoleMeetingEditor(roleId: roleId, meeting: m) }
        }
        .sheet(item: $editingKeyDate) { k in
            NavigationStack { SideRoleKeyDateEditor(roleId: roleId, keyDate: k) }
        }
        .alert("已複製上屆名單", isPresented: Binding(
            get: { showCopyResult != nil },
            set: { if !$0 { showCopyResult = nil } })) {
            Button("好") { showCopyResult = nil }
        } message: {
            Text(showCopyResult ?? "")
        }
    }

    // MARK: 標頭

    private func header(_ role: LifeMilestone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(SideRoleFormat.period(role))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.20))
                    .clipShape(Capsule())
                Text(role.isActiveSideRole ? "在任 \(SideRoleFormat.duration(role))"
                                           : "共擔任 \(SideRoleFormat.duration(role))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
            if let org = role.sideRoleOrg?.trimmingCharacters(in: .whitespaces), !org.isEmpty {
                Label(org, systemImage: "building.2.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            if let base = lifeStore.baseJobTitle(at: role.date) {
                Label("當時本職：\(base)", systemImage: "person.badge.key.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            if let scope = role.sideRoleScope?.trimmingCharacters(in: .whitespaces), !scope.isEmpty {
                Text(scope)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .heroCardShell(card: .sideRoleWorkspace)
        .padding(.horizontal, 16)
    }

    // MARK: 待辦

    private func taskSection(_ role: LifeMilestone) -> some View {
        let tasks = (role.sideRoleTasks ?? []).sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
        }
        let progress = SideRoleFormat.taskProgress(role)
        return sectionBox(title: "待辦", icon: "checklist", color: .indigo,
                          trailing: "\(progress.done)/\(progress.total)",
                          onAdd: { editingTask = SideRoleTask() }) {
            if tasks.isEmpty {
                emptyRow("還沒有待辦事項")
            } else {
                ForEach(tasks) { task in
                    SwipeDeleteRow(onDelete: { lifeStore.deleteSideRoleTask(task.id, in: roleId) }) {
                        taskRow(task)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: SideRoleTask) -> some View {
        HStack(spacing: 10) {
            Button {
                var t = task
                t.isCompleted.toggle()
                t.completedAt = t.isCompleted ? Date() : nil
                lifeStore.upsertSideRoleTask(t, in: roleId)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(task.isCompleted ? .indigo : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!subscription.isPremium)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.content.isEmpty ? "（未填內容）" : task.content)
                    .font(.subheadline)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                if let due = task.dueDate {
                    let overdue = !task.isCompleted && due < Calendar.current.startOfDay(for: Date())
                    Text((overdue ? "已逾期 · " : "") + SideRoleFormat.date(due))
                        .font(.caption2)
                        .foregroundStyle(overdue ? .red : .secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture { editingTask = task }
    }

    // MARK: 重要日期

    private func keyDateSection(_ role: LifeMilestone) -> some View {
        let dates = (role.sideRoleKeyDates ?? []).sorted { $0.date < $1.date }
        return sectionBox(title: "重要日期", icon: "calendar", color: .indigo,
                          trailing: "\(dates.count)",
                          onAdd: { editingKeyDate = SideRoleKeyDate() }) {
            if dates.isEmpty {
                emptyRow("還沒有重要日期。加進來的日期會同時顯示在「我的行事曆」上。")
            } else {
                ForEach(dates) { kd in
                    SwipeDeleteRow(onDelete: { lifeStore.deleteSideRoleKeyDate(kd.id, in: roleId) }) {
                        keyDateRow(kd)
                    }
                }
            }
        }
    }

    private func keyDateRow(_ kd: SideRoleKeyDate) -> some View {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: kd.date)).day ?? 0
        return HStack(spacing: 10) {
            VStack(spacing: 1) {
                Text("\(cal.component(.month, from: kd.date))/\(cal.component(.day, from: kd.date))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("\(cal.component(.year, from: kd.date))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(kd.title.isEmpty ? "（未命名）" : kd.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if !kd.note.isEmpty {
                    Text(kd.note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if days >= 0 && days <= 30 {
                Text(days == 0 ? "今天" : "剩 \(days) 天")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(days <= 7 ? .orange : .indigo)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((days <= 7 ? Color.orange : Color.indigo).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture { editingKeyDate = kd }
    }

    // MARK: 成員

    private func memberSection(_ role: LifeMilestone) -> some View {
        let members = role.sideRoleMembers ?? []
        let hasPrevious = lifeStore.previousTermOfSideRole(role) != nil
        return sectionBox(title: "成員名單", icon: "person.2.fill", color: .indigo,
                          trailing: "\(members.count)",
                          onAdd: { editingMember = SideRoleMember() }) {
            if hasPrevious && subscription.isPremium {
                Button {
                    let n = lifeStore.copyMembersFromPreviousTerm(into: role)
                    showCopyResult = n > 0 ? "已從上一屆複製 \(n) 位成員。"
                                           : "上一屆的成員都已經在名單裡了。"
                } label: {
                    Label("複製上一屆名單", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            if members.isEmpty {
                emptyRow("還沒有成員")
            } else {
                ForEach(members) { m in
                    SwipeDeleteRow(onDelete: { lifeStore.deleteSideRoleMember(m.id, in: roleId) }) {
                        memberRow(m)
                    }
                }
            }
        }
    }

    private func memberRow(_ m: SideRoleMember) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 34, height: 34)
                Text(String(m.name.prefix(1)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.indigo)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name.isEmpty ? "（未填姓名）" : m.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if !m.dutyInRole.isEmpty || !m.contact.isEmpty {
                    Text([m.dutyInRole, m.contact].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture { editingMember = m }
    }

    // MARK: 會議

    private func meetingSection(_ role: LifeMilestone) -> some View {
        let meetings = (role.sideRoleMeetings ?? []).sorted { $0.date > $1.date }
        return sectionBox(title: "會議紀錄", icon: "text.bubble.fill", color: .indigo,
                          trailing: "\(meetings.count)",
                          onAdd: { editingMeeting = SideRoleMeeting() }) {
            if meetings.isEmpty {
                emptyRow("還沒有會議紀錄")
            } else {
                ForEach(meetings) { mt in
                    SwipeDeleteRow(onDelete: { lifeStore.deleteSideRoleMeeting(mt.id, in: roleId) }) {
                        meetingRow(mt)
                    }
                }
            }
        }
    }

    private func meetingRow(_ mt: SideRoleMeeting) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(SideRoleFormat.date(mt.date))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())
                    Text(mt.topic.isEmpty ? "（未填主題）" : mt.topic)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                if !mt.attendees.isEmpty {
                    Text("出席：" + mt.attendees.joined(separator: "、"))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if !mt.decisions.isEmpty {
                    Text(mt.decisions)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture { editingMeeting = mt }
    }

    // MARK: 共用外框

    /// 區塊外框。抽成帶 @ViewBuilder 的單一函式，四個區塊共用——
    /// 不為每個區塊各寫一個 struct（本專案有過型別深度爆棧的事故）。
    @ViewBuilder
    private func sectionBox<Content: View>(title: String, icon: String, color: Color,
                                           trailing: String, onAdd: @escaping () -> Void,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(colors: [color, color.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(trailing)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .disabled(!subscription.isPremium)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            content()
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 14)
            .background(Color(.systemBackground))
    }
}

// MARK: - 編輯表單
//
// 四個編輯器都吃「roleId + 一份子項目」，存檔走 LifeStore 的 upsert，
// 刪除走 destructive 按鈕（列表上的左滑刪除是另一條路徑，兩者並存）。

struct SideRoleTaskEditor: View {
    let roleId: UUID
    @State var task: SideRoleTask

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var hasDue = false

    var body: some View {
        Form {
            Section("內容") {
                TextField("待辦內容", text: $task.content, axis: .vertical).lineLimit(3)
            }
            Section("截止日") {
                Toggle("設定截止日", isOn: $hasDue)
                if hasDue {
                    DatePicker("截止日", selection: Binding(
                        get: { task.dueDate ?? Date() },
                        set: { task.dueDate = $0 }
                    ), displayedComponents: .date)
                }
            }
            Section("備註") {
                TextField("選填備註", text: $task.note, axis: .vertical).lineLimit(3)
            }
            Section {
                Button(role: .destructive) {
                    lifeStore.deleteSideRoleTask(task.id, in: roleId)
                    dismiss()
                } label: {
                    Label("刪除此待辦", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("待辦")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") {
                    if !hasDue { task.dueDate = nil }
                    lifeStore.upsertSideRoleTask(task, in: roleId)
                    dismiss()
                }
                .disabled(task.content.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { hasDue = task.dueDate != nil }
    }
}

struct SideRoleMemberEditor: View {
    let roleId: UUID
    @State var member: SideRoleMember

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("成員") {
                TextField("姓名", text: $member.name)
                TextField("分工（例：場控、攝影）", text: $member.dutyInRole)
                TextField("聯絡方式（選填）", text: $member.contact)
            }
            Section("備註") {
                TextField("選填備註", text: $member.note, axis: .vertical).lineLimit(3)
            }
            Section {
                Button(role: .destructive) {
                    lifeStore.deleteSideRoleMember(member.id, in: roleId)
                    dismiss()
                } label: {
                    Label("刪除此成員", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("成員")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") {
                    lifeStore.upsertSideRoleMember(member, in: roleId)
                    dismiss()
                }
                .disabled(member.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

struct SideRoleMeetingEditor: View {
    let roleId: UUID
    @State var meeting: SideRoleMeeting

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    /// 出席者用逗號分隔輸入，存進去時切成陣列
    @State private var attendeeText = ""

    var body: some View {
        Form {
            Section("會議") {
                DatePicker("日期", selection: $meeting.date, displayedComponents: .date)
                TextField("主題", text: $meeting.topic)
            }
            Section {
                TextField("出席者（用、或,分隔）", text: $attendeeText, axis: .vertical).lineLimit(2)
            } header: {
                Text("出席者")
            } footer: {
                Text("例：王小明、李大華、陳美玲")
            }
            Section("決議事項") {
                TextField("決議", text: $meeting.decisions, axis: .vertical).lineLimit(5)
            }
            Section("備註") {
                TextField("選填備註", text: $meeting.note, axis: .vertical).lineLimit(3)
            }
            Section {
                Button(role: .destructive) {
                    lifeStore.deleteSideRoleMeeting(meeting.id, in: roleId)
                    dismiss()
                } label: {
                    Label("刪除此會議紀錄", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("會議紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") {
                    meeting.attendees = attendeeText
                        .split(whereSeparator: { $0 == "、" || $0 == "," || $0 == "，" })
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    lifeStore.upsertSideRoleMeeting(meeting, in: roleId)
                    dismiss()
                }
                .disabled(meeting.topic.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { attendeeText = meeting.attendees.joined(separator: "、") }
    }
}

struct SideRoleKeyDateEditor: View {
    let roleId: UUID
    @State var keyDate: SideRoleKeyDate

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var hasRemind = false
    @State private var remindDays = 3

    var body: some View {
        Form {
            Section("重要日期") {
                DatePicker("日期", selection: $keyDate.date, displayedComponents: .date)
                TextField("名稱（例：場地確認、彩排）", text: $keyDate.title)
            }
            Section {
                Toggle("提醒", isOn: $hasRemind)
                if hasRemind {
                    Stepper("提前 \(remindDays) 天", value: $remindDays, in: 0...30)
                }
            } header: {
                Text("提醒")
            } footer: {
                Text("這個日期會顯示在「我的行事曆」上。")
            }
            Section("備註") {
                TextField("選填備註", text: $keyDate.note, axis: .vertical).lineLimit(3)
            }
            Section {
                Button(role: .destructive) {
                    lifeStore.deleteSideRoleKeyDate(keyDate.id, in: roleId)
                    dismiss()
                } label: {
                    Label("刪除此日期", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("重要日期")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") {
                    keyDate.remindDaysBefore = hasRemind ? remindDays : nil
                    lifeStore.upsertSideRoleKeyDate(keyDate, in: roleId)
                    dismiss()
                }
                .disabled(keyDate.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            hasRemind = keyDate.remindDaysBefore != nil
            remindDays = keyDate.remindDaysBefore ?? 3
        }
    }
}
