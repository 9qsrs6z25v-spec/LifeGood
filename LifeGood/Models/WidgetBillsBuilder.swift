import Foundation

// MARK: - 接下來要繳的快照（bills_v1.json）：記帳固定支出＋理財 FinanceUpcoming，45 天、去重（小工具 v2）
//
// 只屬於「LifeGood」target。由 G1 實作，規格見 scratchpad/widgets/v2/brief.md（G1-3）、judge §2.5、§3.2。
//
// 今天（含）到今天＋45 天之前，每一次要扣（或要領回）的錢，一次一筆：
//   • 理財：FinanceUpcoming.build（理財總覽「接下來 30 天」同一支）叫兩次——今天起、15 天後起——合併。
//     build 每個項目只給「下一次」，往後 15 天再叫一次才拿得到 45 天內的第二期。
//   • 記帳：每筆週期性固定支出用 nextFixedDueDate 往後找每一次；名字用 stopRowLabel（跟收支總覽同一套）。
//   • 去重：同一筆錢在記帳和理財各有一份（保單、房貸、車貸、停車月租…），理財已經列了的，
//     記帳那邊就不再列——排除保單的 linkedExpenseId、連到保單的記帳、沒賣的房子的房貸支出與每段的
//     linkedExpenseId、每台車（含已售出）VehicleFacts.ledgerExpenseIds。
//
// 只寫件數、**不寫合計**（台幣、美金加不出一個 App 裡找得到的數，judge §2.5）。
// 金額字：理財那幾件是 FinanceUpcoming.amount（App 已經組好），記帳那幾件用 MoneyFormat.short(ntdValue)。
// 規矩：只讀不寫；**不呼叫 FinanceOverviewData.build**（它會寫每月淨資產紀錄）。
//
// [v3] 每一筆多寫 lockTitle：鎖定畫面「下一筆要繳」關掉「顯示名稱」時的類別字（v3 brief G1-7）——
//      記帳固定支出寫分類（「訂閱服務」「電信費」…，沒分類或「其他」寫「固定支出」），
//      理財寫「保費」「保單滿期」「房貸」，車子照 VehicleUpcoming.kind 寫「車貸」「保養」「車子費用」。
//
// @MainActor：MoneyFormat 的 NumberFormatter 只在主執行緒用（跟寫手一樣）。

@MainActor
enum WidgetBillsBuilder {

    /// 清單涵蓋今天起幾天（App 兩週沒開也還有 30 天可以列）
    static let horizonDays = 45
    /// 第二次叫 FinanceUpcoming.build 往後推幾天
    static let financeShiftDays = 15
    /// 每次叫 FinanceUpcoming.build 看幾天
    static let financeWindowDays = 30
    /// 一筆固定支出最多展開幾次（防呆：週期資料壞掉時不要跑不停）
    private static let maxOccurrences = 60

    /// 理財那幾件的色條（mock_spec bills-medium palette）：淺色、深色
    private static let mortgageTint: (UInt32, UInt32) = (0x6B4BE0, 0xB79CFF)
    private static let premiumTint: (UInt32, UInt32) = (0x2F5BD8, 0x8DB7FF)
    private static let maturityTint: (UInt32, UInt32) = (0x177A44, 0x5BD99A)
    private static let vehicleTint: (UInt32, UInt32) = (0x138A7E, 0x7FE3D0)

    static func snapshot(expense: ExpenseStore, finance: FinanceStore, now: Date,
                         calendar cal: Calendar = .current) -> WidgetBillsSnapshot {
        let today = cal.startOfDay(for: now)
        let horizonEnd = cal.date(byAdding: .day, value: horizonDays, to: today) ?? today

        let index = FinanceLoanIndex(finance: finance, expense: expense, now: now)
        var items = financeBills(expense: expense, finance: finance, index: index,
                                 now: now, today: today, horizonEnd: horizonEnd, calendar: cal)
        let excluded = excludedExpenseIds(expense: expense, finance: finance, index: index)
        items += ledgerBills(expense: expense, excluded: excluded, today: today,
                             horizonEnd: horizonEnd, calendar: cal)
        items.sort { a, b in
            if a.dueDate != b.dueDate { return a.dueDate < b.dueDate }
            if a.title != b.title { return a.title < b.title }
            return a.id < b.id
        }
        return WidgetBillsSnapshot(generatedAt: now,
                                   dataDay: WidgetDateText.dayKey(now),
                                   horizonEnd: horizonEnd,
                                   items: items)
    }

    // MARK: - 理財（FinanceUpcoming）

    private static func financeBills(expense: ExpenseStore, finance: FinanceStore, index: FinanceLoanIndex,
                                     now: Date, today: Date, horizonEnd: Date,
                                     calendar cal: Calendar) -> [WidgetBill] {
        let first = FinanceUpcoming.build(finance: finance, expense: expense,
                                          houses: index.houses, vehicles: index.vehicles,
                                          now: now, days: financeWindowDays)
        let shifted = cal.date(byAdding: .day, value: financeShiftDays, to: today) ?? today
        let index2 = FinanceLoanIndex(finance: finance, expense: expense, now: shifted)
        let second = FinanceUpcoming.build(finance: finance, expense: expense,
                                           houses: index2.houses, vehicles: index2.vehicles,
                                           now: shifted, days: financeWindowDays)
        let indexes = [index, index2]

        var seen = Set<String>()
        var out: [WidgetBill] = []
        for u in first + second {
            let due = cal.startOfDay(for: u.date)
            guard due >= today, due < horizonEnd else { continue }
            let key = u.id + "@" + WidgetDateText.dayKey(due)
            guard seen.insert(key).inserted else { continue }
            out.append(financeBill(u, id: key, due: due,
                                   link: financeLink(u, finance: finance, indexes: indexes),
                                   lockTitle: financeLockTitle(u, finance: finance, indexes: indexes)))
        }
        return out
    }

    private static func financeBill(_ u: FinanceUpcoming, id: String, due: Date, link: URL,
                                    lockTitle: String) -> WidgetBill {
        let kind: WidgetBillKind
        let tint: (UInt32, UInt32)
        switch u.kind {
        case .premium:
            kind = .premium
            tint = premiumTint
        case .maturity:
            kind = .maturity
            tint = maturityTint
        case .mortgage:
            kind = .mortgage
            tint = mortgageTint
        case .vehicle:
            kind = .vehicle
            tint = vehicleTint
        }
        return WidgetBill(id: id, kind: kind, title: u.title, detail: u.detail, dueDate: due,
                          amountText: u.amount, isIncome: u.isIncome, icon: u.icon,
                          tint: tint.0, tintDark: tint.1, link: link.absoluteString,
                          lockTitle: lockTitle)
    }

    /// [v3] 理財那幾件的類別字：保費／保單滿期／房貸；車子照 VehicleUpcoming.kind（找不到「車子費用」）
    private static func financeLockTitle(_ u: FinanceUpcoming, finance: FinanceStore,
                                         indexes: [FinanceLoanIndex]) -> String {
        switch u.kind {
        case .premium:
            return "保費"
        case .maturity:
            return "保單滿期"
        case .mortgage:
            return "房貸"
        case .vehicle:
            guard let k = vehicleUpcomingKind(ofUpcomingItem: u.id, finance: finance, indexes: indexes) else {
                return "車子費用"
            }
            switch k {
            case .loan:
                return "車貸"
            case .maintenance:
                return "保養"
            case .fixed:
                return "車子費用"
            }
        }
    }

    /// FinanceUpcoming 沒帶來源 id，照它的 id 格式自己查（FinanceInsights.swift FinanceUpcoming.build）：
    /// 保費「p-<保單 UUID>」、滿期「m-<保單 UUID>」→ 那張保單；房貸「r-<段 id>」→ 有那一段的房子；
    /// 車子「v-<VehicleUpcoming.id>」→ upcoming 裡有它的那台車。找不到退回固定支出頁。
    private static func financeLink(_ u: FinanceUpcoming, finance: FinanceStore,
                                    indexes: [FinanceLoanIndex]) -> URL {
        switch u.kind {
        case .premium, .maturity:
            if let id = UUID(uuidString: String(u.id.dropFirst(2))) {
                return WidgetLink.financeInsurance(id)
            }
        case .mortgage:
            if let houseId = houseId(ofSegmentItem: u.id, finance: finance, indexes: indexes) {
                return WidgetLink.financeHouse(houseId)
            }
        case .vehicle:
            if let carId = vehicleId(ofUpcomingItem: u.id, finance: finance, indexes: indexes) {
                return WidgetLink.financeVehicle(carId)
            }
        }
        return WidgetLink.fixedExpenses
    }

    /// 「r-<段 id>」是哪一間房子的（照 finance.realEstates 的順序找，結果固定）
    private static func houseId(ofSegmentItem itemId: String, finance: FinanceStore,
                                indexes: [FinanceLoanIndex]) -> UUID? {
        for re in finance.realEstates {
            for idx in indexes {
                guard let facts = idx.houses[re.id] else { continue }
                if facts.segments.contains(where: { "r-\($0.id)" == itemId }) { return re.id }
            }
        }
        return nil
    }

    /// 「v-<VehicleUpcoming.id>」是哪一台車的（照 finance.vehicles 的順序找：
    /// FinanceUpcoming.build 兩台都有同一件時也只列在第一台）
    private static func vehicleId(ofUpcomingItem itemId: String, finance: FinanceStore,
                                  indexes: [FinanceLoanIndex]) -> UUID? {
        for v in finance.vehicles {
            for idx in indexes {
                guard let facts = idx.vehicles[v.id] else { continue }
                if facts.upcoming.contains(where: { "v-" + $0.id == itemId }) { return v.id }
            }
        }
        return nil
    }

    /// [v3] 「v-<VehicleUpcoming.id>」是哪一種（車貸／保養／其他定期支出）。查法同 vehicleId(ofUpcomingItem:)
    private static func vehicleUpcomingKind(ofUpcomingItem itemId: String, finance: FinanceStore,
                                            indexes: [FinanceLoanIndex]) -> VehicleUpcoming.Kind? {
        for v in finance.vehicles {
            for idx in indexes {
                guard let facts = idx.vehicles[v.id] else { continue }
                if let up = facts.upcoming.first(where: { "v-" + $0.id == itemId }) { return up.kind }
            }
        }
        return nil
    }

    // MARK: - 記帳（週期性固定支出）

    /// 理財那邊已經列了的記帳支出（同一筆錢只列一次）
    private static func excludedExpenseIds(expense e: ExpenseStore, finance f: FinanceStore,
                                           index: FinanceLoanIndex) -> Set<UUID> {
        var ids = Set<UUID>()
        // 保單：保單上記的那筆＋記帳那邊連到還存在的保單的
        let insuranceIds = Set(f.insurances.map(\.id))
        for ins in f.insurances {
            if let id = ins.linkedExpenseId { ids.insert(id) }
        }
        for ex in e.expenses {
            if let insId = ex.linkedInsuranceId, insuranceIds.contains(insId) { ids.insert(ex.id) }
        }
        // 沒賣的房子：房貸支出（房貸項目＋舊版單筆連結＋只在記帳那邊連過來的）＋每一段連到的那筆
        for re in f.realEstates where !re.isSold {
            ids.formUnion(RealEstateSale.mortgageExpenseIds(of: re, expenses: e.expenses))
            if let facts = index.houses[re.id] {
                ids.formUnion(facts.segments.compactMap(\.linkedExpenseId))
            }
        }
        // 每台車（含已售出：賣了還在扣的停車月租、車貸，理財照樣列在那台車底下）
        for v in f.vehicles {
            if let facts = index.vehicles[v.id] {
                ids.formUnion(facts.ledgerExpenseIds)
            }
        }
        return ids
    }

    private static func ledgerBills(expense: ExpenseStore, excluded: Set<UUID>, today: Date,
                                    horizonEnd: Date, calendar cal: Calendar) -> [WidgetBill] {
        var out: [WidgetBill] = []
        for ex in expense.expenses where ex.isRecurringFixed && !excluded.contains(ex.id) {
            var next = ex.nextFixedDueDate(onOrAfter: today, calendar: cal)
            var n = 0
            while let due = next, n < maxOccurrences {
                let dueDay = cal.startOfDay(for: due)
                guard dueDay < horizonEnd else { break }
                out.append(ledgerBill(ex, due: dueDay, expense: expense))
                n += 1
                guard let after = cal.date(byAdding: .day, value: 1, to: dueDay) else { break }
                next = ex.nextFixedDueDate(onOrAfter: after, calendar: cal)
            }
        }
        return out
    }

    private static func ledgerBill(_ ex: Expense, due: Date, expense: ExpenseStore) -> WidgetBill {
        let theme = MoneyArtTheme.of(ex.fixedCategory)
        return WidgetBill(id: "x-" + ex.id.uuidString + "@" + WidgetDateText.dayKey(due),
                          kind: .fixed,
                          title: ex.stopRowLabel(suppressing: []).primary,
                          detail: ex.recurrence?.rawValue,
                          dueDate: due,
                          amountText: MoneyFormat.short(expense.ntdValue(of: ex)),
                          isIncome: false,
                          icon: ex.categoryIcon,
                          tint: theme.tint,
                          tintDark: theme.top,
                          link: WidgetLink.fixedExpense(ex.id).absoluteString,
                          lockTitle: ledgerLockTitle(ex.fixedCategory))
    }

    /// [v3] 記帳固定支出的類別字：分類名（「訂閱服務」「電信費」「貸款」「保險」「房租」「水電瓦斯」「管理費」）；
    /// 沒分類或「其他」寫「固定支出」
    private static func ledgerLockTitle(_ category: FixedCategory?) -> String {
        guard let category, category != .other else { return "固定支出" }
        return category.rawValue
    }
}
