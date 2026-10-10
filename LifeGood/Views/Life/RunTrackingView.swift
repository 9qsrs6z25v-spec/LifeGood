import SwiftUI
import MapKit
import CoreLocation

// MARK: - 跑步即時紀錄（v25.352）
//
// 開始後邊跑邊畫路徑，顯示距離、時間、配速與爬升。結束後轉成一筆訓練存進健康頁。
// 背景定位有開，鎖屏或切到別的 App 仍會繼續記；狀態列會出現藍色指示條。

struct RunTrackingView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = RunTracker.shared

    /// 結束後把成果交出去（呼叫端負責存檔與寫回 Apple 健康）
    let onFinish: (WorkoutSession) -> Void

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var sportName = "跑步"
    @State private var showDiscardAlert = false

    private let accent = Color(red: 0.20, green: 0.78, blue: 0.45)
    private let sports = ["跑步", "健走", "騎車", "登山"]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mapLayer
                    .ignoresSafeArea(edges: .top)
                controlPanel
            }
            .navigationTitle(tracker.isActive ? sportName : "開始運動")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tracker.isActive ? "隱藏" : "關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if tracker.isActive {
                        Button("放棄", role: .destructive) { showDiscardAlert = true }
                            .foregroundStyle(.red)
                    }
                }
            }
            .alert("放棄這一趟？", isPresented: $showDiscardAlert) {
                Button("放棄", role: .destructive) { tracker.cancel(); dismiss() }
                Button("繼續記錄", role: .cancel) { }
            } message: {
                Text("已經記錄的距離與路徑會直接丟掉，無法復原。")
            }
            .onAppear { tracker.requestAuthorization() }
        }
    }

    // MARK: 地圖

    private var mapLayer: some View {
        Map(position: $camera) {
            UserAnnotation()
            if tracker.points.count >= 2 {
                MapPolyline(coordinates: RouteMath.coordinates(tracker.points))
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = tracker.points.first {
                Annotation("起點", coordinate: CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon)) {
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(accent, lineWidth: 4))
                }
            }
        }
        .mapControls { MapUserLocationButton(); MapCompass() }
    }

    // MARK: 控制面板

    private var controlPanel: some View {
        VStack(spacing: 14) {
            if !tracker.isActive {
                Picker("運動", selection: $sportName) {
                    ForEach(sports, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 0) {
                statCell(Self.distanceText(tracker.distanceMeters), "公里")
                divider
                statCell(Self.clockText(tracker.elapsed), "時間")
                divider
                statCell(Self.paceText(tracker.paceMinPerKm), "配速")
                divider
                statCell(String(format: "%.0f", tracker.elevationGainM), "爬升 m")
            }

            if tracker.waitingForFix && tracker.phase == .running {
                Label("正在等 GPS 定位，走到空曠處會比較快", systemImage: "location.magnifyingglass")
                    .font(.caption).foregroundStyle(.orange)
            }
            if tracker.authorization == .denied || tracker.authorization == .restricted {
                Label("定位權限被關閉，無法記錄路徑。請到「設定 → LifeGood → 位置」開啟。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            buttons
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(.separator).opacity(0.2), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var divider: some View {
        Rectangle().fill(Color(.separator).opacity(0.3)).frame(width: 0.75, height: 30)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var buttons: some View {
        switch tracker.phase {
        case .idle:
            Button {
                tracker.start()
            } label: {
                Label("開始", systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .background(accent, in: Capsule())
            .foregroundStyle(.white)
        case .running:
            HStack(spacing: 12) {
                Button {
                    tracker.pause()
                } label: {
                    Label("暫停", systemImage: "pause.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .background(Color(.tertiarySystemFill), in: Capsule())
            }
        case .paused:
            HStack(spacing: 12) {
                Button {
                    tracker.resume()
                } label: {
                    Label("繼續", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .background(Color(.tertiarySystemFill), in: Capsule())
                Button {
                    finish()
                } label: {
                    Label("完成", systemImage: "checkmark")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .background(accent, in: Capsule())
                .foregroundStyle(.white)
            }
        }
    }

    private func finish() {
        let result = tracker.finish()
        guard result.distanceKm > 0.01 || result.minutes > 0.5 else { dismiss(); return }
        let exercise = WorkoutExercise(
            name: sportName, kind: .cardio, reps: 0, sets: 0, loadType: .none,
            loadKg: 0, distanceKm: result.distanceKm, durationMinutes: result.minutes,
            route: result.route, elevationGainM: result.elevation)
        let session = WorkoutSession(
            date: Date().addingTimeInterval(-result.minutes * 60),
            title: sportName,
            exercises: [exercise],
            durationMinutes: result.minutes)
        onFinish(session)
        dismiss()
    }

    // MARK: 格式

    static func distanceText(_ meters: Double) -> String {
        String(format: "%.2f", meters / 1000)
    }
    static func clockText(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }
    static func paceText(_ minPerKm: Double?) -> String {
        guard let p = minPerKm, p.isFinite, p > 0, p < 60 else { return "—" }
        let m = Int(p)
        let sec = Int((p - Double(m)) * 60)
        return String(format: "%d'%02d\"", m, sec)
    }
}

// MARK: - 已存路徑的靜態地圖

struct RouteMapView: View {
    let route: [RoutePoint]
    var height: CGFloat = 170
    var accent: Color = Color(red: 0.20, green: 0.78, blue: 0.45)

    var body: some View {
        Group {
            if let b = RouteMath.bounds(route), route.count >= 2 {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: b.center,
                    latitudinalMeters: b.spanMeters,
                    longitudinalMeters: b.spanMeters))
                ) {
                    MapPolyline(coordinates: RouteMath.coordinates(route))
                        .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    if let f = route.first {
                        Annotation("起", coordinate: CLLocationCoordinate2D(latitude: f.lat, longitude: f.lon)) {
                            Circle().fill(.white).frame(width: 11, height: 11)
                                .overlay(Circle().stroke(accent, lineWidth: 3))
                        }
                    }
                    if let l = route.last {
                        Annotation("終", coordinate: CLLocationCoordinate2D(latitude: l.lat, longitude: l.lon)) {
                            Circle().fill(accent).frame(width: 11, height: 11)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
            } else {
                EmptyView()
            }
        }
    }
}
