import SwiftUI

// MARK: - 美化紀錄（MacaronDatePicker）
// [2026-06] 本次美化方向：
//   1. 容器卡片：補雙層陰影（主色 0.06 + 黑 0.03）+ 極細 overlay 邊框（separator 0.15），
//      對齊 OverviewView.todayCard / IncomeView.summaryHeader 卡片精緻感，深色模式相容
//   2. 快捷按鈕動畫：easeInOut(0.15) 升級為 .spring(response:0.30, dampingFraction:0.70)，
//      選中狀態加 scaleEffect(1.04)，對齊全 App 按鈕彈跳動畫規格
//   3. 選中快捷鍵：背景加對應色 0.22 光暈陰影（y:3），強化視覺回饋；
//      未選中狀態 opacity 從 0.28 → 0.22，讓選中對比更鮮明
//   4. 快捷鍵與 DatePicker 之間加入 0.5pt 分隔線（separator 0.20），提升視覺分層
//   5. DatePicker 左側加「自訂日期」小圖示 + 文字標籤（.caption2.foregroundStyle(.tertiary)），
//      引導使用者了解底部 compact picker 用途，對齊 IncomeView KPI 橫列輔助文字規格
//   6. 整體 padding 微調：pills 行垂直從 8 → 9，DatePicker 行垂直從 compact → 10，
//      呼吸感與其他表單卡片一致
// [2026-07 v2] 深色模式對比 + 文字自適應：
//   7. pillButton 未選中底色：固定 opacity(0.22) 疊在 systemBackground 上，深色模式下
//      systemBackground 接近純黑，馬卡龍粉彩色會被吃成一片死黑、難以分辨彼此顏色。
//      改為依 colorScheme 切換：淺色維持 0.22，深色提高到 0.34，
//      對齊 FamilyOverviewMap v3 依 colorScheme 切換底色的做法。
//   8. pillButton 標籤／日期文字補 lineLimit(1) + minimumScaleFactor(0.8)：
//      5 顆膠囊在小螢幕（SE）+ 大字體輔助設定下容易被壓縮換行變形，
//      加上後可自動縮小但不低於可辨識下限，對齊全 App 文字自適應規格。
// [2026-07 v3] 進場動畫一致性：本元件在兩個呼叫端（MyCalendarView／SubordinateOverviewView）
//   都夾在「已有 opacity+offset 進場動畫的英雄卡」與「已有錯落進場動畫的清單 section」中間，
//   是唯一一個一開啟畫面就直接定位、沒有進場過場的區塊，讓整條卷軸的進場節奏中間斷了一拍。
//   改為元件自帶 appeared 旗標（opacity 0→1 + 上移 14pt，spring 0.52/0.80，delay 0.06s 銜接在
//   兩處呼叫端英雄卡之後），onDisappear 歸零避免分頁切換/重新開啟時動畫不重播；採自包含寫法
//   （不需呼叫端額外傳入狀態），對齊 ExpensePhotoStackViewer／RenovationStackViewer 等共用元件
//   自行管理進場動畫的既有慣例，兩個呼叫端都自動獲得一致效果。純視覺調整，日期選取、
//   allowFuture 過濾等既有商業邏輯完全未變動。
// [2026-07 v4] 承接上一版留下的待辦：compact DatePicker 主題色統一：
//   9. DatePicker(.compact) 先前未指定 .tint，沿用全 App 系統藍 accentColor，
//      是卡片內唯一一處跟 5 顆馬卡龍快捷鍵、分隔線、標籤色完全無關的元素，
//      展開的日曆彈出視窗選中日期圓圈也是系統藍，與整張卡片的莫蘭迪馬卡龍語言脫節。
//      新增 pickerTint（介於薰衣草與玫瑰之間的霧霧莫蘭迪紫，不偏袒任一顆快捷鍵色），
//      套用 .tint(pickerTint) 到 DatePicker：文字按鈕與彈出日曆選中態改用此色，
//      呼應卡片整體粉彩基調；純視覺調整，日期選取、allowFuture 過濾等既有邏輯完全未變動。
//   （下次美化本元件時，可留意 DatePicker(.compact) 彈出日曆本身其餘系統原生配色
//   是否仍與卡片有落差，或轉往其他仍留有待辦的畫面）

/// 馬卡龍色調的精簡日期選擇器：第一行 5 顆相對日期按鈕，第二行 compact DatePicker。
struct MacaronDatePicker: View {
    @Binding var selectedDate: Date
    /// 是否允許選未來日期（行事曆需要、部屬總覽也允許）
    var allowFuture: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    private let calendar = Calendar.current
    // [v4] compact DatePicker 專用強調色：霧霧莫蘭迪紫，介於薰衣草／玫瑰兩顆快捷鍵色之間，
    // 取代系統預設藍色，讓文字按鈕與彈出日曆選中態都融入卡片整體馬卡龍配色
    private let pickerTint = Color(red: 0.62, green: 0.48, blue: 0.68)
    private static let mdFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private var relativeDays: [(label: String, offset: Int, color: Color)] {
        let all: [(label: String, offset: Int, color: Color)] = [
            ("前天", -2, Color(red: 0.66, green: 0.86, blue: 0.74)),  // mint
            ("昨天", -1, Color(red: 0.78, green: 0.71, blue: 0.89)),  // lavender
            ("今天",  0, Color(red: 0.99, green: 0.80, blue: 0.65)),  // peach
            ("明天",  1, Color(red: 0.99, green: 0.92, blue: 0.65)),  // butter
            ("後天",  2, Color(red: 0.99, green: 0.74, blue: 0.80)),  // rose
        ]
        // allowFuture 原本宣告但未實際套用：未來日快捷鍵與下方 DatePicker 一律允許選未來日期，
        // 與參數文件「是否允許選未來日期」的意圖不符。改為實際依旗標過濾/限制。
        guard !allowFuture else { return all }
        return all.filter { $0.offset <= 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 快捷日期膠囊列
            HStack(spacing: 6) {
                ForEach(relativeDays, id: \.offset) { item in
                    pillButton(label: item.label, offset: item.offset, color: item.color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            // 分隔線：區分快捷按鈕與自訂日期選擇器
            Rectangle()
                .fill(Color(.separator).opacity(0.20))
                .frame(height: 0.5)

            // 自訂日期選擇器列
            HStack(spacing: 8) {
                // 引導標籤：讓使用者了解底部 picker 用途
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text("自訂日期")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)

                Spacer()

                Group {
                    if allowFuture {
                        DatePicker("選擇日期", selection: $selectedDate, displayedComponents: .date)
                    } else {
                        DatePicker("選擇日期", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                    }
                }
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(pickerTint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.15), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.06)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }

    private func pillButton(label: String, offset: Int, color: Color) -> some View {
        let target = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date())
        let isSelected = calendar.isDate(selectedDate, inSameDayAs: target)
        let dateLabel = Self.mdFormatter.string(from: target)
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.70)) {
                selectedDate = target
            }
        } label: {
            VStack(spacing: 2) {
                Text(label).font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(dateLabel).font(.system(size: 10)).opacity(0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            // 選中時飽和度更高（0.90）；未選中依 colorScheme 調整（淺色 0.22／深色 0.34），
            // 避免深色模式下底色被 systemBackground 吃成一片死黑
            .background(color.opacity(isSelected ? 0.90 : (colorScheme == .dark ? 0.34 : 0.22)))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(isSelected ? 0 : 0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            // 選中時輕微放大（對齊 MainTabView tabItemLabel scaleEffect 規格）
            .scaleEffect(isSelected ? 1.04 : 1.0)
            // 選中時加對應色光暈陰影，未選中時不影響佈局（無陰影）
            .shadow(
                color: isSelected ? color.opacity(0.30) : .clear,
                radius: 5, x: 0, y: 3
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.30, dampingFraction: 0.70), value: isSelected)
    }
}
