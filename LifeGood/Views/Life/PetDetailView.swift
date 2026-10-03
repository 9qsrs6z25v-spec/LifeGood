import SwiftUI
import Charts

// MARK: - 寵物詳情
//
// [v25.387] 從寵物履歷點一隻毛小孩進來看到的頁面。
//
// 資料一律沿用 FamilyMember 既有的欄位，沒有另開儲存空間：
//   • childRecords → 疫苗／驅蟲、就醫健檢、體重、過敏、紀念時刻
//   • dailyRecords → 餵食與睡眠
//   • familyPhotos → 相簿
// 編輯表單直接重用 ChildRecordEditorSheet / DailyRecordEditorSheet /
// FamilyAlbumPhotoEditor，三者都只吃一個 FamilyMember.id，寵物與小孩沒有差別。
// 好處是照片的競態守衛、院所自動完成、快速選取膠囊這些既有功能一併拿到；
// 代價是少數欄位帶著育兒的用語（成長紀錄會多問一個身高），這裡用章節標題與
// 說明文字把語意轉過來，不去動那三張表單免得影響兒女頁。

struct PetDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let petId: UUID

    @State private var addingRecordType: PetRecordKind?
    @State private var editingRecord: ChildRecord?
    @State private var addingDailyType: PetDailyKind?
    @State private var editingDaily: DailyRecord?
    @State private var addingPhoto = false
    @State private var editingPhoto: FamilyAlbumPhoto?
    @State private var removing: PetRemoval?
    @State private var showEditProfile = false
    @State private var showPremiumAlert = false
    @State private var heroAppeared = false

    /// 明確初始化：本型別有 private @State，合成的 memberwise init 會是 private，
    /// PetResumeView 跨檔案建不出來。
    init(petId: UUID) {
        self.petId = petId
    }

    private var pet: FamilyMember? {
        lifeStore.familyMembers.first { $0.id == petId }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let shortFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "M/d"; return f
    }()

    private var accent: Color {
        PetPalette.color(for: pet?.pet?.species ?? .other)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let p = pet {
                    ScrollView {
                        VStack(spacing: 14) {
                            heroCard(p)
                            profileCard(p)
                            weightCard(p)
                            recordsCard(p)
                            dailyCard(p)
                            albumCard(p)
                        }
                        .padding(.vertical)
                    }
                } else {
                    // 在別的地方被刪掉了 → 自動關閉
                    Color.clear.onAppear { dismiss() }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("寵物詳情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編輯") { gated { showEditProfile = true } }.bold()
                }
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .sheet(isPresented: $showEditProfile) {
                if let p = pet { AddMilestoneView(editingFamily: p) }
            }
            .sheet(item: $addingRecordType) { kind in
                ChildRecordEditorSheet(childId: petId, type: kind.recordType)
            }
            .sheet(item: $editingRecord) { rec in
                ChildRecordEditorSheet(childId: petId, type: rec.type, editing: rec)
            }
            .sheet(item: $addingDailyType) { kind in
                DailyRecordEditorSheet(childId: petId, type: kind.dailyType)
            }
            .sheet(item: $editingDaily) { rec in
                DailyRecordEditorSheet(childId: petId, type: rec.type, editing: rec)
            }
            .sheet(isPresented: $addingPhoto) {
                FamilyAlbumPhotoEditor(memberId: petId, editing: nil)
            }
            .sheet(item: $editingPhoto) { photo in
                FamilyAlbumPhotoEditor(memberId: petId, editing: photo)
            }
            .confirmationDialog("刪除", isPresented: Binding(
                get: { removing != nil },
                set: { if !$0 { removing = nil } }
            ), presenting: removing) { target in
                Button("刪除", role: .destructive) {
                    perform(target)
                    removing = nil
                }
                Button("取消", role: .cancel) { removing = nil }
            } message: { target in
                Text(target.message)
            }
        }
    }

    // MARK: 英雄卡

    private func heroCard(_ p: FamilyMember) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                    Image(systemName: p.pet?.species.icon ?? "pawprint.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(p.petDisplayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(p.pet?.summaryLine ?? "尚未填寫物種資料")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }

            Rectangle().fill(Color.white.opacity(0.20)).frame(height: 0.5)

            HStack(spacing: 0) {
                heroKpi("年齡", text: p.petAgeText ?? "未知", icon: "birthday.cake.fill")
                heroKpi("換算人類", text: humanAgeText(p), icon: "person.fill")
                heroKpi("在一起", text: p.petTogetherText ?? "未知", icon: "house.fill")
                heroKpi("紀錄", text: "\(p.childRecords.count)", icon: "list.bullet.rectangle.portrait.fill")
            }
        }
        .padding(16)
        .background(
            ZStack {
                LinearGradient(colors: [accent, accent.opacity(0.62)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.white.opacity(0.10)).blur(radius: 18)
                    .frame(width: 140, height: 140).offset(x: 110, y: -60)
                Circle().fill(Color.white.opacity(0.08)).blur(radius: 12)
                    .frame(width: 90, height: 90).offset(x: -120, y: 50)
                Circle().fill(Color.white.opacity(0.06)).blur(radius: 8)
                    .frame(width: 55, height: 55).offset(x: 60, y: 62)
                LinearGradient(colors: [Color.white.opacity(0.18), .clear],
                               startPoint: .top, endPoint: .center)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: accent.opacity(0.28), radius: 12, x: 0, y: 6)
        .padding(.horizontal)
        .opacity(heroAppeared ? 1 : 0)
        .offset(y: heroAppeared ? 0 : 16)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { heroAppeared = true }
        }
    }

    private func heroKpi(_ title: String, text: String, icon: String) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.55)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    /// 只有貓狗算得出來；其他物種顯示「—」，不要編一個數字出來
    private func humanAgeText(_ p: FamilyMember) -> String {
        guard let y = p.petHumanAgeYears else { return "—" }
        return "約 \(y) 歲"
    }

    // MARK: 基本資料

    private func profileCard(_ p: FamilyMember) -> some View {
        card(title: "基本資料", icon: "pawprint.fill", color: accent, count: nil, action: nil) {
            VStack(spacing: 0) {
                infoRow("物種", p.pet?.speciesLabel ?? "未填寫")
                infoRow("品種", valueOrDash(p.pet?.breed))
                infoRow("性別", p.pet?.gender.rawValue ?? "未知")
                infoRow("結紮", (p.pet?.isNeutered ?? false) ? "已結紮" : "未結紮")
                infoRow("生日", p.birthday.map { Self.dateFmt.string(from: $0) } ?? "未填寫")
                infoRow("到家日", p.pet?.adoptionDate.map { Self.dateFmt.string(from: $0) } ?? "未填寫")
                infoRow("晶片號碼", valueOrDash(p.pet?.microchipId))
                infoRow("毛色特徵", valueOrDash(p.pet?.colorMark), isLast: true)
            }
        }
    }

    private func valueOrDash(_ s: String?) -> String {
        let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "未填寫" : t
    }

    private func infoRow(_ label: String, _ value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 66, alignment: .leading)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(value == "未填寫" ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            if !isLast { Divider().padding(.leading, 16) }
        }
    }

    // MARK: 體重曲線

    /// 體重存在成長紀錄（ChildRecord.type == .growth）的 weightKg 裡。
    /// 兩點以上才畫線——一個點的折線圖看不出任何東西。
    private func weightCard(_ p: FamilyMember) -> some View {
        let points = p.childRecords
            .filter { $0.type == .growth && ($0.weightKg ?? 0) > 0 }
            .sorted { $0.date < $1.date }
        return Group {
            if points.count >= 2 {
                card(title: "體重變化", icon: "scalemass.fill", color: .teal,
                     count: nil, action: nil) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(weightSummary(points))
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        Chart {
                            ForEach(points) { rec in
                                LineMark(x: .value("日期", rec.date),
                                         y: .value("體重", rec.weightKg ?? 0))
                                    .foregroundStyle(Color.teal)
                                    .interpolationMethod(.catmullRom)
                                PointMark(x: .value("日期", rec.date),
                                          y: .value("體重", rec.weightKg ?? 0))
                                    .foregroundStyle(Color.teal)
                            }
                        }
                        .chartYAxisLabel("kg")
                        .frame(height: 160)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                    }
                }
            }
        }
    }

    private func weightSummary(_ points: [ChildRecord]) -> String {
        guard let first = points.first, let last = points.last,
              let w0 = first.weightKg, let w1 = last.weightKg else { return "" }
        let delta = w1 - w0
        let sign = delta > 0 ? "＋" : (delta < 0 ? "－" : "±")
        let head = String(format: "目前 %.1f kg", w1)
        let tail = sign + String(format: "%.1f kg", abs(delta))
        return head + "・自 " + Self.shortFmt.string(from: first.date) + " 起 " + tail
    }

    // MARK: 紀錄

    private func recordsCard(_ p: FamilyMember) -> some View {
        // 一次分桶，避免每種類型各 filter 一輪
        var byKind: [ChildRecordType: [ChildRecord]] = [:]
        for rec in p.childRecords where PetRecordKind.supports(rec.type) {
            byKind[rec.type, default: []].append(rec)
        }
        let total = byKind.values.reduce(0) { $0 + $1.count }
        return card(title: "健康與生活紀錄", icon: "heart.text.square.fill",
                    color: .pink, count: total, action: nil) {
            VStack(spacing: 0) {
                ForEach(PetRecordKind.allCases) { kind in
                    let items = (byKind[kind.recordType] ?? []).sorted { $0.date > $1.date }
                    kindGroup(kind, items: items)
                }
                if total == 0 {
                    hint("按各分類右邊的＋開始記錄。體重填在「體重紀錄」裡，累積兩筆以上就會自動畫成曲線。")
                }
            }
        }
    }

    @ViewBuilder
    private func kindGroup(_ kind: PetRecordKind, items: [ChildRecord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: kind.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(kind.color)
                Text(kind.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(kind.color)
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(kind.color.opacity(0.13)).foregroundStyle(kind.color)
                        .clipShape(Capsule())
                }
                Spacer()
                Button { gated { addingRecordType = kind } } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(kind.color)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            ForEach(items) { rec in
                recordRow(rec, kind: kind)
            }
        }
    }

    private func recordRow(_ rec: ChildRecord, kind: PetRecordKind) -> some View {
        Button {
            gated { editingRecord = rec }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(kind.color.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: kind.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(kind.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(recordTitle(rec))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(recordMeta(rec))
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("編輯") { gated { editingRecord = rec } }
            Button("刪除", role: .destructive) { gated { removing = .record(rec) } }
        }
    }

    private func recordTitle(_ rec: ChildRecord) -> String {
        let t = rec.title.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { return t }
        let d = rec.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.isEmpty ? rec.type.rawValue : d
    }

    private func recordMeta(_ rec: ChildRecord) -> String {
        var parts: [String] = [Self.dateFmt.string(from: rec.date)]
        if let w = rec.weightKg, w > 0 { parts.append(String(format: "%.1f kg", w)) }
        if let t = rec.temperatureC, t > 0 { parts.append(String(format: "%.1f°C", t)) }
        if let dose = rec.dose?.trimmingCharacters(in: .whitespaces), !dose.isEmpty {
            parts.append(dose)
        }
        let detail = rec.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty && !rec.title.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(detail)
        }
        return parts.joined(separator: "・")
    }

    // MARK: 日常紀錄

    /// 只開放「食物」與「睡眠」。DailyRecordType 還有一個「喝奶」，那是育兒欄位
    /// （問奶粉品牌與 ml 數），對寵物不適用，所以不放進來。
    private func dailyCard(_ p: FamilyMember) -> some View {
        var byKind: [DailyRecordType: [DailyRecord]] = [:]
        for rec in p.dailyRecords where PetDailyKind.supports(rec.type) {
            byKind[rec.type, default: []].append(rec)
        }
        let total = byKind.values.reduce(0) { $0 + $1.count }
        return card(title: "日常紀錄", icon: "sun.max.fill", color: .orange,
                    count: total, action: nil) {
            VStack(spacing: 0) {
                ForEach(PetDailyKind.allCases) { kind in
                    // 只顯示最近 5 筆，太長的清單在這種摘要卡裡沒人會捲
                    let items = (byKind[kind.dailyType] ?? [])
                        .sorted { $0.date > $1.date }
                        .prefix(5)
                    dailyGroup(kind, items: Array(items))
                }
                if total == 0 {
                    hint("記下今天餵了什麼、睡了多久。這一區只列最近 5 筆。")
                }
            }
        }
    }

    @ViewBuilder
    private func dailyGroup(_ kind: PetDailyKind, items: [DailyRecord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: kind.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(kind.color)
                Text(kind.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(kind.color)
                Spacer()
                Button { gated { addingDailyType = kind } } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(kind.color)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            ForEach(items) { rec in
                Button {
                    gated { editingDaily = rec }
                } label: {
                    HStack(spacing: 10) {
                        Text(Self.shortFmt.string(from: rec.date))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(kind.color)
                            .frame(width: 38, alignment: .leading)
                        Text(dailyText(rec))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("編輯") { gated { editingDaily = rec } }
                    Button("刪除", role: .destructive) { gated { removing = .daily(rec) } }
                }
            }
        }
    }

    private func dailyText(_ rec: DailyRecord) -> String {
        switch rec.type {
        case .food:
            let name = (rec.foodName ?? "").trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "餵食" : name
        case .sleep:
            guard let end = rec.sleepEnd else { return "睡眠" }
            let mins = max(0, Int(end.timeIntervalSince(rec.date) / 60))
            let h = mins / 60, m = mins % 60
            return h == 0 ? "睡了 \(m) 分鐘" : (m == 0 ? "睡了 \(h) 小時" : "睡了 \(h) 小時 \(m) 分")
        case .milk:
            // 理論上不會出現（這頁不提供新增），但舊資料或兒女頁轉過來的還是要顯示
            let ml = rec.mlAmount.map { String(format: "%.0f ml", $0) } ?? ""
            return ml.isEmpty ? "喝奶" : ml
        }
    }

    // MARK: 相簿

    private func albumCard(_ p: FamilyMember) -> some View {
        let photos = p.familyPhotos.sorted { $0.date > $1.date }
        return card(title: "相簿", icon: "photo.on.rectangle.angled",
                    color: .indigo, count: photos.count,
                    action: { gated { addingPhoto = true } }) {
            VStack(spacing: 0) {
                if photos.isEmpty {
                    hint("按右上的＋加一張照片，記下牠今天的樣子。")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos) { photo in
                                photoTile(photo)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                    }
                }
            }
        }
    }

    private func photoTile(_ photo: FamilyAlbumPhoto) -> some View {
        Button {
            gated { editingPhoto = photo }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 104, height: 104)
                    if let url = photo.photoURL,
                       let data = try? Data(contentsOf: url),
                       let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 104, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(photo.title.isEmpty ? Self.shortFmt.string(from: photo.date) : photo.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 104, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("編輯") { gated { editingPhoto = photo } }
            Button("刪除", role: .destructive) { gated { removing = .photo(photo) } }
        }
    }

    // MARK: 共用卡片外框

    private func card<Content: View>(title: String, icon: String, color: Color,
                                     count: Int?, action: (() -> Void)?,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [color, color.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title).font(.subheadline.weight(.semibold))
                if let c = count {
                    Text("\(c)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(color.opacity(0.13)).foregroundStyle(color)
                        .clipShape(Capsule())
                }
                Spacer()
                if let action {
                    Button(action: action) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            content()
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 14)
    }

    // MARK: 訂閱守衛

    /// 付費功能在未訂閱時僅供閱覽（同 ChildDetailView 既有作法）：
    /// 未訂閱就不執行動作、改跳訂閱提示。
    private func gated(_ action: () -> Void) {
        if subscription.isPremium { action() } else { showPremiumAlert = true }
    }

    // MARK: 刪除

    private func perform(_ target: PetRemoval) {
        lifeStore.mutateFamilyMember(petId) { m in
            switch target {
            case .record(let rec):
                if let name = rec.photoFileName { ChildRecord.deletePhoto(name) }
                m.childRecords.removeAll { $0.id == rec.id }
            case .daily(let rec):
                m.dailyRecords.removeAll { $0.id == rec.id }
            case .photo(let photo):
                if let name = photo.photoFileName { FamilyAlbumPhoto.deletePhoto(name) }
                m.familyPhotos.removeAll { $0.id == photo.id }
            }
        }
    }
}

// MARK: - 寵物適用的紀錄分類

/// ChildRecordType 的寵物子集 + 寵物語言的標題。
/// 儲存欄位仍是原本的 ChildRecordType，只是不把「教育里程碑」「興趣才藝」
/// 這種對毛小孩沒有意義的分類端出來。
enum PetRecordKind: String, CaseIterable, Identifiable {
    case vaccination, medical, weight, allergy, memorable

    var id: String { rawValue }

    var recordType: ChildRecordType {
        switch self {
        case .vaccination: return .vaccination
        case .medical:     return .medical
        case .weight:      return .growth
        case .allergy:     return .allergy
        case .memorable:   return .memorable
        }
    }

    var title: String {
        switch self {
        case .vaccination: return "疫苗與驅蟲"
        case .medical:     return "就醫與健檢"
        case .weight:      return "體重紀錄"
        case .allergy:     return "過敏"
        case .memorable:   return "紀念時刻"
        }
    }

    var icon: String {
        switch self {
        case .vaccination: return "syringe"
        case .medical:     return "cross.case.fill"
        case .weight:      return "scalemass.fill"
        case .allergy:     return "allergens"
        case .memorable:   return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .vaccination: return .green
        case .medical:     return .red
        case .weight:      return .teal
        case .allergy:     return .orange
        case .memorable:   return .purple
        }
    }

    static func supports(_ type: ChildRecordType) -> Bool {
        allCases.contains { $0.recordType == type }
    }
}

/// DailyRecordType 的寵物子集（不含「喝奶」，那是育兒欄位）
enum PetDailyKind: String, CaseIterable, Identifiable {
    case food, sleep

    var id: String { rawValue }

    var dailyType: DailyRecordType {
        self == .food ? .food : .sleep
    }

    var title: String { self == .food ? "餵食" : "睡眠" }
    var icon: String { self == .food ? "carrot.fill" : "moon.zzz.fill" }
    var color: Color { self == .food ? .orange : .indigo }

    static func supports(_ type: DailyRecordType) -> Bool {
        type == .food || type == .sleep
    }
}

/// 刪除確認對話框的目標
enum PetRemoval: Identifiable {
    case record(ChildRecord)
    case daily(DailyRecord)
    case photo(FamilyAlbumPhoto)

    var id: UUID {
        switch self {
        case .record(let r): return r.id
        case .daily(let r):  return r.id
        case .photo(let p):  return p.id
        }
    }

    var message: String {
        switch self {
        case .record:
            return "要刪除這筆紀錄嗎？附在上面的照片也會一起刪掉，這個動作沒辦法復原。"
        case .daily:
            return "要刪除這筆日常紀錄嗎？這個動作沒辦法復原。"
        case .photo:
            return "要刪除這張照片嗎？照片檔案會一併從裝置上移除，這個動作沒辦法復原。"
        }
    }
}
