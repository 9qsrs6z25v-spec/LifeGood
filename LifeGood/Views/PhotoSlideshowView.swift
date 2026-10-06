import SwiftUI
import MediaPlayer
import AVFoundation

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

    func play(_ collection: MPMediaItemCollection) {
        prepareAudioSession()
        player.setQueue(with: collection)
        player.repeatMode = .all          // 照片還在播，歌放完要接下去
        player.shuffleMode = .off
        player.play()
        isPlaying = true
        trackTitle = collection.items.first?.title
        if let id = collection.items.first?.persistentID {
            UserDefaults.standard.set(String(id), forKey: lastIdKey)
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func resume() {
        guard trackTitle != nil else { return }
        prepareAudioSession()
        player.play()
        isPlaying = true
    }

    func stop() {
        player.stop()
        isPlaying = false
        trackTitle = nil
        // 音訊工作階段還給系統，不然離開之後別的 App 的聲音會變小
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    /// 靜音開關撥到靜音時也要出得了聲——這是使用者主動按播放的音樂，
    /// 不是突然跳出來的提示音。
    private func prepareAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
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

    /// 每張停留幾秒。記起來，下次照用。
    @AppStorage("slideshow_seconds") private var seconds: Double = 3.5

    private static let speeds: [(label: String, value: Double)] = [
        ("慢", 5.0), ("中", 3.5), ("快", 2.2)
    ]

    private var current: AlbumPhotoItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
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
                    resume()
                },
                onCancel: {
                    showMusicPicker = false
                    resume()
                })
                .ignoresSafeArea()
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
                    .scaleEffect(zoom)
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

    private var controls: some View {
        VStack(spacing: 10) {
            // 這一張播到哪裡
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white)
                        .frame(width: geo.size.width * min(1, elapsed / max(seconds, 0.1)))
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
                if let t = music.trackTitle {
                    Text(t).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .frame(height: 38)
            .padding(.horizontal, 12)
            .background(Capsule().fill(.white.opacity(0.18)))
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
    private func transition(for i: Int) -> AnyTransition {
        switch i % 4 {
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
        default:
            return .asymmetric(
                insertion: .scale(scale: 0.88).combined(with: .opacity),
                removal: .scale(scale: 1.06).combined(with: .opacity))
        }
    }

    // MARK: 流程

    private func start() {
        playing = true
        restartTimer()
        scheduleChromeHide()
        music.refreshRemembered()
        // 上次選過歌就直接接著放，不用再挑一次
        if music.trackTitle == nil, music.hasRemembered { music.playRemembered() }
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
        withAnimation(.easeInOut(duration: 0.55)) { index = next }
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
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled, playing else { return }
                let t = Date().timeIntervalSince(began)
                if showChrome { elapsed = t }
                if t >= seconds {
                    step(1)
                    return
                }
            }
        }
    }

    /// 三秒沒碰就把控制列收起來——看照片的時候那些按鈕是礙事的
    private func scheduleChromeHide() {
        chromeTask?.cancel()
        chromeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showChrome = false }
        }
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
        let dx: CGFloat = (index % 2 == 0) ? 14 : -14
        let dy: CGFloat = (index % 3 == 0) ? -10 : 8
        withAnimation(.linear(duration: seconds + 0.6)) {
            zoom = 1.09
            drift = CGSize(width: dx, height: dy)
        }
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M 月 d 日 (E) HH:mm"; return f
    }()
}
