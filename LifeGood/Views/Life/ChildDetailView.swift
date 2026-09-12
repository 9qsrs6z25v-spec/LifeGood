import SwiftUI
import PhotosUI
import MapKit
import Charts

// MARK: - 美化紀錄（ChildDetailView）
// [2026-06 v1] 基礎美化：漸層英雄卡 / matchedGeometryEffect Tab / Capsule 側條段落標題 /
//              30pt 漸層圖示圓 / 彩色膠囊標籤 / 靜態 DateFormatter / contentAppeared 交錯動畫。
// [2026-06 v2] 進階美化（對齊 OverviewView / VariableExpenseView v4 規格）：
//   • headerCard → 玻璃光澤（white.opacity(0.18)→clear，top→center）+ 第三顆散景圓（55pt / blur 8）
//                  + RoundedRectangle stroke(.white.opacity(0.18), 0.75pt)
//                  + 角色 / 年齡 Capsule 加 stroke(.white.opacity(0.28–0.30), 0.6pt)
//   • 圖示圓升至 36pt（dailyRow / recordRow / consumptionRow / childGiftsSection sub）
//     + 新增 Circle stroke(accent.opacity(0.22), 1pt)；icon 字型 12→14pt
//   • 日期改為彩色 Capsule 徽章（accent tint + stroke）對齊 CareerView / SpouseResumeView 規格
//   • consumptionRow 分類 Capsule + stroke(orange.opacity(0.22), 0.6pt)
//   • childGiftsSection sub 圖示從純色 28pt 升至 36pt LinearGradient + stroke
//   • 段落分隔線 leading: 50→56（對齊 36pt 圖示 + 14pt padding + 6pt spacing）
// [2026-07 v3] 金額顯示量級統一：
//   • 私有 formatCurrency(_:) / Self.currencyFormatter 停用（純 NT$ 整數，高額時字串過長）
//     全面改用共用 Double.ntdWanString（FinanceModels.swift），支援萬/億智慧量級，
//     對齊 ResumeGiftSection / CareerView / EInvoiceSetupView 全 App 金額顯示規格。
//     影響範圍：childGiftsSection 合計與各 SocialSubCategory 小計、consumptionSection 合計、
//               consumptionRow 單筆金額。純顯示層變更，未動支出/禮金篩選與加總邏輯。
// [2026-07 v4] 空狀態補 CTA 按鈕：
//   • 新增 emptyRecordRow(accent:action:) 共用元件，dailySection／recordSection 的「尚無記錄」
//     從純文字改為「tray 圖示 + 文字 + 右側迷你新增膠囊按鈕」，按鈕採 accent 漸層底 + 陰影，
//     對齊 FamilyView v3 emptyMembersPlaceholder CTA 規格，縮小適配卡片內單行高度。
//   • consumptionSection 維持純文字空狀態（消費為連動同步、非本頁可手動新增，不適用 CTA）。
// [2026-07 v5] headerCard 三顆膠囊描邊節奏統一：
//   • 生日原本只是「calendar 圖示 + 純文字」、無底色無描邊，與角色/年齡膠囊質感不一致；
//     改為 Capsule 徽章（bg white.opacity(0.12) + stroke white.opacity(0.20), 0.6pt），
//     文字不透明度 0.78→0.85 補償底色後的可讀性，與角色(0.22/0.30)、年齡(0.16/0.25)
//     形成三段漸淡節奏（主要 → 次要 → 輔助資訊）。純視覺層調整，未動生日資料或年齡計算邏輯。
// [2026-07 v6] headerCard 右側大圖示圓補描邊：
//   • 雙層同心圓（86pt / 74pt）原本只有 fill、無 stroke，是卡片內唯一沒有邊框的圖形元素，
//     與同卡 RoundedRectangle 外框（0.18/0.75pt）、角色/年齡/生日三顆膠囊皆已有描邊不一致；
//     外圈補 stroke(.white.opacity(0.16), 0.75pt)、內圈補 stroke(.white.opacity(0.26), 1pt)，
//     對齊 dailyRow/recordRow 36pt 圖示圓已有的 Circle stroke(accent.opacity(0.22), 1pt) 規格節奏。
//   • 純視覺加強，未動任何年齡/生日計算或圖示邏輯。
// [2026-07 v7] 自訂 Tab 切換器補描邊 + 「還有 N 筆」溢出提示對齊全 App 規格：
//   • 自訂 Capsule Tab 切換器背景原本只有 fill(Color(.tertiarySystemFill))、無 stroke，
//     是本頁滾動內容中唯一沒有邊框的容器（headerCard/各 section 卡片皆已有 stroke）；
//     補 Capsule stroke(Color(.separator).opacity(0.15), 0.5pt) 呼應同頁其他容器描邊節奏。
//   • dailySection／consumptionSection 的「還有 N 筆…」原本是左側行內純文字，且標點不一致
//     （「筆...」三個句點 vs 「筆…」全形省略號）；統一改為「…」單字元，並改用水平置中
//     Capsule 膠囊徽章樣式，對齊 ResumeView.spendingSection／ResumeGiftSection／
//     OrganizationView／SpouseResumeView 全 App「還有 N 筆…」統一規格。
//   • 純視覺與標點統一，未動 prefix(20) 截斷邏輯或筆數計算。
// [2026-07 v8] DailyRecordEditorSheet／ChildRecordEditorSheet 編輯表單 Section header 補齊：
//   • 兩個編輯 Sheet（喝奶/食物/睡眠記錄、疫苗/過敏/成長/就醫/教育/興趣/紀念、日期／備註／
//     插入圖片，共 13 處）原本全是系統預設純文字 Section("標題")，是本檔案內唯一還沒套用
//     「4pt 漸層 Capsule 色條 + 圖示 + 粗體標題」規格的區塊，與 HealthProfileEditView.
//     healthEditorSectionHeader／MyCalendarView.editorSectionHeader／ResumeView.
//     profileEditorSectionHeader 等全 App 編輯表單慣例落差明顯。新增檔案層級共用
//     childEditorSectionHeader(_:icon:color:)，圖示沿用 DailyRecordType/ChildRecordType.icon，
//     色彩新增 accent 計算屬性對齊 ChildDetailView.dailyColor／colorFor 同型別同色彩規格
//     （備註類 Section 統一用 .secondary 中性色，對齊 HealthProfileEditView 慣例）。
//     刪除按鈕獨立 Section 維持無標頭（對齊 HealthProfileEditView 各編輯 Sheet 慣例）。
//     純視覺層調整，Section 內欄位、canSave／save()／delete() 等既有商業邏輯完全未變動。
// [2026-08 v9] ChildRecordEditorSheet「過敏資訊」嚴重度選擇器分級著色：
//   • 「嚴重度」原本是系統預設 Picker(.segmented)（純文字選單、輕/中/重三個等級視覺完全相同，
//     需點開才看得出目前選了哪一級），與同檔案 recordRow 過敏嚴重度 Capsule 徽章（早已用
//     severityColor 分級著色）視覺語意脫節，也是 HealthProfileEditView.AllergyEditor v4 已修過、
//     本檔案唯一還沒跟進的同型缺口。新增 severityPicker(selection:) 三色塊按鈕列（選中＝主題色底
//     + 白字 + 陰影／未選中＝淡底 + 主題色字 + 細邊框 + spring 選中動畫），對齊 HealthProfileEditView
//     既有規格。severityColor(_:) 原為 ChildDetailView 內的 private instance method，僅能給同一個
//     struct 呼叫；改為檔案層級 private free function，讓另一個 struct（ChildRecordEditorSheet）
//     也能共用，配色（輕＝黃／中＝橘／重＝紅）維持不變，與 recordRow 徽章色彩語意完全一致。
//     純視覺層調整，draft 儲存、severity 讀寫等既有商業邏輯完全未變動。
// [2026-08 v10] DailyRecordEditorSheet／ChildRecordEditorSheet 工具列儲存按鈕補齊載入狀態：
//   • 兩者 save() 皆自帶 isSaving 忙碌守衛（disabled(!canSave || isSaving)）避免快速連點造成
//     重複育兒記錄／兒女記錄，但按鈕本身在存檔期間毫無視覺提示。補上 HStack { if isSaving {
//     ProgressView().scaleEffect(0.7).tint(.green) }；Button(...) }，對齊 v25.81～v25.102
//     全 App 儲存按鈕載入狀態規格（AddSavingsInsuranceView 起、ResumeView v25.102 止）。
//     純視覺層調整，save()／delete() 內部守衛判斷與相片刪除等既有商業邏輯完全未變動。
//     至此全 App「儲存按鈕載入狀態」補齊清單全數完成。
//   （下次美化本檔案時，可另尋其他仍留有待辦的角落）

struct ChildDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    @State private var addingType: ChildRecordType?
    @State private var editingRecord: ChildRecord?
    // 點列先看詳情卡（編輯移到卡片右上角）
    @State private var viewingRecord: ChildRecord?
    @State private var viewingDaily: DailyRecord?
    @State private var addingDailyType: DailyRecordType?
    @State private var editingDaily: DailyRecord?
    @State private var showPremiumAlert = false

    // 進場動畫旗標
    @State private var headerAppeared = false
    @State private var contentAppeared = false
    // matchedGeometryEffect：tab 切換指示器平滑滑動
    @Namespace private var tabNamespace

    // 靜態 DateFormatter 共用實例（避免每次 render 重新分配）
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f
    }()
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    enum DetailTab: String, CaseIterable {
        case daily = "日常"
        case life = "生涯"
        case vaccine = "疫苗"
    }
    @State private var detailTab: DetailTab = .life
    // 兒女相簿廊：彙整所有記錄附的照片（重用 MapAlbumSheet 模板，依記錄類型分組）
    @State private var showAlbum = false

    init(child: FamilyMember) {
        self.childId = child.id
    }

    /// 相簿項目：所有兒女記錄（成長/紀念時刻/教育…）附的照片，依類型分組、日期排序
    private var childAlbumItems: [AlbumPhotoItem] {
        child.childRecords.compactMap { rec in
            guard let name = rec.photoFileName, let url = rec.photoURL else { return nil }
            return AlbumPhotoItem(id: name, url: url, group: rec.type.rawValue, date: rec.date)
        }
    }

    private var child: FamilyMember {
        lifeStore.familyMembers.first(where: { $0.id == childId })
            ?? FamilyMember(role: .son)
    }

    private var displayName: String {
        if !child.chineseName.isEmpty { return child.chineseName }
        if !child.englishName.isEmpty { return child.englishName }
        return child.role.rawValue
    }

    private var ageString: String {
        guard let bd = child.birthday else { return "" }
        let c = Calendar.current.dateComponents([.year, .month], from: bd, to: Date())
        let y = c.year ?? 0, m = c.month ?? 0
        return y > 0 ? "\(y) 歲 \(m) 個月" : "\(m) 個月"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                headerAppeared = true
                            }
                        }

                    // 自訂 Capsule Tab 切換器（matchedGeometryEffect 讓指示器平滑滑動）
                    HStack(spacing: 0) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                                    detailTab = tab
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tabIcon(tab))
                                        .font(.caption2)
                                    Text(tab.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 9)
                                .foregroundStyle(detailTab == tab ? .white : .secondary)
                                .background {
                                    if detailTab == tab {
                                        Capsule()
                                            .fill(tabTint(tab))
                                            .matchedGeometryEffect(id: "detailTabIndicator", in: tabNamespace)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(.separator).opacity(0.15), lineWidth: 0.5))
                    .padding(.horizontal)

                    switch detailTab {
                    case .daily: dailyContent
                    case .life: lifeContent
                    case .vaccine: vaccineContent
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(displayName) 履歷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAlbum = true
                    } label: {
                        Image(systemName: "photo.stack")
                    }
                }
            }
            .sheet(isPresented: $showAlbum) {
                MapAlbumSheet(
                    title: "\(displayName) 相簿",
                    accent: child.role == .son ? .blue : .pink,
                    emptyTitle: "還沒有照片",
                    emptyHint: "在成長記錄、紀念時刻等記錄附上照片，就會集中顯示在這裡",
                    groupNoun: "類型",
                    items: childAlbumItems
                )
            }
            .sheet(item: $addingType) { type in
                ChildRecordEditorSheet(childId: childId, type: type, editing: nil)
            }
            .sheet(item: $editingRecord) { rec in
                ChildRecordEditorSheet(childId: childId, type: rec.type, editing: rec)
            }
            .sheet(item: $addingDailyType) { type in
                DailyRecordEditorSheet(childId: childId, type: type, editing: nil)
            }
            .sheet(item: $editingDaily) { rec in
                DailyRecordEditorSheet(childId: childId, type: rec.type, editing: rec)
            }
            .sheet(item: $viewingRecord) { rec in
                ChildRecordDetailSheet(childId: childId, record: rec)
            }
            .sheet(item: $viewingDaily) { rec in
                DailyRecordDetailSheet(childId: childId, record: rec)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.12)) {
                    contentAppeared = true
                }
                // 素描功能移除後的善後：一次性清除舊素描伴生檔（旗標守衛、背景執行）
                ChildRecord.purgeLegacySketchFiles()
            }
            .onChange(of: detailTab) { _, _ in
                contentAppeared = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                    contentAppeared = true
                }
            }
        }
    }

    private func tabTint(_ tab: DetailTab) -> Color {
        switch tab {
        case .daily: return .blue
        case .life: return .orange
        case .vaccine: return .teal
        }
    }

    private func tabIcon(_ tab: DetailTab) -> String {
        switch tab {
        case .daily: return "sun.max.fill"
        case .life: return "star.fill"
        case .vaccine: return "syringe"
        }
    }

    // MARK: - 英雄資訊卡（漸層背景 + 散景裝飾圓）

    private var headerCard: some View {
        let isSon = child.role == .son

        return HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                // 角色 + 年齡膠囊
                HStack(spacing: 6) {
                    Text(child.role.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.6))
                    if !ageString.isEmpty {
                        Text(ageString)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(.white.opacity(0.16))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.6))
                    }
                }
                // 姓名
                Text(displayName)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // 生日（calendar 圖示 + 日期文字 → Capsule 徽章，對齊角色/年齡膠囊描邊節奏）
                if let bd = child.birthday {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .medium))
                        Text(Self.dateFormatter.string(from: bd))
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.20), lineWidth: 0.6))
                }
            }
            Spacer()
            // 右側大圖示圓（雙層同心圓製造層次 + 細邊框，對齊 dailyRow/recordRow 36pt 圖示圓
            // 已有的 Circle stroke 規格，避免本卡唯一沒有描邊的圖形元素）
            ZStack {
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 86, height: 86)
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 0.75)
                    .frame(width: 86, height: 86)
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 74, height: 74)
                Circle()
                    .stroke(.white.opacity(0.26), lineWidth: 1)
                    .frame(width: 74, height: 74)
                Image(systemName: "figure.child.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(20)
        // 這張卡依子女性別換色（兒子藍／女兒粉），走 runtimeColors——
        // 使用者若在進階設定指定顏色，那個顏色仍然優先。
        .heroCardShell(card: .childDetail,
                       runtimeColors: isSon ? HeroCard.childSonGradient
                                            : HeroCard.childDaughterGradient)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18), lineWidth: 0.75))
        .padding(.horizontal)
    }

    // MARK: - 日常頁面（含交錯進場動畫）

    @ViewBuilder
    private var dailyContent: some View {
        // childGifts（雙重 filter + sort 全支出）一次捕捉後共用，
        // 避免 isEmpty 判斷與 childGiftsSection 內部各自再算一次（原本 2 次 → 1 次）
        let gifts = childGifts
        // 日常趨勢圖表：喝奶/食物/睡眠/身高/體重五張折線圖左右滑動切換，點線上資料點顯示細節
        DailyChartsPager(
            records: child.dailyRecords,
            childRecords: child.childRecords
        )
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 14)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: contentAppeared)
        ForEach(Array(DailyRecordType.allCases.enumerated()), id: \.element) { idx, type in
            dailySection(type)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82)
                        .delay(0.05 * Double(idx)),
                    value: contentAppeared
                )
        }
        // 消費（依本人名字連動到變動支出）
        consumptionSection
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 14)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.82)
                    .delay(0.05 * Double(DailyRecordType.allCases.count)),
                value: contentAppeared
            )
        // 收到的禮金（依本人名字連動到 .social 變動支出收受人）
        if !gifts.isEmpty {
            childGiftsSection(gifts)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82)
                        .delay(0.05 * Double(DailyRecordType.allCases.count + 1)),
                    value: contentAppeared
                )
        }
    }

    /// 變動支出 .social 中將兒女列為收受人的紀錄
    private var childGifts: [Expense] {
        let target = child.chineseName
        guard !target.isEmpty else { return [] }
        return expenseStore.expenses
            .filter { $0.expenseType == .variable && $0.variableCategory == .social }
            .filter { e in
                guard let raw = e.socialRecipient, !raw.isEmpty else { return false }
                let names = raw.components(separatedBy: CharacterSet(charactersIn: ",、，"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                return names.contains(target)
            }
            .sorted { $0.date > $1.date }
    }

    private func childGiftsSection(_ gifts: [Expense]) -> some View {
        let total = gifts.reduce(0) { $0 + $1.amount }
        // 依社交子分類一次分桶（O(n)），取代原本 ForEach 內對 gifts 逐分類各 filter 一次（O(分類數 × n)），
        // 對齊 FamilyMembersResumeView.memberGiftsSection 同型修復；無子分類的項目不歸類到任何分類列
        var grouped: [SocialSubCategory: [Expense]] = [:]
        for e in gifts {
            if let sub = e.socialSubCategory {
                grouped[sub, default: []].append(e)
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 漸層側條 + 計數膠囊 + 合計
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.pink, Color.pink.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: "gift.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.pink)
                Text("收到的禮金")
                    .font(.subheadline.weight(.semibold))
                Text("\(gifts.count) 筆")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Color.pink.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.pink.opacity(0.22), lineWidth: 0.6))
                Spacer()
                Text(total.ntdWanString)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.pink)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(SocialSubCategory.allCases) { sub in
                let items = grouped[sub] ?? []
                if !items.isEmpty {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.pink.opacity(0.22), Color.pink.opacity(0.09)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(Color.pink.opacity(0.22), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: sub.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.pink)
                        }
                        Text(sub.rawValue).font(.subheadline)
                        Spacer()
                        Text("\(items.count) 筆")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(items.reduce(0) { $0 + $1.amount }.ntdWanString)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.pink)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    Rectangle()
                        .fill(Color(.separator).opacity(0.20))
                        .frame(height: 0.5)
                        .padding(.leading, 56)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.pink.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }


    private func dailySection(_ type: DailyRecordType) -> some View {
        let accent = dailyColor(type)
        let items = child.dailyRecords.filter { $0.type == type }.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 側條 + 彩色圖示 + 標題 + 計數膠囊 + 新增按鈕
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(type.rawValue)
                    .font(.subheadline.weight(.semibold))
                if !items.isEmpty {
                    Text("\(items.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                Button {
                    if subscription.isPremium { addingDailyType = type }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if items.isEmpty {
                emptyRecordRow(accent: accent) {
                    if subscription.isPremium { addingDailyType = type }
                    else { showPremiumAlert = true }
                }
            } else {
                ForEach(Array(items.prefix(20).enumerated()), id: \.element.id) { idx, rec in
                    Button {
                        viewingDaily = rec
                    } label: {
                        dailyRow(rec)
                    }
                    .buttonStyle(.plain)
                    if idx < min(items.count, 20) - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5)
                            .padding(.leading, 56)
                    }
                }
                if items.count > 20 {
                    overflowCountBadge(items.count - 20)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func dailyRow(_ rec: DailyRecord) -> some View {
        let accent = dailyColor(rec.type)
        return HStack(spacing: 12) {
            // 36pt 漸層圖示圓 + stroke（v2 升級，對齊 VariableExpenseView ExpenseRow 規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Circle()
                    .stroke(accent.opacity(0.22), lineWidth: 1)
                    .frame(width: 36, height: 36)
                Image(systemName: rec.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                switch rec.type {
                case .milk:
                    HStack(spacing: 6) {
                        if let brand = rec.milkBrand, !brand.isEmpty {
                            Text(brand).font(.subheadline.weight(.medium))
                        }
                        if let ml = rec.mlAmount, ml > 0 {
                            // ml 數值改為彩色膠囊標籤
                            Text("\(Int(ml)) ml")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent)
                                .clipShape(Capsule())
                        }
                    }
                case .food:
                    HStack(spacing: 6) {
                        if let name = rec.foodName, !name.isEmpty {
                            Text(name).font(.subheadline.weight(.medium))
                        }
                        if let ml = rec.mlAmount, ml > 0 {
                            Text("\(Int(ml)) ml")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent)
                                .clipShape(Capsule())
                        }
                    }
                case .sleep:
                    if let end = rec.sleepEnd {
                        let dur = end.timeIntervalSince(rec.date) / 3600
                        Text(String(format: "%@ ~ %@（%.1f 小時）",
                                    Self.timeFormatter.string(from: rec.date),
                                    Self.timeFormatter.string(from: end),
                                    dur))
                            .font(.subheadline.weight(.medium))
                    } else {
                        Text(Self.timeFormatter.string(from: rec.date))
                            .font(.subheadline.weight(.medium))
                    }
                }
                Text(Self.dateTimeFormatter.string(from: rec.date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent.opacity(0.72))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.08))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func dailyColor(_ type: DailyRecordType) -> Color {
        switch type {
        case .milk: return .blue
        case .food: return .green
        case .sleep: return .indigo
        }
    }

    // MARK: - 消費（與兒女連動的變動支出）

    private var consumptionExpenses: [Expense] {
        let name = child.chineseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return [] }
        return expenseStore.expenses
            .filter { $0.expenseType == .variable }
            .filter { e in
                guard let raw = e.diningMember, !raw.isEmpty else { return false }
                let names = raw.split(separator: "、").map { String($0).trimmingCharacters(in: .whitespaces) }
                return names.contains(name)
            }
            .sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var consumptionSection: some View {
        // consumptionExpenses（雙重 filter + sort，O(n log n)）一次捕捉後全段共用，
        // 避免 section 內 count / isEmpty / reduce / prefix 各自觸發重複計算（原本 8 次 → 1 次）
        let exps = consumptionExpenses
        VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 漸層側條 + 計數膠囊 + 合計
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                Text("消費")
                    .font(.subheadline.weight(.semibold))
                if exps.count > 0 {
                    Text("\(exps.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.red.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                if !exps.isEmpty {
                    let total = exps.reduce(0) { $0 + $1.amount }
                    Text(total.ntdWanString)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if exps.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(child.chineseName.isEmpty
                         ? "尚未設定姓名，請先填寫中文名字"
                         : "尚無連動的消費紀錄")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            } else {
                ForEach(Array(exps.prefix(20).enumerated()), id: \.element.id) { idx, e in
                    consumptionRow(e)
                    if idx < min(exps.count, 20) - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5)
                            .padding(.leading, 56)
                    }
                }
                if exps.count > 20 {
                    overflowCountBadge(exps.count - 20)
                }
            }
            if !child.chineseName.isEmpty {
                Rectangle()
                    .fill(Color(.separator).opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
                Text("變動支出中將「\(child.chineseName)」加入人員會自動同步到此")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func consumptionRow(_ e: Expense) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 36pt 漸層圖示圓 + stroke（v2 升級）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Circle()
                    .stroke(Color.orange.opacity(0.22), lineWidth: 1)
                    .frame(width: 36, height: 36)
                Image(systemName: e.variableCategory?.icon ?? "questionmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title.isEmpty ? (e.variableCategory?.rawValue ?? "未分類") : e.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Self.shortDateFormatter.string(from: e.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                    if let cat = e.variableCategory {
                        Text(cat.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.6))
                    }
                    if let raw = e.diningMember, !raw.isEmpty {
                        Text(raw).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            Text(e.amount.ntdWanString)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - 生涯頁面

    @ViewBuilder
    private var lifeContent: some View {
        // 疫苗已獨立成第三個分頁（vaccineContent），生涯頁不再內嵌接種時程
        ForEach(Array(ChildRecordType.allCases.filter { $0 != .vaccination }.enumerated()), id: \.element) { idx, type in
            recordSection(type)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82)
                        .delay(0.05 * Double(idx)),
                    value: contentAppeared
                )
        }
    }

    // MARK: - 疫苗頁面（接種時程規劃獨立分頁）

    @ViewBuilder
    private var vaccineContent: some View {
        // 依生日列出所有應施打疫苗，填入施打日期即完成，逾期自動標示
        ChildVaccineScheduleView(childId: childId)
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 14)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: contentAppeared)
    }

    // MARK: - 章節（生涯）

    private func recordSection(_ type: ChildRecordType) -> some View {
        let accent = colorFor(type)
        let items = child.childRecords.filter { $0.type == type }.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 漸層側條 + 彩色圖示 + 標題 + 計數膠囊 + 新增按鈕
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(type.rawValue)
                    .font(.subheadline.weight(.semibold))
                if !items.isEmpty {
                    Text("\(items.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                Button {
                    if subscription.isPremium { addingType = type }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if items.isEmpty {
                emptyRecordRow(accent: accent) {
                    if subscription.isPremium { addingType = type }
                    else { showPremiumAlert = true }
                }
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, rec in
                    recordRow(rec)
                    if idx < items.count - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5)
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func recordRow(_ rec: ChildRecord) -> some View {
        let accent = colorFor(rec.type)
        Button {
            // 點列先開詳情卡（免訂閱可看），編輯移到詳情卡右上角（該處才做訂閱守衛）
            viewingRecord = rec
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // 36pt 漸層圖示圓 + stroke（v2 升級）
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Circle()
                        .stroke(accent.opacity(0.22), lineWidth: 1)
                        .frame(width: 36, height: 36)
                    Image(systemName: rec.type.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(primaryText(rec)).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        if rec.type == .allergy, let sev = rec.severity {
                            // Capsule 標籤（對齊 ChildrenResumeView 規格，取代 RoundedRectangle(cornerRadius:3)）
                            Text(sev.rawValue).font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(severityColor(sev).opacity(0.15))
                                .foregroundStyle(severityColor(sev))
                                .clipShape(Capsule())
                        }
                        if rec.type == .vaccination, let dose = rec.dose, !dose.isEmpty {
                            Text(dose).font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12)).foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        // 就醫體溫膠囊：≥38°C 發燒紅、其餘橙，一眼看出當次是否發燒
                        if rec.type == .medical, let t = rec.temperatureC, t > 0 {
                            Text(String(format: "%.1f°C", t)).font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background((t >= 38 ? Color.red : Color.orange).opacity(0.12))
                                .foregroundStyle(t >= 38 ? Color.red : Color.orange)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    if rec.type == .growth {
                        HStack(spacing: 8) {
                            if let h = rec.heightCm, h > 0 { Text(String(format: "身高 %.1f cm", h)).font(.caption).foregroundStyle(.secondary) }
                            if let w = rec.weightKg, w > 0 { Text(String(format: "體重 %.1f kg", w)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    HStack(spacing: 6) {
                        Text(Self.dateFormatter.string(from: rec.date))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent.opacity(0.80))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accent.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.20), lineWidth: 0.5))
                        if !rec.detail.isEmpty {
                            Text(rec.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }

                // 照片放在 row 右側，依原比例顯示（最大 80×80）
                if rec.photoFileName != nil, let url = rec.photoURL {
                    // 用既有的 AsyncLocalImage 背景讀檔快取，避免清單捲動／其他列狀態
                    // 變化造成整個 body 重新求值時，同步在主執行緒重讀＋重解碼每一列的照片。
                    AsyncLocalImage(url: url) { img, _ in
                        if let img {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 80, maxHeight: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primaryText(_ rec: ChildRecord) -> String {
        rec.type == .growth ? Self.dateFormatter.string(from: rec.date) : (rec.title.isEmpty ? rec.type.rawValue : rec.title)
    }

    private func colorFor(_ type: ChildRecordType) -> Color {
        switch type {
        case .vaccination: return .blue; case .allergy: return .red; case .growth: return .green
        case .medical: return .orange; case .education: return .purple
        case .hobby: return .pink; case .memorable: return .yellow
        }
    }

    // MARK: - 章節空狀態（tray 圖示 + 文字 + 迷你 CTA 按鈕）
    // [2026-07 v4] 對齊 FamilyView v3 emptyMembersPlaceholder 的漸層膠囊 CTA 規格（accent 漸層底 + 陰影），
    // 縮小成適合卡片內單行使用的尺寸，取代原本純文字「尚無記錄」；dailySection / recordSection 共用。
    // consumptionSection 空狀態不適用（消費為連動同步、非本頁可手動新增，維持純文字）。
    private func emptyRecordRow(accent: Color, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("尚無記錄")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("新增")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: accent.opacity(0.30), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    // MARK: - 「還有 N 筆…」溢出提示（水平置中 Capsule 膠囊徽章）
    // [2026-07 v7] 對齊 ResumeView.spendingSection／ResumeGiftSection／OrganizationView／
    // SpouseResumeView 全 App「還有 N 筆…」統一規格；dailySection／consumptionSection 共用。
    private func overflowCountBadge(_ count: Int) -> some View {
        HStack {
            Spacer()
            Text("還有 \(count) 筆…")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 3.5)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

}

/// 子編輯 Sheet 共用 Section header：4pt 漸層 Capsule 色條 + 圖示 + 粗體標題，
/// 對齊 HealthProfileEditView.healthEditorSectionHeader／MyCalendarView.editorSectionHeader 規格；
/// DailyRecordEditorSheet／ChildRecordEditorSheet 共用。
@ViewBuilder
private func childEditorSectionHeader(_ title: String, icon: String, color: Color) -> some View {
    HStack(spacing: 7) {
        Capsule()
            .fill(LinearGradient(colors: [color, color.opacity(0.70)], startPoint: .top, endPoint: .bottom))
            .frame(width: 4, height: 18)
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

/// 過敏嚴重度對應色：輕度＝黃／中度＝橘／重度＝紅，沿用本檔案原本 recordRow 嚴重度 Capsule
/// 徽章配色（見 v9 美化紀錄），ChildRecordEditorSheet 的分級選擇器改用同一份，兩處色彩語意統一。
/// 原為 ChildDetailView 內的 private instance method，改為檔案層級 free function 以便
/// ChildRecordEditorSheet（另一個 struct）也能呼叫。
private func severityColor(_ s: AllergySeverity) -> Color {
    switch s { case .mild: return .yellow; case .moderate: return .orange; case .severe: return .red }
}

/// 過敏嚴重度分級選擇器：三色塊按鈕列（選中＝主題色底 + 白字 + 陰影／未選中＝淡底 + 主題色字 + 細邊框），
/// 對齊 HealthProfileEditView.AllergyEditor 既有規格，取代系統預設 Picker(.segmented)（純文字、三個等級
/// 視覺完全相同，不點開看不出目前選了哪一級）。ChildRecordEditorSheet 專用。
private func severityPicker(selection: Binding<AllergySeverity>) -> some View {
    HStack(spacing: 8) {
        ForEach(AllergySeverity.allCases) { s in
            let isSelected = selection.wrappedValue == s
            let tint = severityColor(s)
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                    selection.wrappedValue = s
                }
            } label: {
                Text(s.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(isSelected ? .white : tint)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? tint : tint.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tint.opacity(isSelected ? 0 : 0.28), lineWidth: 0.75)
                    )
                    .shadow(color: isSelected ? tint.opacity(0.35) : .clear, radius: 5, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.vertical, 2)
}

// MARK: - 日常記錄編輯 Sheet

struct DailyRecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let type: DailyRecordType
    var editing: DailyRecord?

    @State private var date = Date()
    @State private var milkBrand = ""
    @State private var mlText = ""
    @State private var foodName = ""
    @State private var sleepEnd = Date()
    @State private var note = ""
    @State private var isSaving = false

    private var canSave: Bool {
        switch type {
        case .milk: return (Double(mlText) ?? 0) > 0
        case .food: return !foodName.trimmingCharacters(in: .whitespaces).isEmpty
        case .sleep: return true
        }
    }

    /// 用過的奶粉品牌（快速選取膠囊模板選項）
    private var previousBrands: [String] {
        guard let member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { return [] }
        return QuickPickOptions.recent(
            member.dailyRecords.filter { $0.type == .milk }.map { (value: $0.milkBrand, date: $0.date) }
        )
    }

    /// 吃過的食物名稱（快速選取膠囊模板選項）
    private var previousFoods: [String] {
        guard let member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { return [] }
        return QuickPickOptions.recent(
            member.dailyRecords.filter { $0.type == .food }.map { (value: $0.foodName, date: $0.date) }
        )
    }

    // 對齊 ChildDetailView.dailyColor 規格，讓編輯表單 Section header 與清單列圖示圓同色
    private var accent: Color {
        switch type {
        case .milk: return .blue
        case .food: return .green
        case .sleep: return .indigo
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch type {
                case .milk:
                    Section {
                        HStack { Text("時間"); Spacer(); FiveMinuteDateTimePicker(selection: $date).fixedSize() }
                        TextField("奶粉品牌（選填）", text: $milkBrand)
                        // 快速選取膠囊模板：用過的品牌，點一下帶入
                        QuickPickCapsuleRow(options: previousBrands, selection: $milkBrand, accent: .blue)
                        HStack { TextField("ml 數", text: $mlText).keyboardType(.numberPad); Text("ml").foregroundStyle(.secondary) }
                    } header: {
                        childEditorSectionHeader("喝奶記錄", icon: type.icon, color: accent)
                    }
                case .food:
                    Section {
                        HStack { Text("時間"); Spacer(); FiveMinuteDateTimePicker(selection: $date).fixedSize() }
                        TextField("食物名稱", text: $foodName)
                        // 快速選取膠囊模板：吃過的食物，點一下帶入
                        QuickPickCapsuleRow(options: previousFoods, selection: $foodName, accent: .green)
                        HStack { TextField("ml 數（選填）", text: $mlText).keyboardType(.numberPad); Text("ml").foregroundStyle(.secondary) }
                    } header: {
                        childEditorSectionHeader("食物記錄", icon: type.icon, color: accent)
                    }
                case .sleep:
                    Section {
                        HStack { Text("入睡時間"); Spacer(); FiveMinuteDateTimePicker(selection: $date).fixedSize() }
                        HStack { Text("起床時間"); Spacer(); FiveMinuteDateTimePicker(selection: $sleepEnd, minimumDate: date).fixedSize() }
                        if sleepEnd > date {
                            let hours = sleepEnd.timeIntervalSince(date) / 3600
                            HStack {
                                Text("睡眠時長").foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f 小時", hours)).foregroundStyle(.blue)
                            }
                        }
                    } header: {
                        childEditorSectionHeader("睡眠記錄", icon: type.icon, color: accent)
                    }
                }
                Section {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2)
                } header: {
                    childEditorSectionHeader("備註", icon: "text.bubble.fill", color: .secondary)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: { Label("刪除", systemImage: "trash") }
                            .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯\(type.rawValue)" : "新增\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    // v10 美化：isSaving 忙碌守衛補齊載入視覺，對齊全 App 儲存按鈕載入狀態規格。
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(editing != nil ? "儲存" : "新增") { save() }
                            .bold().foregroundStyle(.green).disabled(!canSave || isSaving)
                    }
                }
            }
            .onAppear { loadEditing() }
        }
    }

    private func loadEditing() {
        guard let e = editing else {
            // 新育兒記錄屬「即時紀錄」：預設用當下時間對齊到 5 分鐘，不套排程 09:30 規則
            date = FiveMinuteDateTimePicker.roundedToFiveMinutes(Date())
            sleepEnd = date
            return
        }
        date = e.date
        milkBrand = e.milkBrand ?? ""
        mlText = e.mlAmount.map { $0 > 0 ? String(format: "%.0f", $0) : "" } ?? ""
        foodName = e.foodName ?? ""
        sleepEnd = e.sleepEnd ?? Date()
        note = e.note
    }

    private func save() {
        guard !isSaving else { return }
        guard var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        isSaving = true
        let rec = DailyRecord(
            id: editing?.id ?? UUID(), type: type, date: date,
            milkBrand: type == .milk ? milkBrand.trimmingCharacters(in: .whitespaces) : nil,
            mlAmount: (type == .milk || type == .food) ? Double(mlText) : nil,
            foodName: type == .food ? foodName.trimmingCharacters(in: .whitespaces) : nil,
            sleepEnd: type == .sleep ? sleepEnd : nil,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = member.dailyRecords.firstIndex(where: { $0.id == rec.id }) {
            member.dailyRecords[idx] = rec
        } else {
            member.dailyRecords.append(rec)
        }
        lifeStore.update(member)
        dismiss()
    }

    private func delete() {
        guard !isSaving else { return }
        guard let e = editing, var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        isSaving = true
        member.dailyRecords.removeAll { $0.id == e.id }
        lifeStore.update(member)
        dismiss()
    }
}

// MARK: - 兒女記錄編輯 Sheet

struct ChildRecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let type: ChildRecordType
    var editing: ChildRecord?

    @State private var title = ""
    @State private var detail = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var tempText = ""   // 就醫體溫（°C，選填）
    @State private var dose = ""
    @State private var severity: AllergySeverity = .mild

    // 就醫 / 接種院所 自動完成
    @StateObject private var clinicCompleter = RestaurantSearchCompleter()
    @StateObject private var locationProvider = LocationProvider.shared
    @FocusState private var detailFieldFocused: Bool
    @State private var clinicSuppressNextUpdate: Bool = false
    @State private var clinicExpandedSuggestions: Bool = false
    @State private var clinicDebounceTask: Task<Void, Never>? = nil
    // 過往就醫紀錄的本地比對也要跟 Apple Maps 搜尋走同一組 300ms 防抖後的字串，
    // 避免打字時本地建議先跳、0.3 秒後網路建議才到造成清單重排兩次的閃爍感。
    @State private var clinicDebouncedQuery: String = ""
    @State private var photoFileName: String?
    @State private var photoItem: PhotosPickerItem?
    // 拍照（相機必須用 fullScreenCover：sheet 卡片式呈現會讓快門列被裁切，見 v25.128 修復）
    @State private var showCamera = false
    @State private var previewImage: UIImage?
    /// 進入編輯畫面時的原始照片檔名，用來判斷儲存/取消時該刪哪個檔案（見 save()/取消按鈕註解）。
    @State private var originalPhotoFileName: String?
    // 選取照片是非同步的（iCloud 圖片可能要等幾秒），若使用者在等待期間又重新選了一次，
    // 較慢完成的前一次選取不該覆蓋較新的結果；用世代編號判斷完成時是否仍是最新一次選取
    // （同型修復見 OrgPersonEditor.photoLoadGeneration）。
    @State private var photoLoadGeneration = 0
    @State private var isSaving = false

    private var canSave: Bool {
        switch type {
        case .growth: return (Double(heightText) ?? 0) > 0 || (Double(weightText) ?? 0) > 0
        default: return !title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    // 對齊 ChildDetailView.colorFor 規格，讓編輯表單 Section header 與清單列圖示圓同色
    private var accent: Color {
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

    var body: some View {
        NavigationStack {
            Form {
                switch type {
                case .vaccination: vaccinationFields
                case .allergy: allergyFields
                case .growth: growthFields
                case .medical: medicalFields
                case .education: educationFields
                case .hobby: hobbyFields
                case .memorable: memorableFields
                }
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                } header: {
                    childEditorSectionHeader("日期", icon: "calendar", color: accent)
                }
                Section {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...5)
                } header: {
                    childEditorSectionHeader("備註", icon: "text.bubble.fill", color: .secondary)
                }

                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo")
                            Text(photoFileName == nil ? "選擇圖片" : "更換圖片")
                            Spacer()
                            if photoFileName != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }

                    // 拍照：與相簿選取共用 storePickedPhoto 匯入管線（壓縮存檔＋世代守衛）
                    Button {
                        showCamera = true
                    } label: {
                        HStack {
                            Image(systemName: "camera")
                            Text("拍照")
                            Spacer()
                        }
                    }

                    if let img = previewImage {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if photoFileName != nil {
                        Button(role: .destructive) {
                            // 讓任何仍在進行中的照片載入 Task 過期，避免它稍後才完成、
                            // 把剛移除的照片又重新蓋回來。
                            photoLoadGeneration += 1
                            // 不在這裡立刻刪檔：使用者移除圖片後若按「取消」，原圖應該保持不變
                            // （取消不該有副作用）。實際刪除延到 save() 依最終結果判斷。
                            // 但若移除的是本次 session 剛選的新照片（尚未儲存），要立刻清掉，
                            // 否則變成孤兒檔案。
                            if let name = photoFileName, name != originalPhotoFileName {
                                ChildRecord.deletePhoto(name)
                            }
                            photoFileName = nil; previewImage = nil
                        } label: {
                            Label("移除圖片", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    childEditorSectionHeader("插入圖片", icon: "photo.fill", color: accent)
                }

                if editing != nil {
                    Section { Button(role: .destructive) { delete() } label: { Label("刪除此記錄", systemImage: "trash") }.disabled(isSaving) }
                }
            }
            .navigationTitle(editing != nil ? "編輯\(type.rawValue)" : "新增\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        // 選了新照片但按取消：新照片檔案已寫入磁碟卻不會被任何紀錄引用，
                        // 要在這裡清掉，避免變成永久孤兒檔案（同型修復見 RenovationPhotoEditor.cancel()）。
                        // 原本的照片（originalPhotoFileName）維持不動，因為 onChange 已改為不再
                        // 立刻刪除舊檔，取消時原檔仍完整保留。
                        if let current = photoFileName, current != originalPhotoFileName {
                            ChildRecord.deletePhoto(current)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // v10 美化：isSaving 忙碌守衛補齊載入視覺，對齊全 App 儲存按鈕載入狀態規格。
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(editing != nil ? "儲存" : "新增") { save() }.bold().foregroundStyle(.green).disabled(!canSave || isSaving)
                    }
                }
            }
            .onAppear { loadEditing() }
            .onChange(of: photoItem) { _, newItem in
                // 連續選兩張照片（例如第一張是要等 iCloud 下載的慢速圖，選完又反悔重選）
                // 會有兩個 Task 並行跑 loadTransferable，先前沒有世代編號守衛時，較慢完成的
                // 那個會用「self.photoItem」重新讀到的已是新選取，導致兩個 Task 存的其實是
                // 同一張新照片，且哪個後寫入 photoFileName 全憑完成順序決定，較早選的舊照片
                // 反而可能覆蓋較新的選擇。改用世代編號，只有仍是最新一次選取的 Task 才套用結果。
                photoLoadGeneration += 1
                let generation = photoLoadGeneration
                Task {
                    guard let newItem, let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                    await storePickedPhoto(data: data, generation: generation)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    guard let data = image.jpegData(compressionQuality: 0.9) else { return }
                    photoLoadGeneration += 1
                    let generation = photoLoadGeneration
                    Task { await storePickedPhoto(data: data, generation: generation) }
                }
                .ignoresSafeArea()
            }
            // 避免 300ms 防抖期間關閉表單後，Task 仍在背景驅動診所搜尋（對齊 AddExpenseView 的修復）
            .onDisappear { clinicDebounceTask?.cancel() }
        }
    }

    /// 相簿選取與拍照共用的照片匯入管線：
    /// 編輯既有記錄時 editing.id 不變，若沿用它當檔名，換照片會同路徑覆寫、photoFileName
    /// 字串不變，清單縮圖用的 AsyncLocalImage 依 url 判斷是否重讀，url 沒變就不會重讀，
    /// 換照片後清單頭像停留在舊圖（同類 bug 已在 BusinessCard/OrgPerson/FamilyAlbumPhoto
    /// 修復，改用全新 UUID 檔名）。
    private func storePickedPhoto(data: Data, generation: Int) async {
        let photoId = UUID()
        let savedName = ChildRecord.savePhoto(data, id: photoId)
        let origImage = UIImage(data: data)
        await MainActor.run {
            guard generation == photoLoadGeneration else {
                // 已被更新的選取取代：這次白存的照片檔沒有任何欄位會再引用到，
                // 立刻清掉避免孤兒檔案；不動任何已顯示的狀態。
                if let savedName { ChildRecord.deletePhoto(savedName) }
                return
            }
            // 換照片時不立刻刪舊檔：使用者選了新照片後若按「取消」，若這裡就刪掉
            // originalPhotoFileName，該檔案會被永久刪除卻沒有任何紀錄真的改用新照片
            // （取消不該有副作用）。改成只在 save() 依最終結果與原始檔名的差異決定要刪誰。
            // 若這是本次 session 已經選過一次的新照片（尚未儲存），要先清掉，否則連續換兩次
            // 照片會留下第一次選的孤兒檔案。
            if let previous = photoFileName, previous != originalPhotoFileName {
                ChildRecord.deletePhoto(previous)
            }
            photoFileName = savedName
            previewImage = origImage
        }
    }

    private var vaccinationFields: some View {
        Section {
            TextField("疫苗名稱（如：五合一）", text: $title)
            TextField("劑次（如：第 1 劑、追加）", text: $dose)
            clinicAutocompleteField(label: "接種院所（選填）")
            // 快速選取膠囊模板：去過的院所，點一下帶入
            QuickPickCapsuleRow(options: previousClinics, selection: $detail, accent: .blue)
        } header: {
            childEditorSectionHeader("疫苗資訊", icon: type.icon, color: accent)
        }
    }
    private var allergyFields: some View {
        Section {
            TextField("過敏原（如：花生、牛奶）", text: $title)
            severityPicker(selection: $severity)
            TextField("反應描述（如：紅疹、氣喘）", text: $detail, axis: .vertical).lineLimit(1...3)
        } header: {
            childEditorSectionHeader("過敏資訊", icon: type.icon, color: accent)
        }
    }
    private var growthFields: some View {
        Section {
            HStack { TextField("身高", text: $heightText).keyboardType(.decimalPad); Text("cm").foregroundStyle(.secondary) }
            HStack { TextField("體重", text: $weightText).keyboardType(.decimalPad); Text("kg").foregroundStyle(.secondary) }
        } header: {
            childEditorSectionHeader("成長數據", icon: type.icon, color: accent)
        }
    }
    private var medicalFields: some View {
        Section {
            TextField("症狀/診斷", text: $title)
            HStack {
                TextField("體溫（選填）", text: $tempText).keyboardType(.decimalPad)
                Text("°C").foregroundStyle(.secondary)
            }
            clinicAutocompleteField(label: "院所（選填）")
            // 快速選取膠囊模板：去過的院所，點一下帶入
            QuickPickCapsuleRow(options: previousClinics, selection: $detail, accent: .orange)
        } header: {
            childEditorSectionHeader("就醫資訊", icon: type.icon, color: accent)
        }
    }

    // MARK: - 院所自動完成（適用於就醫 / 疫苗接種院所）

    @ViewBuilder
    private func clinicAutocompleteField(label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(.red)
                    .frame(width: 18)
                TextField(label, text: $detail)
                    .focused($detailFieldFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !detail.isEmpty {
                    Button {
                        detail = ""
                        clinicExpandedSuggestions = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if detailFieldFocused {
                clinicSuggestionsList
            }
        }
        .onAppear {
            LocationProvider.shared.requestIfNeeded()
            clinicCompleter.setRegion(LocationProvider.shared.searchRegion)
            clinicDebouncedQuery = detail
            if !detail.isEmpty { clinicCompleter.queryFragment = detail }
        }
        .onChange(of: detail) { _, newValue in
            if clinicSuppressNextUpdate {
                clinicSuppressNextUpdate = false
                clinicDebouncedQuery = newValue
                return
            }
            // 300ms 防抖，對齊 AddExpenseView / VariableExpenseView 院所/餐廳搜尋規格，
            // 避免每次按鍵都即時發出 MKLocalSearchCompleter 網路請求；過往紀錄本地比對
            // 也一併等防抖後才更新，避免本地建議先跳、網路建議 0.3 秒後才到造成清單重排兩次。
            clinicDebounceTask?.cancel()
            clinicDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                clinicCompleter.queryFragment = newValue
                clinicDebouncedQuery = newValue
                clinicExpandedSuggestions = false
            }
        }
        .onChange(of: locationProvider.lastLocation) { _, _ in
            clinicCompleter.setRegion(LocationProvider.shared.searchRegion)
            if !detail.isEmpty { clinicCompleter.queryFragment = detail }
        }
    }

    @ViewBuilder
    private var clinicSuggestionsList: some View {
        let all = allClinicSuggestions
        if !all.isEmpty {
            let limit = 20
            let visible = clinicExpandedSuggestions ? all : Array(all.prefix(limit))
            let hiddenCount = max(0, all.count - limit)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { item in
                        Button { applyClinicSuggestion(item) } label: {
                            clinicSuggestionRow(item)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 44)
                    }
                    if !clinicExpandedSuggestions && hiddenCount > 0 {
                        Button {
                            clinicExpandedSuggestions = true
                        } label: {
                            HStack {
                                Image(systemName: "chevron.down.circle.fill").foregroundStyle(.blue)
                                Text("顯示更多 (\(hiddenCount))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.blue)
                                Spacer()
                            }
                            .padding(.vertical, 10).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else if clinicExpandedSuggestions && all.count > limit {
                        Button {
                            clinicExpandedSuggestions = false
                        } label: {
                            HStack {
                                Image(systemName: "chevron.up.circle.fill").foregroundStyle(.secondary)
                                Text("收合")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 10).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func clinicSuggestionRow(_ item: ClinicSuggestion) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(item.iconColor.opacity(0.15)).frame(width: 28, height: 28)
                Image(systemName: item.iconName)
                    .foregroundStyle(item.iconColor)
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// 合併所有小孩過往就醫 / 接種院所 + Apple Maps POI（醫療類）
    private var allClinicSuggestions: [ClinicSuggestion] {
        let q = clinicDebouncedQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var seen: Set<String> = []
        var output: [ClinicSuggestion] = []

        let allRecords: [ChildRecord] = lifeStore.familyMembers.flatMap { $0.childRecords }
        let medicalAndVaccination = allRecords.filter {
            $0.type == .medical || $0.type == .vaccination
        }
        let pastDetails: [String] = medicalAndVaccination
            .map { $0.detail.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for d in pastDetails {
            if !q.isEmpty && !d.lowercased().contains(q) { continue }
            let key = "past|\(d.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            output.append(ClinicSuggestion(
                id: key, source: .past, title: d, subtitle: "", completion: nil
            ))
        }

        for c in clinicCompleter.results {
            let key = "apple|\(c.title.lowercased())|\(c.subtitle.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            output.append(ClinicSuggestion(
                id: key, source: .apple, title: c.title, subtitle: c.subtitle, completion: c
            ))
        }

        return output
    }

    private func applyClinicSuggestion(_ item: ClinicSuggestion) {
        clinicSuppressNextUpdate = true
        switch item.source {
        case .past:
            detail = item.title
        case .apple:
            // Apple Maps 帶「名稱 - 地址」較完整
            if item.subtitle.isEmpty {
                detail = item.title
            } else {
                detail = "\(item.title) - \(item.subtitle)"
            }
        }
        clinicExpandedSuggestions = false
        detailFieldFocused = false
    }
    private var educationFields: some View {
        Section {
            TextField("事件", text: $title); TextField("學校或單位（選填）", text: $detail)
        } header: {
            childEditorSectionHeader("教育里程碑", icon: type.icon, color: accent)
        }
    }
    private var hobbyFields: some View {
        Section {
            TextField("項目", text: $title); TextField("描述（選填）", text: $detail, axis: .vertical).lineLimit(1...3)
        } header: {
            childEditorSectionHeader("興趣才藝", icon: type.icon, color: accent)
        }
    }
    private var memorableFields: some View {
        Section {
            TextField("事件", text: $title); TextField("描述（選填）", text: $detail, axis: .vertical).lineLimit(1...3)
        } header: {
            childEditorSectionHeader("紀念時刻", icon: type.icon, color: accent)
        }
    }

    /// 去過的院所（就醫＋疫苗記錄的 detail 欄位，快速選取膠囊模板選項）
    private var previousClinics: [String] {
        guard let member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { return [] }
        return QuickPickOptions.recent(
            member.childRecords
                .filter { $0.type == .medical || $0.type == .vaccination }
                .map { (value: $0.detail, date: $0.date) }
        )
    }

    private func loadEditing() {
        guard let e = editing else { return }
        title = e.title; detail = e.detail; date = e.date; note = e.note
        if let h = e.heightCm, h > 0 { heightText = String(format: "%g", h) }
        if let w = e.weightKg, w > 0 { weightText = String(format: "%g", w) }
        dose = e.dose ?? ""; severity = e.severity ?? .mild
        if let t = e.temperatureC, t > 0 { tempText = String(format: "%g", t) }
        photoFileName = e.photoFileName
        originalPhotoFileName = e.photoFileName
        if let name = e.photoFileName,
           let data = try? Data(contentsOf: ChildRecord.photosDirectory.appendingPathComponent(name)) {
            previewImage = UIImage(data: data)
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        isSaving = true
        // 原始照片與最終結果不同（換照片或移除圖片）才刪除原檔；真正的刪除動作延到這裡才提交，
        // 使用者中途按「取消」不會遺失原本已存在的照片（見 photoItem onChange／移除圖片按鈕註解）。
        if let original = originalPhotoFileName, original != photoFileName {
            ChildRecord.deletePhoto(original)
        }
        let rec = ChildRecord(
            id: editing?.id ?? UUID(), type: type, date: date,
            title: title.trimmingCharacters(in: .whitespaces), detail: detail.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            heightCm: type == .growth ? Double(heightText) : nil, weightKg: type == .growth ? Double(weightText) : nil,
            dose: type == .vaccination ? dose.trimmingCharacters(in: .whitespaces) : nil,
            severity: type == .allergy ? severity : nil,
            photoFileName: photoFileName,
            temperatureC: type == .medical ? Double(tempText) : nil
        )
        if let idx = member.childRecords.firstIndex(where: { $0.id == rec.id }) { member.childRecords[idx] = rec }
        else { member.childRecords.append(rec) }
        lifeStore.update(member); dismiss()
    }

    private func delete() {
        guard !isSaving else { return }
        guard let e = editing, var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        isSaving = true
        member.childRecords.removeAll { $0.id == e.id }
        lifeStore.update(member); dismiss()
    }
}

// MARK: - 院所候選資料型別

fileprivate struct ClinicSuggestion: Identifiable {
    enum Source { case past, apple }
    let id: String
    let source: Source
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion?

    var iconName: String {
        source == .past ? "clock.arrow.circlepath" : "cross.case.fill"
    }
    var iconColor: Color {
        source == .past ? .green : .red
    }
}

// MARK: - 日常趨勢圖表（喝奶/食物/睡眠/身高/體重五張折線圖，左右滑動切換）
//
// 取樣規則（使用者指定）：X 軸涵蓋「第一筆到最後一筆」全期間；有資料的日子才成為資料點
// （喝奶/食物加總 ml、睡眠加總小時、身高/體重取當日值），超過 40 點時等距取樣至 40 點
// （首尾必取），兼顧多年歷史的可讀性與繪圖效能。

private struct DailyTrendPoint: Identifiable {
    let day: Date
    let total: Double
    let count: Int
    var id: Date { day }
}

/// 五個趨勢指標：前三個來自日常紀錄（逐日彙總），身高/體重來自成長紀錄（當日值）
enum ChildTrendMetric: String, CaseIterable {
    case milk = "喝奶量"
    case food = "食物量"
    case sleep = "睡眠量"
    case height = "身高"
    case weight = "體重"
    case temperature = "體溫"

    var icon: String {
        switch self {
        case .milk: return "cup.and.saucer.fill"
        case .food: return "carrot.fill"
        case .sleep: return "moon.zzz.fill"
        case .height: return "ruler.fill"
        case .weight: return "scalemass.fill"
        case .temperature: return "medical.thermometer.fill"
        }
    }

    var accent: Color {
        switch self {
        case .milk: return .blue
        case .food: return .green
        case .sleep: return .indigo
        case .height: return .teal
        case .weight: return .pink
        case .temperature: return .red
        }
    }

    var unit: String {
        switch self {
        case .milk, .food: return "ml"
        case .sleep: return "小時"
        case .height: return "cm"
        case .weight: return "kg"
        case .temperature: return "°C"
        }
    }
}

struct DailyChartsPager: View {
    let records: [DailyRecord]
    let childRecords: [ChildRecord]
    @State private var page: Int = 0

    private static let metrics = ChildTrendMetric.allCases

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(Array(Self.metrics.enumerated()), id: \.offset) { idx, metric in
                    DailyTrendChart(
                        metric: metric,
                        points: Self.trendPoints(for: metric, daily: records, childRecords: childRecords)
                    )
                    .padding(.horizontal, 16)
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 262)

            // 自訂頁點：目前頁拉長成膠囊並套用該圖表主題色
            HStack(spacing: 6) {
                ForEach(0..<Self.metrics.count, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Self.metrics[i].accent : Color(.systemGray4))
                        .frame(width: i == page ? 16 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                }
            }
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    /// 逐日彙總（喝奶/食物加總 ml、睡眠加總小時、身高/體重取當日值、體溫取當日最高）
    /// 後依日期排序，超過 40 點時等距取樣至 40 點
    static fileprivate func trendPoints(for metric: ChildTrendMetric,
                                        daily: [DailyRecord],
                                        childRecords: [ChildRecord]) -> [DailyTrendPoint] {
        let cal = Calendar.current
        var byDay: [Date: (total: Double, count: Int)] = [:]

        switch metric {
        case .milk, .food, .sleep:
            let type: DailyRecordType = (metric == .milk) ? .milk : (metric == .food ? .food : .sleep)
            for r in daily where r.type == type {
                let day = cal.startOfDay(for: r.date)
                let value: Double
                switch type {
                case .milk, .food:
                    value = r.mlAmount ?? 0
                case .sleep:
                    guard let end = r.sleepEnd, end > r.date else { continue }
                    value = end.timeIntervalSince(r.date) / 3600
                }
                var cur = byDay[day] ?? (0, 0)
                cur.total += value
                cur.count += 1
                byDay[day] = cur
            }
        case .height, .weight:
            // 成長紀錄的當日值（同日多筆取較晚一筆），非加總
            for r in childRecords.sorted(by: { $0.date < $1.date }) where r.type == .growth {
                let v = (metric == .height) ? r.heightCm : r.weightKg
                guard let v, v > 0 else { continue }
                let day = cal.startOfDay(for: r.date)
                byDay[day] = (v, (byDay[day]?.count ?? 0) + 1)
            }
        case .temperature:
            // 就醫記錄體溫：同日多筆取「最高」（發燒追蹤最有意義），非加總
            for r in childRecords where r.type == .medical {
                guard let t = r.temperatureC, t > 0 else { continue }
                let day = cal.startOfDay(for: r.date)
                let cur = byDay[day] ?? (0, 0)
                byDay[day] = (max(cur.total, t), cur.count + 1)
            }
        }

        let sorted = byDay
            .map { DailyTrendPoint(day: $0.key, total: $0.value.total, count: $0.value.count) }
            .sorted { $0.day < $1.day }
        return downsample(sorted, maxCount: 40)
    }

    /// 等距取樣至 maxCount 點（首尾必取）：index 依比例映射、去重
    static fileprivate func downsample(_ pts: [DailyTrendPoint], maxCount: Int) -> [DailyTrendPoint] {
        guard pts.count > maxCount, maxCount >= 2 else { return pts }
        let step = Double(pts.count - 1) / Double(maxCount - 1)
        var out: [DailyTrendPoint] = []
        var lastIdx = -1
        for i in 0..<maxCount {
            let idx = Int((Double(i) * step).rounded())
            if idx != lastIdx {
                out.append(pts[idx])
                lastIdx = idx
            }
        }
        return out
    }
}

/// 單張趨勢折線圖：漸層面積 + 資料點 + chartXSelection 點選顯示該日細節
private struct DailyTrendChart: View {
    let metric: ChildTrendMetric
    let points: [DailyTrendPoint]
    @State private var rawSelectedDay: Date?

    private var accent: Color { metric.accent }
    private var unitLabel: String { metric.unit }

    /// 點選的原始 X 值吸附到「最近」的取樣點（取樣後點與點之間可能相隔多天）
    private var selectedPoint: DailyTrendPoint? {
        guard let raw = rawSelectedDay, !points.isEmpty else { return nil }
        return points.min(by: {
            abs($0.day.timeIntervalSince(raw)) < abs($1.day.timeIntervalSince(raw))
        })
    }

    private static let ymdFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.09)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 30, height: 30)
                    Circle()
                        .stroke(accent.opacity(0.20), lineWidth: 0.75)
                        .frame(width: 30, height: 30)
                    Image(systemName: metric.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(metric.rawValue)趨勢")
                        .font(.subheadline.weight(.bold))
                    Text("全期間・最多取樣 40 點・單位 \(unitLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 14)

            if points.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: metric.icon)
                        .font(.title3)
                        .foregroundStyle(accent.opacity(0.45))
                    Text("尚無\(metric.rawValue)紀錄")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 170)
            } else {
                chartBody
            }
        }
    }

    private var chartBody: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(
                    x: .value("日期", p.day, unit: .day),
                    y: .value(unitLabel, p.total)
                )
                .foregroundStyle(LinearGradient(
                    colors: [accent.opacity(0.18), accent.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("日期", p.day, unit: .day),
                    y: .value(unitLabel, p.total)
                )
                .foregroundStyle(accent)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))

                PointMark(
                    x: .value("日期", p.day, unit: .day),
                    y: .value(unitLabel, p.total)
                )
                .foregroundStyle(accent)
                .symbolSize(26)
            }
            if let sel = selectedPoint {
                RuleMark(x: .value("選取", sel.day, unit: .day))
                    .foregroundStyle(accent.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        selectionCard(sel)
                    }
                PointMark(
                    x: .value("選取", sel.day, unit: .day),
                    y: .value(unitLabel, sel.total)
                )
                .foregroundStyle(accent)
                .symbolSize(80)
            }
        }
        .chartXSelection(value: $rawSelectedDay)
        // 身高/體重/體溫的曲線集中在高值區間，鎖 0 起點會被壓扁；量類指標維持 0 起點好比對
        .chartYScale(domain: (metric == .height || metric == .weight || metric == .temperature)
                     ? .automatic(includesZero: false)
                     : .automatic(includesZero: true))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 170)
        .padding(.bottom, 6)
    }

    /// 點選資料點的細節卡：日期、當日數值、筆數/段數
    private func selectionCard(_ p: DailyTrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.ymdFmt.string(from: p.day))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(valueText(p))
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
            if let sub = subText(p) {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.25), lineWidth: 0.75))
    }

    private func valueText(_ p: DailyTrendPoint) -> String {
        switch metric {
        case .milk, .food: return "共 \(Int(p.total)) ml"
        case .sleep: return String(format: "共 %.1f 小時", p.total)
        case .height: return String(format: "%.1f cm", p.total)
        case .weight: return String(format: "%.1f kg", p.total)
        case .temperature: return String(format: "%.1f °C", p.total)
        }
    }

    private func subText(_ p: DailyTrendPoint) -> String? {
        switch metric {
        case .milk, .food: return "\(p.count) 筆紀錄"
        case .sleep: return "\(p.count) 段睡眠"
        case .height, .weight: return "成長紀錄"
        case .temperature: return p.count > 1 ? "當日最高（\(p.count) 筆）" : "就醫紀錄"
        }
    }
}


// MARK: - 兒女記錄詳情卡（點列先看卡片，右上「編輯」；同型模式見 VehicleItemDetailSheet）

fileprivate struct ChildRecordDetailSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let record: ChildRecord

    @State private var editingRecord: ChildRecord?
    @State private var showPremiumAlert = false
    @State private var viewingPhotoURL: IdentifiableURL?

    /// 每次 body 都取最新版本：右上「編輯」存檔回來畫面即時反映
    private var current: ChildRecord {
        lifeStore.familyMembers.first(where: { $0.id == childId })?
            .childRecords.first(where: { $0.id == record.id }) ?? record
    }

    /// 記錄是否已被刪除（編輯器內刪除後自動關閉詳情卡）
    private var isDeleted: Bool {
        lifeStore.familyMembers.first(where: { $0.id == childId })?
            .childRecords.contains(where: { $0.id == record.id }) == false
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private var accent: Color {
        switch current.type {
        case .vaccination: return .blue; case .allergy: return .red; case .growth: return .green
        case .medical: return .orange; case .education: return .purple
        case .hobby: return .pink; case .memorable: return .yellow
        }
    }

    /// detail 欄位在各類型的語意標籤（對齊編輯表單的欄位名稱）
    private var detailLabel: String {
        switch current.type {
        case .medical, .vaccination: return "院所"
        case .allergy: return "反應描述"
        case .education: return "學校或單位"
        default: return "描述"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                let rec = current
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 44, height: 44)
                            Circle()
                                .stroke(accent.opacity(0.22), lineWidth: 1)
                                .frame(width: 44, height: 44)
                            Image(systemName: rec.type.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rec.title.isEmpty ? rec.type.rawValue : rec.title)
                                .font(.headline)
                            HStack(spacing: 6) {
                                Text(rec.type.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(accent.opacity(0.12))
                                    .foregroundStyle(accent)
                                    .clipShape(Capsule())
                                Text(Self.dateFmt.string(from: rec.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("記錄資訊") {
                    if !rec.detail.isEmpty { infoRow(detailLabel, rec.detail) }
                    if rec.type == .growth {
                        if let h = rec.heightCm, h > 0 { infoRow("身高", String(format: "%.1f cm", h)) }
                        if let w = rec.weightKg, w > 0 { infoRow("體重", String(format: "%.1f kg", w)) }
                    }
                    if rec.type == .medical, let t = rec.temperatureC, t > 0 {
                        HStack {
                            Text("體溫").foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f °C", t))
                                .foregroundStyle(t >= 38 ? Color.red : Color.primary)
                                .fontWeight(t >= 38 ? .semibold : .regular)
                        }
                    }
                    if rec.type == .vaccination, let dose = rec.dose, !dose.isEmpty {
                        infoRow("劑次", dose)
                    }
                    if rec.type == .allergy, let sev = rec.severity {
                        infoRow("嚴重度", sev.rawValue)
                    }
                    if !rec.note.isEmpty { infoRow("備註", rec.note) }
                }

                if let url = rec.photoURL, rec.photoFileName != nil {
                    Section("照片") {
                        Button {
                            viewingPhotoURL = IdentifiableURL(url: url)
                        } label: {
                            AsyncLocalImage(url: url) { img, _ in
                                if let img {
                                    Image(uiImage: img)
                                        .resizable().scaledToFit()
                                        .frame(maxHeight: 260)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(current.type.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編輯") {
                        if subscription.isPremium { editingRecord = current }
                        else { showPremiumAlert = true }
                    }
                    .bold().foregroundStyle(.green)
                }
            }
            .sheet(item: $editingRecord) { rec in
                ChildRecordEditorSheet(childId: childId, type: rec.type, editing: rec)
            }
            .sheet(item: $viewingPhotoURL) { wrapper in
                PhotoLightbox(url: wrapper.url)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onChange(of: isDeleted) { _, gone in
                if gone { dismiss() }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - 日常記錄詳情卡（喝奶/食物/睡眠）

fileprivate struct DailyRecordDetailSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let record: DailyRecord

    @State private var editingDaily: DailyRecord?
    @State private var showPremiumAlert = false

    private var current: DailyRecord {
        lifeStore.familyMembers.first(where: { $0.id == childId })?
            .dailyRecords.first(where: { $0.id == record.id }) ?? record
    }

    private var isDeleted: Bool {
        lifeStore.familyMembers.first(where: { $0.id == childId })?
            .dailyRecords.contains(where: { $0.id == record.id }) == false
    }

    private static let dateTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()

    private var accent: Color {
        switch current.type {
        case .milk: return .blue
        case .food: return .green
        case .sleep: return .indigo
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                let rec = current
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 44, height: 44)
                            Circle()
                                .stroke(accent.opacity(0.22), lineWidth: 1)
                                .frame(width: 44, height: 44)
                            Image(systemName: rec.type.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rec.type.rawValue).font(.headline)
                            Text(Self.dateTimeFmt.string(from: rec.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("記錄資訊") {
                    switch rec.type {
                    case .milk:
                        if let brand = rec.milkBrand, !brand.isEmpty { infoRow("奶粉品牌", brand) }
                        if let ml = rec.mlAmount, ml > 0 { infoRow("奶量", "\(Int(ml)) ml") }
                    case .food:
                        if let name = rec.foodName, !name.isEmpty { infoRow("食物", name) }
                        if let ml = rec.mlAmount, ml > 0 { infoRow("份量", "\(Int(ml)) ml") }
                    case .sleep:
                        infoRow("入睡", Self.dateTimeFmt.string(from: rec.date))
                        if let end = rec.sleepEnd {
                            infoRow("起床", Self.dateTimeFmt.string(from: end))
                            if end > rec.date {
                                infoRow("時長", String(format: "%.1f 小時", end.timeIntervalSince(rec.date) / 3600))
                            }
                        }
                    }
                    if !rec.note.isEmpty { infoRow("備註", rec.note) }
                }
            }
            .navigationTitle(current.type.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編輯") {
                        if subscription.isPremium { editingDaily = current }
                        else { showPremiumAlert = true }
                    }
                    .bold().foregroundStyle(.green)
                }
            }
            .sheet(item: $editingDaily) { rec in
                DailyRecordEditorSheet(childId: childId, type: rec.type, editing: rec)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onChange(of: isDeleted) { _, gone in
                if gone { dismiss() }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
