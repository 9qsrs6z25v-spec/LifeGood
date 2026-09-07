# 美好人生・部屬看板（桌面唯讀網頁版）

用瀏覽器直接讀取 App 存在 iCloud 裡的部屬與部門資料，只讀不寫。
純靜態網頁（HTML / CSS / JS），不需要伺服器，放在 GitHub Pages 上即可。

## 網址

GitHub Pages 開啟後：`https://9qsrs6z25v-spec.github.io/LifeGood/`

想先看版面：在網址後面加 `?demo=1`，或在登入頁按「先用示範資料看看」（示範資料為虛構人名）。

## 一次性設定

### 1. 開啟 GitHub Pages

1. 打開 repo → **Settings** → **Pages**。
2. **Source** 選 **Deploy from a branch**。
3. **Branch** 選目前開發的分支（例如 `claude/beautiful-life-self-evolution-lohukl`），資料夾選 **/docs**，按 **Save**。
4. 等一兩分鐘，上方會出現網址。之後每次推送分支，網頁會自動更新。

### 2. 產生 CloudKit API Token

1. 打開 <https://icloud.developer.apple.com>，選容器 **iCloud.com.lifegood.app**。
2. 左側 **API Access** → **API Tokens** → **Create API Token**。
3. 名稱隨意（例如 `LifeGood Web`），環境選 **Production**，其他欄位留空即可。
4. 複製產生的 token 字串。

Token 只會存在你自己瀏覽器的 localStorage，不會寫進程式碼、也不會上傳到任何地方。
它本身只能讀「登入的那個 Apple ID」自己的資料，別人拿到也看不到你的東西。

### 3. 第一次開啟網頁

1. 貼上 token → **儲存並登入**。
2. 按 Apple 的 **Sign in with iCloud** 按鈕，用擁有這份資料的 Apple ID 登入。
3. 讀取完成會直接進入部屬總覽。之後打開網頁只需要按登入。

## 頁面

| 頁面 | 內容 |
|---|---|
| 部屬總覽 | 人數／未完成任務／逾期／未交報告／生日 KPI、逾期任務、綜合分數排行、本週會議、近期生日 |
| 部屬列表 | 可搜尋、依部門篩選、點欄位排序；點任一列進明細 |
| 部屬明細 | 潛力／主動性／綜合分數與計算明細；任務、會議（含場次與議程）、報告、紀錄、請假、執掌設備、升職歷程 |
| 人才矩陣 | 主動性 × 潛力散布圖，中位數切四象限，點圓點進明細 |
| 統計圖表 | 請假時數、任務完成數、報告完成數、加分、扣分、逾期、主動性、潛力、總分；可切年度，團隊平均依數值排進序列 |
| 公司組織 | 部門卡片（主管、成員、設備數）、點進部門看上下游、成員、部屬評分與設備清單 |

## 資料與評分

- 讀取的記錄：`kv_life_subordinates`、`kv_life_departments`、`kv_life_org_people`、
  `kv_life_grade_titles`、`kv_life_equipment_pool`、`kv_life_milestones`（兼任職務待辦）、
  `kv_life_business_cards`（@ 標註比對用的名字）。全部在私有資料庫的 `LifeGoodZone`。
- 評分規則（潛力／主動性／逾期定案制／兼任待辦／被標註／會議掛名基本分與議程項目依指派計分）與 App 相同，
  但權重使用 App 出廠預設值：App 進階設定裡調整過的權重存在手機本機，不會同步到 iCloud，網頁讀不到。
- 統計圖表的年度歸類：任務／報告依完成時間、請假與紀錄依日期、逾期依截止日。

## 自動更新

登入 iCloud 後每 10 分鐘在背景重新讀取一次；只有資料真的有變才會重畫畫面並提示。分頁切到背景時暫停，回到前景若已超過 10 分鐘會立刻補抓。左下角「重新讀取」可隨時手動更新，讀取時間與下次自動更新時間顯示在按鈕上方。

## 限制

- **唯讀**。要改資料請用 App。
- 只支援資料擁有者的 Apple ID 登入；被分享的家庭成員（共享參與者）這版還不能用。
- 網頁不會讀照片。
- 必須用 https 網址開啟；直接雙擊本機 HTML 檔（`file://`）Apple 登入視窗會被瀏覽器擋掉。

## 檔案

- `index.html` 頁面骨架與登入閘
- `style.css` 樣式（自動跟隨系統深淺色）
- `app.js` CloudKit 連線、資料解碼、評分移植、各頁面
- `demo-data.js` 示範資料
