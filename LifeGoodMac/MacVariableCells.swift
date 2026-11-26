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

    // sim7: tbl7#5 金額 medium（色照舊）
    var body: some View {
        Text(row.amountText)
            .fontWeight(.medium)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct MacVariableMineCell: View {
    let row: MacVariableRow

    // sim7: tbl7#6 我的份＝珊瑚色（只有活分帳那列有字；跟誰還欠我同色）
    var body: some View {
        Text(row.mineText)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(MacPageTheme.coral.tint)
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

    // sim7: tbl7#7 組頭右邊＝合計小膠囊（變動橘）；不讀 Environment
    var body: some View {
        HStack(spacing: 8) {
            Text(day.title)
                .fontWeight(.semibold)
                .monospacedDigit()
            MacVariableDayBadge(text: day.badge)
            Spacer(minLength: 8)
            MacTableSumPill(text: day.summary, tint: MacPageTheme.orange.top)
        }
    }
}

/// 「今天」「昨天」小膠囊（其他天沒有）
struct MacVariableDayBadge: View {
    let text: String?

    // sim7: tbl7#8 「今天」「昨天」＝橘色標籤（取代 accentColor）；別天沒有
    var body: some View {
        if let text {
            MacTableDayTag(text: text, tint: MacPageTheme.orange.bottom)
        }
    }
}
