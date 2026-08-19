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
        var healthProfile: HealthProfile?
        var businessCards: [BusinessCard]?
        var personalEvents: [PersonalEvent]?
        var orgPeople: [OrgPerson]?
        var familyTasks: [FamilyTask]?
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
                gradeTitles: life.gradeTitles,
                healthProfile: life.healthProfile,
                businessCards: life.businessCards,
                personalEvents: life.personalEvents,
                orgPeople: life.orgPeople,
                familyTasks: life.familyTasks
            )
        )
    }
}

// MARK: - 匯出器

enum UnifiedExporter {
    static func exportJSON(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) -> Data {
        exportJSON(UnifiedExport.build(expense: expense, finance: finance, life: life))
    }

    /// 純 payload 版本：只碰 struct 快照，不觸及 @Published，可安全在背景執行緒呼叫。
    static func exportJSON(_ payload: UnifiedExport) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(payload)) ?? Data()
    }

    static func exportCSV(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) -> String {
        exportCSV(UnifiedExport.build(expense: expense, finance: finance, life: life))
    }

    /// 純 payload 版本：只碰 struct 快照，不觸及 @Published，可安全在背景執行緒呼叫。
    static func exportCSV(_ payload: UnifiedExport) -> String {
        let expense = payload.expense
        let finance = payload.finance
        let life = payload.life
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

        // 人生 - 配偶協定
        // JSON 匯出／備份整包走 Codable 自動涵蓋；CSV 是逐欄手寫的，要另外補。
        // ⚠️ LifeBundle.familyMembers 是 Optional 陣列。直接 .flatMap 會呼叫到
        //    Optional.flatMap，閉包參數變成整個 [FamilyMember] 而不是單一成員。
        var agreementRows: [(member: FamilyMember, agreement: SpouseAgreement)] = []
        for m in life.familyMembers ?? [] {
            for a in m.agreements ?? [] { agreementRows.append((member: m, agreement: a)) }
        }
        if !agreementRows.isEmpty {
            csv += "\n## 協定 (Agreements)\n"
            csv += "memberId,memberName,title,category,agreedDate,status,party,amount,cadence,detail,note\n"
            let sortedRows = agreementRows.sorted { $0.agreement.agreedDate < $1.agreement.agreedDate }
            for row in sortedRows {
                let m = row.member
                let a = row.agreement
                let fields: [String] = [
                    m.id.uuidString,
                    esc(m.chineseName),
                    esc(a.title),
                    a.category.title,
                    iso.string(from: a.agreedDate),
                    a.status.title,
                    a.party?.title ?? "",
                    a.amount.map { String(Int($0)) } ?? "",
                    a.cadence?.title ?? "",
                    esc(a.detail),
                    esc(a.note)
                ]
                csv += fields.joined(separator: ",") + "\n"
            }
        }

        // 人生 - 兼任職務（含管理頁的四份子資料）
        // JSON 匯出／備份是整包走 Codable，新欄位自動涵蓋；CSV 是逐欄手寫的，
        // 不補在這裡就會變成「JSON 有、CSV 沒有」的靜默落差。
        let sideRoles = life.milestones
            .filter { $0.careerSubCategory == .sideRole }
            .sorted { $0.date < $1.date }
        if !sideRoles.isEmpty {
            csv += "\n## 兼任職務 (Side Roles)\n"
            csv += "id,roleName,org,startDate,endDate,isLead,workspaceEnabled,scope\n"
            for r in sideRoles {
                let fields: [String] = [
                    r.id.uuidString,
                    esc(r.sideRoleName ?? ""),
                    esc(r.sideRoleOrg ?? ""),
                    iso.string(from: r.date),
                    r.sideRoleEndDate.map { iso.string(from: $0) } ?? "",
                    (r.sideRoleIsLead ?? false) ? "1" : "0",
                    (r.sideRoleWorkspaceEnabled ?? false) ? "1" : "0",
                    esc(r.sideRoleScope ?? "")
                ]
                csv += fields.joined(separator: ",") + "\n"
            }

            csv += "\n## 兼任職務待辦 (Side Role Tasks)\n"
            csv += "roleId,roleName,content,assignees,dueDate,isCompleted,completedAt,note,linkedRecords\n"
            for r in sideRoles {
                let memberNames = Dictionary(
                    (r.sideRoleMembers ?? []).map { ($0.id, $0.name) },
                    uniquingKeysWith: { a, _ in a })
                for t in r.sideRoleTasks ?? [] {
                    let assignees = (t.assigneeIds ?? [])
                        .compactMap { memberNames[$0] }
                        .filter { !$0.isEmpty }
                        .joined(separator: "、")
                    // 連結的部屬紀錄：標明是自動建立的分身還是拉進來的既有紀錄，
                    // 匯出檔看得出「這件事在部屬那邊也有一筆」，不會誤以為重複登錄。
                    let linked = (t.links ?? []).map { link -> String in
                        let kind = link.kind == .task ? "任務" : "議程"
                        let origin = link.isAutoCreated ? "自動" : "連結"
                        return "\(kind)/\(origin)/\(link.itemId.uuidString)"
                    }.joined(separator: "、")
                    let fields: [String] = [
                        r.id.uuidString, esc(r.sideRoleName ?? ""), esc(t.content),
                        esc(assignees),
                        t.dueDate.map { iso.string(from: $0) } ?? "",
                        t.isCompleted ? "1" : "0",
                        t.completedAt.map { iso.string(from: $0) } ?? "",
                        esc(t.note), esc(linked)
                    ]
                    csv += fields.joined(separator: ",") + "\n"
                }
            }

            csv += "\n## 兼任職務成員 (Side Role Members)\n"
            csv += "roleId,roleName,name,dutyInRole,contact,note\n"
            for r in sideRoles {
                for m in r.sideRoleMembers ?? [] {
                    let fields: [String] = [
                        r.id.uuidString, esc(r.sideRoleName ?? ""), esc(m.name),
                        esc(m.dutyInRole), esc(m.contact), esc(m.note)
                    ]
                    csv += fields.joined(separator: ",") + "\n"
                }
            }

            csv += "\n## 兼任職務會議 (Side Role Meetings)\n"
            csv += "roleId,roleName,date,topic,attendees,decisions,note\n"
            for r in sideRoles {
                for mt in r.sideRoleMeetings ?? [] {
                    let fields: [String] = [
                        r.id.uuidString, esc(r.sideRoleName ?? ""),
                        iso.string(from: mt.date), esc(mt.topic),
                        esc(mt.attendees.joined(separator: "、")),
                        esc(mt.decisions), esc(mt.note)
                    ]
                    csv += fields.joined(separator: ",") + "\n"
                }
            }

            csv += "\n## 兼任職務重大決議 (Side Role Resolutions)\n"
            csv += "roleId,roleName,date,site,categories,initiator,title,content\n"
            for r in sideRoles {
                for res in r.sideRoleResolutions ?? [] {
                    let fields: [String] = [
                        r.id.uuidString, esc(r.sideRoleName ?? ""),
                        iso.string(from: res.date),
                        esc(res.site),
                        res.categories.map(\.rawValue).joined(separator: "/"),
                        esc(res.initiator),
                        esc(res.title), esc(res.content)
                    ]
                    csv += fields.joined(separator: ",") + "\n"
                }
            }

            csv += "\n## 兼任職務重要日期 (Side Role Key Dates)\n"
            csv += "roleId,roleName,date,title,remindDaysBefore,note\n"
            for r in sideRoles {
                for k in r.sideRoleKeyDates ?? [] {
                    let fields: [String] = [
                        r.id.uuidString, esc(r.sideRoleName ?? ""),
                        iso.string(from: k.date), esc(k.title),
                        k.remindDaysBefore.map(String.init) ?? "",
                        esc(k.note)
                    ]
                    csv += fields.joined(separator: ",") + "\n"
                }
            }
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
        var businessCards: Int = 0
        var personalEvents: Int = 0
        var orgPeople: Int = 0

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
            if businessCards > 0 { parts.append("名片 \(businessCards)") }
            if personalEvents > 0 { parts.append("個人行程 \(personalEvents)") }
            if orgPeople > 0 { parts.append("組織人脈 \(orgPeople)") }
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
            let incomingIds = Set(payload.expense.expenses.map(\.id))
            for old in expense.expenses where !incomingIds.contains(old.id) {
                for name in old.photoFileNames { Expense.deletePhoto(name) }
            }
            // RealEstate 內嵌的電梯保養/水電繳費/裝潢照片/文件檔案未隨 replace 匯入被清掉的話，
            // 舊檔案會永久留在磁碟上並被 CloudKitManager.uploadAllLocalPhotos() 當成「未上傳的本機照片」
            // 反覆重傳，對齊上面 Expense 的清理方式，只清掉被 replace 淘汰、不在新資料中的 RealEstate。
            let incomingRealEstateIds = Set(payload.finance.realEstates.map(\.id))
            for old in finance.realEstates where !incomingRealEstateIds.contains(old.id) {
                for up in old.utilityPayments {
                    for name in up.photoFileNames { UtilityPayment.deletePhoto(name) }
                }
                for rp in old.renovationPhotos {
                    for name in rp.photoFileNames { RenovationPhoto.deletePhoto(name) }
                }
                for em in old.elevatorMaintenances {
                    if let name = em.photoFileName { ElevatorMaintenance.deletePhoto(name) }
                }
                for doc in old.documents {
                    RealEstateDocument.deleteDocument(doc.fileName)
                }
            }
            // FamilyMember 內嵌的兒女記錄照片／家庭相簿照片、BusinessCard／OrgPerson 各自的
            // 大頭照，若未隨 replace 匯入被清掉，同樣會變成孤兒檔案並被
            // CloudKitManager.uploadAllLocalPhotos() 當成「未上傳的本機照片」反覆重傳，
            // 對齊上面 Expense／RealEstate 的清理方式；三者皆為 optional 欄位，只在匯入檔
            // 實際帶有該類資料（下方才會整批覆蓋本機）時才清理，避免匯入檔未帶該類別時
            // 誤刪本機既有照片。
            if let members = payload.life.familyMembers {
                let incomingMemberIds = Set(members.map(\.id))
                for old in life.familyMembers where !incomingMemberIds.contains(old.id) {
                    for record in old.childRecords {
                        if let name = record.photoFileName { ChildRecord.deletePhoto(name) }
                    }
                    for photo in old.familyPhotos {
                        if let name = photo.photoFileName { FamilyAlbumPhoto.deletePhoto(name) }
                    }
                }
            }
            if let cards = payload.life.businessCards {
                let incomingCardIds = Set(cards.map(\.id))
                for old in life.businessCards where !incomingCardIds.contains(old.id) {
                    if let name = old.photoFileName { BusinessCard.deletePhoto(name) }
                }
            }
            if let people = payload.life.orgPeople {
                let incomingPeopleIds = Set(people.map(\.id))
                for old in life.orgPeople where !incomingPeopleIds.contains(old.id) {
                    if let name = old.photoFileName { OrgPerson.deletePhoto(name) }
                }
            }
            // expense／life 各自的多筆屬性指派原本各自觸發一次 save()（ExpenseStore 每次
            // 都把 expenses+incomes 兩份一起重編碼；LifeStore 每次都把全部 13 個集合一起重編碼），
            // 還原/覆蓋整批匯入時最多分別造成 2 次與 13 次完全重複的編碼與畫面重繪；
            // 比照 GradeTitleView 既有的 withBatch 用法，改成各自只存檔一次。
            expense.withBatch {
                expense.expenses = payload.expense.expenses
                expense.incomes = payload.expense.incomes
                if let rates = payload.expense.currencyRates { expense.currencyRates = rates }
            }
            finance.insurances = payload.finance.insurances
            finance.stocks = payload.finance.stocks
            finance.vehicles = payload.finance.vehicles
            finance.realEstates = payload.finance.realEstates
            life.withBatch {
                if let profile = payload.life.profile { life.profile = profile }
                if let members = payload.life.familyMembers { life.familyMembers = members }
                life.milestones = payload.life.milestones
                life.relationships = payload.life.relationships
                life.pets = payload.life.pets
                life.schedules = payload.life.schedules
                if let subs = payload.life.subordinates { life.subordinates = subs }
                if let depts = payload.life.departments { life.departments = depts }
                if let gts = payload.life.gradeTitles { life.gradeTitles = gts }
                if let hp = payload.life.healthProfile { life.healthProfile = hp }
                if let cards = payload.life.businessCards { life.businessCards = cards }
                if let events = payload.life.personalEvents { life.personalEvents = events }
                if let people = payload.life.orgPeople { life.orgPeople = people }
                if let ft = payload.life.familyTasks { life.familyTasks = ft }
            }

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
            result.businessCards = payload.life.businessCards?.count ?? 0
            result.personalEvents = payload.life.personalEvents?.count ?? 0
            result.orgPeople = payload.life.orgPeople?.count ?? 0

        case .merge:
            // expense／life 的多筆屬性合併原本各自散落多處、各自觸發一次 save()（ExpenseStore
            // 每次都把 expenses+incomes 一起重編碼；LifeStore 每次都把全部 13 個集合一起重編碼），
            // 合併匯入一份涵蓋多類別的備份時會造成多次完全重複的編碼與畫面重繪；
            // 比照 GradeTitleView 既有的 withBatch 用法，改成各自只存檔一次（finance 的
            // 4 個集合各自獨立存檔互不重疊，不受此問題影響，維持原樣）。
            expense.withBatch {
                if let rates = payload.expense.currencyRates {
                    let newRates = mergeItems(existing: expense.currencyRates, incoming: rates)
                    expense.currencyRates.append(contentsOf: newRates)
                }
                let newExpenses = mergeItems(existing: expense.expenses, incoming: payload.expense.expenses)
                expense.expenses.append(contentsOf: newExpenses)
                result.expenses = newExpenses.count

                let newIncomes = mergeItems(existing: expense.incomes, incoming: payload.expense.incomes)
                expense.incomes.append(contentsOf: newIncomes)
                result.incomes = newIncomes.count
            }

            life.withBatch {
                // 個人檔案為單一物件：合併模式僅在本機尚無資料時填入，避免匯入別人的備份就把
                // 自己的姓名/生日等個人資料覆蓋掉；比照下方健康檔案既有的合併寫法。
                if let profile = payload.life.profile, life.profile.isEmpty { life.profile = profile }
                // 健康檔案為單一物件：合併模式僅在本機尚無資料時填入，避免覆蓋既有健康檔案
                if let hp = payload.life.healthProfile, life.healthProfile.isEmpty { life.healthProfile = hp }
                if let members = payload.life.familyMembers {
                    // 既有成員（同 id）過去整筆被 mergeItems 丟棄，導致對方備份裡的疫苗接種、
                    // 兒女記錄等子項目在合併模式下永遠進不來；比照下方部屬（subordinates）的
                    // 深度合併寫法：既有成員補進新的子項目、不存在的成員整筆新增。
                    var arr = life.familyMembers
                    var addedMembers = 0
                    for inc in members {
                        if let idx = arr.firstIndex(where: { $0.id == inc.id }) {
                            var m = arr[idx]
                            appendNewByID(&m.childRecords, inc.childRecords)
                            appendNewByID(&m.dailyRecords, inc.dailyRecords)
                            appendNewByID(&m.familyEvents, inc.familyEvents)
                            appendNewByID(&m.familyPhotos, inc.familyPhotos)
                            // 疫苗接種：同一劑次（scheduleId）本機已有紀錄則保留本機，
                            // 僅補上本機缺少的施打日期/備註；本機沒有的劑次整筆帶入。
                            for v in inc.vaccinations {
                                if let vi = m.vaccinations.firstIndex(where: { $0.scheduleId == v.scheduleId }) {
                                    if m.vaccinations[vi].administeredDate == nil, let d = v.administeredDate {
                                        m.vaccinations[vi].administeredDate = d
                                    }
                                    if m.vaccinations[vi].note.isEmpty, !v.note.isEmpty {
                                        m.vaccinations[vi].note = v.note
                                    }
                                } else {
                                    m.vaccinations.append(v)
                                }
                            }
                            // 基本欄位僅在本機空缺時補上，不覆蓋本機既有資料
                            if m.birthday == nil { m.birthday = inc.birthday }
                            if m.birthYear == nil { m.birthYear = inc.birthYear }
                            arr[idx] = m
                        } else {
                            arr.append(inc)
                            addedMembers += 1
                        }
                    }
                    life.familyMembers = arr
                    result.familyMembers = addedMembers
                }

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
                    // 既有部屬：補進新的子項目（班表/任務/會議/報告/紀錄）；不存在的部屬整筆新增
                    var arr = life.subordinates
                    let cal = Calendar.current
                    for inc in subs {
                        if let idx = arr.firstIndex(where: { $0.id == inc.id }) {
                            var s = arr[idx]
                            appendNewByID(&s.records,  inc.records)
                            appendNewByID(&s.meetings, inc.meetings)
                            appendNewByID(&s.tasks,    inc.tasks)
                            appendNewByID(&s.weeklyReports, inc.weeklyReports)
                            appendNewByID(&s.equipments, inc.equipments)
                            var existingShiftDays = Set(s.shifts.map { cal.startOfDay(for: $0.date) })
                            for sh in inc.shifts {
                                let day = cal.startOfDay(for: sh.date)
                                if !existingShiftDays.contains(day) {
                                    s.shifts.append(sh)
                                    existingShiftDays.insert(day)
                                }
                            }
                            if s.plantArea.isEmpty, !inc.plantArea.isEmpty { s.plantArea = inc.plantArea }
                            if s.joinDate == nil { s.joinDate = inc.joinDate }
                            arr[idx] = s
                        } else {
                            arr.append(inc)
                        }
                    }
                    life.subordinates = arr
                }

                if let depts = payload.life.departments {
                    let newDepts = mergeItems(existing: life.departments, incoming: depts)
                    life.departments.append(contentsOf: newDepts)
                }

                if let gts = payload.life.gradeTitles {
                    let newGts = mergeItems(existing: life.gradeTitles, incoming: gts)
                    life.gradeTitles.append(contentsOf: newGts)
                }

                if let cards = payload.life.businessCards {
                    let newCards = mergeItems(existing: life.businessCards, incoming: cards)
                    life.businessCards.append(contentsOf: newCards)
                    result.businessCards = newCards.count
                }

                if let events = payload.life.personalEvents {
                    let newEvents = mergeItems(existing: life.personalEvents, incoming: events)
                    life.personalEvents.append(contentsOf: newEvents)
                    result.personalEvents = newEvents.count
                }

                if let people = payload.life.orgPeople {
                    let newPeople = mergeItems(existing: life.orgPeople, incoming: people)
                    life.orgPeople.append(contentsOf: newPeople)
                    result.orgPeople = newPeople.count
                }

                if let ft = payload.life.familyTasks {
                    let newTasks = mergeItems(existing: life.familyTasks, incoming: ft)
                    life.familyTasks.append(contentsOf: newTasks)
                }
            }

            let newIns = mergeItems(existing: finance.insurances, incoming: payload.finance.insurances)
            finance.insurances.append(contentsOf: newIns)
            result.insurances = newIns.count

            // 股票：既有股票（同 id）補進新的交易/股利子項目，不存在的股票整筆新增；
            // 比照上方家庭成員/部屬的深度合併寫法，避免另一台裝置新增的交易紀錄在合併模式下被丟棄。
            var stockArr = finance.stocks
            var newStockCount = 0
            for inc in payload.finance.stocks {
                if let idx = stockArr.firstIndex(where: { $0.id == inc.id }) {
                    var s = stockArr[idx]
                    // 併入前先把「僅有彙總欄位、無逐筆交易」的舊資料補種成原始買入，
                    // 否則下方重算會把本機既有持股當成 0 蓋掉（同型呼叫序見 StockDetailView）
                    s.seedTransactionsFromLegacyIfNeeded()
                    let beforeTx = s.transactions.count
                    let beforeDiv = s.dividends.count
                    appendNewByID(&s.transactions, inc.transactions)
                    appendNewByID(&s.dividends, inc.dividends)
                    if s.transactions.count != beforeTx || s.dividends.count != beforeDiv {
                        // 有實際併入新交易/股利才重算 shares/均價/已售出狀態——
                        // 過去漏了這步，卡片內交易變多、外層清單股數卻停在合併前舊值。
                        // 計數有成長保證 transactions/dividends 非空，重算不會誤清舊欄位。
                        s.recomputeFromTransactions()
                    }
                    stockArr[idx] = s
                } else {
                    stockArr.append(inc)
                    newStockCount += 1
                }
            }
            finance.stocks = stockArr
            result.stocks = newStockCount

            // 車輛：既有車輛補進新的定期/變動支出子項目，不存在的車輛整筆新增。
            var vehicleArr = finance.vehicles
            var newVehicleCount = 0
            for inc in payload.finance.vehicles {
                if let idx = vehicleArr.firstIndex(where: { $0.id == inc.id }) {
                    var v = vehicleArr[idx]
                    appendNewByID(&v.fixedExpenses, inc.fixedExpenses)
                    appendNewByID(&v.variableExpenses, inc.variableExpenses)
                    appendNewByID(&v.photoRecords, inc.photoRecords)
                    vehicleArr[idx] = v
                } else {
                    vehicleArr.append(inc)
                    newVehicleCount += 1
                }
            }
            finance.vehicles = vehicleArr
            result.vehicles = newVehicleCount

            // 房地產：既有房地產（同 id）過去整筆被 mergeItems 丟棄，導致對方備份新增的水電繳費、
            // 裝潢照片、文件等子項目在合併模式下永遠進不來，附件位元組又已被 FullBackup.restore
            // 無條件寫入磁碟，造成沒有任何項目指向的孤兒檔案；改為既有房地產補進新的子項目。
            var reArr = finance.realEstates
            var newRECount = 0
            for inc in payload.finance.realEstates {
                if let idx = reArr.firstIndex(where: { $0.id == inc.id }) {
                    var re = reArr[idx]
                    appendNewByID(&re.mortgageItems, inc.mortgageItems)
                    appendNewByID(&re.paidItems, inc.paidItems)
                    appendNewByID(&re.variableExpenses, inc.variableExpenses)
                    appendNewByID(&re.elevatorMaintenances, inc.elevatorMaintenances)
                    appendNewByID(&re.landDeeds, inc.landDeeds)
                    appendNewByID(&re.buildingDeeds, inc.buildingDeeds)
                    appendNewByID(&re.floors, inc.floors)
                    appendNewByID(&re.insuranceItems, inc.insuranceItems)
                    appendNewByID(&re.propertyAssets, inc.propertyAssets)
                    appendNewByID(&re.utilityPayments, inc.utilityPayments)
                    appendNewByID(&re.extraMeters, inc.extraMeters)
                    appendNewByID(&re.renovationPhotos, inc.renovationPhotos)
                    appendNewByID(&re.documents, inc.documents)
                    reArr[idx] = re
                } else {
                    reArr.append(inc)
                    newRECount += 1
                }
            }
            finance.realEstates = reArr
            result.realEstates = newRECount
        }

        return result
    }

    private static func mergeItems<T: Identifiable>(existing: [T], incoming: [T]) -> [T] {
        let existingIDs = Set(existing.map(\.id))
        return incoming.filter { !existingIDs.contains($0.id) }
    }

    /// 只補進 dst 中不存在（依 id）的項目；家庭成員與部屬深度合併共用。
    private static func appendNewByID<T: Identifiable>(_ dst: inout [T], _ src: [T]) {
        let ids = Set(dst.map(\.id))
        dst.append(contentsOf: src.filter { !ids.contains($0.id) })
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
        exportJSON(SubordinateExport(
            subordinates: life.subordinates,
            departments: life.departments,
            gradeTitles: life.gradeTitles
        ))
    }

    /// 純 payload 版本：只碰 struct 快照，不觸及 @Published，可安全在背景執行緒呼叫。
    static func exportJSON(_ payload: SubordinateExport) -> Data {
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
        var reportsMerged = 0
        var shiftsMerged = 0
        var departmentsAdded = 0
        var gradeTitlesAdded = 0
        var summary: String {
            "新增 \(added) 人、更新 \(updated) 人；班別 +\(shiftsMerged)、任務 +\(tasksMerged)、會議 +\(meetingsMerged)、報告 +\(reportsMerged)、紀錄 +\(recordsMerged)"
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

        // 部門／職等／部屬最多各觸發一次 life.subordinates/departments/gradeTitles 的指派，
        // 每次都各自觸發 LifeStore.save() 把全部 13 個集合一起重編碼；比照 UnifiedImporter
        // 既有的 withBatch 用法，整段包起來只存檔一次。
        life.withBatch {
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
                        r.reportsMerged  += appendNew(&s.weeklyReports, inc.weeklyReports)
                        r.shiftsMerged   += appendNewShifts(&s.shifts, inc.shifts)
                        _ = appendNew(&s.equipments, inc.equipments)
                        if s.plantArea.isEmpty, !inc.plantArea.isEmpty { s.plantArea = inc.plantArea }
                        if s.joinDate == nil { s.joinDate = inc.joinDate }
                        subs[idx] = s
                        r.updated += 1
                    } else {
                        subs.append(inc); r.added += 1
                    }
                }
                life.subordinates = subs   // withBatch 內：與其餘 department/gradeTitle 變更合併只存檔一次
            }
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
        var existingDays = Set(arr.map { cal.startOfDay(for: $0.date) })
        var added = 0
        for sh in incoming {
            let day = cal.startOfDay(for: sh.date)
            if !existingDays.contains(day) {
                arr.append(sh)
                existingDays.insert(day)
                added += 1
            }
        }
        return added
    }
}
