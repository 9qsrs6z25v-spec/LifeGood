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

struct PhotoSlideshowView: View {
    let items: [AlbumPhotoItem]
    var title: String = "相本"

    @Environment(\.dismiss) private var dismiss
    @StateObject private var music = SlideshowMusic.shared

    @State private var index = 0
    @State private var image: UIImage?
    @State private var playing = true
    @State private var showChrome = true
    @State private var ticker: Task<Void, Never>?
    @State private var chromeTask: Task<Void, Never>?
    @State private var showMusicPicker = false
    @State private var musicDenied = false
    /// 這一張的 Ken Burns 進度（0→1 緩慢推進，製造「照片還活著」的感覺）
    @State private var zoom: CGFloat = 1.0
    @State private var drift: CGSize = .zero
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
        guard items.indices.contains(index) else { return nil }
        return items[index]
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
            scrim
            if showChrome { chrome }
        }
        .statusBarHidden(true)
        .contentShape(Rectangle())
        .onTapGesture { toggleChrome() }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
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
        .onChange(of: music.lastError) { _, new in
            guard new != nil else { return }
            chromeTask?.cancel()
            withAnimation(.easeOut(duration: 0.25)) { showChrome = true }
        }
        .task(id: index) { await loadCurrent() }
        .onAppear { start() }
        .onDisappear {
            ticker?.cancel()
            chromeTask?.cancel()
            music.stop()
        }
    }

    // MARK: 畫面

    @ViewBuilder
    private var slide: some View {
        if let image {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    // [v25.486] 每一拍輕輕彈一下（1.2%）。幅度刻意很小：
                    // 這是「照片跟著音樂呼吸」，不是把畫面搖來搖去。
                    .scaleEffect(zoom * (beatTick % 2 == 0 ? 1.0 : 1.012))
                    .animation(.spring(response: 0.16, dampingFraction: 0.45), value: beatTick)
                    .offset(drift)
                    .clipped()
                    .ignoresSafeArea()
            }
            .ignoresSafeArea()
            .id(index)
            .transition(transition(for: index))
        } else {
            ProgressView().tint(.white)
        }
    }

    /// 上下兩條黑色漸層：白底照片上文字才看得見
    private var scrim: some View {
        VStack {
            LinearGradient(colors: [.black.opacity(showChrome ? 0.55 : 0), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 180)
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.65)],
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
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer()
            Text("\(index + 1) / \(items.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.45)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// 這張是哪一站、哪一天拍的
    @ViewBuilder
    private var caption: some View {
        if let item = current {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.group)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(Self.dayFmt.string(from: item.date))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
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
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white)
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
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(.white))
                }
                Button { step(1) } label: { icon("forward.end.fill") }
                Spacer()
                beatButton
                musicButton
                speedButton
            }
            .padding(.horizontal, 20)
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(.white.opacity(0.18)))
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
            .foregroundStyle(.white)
            .frame(height: 38)
            .padding(.horizontal, 12)
            .background(Capsule().fill(.white.opacity(0.18)))
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
            Button("跟拍：點四下以上") { tapBeat() }
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
            .foregroundStyle(synced ? .black : .white)
            .frame(height: 38)
            .padding(.horizontal, 12)
            .background(Capsule().fill(synced ? Color.white : Color.white.opacity(0.18)))
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
                .foregroundStyle(.white)
                .frame(height: 38)
                .padding(.horizontal, 12)
                .background(Capsule().fill(.white.opacity(0.18)))
        }
    }

    private var speedLabel: String {
        Self.speeds.min { abs($0.value - seconds) < abs($1.value - seconds) }?.label ?? "中"
    }

    // MARK: 轉場
    //
    // 固定依序輪替而不是隨機：隨機看起來像壞掉，輪替看起來像有人設計過。
    //
    // [v25.486] 從四種加到七種，而且**跟著小節走**：卡點時每四張是一個小節的
    // 起頭，那一張給比較狠的轉場（圓形揭開／甩鏡／翻卡），其餘用溫和的
    // （溶接／推近／模糊溶接）。全部都用狠的會暈，全部都溫和又看不出有在卡點。
    private func transition(for i: Int) -> AnyTransition {
        let punchy = synced && i % 4 == 0
        if punchy {
            switch (i / 4) % 3 {
            case 0: return .circleReveal
            case 1: return .whipPan(from: .trailing)
            default: return .flipCard
            }
        }
        switch i % 6 {
        case 0:
            return .opacity
        case 1:
            return .asymmetric(
                insertion: .scale(scale: 1.14).combined(with: .opacity),
                removal: .opacity)
        case 2:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity)
        case 3:
            return .blurDissolve
        case 4:
            return .asymmetric(
                insertion: .scale(scale: 0.88).combined(with: .opacity),
                removal: .scale(scale: 1.06).combined(with: .opacity))
        default:
            return .whipPan(from: .leading)
        }
    }

    /// 轉場要多快。
    ///
    /// 卡點時刻意比較短（0.34 秒）：「踩在拍子上」靠的是**動作結束的瞬間**
    /// 剛好落在拍點，拖太久就糊成一團、感覺不到節奏。
    private var transitionAnimation: Animation {
        synced ? .spring(response: 0.34, dampingFraction: 0.82)
               : .easeInOut(duration: 0.55)
    }

    // MARK: 流程

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
        playing = true
        music.resume()
        restartTimer()
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard items.indices.contains(next) else {
            if delta > 0 { finish() }      // 播完就結束
            return
        }
        withAnimation(transitionAnimation) { index = next }
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
        startKenBurns()
        // 接下來兩張先解好，換場才不會卡一下
        FullImageCache.shared.prefetch(
            [index + 1, index + 2]
                .filter { items.indices.contains($0) }
                .map { items[$0].url })
    }

    /// 緩慢推近＋飄移。方向依序輪替，不然每一張都往同一邊飄會很機械。
    private func startKenBurns() {
        zoom = 1.0
        drift = .zero
        // [v25.486] 推近／拉遠交替，飄移方向四種輪流——
        // 只會推近、只會往同一邊飄的話，看三十張就看得出是同一個公式。
        let dx: CGFloat = (index % 2 == 0) ? 16 : -16
        let dy: CGFloat = (index % 4 < 2) ? -12 : 10
        let zoomsIn = index % 2 == 0
        zoom = zoomsIn ? 1.0 : 1.10
        withAnimation(.linear(duration: slideDuration + 0.6)) {
            zoom = zoomsIn ? 1.10 : 1.0
            drift = CGSize(width: dx, height: dy)
        }
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M 月 d 日 (E) HH:mm"; return f
    }()
}

// MARK: - 自訂轉場（v25.486）
//
// SwiftUI 內建的只有淡入、縮放、位移那幾種。相簿要好看，靠的是「一眼看得出
// 這是一個轉場」的動作——圓形揭開、甩鏡、翻卡、模糊溶接。
// 全部用 .modifier(active:identity:) 做：active 是「還沒進場／已經離場」的樣子，
// identity 是「在畫面上」的樣子，SwiftUI 會在兩者之間補間。

/// 模糊溶接：糊掉並微微放大後消失。最溫和的一種，適合連續的風景照。
private struct BlurDissolveModifier: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 16 : 0)
            .scaleEffect(active ? 1.06 : 1)
            .opacity(active ? 0 : 1)
    }
}

/// 圓形揭開：從中心擴散出來。小節的第一張用，一眼看得出「換段落了」。
private struct CircleRevealModifier: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .mask(
                Circle()
                    // 2.4 倍才蓋得滿整個長方形畫面（對角線比邊長長）
                    .scaleEffect(active ? 0.01 : 2.4)
            )
            .opacity(active ? 0 : 1)
    }
}

/// 甩鏡：快速橫移＋殘影般的模糊。
private struct WhipPanModifier: ViewModifier {
    let active: Bool
    let fromTrailing: Bool
    func body(content: Content) -> some View {
        content
            .offset(x: active ? (fromTrailing ? 280 : -280) : 0)
            .blur(radius: active ? 14 : 0)
            .opacity(active ? 0 : 1)
    }
}

/// 翻卡：繞 Y 軸轉一個角度。刻意只轉 26 度——轉到 90 度會看到紙片的背面，
/// 那需要另外畫一面，在幻燈片裡不值得。
private struct FlipCardModifier: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(active ? 26 : 0),
                              axis: (x: 0, y: 1, z: 0),
                              perspective: 0.55)
            .scaleEffect(active ? 0.94 : 1)
            .opacity(active ? 0 : 1)
    }
}

extension AnyTransition {
    static var blurDissolve: AnyTransition {
        .modifier(active: BlurDissolveModifier(active: true),
                  identity: BlurDissolveModifier(active: false))
    }

    static var circleReveal: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: CircleRevealModifier(active: true),
                                 identity: CircleRevealModifier(active: false)),
            // 離場用單純的淡出：兩張同時做圓形遮罩會看到破圖
            removal: .opacity)
    }

    static func whipPan(from edge: Edge) -> AnyTransition {
        let fromTrailing = edge == .trailing
        return .asymmetric(
            insertion: .modifier(active: WhipPanModifier(active: true, fromTrailing: fromTrailing),
                                 identity: WhipPanModifier(active: false, fromTrailing: fromTrailing)),
            removal: .modifier(active: WhipPanModifier(active: true, fromTrailing: !fromTrailing),
                               identity: WhipPanModifier(active: false, fromTrailing: !fromTrailing)))
    }

    static var flipCard: AnyTransition {
        .modifier(active: FlipCardModifier(active: true),
                  identity: FlipCardModifier(active: false))
    }
}
