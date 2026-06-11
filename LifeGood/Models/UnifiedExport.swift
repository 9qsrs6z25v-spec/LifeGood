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
        var currencyRates: [CurrencyRate]?
    }

    struct FinanceBundle: Codable {
        var insurances: [SavingsInsurance]
        var stocks: [Stock]
        var vehicles: [Vehicle]
        var realEstates: [RealEstate]
    }

    struct LifeBundle: Codable {
        var profile: UserProfile?
        var familyMembers: [FamilyMember]?
        var milestones: [LifeMilestone]
        var relationships: [Relationship]
        var pets: [Pet]
        var schedules: [Schedule]
        var subordinates: [Subordinate]?
        var departments: [Department]?
        var gradeTitles: [GradeTitle]?
    }

    static func build(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) -> UnifiedExport {
        UnifiedExport(
            version: "2",
            exportDate: Date(),
            expense: ExpenseBundle(expenses: expense.expenses, incomes: expense.incomes, currencyRates: expense.currencyRates),
            finance: FinanceBundle(
                insurances: finance.insurances,
                stocks: finance.stocks,
                vehicles: finance.vehicles,
                realEstates: finance.realEstates
            ),
            life: LifeBundle(
                profile: life.profile,
                familyMembers: life.familyMembers,
                milestones: life.milestones,
                relationships: life.relationships,
                pets: life.pets,
                schedules: life.schedules,
                subordinates: life.subordinates,
                departments: life.departments,
                gradeTitles: life.gradeTitles
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
                s.currencyCode,
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
        csv += "id,name,city,address,purchaseDate,purchasePrice,currentValue,monthlyRental,soldDate,note\n"
        for r in finance.realEstates {
            let fields: [String] = [
                r.id.uuidString,
                esc(r.name),
                esc(r.city),
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

        // 理財 - 房地產巢狀明細（攤平成多個區段，以 realEstateId 連結回主表）
        if !finance.realEstates.isEmpty {
            csv += "## 房地產-樓層 (RE Floors)\n"
            csv += "realEstateId,realEstateName,floorNumber,area,functions\n"
            for r in finance.realEstates {
                for f in r.floors {
                    csv += [r.id.uuidString, esc(r.name), esc(f.floorNumber),
                            String(format: "%.2f", f.area),
                            esc(f.functions.map { $0.rawValue }.joined(separator: " / "))].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"

            csv += "## 房地產-資產物件 (RE Floor Items)\n"
            csv += "realEstateId,realEstateName,floorNumber,itemPath\n"
            for r in finance.realEstates {
                for f in r.floors {
                    for path in flattenFloorItems(f.items, prefix: "") {
                        csv += [r.id.uuidString, esc(r.name), esc(f.floorNumber), esc(path)].joined(separator: ",") + "\n"
                    }
                }
            }
            csv += "\n"

            csv += "## 房地產-貸款 (RE Mortgages)\n"
            csv += "realEstateId,realEstateName,title,amountPerPeriod,totalPeriods,startDate\n"
            for r in finance.realEstates {
                for m in r.mortgageItems {
                    csv += [r.id.uuidString, esc(r.name), esc(m.title),
                            String(format: "%.2f", m.amount), String(m.totalPeriods),
                            iso.string(from: m.startDate)].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"

            csv += "## 房地產-已支出 (RE Paid Items)\n"
            csv += "realEstateId,realEstateName,title,amount,date\n"
            for r in finance.realEstates {
                for p in r.paidItems {
                    csv += [r.id.uuidString, esc(r.name), esc(p.title),
                            String(format: "%.2f", p.amount), iso.string(from: p.date)].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"

            csv += "## 房地產-變動支出 (RE Variable Expenses)\n"
            csv += "realEstateId,realEstateName,category,name,amount,date\n"
            for r in finance.realEstates {
                for v in r.variableExpenses {
                    csv += [r.id.uuidString, esc(r.name), esc(v.category.rawValue), esc(v.name),
                            String(format: "%.2f", v.amount), iso.string(from: v.date)].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"

            csv += "## 房地產-附屬資產 (RE Property Assets)\n"
            csv += "realEstateId,realEstateName,category,name,brand,floorLocation,amount\n"
            for r in finance.realEstates {
                for a in r.propertyAssets {
                    csv += [r.id.uuidString, esc(r.name), esc(a.category.rawValue), esc(a.name),
                            esc(a.brand), esc(a.floorLocation), String(format: "%.2f", a.amount)].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"

            csv += "## 房地產-土地權狀 (RE Land Deeds)\n"
            csv += "realEstateId,realEstateName,situation,number,area\n"
            for r in finance.realEstates {
                for d in r.landDeeds {
                    csv += [r.id.uuidString, esc(r.name), esc(d.situation), esc(d.number),
                            String(format: "%.2f", d.area)].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"

            csv += "## 房地產-建物權狀 (RE Building Deeds)\n"
            csv += "realEstateId,realEstateName,situation,number,address,completionDate,usage,annex,area\n"
            for r in finance.realEstates {
                for d in r.buildingDeeds {
                    csv += [r.id.uuidString, esc(r.name), esc(d.situation), esc(d.number), esc(d.address),
                            d.completionDate.map { iso.string(from: $0) } ?? "", esc(d.usage), esc(d.annex),
                            String(format: "%.2f", d.area)].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"

            csv += "## 房地產-保險 (RE Insurances)\n"
            csv += "realEstateId,realEstateName,policyNumber,amount\n"
            for r in finance.realEstates {
                for ins in r.insuranceItems {
                    csv += [r.id.uuidString, esc(r.name), esc(ins.policyNumber),
                            String(format: "%.2f", ins.amount)].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"

            csv += "## 房地產-水電瓦斯繳費 (RE Utility Payments)\n"
            csv += "realEstateId,realEstateName,type,date,amount,note\n"
            for r in finance.realEstates {
                for u in r.utilityPayments {
                    csv += [r.id.uuidString, esc(r.name), esc(u.type.rawValue),
                            iso.string(from: u.date), String(format: "%.2f", u.amount), esc(u.note)].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"

            csv += "## 房地產-文件 (RE Documents)\n"
            csv += "realEstateId,realEstateName,displayName,fileName,date,note\n"
            for r in finance.realEstates {
                for d in r.documents {
                    csv += [r.id.uuidString, esc(r.name), esc(d.displayName), esc(d.fileName),
                            iso.string(from: d.date), esc(d.note)].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"

            csv += "## 房地產-電梯保養 (RE Elevator Maintenances)\n"
            csv += "realEstateId,realEstateName,date,hasPhoto\n"
            for r in finance.realEstates {
                for e in r.elevatorMaintenances {
                    csv += [r.id.uuidString, esc(r.name), iso.string(from: e.date),
                            e.photoFileName != nil ? "1" : "0"].joined(separator: ",") + "\n"
                }
            }
            csv += "\n"
        }

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

    /// 把樓層物件樹攤平成「父 / 子 / 孫」路徑字串（給 CSV 用）
    private static func flattenFloorItems(_ items: [FloorItem], prefix: String) -> [String] {
        var rows: [String] = []
        for it in items {
            let path = prefix.isEmpty ? it.name : "\(prefix) / \(it.name)"
            rows.append(path)
            rows.append(contentsOf: flattenFloorItems(it.children, prefix: path))
        }
        return rows
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
        var familyMembers: Int = 0
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
            if familyMembers > 0 { parts.append("家庭 \(familyMembers)") }
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
            if let rates = payload.expense.currencyRates { expense.currencyRates = rates }
            finance.insurances = payload.finance.insurances
            finance.stocks = payload.finance.stocks
            finance.vehicles = payload.finance.vehicles
            finance.realEstates = payload.finance.realEstates
            if let profile = payload.life.profile { life.profile = profile }
            if let members = payload.life.familyMembers { life.familyMembers = members }
            life.milestones = payload.life.milestones
            life.relationships = payload.life.relationships
            life.pets = payload.life.pets
            life.schedules = payload.life.schedules
            if let subs = payload.life.subordinates { life.subordinates = subs }
            if let depts = payload.life.departments { life.departments = depts }
            if let gts = payload.life.gradeTitles { life.gradeTitles = gts }

            result.expenses = payload.expense.expenses.count
            result.incomes = payload.expense.incomes.count
            result.insurances = payload.finance.insurances.count
            result.stocks = payload.finance.stocks.count
            result.vehicles = payload.finance.vehicles.count
            result.realEstates = payload.finance.realEstates.count
            result.familyMembers = payload.life.familyMembers?.count ?? 0
            result.milestones = payload.life.milestones.count
            result.relationships = payload.life.relationships.count
            result.pets = payload.life.pets.count
            result.schedules = payload.life.schedules.count

        case .merge:
            if let rates = payload.expense.currencyRates {
                let newRates = mergeItems(existing: expense.currencyRates, incoming: rates)
                expense.currencyRates.append(contentsOf: newRates)
            }
            if let profile = payload.life.profile { life.profile = profile }
            if let members = payload.life.familyMembers {
                let newFamily = mergeItems(existing: life.familyMembers, incoming: members)
                life.familyMembers.append(contentsOf: newFamily)
                result.familyMembers = newFamily.count
            }
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

            if let subs = payload.life.subordinates {
                let newSubs = mergeItems(existing: life.subordinates, incoming: subs)
                life.subordinates.append(contentsOf: newSubs)
            }

            if let depts = payload.life.departments {
                let newDepts = mergeItems(existing: life.departments, incoming: depts)
                life.departments.append(contentsOf: newDepts)
            }

            if let gts = payload.life.gradeTitles {
                let newGts = mergeItems(existing: life.gradeTitles, incoming: gts)
                life.gradeTitles.append(contentsOf: newGts)
            }
        }

        return result
    }

    private static func mergeItems<T: Identifiable>(existing: [T], incoming: [T]) -> [T] {
        let existingIDs = Set(existing.map(\.id))
        return incoming.filter { !existingIDs.contains($0.id) }
    }
}

// MARK: - 單獨匯出：部屬資料（含班表 / 任務 / 會議 / 請假等紀錄）

struct SubordinateExport: Codable {
    var kind: String = "subordinates"   // 供匯入時辨識檔案類型
    var version: String = "1"
    var exportDate: Date = Date()
    var subordinates: [Subordinate]
    var departments: [Department]?      // 一併帶出被參照的部門 / 職等，匯入後仍能正確顯示
    var gradeTitles: [GradeTitle]?
}

enum SubordinateExporter {
    static func exportJSON(life: LifeStore) -> Data {
        let payload = SubordinateExport(
            subordinates: life.subordinates,
            departments: life.departments,
            gradeTitles: life.gradeTitles
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(payload)) ?? Data()
    }
}

enum SubordinateImporter {
    struct Result {
        var added = 0
        var updated = 0
        var recordsMerged = 0
        var meetingsMerged = 0
        var tasksMerged = 0
        var shiftsMerged = 0
        var departmentsAdded = 0
        var gradeTitlesAdded = 0
        var summary: String {
            "新增 \(added) 人、更新 \(updated) 人；班別 +\(shiftsMerged)、任務 +\(tasksMerged)、會議 +\(meetingsMerged)、紀錄 +\(recordsMerged)"
        }
    }

    /// 從 JSON 內容判斷是否為「部屬資料」匯出檔（kind == "subordinates"）
    static func isSubordinateExport(_ data: Data) -> Bool {
        struct Probe: Codable { var kind: String? }
        return (try? JSONDecoder().decode(Probe.self, from: data))?.kind == "subordinates"
    }

    static func importData(data: Data, mode: UnifiedImporter.Mode, life: LifeStore) -> Result {
        var r = Result()
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let payload = try? dec.decode(SubordinateExport.self, from: data) else { return r }

        // 部門 / 職等：補進缺少的（依 id），讓部屬參照能正確顯示
        if let depts = payload.departments {
            let ids = Set(life.departments.map(\.id))
            let add = depts.filter { !ids.contains($0.id) }
            if !add.isEmpty { life.departments.append(contentsOf: add); r.departmentsAdded = add.count }
        }
        if let gts = payload.gradeTitles {
            let ids = Set(life.gradeTitles.map(\.id))
            let add = gts.filter { !ids.contains($0.id) }
            if !add.isEmpty { life.gradeTitles.append(contentsOf: add); r.gradeTitlesAdded = add.count }
        }

        switch mode {
        case .replace:
            life.subordinates = payload.subordinates
            r.added = payload.subordinates.count

        case .merge:
            var subs = life.subordinates
            for inc in payload.subordinates {
                // 對應現有部屬：先比 id，再退而求其次比「同名同部門」
                let idx = subs.firstIndex(where: { $0.id == inc.id })
                    ?? subs.firstIndex(where: { !inc.name.isEmpty && $0.name == inc.name && $0.department == inc.department })
                if let idx = idx {
                    var s = subs[idx]
                    r.recordsMerged  += appendNew(&s.records,  inc.records)
                    r.meetingsMerged += appendNew(&s.meetings, inc.meetings)
                    r.tasksMerged    += appendNew(&s.tasks,    inc.tasks)
                    r.shiftsMerged   += appendNewShifts(&s.shifts, inc.shifts)
                    if s.plantArea.isEmpty, !inc.plantArea.isEmpty { s.plantArea = inc.plantArea }
                    if s.joinDate == nil { s.joinDate = inc.joinDate }
                    subs[idx] = s
                    r.updated += 1
                } else {
                    subs.append(inc); r.added += 1
                }
            }
            life.subordinates = subs   // 單次指派 → 單次存檔
        }
        return r
    }

    /// 依 id 加入現有陣列中尚未存在的項目，回傳新增筆數
    private static func appendNew<T: Identifiable>(_ arr: inout [T], _ incoming: [T]) -> Int {
        let ids = Set(arr.map(\.id))
        let add = incoming.filter { !ids.contains($0.id) }
        arr.append(contentsOf: add)
        return add.count
    }

    /// 班別以「同一天」去重：該天已有班別就保留現有、不覆蓋
    private static func appendNewShifts(_ arr: inout [SubordinateShift], _ incoming: [SubordinateShift]) -> Int {
        let cal = Calendar.current
        var added = 0
        for sh in incoming where !arr.contains(where: { cal.isDate($0.date, inSameDayAs: sh.date) }) {
            arr.append(sh); added += 1
        }
        return added
    }
}
