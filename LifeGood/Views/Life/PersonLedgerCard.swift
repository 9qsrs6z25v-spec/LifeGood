import SwiftUI

// [v25.635] 往來卡 PersonLedgerCard（peoplehub1 G1；judge_peoplehub §C2）
//
// 名片詳情頁用（25.636 起家人頁、朋友頁也用同一個，經 PersonLedgerSlot.swift）。全部是純值＋closure：卡片本身不讀 store、不寫任何東西、沒有分享鈕。
// - [v25.636] 使用者選「預設打開」：每次打開都是展開的（展開狀態只放 @State，不記住）；按收合那一行可以收起來，
//   收起來只剩「一起吃飯 6 頓・最近 11/18」＋「還有 1 頓沒還」，收合時看不到任何金額（照舊）。VoiceOver 會念「展開／收合」。
// - 展開：摘要（0 的不顯示）→「還欠我」每列〔已還〕→「最近」先 5 筆〔看全部 N 筆〕→ 同名提醒 → 隱私小字。
// - 是自己：整張卡只有一行「這是你自己的名片」。
// - 卡內每段包 AnyView、每一列是 fileprivate struct（25.618 閃退教訓：型別不要疊太深）。
// 字都從 PersonLedgerText 拿（Models/PersonLedger.swift）；算數字在 PersonLedger（呼叫端 .task(id:) 算好傳 snapshot 進來）。

// MARK: - 往來卡（名片詳情頁「聯絡方式」下面；外面的 slot 加 .padding(.horizontal)）

struct PersonLedgerCard: View {
    let snapshot: PersonLedgerSnapshot
    /// 點一列：打開那筆記帳（expenseId；呼叫端確認那筆還在才開）
    let onOpenExpense: (UUID) -> Void
    /// 〔已還〕：(expenseId, shareId)；寫入是呼叫端開的 SplitRepaySheet 自己做
    let onRepay: (UUID, UUID) -> Void

    /// [v25.636] 預設打開（使用者 25.635 出貨後選的；不記住，每次打開都是展開的）
    @State private var expanded = true
    /// 「最近」看全部（卡內展開，不另開頁）
    @State private var showAll = false

    init(snapshot: PersonLedgerSnapshot, onOpenExpense: @escaping (UUID) -> Void, onRepay: @escaping (UUID, UUID) -> Void) {
        self.snapshot = snapshot
        self.onOpenExpense = onOpenExpense
        self.onRepay = onRepay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let t = snapshot.selfText {
                PersonLedgerSelfRow(text: t)
            } else {
                PersonLedgerHeaderRow(header: headerText, unpaid: unpaidText, expanded: expanded,
                                      onTap: { toggleExpanded() })
                if expanded {
                    AnyView(details)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(cardBorder)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    // MARK: 收合那一行的字（沒有金額）

    private var headerText: String {
        PersonLedgerText.header(snapshot.summary, calendar: .current)
    }

    private var unpaidText: String? {
        PersonLedgerText.unpaid(snapshot.summary)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            expanded.toggle()
        }
        if !expanded {
            showAll = false
        }
    }

    // MARK: 展開後（摘要 → 還欠我 → 最近 → 同名提醒＋隱私小字）

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !totalLines.isEmpty {
                AnyView(totalsBlock)
            }
            if !owedParts.isEmpty {
                AnyView(owedBlock)
            }
            if !snapshot.entries.isEmpty {
                AnyView(recentBlock)
            }
            AnyView(footBlock)
        }
        .padding(.horizontal)
        .padding(.bottom, 14)
    }

    /// 「我請 2 次 NT$1,840」「還欠我 NT$375」「已還 NT$750」（0 的那項 PersonLedgerText 已經拿掉）
    private var totalLines: [String] {
        PersonLedgerText.totals(snapshot.summary)
    }

    private var totalsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(totalLines, id: \.self) { line in
                Text(line)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    /// 一個 owedPart 一列（同一頓同名兩列＝兩列，各自〔已還〕；SplitRepaySheet 一次還一個 share）
    private var owedParts: [PersonLedgerOwedPart] {
        snapshot.entries.flatMap { x in x.owedParts }
    }

    private var owedBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            PersonLedgerSectionTitle(text: PersonLedgerText.owedSection)
            ForEach(owedParts) { p in
                PersonLedgerOwedRow(label: PersonLedgerText.rowLabel(date: p.date, title: p.title, calendar: .current),
                                    amount: ExpenseSplitText.ntd(p.amount),
                                    onOpen: { onOpenExpense(p.expenseId) },
                                    onRepay: { onRepay(p.expenseId, p.shareId) })
            }
        }
    }

    private var shownEntries: [PersonLedgerEntry] {
        showAll ? snapshot.entries : Array(snapshot.entries.prefix(PersonLedgerText.recentLimit))
    }

    private var hasMore: Bool {
        snapshot.entries.count > PersonLedgerText.recentLimit
    }

    private var moreTitle: String {
        showAll ? PersonLedgerText.collapseAll : PersonLedgerText.seeAll(snapshot.entries.count)
    }

    private var recentBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            PersonLedgerSectionTitle(text: PersonLedgerText.recentSection)
            ForEach(shownEntries) { x in
                PersonLedgerEntryRow(label: PersonLedgerText.rowLabel(date: x.date, title: x.title, calendar: .current),
                                     value: PersonLedgerText.rowValue(x),
                                     muted: x.role == .together,
                                     onOpen: { onOpenExpense(x.expenseId) })
            }
            if hasMore {
                Button(moreTitle) { showAll.toggle() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
    }

    private var footBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = snapshot.sameNameText {
                Text(s)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(snapshot.privacyText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 列（純值＋closure）

/// 收合那一行：「往來」＋「一起吃飯 6 頓・最近 11/18」＋「還有 1 頓沒還」。這裡不碰任何金額
fileprivate struct PersonLedgerHeaderRow: View {
    let header: String
    let unpaid: String?
    let expanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                PersonLedgerHeaderText(header: header, unpaid: unpaid)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // [v25.636] VoiceOver 念出現在是展開還是收合（25.635 adjudicate §4）
        .accessibilityValue(expanded ? PersonLedgerText.a11yExpanded : PersonLedgerText.a11yCollapsed)
    }
}

/// 收合那一行中間的字（拆出來，HeaderRow 不疊深）
fileprivate struct PersonLedgerHeaderText: View {
    let header: String
    let unpaid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(PersonLedgerText.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primary)
            if !header.isEmpty {
                Text(header)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let u = unpaid {
                Text(u)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// 自己的名片：整張卡只有這一行
fileprivate struct PersonLedgerSelfRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "person.crop.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 12)
    }
}

/// 段名「還欠我」「最近」
fileprivate struct PersonLedgerSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// 「還欠我」一列：日期＋店名、金額、〔已還〕（同一列有點擊，〔已還〕一定 .borderless；照 OwedMealRow）
fileprivate struct PersonLedgerOwedRow: View {
    let label: String
    let amount: String
    let onOpen: () -> Void
    let onRepay: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(amount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
            Button(ExpenseSplitText.repayButton, action: onRepay)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

/// 「最近」一列：日期＋店名、「我請 NT$460」「要還我 NT$375」「已還 NT$375」或「一起」（只同行沒分帳，灰字）
fileprivate struct PersonLedgerEntryRow: View {
    let label: String
    let value: String
    let muted: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(muted ? Color.secondary : Color.primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}
