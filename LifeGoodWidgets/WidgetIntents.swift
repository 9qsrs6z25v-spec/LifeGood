import Foundation
import AppIntents

// MARK: - 只在小工具裡跑的 AppIntent：一按就記、復原、隱藏金額開關（小工具 v2）
//
// 只屬於「LifeGoodWidgets」target。規格見 scratchpad/widgets/v2/brief.md 的 G3-1。
//
// 三個都 openAppWhenRun = false，而且型別只在小工具 target：系統在小工具的行程裡跑完 perform，
// 不開 App（主控定案 10 的另一半；要開 App 的 LifeGoodOpenIntent 在共用的 WidgetActions.swift）。
//
// • QuickRecordIntent：一按就記的範本按鈕。把範本原樣變成一筆 QuickRecordEntry 寫進收件匣
//   （App Group 的 Widgets/quick_inbox_v1/<UUID>.json），App 下次打開、回前景時收進帳本。
//   AppIntent 的參數只能是單純型別，所以範本的每個欄位各一個參數；車子 UUID 用字串，沒有寫 ""。
//   **這裡不算錢**：金額原樣抄進收件匣，「NT$65」也是 App 寫在範本裡的字。
// • UndoQuickRecordIntent：「✓ 已記…・復原」的復原。App 還沒收走才刪得掉（QuickRecordInbox.undo）。
// • SetHideAmountsIntent：控制中心「隱藏金額」開關（ControlWidgetToggle 的 action）。
//   寫 App Group 的 UserDefaults，然後重畫全部小工具＋這個控制項。
//
// 參數命名：instance 參數不取名 title／description（跟 static 同名容易混），名稱用 entryTitle。

// MARK: - 一按就記

struct QuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "一按就記"
    static var description = IntentDescription("把常記的那一筆記進 LifeGood 的待入帳")
    /// 不開 App：在小工具的行程裡寫完收件匣就結束
    static var openAppWhenRun: Bool = false

    @Parameter(title: "範本")
    var templateId: String

    @Parameter(title: "名稱")
    var entryTitle: String

    @Parameter(title: "金額")
    var amount: Double

    @Parameter(title: "金額字")
    var amountText: String

    @Parameter(title: "分類")
    var categoryKey: String

    /// 車子 UUID 字串；沒有連車是 ""
    @Parameter(title: "車")
    var vehicleId: String

    /// VehicleVariableCategory.rawValue；沒有是 ""
    @Parameter(title: "車子分類")
    var vehicleCategoryKey: String

    init() {}

    /// 範本的每個欄位逐一抄過來（nil 寫 ""）
    init(template t: WidgetQuickTemplate) {
        self.templateId = t.id
        self.entryTitle = t.title
        self.amount = t.amount
        self.amountText = t.amountText
        self.categoryKey = t.categoryKey
        self.vehicleId = t.vehicleId?.uuidString ?? ""
        self.vehicleCategoryKey = t.vehicleCategoryKey ?? ""
    }

    func perform() async throws -> some IntentResult {
        let carCategory: String? = vehicleCategoryKey.isEmpty ? nil : vehicleCategoryKey
        let entry = QuickRecordEntry(templateId: templateId,
                                     title: entryTitle,
                                     amount: amount,
                                     amountText: amountText,
                                     categoryKey: categoryKey,
                                     vehicleId: UUID(uuidString: vehicleId),
                                     vehicleCategoryKey: carCategory)
        // 同一顆 3 秒內連按兩次只記一筆（.ignoredDoubleTap）；寫成功才叫 App
        if QuickRecordInbox.add(entry) == .added {
            QuickRecordInbox.postChanged()
        }
        // 「✓ 已記…・復原」「待入帳 N 筆」立刻出現（系統按完也會自己重畫，多叫一次無害）
        WidgetRefresh.reload([WidgetKind.quickRecord])
        return .result()
    }
}

// MARK: - 復原

struct UndoQuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "復原一按就記"
    static var description = IntentDescription("把剛剛一按就記的那一筆拿掉（LifeGood 還沒收進帳本之前才拿得掉）")
    static var openAppWhenRun: Bool = false

    /// 收件匣那一筆的 id（UUID 字串）
    @Parameter(title: "待入帳")
    var entryId: String

    init() {}

    init(entryId: UUID) {
        self.entryId = entryId.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: entryId), QuickRecordInbox.undo(id: id) {
            QuickRecordInbox.postChanged()
        }
        WidgetRefresh.reload([WidgetKind.quickRecord])
        return .result()
    }
}

// MARK: - 隱藏金額（控制中心開關）

struct SetHideAmountsIntent: SetValueIntent {
    static var title: LocalizedStringResource = "隱藏金額"
    static var description = IntentDescription("把所有 LifeGood 小工具的金額遮起來或打開")
    static var openAppWhenRun: Bool = false

    /// 系統按開關時把新的值放進來（true＝遮起來）
    @Parameter(title: "隱藏金額")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetHideAmounts.set(value)
        WidgetRefresh.afterHideAmountsChanged()
        return .result()
    }
}
