// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.644 mac4 G2] 固定支出表格 8 欄的具名 Cell＋組頭（judge_mac §R8、§Q8 Table 防超時）。
//
// • 每格一個小 View，字在建列時就算好（MacFixedRow），這裡只排版；不包型別抹除。
// • 已停止整列淡：只在 Cell 裡 .opacity(row.dimmed ? 0.45 : 1.0)（Table 列上不加修飾器）。
// • 金額、月均在 Cell 裡靠右＋等寬數字（Table 欄不設對齊）；下次扣款 ≤ 1 天橘色，其餘灰。
// • 這頁沒有拷貝（不加文字選取、不接 ⌘C）。

import SwiftUI

struct MacFixedTitleCell: View {
    let row: MacFixedRow

    var body: some View {
        Text(row.title)
            .lineLimit(1)
            .opacity(row.dimmed ? 0.45 : 1.0)
    }
}

struct MacFixedCategoryCell: View {
    let row: MacFixedRow

    var body: some View {
        Text(row.category)
            .lineLimit(1)
            .opacity(row.dimmed ? 0.45 : 1.0)
    }
}

struct MacFixedPeriodCell: View {
    let row: MacFixedRow

    var body: some View {
        Text(row.period)
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
            .opacity(row.dimmed ? 0.45 : 1.0)
    }
}

struct MacFixedAmountCell: View {
    let row: MacFixedRow

    var body: some View {
        Text(row.amountText)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(row.dimmed ? 0.45 : 1.0)
    }
}

struct MacFixedMonthlyCell: View {
    let row: MacFixedRow

    var body: some View {
        Text(row.monthlyText)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(row.dimmed ? 0.45 : 1.0)
    }
}

struct MacFixedNextDueCell: View {
    let row: MacFixedRow

    var body: some View {
        Text(row.nextDueText)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(row.warn ? Color.orange : Color.secondary)
            .opacity(row.dimmed ? 0.45 : 1.0)
    }
}

struct MacFixedPayCell: View {
    let row: MacFixedRow

    var body: some View {
        Text(row.payText)
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
            .opacity(row.dimmed ? 0.45 : 1.0)
    }
}

struct MacFixedStatusCell: View {
    let row: MacFixedRow

    var body: some View {
        Text(row.status)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
            .opacity(row.dimmed ? 0.45 : 1.0)
    }
}

// MARK: - 組頭「貸款　3 筆　　　　每月 NT$28,000」（整串一組：「依金額排序　24 筆」）

struct MacFixedGroupHeader: View {
    let group: MacFixedGroupSection

    var body: some View {
        HStack(spacing: 8) {
            Text(group.title)
                .fontWeight(.semibold)
            Text(group.countText)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
            Spacer(minLength: 8)
            Text(group.headerText)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
    }
}
