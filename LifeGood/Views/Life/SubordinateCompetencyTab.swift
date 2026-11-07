import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 部屬卡片〔職能〕分頁（G1 負責；radar/judge.md §4.3、§5、§6、§3.6；radar/build/v1a-1/brief.md §4 G1）
//
// • 由上到下：摘要卡（不寫 0–100）→ 人格特質卡（0 項整張不出現）→ 每個系統一張 → 不用學的系統一行。
// • 看不擋；〔評分〕〔不用學的系統〕〔用範例開始〕〔自己設定〕要訂閱（isPremium／premiumLockAlert）。
// • 已轉出：〔評分〕藏起來、「已轉出，評分留著可以看」；這台的 App 比較舊：〔評分〕藏起來、頂上一行說明。
// • 整頁的數字、字只照 CompetencyMath.tabModel；sheet 一律 sheet(item:)＋.appStores()；dismiss 後寫 store 放下一個 runloop。
// • 這個 View 不包 ScrollView（明細頁外面已經有）；白卡、外距自己加。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G1 換成真的。
//
// [v25.600 職能雷達 v1a-2] 這一版加的（radar/build/v1a-2/brief.md §4 G1-A；要退回這一件：照 69f6fa6 的這個檔）：
// • 三支 private 小函式搬進 CompetencyMath（tabModel 的 hasAnyPrevious／overlayLabel／skippedLineText；↑↓ 顏色照 deltaDirection）。
// • 只評了一部分、各張卡上一次不是同一天：膠囊下面一行 previousDayText「上一次：人格特質 4/30・Gas System 10/30…」。
// • 點雷達下面橫條那一列 → 那一格的歷史（CompetencyCellHistorySheet；看不擋）。
// • iPad（.regular）雷達卡兩欄（LazyVGrid、每張最寬 360）；iPhone 照舊一欄。
// • 最下面「評分紀錄」白卡 → 點一列打開那一天的明細（CompetencyRecordDetailView；看不擋、改刪在明細頁擋）。
// • §13：每一格的評語不做——這裡一個字的評語都不顯示。
//
// [v25.601 職能雷達 v1b] 這一版加的（radar/build/v1b/brief.md §4 G1-A；要退回這一件：照 92b02fe 的這個檔）：
// • 照職等疊目標：tabModel 多傳 grades（competencyGradeContext）、mode（摘要卡〔目標 E2 ▾〕，這台記住 competency.targetMode）。
// • 摘要卡「E2 達標 10／12」「離 E2 還差 2 格（差 2 級）」「未評 2 格」；沒設職等一行＋〔設定職等〕（打開既有的部屬編輯表單
//   AddSubordinateView(editing:)，跟明細頁〔編輯〕一樣要訂閱）；職等被刪、這個職等還沒訂目標各一行橘字。
// • 「疊：」那一排多〔目標 E2 ▾〕選單（目前職等／下一個職等／不疊；只是看，不擋訂閱）；一排放不下換兩行（ViewThatFits）。
// • 摘要卡下面「離 E2 目標的差距」白卡（由大到小，最多 6 列＋看全部）→ 點一列打開那一格的歷史（看不擋）。
// • 評分紀錄那一列：那一張的職等跟現在不一樣多一行「那時 E2 工程師」。
// • 通知、小工具、手錶、鎖定畫面一個字都不加（目標、達標也是）。
//
// [v25.605 職能雷達 v4b] 這一版加的（radar/build/v4b/brief.md §3 G1；要退回這一件：照 4097c29 的這個檔）：
// • 摘要卡右上「…」最前面多〔給對方看〕（CompetencyMath.canShow：設好了、任一張卡有評分才出現；fullScreenCover(item:)
//   打開 CompetencyShowView）與〔分享職能雷達…〕（既有的部屬匯出頁 SubordinateExportSheet，preset: .competencyOnly、
//   mentioned: []；這次的勾法不寫進記住上次），分隔線後才是既有兩項。
// • 兩個都只是看／使用者自己按的分享：不擋訂閱；這裡不寫 store；§13 評語照舊不顯示。
//
// [v25.606 職能雷達 v5a] 這一版加的（radar/build/v5a/brief.md §3 G1；要退回這一件：照 8ee35e6 的這個檔）：
// • 摘要卡「…」分隔線後多〔帶訓者〕（打開 CompetencyMentorView）〔記帶訓者的評分…〕（有帶訓者才有；一位一列的子選單；
//   既有的評分畫面、request.rater 帶著），兩個都擋訂閱；已轉出、唯讀不出現。
// • 每張雷達卡標題下一行「帶訓者：陳怡君」＋膠囊〔帶訓者（陳怡君 11/2）〕：只是看、不擋訂閱、不記住（@State）。
// • 摘要卡多一行「跟帶訓者差 2 級以上：Gas 值班技能（你 4、陳怡君 2）」（有才寫）。
// • 評分紀錄多帶訓者記的那幾列（「・陳怡君（帶訓者）」）；點進去帶 raterKey 開那一張的明細。
// • 目前分數、上一次、達標、熱力表、匯出不碰帶訓者評：tabModel 照舊只傳 competencySessions(of:)；帶訓者那一份另外算
//  （CompetencyMath.tabMentorModel）。§13 評語照舊不顯示。
//
// [v25.607 職能雷達 v5b] 這一版加的（radar/build/v5b/brief.md §3 G1；要退回這一件：照 7a6507c 的這個檔）：
// • 評分紀錄上面多「升職」一段（CompTabPromotionCard；lifeStore.competencyPromotionRows）：一筆升職一列「7/1 升 E3 資深工程師
//  （那時 E2）」，點了打開升職快照明細（CompetencyMilestoneView；只是看，不擋訂閱）。以前的升職標「（現算）」、旁邊〔留一份〕
//  （擋訂閱；唯讀、已轉出不出現；寫入只走 keepCompetencyPromotionMilestone）。
// • 摘要卡「…」多〔加到一對一議程…〕（擋訂閱；唯讀、已轉出、沒有一對一會議不出現）：候選議程在按下去那一刻算好
//  （CompetencyMath.agendaCandidates；〔目標 E2 ▾〕不疊時用目前職等），放進 request 打開 CompetencyOneOnOneSheet。
// • tabModel、目前分數、上一次、達標、帶訓者那一份、匯出一個都不碰；§13 評語照舊不顯示。

struct SubordinateCompetencyTab: View {
    let subordinateId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager

    /// 摘要卡「疊：上一次」（這台記住；個人方便用）
    @AppStorage("competency.showPrevious") private var showPrevious = true
    // [v25.601 職能雷達 v1b] 摘要卡〔目標 E2 ▾〕：目前職等／下一個職等／不疊（這台記住；只是看）。要退回這一件：刪這兩行與 targetMode
    @AppStorage("competency.targetMode") private var targetModeRaw: String = CompetencyTargetMode.current.rawValue
    /// [v25.601 v1b] 〔設定職等〕打開的部屬編輯表單（sheet(item:)）。要退回這一件：刪這一行
    @State private var gradeEdit: CompTabGradeEditRequest?
    @State private var ratingRequest: CompetencyRatingRequest?
    @State private var setupRequest: CompTabSetupRequest?
    @State private var skipRequest: CompTabSkipRequest?
    @State private var showPremiumAlert = false
    /// 剛存好「已儲存 10/30 的評分（12 格）」（3 秒後自己消失）
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?
    // [v25.600 職能雷達 v1a-2] 評分紀錄明細、點一格的歷史（sheet(item:)）；iPad 兩欄。要退回這一件：刪這三行
    @State private var recordRequest: CompetencyRecordRequest?
    @State private var historyRequest: CompetencyCellHistoryRequest?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // [v25.605 職能雷達 v4b] 〔給對方看〕（fullScreenCover(item:)）、〔分享職能雷達…〕（sheet(item:)）。要退回這一件：刪這兩行
    @State private var showRequest: CompetencyShowRequest?
    @State private var shareRequest: CompTabShareRequest?
    // [v25.606 職能雷達 v5a]〔帶訓者〕（sheet(item:)）；疊帶訓者開著的組（只是看，不記住）。要退回這一件：刪這兩行
    @State private var mentorRequest: CompetencyMentorRequest?
    @State private var mentorOverlayOn: Set<UUID> = []
    // [v25.607 職能雷達 v5b] 升職快照明細、〔加到一對一議程…〕（sheet(item:)）。要退回這一件：刪這兩行
    @State private var milestoneRequest: CompetencyMilestoneRequest?
    @State private var oneOnOneRequest: CompetencyOneOnOneRequest?

    private var isArchived: Bool { OrgMoveIndex.isArchived(subordinateId) }

    /// [v25.601 v1b] 存的字對不到（舊版、打錯）就當「目前職等」
    private var targetMode: CompetencyTargetMode {
        CompetencyTargetMode(rawValue: targetModeRaw) ?? .current
    }

    /// [v25.601 v1b] 多傳職等與對照（grades 空、mode .off＝跟 v1a-2 一模一樣）。要退回這一件：拿掉最後兩個參數
    private var model: CompetencyTabModel {
        CompetencyMath.tabModel(setup: lifeStore.competencySetup,
                                ratings: lifeStore.competencyRatings,
                                subordinateId: subordinateId,
                                archivedPerson: isArchived,
                                sessions: lifeStore.competencySessions(of: subordinateId),
                                today: CompetencyMath.dayKey(Date()),
                                grades: lifeStore.competencyGradeContext(for: subordinateId),
                                mode: targetMode)
    }

    var body: some View {
        let m = model
        let archived = isArchived
        let canRate = !archived && !m.readOnly
        return VStack(spacing: 16) {
            CompTabNoticeLines(archived: archived, readOnly: m.readOnly, toast: toastText)
            if m.configured {
                configuredContent(m, canRate: canRate)
            } else {
                CompTabEmptyCard(showsButtons: !m.readOnly, onSample: startSample, onBlank: startBlankSetup)
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $ratingRequest) { r in
            CompetencyRatingSheet(request: r, onSaved: { text in showToast(text) })
                .appStores()
        }
        .sheet(item: $setupRequest) { _ in
            NavigationStack {
                CompetencySetupView(showsDoneButton: true)
            }
            .appStores()
        }
        .sheet(item: $skipRequest) { req in
            CompTabSkipSheet(subordinateId: req.subordinateId, initialSkipped: req.initialSkipped)
                .appStores()
        }
        // [v25.600 職能雷達 v1a-2] 明細、點一格的兩個 sheet 包在一個 modifier 裡（body 的修飾器鏈不再拉長）。要退回這一件：刪這一行
        .modifier(CompTabHistorySheets(recordRequest: $recordRequest, historyRequest: $historyRequest))
        // [v25.601 職能雷達 v1b] 〔設定職等〕＝既有的部屬編輯表單（不另外寫職等）。要退回這一件：刪這一行
        .modifier(CompTabGradeSheet(request: $gradeEdit))
        // [v25.605 職能雷達 v4b] 〔給對方看〕〔分享職能雷達…〕兩個 sheet 包在一個 modifier 裡。要退回這一件：刪這一行
        .modifier(CompTabShowShareSheets(showRequest: $showRequest, shareRequest: $shareRequest))
        // [v25.606 職能雷達 v5a]〔帶訓者〕頁（帶訓者評的評分畫面用上面既有的 ratingRequest）。要退回這一件：刪這一行
        .modifier(CompTabMentorSheets(request: $mentorRequest))
        // [v25.607 職能雷達 v5b] 升職快照明細、〔加到一對一議程…〕兩個 sheet 包在一個 modifier 裡。要退回這一件：刪這一行
        .modifier(CompTabV5bSheets(milestoneRequest: $milestoneRequest, oneOnOneRequest: $oneOnOneRequest, onAdded: { text in showToast(text) }))
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .onDisappear { toastTask?.cancel() }
    }

    // MARK: 設好了：摘要卡、每組一張、不用學的系統

    @ViewBuilder
    private func configuredContent(_ m: CompetencyTabModel, canRate: Bool) -> some View {
        // [v25.606 職能雷達 v5a] 帶訓者那一份（tabModel 的數字一個都不動）
        let mm: CompetencyTabMentorModel = mentorModel(m)
        let hasSystems = !lifeStore.competencySetup.activeSystems.isEmpty
        CompTabSummaryCard(summary: m.summary,
                           neverRated: m.neverRated,
                           canRate: canRate,
                           showsSkipItem: canRate && hasSystems,
                           showsOverlayToggle: m.hasAnyPrevious,
                           overlayLabel: m.overlayLabel,
                           previousDayText: m.previousDayText,
                           showPrevious: $showPrevious,
                           onRate: startRating,
                           onSkip: openSkipSheet,
                           onSetup: openSetup,
                           targets: m.targets,
                           onPickMode: pickTargetMode,
                           onSetGrade: openGradeEdit,
                           canSetGrade: canRate,
                           canShowToPerson: CompetencyMath.canShow(m),
                           onShow: openShow,
                           onShare: openShare,
                           mentorDiffLine: mm.diffLine,
                           showsMentorItem: canRate,
                           mentorChoices: canRate ? mm.choices : [],
                           onMentors: openMentors,
                           onRateMentor: rateMentor,
                           showsOneOnOneItem: canRate && lifeStore.competencyHasOneOnOne(subordinateId),
                           onOneOnOne: openOneOnOne)
        // [v25.601 職能雷達 v1b] 離目標的差距（由大到小；沒評的不列）。要退回這一件：刪這個 if
        if let t = m.targets, !t.gapRows.isEmpty {
            CompTabGapCard(title: CompTabGapCard.headerTitle(for: t), rows: t.gapRows, onOpen: openHistory)
        }
        cardsBlock(m, mm)
        if hasSystems {
            CompTabSkippedLine(text: m.skippedLineText,
                               canEdit: canRate,
                               onEdit: openSkipSheet)
        }
        // [v25.607 職能雷達 v5b] 評分紀錄上面「升職」一段（有升職紀錄、生效日之前有評分才有；看不擋）。要退回這一件：刪這三行與 if
        let promos: [CompetencyPromotionRow] = lifeStore.competencyPromotionRows(of: subordinateId)
        if !promos.isEmpty {
            CompTabPromotionCard(rows: promos, canKeep: canRate, onOpen: openMilestone, onKeep: keepMilestone)
        }
        // [v25.600 職能雷達 v1a-2] 評分紀錄（judge §4.3④；§13 不顯示評語）。要退回這一件：刪這個 if
        if !mm.records.isEmpty {
            CompTabRecordsCard(records: mm.records, onOpen: openRecord)
        }
    }

    /// [v25.606 職能雷達 v5a] 〔職能〕分頁帶訓者那一份：卡片標題下一行、疊帶訓者、看法不一樣、評分紀錄合併。
    /// tabModel 照舊只看我評的（sessions 不換）；帶訓者評只從 competencyMentorSessions(of:) 進來
    private func mentorModel(_ m: CompetencyTabModel) -> CompetencyTabMentorModel {
        CompetencyMath.tabMentorModel(tab: m,
                                      setup: lifeStore.competencySetup,
                                      subordinateId: subordinateId,
                                      mentorSessions: lifeStore.competencyMentorSessions(of: subordinateId),
                                      roster: lifeStore.competencyMentorRoster)
    }

    // MARK: [v25.600 職能雷達 v1a-2] 雷達卡：iPad 兩欄、iPhone 一欄（judge §4.10）。要退回這一件：換回 ForEach＋padding

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    @ViewBuilder
    private func cardsBlock(_ m: CompetencyTabModel, _ mm: CompetencyTabMentorModel) -> some View {
        if isRegularWidth {
            LazyVGrid(columns: CompTabGrid.columns, alignment: .center, spacing: 16) {
                ForEach(m.cards) { card in
                    chartCard(card, mm)
                        .frame(maxWidth: 360)
                }
            }
            .padding(.horizontal)
        } else {
            ForEach(m.cards) { card in
                chartCard(card, mm)
                    .padding(.horizontal)
            }
        }
    }

    /// 一張雷達卡；點下面橫條那一列 → 那一格的歷史（看不擋）
    /// [v25.606 v5a] 標題下「帶訓者：陳怡君」＋膠囊；膠囊開著＝灰色虛線換成帶訓者的（整頁〔上一次〕關著也照畫）
    private func chartCard(_ card: CompetencyChartModel, _ mm: CompetencyTabMentorModel) -> CompetencyChartCard {
        let groupId: UUID = card.id
        let on: Set<UUID> = mentorOverlayOn
        let overlaid: Bool = on.contains(groupId) && mm.overlays[groupId] != nil
        let tap: (UUID) -> Void = { itemId in
            openHistory(groupId: groupId, itemId: itemId)
        }
        return CompetencyChartCard(model: CompetencyMath.displayCard(card, model: mm, overlayOn: on),
                                   showPrevious: showPrevious || overlaid,
                                   onTapAxis: tap,
                                   mentorBar: CompetencyMath.mentorBar(for: card, model: mm, overlayOn: on),
                                   onToggleMentor: { toggleMentorOverlay(groupId) })
    }

    // MARK: 動作（看不擋、動手才擋）

    private func startSample() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        lifeStore.applyCompetencySample()
    }

    private func startBlankSetup() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        lifeStore.startCompetencyBlankSetup()
        setupRequest = CompTabSetupRequest()
    }

    private func startRating() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        ratingRequest = CompetencyRatingRequest(subordinateId: subordinateId)
    }

    private func openSkipSheet() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        let current: Set<UUID> = lifeStore.competencySetup.skippedGroupIds(subordinateId)
        skipRequest = CompTabSkipRequest(subordinateId: subordinateId, initialSkipped: current)
    }

    /// 〔職能項目設定〕看不擋（設定頁裡動手才擋）
    private func openSetup() {
        setupRequest = CompTabSetupRequest()
    }

    /// [v25.605 v4b]〔給對方看〕只是看，不擋訂閱
    private func openShow() { showRequest = CompetencyShowRequest(subordinateId: subordinateId) }

    /// [v25.605 v4b]〔分享職能雷達…〕打開既有的部屬匯出頁、只勾職能雷達（不寫記住上次）；不擋訂閱
    private func openShare() { shareRequest = CompTabShareRequest(subordinateId: subordinateId) }

    /// [v25.606 v5a]〔帶訓者〕（擋訂閱；已轉出、唯讀不出現）
    private func openMentors() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        mentorRequest = CompetencyMentorRequest(subordinateId: subordinateId)
    }

    /// [v25.606 v5a]〔記帶訓者的評分…〕（擋訂閱）：既有的評分畫面、帶訓者模式
    private func rateMentor(_ c: CompetencyRaterChoice) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        ratingRequest = CompetencyRatingRequest(subordinateId: subordinateId, rater: c)
    }

    /// [v25.606 v5a] 卡片膠囊〔帶訓者（陳怡君 11/2）〕：只是看，不擋訂閱、不記住
    private func toggleMentorOverlay(_ groupId: UUID) {
        if mentorOverlayOn.contains(groupId) {
            mentorOverlayOn.remove(groupId)
        } else {
            mentorOverlayOn.insert(groupId)
        }
    }

    /// [v25.607 v5b]「升職」一列 → 升職快照明細（只是看，不擋訂閱）
    private func openMilestone(_ row: CompetencyPromotionRow) {
        milestoneRequest = CompetencyMilestoneRequest(subordinateId: subordinateId, promotionId: row.id)
    }

    /// [v25.607 v5b]〔留一份〕（擋訂閱；唯讀、已轉出不出現）：現算的那一份存起來
    private func keepMilestone(_ row: CompetencyPromotionRow) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        let today: String = CompetencyMath.dayKey(Date())
        if lifeStore.keepCompetencyPromotionMilestone(subordinateId, promotionId: row.id) {
            showToast(CompetencyMath.milestoneKeptToast(row, today: today))
        }
    }

    /// [v25.607 v5b]〔加到一對一議程…〕（擋訂閱）：候選議程在這一刻算好放進 request
    private func openOneOnOne() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        let m: CompetencyTabModel = agendaModel()
        let mm: CompetencyTabMentorModel = mentorModel(m)
        let list: [CompetencyAgendaCandidate] = CompetencyMath.agendaCandidates(tab: m, mentorDiffs: mm.diffs,
                                                                               today: CompetencyMath.dayKey(Date()))
        oneOnOneRequest = CompetencyOneOnOneRequest(subordinateId: subordinateId, candidates: list)
    }

    /// [v25.607 v5b] 候選議程用的 tabModel：〔目標 E2 ▾〕不疊時改用目前職等（差距那一種才有）；其他跟 model 一樣
    private func agendaModel() -> CompetencyTabModel {
        let mode: CompetencyTargetMode = targetMode == .off ? .current : targetMode
        return CompetencyMath.tabModel(setup: lifeStore.competencySetup,
                                       ratings: lifeStore.competencyRatings,
                                       subordinateId: subordinateId,
                                       archivedPerson: isArchived,
                                       sessions: lifeStore.competencySessions(of: subordinateId),
                                       today: CompetencyMath.dayKey(Date()),
                                       grades: lifeStore.competencyGradeContext(for: subordinateId),
                                       mode: mode)
    }

    /// [v25.600 職能雷達 v1a-2] 點一格的歷史（看不擋；唯讀、已轉出也能看）
    private func openHistory(groupId: UUID, itemId: UUID) {
        historyRequest = CompetencyCellHistoryRequest(subordinateId: subordinateId, groupId: groupId, itemId: itemId)
    }

    /// [v25.600 職能雷達 v1a-2] 評分紀錄一列 → 那一天的明細（看不擋；〔改分數〕〔改日期〕〔刪除〕在明細頁擋）
    /// [v25.606 v5a] 帶訓者記的那一列帶 raterKey（我評的 nil＝跟 v25.605 一模一樣）
    private func openRecord(_ row: CompetencyRecordRow) {
        recordRequest = CompetencyRecordRequest(subordinateId: subordinateId, dayKey: row.dayKey, raterKey: row.raterKey)
    }

    /// [v25.601 v1b] 〔目標 E2 ▾〕選單（只是看，不擋訂閱）
    private func pickTargetMode(_ mode: CompetencyTargetMode) {
        targetModeRaw = mode.rawValue
    }

    /// [v25.601 v1b] 〔設定職等〕：打開既有的部屬編輯表單（跟明細頁〔編輯〕同一個表單、同一個訂閱規矩）
    private func openGradeEdit() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        guard let s = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { return }
        gradeEdit = CompTabGradeEditRequest(subordinate: s)
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { toastText = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { toastText = nil }
        }
    }
}

// MARK: - sheet 請求（sheet(item:) 用）

/// 打開「職能項目」設定（sheet）
struct CompTabSetupRequest: Identifiable {
    let id = UUID()
}

/// 打開〔不用學的系統〕（打開那一刻的勾選當起點）
struct CompTabSkipRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
    let initialSkipped: Set<UUID>
}

// MARK: - 白卡（跟明細頁其他分頁一樣）

private struct CompTabCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 1))
            .padding(.horizontal)
    }
}

/// 區塊標頭（明細頁的 sectionHeader 是 private，這裡照它的樣子寫一份小的）
private struct CompTabHeader<Trailing: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(color)
                .frame(width: 4, height: 18)
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
            trailing()
        }
    }
}

// MARK: - 頂上一行（已轉出／這台比較舊／剛存好）

private struct CompTabNoticeLines: View {
    let archived: Bool
    let readOnly: Bool
    let toast: String?

    var body: some View {
        if archived || readOnly || toast != nil {
            VStack(alignment: .leading, spacing: 6) {
                if archived {
                    CompTabNoticeRow(icon: "archivebox.fill", text: "已轉出，評分留著可以看", color: .secondary)
                }
                if readOnly {
                    CompTabNoticeRow(icon: "exclamationmark.triangle.fill",
                                     text: "這台的 App 比較舊，評分請在已更新的那台做", color: .orange)
                }
                if let t = toast {
                    CompTabNoticeRow(icon: "checkmark.circle.fill", text: t, color: .green)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }
    }
}

private struct CompTabNoticeRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 還沒設定（空狀態）

private struct CompTabEmptyCard: View {
    let showsButtons: Bool
    let onSample: () -> Void
    let onBlank: () -> Void

    private static let message =
        "人格特質（例：團隊合作、領導力、學習能力）和要學的系統（例：Gas System 的 P&ID、緊急應變、值班技能），"
        + "設好就能幫每位同仁評分、畫雷達。"

    var body: some View {
        VStack(spacing: 14) {
            CompTabSampleArt()
                .frame(width: 120, height: 104)
                .accessibilityHidden(true)
            Text("還沒設定職能項目")
                .font(.headline)
            Text(Self.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showsButtons {
                buttons
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .modifier(CompTabCardStyle())
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onSample) {
                Text("用範例開始")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(Color.white)
                    .background(CompetencyPalette.trait, in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: onBlank) {
                Text("自己設定")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(CompetencyPalette.trait)
                    .background(CompetencyPalette.trait.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}

/// 灰色範例雷達：外圈三角形格線＋裡面一個淡灰三角形
private struct CompTabSampleArt: View {
    var body: some View {
        ZStack {
            CompTabSampleTriangle(scale: 1)
                .stroke(Color(.separator), lineWidth: 1)
            CompTabSampleTriangle(scale: 0.6)
                .stroke(Color(.separator).opacity(0.6), lineWidth: 1)
            CompTabSampleTriangle(scale: 0.75)
                .fill(Color.gray.opacity(0.18))
            CompTabSampleTriangle(scale: 0.75)
                .stroke(Color.gray.opacity(0.55), lineWidth: 1.5)
        }
    }
}

/// 正三角形（頂點在 12 點鐘、順時針），scale 是離中心的比例
struct CompTabSampleTriangle: Shape {
    var scale: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = min(rect.width, rect.height) / 2 * scale
        let cx: CGFloat = rect.midX
        let cy: CGFloat = rect.midY
        var p = Path()
        for i in 0..<3 {
            let a: Double = -Double.pi / 2 + Double(i) * 2 * Double.pi / 3
            let x: CGFloat = cx + radius * CGFloat(cos(a))
            let y: CGFloat = cy + radius * CGFloat(sin(a))
            if i == 0 {
                p.move(to: CGPoint(x: x, y: y))
            } else {
                p.addLine(to: CGPoint(x: x, y: y))
            }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - ① 摘要卡

private struct CompTabSummaryCard: View {
    let summary: CompetencySummaryModel
    let neverRated: Bool
    let canRate: Bool
    let showsSkipItem: Bool
    let showsOverlayToggle: Bool
    let overlayLabel: String
    /// [v25.600 v1a-2] 各張卡上一次不是同一天：「上一次：人格特質 4/30・Gas System 10/30…」（同一天 nil）
    let previousDayText: String?
    @Binding var showPrevious: Bool
    let onRate: () -> Void
    let onSkip: () -> Void
    let onSetup: () -> Void
    // [v25.601 職能雷達 v1b] 職等目標（nil＝整個設定一個目標都沒有：什麼都不畫）。要退回這一件：刪這四行與 targetLines、targetMenu
    let targets: CompetencyTargetSummary?
    let onPickMode: (CompetencyTargetMode) -> Void
    let onSetGrade: () -> Void
    /// 〔設定職等〕（已轉出、唯讀不出現；跟〔評分〕同條件）
    let canSetGrade: Bool
    // [v25.605 職能雷達 v4b] 「…」最前面〔給對方看〕（canShow）〔分享職能雷達…〕。要退回這一件：刪這三行與 menu 裡那幾行
    let canShowToPerson: Bool
    let onShow: () -> Void
    let onShare: () -> Void
    // [v25.606 職能雷達 v5a]「跟帶訓者差 2 級以上：…」一行；「…」〔帶訓者〕〔記帶訓者的評分…〕。要退回這一件：刪這五行與 mentorDiffView、menu 裡那兩段
    let mentorDiffLine: String?
    let showsMentorItem: Bool
    let mentorChoices: [CompetencyRaterChoice]
    let onMentors: () -> Void
    let onRateMentor: (CompetencyRaterChoice) -> Void
    // [v25.607 職能雷達 v5b]〔加到一對一議程…〕。要退回這一件：刪這兩行與 menu 裡那一段
    let showsOneOnOneItem: Bool
    let onOneOnOne: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CompTabHeader(title: "職能", icon: "graduationcap.fill", color: CompetencyPalette.trait) {
                menu
            }
            Text(summary.lastLine)
                .font(.footnote)
                .foregroundStyle(summary.stale ? Color.orange : Color.secondary)
            tiles
            targetLines
            mentorDiffView
            bottomRow
            previousDayLine
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .modifier(CompTabCardStyle())
    }

    private var menu: some View {
        Menu {
            if canShowToPerson {
                Button(action: onShow) {
                    Label("給對方看", systemImage: "person.crop.rectangle")
                }
            }
            Button(action: onShare) {
                Label("分享職能雷達…", systemImage: "square.and.arrow.up")
            }
            Divider()
            // [v25.606 v5a]〔帶訓者〕〔記帶訓者的評分…〕（都擋訂閱；已轉出、唯讀不出現）
            if showsMentorItem {
                Button(action: onMentors) {
                    Label("帶訓者", systemImage: "person.2")
                }
            }
            if !mentorChoices.isEmpty {
                Menu {
                    ForEach(mentorChoices) { c in
                        Button(Self.choiceTitle(c)) { onRateMentor(c) }
                    }
                } label: {
                    Label("記帶訓者的評分…", systemImage: "square.and.pencil")
                }
            }
            // [v25.607 v5b]〔加到一對一議程…〕（擋訂閱；唯讀、已轉出、沒有一對一會議不出現）
            if showsOneOnOneItem {
                Button(action: onOneOnOne) {
                    Label("加到一對一議程…", systemImage: "text.badge.plus")
                }
            }
            if showsSkipItem {
                Button(action: onSkip) {
                    Label("不用學的系統", systemImage: "minus.circle")
                }
            }
            Button(action: onSetup) {
                Label("職能項目設定", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(CompetencyPalette.trait)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("職能選項")
    }

    /// 三格：人格特質（nil 不出現）、本職學能（nil 不出現）、已評
    private var tiles: some View {
        HStack(alignment: .top, spacing: 8) {
            if let tv = summary.traitValueText {
                CompTabTile(label: "人格特質", value: tv, valueDim: false,
                            sub: summary.traitDeltaText, subColor: CompTabTile.deltaColor(summary.traitDeltaText))
            }
            if let sv = summary.skillValueText {
                CompTabTile(label: "本職學能", value: sv, valueDim: summary.skillLowCoverage,
                            sub: skillSub, subColor: skillSubColor)
            }
            CompTabTile(label: "已評", value: summary.filledText, valueDim: false,
                        sub: summary.skillFilledText, subColor: Color.secondary)
        }
    }

    /// 覆蓋不到一半：小字寫「只評了 1／9 格」；不然寫「↑0.9」
    private var skillSub: String? {
        summary.skillLowCoverage ? summary.skillCoverageText : summary.skillDeltaText
    }

    private var skillSubColor: Color {
        summary.skillLowCoverage ? Color.secondary : CompTabTile.deltaColor(summary.skillDeltaText)
    }

    /// [v25.601 v1b] 「E2 達標 10／12」等幾行（targets nil 什麼都不畫）
    @ViewBuilder
    private var targetLines: some View {
        if let t = targets {
            CompTabTargetLines(targets: t, canSetGrade: canSetGrade, onSetGrade: onSetGrade)
        }
    }

    /// [v25.606 v5a]〔記帶訓者的評分…〕子選單一列：「陳怡君」；已不在名冊「陳怡君（已不在名冊）」
    private static func choiceTitle(_ c: CompetencyRaterChoice) -> String {
        c.missing ? c.name + CompetencyMath.mentorMissingNote : c.name
    }

    /// [v25.606 v5a]「跟帶訓者差 2 級以上：Gas 值班技能（你 4、陳怡君 2）」（沒有不畫）
    @ViewBuilder
    private var mentorDiffView: some View {
        if let d = mentorDiffLine {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "person.2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(d)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// [v25.601 v1b] 「疊：〔上一次〕〔目標 E2 ▾〕〔評分〕」：一排放不下換兩行，再放不下一顆一行。
    /// 要退回這一件：換回 HStack { 上一次; Spacer; 評分 }
    private var bottomRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                overlayChips
                Spacer(minLength: 8)
                rateButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    overlayChips
                }
                rateRow
            }
            VStack(alignment: .leading, spacing: 8) {
                previousChip
                targetMenu
                rateRow
            }
        }
    }

    @ViewBuilder
    private var overlayChips: some View {
        previousChip
        targetMenu
    }

    @ViewBuilder
    private var previousChip: some View {
        if showsOverlayToggle {
            CompTabOverlayToggle(label: overlayLabel, isOn: $showPrevious)
        }
    }

    /// 〔目標 E2 ▾〕（chipTitle 有才有：沒設職等、職等被刪沒有）；前面沒有〔上一次〕時自己寫「疊：」
    @ViewBuilder
    private var targetMenu: some View {
        if let t = targets, let chip = t.chipTitle {
            CompTabTargetMenu(chipTitle: chip,
                              mode: t.mode,
                              currentTitle: t.currentOptionTitle,
                              nextTitle: t.nextOptionTitle,
                              showsLabel: !showsOverlayToggle,
                              onPick: onPickMode)
        }
    }

    @ViewBuilder
    private var rateButton: some View {
        if canRate {
            CompTabRateButton(title: neverRated ? "開始第一次評分" : "評分", action: onRate)
        }
    }

    @ViewBuilder
    private var rateRow: some View {
        if canRate {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                rateButton
            }
        }
    }

    /// [v25.600 職能雷達 v1a-2] 膠囊下面一行：每張卡自己的上一次日期（疊開著、而且各張不是同一天才有）。要退回這一件：刪這個 var 與上面那一行
    @ViewBuilder
    private var previousDayLine: some View {
        if showsOverlayToggle && showPrevious, let t = previousDayText {
            Text(t)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 一格（字級照 FinanceTileView：.caption2 標籤／.headline rounded heavy 數字／.caption2 小字）
private struct CompTabTile: View {
    let label: String
    let value: String
    let valueDim: Bool
    let sub: String?
    let subColor: Color

    /// ↑ 綠、↓ 橘、其他灰（[v25.600 v1a-2] 方向照 CompetencyMath.deltaDirection；要退回這一件：換回 hasPrefix 那三行）
    static func deltaColor(_ text: String?) -> Color {
        let d: Int = CompetencyMath.deltaDirection(text)
        if d > 0 { return Color.green }
        if d < 0 { return Color.orange }
        return Color.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(valueDim ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub ?? " ")
                .font(.caption2)
                .foregroundStyle(subColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 「疊：〔上一次 ✓〕」
private struct CompTabOverlayToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("疊：")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                isOn.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isOn ? "checkmark" : "circle")
                        .font(.caption2.weight(.bold))
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? CompetencyPalette.trait : Color.secondary)
                .background(isOn ? CompetencyPalette.trait.opacity(0.12) : Color(.tertiarySystemFill), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("疊" + label)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }
}

/// 右下大按鈕〔評分〕／〔開始第一次評分〕
private struct CompTabRateButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(Color.white)
            .background(CompetencyPalette.trait, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - [v25.600 職能雷達 v1a-2] iPad 兩欄、兩個 sheet、評分紀錄白卡（要退回這一件：刪到「不用學的系統那一行」之前）

private enum CompTabGrid {
    /// 固定兩欄（使用者要的是「iPad 兩欄」：人格＋Gas 一排、Slurry＋Chemical 一排）。卡片自己最寬 360、靠上對齊。
    /// [v1a-2 裁定] 原本 .adaptive(minimum: 320)：〔職能〕分頁是推進來全寬時橫放會變 3～4 欄、窄的 sheet 會變 1 欄，所以改成固定兩欄
    static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]
}

/// 評分紀錄明細、點一格的歷史（sheet(item:)＋.appStores()）
private struct CompTabHistorySheets: ViewModifier {
    @Binding var recordRequest: CompetencyRecordRequest?
    @Binding var historyRequest: CompetencyCellHistoryRequest?

    func body(content: Content) -> some View {
        content
            .sheet(item: $recordRequest) { r in
                CompetencyRecordDetailView(subordinateId: r.subordinateId, dayKey: r.dayKey, raterKey: r.raterKey)
                    .appStores()
            }
            .sheet(item: $historyRequest) { r in
                CompetencyCellHistorySheet(subordinateId: r.subordinateId, groupId: r.groupId, itemId: r.itemId)
                    .appStores()
            }
    }
}

/// [v25.605 v4b]〔分享職能雷達…〕（sheet(item:)；每次新的 id）
private struct CompTabShareRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
}

/// [v25.605 v4b] 給對方看（fullScreenCover）＋分享職能雷達（既有匯出頁、preset）；都 .appStores()
private struct CompTabShowShareSheets: ViewModifier {
    @Binding var showRequest: CompetencyShowRequest?
    @Binding var shareRequest: CompTabShareRequest?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $showRequest) { r in
                CompetencyShowView(subordinateId: r.subordinateId)
                    .appStores()
            }
            .sheet(item: $shareRequest) { r in
                SubordinateExportSheet(subordinateId: r.subordinateId, initialFormat: .image, mentioned: [],
                                       preset: .competencyOnly)
                    .appStores()
            }
    }
}

/// [v25.606 職能雷達 v5a]〔帶訓者〕頁（sheet(item:)＋.appStores()）
private struct CompTabMentorSheets: ViewModifier {
    @Binding var request: CompetencyMentorRequest?

    func body(content: Content) -> some View {
        content
            .sheet(item: $request) { r in
                CompetencyMentorView(subordinateId: r.subordinateId)
                    .appStores()
            }
    }
}

/// [v25.607 職能雷達 v5b] 升職快照明細、〔加到一對一議程…〕（sheet(item:)＋.appStores()）
private struct CompTabV5bSheets: ViewModifier {
    @Binding var milestoneRequest: CompetencyMilestoneRequest?
    @Binding var oneOnOneRequest: CompetencyOneOnOneRequest?
    let onAdded: (String) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $milestoneRequest) { r in
                CompetencyMilestoneView(subordinateId: r.subordinateId, promotionId: r.promotionId)
                    .appStores()
            }
            .sheet(item: $oneOnOneRequest) { r in
                CompetencyOneOnOneSheet(request: r, onAdded: onAdded)
                    .appStores()
            }
    }
}

/// [v25.607 職能雷達 v5b] 評分紀錄上面「升職」白卡：一筆升職一列（新的在前），點了開升職快照明細；現算的旁邊〔留一份〕
private struct CompTabPromotionCard: View {
    let rows: [CompetencyPromotionRow]
    /// 〔留一份〕（唯讀、已轉出 false：照樣列、只是看）
    let canKeep: Bool
    let onOpen: (CompetencyPromotionRow) -> Void
    let onKeep: (CompetencyPromotionRow) -> Void

    private static let baseNote: String = "升職那一天每一格最新的分數。"
    private static let computedNote: String = "以前的升職標「（現算）」，按〔留一份〕存下來。"

    /// 任何一列現算才寫後半句（唯讀、已轉出沒有〔留一份〕：不寫「按〔留一份〕」）
    private var footText: String {
        let anyComputed: Bool = rows.contains { $0.computed }
        return anyComputed && canKeep ? Self.baseNote + Self.computedNote : Self.baseNote
    }

    var body: some View {
        let lastId: UUID? = rows.last?.id
        return VStack(alignment: .leading, spacing: 6) {
            CompTabHeader(title: "升職", icon: "arrow.up.circle.fill", color: CompetencyPalette.trait) {
                EmptyView()
            }
            .padding(.bottom, 4)
            ForEach(rows) { row in
                CompTabPromotionRowView(row: row, canKeep: canKeep, onOpen: onOpen, onKeep: onKeep)
                if row.id != lastId {
                    Divider()
                }
            }
            Text(footText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .modifier(CompTabCardStyle())
    }
}

/// 「升職」一列：左邊「7/1 升 E3 資深工程師（那時 E2）（現算）」＋「12 格」›（點了開明細）；現算的右邊〔留一份〕。
/// 一排放不下（字最大）時〔留一份〕換到下一行
private struct CompTabPromotionRowView: View {
    let row: CompetencyPromotionRow
    let canKeep: Bool
    let onOpen: (CompetencyPromotionRow) -> Void
    let onKeep: (CompetencyPromotionRow) -> Void

    private var showsKeep: Bool { canKeep && row.computed }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                openButton
                keepButton
            }
            VStack(alignment: .leading, spacing: 4) {
                openButton
                keepButton
            }
        }
    }

    private var openButton: some View {
        Button {
            onOpen(row)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                CompTabPromotionTexts(row: row)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.accessibilityText)
        .accessibilityHint("看升職前的雷達")
    }

    @ViewBuilder
    private var keepButton: some View {
        if showsKeep {
            Button("留一份") { onKeep(row) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 44)
        }
    }
}

/// 「升職」一列的字：第一行標題（＋灰字「（現算）」），第二行「12 格」
private struct CompTabPromotionTexts: View {
    let row: CompetencyPromotionRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CompTabPromotionTitleLine(title: row.title, note: row.computedNote)
            Text(row.cellCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 標題＋灰字「（現算）」（字大時標題自己換行）
private struct CompTabPromotionTitleLine: View {
    let title: String
    let note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let n = note {
                Text(n)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 最下面「評分紀錄（N）」白卡：每列一天（新的在前），點了開明細。不是 List，所以不做往左滑（刪除在明細頁）。
private struct CompTabRecordsCard: View {
    let records: [CompetencyRecordRow]
    /// [v25.606 v5a] 整列傳出去（帶訓者那幾列要帶 raterKey）
    let onOpen: (CompetencyRecordRow) -> Void

    @State private var showAll = false

    private static let firstCount: Int = 6

    private var visible: [CompetencyRecordRow] {
        showAll ? records : Array(records.prefix(Self.firstCount))
    }

    private var hasMore: Bool { !showAll && records.count > Self.firstCount }

    var body: some View {
        let rows: [CompetencyRecordRow] = visible
        let lastId: String? = rows.last?.id
        let more: Bool = hasMore
        return VStack(alignment: .leading, spacing: 6) {
            CompTabHeader(title: "評分紀錄（\(records.count)）", icon: "clock.arrow.circlepath",
                          color: CompetencyPalette.trait) {
                EmptyView()
            }
            .padding(.bottom, 4)
            ForEach(rows) { row in
                CompTabRecordButton(row: row, onOpen: { _ in onOpen(row) })
                if row.id != lastId || more {
                    Divider()
                }
            }
            if more {
                CompTabShowAllButton(count: records.count) { showAll = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .modifier(CompTabCardStyle())
    }
}

/// 一列：「10/30（五）・2 次」＋小字「評了 人格・Gas System…」，右邊「12 格」›
private struct CompTabRecordButton: View {
    let row: CompetencyRecordRow
    let onOpen: (String) -> Void

    var body: some View {
        Button {
            onOpen(row.dayKey)
        } label: {
            HStack(spacing: 10) {
                CompTabRecordTexts(row: row)
                Spacer(minLength: 8)
                Text(row.cellCountText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Button 本身就是一個 VoiceOver 元素（念 label、可以按）；這裡只換念的字（不用 .accessibilityElement(children: .ignore)，那會蓋掉按的動作）
        .accessibilityLabel(spoken)
        .accessibilityHint("打開那一次的雷達")
    }

    /// [v25.601 v1b] 後面接「那時 E2 工程師」。要退回這一件：accessibilityLabel 換回 row.accessibilityText
    private var spoken: String {
        guard let g = row.gradeNote else { return row.accessibilityText }
        return row.accessibilityText + "，" + g
    }
}

private struct CompTabRecordTexts: View {
    let row: CompetencyRecordRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text(row.dayText)
                    .font(.subheadline.weight(.semibold))
                // [v25.606 職能雷達 v5a] 帶訓者記的那一列「・陳怡君（帶訓者）」。要退回這一件：刪這個 if
                if let w = row.raterText {
                    Text("・" + w)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let c = row.countText {
                    Text("・" + c)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(row.groupsText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // [v25.601 職能雷達 v1b] 那一張的職等跟現在不一樣：「那時 E2 工程師」。要退回這一件：刪這個 if
            if let g = row.gradeNote {
                Text(g)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 超過 6 列：最後一列「看全部（N）」
private struct CompTabShowAllButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("看全部（\(count)）")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CompetencyPalette.trait)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 不用學的系統那一行

private struct CompTabSkippedLine: View {
    let text: String
    let canEdit: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "minus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if canEdit {
                Button(action: onEdit) {
                    Text("改")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CompetencyPalette.system)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("改不用學的系統")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(minHeight: 48)
        .modifier(CompTabCardStyle())
    }
}

// MARK: - 〔不用學的系統〕sheet

private struct CompTabSkipSheet: View {
    let subordinateId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var skipped: Set<UUID>

    init(subordinateId: UUID, initialSkipped: Set<UUID>) {
        self.subordinateId = subordinateId
        _skipped = State(initialValue: initialSkipped)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(lifeStore.competencySetup.activeSystems) { g in
                        Toggle(g.displayName, isOn: learnBinding(g.id))
                    }
                } header: {
                    Text("要學的系統")
                } footer: {
                    Text("勾掉＝那張雷達不出現、分數留著；勾回來分數都在。")
                }
            }
            .navigationTitle("不用學的系統")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                }
            }
        }
    }

    /// 開著＝要學（不在 skipped 裡）
    private func learnBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { !skipped.contains(id) },
            set: { on in
                if on { skipped.remove(id) } else { skipped.insert(id) }
            }
        )
    }

    /// 先 dismiss，下一個 runloop 再寫 store（已停用系統原本勾掉的，照原樣留在 skipped 裡）
    private func save() {
        let result: Set<UUID> = skipped
        let sid: UUID = subordinateId
        let store: LifeStore = lifeStore
        dismiss()
        DispatchQueue.main.async {
            store.setCompetencySkippedSystems(sid, skipped: result)
        }
    }
}

// MARK: - [v25.601 職能雷達 v1b] 職等目標：摘要卡幾行、〔目標 E2 ▾〕、差距清單、〔設定職等〕（要退回這一件：刪到檔尾）

/// 〔設定職等〕打開既有的部屬編輯表單（sheet(item:) 用）
private struct CompTabGradeEditRequest: Identifiable {
    let id = UUID()
    let subordinate: Subordinate
}

/// 〔設定職等〕＝AddSubordinateView(editing:)（跟明細頁〔編輯〕同一個表單；職等改了有組織人員、名片、互評連動，只走原本那條路）
private struct CompTabGradeSheet: ViewModifier {
    @Binding var request: CompTabGradeEditRequest?

    func body(content: Content) -> some View {
        content
            .sheet(item: $request) { r in
                AddSubordinateView(editing: r.subordinate)
                    .appStores()
            }
    }
}

/// 摘要卡：「E2 達標 10／12」＋「離 E2 還差 2 格（差 2 級）・未評 2 格」；沒設職等一行＋〔設定職等〕；職等被刪、沒訂目標各一行橘字
private struct CompTabTargetLines: View {
    let targets: CompetencyTargetSummary
    let canSetGrade: Bool
    let onSetGrade: () -> Void

    /// 「離 E2 還差 2 格（差 2 級）・未評 2 格」（都沒有 nil）
    private var subLine: String? {
        let parts: [String] = [targets.gapCountText, targets.unratedText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let a = targets.achievedText {
                CompTabAchievedLine(achieved: a, sub: subLine)
            }
            if let n = targets.noGradeLine {
                CompTabNoGradeRow(text: n, canSetGrade: canSetGrade, onSetGrade: onSetGrade)
            }
            if let d = targets.deletedGradeLine {
                CompTabTargetNote(text: d)
            }
            if let n = targets.noTargetLine {
                CompTabTargetNote(text: n)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 「E2 達標 10／12」右邊（放不下就下一行）「離 E2 還差 2 格（差 2 級）・未評 2 格」
private struct CompTabAchievedLine: View {
    let achieved: String
    let sub: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                achievedText
                subText
            }
            VStack(alignment: .leading, spacing: 2) {
                achievedText
                subText
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var achievedText: some View {
        Text(achieved)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CompetencyPalette.trait)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var subText: some View {
        if let t = sub {
            Text(t)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 「設定職等後才有目標」〔設定職等〕
private struct CompTabNoGradeRow: View {
    let text: String
    let canSetGrade: Bool
    let onSetGrade: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if canSetGrade {
                Button(action: onSetGrade) {
                    Text("設定職等")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CompetencyPalette.trait)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityHint("打開這位同仁的資料，選職等")
            }
        }
    }
}

/// 職等被刪、這個職等還沒訂目標（橘字一行）
private struct CompTabTargetNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 〔目標 E2 ▾〕：目前職等／下一個職等（有才列）／不疊目標；打勾的那一項用 Label，其他用純字（不傳空的圖示名）
private struct CompTabTargetMenu: View {
    let chipTitle: String
    let mode: CompetencyTargetMode
    let currentTitle: String?
    let nextTitle: String?
    /// 前面沒有〔上一次〕時自己寫「疊：」
    let showsLabel: Bool
    let onPick: (CompetencyTargetMode) -> Void

    /// 選了「下一個職等」但沒有下一個：照目前職等算（CompetencyMath 也是），勾也打在目前職等
    private var shownMode: CompetencyTargetMode {
        if mode == .next && nextTitle == nil { return .current }
        return mode
    }

    private var isOn: Bool { shownMode != .off }

    var body: some View {
        HStack(spacing: 6) {
            if showsLabel {
                Text("疊：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Menu {
                if let t = currentTitle {
                    item(t, .current)
                }
                if let t = nextTitle {
                    item(t, .next)
                }
                item("不疊目標", .off)
            } label: {
                chip
            }
            .accessibilityLabel("疊目標，" + chipTitle)
            .accessibilityValue(isOn ? "疊著" : "沒有疊")
        }
    }

    @ViewBuilder
    private func item(_ title: String, _ m: CompetencyTargetMode) -> some View {
        if shownMode == m {
            Button {
                onPick(m)
            } label: {
                Label(title, systemImage: "checkmark")
            }
        } else {
            Button(title) {
                onPick(m)
            }
        }
    }

    /// 膠囊樣子照〔上一次〕：開＝紫字紫底、關＝灰
    private var chip: some View {
        HStack(spacing: 4) {
            Text(chipTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(isOn ? CompetencyPalette.trait : Color.secondary)
        .background(isOn ? CompetencyPalette.trait.opacity(0.12) : Color(.tertiarySystemFill), in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// 「離 E2 目標的差距」白卡：每列「Chemical System・緊急應變　2 → 3（差 1）」，點了打開那一格的歷史（看不擋）
private struct CompTabGapCard: View {
    let title: String
    let rows: [CompetencyGapRow]
    let onOpen: (UUID, UUID) -> Void

    @State private var showAll = false

    private static let firstCount: Int = 6

    /// 「離 E2 目標的差距」
    static func headerTitle(for t: CompetencyTargetSummary) -> String {
        guard let g = t.grade else { return "離目標的差距" }
        return "離 " + g.short + " 目標的差距"
    }

    private var visible: [CompetencyGapRow] {
        showAll ? rows : Array(rows.prefix(Self.firstCount))
    }

    private var hasMore: Bool { !showAll && rows.count > Self.firstCount }

    var body: some View {
        let list: [CompetencyGapRow] = visible
        let lastId: String? = list.last?.id
        let more: Bool = hasMore
        return VStack(alignment: .leading, spacing: 6) {
            CompTabHeader(title: title, icon: "scope", color: Color.orange) {
                EmptyView()
            }
            .padding(.bottom, 4)
            ForEach(list) { row in
                CompTabGapRowButton(row: row, onOpen: onOpen)
                if row.id != lastId || more {
                    Divider()
                }
            }
            if more {
                CompTabShowAllButton(count: rows.count) { showAll = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .modifier(CompTabCardStyle())
    }
}

private struct CompTabGapRowButton: View {
    let row: CompetencyGapRow
    let onOpen: (UUID, UUID) -> Void

    /// 「Chemical System・緊急應變，2 → 3，差 1」
    private var spoken: String {
        let d: String = row.detail
            .replacingOccurrences(of: "（", with: "，")
            .replacingOccurrences(of: "）", with: "")
        return row.title + "，" + d
    }

    var body: some View {
        Button {
            onOpen(row.groupId, row.itemId)
        } label: {
            HStack(spacing: 10) {
                Text(row.title)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(row.detail)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.orange)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityHint("打開這一格的歷史")
    }
}
