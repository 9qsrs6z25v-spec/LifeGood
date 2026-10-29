import SwiftUI

// MARK: - 美化紀錄（GradeTitleView）[2026-06]
// 美化方向：
//   • 頂部英雄卡（靛藍漸層 indigo→purple），展示部門數 + 職等數 KPI
//   • departmentRow 圖示升級為 44pt LinearGradient 圓 + stroke overlay + shadow
//   • 部門代號 / checkRow 代號 badge 改用 Capsule，padding (.horizontal,7)(.vertical,2.5)
//   • Section header 改用 4pt Capsule side bar（靛藍）
//   • 部門列 & 職等列加入 stagger opacity+Y offset 入場動畫
//   • 部門與職等各自加入空狀態視圖（double-pulse ring）
//   • 職等列改為圓角卡片樣式 HStack
//   • DepartmentEditor checkRow badge → Capsule 升級
//
// [2026-06 v2] 二輪細化：
//   • heroCard：加入頂部玻璃光澤（glass shine）LinearGradient overlay
//   • heroCard：新增第二、第三顆散景裝飾圓（左下角 + 右下角）
//   • sectionHeader：新增 count 數量 Capsule badge，與 App 全局 section 標頭一致
//   • departmentRow code badge：補 Capsule().stroke(color.opacity(0.22)) 描邊
//   • gradeTitleRow 職稱欄：Color(.systemGray6) → Color(.secondarySystemFill) 深色模式修正
//   • gradeTitleRow 兩欄：補 RoundedRectangle().stroke 細描邊
//   • deptEmptyState / gradeTitleEmptyState：主圓升級為 LinearGradient fill + stroke 描邊
//   • DepartmentEditor checkRow code badge：補 Capsule stroke overlay
//
// [2026-07 v3] 本次美化方向（DepartmentEditor 部門編輯器補齊）：
//   • 五個 Form Section（基本資訊／部門功能／上游／下游／同層級）header 從純文字
//     升級為與外層 GradeTitleView.sectionHeader 同款的 Capsule side bar + icon 標頭，
//     上游／下游／同層級三段並加入已選數量 Capsule badge，對齊全 App section 標頭規格
//   • checkRow：選中時標籤字色 .primary／未選 .secondary 加強可讀對比，
//     toggle 加 easeInOut(0.15) 過場動畫，避免選取狀態切換太生硬
//   • 三處重複的「尚無其他部門可選」提示合併為 noCandidatesHint，補上圖示錨點
//   本次僅調整 DepartmentEditor 視覺呈現，未變動任何雙向同步 / 儲存邏輯
//
// [2026-07 v4] 本次美化方向（deptEmptyState / gradeTitleEmptyState 補齊脈衝動畫）：
//   • 兩處空狀態原本雖在 [v1] 紀錄自稱「double-pulse ring」，實際上僅有靜態同心圓描邊，
//     缺少全 App 其餘空狀態（OrganizationView / SubordinateRosterView / IncomeView 等）
//     共用的雙層脈衝呼吸環動畫，補上外層/內層 Circle().stroke + scaleEffect + repeatForever
//     動畫，並各自加入獨立的 deptEmptyPulse / gradeEmptyPulse 旗標與可取消 Task，
//     於 onAppear 延遲 0.3s 觸發、onDisappear 取消並歸零，對齊 OrganizationView.emptyState
//     規格與寫法，避免動畫洩漏。
//   • 本次僅調整這兩處空狀態視覺呈現，未變動任何部門/職等資料模型、儲存或驗證邏輯。
//
// [2026-08 v25.95] 本次美化方向（DepartmentEditor 工具列儲存按鈕補齊載入狀態）：
//   • DepartmentEditor.save() 自帶 isSaving 忙碌守衛（disabled(isSaving)）避免快速連點造成
//     重複部門紀錄，但按鈕本身在存檔期間毫無視覺提示。補上 ProgressView().scaleEffect(0.7)
//     .tint(.green)，isSaving 為 true 時顯示於按鈕左側，對齊 v25.81～v25.94 全 App
//     Add*View／SubordinateView 儲存按鈕載入狀態規格。
//   • 純視覺層調整，save()／syncReverseLinks() 雙向同步等既有商業邏輯完全未變動。
//   （下次美化時：同批清單仍剩 OrganizationView／SubordinateDetailView／MyCalendarView／
//      LifeFinanceView／ResumeView／ChildDetailView 待比照補齊，此清單自 v25.81 起接續，
//      每完成一檔即從清單移除，找不到待辦清單時可全樹搜尋 "isSaving" 交叉核對。）

struct GradeTitleView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showPremiumAlert = false
    @State private var query = ""

    /// 部門依名稱排序（localizedStandardCompare：中文筆劃與「一部/二部/10 部」
    /// 的數字都排得對），再套搜尋。store 內的原始順序不動——只是顯示排序。
    private var displayedDepartments: [Department] {
        let base = lifeStore.departments.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q)
            || $0.code.localizedCaseInsensitiveContains(q)
            || $0.function.localizedCaseInsensitiveContains(q)
        }
    }

    /// 職等依職等文字排序（數字感知：2 排在 10 前面），再套搜尋
    private var displayedGradeTitles: [GradeTitle] {
        let base = lifeStore.gradeTitles.sorted {
            $0.grade.localizedStandardCompare($1.grade) == .orderedAscending
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.grade.localizedCaseInsensitiveContains(q)
            || $0.title.localizedCaseInsensitiveContains(q)
        }
    }
    @State private var editingDepartmentId: UUID?
    @State private var addingDepartment = false
    @State private var heroAppeared = false
    @State private var rowsAppeared = false
    @State private var rowsAppearedTask: Task<Void, Never>?
    // [2026-07 v4] 空狀態脈衝光環動畫旗標，部門/職等各自獨立（對齊 OrganizationView.orgEmptyPulse 規格）
    @State private var deptEmptyPulse = false
    @State private var deptEmptyPulseTask: Task<Void, Never>?
    @State private var gradeEmptyPulse = false
    @State private var gradeEmptyPulseTask: Task<Void, Never>?
    /// [v25.592 轉組織 v1b] 往左滑〔刪除〕：有排好的交接單要調到這個部門時先問（nil＝沒有在問）
    @State private var pendingDeptDelete: DeptDeleteAsk?

    /// [v25.592 轉組織 v1b] 刪部門前要問的那一次（note＝OrgMovePlan.deptDeleteNote）
    private struct DeptDeleteAsk: Equatable {
        let deptId: UUID
        let note: String
    }

    /// [v25.594] 刪職等前要問的那一次（nil＝沒有在問）。以前按紅色減號就直接刪、沒有確認
    @State private var pendingGradeDelete: GradeDeleteAsk?

    private struct GradeDeleteAsk: Equatable {
        let gradeId: UUID
        let label: String
        let note: String
    }

    var body: some View {
        NavigationStack {
            List {
                // ── 英雄卡 ──
                Section {
                    heroCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // ── 部門名稱 ──
                Section {
                    ForEach(Array(displayedDepartments.enumerated()), id: \.element.id) { idx, dept in
                        Button {
                            editingDepartmentId = dept.id
                        } label: {
                            departmentRow(dept)
                                .opacity(rowsAppeared ? 1 : 0)
                                .offset(y: rowsAppeared ? 0 : 12)
                                .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(0.04 * Double(idx)), value: rowsAppeared)
                        }
                        .buttonStyle(.plain)
                        // 改用 allowsFullSwipe: false 的滑出按鈕取代 .onDelete：
                        // 避免整列滑到底直接刪除（與邊緣切頁手勢衝突，同型修正見 v25.154）
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // [v25.592 轉組織 v1b] 有排好的交接單要調到這裡時先問（askDeleteDepartment）；沒有照舊直接刪。
                            // 不用 role: .destructive：有確認框時，帶 destructive 的列一按就先被 List 滑掉，按〔取消〕也回不來
                            //（坑 #12，同 SubordinateView v25.587）；改紅色 tint，按鈕看起來一樣。
                            // （要退回這一件：改回 Button(role: .destructive) { deleteDepartment(dept) }、拿掉 .tint。）
                            Button {
                                askDeleteDepartment(dept)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }

                    if lifeStore.departments.isEmpty {
                        deptEmptyState
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    Button {
                        addingDepartment = true
                    } label: {
                        Label("新增部門", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    sectionHeader("部門名稱", icon: "building.2.fill", color: .indigo, count: lifeStore.departments.count)
                } footer: {
                    Text("點部門進入編輯畫面，可設定部門功能、上下游部門。資料會被「公司組織」頁拿來繪製組織樹。")
                }

                // ── 職等設定 ──
                Section {
                    ForEach(Array(displayedGradeTitles.enumerated()), id: \.element.id) { index, gt in
                        GradeTitleRow(item: gt, onDelete: { askDeleteGrade(gt.id) })
                            .opacity(rowsAppeared ? 1 : 0)
                            .offset(y: rowsAppeared ? 0 : 12)
                            .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(0.04 * Double(index)), value: rowsAppeared)
                    }

                    if lifeStore.gradeTitles.isEmpty {
                        gradeTitleEmptyState
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    Button {
                        lifeStore.add(GradeTitle())
                    } label: {
                        Label("新增職等", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    sectionHeader("職等設定", icon: "list.number", color: .purple, count: lifeStore.gradeTitles.count)
                } footer: {
                    Text("設定公司內部的職等編號與對應職稱，方便管理部屬與職涯記錄。\n"
                         + "右側橘色「×」是績效互評權重：這個職等的人投出的票，基礎分要乘上的倍數"
                         + "（留空＝×1）。例如 32 職等設 ×2，32 職等的人排第一名的同仁就拿雙倍分數。")
                }

                // ── [v25.594] 職等找不到的人（職等被刪掉了）──
                let missing = lifeStore.missingGradeTitles
                if !missing.isEmpty {
                    Section {
                        ForEach(missing) { m in
                            missingGradeRow(m)
                        }
                    } header: {
                        sectionHeader("職等找不到的人", icon: "exclamationmark.triangle.fill", color: .orange,
                                      count: missing.reduce(0) { $0 + $1.names.count })
                    } footer: {
                        Text("這幾位的職等被刪掉了，績效互評會排在「未設職等」。加回同一個職等（職等字一樣）會自動接回去；"
                             + "對不到的，按〔接回…〕選一個職等，部屬卡片、互評排名、評分加總就會回來。")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "搜尋部門、職等或職稱")
            .navigationTitle("部門職等")
            .disabled(!subscription.isPremium)
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onAppear {
                if !subscription.isPremium { showPremiumAlert = true }
                withAnimation(.easeOut(duration: 0.55)) { heroAppeared = true }
                rowsAppearedTask?.cancel()
                rowsAppearedTask = Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    rowsAppeared = true
                }
            }
            .onDisappear {
                rowsAppearedTask?.cancel()
                heroAppeared = false
                rowsAppeared = false
                lifeStore.relinkMissingGradeTitlesNow()   // [v25.594] 職等編輯完離開：加回的職等把原本那幾位接回去
            }
            .sheet(isPresented: $addingDepartment) {
                DepartmentEditor(editingId: nil)
                    .appStores()
            }
            .sheet(item: Binding(
                get: { editingDepartmentId.map { IdentifiableUUID(id: $0) } },
                set: { editingDepartmentId = $0?.id }
            )) { wrapper in
                DepartmentEditor(editingId: wrapper.id)
                    .appStores()
            }
        }
        // [v25.592 轉組織 v1b] 刪部門確認框掛在 NavigationStack 外面（List 上已經有付費說明，同一個 view 不掛兩個 alert）。
        // 要退回這一件：刪這個 .alert、pendingDeptDelete、DeptDeleteAsk、askDeleteDepartment、confirmDeptDelete、deptDeleteShown。
        .alert("確定要刪除這個部門嗎？", isPresented: deptDeleteShown, presenting: pendingDeptDelete) { a in
            Button("刪除", role: .destructive) { confirmDeptDelete(a) }
            Button("取消", role: .cancel) {}
        } message: { a in
            Text(a.note)
        }
        // [v25.594] 刪職等的確認框：掛在背景那一層（同一個 view 已經掛了兩個 alert，不疊在同一層）
        .background {
            Color.clear
                .alert(pendingGradeDelete.map { "確定要刪除職等「\($0.label)」嗎？" } ?? "確定要刪除這個職等嗎？",
                       isPresented: gradeDeleteShown, presenting: pendingGradeDelete) { a in
                    Button("刪除", role: .destructive) { confirmGradeDelete(a) }
                    Button("取消", role: .cancel) {}
                } message: { a in
                    Text(a.note)
                }
        }
    }

    // MARK: - [v25.594] 刪職等先問；職等找不到的人〔接回…〕

    private var gradeDeleteShown: Binding<Bool> {
        Binding(get: { pendingGradeDelete != nil }, set: { if !$0 { pendingGradeDelete = nil } })
    }

    /// 紅色減號：先問。有人在用就寫出幾位、是誰（App 內頁，可以寫名字）
    private func askDeleteGrade(_ id: UUID) {
        guard let g = lifeStore.gradeTitles.first(where: { $0.id == id }) else { return }
        let label = g.displayLabel.isEmpty ? "未命名職等" : g.displayLabel
        let users = lifeStore.gradeTitleUsers(id)
        let note: String
        if users.isEmpty {
            note = "目前沒有人是這個職等。"
        } else {
            let shown = users.prefix(5).joined(separator: "、")
            let more = users.count > 5 ? " 等 \(users.count) 位" : ""
            note = "有 \(users.count) 位是這個職等（\(shown)\(more)）。刪掉後會變成「未設職等」，績效互評會排到「未設職等」那一組。"
                + "之後加回同一個職等（職等字一樣）會自動接回去。"
        }
        pendingGradeDelete = GradeDeleteAsk(gradeId: id, label: label, note: note)
    }

    /// 確認框收起之後（下一個 runloop）才刪
    private func confirmGradeDelete(_ a: GradeDeleteAsk) {
        pendingGradeDelete = nil
        let id = a.gradeId
        DispatchQueue.main.async {
            lifeStore.deleteGradeTitle(id: id)
        }
    }

    private func missingGradeRow(_ m: LifeStore.MissingGradeTitle) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.label.isEmpty ? "已刪除的職等" : "已刪除的職等「\(m.label)」")
                    .font(.subheadline.weight(.semibold))
                Text(m.names.prefix(6).joined(separator: "、") + (m.names.count > 6 ? " 等 \(m.names.count) 位" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Menu {
                if lifeStore.gradeTitles.isEmpty {
                    Text("還沒有職等：先按〔新增職等〕")
                }
                ForEach(displayedGradeTitlesAll) { g in
                    Button(g.displayLabel.isEmpty ? "未命名職等" : g.displayLabel) {
                        lifeStore.relinkGradeTitle(from: m.id, to: g.id)
                    }
                }
                Divider()
                Button("改成未設職等", role: .destructive) {
                    lifeStore.relinkGradeTitle(from: m.id, to: nil)
                }
            } label: {
                Text("接回…")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 2)
    }

    /// 〔接回…〕的選單：全部職等照職等字排（不套搜尋）
    private var displayedGradeTitlesAll: [GradeTitle] {
        lifeStore.gradeTitles.sorted { $0.grade.localizedStandardCompare($1.grade) == .orderedAscending }
    }

    // MARK: - [v25.592 轉組織 v1b] 刪部門前多一句（judge §5-6）

    private var deptDeleteShown: Binding<Bool> {
        Binding(get: { pendingDeptDelete != nil }, set: { if !$0 { pendingDeptDelete = nil } })
    }

    /// 有排好、部門還沒改的交接單要調到這個部門 → 先問「有 1 張排好的交接單要調到這裡（刪掉後，那幾張到生效日會問你要改去哪個部門）」；沒有＝照舊直接刪
    private func askDeleteDepartment(_ dept: Department) {
        if let note = OrgMovePlan.deptDeleteNote(deptId: dept.id, book: lifeStore.orgMoves) {
            pendingDeptDelete = DeptDeleteAsk(deptId: dept.id, note: note)
        } else {
            deleteDepartment(dept)
        }
    }

    /// 確認框收起之後（下一個 runloop）才刪；用 store 裡現在那一筆（問的期間被別台刪了就什麼都不做）
    private func confirmDeptDelete(_ a: DeptDeleteAsk) {
        pendingDeptDelete = nil
        let id = a.deptId
        DispatchQueue.main.async {
            guard let fresh = lifeStore.departments.first(where: { $0.id == id }) else { return }
            deleteDepartment(fresh)
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("部門職等總覽")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("組織架構與職涯層級")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.60))
                }
                Spacer()
            }

            HStack(spacing: 0) {
                HeroKpiCell(label: "部門數", value: "\(lifeStore.departments.count) 個",
                            icon: "building.2.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "職等數", value: "\(lifeStore.gradeTitles.count) 級",
                            icon: "chart.bar.doc.horizontal.fill")
                HeroKpiDivider()
                // syncReverseLinks 會把每條上下游關係雙向寫入兩個部門（A 的 upstream 對應 B 的
                // downstream），直接加總 upstreamIds+downstreamIds 會把每條關係算兩次，故除以 2。
                let connCount = lifeStore.departments.reduce(0) { $0 + $1.upstreamIds.count + $1.downstreamIds.count } / 2
                HeroKpiCell(label: "關聯鏈", value: "\(connCount) 條",
                            icon: "link")
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .heroCardShell(card: .gradeTitle)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(heroAppeared ? 1 : 0)
        .offset(y: heroAppeared ? 0 : -16)
    }


    // MARK: - Section Header

    // [v2] count 數量 Capsule badge，與 App 全局 section 標頭保持一致
    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            // [v2] 數量 badge（與 FinanceOverviewView / OverviewView 一致）
            ZStack {
                Capsule()
                    .fill(color.opacity(0.10))
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                Capsule()
                    .stroke(color.opacity(0.22), lineWidth: 0.75)
            }
            .fixedSize()
        }
    }

    // MARK: - Department Row

    @ViewBuilder
    private func departmentRow(_ dept: Department) -> some View {
        HStack(spacing: 12) {
            // 44pt 漸層圓形圖示
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.indigo.opacity(0.85), Color.purple.opacity(0.70)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    .frame(width: 44, height: 44)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.indigo.opacity(0.25), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !dept.code.isEmpty {
                        // [v2] 補 Capsule stroke 描邊，與 App 全局 badge 一致
                        Text(dept.code)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(Color.indigo.opacity(0.13))
                            .foregroundStyle(.indigo)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.75))
                    }
                    // [v25.520] 部門名稱放不下改跑馬燈（原本折成多行）
                    MarqueeText(dept.name.isEmpty ? "未命名部門" : dept.name)
                        .font(.subheadline.weight(.medium))
                }
                if !dept.function.isEmpty {
                    Text(dept.function)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !dept.upstreamIds.isEmpty || !dept.downstreamIds.isEmpty || !dept.peerIds.isEmpty {
                    HStack(spacing: 6) {
                        if !dept.upstreamIds.isEmpty {
                            Label("上 \(dept.upstreamIds.count)", systemImage: "arrow.up")
                                .font(.caption2).foregroundStyle(.blue)
                        }
                        if !dept.downstreamIds.isEmpty {
                            Label("下 \(dept.downstreamIds.count)", systemImage: "arrow.down")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                        if !dept.peerIds.isEmpty {
                            Label("平 \(dept.peerIds.count)", systemImage: "arrow.left.and.right")
                                .font(.caption2).foregroundStyle(.purple)
                        }
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty States

    private var deptEmptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                // [v4] 外層脈衝光環（對齊 OrganizationView.emptyState 雙層脈衝規格）
                Circle()
                    .stroke(Color.indigo.opacity(deptEmptyPulse ? 0 : 0.22), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                    .scaleEffect(deptEmptyPulse ? 1.38 : 1.0)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: deptEmptyPulse)
                // [v4] 內層脈衝光環（延遲 0.3s，波紋層次）
                Circle()
                    .stroke(Color.indigo.opacity(deptEmptyPulse ? 0 : 0.11), lineWidth: 1)
                    .frame(width: 96, height: 96)
                    .scaleEffect(deptEmptyPulse ? 1.68 : 1.0)
                    .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: deptEmptyPulse)
                // [v2] 主圓升級為 LinearGradient fill + stroke 描邊
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.indigo.opacity(0.14), Color.indigo.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 70, height: 70)
                Circle()
                    .stroke(Color.indigo.opacity(0.35), lineWidth: 1)
                    .frame(width: 70, height: 70)
                Image(systemName: "building.2")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.indigo.opacity(0.55))
            }
            .onAppear {
                deptEmptyPulse = false
                deptEmptyPulseTask?.cancel()
                deptEmptyPulseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    deptEmptyPulse = true
                }
            }
            .onDisappear {
                deptEmptyPulseTask?.cancel()
                deptEmptyPulse = false
            }
            VStack(spacing: 4) {
                Text("尚未建立任何部門")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("點「新增部門」開始規劃組織架構")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var gradeTitleEmptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                // [v4] 外層脈衝光環（對齊 OrganizationView.emptyState 雙層脈衝規格）
                Circle()
                    .stroke(Color.purple.opacity(gradeEmptyPulse ? 0 : 0.22), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                    .scaleEffect(gradeEmptyPulse ? 1.38 : 1.0)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: gradeEmptyPulse)
                // [v4] 內層脈衝光環（延遲 0.3s，波紋層次）
                Circle()
                    .stroke(Color.purple.opacity(gradeEmptyPulse ? 0 : 0.11), lineWidth: 1)
                    .frame(width: 96, height: 96)
                    .scaleEffect(gradeEmptyPulse ? 1.68 : 1.0)
                    .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: gradeEmptyPulse)
                // [v2] 主圓升級為 LinearGradient fill + stroke 描邊
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.purple.opacity(0.14), Color.purple.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 70, height: 70)
                Circle()
                    .stroke(Color.purple.opacity(0.35), lineWidth: 1)
                    .frame(width: 70, height: 70)
                Image(systemName: "list.number")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.purple.opacity(0.55))
            }
            .onAppear {
                gradeEmptyPulse = false
                gradeEmptyPulseTask?.cancel()
                gradeEmptyPulseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    gradeEmptyPulse = true
                }
            }
            .onDisappear {
                gradeEmptyPulseTask?.cancel()
                gradeEmptyPulse = false
            }
            VStack(spacing: 4) {
                Text("尚未設定職等")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("點「新增職等」開始設定職涯層級")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Delete

    private func deleteDepartment(_ dept: Department) {
        // 用 withBatch 包住整個迴圈：刪一個部門若牽動 N 個關聯部門/人員/部屬，
        // 原本會各自觸發 N 次 LifeStore.save()（全量 12 個集合重編碼 + 畫面重繪），
        // 改成迴圈跑完只存檔一次。
        lifeStore.withBatch {
            for var other in lifeStore.departments where other.id != dept.id {
                let removedUp = other.upstreamIds.contains(dept.id)
                let removedDown = other.downstreamIds.contains(dept.id)
                let removedPeer = other.peerIds.contains(dept.id)
                other.upstreamIds.removeAll { $0 == dept.id }
                other.downstreamIds.removeAll { $0 == dept.id }
                other.peerIds.removeAll { $0 == dept.id }
                if removedUp || removedDown || removedPeer { lifeStore.update(other) }
            }
            for var p in lifeStore.orgPeople where p.departmentId == dept.id {
                p.departmentId = nil
                lifeStore.update(p)
            }
            for var sub in lifeStore.subordinates where sub.departmentId == dept.id {
                sub.departmentId = nil
                lifeStore.update(sub)
            }
            lifeStore.deleteDepartment(dept)
        }
    }
}

// MARK: - 職等清單單列

/// 職等/職稱輸入列：本地暫存文字，停止輸入 400ms 後才寫回 lifeStore.gradeTitles。
/// 先前直接把 TextField 綁在 lifeStore.gradeTitles[index] 上，每敲一個字都會讓
/// LifeStore.save()（全量 12 個集合重新編碼寫入 UserDefaults + 排程 CloudKit push）跑一次，
/// 且 @Published 陣列變動會觸發 GradeTitleView 整頁重繪（英雄卡動畫、KPI 一起重算），
/// 快速輸入時明顯閃爍/卡頓；改成本地 @State 草稿 + debounce 才提交。
private struct GradeTitleRow: View {
    @EnvironmentObject var lifeStore: LifeStore
    let itemId: UUID
    /// [v25.594] 紅色減號：交給 GradeTitleView 先問再刪（以前直接刪、沒有確認）
    let onDelete: () -> Void

    @State private var gradeText: String
    @State private var titleText: String
    /// [v25.348] 績效互評權重（這個職等的人投的票要乘幾倍）
    @State private var weightText: String
    @State private var commitTask: Task<Void, Never>?
    /// [v25.594] 這一列有沒有一格正在打字：打完（離開這一列）才試著把刪掉的職等接回來，不在打到一半時接
    @FocusState private var editing: Bool

    init(item: GradeTitle, onDelete: @escaping () -> Void) {
        itemId = item.id
        self.onDelete = onDelete
        _gradeText = State(initialValue: item.grade)
        _titleText = State(initialValue: item.title)
        _weightText = State(initialValue: item.performanceWeight.map {
            $0 == $0.rounded() ? String(format: "%.0f", $0) : String(format: "%.1f", $0)
        } ?? "")
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.10))
                    .frame(width: 56, height: 36)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.purple.opacity(0.20), lineWidth: 0.75)
                    .frame(width: 56, height: 36)
                TextField("職等", text: $gradeText)
                    .focused($editing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                    .multilineTextAlignment(.center)
                    .frame(width: 52)
                    .onChange(of: gradeText) { _, _ in scheduleCommit() }
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 36)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator).opacity(0.40), lineWidth: 0.75)
                    .frame(height: 36)
                TextField("職稱", text: $titleText)
                    .focused($editing)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .onChange(of: titleText) { _, _ in scheduleCommit() }
            }

            // [v25.348] 績效權重：留空＝×1
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.10))
                    .frame(width: 56, height: 36)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.22), lineWidth: 0.75)
                    .frame(width: 56, height: 36)
                HStack(spacing: 1) {
                    Text("×").font(.caption2.weight(.bold)).foregroundStyle(.orange.opacity(0.7))
                    TextField("1", text: $weightText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .keyboardType(.decimalPad)
                        .frame(width: 34)
                        .onChange(of: weightText) { _, _ in scheduleCommit() }
                }
            }

            // [v25.594] 先把打到一半的字存起來（確認框裡的名稱才對），再問要不要刪
            Button {
                commitTask?.cancel()
                commit()
                onDelete()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.80))
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .onChange(of: editing) { _, now in
            guard !now else { return }
            commitTask?.cancel()
            commit()
            lifeStore.relinkMissingGradeTitlesNow()
        }
        .onDisappear {
            commitTask?.cancel()
            commit()
        }
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        guard let idx = lifeStore.gradeTitles.firstIndex(where: { $0.id == itemId }) else { return }
        if lifeStore.gradeTitles[idx].grade != gradeText { lifeStore.gradeTitles[idx].grade = gradeText }
        if lifeStore.gradeTitles[idx].title != titleText { lifeStore.gradeTitles[idx].title = titleText }
        // 空白或 <= 0 一律存 nil（視為 ×1），避免把權重誤設成 0 讓整個職等的票變沒分
        let w = Double(weightText.trimmingCharacters(in: .whitespaces))
        let newWeight: Double? = (w ?? 0) > 0 ? w : nil
        if lifeStore.gradeTitles[idx].performanceWeight != newWeight {
            lifeStore.gradeTitles[idx].performanceWeight = newWeight
        }
    }
}

// MARK: - 部門編輯器

struct DepartmentEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let editingId: UUID?

    @State private var code = ""
    @State private var name = ""
    @State private var function = ""
    @State private var upstreamIds: Set<UUID> = []
    @State private var downstreamIds: Set<UUID> = []
    @State private var peerIds: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var isSaving = false

    private var isEditing: Bool { editingId != nil }

    private var existing: Department? {
        guard let id = editingId else { return nil }
        return lifeStore.departments.first(where: { $0.id == id })
    }

    /// 候選部門 = 其他所有部門
    private var candidates: [Department] {
        lifeStore.departments.filter { $0.id != editingId }
    }

    /// [v25.592 轉組織 v1b] 刪除確認框多一句「有 1 張排好的交接單要調到這裡…」（沒有＝nil）
    private var deleteNote: String? {
        guard let id = editingId else { return nil }
        return OrgMovePlan.deptDeleteNote(deptId: id, book: lifeStore.orgMoves)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("部門代號（例 ENG-01）", text: $code)
                        .autocapitalization(.allCharacters)
                    TextField("部門名稱", text: $name)
                } header: {
                    sectionHeader("基本資訊", icon: "info.circle.fill", color: .indigo)
                }

                Section {
                    TextField("這個部門做什麼？例如：研發新產品、維護線上服務", text: $function, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    sectionHeader("部門功能", icon: "text.alignleft", color: .indigo)
                } footer: {
                    Text("會顯示在公司組織頁的部門卡片上，幫助記住每個部門的職責。")
                }

                Section {
                    if candidates.isEmpty {
                        noCandidatesHint
                    } else {
                        ForEach(candidates) { d in
                            checkRow(
                                isOn: upstreamIds.contains(d.id),
                                label: d.name.isEmpty ? "未命名" : d.name,
                                code: d.code,
                                color: .blue
                            ) {
                                if upstreamIds.contains(d.id) {
                                    upstreamIds.remove(d.id)
                                } else {
                                    upstreamIds.insert(d.id)
                                    downstreamIds.remove(d.id)
                                    peerIds.remove(d.id)
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader("上游部門（向誰回報 / 由誰決策）", icon: "arrow.up.circle.fill", color: .blue, count: upstreamIds.isEmpty ? nil : upstreamIds.count)
                } footer: {
                    Text("勾選後會自動設定對方為「下游部門」，組織圖會以此繪製。")
                }

                Section {
                    if candidates.isEmpty {
                        noCandidatesHint
                    } else {
                        ForEach(candidates) { d in
                            checkRow(
                                isOn: downstreamIds.contains(d.id),
                                label: d.name.isEmpty ? "未命名" : d.name,
                                code: d.code,
                                color: .orange
                            ) {
                                if downstreamIds.contains(d.id) {
                                    downstreamIds.remove(d.id)
                                } else {
                                    downstreamIds.insert(d.id)
                                    upstreamIds.remove(d.id)
                                    peerIds.remove(d.id)
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader("下游部門（誰受我支援 / 由我管轄）", icon: "arrow.down.circle.fill", color: .orange, count: downstreamIds.isEmpty ? nil : downstreamIds.count)
                } footer: {
                    Text("一個部門不能同時是上游又是下游。儲存時會把對方對應的關係雙向同步。")
                }

                Section {
                    if candidates.isEmpty {
                        noCandidatesHint
                    } else {
                        ForEach(candidates) { d in
                            checkRow(
                                isOn: peerIds.contains(d.id),
                                label: d.name.isEmpty ? "未命名" : d.name,
                                code: d.code,
                                color: .purple
                            ) {
                                if peerIds.contains(d.id) {
                                    peerIds.remove(d.id)
                                } else {
                                    peerIds.insert(d.id)
                                    upstreamIds.remove(d.id)
                                    downstreamIds.remove(d.id)
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader("同層級部門（peer / 平行單位）", icon: "arrow.left.arrow.right.circle.fill", color: .purple, count: peerIds.isEmpty ? nil : peerIds.count)
                } footer: {
                    Text("互不上下級的平行部門，組織圖會以紫色虛線連接表示「橫向夥伴」。")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除此部門", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "編輯部門" : "新增部門")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    // [美化 v25.95] 存檔中顯示同色 ProgressView，對齊 SubordinateView v25.94／
                    // FamilyMembersResumeView v25.93／SubordinateEquipmentView v25.92 等
                    // isSaving 忙碌守衛按鈕載入狀態規格。
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(isEditing ? "儲存" : "新增") { save() }
                            .bold().foregroundStyle(.green)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
            }
            .alert("確定要刪除這個部門嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    // [v25.592 轉組織 v1b] 確認框收起之後（下一個 runloop）才刪。要退回這一件：改回 if let e = existing { deleteSelf(e) }; dismiss()
                    let e = existing
                    dismiss()
                    DispatchQueue.main.async {
                        if let e { deleteSelf(e) }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                // [v25.592 轉組織 v1b] 有排好的交接單要調到這裡時多一句（judge §5-6）。要退回這一件：刪這個 message
                if let note = deleteNote {
                    Text(note)
                }
            }
            .onAppear { loadInitial() }
        }
    }

    // MARK: - Section Header（[v3] 對齊 GradeTitleView.sectionHeader：Capsule side bar + icon + 選中數量 badge）

    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int? = nil) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if let count {
                ZStack {
                    Capsule().fill(color.opacity(0.10))
                    Text("已選 \(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                    Capsule().stroke(color.opacity(0.22), lineWidth: 0.75)
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
        .textCase(nil)
    }

    // [v3] 三處「尚無其他部門可選」重複提示合併，補圖示錨點，強化空狀態可辨識度
    private var noCandidatesHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.slash")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("尚無其他部門可選，請先新增部門。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Check Row (badge 升級為 Capsule)

    private func checkRow(isOn: Bool, label: String, code: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? color : .secondary)
                if !code.isEmpty {
                    // [v2] 補 Capsule stroke 描邊，與 departmentRow code badge 一致
                    Text(code)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(color.opacity(0.12))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.75))
                }
                // [v3] 選中時 .primary／未選 .secondary，加強勾選狀態的文字對比
                // [v25.520] 部門名稱放不下改跑馬燈（原本折成多行）
                MarqueeText(label)
                    .foregroundStyle(isOn ? .primary : .secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // [v3] 勾選切換加短促過場動畫，避免圖示/字色瞬間跳變
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }

    // MARK: - Load / Save

    private func loadInitial() {
        guard let e = existing else { return }
        code = e.code
        name = e.name
        function = e.function
        upstreamIds = Set(e.upstreamIds)
        downstreamIds = Set(e.downstreamIds)
        peerIds = Set(e.peerIds)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let id = editingId ?? UUID()
        let dept = Department(
            id: id,
            code: code.trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces),
            function: function.trimmingCharacters(in: .whitespaces),
            upstreamIds: Array(upstreamIds),
            downstreamIds: Array(downstreamIds),
            peerIds: Array(peerIds),
            // ⚠️ 管理人員在部門詳細頁設定、不在這個編輯器裡——重建時必須帶原值，
            //    否則改個部門名稱就把管理人員名單洗掉（vaccinations 同型教訓 v25.220）
            managerIds: existing?.managerIds ?? []
        )
        if isEditing { lifeStore.update(dept) } else { lifeStore.add(dept) }

        // 雙向同步：對方的 upstream/downstream/peer 一併更新
        syncReverseLinks(forDept: dept)
        dismiss()
    }

    private func syncReverseLinks(forDept dept: Department) {
        // withBatch 包住迴圈：N 個關聯部門原本會各自觸發 N 次 save()，改成只存檔一次。
        lifeStore.withBatch {
            for d in lifeStore.departments where d.id != dept.id {
                var changed = d
                // upstream / downstream 對映同步
                let shouldHaveDown = dept.upstreamIds.contains(d.id)
                if shouldHaveDown && !changed.downstreamIds.contains(dept.id) {
                    changed.downstreamIds.append(dept.id)
                } else if !shouldHaveDown && changed.downstreamIds.contains(dept.id) {
                    if !dept.downstreamIds.contains(d.id) {
                        changed.downstreamIds.removeAll { $0 == dept.id }
                    }
                }
                let shouldHaveUp = dept.downstreamIds.contains(d.id)
                if shouldHaveUp && !changed.upstreamIds.contains(dept.id) {
                    changed.upstreamIds.append(dept.id)
                } else if !shouldHaveUp && changed.upstreamIds.contains(dept.id) {
                    if !dept.upstreamIds.contains(d.id) {
                        changed.upstreamIds.removeAll { $0 == dept.id }
                    }
                }
                // peer 對映同步
                let shouldHavePeer = dept.peerIds.contains(d.id)
                if shouldHavePeer && !changed.peerIds.contains(dept.id) {
                    changed.peerIds.append(dept.id)
                } else if !shouldHavePeer && changed.peerIds.contains(dept.id) {
                    changed.peerIds.removeAll { $0 == dept.id }
                }
                // 互斥
                if changed.upstreamIds.contains(dept.id) && changed.downstreamIds.contains(dept.id) {
                    changed.downstreamIds.removeAll { $0 == dept.id }
                }
                if changed.peerIds.contains(dept.id) {
                    changed.upstreamIds.removeAll { $0 == dept.id }
                    changed.downstreamIds.removeAll { $0 == dept.id }
                }
                if changed.upstreamIds != d.upstreamIds
                    || changed.downstreamIds != d.downstreamIds
                    || changed.peerIds != d.peerIds {
                    lifeStore.update(changed)
                }
            }
        }
    }

    private func deleteSelf(_ dept: Department) {
        // withBatch 包住整個迴圈：與 deleteDepartment(_:) 同型修復，避免 N 筆關聯各自觸發 save()。
        lifeStore.withBatch {
            for var other in lifeStore.departments where other.id != dept.id {
                let removedUp = other.upstreamIds.contains(dept.id)
                let removedDown = other.downstreamIds.contains(dept.id)
                let removedPeer = other.peerIds.contains(dept.id)
                other.upstreamIds.removeAll { $0 == dept.id }
                other.downstreamIds.removeAll { $0 == dept.id }
                other.peerIds.removeAll { $0 == dept.id }
                if removedUp || removedDown || removedPeer { lifeStore.update(other) }
            }
            for var p in lifeStore.orgPeople where p.departmentId == dept.id {
                p.departmentId = nil
                lifeStore.update(p)
            }
            for var sub in lifeStore.subordinates where sub.departmentId == dept.id {
                sub.departmentId = nil
                lifeStore.update(sub)
            }
            lifeStore.deleteDepartment(dept)
        }
    }
}

#Preview {
    GradeTitleView()
        .environmentObject(LifeStore())
        .environmentObject(SubscriptionManager.shared)
}
