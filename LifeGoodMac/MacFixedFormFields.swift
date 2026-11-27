// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.644 mac4 G1] 表單固定支出模式的欄位（分類、週期、扣款日、停止；judge_mac §R5、§R8；brief.md §2 G1 第 29 條）。
// MacEditor.swift 的 MacFixedEditorSection 照「金額 → 名稱 → 分類 → 週期 → 扣款日 → 停止 → 付款方式 → 備註」放；新記支出多一排〔變動｜固定〕。
// 每個 View 一個小 struct、body 最多一層 if；不在 body 寫 store（只改表單自己的 @Binding draft）。
// 分類、週期、停止原因的選單一律用 rawValue（共用檔的字），這裡不寫那幾個字面值；鎖頭沿用 MacIncomeLockedText。
// 詢問框的金額字在 MacFixedCal（照抄 WealthFormat.ntd），這裡不寫金額。

import SwiftUI

// MARK: - 新記支出：〔變動｜固定〕

/// 新記支出才顯示（改既有的那筆不顯示）；固定支出頁 ⌘N 預設〔固定〕
struct MacFixedModePicker: View {
    @Binding var fixedMode: Bool

    var body: some View {
        Picker("類型", selection: $fixedMode) {
            Text("變動").tag(false)
            Text("固定").tag(true)
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - 金額下一行灰字

/// 第一期已經扣過了：存的時候會問以前的要不要跟著改（只給〔從今天起〕）
struct MacFixedAmountHint: View {
    let show: Bool

    var body: some View {
        if show {
            Text(MacEditPolicy.fixedStartedHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 分類（六類）

/// reason 不是 nil＝只顯示原本的分類＋鎖頭
struct MacFixedCategoryField: View {
    @Binding var category: FixedCategory
    let reason: String?
    let lockedName: String

    var body: some View {
        if let reason {
            LabeledContent("分類") {
                MacIncomeLockedText(text: lockedName, reason: reason)
            }
        } else {
            Picker("分類", selection: $category) {
                ForEach(MacEditPolicy.plainFixedCategories, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
        }
    }
}

// MARK: - 週期

struct MacFixedPeriodField: View {
    @Binding var recurrence: Recurrence
    let reason: String?

    var body: some View {
        if let reason {
            LabeledContent("週期") {
                MacIncomeLockedText(text: recurrence.rawValue, reason: reason)
            }
        } else {
            Picker("週期", selection: $recurrence) {
                ForEach(Recurrence.allCases, id: \.self) { r in
                    Text(r.rawValue).tag(r)
                }
            }
        }
    }
}

// MARK: - 扣款日（第一期）

/// 已開始：反灰＋鎖頭（fixed_started）；改既有、還沒開始：只能選今天以後＋提示；新記：不限
struct MacFixedDayField: View {
    @Binding var day: Date
    let isNew: Bool
    let reason: String?

    var body: some View {
        if let reason {
            LabeledContent("扣款日") {
                MacIncomeLockedText(text: Self.dayText(day), reason: reason)
            }
        } else if isNew {
            DatePicker("扣款日", selection: $day, displayedComponents: .date)
        } else {
            MacFixedFutureDay(day: $day)
        }
    }

    /// 「2026/8/10」
    static func dayText(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }
}

private struct MacFixedFutureDay: View {
    @Binding var day: Date

    private var today: Date { MacFixedCal.day(Date()) }

    var body: some View {
        DatePicker("扣款日", selection: $day, in: today..., displayedComponents: .date)
        Text(MacEditPolicy.fixedDateHint)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - 停止（最後一次扣款日＋原因；兩欄一起寫）

/// reason 不是 nil＝整區只顯示現在的停止日＋鎖頭（停在以前＝fixed_end_reopen）。
/// 打開開關時填 defaultEnd（日子＝max(今天, 第一期, 最近已扣過那期)、原因＝這個分類最可能的那個）
struct MacFixedEndField: View {
    @Binding var end: MacFixedEndDraft
    /// DatePicker 不給選更早的那天
    let lower: Date
    let defaultEnd: MacFixedEndDraft
    /// 原因選單的排序（FixedEndReason.suggested(for:)）
    let category: FixedCategory?
    let reason: String?
    let lockedText: String

    var body: some View {
        if let reason {
            LabeledContent("停止") {
                MacIncomeLockedText(text: lockedText, reason: reason)
            }
        } else {
            MacFixedEndEditor(end: $end, lower: lower, defaultEnd: defaultEnd, category: category)
        }
    }

    /// 「2026/12/31（取消訂閱）」「沒有」
    static func endText(_ e: Expense?, calendar: Calendar = .current) -> String {
        guard let e, let end = e.endDate else { return "沒有" }
        let day = MacFixedDayField.dayText(end, calendar: calendar)
        guard let r = e.endReason else { return day }
        return day + "（" + r.rawValue + "）"
    }
}

private struct MacFixedEndEditor: View {
    @Binding var end: MacFixedEndDraft
    let lower: Date
    let defaultEnd: MacFixedEndDraft
    let category: FixedCategory?

    /// 從關到開：整區換成預設（日子不會落在下限以前）
    private var toggle: Binding<Bool> {
        Binding(get: { end.enabled }, set: { on in
            if on && !end.enabled {
                end = defaultEnd
            } else {
                end.enabled = on
            }
        })
    }

    var body: some View {
        Toggle("設停止日", isOn: toggle)
        if end.enabled {
            MacFixedEndDetail(end: $end, lower: lower, category: category)
        }
    }
}

private struct MacFixedEndDetail: View {
    @Binding var end: MacFixedEndDraft
    let lower: Date
    let category: FixedCategory?

    private var reasons: [FixedEndReason] { FixedEndReason.suggested(for: category) }

    var body: some View {
        DatePicker("最後一次扣款", selection: $end.day, in: lower..., displayedComponents: .date)
        Picker("原因", selection: $end.reason) {
            ForEach(reasons) { r in
                Text(r.rawValue).tag(r)
            }
        }
        Text("那天（含）以前的期數照算，之後不再扣；不能早於最近已經扣過的那一期")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - 詢問框〔從今天起〕〔取消〕

/// 已開始那筆改金額：只給〔從今天起（以前的照舊）〕；〔取消〕是預設鍵（Return 不會誤選〔從今天起〕）
struct MacFixedAskButtons: View {
    let fromToday: @MainActor () -> Void

    var body: some View {
        Button(MacEditPolicy.askFromToday) { later() }
        Button("取消", role: .cancel) {}
            .keyboardShortcut(.defaultAction)
    }

    /// 確認框收起來之後才寫
    private func later() {
        let go = fromToday
        DispatchQueue.main.async { go() }
    }
}
