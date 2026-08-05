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
                    ForEach(Array(lifeStore.departments.enumerated()), id: \.element.id) { idx, dept in
                        Button {
                            editingDepartmentId = dept.id
                        } label: {
                            departmentRow(dept)
                                .opacity(rowsAppeared ? 1 : 0)
                                .offset(y: rowsAppeared ? 0 : 12)
                                .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(0.04 * Double(idx)), value: rowsAppeared)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let snapshot = lifeStore.departments
                        let items = offsets.compactMap { $0 < snapshot.count ? snapshot[$0] : nil }
                        for item in items { deleteDepartment(item) }
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
                    ForEach(Array(lifeStore.gradeTitles.enumerated()), id: \.element.id) { index, gt in
                        GradeTitleRow(item: gt)
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
                    Text("設定公司內部的職等編號與對應職稱，方便管理部屬與職涯記錄。")
                }
            }
            .listStyle(.insetGrouped)
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
            }
            .sheet(isPresented: $addingDepartment) {
                DepartmentEditor(editingId: nil)
            }
            .sheet(item: Binding(
                get: { editingDepartmentId.map { IdentifiableUUID(id: $0) } },
                set: { editingDepartmentId = $0?.id }
            )) { wrapper in
                DepartmentEditor(editingId: wrapper.id)
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color.indigo, Color.purple.opacity(0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // [v2] 玻璃光澤 glass shine overlay（與 App 全局英雄卡一致）
            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top, endPoint: .center
            )

            // 第一顆散景圓（右上）
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 160, height: 160)
                .blur(radius: 30)
                .offset(x: 40, y: -30)

            // [v2] 第二顆散景圓（左下）
            Circle()
                .fill(Color.purple.opacity(0.14))
                .frame(width: 90, height: 90)
                .blur(radius: 22)
                .offset(x: -50, y: 50)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // [v2] 第三顆散景圓（右下，細小）
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 60, height: 60)
                .blur(radius: 14)
                .offset(x: 20, y: 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

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
                    kpiCell(title: "部門數", value: "\(lifeStore.departments.count)", unit: "個")
                    Divider().frame(height: 36).background(.white.opacity(0.25))
                    kpiCell(title: "職等數", value: "\(lifeStore.gradeTitles.count)", unit: "級")
                    Divider().frame(height: 36).background(.white.opacity(0.25))
                    // syncReverseLinks 會把每條上下游關係雙向寫入兩個部門（A 的 upstream 對應 B 的
                    // downstream），直接加總 upstreamIds+downstreamIds 會把每條關係算兩次，故除以 2。
                    let connCount = lifeStore.departments.reduce(0) { $0 + $1.upstreamIds.count + $1.downstreamIds.count } / 2
                    kpiCell(title: "關聯鏈", value: "\(connCount)", unit: "條")
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.indigo.opacity(0.28), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(heroAppeared ? 1 : 0)
        .offset(y: heroAppeared ? 0 : -16)
    }

    private func kpiCell(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.70))
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity)
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
                    Text(dept.name.isEmpty ? "未命名部門" : dept.name)
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

    @State private var gradeText: String
    @State private var titleText: String
    @State private var commitTask: Task<Void, Never>?

    init(item: GradeTitle) {
        itemId = item.id
        _gradeText = State(initialValue: item.grade)
        _titleText = State(initialValue: item.title)
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
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .onChange(of: titleText) { _, _ in scheduleCommit() }
            }

            Button(role: .destructive) {
                commitTask?.cancel()
                lifeStore.gradeTitles.removeAll { $0.id == itemId }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.80))
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
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
                    if let e = existing { deleteSelf(e) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
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
                Text(label)
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
            peerIds: Array(peerIds)
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
