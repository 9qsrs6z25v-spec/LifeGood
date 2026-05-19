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
    case overview, resume, finance, career, family, realEstate, tax, foodMap
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
        lifeStore.milestones
            .filter { $0.category == .career }
            .sorted { $0.date > $1.date }
            .first(where: {
                let sub = $0.careerSubCategory
                return sub == .join || sub == .promote || sub == .transfer || sub == .demote
            })?.isManagerial == true
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
    @State private var aiToast: AIToastInfo?
    @State private var aiBusy = false
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
                // 佔位用：與底部 tab bar 同高，保證內容區不會被 tab bar 蓋住
                bottomTabBar
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
                bottomTabBar
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
                .shadow(color: Color.purple.opacity(listening ? 0.7 : 0.35),
                        radius: listening ? 14 : 8, y: 4)
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
                    Image(systemName: listening ? "waveform" : "mic.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 24, weight: .bold))
                        .scaleEffect(listening ? 1.1 : 1.0)
                }
            }
        }
        .contentShape(Circle())
        // 按住開始 / 放開停止
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !speechRecognizer.isRecording, !aiBusy else { return }
                    Task { await aiStartRecording() }
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
            let myName = memberName(lifeStore.profile.chineseName, lifeStore.profile.englishName)
            if !myName.isEmpty { familyNames.insert(myName, at: 0) }

            // 蒐集信用卡 / 銀行帳戶顯示名稱，讓 AI 從清單挑選扣款帳戶
            let cardDisplayNames = aiCreditCardDisplayNames()
            let bankDisplayNames = aiBankDisplayNames()

            let parsed = try await AIExpenseParserService.shared.parse(
                text,
                availableMembers: familyNames,
                availableCreditCards: cardDisplayNames.map(\.display),
                availableBankAccounts: bankDisplayNames.map(\.display)
            )
            aiBusy = false
            try await aiCommitExpense(
                parsed: parsed,
                cardDisplayNames: cardDisplayNames,
                bankDisplayNames: bankDisplayNames
            )
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
            let name = (ms.cardName?.isEmpty == false ? ms.cardName! : ms.title)
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
            let name = (ms.bankName?.isEmpty == false ? ms.bankName! : ms.title)
            return AIAccountOption(id: ms.id, display: name, linkedBankId: nil)
        }
    }

    @MainActor
    private func aiCommitExpense(
        parsed: ParsedAIExpense,
        cardDisplayNames: [AIAccountOption] = [],
        bankDisplayNames: [AIAccountOption] = []
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
        let exp = Expense(
            id: UUID(),
            title: title,
            amount: amount,
            date: Date(),
            expenseType: .variable,
            variableCategory: category,
            note: parsed.note ?? "",
            diningMember: parsed.diningMember,
            linkedBankMilestoneId: linkedBankId,
            linkedBankCurrency: linkedBankId == nil ? nil : "NT$",
            linkedCreditCardMilestoneId: linkedCardId,
            placeAddress: placeAddress,
            placeLatitude: placeLat,
            placeLongitude: placeLon
        )
        expenseStore.add(exp)
        // 成功 toast
        var detailParts: [String] = ["\(category.rawValue)・NT$ \(Int(amount))"]
        if let m = parsed.diningMember, !m.isEmpty { detailParts.append(m) }
        if let acc = matchedAccountDisplay { detailParts.append(acc) }
        if placeLat != nil { detailParts.append("已標 美食地圖") }
        aiShowToast("已記一筆：\(title)", detail: detailParts.joined(separator: "・"), isError: false)
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
            search.start { resp, _ in
                cont.resume(returning: resp?.mapItems.first)
            }
        }
    }

    @MainActor
    private func aiShowToast(_ title: String, detail: String, isError: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            aiToast = AIToastInfo(title: title, detail: detail, isError: isError)
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    aiToast = nil
                }
            }
        }
    }

    private func aiToastView(_ toast: AIToastInfo) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(toast.isError ? Color.orange : Color.green)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title).font(.subheadline.weight(.semibold))
                    Text(toast.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - 頂部子功能列

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
                Text(title).font(.caption.weight(.medium))
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isSelected ? tint : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部四按鈕

    private var bottomTabBar: some View {
        HStack {
            tabButton(mode: .expense, icon: "dollarsign.circle.fill", label: "收支")
            tabButton(mode: .finance, icon: "chart.pie.fill", label: "理財")
            tabButton(mode: .life, icon: "person.fill", label: "人生")
            Button {
                isSettingsActive = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "gearshape.fill").font(.system(size: 20))
                    Text("設定").font(.system(size: 10))
                }
                .foregroundStyle(isSettingsActive ? Color.green : Color.secondary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8).padding(.bottom, 6)
        .background(
            Color(.systemBackground).shadow(color: .black.opacity(0.08), radius: 4, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(mode: AppMode, icon: String, label: String) -> some View {
        Button {
            appMode = mode.rawValue
            isSettingsActive = false
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 10))
            }
            .foregroundStyle(currentMode == mode && !isSettingsActive ? Color.green : Color.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: .green.opacity(0.3), radius: 6, y: 3)
                    }

                    Button {
                        showQuickAdd = false
                        showAddExpense = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "minus.circle.fill")
                            Text("新增支出")
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: .red.opacity(0.3), radius: 6, y: 3)
                    }
                }
                .transition(.scale.combined(with: .opacity))
                .padding(.bottom, 64)
            }

            Button {
                withAnimation(.spring(duration: 0.3)) { showQuickAdd.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showQuickAdd ? "xmark" : "plus")
                        .font(.title3.weight(.bold))
                        .rotationEffect(.degrees(showQuickAdd ? 45 : 0))
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
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
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
        return list
    }

    /// 任一稅費 / 節稅紀錄、有房產或車輛（會產生年度稅）→ 顯示稅務頁
    private var hasTaxData: Bool {
        if expenseStore.expenses.contains(where: {
            $0.variableCategory == .tax || $0.variableCategory == .taxSaving
        }) { return true }
        if expenseStore.expenses.contains(where: {
            $0.expenseType == .fixed && $0.effectivelyTaxDeductible
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
}

#Preview {
    MainTabView()
        .environmentObject(ExpenseStore())
        .environmentObject(FinanceStore())
        .environmentObject(LifeStore())
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(EInvoiceSyncManager.shared)
}
