// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.642 mac3 G2] 變動支出表格 9 欄的具名 Cell＋組頭（judge_mac §Q8-3；brief §2 G2 MacVariableCells）。
//
// • 每格一個小 View，字在建列時就算好（MacVariableRow），這裡只排版；不包 AnyView。
// • 金額、我的份在 Cell 裡靠右＋等寬數字（Table 不用 .alignment(）。
// • 同行那格不能選取拷貝（不加文字選取）；⌘C 也不帶（MacVariableCopy 白名單）。

import SwiftUI

struct MacVariableTimeCell: View {
    let row: MacVariableRow

    var body: some View {
        Text(row.timeText)
            .monospacedDigit()
            .lineLimit(1)
    }
}

struct MacVariableTitleCell: View {
    let row: MacVariableRow

    var body: some View {
        Text(row.title)
            .lineLimit(1)
    }
}

struct MacVariableCategoryCell: View {
    let row: MacVariableRow

    var body: some View {
        Text(row.category)
            .lineLimit(1)
    }
}

struct MacVariableAmountCell: View {
    let row: MacVariableRow

    var body: some View {
        Text(row.amountText)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct MacVariableMineCell: View {
    let row: MacVariableRow

    var body: some View {
        Text(row.mineText)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct MacVariablePayCell: View {
    let row: MacVariableRow

    var body: some View {
        Text(row.payText)
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
    }
}

/// 同行（只顯示；不能選取拷貝）
struct MacVariableWithCell: View {
    let row: MacVariableRow

    var body: some View {
        Text(row.with)
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
    }
}

struct MacVariablePlaceCell: View {
    let row: MacVariableRow

    var body: some View {
        Text(row.place)
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
    }
}

struct MacVariableNoteCell: View {
    let row: MacVariableRow

    var body: some View {
        Text(row.note)
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
    }
}

// MARK: - 組頭「11/23 週日〔今天〕　　3 筆・NT$1,340（你的份 NT$1,100）」

struct MacVariableDayHeader: View {
    let day: MacVariableDay

    var body: some View {
        HStack(spacing: 8) {
            Text(day.title)
                .fontWeight(.semibold)
                .monospacedDigit()
            MacVariableDayBadge(text: day.badge)
            Spacer(minLength: 8)
            Text(day.summary)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
    }
}

/// 「今天」「昨天」小膠囊（其他天沒有）
struct MacVariableDayBadge: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
        }
    }
}
