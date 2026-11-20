import SwiftUI

// MARK: - [v25.616] 一鍵整理（車子卡、房屋卡「要確認」→〔看一下〕；radar/judge_govfee.md §C9；build/govfee2/brief.md）
//
// • 逐筆〔改成罰款〕〔不是〕；還沒按的有兩筆以上時多一顆〔全部改〕（再確認一次「這 2 筆金額、日期不會變」）。
// • 只寫細項那個鍵（ExpenseKindStore.recordRetag／recordDismiss）：記帳那筆一個欄位都不動、JSON 一個 byte 都不變。
// • 付費在外殼（卡片 fixCheck 的 requirePremium）；這頁的字都在 ExpenseKindTidy（ExpenseKinds.swift）。
// • 寫完卡片自己重算（ExpenseKindStore → .expenseKindsDidChange → ExpenseStore.modifyID）；這頁用 done 記住按過哪幾筆。
// • 外殼一律 .sheet(item:) 打開、外面已經掛 .appStores()（要讀 ExpenseStore）。

struct ExpenseKindTidySheet: View {
    let request: ExpenseKindTidyRequest

    @EnvironmentObject private var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss
    /// 按過的那幾筆：true＝改了、false＝〔不是〕
    @State private var done: [UUID: Bool] = [:]
    @State private var askAll = false

    /// 還沒按的
    private var pending: [ExpenseKindCandidate] {
        request.candidates.filter { c in done[c.expenseId] == nil }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(request.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .confirmationDialog(ExpenseKindTidy.allConfirmTitle, isPresented: $askAll,
                                    titleVisibility: .visible) {
                    Button(ExpenseKindTidy.allButton) { retagAllLater() }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(ExpenseKindTidy.allConfirmMessage(pending.count))
                }
        }
    }

    private var content: some View {
        List {
            candidatesSection
            if pending.count >= 2 {
                Section {
                    Button(ExpenseKindTidy.allButton) { askAll = true }
                }
            }
            if !request.notes.isEmpty {
                notesSection
            }
        }
    }

    private var candidatesSection: some View {
        Section {
            ForEach(request.candidates) { c in
                ExpenseKindTidyRow(candidate: c, outcome: done[c.expenseId],
                                   onRetag: { retag(c) }, onDismiss: { dismissOne(c) })
            }
        } footer: {
            Text(ExpenseKindTidy.sheetFooter)
        }
    }

    private var notesSection: some View {
        Section {
            ForEach(Array(request.notes.enumerated()), id: \.offset) { _, name in
                Text(name)
            }
        } footer: {
            Text(ExpenseKindTidy.houseOtherNote)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("完成") { dismiss() }
        }
    }

    // MARK: 寫（只寫細項那個鍵）

    private func retag(_ c: ExpenseKindCandidate) {
        ExpenseKindStore.shared.recordRetag([c], expenses: expenseStore.expenses)
        done[c.expenseId] = true
    }

    private func dismissOne(_ c: ExpenseKindCandidate) {
        ExpenseKindStore.shared.recordDismiss([c])
        done[c.expenseId] = false
    }

    /// 確認框收完那一輪先過，下一輪才寫
    private func retagAllLater() {
        let list: [ExpenseKindCandidate] = pending
        let store = expenseStore
        DispatchQueue.main.async {
            ExpenseKindStore.shared.recordRetag(list, expenses: store.expenses)
            for c in list { done[c.expenseId] = true }
        }
    }
}

/// 一列：名稱、日期・金額，下面〔改成罰款〕〔不是〕；按過寫「已改成罰款」「不會再問」
private struct ExpenseKindTidyRow: View {
    let candidate: ExpenseKindCandidate
    let outcome: Bool?
    let onRetag: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.title)
                .font(.body)
            Text(candidate.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            actions
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var actions: some View {
        if let changed = outcome {
            Label(changed ? ExpenseKindTidy.doneText(candidate.kind) : ExpenseKindTidy.dismissedText,
                  systemImage: changed ? "checkmark.circle.fill" : "minus.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 20) {
                Button(ExpenseKindTidy.retagButton(candidate.kind), action: onRetag)
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
                Button(ExpenseKindTidy.dismissButton, action: onDismiss)
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
