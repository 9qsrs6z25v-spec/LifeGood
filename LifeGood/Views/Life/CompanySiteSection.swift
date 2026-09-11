import SwiftUI

// MARK: - 公司廠區據點（v25.357）
//
// 放在「公司組織」目錄最下面。一家公司可能有很多廠（台積電 F12A／F14／F18……），
// 每個廠記下公司、廠名、地點與啟用年月；底下自動掛上「廠區」欄位對得上的重大決議，
// 於是每個廠就是一條由決議組成的歷史年線。
//
// 版型用 v25.354 的共用 ItemRow 模板：項目＝廠，子項目＝重大決議。

struct CompanySiteSection: View {
    @EnvironmentObject var lifeStore: LifeStore

    @State private var editing: CompanySite?
    @State private var showEditor = false
    /// 點子項目要開的決議（交給呼叫端決定怎麼開）
    var onOpenResolution: ((LifeMilestone, SideRoleResolution) -> Void)?

    /// 明確寫出 init：上面有 private 的 @State，合成的 memberwise init 會跟著變 private，
    /// 跨檔案（OrganizationView）叫不到。
    init(onOpenResolution: ((LifeMilestone, SideRoleResolution) -> Void)? = nil) {
        self.onOpenResolution = onOpenResolution
    }

    private let accent = Color.brown

    var body: some View {
        Section {
            if lifeStore.companySites.isEmpty {
                emptyRow
            } else {
                ForEach(lifeStore.companySitesSorted) { site in
                    siteRow(site)
                }
            }
            Button {
                editing = nil
                showEditor = true
            } label: {
                Label("新增廠區據點", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }
            if !lifeStore.unregisteredResolutionSites.isEmpty {
                unregisteredHint
            }
        } header: {
            HStack(spacing: 8) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(accent)
                Text("廠區據點")
                Text("\(lifeStore.companySites.count)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(accent.opacity(0.14), in: Capsule())
                    .foregroundStyle(accent)
            }
        } footer: {
            Text("記下每個廠的公司、地點與啟用年月。重大決議上填的「廠區」只要對得上廠名，就會自動掛在那個廠底下，點開就是那個廠的歷史年線。")
        }
        .sheet(isPresented: $showEditor) {
            CompanySiteEditor(site: editing) { saved in
                lifeStore.upsertCompanySite(saved)
            } onDelete: { id in
                lifeStore.deleteCompanySite(id: id)
            }
        }
    }

    // MARK: 列

    private func siteRow(_ site: CompanySite) -> some View {
        let pairs = lifeStore.resolutions(atSite: site)
        return ItemRow(
            chips: chips(site, resolutionCount: pairs.count),
            title: site.displayName,
            titleIsMuted: !site.isActive,
            preview: site.note,
            previewLineLimit: 2,
            disclosures: disclosures(pairs),
            disclosureLabel: "重大決議",
            disclosureColor: accent,
            onTap: { editing = site; showEditor = true },
            leading: {
                ItemIconDisc(icon: "building.2.fill",
                             color: site.isActive ? accent : .secondary,
                             iconSize: 14)
            }
        )
        .listRowInsets(EdgeInsets())
        .opacity(site.isActive ? 1 : 0.65)
    }

    private func chips(_ site: CompanySite, resolutionCount: Int) -> [ItemChip] {
        var chips: [ItemChip] = []
        if !site.company.trimmingCharacters(in: .whitespaces).isEmpty {
            chips.append(ItemChip(id: "company", text: site.company, color: .indigo))
        }
        chips.append(ItemChip(id: "start", text: site.startText, color: accent, icon: "calendar"))
        if let end = site.endText {
            chips.append(ItemChip(id: "end", text: "止 " + end, color: .secondary))
        }
        if let y = site.years, y >= 0.1 {
            chips.append(ItemChip(id: "years", text: String(format: "%.1f 年", y), color: .orange))
        }
        if !site.location.trimmingCharacters(in: .whitespaces).isEmpty {
            chips.append(ItemChip(id: "loc", text: site.location, color: .teal, icon: "mappin"))
        }
        if resolutionCount > 0 {
            chips.append(ItemChip(id: "res", text: "\(resolutionCount) 則決議", color: .purple))
        }
        return chips
    }

    private func disclosures(_ pairs: [(role: LifeMilestone, resolution: SideRoleResolution)]) -> [ItemDisclosure] {
        pairs.map { pair -> ItemDisclosure in
            let r = pair.resolution
            return ItemDisclosure(
                id: r.id.uuidString,
                badge: r.serialLabel.isEmpty ? nil : r.serialLabel,
                title: r.title,
                meta: SideRoleFormat.date(r.date),
                body: r.previewContent,
                actionLabel: onOpenResolution == nil ? nil : "開啟這筆決議",
                action: onOpenResolution == nil ? nil : { onOpenResolution?(pair.role, r) })
        }
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("還沒有廠區據點").font(.subheadline.weight(.semibold))
            Text("例如「台積電 F12A・新竹科學園區・2000/01」。建好之後，重大決議上填同樣的廠區名就會自動掛進來。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    /// 決議上出現過、但還沒建成據點的廠區字串
    private var unregisteredHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("決議裡有這些廠區還沒建成據點")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(lifeStore.unregisteredResolutionSites, id: \.self) { name in
                        Button {
                            editing = CompanySite(name: name)
                            showEditor = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                                Text(name).font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.13), in: Capsule())
                            .overlay(Capsule().stroke(Color.orange.opacity(0.25), lineWidth: 0.6))
                            .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 新增／編輯據點

struct CompanySiteEditor: View {
    @Environment(\.dismiss) private var dismiss

    let site: CompanySite?
    let onSave: (CompanySite) -> Void
    let onDelete: (UUID) -> Void

    @State private var company = ""
    @State private var name = ""
    @State private var location = ""
    @State private var startYear = Calendar.current.component(.year, from: Date())
    @State private var startMonth = Calendar.current.component(.month, from: Date())
    @State private var hasEnd = false
    @State private var endYear = Calendar.current.component(.year, from: Date())
    @State private var endMonth = Calendar.current.component(.month, from: Date())
    @State private var note = ""
    @State private var loaded = false

    private var years: [Int] {
        let thisYear = Calendar.current.component(.year, from: Date())
        return Array((1950...(thisYear + 5)).reversed())
    }
    private let months = Array(1...12)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("公司（例：台積電）", text: $company)
                    TextField("廠區／據點（例：F12A 十二廠）", text: $name)
                    TextField("地點（例：新竹科學園區）", text: $location)
                } footer: {
                    Text("「廠區／據點」要跟你在重大決議上填的廠區名一致，決議才掛得進來。")
                }

                Section("啟用年月") {
                    Picker("年", selection: $startYear) {
                        ForEach(years, id: \.self) { Text(String($0) + " 年").tag($0) }
                    }
                    Picker("月", selection: $startMonth) {
                        ForEach(months, id: \.self) { Text("\($0) 月").tag($0) }
                    }
                }

                Section {
                    Toggle("已結束（關廠／轉移／離開）", isOn: $hasEnd)
                    if hasEnd {
                        Picker("年", selection: $endYear) {
                            ForEach(years, id: \.self) { Text(String($0) + " 年").tag($0) }
                        }
                        Picker("月", selection: $endMonth) {
                            ForEach(months, id: \.self) { Text("\($0) 月").tag($0) }
                        }
                    }
                } header: {
                    Text("結束年月")
                } footer: {
                    Text("沒有結束年月＝仍在運作。已結束的據點會淡化排在清單裡，決議仍然掛在底下。")
                }

                Section("備註") {
                    TextField("備註（選填）", text: $note, axis: .vertical).lineLimit(1...4)
                }

                if let site {
                    Section {
                        Button(role: .destructive) {
                            onDelete(site.id)
                            dismiss()
                        } label: {
                            Label("刪除此據點", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    } footer: {
                        Text("只會刪掉這筆據點資料，掛在底下的重大決議本身不受影響。")
                    }
                }
            }
            .navigationTitle(site == nil ? "新增據點" : "編輯據點")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold()
                        .disabled(company.trimmingCharacters(in: .whitespaces).isEmpty
                                  && name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                guard let s = site else { return }
                company = s.company; name = s.name; location = s.location; note = s.note
                if s.startYear > 0 { startYear = s.startYear; startMonth = max(1, s.startMonth) }
                if let ey = s.endYear, ey > 0 {
                    hasEnd = true; endYear = ey; endMonth = max(1, s.endMonth ?? 1)
                }
            }
        }
    }

    private func save() {
        var s = site ?? CompanySite()
        s.company = company.trimmingCharacters(in: .whitespaces)
        s.name = name.trimmingCharacters(in: .whitespaces)
        s.location = location.trimmingCharacters(in: .whitespaces)
        s.startYear = startYear
        s.startMonth = startMonth
        s.endYear = hasEnd ? endYear : nil
        s.endMonth = hasEnd ? endMonth : nil
        s.note = note
        onSave(s)
        dismiss()
    }
}
