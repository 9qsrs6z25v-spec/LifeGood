import SwiftUI
import WidgetKit

// MARK: - 記帳台、一按就記（中）共用的左半「還能花」面板（小工具 v2）
//
// 只屬於「LifeGoodWidgets」target。規格見 scratchpad/widgets/v2/brief.md 的 G3-2；
// 樣稿 mock_spec ledger-desk-medium 左半（J:192-203）。
//
// 由上而下：「10 月・第 13 天」、小標、大字、第二行、這個月的錢（橫條，同還能花的 MoneyLeftBar）、
// 「今天 NT$1,240・3 筆」（今天還沒記帳「今天 還沒花錢」畫綠）、「收入 NT$12萬・預估」。
// 字一律經過 WidgetMoneyDay.lines(hidden:) 拿（隱藏金額開著時「本月已花／62%／還有 19 天／今天 3 筆」），
// **不算錢、不拼金額**；這裡只拼日期字（WidgetDateText）。
//
// 外面包 Link（點了開收支總覽）由呼叫端做；這裡只畫。
//
// 型別：WidgetMoneyPanel（internal）；WidgetMoneyPanelModel 與畫面零件都是 private。

struct WidgetMoneyPanel: View {
    /// nil＝還沒打開過新版 App
    let snapshot: WidgetMoneySnapshot?
    /// entry.date（不在 View 裡呼叫 Date()）
    let now: Date
    /// 「隱藏金額」開著
    let hidden: Bool
    let palette: WidgetPalette

    private var model: WidgetMoneyPanelModel {
        WidgetMoneyPanelModel.make(snapshot: snapshot, now: now, hidden: hidden)
    }

    var body: some View {
        WidgetMoneyPanelContent(model: model, palette: palette)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 畫面要的字（全部在這裡挑好，body 只讀）

private struct WidgetMoneyPanelModel {
    enum Kind {
        /// 一句話（沒快照）
        case message
        /// 某一天（正常／超支／沒收入）
        case day
        /// 快照的最後一天過完了（v2 已經多寫下個月 1–7 號，過了那 7 天才會走到這裡）
        case monthStarted
    }

    var kind: Kind = .message
    var message = ""
    /// 「10 月・第 13 天」
    var caption = ""
    var title = ""
    var hero = ""
    var line = ""
    var bar: WidgetMoneyBar? = nil
    /// 「今天 NT$1,240・3 筆」「今天 還沒花錢」（隱藏時「今天 3 筆」）
    var todayText = ""
    /// 今天還沒記帳：「今天 還沒花錢」畫綠（跟 App 四格同一句）
    var todayIsGood = false
    /// 最下面一行：「收入 NT$12萬・預估」；快照太舊時「上次更新 10/11」
    var bottomText = ""
    var isOver = false

    /// 只挑字、不算錢
    static func make(snapshot: WidgetMoneySnapshot?, now: Date, hidden: Bool) -> WidgetMoneyPanelModel {
        var model = WidgetMoneyPanelModel()
        guard let snap = snapshot else {
            model.message = "打開 LifeGood 一次，這裡就會出現本月還能花"
            return model
        }
        guard !snap.hasEnded(at: now), let day = snap.day(at: now) else {
            model.kind = .monthStarted
            model.caption = WidgetDateText.monthDayLabel(now)
            model.title = WidgetDateText.monthStarted(now)
            model.line = "打開 LifeGood 算這個月還能花"
            model.bottomText = WidgetDateText.lastUpdated(snap.generatedAt)
            return model
        }
        let lines = day.lines(hidden: hidden)
        model.kind = .day
        model.caption = WidgetDateText.monthDayLabel(day.dayStart)
        model.title = lines.title
        model.hero = lines.hero
        model.line = lines.line
        model.bar = day.bar
        model.isOver = day.isOver
        model.todayText = lines.todayText
        model.todayIsGood = day.todayCount == 0
        // 超過兩天沒更新：最下面一行老實說是舊的（J:63）
        if snap.isStale(at: now) {
            model.bottomText = WidgetDateText.lastUpdated(snap.generatedAt)
        } else {
            model.bottomText = lines.incomeText ?? ""
        }
        return model
    }
}

// MARK: - 畫面

private struct WidgetMoneyPanelContent: View {
    let model: WidgetMoneyPanelModel
    let palette: WidgetPalette

    var body: some View {
        switch model.kind {
        case .message:
            WidgetMoneyPanelMessage(text: model.message, palette: palette)
        case .monthStarted:
            WidgetMoneyPanelMonthStarted(model: model, palette: palette)
        case .day:
            WidgetMoneyPanelDay(model: model, palette: palette)
        }
    }
}

/// 超支時小標、大字、第二行用紅色；著色模式靠「已超支」三個字
private struct WidgetMoneyPanelTone {
    let model: WidgetMoneyPanelModel
    let palette: WidgetPalette

    var title: Color { model.isOver ? palette.bad : palette.label }
    var hero: Color { model.isOver ? palette.bad : palette.ink }
    var line: Color { model.isOver ? palette.bad : palette.inkSoft }
    var today: Color { model.todayIsGood ? palette.good : palette.ink }
}

/// 大字（著色模式染重點色）
private struct WidgetMoneyPanelHero: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .widgetAccentable()
    }
}

/// 某一天。放不下時先拿掉橫條、再拿掉最下面一行（ViewThatFits 由上往下挑第一個放得下的）
private struct WidgetMoneyPanelDay: View {
    let model: WidgetMoneyPanelModel
    let palette: WidgetPalette

    private var tone: WidgetMoneyPanelTone { WidgetMoneyPanelTone(model: model, palette: palette) }

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(showsBar: true, showsBottom: true)
            column(showsBar: false, showsBottom: true)
            column(showsBar: false, showsBottom: false)
        }
    }

    private func column(showsBar: Bool, showsBottom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.caption)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.inkDate)
                .lineLimit(1)
            titleText
            WidgetMoneyPanelHero(text: model.hero, color: tone.hero)
            lineText
            Spacer(minLength: 3)
            barView(showsBar: showsBar)
            todayLine
            bottomLine(shows: showsBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var titleText: some View {
        Text(model.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tone.title)
            .lineLimit(1)
            .padding(.top, 1)
    }

    /// 「每天 NT$2,402」；沒收入時「記一筆收入，才算得出還能花」比較長，給兩行
    private var lineText: some View {
        Text(model.line)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(tone.line)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }

    @ViewBuilder
    private func barView(showsBar: Bool) -> some View {
        if showsBar, let bar = model.bar {
            MoneyLeftBar(bar: bar, palette: palette)
                .frame(height: 10)
                .padding(.bottom, 3)
        }
    }

    @ViewBuilder
    private var todayLine: some View {
        if !model.todayText.isEmpty {
            Text(model.todayText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone.today)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private func bottomLine(shows: Bool) -> some View {
        if shows, !model.bottomText.isEmpty {
            Text(model.bottomText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 1)
        }
    }
}

/// 快照的最後一天過完了、App 還沒打開
private struct WidgetMoneyPanelMonthStarted: View {
    let model: WidgetMoneyPanelModel
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.caption)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.inkDate)
            Text(model.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.ink)
                .padding(.top, 4)
                .widgetAccentable()
            Text(model.line)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.inkSoft)
                .lineLimit(3)
                .padding(.top, 5)
            Spacer(minLength: 3)
            Text(model.bottomText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
        }
    }
}

/// 還沒打開過新版 App：只寫一句話，不顯示 NT$0
private struct WidgetMoneyPanelMessage: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "creditcard")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.label)
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
