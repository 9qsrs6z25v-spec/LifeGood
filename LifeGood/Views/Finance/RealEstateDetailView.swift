import SwiftUI

struct RealEstateDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let estateId: UUID
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    enum DetailTab: String, CaseIterable {
        case finance = "理財"
        case house = "房屋資料"
    }
    @State private var detailTab: DetailTab = .finance

    private var estate: RealEstate {
        store.realEstates.first(where: { $0.id == estateId }) ?? placeholder
    }

    private let placeholder = RealEstate(name: "")

    init(estate: RealEstate) {
        self.estateId = estate.id
    }

    private var rarity: CardRarity { CardRarity.realEstate(price: estate.purchasePrice) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    flashCard
                    tabPicker
                    if detailTab == .finance {
                        infoSection
                    } else {
                        houseInfoSection
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("房地產卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showEdit = true } label: {
                            Text("編輯").foregroundStyle(.green)
                        }
                        Button { showDeleteConfirm = true } label: {
                            Text("刪除").foregroundStyle(.red)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddRealEstateView(editing: estate)
            }
            .alert("確定要刪除這筆房地產嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    deleteEstate()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後所有連結的記帳支出也會一併移除，此操作無法復原。")
            }
        }
    }

    // MARK: - 閃卡主體

    private var flashCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(rarity.label)
                    .font(.caption2.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(rarity.textColor)
                Spacer()
                Label("房地產", systemImage: "building.2.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .yellow : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            VStack(spacing: 6) {
                Text(estate.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .white : .primary)
                    .multilineTextAlignment(.center)

                if !estate.fullAddress.isEmpty {
                    Text(estate.fullAddress)
                        .font(.subheadline)
                        .foregroundStyle(rarity == .legendary ? .white.opacity(0.7) : .secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)

            VStack(spacing: 4) {
                Text("\(fmtWan(estate.currentValue))")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(rarity.textColor)
                Text("萬元")
                    .font(.subheadline)
                    .foregroundStyle(rarity == .legendary ? .white.opacity(0.6) : .secondary)
            }
            .padding(.vertical, 20)

            HStack {
                VStack(spacing: 2) {
                    Text("購入")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text("\(fmtWan(estate.purchasePrice)) 萬")
                        .font(.caption.bold()).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.8) : Color.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("增值率")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%@%.1f%%", estate.appreciationRate >= 0 ? "+" : "", estate.appreciationRate))
                        .font(.caption.bold()).foregroundStyle(estate.appreciationRate >= 0 ? .green : .red)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("月租")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(estate.monthlyRental > 0 ? fmt(estate.monthlyRental) : "—")
                        .font(.caption.bold()).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.8) : Color.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(colors: rarity.bgGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    AngularGradient(colors: rarity.borderGradient, center: .center),
                    lineWidth: rarity.borderWidth
                )
        )
        .shadow(color: rarity.shadowColor, radius: rarity == .legendary ? 15 : 8, y: 4)
        .overlay(alignment: .topLeading) {
            if estate.isSold {
                SoldStamp(size: 32)
                    .offset(x: -10, y: -14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - 詳細資訊

    private var infoSection: some View {
        VStack(spacing: 0) {
            if !estate.mortgageItems.isEmpty {
                sectionHeader("貸款明細")
                ForEach(estate.mortgageItems) { m in
                    HStack {
                        Text(m.title.isEmpty ? "房貸" : m.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text("\(m.elapsedPeriods)/\(m.totalPeriods) 期")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(fmt(m.amount) + "/月").font(.subheadline.bold())
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
                HStack {
                    Text("已繳貸款").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(fmt(estate.totalMortgagePaid))
                        .font(.subheadline.bold()).foregroundStyle(.blue)
                }
                .padding(.horizontal).padding(.vertical, 6)
            }

            if !estate.paidItems.isEmpty {
                sectionHeader("已支出")
                ForEach(estate.paidItems) { p in
                    HStack {
                        Text(p.title.isEmpty ? "已付款" : p.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Spacer()
                        Text(fmt(p.amount)).font(.subheadline.bold())
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }

            if !estate.variableExpenses.isEmpty {
                sectionHeader("變動支出")
                ForEach(estate.variableExpenses) { ve in
                    HStack {
                        Text(ve.category.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        if !ve.name.isEmpty {
                            Text(ve.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(fmt(ve.amount)).font(.subheadline.bold())
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }

            if estate.monthlyRental > 0 {
                sectionHeader("收益")
                HStack {
                    Text("月淨現金流").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    let flow = estate.monthlyCashFlow
                    Text(fmt(flow))
                        .font(.subheadline.bold())
                        .foregroundStyle(flow >= 0 ? .green : .red)
                }
                .padding(.horizontal).padding(.vertical, 8)
                HStack {
                    Text("年租金報酬率").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f%%", estate.rentalYield))
                        .font(.subheadline.bold()).foregroundStyle(.blue)
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
        }
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - 分頁選擇器

    private var tabPicker: some View {
        Picker("", selection: $detailTab) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - 房屋資料（人生）

    private var houseInfoSection: some View {
        VStack(spacing: 0) {
            let hasProperty = estate.pingCount > 0 || !estate.landOwner.isEmpty

            if hasProperty {
                sectionHeader("房屋資料")
                if estate.pingCount > 0 { infoRow("坪數", String(format: "%g 坪", estate.pingCount)) }
                if !estate.landOwner.isEmpty { infoRow("所有權人", estate.landOwner) }
            }

            if !estate.landDeeds.isEmpty || !estate.buildingDeeds.isEmpty {
                for (i, d) in estate.landDeeds.enumerated() {
                    sectionHeader("土地權狀\(estate.landDeeds.count > 1 ? " \(i + 1)" : "")")
                    if !d.situation.isEmpty { infoRow("坐落", d.situation) }
                    if !d.number.isEmpty { infoRow("地號", d.number) }
                    if d.area > 0 { infoRow("面積", String(format: "%g ㎡", d.area)) }
                }
                for (i, d) in estate.buildingDeeds.enumerated() {
                    sectionHeader("建物權狀\(estate.buildingDeeds.count > 1 ? " \(i + 1)" : "")")
                    if !d.situation.isEmpty { infoRow("坐落", d.situation) }
                    if !d.number.isEmpty { infoRow("建號", d.number) }
                    if !d.address.isEmpty { infoRow("門牌", d.address) }
                    if let cd = d.completionDate { infoRow("完工日", formatDate(cd)) }
                    if !d.usage.isEmpty { infoRow("用途", d.usage) }
                    if !d.annex.isEmpty { infoRow("附屬建物", d.annex) }
                    if d.area > 0 { infoRow("面積", String(format: "%g ㎡", d.area)) }
                }
            }

            if !estate.floors.isEmpty {
                buildingVisualization
            }

            let hasUtilities = !estate.waterMeterNumber.isEmpty || !estate.waterMeterOwner.isEmpty
                || !estate.electricityMeterNumber.isEmpty || !estate.electricityMeterOwner.isEmpty
                || !estate.gasMeterNumber.isEmpty || !estate.gasMeterOwner.isEmpty

            if hasUtilities {
                sectionHeader("水電瓦斯")
                if !estate.waterMeterNumber.isEmpty || !estate.waterMeterOwner.isEmpty {
                    utilityRow(icon: "drop.fill", color: .blue,
                               number: estate.waterMeterNumber, owner: estate.waterMeterOwner,
                               numberLabel: "水號")
                }
                if !estate.electricityMeterNumber.isEmpty || !estate.electricityMeterOwner.isEmpty {
                    utilityRow(icon: "bolt.fill", color: .yellow,
                               number: estate.electricityMeterNumber, owner: estate.electricityMeterOwner,
                               numberLabel: "電號")
                }
                if !estate.gasMeterNumber.isEmpty || !estate.gasMeterOwner.isEmpty {
                    utilityRow(icon: "flame.fill", color: .orange,
                               number: estate.gasMeterNumber, owner: estate.gasMeterOwner,
                               numberLabel: "瓦斯表號")
                }
            }

            if !estate.insuranceItems.isEmpty {
                sectionHeader("保險項目")
                ForEach(estate.insuranceItems) { ins in
                    HStack {
                        Image(systemName: "shield.fill").foregroundStyle(.indigo)
                        Text(ins.policyNumber.isEmpty ? "未填險號" : ins.policyNumber)
                            .font(.subheadline)
                            .foregroundStyle(ins.policyNumber.isEmpty ? .tertiary : .primary)
                        Spacer()
                        if ins.amount > 0 {
                            Text(fmt(ins.amount)).font(.subheadline.bold()).foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }

            if !estate.propertyAssets.isEmpty {
                sectionHeader("房屋附屬資產")
                ForEach(estate.propertyAssets) { asset in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(asset.category.rawValue)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .foregroundStyle(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(asset.name.isEmpty ? "—" : asset.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if asset.amount > 0 {
                                Text(fmt(asset.amount)).font(.subheadline.bold()).foregroundStyle(.orange)
                            }
                        }
                        HStack(spacing: 10) {
                            if !asset.brand.isEmpty {
                                Text("廠牌 \(asset.brand)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if !asset.floorLocation.isEmpty {
                                Text("位置 \(asset.floorLocation)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }

            if !hasProperty && !hasDetail && estate.floors.isEmpty && !hasUtilities && estate.insuranceItems.isEmpty && estate.propertyAssets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text("尚未填寫房屋資料").font(.subheadline).foregroundStyle(.secondary)
                    Text("點擊下方編輯按鈕填寫").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - 建物立體圖

    private static let cyanColor = Color(red: 0, green: 0.85, blue: 1.0)

    private var sortedFloors: [FloorInfo] {
        estate.floors.sorted { floorOrder($0) < floorOrder($1) }
    }

    private func floorOrder(_ f: FloorInfo) -> Int {
        let s = f.floorNumber.uppercased()
            .replacingOccurrences(of: "F", with: "")
            .replacingOccurrences(of: "樓", with: "")
            .trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("B") { return -(Int(s.dropFirst()) ?? 0) }
        return Int(s) ?? 0
    }

    private var buildingVisualization: some View {
        let sorted = sortedFloors
        let count = sorted.count
        let floorH: CGFloat = 44
        let depth: CGFloat = 22
        let depthY: CGFloat = depth * 0.55
        let cyan = Self.cyanColor
        let visibleRows = estate.buildingType == .townhouse ? count : max(count, 8)
        let canvasHeight = CGFloat(visibleRows) * floorH + depthY + 8

        return VStack(spacing: 0) {
            sectionHeader("樓層資訊（\(count) 層）")

            ZStack(alignment: .topLeading) {
                // 建物線框
                if estate.buildingType == .townhouse {
                    townhouseWireframe(floorCount: count, floorH: floorH, depth: depth, depthY: depthY)
                } else {
                    apartmentWireframe(userFloors: sorted, floorH: floorH, depth: depth, depthY: depthY)
                }

                // 樓層標籤
                if estate.buildingType == .townhouse {
                    VStack(spacing: 0) {
                        ForEach(sorted.reversed()) { floor in
                            floorLabel(floor).frame(height: floorH)
                        }
                    }
                    .padding(.leading, 190)
                    .padding(.top, depthY)
                } else {
                    let totalVisible = max(count, 8)
                    let userStart = (totalVisible - count) / 2
                    VStack(spacing: 0) {
                        ForEach(sorted.reversed()) { floor in
                            floorLabel(floor).frame(height: floorH)
                        }
                    }
                    .padding(.leading, 190)
                    .padding(.top, depthY + CGFloat(userStart) * floorH)
                }
            }
            .frame(height: canvasHeight)
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black)

                    // HUD 外框 + 泛光
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(cyan.opacity(0.35), lineWidth: 1)
                        .shadow(color: cyan.opacity(0.6), radius: 6)
                        .shadow(color: cyan.opacity(0.4), radius: 12)

                    // HUD 四角括號
                    GeometryReader { geo in
                        Canvas { context, _ in
                            let w = geo.size.width
                            let h = geo.size.height
                            let leg: CGFloat = 14
                            let inset: CGFloat = 4
                            var p = Path()
                            // top-left
                            p.move(to: CGPoint(x: inset, y: inset + leg))
                            p.addLine(to: CGPoint(x: inset, y: inset))
                            p.addLine(to: CGPoint(x: inset + leg, y: inset))
                            // top-right
                            p.move(to: CGPoint(x: w - inset - leg, y: inset))
                            p.addLine(to: CGPoint(x: w - inset, y: inset))
                            p.addLine(to: CGPoint(x: w - inset, y: inset + leg))
                            // bottom-left
                            p.move(to: CGPoint(x: inset, y: h - inset - leg))
                            p.addLine(to: CGPoint(x: inset, y: h - inset))
                            p.addLine(to: CGPoint(x: inset + leg, y: h - inset))
                            // bottom-right
                            p.move(to: CGPoint(x: w - inset - leg, y: h - inset))
                            p.addLine(to: CGPoint(x: w - inset, y: h - inset))
                            p.addLine(to: CGPoint(x: w - inset, y: h - inset - leg))

                            context.drawLayer { layer in
                                layer.addFilter(.shadow(color: cyan.opacity(0.8), radius: 3))
                                layer.stroke(p, with: .color(cyan), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                            }
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: cyan.opacity(0.3), radius: 10)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func townhouseWireframe(floorCount: Int, floorH: CGFloat, depth: CGFloat, depthY: CGFloat) -> some View {
        let bWidth: CGFloat = 90
        let bX: CGFloat = 20
        let bH = CGFloat(floorCount) * floorH
        let labelX: CGFloat = 190

        return Canvas { context, size in
            let cyan = Self.cyanColor

            // Front face fill
            let frontRect = CGRect(x: bX, y: depthY, width: bWidth, height: bH)
            context.fill(Path(frontRect), with: .color(cyan.opacity(0.05)))

            // Right side fill
            var sideFill = Path()
            sideFill.move(to: CGPoint(x: bX + bWidth, y: depthY))
            sideFill.addLine(to: CGPoint(x: bX + bWidth + depth, y: 0))
            sideFill.addLine(to: CGPoint(x: bX + bWidth + depth, y: bH))
            sideFill.addLine(to: CGPoint(x: bX + bWidth, y: depthY + bH))
            sideFill.closeSubpath()
            context.fill(sideFill, with: .color(cyan.opacity(0.03)))

            // Top face fill
            var topFill = Path()
            topFill.move(to: CGPoint(x: bX, y: depthY))
            topFill.addLine(to: CGPoint(x: bX + depth, y: 0))
            topFill.addLine(to: CGPoint(x: bX + bWidth + depth, y: 0))
            topFill.addLine(to: CGPoint(x: bX + bWidth, y: depthY))
            topFill.closeSubpath()
            context.fill(topFill, with: .color(cyan.opacity(0.04)))

            // Wireframe outline with glow
            var wire = Path()
            wire.addRect(frontRect)
            wire.addPath(sideFill)
            wire.addPath(topFill)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: cyan.opacity(0.5), radius: 2))
                layer.stroke(wire, with: .color(cyan.opacity(0.65)), style: StrokeStyle(lineWidth: 1.2))
            }

            // Floor separator lines
            for i in 1..<floorCount {
                let y = depthY + CGFloat(i) * floorH
                var line = Path()
                line.move(to: CGPoint(x: bX, y: y))
                line.addLine(to: CGPoint(x: bX + bWidth, y: y))
                line.move(to: CGPoint(x: bX + bWidth, y: y))
                line.addLine(to: CGPoint(x: bX + bWidth + depth, y: y - depthY))
                context.stroke(line, with: .color(cyan.opacity(0.3)), style: StrokeStyle(lineWidth: 0.8))
            }

            // Glow scan line
            let scanY = depthY + bH * 0.5
            var scanLine = Path()
            scanLine.move(to: CGPoint(x: bX, y: scanY))
            scanLine.addLine(to: CGPoint(x: bX + bWidth, y: scanY))
            context.stroke(scanLine, with: .color(cyan.opacity(0.15)), style: StrokeStyle(lineWidth: 3))

            // 泛光連接線
            let startX = bX + bWidth + depth
            for i in 0..<floorCount {
                let y = depthY + CGFloat(i) * floorH + floorH / 2
                var conn = Path()
                conn.move(to: CGPoint(x: startX, y: y))
                conn.addLine(to: CGPoint(x: labelX - 4, y: y))
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: cyan.opacity(0.9), radius: 3))
                    layer.stroke(conn, with: .color(cyan.opacity(0.7)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                // 端點圓點
                let dot1 = Path(ellipseIn: CGRect(x: startX - 2, y: y - 2, width: 4, height: 4))
                let dot2 = Path(ellipseIn: CGRect(x: labelX - 6, y: y - 2, width: 4, height: 4))
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: cyan.opacity(0.9), radius: 3))
                    layer.fill(dot1, with: .color(cyan))
                    layer.fill(dot2, with: .color(cyan))
                }
            }
        }
        .frame(width: 260)
    }

    private func apartmentWireframe(userFloors: [FloorInfo], floorH: CGFloat, depth: CGFloat, depthY: CGFloat) -> some View {
        let bWidth: CGFloat = 90
        let bX: CGFloat = 20
        let totalVisible = max(userFloors.count, 8)
        let bH = CGFloat(totalVisible) * floorH
        let userStart = (totalVisible - userFloors.count) / 2
        let labelX: CGFloat = 190

        return Canvas { context, size in
            let cyan = Self.cyanColor

            // Building outline
            let frontRect = CGRect(x: bX, y: depthY, width: bWidth, height: bH)
            context.fill(Path(frontRect), with: .color(cyan.opacity(0.03)))

            var wire = Path()
            wire.addRect(frontRect)

            var side = Path()
            side.move(to: CGPoint(x: bX + bWidth, y: depthY))
            side.addLine(to: CGPoint(x: bX + bWidth + depth, y: 0))
            side.addLine(to: CGPoint(x: bX + bWidth + depth, y: bH))
            side.addLine(to: CGPoint(x: bX + bWidth, y: depthY + bH))
            side.closeSubpath()
            wire.addPath(side)

            var top = Path()
            top.move(to: CGPoint(x: bX, y: depthY))
            top.addLine(to: CGPoint(x: bX + depth, y: 0))
            top.addLine(to: CGPoint(x: bX + bWidth + depth, y: 0))
            top.addLine(to: CGPoint(x: bX + bWidth, y: depthY))
            top.closeSubpath()
            wire.addPath(top)

            context.drawLayer { layer in
                layer.addFilter(.shadow(color: cyan.opacity(0.4), radius: 2))
                layer.stroke(wire, with: .color(cyan.opacity(0.5)), style: StrokeStyle(lineWidth: 1))
            }

            // All floor lines (dimmed)
            for i in 1..<totalVisible {
                let y = depthY + CGFloat(i) * floorH
                var line = Path()
                line.move(to: CGPoint(x: bX, y: y))
                line.addLine(to: CGPoint(x: bX + bWidth, y: y))
                line.move(to: CGPoint(x: bX + bWidth, y: y))
                line.addLine(to: CGPoint(x: bX + bWidth + depth, y: y - depthY))
                context.stroke(line, with: .color(cyan.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5))
            }

            // Highlight user's floors
            for i in 0..<userFloors.count {
                let row = userStart + i
                let y = depthY + CGFloat(row) * floorH
                let highlight = CGRect(x: bX + 1, y: y + 1, width: bWidth - 2, height: floorH - 2)
                context.fill(Path(highlight), with: .color(cyan.opacity(0.12)))
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: cyan.opacity(0.6), radius: 2))
                    layer.stroke(Path(highlight), with: .color(cyan.opacity(0.75)), style: StrokeStyle(lineWidth: 1.5))
                }
            }

            // 泛光連接線
            let startX = bX + bWidth + depth
            for i in 0..<userFloors.count {
                let row = userStart + i
                let y = depthY + CGFloat(row) * floorH + floorH / 2
                var conn = Path()
                conn.move(to: CGPoint(x: startX, y: y))
                conn.addLine(to: CGPoint(x: labelX - 4, y: y))
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: cyan.opacity(0.9), radius: 3))
                    layer.stroke(conn, with: .color(cyan.opacity(0.7)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                let dot1 = Path(ellipseIn: CGRect(x: startX - 2, y: y - 2, width: 4, height: 4))
                let dot2 = Path(ellipseIn: CGRect(x: labelX - 6, y: y - 2, width: 4, height: 4))
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: cyan.opacity(0.9), radius: 3))
                    layer.fill(dot1, with: .color(cyan))
                    layer.fill(dot2, with: .color(cyan))
                }
            }
        }
        .frame(width: 260)
    }

    private func floorLabel(_ floor: FloorInfo) -> some View {
        let cyan = Self.cyanColor
        let fnText = floor.functions.map(\.rawValue).joined(separator: "與")

        return HStack(spacing: 6) {
            Text(floor.floorNumber.isEmpty ? "—" : floor.floorNumber)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(cyan)

            if !fnText.isEmpty {
                Text(fnText)
                    .font(.caption2)
                    .foregroundStyle(cyan.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(cyan.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(cyan.opacity(0.2), lineWidth: 0.8)
                )
        )
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private func utilityRow(icon: String, color: Color, number: String, owner: String, numberLabel: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(numberLabel).font(.caption2).foregroundStyle(.secondary)
                    Text(number.isEmpty ? "—" : number).font(.subheadline.weight(.medium))
                }
                if !owner.isEmpty {
                    Text("所有權人：\(owner)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    // MARK: - 輔助

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)
    }

    private func deleteEstate() {
        for m in estate.mortgageItems {
            if let linkedId = m.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for p in estate.paidItems {
            if let linkedId = p.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for ve in estate.variableExpenses {
            if let linkedId = ve.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for ins in estate.insuranceItems {
            if let linkedId = ins.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for asset in estate.propertyAssets {
            if let linkedId = asset.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        if let linkedId = estate.linkedExpenseId {
            expenseStore.expenses.removeAll { $0.id == linkedId }
        }
        store.deleteRealEstate(estate)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtWan(_ v: Double) -> String {
        String(format: "%g", v / 10000)
    }
}
