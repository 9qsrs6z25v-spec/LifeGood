import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - 英雄卡樣式系統：全域預設 + 各卡覆寫
// ═══════════════════════════════════════════════════════════════════════════
//
// 【解析順序】三層，缺一層往下掉：
//   ① hs.p.<card>.<param>  單卡鍵存在 → 這張卡已覆寫
//   ② hs.g.<param>         全域鍵存在 → 全域已調整
//   ③ HeroNum.factory      Swift 常數，永不寫進 UserDefaults
//
// 【核心語意】「跟隨全域」＝ UserDefaults 裡沒有這把鍵。
//   覆寫 = set、取消覆寫 = removeObject、判斷狀態 = object(forKey:) != nil。
//   不用 −1 / NaN / 任何哨兵值，因為哨兵無法區分「跟隨」與「剛好調到跟全域一樣」。
//
// 【為什麼不用 @AppStorage】
//   ① 它無法表達「鍵不存在」——缺鍵直接頂預設值，三層解析當場失效；
//   ② 動態鍵要在每個 View 的 init 逐條綁定；
//   ③ card 一變就得重建整個 View。
//   改用單一 ObservableObject：鍵名字串組、狀態看鍵在不在、失效用 revision 帶動。
//
// ─────────────────────────────────────────────────────────────────────────
// 【十條紅線】改這個檔案前務必先讀完
// ─────────────────────────────────────────────────────────────────────────
//  1. 絕不對 hs.* 呼叫 UserDefaults.register(defaults:)——那會讓每把鍵都「存在」。
//  2. 重設一律 removeObject，不可用「寫回出廠值」實作，否則狀態永遠顯示已自訂。
//  3. 同一把鍵不可同時被 @AppStorage 與本 store 持有，不留半套。
//  4. set() 必須量化 + 值沒變就 return，否則每拖一格滑桿 = 一輪 CloudKit 推送。
//  5. 不用 UserDefaults.didChangeNotification 驅動 revision——各 Store 每次 save()
//     都在寫 UserDefaults，掛全域通知等於任何一次記帳都讓全 App 英雄卡重繪。
//  6. bump() 必須在主執行緒（revision 是 @Published）。
//  7. 一律 (object(forKey:) as? NSNumber)?.doubleValue，不用 as? Double
//     （JSON round-trip 後整數會變 NSNumber(int)，as? Double 會失敗）。
//  8. dictionaryRepresentation() 只在 rebuildIndex / removeAll 各呼叫一次，
//     永不進迴圈、永不進 body。
//  9. 不用 .id(store.revision) 強制重建 View（會炸掉 contentTransition 與進場動畫）。
// 10. store 只掛葉節點（殼層 modifier、KPI、大字、設定頁），
//     絕不掛 MainTabView 或各頁根 View。
//
// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Phase 0 現值對照表（重構前的回歸基準，2026/08 實測）
// ═══════════════════════════════════════════════════════════════════════════
//
// 這張表是整個重構的回歸基準：統一之後若某張卡「變醜」，靠它區分是收斂還是退化。
// 欄位＝散景三圓(直徑/不透明度) · 陰影(不透明度/半徑/Y) · 大字pt · KPI排法
//
// 【已接殼層（5 張，Phase 1 遷移）】
//   income          130/80/55 · .12/.07/.06 | .42/16/8  | 30 | 標籤在上
//   variableExpense 130/80/55 · .12/.07/.06 | .38/14/7  | 32 | 標籤在上
//   fixedExpense    130/80/55 · .12/.07/.06 | .42/16/8  | 32 | 標籤在上
//   stock           130/80/55 · .12/.07/.06 | .42/16/8  | 32 | 標籤在上
//   savings         130/75/55 · .13/.07/.05 | .42/16/8  | 32 | 標籤在上
//
// 【手刻殼層（Phase 3 遷移）】
//   overview        140/90/55 · .12/.07/.05 | .42/18/9  | 30 | 標籤在上
//   chart           140/90/55 · .12/.07/.05 | .42/18/9  | 32 | 標籤在上
//   vehicle         130/80/55 · .13/.07/.05 | .42/16/8  | 32 | 標籤在上
//   realEstate      130/80/55 · .13/.07/.05 | .42/16/8  | 32 | 標籤在上
//   financeOverview 兩圓(140/90) · .12/.07  | .42/18/9  | 34 | 標籤在上
//   financeChart    140/90/55 · .12/.07/.05 | .42/18/9  | 34 | 圖示在上(28pt)
//   lifeFinance     140/90/55 · .12/.07/.05 | .42/16/8  | 30 | 圖示在上(30pt)
//   lifeRealEstate  140/90/55 · .12/.07/.05 | .52/18/9 + black.08/8/4 | 40 | 圖示在上(32pt)
//   subordinateOvw  140/90/55 · .13/.07/.05 | .38/14/6 + black.10/4/2 | — | 圖示在上
//   travelMapStats  120/70/55 · .12/.07/.05 | .38/14/7  | 30 | 數值在上(14pt)
//   travelMapDetail 110/65/50 · .12/.07/.04 | .35/14/7  | 30 | 數值在上(裸排無容器)
//   foodMapStats    120/70/55 · .12/.07/.05 | .38/14/7  | 30 | 數值在上(14pt)
//   foodMapDetail   110/65/50 · .12/.07/.04 | .35/14/7  | 30 | 數值在上
//   businessCardList 130/75/55 · .12/.07/.06 | .42/16/8  | 30 | 標籤在上
//   businessCardDetail 兩圓(140/90) · .12/.07 | .38/18/9 + black.10/4/2 | — | 裸排
//                   （明細卡圓角 18 非 20、漸層是橘→粉→紫三色，遷移時要留意）
//   spouseResume    140/90/55 · .12/.07/.05 | .42/16/8  | 30 | 數值在上(12pt)
//   gradeTitle      160/90/60 · .12/.07/紫  | indigo.28/16/8 + black.06/4/2 | — | 數值在上(title3)
//   settings        140/90/55 · .12/.07/.05 | .42/16/8  | 28 | 標籤在上
//   eInvoice        散景兩圓             | —            | — | 圖示在上(28pt)
//
// 【KPI 豎分隔線高度現況】28(標準) / 32(foodMap) / 36(lifeFinance,lifeRealEstate,eInvoice) / 48(subordinateOvw)
// 【KPI 容器現況】白.08+圓角10+內距10(標準) / 白.10+內距8(addStock) / 有描邊(lifeFinance) / 裸排(travelMapDetail)
//
// ─────────────────────────────────────────────────────────────────────────
// 【Phase 3a 遷移狀態】19 張已接殼層 / 5 張待處理
// ─────────────────────────────────────────────────────────────────────────
// 已遷移（v25.209 五張 + v25.210 十四張）：income variableExpense fixedExpense
//   stock savings overview chart vehicle realEstate financeOverview financeChart
//   lifeFinance lifeRealEstate subordinateList talentMatrix spouseResume
//   calendar travelMapStats travelMapDetail foodMapStats foodMapDetail
//
// 尚未遷移（結構不同，需各自改寫版面才能接殼層，不硬套以免退化）：
//   · businessCardDetail   圓角 18 非 20、無光澤層、雙層陰影，與列表卡是兩張
//                          不同規格的卡（拆成兩個身分的原因）
//   · settings             漸層依訂閱狀態動態切換（付費綠／未付費紫），
//                          殼層目前只吃靜態卡片身分，需先想清楚動態色怎麼表達
//   · eInvoice             圓角非 20、僅兩顆散景圓，版面結構與其餘不同型
//
// ─────────────────────────────────────────────────────────────────────────
// 【Phase 3c 遷移狀態】ZStack 型卡片改接殼層（v25.213）
// ─────────────────────────────────────────────────────────────────────────
// subordinateOverview / gradeTitle / businessCardList 三張遷移完成，
// 共 22 張走同一套殼層。三張原本都是「ZStack 疊背景層 + 內容 + 光澤覆層」，
// 改寫成「內容 .padding() .heroCardShell(card:)」——內容不動，只是背景層
// 從手刻改成殼層供應。已知收斂：
//   · subordinateOverview 散景圓 140/90/55 → 130/80/55、偏移量改用殼層標準
//     （原本是 topLeading 對齊的絕對座標 x:200，殼層是置中相對偏移）；
//     陰影 .38/14/6 + black.10/4/2 → .42/16/8 單層；KPI 分隔線 48 → 28。
//   · gradeTitle 第二顆紫色散景圓收斂成白（要救回用單卡「散景圓顏色」覆寫）；
//     散景圓 160/90/60 → 130/80/55、模糊 30/22/14 → 14/10/8（原本糊很多）；
//     陰影 indigo.28/16/8 + black.06/4/2 → 出廠 .42/16/8 單層；
//     出廠漸層更正為實測的 indigo → purple.85（原本表裡填的是估計值）。
//     KPI 的「值 + 單位」雙段基線對齊收斂成單段（「3」「個」→「3 個」），
//     並補上圖示（部門／職等／關聯鏈）讓「圖示在上」排法有東西可顯示。
//   · businessCardList 散景圓 130/75/55 → 130/80/55；大字 30 → 全域 32。
//
// ─────────────────────────────────────────────────────────────────────────
// 【Phase 3b 遷移狀態】KPI 橫列與主數值大字（v25.211）
// ─────────────────────────────────────────────────────────────────────────
// · 大字：18 個寫死字級（30／32／34／40pt）→ .heroBigValueFont()，全部收斂到
//   全域出廠 32pt。收斂幅度最大的兩張是 lifeRealEstate（40→32）與
//   subordinateList（28→32）；兩張原本的字級是「內容驅動」（一個是筆數、
//   一個是「N 位部屬」），要救回請用單卡覆寫。
// · 豎分隔線：58 處寫死高度（28／30／32／34／36）→ HeroKpiDivider()，
//   高度改由「排法基準高 × 全域倍率」推導（標籤在上 28／數值在上 32／
//   圖示在上 36）。預設排法是標籤在上，所以原本 32～36 的卡片會縮到 28。
// · KPI 小格：13 支各頁自刻的 kpiCell／heroKpiCell／summaryKpi 全數收掉，
//   一律走 HeroKpiCell。原本各自不同的 12～17pt 數值、9～11pt 標籤、
//   28～32pt 圖示圓，收斂成三層解析的 kpiValueSize／kpiLabelSize／kpiIconSize。
//   為了不讓收斂變成退化，HeroKpiCell 同步補了兩件事：
//     ① 圖示圓改成漸層 + 0.75pt 描邊（採用原本多數卡片的規格，而非扁平圓）
//     ② 新增 valueColor，保住「這一格語意上就該有顏色」的欄位
//        （talentMatrix 四象限色、lifeRealEstate 三態色、AddVehicle 折舊金色）
// · 沿用 .legacy 身分（吃全域、不吃單卡覆寫）：AddVehicleView 預覽卡、
//   MedicalMapView、ChildrenResumeView、SubordinateDetailView。這四張的殼層
//   本來就沒遷移，等它們進 HeroCard 列舉後 KPI 會自動跟著吃單卡層。
// · 未動：GradeTitleView（kpiCell 帶 unit 第三段）、SubordinateOverviewView／
//   ResumeView／FamilyMembersResumeView（與其殼層同批待處理）。
//
// ═══════════════════════════════════════════════════════════════════════════

// MARK: - 卡片身分

/// 英雄卡的識別單位是「卡」不是「頁」——旅遊地圖／美食地圖同一頁各有
/// 統計卡與詳情卡兩張，尺寸本來就該不同（大卡 vs 窄卡），用頁當鍵會把兩張
/// 壓成同一組尺寸且事後無法各自救回。
///
/// ⚠️ rawValue 直接組成 UserDefaults 鍵名並進 iCloud 同步，**上線後不可更改**。
enum HeroCard: String, CaseIterable, Identifiable {
    /// 尚未帶身分的舊呼叫點：只吃全域層，不吃單卡覆寫（遷移期的安全網）
    case legacy

    // 記帳
    case income, variableExpense, fixedExpense, overview, chart
    // 理財
    case stock, savings, vehicle, realEstate, financeOverview, financeChart
    // 人生
    case lifeFinance, lifeRealEstate, subordinateOverview, subordinateList
    case talentMatrix, calendar, businessCardList, businessCardDetail
    case gradeTitle, spouseResume
    case travelMapStats, travelMapDetail, foodMapStats, foodMapDetail
    // 系統
    case settings, eInvoice

    var id: String { rawValue }

    enum Family: String, CaseIterable, Identifiable {
        case expense = "記帳", finance = "理財", life = "人生", system = "系統"
        var id: String { rawValue }
    }

    var family: Family {
        switch self {
        case .income, .variableExpense, .fixedExpense, .overview, .chart: return .expense
        case .stock, .savings, .vehicle, .realEstate, .financeOverview, .financeChart: return .finance
        case .settings, .eInvoice, .legacy: return .system
        default: return .life
        }
    }

    /// 這張卡的殼層是否已接上樣式系統。
    /// false = 還在手刻背景，單卡覆寫調了也不會有反應——設定頁必須標示出來，
    /// 否則使用者會以為是壞掉。清單隨 Phase 3c／4 遷移逐張縮短，全部清空後
    /// 這個屬性連同設定頁的標示一起刪掉。
    var isWired: Bool {
        switch self {
        case .businessCardDetail, .settings, .eInvoice:
            return false
        default:
            return true
        }
    }

    /// 設定頁顯示的中文卡名
    var title: String {
        switch self {
        case .legacy:              return "未指定"
        case .income:              return "收入"
        case .variableExpense:     return "變動支出"
        case .fixedExpense:        return "固定支出"
        case .overview:            return "收支總覽"
        case .chart:               return "收支圖表"
        case .stock:               return "股票"
        case .savings:             return "儲蓄險"
        case .vehicle:             return "汽車"
        case .realEstate:          return "房地產"
        case .financeOverview:     return "理財總覽"
        case .financeChart:        return "理財圖表"
        case .lifeFinance:         return "人生財務"
        case .lifeRealEstate:      return "人生房地產"
        case .subordinateOverview: return "部屬總覽"
        case .subordinateList:     return "部屬列表"
        case .talentMatrix:        return "人才矩陣"
        case .calendar:            return "我的行事曆"
        case .businessCardList:    return "名片列表"
        case .businessCardDetail:  return "名片明細"
        case .gradeTitle:          return "職等職稱"
        case .spouseResume:        return "另一半履歷"
        case .travelMapStats:      return "旅遊地圖 › 統計卡"
        case .travelMapDetail:     return "旅遊地圖 › 詳情卡"
        case .foodMapStats:        return "美食地圖 › 統計卡"
        case .foodMapDetail:       return "美食地圖 › 詳情卡"
        case .settings:            return "設定"
        case .eInvoice:            return "電子發票"
        }
    }

    /// 出廠漸層（起點色、終點色）。
    /// 這是本次重構的第二個大收斂：41 處硬寫在呼叫端的顏色收進單一登錄表——
    /// 即使永遠不做覆寫也該做，因為設定頁的即時預覽要跑「真的那張卡的顏色」。
    var factoryGradient: [Color] {
        switch self {
        case .income, .overview, .chart, .settings, .legacy:
            return [Color(red: 0.16, green: 0.74, blue: 0.50),
                    Color(red: 0.07, green: 0.50, blue: 0.38)]
        case .variableExpense, .stock:
            return [Color(red: 1.00, green: 0.62, blue: 0.22),
                    Color(red: 0.86, green: 0.36, blue: 0.06)]
        case .foodMapStats, .foodMapDetail:
            return [Color(red: 1.00, green: 0.55, blue: 0.18),
                    Color(red: 0.85, green: 0.32, blue: 0.05)]
        case .fixedExpense, .savings, .lifeFinance, .subordinateList:
            return [Color(red: 0.22, green: 0.53, blue: 0.98),
                    Color(red: 0.10, green: 0.35, blue: 0.82)]
        case .vehicle:
            return [Color(red: 0.18, green: 0.68, blue: 0.68),
                    Color(red: 0.08, green: 0.46, blue: 0.48)]
        case .realEstate:
            return [Color(red: 0.48, green: 0.25, blue: 0.80),
                    Color(red: 0.25, green: 0.15, blue: 0.60)]
        case .financeOverview:
            return [Color(red: 0.14, green: 0.64, blue: 0.60),
                    Color(red: 0.07, green: 0.46, blue: 0.42)]
        case .financeChart:
            return [Color(red: 0.44, green: 0.30, blue: 0.88),
                    Color(red: 0.28, green: 0.16, blue: 0.68)]
        case .lifeRealEstate:
            return [Color(red: 0.50, green: 0.30, blue: 0.90),
                    Color(red: 0.32, green: 0.14, blue: 0.72)]
        case .subordinateOverview:
            return [Color(red: 0.17, green: 0.54, blue: 0.90),
                    Color(red: 0.05, green: 0.78, blue: 0.72)]
        case .calendar:
            return [Color(red: 0.28, green: 0.48, blue: 0.90),
                    Color(red: 0.16, green: 0.30, blue: 0.72)]
        case .talentMatrix:
            return [Color(red: 0.30, green: 0.25, blue: 0.90),
                    Color(red: 0.18, green: 0.40, blue: 0.92)]
        case .businessCardList:
            // BusinessCardView:490 accentTop / accentBot
            return [Color(red: 1.00, green: 0.58, blue: 0.28),
                    Color(red: 0.90, green: 0.28, blue: 0.55)]
        case .businessCardDetail:
            // BusinessCardDetailView.heroCard：橘 → 粉 .85 → 紫 .70 三色
            return [.orange, .pink.opacity(0.85), .purple.opacity(0.70)]
        case .gradeTitle:
            // GradeTitleView.heroCard 實測：系統 indigo → purple.85
            return [.indigo, .purple.opacity(0.85)]
        case .spouseResume:
            // Self.heroAccent / heroAccentDark（SpouseResumeView:167）
            return [Color(red: 0.96, green: 0.35, blue: 0.58),
                    Color(red: 0.76, green: 0.18, blue: 0.40)]
        case .travelMapStats, .travelMapDetail:
            return [Color(red: 0.62, green: 0.36, blue: 1.00),
                    Color(red: 0.42, green: 0.16, blue: 0.82)]
        case .eInvoice:
            return [Color(red: 0.38, green: 0.42, blue: 0.92),
                    Color(red: 0.22, green: 0.24, blue: 0.72)]
        }
    }
}

// MARK: - 參數目錄

enum HeroKpiLayout: Int, CaseIterable, Identifiable {
    case labelTop = 0, valueTop, iconTop
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .labelTop: return "標籤在上"
        case .valueTop: return "數值在上"
        case .iconTop:  return "圖示在上"
        }
    }
    /// 豎分隔線的基準高度由排法推導——不開自由滑桿，否則等於把 28/32/36/48 重新合法化
    var dividerBase: CGFloat {
        switch self {
        case .labelTop: return 28
        case .valueTop: return 32
        case .iconTop:  return 36
        }
    }
}

enum HeroKpiChrome: Int, CaseIterable, Identifiable {
    case bare = 0, plate, plateStroked
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .bare:         return "無容器"
        case .plate:        return "淡底"
        case .plateStroked: return "淡底＋描邊"
        }
    }
}

/// 數值型參數（列舉也存 rawValue 的 Double，儲存層只有一種型別）
enum HeroNum: String, CaseIterable, Identifiable {
    // 殼層
    case corner, bokehScale, bokehSize, shine, shadowScale, shadowRadius
    // KPI
    case kpiLayout, kpiValueSize, kpiLabelSize, kpiIconSize, kpiDividerScale, kpiChrome
    // 大字
    case bigValueSize

    var id: String { rawValue }

    /// 出廠值。⚠️ 只能活在這裡，絕不可 register(defaults:)
    var factory: Double {
        switch self {
        case .corner:          return 20
        case .bokehScale:      return 1.0
        case .bokehSize:       return 1.0
        case .shine:           return 0.18
        case .shadowScale:     return 1.0
        case .shadowRadius:    return 16
        case .kpiLayout:       return Double(HeroKpiLayout.labelTop.rawValue)
        case .kpiValueSize:    return 12
        case .kpiLabelSize:    return 9
        case .kpiIconSize:     return 30
        case .kpiDividerScale: return 1.0
        case .kpiChrome:       return Double(HeroKpiChrome.plate.rawValue)
        case .bigValueSize:    return 32
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .corner:          return 12...28
        case .bokehScale:      return 0...2
        case .bokehSize:       return 0.6...1.4
        case .shine:           return 0...0.40
        case .shadowScale:     return 0...2
        case .shadowRadius:    return 8...24
        case .kpiLayout:       return 0...2
        case .kpiValueSize:    return 10...22
        case .kpiLabelSize:    return 8...13
        case .kpiIconSize:     return 22...36
        case .kpiDividerScale: return 0.8...1.4
        case .kpiChrome:       return 0...2
        case .bigValueSize:    return 24...44
        }
    }

    var step: Double {
        switch self {
        case .shine:                          return 0.02
        case .bokehScale, .shadowScale:       return 0.1
        case .bokehSize, .kpiDividerScale:    return 0.05
        case .kpiIconSize:                    return 2
        default:                              return 1
        }
    }

    var title: String {
        switch self {
        case .corner:          return "卡片圓角"
        case .bokehScale:      return "散景亮度"
        case .bokehSize:       return "散景圓尺寸"
        case .shine:           return "玻璃光澤"
        case .shadowScale:     return "陰影強度"
        case .shadowRadius:    return "陰影半徑"
        case .kpiLayout:       return "KPI 排法"
        case .kpiValueSize:    return "KPI 數值字級"
        case .kpiLabelSize:    return "KPI 標籤字級"
        case .kpiIconSize:     return "KPI 圖示圓直徑"
        case .kpiDividerScale: return "KPI 分隔線高度"
        case .kpiChrome:       return "KPI 容器樣式"
        case .bigValueSize:    return "大字字級"
        }
    }

    /// 是否支援單卡覆寫（使用者拍板：顏色／KPI 排法／大字字級要能各卡獨立）
    var supportsPerCard: Bool {
        switch self {
        case .kpiLayout, .kpiValueSize, .kpiChrome, .bigValueSize: return true
        default: return false
        }
    }

    var isEnumLike: Bool { self == .kpiLayout || self == .kpiChrome }

    func display(_ v: Double) -> String {
        switch self {
        case .shine:
            return "\(Int((v * 100).rounded()))%"
        case .bokehScale, .bokehSize, .shadowScale, .kpiDividerScale:
            return v == v.rounded() ? "\(Int(v)) 倍" : String(format: "%.2g 倍", v)
        case .kpiLayout:
            return (HeroKpiLayout(rawValue: Int(v)) ?? .labelTop).title
        case .kpiChrome:
            return (HeroKpiChrome(rawValue: Int(v)) ?? .plate).title
        default:
            return "\(Int(v.rounded())) pt"
        }
    }

    enum Bucket: String, CaseIterable, Identifiable {
        case shell = "殼層", kpi = "KPI 橫列", big = "大字"
        var id: String { rawValue }
    }

    var bucket: Bucket {
        switch self {
        case .corner, .bokehScale, .bokehSize, .shine, .shadowScale, .shadowRadius:
            return .shell
        case .kpiLayout, .kpiValueSize, .kpiLabelSize, .kpiIconSize, .kpiDividerScale, .kpiChrome:
            return .kpi
        case .bigValueSize:
            return .big
        }
    }
}

/// 顏色型參數
enum HeroTint: String, CaseIterable, Identifiable {
    case gradA, gradB, bokeh, shadow
    var id: String { rawValue }

    /// 漸層兩色沒有全域層（每張卡本來就該不同色）；散景／陰影有
    var hasGlobalLevel: Bool { self == .bokeh || self == .shadow }

    var title: String {
        switch self {
        case .gradA:  return "漸層起點色"
        case .gradB:  return "漸層終點色"
        case .bokeh:  return "散景圓顏色"
        case .shadow: return "陰影顏色"
        }
    }
}

// MARK: - 鍵名（永久契約）

enum HeroKey {
    static let namespace = "hs."
    static let globalPrefix = "hs.g."
    static let allCardsPrefix = "hs.p."
    static func g(_ p: String) -> String { globalPrefix + p }
    static func p(_ card: HeroCard, _ p: String) -> String { "hs.p.\(card.rawValue).\(p)" }
    static func cardPrefix(_ card: HeroCard) -> String { "hs.p.\(card.rawValue)." }
}

// MARK: - 解析器

final class HeroStyleStore: ObservableObject {
    static let shared = HeroStyleStore()

    /// 任何寫入都 +1；葉節點靠它重繪。不要用 .id(revision) 強制重建 View。
    @Published private(set) var revision: Int = 0

    private let d = UserDefaults.standard
    private var cache: [HeroCard: HeroStyle] = [:]
    /// 覆寫鍵索引：避免每次重繪都掃 dictionaryRepresentation（清單頁 25 列會卡頓）
    private var overrideKeys: Set<String> = []

    private init() { rebuildIndex() }

    // ── 讀 ──

    func value(_ p: HeroNum, _ card: HeroCard) -> Double {
        if card != .legacy, p.supportsPerCard,
           let n = d.object(forKey: HeroKey.p(card, p.rawValue)) as? NSNumber {
            return n.doubleValue
        }
        return globalValue(p)
    }

    func globalValue(_ p: HeroNum) -> Double {
        (d.object(forKey: HeroKey.g(p.rawValue)) as? NSNumber)?.doubleValue ?? p.factory
    }

    func cardColor(_ t: HeroTint, _ card: HeroCard) -> Color? {
        guard card != .legacy,
              let s = d.string(forKey: HeroKey.p(card, t.rawValue)) else { return nil }
        return Color(heroHex: s)
    }

    func globalColor(_ t: HeroTint) -> Color? {
        guard t.hasGlobalLevel, let s = d.string(forKey: HeroKey.g(t.rawValue)) else { return nil }
        return Color(heroHex: s)
    }

    // ── 狀態（純粹看鍵在不在）──

    func isOverridden(_ p: HeroNum, _ card: HeroCard) -> Bool {
        card != .legacy && overrideKeys.contains(HeroKey.p(card, p.rawValue))
    }
    func isOverridden(_ t: HeroTint, _ card: HeroCard) -> Bool {
        card != .legacy && overrideKeys.contains(HeroKey.p(card, t.rawValue))
    }
    func isGlobalCustomized(_ p: HeroNum) -> Bool {
        d.object(forKey: HeroKey.g(p.rawValue)) != nil
    }
    /// 這張卡覆寫了幾項（讀索引，不掃全網域）
    func overrideCount(_ card: HeroCard) -> Int {
        guard card != .legacy else { return 0 }
        let pre = HeroKey.cardPrefix(card)
        return overrideKeys.reduce(0) { $0 + ($1.hasPrefix(pre) ? 1 : 0) }
    }
    /// 有幾張卡覆寫了這一項（給全域頁的「N 張卡自訂此項 · 一併套用」）
    func cardsOverriding(_ p: HeroNum) -> [HeroCard] {
        HeroCard.allCases.filter { $0 != .legacy && overrideKeys.contains(HeroKey.p($0, p.rawValue)) }
    }

    // ── 寫（card == nil ＝寫全域層）──

    func set(_ p: HeroNum, _ v: Double, card: HeroCard? = nil) {
        let key = card.map { HeroKey.p($0, p.rawValue) } ?? HeroKey.g(p.rawValue)
        let q = quantize(v, step: p.step, in: p.range)
        // 值沒變就不寫：否則每拖一格滑桿都是一輪 CloudKit 推送
        if let old = (d.object(forKey: key) as? NSNumber)?.doubleValue, abs(old - q) < 1e-9 { return }
        d.set(q, forKey: key)
        if card != nil { overrideKeys.insert(key) }
        bump()
    }

    func setColor(_ t: HeroTint, _ c: Color, card: HeroCard? = nil) {
        let key = card.map { HeroKey.p($0, t.rawValue) } ?? HeroKey.g(t.rawValue)
        guard let hex = c.heroHex else { return }
        if d.string(forKey: key) == hex { return }
        d.set(hex, forKey: key)
        if card != nil { overrideKeys.insert(key) }
        bump()
    }

    func clear(_ p: HeroNum, card: HeroCard) {
        clearKey(HeroKey.p(card, p.rawValue))
    }
    func clear(_ t: HeroTint, card: HeroCard) {
        clearKey(HeroKey.p(card, t.rawValue))
    }
    func clearGlobal(_ p: HeroNum) { clearKey(HeroKey.g(p.rawValue)) }
    func clearGlobal(_ t: HeroTint) { clearKey(HeroKey.g(t.rawValue)) }

    private func clearKey(_ k: String) {
        guard d.object(forKey: k) != nil else { return }
        d.removeObject(forKey: k)
        overrideKeys.remove(k)
        bump()
    }

    /// 全域頁的「一併套用」：清掉所有卡對這一項的覆寫
    func clearOverridesEverywhere(_ p: HeroNum) {
        for c in cardsOverriding(p) { clear(p, card: c) }
    }

    // ── 重設：全部是 removeObject，不寫任何值 ──

    func resetCard(_ c: HeroCard) { removeAll(prefix: HeroKey.cardPrefix(c)) }
    func resetGlobal() { removeAll(prefix: HeroKey.globalPrefix) }
    func resetAllCards() { removeAll(prefix: HeroKey.allCardsPrefix) }
    /// 同步「以雲端覆蓋本機」時用：整個命名空間清空
    func resetNamespace() { removeAll(prefix: HeroKey.namespace) }

    private func removeAll(prefix: String) {
        let all = d.dictionaryRepresentation()   // 只取一次到區域變數再跑迴圈
        var removed = false
        for k in all.keys where k.hasPrefix(prefix) {
            d.removeObject(forKey: k)
            overrideKeys.remove(k)
            removed = true
        }
        if removed { bump() }
    }

    /// iCloud 拉取後呼叫：重建索引並讓所有葉節點重繪
    func invalidate() {
        if Thread.isMainThread { rebuildIndex(); bump() }
        else { DispatchQueue.main.async { self.rebuildIndex(); self.bump() } }
    }

    private func bump() {
        cache.removeAll()
        if Thread.isMainThread { revision &+= 1 }
        else { DispatchQueue.main.async { self.revision &+= 1 } }
    }

    private func rebuildIndex() {
        overrideKeys = Set(d.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(HeroKey.allCardsPrefix) })
    }

    private func quantize(_ v: Double, step: Double, in r: ClosedRange<Double>) -> Double {
        let clamped = min(max(v, r.lowerBound), r.upperBound)
        guard step > 0 else { return (clamped * 10_000).rounded() / 10_000 }
        return ((clamped / step).rounded() * step * 10_000).rounded() / 10_000
    }

    // ── 一張卡一次解析完 ──

    func style(for card: HeroCard) -> HeroStyle {
        if let hit = cache[card] { return hit }
        let layout = HeroKpiLayout(rawValue: Int(value(.kpiLayout, card))) ?? .labelTop
        let gradient = [cardColor(.gradA, card) ?? card.factoryGradient[0],
                        cardColor(.gradB, card) ?? card.factoryGradient[1]]
        let s = HeroStyle(
            corner: CGFloat(value(.corner, card)),
            bokehScale: value(.bokehScale, card),
            bokehSize: value(.bokehSize, card),
            shine: value(.shine, card),
            shadowScale: value(.shadowScale, card),
            shadowRadius: CGFloat(value(.shadowRadius, card)),
            kpiLayout: layout,
            kpiChrome: HeroKpiChrome(rawValue: Int(value(.kpiChrome, card))) ?? .plate,
            kpiValueSize: CGFloat(value(.kpiValueSize, card)),
            kpiLabelSize: CGFloat(value(.kpiLabelSize, card)),
            kpiIconSize: CGFloat(value(.kpiIconSize, card)),
            kpiDividerHeight: layout.dividerBase * CGFloat(value(.kpiDividerScale, card)),
            bigValueSize: CGFloat(value(.bigValueSize, card)),
            gradient: gradient,
            bokehTint: cardColor(.bokeh, card) ?? globalColor(.bokeh) ?? .white,
            // ⚠️ fallback 是「解析後的 gradB」而非出廠色，才維持現行
            //    shadowTint ?? colors.last 的「陰影跟著當下顏色」行為
            shadowTint: cardColor(.shadow, card) ?? globalColor(.shadow) ?? gradient[1])
        cache[card] = s
        return s
    }
}

// MARK: - 解析結果

struct HeroStyle {
    let corner: CGFloat
    let bokehScale: Double
    let bokehSize: Double
    let shine: Double
    let shadowScale: Double
    let shadowRadius: CGFloat
    let kpiLayout: HeroKpiLayout
    let kpiChrome: HeroKpiChrome
    let kpiValueSize: CGFloat
    let kpiLabelSize: CGFloat
    let kpiIconSize: CGFloat
    let kpiDividerHeight: CGFloat
    let bigValueSize: CGFloat
    let gradient: [Color]
    let bokehTint: Color
    let shadowTint: Color

    /// 次要數值字級由大字等比推導，不另開滑桿——
    /// 保證 40pt 大字不會配上固定 20pt 的副值
    var secondaryValueSize: CGFloat { bigValueSize * 0.62 }
}

// MARK: - 環境（卡片身分自動往下傳）

private struct HeroCardEnvKey: EnvironmentKey {
    static let defaultValue: HeroCard = .legacy
}

extension EnvironmentValues {
    var heroCard: HeroCard {
        get { self[HeroCardEnvKey.self] }
        set { self[HeroCardEnvKey.self] = newValue }
    }
}

// MARK: - 顏色 hex 編解碼（儲存層只認 String）

extension Color {
    init?(heroHex: String) {
        var s = heroHex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    var heroHex: String? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let clamp = { (v: CGFloat) -> Int in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
        #else
        return nil
        #endif
    }
}
