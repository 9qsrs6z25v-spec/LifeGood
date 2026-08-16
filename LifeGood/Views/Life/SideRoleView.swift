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
// 當中樞入口，中樞裡再用 .sheet(item:) 開各筆的管理頁——
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

    /// 一則待辦的負責人姓名（逗號串接）。名稱取自成員名單的文字快照，
    /// 指派到已被刪除的成員時該筆自動略過（刪成員時本來就會清掉指派，
    /// 這裡只是多一層保險，避免舊資料留下的懸空 id 印出空字串）。
    static func assigneeNames(_ task: SideRoleTask, in role: LifeMilestone) -> String {
        guard let ids = task.assigneeIds, !ids.isEmpty else { return "" }
        let members = role.sideRoleMembers ?? []
        return ids.compactMap { id in
            members.first { $0.id == id }?.name.trimmingCharacters(in: .whitespaces)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "、")
    }

    /// 待辦完成度
    static func taskProgress(_ role: LifeMilestone) -> (done: Int, total: Int) {
        let list = role.sideRoleTasks ?? []
        return (list.filter(\.isCompleted).count, list.count)
    }
}

// MARK: - 資料來源：既有人員與既有單位

/// 兼任職務成員可挑選的人員。三個來源：部屬、名片、公司組織人員。
///
/// ⚠️ 早期版本只列部屬與名片，理由寫的是「公司組織人員會與這兩者雙向同步」——
///    那是錯的。刪除一張名片時，LifeStore 只會把 OrgPerson.linkedBusinessCardId
///    清成 nil、人員本身留著（LifeStore.deleteBusinessCard），這種人既不是部屬
///    也沒有名片，於是完全挑不到。跨部門的同事多半就是這樣進來的，
///    造成「其他部門的人選不到」。現在三個來源都列，靠 id 連結去重。
struct SideRolePersonCandidate: Identifiable, Hashable {
    enum Kind: String {
        case subordinate = "部屬"
        case card = "名片"
        case orgPerson = "組織"
        var icon: String {
            switch self {
            case .subordinate: return "person.2.fill"
            case .card:        return "person.crop.rectangle.stack"
            case .orgPerson:   return "building.2.crop.circle"
            }
        }
    }
    let id: UUID
    let kind: Kind
    let name: String
    /// 職稱／公司，挑人時用來分辨同名的人
    let subtitle: String
    /// 自動帶入用的聯絡方式（名片才有）
    let contact: String
    /// 部門名稱（沒有就空字串）。挑跨部門的人時，這是唯一分得出誰是誰的欄位，
    /// 所以拉成獨立欄位供分組與篩選用，不只是塞進 subtitle。
    var department: String = ""
}

extension LifeStore {
    /// 挑選成員用的人員清單。
    /// 刻意不複用 mentionPeople()：那個是給 @ 標註用的、不帶聯絡方式，
    /// 而這裡挑完人要能自動帶入電話／Email，少了會變成挑完還要手動再打一次。
    func sideRolePersonCandidates() -> [SideRolePersonCandidate] {
        var out: [SideRolePersonCandidate] = []
        let deptName = Dictionary(departments.map { ($0.id, $0.name) },
                                  uniquingKeysWith: { a, _ in a })

        // 部屬本身沒有聯絡方式欄位，電話／Email 存在他自動產生的那張名片上。
        // 去重之後名片那一列不再出現，所以要在這裡把聯絡方式接回來，
        // 否則挑了部屬卻帶不進電話，等於比去重前更難用。
        let cardById = Dictionary(businessCards.map { ($0.id, $0) },
                                  uniquingKeysWith: { a, _ in a })
        var contactOfSub: [UUID: String] = [:]
        for p in orgPeople {
            guard let sid = p.linkedSubordinateId, let cid = p.linkedBusinessCardId,
                  let card = cardById[cid] else { continue }
            let c = card.phones.first ?? card.emails.first ?? ""
            if !c.isEmpty { contactOfSub[sid] = c }
        }

        for s in subordinates {
            let n = s.name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { continue }
            let dept = s.department.isEmpty
                ? (s.departmentId.flatMap { deptName[$0] } ?? "")
                : s.department
            let sub = [s.jobTitle, dept].filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(SideRolePersonCandidate(id: s.id, kind: .subordinate,
                                               name: n, subtitle: sub,
                                               contact: contactOfSub[s.id] ?? "",
                                               department: dept))
        }
        // ⚠️ 每新增一位有部門的部屬，LifeStore.syncOrgPersonFor(subordinate:) 會
        //    **自動**幫他建一張名片與一個組織人員。所以「全部部屬 + 全部名片」會讓
        //    同一個人出現兩次（一次部屬、一次名片），而且兩列名字一模一樣、
        //    只有右側小標籤有差，使用者根本分不出哪一列才是對的。
        //
        //    點到名片那一列的後果是實質的：成員的 linkedPersonId 存成名片 id，
        //    於是部屬明細頁的「兼任職務參與」查不到（那裡用部屬 id 反查）、
        //    他完成的兼任待辦也不會計入主動性評分（sideRoleTaskCounts 記在名片 id 底下）。
        //
        //    因此：凡是能循「名片 → 組織人員 → 部屬」連回某位部屬的名片一律不列，
        //    部屬身分才是這個人的正典 id。
        let listedSubIds = Set(subordinates.map(\.id))
        let cardIdsOwnedBySubordinates = Set(
            orgPeople.compactMap { p -> UUID? in
                guard let sid = p.linkedSubordinateId, listedSubIds.contains(sid) else { return nil }
                return p.linkedBusinessCardId
            }
        )
        for c in businessCards where !cardIdsOwnedBySubordinates.contains(c.id) {
            let n = c.name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { continue }
            let sub = [c.company, c.jobTitle, c.department]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            let contact = c.phones.first ?? c.emails.first ?? ""
            out.append(SideRolePersonCandidate(id: c.id, kind: .card,
                                               name: n, subtitle: sub, contact: contact,
                                               department: c.department))
        }
        // 組織人員：只補「既不是部屬、也沒有名片」的那些，避免同一個人列三次。
        // 已離職者不列（isInactive）——找人做事不會找已經離開的人。
        let linkedSubIds = listedSubIds
        let linkedCardIds = Set(businessCards.map(\.id))
        for p in orgPeople where !p.isInactive {
            let n = p.name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { continue }
            if let sid = p.linkedSubordinateId, linkedSubIds.contains(sid) { continue }
            if let cid = p.linkedBusinessCardId, linkedCardIds.contains(cid) { continue }
            let dept = p.departmentId.flatMap { deptName[$0] } ?? ""
            let title = gradeTitles.first { $0.id == p.gradeTitleId }?.title ?? p.jobTitle
            let sub = [title, dept].filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(SideRolePersonCandidate(id: p.id, kind: .orgPerson,
                                               name: n, subtitle: sub, contact: "",
                                               department: dept))
        }
        return out.sorted {
            // 先依部門再依姓名：跨部門挑人時，同部門的人會聚在一起
            if $0.department != $1.department { return $0.department < $1.department }
            return $0.name < $1.name
        }
    }

    /// 依 id 找回被連結的人現在的樣子。用來在名單上標「已連結」，
    /// 以及在對方已被刪除時把徽章收掉——連結是額外資訊，斷了不影響名單本身，
    /// 因為姓名一律存的是文字快照。
    func sideRolePerson(_ id: UUID?) -> SideRolePersonCandidate? {
        guard let id else { return nil }
        return sideRolePersonCandidates().first { $0.id == id }
    }

    /// 主辦單位的候選清單：公司內部單位（部門表）＋ 過去填過的外部單位。
    /// 兼任職務的主辦單位常常是外部組織（例如「台灣氣體化學工業協會」），
    /// 不在部門表裡，所以填過一次就收進建議、下次直接選。
    func sideRoleOrgSuggestions() -> (internalUnits: [String], usedBefore: [String]) {
        let units = departments
            .map { $0.name.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let used = sideRoles
            .compactMap { $0.sideRoleOrg?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let unitSet = Set(units)
        // 已經在部門表裡的就不重複列進「用過」
        let extras = Array(Set(used).subtracting(unitSet)).sorted()
        return (Array(Set(units)).sorted(), extras)
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
    @State private var viewingRole: LifeMilestone?
    @State private var dormantExpanded = false
    @State private var heroAppeared = false

    private var roles: [LifeMilestone] { lifeStore.sideRoleWorkspaces }
    private var dormant: [LifeMilestone] { lifeStore.dormantSideRoles }

    // ⚠️ MainTabView 沒有任何 NavigationStack，每個管理頁都必須自己帶一個
    //（比照 SubordinateView / GradeTitleView / OrganizationView 的既有寫法）。
    //   少了它，navigationTitle 與 toolbar 都不會出現、NavigationLink 也完全點不動——
    //   卡片畫得出來但按了沒反應。也因此本專案的管理頁一律用 .sheet(item:) 開明細，
    //   全 App 的管理頁沒有任何一處用 NavigationLink 推頁。
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    heroCard
                    if roles.isEmpty {
                        emptyState
                    } else {
                        ForEach(roles) { role in
                            Button { viewingRole = role } label: { roleCard(role) }
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
            .sheet(item: $viewingRole) { role in
                SideRoleWorkspaceView(roleId: role.id)
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
    /// 成員明細裡要不要提供「跳到部屬明細」的入口。
    /// 從部屬明細頁開進來時傳 false——否則會變成
    /// 部屬 → 職務 → 成員 → 部屬 → … 無限往下疊 sheet，而且每一層都要各自關閉。
    var allowSubordinateJump: Bool = true

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var editingTask: SideRoleTask?
    @State private var editingMember: SideRoleMember?
    /// 點成員列開明細（可看到他負責的待辦與出席的會議）；編輯是明細頁裡的動作
    @State private var viewingMember: SideRoleMember?
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
                // 這一頁在別處被刪除時會落到這裡。它同樣是 sheet，
                // 一樣要自己帶 NavigationStack 才會有「關閉」可按。
                NavigationStack {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("關閉") { dismiss() }
                        }
                    }
                }
            }
        }
    }

    private func content(_ role: LifeMilestone) -> some View {
        // 這頁是被 .sheet 開起來的，同樣要自己帶 NavigationStack 才有標題與工具列
        //（對齊 SubordinateDetailView 的既有寫法：左上「關閉」、右上動作）。
        NavigationStack {
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditRole = true } label: { Image(systemName: "square.and.pencil") }
                        .disabled(!subscription.isPremium)
                }
            }
        }
        .sheet(isPresented: $showEditRole) {
            NavigationStack { AddMilestoneView(editing: role) }
        }
        .sheet(item: $editingTask) { t in
            NavigationStack { SideRoleTaskEditor(roleId: roleId, task: t) }
        }
        .sheet(item: $viewingMember) { m in
            SideRoleMemberDetailView(roleId: roleId, memberId: m.id,
                                     allowSubordinateJump: allowSubordinateJump)
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
                        taskRow(task, assigneeNames: SideRoleFormat.assigneeNames(task, in: role))
                    }
                }
            }
        }
    }

    private func taskRow(_ task: SideRoleTask, assigneeNames: String) -> some View {
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
                HStack(spacing: 5) {
                    if let due = task.dueDate {
                        let overdue = !task.isCompleted && due < Calendar.current.startOfDay(for: Date())
                        Text((overdue ? "已逾期 · " : "") + SideRoleFormat.date(due))
                            .font(.caption2)
                            .foregroundStyle(overdue ? .red : .secondary)
                    }
                    if !assigneeNames.isEmpty {
                        Text(assigneeNames)
                            .font(.caption2)
                            .foregroundStyle(.indigo.opacity(0.85))
                            .lineLimit(1)
                    }
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
        // 人員對照表只建一次往下傳。放在 memberRow 裡就是每一列各建一次
        // 完整清單（部屬 + 名片）並排序——15 位成員等於在 body 裡跑 15 次，
        // 這是本專案改版紀錄裡反覆出現的那類效能問題。
        let peopleIndex = Dictionary(lifeStore.sideRolePersonCandidates().map { ($0.id, $0) },
                                     uniquingKeysWith: { a, _ in a })
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
                        memberRow(m, peopleIndex: peopleIndex,
                                  taskStat: memberTaskStat(of: m.id, in: role))
                    }
                }
            }
        }
    }

    /// 這位成員被指派了幾則待辦、完成幾則
    private func memberTaskStat(of memberId: UUID, in role: LifeMilestone) -> (done: Int, total: Int) {
        let list = lifeStore.sideRoleTasks(of: memberId, in: role)
        return (list.filter(\.isCompleted).count, list.count)
    }

    private func memberRow(_ m: SideRoleMember,
                           peopleIndex: [UUID: SideRolePersonCandidate],
                           taskStat: (done: Int, total: Int)) -> some View {
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
                HStack(spacing: 5) {
                    Text(m.name.isEmpty ? "（未填姓名）" : m.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let id = m.linkedPersonId, let p = peopleIndex[id] {
                        Image(systemName: p.kind.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(.indigo.opacity(0.7))
                    }
                }
                if !m.dutyInRole.isEmpty || !m.contact.isEmpty {
                    Text([m.dutyInRole, m.contact].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if taskStat.total > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9))
                    Text("\(taskStat.done)/\(taskStat.total)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(taskStat.done == taskStat.total ? .green : .indigo)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background((taskStat.done == taskStat.total ? Color.green : Color.indigo).opacity(0.12))
                .clipShape(Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture { viewingMember = m }
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

    /// 這筆兼任職務底下的成員名單（指派對象）
    private var members: [SideRoleMember] {
        lifeStore.milestones.first { $0.id == roleId }?.sideRoleMembers ?? []
    }

    var body: some View {
        Form {
            Section("內容") {
                TextField("待辦內容", text: $task.content, axis: .vertical).lineLimit(3)
            }
            Section {
                if members.isEmpty {
                    Text("還沒有成員。先到「成員名單」新增，就能把待辦指派給人。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // 直接列成可勾選的列，不用 Picker——多選在 Picker 上表達不了，
                    // 而成員數量本來就不多（一場尾牙十來個人），攤開反而好按。
                    ForEach(members) { m in
                        Button {
                            toggleAssignee(m.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isAssigned(m.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(isAssigned(m.id) ? .indigo : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(m.name.isEmpty ? "（未填姓名）" : m.name)
                                        .foregroundStyle(.primary)
                                    if !m.dutyInRole.isEmpty {
                                        Text(m.dutyInRole)
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("負責成員")
            } footer: {
                Text("可以多選。指派後，在成員頁就看得到他負責哪些事。")
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
                    // 空陣列收成 nil：兩者語意相同，但留著空陣列會讓 JSON 多一個
                    // 沒意義的鍵，也讓 assigneeIds != nil 的判斷變得不可靠。
                    if task.assigneeIds?.isEmpty == true { task.assigneeIds = nil }
                    lifeStore.upsertSideRoleTask(task, in: roleId)
                    dismiss()
                }
                .disabled(task.content.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { hasDue = task.dueDate != nil }
    }

    private func isAssigned(_ id: UUID) -> Bool {
        task.assigneeIds?.contains(id) == true
    }

    private func toggleAssignee(_ id: UUID) {
        var ids = task.assigneeIds ?? []
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
        task.assigneeIds = ids.isEmpty ? nil : ids
    }
}

struct SideRoleMemberEditor: View {
    let roleId: UUID
    @State var member: SideRoleMember

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false

    /// 目前連結到的人（可能已被刪除 → nil）
    private var linked: SideRolePersonCandidate? {
        lifeStore.sideRolePerson(member.linkedPersonId)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Label("從部屬／名片挑人", systemImage: "person.crop.circle.badge.plus")
                            .foregroundStyle(.indigo)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                if let linked {
                    HStack(spacing: 8) {
                        Image(systemName: linked.kind.icon)
                            .font(.caption)
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("已連結\(linked.kind.rawValue)：\(linked.name)")
                                .font(.caption)
                            if !linked.subtitle.isEmpty {
                                Text(linked.subtitle)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("解除") { member.linkedPersonId = nil }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                    }
                } else if member.linkedPersonId != nil {
                    // 連結指向的人已經被刪除。姓名是文字快照所以名單本身沒事，
                    // 但要講清楚，不然使用者不知道這裡曾經連過。
                    HStack(spacing: 8) {
                        Image(systemName: "link.badge.plus")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("原本連結的人已不存在，姓名仍保留")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("清除連結") { member.linkedPersonId = nil }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                    }
                }
            } footer: {
                Text("挑人只是把姓名與聯絡方式帶過來，之後對方資料異動或被刪除，這份名單都不會受影響。外部人員直接手動輸入即可。")
            }

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
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                SideRolePersonPicker { picked in
                    member.linkedPersonId = picked.id
                    member.name = picked.name
                    // 只在空白時才帶入，不覆蓋使用者已經打好的內容
                    if member.contact.trimmingCharacters(in: .whitespaces).isEmpty {
                        member.contact = picked.contact
                    }
                    if member.dutyInRole.trimmingCharacters(in: .whitespaces).isEmpty {
                        member.dutyInRole = picked.subtitle
                    }
                }
            }
        }
    }
}

/// 挑人清單。單一參數化 struct + 搜尋 + 部門篩選，不為每種來源各寫一份。
///
/// 跨部門挑人是主要情境（要 drive 別的部門的人），所以清單依部門分組、
/// 上方有部門篩選膠囊列——只靠一個平坦的姓名清單，人一多就等於找不到。
struct SideRolePersonPicker: View {
    let onPick: (SideRolePersonCandidate) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var deptFilter: String?

    private var all: [SideRolePersonCandidate] { lifeStore.sideRolePersonCandidates() }

    /// 有人的部門清單（依人數多寡排序，人最多的排前面）
    private var departments: [String] {
        Dictionary(grouping: all, by: { $0.department.isEmpty ? "未分部門" : $0.department })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
            .map(\.0)
    }

    private var candidates: [SideRolePersonCandidate] {
        var list = all
        if let deptFilter {
            list = list.filter {
                ($0.department.isEmpty ? "未分部門" : $0.department) == deptFilter
            }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(q)
                          || $0.subtitle.localizedCaseInsensitiveContains(q)
                          || $0.department.localizedCaseInsensitiveContains(q) }
    }

    /// 依部門分組（保留 candidates 的排序）
    private var grouped: [(dept: String, people: [SideRolePersonCandidate])] {
        var order: [String] = []
        var map: [String: [SideRolePersonCandidate]] = [:]
        for p in candidates {
            let key = p.department.isEmpty ? "未分部門" : p.department
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(p)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        List {
            if departments.count > 1 {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            deptChip("全部", value: nil)
                            ForEach(departments, id: \.self) { d in
                                deptChip(d, value: d)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            if candidates.isEmpty {
                Text(all.isEmpty
                     ? "還沒有部屬、名片或公司組織人員。可以直接在上一頁手動輸入姓名。"
                     : "找不到符合的人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(grouped, id: \.dept) { group in
                    Section(group.dept) {
                        ForEach(group.people) { p in
                            Button {
                                onPick(p)
                                dismiss()
                            } label: {
                                personRow(p)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜尋姓名、職稱或部門")
        .navigationTitle("挑選成員")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }

    private func deptChip(_ label: String, value: String?) -> some View {
        let selected = deptFilter == value
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { deptFilter = value }
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(selected ? AnyShapeStyle(Color.indigo) : AnyShapeStyle(.ultraThinMaterial))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.primary.opacity(selected ? 0 : 0.08), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func personRow(_ p: SideRolePersonCandidate) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: p.kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.indigo)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.subheadline).foregroundStyle(.primary)
                if !p.subtitle.isEmpty {
                    Text(p.subtitle).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(p.kind.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
        }
    }
}

struct SideRoleMeetingEditor: View {
    let roleId: UUID
    @State var meeting: SideRoleMeeting

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    /// 手動輸入的出席者（用、或,分隔）。與挑選來的名單合併後存檔。
    @State private var attendeeText = ""
    @State private var showAttendeePicker = false

    var body: some View {
        Form {
            Section("會議") {
                DatePicker("日期", selection: $meeting.date, displayedComponents: .date)
                TextField("主題", text: $meeting.topic)
            }
            Section {
                if !meeting.attendees.isEmpty {
                    // 已選出席者的膠囊列，點 × 移除
                    FlexibleChipWrap(items: meeting.attendees) { name in
                        HStack(spacing: 4) {
                            Text(name).font(.caption)
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.indigo.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.6))
                        .onTapGesture {
                            meeting.attendees.removeAll { $0 == name }
                        }
                    }
                }
                Button {
                    showAttendeePicker = true
                } label: {
                    Label("從成員／部屬／名片／組織挑人", systemImage: "person.crop.circle.badge.plus")
                        .foregroundStyle(.indigo)
                }
                TextField("或直接輸入（用、或,分隔）", text: $attendeeText, axis: .vertical)
                    .lineLimit(2)
            } header: {
                Text("出席者")
            } footer: {
                Text("挑人涵蓋這個職務的成員、以及全部部屬、名片與公司組織人員（含其他部門）。外部與會者直接打字即可，兩種方式可以混用。")
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
                    // 挑選來的（已在 meeting.attendees）＋ 手打的，合併去重、保留順序
                    let typed = attendeeText
                        .split(whereSeparator: { $0 == "、" || $0 == "," || $0 == "，" })
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    var merged = meeting.attendees
                    for n in typed where !merged.contains(n) { merged.append(n) }
                    meeting.attendees = merged
                    lifeStore.upsertSideRoleMeeting(meeting, in: roleId)
                    dismiss()
                }
                .disabled(meeting.topic.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(isPresented: $showAttendeePicker) {
            NavigationStack {
                SideRoleAttendeePicker(roleId: roleId, selected: $meeting.attendees)
            }
        }
        // 出席者改成「膠囊＋挑人」後，attendeeText 只承載「還沒挑過的手打內容」，
        // 不再預先塞入既有名單——否則儲存時會與膠囊列的內容重複合併一次。
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

// MARK: - 成員明細

/// 點成員列進來的頁面：這個人是誰、他負責哪些待辦、他出席過哪些會議。
///
/// 資料一律從 store 現查（吃 roleId + memberId），不快取進 @State——
/// 在這頁勾完成一則待辦後，統計與清單要立刻跟著更新。
struct SideRoleMemberDetailView: View {
    let roleId: UUID
    let memberId: UUID
    /// 見 SideRoleWorkspaceView.allowSubordinateJump
    var allowSubordinateJump: Bool = true

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var editingTask: SideRoleTask?
    /// 點「已連結部屬」跳過去的部屬。存整個 Subordinate 而不是 UUID——
    /// UUID 沒有 Identifiable，.sheet(item:) 吃不了。
    @State private var viewingSubordinate: Subordinate?

    private var role: LifeMilestone? {
        lifeStore.milestones.first { $0.id == roleId }
    }
    private var member: SideRoleMember? {
        role?.sideRoleMembers?.first { $0.id == memberId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let role, let member {
                    content(role: role, member: member)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("找不到這位成員")
                            .font(.subheadline.weight(.semibold))
                        Text("他可能已經從名單裡移除了。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(member?.name.isEmpty == false ? member!.name : "成員")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                if member != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showEdit = true } label: { Image(systemName: "square.and.pencil") }
                            .disabled(!subscription.isPremium)
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                if let member {
                    NavigationStack { SideRoleMemberEditor(roleId: roleId, member: member) }
                }
            }
            .sheet(item: $editingTask) { t in
                NavigationStack { SideRoleTaskEditor(roleId: roleId, task: t) }
            }
            .sheet(item: $viewingSubordinate) { sub in
                SubordinateDetailView(subordinate: sub)
            }
        }
    }

    private func content(role: LifeMilestone, member: SideRoleMember) -> some View {
        let tasks = lifeStore.sideRoleTasks(of: memberId, in: role)
        let done = tasks.filter(\.isCompleted).count
        let meetings = attendedMeetings(role: role, member: member)
        return ScrollView {
            LazyVStack(spacing: 14) {
                headerCard(role: role, member: member, done: done, total: tasks.count,
                           meetingCount: meetings.count)
                taskBox(tasks)
                meetingBox(meetings)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: 標頭

    private func headerCard(role: LifeMilestone, member: SideRoleMember,
                            done: Int, total: Int, meetingCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.20))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 0.75))
                    Text(String(member.name.prefix(1)))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name.isEmpty ? "（未填姓名）" : member.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(SideRoleFormat.displayName(role))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                }
                Spacer()
            }
            if !member.dutyInRole.isEmpty {
                Label(member.dutyInRole, systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(.white.opacity(0.88))
            }
            if !member.contact.isEmpty {
                Label(member.contact, systemImage: "phone.fill")
                    .font(.caption).foregroundStyle(.white.opacity(0.88))
                    .textSelection(.enabled)
            }
            if let p = lifeStore.sideRolePerson(member.linkedPersonId) {
                if p.kind == .subordinate && allowSubordinateJump {
                    // 只有部屬有明細頁可跳；名片的明細在另一個模式底下，
                    // 從這裡硬跳過去會把使用者丟到完全不同的分頁，反而迷路。
                    Button {
                        viewingSubordinate = lifeStore.subordinates.first { $0.id == p.id }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: p.kind.icon).font(.system(size: 10))
                            Text("已連結部屬：\(p.name)")
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.white.opacity(0.16))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("已連結\(p.kind.rawValue)：\(p.name)", systemImage: p.kind.icon)
                        .font(.caption2).foregroundStyle(.white.opacity(0.75))
                }
            }

            HStack(spacing: 0) {
                HeroKpiCell(label: "負責待辦", value: "\(done)/\(total)", icon: "checklist")
                HeroKpiDivider()
                HeroKpiCell(label: "出席會議", value: "\(meetingCount)", icon: "text.bubble.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "未完成",
                            value: "\(max(0, total - done))",
                            icon: "exclamationmark.circle.fill")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .heroCardShell(card: .sideRoleWorkspace)
        .padding(.horizontal, 16)
    }

    // MARK: 負責的待辦

    private func taskBox(_ tasks: [SideRoleTask]) -> some View {
        box(title: "負責的待辦", icon: "checklist", trailing: "\(tasks.count)") {
            if tasks.isEmpty {
                emptyRow("還沒有指派給他的待辦。到「待辦」區塊編輯任一則，在「負責成員」勾選即可。")
            } else {
                ForEach(tasks) { t in
                    Button {
                        editingTask = t
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(t.isCompleted ? .indigo : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.content.isEmpty ? "（未填內容）" : t.content)
                                    .font(.subheadline)
                                    .strikethrough(t.isCompleted, color: .secondary)
                                    .foregroundStyle(t.isCompleted ? .secondary : .primary)
                                    .lineLimit(2)
                                if let due = t.dueDate {
                                    let overdue = !t.isCompleted
                                        && due < Calendar.current.startOfDay(for: Date())
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
                    }
                    .buttonStyle(.plain)
                    .disabled(!subscription.isPremium)
                }
            }
        }
    }

    // MARK: 出席的會議

    /// 會議的出席者存的是姓名文字（外部與會者很常見，不綁 id），
    /// 所以這裡用姓名比對。姓名為空的成員一律不比對，否則會把所有
    /// 出席者欄位有空字串的會議都算成他出席。
    private func attendedMeetings(role: LifeMilestone, member: SideRoleMember) -> [SideRoleMeeting] {
        let name = member.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return [] }
        return (role.sideRoleMeetings ?? [])
            .filter { $0.attendees.contains { $0.trimmingCharacters(in: .whitespaces) == name } }
            .sorted { $0.date > $1.date }
    }

    private func meetingBox(_ meetings: [SideRoleMeeting]) -> some View {
        box(title: "出席的會議", icon: "text.bubble.fill", trailing: "\(meetings.count)") {
            if meetings.isEmpty {
                emptyRow("還沒有他出席的會議紀錄（依會議的出席者姓名比對）。")
            } else {
                ForEach(meetings) { mt in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(SideRoleFormat.date(mt.date))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.12))
                                .clipShape(Capsule())
                            Text(mt.topic.isEmpty ? "（未填主題）" : mt.topic)
                                .font(.subheadline).lineLimit(1)
                        }
                        if !mt.decisions.isEmpty {
                            Text(mt.decisions)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(.systemBackground))
                }
            }
        }
    }

    // MARK: 共用外框

    @ViewBuilder
    private func box<Content: View>(title: String, icon: String, trailing: String,
                                    @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(colors: [.indigo, .indigo.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text(title).font(.subheadline.weight(.bold))
                Text(trailing)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.indigo.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
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

// MARK: - 從部屬那一側加入兼任職務

/// 「把這位部屬加進某個兼任職務的成員名單」的挑選頁。
///
/// 這是雙向新增的另一半：原本只能從兼任職務的成員名單挑部屬（SideRolePersonPicker），
/// 現在從部屬明細頁也能反過來把他掛進某個職務。兩邊寫入的是同一份
/// SideRoleMember，linkedPersonId 一律填上，所以雙向查詢立刻成立。
struct SideRoleJoinPicker: View {
    let personId: UUID
    let personName: String

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var duty = ""

    /// 尚未加入這位部屬的兼任職務（在任的排前面）
    private var candidates: [LifeMilestone] {
        lifeStore.sideRoles
            .filter { role in
                !(role.sideRoleMembers ?? []).contains { $0.linkedPersonId == personId }
            }
            .sorted {
                if $0.isActiveSideRole != $1.isActiveSideRole { return $0.isActiveSideRole }
                return $0.date > $1.date
            }
    }

    /// 已經加入的（列出來當作說明，避免使用者以為漏了）
    private var joined: [LifeMilestone] {
        lifeStore.sideRoleParticipations(of: personId).map(\.role)
    }

    var body: some View {
        Form {
            Section {
                TextField("分工（選填，例：場控、資料彙整）", text: $duty)
            } header: {
                Text("分工")
            } footer: {
                Text("留空的話會自動帶入他的職稱與部門。")
            }

            Section {
                if candidates.isEmpty {
                    Text(lifeStore.sideRoles.isEmpty
                         ? "目前沒有任何兼任職務。先到「職涯」新增一筆「兼任」里程碑。"
                         : "\(personName.isEmpty ? "這位部屬" : personName) 已經在所有兼任職務的名單裡了。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { role in
                        Button {
                            add(to: role)
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(Color.indigo.opacity(0.12))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.indigo)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(SideRoleFormat.displayName(role))
                                        .foregroundStyle(.primary)
                                    Text(SideRoleFormat.subtitle(role))
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if role.isActiveSideRole {
                                    Text("在任")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.indigo)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.indigo.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("加入哪個兼任職務")
            }

            if !joined.isEmpty {
                Section("已經在名單裡") {
                    ForEach(joined) { role in
                        HStack {
                            Text(SideRoleFormat.displayName(role))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle("加入兼任職務")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        }
    }

    private func add(to role: LifeMilestone) {
        // 用 sideRolePersonCandidates 取回這個人現在的姓名與聯絡方式，
        // 而不是只寫 personName——成員存的是文字快照，寫入當下就該是最完整的一份。
        guard let person = lifeStore.sideRolePerson(personId) else { return }
        lifeStore.addPersonToSideRole(person, roleId: role.id, dutyInRole: duty)
        dismiss()
    }
}

// MARK: - 出席者挑選

/// 會議出席者挑選：涵蓋這個職務的成員 ＋ 全部部屬／名片／公司組織人員。
///
/// 與 SideRolePersonPicker 的差別：這裡是「多選、回填姓名字串」，
/// 因為 SideRoleMeeting.attendees 存的是姓名文字快照（外部與會者很常見，不綁 id）。
struct SideRoleAttendeePicker: View {
    let roleId: UUID
    @Binding var selected: [String]

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// 這個職務的成員排最前面——開會最常出席的就是自己團隊的人
    private var members: [SideRoleMember] {
        lifeStore.milestones.first { $0.id == roleId }?.sideRoleMembers ?? []
    }

    private var others: [SideRolePersonCandidate] {
        let memberNames = Set(members.map { $0.name.trimmingCharacters(in: .whitespaces) })
        return lifeStore.sideRolePersonCandidates()
            .filter { !memberNames.contains($0.name) }
    }

    private func matches(_ text: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || text.localizedCaseInsensitiveContains(q)
    }

    private var filteredMembers: [SideRoleMember] {
        members.filter { matches($0.name) || matches($0.dutyInRole) }
    }

    private var groupedOthers: [(dept: String, people: [SideRolePersonCandidate])] {
        let list = others.filter { matches($0.name) || matches($0.subtitle) || matches($0.department) }
        var order: [String] = []
        var map: [String: [SideRolePersonCandidate]] = [:]
        for p in list {
            let key = p.department.isEmpty ? "未分部門" : p.department
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(p)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        List {
            if !filteredMembers.isEmpty {
                Section("本職務成員") {
                    ForEach(filteredMembers) { m in
                        row(name: m.name, sub: m.dutyInRole, icon: "person.badge.plus")
                    }
                }
            }
            ForEach(groupedOthers, id: \.dept) { group in
                Section(group.dept) {
                    ForEach(group.people) { p in
                        row(name: p.name, sub: p.subtitle, icon: p.kind.icon)
                    }
                }
            }
            if filteredMembers.isEmpty && groupedOthers.isEmpty {
                Text("找不到符合的人。外部與會者可以回上一頁直接輸入姓名。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: "搜尋姓名、職稱或部門")
        .navigationTitle("挑選出席者")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
    }

    private func row(name: String, sub: String, icon: String) -> some View {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let isOn = selected.contains(trimmed)
        return Button {
            guard !trimmed.isEmpty else { return }
            if isOn { selected.removeAll { $0 == trimmed } }
            else { selected.append(trimmed) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? .indigo : .secondary)
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.indigo.opacity(0.7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(trimmed.isEmpty ? "（未填姓名）" : trimmed)
                        .foregroundStyle(.primary)
                    if !sub.isEmpty {
                        Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(trimmed.isEmpty)
    }
}

// MARK: - 自動換行膠囊列

/// 會依寬度自動換行的膠囊容器。SwiftUI 沒有內建的 flow layout，
/// 用 iOS 16+ 的 Layout 協定實作一份最小可用版本（只做換行，不做對齊變化）。
struct FlexibleChipWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        ChipFlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
