import SwiftUI

// [v25.636] 家人頁、朋友頁的往來那一格（peoplehub2 總設計；judge_peoplehub §C7-2、§C11）
//
// 照 25.635 名片頁的 BusinessCardLedgerSlot（BusinessCardView.swift 檔尾；那一個照舊用 cardSnapshot，25.636 只多了名片↔朋友那一列）寫成共用的：
// - VStack(spacing: 16) { above（一定有的那張卡，.task 才一定會跑）; 往來卡?; 〔已還〕完成提示? }
//   沒有往來＝只剩 above，版面跟原本一樣（呼叫端外層 VStack 也是 16）。
// - 只讀：.task(id:) 裡算 PersonLedger.snapshot(subject:…) 放進 @State；body 不算。
// - 點一列開記帳卡、〔已還〕開 SplitRepaySheet：都是 sheet(item:)＋.appStores()，那一筆還在才開。
//   唯一會寫的是〔已還〕（SplitRepaySheet 自己 dismiss 後下一個 runloop 寫，沿用 25.634）。
// 呼叫端一律包 AnyView：AnyView(PersonLedgerSlot(subject: …, above: AnyView(…)))。

/// .task(id:) 的 key：記帳／分帳一變（modifyID）、名字組合、本人名字、名單人數變了才重算
fileprivate struct PersonLedgerSlotKey: Equatable {
    let modifyID: UUID
    let subject: PersonLedgerSubject
    let meName: String
    let people: Int
}

struct PersonLedgerSlot: View {
    let subject: PersonLedgerSubject
    let above: AnyView

    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore

    @State private var snapshot = PersonLedgerSnapshot()
    @State private var repayTarget: SplitRepayTarget? = nil
    @State private var openCard: FinanceCardTarget? = nil
    @State private var doneText: String? = nil

    init(subject: PersonLedgerSubject, above: AnyView) {
        self.subject = subject
        self.above = above
    }

    private var slotKey: PersonLedgerSlotKey {
        let people = lifeStore.familyMembers.count + lifeStore.relationships.count + lifeStore.subordinates.count
            + lifeStore.orgPeople.count + lifeStore.businessCards.count
        return PersonLedgerSlotKey(modifyID: store.modifyID, subject: subject,
                                   meName: lifeStore.profile.chineseName + "|" + lifeStore.profile.englishName,
                                   people: people)
    }

    var body: some View {
        VStack(spacing: 16) {
            above
            if snapshot.shows {
                AnyView(PersonLedgerCard(snapshot: snapshot, onOpenExpense: { id in open(id) },
                                         onRepay: { eid, sid in repay(eid, sid) })
                    .padding(.horizontal))
            }
            if let t = doneText {
                PersonLedgerDoneLine(text: t)
            }
        }
        .task(id: slotKey) { reload() }
        .task(id: doneText) {
            guard doneText != nil else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            doneText = nil
        }
        .sheet(item: $repayTarget) { t in
            SplitRepaySheet(expenseId: t.expenseId, shareId: t.shareId, onDone: { msg in doneText = msg })
                .appStores()
        }
        .sheet(item: $openCard) { t in
            FinanceItemCard(target: t)
                .appStores()
        }
    }

    /// 只讀：記帳＋分帳＋名單 → @State
    private func reload() {
        snapshot = PersonLedger.snapshot(subject: subject, life: lifeStore, expenses: store.expenses,
                                         index: ExpenseSplitStore.shared.index)
    }

    /// 那筆還在才開（在記帳卡刪掉那頓：modifyID 跳 → 重算 → 那列不見）
    private func open(_ id: UUID) {
        guard store.expenses.contains(where: { e in e.id == id }) else { return }
        openCard = .variableExpense(id)
    }

    private func repay(_ eid: UUID, _ sid: UUID) {
        guard store.expenses.contains(where: { e in e.id == eid }) else { return }
        repayTarget = SplitRepayTarget(expenseId: eid, shareId: sid)
    }
}

/// 〔已還〕完成提示「記好了：國泰世華 ＋NT$375」（2.5 秒自己消失）
fileprivate struct PersonLedgerDoneLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}
