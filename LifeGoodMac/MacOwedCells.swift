// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G2] 誰還欠我的小元件（judge_mac.md §T3-5、§T3-8、§T3-9）：側欄那一列、人卡片、字首圓、詳情欄分帳區。
//
// • 側欄那一列不用 .badge(、不改 MacSidebarRow；人數膠囊自己畫（coral.tint）。
// • 人卡片 Button(.plain)；字首圓 6 色（coral、orange、blue、green、night、slate，沒有紅），色號用 unicodeScalars 穩定算
//   （MacOwedScreen.avatarIndex；不用 hashValue）。
// • 詳情欄分帳區（G3a 在 MacInspector 變動支出那一路呼叫）：唯讀＋〔看誰還欠我〕（只換頁）；沒有寫入按鈕。
// • 名字不准進 .help(、accessibilityIdentifier、log、⌘C；VoiceOver 朗讀可以（畫面上本來就看得到）。

import SwiftUI

// MARK: - 側欄

/// 側欄「變動支出」下面縮排一列「誰還欠我」＋人數膠囊（sim6: owed6#17 出現條件在 MacOwedScreen.sidebarShows）
struct MacSidebarOwedRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Label {
                Text("誰還欠我")
            } icon: {
                Image(systemName: "person.2")
                    .foregroundStyle(MacPageTheme.coral.tint)
            }
            Spacer(minLength: 4)
            if count > 0 {
                MacOwedCountPill(count: count)
            }
        }
        .padding(.leading, 12)
        .symbolRenderingMode(.hierarchical)
        .help("有人要還你錢時才出現")
    }
}

/// 人數膠囊：coral.tint@0.10 底、@0.22 框 0.6、caption2 semibold（同 MacSectionHeader 的計數膠囊）
struct MacOwedCountPill: View {
    let count: Int

    var body: some View {
        let tint = MacPageTheme.coral.tint
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 0.6))
    }
}

// MARK: - 字首圓

/// 名字第一個字的圓（空名字放 person.fill）；28pt 卡片、18pt 組頭與詳情欄
struct MacOwedAvatar: View {
    let name: String
    let size: CGFloat

    /// 6 色（沒有紅）：coral、orange、blue、green、night、slate
    static let palette: [Color] = [MacPageTheme.coral.tint, MacPageTheme.orange.top, MacPageTheme.blue.top,
                                   MacPageTheme.green.top, MacPageTheme.night.tint, MacPageTheme.slate.top]

    var body: some View {
        let fill: Color = Self.palette[MacOwedScreen.avatarIndex(name) % Self.palette.count]
        ZStack {
            Circle()
                .fill(fill)
            MacOwedAvatarMark(name: name, size: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 圓裡的白字（或 person.fill）
private struct MacOwedAvatarMark: View {
    let name: String
    let size: CGFloat

    var body: some View {
        if name.isEmpty {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(Color.white)
        } else {
            Text(String(name.prefix(1)))
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
    }
}

// MARK: - 人卡片（點一張＝只看那個人；再點一次或點「全部」回來）

struct MacOwedPersonCard: View {
    let person: MacOwedPerson
    let selected: Bool
    @Binding var pick: String?

    var body: some View {
        Button {
            pick = (pick == person.name ? nil : person.name)
        } label: {
            MacOwedPersonCardBody(person: person)
                .frame(width: 190)
                .macCard()
                .overlay(MacOwedCardRing(selected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }

    /// VoiceOver「王小明，還欠 NT$750，2 頓」（畫面朗讀；不進 .help）
    private var spoken: String {
        "\(person.name)，還欠 \(MacOwedText.ntd(person.total))，\(person.meals.count) 頓"
    }
}

struct MacOwedAllCard: View {
    let count: Int
    let total: Double
    let selected: Bool
    @Binding var pick: String?

    var body: some View {
        Button {
            pick = nil
        } label: {
            MacOwedAllCardBody(count: count, total: total)
                .frame(width: 190)
                .macCard()
                .overlay(MacOwedCardRing(selected: selected))
        }
        .buttonStyle(.plain)
    }
}

/// 選到的那張：1.5pt coral.tint 外框（沒選＝透明，版面不跳）
private struct MacOwedCardRing: View {
    let selected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: MacTheme.cardCorner, style: .continuous)
            .stroke(selected ? MacPageTheme.coral.tint : Color.clear, lineWidth: 1.5)
    }
}

/// 「(王) 王小明／2 頓・等了 35 天　NT$750」（等了那段 warn 色）
private struct MacOwedPersonCardBody: View {
    let person: MacOwedPerson
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        let late: Bool = person.maxDays > MacOwedText.lateDays
        HStack(spacing: 8) {
            MacOwedAvatar(name: person.name, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.headline)
                    .foregroundStyle(p.ink)
                    .lineLimit(1)
                Text(line(late: late))
                    .font(.caption)
                    .foregroundStyle(late ? MacTone.warn.color(p) : p.label)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(MacOwedText.ntd(person.total))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(p.ink)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    /// 「N 頓」＋（maxDays > 30 ? 「・等了 N 天」: ""）
    private func line(late: Bool) -> String {
        "\(person.meals.count) 頓" + (late ? "・等了 \(person.maxDays) 天" : "")
    }
}

/// 「全部／3 人　NT$1,235」
private struct MacOwedAllCardBody: View {
    let count: Int
    let total: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = MacPalette(scheme)
        let tint = MacPageTheme.coral.tint
        HStack(spacing: 8) {
            MacIconBadge(icon: "person.2.fill", top: tint, bottom: tint, size: 28, solid: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("全部")
                    .font(.headline)
                    .foregroundStyle(p.ink)
                Text("\(count) 人")
                    .font(.caption)
                    .foregroundStyle(p.label)
            }
            Spacer(minLength: 4)
            Text(MacOwedText.ntd(total))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(p.ink)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 詳情欄分帳區（唯讀）

/// 詳情欄分帳區（唯讀＋〔看誰還欠我〕；只在變動支出那一路；owedBook.split(for: e) 有值才畫）
struct MacOwedFactsSection: View {
    let expenseID: UUID
    @EnvironmentObject private var money: MacMoneyStore
    @EnvironmentObject private var ui: MacUIState

    var body: some View {
        if let e = money.expense(expenseID), let split = money.owedBook.split(for: e) {
            MacOwedFactsContent(expense: e, split: split, ui: ui)
        }
    }
}

/// sim6: owed6#26 一個活的人一列（detailShare）、最後一行 detailOwn、金額改過橘字、有人還沒還而且不在這頁 →〔看誰還欠我〕
private struct MacOwedFactsContent: View {
    let expense: Expense
    let split: MacOwedSplit
    @ObservedObject var ui: MacUIState

    var body: some View {
        let shares: [MacOwedShare] = split.liveShares
        Section {
            ForEach(shares, id: \.id) { s in
                MacOwedFactsShareRow(share: s)
            }
            Text(MacOwedText.detailOwn(split, amount: expense.amount))
                .font(.callout)
            if abs(expense.amount - split.baseAmount) >= 1 {
                Text(MacOwedText.amountChanged(base: split.baseAmount, now: expense.amount))
                    .font(.callout)
                    .foregroundStyle(Color.orange)
            }
            if ui.page != .owed && shares.contains(where: { s in s.owes && !s.isSettled && s.outstanding >= 0.5 }) {
                Button("看誰還欠我") { openOwed() }
            }
        } header: {
            MacSectionHeader(title: "分帳", icon: "person.2.fill", tint: MacPageTheme.coral.tint, count: "\(shares.count) 人")
        }
    }

    /// sim6: owed6#27 只換頁、不寫（選取留著：換頁會清選取，換完放回去）
    private func openOwed() {
        let keep: MacEntryRef? = ui.selection
        ui.page = .owed
        ui.selection = keep
    }
}

/// 「(王) 王小明　要還我 NT$375」／「已還 NT$375・11/21・現金 ✓」（綠）／「我請 NT$375」
private struct MacOwedFactsShareRow: View {
    let share: MacOwedShare

    var body: some View {
        let account: Bool = share.lastRepayment?.account ?? false
        LabeledContent {
            Text(MacOwedText.detailShare(share, accountName: account ? "帳戶" : nil, calendar: .current))
                .monospacedDigit()
                .foregroundStyle(share.isSettled ? Color.green : Color.primary)
        } label: {
            HStack(spacing: 6) {
                MacOwedAvatar(name: share.name, size: 18)
                Text(share.name)
                    .lineLimit(1)
            }
        }
    }
}
