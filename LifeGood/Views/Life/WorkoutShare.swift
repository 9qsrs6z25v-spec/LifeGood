import SwiftUI
import UIKit
import PhotosUI
import ImageIO

// MARK: - 分享一趟運動（v25.555，健康 v5；health/judge.md §5.3、待決定 9；build/v5/brief.md §6 G3-3）
//
// 成果頁「⋯ › 分享」（剛跑完、一般模式都有，不擋訂閱）用 .sheet(item:) 打開（最外層 .appStores()）。
// 分享前一張小表單：預覽（就是要輸出的那一張圖，算好的 JPG 縮小放）＋「加上路線形狀」（預設關）＋「用我拍的照片當底」＋〔分享〕。
//
// 圖（WorkoutShareImage，一律淺色、寬 390、ImageExportLimits.safeScale、JPG 0.95、系統分享面板 ShareSheet）：
// • 上半：成果看板（MoneyBoardHeader＋MoneyBoardChrome：天空＋側面的路，**沒有路線形狀**）；有照片時換成照片（高 300 裁切、
//   下半一層黑色漸層、白字：左上日期膠囊、大字、名稱）。
// • 中間大字一行「河濱晨跑　5.2 公里・32:10・配速 6'11"」（WorkoutFacts.shareHeadline）。
// • 打開「加上路線形狀」：WorkoutFacts.shareRouteShape（頭尾各剪 200 公尺、換成 0…1 形狀），用卡面那支 WorkoutRoutePanel 畫
//   （紙底、不放地圖、沒有街名）；整條不到 600 公尺（剪完不到 200 公尺）不給開。
// • 每公里迷你條（成果頁「每公里」那幾行，最多 10 行；最後不滿一段不放）；右下小字「LifeGood」。
// • **不放**：幾點（日期只寫「10/15」：WorkoutFacts.shareDate；看板的 card.board.date 有幾點，不用）、地點、備註、地圖、
//   Apple 健康、要確認。檔名也只有日期（LifeGood_運動_20261015.jpg）。
// • 取捨：預設不放路線形狀（待決定 9：家門口不會跟著圖到處傳）；要放時頭尾剪掉、不放地圖底。照片用 PhotosPicker
//   （系統挑照片，不用相簿權限）；縮到長邊 1,600 像素重新編碼（ImageIO 縮圖），整張圖再用 ImageRenderer 重新畫成 JPG，
//   照片裡的 GPS 等 EXIF 不會跟著出去。
// • 預覽用算好的圖（ImageRenderer 出的 UIImage）縮小放：預覽跟分享出去的一模一樣；開關、換照片時重算（排到下一輪，
//   開關那一下先畫完；世代守門，連按只留最後一次）。〔分享〕時再算一次（不拿可能還沒更新的預覽）。
//
// [v25.557] 健康 v7（build/v7/brief.md §6 G4-6）：看板手寫跟著成果頁（破紀錄 New / record!）；右上膠囊破紀錄那一趟寫
// 「[star.fill] 最快 1 公里」（綠，同成果頁），**同一條路那顆不放、換回運動名**（路線名可能取自以前那幾趟的地點：分享圖不放地點）。
// build 傳 leave: store.workoutLeave（跟成果頁同一份；圖上沒有「這趟的收穫」，請假不影響圖）。路線形狀、地點的規則不變。

/// 分享前那張小表單（成果頁「⋯ › 分享」用 .sheet(item:) 打開、最外層 .appStores()）
struct WorkoutShareSheet: View {
    let sessionId: UUID

    init(sessionId: UUID) {
        self.sessionId = sessionId
    }

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    /// 加上路線形狀（預設關：待決定 9）
    @State private var withRoute = false
    @State private var photoItem: PhotosPickerItem?
    /// 當底的照片（已縮到長邊 1,600 像素）
    @State private var photo: UIImage?
    /// 選照片的世代：換一張、拿掉之後，還沒讀完的那一次回來時不蓋掉
    @State private var photoGen = 0
    @State private var photoLoading = false
    @State private var payload: StockCardSharePayload?
    /// 提示框：算圖失敗「圖沒做出來，再試一次」；照片讀不到「這張照片讀不到，換一張試試」（一個 .alert，字跟著換）
    @State private var failed = false
    @State private var failTitle = WorkoutShareSheet.renderFailedTitle
    /// 圖上要的字與數字（.task 裡算一次）
    @State private var content: WorkoutShareContent?
    /// 這一趟已經刪掉了
    @State private var missing = false
    /// 預覽：算好的那張圖
    @State private var preview: UIImage?
    @State private var previewGen = 0

    var body: some View {
        NavigationStack {
            page
                .navigationTitle("分享這一趟")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
        }
        .task { load() }
        .onChange(of: withRoute) { _, _ in renderPreview() }
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
        .sheet(item: $payload) { p in ShareSheet(items: p.items).appStores() }
        .alert(failTitle, isPresented: $failed) {
            Button("好", role: .cancel) {}
        }
    }

    // MARK: 畫面

    @ViewBuilder
    private var page: some View {
        if let c = content {
            ScrollView {
                form(c)
            }
            .background(Color(.systemGroupedBackground))
        } else if missing {
            missingView
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        }
    }

    private func form(_ c: WorkoutShareContent) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            previewCard(c)
            optionsCard(c)
            Text(footText(c))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 28)
    }

    /// 預覽：算好的那張圖縮小放（高最多 440，下面的選項一打開就看得到）
    @ViewBuilder
    private func previewCard(_ c: WorkoutShareContent) -> some View {
        if let img = preview {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
                .frame(maxWidth: .infinity, maxHeight: 440)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("分享圖預覽：" + c.headline)
        } else {
            previewPlaceholder
        }
    }

    private var previewPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .frame(height: 220)
            .overlay { ProgressView() }
            .accessibilityHidden(true)
    }

    private func optionsCard(_ c: WorkoutShareContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            routeRow(c)
            Divider()
                .padding(.leading, 14)
            photoRow
        }
        .modifier(FinanceCardChrome())
    }

    private func routeRow(_ c: WorkoutShareContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("加上路線形狀", isOn: $withRoute)
                .font(.subheadline.weight(.semibold))
                .tint(WorkoutPalette.go)
                .disabled(c.shape == nil)
            Text(routeNote(c))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var photoRow: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(photoTitle, systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 8)
            photoTrailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// 讀照片中轉圈；有照片時「拿掉照片」
    @ViewBuilder
    private var photoTrailing: some View {
        if photoLoading {
            ProgressView()
                .controlSize(.small)
        } else if photo != nil {
            Button {
                removePhoto()
            } label: {
                Text("拿掉照片")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.red)
            }
        }
    }

    private var missingView: some View {
        VStack(spacing: 14) {
            Text("這一趟已經刪掉了")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("關閉") { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                export()
            } label: {
                Text("分享").fontWeight(.semibold)
            }
            .disabled(content == nil)
        }
    }

    // MARK: 字

    private var photoTitle: String {
        photo == nil ? "用我拍的照片當底" : "換一張照片"
    }

    private func routeNote(_ c: WorkoutShareContent) -> String {
        guard c.shape != nil else { return "這一趟沒有路線，或太短（剪掉頭尾 200 公尺就沒了）。" }
        return "頭尾各 200 公尺會剪掉、不放地圖，看不出你從哪裡出發。"
    }

    private func footText(_ c: WorkoutShareContent) -> String {
        "圖上只寫日期（" + c.date + "），不寫幾點、不寫地點。"
    }

    // MARK: 動作

    /// 主執行緒算一次（WorkoutCardData.build 是 @MainActor；WorkoutFormat 的 DateFormatter 共用）
    private func load() {
        guard content == nil else { return }
        guard let s = lifeStore.workouts.first(where: { $0.id == sessionId }) else {
            missing = true
            return
        }
        content = WorkoutShareContent.make(s, store: lifeStore)
        // 第一張等表單滑上來再算（算圖約一兩百毫秒，跟滑上來的動畫擠在一起會頓一下）
        renderPreview(after: 0.35)
    }

    /// 選了照片：背景讀、縮到長邊 1,600 像素；世代對得上才寫（換一張、拿掉之後，舊的那一次回來不蓋掉）
    private func loadPhoto(_ item: PhotosPickerItem?) {
        photoGen += 1
        let gen = photoGen
        guard let item else {
            photoLoading = false
            return
        }
        photoLoading = true
        Task { @MainActor in
            let small = await WorkoutSharePhoto.load(item)
            guard gen == photoGen else { return }
            photoLoading = false
            guard let small, let image = UIImage(data: small) else {
                // 選取清掉：同一張再選一次 onChange 才會再跑（原本的照片、預覽不動）
                photoItem = nil
                fail(Self.photoFailedTitle)
                return
            }
            photo = image
            renderPreview()
        }
    }

    private func removePhoto() {
        photoGen += 1
        photoLoading = false
        photo = nil
        photoItem = nil
        renderPreview()
    }

    /// 重算預覽：排到下一輪（開關、選照片那一下先畫完）；連按只留最後一次
    private func renderPreview(after seconds: Double = 0) {
        previewGen += 1
        let gen = previewGen
        Task { @MainActor in
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            } else {
                await Task.yield()
            }
            guard gen == previewGen, let c = content else { return }
            let image = renderImage(c)
            guard gen == previewGen else { return }
            preview = image
        }
    }

    /// 算圖（照 VehicleDetailView.exportCardImage）：最外層 .appStores()、淺色；先量大小再定倍率；空白圖當失敗
    @MainActor
    private func renderImage(_ c: WorkoutShareContent) -> UIImage? {
        let art = WorkoutShareImage(content: c, withRoute: withRoute, photo: photo)
        let view = AnyView(art.appStores().environment(\.colorScheme, .light))
        let renderer = ImageRenderer(content: view)
        var measured = CGSize.zero
        renderer.render { size, _ in measured = size }
        renderer.scale = ImageExportLimits.safeScale(for: measured)
        guard let ui = renderer.uiImage, !ImageExportLimits.isBlank(ui) else { return nil }
        return ui
    }

    /// 〔分享〕：照現在的選項再算一次 → JPG 0.95 → 暫存檔「LifeGood_運動_20261015.jpg」（只有日期）→ 系統分享面板
    @MainActor
    private func export() {
        guard let c = content,
              let ui = renderImage(c),
              let data = ui.jpegData(compressionQuality: 0.95) else {
            fail(Self.renderFailedTitle)
            return
        }
        let base = PagedImageExporter.sanitizeFileName("LifeGood_運動_" + WorkoutShareFileName.day(c.day))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(base + ".jpg")
        do {
            try data.write(to: url, options: .atomic)
            payload = StockCardSharePayload(items: [url])
        } catch {
            fail(Self.renderFailedTitle)
        }
    }

    static let renderFailedTitle = "圖沒做出來，再試一次"
    static let photoFailedTitle = "這張照片讀不到，換一張試試"

    private func fail(_ title: String) {
        failTitle = title
        failed = true
    }
}

// MARK: - 圖上要的字與數字

/// 分享圖要的東西（.task 裡、主執行緒算一次；body 只畫）
private struct WorkoutShareContent {
    let sport: WorkoutSport
    /// 成果看板的頭部（label、big、line、greeting、seed；**date 不用**：那裡有幾點）
    let board: WorkoutCardData.Board
    let scene: WorkoutTrailScene
    /// 「每公里」「每 5 公里」
    let splitTitle: String
    /// 最多 10 行；最後不滿一段（note 有值）不放
    let splitRows: [WorkoutCardData.SplitRow]
    /// 頭尾各剪 200 公尺的路線形狀；沒有路線或太短是 nil（「加上路線形狀」不給開）
    let shape: WorkoutRouteShape?
    /// 「河濱晨跑　5.2 公里・32:10・配速 6'11"」
    let headline: String
    /// 「10/15」
    let date: String
    /// 檔名的日期
    let day: Date

    /// 最多幾行每公里
    static let maxSplitRows = 10

    @MainActor
    static func make(_ s: WorkoutSession, store: LifeStore) -> WorkoutShareContent {
        // Apple 健康三個都傳 false：圖上不放 Apple 健康那一列、不放要確認（build 的參數不改）
        let card = WorkoutCardData.build(session: s, sessions: store.workouts, prefs: store.workoutPrefs,
                                         bodyWeightKg: store.latestBodyWeightKg, hkEnabled: false,
                                         hkAvailable: false, hkCanWrite: false,
                                         ledger: store.workoutHealthLedger, leave: store.workoutLeave)
        let rows = (card.splits?.rows ?? []).filter { $0.note == nil }
        return WorkoutShareContent(sport: card.sport,
                                   board: card.board,
                                   scene: card.scene,
                                   splitTitle: card.splits?.title ?? "每公里",
                                   splitRows: Array(rows.prefix(maxSplitRows)),
                                   shape: WorkoutFacts.shareRouteShape(s),
                                   headline: WorkoutFacts.shareHeadline(s),
                                   date: WorkoutFacts.shareDate(s),
                                   day: s.date)
    }
}

/// 檔名的日期：西曆 yyyyMMdd（手機設成民國曆也不會寫成 115）
private enum WorkoutShareFileName {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    static func day(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

/// 當底的照片：長邊縮到 1,600 像素、重新編成 JPG（ImageIO 縮圖：不整張解碼；方向轉正；原本的 EXIF、GPS 不留）
private enum WorkoutSharePhoto {
    static let maxPixels = 1600

    /// 讀照片＋縮圖都在背景做（不卡畫面：loadTransferable 會把 iCloud 的原圖整張拉回來，同 PhotoImportCenter 的教訓）；
    /// 讀不到、不是圖回 nil。
    /// 寫法照 PhotoImportCenter（先宣告型別再 await .value：新 SDK 的 detached 多載才不會模稜兩可，v25.201 那次）
    static func load(_ item: PhotosPickerItem) async -> Data? {
        let out: Data? = await Task.detached(priority: .userInitiated) {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                return nil
            }
            return WorkoutSharePhoto.downscaled(data)
        }.value
        return out
    }

    static func downscaled(_ data: Data) -> Data? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.9)
    }
}

// MARK: - 圖

/// 要輸出的那一張（寬 390、淺色；最外層由 renderImage 包 .appStores()＋淺色）
private struct WorkoutShareImage: View {
    let content: WorkoutShareContent
    let withRoute: Bool
    let photo: UIImage?

    static let width: CGFloat = 390
    /// 左右各 16 之後的寬
    static let innerWidth: CGFloat = 358

    private var pal: TripBoardPalette { TripBoardPalette(.light) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            headlineText
            routePart
            splitsPart
            brand
        }
        .padding(16)
        .frame(width: Self.width)
        .background(Color(.systemGroupedBackground))
        // 分享圖的字一律標準大小（手機字放很大時圖不會被撐爆）
        .dynamicTypeSize(.large)
    }

    /// 沒照片：成果看板（天空＋側面的路）；有照片：照片當底
    @ViewBuilder
    private var header: some View {
        if let photo {
            WorkoutSharePhotoHeader(photo: photo, date: content.date, big: content.board.big,
                                    name: content.board.label, icon: content.sport.icon)
        } else {
            WorkoutShareBoard(content: content)
        }
    }

    private var headlineText: some View {
        Text(content.headline)
            .font(.title3.weight(.bold))
            .foregroundStyle(pal.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 打開「加上路線形狀」而且有形狀才畫：卡面那支 WorkoutRoutePanel（紙底、不放地圖）。
    /// compact：線畫滿整塊（一般卡面右邊留給斜切、上下留給膠囊與手寫字，放在這裡會偏左）
    @ViewBuilder
    private var routePart: some View {
        if withRoute, let shape = content.shape {
            WorkoutRoutePanel(shape: shape, theme: MoneyArtTheme.of(content.sport), dark: false, compact: true)
                .frame(width: Self.innerWidth, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var splitsPart: some View {
        if !content.splitRows.isEmpty {
            WorkoutShareSplits(title: content.splitTitle, rows: content.splitRows)
        }
    }

    private var brand: some View {
        HStack {
            Spacer()
            Text("LifeGood")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// 上半（沒照片）：成果看板的頭部（同成果頁 ① 的 MoneyBoardHeader，日期換成只有「10/15」）
private struct WorkoutShareBoard: View {
    let content: WorkoutShareContent

    private var pal: TripBoardPalette { TripBoardPalette(.light) }

    var body: some View {
        header
            .modifier(MoneyBoardChrome(pal: pal, corner: 22))
    }

    private var line: Text? {
        let l = content.board.line
        return l.runs.isEmpty ? nil : FinanceLineText.text(l, pal: pal)
    }

    /// [v25.557] 右上膠囊用成果頁那一顆（破紀錄「最快 1 公里」、或運動名）；同一條路那顆換回運動名（路線名可能是地點）
    private var usesBoardCapsule: Bool {
        !content.board.capsuleIsRoute && content.board.capsule != nil
    }

    private var capsuleText: String {
        usesBoardCapsule ? (content.board.capsule ?? content.sport.displayName) : content.sport.displayName
    }

    private var capsuleIcon: String {
        usesBoardCapsule ? (content.board.capsuleIcon ?? content.sport.icon) : content.sport.icon
    }

    private var capsuleTint: Color? {
        usesBoardCapsule ? content.board.capsuleTone?.color(pal) : nil
    }

    private var header: some View {
        let b = content.board
        return MoneyBoardHeader(
            date: content.date,
            dateIcon: content.sport.icon,
            capsule: capsuleText,
            capsuleIcon: capsuleIcon,
            capsuleTint: capsuleTint,
            label: b.label,
            big: b.big,
            bigTone: nil,
            line: line,
            greeting: b.greeting,
            scene: .runTrail(content.scene),
            band: 132,
            seed: b.seed)
    }
}

/// 上半（有照片）：照片高 300 裁切、下半黑色 0→0.55 漸層、白字（左上日期膠囊、大字、名稱）
private struct WorkoutSharePhotoHeader: View {
    let photo: UIImage
    let date: String
    let big: String
    let name: String
    let icon: String

    var body: some View {
        Color.clear
            .frame(height: 300)
            .overlay { photoLayer }
            .overlay { shade }
            .overlay(alignment: .topLeading) { dateChip }
            .overlay(alignment: .bottomLeading) { texts }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var photoLayer: some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFill()
    }

    private var shade: some View {
        LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                       startPoint: .center, endPoint: .bottom)
    }

    private var dateChip: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(date)
                .font(.footnote.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.35), in: Capsule())
        .padding(14)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(name)
                .font(.headline)
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
        .padding(16)
    }
}

/// 每公里迷你條：白卡，一行「1　███████▌　6'02"」（長條越長越快、五級色；字一律一般字色）
private struct WorkoutShareSplits: View {
    let title: String
    let rows: [WorkoutCardData.SplitRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TripBoardPalette(.light).ink)
            ForEach(rows) { r in
                WorkoutShareSplitRow(row: r)
            }
        }
        .padding(14)
        .frame(width: WorkoutShareImage.innerWidth, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 一行：寬固定（圖固定寬 390：358 − 左右 14 ＝ 330 ＝ 28＋8＋226＋8＋60），不用 GeometryReader
private struct WorkoutShareSplitRow: View {
    let row: WorkoutCardData.SplitRow

    static let labelWidth: CGFloat = 28
    static let barWidth: CGFloat = 226
    static let valueWidth: CGFloat = 60

    var body: some View {
        HStack(spacing: 8) {
            Text(row.label)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(TripBoardPalette(.light).label)
                .frame(width: Self.labelWidth, alignment: .trailing)
            bar
            Text(row.value)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(TripBoardPalette(.light).ink)
                .frame(width: Self.valueWidth, alignment: .trailing)
        }
        .lineLimit(1)
    }

    /// 0…1；壞掉的數字當 0（0＝不畫長條）
    private var fraction: CGFloat {
        let f = row.fraction
        guard f.isFinite else { return 0 }
        return CGFloat(min(1, max(0, f)))
    }

    private var barLength: CGFloat {
        fraction > 0 ? max(6, Self.barWidth * fraction) : 0
    }

    private var bar: some View {
        Capsule()
            .fill(WorkoutPalette.pace(row.level, dark: false))
            .frame(width: barLength, height: 10)
            .frame(width: Self.barWidth, alignment: .leading)
    }
}
