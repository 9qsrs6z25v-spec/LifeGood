import SwiftUI

// MARK: - 美化紀錄（FamilyOverviewMap）
// [2026-06] 本次美化方向：
//   1. personChip 圖示圓：從 22pt 純色背景升級為 26pt LinearGradient 漸層底圓
//      + 白色圖示 + 彩色外光暈陰影，對齊全 App 漸層圖示圓設計語言（ExpenseRow / incomeRow）。
//   2. HouseView 雙層陰影：從單層 shadow 升級為「彩色頂光 + 黑色基底」雙層陰影，
//      提升房子卡片的立體感，對齊 StockView.stockCard / VehicleView.vehicleCard 規格。
//   3. 屋頂 stroke overlay：顏色從 roofColor.opacity(0.6) 改為 roofColor.opacity(0.80)，
//      提升屋頂三角形與屋身接合處的對比度。
//   4. 屋身 overlay stroke：lineWidth 從 1 改為 0.75、顏色微調，深色模式下邊框更細膩，
//      對齊全 App overlay stroke 規格（StockView / VehicleView 0.75pt 邊框）。
//   5. 屋頂標籤字重：.semibold → .bold，與全 App Capsule sectionHeader 字重一致。
//   6. 人名字體：9pt → 10pt，提升最小可識別閾值，避免超小字在小螢幕閱讀困難。

// MARK: - 家庭總覽（街道式）

/// 將家庭成員依關係分組成數個「房子」，並排列在一條橫向街道的上下兩側。
/// 我家（含配偶與子女）會與爸媽家以線連在一起，其餘親屬各自有獨立的房子。
struct FamilyOverviewMap: View {
    let myName: String
    let members: [FamilyMember]

    private var spouse: FamilyMember? { members.first { $0.role == .spouse } }
    private var children: [FamilyMember] {
        members.filter { $0.role == .son || $0.role == .daughter }
    }
    private var parents: [FamilyMember] {
        members.filter { $0.role == .father || $0.role == .mother }
    }
    private var siblings: [FamilyMember] {
        members.filter {
            [.elderBrother, .elderSister, .youngerBrother, .youngerSister].contains($0.role)
        }
    }
    private var otherRelatives: [FamilyMember] {
        members.filter { $0.role == .otherRelative }
    }

    /// 街道下方的房子（包含我家、兄弟姐妹、一半的其他親屬）
    private var bottomHouses: [FamilyHouse] {
        var list: [FamilyHouse] = []
        // 我家：把使用者本人 + 配偶 + 子女裝在同一棟
        list.append(FamilyHouse(
            id: "self",
            label: myName.isEmpty ? "我家" : "\(myName)的家",
            kind: .myFamily,
            occupants: nuclearOccupants
        ))
        // 兄弟姐妹各自一棟
        for s in siblings {
            list.append(FamilyHouse(
                id: "sib-\(s.id.uuidString)",
                label: "\(s.role.rawValue)的家",
                kind: .sibling,
                occupants: [.init(id: s.id.uuidString,
                                   name: s.chineseName.isEmpty ? s.role.rawValue : s.chineseName,
                                   role: s.role)]
            ))
        }
        // 一半其他親屬放底下
        let half = otherRelatives.count / 2
        for r in otherRelatives.prefix(half + (otherRelatives.count % 2)) {
            list.append(FamilyHouse(
                id: "rel-\(r.id.uuidString)",
                label: r.chineseName.isEmpty ? "親屬" : r.chineseName,
                kind: .relative,
                occupants: [.init(id: r.id.uuidString, name: r.chineseName.isEmpty ? "親屬" : r.chineseName, role: r.role)]
            ))
        }
        return list
    }

    /// 街道上方的房子（爸媽 + 一半的其他親屬）
    private var topHouses: [FamilyHouse] {
        var list: [FamilyHouse] = []
        if !parents.isEmpty {
            list.append(FamilyHouse(
                id: "parents",
                label: "爸媽的家",
                kind: .parents,
                occupants: parents.map { p in
                    .init(id: p.id.uuidString, name: p.chineseName.isEmpty ? p.role.rawValue : p.chineseName, role: p.role)
                }
            ))
        }
        // 另一半的其他親屬放上面
        let half = otherRelatives.count / 2
        for r in otherRelatives.suffix(half) {
            list.append(FamilyHouse(
                id: "rel-top-\(r.id.uuidString)",
                label: r.chineseName.isEmpty ? "親屬" : r.chineseName,
                kind: .relative,
                occupants: [.init(id: r.id.uuidString, name: r.chineseName.isEmpty ? "親屬" : r.chineseName, role: r.role)]
            ))
        }
        return list
    }

    private var nuclearOccupants: [HouseOccupant] {
        var list: [HouseOccupant] = [.init(id: "me", name: myName.isEmpty ? "我" : myName, role: nil)]
        if let s = spouse {
            list.append(.init(id: s.id.uuidString, name: s.chineseName.isEmpty ? "配偶" : s.chineseName, role: .spouse))
        }
        for c in children {
            list.append(.init(id: c.id.uuidString, name: c.chineseName.isEmpty ? c.role.rawValue : c.chineseName, role: c.role))
        }
        return list
    }

    // MARK: - body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                // 上排（爸媽 + 部分親屬）
                HStack(alignment: .bottom, spacing: 24) {
                    ForEach(topHouses) { h in
                        VStack(spacing: 4) {
                            HouseView(house: h)
                            // 我家連到爸媽家：底部一條短線（街道下會接續）
                            if h.kind == .parents {
                                Rectangle()
                                    .fill(Color.green.opacity(0.6))
                                    .frame(width: 2, height: 14)
                            } else {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 2, height: 14)
                            }
                        }
                        .frame(width: HouseView.fixedWidth)
                    }
                    if topHouses.isEmpty {
                        // 占位：沒有上排房子時保留高度，街道仍會在中間
                        Color.clear.frame(height: 130)
                    }
                }
                .padding(.horizontal, 24)
                .frame(minWidth: scrollMinWidth, alignment: .center)

                // 中央街道（加厚）
                streetLine
                    .frame(minWidth: scrollMinWidth)

                // 下排（我家 + 兄弟姐妹 + 部分親屬）
                // 上方負 padding 讓房子腰部疊到街道上
                HStack(alignment: .top, spacing: 24) {
                    ForEach(bottomHouses) { h in
                        VStack(spacing: 4) {
                            // 我家上方畫一條短線承接到街道（爸媽連結用）
                            if h.kind == .myFamily && !parents.isEmpty {
                                Rectangle()
                                    .fill(Color.green.opacity(0.6))
                                    .frame(width: 2, height: 14)
                            } else {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 2, height: 14)
                            }
                            HouseView(house: h)
                        }
                        .frame(width: HouseView.fixedWidth)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, -32)
                .frame(minWidth: scrollMinWidth, alignment: .center)
            }
            .padding(.vertical, 12)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemGroupedBackground), Color(red: 0.93, green: 0.96, blue: 0.92)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// 估算 ScrollView 視覺最小寬度（以屋子數量決定，含 padding）
    private var scrollMinWidth: CGFloat {
        let topCount = max(topHouses.count, 1)
        let bottomCount = max(bottomHouses.count, 1)
        let count = max(topCount, bottomCount)
        return CGFloat(count) * (HouseView.fixedWidth + 24) + 48
    }

    // MARK: - 街道

    private var streetLine: some View {
        ZStack {
            // 路面（深綠灰）
            Rectangle()
                .fill(Color(red: 0.55, green: 0.62, blue: 0.50))
                .frame(height: 32)
            // 雙黃線
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    ForEach(0..<80, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.yellow.opacity(0.85))
                            .frame(width: 18, height: 2)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(0..<80, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.yellow.opacity(0.85))
                            .frame(width: 18, height: 2)
                    }
                }
            }
            // 路肩白邊
            VStack {
                Rectangle().fill(Color.white.opacity(0.55)).frame(height: 1.5)
                Spacer()
                Rectangle().fill(Color.white.opacity(0.55)).frame(height: 1.5)
            }
            .frame(height: 32)
        }
        .frame(height: 32)
    }
}

// MARK: - 房子資料

struct HouseOccupant: Identifiable, Hashable {
    let id: String  // 直接傳入成員 UUID，避免同名同角色的成員產生重複 ID
    let name: String
    let role: FamilyMemberRole?
}

enum HouseKind {
    case myFamily, parents, sibling, relative

    var roofColor: Color {
        switch self {
        case .myFamily: return Color(red: 0.95, green: 0.55, blue: 0.55)   // 紅磚
        case .parents:  return Color(red: 0.45, green: 0.65, blue: 0.85)   // 藍
        case .sibling:  return Color(red: 0.95, green: 0.78, blue: 0.45)   // 黃
        case .relative: return Color(red: 0.7, green: 0.7, blue: 0.7)      // 灰
        }
    }

    var bodyColor: Color {
        switch self {
        case .myFamily: return Color(red: 1.0, green: 0.96, blue: 0.92)
        case .parents:  return Color(red: 0.94, green: 0.97, blue: 1.0)
        case .sibling:  return Color(red: 1.0, green: 0.99, blue: 0.92)
        case .relative: return Color(red: 0.96, green: 0.96, blue: 0.96)
        }
    }
}

struct FamilyHouse: Identifiable {
    let id: String
    let label: String
    let kind: HouseKind
    let occupants: [HouseOccupant]
}

// MARK: - 房子畫面

struct HouseView: View {
    let house: FamilyHouse
    static let fixedWidth: CGFloat = 130

    var body: some View {
        VStack(spacing: 0) {
            // 屋頂（三角形）
            RoofShape()
                .fill(house.kind.roofColor)
                .frame(height: 32)
                .overlay(
                    RoofShape()
                        .stroke(house.kind.roofColor.opacity(0.80), lineWidth: 1)
                )

            // 屋身
            VStack(spacing: 4) {
                Text(house.label)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .padding(.top, 6)

                Divider()
                    .padding(.horizontal, 8)

                // 成員圈圈
                let occupants = house.occupants
                let chunks = occupants.chunked(into: 2)
                VStack(spacing: 4) {
                    ForEach(Array(chunks.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 6) {
                            ForEach(row) { person in
                                personChip(person)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(width: HouseView.fixedWidth)
            .background(house.kind.bodyColor)
            .overlay(
                Rectangle()
                    .stroke(house.kind.roofColor.opacity(0.45), lineWidth: 0.75)
            )
        }
        // 雙層陰影：彩色頂光 + 黑色基底
        .shadow(color: house.kind.roofColor.opacity(0.28), radius: 10, x: 0, y: 5)
        .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)
    }

    private func personChip(_ p: HouseOccupant) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [house.kind.roofColor, house.kind.roofColor.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                    .shadow(color: house.kind.roofColor.opacity(0.35), radius: 4, x: 0, y: 2)
                Image(systemName: p.role?.icon ?? "person.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text(p.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 50)
        }
    }
}

// MARK: - 屋頂三角形

private struct RoofShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let overhang: CGFloat = 4
        p.move(to: CGPoint(x: -overhang, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX + overhang, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Array helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
