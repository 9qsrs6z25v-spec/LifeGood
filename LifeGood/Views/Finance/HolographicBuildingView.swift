import SwiftUI
import SceneKit

// MARK: - 全息 HUD 配色

private enum HoloPalette {
    static let cyan      = UIColor(red: 0.1, green: 0.85, blue: 0.95, alpha: 1.0)
    static let cyanSoft  = UIColor(red: 0.1, green: 0.85, blue: 0.95, alpha: 0.55)
    static let cyanGlow  = UIColor(red: 0.55, green: 0.92, blue: 1.0, alpha: 1.0)
    static let glass     = UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 0.45)
    static let bgDark    = Color(red: 0.008, green: 0.016, blue: 0.031)  // #020408
    static let neonCyan  = Color(red: 0.1, green: 0.85, blue: 0.95)
}

// MARK: - 主視圖

struct HolographicBuildingView: View {
    /// 使用者實際擁有的樓層
    let floors: [FloorInfo]
    /// 大樓型態：true = 公寓（會在使用者樓層上下加灰色虛擬樓層）
    let isApartment: Bool

    @State private var selectedFloorId: UUID?
    @State private var pulse: Double = 0.4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HStack(alignment: .center, spacing: 12) {
                BuildingSceneView(
                    floors: floors,
                    isApartment: isApartment,
                    selectedFloorId: $selectedFloorId
                )
                .frame(width: 170, height: 320)

                sideLabels
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(
            ZStack {
                HoloPalette.bgDark
                gridBackground
            }
        )
        .overlay(cornerBrackets.allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = 1.0
            }
        }
    }

    // MARK: 標題

    private var header: some View {
        HStack(spacing: 8) {
            Text("樓層資訊")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("(\(floors.count)層)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(HoloPalette.neonCyan.opacity(0.85))
            Circle()
                .fill(HoloPalette.neonCyan)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse)
                .shadow(color: HoloPalette.neonCyan.opacity(0.8), radius: 4)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: 側邊樓層標籤

    private var sideLabels: some View {
        VStack(spacing: 6) {
            ForEach(floors.sorted { floorOrder($0) > floorOrder($1) }) { f in
                FloorTagView(
                    floor: f,
                    isSelected: selectedFloorId == f.id,
                    onTap: {
                        withAnimation(.spring(duration: 0.25)) {
                            selectedFloorId = (selectedFloorId == f.id) ? nil : f.id
                        }
                    }
                )
            }
        }
    }

    private func floorOrder(_ f: FloorInfo) -> Int {
        let s = f.floorNumber.uppercased()
        if s.hasPrefix("B"), let n = Int(s.dropFirst()) { return -n }
        if s.hasSuffix("F"), let n = Int(s.dropLast()) { return n }
        if let n = Int(s) { return n }
        return 0
    }

    // MARK: 背景網格

    private var gridBackground: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 22
            let color = GraphicsContext.Shading.color(HoloPalette.neonCyan.opacity(0.06))
            for x in stride(from: 0, through: size.width, by: spacing) {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: color, lineWidth: 0.5)
            }
            for y in stride(from: 0, through: size.height, by: spacing) {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: color, lineWidth: 0.5)
            }
        }
    }

    // MARK: 角落準星

    private var cornerBrackets: some View {
        Canvas { ctx, size in
            let cyan = GraphicsContext.Shading.color(HoloPalette.neonCyan)
            let leg: CGFloat = 14
            let inset: CGFloat = 6
            var p = Path()
            // top-left
            p.move(to: CGPoint(x: inset, y: inset + leg))
            p.addLine(to: CGPoint(x: inset, y: inset))
            p.addLine(to: CGPoint(x: inset + leg, y: inset))
            // top-right
            p.move(to: CGPoint(x: size.width - inset - leg, y: inset))
            p.addLine(to: CGPoint(x: size.width - inset, y: inset))
            p.addLine(to: CGPoint(x: size.width - inset, y: inset + leg))
            // bottom-left
            p.move(to: CGPoint(x: inset, y: size.height - inset - leg))
            p.addLine(to: CGPoint(x: inset, y: size.height - inset))
            p.addLine(to: CGPoint(x: inset + leg, y: size.height - inset))
            // bottom-right
            p.move(to: CGPoint(x: size.width - inset - leg, y: size.height - inset))
            p.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
            p.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - leg))
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: HoloPalette.neonCyan.opacity(0.8), radius: 3))
                layer.stroke(p, with: cyan, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
    }
}

// MARK: - 切角樓層標籤

private struct FloorTagView: View {
    let floor: FloorInfo
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(floor.floorNumber.isEmpty ? "—" : floor.floorNumber)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? .white : Color.white.opacity(0.95))
                        .shadow(color: isSelected ? HoloPalette.neonCyan : .clear, radius: 4)
                    Spacer(minLength: 0)
                }
                if !floor.functions.isEmpty {
                    Text(floor.functions.map(\.rawValue).joined(separator: "・"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HoloPalette.neonCyan.opacity(isSelected ? 1.0 : 0.75))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChamferedRectangle().fill(
                isSelected
                    ? HoloPalette.neonCyan.opacity(0.35)
                    : Color.white.opacity(0.04)
            ))
            .overlay(
                ChamferedRectangle()
                    .stroke(
                        HoloPalette.neonCyan.opacity(isSelected ? 1.0 : 0.4),
                        lineWidth: isSelected ? 1.4 : 0.7
                    )
                    .shadow(color: HoloPalette.neonCyan.opacity(isSelected ? 0.7 : 0), radius: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 切角矩形：左上 + 右下倒角，營造科技 HUD 感
private struct ChamferedRectangle: Shape {
    var chamfer: CGFloat = 6
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + chamfer, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - chamfer))
        p.addLine(to: CGPoint(x: rect.maxX - chamfer, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + chamfer))
        p.closeSubpath()
        return p
    }
}

// MARK: - SceneKit 3D 建築

struct BuildingSceneView: UIViewRepresentable {
    let floors: [FloorInfo]
    let isApartment: Bool
    @Binding var selectedFloorId: UUID?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.scene = context.coordinator.makeScene(floors: floors, isApartment: isApartment)

        // 拖曳手勢：使用者旋轉建築
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)

        // 點擊：選擇樓層
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        context.coordinator.sceneView = view
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.applySelection(selectedFloorId)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject {
        let parent: BuildingSceneView
        weak var sceneView: SCNView?
        private var floorNodes: [(id: UUID, node: SCNNode, edges: SCNNode)] = []
        private var rootNode: SCNNode?
        private var rotationAction: SCNAction?
        private var lastPanX: CGFloat = 0

        init(parent: BuildingSceneView) {
            self.parent = parent
        }

        // MARK: 場景組裝

        func makeScene(floors: [FloorInfo], isApartment: Bool) -> SCNScene {
            let scene = SCNScene()

            // 相機：放在地面之下、向上仰望，營造由地面往上看的視角
            let camNode = SCNNode()
            camNode.camera = SCNCamera()
            camNode.camera?.fieldOfView = 50
            camNode.position = SCNVector3(0, -4, 16)
            camNode.eulerAngles = SCNVector3(Float.pi / 8, 0, 0)  // 鏡頭仰角 22.5°
            scene.rootNode.addChildNode(camNode)

            // 環境光（暗一點讓 emission 突出）
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.color = UIColor(white: 0.08, alpha: 1.0)
            scene.rootNode.addChildNode(ambient)

            // 建築主體 root（用於旋轉）
            let buildingRoot = SCNNode()
            buildingRoot.position = SCNVector3(0, 0, 0)
            scene.rootNode.addChildNode(buildingRoot)
            self.rootNode = buildingRoot

            // 排序使用者樓層（B1 → B2 → 1F → 2F …）
            let sorted = floors.sorted { Self.order($0) < Self.order($1) }

            // 計算總視覺樓層數（公寓至少 8 層）
            let userCount = sorted.count
            let totalCount = isApartment ? max(userCount, 8) : userCount
            let userStartIndex = isApartment ? (totalCount - userCount) / 2 : 0

            // 樓層幾何
            let floorWidth: CGFloat = 5.0
            let floorDepth: CGFloat = 4.0
            let floorHeight: CGFloat = 0.95
            let gap: CGFloat = 0.1

            let totalH = CGFloat(totalCount) * (floorHeight + gap) - gap
            let baseY = -totalH / 2 + floorHeight / 2

            // 為每一層建立節點
            for i in 0..<totalCount {
                let isUserFloor = i >= userStartIndex && i < userStartIndex + userCount
                let userFloor: FloorInfo? = isUserFloor ? sorted[i - userStartIndex] : nil
                let y = baseY + CGFloat(i) * (floorHeight + gap)

                // 立方體本體（半透明深色玻璃）
                let box = SCNBox(width: floorWidth, height: floorHeight,
                                 length: floorDepth, chamferRadius: 0.02)
                box.firstMaterial?.diffuse.contents = HoloPalette.glass
                box.firstMaterial?.transparency = isUserFloor ? 0.35 : 0.15
                box.firstMaterial?.emission.contents = isUserFloor
                    ? HoloPalette.cyan.withAlphaComponent(0.18)
                    : HoloPalette.cyanSoft.withAlphaComponent(0.04)
                box.firstMaterial?.specular.contents = HoloPalette.cyan
                box.firstMaterial?.lightingModel = .physicallyBased
                let boxNode = SCNNode(geometry: box)
                boxNode.position = SCNVector3(0, Float(y), 0)
                buildingRoot.addChildNode(boxNode)

                // 邊框（12 條霓虹細管）
                let edgeColor = isUserFloor ? HoloPalette.cyanGlow : HoloPalette.cyanSoft
                let edgeOpacity: Float = isUserFloor ? 1.0 : 0.35
                let edges = makeEdgeWireframe(width: floorWidth, height: floorHeight,
                                              depth: floorDepth, color: edgeColor)
                edges.opacity = CGFloat(edgeOpacity)
                edges.position = SCNVector3(0, Float(y), 0)
                buildingRoot.addChildNode(edges)

                if let userFloor {
                    floorNodes.append((id: userFloor.id, node: boxNode, edges: edges))
                }
            }

            // 掃描線（細長的發光平面，從底部往上動）
            let scanGeo = SCNPlane(width: floorWidth + 0.4, height: 0.05)
            scanGeo.firstMaterial?.diffuse.contents = HoloPalette.cyanGlow
            scanGeo.firstMaterial?.emission.contents = HoloPalette.cyanGlow
            scanGeo.firstMaterial?.isDoubleSided = true
            let scanNode = SCNNode(geometry: scanGeo)
            scanNode.opacity = 0.7
            scanNode.position = SCNVector3(0, Float(baseY - 0.3), 0)
            buildingRoot.addChildNode(scanNode)

            // 掃描動畫（4 秒一輪）
            let upDist = totalH + 0.6
            let scanUp = SCNAction.move(by: SCNVector3(0, Float(upDist), 0), duration: 3.0)
            scanUp.timingMode = .easeOut
            let fadeOut = SCNAction.fadeOpacity(to: 0, duration: 0.5)
            let reset = SCNAction.run { [weak scanNode] _ in
                scanNode?.position = SCNVector3(0, Float(baseY - 0.3), 0)
                scanNode?.opacity = 0.7
            }
            let wait = SCNAction.wait(duration: 1.5)
            let cycle = SCNAction.sequence([scanUp, fadeOut, reset, wait])
            scanNode.runAction(SCNAction.repeatForever(cycle))

            // 建築物保持正立（不傾斜、不自動旋轉）；視覺仰望感由相機角度提供。
            // 仍保留 self.rotationAction = nil，方便手勢結束後也不會自動恢復轉動。
            buildingRoot.eulerAngles = SCNVector3(0, 0, 0)
            self.rotationAction = nil

            // 全息地板：放在建築底部，浮空略低於最低層
            let groundY = Float(baseY) - Float(floorHeight) / 2 - 0.15
            let ground = makeHologramGround(buildingWidth: floorWidth,
                                            buildingDepth: floorDepth,
                                            groundY: groundY)
            buildingRoot.addChildNode(ground)

            return scene
        }

        /// 全息地板：圓形漸層 + 同心發光環 + 向外輻射的網格線
        private func makeHologramGround(buildingWidth: CGFloat,
                                        buildingDepth: CGFloat,
                                        groundY: Float) -> SCNNode {
            let group = SCNNode()
            group.position = SCNVector3(0, groundY, 0)

            let groundRadius = max(buildingWidth, buildingDepth) * 1.3

            // 主地板：暗藍盤
            let disc = SCNCylinder(radius: groundRadius, height: 0.04)
            disc.firstMaterial?.diffuse.contents = UIColor(red: 0.04, green: 0.08, blue: 0.14, alpha: 0.9)
            disc.firstMaterial?.emission.contents = HoloPalette.cyan.withAlphaComponent(0.06)
            disc.firstMaterial?.specular.contents = HoloPalette.cyan
            disc.firstMaterial?.lightingModel = .physicallyBased
            let discNode = SCNNode(geometry: disc)
            group.addChildNode(discNode)

            // 三圈同心霓虹環
            for (idx, ratio) in [0.45, 0.75, 1.0].enumerated() {
                let r = groundRadius * CGFloat(ratio)
                let ring = SCNTorus(ringRadius: r, pipeRadius: 0.018)
                let alpha: CGFloat = idx == 2 ? 1.0 : (idx == 1 ? 0.7 : 0.45)
                ring.firstMaterial?.emission.contents = HoloPalette.cyanGlow.withAlphaComponent(alpha)
                ring.firstMaterial?.diffuse.contents = HoloPalette.cyanGlow.withAlphaComponent(alpha)
                ring.firstMaterial?.lightingModel = .constant
                let ringNode = SCNNode(geometry: ring)
                ringNode.position = SCNVector3(0, 0.025, 0)
                group.addChildNode(ringNode)
            }

            // 輻射狀的格子細線（8 條）
            for i in 0..<8 {
                let angle = Float(i) * Float.pi / 4
                let line = SCNCylinder(radius: 0.008, height: groundRadius * 2)
                line.firstMaterial?.emission.contents = HoloPalette.cyanSoft
                line.firstMaterial?.diffuse.contents = HoloPalette.cyanSoft
                line.firstMaterial?.lightingModel = .constant
                let lineNode = SCNNode(geometry: line)
                lineNode.position = SCNVector3(0, 0.022, 0)
                lineNode.eulerAngles = SCNVector3(0, angle, Float.pi / 2)
                lineNode.opacity = 0.3
                group.addChildNode(lineNode)
            }

            return group
        }

        /// 用 12 條 cylinder 做出方塊邊框
        private func makeEdgeWireframe(width: CGFloat, height: CGFloat,
                                       depth: CGFloat, color: UIColor) -> SCNNode {
            let group = SCNNode()
            let radius: CGFloat = 0.018
            let hw = width / 2
            let hh = height / 2
            let hd = depth / 2

            // 12 條邊：4 條水平 X、4 條水平 Z、4 條垂直 Y
            // 水平 X（4 條）— 沿 X 軸
            let xCorners: [(y: CGFloat, z: CGFloat)] = [
                (hh, hd), (hh, -hd), (-hh, hd), (-hh, -hd)
            ]
            for c in xCorners {
                let cyl = makeEdgeCylinder(length: width, radius: radius, color: color)
                cyl.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                cyl.position = SCNVector3(0, Float(c.y), Float(c.z))
                group.addChildNode(cyl)
            }
            // 水平 Z（4 條）— 沿 Z 軸
            let zCorners: [(x: CGFloat, y: CGFloat)] = [
                (hw, hh), (hw, -hh), (-hw, hh), (-hw, -hh)
            ]
            for c in zCorners {
                let cyl = makeEdgeCylinder(length: depth, radius: radius, color: color)
                cyl.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                cyl.position = SCNVector3(Float(c.x), Float(c.y), 0)
                group.addChildNode(cyl)
            }
            // 垂直 Y（4 條）— 沿 Y 軸
            let yCorners: [(x: CGFloat, z: CGFloat)] = [
                (hw, hd), (hw, -hd), (-hw, hd), (-hw, -hd)
            ]
            for c in yCorners {
                let cyl = makeEdgeCylinder(length: height, radius: radius, color: color)
                cyl.position = SCNVector3(Float(c.x), 0, Float(c.z))
                group.addChildNode(cyl)
            }
            return group
        }

        private func makeEdgeCylinder(length: CGFloat, radius: CGFloat, color: UIColor) -> SCNNode {
            let cyl = SCNCylinder(radius: radius, height: length)
            cyl.firstMaterial?.diffuse.contents = color
            cyl.firstMaterial?.emission.contents = color
            cyl.firstMaterial?.lightingModel = .constant
            cyl.firstMaterial?.writesToDepthBuffer = true
            return SCNNode(geometry: cyl)
        }

        private static func order(_ f: FloorInfo) -> Int {
            let s = f.floorNumber.uppercased()
            if s.hasPrefix("B"), let n = Int(s.dropFirst()) { return -n }
            if s.hasSuffix("F"), let n = Int(s.dropLast()) { return n }
            if let n = Int(s) { return n }
            return 0
        }

        // MARK: 手勢

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = sceneView, let root = rootNode else { return }
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                lastPanX = 0
                root.removeAction(forKey: "auto-rotate")
            case .changed:
                let dx = Float(translation.x - lastPanX) * 0.012
                root.eulerAngles.y += dx
                lastPanX = translation.x
            case .ended, .cancelled:
                // 慣性轉一段時間後恢復自轉
                let velocity = gesture.velocity(in: view).x
                let coast = SCNAction.rotateBy(
                    x: 0, y: CGFloat(velocity) * 0.0005, z: 0,
                    duration: 1.0)
                coast.timingMode = .easeOut
                let resume = SCNAction.run { [weak root, weak self] _ in
                    guard let root, let self else { return }
                    if let auto = self.rotationAction {
                        root.runAction(auto, forKey: "auto-rotate")
                    }
                }
                root.runAction(SCNAction.sequence([coast, resume]))
            default:
                break
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = sceneView else { return }
            let p = gesture.location(in: view)
            let hits = view.hitTest(p, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let hit = hits.first else {
                Task { @MainActor in self.parent.selectedFloorId = nil }
                return
            }
            // 找到對應的使用者樓層
            for entry in floorNodes {
                if hit.node == entry.node {
                    let id = entry.id
                    Task { @MainActor in
                        self.parent.selectedFloorId = (self.parent.selectedFloorId == id) ? nil : id
                    }
                    return
                }
            }
        }

        // MARK: 套用選取狀態

        func applySelection(_ id: UUID?) {
            for entry in floorNodes {
                let isSel = entry.id == id
                let box = entry.node.geometry as? SCNBox
                box?.firstMaterial?.emission.contents = isSel
                    ? HoloPalette.cyanGlow.withAlphaComponent(0.55)
                    : HoloPalette.cyan.withAlphaComponent(0.18)
                box?.firstMaterial?.transparency = isSel ? 0.6 : 0.35
                entry.edges.opacity = isSel ? 1.0 : 0.85
                // 邊框脈動
                entry.edges.removeAction(forKey: "pulse")
                if isSel {
                    let up = SCNAction.fadeOpacity(to: 1.0, duration: 0.5)
                    let down = SCNAction.fadeOpacity(to: 0.7, duration: 0.5)
                    entry.edges.runAction(SCNAction.repeatForever(SCNAction.sequence([down, up])),
                                          forKey: "pulse")
                }
            }
        }
    }
}
