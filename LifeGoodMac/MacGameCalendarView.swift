// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G3b] 記帳月曆 popover（judge_mac.md §T6-5）：一格一個記號、沒記的日子不打叉、能按的才包 Button、第 8 欄週打勾。
//
// • 遊戲列第二排〔徽章〕左邊那顆鈕開（MacGameViews，同 MGV:67 寫法），內容外面掛 .macStores(app)；寬 360；Grid／GridRow；
//   格子拆 MacGameCalCell（28×34）；popover 裡不放 ScrollView。
// • 主控骨架：`struct MacGameCalendarPopover: View` 無參數、回 EmptyView()；G3b 換內容。
// • [G3b] 這裡只畫：月曆格子由 MacGameModel.openCalendar／stepCalendar／recompute 算好（calendarGrid）；按格子＝toggleNoSpend（按鈕動作）。
//   同檔還有遊戲列第三排的回顧卡（MacGameReviewCard）、徽章 popover 的「自己的紀錄」（MacGameRecordLines）。
// • 一個金額、一個名字都不顯示；不分深淺、不打叉、不用紅；顏色只用 MacGameTint、MacPalette、系統 secondary。

import SwiftUI

// sim6: game#32（popover：標頭 ‹ 月份 ›、表頭一到日＋第 8 欄、4～6 列格子、底部兩行；寬 360、內距 14）
struct MacGameCalendarPopover: View {
    @EnvironmentObject private var game: MacGameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let g = game.calendarGrid {
                MacGameCalHeader(grid: g, onStep: { n in game.stepCalendar(n) })
                MacGameCalTable(grid: g, onTap: { d in game.toggleNoSpend(d) })
                Divider()
                MacGameCalFooter(lines: g.footer)
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}

/// 〔‹〕「2026 年 11 月」〔›〕（不能翻到未來、不能翻到開始記帳以前）
private struct MacGameCalHeader: View {
    let grid: MacGameCalendarGrid
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onStep(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!grid.canBack)
            Spacer(minLength: 4)
            Text(grid.title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                onStep(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!grid.canForward)
        }
    }
}

/// 表頭一行＋每週一列（7 格＋第 8 欄）
private struct MacGameCalTable: View {
    let grid: MacGameCalendarGrid
    let onTap: (Date) -> Void

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                ForEach(MacGameText.weekdays, id: \.self) { w in
                    MacGameCalWeekday(text: w)
                }
                MacGameCalWeekday(text: "")
            }
            // 一列：7 格＋第 8 欄（這週算進連續週數＝打勾；沒算＝空白，不打叉）
            ForEach(grid.weeks) { week in
                GridRow {
                    ForEach(week.days) { day in
                        MacGameCalCell(day: day, onTap: onTap)
                    }
                    MacGameCalWeekMark(counted: week.counted)
                }
            }
        }
    }
}

private struct MacGameCalWeekday: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

// sim6: game#32（能按的格子才是 Button（plain）：補按／取消；其餘只畫，help 寫那天的記號）
private struct MacGameCalCell: View {
    let day: MacGameCalDay
    let onTap: (Date) -> Void

    var body: some View {
        if day.canCheck || day.canUncheck {
            Button {
                onTap(day.date)
            } label: {
                MacGameCalFace(day: day)
            }
            .buttonStyle(.plain)
            .help(day.help)
        } else {
            MacGameCalFace(day: day)
                .help(day.help)
        }
    }
}

/// 28×34：上面幾號、下面一個記號；鄰月淡 0.45；今天還沒記＝細框
private struct MacGameCalFace: View {
    let day: MacGameCalDay
    @Environment(\.colorScheme) private var scheme

    private var ring: Color {
        day.mark == .today ? MacPalette(scheme).hint : Color.clear
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(String(day.day))
                .font(.caption2)
                .foregroundStyle(MacPalette(scheme).label)
            MacGameCalSymbol(mark: day.mark)
        }
        .frame(width: 28, height: 34)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ring, lineWidth: 1))
        .contentShape(Rectangle())
        .opacity(day.inMonth ? 1 : 0.45)
    }
}

/// 金燈＝實心圓、打勾的葉子、葉子、今天空心圓、空白不畫（沒有叉）
private struct MacGameCalSymbol: View {
    let mark: MacGameDayMark
    @Environment(\.colorScheme) private var scheme

    private var icon: String? {
        switch mark {
        case .lamp: return "circle.fill"
        case .checked: return "checkmark.circle.fill"
        case .leaf: return "leaf.fill"
        case .today: return "circle"
        case .blank: return nil
        }
    }

    private var color: Color {
        let t = MacGameTint(scheme)
        switch mark {
        case .lamp: return t.star
        case .checked, .leaf: return t.leaf
        case .today, .blank: return MacGameTint.dimStroke
        }
    }

    var body: some View {
        if let name = icon {
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16, height: 16)
        } else {
            Color.clear
                .frame(width: 16, height: 16)
        }
    }
}

private struct MacGameCalWeekMark: View {
    let counted: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(MacGameTint(scheme).leaf)
            .opacity(counted ? 1 : 0)
            .frame(width: 18, height: 34)
            .help(counted ? MacGameText.weekCounted : "")
    }
}

/// 「連續 6 週・9/7 那週起」／「打卡只存在這台 Mac，可以補按 6 天內」
private struct MacGameCalFooter: View {
    let lines: [String]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.self) { s in
                Text(s)
                    .font(.caption)
                    .foregroundStyle(MacPalette(scheme).label)
            }
        }
    }
}

// MARK: - 遊戲列第三排：每週回顧卡

// sim6: game#34（白卡：「上週回顧・11/23～11/29」＋一行；右邊手寫 Nice week!＋〔好〕；不跟上上週比、沒有金額與名字）
struct MacGameReviewCard: View {
    let review: MacGameReview
    let onDone: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        HStack(spacing: 10) {
            MacGameReviewText(review: review, p: p)
            Spacer(minLength: 8)
            MacGreeting(text: MacGameText.scriptWeek)
            Button(MacGameText.reviewDone, action: onDone)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(p.cellFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.cellStroke, lineWidth: 0.75))
    }
}

private struct MacGameReviewText: View {
    let review: MacGameReview
    let p: MacPalette

    var body: some View {
        HStack(spacing: 10) {
            Text(review.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(p.ink)
                .lineLimit(1)
            Text(review.text)
                .font(.caption)
                .foregroundStyle(p.label)
                .lineLimit(1)
        }
    }
}

// MARK: - 徽章 popover：自己的紀錄

// sim6: game#36（「最長連續：12 週（9/7 那週起）」「最多星的月：2026 年 10 月・3 顆」＋「只跟自己比」）
struct MacGameRecordLines: View {
    let records: MacGameRecords

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(MacGameText.recordLines(records, calendar: MacGameRules.calendar), id: \.self) { s in
                Text(s)
                    .font(.caption)
            }
            Text(MacGameText.recordsNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
