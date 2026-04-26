# LifeGood 記帳理財

> 打造完美人生，從記帳與理財開始。

## 簡述

LifeGood 是專為台灣使用者打造的 iOS 生活管理 App，整合記帳、理財、人生三大模式。記帳涵蓋收支與週期投射；理財管理儲蓄險、股票、載具與房地產並附閃卡稀有度；人生記錄履歷里程碑、家庭成員與房地產地圖。三端資料雙向連動，完全離線，支援 JSON/CSV 匯出匯入，需 iOS 17 以上。

## 功能概述

- 記帳模式
    - 總覽：本月收支摘要、今日花費、分類統計、最近交易
    - 收入：4 大分類（薪水/獎金/禮金/確幸），固定薪水自動代入每月
    - 變動支出：10 大分類（飲食/交通/汽車/娛樂/購物/日用品/醫療/教育/社交/其他）
    - 固定支出：8 大分類、月/季/年週期投射
    - 圖表:日/週/月/季/年五維度趨勢
    - 設定：模式切換、匯率設定、匯出 JSON/CSV、匯入、一小時前資料復原、清除

- 理財模式
    - 總覽：總資產、四大類別卡片、配置比例、每月現金流
    - 儲蓄險：TWD/USD 幣別、複利年利率、期滿領回試算
    - 股票：成本/市值/損益/報酬率
    - 汽車：動力類型連動、閃卡稀有度、定期/變動支出分開管理
    - 房地產：購入/估值以萬元輸入，多筆貸款、已支出、變動支出、淨現金流；人生分頁記錄房屋資料/水電瓦斯/保險/附屬資產
    - 圖表：資產配置圓餅、股票損益、房產績效

- 人生模式
    - 總覽：個人檔案閃卡（傳說級，固定置頂）、最近里程碑
    - 履歷：依分類分節顯示，配偶章節置頂；家庭成員自動衍生結婚/離婚/出生
    - 家庭：配偶/兒女/兄弟姐妹管理
    - 房地產：台灣地圖顯示大頭針、點擊動畫展開物件列表、縣市分組
    - 設定：與其他模式共用

- 跨模式連動
    - 理財資產雙向同步對應的固定/變動支出
    - 記帳項目可反向連結既有理財資產
    - 「房屋價金」類別於記帳/理財雙向同步至已支出房屋金額章節
    - 人生家庭成員連動個人檔案與里程碑
    - 人生房地產連結理財物件並以地圖呈現

## 版本紀錄（近 10 個版本）

- v12.9 (Build 120) — 2026-04-26
    - 信用卡財富卡片新增「月扣款金額」章節（柱狀圖 + 列表），與銀行同邏輯
    - 圖表依結帳日/繳款日將支出彙總到對應月份的扣款日
    - 銀行圖表的信用卡扣款依月份合併為一筆虛擬條目（標示「信用卡」橘色徽章）
    - syncBankWithdrawal 信用卡支出不再寫入 BankDeposit，改於顯示時動態彙總
    - 銀行 deposits 自動過濾舊版殘留的信用卡 BankDeposit，避免重複
    - 虛擬彙總條目不可點擊編輯（區分於手動存款記錄）

- v12.8 (Build 119) — 2026-04-26
    - 編輯汽車/機車頁面的項目編輯改用 AddExpenseView，與固定/變動支出編輯體驗一致
    - 點擊既有項目（車貸、稅費、訂閱、油錢、電費等）→ 開啟對應類別的 AddExpenseView 編輯
    - 點擊「新增項目」→ 顯示類別選擇 → 開啟 AddExpenseView 新增（含車輛預設連結）
    - 為新車自動於新增項目時建立 Vehicle 紀錄（auto-save），確保 Expense 連結正確
    - AddExpenseView 新增 preset 參數與 AddExpensePreset 結構，支援預設分類/連結
    - 移除 VehicleFixedItemEditor / VehicleVariableItemEditor 自訂卡片
    - 項目支援滑動刪除（同步移除連結的 Expense）

- v12.7 (Build 118) — 2026-04-26
    - 變動支出/固定支出的「扣款銀行」改名為「扣款目標」
    - 扣款目標選單新增「信用卡」分組，可從銀行或信用卡擇一
    - 選擇信用卡時，依結帳日/繳款日自動推算實際扣款日，記入信用卡連結銀行的扣款柱狀圖
    - Expense 模型新增 linkedCreditCardMilestoneId 選填欄位，向下相容
    - LifeMilestone 新增 creditCardWithdrawalDate(for:billingDay:paymentDay:) 計算工具
    - 收入頁面項目金額下方顯示入帳銀行（含幣別）
    - 變動/固定支出頁面項目金額下方顯示扣款目標（信用卡顯示卡名 + creditcard 圖示，銀行顯示銀行名 + 圖示）

- v12.6 (Build 117) — 2026-04-26
    - 載具卡片（VehicleDetailView）編輯/刪除按鈕仿照房地產移至右上角
    - 編輯/新增汽車頁面標題改為動態：油車/電車/混合動力顯示「🚗汽車」、機車/電動機車顯示「🛵機車」
    - 定期支出與變動支出 section 內的項目改為精簡列表，點擊開啟卡片編輯
    - 卡片內可編輯項目欄位（類別/週期/日期/金額），右上角同時提供「完成」與「刪除」
    - 新增 VehicleFixedItemEditor / VehicleVariableItemEditor 卡片視圖

- v12.5 (Build 116) — 2026-04-26
    - 編輯收入頁面基本資訊章節，金額欄位下方新增銀行選單
    - 當使用者於人生功能新增銀行里程碑後，新增/編輯收入時可選擇入帳銀行
    - 多幣別銀行帳戶展開為子選單供選擇對應幣別
    - 收入儲存時自動寫入連結銀行的存款記錄（isWithdrawal=false），刪除收入時同步移除
    - Income 模型新增 linkedBankMilestoneId / linkedBankCurrency 選填欄位，向下相容
    - IncomeView 刪除收入時清除對應的 BankDeposit 記錄

- v11.6 (Build 107) — 2026-04-24
    - 固定支出貸款子選項選擇「車貸」時，基本資訊章節新增三個欄位
    - 日期上方：總貸款金額（NT$）
    - 日期下方：貸款年限（年）、貸款利率（%）
    - 填入後即時試算：貸款總繳 / 利息總額 / 實際年利率（估算）
    - 金額欄位名稱改為「每月車貸金額」
    - Expense 模型新增 loanTotalAmount / loanYears / loanRate 選填欄位，向下相容
    - 計算公式：總繳 = 月繳 × 12 × 年限，利息 = 總繳 − 總金額，年利率 = 利息 / 總金額 / 年限 × 100

- v11.5 (Build 106) — 2026-04-24
    - 里程碑「成就」分類重新命名為「理財」，圖示改為 banknote.fill
    - 選中後顯示子分類 Picker：銀行/信用卡/證券/保險
    - 銀行：銀行名稱/分行/帳號/帳戶類型（活存/定存/外幣）/開戶日期/備註
    - 信用卡：發卡銀行/卡別名稱/末四碼/額度/年費/帳單日/繳款日/核卡日/到期日/備註
    - 證券：券商名稱/帳號/帳戶類型（一般/融資融券）/開戶日期/備註
    - 保險：保險公司/保單號碼/險種（壽險/醫療/意外/旅平/車險）/保費/生效日/到期日/受益人/備註
    - 自動產生標題（如「開戶 中國信託 敦南分行」「國泰 醫療」）
    - 新增 FinanceSubCategory/BankAccountType/SecuritiesAccountType/InsuranceType 列舉
    - LifeMilestone 新增 17 個理財專屬欄位，向下相容

- v11.4 (Build 105) — 2026-04-24
    - 記帳/理財/人生三個模式的總覽頁面右上角新增快速新增按鈕
    - 彈跳選單可選擇：變動支出/固定支出/股票/房地產
    - 選擇後直接開啟對應的新增頁面（sheet）
    - 不需切換模式即可快速新增跨模式項目

- v11.3 (Build 104) — 2026-04-23
    - 編輯部屬基本資訊新增「入職日期」欄位，以 Toggle 決定是否填寫
    - 職位欄位上方新增「填入入職日期」開關，開啟後顯示 DatePicker
    - Subordinate 模型新增 joinDate: Date? 欄位，向下相容
    - 部屬卡片詳細頁頭部卡片顯示入職日期（含日曆圖示）
    - 儲存/編輯時保留既有記錄（records）不受影響

- v11.2 (Build 103) — 2026-04-23
    - 兒女履歷頁面改為可點擊卡片，開啟 ChildDetailView 詳細頁
    - 兒女詳細頁新增 7 個章節：疫苗/過敏/成長記錄/就醫記錄/教育里程碑/興趣才藝/紀念時刻
    - 疫苗記錄：疫苗名稱/劑次/接種院所/日期/備註
    - 過敏記錄：過敏原/嚴重度（輕/中/重）/反應描述/日期/備註
    - 成長記錄：身高(cm)/體重(kg)/日期/備註
    - 就醫記錄：症狀或診斷/院所/日期/備註
    - 教育里程碑：事件/學校或單位/日期/備註
    - 興趣才藝：項目名稱/描述/日期/備註
    - 紀念時刻：事件/描述/日期/備註（如第一次走路、第一次說話）
    - 卡片列表顯示各類記錄數量徽章（圖示+數量）
    - 新增 ChildRecordType/AllergySeverity 列舉、ChildRecord 模型
    - FamilyMember 新增 childRecords 欄位，向下相容

- v11.1 (Build 102) — 2026-04-23
    - 點擊部屬項目開啟 SubordinateDetailView 卡片（取代原直接開啟編輯頁）
    - 頂部頭像卡片顯示姓名/職等職稱/部門 + 四項統計徽章（優點/缺點/成就/Miss）
    - 新增 5 個章節：優缺點（合併）、成就、改善、缺失、Miss Operation
    - 每章節右上角 + 按鈕可新增項目，優缺點以 Menu 選優或缺
    - RecordEditorSheet：內容、日期、備註；Miss Operation 另含嚴重度（輕微/一般/嚴重）
    - 點擊既有記錄可編輯/刪除；列表依日期新→舊排序
    - 新增 SubordinateRecordType 列舉（pro/con/achievement/improvement/fault/missOperation）
    - 新增 MissOpSeverity 列舉（minor/normal/severe）
    - Subordinate 模型新增 records: [SubordinateRecord]，向下相容
    - toolbar 右上角「編輯」按鈕開啟基本資訊編輯

- v11.0 (Build 101) — 2026-04-23
    - 移除管理功能選單按鈕的「附屬功能」前綴，僅顯示選中功能名稱（部屬/職等職稱）
    - 部屬頁面右上角新增排序按鈕（與房地產頁面一致）
    - 可依姓名/部門/職位/新增順序排序，點擊相同選項切換升/降序
    - 部屬列表右側部門顯示改為兩行：第一行部門編號（灰色小字）、第二行部門名稱
    - 未連結部門的部屬保持舊有單行顯示

- v10.9 (Build 100) — 2026-04-23
    - 理財總覽儲蓄險金額全部換算為台幣顯示（依設定中的匯率自動換算）
    - 總資產金額改用換算後的儲蓄險台幣值重新計算
    - 資產配置圓餅圖與比例改用台幣換算後的數值
    - 四宮格卡片新增損益顯示：儲蓄險（目前價值−已繳，換算台幣）、股票（總損益含已賣出）
    - 汽車/房地產暫不顯示損益；房地產筆數改為僅顯示持有中
    - 新增 rateForCode/insuranceValueNTD/insurancePaidNTD/insuranceProfitLoss 計算屬性

- v10.8 (Build 99) — 2026-04-23
    - 部屬的部門改為以 departmentId (UUID) 連結，修改部門名稱後部屬自動聯動
    - 部屬列表優先顯示 departmentId 連結的部門（即時查詢 lifeStore.departments）
    - 連結不存在時回退顯示舊有 department 文字（向下相容）
    - 新增/編輯部屬時部門 Picker 改為 UUID 綁定（tag UUID?.some(dept.id)）
    - 儲存時同步寫入 departmentId 與 department 文字（冗餘備份）
    - Subordinate 模型新增 departmentId: UUID? 欄位，向下相容

- v10.7 (Build 98) — 2026-04-23
    - 管理功能選單按鈕文字改為「附屬功能」換行「部屬/職等職稱」
    - 職等職稱頁面（GradeTitleView）職等章節上方新增「部門名稱」章節
    - 部門設定：左側部門編號 + 右側部門名稱，可新增/刪除多筆
    - 新增 Department 模型（code/name），LifeStore 新增 CRUD + 持久化
    - UnifiedExport 新增 departments 選填欄位，匯出匯入涵蓋
    - CloudSyncManager 新增 life_departments 同步 key
    - 新增部屬頁面「部門」欄位改為 Picker，選項來自部門設定（無部門時回退 TextField）

    - 電梯保養照片改為檔案儲存（Documents/ElevatorPhotos/），模型只存檔名
    - 解決照片 Data 存入 UserDefaults / iCloud KV 導致超量與效能問題
    - 照片上傳後顯示為小按鈕（photo.fill 圖示），點擊開啟全螢幕照片檢視器
    - 新增 PhotoViewerSheet：黑底全螢幕顯示，右上角關閉按鈕
    - 修正房地產卡片（RealEstateDetailView）未顯示電梯資料的 bug
    - 卡片房屋資料頁新增「電梯資料」章節，列出所有保養記錄（日期+照片按鈕）
    - ElevatorMaintenance 模型 photoData 改為 photoFileName，新增 savePhoto/deletePhoto/photoURL 靜態方法

    - 編輯房地產房屋資料：透天類型下方新增「有電梯」Toggle
    - 開啟後房屋資料下方出現「電梯資料」章節，可新增多筆保養記錄
    - 每筆保養記錄包含保養日期（DatePicker）與保養照片（PhotosPicker）
    - 照片以 Data 存入 ElevatorMaintenance 模型，編輯時即時顯示縮圖
    - 新增 ElevatorMaintenance 模型（date/photoData），RealEstate 新增 hasElevator + elevatorMaintenances
    - 切換為大樓時電梯資料自動隱藏，儲存時不保留

> 更早版本收納於 `docs/readme-archive/`。

## 授權

&copy; 2026 LifeGood. All rights reserved.
