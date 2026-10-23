import SwiftUI

// MARK: - 財富頁的字和數字（v25.564，財富 v3；wealth/judge.md §3.0–3.12）
//
// 照 HealthPageData：財富頁看板（頭部各種狀態、膠囊、一句話、手寫、VoiceOver 一句）、頂樓水塔（WealthTowerScene）、
// 存款組成條、四格、接下來 30 天・各帳戶夠不夠扣、信用卡／銀行／證券戶／保單／收起來的項目卡要的字，
// 全部在這裡一次組好（WealthPageData.build(facts:…)，在主執行緒的 .task(id:) 叫一次存 @State），body 只畫。
// 數字一律讀 WealthFacts（LifeStore.wealthFacts 的快取）。
//
// 分工：G1 實作（這個檔＋WealthBoard.swift、WealthItems.swift、LifeFinanceView.swift）。主控只開檔。
//
// [v25.564] G1：
// • 狀態（先符合先用；build/v3/brief.md §G1-1 表）：新手（沒有沒收起來的銀行、也沒有沒停用的卡）→ 只有卡 → 某帳戶 30 天內不夠扣
//   → 有逾期 → 領薪日起 3 天 → 有幣別沒匯率 → 要繳都 0 → 平常。
// • 膠囊挑一件：不夠扣 > 逾期 > 自己繳／每次問我的卡 14 天內截止 > 自動扣的卡 14 天內扣 > 要繳的都繳了 ✓ > 不出現。
// • 一句裡的萬不寫 NT$（「4.8萬」）；單筆對得上單據的寫到元（「18,600」）。遮住：金額換「••••」，日期、%、件數照常；
//   VoiceOver 念「金額已遮住」。
// • 水塔：塔＝沒收起來的銀行（照頁面順序，最多 5 座，第 6 個起併成一座「其他 ＋N」）；水位 √(存摺上÷最大那座)；
//   斜線 還沒扣÷存摺上；卡站在扣它卡費的那座塔下（沒設、帳戶收起來了：最後補一座灰色空塔「還沒選」）。
// • 排序：有 sortIndex 的照它（小的在前、沒有的排後面）；都沒排過：卡＝有要繳的在前、截止日近的在前；銀行＝最近 90 天進出筆數多到少。
// • 這裡不叫 LifeStore、不寫任何東西；NumberFormatter（ntdWanString）只在主執行緒用，所以 build 要在主執行緒叫。
//
// [v25.565] 財富 v4（build/v4/brief.md §G4-1；judge §3.4）：
// • ①' 橋 WealthPageBridge：「這些已算進理財淨資產 NT$1381.1萬 ›」。數字＝FinanceSnapshot.current(...).netWorth
//  （跟理財總覽、人生總覽名片同一個數；財富頁 rebuild() 算好傳進 build(…, netWorth:)，這裡不自己算）。
//   新手、沒傳 netWorth 不出現；遮住寫「NT$ ••••」、VoiceOver 念「金額已遮住」。
//
// [v25.566] 財富 v5 定存與外幣（build/v5/brief.md §G1 1–5；judge §3.2 定存塔、§3.8）：
// • 水塔接上真的定存：塔的數字＝towerValue（定存帳戶 showsAsDeposit＝存摺上＋定存 totalNTD，其他照存摺上 ntdTotal；
//   水位、併塔合計、最大那座都用它）。showsAsDeposit（舊的「定存」種類，或有定存、存摺上都是 0）→ 金水＋鎖頭、
//   小牌＝最近到期那一期「3/15」（沒有 nil）、lockOpen＝有到期再決定已經到期的，或最近那一期 0…7 天內到期（鎖頭打開一半）。
// • 接下來一列：定存那幾列（轉定存、定存到期、解約）短名「定存」、日期塊字「定」；定存利息「定存利息」。
// • 頁尾：有定存才加一句「定存的利息是預估…」；「這頁的數字怎麼算」加定存、存款保險兩句（都是 static let）。
// • 外幣第二行要匯率日期：build 把 ratesUpdatedAt 傳給 MoneyItem.wealthBank（⑤ 與 ⑧ 收起來的都傳）。
// • 四格「30 天內最低」不看定存帳戶（存摺上常是 0；全部都是定存帳戶才照算），免得記了定存就變「約 NT$0」。
// • 數字一律讀 WealthFacts（TimeDeposit 的到期日、狀態、天數），這裡不自己算定存利息、到期日。
//
// [v25.567] 財富 v6 保單總表（build/v6/brief.md §6 G1 1–4；judge §3.10、樣稿①⑦）：
// • ⑦ 保單整區改讀 facts.policies（WealthPolicyFacts：財富的保障型保單、儲蓄險、車險、房屋險四個來源，一筆記帳保費只算一次）；
//   這裡不再自己算保費、繳法、下次、從哪扣。列＝WealthPolicyFacts.Row 一列一列搬（id 改成 Row.id 字串、多 source／tag）；
//   右上「一年約 NT$16萬」、最下灰字「保障型一年 6.4萬（不含儲蓄險）・外幣照今天匯率」、灰字「記帳裡還有 1 筆保費沒有保單資料：…」〔補保單〕、
//   保障六格（cells，不含金額）。v3 的「儲蓄險 N 張記在理財」那一列拿掉（儲蓄險已經是一列）。
// • 遮住：列的金額「••••」、VoiceOver「金額已遮住」；右上「一年約 NT$ ••••」；保障型那段「保障型一年 ••••（不含儲蓄險）」；
//   灰字的金額段「••••」。六格不含金額，照常。
// • 一列都沒有、灰字也沒有（沒有保單，或財富的保單都收起來了、也沒有儲蓄險／車險／房屋險）＝nil，整區不出現（同 v3）。
// • 「這頁的數字怎麼算」多兩句：保單一年合計怎麼算、證券戶不自己記錢。
//
// [v25.568] 財富 v7 隱私加強與網頁版（build/v7/brief.md §4 G2-5；judge §7.1、§7.3）：
// • 「iCloud 與家人共享說明」第一句：加密的多了有效期限、保單號碼、票證號碼（安全碼照樣加密存：第 6 題）。
// • 「這頁的數字怎麼算」多一句 webHow：網頁版讀 App 算好的那一包（life_wealth_facts_v1），只露後 4 碼、沒有卡片到期日。
//
// [v25.575] 定期轉帳 v1a（transfer/build/v1a/brief.md §6 G1；transfer/judge.md §4.3、§5；樣稿①-2）：
// • ⑤ 銀行帳戶最後一張「定期轉帳・4 條」卡：WealthPageTransfers（facts.transferRules 空的＝nil，整張不出現）。
//   一列＝一條還在跑的（facts.runningTransfers）：第一行「薪轉 → 零用錢」＋右「3,000」；第二行「每週五・銀行自動轉」＋右「下次 10/30（五）」；
//   第三行（有才出現）最要緊的一件：14 天內最後一次（橘）＞對方收起來了／找不到（橘）＞銀行設到哪天（灰）——照樣稿①-2 拆三行
//  （樣稿註 5：規劃把週期擠在第一行，393 寬「薪轉 → 房貸扣款」會撞到金額）。照轉出帳戶在 ⑤ 的位置→下次日子→建立先後排。
//   卡底「一個月大約轉出 63,000（每週的照一年 52 次算）」（monthlyOut 加總；有每週的才寫括號）＋灰字；已結束的「已結束 1 條 ›」點了在卡裡展開
//  （第二行右邊「最後一次 2026/12/6」；設錯了「一期都不算」；收起來、刪帳戶結束的第三行灰字說一句）。
// • ③ 短名：轉帳寫「轉給房貸扣款」「來自薪轉」（只拿掉開頭那個空白、不再截 6 字；換匯「換匯（換出）」照原字）；不夠扣那一筆同樣。
// • 收起來確認框多一句：WealthPageBankRow.hideNote＝facts.hideTransferSentence(id)（「有 1 條定期轉帳轉進這裡，會一起結束」）。
//   結束本身在 LifeStore.setWealthHidden 裡（主控），這裡只組字。
//
// [v25.577] 定期轉帳 v1b（transfer/build/v1b/brief.md §6 G1；judge §4.1、§4.3；樣稿③-A5；sim_v1b §9）：
// • 〔看全部〕一筆轉帳併成一列：定期照 transferRuleId＋periodKey、單次照 transferPairId；同一個 key 剛好兩列、在兩個不同的
//   列出帳戶、一出一進、同一個幣別才併（另一邊收起來、換匯同一個帳戶兩格、兩個帳戶之間台幣轉外幣照舊單列）。併的那列「薪轉 → 零用錢」右「3,000」（不帶正負號）、
//   灰字「薪轉扣完剩 49,400・定期」（自己轉「・自己轉」、單次不加）、日期塊「轉」；件數照併完的算（例 18 列 → 11 件）。
//   排序：日子 → 帳戶在 listed 的位置（併的那列用轉出帳戶）→ 那一列在 next30 的位置。定期那一期帶 transferRuleId／periodKey
//  （WealthBoard 的〔看全部〕點了開那一期）。③ 每個帳戶那一列不動。
// • transferInvite：沒有規則（刪掉的不算）、沒按過〔不用了〕、沒收起來的銀行兩個以上 → ⑤ 最下面一行邀請。
// • 定期轉帳卡底字補「在每個帳戶的「連到這個帳戶的」看得到。」（v1b 有 ④ 了）。
//
// [v25.579] 定期轉帳 v2 會提醒你（transfer/build/v2/brief.md §6 G2-3；judge §4.3；樣稿③-A1；sim_v2 §10）：
// • 定期轉帳卡第三行最優先「暫停到 12/24」（暫停中，恢復那一期的前一天）／「12/4 起暫停到 12/24」（還沒開始）／「暫停中」「12/4 起暫停」
//  （沒設恢復），灰字；字照 WealthTransferRule.pauseInfo(today:).text（主控），這裡只排先後。其他照舊：14 天內最後一次（橘）＞
//   對方收起來了／找不到（橘）＞銀行設到哪天（灰）。VoiceOver 照舊帶到第三行那句。

// MARK: - 捲到哪一區

/// 財富頁看板上的格子、圖例點了捲到哪一區（ScrollViewReader 的 id）
enum WealthPageAnchor: Hashable {
    /// ③ 接下來 30 天・各帳戶夠不夠扣
    case upcoming
    /// ④ 信用卡
    case cards
    /// ⑤ 銀行帳戶
    case banks
}

// MARK: - 看板

/// ① 看板頭部（照 VehicleCardBoardData 的欄位）
struct WealthPageBoard {
    /// 「10/19 週一」
    let date: String
    let capsule: String?
    let capsuleIcon: String?
    /// 膠囊字色：neutral＝一般膠囊字色
    let capsuleTone: MoneyTone
    /// 「存款合計（存摺上）」「卡費還沒扣」「存款合計」
    let label: String
    /// 「NT$81.7萬」「NT$ ••••」「—」
    let big: String
    let bigTone: MoneyTone?
    /// 一句話（數字粗體、扣完能用負的才 bad）
    let line: FinanceLine
    /// 手寫（英文兩行）
    let greeting: [String]
    /// 整個頭部 VoiceOver 念的一句
    let accessibilityText: String
    let seed: Int
}

/// 看板下的一格（MoneyTile：圖示＋標籤／大字／一行灰字）
struct WealthPageTile: Identifiable {
    enum Kind: String {
        case due, unbilled, available, lowest
    }
    let kind: Kind
    let icon: String
    let tint: TripBoardTint
    let label: String
    let value: String
    let valueTone: MoneyTone?
    let detail: String?
    /// 灰字後面要上色的那一小段（「都繳了」good、「已過截止日」bad）
    let accent: String?
    let accentTone: MoneyTone
    /// 點了捲到哪一區
    let target: WealthPageAnchor

    var id: String { kind.rawValue }
}

/// 存款組成條下面的一個圖例
struct WealthPageLegend: Identifiable {
    let id: String
    let theme: MoneyArtTheme
    let text: String
}

/// 存款組成條（活存藍、定存金、外幣青；只有一種不畫條、只寫一行圖例）
struct WealthPageRibbon {
    /// 兩種以上才有（一種＝空陣列）
    let segments: [MoneyShareRibbon.Segment]
    let legend: [WealthPageLegend]
    let accessibilityText: String
}

// MARK: - ③ 接下來 30 天

/// ③ 一個帳戶一列：「薪轉（台新）　最低 約 7.6萬　✓ 夠扣」＋「10/21 交割 −52,340・11/5 月薪 +80,000」
struct WealthPageUpcomingRow: Identifiable {
    let id: UUID
    let name: String
    /// 「（台新）」：有暱稱才有
    let bank: String?
    /// 「最低 約 7.6萬」
    let lowest: String
    /// 「✓ 夠扣」「差 23,940」「現在是負的」
    let badge: String
    let badgeTone: MoneyTone
    /// 最大的兩件
    let detail: String
    let accessibilityText: String
}

/// 「看 6 件 ›」表單的一列（照日期排；FinanceLedgerRow）
struct WealthPageUpcomingItem: Identifiable {
    enum Mark {
        case income, card, stock, other
    }
    let id: String
    let day: String
    let month: String
    let glyph: String
    let mark: Mark
    let title: String
    /// 「薪轉・扣完剩 76,060」
    let detail: String
    let amount: String
    /// 扣完變負的（整列 warn）
    let negative: Bool
    let accessibilityText: String
    /// [v25.577] 定期轉帳那一期（〔看全部〕點了在 sheet 裡開那一期）：規則的 id、那一期原本的日子「2026-11-06」；
    /// 單次轉帳、其他列 nil（不能點）
    var transferRuleId: UUID? = nil
    var periodKey: String? = nil
}

struct WealthPageUpcoming {
    /// 「6 件」
    let trailing: String
    let rows: [WealthPageUpcomingRow]
    let all: [WealthPageUpcomingItem]
}

// MARK: - ④～⑧ 項目卡

/// 分組標頭（MoneyGroupHeader 的數字與合計）
struct WealthPageGroupHeader {
    let count: Int
    let total: String
}

/// ④ 一張信用卡
struct WealthPageCardRow: Identifiable {
    let id: UUID
    let item: MoneyItem
    /// 確認框用的名字（「國泰世華 CUBE」）
    let name: String
    /// 有要繳（長按才有〔標成已繳〕）
    let canMarkPaid: Bool
    /// 還在刷它的定期扣款幾筆（停用前問「要先改嗎？」）
    let recurringCount: Int
}

/// ⑤ 一個銀行帳戶
struct WealthPageBankRow: Identifiable {
    let id: UUID
    let item: MoneyItem
    let name: String
    /// 這個帳戶的幣別（對存摺選哪一格；兩個以上長按出子選單）
    let codes: [String]
    /// [v25.575] 收起來確認框多的那一句（facts.hideTransferSentence：「有 1 條定期轉帳轉進這裡，會一起結束」）；沒有＝nil
    let hideNote: String?
}

/// [v25.575] ⑤ 銀行帳戶最後一張「定期轉帳・4 條」卡（judge §4.3、樣稿①-2；facts.transferRules 空的＝nil，整張不出現）。
/// 字全部在 WealthPageText.transfers 組好，WealthPageTransfersCard 只畫
struct WealthPageTransfers {
    /// 一列＝一條規則：第一行「薪轉 → 零用錢」＋右「3,000」；第二行「每週五・銀行自動轉」＋右「下次 10/30（五）」；
    /// 第三行（有才出現）最要緊的一件「銀行設到 2027/4/9」
    struct Row: Identifiable {
        /// 規則的 id（點了開規則頁）
        let id: UUID
        /// 「薪轉 → 零用錢」（有取名字寫名字）
        let title: String
        /// 「每週五・銀行自動轉」「每月最後一天・自己轉」
        let detail: String
        /// 「3,000」；遮住「••••」
        let amount: String
        /// 還在跑：「下次 10/30（五）」「沒有下一期」；已結束：「最後一次 2026/12/6」「一期都不算」
        let next: String
        /// 第三行（有才出現）：「4/9 最後一次」「零用錢 已經收起來」「轉進的帳戶已經刪掉了」「銀行設到 2027/4/9」；
        /// 已結束的「零用錢收起來時結束」「帳戶刪掉時結束」
        let note: String?
        /// 第三行用注意色（14 天內最後一次、對方收起來／找不到）；其他灰
        let noteWarn: Bool
        /// 已結束的那幾列（淡一點）
        let ended: Bool
        /// VoiceOver「薪轉 轉到 零用錢，每週五，銀行自動轉，3,000 元，下次 10 月 30 日」（遮住念「金額已遮住」）
        let accessibilityText: String
    }

    /// 標頭「定期轉帳・4 條」（還在跑的條數；一條都沒在跑「定期轉帳」）
    let title: String
    /// 還在跑的（照轉出帳戶在 ⑤ 的位置、下次日子、建立先後排）
    let rows: [Row]
    /// 一條還在跑的都沒有：「現在沒有還在轉的定期轉帳」；有＝nil
    let emptyText: String?
    /// 「一個月大約轉出 63,000（每週的照一年 52 次算）」（金額粗體；遮住「••••」）；一條還在跑的都沒有＝nil
    let monthly: FinanceLine?
    /// VoiceOver 念 monthly 那一句（遮住念「金額已遮住」）
    let monthlySpoken: String?
    /// 灰字「轉給家人、房東的記在記帳的固定支出（算花掉）。」
    let note: String
    /// 「已結束 1 條」；沒有已結束的＝nil
    let endedTitle: String?
    /// 已結束的（點「已結束 1 條 ›」在卡裡展開；最後一次新的在前）
    let ended: [Row]
    /// 標頭〔＋〕：沒收起來的銀行帳戶兩個以上才有
    let canAdd: Bool
}

/// ⑥ 一個證券戶
struct WealthPageBrokerRow: Identifiable {
    let id: UUID
    let item: MoneyItem
}

/// ⑦ 保單總表一列（[v25.567] 照 WealthPolicyFacts.Row 搬：四個來源，點了開哪裡看 source）
struct WealthPagePolicyRow: Identifiable {
    /// WealthPolicyFacts.Row.id（「p-…」「s-…」「v-…」「h-…-…」）
    let id: String
    /// 點了開哪裡：保單頁／儲蓄險保單卡／車子卡／房屋卡
    let source: WealthPolicySource
    let icon: String
    /// 「國泰人壽 醫療險」「Taycan 車險」
    let title: String
    /// 「24,000」「US$3,000」「—」；遮住「••••」
    let amount: String
    /// 「/年」「躉繳」「繳完了」
    let unit: String?
    /// 右邊小字（點了開別的頁）：「儲蓄險」「車子卡」「房屋卡」；保障型保單 nil
    let tag: String?
    /// 「下次 2027/8/15・刷 CUBE」
    let detail: String?
    let accessibilityText: String
}

/// [v25.567] 保障六格的一格（不含金額；遮住照常）
struct WealthPageCoverCell: Identifiable {
    /// 「medical」「accident」「cancer」「disability」「life」「other」
    let id: String
    /// 「醫療」「癌症／重大疾病」
    let title: String
    let icon: String
    /// 有這一種保單
    let on: Bool
    /// 「國泰人壽」；沒有「還沒記」
    let detail: String

    /// VoiceOver：「醫療，國泰人壽」「意外，還沒記」
    var accessibilityText: String { title + "，" + detail }
}

/// [v25.567] ⑦ 保單總表（facts.policies）
struct WealthPagePolicies {
    let rows: [WealthPagePolicyRow]
    /// 標頭的數字（＝rows 數）
    let count: Int
    /// 「一年約 NT$16萬」；遮住「一年約 NT$ ••••」；算不出來 nil
    let trailing: String?
    /// 最下灰字「保障型一年 6.4萬（不含儲蓄險）・外幣照今天匯率」；不用寫 nil
    let footer: String?
    /// 灰字「記帳裡還有 1 筆保費沒有保單資料：中國人壽意外險 1,200/年」；沒有 nil
    let unclaimedText: String?
    /// 〔補保單〕預填的那一筆記帳保費（unclaimed 的第一筆）
    let unclaimedExpenseId: UUID?
    /// VoiceOver 念灰字那一句（遮住時金額念「金額已遮住」）
    let unclaimedSpoken: String?
    /// 保障六格
    let cells: [WealthPageCoverCell]
}

/// ⑧ 收起來的一列（緊湊項目卡、淡一點）
struct WealthPageHiddenRow: Identifiable {
    let id: UUID
    let item: MoneyItem
    /// 停用的卡（長按〔重新啟用〕）；false＝收起來的帳戶（〔不收起來〕）
    let isCard: Bool
}

struct WealthPageHidden {
    let rows: [WealthPageHiddenRow]
    /// 右邊灰字「玉山 Pi 卡・中華郵政」
    let names: String
}

// MARK: - ①' 橋（v25.565）

/// ①' 看板下的橋：「↗ 這些已算進理財淨資產 NT$1381.1萬 ›」（點了切到理財 › 總覽）
struct WealthPageBridge {
    /// 「這些已算進理財淨資產」
    let text: String
    /// 「NT$1381.1萬」；遮住「NT$ ••••」
    let amount: String
    /// 「這些已算進理財淨資產 1381 萬 560 元」；遮住「這些已算進理財淨資產，金額已遮住」
    let accessibilityText: String
}

// MARK: - 整頁

struct WealthPageData {
    enum Mode {
        /// 一個沒收起來的銀行、一張沒停用的卡都沒有
        case newbie
        /// 只有卡（沒有沒收起來的銀行）
        case cardsOnly
        case normal
    }

    let mode: Mode
    let board: WealthPageBoard
    let tower: WealthTowerScene
    let ribbon: WealthPageRibbon?
    /// 四格（沒有卡：只剩 30 天那一格；只有卡：前三格；新手：空的，換三顆大按鈕）
    let tiles: [WealthPageTile]
    /// ② 要確認（facts.pageChecks；0 件整區不出現）
    let checks: [WealthCheck]
    let upcoming: WealthPageUpcoming?
    let cardsHeader: WealthPageGroupHeader?
    let cards: [WealthPageCardRow]
    /// 沒有銀行帳戶（新手以外）：⑤ 換一張提示卡
    let showBankPrompt: Bool
    let banksHeader: WealthPageGroupHeader?
    let banks: [WealthPageBankRow]
    /// [v25.575] ⑤ 銀行帳戶最後一張「定期轉帳」卡（沒有規則＝nil）
    let transfers: WealthPageTransfers?
    /// [v25.577] ⑤ 最下面一行邀請「在銀行設了預約轉帳？…」〔＋ 定期轉帳〕〔不用了〕（judge §4.1、樣稿③-A5）：
    /// 一條規則都沒有（刪掉的不算）、沒按過〔不用了〕（哪一台按的都算）、沒收起來的銀行兩個以上
    let transferInvite: Bool
    let brokersHeader: WealthPageGroupHeader?
    let brokers: [WealthPageBrokerRow]
    let policies: WealthPagePolicies?
    let hidden: WealthPageHidden?
    /// ⑨ 頁尾（新手不出現）
    let footer: FinanceLine?
    /// [v25.565] ①' 橋（新手、沒傳淨資產不出現）
    let bridge: WealthPageBridge?
    let masked: Bool

    /// 整頁一次組好（主執行緒：ntdWanString 用共用的 NumberFormatter）。
    /// [v25.565] netWorth：理財淨資產（FinanceSnapshot.current(...).netWorth，財富頁算好傳進來）；nil＝橋不出現
    static func build(facts: WealthFacts, milestones: [LifeMilestone], book: WealthBook, expenses: [Expense],
                      insurances: [SavingsInsurance], rates: FinanceRates, ratesUpdatedAt: Date?,
                      now: Date, masked: Bool, dark: Bool, netWorth: Double? = nil) -> WealthPageData {
        let today = WealthCal.day(now)
        let banks = WealthPageText.orderBanks(facts.banks.filter { !$0.hidden })
        let allCards = facts.cards
        let active = WealthPageText.orderCards(allCards.filter { !$0.isDisabled })
        let mode: Mode = banks.isEmpty ? (active.isEmpty ? .newbie : .cardsOnly) : .normal

        let board = WealthPageText.board(facts: facts, mode: mode, banks: banks, cards: allCards,
                                         today: today, masked: masked)
        let tower = WealthPageText.tower(banks: banks, cards: active, mode: mode, today: today)
        let ribbon: WealthPageRibbon? = mode == .normal ? WealthPageText.ribbon(facts: facts, masked: masked) : nil
        let tiles: [WealthPageTile] = mode == .newbie
            ? []
            : WealthPageText.tiles(facts: facts, banks: banks, allCards: allCards, active: active,
                                   today: today, masked: masked)
        let upcoming = WealthPageText.upcoming(banks: banks, facts: facts, rates: rates, masked: masked)

        // ④ 信用卡
        var cardRows: [WealthPageCardRow] = []
        for c in active {
            let item = MoneyItem.wealthCard(c, masked: masked, now: now, dark: dark)
            cardRows.append(WealthPageCardRow(id: c.id, item: item, name: c.fullName, canMarkPaid: c.due > 0.5,
                                              recurringCount: WealthPageText.recurringCount(cardId: c.id,
                                                                                            expenses: expenses,
                                                                                            today: today)))
        }
        let owedActive = active.reduce(0) { $0 + $1.owed }
        let cardsHeader: WealthPageGroupHeader? = active.isEmpty ? nil
            : WealthPageGroupHeader(count: active.count,
                                    total: "還沒扣 " + (masked ? WealthFormat.masked : owedActive.ntdWanString))

        // ⑤ 銀行帳戶
        var bankRows: [WealthPageBankRow] = []
        for a in banks {
            // [v25.566] 外幣第二行「約 NT$102,400（10/19 匯率 32.0）」要匯率更新那天
            let item = MoneyItem.wealthBank(a, facts: facts, rates: rates, masked: masked, now: now,
                                            rateDate: ratesUpdatedAt)
            // [v25.575] 收起來確認框多一句「有 1 條定期轉帳轉進這裡，會一起結束」（沒有＝nil）
            bankRows.append(WealthPageBankRow(id: a.id, item: item, name: a.name, codes: WealthPageText.codes(a),
                                              hideNote: facts.hideTransferSentence(a.id)))
        }
        let banksHeader: WealthPageGroupHeader? = banks.isEmpty ? nil
            : WealthPageGroupHeader(count: banks.count,
                                    total: "存摺合計 " + (masked ? WealthFormat.masked : facts.cashText))
        // [v25.575] ⑤ 銀行帳戶最後一張「定期轉帳」卡（有規則才有）
        let transfers = WealthPageText.transfers(facts: facts, banks: banks, today: today, masked: masked)
        // [v25.577] 沒有規則時 ⑤ 最下面一行邀請（inviteDismissed 同步、合併取聯集：另一台按過〔不用了〕這台也不出現）
        let transferInvite: Bool = facts.transferRules.isEmpty && facts.transferBook.inviteDismissed != true
            && banks.count >= 2

        // ⑥ 證券戶（收起來的放 ⑧）
        let visibleBrokers = WealthPageText.orderBrokers(facts.brokers.filter { facts.account($0.id)?.hidden != true },
                                                         facts: facts)
        var brokerRows: [WealthPageBrokerRow] = []
        for b in visibleBrokers {
            brokerRows.append(WealthPageBrokerRow(id: b.id, item: MoneyItem.wealthBroker(b, facts: facts, masked: masked)))
        }
        let marketValue = visibleBrokers.reduce(0) { $0 + $1.marketValue }
        let brokersHeader: WealthPageGroupHeader? = visibleBrokers.isEmpty ? nil
            : WealthPageGroupHeader(count: visibleBrokers.count,
                                    total: "持股市值 " + (masked ? WealthFormat.masked : marketValue.ntdWanString))

        // [v25.567] ⑦ 保單總表讀 facts.policies（insurances、milestones 不再用來數保單：四個來源 WealthFacts.build 已經合好）
        let policies = WealthPageText.policies(facts: facts, masked: masked)
        let hidden = WealthPageText.hidden(facts: facts, rates: rates, masked: masked, now: now, dark: dark,
                                           ratesUpdatedAt: ratesUpdatedAt)
        let footer: FinanceLine? = mode == .newbie
            ? nil
            : WealthPageText.footer(banks: banks, rates: rates, ratesUpdatedAt: ratesUpdatedAt, today: today)
        let bridge: WealthPageBridge? = mode == .newbie
            ? nil
            : WealthPageText.bridge(netWorth: netWorth, masked: masked)

        return WealthPageData(mode: mode, board: board, tower: tower, ribbon: ribbon, tiles: tiles,
                              checks: facts.pageChecks, upcoming: upcoming,
                              cardsHeader: cardsHeader, cards: cardRows,
                              showBankPrompt: mode == .cardsOnly,
                              banksHeader: banksHeader, banks: bankRows, transfers: transfers,
                              transferInvite: transferInvite, brokersHeader: brokersHeader, brokers: brokerRows,
                              policies: policies, hidden: hidden, footer: footer, bridge: bridge, masked: masked)
    }
}

// MARK: - 字（全部在這裡組；body 只畫）

enum WealthPageText {
    /// 遮住時句子裡的數字
    static let dots = "••••"

    // MARK: 金額、日期

    /// 句子裡的萬不寫 NT$：「4.8萬」「1381.1萬」；一萬以下寫到元「9,800」；負的前面「-」
    static func wan(_ v: Double) -> String {
        if Swift.abs(v) >= 10_000 {
            return v.ntdWanString.replacingOccurrences(of: "NT$", with: "")
        }
        return WealthFormat.grouped(v.rounded(), decimals: 0)
    }

    /// VoiceOver 念的金額：「81 萬 6,800 元」「50 萬元」「1,860 元」「負 3,200 元」
    static func spoken(_ v: Double) -> String {
        let r = Swift.abs(v).rounded()
        guard r.isFinite, r < 9e15 else { return WealthFormat.grouped(v, decimals: 0) + " 元" }
        let n = Int64(r)
        let yi = n / 100_000_000
        let wanPart = (n % 100_000_000) / 10_000
        let rest = n % 10_000
        var s = ""
        if yi > 0 { s += "\(yi) 億" }
        if wanPart > 0 { s += (s.isEmpty ? "" : " ") + "\(wanPart) 萬" }
        if rest > 0 || s.isEmpty {
            s += (s.isEmpty ? "" : " ") + WealthFormat.grouped(Double(rest), decimals: 0) + " 元"
        } else {
            s += "元"
        }
        return (v < 0 && n != 0 ? "負 " : "") + s
    }

    /// 「10/27」
    static func md(_ d: Date) -> String { WealthFormat.monthDay(d) }

    /// VoiceOver 的日期「10 月 27 日」
    static func spokenDate(_ d: Date) -> String {
        let c = WealthCal.calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }

    /// 「2027/8/15」
    static func ymd(_ d: Date) -> String {
        let c = WealthCal.calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 看板日期列「10/19 週一」（只寫日期；樣稿①註 3）
    static func boardDate(_ d: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let w = WealthCal.calendar.component(.weekday, from: d)
        let name = (w >= 1 && w <= 7) ? names[w - 1] : ""
        return md(d) + " 週" + name
    }

    /// 百分比的字「8.3%」
    static func percent(_ ratio: Double) -> String { WealthFormat.percent(ratio) }

    /// 使用率四段字（同 WealthFacts.Card.usageTierName：30／50／90%）
    static func tierName(_ u: Double) -> String {
        if u < 0.3 { return "很寬鬆" }
        if u < 0.5 { return "正常" }
        if u < 0.9 { return "偏高" }
        return "快刷滿了"
    }

    static func tier(_ u: Double) -> Int {
        if u < 0.3 { return 0 }
        if u < 0.5 { return 1 }
        if u < 0.9 { return 2 }
        return 3
    }

    // MARK: 名字

    /// 銀行簡稱：去「國際商業銀行」「商業銀行」「銀行」（「國泰世華商業銀行」→「國泰世華」）；去完只剩「台灣」照原名
    static func bankShort(_ name: String) -> String {
        let full = name.trimmingCharacters(in: .whitespaces)
        var s = full
        for suffix in ["國際商業銀行", "商業銀行", "銀行"] where s.hasSuffix(suffix) && s.count > suffix.count {
            s = String(s.dropLast(suffix.count))
            break
        }
        if s == "台灣" || s == "臺灣" { return full }
        return s
    }

    /// 卡的短名（去「@」）：「@GoGo」→「GoGo」
    static func cardShort(_ name: String) -> String {
        let s = name.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? name : s
    }

    /// 卡費那一列的標題「@GoGo 10 月帳單（還沒繳）」→「GoGo」（沒有卡的 id 時用）
    static func cardShort(fromBillTitle title: String) -> String {
        let cut = title.replacingOccurrences(of: #"\s*\d+ 月帳單.*$"#, with: "", options: .regularExpression)
        return cardShort(cut.isEmpty ? title : cut)
    }

    /// 接下來那一列的短名：股票「交割」、卡費「GoGo」、其他照標題（最多 6 個字）
    static func shortName(_ row: WealthLedgerRow, facts: WealthFacts) -> String {
        switch row.kind {
        case .stockBuy, .stockSell:
            return "交割"
        case .dividend:
            return "股利"
        case .cardBill:
            if let c = facts.card(row.cardId) { return cardShort(c.name) }
            return cardShort(fromBillTitle: row.title)
        case .timeDeposit:
            // [v25.566] 轉定存、定存到期、定存解約（標題前 6 字會變「台灣銀行 定」）
            return "定存"
        case .interest where row.timeDepositId != nil:
            // [v25.566] 定存利息（本金續存的利息、舊的定存種類帳戶到期的利息）
            return "定存利息"
        case .transferOut, .transferIn:
            // [v25.575] 轉帳（定期、單次）：「轉給房貸扣款」「來自薪轉」（前 6 字會變「轉給 房貸扣」）；換匯「換匯（換出）」照原字
            return transferShort(row.title)
        default:
            return String(row.title.prefix(6))
        }
    }

    /// 不夠扣那一筆的短名（WealthShortage 沒有卡的 id）
    static func shortName(_ s: WealthShortage) -> String {
        switch s.kind {
        case .stockBuy, .stockSell: return "交割"
        case .cardBill: return cardShort(fromBillTitle: s.title)
        // [v25.566] 起存那天從活存轉出（「轉定存（一年定存）」）
        case .timeDeposit: return "轉定存"
        // [v25.575] 定期轉帳、單次轉帳轉出：「轉給零用錢」（四格「薪轉・11/13 轉給零用錢前」）
        case .transferOut, .transferIn: return transferShort(s.title)
        default: return String(s.title.prefix(6))
        }
    }

    /// [v25.575] 轉帳的短名：「轉給 房貸扣款」→「轉給房貸扣款」、「來自 薪轉」→「來自薪轉」（只拿掉開頭那個空白，
    /// 暱稱裡的空白照留、不截字）；其他（換匯「換匯（換出）」）照原字
    static func transferShort(_ title: String) -> String {
        for head in ["轉給 ", "來自 "] where title.hasPrefix(head) {
            return String(head.dropLast()) + String(title.dropFirst(head.count))
        }
        return title
    }

    /// 接下來一列的金額「−52,340」「+80,000」「約 −23,000」（句子裡：台幣不寫 NT$）
    static func signed(_ row: WealthLedgerRow) -> String {
        let body = WealthFormat.plain(row.amount, code: row.code)
        return (row.isEstimate ? "約 " : "") + (row.isOutflow ? "−" : "+") + body
    }

    /// 一列換台幣（排「最大的兩件」用；查不到匯率照原數字）
    static func ntd(_ row: WealthLedgerRow, rates: FinanceRates) -> Double {
        row.amount * (rates.known(row.code) ?? 1)
    }

    /// 這個帳戶的幣別（對存摺選哪一格）：台幣在前；都沒有＝["NT$"]
    static func codes(_ a: WealthFacts.Account) -> [String] {
        a.currencies.isEmpty ? ["NT$"] : a.currencies
    }

    // MARK: 排序

    /// 銀行：有 sortIndex 的照它（小的在前）、沒有的排後面；都沒排過照最近 90 天進出筆數多到少
    static func orderBanks(_ list: [WealthFacts.Account]) -> [WealthFacts.Account] {
        list.enumerated().sorted { l, r in
            let a = l.element
            let b = r.element
            switch (a.sortIndex, b.sortIndex) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            if a.recentCount != b.recentCount { return a.recentCount > b.recentCount }
            return l.offset < r.offset
        }.map(\.element)
    }

    /// 證券戶：有 sortIndex 的照它（排序表單拖的，小的在前）、沒有的排後面照原本先後
    static func orderBrokers(_ list: [WealthFacts.Broker], facts: WealthFacts) -> [WealthFacts.Broker] {
        list.enumerated().sorted { l, r in
            let x: Int? = facts.account(l.element.id)?.sortIndex
            let y: Int? = facts.account(r.element.id)?.sortIndex
            switch (x, y) {
            case let (p?, q?) where p != q: return p < q
            case (.some, nil): return true
            case (nil, .some): return false
            default: return l.offset < r.offset
            }
        }.map(\.element)
    }

    /// 卡：有 sortIndex 的照它；都沒排過：有要繳的在前、截止日近的在前
    static func orderCards(_ list: [WealthFacts.Card]) -> [WealthFacts.Card] {
        list.enumerated().sorted { l, r in
            let a = l.element
            let b = r.element
            switch (a.sortIndex, b.sortIndex) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            let aDue = a.due > 0.5
            let bDue = b.due > 0.5
            if aDue != bDue { return aDue }
            let ad = a.dueStatement?.due ?? a.nextDue
            let bd = b.dueStatement?.due ?? b.nextDue
            if ad != bd { return ad < bd }
            return l.offset < r.offset
        }.map(\.element)
    }

    /// 還在刷這張卡的定期扣款（同 WealthFacts #5 的認法：固定支出、有週期、還沒結束）
    static func recurringCount(cardId: UUID, expenses: [Expense], today: Date) -> Int {
        expenses.filter { e in
            guard e.linkedCreditCardMilestoneId == cardId, e.expenseType == .fixed, e.recurrence != nil else { return false }
            guard let end = e.endDate else { return true }
            return WealthCal.day(end) >= today
        }.count
    }
}

// MARK: - 看板頭部

/// 一句話一段一段組：畫面的字（數字粗體、上色）跟 VoiceOver 念的字一起組
private struct WealthLineBuilder {
    var runs: [FinanceRun] = []
    var spoken: String = ""
    let masked: Bool

    init(masked: Bool) {
        self.masked = masked
    }

    /// 念的時候「・」換成「，」（VoiceOver 照 judge §3.1 那句：「…還沒扣，扣完活存能用…」）
    mutating func text(_ s: String) {
        runs.append(FinanceRun(text: s))
        spoken += s.replacingOccurrences(of: "・", with: "，")
    }

    /// 金額：shown 是畫面上的字（「4.8萬」「18,600」）；遮住時「••••」、念「金額已遮住」
    mutating func money(_ v: Double, shown: String, tone: MoneyTone? = nil) {
        if masked {
            runs.append(FinanceRun(text: WealthPageText.dots, bold: true))
            spoken += "金額已遮住"
        } else {
            runs.append(FinanceRun(text: shown, bold: true, tone: tone))
            spoken += WealthPageText.spoken(v)
        }
    }

    /// 不換台幣念的金額（外幣入帳「美金 3,200.00」）：遮住時一樣「••••」
    mutating func raw(_ shown: String, spoken said: String) {
        if masked {
            runs.append(FinanceRun(text: WealthPageText.dots, bold: true))
            spoken += "金額已遮住"
        } else {
            runs.append(FinanceRun(text: shown, bold: true))
            spoken += said
        }
    }

    var line: FinanceLine { FinanceLine(runs: runs) }
}

/// 膠囊（挑一件）
private struct WealthCapsulePick {
    let text: String
    let icon: String
    let tone: MoneyTone
    let spoken: String
}

extension WealthPageText {
    /// ① 看板頭部：照狀態表挑小字、大字、一句、手寫；膠囊挑一件
    static func board(facts: WealthFacts, mode: WealthPageData.Mode, banks: [WealthFacts.Account],
                      cards: [WealthFacts.Card], today: Date, masked: Bool) -> WealthPageBoard {
        let date = boardDate(today)
        let pick = capsule(banks: banks, cards: cards, today: today, masked: masked)
        var b = WealthLineBuilder(masked: masked)
        let label: String
        let big: String
        var bigTone: MoneyTone? = nil
        let bigSpoken: String
        var greeting: [String] = ["Cash", "flows!"]

        switch mode {
        case .newbie:
            label = "存款合計"
            big = "—"
            bigSpoken = "存款合計，還沒有帳戶"
            b.text("加一個常用的帳戶，記帳扣款、卡費、薪水入帳就會接起來")
            greeting = ["Hello,", "wallet!"]
        case .cardsOnly:
            label = "卡費還沒扣"
            big = masked ? WealthFormat.masked : facts.owedCards.ntdWanString
            bigSpoken = "卡費還沒扣 " + (masked ? "金額已遮住" : spoken(facts.owedCards))
            cardsOnlyLine(&b, cards: cards)
            greeting = ["Pay", "on time!"]
        case .normal:
            label = "存款合計（存摺上）"
            big = masked ? WealthFormat.masked : facts.cashText
            if facts.cash < -0.5 { bigTone = .bad }
            let approx: String = facts.cashIsApprox ? "約 " : ""
            bigSpoken = masked ? "存款合計 金額已遮住" : "存款合計 \(approx)\(spoken(facts.cash))"
            greeting = normalLine(&b, facts: facts, banks: banks, cards: cards, today: today)
        }

        var a11y = bigSpoken + "。"
        if !b.spoken.isEmpty { a11y += b.spoken + "。" }
        if let p = pick { a11y += p.spoken + "。" }

        return WealthPageBoard(date: date, capsule: pick?.text, capsuleIcon: pick?.icon,
                               capsuleTone: pick?.tone ?? .neutral, label: label, big: big, bigTone: bigTone,
                               line: b.line, greeting: greeting, accessibilityText: a11y, seed: 71)
    }

    /// 只有卡：「要繳 18,600・還沒出帳 2.9萬」
    private static func cardsOnlyLine(_ b: inout WealthLineBuilder, cards: [WealthFacts.Card]) {
        let dueCards = cards.filter { $0.due > 0.5 }
        let due = dueCards.reduce(0) { $0 + $1.due }
        let unbilled = cards.reduce(0) { $0 + $1.unbilled }
        if due > 0.5 {
            b.text("要繳 ")
            b.money(due, shown: dueCards.count == 1 ? WealthFormat.grouped(due.rounded(), decimals: 0) : wan(due))
            if unbilled > 0.5 {
                b.text("・還沒出帳 ")
                b.money(unbilled, shown: wan(unbilled))
            }
        } else if unbilled > 0.5 {
            b.text("還沒出帳 ")
            b.money(unbilled, shown: wan(unbilled))
        } else {
            b.text("這期還沒刷")
        }
    }

    /// 有銀行帳戶：照狀態表組一句，回傳手寫
    private static func normalLine(_ b: inout WealthLineBuilder, facts: WealthFacts, banks: [WealthFacts.Account],
                                   cards: [WealthFacts.Card], today: Date) -> [String] {
        // 某帳戶 30 天內會不夠扣：照平常那句
        if banks.contains(where: { $0.shortage != nil }) {
            pendingLine(&b, facts: facts)
            return ["Top it", "up!"]
        }
        // 有逾期：「10/27 的 CUBE 帳單 18,600 還沒繳」
        if let c = cards.first(where: { $0.overdue > 0.5 }) {
            let due = c.dueStatement?.due ?? today
            b.text("\(md(due)) 的 \(c.name) 帳單 ")
            b.money(c.overdue, shown: WealthFormat.grouped(c.overdue.rounded(), decimals: 0))
            b.text(" 還沒繳")
            return ["Pay", "today!"]
        }
        // 領薪日起 3 天：「月薪 +80,000 進薪轉了・卡費還沒扣 2.9萬」
        if let pay = payday(banks: banks, today: today) {
            b.text(pay.row.title + " ")
            if FinanceRates.isNTD(pay.row.code) {
                b.money(pay.row.amount, shown: "+" + WealthFormat.plain(pay.row.amount, code: pay.row.code))
            } else {
                // 外幣入帳：念的時候照原幣寫（不換台幣）
                let plain = WealthFormat.plain(pay.row.amount, code: pay.row.code)
                b.raw("+" + plain, spoken: plain)
            }
            b.text(" 進" + pay.name + "了")
            if facts.owedCards > 0.5 {
                b.text("・卡費還沒扣 ")
                b.money(facts.owedCards, shown: wan(facts.owedCards))
            }
            return ["Pay", "day!"]
        }
        // 有幣別查不到匯率
        if facts.cashIsApprox, !facts.unknownCodes.isEmpty {
            b.text(facts.unknownCodes.joined(separator: "、") + "沒有匯率，先不算進合計")
            return ["Cash", "flows!"]
        }
        // 要繳都 0（有沒停用的卡；只剩停用的卡不算「都繳了」）
        if cards.contains(where: { !$0.isDisabled }), cards.allSatisfy({ $0.due < 0.5 }) {
            allPaidLine(&b, facts: facts)
            return ["All", "covered!"]
        }
        pendingLine(&b, facts: facts)
        return ["Cash", "flows!"]
    }

    /// 平常：「卡費 4.8萬、交割 5.2萬還沒扣・扣完活存能用 11.4萬」；只有一種「卡費還沒扣 4.8萬・扣完活存能用 16.7萬」
    private static func pendingLine(_ b: inout WealthLineBuilder, facts: WealthFacts) {
        var parts: [(name: String, value: Double)] = []
        if facts.owedCards > 0.5 { parts.append((name: "卡費", value: facts.owedCards)) }
        if facts.pendingSettlement > 0.5 { parts.append((name: "交割", value: facts.pendingSettlement)) }
        if facts.scheduledOut > 0.5 { parts.append((name: "其他", value: facts.scheduledOut)) }
        if parts.isEmpty {
            b.text("沒有還沒扣的錢・活存能用 ")
            usable(&b, facts.usable)
            return
        }
        if parts.count == 1, let only = parts.first {
            b.text(only.name + "還沒扣 ")
            b.money(only.value, shown: wan(only.value))
        } else {
            for (i, p) in parts.enumerated() {
                b.text((i == 0 ? "" : "、") + p.name + " ")
                b.money(p.value, shown: wan(p.value))
            }
            b.text("還沒扣")
        }
        b.text("・扣完活存能用 ")
        usable(&b, facts.usable)
    }

    /// 要繳都 0：「還沒出帳 2.9萬・扣完活存能用 11.4萬」（有交割、其他接在後面）
    private static func allPaidLine(_ b: inout WealthLineBuilder, facts: WealthFacts) {
        var parts: [(name: String, value: Double)] = []
        if facts.owedCards > 0.5 { parts.append((name: "還沒出帳", value: facts.owedCards)) }
        if facts.pendingSettlement > 0.5 { parts.append((name: "交割", value: facts.pendingSettlement)) }
        if facts.scheduledOut > 0.5 { parts.append((name: "其他", value: facts.scheduledOut)) }
        if parts.isEmpty {
            b.text("要繳的都繳了・活存能用 ")
            usable(&b, facts.usable)
            return
        }
        for (i, p) in parts.enumerated() {
            b.text((i == 0 ? "" : "、") + p.name + " ")
            b.money(p.value, shown: wan(p.value))
        }
        if parts.count > 1 || parts.first?.name != "還沒出帳" { b.text("還沒扣") }
        b.text("・扣完活存能用 ")
        usable(&b, facts.usable)
    }

    /// 扣完能用：負的才 bad
    private static func usable(_ b: inout WealthLineBuilder, _ v: Double) {
        b.money(v, shown: wan(v), tone: v < -0.5 ? .bad : nil)
    }

    /// 領薪日起 3 天：任一銀行今天往前 2 天內有月薪入帳（ledger 新到舊）
    private static func payday(banks: [WealthFacts.Account], today: Date) -> (row: WealthLedgerRow, name: String)? {
        for a in banks {
            for row in a.ledger where row.kind == .recurringIncome && !row.isOutflow {
                let d = WealthCal.days(from: row.date, to: today)
                if d >= 0 && d <= 2 { return (row: row, name: a.name) }
                if d > 2 { break }
            }
        }
        return nil
    }

    /// 膠囊挑一件：不夠扣 > 逾期 > 自己繳的卡 14 天內截止 > 自動扣的卡 14 天內扣 > 要繳的都繳了 ✓
    private static func capsule(banks: [WealthFacts.Account], cards: [WealthFacts.Card], today: Date,
                                masked: Bool) -> WealthCapsulePick? {
        // ① 不夠扣（最早那一筆）
        let shorts = banks.compactMap { a -> (WealthFacts.Account, WealthShortage)? in
            guard let s = a.shortage else { return nil }
            return (a, s)
        }.sorted { $0.1.date < $1.1.date }
        if let first = shorts.first {
            let a = first.0
            let s = first.1
            let head = "\(md(s.date)) \(a.name)"
            let text: String = masked ? "\(head)不夠扣" : "\(head)差 \(WealthFormat.plain(s.short, code: s.code))"
            var say = "\(spokenDate(s.date)) \(a.name)不夠扣"
            if !masked { say += "，差 \(spokenShort(s))" }
            return WealthCapsulePick(text: text, icon: "exclamationmark.triangle", tone: .warn, spoken: say)
        }
        // ② 逾期
        if let c = cards.first(where: { $0.overdue > 0.5 }) {
            let due = c.dueStatement?.due ?? today
            let n = Swift.max(1, WealthCal.days(from: due, to: today))
            return WealthCapsulePick(text: "\(c.name) 已過截止日 \(n) 天", icon: "exclamationmark.circle", tone: .bad,
                                     spoken: "\(c.fullName) 卡已過截止日 \(n) 天")
        }
        // ③ 自己繳／每次問我的卡 14 天內截止（最近的）
        let manual = cards.compactMap { c -> (WealthFacts.Card, Date)? in
            guard !c.payMode.isAuto, let s = c.dueStatement, s.status == .due else { return nil }
            let n = WealthCal.days(from: today, to: s.due)
            return (n >= 0 && n <= 14) ? (c, s.due) : nil
        }.sorted { $0.1 < $1.1 }
        if let first = manual.first {
            let c = first.0
            let due = first.1
            let n = WealthCal.days(from: today, to: due)
            let text = n == 0 ? "\(c.name) 今天截止" : "\(c.name) \(md(due)) 截止・\(n) 天"
            let say = n == 0 ? "\(c.fullName) 卡今天截止" : "\(c.fullName) 卡 \(spokenDate(due))截止，還有 \(n) 天"
            return WealthCapsulePick(text: text, icon: "creditcard", tone: n <= 3 ? .warn : .neutral, spoken: say)
        }
        // ④ 自動扣的卡有要繳、14 天內扣
        let auto = cards.compactMap { c -> (WealthFacts.Card, Date)? in
            guard c.payMode.isAuto, c.due > 0.5, let s = c.dueStatement, s.status == .due else { return nil }
            let n = WealthCal.days(from: today, to: s.due)
            return (n >= 0 && n <= 14) ? (c, s.due) : nil
        }.sorted { $0.1 < $1.1 }
        if let first = auto.first {
            let c = first.0
            let due = first.1
            let n = WealthCal.days(from: today, to: due)
            let from = c.payerName.map { "從\($0)扣" } ?? "扣款"
            let text = n == 0 ? "\(c.name) 今天\(from)" : "\(c.name) \(md(due)) \(from)・\(n) 天"
            let say = n == 0 ? "\(c.fullName) 卡今天\(from)" : "\(c.fullName) 卡 \(spokenDate(due))\(from)，還有 \(n) 天"
            return WealthCapsulePick(text: text, icon: "creditcard", tone: n <= 3 ? .warn : .neutral, spoken: say)
        }
        // ⑤ 卡的要繳都 0、最近 30 天有已繳（同那一句「要繳都 0」：要有沒停用的卡，只剩停用的卡不算）
        if cards.contains(where: { !$0.isDisabled }), cards.allSatisfy({ $0.due < 0.5 }) {
            let recent = cards.contains { c in
                guard let p = c.lastPaid else { return false }
                let d = WealthCal.days(from: p.paidOn ?? p.due, to: today)
                return d >= 0 && d <= 30
            }
            if recent {
                return WealthCapsulePick(text: "要繳的都繳了 ✓", icon: "checkmark.circle", tone: .good,
                                         spoken: "要繳的都繳了")
            }
        }
        return nil
    }

    private static func spokenShort(_ s: WealthShortage) -> String {
        FinanceRates.isNTD(s.code) ? spoken(s.short) : WealthFormat.plain(s.short, code: s.code)
    }
}

// MARK: - 水塔、組成條、四格

extension WealthPageText {
    /// 頂樓水塔（規則照 WealthBoardScenes.swift 檔頭 A＋sim 3）
    static func tower(banks: [WealthFacts.Account], cards: [WealthFacts.Card], mode: WealthPageData.Mode,
                      today: Date) -> WealthTowerScene {
        if mode == .newbie {
            let empty = WealthTowerScene.Tower(level: 0, hatch: 0, kind: .empty, label: "", badge: nil, warn: false,
                                               dashed: true)
            return WealthTowerScene(towers: [empty, empty, empty], cards: [])
        }
        // 塔：前 5 座照頁面順序，第 6 個起併成一座。有卡沒設從哪扣（或扣款帳戶收起來了）要多補一座灰色空塔：
        // 那時只放 4 座＋併塔，整排最多 6 座（G4 照 6 座排塔寬）
        let bankIds = Set(banks.map(\.id))
        let needsEmpty = cards.contains { c in
            guard let p = c.payerId else { return true }
            return !bankIds.contains(p)
        }
        let limit = (needsEmpty && banks.count > 5) ? 4 : 5
        let shown = Array(banks.prefix(limit))
        let rest = Array(banks.dropFirst(limit))
        // [v25.566] 塔的數字：定存帳戶含存著的定存（towerValue），其他照存摺上
        var totals: [Double] = shown.map { towerValue($0) }
        if !rest.isEmpty { totals.append(rest.reduce(0) { $0 + towerValue($1) }) }
        let top = totals.map { Swift.max(0, $0) }.max() ?? 0

        var towers: [WealthTowerScene.Tower] = []
        var towerOf: [UUID: Int] = [:]
        for (i, a) in shown.enumerated() {
            towers.append(towerFor(a, top: top, today: today))
            towerOf[a.id] = i
        }
        if !rest.isEmpty {
            let total = rest.reduce(0) { $0 + towerValue($1) }
            let owed = rest.reduce(0) { $0 + $1.notYetDebited }
            let warn = rest.contains { $0.shortage != nil || $0.ntdTotal < -0.5 }
            towers.append(WealthTowerScene.Tower(level: level(total, top: top), hatch: hatch(owed, of: total),
                                                 kind: .live, label: "其他", badge: "＋\(rest.count)", warn: warn))
            for a in rest { towerOf[a.id] = towers.count - 1 }
        }

        // 卡：站在扣它卡費的那座塔下；沒設、帳戶收起來了＝最後補一座灰色空塔
        var sceneCards: [WealthTowerScene.Card] = []
        var emptyIndex: Int? = nil
        for c in cards {
            let index: Int
            if let p = c.payerId, let t = towerOf[p] {
                index = t
            } else if let e = emptyIndex {
                index = e
            } else {
                let label = towers.isEmpty ? "還沒選從哪扣" : "還沒選"
                towers.append(WealthTowerScene.Tower(level: 0, hatch: 0, kind: .empty, label: label, badge: nil,
                                                     warn: false))
                emptyIndex = towers.count - 1
                index = towers.count - 1
            }
            let next = c.dueStatement?.due ?? c.nextDue
            sceneCards.append(WealthTowerScene.Card(tower: index, dashed: !c.payMode.isAuto, color: c.faceColor,
                                                    label: md(next)))
        }
        return WealthTowerScene(towers: towers, cards: sceneCards)
    }

    /// [v25.566] today：定存小牌「3/15」、到期前 7 天鎖頭打開一半（sim_v5 tower_deposit）
    private static func towerFor(_ a: WealthFacts.Account, top: Double, today: Date) -> WealthTowerScene.Tower {
        let kind: WealthTowerScene.Tower.Kind
        var badge: String? = nil
        var lockIsOpen = false
        if a.showsAsDeposit {
            // [v25.566] 舊的「定存」種類、或有定存而存摺上都是 0：金水＋鎖頭，小牌＝最近到期那一期
            kind = .deposit
            badge = a.nextMaturing?.maturityText(today)
            lockIsOpen = lockOpen(a, today: today)
        } else if let code = foreignCode(a) {
            kind = .foreign
            badge = FinanceRates.isUSD(code) ? "US$" : String(code.prefix(3))
        } else {
            kind = .live
        }
        let label = a.nickname ?? String(bankShort(a.bankName).prefix(4))
        let warn = a.shortage != nil || a.ntdTotal < -0.5
        let value = towerValue(a)
        return WealthTowerScene.Tower(level: level(value, top: top), hatch: hatch(a.notYetDebited, of: value),
                                      kind: kind, label: label, badge: badge, warn: warn, lockOpen: lockIsOpen)
    }

    /// [v25.566] 塔裡的水：定存帳戶＝存摺上＋存著的定存（totalNTD），其他＝存摺上（ntdTotal）
    private static func towerValue(_ a: WealthFacts.Account) -> Double {
        a.showsAsDeposit ? a.totalNTD : a.ntdTotal
    }

    /// [v25.566] 鎖頭打開一半：有到期再決定、已經到期還沒決定的；或最近到期那一期 0…7 天內到期
    private static func lockOpen(_ a: WealthFacts.Account, today: Date) -> Bool {
        if a.timeDeposits.contains(where: { $0.status == .waiting }) { return true }
        guard let left = a.nextMaturing?.daysLeft(today) else { return false }
        return left >= 0 && left <= 7
    }

    /// 外幣帳戶（種類是外幣、或只有一個不是台幣的幣別）的那個幣別；不是外幣帳戶 nil
    static func foreignCode(_ a: WealthFacts.Account) -> String? {
        if let c = a.singleCode, !FinanceRates.isNTD(c) { return c }
        if a.isForeignType {
            return a.currencies.first(where: { !FinanceRates.isNTD($0) }) ?? "外幣"
        }
        return nil
    }

    /// 水位 √(存摺上÷最大那座)；負的、0 元＝0
    private static func level(_ v: Double, top: Double) -> Double {
        guard top > 0.5, v > 0 else { return 0 }
        return Swift.min(1, (v / top).squareRoot())
    }

    /// 斜線 還沒扣÷存摺上（比水還多＝1）
    private static func hatch(_ owed: Double, of total: Double) -> Double {
        guard total > 0.5, owed > 0 else { return 0 }
        return Swift.min(1, owed / total)
    }

    /// 存款組成條：活存藍、定存金、外幣青（外幣一律「約」）
    static func ribbon(facts: WealthFacts, masked: Bool) -> WealthPageRibbon? {
        var parts: [(id: String, name: String, theme: MoneyArtTheme, value: Double, approx: Bool)] = []
        if facts.live > 0.5 { parts.append((id: "live", name: "活存", theme: .wealthLive, value: facts.live, approx: false)) }
        if facts.fixedDeposit > 0.5 {
            parts.append((id: "fixed", name: "定存", theme: .wealthDeposit, value: facts.fixedDeposit, approx: false))
        }
        if facts.foreign > 0.5 {
            parts.append((id: "foreign", name: "外幣", theme: .wealthForeign, value: facts.foreign, approx: true))
        }
        guard !parts.isEmpty else { return nil }
        let total = parts.reduce(0) { $0 + $1.value }
        let segments: [MoneyShareRibbon.Segment] = parts.count >= 2
            ? parts.map { MoneyShareRibbon.Segment(theme: $0.theme, value: $0.value) }
            : []
        var legend: [WealthPageLegend] = []
        var said: [String] = []
        for p in parts {
            let approx: String = p.approx ? "約" : ""
            let amount: String = masked ? dots : "\(approx)\(wan(p.value))"
            legend.append(WealthPageLegend(id: p.id, theme: p.theme, text: "\(p.name) \(amount)"))
            let pct: Int = total > 0 ? Int((p.value / total * 100).rounded()) : 0
            var one = "\(p.name) \(pct)%"
            if !masked { one += "，\(approx)\(spoken(p.value))" }
            said.append(one)
        }
        return WealthPageRibbon(segments: segments, legend: legend,
                                accessibilityText: "存款組成：" + said.joined(separator: "；"))
    }

    /// 四格（沒有卡：只剩 30 天那一格；只有卡：前三格）
    static func tiles(facts: WealthFacts, banks: [WealthFacts.Account], allCards: [WealthFacts.Card],
                      active: [WealthFacts.Card], today: Date, masked: Bool) -> [WealthPageTile] {
        var out: [WealthPageTile] = []
        if !active.isEmpty {
            out.append(dueTile(allCards, masked: masked))
            out.append(unbilledTile(allCards, active: active, masked: masked))
            out.append(availableTile(active, masked: masked))
        }
        if !banks.isEmpty {
            out.append(lowestTile(banks, facts: facts, today: today, masked: masked))
        }
        return out
    }

    /// 要繳：一張寫到元「NT$18,600」；兩張以上萬；0「NT$0」灰字「都繳了」（good）
    private static func dueTile(_ cards: [WealthFacts.Card], masked: Bool) -> WealthPageTile {
        let dueCards = cards.filter { $0.due > 0.5 }
            .sorted { ($0.dueStatement?.due ?? $0.nextDue) < ($1.dueStatement?.due ?? $1.nextDue) }
        let total = dueCards.reduce(0) { $0 + $1.due }
        var value: String
        var detail: String? = nil
        var accent: String? = nil
        var accentTone: MoneyTone = .neutral
        if dueCards.isEmpty {
            value = "NT$0"
            accent = "都繳了"
            accentTone = .good
        } else if dueCards.count == 1, let c = dueCards.first {
            value = WealthFormat.ntd(total)
            let due = c.dueStatement?.due ?? c.nextDue
            if c.overdue > 0.5 {
                accent = c.name + " 已過截止日"
                accentTone = .bad
            } else {
                detail = c.name + " " + md(due) + " 截止"
            }
        } else {
            value = total.ntdWanString
            let first = dueCards.first.map { $0.dueStatement?.due ?? $0.nextDue } ?? Date()
            detail = "\(dueCards.count) 張・最近 \(md(first))"
            if dueCards.contains(where: { $0.overdue > 0.5 }) {
                accent = "有逾期"
                accentTone = .bad
            }
        }
        if masked { value = WealthFormat.masked }
        return WealthPageTile(kind: .due, icon: "doc.text.fill", tint: .orange, label: "要繳", value: value,
                              valueTone: nil, detail: detail, accent: accent, accentTone: accentTone, target: .cards)
    }

    /// 還沒出帳「NT$2.9萬」「2 張・下次 10/25 結帳」
    private static func unbilledTile(_ cards: [WealthFacts.Card], active: [WealthFacts.Card],
                                     masked: Bool) -> WealthPageTile {
        let total = cards.reduce(0) { $0 + $1.unbilled }
        let n = cards.filter { $0.unbilled > 0.5 }.count
        let next = active.map(\.nextClose).min()
        var detail: String? = nil
        if let d = next {
            detail = (n > 0 ? "\(n) 張・下次 " : "下次 ") + md(d) + " 結帳"
        }
        return WealthPageTile(kind: .unbilled, icon: "creditcard.fill", tint: .mint, label: "還沒出帳",
                              value: masked ? WealthFormat.masked : total.ntdWanString, valueTone: nil,
                              detail: detail, accent: nil, accentTone: .neutral, target: .cards)
    }

    /// 還能刷：有額度的卡合計；「額度用了 9.6%・很寬鬆」（沒填額度的卡不算）
    private static func availableTile(_ active: [WealthFacts.Card], masked: Bool) -> WealthPageTile {
        let limited = active.filter { $0.limit != nil }
        let missing = active.count - limited.count
        guard !limited.isEmpty else {
            return WealthPageTile(kind: .available, icon: "gauge.with.dots.needle.33percent", tint: .purple,
                                  label: "還能刷", value: "—", valueTone: nil, detail: "沒填額度", accent: nil,
                                  accentTone: .neutral, target: .cards)
        }
        let available = limited.reduce(0) { $0 + ($1.available ?? 0) }
        let owed = limited.reduce(0) { $0 + $1.owed }
        let limit = limited.reduce(0) { $0 + ($1.limit ?? 0) }
        var detail = ""
        if limit > 0 {
            let u = owed / limit
            detail = "額度用了 " + percent(u) + "・" + tierName(u)
        }
        if missing > 0 { detail += (detail.isEmpty ? "" : "・") + "\(missing) 張沒填額度" }
        return WealthPageTile(kind: .available, icon: "gauge.with.dots.needle.33percent", tint: .purple,
                              label: "還能刷", value: masked ? WealthFormat.masked : available.ntdWanString,
                              valueTone: nil, detail: detail.isEmpty ? nil : detail, accent: nil,
                              accentTone: .neutral, target: .cards)
    }

    /// 30 天內最低：沒收起來的銀行 lowestNTD 最小那個；有不夠扣「差 NT$23,940」（warn）
    private static func lowestTile(_ banks: [WealthFacts.Account], facts: WealthFacts, today: Date,
                                   masked: Bool) -> WealthPageTile {
        let shorts = banks.compactMap { a -> (WealthFacts.Account, WealthShortage)? in
            guard let s = a.shortage else { return nil }
            return (a, s)
        }.sorted { $0.1.date < $1.1.date }
        var value: String
        var tone: MoneyTone? = nil
        let detail: String
        if let first = shorts.first {
            let a = first.0
            let s = first.1
            value = "差 " + WealthFormat.money(s.short, code: s.code)
            tone = .warn
            detail = "\(a.name)・\(md(s.date)) \(shortName(s))前"
            if masked { value = "差 " + WealthFormat.masked }
        } else {
            let pool = lowestPool(banks)
            let lows = pool.compactMap { a -> (WealthFacts.Account, Double)? in
                guard let l = a.lowestNTD else { return nil }
                return (a, l)
            }
            if let best = lows.min(by: { $0.1 < $1.1 }) {
                let a = best.0
                let low = best.1
                value = "約 " + low.ntdWanString
                if low < -0.5 { tone = .bad }
                detail = lowestDetail(a, facts: facts, today: today)
            } else {
                let now = pool.map(\.ntdTotal).min() ?? 0
                value = now.ntdWanString
                if now < -0.5 { tone = .bad }
                detail = "30 天內沒有扣款"
            }
            if masked { value = WealthFormat.masked }
        }
        // ③ 不出現（30 天內都沒有進出）就捲到 ⑤
        let target: WealthPageAnchor = banks.contains(where: { !$0.next30.isEmpty }) ? .upcoming : .banks
        return WealthPageTile(kind: .lowest, icon: "drop.fill", tint: .blue, label: "30 天內最低", value: value,
                              valueTone: tone, detail: detail, accent: nil, accentTone: .neutral, target: target)
    }

    /// [v25.566] 「30 天內最低」看哪些帳戶：定存帳戶（showsAsDeposit：錢在定存裡、存摺上常是 0）不算，
    /// 不然記了一筆從活存轉出的定存，這格就變「約 NT$0・台灣銀行」；全部都是定存帳戶才照算
    private static func lowestPool(_ banks: [WealthFacts.Account]) -> [WealthFacts.Account] {
        let live = banks.filter { !$0.showsAsDeposit }
        return live.isEmpty ? banks : live
    }

    /// 「房貸扣款・11/5 房貸後」（最低那天最後一筆的短名＋「後」）；最低就是今天「房貸扣款・今天」
    private static func lowestDetail(_ a: WealthFacts.Account, facts: WealthFacts, today: Date) -> String {
        guard let d = a.lowestDate, WealthCal.day(d) > today else { return a.name + "・今天" }
        let day = WealthCal.day(d)
        if let last = a.next30.last(where: { WealthCal.day($0.date) == day }) {
            return "\(a.name)・\(md(d)) \(shortName(last, facts: facts))後"
        }
        return a.name + "・" + md(d)
    }
}

// MARK: - ③ 接下來 30 天

/// [v25.577] 〔看全部〕併列用：一筆轉帳的一邊在哪（帳戶在 listed 的位置、在那個帳戶 next30 的位置、是不是轉出、幣別）
private struct WealthPageUpcomingSpot {
    let order: Int
    let index: Int
    let out: Bool
    let code: String
}

/// [v25.577] 〔看全部〕要併成一列的一筆轉帳：轉出那一列在哪（帳戶位置、next30 位置）、轉入那邊是哪個帳戶（listed 的位置）
private struct WealthPageUpcomingPair {
    let outOrder: Int
    let outIndex: Int
    let inOrder: Int
}

extension WealthPageText {
    /// 每個沒收起來、30 天內有進出的銀行一列；「看 6 件」照日期排全部。
    /// [v25.577] 〔看全部〕一筆轉帳（定期轉帳的一期、一筆單次轉帳）兩邊帳戶各一列 → 併成一列（upcomingTransferPairs）；
    /// 件數照併完的算（judge §11 例：各帳戶分開 18 列 → 11 件）。③ 每個帳戶那一列（upcomingRow）照舊各算各的。
    /// 排序：日子 → 帳戶在 listed 的位置（併的那列用轉出帳戶）→ 那一列在帳戶 next30 裡的位置（Swift 的 sort 不穩定：
    /// 第三層一定要有，同一天同一個帳戶的先後才不會亂）
    static func upcoming(banks: [WealthFacts.Account], facts: WealthFacts, rates: FinanceRates,
                         masked: Bool) -> WealthPageUpcoming? {
        let listed = banks.filter { !$0.next30.isEmpty }
        guard !listed.isEmpty else { return nil }
        let pairs = upcomingTransferPairs(listed)
        var rows: [WealthPageUpcomingRow] = []
        var all: [(day: Date, order: Int, index: Int, item: WealthPageUpcomingItem)] = []
        for (order, a) in listed.enumerated() {
            rows.append(upcomingRow(a, facts: facts, rates: rates, masked: masked))
            for (index, row) in a.next30.enumerated() {
                let day = WealthCal.day(row.date)
                let item: WealthPageUpcomingItem
                if let key = upcomingTransferKey(row), let pair = pairs[key] {
                    // 併的那一列只在轉出那邊出一次；轉入那邊那一列跳過
                    guard pair.outOrder == order, pair.outIndex == index else { continue }
                    item = upcomingTransferItem(row, from: a, to: listed[pair.inOrder], key: key, masked: masked)
                } else {
                    item = upcomingItem(row, account: a, facts: facts, masked: masked)
                }
                all.append((day: day, order: order, index: index, item: item))
            }
        }
        let sorted = all.sorted { l, r in
            if l.day != r.day { return l.day < r.day }
            if l.order != r.order { return l.order < r.order }
            return l.index < r.index
        }.map(\.item)
        return WealthPageUpcoming(trailing: "\(sorted.count) 件", rows: rows, all: sorted)
    }

    /// [v25.577] 一筆轉帳兩邊共用的 key：定期轉帳「r|規則|2026-11-06」（transferRuleId＋periodKey）、單次「p|配對」（transferPairId）；
    /// 不是轉帳的列 nil
    private static func upcomingTransferKey(_ row: WealthLedgerRow) -> String? {
        guard row.kind == .transferOut || row.kind == .transferIn else { return nil }
        if let rid = row.transferRuleId, let key = row.periodKey {
            return "r|" + rid.uuidString + "|" + key
        }
        if let pid = row.transferPairId {
            return "p|" + pid.uuidString
        }
        return nil
    }

    /// [v25.577] 哪幾筆轉帳要併成一列：同一個 key 剛好兩列、在兩個不同帳戶（都在 listed 裡）、一出一進、兩邊同一個幣別才併。
    /// 另一邊收起來（不在 listed）＝只有一列、換匯（同一個帳戶的兩格）＝同一個帳戶 → 都照舊單列；
    /// 兩個帳戶之間台幣轉外幣的單次轉帳也照舊兩列（併成一列只看得到轉出那邊的幣別與金額）
    private static func upcomingTransferPairs(_ listed: [WealthFacts.Account]) -> [String: WealthPageUpcomingPair] {
        var found: [String: [WealthPageUpcomingSpot]] = [:]
        for (order, a) in listed.enumerated() {
            for (index, row) in a.next30.enumerated() {
                guard let key = upcomingTransferKey(row) else { continue }
                let spot = WealthPageUpcomingSpot(order: order, index: index, out: row.isOutflow, code: row.code)
                found[key, default: []].append(spot)
            }
        }
        var pairs: [String: WealthPageUpcomingPair] = [:]
        for (key, spots) in found where spots.count == 2 {
            guard let o = spots.first(where: { $0.out }), let i = spots.first(where: { !$0.out }),
                  o.order != i.order, o.code == i.code else { continue }
            pairs[key] = WealthPageUpcomingPair(outOrder: o.order, outIndex: o.index, inOrder: i.order)
        }
        return pairs
    }

    /// [v25.577] 併成一列的一筆轉帳（judge §4.3、sim_v1b §9）：日期塊「轉」、藍圓；「薪轉 → 零用錢」（兩個帳戶的名字，不用規則的名字）、
    /// 右「3,000」（不帶正負號；遮住 ••••）、灰字「薪轉扣完剩 49,400・定期」（自己轉的那條「・自己轉」、單次轉帳不加尾巴；
    /// 遮住「薪轉扣完剩 ••••・定期」）；轉出那邊扣完是負的整列 warn。id「tr|」＋key；定期那一期帶 transferRuleId／periodKey（點了開那一期）。
    /// VoiceOver「10 月 30 日，薪轉 轉到 零用錢，3,000，薪轉扣完剩 49,400，定期」
    private static func upcomingTransferItem(_ row: WealthLedgerRow, from a: WealthFacts.Account,
                                             to b: WealthFacts.Account, key: String,
                                             masked: Bool) -> WealthPageUpcomingItem {
        let c = WealthCal.calendar.dateComponents([.month, .day], from: row.date)
        let plain: String = WealthFormat.plain(row.amount, code: row.code)
        let after: String = WealthFormat.plain(row.balanceAfter, code: row.code)
        let tail: String = upcomingTransferTail(row)
        var detail: String = a.name + "扣完剩 " + (masked ? dots : after)
        if !tail.isEmpty { detail += "・" + tail }
        let negative = row.balanceAfter < -0.5
        let money: String = "\(plain)，\(a.name)扣完剩 \(after)"
        var said: String = "\(spokenDate(row.date))，\(a.name) 轉到 \(b.name)，"
        said += masked ? "金額已遮住" : money
        if !tail.isEmpty { said += "，" + tail }
        if negative { said += "，會不夠扣" }
        return WealthPageUpcomingItem(id: "tr|" + key, day: "\(c.day ?? 0)", month: "\(c.month ?? 0)月",
                                      glyph: "轉", mark: .other, title: a.name + " → " + b.name, detail: detail,
                                      amount: masked ? dots : plain, negative: negative, accessibilityText: said,
                                      transferRuleId: row.periodKey == nil ? nil : row.transferRuleId,
                                      periodKey: row.transferRuleId == nil ? nil : row.periodKey)
    }

    /// [v25.577] 併的那一列灰字尾巴：定期轉帳「定期」、自己轉的那條「自己轉」、單次轉帳不加（""）
    private static func upcomingTransferTail(_ row: WealthLedgerRow) -> String {
        guard row.transferRuleId != nil else { return "" }
        return row.transferManual ? "自己轉" : "定期"
    }

    private static func upcomingRow(_ a: WealthFacts.Account, facts: WealthFacts, rates: FinanceRates,
                                    masked: Bool) -> WealthPageUpcomingRow {
        let bank: String? = a.nickname == nil ? nil : "（" + bankShort(a.bankName) + "）"
        let low = a.lowestNTD ?? a.ntdTotal
        let lowest: String = masked ? "最低 \(dots)" : "最低 約 \(wan(low))"
        let badge: String
        let tone: MoneyTone
        var said: String
        if a.ntdTotal < -0.5 {
            badge = "現在是負的"
            tone = .bad
            said = "現在是負的"
        } else if let s = a.shortage {
            badge = masked ? "不夠扣" : "差 \(WealthFormat.plain(s.short, code: s.code))"
            tone = .warn
            said = "\(spokenDate(s.date))不夠扣"
            if !masked { said += "，差 \(spokenShort(s))" }
        } else {
            badge = "✓ 夠扣"
            tone = .good
            said = "夠扣"
        }
        // 第二行：最大的兩件（照 |金額|），再照日期排（next30 本來就是舊到新）
        let biggest = biggestTwo(a.next30, rates: rates)
        let pieces: [String] = biggest.map { row in
            let head = md(row.date) + " " + shortName(row, facts: facts)
            return masked ? head : head + " " + signed(row)
        }
        let detail = pieces.joined(separator: "・")
        let lowSaid: String = masked ? "金額已遮住" : "約 \(spoken(low))"
        var who: String = a.name
        if bank != nil { who += "，\(bankShort(a.bankName))" }
        said = "\(who)，30 天內最低 \(lowSaid)，\(said)。\(detail)"
        return WealthPageUpcomingRow(id: a.id, name: a.name, bank: bank, lowest: lowest, badge: badge, badgeTone: tone,
                                     detail: detail, accessibilityText: said)
    }

    /// 金額（換台幣）最大的兩件，照原本的先後（日期）回傳
    private static func biggestTwo(_ rows: [WealthLedgerRow], rates: FinanceRates) -> [WealthLedgerRow] {
        var indexed: [(index: Int, size: Double)] = []
        for (i, row) in rows.enumerated() {
            indexed.append((index: i, size: Swift.abs(ntd(row, rates: rates))))
        }
        indexed.sort { l, r in
            if l.size != r.size { return l.size > r.size }
            return l.index < r.index
        }
        let picked: [Int] = indexed.prefix(2).map { $0.index }.sorted()
        return picked.map { rows[$0] }
    }

    private static func upcomingItem(_ row: WealthLedgerRow, account a: WealthFacts.Account, facts: WealthFacts,
                                     masked: Bool) -> WealthPageUpcomingItem {
        let c = WealthCal.calendar.dateComponents([.month, .day], from: row.date)
        let mark: WealthPageUpcomingItem.Mark
        let glyph: String
        switch row.kind {
        case .stockBuy, .stockSell, .dividend:
            mark = .stock
            glyph = "股"
        case .cardBill:
            mark = .card
            glyph = "卡"
        case .timeDeposit:
            // [v25.566] 轉定存（出去）、定存到期／解約（進帳）
            mark = row.isOutflow ? .other : .income
            glyph = "定"
        default:
            if row.isOutflow {
                mark = .other
                glyph = row.kind == .transferOut ? "轉" : "扣"
            } else {
                mark = .income
                glyph = upcomingInGlyph(row)
            }
        }
        let after = WealthFormat.plain(row.balanceAfter, code: row.code)
        let detail = a.name + "・扣完剩 " + (masked ? dots : after)
        let amount = masked ? dots : signed(row)
        let negative = row.balanceAfter < -0.5
        var said = "\(spokenDate(row.date))，\(row.title)，\(a.name)，"
        said += masked ? "金額已遮住" : "\(signed(row))，扣完剩 \(after)"
        if negative { said += "，會不夠扣" }
        // [v25.577] 沒併的定期轉帳那一期（另一邊收起來了）也帶規則與那一期：〔看全部〕點了一樣開那一期
        return WealthPageUpcomingItem(id: a.id.uuidString + "|" + row.id, day: "\(c.day ?? 0)",
                                      month: "\(c.month ?? 0)月", glyph: glyph, mark: mark, title: row.title,
                                      detail: detail, amount: amount, negative: negative, accessibilityText: said,
                                      transferRuleId: row.periodKey == nil ? nil : row.transferRuleId,
                                      periodKey: row.transferRuleId == nil ? nil : row.periodKey)
    }

    /// 進帳那一列日期塊的字：轉入「轉」、[v25.566] 定存利息「定」、其他「入」
    private static func upcomingInGlyph(_ row: WealthLedgerRow) -> String {
        if row.kind == .transferIn { return "轉" }
        if row.timeDepositId != nil { return "定" }
        return "入"
    }
}

// MARK: - ⑤ 定期轉帳卡（[v25.575] 定期轉帳 v1a；transfer/judge.md §4.3、樣稿①-2）

extension WealthPageText {
    /// 卡底灰字。[v25.577] v1b 銀行頁有 ④「連到這個帳戶的」定期轉帳那一組了：補「在每個帳戶的…看得到」（judge §4.3）
    static let transferNote = "轉給家人、房東的記在記帳（算花掉），在每個帳戶的「連到這個帳戶的」看得到。"

    /// [v25.577] ⑤ 最下面那一行邀請（沒有規則時；judge §4.1、樣稿③-A5）
    static let transferInvite = "在銀行設了預約轉帳？抄一份進來，接下來 30 天就算得準。"

    /// 第三行要緊的那一件：14 天內最後一次幾天內算
    static let transferEndSoonDays = 14

    /// ⑤ 銀行帳戶最後一張「定期轉帳」卡：facts.transferRules（沒刪掉的，含已結束）空的＝nil。
    /// banks：⑤ 的順序（orderBanks、沒收起來的）；還在跑的照「轉出帳戶在 banks 的位置（找不到排最後）→ 下次日子 → 建立先後」排，
    /// 已結束的照最後一次新到舊。一個月大約＝還在跑的 monthlyOut 加總（每週＝每期 × 52 ÷ 12，WealthFacts.makeTransferRules 算好）
    static func transfers(facts: WealthFacts, banks: [WealthFacts.Account], today: Date,
                          masked: Bool) -> WealthPageTransfers? {
        let all: [WealthFacts.TransferRule] = facts.transferRules
        guard !all.isEmpty else { return nil }
        var position: [UUID: Int] = [:]
        for (i, a) in banks.enumerated() where position[a.id] == nil {
            position[a.id] = i
        }
        let running: [WealthFacts.TransferRule] = all.filter { !$0.isEnded }.sorted { l, r in
            let lp: Int = l.fromId.flatMap { position[$0] } ?? Int.max
            let rp: Int = r.fromId.flatMap { position[$0] } ?? Int.max
            if lp != rp { return lp < rp }
            let ld: Date = l.next?.day ?? Date.distantFuture
            let rd: Date = r.next?.day ?? Date.distantFuture
            if ld != rd { return ld < rd }
            return l.order < r.order
        }
        let ended: [WealthFacts.TransferRule] = all.filter { $0.isEnded }.sorted { l, r in
            let ld: Date = l.lastDay ?? Date.distantPast
            let rd: Date = r.lastDay ?? Date.distantPast
            if ld != rd { return ld > rd }
            return l.order < r.order
        }
        var rows: [WealthPageTransfers.Row] = []
        for t in running {
            rows.append(transferRow(t, today: today, masked: masked))
        }
        var endedRows: [WealthPageTransfers.Row] = []
        for t in ended {
            endedRows.append(transferRow(t, today: today, masked: masked))
        }
        let title: String = running.isEmpty ? "定期轉帳" : "定期轉帳・\(running.count) 條"
        let monthly = transferMonthly(running, masked: masked)
        return WealthPageTransfers(title: title, rows: rows,
                                   emptyText: running.isEmpty ? "現在沒有還在轉的定期轉帳" : nil,
                                   monthly: monthly?.line, monthlySpoken: monthly?.spoken, note: transferNote,
                                   endedTitle: ended.isEmpty ? nil : "已結束 \(ended.count) 條", ended: endedRows,
                                   canAdd: banks.count >= 2)
    }

    /// 「一個月大約轉出 63,000（每週的照一年 52 次算）」：金額粗體；有每週的才寫括號；遮住「••••」、念「金額已遮住」
    private static func transferMonthly(_ running: [WealthFacts.TransferRule],
                                        masked: Bool) -> (line: FinanceLine, spoken: String)? {
        guard !running.isEmpty else { return nil }
        let total: Double = running.reduce(0) { $0 + $1.monthlyOut }
        let shown: String = masked ? dots : WealthFormat.grouped(total.rounded(), decimals: 0)
        var runs: [FinanceRun] = [FinanceRun(text: "一個月大約轉出 ")]
        runs.append(FinanceRun(text: shown, bold: true))
        var said: String = "一個月大約轉出 " + (masked ? "金額已遮住" : spoken(total))
        if running.contains(where: { $0.rule.cycleKind == .weekly }) {
            runs.append(FinanceRun(text: "（每週的照一年 52 次算）"))
            said += "，每週的照一年 52 次算"
        }
        return (line: FinanceLine(runs: runs), spoken: said)
    }

    /// 一條一列（還在跑、已結束共用）
    private static func transferRow(_ t: WealthFacts.TransferRule, today: Date,
                                    masked: Bool) -> WealthPageTransfers.Row {
        let detail: String = t.cycleText + "・" + t.modeText
        let amount: String = masked ? dots : WealthFormat.plain(t.amount, code: t.code)
        let amountSaid: String
        if masked {
            amountSaid = "金額已遮住"
        } else if FinanceRates.isNTD(t.code) {
            amountSaid = spoken(t.amount)
        } else {
            amountSaid = WealthFormat.plain(t.amount, code: t.code)
        }
        var said: [String] = [transferSpokenTitle(t), t.cycleText, t.modeText, amountSaid]
        let next: String
        let pick: (text: String, warn: Bool)?
        if t.isEnded {
            next = transferEndedText(t)
            pick = transferEndedNote(t)
            said.append("已結束，" + next)
        } else {
            if let n = t.next {
                next = "下次 " + WealthFormat.monthDayWeek(n.day)
                said.append("下次 " + spokenDate(n.day))
            } else {
                next = "沒有下一期"
                said.append(next)
            }
            pick = transferPick(t, today: today)
        }
        if let p = pick { said.append(p.text) }
        return WealthPageTransfers.Row(id: t.id, title: t.title, detail: detail, amount: amount, next: next,
                                       note: pick?.text, noteWarn: pick?.warn ?? false, ended: t.isEnded,
                                       accessibilityText: said.joined(separator: "，"))
    }

    /// 第三行最要緊的一件：[v25.579] 暫停（灰：「暫停到 12/24」「12/4 起暫停到 12/24」「暫停中」）＞14 天內最後一次（橘）＞
    /// 對方收起來了／找不到（橘）＞銀行設到哪天（灰，年份不是今年才寫年）；都沒有 nil。
    private static func transferPick(_ t: WealthFacts.TransferRule, today: Date) -> (text: String, warn: Bool)? {
        // [v25.579] 暫停最優先（WealthTransferRule.pauseInfo：還在跑、今天以後 400 天內有暫停的期才有；judge §4.3、sim_v2 §10）
        if let p = t.rule.pauseInfo(today: today) {
            return (text: p.text, warn: false)
        }
        if let last = t.lastDay {
            let n = WealthCal.days(from: today, to: last)
            if n >= 0 && n <= transferEndSoonDays {
                let text: String = n == 0 ? "今天最後一次" : md(last) + " 最後一次"
                return (text: text, warn: true)
            }
        }
        if t.toMissing { return (text: "轉進的帳戶已經刪掉了", warn: true) }
        if t.fromMissing { return (text: "轉出的帳戶已經刪掉了", warn: true) }
        if t.toHidden { return (text: t.toName + " 已經收起來", warn: true) }
        if t.fromHidden { return (text: t.fromName + " 已經收起來", warn: true) }
        if let last = t.lastDay {
            return (text: "銀行設到 " + yearAwareDate(last, today: today), warn: false)
        }
        return nil
    }

    /// 已結束那一列第二行右邊：「最後一次 2026/12/6」；設錯了（最後一期比第一期早）「一期都不算」
    private static func transferEndedText(_ t: WealthFacts.TransferRule) -> String {
        guard let last = t.lastDay else { return "已結束" }
        if let first = t.firstDay, last < first { return "一期都不算" }
        return "最後一次 " + ymd(last)
    }

    /// 已結束那一列第三行（灰）：收起來時結束「零用錢收起來時結束」、刪帳戶時結束「帳戶刪掉時結束」；你按的〔結束〕nil
    private static func transferEndedNote(_ t: WealthFacts.TransferRule) -> (text: String, warn: Bool)? {
        switch t.rule.endedBy {
        case "accountHidden"?:
            if t.toHidden { return (text: t.toName + "收起來時結束", warn: false) }
            if t.fromHidden { return (text: t.fromName + "收起來時結束", warn: false) }
            return (text: "帳戶收起來時結束", warn: false)
        case "accountDeleted"?:
            return (text: "帳戶刪掉時結束", warn: false)
        default:
            return nil
        }
    }

    /// VoiceOver 的頭：「薪轉 轉到 零用錢」；有取名字「房租，薪轉 轉到 零用錢」
    private static func transferSpokenTitle(_ t: WealthFacts.TransferRule) -> String {
        let pair: String = t.fromName + " 轉到 " + t.toName
        let plainTitle: String = t.fromName + " → " + t.toName
        if t.title == plainTitle { return pair }
        return t.title + "，" + pair
    }

    /// 今年「4/9」；不是今年「2027/4/9」
    static func yearAwareDate(_ d: Date, today: Date) -> String {
        let y = WealthCal.calendar.component(.year, from: d)
        let ty = WealthCal.calendar.component(.year, from: today)
        return y == ty ? md(d) : ymd(d)
    }
}

// MARK: - ⑦ 保單、⑧ 收起來的、⑨ 頁尾

extension WealthPageText {
    /// ⑦ 保單總表（[v25.567] 財富 v6；judge §3.10、樣稿①⑦）：整區讀 facts.policies（WealthPolicyFacts，四個來源、一筆記帳保費只算一次），
    /// 這裡只搬字、遮金額。一列都沒有、灰字也沒有＝nil（整區不出現；財富的保單都收起來了、也沒有別的來源也是 nil，同 v3）。
    /// trailingText、footerText 用 ntdWanString：主執行緒（build 本來就在主執行緒叫）
    static func policies(facts: WealthFacts, masked: Bool) -> WealthPagePolicies? {
        let pf = facts.policies
        guard !pf.rows.isEmpty || !pf.unclaimed.isEmpty else { return nil }
        var rows: [WealthPagePolicyRow] = []
        for r in pf.rows {
            rows.append(policyRow(r, masked: masked))
        }
        var trailing: String? = nil
        if let t = pf.trailingText {
            trailing = masked ? "一年約 " + WealthFormat.masked : t
        }
        let footer: String? = masked ? maskedPolicyFooter(pf) : pf.footerText
        var unclaimedText: String? = nil
        var unclaimedSpoken: String? = nil
        if let first = pf.unclaimed.first {
            let text: String = masked ? maskedUnclaimedText(pf, first: first) : (pf.unclaimedText ?? first.text)
            unclaimedText = text
            unclaimedSpoken = text.replacingOccurrences(of: dots, with: "金額已遮住")
        }
        var cells: [WealthPageCoverCell] = []
        for c in pf.cells {
            cells.append(WealthPageCoverCell(id: c.id, title: c.title, icon: c.icon, on: c.on, detail: c.detail))
        }
        return WealthPagePolicies(rows: rows, count: rows.count, trailing: trailing, footer: footer,
                                  unclaimedText: unclaimedText, unclaimedExpenseId: pf.unclaimed.first?.expenseId,
                                  unclaimedSpoken: unclaimedSpoken, cells: cells)
    }

    /// 保單總表一列：照 Row 搬；遮住時金額「••••」、VoiceOver「國泰人壽 醫療險，金額已遮住，下次 2027/8/15・刷 CUBE」
    /// （沒有金額「—」的列照 Row 原本那句：本來就沒念金額）
    private static func policyRow(_ r: WealthPolicyFacts.Row, masked: Bool) -> WealthPagePolicyRow {
        let hasAmount = r.amountText != "—"
        let amount: String = (masked && hasAmount) ? dots : r.amountText
        var said: String = r.accessibilityText
        if masked && hasAmount {
            said = r.title + "，金額已遮住"
            if let d = r.detail { said += "，" + d }
        }
        return WealthPagePolicyRow(id: r.id, source: r.source, icon: r.icon, title: r.title, amount: amount,
                                   unit: r.unitText, tag: r.tag, detail: r.detail, accessibilityText: said)
    }

    /// 遮住時的最下灰字：條件同 WealthPolicyFacts.footerText，保障型那段金額換「••••」
    private static func maskedPolicyFooter(_ pf: WealthPolicyFacts) -> String? {
        var parts: [String] = []
        if pf.hasSavings && pf.protectionNTD > 0.5 {
            parts.append("保障型一年 " + dots + "（不含儲蓄險）")
        }
        if pf.hasForeign { parts.append("外幣照今天匯率") }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    /// 遮住時的灰字：同 WealthPolicyFacts.unclaimedText，金額段換「••••」
    private static func maskedUnclaimedText(_ pf: WealthPolicyFacts, first: WealthPolicyFacts.Unclaimed) -> String {
        var s = "記帳裡還有 \(pf.unclaimed.count) 筆保費沒有保單資料：" + first.title + " " + dots
        if pf.unclaimed.count > 1 { s += " 等" }
        return s
    }

    /// ⑧ 收起來的：停用的卡、收起來的銀行、收起來的證券戶（緊湊、淡一點）
    /// [v25.566] ratesUpdatedAt：外幣第二行的匯率日期（同 ⑤）
    static func hidden(facts: WealthFacts, rates: FinanceRates, masked: Bool, now: Date,
                       dark: Bool, ratesUpdatedAt: Date? = nil) -> WealthPageHidden? {
        var rows: [WealthPageHiddenRow] = []
        var names: [String] = []
        for c in facts.cards where c.isDisabled {
            var item = MoneyItem.wealthCard(c, masked: masked, now: now, dark: dark)
            item.dimmed = true
            rows.append(WealthPageHiddenRow(id: c.id, item: item, isCard: true))
            names.append(c.fullName)
        }
        for a in facts.accounts where a.hidden {
            var item: MoneyItem
            if a.isSecurities, let b = facts.broker(a.id) {
                item = MoneyItem.wealthBroker(b, facts: facts, masked: masked)
            } else {
                item = MoneyItem.wealthBank(a, facts: facts, rates: rates, masked: masked, now: now,
                                            rateDate: ratesUpdatedAt)
            }
            item.dimmed = true
            rows.append(WealthPageHiddenRow(id: a.id, item: item, isCard: false))
            names.append(a.name)
        }
        guard !rows.isEmpty else { return nil }
        return WealthPageHidden(rows: rows, names: names.joined(separator: "・"))
    }

    /// [v25.565] ①' 橋：「這些已算進理財淨資產」＋「NT$1381.1萬」（ntdWanString：整數不帶 .0、萬前不加千分位）；
    /// 沒有淨資產（呼叫端沒傳）nil。遮住：金額「NT$ ••••」、VoiceOver「金額已遮住」
    static func bridge(netWorth: Double?, masked: Bool) -> WealthPageBridge? {
        guard let v = netWorth, v.isFinite else { return nil }
        let text = "這些已算進理財淨資產"
        let amount: String = masked ? WealthFormat.masked : v.ntdWanString
        let said: String = masked ? text + "，金額已遮住" : text + " " + spoken(v)
        return WealthPageBridge(text: text, amount: amount, accessibilityText: said)
    }

    /// ⑨ 頁尾：存摺上怎麼算＋外幣用哪個匯率（超過 3 天沒更新，最後那句琥珀色「匯率是 10/15 的」）
    static func footer(banks: [WealthFacts.Account], rates: FinanceRates, ratesUpdatedAt: Date?,
                       today: Date) -> FinanceLine {
        var runs: [FinanceRun] = [FinanceRun(text: footerBase)]
        // [v25.566] 有定存才說利息是預估、本息續存自動接下一期
        if banks.contains(where: { !$0.timeDeposits.isEmpty }) {
            runs.append(FinanceRun(text: depositNote))
        }
        var foreign: [String] = []
        for a in banks {
            for code in a.currencies where !FinanceRates.isNTD(code) && !foreign.contains(code) {
                foreign.append(code)
            }
        }
        let known = foreign.compactMap { code -> String? in
            guard let r = rates.known(code) else { return nil }
            return code + " " + WealthFormat.rate(r)
        }.prefix(2)
        guard !known.isEmpty else { return FinanceLine(runs: runs) }
        let list = known.joined(separator: "、")
        if let at = ratesUpdatedAt {
            let age = WealthCal.days(from: at, to: today)
            if age > 3 {
                runs.append(FinanceRun(text: "外幣用設定裡的匯率（" + list + "），"))
                runs.append(FinanceRun(text: "匯率是 " + md(at) + " 的。", bold: true, tone: .warn))
            } else {
                runs.append(FinanceRun(text: "外幣用設定裡的匯率（\(list)，\(md(at))）。"))
            }
        } else {
            runs.append(FinanceRun(text: "外幣用設定裡的匯率（" + list + "）。"))
        }
        return FinanceLine(runs: runs)
    }

    /// 頁尾前半（「這頁的數字怎麼算」也用；v3 不寫理財的淨資產，v4 才接）
    static let footerBase = "存摺上的數字：卡費在繳款截止日、股票交割在第 2 個營業日才扣，跟銀行 App 對得上。"
        + "記帳、股票、房子的扣款選單用的都是這個數。對不上時到帳戶裡按〔對存摺〕。"

    /// [v25.566] 頁尾：有定存才加的一句
    static let depositNote = "定存的利息是預估（單利、未扣稅），到期本息續存會自動接下一期。"

    /// [v25.566] 「這頁的數字怎麼算」：定存算在哪裡
    static let depositHow = "定存算進存款合計的「定存」那一格；到期轉活存的那天自動入帳。"

    /// [v25.566] 「這頁的數字怎麼算」：存款保險
    static let insuranceHow = "同一家銀行存摺上加定存超過 300 萬，要確認會提醒一次存款保險（同一家最多保 300 萬，一年內不再提）。"

    /// [v25.567] 「這頁的數字怎麼算」：保單一年合計（四個來源、一筆記帳保費只算一次；不進存款、不進淨資產）
    static let policyHow = "保單一年合計：財富的保單、儲蓄險、車險、房屋險合在一起，一筆記帳保費只算一次；保費不算進存款合計，也不算進淨資產。"

    /// [v25.567] 「這頁的數字怎麼算」：證券戶自己不記錢
    static let brokerHow = "證券戶的持股、買賣、股利讀理財 › 股票；交割記在交割銀行，證券戶自己不記錢。"

    /// ⋯「這頁的數字怎麼算」
    static let howItWorks: [String] = [
        footerBase,
        "扣完能用＝存摺上 − 還沒扣（卡費要繳＋還沒出帳＋還沒交割的股票款）。存款合計不含證券戶的持股，持股市值在理財 › 股票。",
        "自己繳的卡過了截止日沒標成已繳，App 當作從「通常從」的帳戶繳了全額，隔天會在「要確認」問你一次；選「每次問我」的卡不會當作已繳。",
        depositHow,
        insuranceHow,
        brokerHow,
        policyHow,
        "外幣照設定裡的匯率換台幣；查不到匯率的那一格不算進合計，大字前面會加「約」。",
        "繳款截止日、交割日遇到假日，銀行可能順延；App 不會自己順延。",
        "右上的眼睛可以把金額遮住（記在這台裝置）；關掉遮住要 Face ID。",
        webHow
    ]

    /// [v25.568] 「這頁的數字怎麼算」：桌面網頁版讀 App 算好的那一包（life_wealth_facts_v1，WealthWebFacts）
    static let webHow = "桌面網頁版的數字是這支 App 算好、跟著 iCloud 上去的（同一個數）；網頁版只露後 4 碼、沒有卡片到期日。"

    /// ⋯「iCloud 與家人共享說明」（judge §7.3；使用者第 6 題：安全碼照樣加密存；[v25.568] v7 起有效期限、保單號碼、票證號碼也加密）
    static let iCloudNote: [String] = [
        "家人接受共享後看得到所有帳戶名稱、存摺數字、帳號後 4 碼。"
            + "完整卡號、安全碼、完整帳號、有效期限、保單號碼、票證號碼是加密的："
            + "用同一個 Apple ID 的裝置解得開，用不同 Apple ID 的家人解不開、也存不了新的完整號碼（號碼請在你自己的裝置改）。",
        "看完整號碼要 Face ID，30 秒自動收回；App 切到背景時，財富的卡片頁和表單會先蓋住。",
        "小孩或家人的戶頭可以列著但不算進存款合計：到「⋯ › 排序與收起來」關掉「算進存款合計」。"
    ]
}
