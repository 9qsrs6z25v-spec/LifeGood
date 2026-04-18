import Foundation

// MARK: - 統一匯出結構（記帳 + 理財 + 人生）

struct UnifiedExport: Codable {
    var version: String
    var exportDate: Date
    var expense: ExpenseBundle
    var finance: FinanceBundle
    var life: LifeBundle

    struct ExpenseBundle: Codable {
        var expenses: [Expense]
        var incomes: [Income]
    }

    struct FinanceBundle: Codable {
        var insurances: [SavingsInsurance]
        var stocks: [Stock]
        var vehicles: [Vehicle]
        var realEstates: [RealEstate]
    }

    struct LifeBundle: Codable {
        var milestones: [LifeMilestone]
        var relationships: [Relationship]
        var pets: [Pet]
        var schedules: [Schedule]
    }

    static func build(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) -> UnifiedExport {
        UnifiedExport(
            version: "2",
            exportDate: Date(),
            expense: ExpenseBundle(expenses: expense.expenses, incomes: expense.incomes),
            finance: FinanceBundle(
                insurances: finance.insurances,
                stocks: finance.stocks,
                vehicles: finance.vehicles,
                realEstates: finance.realEstates
            ),
            life: LifeBundle(
                milestones: life.milestones,
                relationships: life.relationships,
                pets: life.pets,
                schedules: life.schedules
            )
        )
    }
}

// MARK: - 匯出器

enum UnifiedExporter {
    static func exportJSON(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) -> Data {
        let payload = UnifiedExport.build(expense: expense, finance: finance, life: life)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(payload)) ?? Data()
    }

    static func exportCSV(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) -> String {
        let iso = ISO8601DateFormatter()
        var csv = ""

        // 記帳 - 支出
        csv += "## 支出 (Expenses)\n"
        csv += "id,title,amount,date,type,category,recurrence,note\n"
        for e in expense.expenses.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                e.id.uuidString,
                esc(e.title),
                String(format: "%.2f", e.amount),
                iso.string(from: e.date),
                e.expenseType.rawValue,
                e.categoryName,
                e.recurrence?.rawValue ?? "",
                esc(e.note)
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        csv += "\n"

        // 記帳 - 收入
        csv += "## 收入 (Incomes)\n"
        csv += "id,title,amount,date,category,period,isFixedSalary,note\n"
        for i in expense.incomes.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                i.id.uuidString,
                esc(i.title),
                String(format: "%.2f", i.amount),
                iso.string(from: i.date),
                i.category.rawValue,
                i.period.rawValue,
                i.isFixedSalary ? "Y" : "N",
                esc(i.note)
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        csv += "\n"

        // 理財 - 儲蓄險
        csv += "## 儲蓄險 (Savings Insurances)\n"
        csv += "id,name,company,currency,premiumAmount,paymentPeriod,annualRate,startDate,maturityDate,expectedReturn,currentValue,note\n"
        for s in finance.insurances {
            let fields: [String] = [
                s.id.uuidString,
                esc(s.name),
                esc(s.company),
                s.currency.rawValue,
                String(format: "%.2f", s.premiumAmount),
                s.paymentPeriod.rawValue,
                String(format: "%.4f", s.annualRate),
                iso.string(from: s.startDate),
                iso.string(from: s.maturityDate),
                String(format: "%.2f", s.expectedReturn),
                String(format: "%.2f", s.currentValue),
                esc(s.note)
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        csv += "\n"

        // 理財 - 股票
        csv += "## 股票 (Stocks)\n"
        csv += "id,symbol,name,purchaseDate,shares,purchasePrice,currentPrice,note\n"
        for s in finance.stocks {
            let fields: [String] = [
                s.id.uuidString,
                esc(s.symbol),
                esc(s.name),
                iso.string(from: s.purchaseDate),
                String(format: "%.4f", s.shares),
                String(format: "%.4f", s.purchasePrice),
                String(format: "%.4f", s.currentPrice),
                esc(s.note)
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        csv += "\n"

        // 理財 - 汽車
        csv += "## 汽車 (Vehicles)\n"
        csv += "id,name,brand,powerType,purchaseDate,purchasePrice,currentValue,soldDate,note\n"
        for v in finance.vehicles {
            let fields: [String] = [
                v.id.uuidString,
                esc(v.name),
                esc(v.brand),
                v.powerType.rawValue,
                iso.string(from: v.purchaseDate),
                String(format: "%.2f", v.purchasePrice),
                String(format: "%.2f", v.currentValue),
                v.soldDate.map { iso.string(from: $0) } ?? "",
                esc(v.note)
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        csv += "\n"

        // 理財 - 房地產
        csv += "## 房地產 (Real Estates)\n"
        csv += "id,name,address,purchaseDate,purchasePrice,currentValue,monthlyRental,soldDate,note\n"
        for r in finance.realEstates {
            let fields: [String] = [
                r.id.uuidString,
                esc(r.name),
                esc(r.address),
                iso.string(from: r.purchaseDate),
                String(format: "%.2f", r.purchasePrice),
                String(format: "%.2f", r.currentValue),
                String(format: "%.2f", r.monthlyRental),
                r.soldDate.map { iso.string(from: $0) } ?? "",
                esc(r.note)
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        csv += "\n"

        // 人生 - 里程碑
        csv += "## 里程碑 (Milestones)\n"
        csv += "id,title,date,category,note\n"
        for m in life.milestones.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                m.id.uuidString,
                esc(m.title),
                iso.string(from: m.date),
                m.category.rawValue,
                esc(m.note)
            ]
            csv += fields.joined(separator: ",") + "\n"
        }

        return csv
    }

    private static func esc(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

// MARK: - 匯入器

enum UnifiedImporter {
    enum Mode {
        case merge
        case replace
    }

    struct ImportResult {
        var expenses: Int = 0
        var incomes: Int = 0
        var insurances: Int = 0
        var stocks: Int = 0
        var vehicles: Int = 0
        var realEstates: Int = 0
        var milestones: Int = 0
        var relationships: Int = 0
        var pets: Int = 0
        var schedules: Int = 0

        var summary: String {
            var parts: [String] = []
            if expenses > 0 { parts.append("支出 \(expenses)") }
            if incomes > 0 { parts.append("收入 \(incomes)") }
            if insurances > 0 { parts.append("儲蓄險 \(insurances)") }
            if stocks > 0 { parts.append("股票 \(stocks)") }
            if vehicles > 0 { parts.append("汽車 \(vehicles)") }
            if realEstates > 0 { parts.append("房地產 \(realEstates)") }
            if milestones > 0 { parts.append("里程碑 \(milestones)") }
            if relationships > 0 { parts.append("人脈 \(relationships)") }
            if pets > 0 { parts.append("寵物 \(pets)") }
            if schedules > 0 { parts.append("行程 \(schedules)") }
            return parts.isEmpty ? "沒有資料" : parts.joined(separator: "、")
        }
    }

    /// 嘗試匯入統一格式。若失敗則退回舊版（僅支出陣列）
    static func importData(
        data: Data,
        mode: Mode,
        expense: ExpenseStore,
        finance: FinanceStore,
        life: LifeStore
    ) -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let payload = try? decoder.decode(UnifiedExport.self, from: data) {
            return applyUnified(payload, mode: mode, expense: expense, finance: finance, life: life)
        }

        // 舊版：純支出陣列
        if let legacyExpenses = try? decoder.decode([Expense].self, from: data) {
            var result = ImportResult()
            switch mode {
            case .merge:
                let existing = Set(expense.expenses.map(\.id))
                let add = legacyExpenses.filter { !existing.contains($0.id) }
                expense.expenses.append(contentsOf: add)
                result.expenses = add.count
            case .replace:
                expense.expenses = legacyExpenses
                result.expenses = legacyExpenses.count
            }
            return result
        }

        return ImportResult()
    }

    private static func applyUnified(
        _ payload: UnifiedExport,
        mode: Mode,
        expense: ExpenseStore,
        finance: FinanceStore,
        life: LifeStore
    ) -> ImportResult {
        var result = ImportResult()

        switch mode {
        case .replace:
            expense.expenses = payload.expense.expenses
            expense.incomes = payload.expense.incomes
            finance.insurances = payload.finance.insurances
            finance.stocks = payload.finance.stocks
            finance.vehicles = payload.finance.vehicles
            finance.realEstates = payload.finance.realEstates
            life.milestones = payload.life.milestones
            life.relationships = payload.life.relationships
            life.pets = payload.life.pets
            life.schedules = payload.life.schedules

            result.expenses = payload.expense.expenses.count
            result.incomes = payload.expense.incomes.count
            result.insurances = payload.finance.insurances.count
            result.stocks = payload.finance.stocks.count
            result.vehicles = payload.finance.vehicles.count
            result.realEstates = payload.finance.realEstates.count
            result.milestones = payload.life.milestones.count
            result.relationships = payload.life.relationships.count
            result.pets = payload.life.pets.count
            result.schedules = payload.life.schedules.count

        case .merge:
            let newExpenses = mergeItems(existing: expense.expenses, incoming: payload.expense.expenses)
            expense.expenses.append(contentsOf: newExpenses)
            result.expenses = newExpenses.count

            let newIncomes = mergeItems(existing: expense.incomes, incoming: payload.expense.incomes)
            expense.incomes.append(contentsOf: newIncomes)
            result.incomes = newIncomes.count

            let newIns = mergeItems(existing: finance.insurances, incoming: payload.finance.insurances)
            finance.insurances.append(contentsOf: newIns)
            result.insurances = newIns.count

            let newStocks = mergeItems(existing: finance.stocks, incoming: payload.finance.stocks)
            finance.stocks.append(contentsOf: newStocks)
            result.stocks = newStocks.count

            let newVehicles = mergeItems(existing: finance.vehicles, incoming: payload.finance.vehicles)
            finance.vehicles.append(contentsOf: newVehicles)
            result.vehicles = newVehicles.count

            let newRE = mergeItems(existing: finance.realEstates, incoming: payload.finance.realEstates)
            finance.realEstates.append(contentsOf: newRE)
            result.realEstates = newRE.count

            let newMs = mergeItems(existing: life.milestones, incoming: payload.life.milestones)
            life.milestones.append(contentsOf: newMs)
            result.milestones = newMs.count

            let newRel = mergeItems(existing: life.relationships, incoming: payload.life.relationships)
            life.relationships.append(contentsOf: newRel)
            result.relationships = newRel.count

            let newPets = mergeItems(existing: life.pets, incoming: payload.life.pets)
            life.pets.append(contentsOf: newPets)
            result.pets = newPets.count

            let newSchs = mergeItems(existing: life.schedules, incoming: payload.life.schedules)
            life.schedules.append(contentsOf: newSchs)
            result.schedules = newSchs.count
        }

        return result
    }

    private static func mergeItems<T: Identifiable>(existing: [T], incoming: [T]) -> [T] {
        let existingIDs = Set(existing.map(\.id))
        return incoming.filter { !existingIDs.contains($0.id) }
    }
}
