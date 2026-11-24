// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.641 mac2 G1] 收入表單的週期、固定薪水、結束日欄位（judge_mac §P8 表單、§P5；brief.md §2 G1 第 22～24 條）。
// MacEditor.swift 的 MacEditorFields 在「分類」後面放 MacIncomePeriodField、「日期」後面放 MacIncomeEndField（只在收入時）。
// 每個 View 一個小 struct、body 最多一層 if；不在 body 寫 store（只改表單自己的 @Binding draft）。
// 原因選單、週期選單一律用 rawValue（共用檔的字），這裡不寫那幾個字面值。

import SwiftUI

// MARK: - 週期／固定薪水

/// 新記＋薪水：〔固定薪水〕開關；新記＋非薪水：週期選單（預設單次）；改既有的週期收入：只顯示文字＋鎖頭；單次：不顯示
struct MacIncomePeriodField: View {
    let isNew: Bool
    @Binding var draft: MacEntryRules.Draft
    let original: Income?

    var body: some View {
        if isNew {
            MacIncomeFormNewPeriod(draft: $draft)
        } else if let original, original.period != .once {
            LabeledContent("週期") {
                MacIncomeLockedText(text: Self.periodText(original), reason: MacEditPolicy.reasonIncomePeriod)
            }
        }
    }

    /// 「每月（固定薪水）」「每年」
    static func periodText(_ i: Income) -> String {
        i.period.rawValue + (i.isFixedSalary ? "（固定薪水）" : "")
    }
}

private struct MacIncomeFormNewPeriod: View {
    @Binding var draft: MacEntryRules.Draft

    var body: some View {
        if draft.incomeCategory == .salary {
            MacIncomeFormFixedToggle(isOn: $draft.isFixedSalary)
        } else {
            Picker("週期", selection: $draft.period) {
                ForEach(IncomePeriod.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
        }
    }
}

private struct MacIncomeFormFixedToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("固定薪水")
                Text("每月自動計入收入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 結束日

/// 新記：薪水＋固定薪水才顯示；改既有的：週期收入才顯示。reason 不是 nil＝只顯示現在的字＋鎖頭
struct MacIncomeEndField: View {
    let isNew: Bool
    @Binding var draft: MacEntryRules.Draft
    /// 開始那天（DatePicker 不給選更早）
    let start: Date
    /// verdict.reason(.endDate)
    let reason: String?
    /// 改既有的那筆（鎖住時顯示原本的結束日、原因）；新記＝nil
    let original: Income?

    private var visible: Bool {
        if isNew { return draft.incomeCategory == .salary && draft.isFixedSalary }
        return (original?.period ?? .once) != .once
    }

    var body: some View {
        if visible {
            MacIncomeFormEndRows(draft: $draft, start: start, reason: reason,
                                 lockedText: Self.endText(original))
        }
    }

    /// 「2026/12/31（離職）」「2026/12/31」「沒有」
    static func endText(_ i: Income?, calendar: Calendar = .current) -> String {
        guard let i, let end = i.endDate else { return "沒有" }
        let c = calendar.dateComponents([.year, .month, .day], from: end)
        let day = "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
        guard let r = i.endReason else { return day }
        return day + "（" + r.rawValue + "）"
    }
}

private struct MacIncomeFormEndRows: View {
    @Binding var draft: MacEntryRules.Draft
    let start: Date
    let reason: String?
    let lockedText: String

    var body: some View {
        if let reason {
            LabeledContent("結束日") {
                MacIncomeLockedText(text: lockedText, reason: reason)
            }
        } else {
            MacIncomeFormEndEditor(end: $draft.end, start: start)
        }
    }
}

private struct MacIncomeFormEndEditor: View {
    @Binding var end: MacIncomeEndDraft
    let start: Date

    var body: some View {
        Toggle("設結束日", isOn: $end.enabled)
        if end.enabled {
            MacIncomeFormEndDetail(end: $end, start: start)
        }
    }
}

private struct MacIncomeFormEndDetail: View {
    @Binding var end: MacIncomeEndDraft
    let start: Date

    var body: some View {
        DatePicker("結束日", selection: $end.day, in: start..., displayedComponents: .date)
        Picker("原因", selection: $end.reason) {
            ForEach(SalaryEndReason.allCases) { r in
                Text(r.rawValue).tag(r)
            }
        }
        Text("結束月份（含）之後不再計入每月收入")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - 鎖頭（MacEditor.swift 的 MacLockedValue 是 private，這裡自己一份）

/// 灰字＋鎖頭，滑過去顯示原因
struct MacIncomeLockedText: View {
    let text: String
    let reason: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .foregroundStyle(.secondary)
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
        }
        .help(reason)
    }
}
