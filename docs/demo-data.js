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
    { id: id(), title: '氣體化學執行秘書', date: ymd(2025, 1, 1), category: '職涯', note: '', careerSubCategory: 'sideRole', sideRoleName: '氣體化學執行秘書',
      sideRoleMembers: [{ id: M1, name: '林雅婷', dutyInRole: '分析', contact: '', linkedPersonId: E.id, note: '' }, { id: M2, name: '陳志豪', dutyInRole: '鋼瓶', contact: '', linkedPersonId: C.id, note: '' }],
      sideRoleTasks: [{ id: id(), content: '季度氣體用量統計', dueDate: d(-5), isCompleted: true, completedAt: d(-6), note: '', assigneeIds: [M1], categories: ['統計'] }, { id: id(), content: '鋼瓶供應商評鑑', dueDate: d(12), isCompleted: false, completedAt: null, note: '', assigneeIds: [M2], categories: [] }, { id: id(), content: '安全教育訓練教材', dueDate: d(-1), isCompleted: true, completedAt: d(-2), note: '', assigneeIds: [M1, M2], categories: [] }] },
  ];

  const cards = [
    { id: id(), name: '吳美玲', company: '本公司', linkedOrgPersonId: P_QA1 },
    { id: id(), name: '大同氣體 陳經理', company: '大同氣體' },
  ];

  window.LIFEGOOD_DEMO = { subs, depts, orgPeople, grades, equipment, milestones, cards };
})();
