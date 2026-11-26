// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.645 mac5 G3] 記帳小鎮的畫面（judge_mac.md §S6-6）：總覽頂端一條遊戲列＋徽章 popover。
//
// • 一個金額、一個名字都不顯示；不罰、不比較、不誘導花錢、沒有倒數與紅點（§S4-0）；沒點亮的一律灰，不用紅、不打叉。
// • 減少動態效果：最外層 .symbolEffectsRemoved(reduceMotion)；膠囊直接出現、直接消失。
// • popover 內容一律 .macStores(app)（同 sheet 規則）。
// • 主控骨架：MacGameStrip、MacGameBoardPopover 無參數（總覽那行用）；G3 換內容。
// • 顏色只用 MacGameTint、MacPageTheme.green、MacPalette（＋系統 secondary）；字一律 MacGameText（照 sim_mac5 GAME_TEXT）。
// • 這裡只畫：不算、不寫（算與寫都在 MacGameModel 的 Combine sink／計時器／按鈕動作）。
// • [v25.646 mac6 G3b] 第二排加〔今天沒花錢〕〔月曆〕、第三排回顧卡、燈多打勾的葉子（跳一下）、徽章 popover 4／4／2＋自己的紀錄。
//   月曆 popover、回顧卡、紀錄兩行在 MacGameCalendarView.swift。

import SwiftUI

/// 總覽頂端的遊戲列（關掉、沒有帳號雜湊、沒有帳本 → 什麼都不畫）
struct MacGameStrip: View {
    @EnvironmentObject private var game: MacGameModel
    @EnvironmentObject private var app: MacAppModel
    @EnvironmentObject private var money: MacMoneyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showBoard = false
    @State private var showCalendar = false

    var body: some View {
        if !game.enabled || money.accountHash == nil || !money.account.hasLedger {
            EmptyView()
        } else {
            strip
        }
    }

    private var strip: some View {
        VStack(alignment: .leading, spacing: 8) {
            MacGameStripTop(snap: game.snapshot, toast: game.toast, bounce: game.bounce, onToast: { game.dismissToast() })
            if game.snapshot.hasProgress {
                bottomRow
            }
            // sim6: game#34（第三排：每週回顧卡；上週沒東西可講就沒有）
            if let r = game.snapshot.review {
                MacGameReviewCard(review: r, onDone: { game.dismissReview() })
            }
        }
        .macBoard(.green)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .macAppear(0)
        .symbolEffectsRemoved(reduceMotion)
    }

    /// 第二行：連續週數｜本週 7 盞燈｜本月三顆星｜（第一次那行字）〔徽章 N／6〕（還沒開始：整行不畫，沒有 0 週、0／3）
    private var bottomRow: some View {
        HStack(spacing: 14) {
            MacGameStreakLine(snap: game.snapshot)
            MacGameLights(lights: game.snapshot.lights)
            if let m = game.snapshot.current {
                MacGameStars(month: m, showsPending: true)
            }
            Spacer(minLength: 8)
            if let note = game.snapshot.backfillNote {
                MacGameNote(text: note)
            }
            if let note = game.snapshot.readOnlyNote {
                MacGameNote(text: note)
            }
            checkButton
            calendarButton
            badgeButton
        }
    }

    // sim6: game#26（〔今天沒花錢〕：今天能打卡才有；按了那盞燈變打勾葉子、跳一下）
    @ViewBuilder
    private var checkButton: some View {
        if game.snapshot.canCheckToday {
            Button {
                game.toggleNoSpend(MacGameRules.calendar.startOfDay(for: Date()))
            } label: {
                Label(MacGameText.noSpendButton, systemImage: "leaf")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(MacGameText.noSpendHelp)
        }
    }

    // sim6: game#32（〔月曆〕：打開＝算這個月；popover 內容 .macStores(app)）
    private var calendarButton: some View {
        Button {
            game.openCalendar()
            showCalendar = true
        } label: {
            Image(systemName: "calendar")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(MacGameText.calendarHelp)
        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
            MacGameCalendarPopover().macStores(app)
        }
    }

    private var badgeButton: some View {
        Button {
            showBoard = true
        } label: {
            Label(MacGameText.badgeCount(game.snapshot.litCount), systemImage: "rosette")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .popover(isPresented: $showBoard, arrowEdge: .bottom) {
            MacGameBoardPopover().macStores(app)
        }
    }
}

// MARK: - 遊戲列第一行：景圖示（點亮時跳一下）｜等級｜經驗條｜大約再記 N 週｜點亮膠囊｜手寫招呼

private struct MacGameStripTop: View {
    let snap: MacGameSnapshot
    let toast: MacGameToast?
    let bounce: Int
    let onToast: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MacIconBadge(icon: snap.stageIcon, top: MacPageTheme.green.top, bottom: MacPageTheme.green.bottom,
                         size: 36, solid: true)
                .symbolEffect(.bounce, value: bounce)
            MacGameStageTitle(snap: snap)
            if snap.hasProgress {
                MacGameProgressLine(snap: snap)
            }
            Spacer(minLength: 8)
            if let t = toast {
                MacGameToastPill(toast: t, onTap: onToast)
            }
            MacGreeting(text: MacGameText.greeting)
        }
    }
}

/// 「Lv.3 街角」；還沒開始：「Lv.0 空地・記下第一筆，小鎮就開始蓋」
private struct MacGameStageTitle: View {
    let snap: MacGameSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(snap.titleText)
            .font(.headline)
            .foregroundStyle(MacPalette(scheme).ink)
            .lineLimit(1)
    }
}

/// 經驗條（寬 140）＋「大約再記 N 週到菜園」；經驗值數字只在 help
private struct MacGameProgressLine: View {
    let snap: MacGameSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            MacMeterBar(fraction: snap.fraction, tint: MacPageTheme.green.top)
                .frame(width: 140)
            Text(MacGameRules.nextText(xp: snap.xp))
                .font(.caption)
                .foregroundStyle(MacPalette(scheme).label)
                .lineLimit(1)
        }
        .help(MacGameText.xpText(snap.xp, next: snap.next))
    }
}

/// 「連續 6 週・9/7 那週起」／「這週記一筆，就開始算連續週數」
private struct MacGameStreakLine: View {
    let snap: MacGameSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MacPalette(scheme).label)
            Text(MacGameText.streakText(snap.streakWeeks, since: snap.streakSince, calendar: MacGameRules.calendar))
                .font(.caption.weight(.semibold))
                .foregroundStyle(MacPalette(scheme).capsuleText)
                .lineLimit(1)
        }
    }
}

/// 點亮膠囊：直接出現（不包 withAnimation）；點一下收掉
private struct MacGameToastPill: View {
    let toast: MacGameToast
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        Button(action: onTap) {
            MacGameToastContent(toast: toast, p: p, star: MacGameTint(scheme).star)
                .padding(.horizontal, 10)
                .frame(height: MacTheme.pillHeight)
                .background(p.cellFill, in: Capsule())
                .overlay(Capsule().stroke(p.cellStroke, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }
}

private struct MacGameToastContent: View {
    let toast: MacGameToast
    let p: MacPalette
    let star: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(star)
            Text(toast.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(p.capsuleText)
                .lineLimit(1)
            MacGreeting(text: toast.script)
        }
    }
}

/// 第一次打開那一行小字
private struct MacGameNote: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(MacPalette(scheme).label)
            .lineLimit(1)
    }
}

// MARK: - 遊戲列下排：本週 7 盞燈、本月三顆星

private struct MacGameLights: View {
    let lights: [MacGameLight]
    @Environment(\.colorScheme) private var scheme

    /// 今天是這週第幾天（週一 0 … 週日 6；只讀時間、不寫）
    private var todayIndex: Int {
        (MacGameRules.calendar.component(.weekday, from: Date()) + 5) % 7
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("本週")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MacPalette(scheme).label)
                .help(MacGameText.lightsHelp)
            ForEach(lights.indices, id: \.self) { i in
                MacGameLightCell(light: lights[i], day: i < MacGameText.weekdays.count ? MacGameText.weekdays[i] : "",
                                 isToday: i == todayIndex)
            }
        }
    }
}

private struct MacGameLightCell: View {
    let light: MacGameLight
    let day: String
    let isToday: Bool
    @Environment(\.colorScheme) private var scheme
    /// [v25.646 mac6] 今天那盞按了〔今天沒花錢〕跳一下（外層 symbolEffectsRemoved 擋減少動態效果）
    @EnvironmentObject private var game: MacGameModel

    private var icon: String {
        switch light {
        case .lamp: return "circle.fill"
        case .leaf: return "leaf.fill"
        case .empty: return "circle"
        case .checked: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        let t = MacGameTint(scheme)
        switch light {
        case .lamp: return t.star
        case .leaf: return t.leaf
        case .empty: return MacGameTint.dimStroke
        case .checked: return t.leaf
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .symbolEffect(.bounce, value: isToday ? game.checkBounce : 0)
                .frame(width: 16, height: 16)
            Text(day)
                .font(.caption2)
                .foregroundStyle(MacPalette(scheme).label)
        }
        .help(MacGameText.lightHelp(light, isToday: isToday))
    }
}

/// 「11 月」＋三顆星（滑過去看說明）；遊戲列的本月旁邊灰小字「月底結算」
private struct MacGameStars: View {
    let month: MacGameMonth
    var showsPending: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            Text(MacGameText.monthLabel(month.start, calendar: MacGameRules.calendar))
                .font(.caption.weight(.semibold))
                .foregroundStyle(MacPalette(scheme).label)
            MacGameStarIcon(star: month.record, help: MacGameText.starHelp(month, which: 0))
            MacGameStarIcon(star: month.hold, help: MacGameText.starHelp(month, which: 1))
            MacGameStarIcon(star: month.save, help: MacGameText.starHelp(month, which: 2))
            if showsPending && month.isCurrent {
                Text(MacGameText.pending)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 一顆星：拿到＝實心金星；還沒／月底結算＝灰空心；不算＝灰橫線
private struct MacGameStarIcon: View {
    let star: MacGameStar
    let help: String
    @Environment(\.colorScheme) private var scheme

    private var icon: String {
        switch star {
        case .got: return "star.fill"
        case .notYet, .pending: return "star"
        case .notCounted: return "minus"
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(star == .got ? MacGameTint(scheme).star : MacGameTint.dimIcon)
            .frame(width: 16, height: 16)
            .help(help)
    }
}

// MARK: - 〔徽章 N／6〕的 popover

/// 〔徽章 N／6〕的 popover（寬 420）
struct MacGameBoardPopover: View {
    @EnvironmentObject private var game: MacGameModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MacGameBoardHeader(snap: game.snapshot)
            Divider()
            MacGameSectionTitle(text: MacGameText.badgeHeader)
            MacGameBadgeGrid(snap: game.snapshot)
            if !game.snapshot.settled.isEmpty {
                MacGameSectionTitle(text: MacGameText.monthsHeader)
                MacGameMonthGrid(months: game.snapshot.settled)
            }
            // sim6: game#36（自己的紀錄：最長連續、最多星的月；都沒有就整段不畫）
            if !game.snapshot.records.isEmpty {
                MacGameSectionTitle(text: MacGameText.recordsHeader)
                MacGameRecordLines(records: game.snapshot.records)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 480)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(MacGameText.footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(MacGameText.turnOff) {
                // popover 先收，下一個 runloop 才寫（dismiss 後寫 store 放下一個 runloop；同 MacEditor.swift:2387-2389 先抓 local）
                let game = self.game
                dismiss()
                DispatchQueue.main.async { game.setEnabled(false) }
            }
        }
    }
}

private struct MacGameSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
    }
}

/// 景圖示＋「Lv.3 街角」＋「經驗值 640／1,000」＋經驗條
private struct MacGameBoardHeader: View {
    let snap: MacGameSnapshot

    var body: some View {
        HStack(spacing: 12) {
            MacIconBadge(icon: snap.stageIcon, top: MacPageTheme.green.top, bottom: MacPageTheme.green.bottom,
                         size: 44, solid: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(snap.titleText)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text(MacGameText.xpText(snap.xp, next: snap.next))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                MacMeterBar(fraction: snap.fraction, tint: MacPageTheme.green.top)
                    .frame(width: 200)
            }
            Spacer(minLength: 8)
            MacGreeting(text: MacGameText.greeting)
        }
    }
}

/// 6 枚徽章 3×2
private struct MacGameBadgeGrid: View {
    let snap: MacGameSnapshot

    // sim6: game#47（10 枚每排 4：4／4／2）
    private static let rows: [[MacGameBadge]] = MacGameDays.badgeRows(MacGameBadge.all, per: 4)

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 14) {
            ForEach(0..<Self.rows.count, id: \.self) { r in
                GridRow {
                    ForEach(Self.rows[r]) { b in
                        MacGameBadgeCell(badge: b, lit: snap.lit.contains(b.id), earnedAt: snap.earned[b.id])
                    }
                }
            }
        }
    }
}

private struct MacGameBadgeCell: View {
    let badge: MacGameBadge
    let lit: Bool
    /// 點亮時間（nil＝還沒寫進本機，例如快照時只顯示）
    let earnedAt: Double?

    private var theme: MacPageTheme {
        switch badge.tone {
        case .medal: return MacGameTint.medal
        case .save: return MacGameTint.save
        case .gold: return MacGameTint.gold
        }
    }

    private var detail: String {
        lit ? MacGameText.earnedText(earnedAt ?? 0, calendar: MacGameRules.calendar) : badge.hint
    }

    var body: some View {
        VStack(spacing: 6) {
            MacMedalFrame(icon: badge.icon, top: theme.top, bottom: theme.bottom, earned: lit, size: 40)
            Text(badge.name)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
            MacGameBadgeDetail(text: detail)
        }
        .frame(width: 104, alignment: .top)
    }
}

private struct MacGameBadgeDetail: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 結算月（新到舊、最多 12 個）兩欄：「10 月」＋三顆星（不算的是灰橫線）
private struct MacGameMonthGrid: View {
    let months: [MacGameMonth]

    private var pairs: [Int] { Array(stride(from: 0, to: months.count, by: 2)) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
            ForEach(pairs, id: \.self) { i in
                GridRow {
                    MacGameStars(month: months[i])
                    if i + 1 < months.count {
                        MacGameStars(month: months[i + 1])
                    }
                }
            }
        }
    }
}

// MARK: - 畫面用的小值（只讀 snapshot）

fileprivate extension MacGameSnapshot {
    /// 「Lv.3 街角」；還沒開始而且 Lv.0：「Lv.0 空地・記下第一筆，小鎮就開始蓋」
    var titleText: String {
        hasProgress ? MacGameText.stripTitle(level) : MacGameText.notStarted
    }

    var hasProgress: Bool { started || level > 0 }

    /// 經驗條：(顯示 − T(level)) ÷ (T(level＋1) − T(level))，夾在 0…1
    var fraction: Double {
        let span = max(1, next - floor)
        return min(max(Double(xp - floor) / Double(span), 0), 1)
    }

    /// 點亮幾枚（只算這一批 6 枚）
    var litCount: Int {
        MacGameBadge.all.filter { lit.contains($0.id) }.count
    }
}
