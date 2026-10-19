import SwiftUI

// MARK: - 財富的卡片頁（v25.564，財富 v3；wealth/judge.md §4.0–4.4）
//
// 一個入口 WealthCardPage(accountId:scrollTo:)：照那筆里程碑的子分類畫信用卡頁（§4.1）、銀行帳戶頁（§4.2）、
// 證券戶頁（§4.3 基本版）、保單頁（§4.4 基本版）。從財富頁項目卡、接下來 30 天、履歷、我的行事曆、要確認打開
// （呼叫端一律 .sheet(item:) { WealthCardPage(accountId: …).appStores() }）。
// 骨架照股票、房屋、車子的卡片頁（U3 §4.3）：ScrollViewReader > ScrollView > VStack(spacing: 22)；⓪ FinanceSwitcherStrip；
// 工具列 左「關閉」、中 MarqueeText、右綠〔＋〕＋綠字「編輯」（沒有分享、刪除在編輯頁最下面）；一個 enum WealthCardSheet＋
// 一個 .sheet(item:)＋.appStores()；資料 WealthCardData.build 在 .task(id:) 算一次；整頁掛 WealthPrivacyCurtain(armed: true)，
// 切到背景號碼收回。每區一個小 struct（坑 #7）。
//
// 分工：G2 實作（這個檔＋Models/WealthCardData.swift）。主控只放能編譯的入口，簽章不要改（G1、G3 在叫）。

/// 打開卡片頁時捲到哪一區（財富頁 ③ 點一列＝.upcoming；要確認、四格點了也用）
enum WealthCardAnchor: String, Hashable {
    case top, checks
    // 信用卡
    case statement, unbilled, recurring, history, fee, cardInfo, photos
    // 銀行
    case upcoming, linked, foreign, ledger, accountInfo, note
    // 證券戶、保單
    case holdings, payment
}

/// 財富的卡片頁（入口；G2 換成真的，簽章不改）
struct WealthCardPage: View {
    let accountId: UUID
    var scrollTo: WealthCardAnchor? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("財富卡片")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                }
        }
        .modifier(WealthPrivacyCurtain(armed: true))
    }
}
