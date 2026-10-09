import SwiftUI
import MediaPlayer

// MARK: - 動態相簿（v25.484）
//
// 使用者要求：相本右上角一顆播放鍵，把所有照片配上轉場與溫馨的音樂直接播。
//
// ── 音樂能做到什麼、不能做到什麼 ──
// 這裡放的是**你自己音樂 App 裡的歌**（MPMusicPlayerController.applicationMusicPlayer
// ＋系統的歌曲選擇器）。Apple Music 訂閱者加進資料庫的歌也在裡面。
//
// 做不到的是「在 App 裡直接搜尋整個 Apple Music 曲庫」：那要 MusicKit，
// 而 MusicKit 跟 WeatherKit 一樣要先去 Apple Developer 後台替這個 App ID 開能力、
// 重新簽章才會生效（v25.447 的天氣就是卡在這件事）。想要的話再開，程式這邊
// 換成 MusicKit 不難，但沒開之前換過去只會變成一個永遠授權失敗的功能。
//
// 也不能內建背景音樂：有版權的曲子不能打包進 App。

/// 幻燈片的音樂（使用者自己資料庫裡的歌）。
///
/// 選過的歌記在 @AppStorage，下次直接接著用——每次播都要重選的話，
/// 這個功能只會被用一次。
final class SlideshowMusic: NSObject, ObservableObject {
    static let shared = SlideshowMusic()

    @Published private(set) var isPlaying = false
    @Published private(set) var trackTitle: String?
    /// 上次選的那首還在不在。**存成值而不是每次算**——畫面上的進度線會高頻重畫，
    /// 每次重畫都去查一次音樂資料庫等於每秒查十次。
    @Published private(set) var hasRemembered = false
    /// [v25.486] 正在播的這首的檔案位置。分析節拍要讀波形，只有這裡拿得到。
    ///
    /// **Apple Music 串流下載的歌是 nil**——那是加密檔案，任何 App 都讀不到波形
    /// （讀得到就等於能側錄）。那種情況只能靠手動跟拍。
    @Published private(set) var assetURL: URL?
    /// 佇列還在準備（setQueue 是非同步的）
    @Published private(set) var isPreparing = false
    /// 播放失敗的原因。有值就要讓使用者看見。
    @Published private(set) var lastError: String?

    private var verifyTask: Task<Void, Never>?

    private let player = MPMusicPlayerController.applicationMusicPlayer
    private let lastIdKey = "slideshow_music_persistent_id"

    private override init() { super.init() }

    /// 重新確認上次那首還在不在（資料庫可能被刪掉了）。開始播放時叫一次就好。
    func refreshRemembered() {
        hasRemembered = rememberedItem() != nil
    }

    func playRemembered() {
        guard let item = rememberedItem() else { return }
        play(MPMediaItemCollection(items: [item]))
    }

    /// [v25.487] 選好歌卻一直沒聲音的修法。
    ///
    /// 兩個原因疊在一起：
    ///
    /// 1. **setQueue 是非同步的**。接著馬上呼叫 play() 時佇列還沒備妥，
    ///    系統就把這次播放要求丟掉——而且不會報錯，什麼都不會發生。
    ///    正確做法是等 prepareToPlay 的回呼回來再 play。
    ///
    /// 2. **我多設了一個 AVAudioSession**。系統音樂播放器的聲音是媒體服務
    ///    程序發出來的，它自己管音訊工作階段；App 這邊再把 .playback 設起來
    ///    並 setActive(true)，等於跟它搶路由，有機會直接把音樂按停。
    ///    這個 App 的幻燈片本來就沒有自己的聲音，不需要工作階段——整段拿掉。
    ///    （靜音開關也不用擔心：音樂播放器本來就不受靜音開關影響。）
    func play(_ collection: MPMediaItemCollection) {
        let first = collection.items.first
        trackTitle = first?.title
        assetURL = first?.assetURL
        lastError = nil
        isPreparing = true
        if let id = first?.persistentID {
            UserDefaults.standard.set(String(id), forKey: lastIdKey)
        }

        player.setQueue(with: collection)
        player.repeatMode = .all          // 照片還在播，歌放完要接下去
        player.shuffleMode = .off
        player.prepareToPlay { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isPreparing = false
                if let error {
                    self.isPlaying = false
                    self.lastError = "這首歌放不出來：" + error.localizedDescription
                    return
                }
                self.player.play()
                self.isPlaying = true
                self.verifyStarted(item: first)
            }
        }
    }

    /// 按了播放之後真的有在播嗎。
    ///
    /// 沒有回報的失敗是最糟的失敗——使用者看了十幾張照片才發現沒聲音，
    /// 而畫面上的音符圖示還亮著。1.2 秒後確認一次播放狀態，沒播就講原因。
    private func verifyStarted(item: MPMediaItem?) {
        verifyTask?.cancel()
        verifyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            guard player.playbackState != .playing else {
                lastError = nil
                return
            }
            isPlaying = false
            if item?.isCloudItem == true {
                lastError = "這首在 iCloud 音樂資料庫裡，裝置上沒有檔案，所以放不出來。"
                    + "到音樂 App 把它下載起來，或換一首已經下載的。"
            } else {
                lastError = "音樂沒有播起來。到音樂 App 確認這首放得動，或換一首試試。"
            }
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func resume() {
        // 佇列還在準備就別插隊——prepareToPlay 的回呼會自己接著播
        guard trackTitle != nil, !isPreparing else { return }
        player.play()
        isPlaying = true
    }

    /// 歌曲目前播到第幾秒。卡點就是靠它跟節拍網格對時。
    var currentTime: Double { player.currentPlaybackTime }

    func stop() {
        verifyTask?.cancel()
        player.stop()
        isPlaying = false
        isPreparing = false
        lastError = nil
        trackTitle = nil
        assetURL = nil
    }

    private func rememberedItem() -> MPMediaItem? {
        guard MPMediaLibrary.authorizationStatus() == .authorized,
              let raw = UserDefaults.standard.string(forKey: lastIdKey),
              let id = UInt64(raw) else { return nil }
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(
            value: NSNumber(value: id), forProperty: MPMediaItemPropertyPersistentID))
        return query.items?.first
    }
}

/// 系統的歌曲選擇器
struct MusicPickerSheet: UIViewControllerRepresentable {
    let onPicked: (MPMediaItemCollection) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = true
        picker.showsCloudItems = true
        picker.prompt = "挑一首配這本相簿的歌"
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let parent: MusicPickerSheet
        init(_ parent: MusicPickerSheet) { self.parent = parent }

        func mediaPicker(_ mediaPicker: MPMediaPickerController,
                         didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            parent.onPicked(mediaItemCollection)
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            parent.onCancel()
        }
    }
}

// MARK: - 幻燈片本體

/// 主題（v25.497）。
///
/// 一套主題不是換配色，是換一整個世界：背景、前景、相框、落款、照片怎麼出現，
/// 全部都要照那個世界的物理重做一次。所以這裡只會有少數幾套，
/// 每一套都做到站得住為止。
enum SlideshowTheme: String, CaseIterable, Identifiable {
    /// 水墨山水（v25.489～25.496）
    case ink
    /// 賽博龐克（v25.497）
    case cyber

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ink:   return "水墨山水"
        case .cyber: return "賽博龐克"
        }
    }

    var detail: String {
        switch self {
        case .ink:   return "宣紙、遠山、落梅，照片一張張落在紙上"
        case .cyber: return "夜雨、霓虹、濕地面，照片懸在街上的全像面板裡"
        }
    }

    var icon: String {
        switch self {
        case .ink:   return "mountain.2.fill"
        case .cyber: return "building.2.fill"
        }
    }

    /// 底是亮的還是暗的。字、膠囊、罩子全看這一個。
    var isLight: Bool { self == .ink }

    /// 壓在背景上的文字顏色
    var onBackdrop: Color {
        isLight ? Color(red: 0.13, green: 0.13, blue: 0.15) : .white
    }

    /// 膠囊按鈕的底色
    var chipFill: Color {
        isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.16)
    }

    /// 上下兩條漸層罩的顏色。亮底要用白罩——黑罩會把整幅畫壓成灰的；
    /// 暗底反過來，白罩會讓夜景整個發灰。
    var veil: Color { isLight ? .white : .black }

    /// 開場那張紙（或面板）的底色
    var sheet: Color {
        isLight ? Color(red: 0.96, green: 0.95, blue: 0.93)
                : Color(red: 0.04, green: 0.04, blue: 0.07)
    }
}

/// 播放順序（v25.495）。
///
/// 三種順序講的是三種看相簿的方式，不是三種排序演算法：
/// 逐站是「再走一次這趟行程」，新增時間是「照拍的先後重看一遍」，
/// 隨機是「讓我忘掉的那幾張自己冒出來」。
enum SlideshowOrder: String, CaseIterable, Identifiable {
    /// 照相簿畫面上的分組順序（依地點或月份攤平）
    case station
    /// 照檔案進到手機裡的先後
    case added
    /// 隨機
    case shuffled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .station:  return "逐站播放"
        case .added:    return "依新增時間"
        case .shuffled: return "隨機"
        }
    }

    var detail: String {
        switch self {
        case .station:  return "照相簿上的分組，一站一站走完"
        case .added:    return "照存進手機的先後，重走一次時間軸"
        case .shuffled: return "每次播的順序都不一樣"
        }
    }

    var icon: String {
        switch self {
        case .station:  return "signpost.right.fill"
        case .added:    return "clock.fill"
        case .shuffled: return "shuffle"
        }
    }
}

struct PhotoSlideshowView: View {
    let items: [AlbumPhotoItem]
    var title: String = "相本"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var music = SlideshowMusic.shared

    @State private var index = 0
    @State private var image: UIImage?
    @State private var playing = true
    @State private var showChrome = true
    @State private var ticker: Task<Void, Never>?
    @State private var chromeTask: Task<Void, Never>?
    @State private var showMusicPicker = false
    @State private var musicDenied = false
    /// 這一張已經播了多久（底下那條細線）
    @State private var elapsed: Double = 0

    // [v25.486] 卡點
    /// 這首歌的節拍網格（分析或跟拍得來）
    @State private var grid: BeatGrid?
    @State private var analyzing = false
    /// 手動跟拍的點擊時間
    @State private var tapTimes: [Date] = []
    /// 每踩到一拍就 +1，用來驅動輕微的脈動
    @State private var beatTick = 0
    /// 節拍信心不足或沒波形可讀時，給使用者一句說明
    @State private var beatNote: String?

    /// 拼貼牆上目前有哪幾張
    @State private var wall: [WallPhoto] = []
    /// 跟拍模式（一個可以連點的大區塊）
    @State private var tapMode = false

    // [v25.495] 播放順序
    /// 記住上次選的，下次開啟直接是那一個
    @AppStorage("slideshow_order") private var orderRaw = SlideshowOrder.station.rawValue
    /// 排好順序的播放清單。畫面上跑的是這個，不是 items。
    @State private var queue: [AlbumPhotoItem] = []
    /// 還停在開場畫面（還沒按「開始播放」）
    @State private var started = false

    private var order: SlideshowOrder {
        SlideshowOrder(rawValue: orderRaw) ?? .station
    }

    /// 載圖的觸發條件：第幾張、開始了沒、清單是哪一份
    private var taskKey: String {
        "\(index)#\(started)#\(queue.count)#\(queue.first?.id ?? "")"
    }

    // [v25.497] 顏色跟著主題走。
    //
    // v25.490 曾經把這兩個寫死成亮底的值，理由是「背景永遠是宣紙」——
    // 當時只有一套主題，那是對的。現在有第二套暗底的，就得還給主題決定。
    @AppStorage("slideshow_theme") private var themeRaw = SlideshowTheme.ink.rawValue

    private var theme: SlideshowTheme {
        SlideshowTheme(rawValue: themeRaw) ?? .ink
    }

    /// [v25.498] 背景的動畫要不要停。
    ///
    /// 使用者回報「截圖之後，截圖編輯畫面會卡」。原因是背景真的一直在算圖：
    /// TimelineView(.periodic) 只要還在畫面上就不會停，App 退到背景、
    /// 或被系統畫面（截圖編輯器正是）蓋住，底下兩個全螢幕 Canvas 照樣
    /// 每秒各重畫二十四次。
    ///
    /// 挑歌的時候也停——那時候整幅景被全螢幕的歌單蓋住，一幀都看不到。
    private var paused: Bool { scenePhase != .active || showMusicPicker }

    private var onBackdrop: Color { theme.onBackdrop }
    private var chipFill: Color { theme.chipFill }

    /// 要不要跟著拍子換照片
    @AppStorage("slideshow_beat_sync") private var beatSync = true
    /// 幾拍換一張；0＝依速度自動換算
    @AppStorage("slideshow_beats_per_slide") private var beatsSetting = 0

    /// 每張停留幾秒。記起來，下次照用。
    @AppStorage("slideshow_seconds") private var seconds: Double = 3.5

    private static let speeds: [(label: String, value: Double)] = [
        ("慢", 5.0), ("中", 3.5), ("快", 2.2)
    ]

    private var current: AlbumPhotoItem? {
        guard queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    /// 這張照片存進手機的時間。
    ///
    /// 不能用 AlbumPhotoItem.date——那是「紀錄的日期」（使用者填的那一天），
    /// 同一天補進去的十張照片 date 全部一樣，排不出先後。檔案本身的建立時間
    /// 才是真正的新增順序。
    private static func addedAt(_ item: AlbumPhotoItem) -> Date {
        let values = try? item.url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? item.date
    }

    private func ordered(_ order: SlideshowOrder) -> [AlbumPhotoItem] {
        switch order {
        case .station:
            return items
        case .added:
            // 先把時間讀出來再排。在比較函式裡讀檔的話，sort 會呼叫它
            // O(n log n) 次，每一次都碰一下磁碟——幾百張照片就卡住了。
            return items.map { ($0, Self.addedAt($0)) }
                .sorted { $0.1 < $1.1 }
                .map { $0.0 }
        case .shuffled:
            return items.shuffled()
        }
    }

    // MARK: 卡點

    /// 現在有沒有在跟拍子走
    private var synced: Bool { beatSync && grid != nil && music.isPlaying }

    /// 幾拍換一張。
    ///
    /// 自動模式不是直接拿「秒數 ÷ 一拍」四捨五入——那會算出 7 拍、11 拍這種
    /// 聽起來很彆扭的數字。音樂是兩拍一組的，所以只挑 2／4／8／16，
    /// 取最接近使用者設定速度的那一個。
    private var beatsPerSlide: Int {
        if beatsSetting > 0 { return beatsSetting }
        guard let grid else { return 4 }
        let raw = seconds / grid.interval
        return [2, 4, 8, 16].min { abs(Double($0) - raw) < abs(Double($1) - raw) } ?? 4
    }

    /// 這一張要停留多久
    private var slideDuration: Double {
        guard synced, let grid else { return seconds }
        return grid.interval * Double(beatsPerSlide)
    }

    /// 「♩ 128・每 8 拍」
    private var beatLabel: String {
        if analyzing { return "分析節奏中…" }
        guard let grid else { return "卡點" }
        return "♩ \(Int(grid.bpm.rounded()))・每 \(beatsPerSlide) 拍"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            slide
            if started {
                scrim
                if showChrome { chrome }
            } else {
                startCard
            }
        }
        .statusBarHidden(true)
        .contentShape(Rectangle())
        .onTapGesture { if started { toggleChrome() } }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    guard started else { return }
                    if v.translation.height > 80 { finish() }
                    else if v.translation.width < -50 { step(1) }
                    else if v.translation.width > 50 { step(-1) }
                }
        )
        .alert("需要音樂權限", isPresented: $musicDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("要到「設定 → LifeGood → 媒體與 Apple Music」打開，才能挑你資料庫裡的歌來配這本相簿。")
        }
        .fullScreenCover(isPresented: $showMusicPicker) {
            MusicPickerSheet(
                onPicked: { collection in
                    showMusicPicker = false
                    music.play(collection)
                    music.refreshRemembered()
                    grid = nil
                    analyze()
                    resume()
                },
                onCancel: {
                    showMusicPicker = false
                    resume()
                })
                .ignoresSafeArea()
        }
        .overlay { tapOverlay }
        .onChange(of: music.lastError) { _, new in
            guard new != nil else { return }
            chromeTask?.cancel()
            withAnimation(.easeOut(duration: 0.25)) { showChrome = true }
        }
        // 清單換了順序、或剛按下開始，都要重跑一次：
        // 只看 index 的話，開場畫面把 queue 排好之後 index 還是 0，
        // task 不會再觸發，第一張就永遠載不進來。
        .task(id: taskKey) { await loadCurrent() }
        .onAppear { prepare() }
        .onDisappear {
            ticker?.cancel()
            chromeTask?.cancel()
            music.stop()
        }
    }

    // MARK: 畫面

    /// [v25.493] 三層：景在後、照片在中、景在前。
    ///
    /// 使用者說得對——東西全部在照片後面，看起來就是「照片貼在一張圖上」。
    /// 梅枝、近處的落梅、貼著地面流的霧、岸邊的蘆葦移到照片前面之後，
    /// 照片才真的坐進這幅畫裡。
    @ViewBuilder
    private var slide: some View {
        ZStack {
            // 背景自己一層，不跟著照片轉場——會動的場景每張重畫一次就不叫場景了
            switch theme {
            case .ink:
                InkLandscapeView(paused: paused)
                collageWall
                InkForegroundView(paused: paused)
            case .cyber:
                CyberCityView(paused: paused)
                collageWall
                CyberForegroundView(paused: paused)
            }
            colophon
        }
    }

    // MARK: 開場（v25.495）

    /// 按下播放之後先問一句「照什麼順序走」。
    ///
    /// 為什麼值得多一個畫面：順序決定了這本相簿講的是哪一個故事。
    /// 逐站是行程、新增時間是時間軸、隨機是回憶。直接開播等於幫使用者
    /// 決定了故事，而且事後沒有地方可以改。
    ///
    /// 這個畫面長在同一幅水墨上，不另外蓋一層黑底——開場與正片是同一幅畫，
    /// 按下開始只是畫裡開始落照片而已。
    private var startCard: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text(colophonTitle)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(onBackdrop)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Text("共 \(items.count) 張")
                .font(.system(size: 13, weight: .medium, design: .serif))
                .foregroundStyle(onBackdrop.opacity(0.55))
                .padding(.top, 6)

            VStack(spacing: 8) {
                sectionLabel("主題")
                ForEach(SlideshowTheme.allCases) { option in
                    themeRow(option)
                }
                sectionLabel("順序")
                    .padding(.top, 8)
                ForEach(SlideshowOrder.allCases) { option in
                    orderRow(option)
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 26)

            Button {
                begin()
            } label: {
                Label("開始播放", systemImage: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(onBackdrop))
            }
            .padding(.top, 24)
            .padding(.horizontal, 26)

            HStack(spacing: 18) {
                Button {
                    showMusicPicker = true
                } label: {
                    Label(music.trackTitle ?? "選配樂", systemImage: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Button("關閉") { dismiss() }
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(onBackdrop.opacity(0.7))
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // 底色淡淡壓一層，字壓在景上才讀得到
            theme.sheet.opacity(theme.isLight ? 0.72 : 0.80).ignoresSafeArea())
        .transition(.opacity)
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(onBackdrop.opacity(0.45))
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
    }

    private func themeRow(_ option: SlideshowTheme) -> some View {
        pickerRow(icon: option.icon, label: option.label, detail: option.detail,
                  picked: option == theme) {
            themeRaw = option.rawValue
        }
    }

    private func orderRow(_ option: SlideshowOrder) -> some View {
        pickerRow(icon: option.icon, label: option.label, detail: option.detail,
                  picked: option == order) {
            orderRaw = option.rawValue
            queue = ordered(option)
            index = 0
        }
    }

    /// 開場那張紙上的一列選項。主題與順序長得一樣——
    /// 兩種外觀不同的清單會讓人以為它們是兩種不同的東西。
    private func pickerRow(icon: String, label: String, detail: String,
                           picked: Bool, action: @escaping () -> Void) -> some View {
        // 暗底的時候輪廓要用亮色畫，黑線在黑底上等於沒畫
        let line = theme.isLight ? Color.black : Color.white
        return Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(onBackdrop.opacity(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(picked ? onBackdrop : onBackdrop.opacity(0.25))
            }
            .foregroundStyle(onBackdrop)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(line.opacity(picked ? 0.10 : 0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(line.opacity(picked ? 0.38 : 0.12),
                                    lineWidth: picked ? 1.2 : 0.8)))
        }
        .buttonStyle(.plain)
    }

    /// [v25.492] 題款與鈐印。
    ///
    /// 這是畫的一部分，不是控制列——所以收起控制列之後它還在。
    /// 中國畫的三件套是「畫、題款、印」，少了後面兩個，再像水墨也只是背景圖。
    @ViewBuilder
    private var colophon: some View {
        Group {
            switch theme {
            case .ink:
                InkColophon(title: colophonTitle, dateText: colophonDate)
                    // [v25.495] 墊一層紙色的光暈。落點已經讓開左邊這一欄了，
                    // 但卡片會旋轉、會抖動，萬一邊角飄過來，字還讀得到。
                    .shadow(color: Color(red: 0.96, green: 0.95, blue: 0.93).opacity(0.95),
                            radius: 7)
            case .cyber:
                // [v25.497] 賽博龐克版的題款。中國畫的「畫、題款、印」在這裡的
                // 對應物是 HUD：帶刻度的側軌加等寬字。位置一樣在左緣——
                // 照片的落點早就為這一欄讓開了，兩套主題共用同一份版型。
                CyberHUD(title: colophonTitle, dateText: colophonDate,
                         counter: String(format: "%02d / %02d",
                                         min(index + 1, items.count), items.count))
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 18)
            .padding(.top, 92)
            .allowsHitTesting(false)
    }

    /// 落款題的是畫名，不是畫面標題——所以把「…的相本」去掉
    private var colophonTitle: String {
        title.replacingOccurrences(of: " 的相本", with: "")
             .replacingOccurrences(of: "的相本", with: "")
    }

    /// 落款上的日期：寫目前這張照片拍的那一天
    private var colophonDate: String? {
        guard let item = current else { return nil }
        return Self.colophonFmt.string(from: item.date)
    }

    /// 拼貼牆：照片一張一張飄進同一個畫面，滿了就把最舊的那張推掉。
    private var collageWall: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(wall.enumerated()), id: \.element.id) { position, item in
                    WallCard(item: item,
                             cardSize: PhotoLightbox.fittedSize(
                                item.image.size,
                                in: WallLayout.cardArea(geo.size)),
                             container: geo.size,
                             age: wall.count - 1 - position,
                             theme: theme)
                        .transition(.asymmetric(
                            // [v25.494] 使用者指定：三秒淡入。
                            // [v25.497] 淡入是兩套主題共同的骨架，差別在於
                            // 「淡入的時候還發生了什麼」：水墨是墨化開一圈，
                            // 賽博是鏡頭在對焦。
                            insertion: theme == .ink ? .inkFadeIn : .cyberFocusIn,
                            // [v25.492] 離場往上飄，像把這一頁揭起來
                            removal: .opacity.combined(with: .offset(y: -38))
                                .combined(with: .scale(scale: 0.94))))
                        .zIndex(Double(item.id))
                }
            }
            // 整面牆跟著拍子呼吸
            .scaleEffect(beatTick % 2 == 0 ? 1.0 : 1.008)
            .animation(.spring(response: 0.16, dampingFraction: 0.45), value: beatTick)
        }
        .ignoresSafeArea()
    }

    /// 上下兩條黑色漸層：白底照片上文字才看得見
    private var scrim: some View {
        // 亮底用白罩（黑罩會把整幅水墨壓成灰的），暗底用黑罩
        // （白罩會讓夜景整個發灰）。
        let veil = theme.veil
        return VStack {
            LinearGradient(colors: [veil.opacity(showChrome ? 0.55 : 0), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 180)
            Spacer()
            LinearGradient(colors: [.clear, veil.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.25), value: showChrome)
    }

    private var chrome: some View {
        VStack {
            topBar
            Spacer()
            caption
            musicNotice
            controls
        }
        .padding(.bottom, 10)
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { finish() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(onBackdrop.opacity(0.55)))
            }
            // [v25.520] 相簿名放不下就跑馬燈（原本切成「…」）
            MarqueeText(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(onBackdrop.opacity(0.9))
            Spacer()
            Text("\(index + 1) / \(items.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(onBackdrop.opacity(0.55)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// 這張是哪一站、哪一天拍的
    @ViewBuilder
    private var caption: some View {
        if let item = current {
            VStack(alignment: .leading, spacing: 3) {
                // [v25.520] 站名放不下就跑馬燈（原本切成「…」）
                MarqueeText(item.group)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(onBackdrop)
                Text(Self.dayFmt.string(from: item.date))
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(onBackdrop.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .id(item.id)
            .transition(.opacity)
        }
    }

    /// [v25.487] 音樂沒播起來時把原因寫出來。
    ///
    /// 這一塊存在的理由就是使用者那句「為什麼選好音樂看了十幾張還是沒聽到」：
    /// 失敗卻不說話，使用者只能自己猜。
    @ViewBuilder
    private var musicNotice: some View {
        if let error = music.lastError {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(error)
                    .font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            // 這一張播到哪裡
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(onBackdrop.opacity(0.22))
                    Capsule().fill(onBackdrop)
                        .frame(width: geo.size.width * min(1, elapsed / max(slideDuration, 0.1)))
                }
            }
            .frame(height: 2.5)
            .padding(.horizontal, 20)

            HStack(spacing: 14) {
                Button { step(-1) } label: { icon("backward.end.fill") }
                Button { playing ? pause() : resume() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(onBackdrop))
                }
                Button { step(1) } label: { icon("forward.end.fill") }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)

            // [v25.488] 四顆設定膠囊擠在同一排會互相壓扁（歌名可能很長），
            // 改成自己一排、可以左右捲
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    beatButton
                    musicButton
                    speedButton
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(onBackdrop)
            .frame(width: 38, height: 38)
            .background(Circle().fill(chipFill))
    }

    private var musicButton: some View {
        Menu {
            Button("選一首歌…") { askMusicThenPick() }
            if music.hasRemembered && music.trackTitle == nil {
                Button("用上次那首") { music.playRemembered() }
            }
            if music.trackTitle != nil {
                Button(music.isPlaying ? "暫停音樂" : "繼續播放") {
                    music.isPlaying ? music.pause() : music.resume()
                }
                Button("停止音樂", role: .destructive) { music.stop() }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: music.isPlaying ? "music.note.list" : "music.note")
                    .font(.system(size: 13, weight: .semibold))
                if music.isPreparing {
                    Text("準備中…").font(.system(size: 11, weight: .semibold))
                } else if let t = music.trackTitle {
                    Text(t).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
            }
            .foregroundStyle(onBackdrop)
            .frame(height: 38)
            .padding(.horizontal, 12)
            .background(Capsule().fill(chipFill))
        }
    }

    /// [v25.486] 卡點。有節拍網格時寫出 BPM 與幾拍一張，點開可以調。
    private var beatButton: some View {
        Menu {
            Toggle("跟著拍子換照片", isOn: $beatSync)
            if grid != nil {
                Picker("幾拍換一張", selection: $beatsSetting) {
                    Text("自動").tag(0)
                    Text("每 2 拍").tag(2)
                    Text("每 4 拍（一小節）").tag(4)
                    Text("每 8 拍").tag(8)
                    Text("每 16 拍").tag(16)
                }
            }
            Button("用跟拍設定節奏…") { startTapMode() }
            if music.assetURL != nil {
                Button(analyzing ? "分析中…" : "重新分析這首歌") { analyze() }
                    .disabled(analyzing)
            }
            if let note = beatNote {
                // 停用的按鈕＝灰字說明。Menu 裡放裸 Text 不保證畫得出來。
                Button(note) {}.disabled(true)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: synced ? "waveform.path.ecg" : "metronome")
                    .font(.system(size: 13, weight: .semibold))
                Text(beatLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(synced ? .white : onBackdrop)
            .frame(height: 38)
            .padding(.horizontal, 12)
            .background(Capsule().fill(synced ? onBackdrop : chipFill))
        }
    }

    private var speedButton: some View {
        Menu {
            ForEach(Self.speeds, id: \.label) { speed in
                Button(speed.label + "（\(String(format: "%.1f", speed.value)) 秒）") {
                    seconds = speed.value
                    restartTimer()
                }
            }
        } label: {
            Text(speedLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(onBackdrop)
                .frame(height: 38)
                .padding(.horizontal, 12)
                .background(Capsule().fill(chipFill))
        }
    }

    private var speedLabel: String {
        Self.speeds.min { abs($0.value - seconds) < abs($1.value - seconds) }?.label ?? "中"
    }

    /// [v25.494] 照片淡入三秒（使用者指定）。
    ///
    /// 只有一個地方要讓步：每張停留時間比三秒短的時候（快速模式 2.2 秒），
    /// 整面牆會永遠停在半透明狀態——那看起來不是淡入，是沒載好。
    /// 所以淡入時間最多取停留時間的 85%。
    private var fadeInSeconds: Double {
        min(3.0, max(0.8, slideDuration * 0.85))
    }

    private var arrivalAnimation: Animation {
        .easeInOut(duration: fadeInSeconds)
    }

    // MARK: 流程

    /// 開場畫面要用的東西：排好清單、把上次的歌讀回來。
    /// 這裡**不**開計時器——還沒按開始，照片不該自己往下跑。
    private func prepare() {
        queue = ordered(order)
        music.refreshRemembered()
    }

    private func begin() {
        queue = ordered(order)
        index = 0
        withAnimation(.easeOut(duration: 0.4)) { started = true }
        // 開場畫面期間第一張就先解好了，這裡把它放上牆
        if let img = image { pushToWall(img) }
        start()
    }

    private func start() {
        playing = true
        restartTimer()
        scheduleChromeHide()
        music.refreshRemembered()
        // 上次選過歌就直接接著放，不用再挑一次
        if music.trackTitle == nil, music.hasRemembered { music.playRemembered() }
        // 有歌就順手分析節拍（讀波形是背景工作，不會卡住開場）
        if music.assetURL != nil { analyze() }
    }

    private func finish() {
        ticker?.cancel()
        music.stop()
        dismiss()
    }

    private func pause() {
        playing = false
        ticker?.cancel()
        music.pause()
    }

    private func resume() {
        music.resume()
        // 還停在開場畫面就不要開計時器——不然選完歌回來，
        // 照片會在那張問順序的紙後面自己跑掉好幾張。
        guard started else { return }
        playing = true
        restartTimer()
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard queue.indices.contains(next) else {
            if delta > 0 { finish() }      // 播完就結束
            return
        }
        // 換 index 本身不需要動畫：畫面上會動的是「新照片落到牆上」那一下，
        // 由 pushToWall 負責。
        index = next
        restartTimer()
    }

    /// 時間到就換下一張。
    ///
    /// 用 Task 而不是 Timer：畫面關掉時跟著取消，不會留下跑不完的計時器。
    /// 進度只在控制列看得見的時候才寫進 @State——收起來之後還每 0.1 秒寫一次，
    /// 等於每秒讓整個畫面重算十次，只為了一條沒人看得到的線。
    private func restartTimer() {
        elapsed = 0
        ticker?.cancel()
        guard playing else { return }
        let began = Date()
        let duration = slideDuration
        // 卡點：這一張要在歌曲的第幾秒換，現在就算好。
        // 每次迴圈重算的話，歌曲時間有一點抖動就會前後跳。
        let target: Double? = synced
            ? grid?.next(after: music.currentTime + 0.15, every: beatsPerSlide)
            : nil

        ticker = Task { @MainActor in
            var lastBeat = Int.min
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 40_000_000)
                guard !Task.isCancelled, playing else { return }

                // 安全網：歌切掉、使用者在音樂 App 拉進度條、或分析得到的
                // 拍點根本對不上時，不能卡在這裡等一個永遠不會到的時間點。
                let wall = Date().timeIntervalSince(began)
                if wall > duration * 2.5 { step(1); return }

                if let target, let grid, music.isPlaying {
                    let t = music.currentTime
                    let beat = grid.beatIndex(at: t)
                    if beat != lastBeat {
                        lastBeat = beat
                        beatTick &+= 1          // 每拍彈一下
                    }
                    if showChrome { elapsed = max(0, duration - (target - t)) }
                    // 提早 0.02 秒動手：轉場本身要一點時間，這樣動作收尾
                    // 才會剛好踩在拍上
                    if t >= target - 0.02 { step(1); return }
                } else {
                    if showChrome { elapsed = wall }
                    if wall >= duration { step(1); return }
                }
            }
        }
    }

    /// 三秒沒碰就把控制列收起來——看照片的時候那些按鈕是礙事的
    private func scheduleChromeHide() {
        chromeTask?.cancel()
        // 有話要講的時候就不要自動收起來
        guard music.lastError == nil else { return }
        chromeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showChrome = false }
        }
    }

    // MARK: 節拍

    /// 分析目前這首歌。拿不到波形（Apple Music 的保護曲目）就直說，
    /// 並把路指到手動跟拍——沉默地不作用最糟。
    private func analyze() {
        guard let url = music.assetURL else {
            grid = nil
            beatNote = "這首是 Apple Music 的保護曲目，讀不到波形。用「跟拍」手動點四下就能卡點。"
            return
        }
        analyzing = true
        beatNote = nil
        Task {
            let result = await BeatDetector.analyze(url: url)
            await MainActor.run {
                analyzing = false
                guard let result else {
                    beatNote = "這首分析不出穩定的拍子，維持照時間換。"
                    return
                }
                // 信心不足就不要硬卡：亂卡比不卡更難看
                guard result.confidence >= 0.25 else {
                    grid = nil
                    beatNote = String(format: "節奏不夠明確（抓到 %.0f BPM，信心 %.0f%%），"
                                      + "維持照時間換。要的話可以用「跟拍」自己定。",
                                      result.bpm, result.confidence * 100)
                    return
                }
                grid = result
                beatNote = nil
                restartTimer()
            }
        }
    }

    /// [v25.488] 跟拍模式。
    ///
    /// 原本「跟拍」是選單裡的一個項目——而選單點一下就關了，根本連不了四下。
    /// 使用者回報「手點四下要按哪裡不太清楚」就是這個原因。
    /// 改成蓋一塊明確寫著「點這裡」的區域，點幾下、還差幾下都寫出來。
    private func startTapMode() {
        tapTimes.removeAll()
        beatNote = nil
        withAnimation(.easeOut(duration: 0.2)) { tapMode = true }
    }

    @ViewBuilder
    private var tapOverlay: some View {
        if tapMode {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 38, weight: .semibold))
                    Text(tapHint)
                        .font(.title3.weight(.bold))
                    Text("跟著歌的節奏，點這塊區域")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                    if let grid {
                        Text("♩ \(Int(grid.bpm.rounded())) BPM")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.2)))
                    }
                    Button("完成") {
                        withAnimation(.easeOut(duration: 0.2)) { tapMode = false }
                        tapTimes.removeAll()
                        restartTimer()
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(Capsule().fill(.white))
                    .padding(.top, 4)
                }
                .foregroundStyle(.white)
                .padding(30)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
                .padding(.horizontal, 40)
            }
            .contentShape(Rectangle())
            .onTapGesture { tapBeat() }
            .transition(.opacity)
        }
    }

    private var tapHint: String {
        let left = 4 - tapTimes.count
        if left > 0 { return "還需要 \(left) 下" }
        return "抓到了，繼續點可以更準"
    }

    /// 手動跟拍：點四下以上算出 BPM，相位就用最後一下的播放位置。
    /// 使用者是跟著歌點的，所以那一下本身就是一個拍點。
    private func tapBeat() {
        let now = Date()
        // 兩秒沒點就當作重新開始數
        if let last = tapTimes.last, now.timeIntervalSince(last) > 2 { tapTimes.removeAll() }
        tapTimes.append(now)
        guard let bpm = BeatDetector.bpm(fromTaps: tapTimes) else {
            beatNote = "再點幾下（至少四下）"
            return
        }
        grid = BeatGrid(bpm: bpm, firstBeat: music.currentTime, confidence: 1)
        beatNote = nil
        restartTimer()
    }

    /// 先要授權再開選擇器。沒授權就直接開的話，使用者看到的是一個空的曲庫，
    /// 會以為是 App 壞了而不是權限沒給。
    private func askMusicThenPick() {
        // 挑歌期間先停住，不然選完回來已經播掉好幾張了
        pause()
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            showMusicPicker = true
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { status in
                Task { @MainActor in
                    if status == .authorized { showMusicPicker = true }
                    else { musicDenied = true; resume() }
                }
            }
        default:
            musicDenied = true
            resume()
        }
    }

    private func toggleChrome() {
        withAnimation(.easeOut(duration: 0.25)) { showChrome.toggle() }
        if showChrome { scheduleChromeHide() } else { chromeTask?.cancel() }
    }

    // MARK: 圖片

    private func loadCurrent() async {
        guard let item = current else { return }
        // 先吃快取（大圖預覽那一套），沒有才讀檔
        if let cached = FullImageCache.shared.image(for: item.url) {
            image = cached
        } else {
            image = await FullImageCache.shared.load(item.url)
        }
        // 還在開場畫面就先不要上牆——那一下淡入會被開場的紙蓋住，
        // 等於白白用掉了第一張最好看的進場。改由 begin() 放上去。
        if started, let img = image { pushToWall(img) }
        // 接下來兩張先解好，換場才不會卡一下
        FullImageCache.shared.prefetch(
            [index + 1, index + 2]
                .filter { queue.indices.contains($0) }
                .map { queue[$0].url })
    }

    /// [v25.489] 把這一張放上拼貼牆。
    ///
    /// 超過上限就把最舊的推掉：再多就看不清楚，而且記憶體要同時扛好幾張
    /// 全解析度的圖（一張 1200 萬畫素解開就是 48MB）。
    private func pushToWall(_ img: UIImage) {
        guard !wall.contains(where: { $0.id == index }) else { return }
        // [v25.492] 滿一頁就整面揭掉，新的一張落在空白的紙上。
        //
        // 原本是「擠掉最舊的那一張」——那會讓畫面永遠是滿的、永遠在換，
        // 看久了很疲勞。八張一頁的節奏給了一個呼吸點，而且空紙上落下
        // 第一張的那一下最好看。
        if wall.count >= WallLayout.capacity {
            withAnimation(.easeInOut(duration: 0.55)) { wall.removeAll() }
        }
        withAnimation(arrivalAnimation) {
            wall.append(WallPhoto(id: index, image: img, slot: index))
        }
    }

    /// 落款的日期寫法：直書時「二〇二六年十月五日」太長，用「丙午年十月初五」
    /// 又太假，取中間——數字年月日，直書讀起來剛好。
    private static let colophonFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy年M月d日"; return f
    }()

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M 月 d 日 (E) HH:mm"; return f
    }()
}
