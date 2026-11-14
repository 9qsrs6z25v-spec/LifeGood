import SwiftUI

// MARK: - 全部運動紀錄（v25.553，健康 v3；health/judge.md §3.5）
//
// 健康頁「看全部紀錄（148 趟）›」推進來的一頁（NavigationLink；HealthView 的 NavigationStack 裡）。
// 列表頁的寫法照記帳、理財、車子列表（U3 §3）：List .insetGrouped＋.listSectionSpacing(.compact)、透明列、
// 一趟一張 MoneyItemCard（卡面是路線形狀，不開地圖：捲一百趟不卡）。
//
// • 最上面篩選膠囊：全部・跑步・健走・騎車・登山・重訓（只列有紀錄的，照 primarySport；「其他有氧」只在「全部」）。
// • 依週分組（週一開始）：組頭左「本週・10/12–10/18」「上週・10/5–10/11」「9/28–10/4」，
//   右「4 趟・跑 14.6・走 3.1 公里」（有幾種寫幾種、重訓另寫「重訓 1 次」）；篩選跑步時「3 趟・14.6 公里」。
// • 右上緊湊／一般（自己的鍵 workout_items_compact，不跟記帳那三頁共用）。
// • 先列 8 週（有紀錄的週才算），最下面「再看 8 週」。
// • 點卡片 → 成果頁（自己的 .sheet(item:)＋.appStores()）；長按：編輯／複製到現在（只有重訓、手動補記）／刪除（先確認）。
//   編輯、複製、刪除要訂閱（待決定 8；沒訂閱跳付費說明）；看成果頁不擋。
// • 資料在 .task(id: lifeStore.workoutsRevision) 算一次（每一趟的卡先做好放著），換篩選只重新分組；body 只畫。
//
// [v25.554] 健康 v4（build/v4/brief.md §G3-9）：刪除確認框照 WorkoutActions.deleteAsk 三種（同健康頁、成果頁）——
//   LifeGood 寫進 Apple 健康的〔連 Apple 健康那筆一起刪〕〔只刪 LifeGood 這筆〕〔取消〕；手錶記的、合成過的〔刪除〕〔取消〕
//  （手錶那一筆不會刪、以後不再帶進來）；沒碰過 Apple 健康的〔刪除〕〔取消〕。

struct WorkoutListView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.colorScheme) private var scheme
    /// 緊湊／一般（只給全部紀錄這一頁；不用記帳那三頁的 MoneyItemCard.compactKey）
    @AppStorage("workout_items_compact") private var compact = false

    /// 依週分好的（新到舊）；篩選過的
    @State private var weeks: [WorkoutListWeek] = []
    /// 有紀錄的運動（篩選膠囊）
    @State private var sports: [WorkoutSport] = []
    /// nil＝全部
    @State private var filter: WorkoutSport?
    /// 列到第幾週（有紀錄的週）
    @State private var shownWeeks = 8
    /// 每一趟的卡（workoutsRevision 變了才重做）
    @State private var itemCache: [UUID: MoneyItem] = [:]
    @State private var loaded = false
    @State private var appeared = false
    @State private var sheet: WorkoutListSheet?
    /// [v25.554] 按了「刪除」、等確認的那一趟（字和三種按鈕先算好：WorkoutActions.deleteAsk）
    @State private var deleteAsk: WorkoutDeleteAsk?
    @State private var showPremiumAlert = false
    /// 複製之後那一行綠字（3 秒）
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

    var body: some View {
        list
            .sheet(item: $sheet) { s in
                sheetView(s)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    private var visibleWeeks: [WorkoutListWeek] { Array(weeks.prefix(shownWeeks)) }

    // MARK: 列表

    private var list: some View {
        List {
            if let notice {
                noticeSection(notice)
            }
            if sports.count > 1 {
                filterSection
            }
            if loaded && weeks.isEmpty {
                emptySection
            } else {
                ForEach(visibleWeeks) { w in
                    weekSection(w)
                }
                if weeks.count > shownWeeks {
                    moreSection
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("全部紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MoneyCompactToggle(compact: $compact)
            }
        }
        .task(id: lifeStore.workoutsRevision) { rebuild() }
        // 進場淡入掛在 List 本身（掛在 ForEach 上會反覆重播，坑 #13）
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .onDisappear {
            noticeTask?.cancel()
            noticeTask = nil
        }
        // 刪除確認掛在 List（付費說明掛在外層，同一個 view 不掛兩個 alert）
        .alert(deleteTitle, isPresented: deleteBinding, presenting: deleteAsk) { a in
            deleteButtons(a)
        } message: { a in
            Text(a.message)
        }
    }

    /// [v25.554] 刪除確認框的按鈕（WorkoutActions.deleteKind）：LifeGood 寫進 Apple 健康的三顆；手錶的、沒碰過的〔刪除〕〔取消〕
    @ViewBuilder
    private func deleteButtons(_ a: WorkoutDeleteAsk) -> some View {
        if a.kind == .withHealth {
            Button("連 Apple 健康那筆一起刪", role: .destructive) { deleteNow(a, alsoFromHealth: true) }
            Button("只刪 LifeGood 這筆", role: .destructive) { deleteNow(a, alsoFromHealth: false) }
        } else {
            Button("刪除", role: .destructive) { deleteNow(a, alsoFromHealth: false) }
        }
        Button("取消", role: .cancel) { }
    }

    private func weekSection(_ w: WorkoutListWeek) -> some View {
        Section {
            ForEach(w.rows) { row in
                card(row)
            }
        } header: {
            WorkoutListWeekHeader(title: w.title, trailing: w.trailing)
        }
    }

    /// 一趟一張卡：點了開成果頁、長按三個動作
    private func card(_ row: WorkoutListRow) -> some View {
        let radius: CGFloat = compact ? 14 : 18
        let gap: CGFloat = compact ? 4 : 6
        let id = row.session.id
        return MoneyItemCard(item: row.item, compact: compact)
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture { sheet = .detail(UUID(), id) }
            .contextMenu { menuItems(row.session) }
            .accessibilityAddTraits(.isButton)
            // VoiceOver 點兩下＝點卡片（明寫，不靠 onTapGesture 自動帶出來）；提示字跟健康頁最近運動同一句
            .accessibilityAction { sheet = .detail(UUID(), id) }
            .accessibilityHint("點兩下看這一趟的成果；長按可以編輯或刪除")
            .listRowInsets(EdgeInsets(top: gap, leading: 16, bottom: gap, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .opacity(appeared ? 1 : 0)
    }

    @ViewBuilder
    private func menuItems(_ s: WorkoutSession) -> some View {
        Button {
            edit(s)
        } label: {
            Label("編輯", systemImage: "pencil")
        }
        if WorkoutActions.canDuplicate(s) {
            Button {
                duplicate(s)
            } label: {
                Label("複製到現在", systemImage: "plus.square.on.square")
            }
        }
        // 跟健康頁最近運動的長按選單同一個樣子（刪除隔一條線）
        Divider()
        Button(role: .destructive) {
            askDelete(s)
        } label: {
            Label("刪除", systemImage: "trash")
        }
    }

    // MARK: 其他列

    private var filterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FinanceFilterChip(text: "全部", on: filter == nil, pal: pal) { setFilter(nil) }
                    ForEach(sports) { s in
                        FinanceFilterChip(text: s.displayName, on: filter == s, pal: pal) { setFilter(s) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func noticeSection(_ text: String) -> some View {
        Section {
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MoneyTone.good.color(pal))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// 「再看 8 週」（樣子照 FinanceMoreButton：藍字、置中）
    private var moreSection: some View {
        let left = max(0, weeks.count - shownWeeks)
        let text = left >= 8 ? "再看 8 週" : "再看 \(left) 週"
        return Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { shownWeeks += 8 }
            } label: {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.hint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(MoneyPressStyle())
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// 一筆都沒有（judge §3.5 那段字；這一頁上面沒有開始鈕，所以寫「回健康頁」）
    private var emptySection: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(WorkoutPalette.sport(.run, dark: scheme == .dark))
                Text("還沒有運動紀錄")
                    .font(.headline)
                Text("回健康頁按「開始跑步」；之前跑過的可以按健康頁右上「＋」補記，例如河濱 5.2 公里・32 分；有戴 Apple Watch 的話，打開健康頁下面的「Apple 健康」，手錶記的會自己出現。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: 彈出頁

    private func sheetView(_ s: WorkoutListSheet) -> AnyView {
        switch s {
        case .detail(_, let id):
            return WorkoutDetailView(sessionId: id).appStores()
        case .editor(_, let session):
            let store = lifeStore
            // onSave 已經在表單關掉之後的下一輪才呼叫
            return WorkoutEditorView(session: session, initialSport: nil) { saved in
                WorkoutActions.save(saved, store: store)
            }
            .appStores()
        }
    }

    // MARK: 動作（編輯、複製、刪除要訂閱；看成果頁不擋）

    private func edit(_ s: WorkoutSession) {
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        sheet = .editor(UUID(), s)
    }

    private func duplicate(_ s: WorkoutSession) {
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        let copy = WorkoutActions.duplicate(s, store: lifeStore)
        showNotice("已複製一份「" + WorkoutFacts.title(copy) + "」到現在")
    }

    /// 長按「刪除」：先問。[v25.554] 拿 store 裡最新的那一筆算要問哪一種（列上的那一份是上一次算的）
    private func askDelete(_ s: WorkoutSession) {
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        let latest = lifeStore.workouts.first(where: { $0.id == s.id }) ?? s
        deleteAsk = WorkoutActions.deleteAsk(latest)
    }

    /// 「刪除 10/15 晨跑 5.2 公里？」
    private var deleteTitle: String {
        deleteAsk?.title ?? ""
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteAsk != nil }, set: { if !$0 { deleteAsk = nil } })
    }

    /// 提示框關掉那一次畫面更新先過，下一輪主執行緒才寫 store（WorkoutActions.delete 已經排到下一輪）；
    /// alsoFromHealth：〔連 Apple 健康那筆一起刪〕。Apple 健康那筆留著的，HealthSyncCenter 記進「不再帶進來」
    private func deleteNow(_ a: WorkoutDeleteAsk, alsoFromHealth: Bool) {
        WorkoutActions.delete(a.id, alsoFromHealth: alsoFromHealth, store: lifeStore)
    }

    /// 綠字 3 秒（同舊健康頁複製提示的寫法）
    private func showNotice(_ text: String) {
        noticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { notice = text }
        noticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { notice = nil }
        }
    }

    private func setFilter(_ s: WorkoutSport?) {
        guard s != filter else { return }
        filter = s
        shownWeeks = 8
        regroup(s, items: itemCache)
    }

    // MARK: 資料

    /// workoutsRevision 變了（新增、編輯、刪除、iCloud 拉下來、體重改了）：每一趟的卡重做一次，再分組
    private func rebuild() {
        let w = lifeStore.latestBodyWeightKg
        var map: [UUID: MoneyItem] = [:]
        map.reserveCapacity(lifeStore.workouts.count)
        for s in lifeStore.workouts {
            map[s.id] = MoneyItem.workout(s, bodyWeightKg: w)
        }
        itemCache = map
        regroup(filter, items: map)
        loaded = true
    }

    /// 照篩選分週；篩選的那種已經沒有紀錄（刪光了）、或只剩一種（篩選膠囊收起來了）就回到全部
    /// （不然只剩一種時膠囊不見，「其他有氧」那幾趟被藏起來又按不回「全部」）
    private func regroup(_ f: WorkoutSport?, items: [UUID: MoneyItem]) {
        let all = lifeStore.workouts.sorted { $0.date > $1.date }
        let present = WorkoutListWeek.filterSports.filter { sp in
            all.contains { $0.primarySport == sp }
        }
        var use = f
        if let cur = use, !present.contains(cur) || present.count < 2 { use = nil }
        let shown: [WorkoutSession]
        if let sp = use {
            shown = all.filter { $0.primarySport == sp }
        } else {
            shown = all
        }
        sports = present
        if use != filter { filter = use }
        weeks = WorkoutListWeek.group(shown, items: items, bodyWeightKg: lifeStore.latestBodyWeightKg,
                                      filter: use, now: Date())
    }
}

// MARK: - 資料型別（這一頁自己用）

private enum WorkoutListSheet: Identifiable {
    /// (每次新的 UUID, 那一趟的 id)
    case detail(UUID, UUID)
    case editor(UUID, WorkoutSession)

    var id: UUID {
        switch self {
        case .detail(let key, _): return key
        case .editor(let key, _): return key
        }
    }
}

/// 一列：那一趟＋它的卡（item.id == session.id）
private struct WorkoutListRow: Identifiable {
    let session: WorkoutSession
    let item: MoneyItem
    var id: UUID { item.id }
}

/// 一週一組
private struct WorkoutListWeek: Identifiable {
    /// 那週的週一 00:00
    let start: Date
    /// 「本週・10/12–10/18」「上週・10/5–10/11」「9/28–10/4」
    let title: String
    /// 「4 趟・跑 14.6・走 3.1 公里」／篩選跑步「3 趟・14.6 公里」
    let trailing: String
    let rows: [WorkoutListRow]
    var id: Date { start }

    /// 篩選膠囊的順序（其他有氧只在「全部」）
    static let filterSports: [WorkoutSport] = [.run, .walk, .bike, .hike, .strength]
    /// 組頭右邊寫公里的運動（簡字 跑／走／騎／爬）
    static let kmSports: [WorkoutSport] = [.run, .walk, .bike, .hike]

    /// sessions 已經新到舊排好；items 沒有的（不該發生）當場做
    static func group(_ sessions: [WorkoutSession], items: [UUID: MoneyItem], bodyWeightKg: Double?,
                      filter: WorkoutSport?, now: Date) -> [WorkoutListWeek] {
        var buckets: [Date: [WorkoutSession]] = [:]
        for s in sessions {
            buckets[WorkoutFacts.weekStart(of: s.date), default: []].append(s)
        }
        let thisWeek = WorkoutFacts.weekStart(of: now)
        let lastWeek = WorkoutFacts.calendar.date(byAdding: .day, value: -7, to: thisWeek)
        var out: [WorkoutListWeek] = []
        out.reserveCapacity(buckets.count)
        for start in buckets.keys.sorted(by: >) {
            let list = buckets[start] ?? []
            var rows: [WorkoutListRow] = []
            rows.reserveCapacity(list.count)
            for s in list {
                let item = items[s.id] ?? MoneyItem.workout(s, bodyWeightKg: bodyWeightKg)
                rows.append(WorkoutListRow(session: s, item: item))
            }
            out.append(WorkoutListWeek(start: start,
                                       title: makeTitle(start, thisWeek: thisWeek, lastWeek: lastWeek, now: now),
                                       trailing: makeTrailing(list, filter: filter),
                                       rows: rows))
        }
        return out
    }

    /// 「本週・10/12–10/18」；不是今年的寫年「2025/12/29–1/4」
    static func makeTitle(_ start: Date, thisWeek: Date, lastWeek: Date?, now: Date) -> String {
        let cal = WorkoutFacts.calendar
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let sameYear = cal.component(.year, from: start) == cal.component(.year, from: now)
        let from = sameYear ? WorkoutFormat.monthDay(start) : WorkoutFormat.date(start)
        let range = from + "–" + WorkoutFormat.monthDay(end)
        if cal.isDate(start, inSameDayAs: thisWeek) { return "本週・" + range }
        if let lastWeek, cal.isDate(start, inSameDayAs: lastWeek) { return "上週・" + range }
        return range
    }

    /// 組頭右邊
    static func makeTrailing(_ list: [WorkoutSession], filter: WorkoutSport?) -> String {
        let n = list.count
        if let f = filter {
            if f == .strength { return "\(n) 次" }
            let km = distance(list, sport: f)
            return km >= 0.05 ? "\(n) 趟・" + WorkoutFormat.km(km) : "\(n) 趟"
        }
        var parts: [String] = []
        for sp in kmSports {
            let km = distance(list, sport: sp)
            if km >= 0.05 { parts.append(WorkoutFacts.verb(sp) + " " + WorkoutFormat.kmNumber(km)) }
        }
        let lifts = list.filter { !$0.strengthExercises.isEmpty }.count
        if parts.isEmpty && lifts == n && n > 0 { return "重訓 \(n) 次" }
        var text = "\(n) 趟"
        if !parts.isEmpty { text += "・" + parts.joined(separator: "・") + " 公里" }
        if lifts > 0 { text += "・重訓 \(lifts) 次" }
        return text
    }

    /// 這幾趟裡某種運動的公里（一趟裡只加那種運動的動作；跑、走、騎各算各的）
    static func distance(_ list: [WorkoutSession], sport: WorkoutSport) -> Double {
        var km = 0.0
        for s in list {
            for e in s.exercises where e.kind == .cardio && e.resolvedSport == sport {
                km += max(0, e.distanceKm)
            }
        }
        return km
    }
}

/// 組頭：左「本週・10/12–10/18」（.headline），右「4 趟・跑 14.6・走 3.1 公里」；放不下就上下兩行
private struct WorkoutListWeekHeader: View {
    let title: String
    let trailing: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText
                Spacer(minLength: 6)
                trailingText
            }
            VStack(alignment: .leading, spacing: 2) {
                titleText
                trailingText
            }
        }
        .textCase(nil)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var titleText: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var trailingText: some View {
        Text(trailing)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
