import SwiftUI
import MapKit

// MARK: - 功能項目定義

enum ExpenseFeature: String, CaseIterable, Identifiable {
    case overview, income, variable, fixed, chart
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "總覽"
        case .income: return "收入"
        case .variable: return "變動支出"
        case .fixed: return "固定支出"
        case .chart: return "圖表"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "house.fill"
        case .income: return "banknote.fill"
        case .variable: return "arrow.up.arrow.down.circle.fill"
        case .fixed: return "pin.circle.fill"
        case .chart: return "chart.line.uptrend.xyaxis"
        }
    }
}

enum FinanceFeature: String, CaseIterable, Identifiable {
    case overview, insurance, stock, vehicle, realEstate, chart
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "總覽"
        case .insurance: return "儲蓄險"
        case .stock: return "股票"
        case .vehicle: return "載具"
        case .realEstate: return "房地產"
        case .chart: return "圖表"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "house.fill"
        case .insurance: return "shield.fill"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .vehicle: return "car.fill"
        case .realEstate: return "building.2.fill"
        case .chart: return "chart.pie.fill"
        }
    }
}

enum LifeFeature: String, CaseIterable, Identifiable {
    case overview, resume, finance, career, family, realEstate, tax, foodMap, travelMap, medicalMap
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "總覽"
        case .resume: return "履歷"
        case .finance: return "財富"
        case .career: return "職涯"
        case .family: return "家庭"
        case .realEstate: return "房地產"
        case .tax: return "稅務"
        case .foodMap: return "美食地圖"
        case .travelMap: return "旅遊地圖"
        case .medicalMap: return "醫療地圖"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "house.fill"
        case .resume: return "trophy.fill"
        case .finance: return "banknote.fill"
        case .career: return "briefcase.fill"
        case .family: return "person.3.fill"
        case .realEstate: return "building.2.fill"
        case .tax: return "doc.text.fill"
        case .foodMap: return "fork.knife.circle.fill"
        case .travelMap: return "airplane.circle.fill"
        case .medicalMap: return "cross.case.circle.fill"
        }
    }
}

enum ManagementFeature: String, CaseIterable, Identifiable {
    case calendar, overview, subordinates, businessCard, organization, gradeTitle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calendar: return "我的行事曆"
        case .overview: return "部屬總覽"
        case .subordinates: return "部屬"
        case .businessCard: return "名片"
        case .organization: return "公司組織"
        case .gradeTitle: return "部門職等"
        }
    }
    var icon: String {
        switch self {
        case .calendar: return "calendar.badge.clock"
        case .overview: return "chart.bar.doc.horizontal"
        case .subordinates: return "person.2.fill"
        case .businessCard: return "person.crop.rectangle.stack"
        case .organization: return "building.2.crop.circle"
        case .gradeTitle: return "list.number"
        }
    }
}

enum FamilyMgmtFeature: String, CaseIterable, Identifiable {
    case spouseResume, childrenResume, relativeResume
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spouseResume:   return "配偶履歷"
        case .childrenResume: return "兒女履歷"
        case .relativeResume: return "家人履歷"
        }
    }
    var icon: String {
        switch self {
        case .spouseResume:   return "heart.circle.fill"
        case .childrenResume: return "figure.2.and.child.holdinghands"
        case .relativeResume: return "person.3.sequence.fill"
        }
    }
}

// MARK: - 美化紀錄（MainTabView）
// [初版] UI 美化方向（既有）：
//   • bottomTabBar：@Namespace + matchedGeometryEffect 讓選中膠囊在頁籤間平滑滑動
//   • topSubFeatureBar：兩側漸層遮罩（allowsHitTesting false）暗示橫向可捲動
//   • FAB：彈出選單彩色陰影 + 主 FAB 雙層 shadow 綠色光暈
//   • Tab 圖示：active 時 scaleEffect 1.05 + symbolEffect(.bounce)
// [2026-06] 本次美化方向：
//   1. subFeaturePill 非選中狀態：補 Capsule overlay stroke（.primary.opacity(0.08), 0.6pt），
//      深色模式下未選中膠囊具備細框線，與全 App 系統元件細邊框設計語言一致，
//      對齊 FilterChip / ExpenseRow categoryAccent Capsule 規格。
//   2. exportProgressBar：
//      ① 軌道從 Rectangle → Capsule，圓頭視覺更精緻；
//      ② 進度填充從純色 Color.green → LinearGradient（.green→teal）+ Capsule + 軟光暈 shadow，
//         對齊 IncomeView summaryHeader 雙軌進度條設計語言；
//      ③ 高度 2.5pt → 3.5pt，避免細到難以辨識。
//   3. tabItemLabel 選中指示器：
//      Capsule 底色從純色 Color.green.opacity(0.15) 升級為
//      LinearGradient（topLeading 0.22 → bottomTrailing 0.10）+ overlay stroke（0.75pt），
//      對齊 FinanceOverviewView.totalAssetsCard / SavingsInsuranceView 漸層卡片設計語言。
// [2026-07] 本次美化方向：AI 語音記帳結果提示卡（aiToastView）
//   4. 圖示從裸 SF Symbol 升級為 32pt 漸層圓徽章（LinearGradient 填色 + stroke 邊框），
//      對齊 AdminConsoleView / SettingsView 圖示圓規格。
//   5. 卡片補上 accent 色（成功綠／失敗橘）overlay RoundedRectangle stroke（0.75pt）
//      與第二層柔化陰影，取代單一黑色陰影，成功/失敗主題更醒目。
//   6. aiCommitExpense 成功 toast 金額顯示改用全 App 共用 ntdWanString 萬/億智慧量級，
//      取代原本高額時會顯示成長串裸整數（如 NT$ 1200000）的寫法；
//      純顯示調整，未變動實際存入的 Expense.amount 或其他記帳邏輯。
//   （下次美化本檔案時，可從 topSubFeatureBar／floatingActionButton 繼續找可統一之處）

// MARK: - 主畫面

struct MainTabView: View {
    @AppStorage("appMode") private var appMode: String = AppMode.expense.rawValue
    @AppStorage("expense_feature") private var expenseFeatureRaw: String = ExpenseFeature.overview.rawValue
    @AppStorage("finance_feature") private var financeFeatureRaw: String = FinanceFeature.overview.rawValue
    @AppStorage("life_feature") private var lifeFeatureRaw: String = LifeFeature.overview.rawValue
    /// 職涯子功能；空字串代表選的是「職涯」本身
    @AppStorage("management_feature") private var managementFeatureRaw: String = ""
    /// 家庭子功能；空字串代表選的是「家庭」本身
    @AppStorage("family_mgmt_feature") private var familyMgmtFeatureRaw: String = ""
    @State private var isSettingsActive: Bool = false
    // UI美化：matchedGeometryEffect 讓底部 Tab Bar 選中指示器在頁籤間滑動而非消失/出現
    @Namespace private var tabBarNamespace
    // 佔位用（.hidden()）bottomTabBar 副本專用的獨立 namespace：避免與下方真正顯示的
    // bottomTabBar 共用 tabBarNamespace，導致同一個 matchedGeometryEffect(id:) 在同一個
    // namespace 裡同時有兩個 source view（Apple 文件：結果為 undefined），
    // 可能造成分頁切換時膠囊指示器位置偶發跳動。
    @Namespace private var hiddenTabBarNamespace

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPaywall: Bool = false

    private var currentMode: AppMode {
        AppMode(rawValue: appMode) ?? .expense
    }

    private var expenseFeature: ExpenseFeature {
        ExpenseFeature(rawValue: expenseFeatureRaw) ?? .overview
    }

    private var financeFeature: FinanceFeature {
        FinanceFeature(rawValue: financeFeatureRaw) ?? .overview
    }

    private var lifeFeature: LifeFeature {
        LifeFeature(rawValue: lifeFeatureRaw) ?? .overview
    }

    private var managementFeature: ManagementFeature? {
        ManagementFeature(rawValue: managementFeatureRaw)
    }

    private var currentFeatureTitle: String {
        switch currentMode {
        case .expense: return expenseFeature.title
        case .finance: return financeFeature.title
        case .life:
            if lifeFeature == .career, let m = managementFeature { return m.title }
            if lifeFeature == .family, let f = familyMgmtFeature { return f.title }
            return lifeFeature.title
        }
    }

    private var currentFeatureIcon: String {
        switch currentMode {
        case .expense: return expenseFeature.icon
        case .finance: return financeFeature.icon
        case .life:
            if lifeFeature == .career, let m = managementFeature { return m.icon }
            if lifeFeature == .family, let f = familyMgmtFeature { return f.icon }
            return lifeFeature.icon
        }
    }

    private var isCurrentlyManagerial: Bool {
        let relevant = lifeStore.milestones.filter {
            $0.category == .career &&
            ($0.careerSubCategory == .join || $0.careerSubCategory == .promote ||
             $0.careerSubCategory == .transfer || $0.careerSubCategory == .demote)
        }
        return relevant.max(by: { $0.date < $1.date })?.isManagerial == true
    }

    private var familyMgmtFeature: FamilyMgmtFeature? {
        FamilyMgmtFeature(rawValue: familyMgmtFeatureRaw)
    }

    private var hasSpouse: Bool {
        lifeStore.familyMembers.contains { $0.role == .spouse }
    }

    private var hasChildren: Bool {
        lifeStore.familyMembers.contains { $0.role == .son || $0.role == .daughter }
    }

    /// 是否有「直系（爸媽）+ 二等親屬（兄弟姐妹 / 其他親屬）」可進入家人履歷
    private var hasExtendedFamily: Bool {
        lifeStore.familyMembers.contains {
            [.father, .mother, .elderBrother, .elderSister,
             .youngerBrother, .youngerSister, .otherRelative].contains($0.role)
        }
    }

    /// 職涯子功能列在「職涯」被選取且使用者目前為主管時展開
    private var shouldExpandManagement: Bool {
        currentMode == .life && lifeFeature == .career && isCurrentlyManagerial && !isSettingsActive
    }

    /// 家庭子功能列在「家庭」被選取且有家庭成員時展開
    private var shouldExpandFamily: Bool {
        currentMode == .life && lifeFeature == .family && !lifeStore.familyMembers.isEmpty && !isSettingsActive
    }

    private var availableFamilyFeatures: [FamilyMgmtFeature] {
        var list: [FamilyMgmtFeature] = []
        if hasSpouse { list.append(.spouseResume) }
        if hasChildren { list.append(.childrenResume) }
        if hasExtendedFamily { list.append(.relativeResume) }
        return list
    }

    @State private var showQuickAdd = false
    @State private var showAddIncome = false
    @State private var showAddExpense = false
    @State private var fabOffset: CGSize = .zero
    @State private var fabDragOffset: CGSize = .zero

    // MARK: - 語音 AI 記帳
    @StateObject private var aiSettings = AISettingsStore.shared
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var exportProgress = ExportProgressModel.shared
    @State private var aiToast: AIToastInfo?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var aiBusy = false
    /// 同步守門旗標：DragGesture.onChanged 在按住期間會反覆觸發，
    /// 但 aiStartRecording 是 async，從觸發到 speechRecognizer.isRecording=true 之間有空窗，
    /// 若沒這個旗標會多次平行 startRecording → 重設 transcript / 重裝 audio tap → 畫面閃爍
    @State private var aiStartingRecording = false
    /// 麥克風進場動畫旗標：每次切到變動支出頁就從左下角彈一次
    @State private var micEntered = false

    /// 是否在「收支 → 變動支出」分頁
    private var isOnVariableExpense: Bool {
        currentMode == .expense
        && expenseFeatureRaw == ExpenseFeature.variable.rawValue
        && !isSettingsActive
    }

    private struct AIToastInfo: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let isError: Bool
    }

    /// 目前所在頁面是否屬於付費功能（且尚未訂閱）。
    private var isCurrentViewPremiumLocked: Bool {
        if subscription.isPremium { return false }
        if isSettingsActive { return false }
        switch currentMode {
        case .expense: return !FeatureGate.isFree(expenseFeature)
        case .finance: return !FeatureGate.isFree(financeFeature)
        case .life:
            if lifeFeature == .career, let m = managementFeature { return !FeatureGate.isFree(m) }
            if lifeFeature == .family, let f = familyMgmtFeature { return !FeatureGate.isFree(f) }
            return !FeatureGate.isFree(lifeFeature)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !isSettingsActive {
                    topSubFeatureBar
                }
                if isCurrentViewPremiumLocked {
                    PremiumBanner(showPaywall: $showPaywall)
                }
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 佔位用：與底部 tab bar 同高，保證內容區不會被 tab bar 蓋住。
                // 用獨立的 hiddenTabBarNamespace，避免跟下方真正顯示的副本共用同一個
                // matchedGeometryEffect namespace（見上方 hiddenTabBarNamespace 宣告註解）。
                bottomTabBar(namespace: hiddenTabBarNamespace)
                    .hidden()
            }
            .tint(.green)
            .onChange(of: appMode) { _, _ in
                isSettingsActive = false
            }
            .onChange(of: lifeFeatureRaw) { _, newValue in
                // 切到別的人生子功能時，清除非當前父功能的 sub 選擇
                if newValue != LifeFeature.career.rawValue { managementFeatureRaw = "" }
                if newValue != LifeFeature.family.rawValue { familyMgmtFeatureRaw = "" }
            }

            floatingActionButton

            if isOnVariableExpense && aiSettings.isReady && subscription.isPremium {
                aiMicOverlay
            }

            // 真正顯示用的 tab bar：壓在麥克風上層，誤觸時也能看清楚分頁
            VStack(spacing: 0) {
                Spacer()
                if exportProgress.isExporting {
                    exportProgressBar
                }
                bottomTabBar(namespace: tabBarNamespace)
            }

            if let toast = aiToast {
                aiToastView(toast)
            }
        }
        .sheet(isPresented: $showAddIncome) { AddIncomeView() }
        .sheet(isPresented: $showAddExpense) { AddExpenseView(expenseType: .variable) }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(subscription)
        }
        .onChange(of: scenePhase) { _, phase in
            // 切換 App 時，若正在錄音則立即終止；避免 audio session 被系統中斷
            // 反覆觸發 isRecording 切換造成麥克風光暈動畫不停閃爍
            if phase != .active && speechRecognizer.isRecording {
                speechRecognizer.stopRecording()
                aiBusy = false
            }
        }
        .onChange(of: isOnVariableExpense, initial: true) { _, isOn in
            // 每次切到變動支出頁，從左下角彈一次皮球進場
            if isOn {
                micEntered = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.5)) {
                        micEntered = true
                    }
                }
            } else {
                micEntered = false
            }
        }
    }

    // MARK: - 語音 AI 浮動麥克風

    private var aiMicOverlay: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            VStack(alignment: .leading, spacing: 8) {
                // 即時辨識文字氣泡：保持在原本 20pt 內距、不跟著麥克風偏左，否則會被銀幕邊緣裁掉
                if speechRecognizer.isRecording && !speechRecognizer.transcript.isEmpty {
                    Text(speechRecognizer.transcript)
                        .font(.caption.weight(.medium))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        .frame(maxWidth: 260, alignment: .leading)
                        .transition(.scale.combined(with: .opacity))
                }
                aiMicButton
                    .scaleEffect(micEntered ? 1.8 : 0.05)
                    .rotationEffect(.degrees(micEntered ? 30 : -120))
                    .offset(
                        x: micEntered ? -30 : -120,
                        y: micEntered ? 35 : 180
                    )
            }
            .padding(.leading, 20)
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    private var aiMicButton: some View {
        let listening = speechRecognizer.isRecording
        return ZStack {
            // 外圍呼吸光暈
            Circle()
                .fill(Color.purple.opacity(listening ? 0.45 : 0))
                .frame(width: 96, height: 96)
                .scaleEffect(listening ? 1.25 : 1.0)
                .blur(radius: listening ? 14 : 0)
                .animation(
                    listening
                    ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.2),
                    value: listening
                )
            // 中圈光暈
            Circle()
                .stroke(Color.purple.opacity(listening ? 0.55 : 0), lineWidth: 2)
                .frame(width: 78, height: 78)
                .scaleEffect(listening ? 1.18 : 1.0)
                .animation(
                    listening
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.2),
                    value: listening
                )
            // 主按鈕
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.55, green: 0.35, blue: 0.95),
                                 Color(red: 0.40, green: 0.20, blue: 0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 62, height: 62)
                // 深色陰影：營造按鈕浮起感
                .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 8)
                // 紫色光暈：強調主題色、錄音時更亮
                .shadow(color: Color.purple.opacity(listening ? 0.8 : 0.5),
                        radius: listening ? 18 : 14, x: 0, y: 4)
                .scaleEffect(listening ? 1.08 : 1.0)
                .animation(
                    listening
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.2),
                    value: listening
                )
            Group {
                if aiBusy {
                    ProgressView().tint(.white)
                } else {
                    VStack(spacing: 1) {
                        Image(systemName: listening ? "waveform" : "mic.fill")
                            .foregroundStyle(.white)
                            .font(.system(size: 22, weight: .bold))
                            .scaleEffect(listening ? 1.1 : 1.0)
                        Text("AI 嵌入")
                            .foregroundStyle(.white)
                            .font(.system(size: 8, weight: .semibold))
                    }
                }
            }
        }
        .contentShape(Circle())
        // 按住開始 / 放開停止
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    // 已在錄音、AI 處理中或正在啟動 → 直接略過
                    guard !speechRecognizer.isRecording,
                          !aiBusy,
                          !aiStartingRecording
                    else { return }
                    aiStartingRecording = true
                    Task {
                        await aiStartRecording()
                        await MainActor.run { aiStartingRecording = false }
                    }
                }
                .onEnded { _ in
                    guard speechRecognizer.isRecording else { return }
                    Task { await aiFinishRecording() }
                }
        )
    }

    @MainActor
    private func aiStartRecording() async {
        let granted = await speechRecognizer.requestAccess()
        guard granted else {
            aiShowToast("無法啟用語音", detail: "請至「設定 → LifeGood」開啟麥克風與語音辨識權限。", isError: true)
            return
        }
        do {
            try speechRecognizer.startRecording()
        } catch {
            aiShowToast("錄音失敗", detail: error.localizedDescription, isError: true)
        }
    }

    @MainActor
    private func aiFinishRecording() async {
        let text = speechRecognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        speechRecognizer.stopRecording()
        guard !text.isEmpty else {
            aiShowToast("沒聽到內容", detail: "請再按住麥克風試一次。", isError: true)
            return
        }
        aiBusy = true
        do {
            // 把家庭成員姓名與本人名字一起送給 AI，讓它從固定清單選同行者
            // 優先用中文姓名，沒填才用英文姓名
            func memberName(_ chinese: String, _ english: String) -> String {
                let c = chinese.trimmingCharacters(in: .whitespaces)
                if !c.isEmpty { return c }
                return english.trimmingCharacters(in: .whitespaces)
            }
            var familyNames: [String] = lifeStore.familyMembers
                .map { memberName($0.chineseName, $0.englishName) }
                .filter { !$0.isEmpty }
            let myName = aiSpeakerName()
            if !myName.isEmpty { familyNames.insert(myName, at: 0) }

            // 蒐集信用卡 / 銀行帳戶 / 房地產顯示名稱，讓 AI 從清單挑選關聯
            let cardDisplayNames = aiCreditCardDisplayNames()
            let bankDisplayNames = aiBankDisplayNames()
            let realEstateDisplayNames = aiRealEstateDisplayNames()

            let parsed = try await AIExpenseParserService.shared.parse(
                text,
                availableMembers: familyNames,
                availableCreditCards: cardDisplayNames.map(\.display),
                availableBankAccounts: bankDisplayNames.map(\.display),
                availableRealEstates: realEstateDisplayNames.map(\.display)
            )
            // aiBusy 要保護到 aiCommitExpense（含其內部的 Apple Maps 地點查詢與
            // expenseStore/lifeStore/financeStore 寫入）完全結束為止，否則使用者能在
            // 上一筆記帳仍在背景寫入時就按住麥克風開始下一筆，兩個 commit 交錯執行，
            // toast 顯示順序錯亂，畫面卻顯示「未在忙碌」造成誤導。
            try await aiCommitExpense(
                parsed: parsed,
                cardDisplayNames: cardDisplayNames,
                bankDisplayNames: bankDisplayNames,
                realEstateDisplayNames: realEstateDisplayNames
            )
            aiBusy = false
        } catch {
            aiBusy = false
            aiShowToast("AI 解析失敗", detail: error.localizedDescription, isError: true)
        }
    }

    private struct AIAccountOption {
        let id: UUID
        let display: String
        /// 信用卡專用：底下連結的銀行帳戶 id
        let linkedBankId: UUID?
    }

    /// 信用卡清單：排除停用卡，顯示名稱包含品牌名 + 末四碼
    private func aiCreditCardDisplayNames() -> [AIAccountOption] {
        lifeStore.milestones.compactMap { ms in
            guard ms.category == .achievement,
                  ms.financeSubCategory == .creditCard,
                  ms.isDisabled != true else { return nil }
            let name = (ms.cardName?.isEmpty == false ? ms.cardName ?? ms.title : ms.title)
            var display = name
            if let last4 = ms.cardLastFour, !last4.isEmpty {
                display += " 末\(last4)"
            }
            return AIAccountOption(id: ms.id, display: display, linkedBankId: ms.linkedBankMilestoneId)
        }
    }

    /// 銀行帳戶清單：顯示名稱使用 bankName 或 title
    private func aiBankDisplayNames() -> [AIAccountOption] {
        lifeStore.milestones.compactMap { ms in
            guard ms.category == .achievement,
                  ms.financeSubCategory == .bank else { return nil }
            let name = (ms.bankName?.isEmpty == false ? ms.bankName ?? ms.title : ms.title)
            return AIAccountOption(id: ms.id, display: name, linkedBankId: nil)
        }
    }

    private struct AIRealEstateOption {
        let id: UUID
        let display: String
    }

    /// 房地產清單（排除已售出）：顯示名稱使用 RealEstate.name
    private func aiRealEstateDisplayNames() -> [AIRealEstateOption] {
        financeStore.realEstates.compactMap { re in
            guard re.soldDate == nil else { return nil }
            let name = re.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return AIRealEstateOption(id: re.id, display: name)
        }
    }

    @MainActor
    private func aiCommitExpense(
        parsed: ParsedAIExpense,
        cardDisplayNames: [AIAccountOption] = [],
        bankDisplayNames: [AIAccountOption] = [],
        realEstateDisplayNames: [AIRealEstateOption] = []
    ) async throws {
        let amount = parsed.amount ?? 0
        guard amount > 0 else {
            aiShowToast("找不到金額", detail: parsed.originalText ?? "AI 沒辨識出金額", isError: true)
            return
        }
        let category = AIVariableCategoryMapper.map(parsed.categoryRaw) ?? .other
        let title: String = {
            if let t = parsed.title, !t.isEmpty { return t }
            return category.rawValue
        }()
        // 飲食 / 娛樂 / 購物 / 日用品 / 醫療類支出做 Apple Maps 查詢，
        // 抓到座標後寫入 placeLatitude / Longitude / Address，讓美食地圖能標到
        let placeCategories: Set<VariableCategory> = [
            .food, .entertainment, .shopping, .dailyNecessities, .medical
        ]
        var placeAddress: String? = nil
        var placeLat: Double? = nil
        var placeLon: Double? = nil
        if placeCategories.contains(category), !title.isEmpty {
            if let mapItem = await aiLookupPlace(query: title) {
                placeAddress = mapItem.formattedAddress
                placeLat = mapItem.placemark.coordinate.latitude
                placeLon = mapItem.placemark.coordinate.longitude
            }
        }
        // AI 辨識到的扣款帳戶：對回 LifeMilestone（信用卡優先；無對應再找銀行）
        var linkedBankId: UUID? = nil
        var linkedCardId: UUID? = nil
        var matchedAccountDisplay: String? = nil
        if let acc = parsed.paymentAccount?.trimmingCharacters(in: .whitespaces),
           !acc.isEmpty {
            if let card = cardDisplayNames.first(where: { $0.display == acc }) {
                linkedCardId = card.id
                linkedBankId = card.linkedBankId
                matchedAccountDisplay = card.display
            } else if let bank = bankDisplayNames.first(where: { $0.display == acc }) {
                linkedBankId = bank.id
                matchedAccountDisplay = bank.display
            }
        }
        // 把本人也加進同行者：AI 通常只抽出對方（「我跟老婆」會抽出老婆），
        // 但用「我跟」「和」「陪」「帶」等措辭時，本人也在場
        let resolvedDiningMember = aiAppendSpeakerIfNeeded(parsed.diningMember)
        // 對回房地產 UUID 與子分類；若 AI 配到房地產，分類強制為 .realEstate
        var linkedRealEstateId: UUID? = nil
        var realEstateSubCat: RealEstateExpenseCategory? = nil
        var matchedRealEstateDisplay: String? = nil
        if let re = parsed.realEstate?.trimmingCharacters(in: .whitespaces),
           !re.isEmpty,
           let match = realEstateDisplayNames.first(where: { $0.display == re }) {
            linkedRealEstateId = match.id
            matchedRealEstateDisplay = match.display
            realEstateSubCat = RealEstateExpenseCategory(rawValue:
                parsed.realEstateSubCategory?.trimmingCharacters(in: .whitespaces) ?? ""
            ) ?? .other
        }
        let finalCategory: VariableCategory = (linkedRealEstateId != nil) ? .realEstate : category
        let exp = Expense(
            id: UUID(),
            title: title,
            amount: amount,
            date: Date(),
            expenseType: .variable,
            variableCategory: finalCategory,
            linkedRealEstateId: linkedRealEstateId,
            realEstateExpenseCategory: realEstateSubCat,
            note: parsed.note ?? "",
            diningMember: resolvedDiningMember,
            linkedBankMilestoneId: linkedBankId,
            linkedBankCurrency: linkedBankId.map { aiBankCurrency(for: $0) },
            linkedCreditCardMilestoneId: linkedCardId,
            placeAddress: placeAddress,
            placeLatitude: placeLat,
            placeLongitude: placeLon
        )
        expenseStore.add(exp)
        // AI 語音記帳原本只寫入 Expense 就結束，沒有比照 AddExpenseView.save() 呼叫
        // syncBankWithdrawal／syncRealEstateVariableExpense，導致銀行帳戶餘額、房地產支出
        // 章節帳實不符（AI 標了扣款帳戶／房地產，但對應清單與總額完全看不到這筆錢）；
        // 這裡補上對等的同步邏輯，供 AI 記帳流程使用。
        aiSyncBankWithdrawal(for: exp)
        aiSyncRealEstateExpense(for: exp)
        // 成功 toast
        // [美化] 金額改用全 App 共用的萬/億智慧量級（ntdWanString），對齊其餘頁面金額顯示規格，
        // 取代原本高額時會顯示成長串裸整數（如 NT$ 1200000）的寫法；純顯示調整，未變動實際存入的 exp.amount。
        var detailParts: [String] = ["\(finalCategory.rawValue)・\(amount.ntdWanString)"]
        if let m = resolvedDiningMember, !m.isEmpty { detailParts.append(m) }
        if let acc = matchedAccountDisplay { detailParts.append(acc) }
        if let re = matchedRealEstateDisplay {
            let subText = realEstateSubCat.map { "（\($0.rawValue)）" } ?? ""
            detailParts.append("\(re)\(subText)")
        }
        if placeLat != nil { detailParts.append("已標 美食地圖") }
        aiShowToast("已記一筆：\(title)", detail: detailParts.joined(separator: "・"), isError: false)
    }

    /// AI 記帳扣款帳戶預設幣別：沿用該銀行帳戶既有存款紀錄的幣別（比照 AddExpenseView.bankCurrencies(for:)），
    /// 而非寫死 "NT$"，避免外幣帳戶被記到錯誤幣別的桶子。
    private func aiBankCurrency(for bankId: UUID) -> String {
        guard let ms = lifeStore.milestones.first(where: { $0.id == bankId }) else { return "NT$" }
        let code = (ms.bankDeposits ?? []).first(where: { !$0.isWithdrawal })?.currencyCode
        return code ?? "NT$"
    }

    /// AI 記帳同步：寫入銀行扣款紀錄，比照 AddExpenseView.syncBankWithdrawal(for:previous:)（新記錄、無需移除舊連結）。
    @MainActor
    private func aiSyncBankWithdrawal(for expense: Expense) {
        guard expense.linkedCreditCardMilestoneId == nil,
              let bankId = expense.linkedBankMilestoneId,
              var ms = lifeStore.milestones.first(where: { $0.id == bankId }) else { return }
        var list = ms.bankDeposits ?? []
        list.append(BankDeposit(
            id: UUID(), date: expense.date, amount: expense.amount,
            currencyCode: expense.linkedBankCurrency ?? "NT$",
            isWithdrawal: true, linkedExpenseId: expense.id
        ))
        ms.bankDeposits = list
        lifeStore.update(ms)
    }

    /// AI 記帳同步：寫入房地產已支出／水電瓦斯／變動支出章節，比照 AddExpenseView.syncRealEstateVariableExpense(realEstateId:expenseId:amount:)。
    @MainActor
    private func aiSyncRealEstateExpense(for expense: Expense) {
        guard let reId = expense.linkedRealEstateId,
              var re = financeStore.realEstates.first(where: { $0.id == reId }) else { return }
        let category = expense.realEstateExpenseCategory ?? .other
        switch category {
        case .housePayment:
            re.paidItems.append(RealEstatePaidItem(
                id: UUID(), title: expense.title, amount: expense.amount,
                date: expense.date, linkedExpenseId: expense.id
            ))
        case .utility:
            let lower = expense.title.lowercased()
            let inferredType: UtilityType = {
                if lower.contains("水") || lower.contains("water") { return .water }
                if lower.contains("電") || lower.contains("electric") { return .electricity }
                if lower.contains("瓦斯") || lower.contains("gas") { return .gas }
                return .electricity
            }()
            re.utilityPayments.append(UtilityPayment(
                type: inferredType, date: expense.date, amount: expense.amount,
                note: expense.note, linkedExpenseId: expense.id
            ))
        default:
            re.variableExpenses.append(RealEstateVariableExpense(
                id: UUID(), category: category, name: expense.note,
                amount: expense.amount, date: expense.date, linkedExpenseId: expense.id
            ))
        }
        financeStore.update(re)
    }

    /// 取得本人姓名（中文優先，否則英文；都空 → 回空字串）
    private func aiSpeakerName() -> String {
        let c = lifeStore.profile.chineseName.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty { return c }
        return lifeStore.profile.englishName.trimmingCharacters(in: .whitespaces)
    }

    /// 若 AI 抽出的 diningMember 沒包含本人，幫忙補進去（最前面）
    private func aiAppendSpeakerIfNeeded(_ raw: String?) -> String? {
        let speaker = aiSpeakerName()
        // guard 失敗時以 trimmed 後的值判斷：原始 raw 可能是純空白字串，
        // 直接回傳未 trim 的值會讓 diningMember 存到無效空白內容。
        let trimmedRaw = raw?.trimmingCharacters(in: .whitespaces)
        guard !speaker.isEmpty,
              let trimmedRaw = trimmedRaw,
              !trimmedRaw.isEmpty
        else { return trimmedRaw?.isEmpty == true ? nil : trimmedRaw }
        let separators = CharacterSet(charactersIn: "、,，;； ")
        let existing = trimmedRaw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if existing.contains(speaker) { return trimmedRaw }
        return "\(speaker)、\(trimmedRaw)"
    }

    /// 用 MKLocalSearch 查 AI 給出的店家名稱，帶當前位置偏向
    private func aiLookupPlace(query: String) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region = LocationProvider.shared.searchRegion {
            request.region = region
        }
        request.resultTypes = .pointOfInterest
        let search = MKLocalSearch(request: request)
        return await withCheckedContinuation { cont in
            search.start { [search] resp, _ in
                _ = search  // 防止 ARC 在回調完成前提前釋放 search，導致 continuation 永不 resume
                cont.resume(returning: resp?.mapItems.first)
            }
        }
    }

    @MainActor
    private func aiShowToast(_ title: String, detail: String, isError: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            aiToast = AIToastInfo(title: title, detail: detail, isError: isError)
        }
        // 取消前一個倒數計時，避免連續呼叫時多個 Task 同時競爭清除 toast
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    aiToast = nil
                }
            }
        }
    }

    // [美化] 圖示改為漸層圓徽章（對齊全 App icon 圓規格：LinearGradient 填色 + stroke 邊框），
    // 取代原本裸 SF Symbol；卡片補 accent 色 overlay 邊框（0.75pt）與雙層陰影，
    // 成功/失敗兩色主題更醒目，對齊 AdminConsoleView 錯誤橫幅、OverviewView 卡片邊框設計語言。
    private func aiToastView(_ toast: AIToastInfo) -> some View {
        let accent: Color = toast.isError ? .orange : .green
        return VStack {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [accent.opacity(0.24), accent.opacity(0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 32, height: 32)
                    Circle()
                        .stroke(accent.opacity(0.30), lineWidth: 1)
                        .frame(width: 32, height: 32)
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(accent)
                        .font(.system(size: 15, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title).font(.subheadline.weight(.semibold))
                    Text(toast.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(accent.opacity(0.22), lineWidth: 0.75)
            )
            .shadow(color: accent.opacity(0.18), radius: 10, y: 4)
            .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - 頂部子功能列

    // UI美化：兩側漸層遮罩暗示橫向可捲動；allowsHitTesting false 確保捲動手勢不被阻擋
    private var topSubFeatureBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch currentMode {
                case .expense:
                    ForEach(ExpenseFeature.allCases) { f in
                        subFeaturePill(f.title, icon: f.icon,
                                       isSelected: expenseFeatureRaw == f.rawValue,
                                       locked: !FeatureGate.isFree(f) && !subscription.isPremium) {
                            expenseFeatureRaw = f.rawValue
                        }
                    }
                case .finance:
                    ForEach(FinanceFeature.allCases) { f in
                        subFeaturePill(f.title, icon: f.icon,
                                       isSelected: financeFeatureRaw == f.rawValue,
                                       locked: !FeatureGate.isFree(f) && !subscription.isPremium) {
                            financeFeatureRaw = f.rawValue
                        }
                    }
                case .life:
                    ForEach(lifeAvailableFeatures) { f in
                        // 「職涯」展開：父功能 + 橘色子功能 包在淡橘背景框
                        if f == .career && shouldExpandManagement {
                            careerGroupedPills
                        }
                        // 「家庭」展開：父功能 + 粉色子功能 包在淡粉背景框
                        else if f == .family && shouldExpandFamily {
                            familyGroupedPills
                        }
                        // 一般父分類 pill
                        else {
                            subFeaturePill(f.title, icon: f.icon,
                                           isSelected: isLifeParentSelected(f),
                                           locked: !FeatureGate.isFree(f) && !subscription.isPremium) {
                                lifeFeatureRaw = f.rawValue
                                if f == .career { managementFeatureRaw = "" }
                                if f == .family { familyMgmtFeatureRaw = "" }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
        // 左右兩側漸層遮罩，提示橫向可捲動
        .overlay(
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemBackground).opacity(0)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 14)
                Spacer()
                LinearGradient(
                    colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 14)
            }
            .allowsHitTesting(false)
        )
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.25))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    /// 父功能是否處於「自身被選取」狀態（沒有任何子功能被選中）
    private func isLifeParentSelected(_ f: LifeFeature) -> Bool {
        guard lifeFeatureRaw == f.rawValue else { return false }
        if f == .career { return managementFeature == nil }
        if f == .family { return familyMgmtFeature == nil }
        return true
    }

    /// 職涯父功能 + 橘色管理子功能，包在淡橘背景框
    private var careerGroupedPills: some View {
        HStack(spacing: 6) {
            subFeaturePill(LifeFeature.career.title, icon: LifeFeature.career.icon,
                           isSelected: isLifeParentSelected(.career),
                           locked: !FeatureGate.isFree(LifeFeature.career) && !subscription.isPremium) {
                lifeFeatureRaw = LifeFeature.career.rawValue
                managementFeatureRaw = ""
            }
            ForEach(ManagementFeature.allCases) { m in
                subFeaturePill(m.title, icon: m.icon,
                               isSelected: managementFeatureRaw == m.rawValue,
                               tint: .orange,
                               locked: !FeatureGate.isFree(m) && !subscription.isPremium) {
                    lifeFeatureRaw = LifeFeature.career.rawValue
                    managementFeatureRaw = m.rawValue
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color.orange.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    /// 家庭父功能 + 粉色子功能，包在淡粉背景框
    private var familyGroupedPills: some View {
        HStack(spacing: 6) {
            subFeaturePill(LifeFeature.family.title, icon: LifeFeature.family.icon,
                           isSelected: isLifeParentSelected(.family),
                           locked: !FeatureGate.isFree(LifeFeature.family) && !subscription.isPremium) {
                lifeFeatureRaw = LifeFeature.family.rawValue
                familyMgmtFeatureRaw = ""
            }
            ForEach(availableFamilyFeatures) { fm in
                subFeaturePill(fm.title, icon: fm.icon,
                               isSelected: familyMgmtFeatureRaw == fm.rawValue,
                               tint: .pink,
                               locked: !FeatureGate.isFree(fm) && !subscription.isPremium) {
                    lifeFeatureRaw = LifeFeature.family.rawValue
                    familyMgmtFeatureRaw = fm.rawValue
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color.pink.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.pink.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func subFeaturePill(_ title: String, icon: String, isSelected: Bool, tint: Color = .green, locked: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            isSettingsActive = false
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(.caption.weight(isSelected ? .semibold : .medium))
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isSelected ? tint : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(.primary.opacity(0.08), lineWidth: 0.6)
                    .opacity(isSelected ? 0 : 1)
            )
            .shadow(
                color: isSelected ? tint.opacity(0.38) : .clear,
                radius: 6, x: 0, y: 3
            )
            .scaleEffect(isSelected ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
    }

    // MARK: - 匯出進度條（細，壓在底部導覽上方，不影響介面）

    private var exportProgressBar: some View {
        VStack(spacing: 1) {
            HStack {
                Spacer()
                Text("匯出 \(Int(exportProgress.fraction * 100))%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 14)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.green.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.16, green: 0.74, blue: 0.50), Color(red: 0.07, green: 0.50, blue: 0.38)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(0, geo.size.width * exportProgress.fraction))
                        .shadow(color: Color.green.opacity(0.40), radius: 3, x: 0, y: 0)
                        .animation(.linear(duration: 0.2), value: exportProgress.fraction)
                }
            }
            .frame(height: 3.5)
        }
        .padding(.bottom, 1)
        .background(.ultraThinMaterial)
        .transition(.opacity)
    }

    // MARK: - 底部四按鈕

    // UI美化：傳入 tabBarNamespace 給各頁籤，讓 matchedGeometryEffect 可跨按鈕滑動
    private func bottomTabBar(namespace: Namespace.ID) -> some View {
        HStack(spacing: 0) {
            tabButton(mode: .expense, icon: "dollarsign.circle.fill", label: "收支", namespace: namespace)
            tabButton(mode: .finance, icon: "chart.pie.fill", label: "理財", namespace: namespace)
            tabButton(mode: .life, icon: "person.fill", label: "人生", namespace: namespace)
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
                    isSettingsActive = true
                }
            } label: {
                tabItemLabel(icon: "gearshape.fill", label: "設定", isActive: isSettingsActive, namespace: namespace)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.10), radius: 24, y: -8)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.18))
                .frame(height: 0.5),
            alignment: .top
        )
    }

    private func tabButton(mode: AppMode, icon: String, label: String, namespace: Namespace.ID) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
                appMode = mode.rawValue
                isSettingsActive = false
            }
        } label: {
            tabItemLabel(icon: icon, label: label, isActive: currentMode == mode && !isSettingsActive, namespace: namespace)
        }
        .buttonStyle(.plain)
    }

    // UI美化：matchedGeometryEffect(id:"activeTabIndicator") 讓選中膠囊背景在頁籤間平滑位移；
    //         active 圖示輕放大 1.05 增強視覺回饋；字級從 10 → 10.5 改善小字可讀性
    private func tabItemLabel(icon: String, label: String, isActive: Bool, namespace: Namespace.ID) -> some View {
        VStack(spacing: 3) {
            ZStack {
                if isActive {
                    // 選中時的膠囊指示器：漸層填色 + 細框 + matchedGeometryEffect 跨頁籤滑動
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.green.opacity(0.22), Color.green.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 54, height: 30)
                        .overlay(Capsule().stroke(Color.green.opacity(0.18), lineWidth: 0.75))
                        .matchedGeometryEffect(id: "activeTabIndicator", in: namespace)
                } else {
                    // 佔位透明膠囊，確保圖示對齊不跳動
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: 54, height: 30)
                }
                Image(systemName: icon)
                    .font(.system(size: 21, weight: isActive ? .semibold : .medium))
                    .symbolEffect(.bounce, value: isActive)
                    .scaleEffect(isActive ? 1.05 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isActive)
            }
            Text(label)
                .font(.system(size: 10.5, weight: isActive ? .semibold : .regular))
        }
        .foregroundStyle(isActive ? Color.green : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isActive)
    }

    // MARK: - 浮動新增按鈕

    private var floatingActionButton: some View {
        GeometryReader { geo in
            // 基本佈局常數
            let fabWidth: CGFloat = 130   // 顯示「新增收支」時的膠囊寬度（用於拖曳邊界）
            let fabHeight: CGFloat = 52
            let hPad: CGFloat = 20         // 距左/右邊距
            let bottomPad: CGFloat = 80    // 距下緣（避開底部 Tab Bar）
            let topMargin: CGFloat = 120   // 不可拖至此線以上（避開頂部子功能列）

            // 拖曳上下界（offset 相對於 bottom-right 自然錨點）
            let leftLimit  = -(geo.size.width  - fabWidth  - 2 * hPad)
            let topLimit   = -(geo.size.height - fabHeight - bottomPad - topMargin)

            let liveX = clamp(fabOffset.width  + fabDragOffset.width,  leftLimit, 0)
            let liveY = clamp(fabOffset.height + fabDragOffset.height, topLimit,  0)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    fabStack
                        .offset(x: liveX, y: liveY)
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    if showQuickAdd { showQuickAdd = false } // 拖曳時自動收起選單
                                    fabDragOffset = v.translation
                                }
                                .onEnded { v in
                                    let finalX = clamp(fabOffset.width  + v.translation.width,  leftLimit, 0)
                                    let finalY = clamp(fabOffset.height + v.translation.height, topLimit,  0)
                                    // 水平吸邊：靠近哪邊就吸過去
                                    let snappedX: CGFloat = finalX < (leftLimit / 2) ? leftLimit : 0
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                                        fabOffset = CGSize(width: snappedX, height: finalY)
                                        fabDragOffset = .zero
                                    }
                                }
                        )
                        .padding(.trailing, hPad)
                        .padding(.bottom, bottomPad)
                }
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    // UI美化：彈出選單加粗字重 + 更大內距 + 強化彩色陰影；主 FAB 雙層 shadow 加綠色光暈；
    //         transition 改用 asymmetric scale(anchor:.bottom) 讓選單從 FAB 方向彈出/縮回
    /// FAB + 彈出選單，獨立出來方便閱讀
    private var fabStack: some View {
        ZStack(alignment: .bottom) {
            if showQuickAdd {
                VStack(spacing: 10) {
                    Button {
                        showQuickAdd = false
                        showAddIncome = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("新增收入")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: .green.opacity(0.45), radius: 10, y: 5)
                    }

                    Button {
                        showQuickAdd = false
                        showAddExpense = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "minus.circle.fill")
                            Text("新增支出")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: .red.opacity(0.45), radius: 10, y: 5)
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.82, anchor: .bottom).combined(with: .opacity),
                    removal: .scale(scale: 0.82, anchor: .bottom).combined(with: .opacity)
                ))
                .padding(.bottom, 64)
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showQuickAdd.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showQuickAdd ? "xmark" : "plus")
                        .font(.title3.weight(.bold))
                        .rotationEffect(.degrees(showQuickAdd ? 45 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showQuickAdd)
                    if !showQuickAdd {
                        Text("新增收支")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, showQuickAdd ? 0 : 14)
                .frame(minWidth: 52, minHeight: 52)
                .background(showQuickAdd ? Color.secondary : Color.green)
                .clipShape(Capsule())
                // 深色基礎陰影 + 綠色光暈（展開時光暈消隱）
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .shadow(color: showQuickAdd ? .clear : Color.green.opacity(0.38), radius: 14, y: 6)
            }
        }
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(upper, max(lower, value))
    }

    // MARK: - 內容區

    @ViewBuilder
    private var contentView: some View {
        if isSettingsActive {
            SettingsView()
        } else {
            switch currentMode {
            case .expense: expenseContent
            case .finance: financeContent
            case .life: lifeContent
            }
        }
    }

    @ViewBuilder
    private var expenseContent: some View {
        switch expenseFeature {
        case .overview: OverviewView()
        case .income: IncomeView()
        case .variable: VariableExpenseView()
        case .fixed: FixedExpenseView()
        case .chart: ChartView()
        }
    }

    @ViewBuilder
    private var financeContent: some View {
        switch financeFeature {
        case .overview: FinanceOverviewView()
        case .insurance: SavingsInsuranceView()
        case .stock: StockView()
        case .vehicle: VehicleView()
        case .realEstate: RealEstateView()
        case .chart: FinanceChartView()
        }
    }

    @ViewBuilder
    private var lifeContent: some View {
        switch lifeFeature {
        case .overview: LifeOverviewView()
        case .resume: ResumeView()
        case .finance:
            if hasFinanceMilestones {
                LifeFinanceView()
            } else {
                LifeOverviewView()
            }
        case .career:
            // 有選子功能 → 顯示對應的管理 view；否則回到 CareerView
            if let m = managementFeature {
                switch m {
                case .calendar:     MyCalendarView()
                case .overview:     SubordinateOverviewView()
                case .subordinates: SubordinateView()
                case .businessCard: BusinessCardView()
                case .organization: OrganizationView()
                case .gradeTitle:   GradeTitleView()
                }
            } else if hasCareerMilestones {
                CareerView()
            } else {
                LifeOverviewView()
            }
        case .family:
            // 有選子功能 → 顯示配偶 / 兒女履歷；否則回到 FamilyView
            if let f = familyMgmtFeature {
                switch f {
                case .spouseResume:
                    if hasSpouse { SpouseResumeView() } else { FamilyView() }
                case .childrenResume:
                    if hasChildren { ChildrenResumeView() } else { FamilyView() }
                case .relativeResume:
                    if hasExtendedFamily { FamilyMembersResumeView() } else { FamilyView() }
                }
            } else if !lifeStore.familyMembers.isEmpty {
                FamilyView()
            } else {
                LifeOverviewView()
            }
        case .realEstate:
            if !financeStore.realEstates.isEmpty {
                LifeRealEstateView()
            } else {
                LifeOverviewView()
            }
        case .tax:
            TaxOverviewView()
        case .foodMap:
            FoodMapView()
        case .travelMap:
            TravelMapView()
        case .medicalMap:
            MedicalMapView()
        }
    }

    private var hasCareerMilestones: Bool {
        lifeStore.milestones.contains { $0.category == .career }
    }

    private var hasFinanceMilestones: Bool {
        lifeStore.milestones.contains { $0.category == .achievement }
    }

    private var lifeAvailableFeatures: [LifeFeature] {
        var list: [LifeFeature] = [.overview, .resume]
        if hasFinanceMilestones { list.append(.finance) }
        if hasCareerMilestones { list.append(.career) }
        if !lifeStore.familyMembers.isEmpty { list.append(.family) }
        if !financeStore.realEstates.isEmpty { list.append(.realEstate) }
        if hasTaxData { list.append(.tax) }
        if hasFoodMapData { list.append(.foodMap) }
        if hasTravelMapData { list.append(.travelMap) }
        if hasMedicalMapData { list.append(.medicalMap) }
        return list
    }

    /// 任一稅費 / 節稅紀錄、有房產或車輛（會產生年度稅）→ 顯示稅務頁
    private var hasTaxData: Bool {
        if expenseStore.expenses.contains(where: {
            $0.variableCategory == .tax || $0.variableCategory == .taxSaving ||
            ($0.expenseType == .fixed && $0.effectivelyTaxDeductible)
        }) { return true }
        if !financeStore.realEstates.isEmpty || !financeStore.vehicles.isEmpty { return true }
        return false
    }

    /// 任一飲食紀錄已附經緯度 → 顯示美食地圖頁
    private var hasFoodMapData: Bool {
        expenseStore.expenses.contains(where: {
            $0.variableCategory == .food && $0.placeLatitude != nil && $0.placeLongitude != nil
        })
    }

    /// 任一娛樂紀錄已附經緯度 → 顯示旅遊地圖頁
    private var hasTravelMapData: Bool {
        expenseStore.expenses.contains(where: {
            $0.variableCategory == .entertainment && $0.placeLatitude != nil && $0.placeLongitude != nil
        })
    }

    /// 有醫療支出、健康里程碑或已建立健康檔案 → 顯示醫療地圖頁
    private var hasMedicalMapData: Bool {
        if expenseStore.expenses.contains(where: { $0.variableCategory == .medical }) { return true }
        if lifeStore.milestones.contains(where: { $0.category == .health }) { return true }
        return !lifeStore.healthProfile.isEmpty
    }
}

#Preview {
    MainTabView()
        .environmentObject(ExpenseStore())
        .environmentObject(FinanceStore())
        .environmentObject(LifeStore())
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(EInvoiceSyncManager.shared)
}
