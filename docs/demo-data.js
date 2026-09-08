/* 示範資料：讓還沒設定 token 的人先看到版面。格式與 App 寫進 iCloud 的 JSON 完全相同
 *（日期為「距 2001-01-01 的秒數」，由 app.js 的 reviveDates 還原）。全部為虛構人名。 */
(function () {
  const REF = 978307200;
  const now = new Date();
  const d = (offsetDays, h = 9, m = 0) => { const x = new Date(now); x.setDate(x.getDate() + offsetDays); x.setHours(h, m, 0, 0); return x.getTime() / 1000 - REF; };
  const ymd = (y, mo, da, h = 0, mi = 0) => new Date(y, mo - 1, da, h, mi).getTime() / 1000 - REF;
  let seq = 0;
  const id = () => { seq++; const hex = seq.toString(16).toUpperCase().padStart(12, '0'); return `00000000-0000-4000-8000-${hex}`; };

  const D_EQ = id(), D_LAB = id(), D_PROD = id(), D_QA = id();
  const G1 = id(), G2 = id(), G3 = id();
  const P_ME = id(), P_QA1 = id(), P_QA2 = id(), P_PROD1 = id();

  const grades = [
    { id: G1, grade: 'E3', title: '工程師' },
    { id: G2, grade: 'E5', title: '資深工程師' },
    { id: G3, grade: 'M1', title: '課長' },
  ];

  const mkSub = (name, jobTitle, deptId, gradeId, opts) => Object.assign({
    id: id(), name, jobTitle, department: '', note: '', gradeTitleId: gradeId, departmentId: deptId,
    records: [], joinDate: ymd(2021, 3, 1), meetings: [], tasks: [], shifts: [], plantArea: 'P1',
    weeklyReports: [], equipments: [], promotions: [], birthday: null, birthdayEventId: null,
  }, opts);

  const task = (topic, content, dayOff, dueOff, done, extra) => Object.assign({
    id: id(), topic, content, date: d(dayOff, 9), dueDate: dueOff == null ? null : d(dueOff, 18),
    note: '', isCompleted: !!done, completedAt: done ? d(typeof done === 'number' ? done : dueOff ?? dayOff, 15) : null,
    responseAction: '', responseResult: '', isDereliction: false,
  }, extra || {});
  const item = (content, assignee, done, dueOff) => ({ id: id(), content, assigneeIds: assignee ? [assignee] : [], dueDate: dueOff == null ? null : d(dueOff, 18), isCompleted: !!done, completedAt: done ? d(dueOff ?? 0, 16) : null, note: '' });
  const rec = (type, content, dayOff, extra) => Object.assign({ id: id(), type, content, date: d(dayOff, 10), endDate: null, note: '' }, extra || {});
  const report = (topic, type, dayOff, done, lateDays) => ({ id: id(), topic, date: d(dayOff, 9), note: '', isCompleted: !!done, completedAt: done ? d(dayOff + (lateDays || 0), lateDays ? 17 : 8) : null, reportType: type });

  const A = mkSub('王小明', '資深工程師', D_EQ, G2, { joinDate: ymd(2019, 7, 15), birthday: ymd(1990, now.getMonth() + 1, Math.min(28, now.getDate() + 3)) });
  const B = mkSub('李佳穎', '工程師', D_EQ, G1, { joinDate: ymd(2022, 2, 14), birthday: ymd(1995, 11, 3) });
  const C = mkSub('陳志豪', '工程師', D_LAB, G1, { joinDate: ymd(2023, 9, 1), birthday: ymd(1997, now.getMonth() + 1, now.getDate()) });
  const E = mkSub('林雅婷', '資深工程師', D_LAB, G2, { joinDate: ymd(2018, 5, 20), plantArea: 'P2' });
  const F = mkSub('張建國', '課長', D_PROD, G3, { joinDate: ymd(2015, 1, 5), birthday: ymd(1985, 4, 18) });
  const G = mkSub('黃冠宇', '工程師', D_PROD, G1, { joinDate: ymd(2024, 6, 3) });

  const EQ1 = id(), EQ2 = id(), EQ3 = id(), EQ4 = id(), EQ5 = id();

  A.tasks = [
    task('CDA 壓縮機油品更換', '依 PM 計畫更換 #2 壓縮機潤滑油，回報油品分析。', -20, -14, -14),
    task('冰水主機效率評估', '整理 7 月 COP 曲線，提出節能建議。', -12, -2, -1),
    task('P1 廢水 pH 異常追查', '追查 8/28 pH 飄移原因並提出對策。', -9, -3, false),
    task('年度 PM 排程彙整', '彙整全部門 Q4 PM 排程。', -5, 10, false),
    task('@李佳穎 交接 CDA 系統', '帶新人熟悉 CDA 系統圖與巡檢點。', -30, -25, -25, { customScore: 5 }),
  ];
  A.meetings = [
    { id: id(), topic: '設備課週會', date: d(-28, 14, 0), durationMinutes: 60, rule: { frequency: '每週', weekdays: [3], endDate: null }, items: [], note: '', createdAt: d(-28, 9), occurrences: [
      { id: id(), scheduledDate: d(-7, 14, 0), movedTo: null, isCancelled: false, isAdHoc: false, items: [item('CDA 洩漏點盤點', A.id, true, -5), item('冰機保養報價', B.id, true, -4), item('廢水系統圖更新', B.id, false, 3)] },
    ] },
    { id: id(), topic: '節能專案啟動', date: d(2, 10, 0), durationMinutes: 90, rule: null, items: [item('蒐集各系統用電基線', A.id, false, 9), item('簡報初稿', B.id, false, 12)], note: '與 @張建國 協調產線配合時段', createdAt: d(-3, 9), occurrences: [] },
  ];
  A.weeklyReports = [report('冰水系統 8 月月報', '月報', -8, true), report('第 36 週週報', '周報', -1, true, 1), report('第 37 週週報', '周報', 6, false)];
  A.records = [rec('優點', '主動整理系統圖，交接完整', -40), rec('成就', '節能提案獲廠區採用', -60), rec('改善', '巡檢表數位化', -15), rec('請假', '', -33, { leaveType: '特休', leaveHours: 8 }), rec('請假', '', -70, { leaveType: '病假', leaveHours: 4 })];
  A.promotions = [{ id: id(), date: ymd(2023, 1, 1), fromTitle: 'E3 工程師', toTitle: 'E5 資深工程師', toGradeTitleId: G2, note: '' }];

  B.tasks = [
    task('冰機 A 保養報價比較', '取得三家報價並比較。', -15, -8, -9),
    task('CDA 巡檢表修訂', '依新系統圖更新巡檢點。', -10, -6, false),
    task('未回報 8/30 夜班巡檢', '應做未作為：漏填夜班巡檢紀錄。', -8, -8, -7, { isDereliction: true, customScore: -1 }),
    task('廢水系統圖更新', '更新 P1 廢水系統 P&ID。', -4, 3, false),
  ];
  B.weeklyReports = [report('第 36 週週報', '周報', -1, true), report('新人報告：CDA 系統', '新人報', 4, false)];
  B.records = [rec('優點', '學習態度積極', -20), rec('缺點', '紀錄常漏填', -8), rec('Miss Operation', '誤關 CDA 旁通閥', -25, { severity: '輕微' }), rec('請假', '', -12, { leaveType: '事假', leaveHours: 8 })];

  C.tasks = [
    task('實驗室氣體鋼瓶盤點', '盤點所有鋼瓶效期與壓力。', -18, -10, -10),
    task('純水機濾心更換', '更換 RO 前置濾心。', -7, -1, false),
    task('氣體偵測器校正', '半年校正。', -3, 14, false),
  ];
  C.meetings = [{ id: id(), topic: '實驗室安全月會', date: d(-40, 15, 0), durationMinutes: 45, rule: { frequency: '每月', weekdays: [], endDate: null }, items: [], note: '', createdAt: d(-40, 9), occurrences: [
    { id: id(), scheduledDate: d(-10, 15, 0), movedTo: null, isCancelled: false, isAdHoc: false, items: [item('鋼瓶固定鏈檢查', C.id, true, -8), item('緊急沖淋測試', E.id, true, -8)] },
  ] }];
  C.weeklyReports = [report('第 36 週週報', '周報', -1, false)];
  C.records = [rec('改善', '鋼瓶標示改色碼', -30), rec('請假', '', -5, { leaveType: '喪假', leaveHours: 16 })];

  E.tasks = [
    task('新儀器驗收', 'GC-MS 驗收與 SOP 撰寫。', -25, -12, -11),
    task('SOP 年度審查', '審查 12 份 SOP。', -20, -15, -14, { customScore: 4 }),
    task('化學品庫存系統上線', '導入條碼管理。', -14, 20, false),
    task('@陳志豪 帶教純水系統', '交接純水系統維護。', -6, 1, false),
  ];
  E.weeklyReports = [report('儀器驗收報告', 'PM', -12, true), report('第 36 週週報', '周報', -1, true), report('8 月月報', '月報', -5, true, 2)];
  E.records = [rec('成就', '主導 GC-MS 導入', -12), rec('優點', '文件品質高', -50), rec('優點', '樂於教新人', -3)];
  E.promotions = [{ id: id(), date: ymd(2022, 7, 1), fromTitle: 'E3 工程師', toTitle: 'E5 資深工程師', toGradeTitleId: G2, note: '' }];

  F.tasks = [task('產線 Q4 人力規劃', '', -10, 5, false), task('新機台 SAT 協調', '', -30, -20, -18), task('稽核缺失改善回覆', '', -15, -10, false)];
  F.meetings = [{ id: id(), topic: '產線日會', date: d(-14, 8, 30), durationMinutes: 20, rule: { frequency: '每日', weekdays: [], endDate: d(30) }, items: [], note: '', createdAt: d(-14), occurrences: [] }];
  F.weeklyReports = [report('第 36 週週報', '周報', -1, true), report('稽核回覆報告', 'PM', -3, false)];
  F.records = [rec('優點', '跨部門協調能力強', -22), rec('缺失', '稽核未如期回覆', -9), rec('請假', '', -18, { leaveType: '公假', leaveHours: 8 })];

  G.tasks = [task('產線 5S 巡檢', '', -9, -2, -2), task('新人訓練課程', '', -30, -1, false), task('包裝機異常紀錄整理', '', -4, 6, false)];
  G.weeklyReports = [report('新人報告：包裝線', '新人報', -2, true, 1)];
  G.records = [rec('缺點', '報告常遲交', -6), rec('Miss Operation', '未依 SOP 停機', -16, { severity: '一般' }), rec('請假', '', -2, { leaveType: '事假', leaveHours: 4 })];

  const subs = [A, B, C, E, F, G];

  const depts = [
    { id: D_EQ, code: 'FAC-EQ', name: '設備課', function: '廠務設備（CDA、冰水、廢水）維運與 PM', upstreamIds: [D_PROD], downstreamIds: [], peerIds: [D_LAB], managerIds: [P_ME] },
    { id: D_LAB, code: 'FAC-LAB', name: '實驗室', function: '氣體化學分析、純水與化學品管理', upstreamIds: [D_PROD], downstreamIds: [], peerIds: [D_EQ], managerIds: [P_ME] },
    { id: D_PROD, code: 'MFG-1', name: '製造一課', function: '產線生產與包裝', upstreamIds: [], downstreamIds: [D_EQ, D_LAB, D_QA], peerIds: [], managerIds: [P_PROD1] },
    { id: D_QA, code: 'QA', name: '品保課', function: '進料／出貨檢驗、稽核', upstreamIds: [D_PROD], downstreamIds: [], peerIds: [], managerIds: [P_QA1] },
  ];

  const orgPeople = [
    { id: P_ME, name: '我', jobTitle: '副理', departmentId: D_EQ, birthday: null, relationship: '', note: '', children: [], relations: [], dateAdded: ymd(2024, 1, 1), isInactive: false, leftDate: null, gradeTitleId: null, works: [] },
    { id: id(), name: '王小明', jobTitle: '資深工程師', departmentId: D_EQ, relationship: '', note: '', children: [], relations: [], dateAdded: ymd(2024, 1, 1), isInactive: false, linkedSubordinateId: A.id, gradeTitleId: G2, works: [] },
    { id: id(), name: '李佳穎', jobTitle: '工程師', departmentId: D_EQ, relationship: '', note: '', children: [], relations: [], dateAdded: ymd(2024, 1, 1), isInactive: false, linkedSubordinateId: B.id, gradeTitleId: G1, works: [] },
    { id: id(), name: '陳志豪', jobTitle: '工程師', departmentId: D_LAB, relationship: '', note: '', children: [], relations: [], dateAdded: ymd(2024, 1, 1), isInactive: false, linkedSubordinateId: C.id, gradeTitleId: G1, works: [] },
    { id: id(), name: '林雅婷', jobTitle: '資深工程師', departmentId: D_LAB, relationship: '', note: '', children: [], relations: [], dateAdded: ymd(2024, 1, 1), isInactive: false, linkedSubordinateId: E.id, gradeTitleId: G2, works: [] },
    { id: P_PROD1, name: '張建國', jobTitle: '課長', departmentId: D_PROD, relationship: '', note: '', children: [], relations: [], dateAdded: ymd(2024, 1, 1), isInactive: false, linkedSubordinateId: F.id, gradeTitleId: G3, works: [] },
    { id: id(), name: '黃冠宇', jobTitle: '工程師', departmentId: D_PROD, relationship: '', note: '', children: [], relations: [], dateAdded: ymd(2024, 1, 1), isInactive: false, linkedSubordinateId: G.id, gradeTitleId: G1, works: [] },
    { id: P_QA1, name: '吳美玲', jobTitle: '品保課長', departmentId: D_QA, relationship: '稽核窗口', note: '', children: [], relations: [], dateAdded: ymd(2024, 1, 1), isInactive: false, gradeTitleId: null, works: [{ id: id(), title: '年度稽核總結報告', date: d(-20) }] },
    { id: P_QA2, name: '許志偉', jobTitle: '品保工程師', departmentId: D_QA, relationship: '', note: '', children: [], relations: [], dateAdded: ymd(2024, 1, 1), isInactive: true, leftDate: d(-90), gradeTitleId: null, works: [] },
    { id: id(), name: '劉大偉', jobTitle: '顧問', departmentId: null, relationship: '外部顧問', note: '', children: [], relations: [], dateAdded: ymd(2024, 1, 1), isInactive: false, gradeTitleId: null, works: [] },
  ];

  const pm = (dayOff, phase, note) => ({ id: id(), date: d(dayOff, phase === '完成復機' ? 16 : 8), note: note || '', phase });
  const alarm = (dayOff, h, content) => ({ id: id(), date: d(dayOff, h), content });
  const equipment = [
    { id: EQ1, name: 'CDA 壓縮機 #1', note: '2F 機械室', pmRecords: [pm(-45, '停機', '季保'), pm(-45, '完成復機'), pm(-3, '停機', '油品更換')], alarms: [alarm(-30, 3, '排氣溫度高'), alarm(-2, 22, '油壓低')], departmentId: D_EQ, ownerId: A.id, system: 'CDA' },
    { id: EQ2, name: 'CDA 壓縮機 #2', note: '', pmRecords: [pm(-14, '停機'), pm(-14, '完成復機')], alarms: [], departmentId: D_EQ, ownerId: A.id, system: 'CDA' },
    { id: EQ3, name: '冰水主機 A', note: 'RT-500', pmRecords: [pm(-60, null, '年保')], alarms: [alarm(-12, 14, '冷凝壓力高'), alarm(-11, 15, '冷凝壓力高'), alarm(-1, 9, '冷卻水流量低')], departmentId: D_EQ, ownerId: B.id, system: '冰水' },
    { id: EQ4, name: '純水機 RO-1', note: '', pmRecords: [pm(-7, '停機', '濾心更換'), pm(-7, '完成復機')], alarms: [alarm(-8, 10, '進水壓力低')], departmentId: D_LAB, ownerId: C.id, system: '純水' },
    { id: EQ5, name: 'GC-MS', note: '', pmRecords: [pm(-20, null, '原廠保養')], alarms: [], departmentId: D_LAB, ownerId: E.id, system: '分析' },
  ];

  // 警報自動掛任務：EQ1「油壓低」→ 王小明處理中；冰水主機「冷卻水流量低」→ 李佳穎已回報完成
  const alarmOil = equipment[0].alarms[1], alarmFlow = equipment[2].alarms[2];
  A.tasks.push({ id: id(), topic: '警報處理：油壓低', content: 'CDA 壓縮機 #1 油壓低警報', date: alarmOil.date, dueDate: d(0, 18), note: '', isCompleted: false, completedAt: null,
    equipmentLink: { equipmentId: EQ1, alarmId: alarmOil.id, equipmentName: 'CDA 壓縮機 #1', system: 'CDA' }, responseAction: '已補油並檢查油位開關，觀察中', responseResult: '', isDereliction: false });
  B.tasks.push({ id: id(), topic: '警報處理：冷卻水流量低', content: '冰水主機 A 冷卻水流量低', date: alarmFlow.date, dueDate: d(0, 18), note: '', isCompleted: true, completedAt: d(-1, 14),
    equipmentLink: { equipmentId: EQ3, alarmId: alarmFlow.id, equipmentName: '冰水主機 A', system: '冰水' }, responseAction: '清洗 Y 型過濾器', responseResult: '流量恢復 120 m³/h，警報解除', isDereliction: false });

  const M1 = id(), M2 = id();
  const milestones = [
    { id: id(), title: '氣體化學執行秘書', date: ymd(2025, 1, 1), category: '職涯', note: '', careerSubCategory: 'sideRole', sideRoleName: '氣體化學執行秘書', sideRoleOrg: '台灣氣體化學工業協會', sideRoleIsLead: true, sideRoleScope: '廠內特殊氣體與化學品安全、供應商評鑑、季度統計',
      sideRoleResolutions: (() => { const R1 = id(), R2 = id(); return [
        { id: R1, date: ymd(2026, 3, 12), title: '鋼瓶櫃改為雙迴路排氣', content: '因 F1 鋼瓶櫃排氣單迴路在停電時無備援，決議所有毒性氣體鋼瓶櫃改為雙迴路排氣，Q2 前完成。\n預算 120 萬，由廠務設備課執行。', site: 'F1', categories: ['GAS', '安全'], initiator: '吳美玲', serial: 1, references: [] },
        { id: R2, date: ymd(2026, 6, 20), title: '雙迴路排氣驗收標準', content: '依 #001 決議，驗收標準：\n1. 單迴路失效時 30 秒內切換\n2. 櫃內負壓維持 -50 Pa 以上\n3. 每季測試一次並留紀錄', site: 'F1', categories: ['GAS'], initiator: '林雅婷', serial: 2, references: [R1] },
        { id: id(), date: d(-12), title: '化學品倉庫溫濕度監控上線', content: '倉庫加裝溫濕度感測並接上中控，超限即通知值班人員；歷史資料保存一年。', site: 'F2', categories: ['CHM'], initiator: '王小明', serial: 3, references: [] },
      ]; })(),
      sideRoleMeetings: [{ id: id(), date: ymd(2026, 6, 18, 14, 0), topic: '第二季氣化委員會', attendees: ['吳美玲', '林雅婷', '陳志豪', '大同氣體 陳經理'], decisions: '雙迴路排氣驗收標準定案（見決議 #002）；下季啟動供應商評鑑。', note: '' }, { id: id(), date: d(-9, 10, 0), topic: '供應商評鑑前置會', attendees: ['陳志豪', '林雅婷'], decisions: '評鑑表由陳志豪 9/20 前擬定。', note: '' }],
      sideRoleKeyDates: [{ id: id(), date: d(9, 9, 0), title: '供應商評鑑現場稽核', remindDaysBefore: 3, note: '大同氣體 竹北廠' }, { id: id(), date: d(25, 14, 0), title: '第三季氣化委員會', remindDaysBefore: 7, note: '' }, { id: id(), date: ymd(2026, 6, 18, 14, 0), title: '第二季氣化委員會', remindDaysBefore: null, note: '' }],
      sideRoleMembers: [{ id: M1, name: '林雅婷', dutyInRole: '分析', contact: '', linkedPersonId: E.id, note: '' }, { id: M2, name: '陳志豪', dutyInRole: '鋼瓶', contact: '', linkedPersonId: C.id, note: '' }],
      sideRoleTasks: [{ id: id(), content: '季度氣體用量統計', dueDate: d(-5), isCompleted: true, completedAt: d(-6), note: '', assigneeIds: [M1], categories: ['統計'] }, { id: id(), content: '鋼瓶供應商評鑑', dueDate: d(12), isCompleted: false, completedAt: null, note: '含大同氣體現場稽核', assigneeIds: [M2], extraAssignees: ['吳美玲'], categories: ['評鑑'] }, { id: id(), content: '雙迴路排氣季測試（Q3）', dueDate: d(-3), isCompleted: false, completedAt: null, note: '', assigneeIds: [M1], categories: ['GAS'] }, { id: id(), content: '安全教育訓練教材', dueDate: d(-1), isCompleted: true, completedAt: d(-2), note: '', assigneeIds: [M1, M2], categories: [] }] },
    { id: id(), title: '尾牙負責人', date: ymd(2025, 10, 1), category: '職涯', note: '2025 年尾牙總召', careerSubCategory: 'sideRole', sideRoleName: '尾牙負責人', sideRoleOrg: '員工福委會', sideRoleIsLead: true, sideRoleEndDate: ymd(2026, 2, 1), sideRoleScope: '場地、節目、預算',
      sideRoleMembers: [{ id: id(), name: '黃冠宇', dutyInRole: '場控', contact: '', linkedPersonId: G.id, note: '' }],
      sideRoleTasks: [{ id: id(), content: '場地簽約', dueDate: ymd(2025, 11, 15), isCompleted: true, completedAt: ymd(2025, 11, 10), note: '', assigneeIds: [], categories: ['場地'] }],
      sideRoleResolutions: [{ id: id(), date: ymd(2025, 11, 5), title: '場地定案：竹北喜來登', content: '兩家比價後選定，預算 85 萬含餐。', site: '', categories: ['場地'], initiator: '我', serial: 1, references: [] }],
      sideRoleMeetings: [], sideRoleKeyDates: [{ id: id(), date: ymd(2026, 1, 23, 18, 0), title: '尾牙正式日', remindDaysBefore: 7, note: '' }] },
  ];

  const cards = [
    { id: id(), name: '吳美玲', company: '本公司', department: '品保課', jobTitle: '品保課長', phones: ['03-5678900 #201'], emails: ['meiling.wu@example.com'], faxes: [], address: '新竹縣竹北市光明六路 100 號', note: '稽核窗口，回覆快。', date: ymd(2024, 3, 12), primaryBusiness: '進料／出貨檢驗、內部稽核', linkedOrgPersonId: P_QA1 },
    { id: id(), name: '陳建豪', company: '大同氣體', department: '業務部', jobTitle: '業務經理', phones: ['0912-345-678', '03-5551234'], emails: ['jh.chen@example-gas.com'], faxes: ['03-5551235'], address: '新竹縣竹北市興隆路一段 50 號', note: '特殊氣體供應商，季度評鑑對口。報價可談 3~5%。', date: ymd(2025, 6, 3), primaryBusiness: '特殊氣體、鋼瓶配送' },
    { id: id(), name: '林淑芬', company: '永豐冷凍空調', department: '', jobTitle: '技術服務主任', phones: ['0933-221-100'], emails: ['sf.lin@example-hvac.com'], faxes: [], address: '桃園市中壢區中華路二段 88 號', note: '冰水主機年度保養廠商，24H 緊急叫修。', date: ymd(2025, 11, 20), primaryBusiness: '冰水主機保養、冷卻水塔' },
    { id: id(), name: '王志明', company: '永豐冷凍空調', department: '工程部', jobTitle: '工程師', phones: ['0955-778-899'], emails: [], faxes: [], address: '', note: '現場施工窗口。', date: ymd(2026, 1, 8), primaryBusiness: '' },
    { id: id(), name: '張安倫', company: '安倫科技', department: '總經理室', jobTitle: '總經理', phones: ['+886-2-27001234'], emails: ['enzo.chang@example-tech.com'], faxes: ['+886-2-27001235'], address: '台北市信義區松高路 11 號', note: '尾牙場地合作、贊助洽談。', date: ymd(2026, 4, 15), primaryBusiness: '自動化設備整合' },
    { id: id(), name: '黃冠宇', company: '本公司', department: '製造一課', jobTitle: '工程師', phones: ['分機 315'], emails: [], faxes: [], address: '', note: '', date: ymd(2025, 8, 1), primaryBusiness: '', linkedOrgPersonId: null },
  ];

  const personalEvents = [
    { id: id(), title: '主管週會', kind: '會議', date: d(-21, 9, 30), durationMinutes: 60, note: '', recurrence: '每週', recurrenceEndDate: null, reminderMinutes: 15, location: '3F 會議室', syncToAppleCalendar: false },
    { id: id(), title: '繳交月報', kind: '事務', date: d(4, 0, 0), durationMinutes: 0, note: '', recurrence: '每月', recurrenceEndDate: null, reminderMinutes: 1440, location: '', syncToAppleCalendar: false },
    { id: id(), title: '牙醫回診', kind: '事務', date: d(6, 18, 30), durationMinutes: 30, note: '', recurrence: '不重複', recurrenceEndDate: null, reminderMinutes: 60, location: '', syncToAppleCalendar: false },
  ];
  // ---- 理財示範 ----
  const BANK1 = id(), BANK2 = id(), CARD1 = id(), SEC1 = id(), VEH1 = id();
  const dep = (dayOff, amount, isWithdrawal, cur = 'NT$') => ({ id: id(), date: d(dayOff, 12), amount, currencyCode: cur, isWithdrawal, isAdjust: false });
  milestones.push(
    { id: BANK1, title: '玉山薪轉戶', date: ymd(2019, 3, 1), category: '成就', note: '', financeSubCategory: '銀行', bankName: '玉山銀行', branchName: '竹科分行', bankAccountType: '活存',
      bankDeposits: [dep(-400, 350000, false), dep(-200, 60000, true), dep(-90, 120000, false), dep(-40, 45000, true), dep(-20, 30000, false)] },
    { id: BANK2, title: '國泰外幣戶', date: ymd(2021, 6, 1), category: '成就', note: '', financeSubCategory: '銀行', bankName: '國泰世華', branchName: '', bankAccountType: '外幣',
      bankDeposits: [dep(-300, 8000, false, '美金'), dep(-100, 2500, false, '美金'), dep(-60, 1200, true, '美金')] },
    { id: CARD1, title: '玉山 U Bear 卡', date: ymd(2022, 1, 1), category: '成就', note: '', financeSubCategory: '信用卡', cardName: 'U Bear', cardLastFour: '3388', creditLimit: 200000, annualFee: 0, billingDay: 5, paymentDay: 20, linkedBankMilestoneId: BANK1 },
    { id: SEC1, title: '永豐金證券', date: ymd(2020, 4, 1), category: '成就', note: '', financeSubCategory: '證券', securitiesAccountType: '台股' },
    { id: id(), title: '南山儲蓄險', date: ymd(2018, 8, 11), category: '成就', note: '', financeSubCategory: '保險', insuranceCompany: '南山人壽', insuranceType: '儲蓄險', policyNumber: 'NS-2018-0811', premiumAmount: 67000, beneficiary: '配偶' },
  );
  const expense = (title, amount, dayOff, type, cat, extra) => Object.assign({ id: id(), title, amount, date: d(dayOff, 12), expenseType: type, note: '', currencyCode: 'NT$', photoFileNames: [], amountHistory: [] }, type === '固定支出' ? { fixedCategory: cat } : { variableCategory: cat }, extra || {});
  const expenses = [
    expense('房貸', 32000, -700, '固定支出', '貸款', { recurrence: '每月', linkedBankMilestoneId: BANK1 }),
    expense('中華電信', 1399, -500, '固定支出', '電信費', { recurrence: '每月', linkedCreditCardMilestoneId: CARD1 }),
    expense('Netflix', 390, -400, '固定支出', '訂閱服務', { recurrence: '每月', linkedCreditCardMilestoneId: CARD1 }),
    expense('乙式車險', 28500, -320, '固定支出', '保險', { recurrence: '每年', linkedBankMilestoneId: BANK1 }),
    expense('社區管理費', 2400, -600, '固定支出', '管理費', { recurrence: '每月', linkedBankMilestoneId: BANK1 }),
    expense('好市多採買', 6800, -3, '變動支出', '日用品', { linkedCreditCardMilestoneId: CARD1 }),
    expense('家庭聚餐', 3200, -6, '變動支出', '飲食', { linkedCreditCardMilestoneId: CARD1 }),
    expense('加油', 1500, -9, '變動支出', '汽車'),
    expense('小孩補習費', 8000, -12, '變動支出', '教育'),
    expense('電動車充電', 620, -2, '變動支出', '汽車', { evKwh: 42, evFromPct: 20, evToPct: 90, evOdometer: 31250, linkedVehicleId: VEH1, vehicleExpenseCategory: '電費' }),
    expense('電動車充電', 540, -16, '變動支出', '汽車', { evKwh: 38, evFromPct: 25, evToPct: 85, evOdometer: 30810, linkedVehicleId: VEH1, vehicleExpenseCategory: '電費' }),
    expense('電動車充電', 700, -33, '變動支出', '汽車', { evKwh: 45, evFromPct: 15, evToPct: 90, evOdometer: 30320, linkedVehicleId: VEH1, vehicleExpenseCategory: '電費' }),
    expense('停車費', 1200, -20, '變動支出', '汽車', { linkedVehicleId: VEH1, vehicleExpenseCategory: '停車' }),
    expense('輪胎更換', 18000, -150, '變動支出', '汽車', { linkedVehicleId: VEH1, vehicleExpenseCategory: '保養' }),
    expense('牙醫', 1200, -18, '變動支出', '醫療'),
    expense('週年旅行', 24000, -45, '變動支出', '娛樂', { linkedCreditCardMilestoneId: CARD1 }),
    expense('婚禮禮金', 6000, -70, '變動支出', '社交'),
    expense('新手機', 32900, -100, '變動支出', '購物', { linkedCreditCardMilestoneId: CARD1 }),
    expense('家電維修', 4500, -130, '變動支出', '其他'),
    expense('綜所稅', 68000, -110, '變動支出', '稅費'),
  ];
  const incomes = [
    { id: id(), title: '薪資', amount: 98000, date: ymd(2024, 1, 5), category: '薪水', period: '每月', isFixedSalary: true, note: '', linkedBankMilestoneId: BANK1, linkedBankCurrency: 'NT$', endDate: null },
    { id: id(), title: '年終獎金', amount: 180000, date: ymd(2026, 2, 5), category: '獎金', period: '單次', isFixedSalary: false, note: '', linkedBankMilestoneId: BANK1, linkedBankCurrency: 'NT$' },
    { id: id(), title: '0056 配息', amount: 12600, date: d(-25), category: '投資', period: '單次', isFixedSalary: false, note: '' },
  ];
  const currencyRates = [{ id: id(), code: '美金', rate: 32.1 }, { id: id(), code: '日圓', rate: 0.21 }];
  const tx = (dayOff, kind, lots, price) => ({ id: id(), date: d(dayOff, 9), kind, lots, price });
  const stocks = [
    { id: id(), name: '台積電', symbol: '2330', purchaseDate: ymd(2023, 5, 10), shares: 2000, purchasePrice: 560, currentPrice: 1085, note: '', isSold: false, soldPrice: 0, soldDate: null, linkedSecuritiesMilestoneId: SEC1, transactions: [tx(-480, '買入', 1, 540), tx(-300, '買入', 1, 580)], dividends: [{ id: id(), date: d(-60), kind: '現金股利', lots: 2, perShare: 4.5, sharesAtEvent: 2000, note: '' }] },
    { id: id(), name: '元大高股息', symbol: '0056', purchaseDate: ymd(2022, 9, 1), shares: 15000, purchasePrice: 31.2, currentPrice: 38.4, note: '', isSold: false, soldPrice: 0, soldDate: null, linkedSecuritiesMilestoneId: SEC1, transactions: [tx(-700, '買入', 10, 30.5), tx(-350, '買入', 5, 32.6)], dividends: [{ id: id(), date: d(-25), kind: '現金股利', lots: 15, perShare: 0.84, sharesAtEvent: 15000, note: '' }] },
    { id: id(), name: 'Vanguard S&P 500', symbol: 'VOO', purchaseDate: ymd(2025, 3, 3), shares: 12, purchasePrice: 512, currentPrice: 598, note: '', isSold: false, soldPrice: 0, soldDate: null, linkedBankMilestoneId: BANK2, linkedBankCurrency: '美金', transactions: [{ id: id(), date: ymd(2025, 3, 3), kind: '買入', lots: 0.012, price: 512 }], dividends: [] },
    { id: id(), name: '長榮', symbol: '2603', purchaseDate: ymd(2024, 2, 1), shares: 1000, purchasePrice: 150, currentPrice: 0, note: '', isSold: true, soldPrice: 205, soldDate: ymd(2024, 8, 20), transactions: [], dividends: [] },
  ];
  const insurances = [{ id: id(), name: '美元儲蓄險', company: '南山人壽', currencyCode: '美金', premiumAmount: 2100, paymentPeriod: '每年', annualRate: 3.8, startDate: ymd(2018, 8, 11), maturityDate: ymd(2028, 8, 10), expectedReturn: 25400, currentValue: 19800, note: '' }];
  const vehicles = [{ id: VEH1, name: 'Model Y', brand: 'Tesla', ownerName: '我', powerType: '電車', purchaseDate: ymd(2024, 6, 15), soldDate: null, purchasePrice: 1890000, currentValue: 1450000, fixedExpenses: [{ id: id(), category: '車貸', amount: 21000, period: '月' }, { id: id(), category: '稅費', amount: 11920, period: '年' }], variableExpenses: [], photoRecords: [], note: '' }];
  const realEstates = [{ id: id(), name: '竹北自住宅', city: '新竹縣', address: '', purchaseDate: ymd(2021, 9, 1), soldDate: null, purchasePrice: 15800000, currentValue: 18500000, monthlyRental: 0, mortgageItems: [{ id: id(), title: '玉山房貸', amount: 32000, totalPeriods: 360, startDate: ymd(2021, 10, 1) }], paidItems: [], variableExpenses: [], note: '', buildingType: '大樓', hasElevator: true, elevatorMaintenances: [], pingCount: 42.5 }];

  // ---- 履歷示範 ----
  const profile = { chineseName: '林承翰', englishName: 'Hank Lin', company: '晶宏科技', jobTitle: '副理', spouse: '陳怡君' };
  const ms = (title, cat, y, mo, da, extra) => Object.assign({ id: id(), title, date: ymd(y, mo, da), category: cat, note: '' }, extra || {});
  milestones.push(
    ms('入職 晶宏科技 廠務工程師', '職涯', 2015, 8, 3, { careerSubCategory: '入職', companyName: '晶宏科技', department: '廠務部', jobTitle: '工程師', jobGrade: 'E3', salary: 52000, mood: '第一份正職，緊張但興奮。', note: '負責 CDA 與冰水系統巡檢。' }),
    ms('調薪', '職涯', 2017, 1, 1, { careerSubCategory: '調薪', companyName: '晶宏科技', jobTitle: '工程師', jobGrade: 'E3', salaryBefore: 52000, salaryAfter: 58000 }),
    ms('升職 資深工程師', '職涯', 2018, 7, 1, { careerSubCategory: '升職', companyName: '晶宏科技', department: '廠務部', jobTitle: '資深工程師', jobGrade: 'E5', salaryBefore: 58000, salaryAfter: 71000, mood: '帶第一個新人。' }),
    ms('轉調 設備課', '職涯', 2020, 4, 1, { careerSubCategory: '轉職', companyName: '晶宏科技', department: '設備課', jobTitle: '資深工程師', jobGrade: 'E5', salary: 76000 }),
    ms('升職 課長（管理職）', '職涯', 2022, 7, 1, { careerSubCategory: '升職', companyName: '晶宏科技', department: '設備課', jobTitle: '課長', jobGrade: 'M1', salaryBefore: 76000, salaryAfter: 92000, isManagerial: true, managedUnit: '設備課', futurePlan: '兩年內把 PM 制度數位化。' }),
    ms('升職 副理', '職涯', 2025, 1, 1, { careerSubCategory: '升職', companyName: '晶宏科技', department: '廠務部', jobTitle: '副理', jobGrade: 'M2', salaryBefore: 92000, salaryAfter: 112000, isManagerial: true, managedUnit: '廠務部', mood: '管理範圍擴大到實驗室。' }),
    ms('國立交通大學 機械工程學系', '學歷', 2011, 9, 1, { note: '學士' }),
    ms('清華大學 工業工程碩士在職專班', '學歷', 2021, 9, 1, { note: '在職進修' }),
    ms('結婚', '結婚', 2019, 11, 9, { note: '與陳怡君結婚。' }),
    ms('長子出生', '家庭', 2021, 5, 18, {}),
    ms('購入竹北自住宅', '房地產', 2021, 9, 1, { note: '42.5 坪，大樓。' }),
    ms('公司年度創新提案首獎', '其他', 2023, 12, 20, { note: '冰水主機節能提案，年省電費約 180 萬。' }),
    ms('日本北海道家庭旅行', '旅行', 2024, 2, 10, {}),
    ms('領養柴犬「麻糬」', '寵物', 2023, 6, 5, {}),
    ms('完成人生第一次半馬', '健康', 2025, 3, 16, { note: '2 小時 08 分。' }),
  );
  window.LIFEGOOD_DEMO = { subs, depts, orgPeople, grades, equipment, milestones, cards, personalEvents, expenses, incomes, currencyRates, insurances, stocks, vehicles, realEstates, profile };
})();
