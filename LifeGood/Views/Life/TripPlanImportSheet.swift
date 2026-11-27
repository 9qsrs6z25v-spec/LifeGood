import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

// MARK: - [v25.595] 匯入旅遊規劃本
//
// 三步：① 〔複製給 AI 的說明〕貼給 ChatGPT／Claude／Gemini，跟它說想去哪；
//       ② AI 回的那一段複製回來，〔貼上〕（或〔從檔案〕選 .txt）；
//       ③ 看一眼預覽，〔匯入〕：App 一站一站問 Apple 地圖找位置（找不到的之後在那一站選），做好打開那份行程。
// 格式見 TripPlanImport。

struct TripPlanImportSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    /// 匯入好了：交給清單打開那份行程
    let onImported: (UUID) -> Void

    @State private var wish = ""
    @State private var text = ""
    @State private var copied = false
    @State private var showFilePicker = false
    @State private var fileError: String?
    /// 正在找位置：第幾站／共幾站（nil＝沒在找）
    @State private var progress: (done: Int, total: Int)?
    @State private var importTask: Task<Void, Never>?
    /// 按了〔先不找了，直接匯入〕：已經找到的留著、其他的不找了
    @State private var skipLookup = false
    /// 預覽（停手 0.25 秒才讀一次：每打一個字都重讀，長的一份會卡）
    @State private var result: TripPlanImport.Result?
    /// result 是照哪一份字讀的（還沒讀到最新的字時，不要先跳「看不出行程」）
    @State private var parsedFor = ""

    private let accent = TripDayPalette.color(0)

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d (E) HH:mm"; return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                stepOne
                stepTwo
                if let r = result {
                    preview(r)
                } else if parsedFor == text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Label("看不出行程：至少要有一行「景點：…」或「行程：…」。可以把 AI 回的整段原封不動貼上來。",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("匯入旅遊規劃本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        // 找位置找到一半按〔取消〕：什麼都不存（Task 被取消，最後那段不會存）
                        importTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("匯入") { startImport() }
                        .disabled(result == nil || progress != nil)
                }
            }
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: [.plainText, .text, .utf8PlainText],
                          allowsMultipleSelection: false) { picked in
                readFile(picked)
            }
            .alert("讀不到這個檔案", isPresented: Binding(get: { fileError != nil },
                                                    set: { if !$0 { fileError = nil } })) {
                Button("好") { fileError = nil }
            } message: {
                Text(fileError ?? "")
            }
            .overlay { if let p = progress { locatingOverlay(p) } }
            .task(id: text) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                result = t.isEmpty ? nil : TripPlanImport.parse(t)
                parsedFor = text
            }
            .onChange(of: wish) { _, _ in copied = false }
            .interactiveDismissDisabled(progress != nil)
        }
    }

    // MARK: ① 給 AI

    private var stepOne: some View {
        Section {
            TextField("想去哪、幾天、誰去（選填）", text: $wish, axis: .vertical)
                .lineLimit(1...3)
            Button {
                UIPasteboard.general.string = TripPlanImport.aiGuide(wish: wish)
                withAnimation { copied = true }
            } label: {
                Label(copied ? "已複製，貼給 AI 就好" : "複製給 AI 的說明",
                      systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
            }
        } header: {
            Text("① 請 AI 幫你排")
        } footer: {
            Text("說明裡有格式和範例。貼到 ChatGPT、Claude 或 Gemini，它會照格式回一整段。")
        }
    }

    // MARK: ② 貼回來

    private var stepTwo: some View {
        Section {
            HStack {
                Button {
                    if let s = UIPasteboard.general.string { text = s }
                } label: {
                    Label("貼上", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button {
                    showFilePicker = true
                } label: {
                    Label("從檔案", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                if !text.isEmpty {
                    Spacer()
                    Button(role: .destructive) { text = "" } label: {
                        Label("清掉", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("行程：福岡三天兩夜\n出發：2026/12/20 08:30\n第1天\n景點：太宰府天滿宮\n停留：90")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("② 把 AI 回的那一段貼回來")
        }
    }

    // MARK: ③ 預覽

    @ViewBuilder
    private func preview(_ r: TripPlanImport.Result) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(r.plan.displayTitle).font(.headline)
                Text(summary(r)).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(r.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("③ 看一眼再匯入")
        }
        ForEach(dayGroups(r), id: \.day) { g in
            Section("第 \(g.day) 天") {
                ForEach(g.stops, id: \.id) { s in
                    stopRow(s, hasHint: r.hints[s.id] != nil)
                }
            }
        }
        if !r.plan.packingItems.isEmpty || !r.plan.souvenirItems.isEmpty {
            Section("行前準備") {
                if !r.plan.packingItems.isEmpty {
                    Text("攜帶：" + r.plan.packingItems.map(itemText).joined(separator: "、"))
                        .font(.caption)
                }
                if !r.plan.souvenirItems.isEmpty {
                    Text("伴手禮：" + r.plan.souvenirItems.map(itemText).joined(separator: "、"))
                        .font(.caption)
                }
            }
        }
    }

    private func stopRow(_ s: TripStop, hasHint: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: s.isOvernight ? "bed.double.fill" : (s.isMustVisit ? "star.fill" : "mappin.circle.fill"))
                .foregroundStyle(s.isOvernight ? Color.indigo : (s.isMustVisit ? Color.orange : accent))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name.isEmpty ? "（沒有名稱）" : s.name).font(.subheadline.weight(.semibold))
                Text(stopMeta(s)).font(.caption2).foregroundStyle(.secondary)
                if !s.address.isEmpty {
                    Text(s.address).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
    }

    private struct DayGroup { let day: Int; let stops: [TripStop] }

    private func dayGroups(_ r: TripPlanImport.Result) -> [DayGroup] {
        var out: [DayGroup] = []
        for (i, s) in r.plan.stops.enumerated() {
            let d = i < r.stopDays.count ? r.stopDays[i] : 1
            if let last = out.last, last.day == d {
                out[out.count - 1] = DayGroup(day: d, stops: last.stops + [s])
            } else {
                out.append(DayGroup(day: d, stops: [s]))
            }
        }
        return out
    }

    private func summary(_ r: TripPlanImport.Result) -> String {
        var parts = ["出發 " + Self.dayFmt.string(from: r.plan.startDate), r.plan.travelMode.rawValue,
                     "\(r.plan.stops.count) 站"]
        let nights = r.plan.stops.filter(\.isOvernight).count
        if nights > 0 { parts.append("住 \(nights) 晚") }
        return parts.joined(separator: "・")
    }

    private func stopMeta(_ s: TripStop) -> String {
        var parts: [String] = []
        if let a = s.arrivalOverride { parts.append(Self.timeFmt.string(from: a) + " 抵達") }
        if s.isOvernight {
            parts.append("過夜")
            if let c = s.checkOutTime { parts.append(Self.timeFmt.string(from: c) + " 退房") }
        } else {
            parts.append("停留 \(s.dwellMinutes) 分")
        }
        if let m = s.legModeOverride { parts.append(m.rawValue) }
        if let p = s.phone, !p.isEmpty { parts.append("☎︎ " + p) }
        if s.isMustVisit { parts.append("必去") }
        return parts.joined(separator: "・")
    }

    private func itemText(_ i: TripChecklistItem) -> String {
        var t = i.name
        if i.quantity > 1 { t += " ×\(i.quantity)" }
        if !i.forWhom.isEmpty { t += "（給\(i.forWhom)）" }
        return t
    }

    // MARK: 匯入

    private func locatingOverlay(_ p: (done: Int, total: Int)) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView(value: Double(p.done), total: Double(max(1, p.total)))
                    .frame(width: 200)
                Text("正在 Apple 地圖找位置… \(p.done) / \(p.total)")
                    .font(.footnote)
                Button("先不找了，直接匯入") { skipLookup = true }
                    .font(.footnote.weight(.semibold))
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
        }
    }

    private func startImport() {
        // 用現在的字再讀一次（預覽是停手 0.25 秒才更新的，剛貼上就按也對）
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard progress == nil, !t.isEmpty, let r = TripPlanImport.parse(t) else { return }
        let total = r.plan.stops.count
        progress = (0, total)
        skipLookup = false
        importTask = Task { @MainActor in
            var plan = r.plan
            var near: CLLocationCoordinate2D?
            for i in plan.stops.indices {
                if skipLookup || Task.isCancelled { break }
                progress = (i, total)
                let hint = r.hints[plan.stops[i].id]
                if let f = await TripPlanImport.locate(plan.stops[i], hint: hint, near: near) {
                    plan.stops[i].latitude = f.latitude
                    plan.stops[i].longitude = f.longitude
                    if plan.stops[i].address.trimmingCharacters(in: .whitespaces).isEmpty { plan.stops[i].address = f.address }
                    if (plan.stops[i].phone ?? "").trimmingCharacters(in: .whitespaces).isEmpty, let ph = f.phone {
                        plan.stops[i].phone = ph
                    }
                    near = CLLocationCoordinate2D(latitude: f.latitude, longitude: f.longitude)
                } else if let hint {
                    plan.stops[i].latitude = hint.latitude
                    plan.stops[i].longitude = hint.longitude
                }
            }
            // 找到一半按了〔先不找了〕：已經找到的留著，其他的之後在那一站選。按〔取消〕就什麼都不存
            if Task.isCancelled { return }
            lifeStore.upsertTripPlan(plan)
            progress = nil
            onImported(plan.id)
            dismiss()
        }
    }

    private func readFile(_ picked: Result<[URL], Error>) {
        guard case .success(let urls) = picked, let url = urls.first else {
            if case .failure(let e) = picked { fileError = e.localizedDescription }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            fileError = "沒辦法打開「\(url.lastPathComponent)」。"
            return
        }
        if let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
            text = s
        } else {
            fileError = "「\(url.lastPathComponent)」不是文字檔（要 .txt）。"
        }
    }
}
