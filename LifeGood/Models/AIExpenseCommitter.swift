import Foundation
import MapKit

// MARK: - AI 記帳存檔（小工具 v3：從 MainTabView 抽出來，浮動麥克風與「說一句」共用一份）
//
// 只屬於「LifeGood」target。由 G1 實作，規格見 scratchpad/widgets/v3/brief.md 的 G1-1。
//
// 一句話（語音辨識的字）→ AIExpenseParserService 解析 → 建 Expense、存檔、同步銀行扣款與房地產章節 →
// 回傳要顯示的提示（成功「已記一筆：午餐」／失敗「AI 解析失敗」「找不到金額」）。
// 內容是 v3 之前 MainTabView 的 aiFinishRecording（aiBusy = true 之後那一段）＋aiCommitExpense 與它的
// 輔助函式，**逐字搬過來、行為不變**；MainTabView 的按住講、放開停改呼叫這裡。
//
// 型別：AIExpenseOutcome、AIExpenseCommitter（@MainActor enum）；檔內小零件 private。
//
// 搬家時只改了三件事（其餘一個字都沒動）：
//   • lifeStore／financeStore／expenseStore → 參數 life／finance／expense
//   • aiShowToast(…) → return AIExpenseOutcome(…)（同樣的字，由呼叫的人決定怎麼顯示）
//   • 函式去掉 ai 前綴、變成 private static；兩個 struct 收進這個 enum 裡當 private 型別

/// AI 記帳的結果提示（浮動麥克風的 toast、說一句的結果卡都用這一份字）
struct AIExpenseOutcome: Equatable {
    let title: String
    let detail: String
    let isError: Bool
}

@MainActor
enum AIExpenseCommitter {

    /// 一句話 → AI 解析 → 存檔（含銀行扣款、房地產章節同步、美食地圖查詢）→ 要顯示的提示。
    /// text 由呼叫的人去頭尾空白、確定不是空的（空的提示字兩邊不一樣，各自處理）。
    static func record(text: String, expense: ExpenseStore, life: LifeStore,
                       finance: FinanceStore) async -> AIExpenseOutcome {
        do {
            // 把家庭成員姓名與本人名字一起送給 AI，讓它從固定清單選同行者
            // 優先用中文姓名，沒填才用英文姓名
            func memberName(_ chinese: String, _ english: String) -> String {
                let c = chinese.trimmingCharacters(in: .whitespaces)
                if !c.isEmpty { return c }
                return english.trimmingCharacters(in: .whitespaces)
            }
            var familyNames: [String] = life.familyMembers
                .map { memberName($0.chineseName, $0.englishName) }
                .filter { !$0.isEmpty }
            let myName = speakerName(life: life)
            if !myName.isEmpty { familyNames.insert(myName, at: 0) }

            // 蒐集信用卡 / 銀行帳戶 / 房地產顯示名稱，讓 AI 從清單挑選關聯
            let cardDisplayNames = creditCardOptions(life: life)
            let bankDisplayNames = bankOptions(life: life)
            let realEstateDisplayNames = realEstateOptions(finance: finance)

            let parsed = try await AIExpenseParserService.shared.parse(
                text,
                availableMembers: familyNames,
                availableCreditCards: cardDisplayNames.map(\.display),
                availableBankAccounts: bankDisplayNames.map(\.display),
                availableRealEstates: realEstateDisplayNames.map(\.display)
            )
            // 呼叫的人（浮動麥克風的 aiBusy、說一句的 .working）要保護到這裡回來為止：commit 含
            // Apple Maps 地點查詢與 expense／life／finance 寫入，兩筆交錯執行提示順序會錯亂。
            return await commit(
                parsed: parsed,
                expense: expense,
                life: life,
                finance: finance,
                cards: cardDisplayNames,
                banks: bankDisplayNames,
                estates: realEstateDisplayNames
            )
        } catch {
            return AIExpenseOutcome(title: "AI 解析失敗", detail: error.localizedDescription, isError: true)
        }
    }

    // MARK: - 給 AI 挑的清單

    private struct AccountOption {
        let id: UUID
        let display: String
        /// 信用卡專用：底下連結的銀行帳戶 id
        let linkedBankId: UUID?
    }

    /// 信用卡清單：排除停用卡，顯示名稱包含品牌名 + 末四碼
    private static func creditCardOptions(life: LifeStore) -> [AccountOption] {
        life.milestones.compactMap { ms in
            guard ms.category == .achievement,
                  ms.financeSubCategory == .creditCard,
                  ms.isDisabled != true else { return nil }
            let name = (ms.cardName?.isEmpty == false ? ms.cardName ?? ms.title : ms.title)
            var display = name
            if let last4 = ms.cardLastFour, !last4.isEmpty {
                display += " 末\(last4)"
            }
            return AccountOption(id: ms.id, display: display, linkedBankId: ms.linkedBankMilestoneId)
        }
    }

    /// 銀行帳戶清單：顯示名稱使用 bankName 或 title
    private static func bankOptions(life: LifeStore) -> [AccountOption] {
        life.milestones.compactMap { ms in
            guard ms.category == .achievement,
                  ms.financeSubCategory == .bank else { return nil }
            let name = (ms.bankName?.isEmpty == false ? ms.bankName ?? ms.title : ms.title)
            return AccountOption(id: ms.id, display: name, linkedBankId: nil)
        }
    }

    private struct RealEstateOption {
        let id: UUID
        let display: String
    }

    /// 房地產清單（排除已售出）：顯示名稱使用 RealEstate.name
    private static func realEstateOptions(finance: FinanceStore) -> [RealEstateOption] {
        finance.realEstates.compactMap { re in
            guard re.soldDate == nil else { return nil }
            let name = re.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return RealEstateOption(id: re.id, display: name)
        }
    }

    // MARK: - 存檔

    private static func commit(
        parsed: ParsedAIExpense,
        expense: ExpenseStore,
        life: LifeStore,
        finance: FinanceStore,
        cards cardDisplayNames: [AccountOption],
        banks bankDisplayNames: [AccountOption],
        estates realEstateDisplayNames: [RealEstateOption]
    ) async -> AIExpenseOutcome {
        let amount = parsed.amount ?? 0
        guard amount > 0 else {
            return AIExpenseOutcome(title: "找不到金額", detail: parsed.originalText ?? "AI 沒辨識出金額", isError: true)
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
            if let mapItem = await lookupPlace(query: title) {
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
        let resolvedDiningMember = appendSpeakerIfNeeded(parsed.diningMember, life: life)
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
            linkedBankCurrency: linkedBankId.map { bankCurrency(for: $0, life: life) },
            linkedCreditCardMilestoneId: linkedCardId,
            placeAddress: placeAddress,
            placeLatitude: placeLat,
            placeLongitude: placeLon
        )
        expense.add(exp)
        // AI 語音記帳原本只寫入 Expense 就結束，沒有比照 AddExpenseView.save() 呼叫
        // syncBankWithdrawal／syncRealEstateVariableExpense，導致銀行帳戶餘額、房地產支出
        // 章節帳實不符（AI 標了扣款帳戶／房地產，但對應清單與總額完全看不到這筆錢）；
        // 這裡補上對等的同步邏輯，供 AI 記帳流程使用。
        // [v25.562] 扣外幣子帳戶要換匯（跟記帳頁同一支 FinanceRates.bankAmount）；expense 是 ExpenseStore、exp 是這筆支出
        syncBankWithdrawal(for: exp, life: life, rates: FinanceRates(expense), ntd: expense.ntdValue(of: exp))
        syncRealEstateExpense(for: exp, finance: finance)
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
        return AIExpenseOutcome(title: "已記一筆：\(title)", detail: detailParts.joined(separator: "・"), isError: false)
    }

    /// AI 記帳扣款帳戶預設幣別：沿用該銀行帳戶既有存款紀錄的幣別（比照 AddExpenseView.bankCurrencies(for:)），
    /// 而非寫死 "NT$"，避免外幣帳戶被記到錯誤幣別的桶子。
    private static func bankCurrency(for bankId: UUID, life: LifeStore) -> String {
        guard let ms = life.milestones.first(where: { $0.id == bankId }) else { return "NT$" }
        let code = (ms.bankDeposits ?? []).first(where: { !$0.isWithdrawal })?.currencyCode
        return code ?? "NT$"
    }

    /// AI 記帳同步：寫入銀行扣款紀錄，比照 AddExpenseView.syncBankWithdrawal(for:previous:)（新記錄、無需移除舊連結）。
    /// [v25.562] 金額、幣別走 FinanceRates.bankAmount：記帳金額是台幣，扣「玉山・美金」以前直接寫成「美金 320」，
    /// 現在換成美金 10.00；查不到匯率寫進這個帳戶的台幣那一格。ntd 由呼叫端用 ExpenseStore.ntdValue(of:) 算好。
    private static func syncBankWithdrawal(for expense: Expense, life: LifeStore, rates: FinanceRates, ntd: Double) {
        guard expense.linkedCreditCardMilestoneId == nil,
              let bankId = expense.linkedBankMilestoneId,
              var ms = life.milestones.first(where: { $0.id == bankId }) else { return }
        let withdrawal = rates.bankAmount(of: expense, ntd: ntd)
        var list = ms.bankDeposits ?? []
        list.append(BankDeposit(
            id: UUID(), date: expense.date, amount: withdrawal.amount,
            currencyCode: withdrawal.code,
            isWithdrawal: true, linkedExpenseId: expense.id
        ))
        ms.bankDeposits = list
        life.update(ms)
    }

    /// AI 記帳同步：寫入房地產已支出／水電瓦斯／變動支出章節，比照 AddExpenseView.syncRealEstateVariableExpense(realEstateId:expenseId:amount:)。
    private static func syncRealEstateExpense(for expense: Expense, finance: FinanceStore) {
        guard let reId = expense.linkedRealEstateId,
              var re = finance.realEstates.first(where: { $0.id == reId }) else { return }
        let category = expense.realEstateExpenseCategory ?? .other
        switch category {
        case .housePayment:
            re.paidItems.append(RealEstatePaidItem(
                id: UUID(), title: expense.title, amount: expense.amount,
                date: expense.date, linkedExpenseId: expense.id
            ))
        case .utility:
            // [v25.530] 跟記帳頁共用同一套判斷（先拿掉房子名稱，「水岸花園 電費」才不會被當成水費）
            let inferredType = guessUtilityType(title: expense.title, note: expense.note, estateName: re.name)
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
        finance.update(re)
    }

    // MARK: - 同行者

    /// 取得本人姓名（中文優先，否則英文；都空 → 回空字串）
    private static func speakerName(life: LifeStore) -> String {
        let c = life.profile.chineseName.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty { return c }
        return life.profile.englishName.trimmingCharacters(in: .whitespaces)
    }

    /// 若 AI 抽出的 diningMember 沒包含本人，幫忙補進去（最前面）
    private static func appendSpeakerIfNeeded(_ raw: String?, life: LifeStore) -> String? {
        let speaker = speakerName(life: life)
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

    // MARK: - 美食地圖

    /// 用 MKLocalSearch 查 AI 給出的店家名稱，帶當前位置偏向
    private static func lookupPlace(query: String) async -> MKMapItem? {
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
}
