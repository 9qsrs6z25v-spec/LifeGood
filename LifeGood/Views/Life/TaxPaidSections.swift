import SwiftUI

// MARK: - [v25.617] 稅務頁的小區塊（radar/judge_govfee.md §C10；build/govfee3/brief.md G1）
//
// TaxOverviewView 拆出來的小 View：稅費紀錄一列（來源膠囊）、罰款另一行（點開列出）、檢核一列（三態）、
// 可收合說明。數字、字都由 ExpenseKinds.swift 的 TaxPaid／TaxPaidText 算好，這裡只排版。
// 隱私：只在 App 內稅務頁；通知、小工具、手錶、鎖定畫面、靈動島一個字都沒加。
//（這個檔由主控登記進 project.pbxproj：A01A000001001661／A01B000001001661，只進 App target；G1 填內容）

/// 稅費紀錄、罰款一列要顯示的字（TaxOverviewView 算好傳進來）
struct TaxPaidRowText: Identifiable {
    /// ＝TaxPaidRecord.id（同一筆、同一期只有一列）
    let id: String
    let title: String
    let dateText: String
    /// 來源膠囊（「房子・一日拾樂」「車子・Swift Sport」「每年」；一般稅費是空的）
    let chips: [String]
    let amountText: String
}

/// 小膠囊（同 25.616 以前稅費紀錄的日期膠囊樣式）
struct TaxChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
    }
}

/// 日期膠囊＋來源膠囊
struct TaxChipLine: View {
    let row: TaxPaidRowText

    var body: some View {
        HStack(spacing: 4) {
            TaxChip(text: row.dateText)
            ForEach(Array(row.chips.enumerated()), id: \.offset) { _, chip in
                TaxChip(text: chip)
            }
        }
    }
}

/// 稅費紀錄一列：左邊紅條、44pt 漸層圓、名稱（跑馬燈）、日期＋來源膠囊、金額
struct TaxPaidRecordRow: View {
    let row: TaxPaidRowText

    var body: some View {
        HStack(spacing: 0) {
            accentBar
            HStack(spacing: 12) {
                iconCircle
                VStack(alignment: .leading, spacing: 3) {
                    // [v25.520] 名稱過長改跑馬燈（原本 lineLimit(1) 切成「…」）
                    MarqueeText(row.title)
                        .font(.subheadline.weight(.semibold))
                    TaxChipLine(row: row)
                }
                Spacer(minLength: 4)
                amountText
            }
            .padding(.trailing, 14)
            .padding(.vertical, 10)
        }
    }

    private var accentBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(
                colors: [Color.red.opacity(0.85), Color.red.opacity(0.35)],
                startPoint: .top, endPoint: .bottom))
            .frame(width: 4)
            .padding(.vertical, 10)
            .padding(.trailing, 14)
    }

    private var iconCircle: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.red.opacity(0.20), Color.red.opacity(0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .shadow(color: Color.red.opacity(0.20), radius: 6, x: 0, y: 3)
            Image(systemName: "doc.text.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.85))
        }
    }

    private var amountText: some View {
        Text(row.amountText)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(Color.red.opacity(0.85))
            .contentTransition(.numericText())
    }
}

/// 罰款一列（點開罰款那一行才看得到）
struct TaxFineRow: View {
    let row: TaxPaidRowText

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                TaxChipLine(row: row)
            }
            Spacer(minLength: 4)
            Text(row.amountText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// 罰款另一行：「另外繳了罰款 NT$600（1 筆）・不算稅費」，點開逐筆列出（使用者決定：罰款不算進年度稅費）
struct TaxFinesBlock: View {
    /// TaxPaidText.finesLine 算好的字
    let line: String
    let rows: [TaxPaidRowText]

    var body: some View {
        DisclosureGroup {
            fineList
        } label: {
            Text(line)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var fineList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { r in
                TaxFineRow(row: r)
            }
        }
        .padding(.top, 8)
    }
}

/// 年度稅務檢核一列：圖示圓、標題、灰字、月份膠囊、右邊狀態膠囊（已記／還沒到／還沒看到紀錄／不用查／應注意）
struct TaxCheckRow: View {
    let item: TaxCheckItem
    let color: Color

    private var active: Bool { item.state.isActive }

    private var iconName: String {
        if item.state == .recorded { return "checkmark.seal.fill" }
        return active ? "checkmark.circle.fill" : "circle"
    }

    private var circleFill: LinearGradient {
        if active {
            return LinearGradient(colors: [color.opacity(0.20), color.opacity(0.08)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [Color(.systemFill), Color(.systemFill)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var iconColor: Color { active ? color : Color(.tertiaryLabel) }

    private var monthColor: Color { active ? color : Color.secondary }

    private var stateColor: Color {
        switch item.state {
        case .recorded: return Color.green
        case .missing, .reminder: return Color.orange
        case .notYet, .notNeeded, .irrelevant: return Color.secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            iconCircle
            titleBlock
            Spacer(minLength: 4)
            if let t = item.state.text {
                stateChip(t)
            }
        }
    }

    private var iconCircle: some View {
        ZStack {
            Circle()
                .fill(circleFill)
                .frame(width: 36, height: 36)
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : Color.secondary)
            if let n = item.note {
                Text(n)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            monthChip
        }
    }

    private var monthChip: some View {
        Text(item.month)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(monthColor)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(monthColor.opacity(0.10))
            .clipShape(Capsule())
    }

    private func stateChip(_ t: String) -> some View {
        Text(t)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(stateColor)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(stateColor.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(stateColor.opacity(0.22), lineWidth: 0.6))
            .layoutPriority(1)
    }
}

/// 檢核下面的提示一句（可能是稅費、名稱有「罰」的稅費）
struct TaxHintRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 可收合說明「稅費能不能抵稅？」（預設收起；樣式同其他 section 的白底圓角卡）
struct TaxNotesBlock: View {
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            notesList
        } label: {
            titleLabel
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private var titleLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.indigo)
            Text(TaxPaidText.notesTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(TaxPaidText.notes, id: \.self) { n in
                Text("・" + n)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 8)
    }
}
