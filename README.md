# LifeGood 記帳

> 打造完美人生，從記帳開始。

LifeGood 是一款專為台灣使用者設計的 iOS 記帳 App，幫助您輕鬆管理每日變動支出與每月固定開支。直覺的操作介面搭配強大的圖表分析，讓您一眼掌握金錢的流向。

## 功能特色

### 總覽儀表板

一頁掌握您的財務全貌：本月總支出、今日花費、變動與固定支出比例，以及最近交易紀錄。

### 變動支出管理

支援 9 大分類（飲食、交通、娛樂、購物、日用品、醫療、教育、社交、其他），可依分類快速篩選，依日期自動分組，隨時新增、編輯或刪除。

### 固定支出管理

支援 8 大分類（房租、水電瓦斯、保險、訂閱服務、貸款、電信費、管理費、其他），設定每月、每季或每年的週期，系統自動換算並投射到每個月。

### 趨勢圖表分析

五種時間維度一鍵切換：

| 維度 | 範圍 |
|------|------|
| 日總結 | 近 30 天每日花費趨勢 |
| 週總結 | 近 12 週支出變化 |
| 月總結 | 近 12 個月花費走勢 |
| 季總結 | 近 8 季支出概覽 |
| 年總結 | 近 5 年年度趨勢 |

互動式長條圖搭配折線圖，支援觸控查看詳細金額。

## 技術規格

| 項目 | 說明 |
|------|------|
| 平台 | iOS 17.0+ |
| 框架 | SwiftUI, Swift Charts |
| 語言 | Swift 5 |
| 資料儲存 | UserDefaults (本機) |
| 網路需求 | 無 (完全離線) |
| 最低版本 | 1.2 (Build 3) |

## 專案結構

```
LifeGood/
├── LifeGood.xcodeproj/
├── LifeGood/
│   ├── LifeGoodApp.swift              # App 進入點
│   ├── Models/
│   │   ├── Expense.swift              # 資料模型、分類、列舉
│   │   └── ExpenseStore.swift         # 資料管理、統計計算、持久化
│   ├── Views/
│   │   ├── MainTabView.swift          # 底部 Tab 導覽 (4 頁)
│   │   ├── OverviewView.swift         # 總覽頁面
│   │   ├── VariableExpenseView.swift  # 變動支出頁面
│   │   ├── FixedExpenseView.swift     # 固定支出頁面
│   │   ├── AddExpenseView.swift       # 新增／編輯支出表單
│   │   └── ChartView.swift           # 圖表分析頁面
│   ├── Assets.xcassets/               # App Icon 與色彩資源
│   └── Preview Content/               # SwiftUI 預覽資源
├── AppStoreConnect.md                 # App Store Connect 上架文字
└── README.md
```

## 安裝與執行

1. Clone 此專案
2. 使用 Xcode 15+ 開啟 `LifeGood.xcodeproj`
3. 選擇 iOS Simulator 或實機
4. Build & Run (Cmd + R)

> 無需安裝任何第三方套件，所有功能皆使用 Apple 原生框架。

---

## App Store Connect 上架資訊

以下為 App Store Connect 提交審核所需的所有欄位內容。

### 基本資訊

| 欄位 | 繁體中文 | English |
|------|---------|---------|
| App 名稱 (30字內) | LifeGood 記帳 | LifeGood Expense |
| 副標題 (30字內) | 輕鬆掌握每一筆開支 | Track Every Expense Easily |
| 套件名稱 (Bundle ID) | com.lifegood.app | com.lifegood.app |
| 版本 | 1.2 | 1.2 |

### 類別

| 欄位 | 選擇 |
|------|------|
| 主要類別 | 財經 (Finance) |
| 次要類別 | 工具程式 (Utilities) |

### 描述 (Description)

**繁體中文**

> LifeGood — 打造完美人生，從記帳開始。
>
> LifeGood 是一款專為台灣使用者設計的記帳 App，幫助您輕鬆管理每日變動支出與每月固定開支。直覺的操作介面搭配強大的圖表分析，讓您一眼掌握金錢的流向。
>
> 【四大核心功能】
>
> ◆ 總覽儀表板
> 一頁掌握您的財務全貌：本月總支出、今日花費、變動與固定支出比例，以及最近交易紀錄。不需繁複操作，打開 App 即刻了解財務現況。
>
> ◆ 變動支出管理
> 支援 9 大分類：飲食、交通、娛樂、購物、日用品、醫療、教育、社交、其他。可依分類快速篩選，依日期自動分組，隨時新增、編輯或刪除支出紀錄。
>
> ◆ 固定支出管理
> 支援 8 大分類：房租、水電瓦斯、保險、訂閱服務、貸款、電信費、管理費、其他。設定每月、每季或每年的週期，系統自動換算並投射到每個月，不會漏算任何固定開支。
>
> ◆ 趨勢圖表分析
> 五種時間維度一鍵切換：日總結（近30天）、週總結（近12週）、月總結（近12個月）、季總結（近8季）、年總結（近5年）。互動式長條圖搭配折線圖，支援觸控查看詳細金額。提供總計、平均、最高三大關鍵數據，以及變動與固定支出的比例分析。
>
> 【為什麼選擇 LifeGood？】
>
> ✓ 完全免費 — 所有功能免費使用，無內購、無廣告
> ✓ 隱私至上 — 所有資料僅儲存於您的裝置，不上傳任何伺服器
> ✓ 台灣在地化 — 全繁體中文介面，新台幣 NT$ 顯示
> ✓ 操作直覺 — 簡潔現代的設計，3 秒即可完成一筆記帳
> ✓ 離線使用 — 無需網路，隨時隨地記錄開支
>
> 開始使用 LifeGood，讓每一筆錢花得更有價值。

**English**

> LifeGood — Build a better life, starting with your finances.
>
> LifeGood is an intuitive expense tracker designed to help you effortlessly manage both variable and fixed expenses. With a clean dashboard and powerful chart analytics, you can see exactly where your money goes.
>
> 【Four Core Features】
>
> ◆ Overview Dashboard
> Get the full picture at a glance: monthly total, today's spending, variable vs. fixed expense breakdown, and recent transactions — all on one page.
>
> ◆ Variable Expense Tracking
> 9 categories: Food, Transportation, Entertainment, Shopping, Daily Necessities, Medical, Education, Social, Other. Filter by category, auto-grouped by date, with full add/edit/delete support.
>
> ◆ Fixed Expense Management
> 8 categories: Rent, Utilities, Insurance, Subscriptions, Loans, Telecom, Management Fees, Other. Set monthly, quarterly, or yearly recurrence — the app automatically projects costs into every period.
>
> ◆ Trend Chart Analytics
> Switch between 5 time dimensions: Daily (30 days), Weekly (12 weeks), Monthly (12 months), Quarterly (8 quarters), Yearly (5 years). Interactive bar + line charts with touch-to-inspect. Key stats include total, average, and peak spending, plus a variable vs. fixed ratio breakdown.
>
> 【Why LifeGood?】
>
> ✓ Completely Free — no in-app purchases, no ads
> ✓ Privacy First — all data stored locally on your device only
> ✓ Localized — full Traditional Chinese UI with NT$ currency
> ✓ Intuitive — clean, modern design; log an expense in 3 seconds
> ✓ Works Offline — no internet required
>
> Start using LifeGood and make every dollar count.

### 宣傳文字 (Promotional Text)

| 語言 | 文字 |
|------|------|
| 繁體中文 | 全新記帳體驗！LifeGood 幫您輕鬆追蹤變動與固定支出，五種時間維度的趨勢圖表讓財務一目瞭然。完全免費、離線使用、隱私優先。 |
| English | A fresh way to track expenses! LifeGood helps you manage variable & fixed spending with trend charts across 5 time dimensions. Free, offline, privacy-first. |

### 關鍵字 (Keywords)

| 語言 | 關鍵字 |
|------|--------|
| 繁體中文 | 記帳,支出,理財,開支,帳本,花費,預算,固定支出,變動支出,圖表,趨勢,財務管理,省錢,日記帳,月記帳 |
| English | expense,tracker,budget,finance,spending,money,chart,trend,fixed,variable,bookkeeping,ledger,saving |

### 新功能介紹 (What's New) — v1.2

**繁體中文**

> v1.2 更新內容：
>
> ◆ 新增 App 圖示
> 全新設計的綠色主題圖示，結合錢幣符號與趨勢圖，一眼辨識。
>
> ◆ 固定支出智慧投射
> 固定支出現在會依週期自動投射到每個月份。一月設定的房租，二月以後也會正確顯示。
> - 年度圖表：每月×12、每季×4、每年×1
> - 月度圖表：每月×1、每季÷3、每年÷12
> - 每日與每週同步依比例換算
>
> ◆ 總覽頁面優化
> 本月總支出與今日花費現在正確包含投射的固定支出金額。
>
> ◆ 修正 App Icon 格式
> 修正圖示透明通道問題，確保在所有裝置上正確顯示。

**English**

> v1.2 What's New:
>
> ◆ New App Icon — fresh green-themed icon with dollar symbol and trend line.
> ◆ Smart Fixed Expense Projection — fixed expenses auto-project into every future period based on recurrence.
> ◆ Overview Improvements — monthly total and today's spending now include projected fixed expenses.
> ◆ Icon Format Fix — resolved alpha channel issue for proper display on all devices.

### 隱私權資訊 (App Privacy)

| 問題 | 回答 |
|------|------|
| 是否收集資料？ | 否 |
| 是否使用追蹤？ | 否 |
| 是否與第三方共享資料？ | 否 |

**App Store Connect 隱私標籤：不收集資料 (Data Not Collected)**

本 App 所有資料皆儲存於使用者裝置的 UserDefaults 中，不會透過網路傳送至任何伺服器，也不包含任何分析或追蹤 SDK。

### 年齡分級 (Age Rating)

所有內容分級問題皆回答「無」，建議分級結果：**4+ (所有年齡)**

| 問題 | 回答 |
|------|------|
| 暴力卡通或幻想 | 無 |
| 寫實暴力 | 無 |
| 性與裸露內容 | 無 |
| 褻瀆或粗俗幽默 | 無 |
| 賭博 / 模擬賭博 | 無 |
| 恐怖／驚悚 | 無 |
| 成熟／暗示性主題 | 無 |
| 醫療資訊 | 無 |
| 酒精、菸草或藥物 | 無 |
| 不受限制的網頁存取 | 否 |

### 其他必填欄位

| 欄位 | 內容 |
|------|------|
| 版權 (Copyright) | &copy; 2026 LifeGood. All rights reserved. |
| 授權合約 | 使用 Apple 標準 EULA |
| 支援網址 (Support URL) | *請替換為您的支援頁面* |
| 行銷網址 (Marketing URL) | *選填* |

### App 預覽與截圖建議

上架需提供 iPhone 6.7" 及 6.5" 截圖：

| 順序 | 畫面 | 標題文字 |
|------|------|---------|
| 1 | 總覽頁面 | 一頁掌握您的財務全貌 |
| 2 | 變動支出列表（含篩選） | 9 大分類，輕鬆管理日常開支 |
| 3 | 新增支出表單 | 3 秒完成一筆記帳 |
| 4 | 固定支出列表 | 固定支出自動投射，不再遺漏 |
| 5 | 圖表頁面（月趨勢） | 五種維度，看見花費趨勢 |

---

## 版本紀錄

### v1.2 (Build 3) — 2026-04-13

- 修正 App Icon 透明通道問題 (RGBA → RGB)
- 新增 App Store Connect 上架資訊至 README

### v1.1 (Build 2) — 2026-04-13

- 新增 App Icon（綠色主題 + $ 符號 + 趨勢線）
- 固定支出智慧投射：依週期自動換算到所有時間區間
- 總覽頁面正確包含投射的固定支出金額
- 固定支出頁面新增年度預估金額

### v1.0 (Build 1) — 2026-04-13

- 初始版本
- 四大功能頁面：總覽、變動支出、固定支出、圖表
- 9 種變動支出分類、8 種固定支出分類
- 五種時間維度的趨勢圖表（日/週/月/季/年）
- UserDefaults 本機資料持久化
- 全繁體中文介面，NT$ 貨幣顯示

## 授權

&copy; 2026 LifeGood. All rights reserved.
