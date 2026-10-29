import SwiftUI

// MARK: - 「這一趟用哪個記？」（手錶 v5，v25.582；watch/judge.md §8 v5 做好標準 5；watch/build/v5/brief.md G2-5）
//
// 只屬於主 App。**骨架（主控寫）：名字與參數 WatchRunChoiceSheet(sport:onPick:) 不准改（HealthView、RunTrackingView 在叫）；G2 填內容。**
// 健康頁「▶ 開始跑步」、跑步畫面〔開始〕：戴著手錶（WatchRunStarter.route == .ask）先彈這一頁（.sheet(item:)＋.appStores()，
// .presentationDetents([.medium])）：
//   「這一趟用哪個記？」
//   〔⌚︎ 用手錶記〕有心率，可以不帶手機
//   〔📱 用 iPhone 記〕地圖跟著你走，鎖定畫面看得到
//   ☐ 記住我的選擇（之後可以在 設定 › Apple Watch 改）
// 按了：先 dismiss()，**下一個 runloop** 才呼叫 onPick(選的, 記住沒有)（呼叫端寫設定、叫手錶、或開跑步畫面）。字全部是 WatchRunStarter 的常數。
//
// [G2 填] 版面：半頁（字放大時整頁可以捲）、系統分組底色上兩張大按鈕（圓角 14、secondarySystemGroupedBackground、
// 圖示 28 點運動色）、下面「記住我的選擇」開關＋一行小字。最上面一行小字是要開始的運動（圖示＋「跑步」，運動色）。
// 連點兩下只算第一下（picked）；往下滑收掉＝什麼都不選（呼叫端不動）。

struct WatchRunChoiceSheet: View {
    /// 要開始的運動（圖示、按鈕上的運動名）
    let sport: WorkoutSport
    /// 選了 .watch 或 .phone（不會是 .ask）、勾了「記住我的選擇」沒有
    let onPick: (WatchRunStarter.Choice, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    /// 「記住我的選擇」（預設不勾：設定頁 Apple Watch 段也可以改）
    @State private var remember = false
    /// 已經按了一顆（收起來的動畫還在跑時再按不再算）
    @State private var picked = false

    var body: some View {
        ScrollView {
            content
                .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// 運動色（跑步橘 EB6834）：上面那行小字、兩顆按鈕的圖示
    private var tint: Color {
        WorkoutPalette.sport(sport, dark: scheme == .dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            optionButton(icon: "applewatch",
                         title: WatchRunStarter.watchOption,
                         note: WatchRunStarter.watchOptionNote,
                         choice: .watch)
            optionButton(icon: "iphone",
                         title: WatchRunStarter.phoneOption,
                         note: WatchRunStarter.phoneOptionNote,
                         choice: .phone)
            rememberRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「🏃 跑步」小字＋「這一趟用哪個記？」
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(sport.displayName, systemImage: sport.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
            Text(WatchRunStarter.askTitle)
                .font(.title3.bold())
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.bottom, 2)
    }

    /// 一顆全寬大按鈕：圖示＋名字＋一行說明
    private func optionButton(icon: String, title: String, note: String,
                              choice: WatchRunStarter.Choice) -> some View {
        Button {
            pick(choice)
        } label: {
            WatchRunChoiceOption(icon: icon, title: title, note: note, tint: tint)
        }
        .buttonStyle(MoneyPressStyle())
    }

    /// 「記住我的選擇」＋「之後可以在 設定 › Apple Watch 改」
    private var rememberRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(WatchRunStarter.rememberTitle, isOn: $remember)
                .font(.subheadline.weight(.semibold))
                .tint(WorkoutPalette.go)
            Text(WatchRunStarter.rememberNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    /// 先收起來，下一輪主執行緒才交出去（坑：dismiss 跟寫設定、開全螢幕同一輪，收起來那一下會搶）
    private func pick(_ c: WatchRunStarter.Choice) {
        guard !picked else { return }
        picked = true
        let r = remember
        dismiss()
        DispatchQueue.main.async {
            onPick(c, r)
        }
    }
}

/// 一顆大按鈕的長相（按鈕本身在 WatchRunChoiceSheet.optionButton）
private struct WatchRunChoiceOption: View {
    let icon: String
    let title: String
    let note: String
    let tint: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 14) {
            iconView
            texts
            Spacer(minLength: 0)
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: shape)
        .contentShape(shape)
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36)
            .accessibilityHidden(true)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.primary)
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
