/* 美好人生・部屬看板（桌面唯讀版）
 *
 * 資料來源：CloudKit JS 直讀 iCloud 私有資料庫 LifeGoodZone 裡的 KVBlob 記錄
 *（每份資料一筆固定名稱的記錄，payload 為 App 用 JSONEncoder 寫出的 JSON 檔）。
 * 評分規則（潛力／主動性／逾期定案制／兼任待辦／被標註）完整移植自 App 的
 * TalentMatrixView.swift 與 SubordinateDetailView.swift，權重使用 App 出廠預設值
 *（App 進階設定裡的自訂權重存在手機 UserDefaults、不同步到 iCloud，網頁讀不到）。
 */
'use strict';

// ---------------------------------------------------------------------------
// 常數
// ---------------------------------------------------------------------------
/** 網頁版自己的版本（與 App 版本無關；改網頁不再動 App 版號） */
const WEB_VERSION = '1.5';
const CONTAINER_ID = 'iCloud.com.lifegood.app';
const ZONE_NAME = 'LifeGoodZone';
const TOKEN_KEY = 'lifegood_ck_token';
const REF_EPOCH = 978307200; // Swift Date 的參考時間（2001-01-01）與 Unix 的差
const KV_KEYS = {
  subs: 'life_subordinates',
  depts: 'life_departments',
  orgPeople: 'life_org_people',
  grades: 'life_grade_titles',
  equipment: 'life_equipment_pool',
  milestones: 'life_milestones',
  cards: 'life_business_cards',
  personalEvents: 'life_personal_events',
  profile: 'life_profile',
  familyMembers: 'life_family',
  relationships: 'life_relationships',
  pets: 'life_pets',
  familyTasks: 'life_family_tasks',
  ballots: 'life_performance_ballots',
  // 理財（ExpenseStore／FinanceStore，同樣是 JSON blob）
  expenses: 'lifegood_expenses',
  incomes: 'lifegood_incomes',
  currencyRates: 'lifegood_currency_rates',
  insurances: 'lifegood_insurances',
  stocks: 'lifegood_stocks',
  vehicles: 'lifegood_vehicles',
  realEstates: 'lifegood_realestates',
};
// JSONEncoder 預設把 Date 編成「距 2001-01-01 的秒數」；這些欄位名一律還原成 Date
const DATE_KEYS = new Set([
  'date', 'dueDate', 'completedAt', 'endDate', 'joinDate', 'birthday', 'scheduledDate',
  'movedTo', 'createdAt', 'dateAdded', 'leftDate', 'sideRoleEndDate', 'updatedAt', 'recurrenceEndDate',
  'marriageDate', 'divorceDate', 'anniversary', 'submittedAt',
  'purchaseDate', 'soldDate', 'startDate', 'maturityDate', 'expiryDate', 'bldgCompletionDate',
]);

// App 出廠權重（TalentMatrixView.ScoreWeights）
const W = {
  potBase: 80, potPro: 2, potCon: 2, potAch: 3, potImp: 1, potFault: 3,
  potMissMinor: 1, potMissNormal: 2, potMissSevere: 4,
  actBase: 60, actTask: 3, actItem: 1, actMeetingOwner: 1, actReport: 3, actMention: 2, actSideRole: 3,
  actLeavePer8h: 2, actOverdue: 0,
};
const LEAVE_EXEMPT = new Set(['喪假', '公假', '病假']);
const REC_COLOR = { '優點': 'green', '缺點': 'red', '成就': 'orange', '改善': 'blue', '缺失': 'pink', 'Miss Operation': 'purple', '請假': 'teal' };

// ---------------------------------------------------------------------------
// 狀態
// ---------------------------------------------------------------------------
const Store = {
  subs: [], depts: [], orgPeople: [], grades: [], equipment: [], milestones: [], cards: [], personalEvents: [],
  expenses: [], incomes: [], currencyRates: [], insurances: [], stocks: [], vehicles: [], realEstates: [],
  profile: {}, familyMembers: [], relationships: [], pets: [], familyTasks: [], ballots: [],
  source: '', loadedAt: null, ctx: null,
};
let ckContainer = null;
let charts = [];

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------
const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const pad2 = (n) => String(n).padStart(2, '0');
const WD = ['日', '一', '二', '三', '四', '五', '六'];
function fmtDate(d) { if (!(d instanceof Date) || isNaN(d)) return '—'; return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} (${WD[d.getDay()]})`; }
function fmtTime(d) { return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`; }
function fmtDateTime(d) { if (!(d instanceof Date) || isNaN(d)) return '—'; return `${fmtDate(d)} ${fmtTime(d)}`; }
function fmtDue(d) { if (!(d instanceof Date)) return '—'; return (d.getHours() === 0 && d.getMinutes() === 0) ? fmtDate(d) : fmtDateTime(d); }
function startOfDay(d) { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
function daysBetween(a, b) { return Math.round((startOfDay(b) - startOfDay(a)) / 86400000); }
function scoreClass(n) { return n >= 90 ? 's90' : n >= 80 ? 's80' : n >= 70 ? 's70' : 's0'; }
function scoreHTML(n) { return `<span class="score ${scoreClass(n)}">${n}</span>`; }
function initial(name) { return (name || '？').trim().slice(0, 1); }
function zodiac(d) {
  const m = d.getMonth() + 1, day = d.getDate();
  const t = [[1, 19, '摩羯座'], [2, 18, '水瓶座'], [3, 20, '雙魚座'], [4, 19, '牡羊座'], [5, 20, '金牛座'], [6, 21, '雙子座'],
    [7, 22, '巨蟹座'], [8, 22, '獅子座'], [9, 22, '處女座'], [10, 23, '天秤座'], [11, 22, '天蠍座'], [12, 21, '射手座']];
  for (const [mm, dd, name] of t) { if (m === mm) return day <= dd ? name : (t[mm % 12][2]); }
  return '摩羯座';
}
function toast(msg) { const t = $('#toast'); t.textContent = msg; t.hidden = false; clearTimeout(toast._t); toast._t = setTimeout(() => { t.hidden = true; }, 2600); }
function setStatus(msg, kind) { const s = $('#gate-status'); if (!msg) { s.hidden = true; return; } s.hidden = false; s.textContent = msg; s.className = 'status' + (kind ? ' ' + kind : ''); }

/** 遞迴把已知日期欄位的數字還原成 Date */
function reviveDates(node) {
  if (Array.isArray(node)) { node.forEach(reviveDates); return node; }
  if (node && typeof node === 'object') {
    for (const k of Object.keys(node)) {
      const v = node[k];
      if (DATE_KEYS.has(k) && typeof v === 'number') node[k] = new Date((v + REF_EPOCH) * 1000);
      else if (v && typeof v === 'object') reviveDates(v);
    }
  }
  return node;
}

// ---------------------------------------------------------------------------
// CloudKit
// ---------------------------------------------------------------------------
function waitForCloudKit() {
  return new Promise((resolve, reject) => {
    const t0 = Date.now();
    (function poll() {
      if (window.CloudKit) return resolve(window.CloudKit);
      if (window.__ckFailed) return reject(new Error('CloudKit JS 載入失敗（cdn.apple-cloudkit.com 無法連線）'));
      if (Date.now() - t0 > 15000) return reject(new Error('CloudKit JS 載入逾時'));
      setTimeout(poll, 100);
    })();
  });
}

async function configureCloudKit(token) {
  const CloudKit = await waitForCloudKit();
  if (!ckContainer) {
    CloudKit.configure({
      containers: [{
        containerIdentifier: CONTAINER_ID,
        apiTokenAuth: {
          apiToken: token,
          persist: true,
          signInButton: { id: 'apple-sign-in-button', theme: 'black' },
          signOutButton: { id: 'apple-sign-out-button', theme: 'black' },
        },
        environment: 'production',
      }],
    });
    ckContainer = CloudKit.getDefaultContainer();
  }
  return ckContainer;
}

/** 抓一筆 KVBlob，回傳解析後的 JSON（找不到回傳 null） */
async function fetchKV(db, key) {
  const name = `kv_${key}`;
  let resp;
  try {
    resp = await db.fetchRecords([name], { zoneID: { zoneName: ZONE_NAME } });
  } catch (e) {
    const code = e && (e.ckErrorCode || e.serverErrorCode);
    if (code === 'NOT_FOUND' || code === 'ZONE_NOT_FOUND') return null;
    throw new Error(`讀取 ${name} 失敗：${e.reason || e.message || code || JSON.stringify(e)}`);
  }
  if (resp.hasErrors) {
    const err = resp.errors[0] || {};
    const code = err.ckErrorCode || err.serverErrorCode;
    if (code === 'NOT_FOUND' || code === 'ZONE_NOT_FOUND') return null;
    throw new Error(`讀取 ${name} 失敗：${err.reason || code}`);
  }
  const rec = resp.records && resp.records[0];
  const asset = rec && rec.fields && rec.fields.payload && rec.fields.payload.value;
  if (!asset || !asset.downloadURL) return null;
  const r = await fetch(asset.downloadURL);
  if (!r.ok) throw new Error(`下載 ${name} 內容失敗（HTTP ${r.status}）`);
  const text = await r.text();
  return text.trim() ? JSON.parse(text) : null;
}

async function loadFromCloud() {
  const db = ckContainer.privateCloudDatabase;
  const out = {};
  const entries = Object.entries(KV_KEYS);
  const results = await Promise.all(entries.map(([k, key]) => fetchKV(db, key)));
  entries.forEach(([k], i) => { out[k] = results[i] || []; });
  if (!out.subs.length && !out.depts.length && !out.orgPeople.length) {
    throw new Error('iCloud 裡沒有找到部屬／部門資料。請確認是用「擁有資料的那個 Apple ID」登入，且 App 已完成一次 iCloud 同步。');
  }
  return applyData(out, 'iCloud');
}

/** 套用資料；回傳內容是否與上一次不同（自動更新時沒變就不重畫，免得打斷正在看的畫面） */
function applyData(raw, source) {
  const fingerprint = fingerprintOf(raw);
  const changed = fingerprint !== Store.fingerprint;
  Store.fingerprint = fingerprint;
  for (const k of Object.keys(KV_KEYS)) {
    const v = raw[k];
    // life_profile 是單一物件，其餘都是陣列
    Store[k] = k === 'profile'
      ? reviveDates(v && typeof v === 'object' && !Array.isArray(v) ? v : {})
      : reviveDates(Array.isArray(v) ? v : []);
  }
  Store.source = source;
  Store.loadedAt = new Date();
  Store.ctx = buildScoreContext();
  updateSourceLabel();
  return changed;
}
function fingerprintOf(raw) {
  // 簡單 32-bit 雜湊：資料量不大（幾百 KB），逐字掃一次可接受
  const str = JSON.stringify(raw);
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
  return `${str.length}:${h >>> 0}`;
}
function updateSourceLabel() {
  const el = $('#data-source'); if (!el || !Store.loadedAt) return;
  let text = `${Store.source}・${fmtTime(Store.loadedAt)} 讀取`;
  if (AutoRefresh.nextAt) text += `・${fmtTime(AutoRefresh.nextAt)} 自動更新`;
  el.textContent = text;
}

// 自動更新：登入 iCloud 後每 10 分鐘背景抓一次；分頁在背景時暫停，回到前景若已過期立刻補抓
const AutoRefresh = {
  intervalMs: (() => { try { const m = Number(localStorage.getItem('lifegood_refresh_min')); return m >= 1 ? m * 60000 : 10 * 60000; } catch (e) { return 10 * 60000; } })(),
  timer: null, nextAt: null, busy: false,
  start() {
    this.stop();
    this.schedule();
    document.addEventListener('visibilitychange', this.onVisibility);
  },
  stop() { if (this.timer) clearTimeout(this.timer); this.timer = null; this.nextAt = null; document.removeEventListener('visibilitychange', this.onVisibility); updateSourceLabel(); },
  schedule(ms = this.intervalMs) {
    if (this.timer) clearTimeout(this.timer);
    this.nextAt = new Date(Date.now() + ms);
    this.timer = setTimeout(() => this.tick(), ms);
    updateSourceLabel();
  },
  async tick() {
    if (document.hidden) { this.timer = null; this.nextAt = null; updateSourceLabel(); return; } // 背景分頁：等回前景再抓
    await this.refresh(true);
    this.schedule();
  },
  onVisibility: () => {
    if (document.hidden || Store.source !== 'iCloud') return;
    const stale = !Store.loadedAt || Date.now() - Store.loadedAt.getTime() >= AutoRefresh.intervalMs;
    if (stale || !AutoRefresh.timer) { AutoRefresh.refresh(true).then(() => AutoRefresh.schedule()); }
  },
  /** silent=true：背景更新，只在資料有變時重畫並輕提示 */
  async refresh(silent) {
    if (this.busy || !ckContainer || Store.source !== 'iCloud') return false;
    this.busy = true;
    try {
      const changed = await loadFromCloud();
      if (changed) { route(); toast(silent ? '資料已自動更新' : '已更新'); }
      else if (!silent) toast('資料沒有變動');
      return changed;
    } catch (e) {
      if (!silent) toast('讀取失敗：' + (e.message || e));
      updateSourceLabel();
      return false;
    } finally { this.busy = false; }
  },
};

// ---------------------------------------------------------------------------
// 評分（移植自 App）
// ---------------------------------------------------------------------------
function potentialScore(s) {
  let score = W.potBase;
  for (const r of s.records || []) {
    switch (r.type) {
      case '優點': score += W.potPro; break;
      case '缺點': score -= W.potCon; break;
      case '成就': score += W.potAch; break;
      case '改善': score += W.potImp; break;
      case '缺失': score -= W.potFault; break;
      case 'Miss Operation':
        score -= r.severity === '輕微' ? W.potMissMinor : r.severity === '嚴重' ? W.potMissSevere : W.potMissNormal; break;
      default: break;
    }
  }
  return Math.max(0, Math.round(score));
}

/** 逾期定案制：逾期未完成 ＋ 逾期才完成（completedAt > dueDate）都算 */
function overdueOpenCount(s) {
  const now = new Date();
  let n = 0;
  for (const t of s.tasks || []) {
    if (t.sideRoleLink || !t.dueDate) continue;
    if (t.isCompleted) { if (t.completedAt && t.completedAt > t.dueDate) n++; }
    else if (t.dueDate < now) n++;
  }
  for (const r of s.weeklyReports || []) {
    if (r.isCompleted) { if (r.completedAt && r.completedAt > r.date) n++; }
    else if (r.date < now) n++;
  }
  return n;
}

function leaveHoursOf(s) {
  return (s.records || []).filter((r) => r.type === '請假' && !LEAVE_EXEMPT.has(r.leaveType || ''))
    .reduce((a, r) => a + (typeof r.leaveHours === 'number' ? r.leaveHours : 8), 0);
}

function proactivityBreakdown(s, ctx) {
  const mentioned = (ctx.mentions[s.id] || 0);
  const sideDone = (ctx.sideRoles[s.id] || { done: 0 }).done;
  const items = [['基礎分', W.actBase]];
  const doneTasks = (s.tasks || []).filter((t) => t.isCompleted && !t.sideRoleLink);
  const defaultTasks = doneTasks.filter((t) => t.customScore == null).length;
  const customTasks = doneTasks.filter((t) => t.customScore != null).map((t) => t.customScore);
  const completedItems = ctx.itemCredits[s.id] || 0;
  const completedReports = (s.weeklyReports || []).filter((r) => r.isCompleted).length;
  const leaveHours = leaveHoursOf(s);
  const owned = (s.meetings || []).length;
  if (owned > 0) items.push([`會議掛名 ×${owned}`, owned * W.actMeetingOwner]);
  if (defaultTasks > 0) items.push([`完成任務 ×${defaultTasks}`, defaultTasks * W.actTask]);
  if (customTasks.length) items.push([`完成任務（自訂分）×${customTasks.length}`, customTasks.reduce((a, b) => a + b, 0)]);
  if (completedItems > 0) items.push([`完成議程項目（指派給我）×${completedItems}`, completedItems * W.actItem]);
  if (completedReports > 0) items.push([`完成報告 ×${completedReports}`, completedReports * W.actReport]);
  if (mentioned > 0) items.push([`被標註 ×${mentioned}`, mentioned * W.actMention]);
  if (sideDone > 0) items.push([`完成兼任待辦 ×${sideDone}`, sideDone * W.actSideRole]);
  if (leaveHours > 0) {
    const h = Number.isInteger(leaveHours) ? String(leaveHours) : leaveHours.toFixed(1);
    items.push([`請假 ${h} 小時`, -Math.round(leaveHours / 8 * W.actLeavePer8h)]);
  }
  const overdue = overdueOpenCount(s);
  if (W.actOverdue > 0 && overdue > 0) items.push([`逾期（含補完成）×${overdue}`, -overdue * W.actOverdue]);
  return items;
}

function proactivityScore(s, ctx) {
  // 與 App 相同：分項用 Double 累加後四捨五入、下限 0（請假扣分不先取整）
  const mentioned = (ctx.mentions[s.id] || 0);
  const sideDone = (ctx.sideRoles[s.id] || { done: 0 }).done;
  const taskPoints = (s.tasks || []).filter((t) => t.isCompleted && !t.sideRoleLink)
    .reduce((a, t) => a + (t.customScore ?? W.actTask), 0);
  const completedItems = ctx.itemCredits[s.id] || 0;
  const completedReports = (s.weeklyReports || []).filter((r) => r.isCompleted).length;
  let score = W.actBase + taskPoints + (s.meetings || []).length * W.actMeetingOwner + completedItems * W.actItem + completedReports * W.actReport
    + mentioned * W.actMention + sideDone * W.actSideRole;
  score -= leaveHoursOf(s) / 8 * W.actLeavePer8h;
  score -= overdueOpenCount(s) * W.actOverdue;
  return Math.max(0, Math.round(score));
}

function potentialBreakdown(s) {
  const items = [['基礎分', W.potBase]];
  const c = {};
  for (const r of s.records || []) {
    if (r.type === 'Miss Operation') { const k = 'miss_' + (r.severity || '一般'); c[k] = (c[k] || 0) + 1; }
    else c[r.type] = (c[r.type] || 0) + 1;
  }
  if (c['成就']) items.push([`成就 ×${c['成就']}`, c['成就'] * W.potAch]);
  if (c['優點']) items.push([`優點 ×${c['優點']}`, c['優點'] * W.potPro]);
  if (c['改善']) items.push([`進步 ×${c['改善']}`, c['改善'] * W.potImp]);
  if (c['缺點']) items.push([`缺點 ×${c['缺點']}`, -c['缺點'] * W.potCon]);
  if (c['缺失']) items.push([`缺失 ×${c['缺失']}`, -c['缺失'] * W.potFault]);
  if (c['miss_輕微']) items.push([`疏失·輕微 ×${c['miss_輕微']}`, -c['miss_輕微'] * W.potMissMinor]);
  if (c['miss_一般']) items.push([`疏失·一般 ×${c['miss_一般']}`, -c['miss_一般'] * W.potMissNormal]);
  if (c['miss_嚴重']) items.push([`疏失·嚴重 ×${c['miss_嚴重']}`, -c['miss_嚴重'] * W.potMissSevere]);
  return items;
}

function overallScore(s, ctx) { return Math.round((potentialScore(s) + proactivityScore(s, ctx)) / 2); }

function allItems(m) { return (m.items || []).concat((m.occurrences || []).flatMap((o) => o.items || [])); }

/** 被 @ 標註計數（同一項目同一人只計一次）；人員清單 = 部屬 ＋ 非部屬本人的名片 */
function mentionPeople() {
  const subIds = new Set(Store.subs.map((s) => s.id));
  const ownedCards = new Set(Store.orgPeople.filter((p) => p.linkedSubordinateId && subIds.has(p.linkedSubordinateId) && p.linkedBusinessCardId).map((p) => p.linkedBusinessCardId));
  const out = [];
  for (const s of Store.subs) if ((s.name || '').trim()) out.push({ id: s.id, name: s.name });
  for (const c of Store.cards) if ((c.name || '').trim() && !ownedCards.has(c.id)) out.push({ id: c.id, name: c.name });
  return out.sort((a, b) => b.name.length - a.name.length);
}
function mentionedIDs(raw, sorted) {
  const ids = new Set();
  let s = String(raw || '');
  let at;
  while ((at = s.indexOf('@')) >= 0) {
    const after = s.slice(at + 1);
    const p = sorted.find((x) => after.startsWith(x.name));
    if (p) { ids.add(p.id); s = after.slice(p.name.length); } else s = after;
  }
  return ids;
}
function mentionedCounts() {
  const sorted = mentionPeople();
  const counts = {};
  const bump = (ids) => { for (const id of ids) counts[id] = (counts[id] || 0) + 1; };
  for (const s of Store.subs) {
    for (const t of s.tasks || []) bump(new Set([...mentionedIDs(t.content, sorted), ...mentionedIDs(t.note, sorted)]));
    for (const m of s.meetings || []) {
      const ids = mentionedIDs(m.note, sorted);
      for (const it of allItems(m)) { for (const id of mentionedIDs(it.content, sorted)) ids.add(id); for (const id of mentionedIDs(it.note, sorted)) ids.add(id); }
      bump(ids);
    }
    for (const r of s.weeklyReports || []) bump(mentionedIDs(r.note, sorted));
  }
  return counts;
}
function sideRoleTaskCounts() {
  const out = {};
  for (const role of Store.milestones) {
    if (role.careerSubCategory !== 'sideRole') continue;
    const linkOf = {};
    for (const m of role.sideRoleMembers || []) if (m.linkedPersonId) linkOf[m.id] = m.linkedPersonId;
    if (!Object.keys(linkOf).length) continue;
    for (const t of role.sideRoleTasks || []) {
      for (const mid of t.assigneeIds || []) {
        const pid = linkOf[mid]; if (!pid) continue;
        const cur = out[pid] || { done: 0, total: 0 };
        cur.total++; if (t.isCompleted) cur.done++;
        out[pid] = cur;
      }
    }
  }
  return out;
}
/** 議程項目完成分歸屬：有指派部屬 → 每位各計一次；沒指派或都不是部屬 → 會議掛名負責人 */
function meetingItemCredits() {
  const subIds = new Set(Store.subs.map((s) => s.id));
  const viaOrg = {}, viaCard = {};
  for (const p of Store.orgPeople) {
    if (!p.linkedSubordinateId || !subIds.has(p.linkedSubordinateId)) continue;
    viaOrg[p.id] = p.linkedSubordinateId;
    if (p.linkedBusinessCardId) viaCard[p.linkedBusinessCardId] = p.linkedSubordinateId;
  }
  const resolve = (pid) => (subIds.has(pid) ? pid : (viaOrg[pid] || viaCard[pid] || null));
  const out = {};
  for (const s of Store.subs) for (const m of s.meetings || []) for (const it of allItems(m)) {
    if (!it.isCompleted || it.sideRoleLink) continue;
    const owners = new Set((it.assigneeIds || []).map(resolve).filter(Boolean));
    if (!owners.size) out[s.id] = (out[s.id] || 0) + 1;
    else for (const id of owners) out[id] = (out[id] || 0) + 1;
  }
  return out;
}
function buildScoreContext() { return { mentions: mentionedCounts(), sideRoles: sideRoleTaskCounts(), itemCredits: meetingItemCredits() }; }

// ---------------------------------------------------------------------------
// 會議場次展開（規則是真相，展開結果是畫面）
// ---------------------------------------------------------------------------
function expandOccurrences(m, from, horizon) {
  const out = [];
  const overrides = new Map((m.occurrences || []).map((o) => [+o.scheduledDate, o]));
  const push = (scheduled, o) => {
    const date = o && o.movedTo ? o.movedTo : scheduled;
    out.push({ scheduledDate: scheduled, date, isCancelled: !!(o && o.isCancelled), isMoved: !!(o && o.movedTo), items: (o && o.items) || [], isAdHoc: !!(o && o.isAdHoc) });
  };
  if (!m.rule) {
    push(m.date, overrides.get(+m.date));
  } else {
    const r = m.rule;
    const end = r.endDate ? new Date(Math.min(+r.endDate, +horizon)) : horizon;
    const base = new Date(m.date);
    const wdays = (r.weekdays && r.weekdays.length) ? r.weekdays : [base.getDay() + 1];
    let cur = new Date(base);
    let guard = 0;
    if (r.frequency === '每週' || r.frequency === '隔週') {
      // 從起始週的週日開始逐週掃，挑選指定的星期幾（1=週日…7=週六）
      const step = r.frequency === '隔週' ? 14 : 7;
      const weekStart = new Date(base); weekStart.setDate(base.getDate() - base.getDay());
      for (let w = new Date(weekStart); w <= end && guard < 400; w.setDate(w.getDate() + step), guard++) {
        for (const wd of [...wdays].sort()) {
          const d = new Date(w); d.setDate(w.getDate() + (wd - 1)); d.setHours(base.getHours(), base.getMinutes(), 0, 0);
          if (d < base || d > end) continue;
          push(d, overrides.get(+d));
        }
      }
    } else {
      while (cur <= end && guard < 400) {
        push(new Date(cur), overrides.get(+cur));
        if (r.frequency === '每日') cur.setDate(cur.getDate() + 1);
        else cur.setMonth(cur.getMonth() + 1);
        guard++;
      }
    }
  }
  // 臨時加開場次
  for (const o of m.occurrences || []) if (o.isAdHoc && !out.some((x) => +x.scheduledDate === +o.scheduledDate)) push(o.scheduledDate, o);
  return out.filter((o) => o.date >= from || o.items.length).sort((a, b) => a.date - b.date);
}
function nextOccurrence(m) {
  const now = new Date();
  const horizon = new Date(now); horizon.setMonth(horizon.getMonth() + 3);
  const list = expandOccurrences(m, startOfDay(now), horizon).filter((o) => !o.isCancelled && o.date >= startOfDay(now));
  return list[0] || null;
}
function ruleSummary(r) {
  if (!r) return '單次';
  let s = r.frequency;
  if ((r.frequency === '每週' || r.frequency === '隔週') && r.weekdays && r.weekdays.length) {
    s += `（${[...r.weekdays].sort().map((d) => '週' + WD[d - 1]).join('、')}）`;
  }
  if (r.endDate) s += `，至 ${fmtDate(r.endDate).split(' ')[0]}`;
  return s;
}

// ---------------------------------------------------------------------------
// 查詢輔助
// ---------------------------------------------------------------------------
const deptById = (id) => Store.depts.find((d) => d.id === id);
const gradeById = (id) => Store.grades.find((g) => g.id === id);
const subById = (id) => Store.subs.find((s) => s.id === id);
function deptNameOf(s) { const d = s.departmentId && deptById(s.departmentId); return d ? d.name : (s.department || ''); }
function gradeLabelOf(s) { const g = s.gradeTitleId && gradeById(s.gradeTitleId); return g ? `${g.grade}${g.grade && g.title ? '・' : ''}${g.title}` : ''; }
function personName(id) {
  const s = subById(id); if (s) return s.name;
  const p = Store.orgPeople.find((x) => x.id === id); if (p) return p.name;
  const c = Store.cards.find((x) => x.id === id); if (c) return c.name;
  return '';
}
function equipmentOf(subId) { return Store.equipment.filter((e) => e.ownerId === subId); }
function birthdayInfo(bday) {
  if (!(bday instanceof Date)) return null;
  const now = startOfDay(new Date());
  let next = new Date(now.getFullYear(), bday.getMonth(), bday.getDate());
  if (next < now) next = new Date(now.getFullYear() + 1, bday.getMonth(), bday.getDate());
  return { next, days: daysBetween(now, next), sign: zodiac(bday) };
}

// ---------------------------------------------------------------------------
// 路由與畫面
// ---------------------------------------------------------------------------
function destroyCharts() { charts.forEach((c) => { try { c.destroy(); } catch (e) { /* ignore */ } }); charts = []; }
function route() {
  const hash = location.hash || '#/overview';
  const parts = hash.replace(/^#\//, '').split('/');
  const page = parts[0] || 'overview';
  // 側欄高亮：分組頁面用「群組/分頁」當 key，舊有單層頁面用第一段
  const groupKey = ['expense', 'finance', 'life'].includes(page) ? `${page}/${parts[1] || 'overview'}` : null;
  const legacyKey = { sub: 'subs', siderole: 'sideroles', dept: 'org', equipment: 'org' }[page] || page;
  document.querySelectorAll('.nav a').forEach((a) => a.classList.toggle('active', a.dataset.route === (groupKey || legacyKey)));
  destroyCharts();
  const main = $('#main');
  main.scrollTop = 0; window.scrollTo(0, 0);
  const ctx = Store.ctx;
  switch (page) {
    case 'subs': renderSubs(main, ctx); break;
    case 'sub': renderSubDetail(main, ctx, decodeURIComponent(parts[1] || ''), parts[2] || 'tasks'); break;
    case 'matrix': renderMatrix(main, ctx); break;
    case 'stats': renderStats(main, ctx, parts[1] || 'all'); break;
    case 'org': renderOrg(main); break;
    case 'dept': renderDept(main, ctx, decodeURIComponent(parts[1] || '')); break;
    case 'equipment': renderEquipment(main, ctx, decodeURIComponent(parts[1] || '')); break;
    case 'sideroles': renderSideRoles(main); break;
    case 'calendar': renderCalendar(main, parts[1] || ''); break;
    case 'expense': renderExpense(main, parts[1] || 'overview', parts[2] || ''); break;
    case 'finance': {
      const t = parts[1] || 'overview';
      // 舊網址相容：#/finance/accounts→財富卡片、stocks→股票、assets→總覽
      if (t === 'accounts') { location.hash = '#/life/wealth'; return; }
      if (t === 'stocks') { location.hash = '#/finance/stock'; return; }
      renderFinanceHome(main, t === 'assets' ? 'overview' : t, parts[2] ? decodeURIComponent(parts[2]) : '');
      break;
    }
    case 'life': {
      const t = parts[1] || '';
      if (t === 'wealth') renderWealth(main);
      else if (t === 'resume') renderResume(main, parts[2] || 'all');
      else if (t === 'family') renderFamily(main, parts[2] || 'members');
      else if (t === 'overview') renderLifeOverview(main, ctx);
      else renderOverview(main, ctx);
      break;
    }
    case 'grades': renderGrades(main); break;
    case 'perf': renderPerf(main, parts[1] || ''); break;
    case 'tax': renderTax(main, parts[1] || ''); break;
    case 'settings': renderSettings(main); break;
    case 'cards': renderCards(main, parts[1] ? decodeURIComponent(parts[1]) : ''); break;
    case 'siderole': renderSideRole(main, decodeURIComponent(parts[1] || ''), parts[2] || 'tasks'); break;
    default: renderOverview(main, ctx);
  }
}

function pageHead(title, sub, extra = '') {
  return `<div class="page-head"><div><h2>${esc(title)}</h2>${sub ? `<div class="sub">${sub}</div>` : ''}</div><div class="spacer"></div>${extra}</div>`;
}

// ---- 部屬總覽 -------------------------------------------------------------
function renderOverview(main, ctx) {
  const subs = Store.subs;
  const now = new Date();
  const openTasks = [], overdueTasks = [], openReports = [];
  for (const s of subs) {
    for (const t of s.tasks || []) {
      if (t.isCompleted) continue;
      openTasks.push({ s, t });
      if (t.dueDate && t.dueDate < now) overdueTasks.push({ s, t, days: daysBetween(t.dueDate, now) });
    }
    for (const r of s.weeklyReports || []) if (!r.isCompleted) openReports.push({ s, r });
  }
  overdueTasks.sort((a, b) => b.days - a.days);
  openReports.sort((a, b) => a.r.date - b.r.date);
  const totalOverdue = subs.reduce((a, s) => a + overdueOpenCount(s), 0);

  // 本週會議（今天起 7 天）
  const weekEnd = new Date(startOfDay(now)); weekEnd.setDate(weekEnd.getDate() + 7);
  const meetings = [];
  for (const s of subs) for (const m of s.meetings || []) {
    for (const o of expandOccurrences(m, startOfDay(now), weekEnd)) if (!o.isCancelled && o.date >= startOfDay(now) && o.date < weekEnd) meetings.push({ s, m, o });
  }
  meetings.sort((a, b) => a.o.date - b.o.date);

  // 生日
  const bdays = subs.map((s) => ({ s, b: birthdayInfo(s.birthday) })).filter((x) => x.b && x.b.days <= 30).sort((a, b) => a.b.days - b.b.days);
  const ranking = subs.map((s) => ({ s, total: overallScore(s, ctx), pot: potentialScore(s), act: proactivityScore(s, ctx) })).sort((a, b) => b.total - a.total);
  const today = startOfDay(now);
  const todayTasks = openTasks.filter((x) => x.t.dueDate && daysBetween(today, x.t.dueDate) === 0);

  main.innerHTML = `
    ${pageHead('部屬總覽', `${fmtDate(now)}・共 ${subs.length} 位部屬`)}
    <div class="grid cols-5">
      <div class="card kpi"><div class="label">部屬人數</div><div class="value">${subs.length}</div><div class="foot">${Store.depts.length} 個部門</div></div>
      <div class="card kpi"><div class="label">未完成任務</div><div class="value ${openTasks.length ? 'orange' : ''}">${openTasks.length}</div><div class="foot">今日到期 ${todayTasks.length}</div></div>
      <div class="card kpi"><div class="label">逾期（含補完成）</div><div class="value ${totalOverdue ? 'red' : 'green'}">${totalOverdue}</div><div class="foot">目前逾期未完成 ${overdueTasks.length}</div></div>
      <div class="card kpi"><div class="label">未完成報告</div><div class="value ${openReports.length ? 'orange' : ''}">${openReports.length}</div><div class="foot">本週會議 ${meetings.length} 場</div></div>
      <div class="card kpi"><div class="label">30 天內生日</div><div class="value ${bdays.some((x) => x.b.days <= 1) ? 'pink' : ''}">${bdays.length}</div><div class="foot">${bdays[0] ? `最近：${esc(bdays[0].s.name)}（${bdays[0].b.days === 0 ? '今天' : bdays[0].b.days + ' 天後'}）` : '無'}</div></div>
    </div>

    <div class="grid cols-2 mt">
      <div class="card">
        <h3>🚨 逾期未完成任務 <span class="count">${overdueTasks.length}</span></h3>
        <div class="list">${overdueTasks.slice(0, 12).map(({ s, t, days }) => `
          <a class="item clickable" href="#/sub/${s.id}/tasks">
            <div class="avatar sm">${esc(initial(s.name))}</div>
            <div class="main-text"><div class="title ${t.isDereliction ? 'derel' : ''}">${esc(t.topic || '未命名任務')}</div><div class="meta">${esc(s.name)}・截止 ${fmtDue(t.dueDate)}</div></div>
            <span class="chip red">逾期 ${days} 天</span>
          </a>`).join('') || '<div class="empty">沒有逾期任務 🎉</div>'}</div>
      </div>
      <div class="card">
        <h3>🏆 綜合分數排行 <span class="count">${ranking.length}</span></h3>
        <div class="list">${ranking.slice(0, 8).map(({ s, total, pot, act }, i) => `
          <a class="item clickable" href="#/sub/${s.id}">
            <div class="avatar sm">${i + 1}</div>
            <div class="main-text"><div class="title">${esc(s.name)}</div><div class="meta">${esc(s.jobTitle || '')}${deptNameOf(s) ? '・' + esc(deptNameOf(s)) : ''}・潛力 ${pot}・主動性 ${act}</div></div>
            ${scoreHTML(total)}
          </a>`).join('') || '<div class="empty">尚無部屬</div>'}</div>
      </div>
    </div>

    <div class="grid cols-3 mt">
      <div class="card">
        <h3>📅 本週會議 <span class="count">${meetings.length}</span></h3>
        <div class="list">${meetings.slice(0, 12).map(({ s, m, o }) => `
          <a class="item clickable" href="#/sub/${s.id}/meetings">
            <div class="main-text"><div class="title">${esc(m.topic || '未命名會議')}</div><div class="meta">${esc(s.name)}・${fmtDateTime(o.date)}${o.isMoved ? '（已改期）' : ''}${o.isAdHoc ? '（臨時）' : ''}</div></div>
            <span class="chip indigo">${o.items.length} 項</span>
          </a>`).join('') || '<div class="empty">本週沒有排定會議</div>'}</div>
      </div>
      <div class="card">
        <h3>📝 未完成報告 <span class="count">${openReports.length}</span></h3>
        <div class="list">${openReports.slice(0, 12).map(({ s, r }) => `
          <a class="item clickable" href="#/sub/${s.id}/reports">
            <div class="main-text"><div class="title">${esc(r.topic || '未命名報告')}</div><div class="meta">${esc(s.name)}・${fmtDate(r.date)}</div></div>
            ${r.reportType ? `<span class="chip blue">${esc(r.reportType)}</span>` : ''}${r.date < now ? '<span class="chip red">逾期</span>' : ''}
          </a>`).join('') || '<div class="empty">報告都交齊了</div>'}</div>
      </div>
      <div class="card">
        <h3>🎂 近期生日 <span class="count">${bdays.length}</span></h3>
        <div class="list">${bdays.map(({ s, b }) => `
          <a class="item clickable" href="#/sub/${s.id}">
            <div class="avatar sm">${esc(initial(s.name))}</div>
            <div class="main-text"><div class="title">${esc(s.name)}</div><div class="meta">${fmtDate(b.next)}・${b.sign}</div></div>
            <span class="chip ${b.days <= 1 ? 'pink' : ''}">${b.days === 0 ? '今天' : b.days === 1 ? '明天' : b.days + ' 天後'}</span>
          </a>`).join('') || '<div class="empty">30 天內沒有人生日</div>'}</div>
      </div>
    </div>`;
}

// ---- 部屬列表 -------------------------------------------------------------
const subsState = { dept: 'all', q: '', sort: 'total', dir: -1 };
function renderSubs(main, ctx) {
  const rows = Store.subs.map((s) => {
    const open = (s.tasks || []).filter((t) => !t.isCompleted).length;
    return { s, name: s.name, title: s.jobTitle || '', dept: deptNameOf(s), grade: gradeLabelOf(s), pot: potentialScore(s), act: proactivityScore(s, ctx), total: overallScore(s, ctx), open, overdue: overdueOpenCount(s), reports: (s.weeklyReports || []).filter((r) => !r.isCompleted).length, leave: leaveHoursOf(s) };
  });
  const depts = [...new Set(rows.map((r) => r.dept).filter(Boolean))].sort();
  const draw = () => {
    let list = rows.filter((r) => (subsState.dept === 'all' || r.dept === subsState.dept) && (!subsState.q || (r.name + r.title + r.dept + r.grade).toLowerCase().includes(subsState.q.toLowerCase())));
    const k = subsState.sort;
    list.sort((a, b) => (typeof a[k] === 'number' ? (a[k] - b[k]) : String(a[k]).localeCompare(String(b[k]), 'zh-Hant')) * subsState.dir);
    const th = (key, label, num) => `<th class="${num ? 'num' : ''} ${subsState.sort === key ? 'sorted' : ''}" data-sort="${key}">${label}${subsState.sort === key ? (subsState.dir > 0 ? ' ↑' : ' ↓') : ''}</th>`;
    $('#subs-table').innerHTML = `<table class="tbl"><thead><tr>${th('name', '姓名')}${th('title', '職稱')}${th('dept', '部門')}${th('grade', '職等')}${th('pot', '潛力', 1)}${th('act', '主動性', 1)}${th('total', '總分', 1)}${th('open', '未完成任務', 1)}${th('overdue', '逾期', 1)}${th('reports', '未交報告', 1)}${th('leave', '請假時數', 1)}</tr></thead><tbody>
      ${list.map((r) => `<tr class="clickable" data-id="${r.s.id}"><td><b>${esc(r.name)}</b></td><td>${esc(r.title)}</td><td>${esc(r.dept)}</td><td>${esc(r.grade)}</td><td class="num">${scoreHTML(r.pot)}</td><td class="num">${scoreHTML(r.act)}</td><td class="num">${scoreHTML(r.total)}</td><td class="num">${r.open}</td><td class="num">${r.overdue ? `<span class="chip red">${r.overdue}</span>` : '0'}</td><td class="num">${r.reports}</td><td class="num">${r.leave}</td></tr>`).join('') || '<tr><td colspan="11" class="empty">沒有符合的部屬</td></tr>'}
    </tbody></table>`;
    $('#subs-table').querySelectorAll('th').forEach((h) => h.onclick = () => { const key = h.dataset.sort; if (subsState.sort === key) subsState.dir *= -1; else { subsState.sort = key; subsState.dir = typeof rows[0]?.[key] === 'number' ? -1 : 1; } draw(); });
    $('#subs-table').querySelectorAll('tr.clickable').forEach((tr) => tr.onclick = () => { location.hash = `#/sub/${tr.dataset.id}`; });
  };
  main.innerHTML = `
    ${pageHead('部屬列表', `${Store.subs.length} 位・點任一列看明細`)}
    <div class="filters">
      <input type="search" id="subs-q" placeholder="搜尋姓名／職稱／部門" value="${esc(subsState.q)}">
      <span class="fchip ${subsState.dept === 'all' ? 'on' : ''}" data-dept="all">全部</span>
      ${depts.map((d) => `<span class="fchip ${subsState.dept === d ? 'on' : ''}" data-dept="${esc(d)}">${esc(d)}</span>`).join('')}
    </div>
    <div class="card table-wrap" id="subs-table"></div>`;
  $('#subs-q').oninput = (e) => { subsState.q = e.target.value; draw(); };
  main.querySelectorAll('.fchip').forEach((c) => c.onclick = () => { subsState.dept = c.dataset.dept; main.querySelectorAll('.fchip').forEach((x) => x.classList.toggle('on', x === c)); draw(); });
  draw();
}

// ---- 部屬明細 -------------------------------------------------------------
function breakdownHTML(items) {
  return `<div class="breakdown">${items.map(([l, p]) => `<div><span>${esc(l)}</span><span class="pts ${p > 0 ? 'pos' : p < 0 ? 'neg' : ''}">${p > 0 ? '+' : ''}${p}</span></div>`).join('')}</div>`;
}
function taskRow(t) {
  const now = new Date();
  const overdue = !t.isCompleted && t.dueDate && t.dueDate < now;
  const late = t.isCompleted && t.dueDate && t.completedAt && t.completedAt > t.dueDate;
  const score = t.isDereliction ? (t.customScore ?? -1) : (t.customScore ?? W.actTask);
  return `<div class="task-row">
    <div class="tick">${t.isCompleted ? '✅' : t.isDereliction ? '⚠️' : '⬜️'}</div>
    <div>
      <div class="t-title ${t.isCompleted ? 'done' : ''} ${t.isDereliction ? 'derel' : ''}">${esc(t.topic || '未命名任務')}</div>
      <div class="t-meta">${esc(t.content || '')}</div>
      <div class="t-meta">任務 ${fmtDateTime(t.date)}${t.dueDate ? '・截止 ' + fmtDue(t.dueDate) : ''}${t.isCompleted && t.completedAt ? '・完成 ' + fmtDateTime(t.completedAt) : ''}${t.equipmentLink ? '・來源機台 ' + esc(t.equipmentLink.equipmentName) : ''}</div>
      ${t.note ? `<div class="t-meta">備註：${esc(t.note)}</div>` : ''}
    </div>
    <div class="t-right">
      ${t.isDereliction ? '<span class="chip red">缺失</span>' : ''}
      ${overdue ? `<span class="chip red">逾期 ${daysBetween(t.dueDate, now)} 天</span>` : ''}
      ${late ? '<span class="chip orange">逾期完成</span>' : ''}
      ${t.sideRoleLink ? '<span class="chip purple">兼任</span>' : ''}
      <span class="chip ${score < 0 ? 'red' : 'green'}">${score > 0 ? '+' : ''}${score} 分</span>
    </div>
  </div>`;
}
function itemRow(it) {
  const now = new Date();
  const overdue = !it.isCompleted && it.dueDate && it.dueDate < now;
  const names = (it.assigneeIds || []).map(personName).filter(Boolean);
  return `<div class="task-row">
    <div class="tick">${it.isCompleted ? '✅' : '⬜️'}</div>
    <div><div class="t-title ${it.isCompleted ? 'done' : ''}">${esc(it.content || '（空白項目）')}</div>
      <div class="t-meta">${names.length ? '負責：' + esc(names.join('、')) : '未指派'}${it.dueDate ? '・截止 ' + fmtDue(it.dueDate) : ''}${it.completedAt ? '・完成 ' + fmtDateTime(it.completedAt) : ''}${it.note ? '・' + esc(it.note) : ''}</div></div>
    <div class="t-right">${overdue ? '<span class="chip red">逾期</span>' : ''}${it.sideRoleLink ? '<span class="chip purple">兼任</span>' : ''}</div>
  </div>`;
}
function renderSubDetail(main, ctx, id, tab) {
  const s = subById(id);
  if (!s) { main.innerHTML = pageHead('找不到部屬', '<a href="#/subs">回部屬列表</a>'); return; }
  const pot = potentialScore(s), act = proactivityScore(s, ctx), total = Math.round((pot + act) / 2);
  const b = birthdayInfo(s.birthday);
  const eq = equipmentOf(s.id);
  const now = new Date();
  const tabs = [['tasks', `任務 ${(s.tasks || []).length}`], ['meetings', `會議 ${(s.meetings || []).length}`], ['reports', `報告 ${(s.weeklyReports || []).length}`], ['records', `紀錄 ${(s.records || []).filter((r) => r.type !== '請假').length}`], ['leave', `請假 ${(s.records || []).filter((r) => r.type === '請假').length}`], ['equipment', `執掌設備 ${eq.length}`], ['career', `升職歷程 ${(s.promotions || []).length}`]];
  let body = '';
  if (tab === 'tasks') {
    const open = (s.tasks || []).filter((t) => !t.isCompleted).sort((a, b) => (a.dueDate || a.date) - (b.dueDate || b.date));
    const done = (s.tasks || []).filter((t) => t.isCompleted).sort((a, b) => (b.completedAt || b.date) - (a.completedAt || a.date));
    body = `<div class="grid cols-2"><div class="card"><h3>進行中 <span class="count">${open.length}</span></h3>${open.map(taskRow).join('') || '<div class="empty">沒有進行中的任務</div>'}</div>
      <div class="card"><h3>已完成 <span class="count">${done.length}</span></h3>${done.map(taskRow).join('') || '<div class="empty">尚無完成任務</div>'}</div></div>`;
  } else if (tab === 'meetings') {
    const ms = [...(s.meetings || [])].sort((a, b) => { const na = nextOccurrence(a), nb = nextOccurrence(b); return (na ? na.date : 8e15) - (nb ? nb.date : 8e15); });
    body = `<div class="card"><h3>會議 <span class="count">${ms.length}</span></h3>${ms.map((m) => {
      const items = allItems(m); const done = items.filter((i) => i.isCompleted).length; const nx = nextOccurrence(m);
      const horizon = new Date(now); horizon.setMonth(horizon.getMonth() + 3);
      const floor = new Date(now); floor.setDate(floor.getDate() - 7);
      const occs = expandOccurrences(m, floor, horizon).slice(0, 12);
      return `<div class="task-row"><div class="tick">${nx ? '📅' : '🗓️'}</div><div>
        <div class="t-title">${esc(m.topic || '未命名會議')}</div>
        <div class="t-meta">${ruleSummary(m.rule)}・${m.durationMinutes || 60} 分鐘・${nx ? '下一場 ' + fmtDateTime(nx.date) : '無未來場次'}・起 ${fmtDate(m.date).split(' ')[0]}</div>
        ${m.note ? `<div class="t-meta">${esc(m.note)}</div>` : ''}
        ${m.rule || (m.occurrences || []).length ? `<details class="agenda"><summary>場次與議程（近期 ${occs.length} 場）</summary><div class="sub-items">${occs.map((o) => `<div class="t-meta" style="margin-top:6px"><b>${fmtDateTime(o.date)}</b>${o.isCancelled ? '（已取消）' : o.isMoved ? '（已改期）' : ''}${o.isAdHoc ? '（臨時）' : ''}</div>${o.items.map(itemRow).join('') || '<div class="empty" style="padding:4px">尚未填議程</div>'}`).join('')}</div></details>` : ''}
        ${(m.items || []).length ? `<details class="agenda" open><summary>議程項目 ${done}/${items.length}</summary><div class="sub-items">${m.items.map(itemRow).join('')}</div></details>` : ''}
      </div><div class="t-right"><span class="chip indigo">${done}/${items.length} 項</span></div></div>`;
    }).join('') || '<div class="empty">尚無會議</div>'}</div>`;
  } else if (tab === 'reports') {
    const rs = [...(s.weeklyReports || [])].sort((a, b) => b.date - a.date);
    body = `<div class="card"><h3>報告 <span class="count">${rs.length}</span></h3>${rs.map((r) => `<div class="task-row"><div class="tick">${r.isCompleted ? '✅' : '⬜️'}</div><div><div class="t-title ${r.isCompleted ? 'done' : ''}">${esc(r.topic || '未命名報告')}</div><div class="t-meta">${fmtDate(r.date)}${r.completedAt ? '・完成 ' + fmtDateTime(r.completedAt) : ''}${r.note ? '・' + esc(r.note) : ''}</div></div><div class="t-right">${r.reportType ? `<span class="chip blue">${esc(r.reportType)}</span>` : ''}${!r.isCompleted && r.date < now ? '<span class="chip red">逾期</span>' : ''}${r.isCompleted && r.completedAt && r.completedAt > r.date ? '<span class="chip orange">逾期完成</span>' : ''}</div></div>`).join('') || '<div class="empty">尚無報告</div>'}</div>`;
  } else if (tab === 'records') {
    const rs = (s.records || []).filter((r) => r.type !== '請假').sort((a, b) => b.date - a.date);
    body = `<div class="card"><h3>紀錄 <span class="count">${rs.length}</span></h3>${rs.map((r) => `<div class="task-row"><div class="tick">•</div><div><div class="t-title">${esc(r.content || '（未填內容）')}</div><div class="t-meta">${fmtDate(r.date)}${r.note ? '・' + esc(r.note) : ''}</div></div><div class="t-right"><span class="chip ${REC_COLOR[r.type] || ''}">${esc(r.type)}${r.type === 'Miss Operation' && r.severity ? '・' + esc(r.severity) : ''}</span></div></div>`).join('') || '<div class="empty">尚無紀錄</div>'}</div>`;
  } else if (tab === 'leave') {
    const rs = (s.records || []).filter((r) => r.type === '請假').sort((a, b) => b.date - a.date);
    const hours = rs.reduce((a, r) => a + (typeof r.leaveHours === 'number' ? r.leaveHours : 8), 0);
    body = `<div class="card"><h3>請假 <span class="count">${rs.length} 筆・${hours} 小時</span></h3>${rs.map((r) => `<div class="task-row"><div class="tick">🗓️</div><div><div class="t-title">${esc(r.leaveType || '請假')}${r.content ? '・' + esc(r.content) : ''}</div><div class="t-meta">${fmtDateTime(r.date)}${r.endDate ? ' – ' + fmtDateTime(r.endDate) : ''}${r.note ? '・' + esc(r.note) : ''}</div></div><div class="t-right"><span class="chip teal">${typeof r.leaveHours === 'number' ? r.leaveHours : 8} 小時</span>${LEAVE_EXEMPT.has(r.leaveType || '') ? '<span class="chip">不扣分</span>' : ''}</div></div>`).join('') || '<div class="empty">沒有請假紀錄</div>'}</div>`;
  } else if (tab === 'equipment') {
    body = `<div class="card"><h3>執掌設備 <span class="count">${eq.length}</span></h3>${eq.map((e) => {
      const pms = [...(e.pmRecords || [])].sort((a, b) => b.date - a.date); const als = [...(e.alarms || [])].sort((a, b) => b.date - a.date);
      const d = e.departmentId && deptById(e.departmentId);
      return `<div class="task-row"><div class="tick">⚙️</div><div><div class="t-title"><a href="#/equipment/${e.id}" style="color:var(--teal)">${esc(e.name || '未命名設備')} ›</a></div><div class="t-meta">${d ? esc(d.name) + '・' : ''}${e.system ? esc(e.system) + '・' : ''}最近 PM ${pms[0] ? fmtDate(pms[0].date) + (pms[0].phase ? '（' + esc(pms[0].phase) + '）' : '') : '—'}・最近警報 ${als[0] ? fmtDateTime(als[0].date) : '—'}</div>${e.note ? `<div class="t-meta">${esc(e.note)}</div>` : ''}
        ${als.length ? `<details class="agenda"><summary>警報 ${als.length} 筆</summary><div class="sub-items">${als.slice(0, 20).map((a) => `<div class="t-meta" style="padding:3px 0">🔔 ${fmtDateTime(a.date)}　${esc(a.content)}</div>`).join('')}</div></details>` : ''}
        ${pms.length ? `<details class="agenda"><summary>PM ${pms.length} 筆</summary><div class="sub-items">${pms.slice(0, 20).map((p) => `<div class="t-meta" style="padding:3px 0">${p.phase === '停機' ? '⏸️' : p.phase === '完成復機' ? '▶️' : '🛠️'} ${fmtDateTime(p.date)}　${esc(p.phase || 'PM')}${p.note ? '・' + esc(p.note) : ''}</div>`).join('')}</div></details>` : ''}
      </div><div class="t-right"><span class="chip teal">PM ${pms.length}</span><span class="chip ${als.length ? 'red' : ''}">警報 ${als.length}</span></div></div>`;
    }).join('') || '<div class="empty">沒有執掌的設備</div>'}</div>`;
  } else if (tab === 'career') {
    const ps = [...(s.promotions || [])].sort((a, b) => b.date - a.date);
    body = `<div class="card"><h3>升職歷程 <span class="count">${ps.length}</span></h3>${ps.map((p) => `<div class="task-row"><div class="tick">📈</div><div><div class="t-title">${esc(p.fromTitle || '—')} → ${esc(p.toTitle || '—')}</div><div class="t-meta">${fmtDate(p.date)}${p.note ? '・' + esc(p.note) : ''}</div></div><div></div></div>`).join('') || '<div class="empty">尚無升職紀錄</div>'}</div>`;
  }

  main.innerHTML = `
    <div class="crumb"><a href="#/subs">部屬列表</a> › ${esc(s.name)}</div>
    <div class="card hero">
      <div class="avatar">${esc(initial(s.name))}</div>
      <div style="flex:1;min-width:0">
        <div class="name">${esc(s.name)}</div>
        <div class="facts">
          ${s.jobTitle ? `<span>💼 ${esc(s.jobTitle)}</span>` : ''}
          ${deptNameOf(s) ? `<span>🏢 ${esc(deptNameOf(s))}${s.plantArea ? '（' + esc(s.plantArea) + '）' : ''}</span>` : ''}
          ${gradeLabelOf(s) ? `<span>🎖️ ${esc(gradeLabelOf(s))}</span>` : ''}
          ${s.joinDate ? `<span>📆 到職 ${fmtDate(s.joinDate).split(' ')[0]}（${Math.floor(daysBetween(s.joinDate, now) / 365)} 年）</span>` : ''}
          ${b ? `<span>🎂 ${s.birthday.getMonth() + 1}/${s.birthday.getDate()}・${b.sign}${b.days <= 30 ? `・${b.days === 0 ? '今天生日' : b.days + ' 天後'}` : ''}</span>` : ''}
          ${ctx.sideRoles[s.id] ? `<span>🧩 兼任待辦 ${ctx.sideRoles[s.id].done}/${ctx.sideRoles[s.id].total}</span>` : ''}
          ${ctx.mentions[s.id] ? `<span>@ 被標註 ${ctx.mentions[s.id]}</span>` : ''}
        </div>
        ${s.note ? `<div class="muted small" style="margin-top:6px">${esc(s.note)}</div>` : ''}
      </div>
      <div class="row" style="gap:18px">
        <div class="score-card"><div class="muted small">潛力</div><div class="big score ${scoreClass(pot)}">${pot}</div></div>
        <div class="score-card"><div class="muted small">主動性</div><div class="big score ${scoreClass(act)}">${act}</div></div>
        <div class="score-card"><div class="muted small">綜合</div><div class="big score ${scoreClass(total)}">${total}</div></div>
      </div>
    </div>
    <div class="grid cols-2 mt">
      <div class="card"><h3>潛力評分明細</h3>${breakdownHTML(potentialBreakdown(s))}<div class="legend-note">記錄式評分：優點／成就／改善加分，缺點／缺失／疏失扣分。沒有 100 分上限。</div></div>
      <div class="card"><h3>主動性評分明細</h3>${breakdownHTML(proactivityBreakdown(s, ctx))}<div class="legend-note">逾期採定案制：逾期未完成與逾期才完成都計入（目前逾期 ${overdueOpenCount(s)} 項）。</div></div>
    </div>
    <div class="tabs">${tabs.map(([k, l]) => `<button class="${k === tab ? 'on' : ''}" data-tab="${k}">${l}</button>`).join('')}</div>
    ${body}`;
  main.querySelectorAll('.tabs button').forEach((btn) => btn.onclick = () => { location.hash = `#/sub/${s.id}/${btn.dataset.tab}`; });
}

// ---- 人才矩陣 -------------------------------------------------------------
function median(arr) { if (!arr.length) return 0; const a = [...arr].sort((x, y) => x - y); const m = Math.floor(a.length / 2); return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2; }
function renderMatrix(main, ctx) {
  const pts = Store.subs.map((s) => ({ s, x: proactivityScore(s, ctx), y: potentialScore(s), total: overallScore(s, ctx) }));
  const mx = median(pts.map((p) => p.x)), my = median(pts.map((p) => p.y));
  const q = { star: pts.filter((p) => p.x >= mx && p.y >= my), pot: pts.filter((p) => p.x < mx && p.y >= my), work: pts.filter((p) => p.x >= mx && p.y < my), watch: pts.filter((p) => p.x < mx && p.y < my) };
  main.innerHTML = `
    ${pageHead('人才矩陣', `橫軸主動性・縱軸潛力・以中位數（${mx} / ${my}）切四象限`)}
    <div class="card chart-card"><div class="chart-box" style="height:520px"><canvas id="matrix-chart"></canvas></div>
      <div class="quad">
        <div class="q"><div class="qn" style="color:var(--green)">${q.star.length}</div><div class="ql">⭐ 明星（高潛力・高主動）</div><div class="small muted">${esc(q.star.map((p) => p.s.name).join('、')) || '—'}</div></div>
        <div class="q"><div class="qn" style="color:var(--blue)">${q.pot.length}</div><div class="ql">🌱 潛力股（高潛力・待啟動）</div><div class="small muted">${esc(q.pot.map((p) => p.s.name).join('、')) || '—'}</div></div>
        <div class="q"><div class="qn" style="color:var(--orange)">${q.work.length}</div><div class="ql">🔧 實幹型（高主動・潛力待養）</div><div class="small muted">${esc(q.work.map((p) => p.s.name).join('、')) || '—'}</div></div>
        <div class="q"><div class="qn" style="color:var(--red)">${q.watch.length}</div><div class="ql">👀 需關注</div><div class="small muted">${esc(q.watch.map((p) => p.s.name).join('、')) || '—'}</div></div>
      </div></div>
    <div class="card mt table-wrap"><table class="tbl"><thead><tr><th>姓名</th><th>部門</th><th class="num">潛力</th><th class="num">主動性</th><th class="num">綜合</th><th>象限</th></tr></thead><tbody>
      ${pts.sort((a, b) => b.total - a.total).map((p) => `<tr class="clickable" onclick="location.hash='#/sub/${p.s.id}'"><td><b>${esc(p.s.name)}</b></td><td>${esc(deptNameOf(p.s))}</td><td class="num">${scoreHTML(p.y)}</td><td class="num">${scoreHTML(p.x)}</td><td class="num">${scoreHTML(p.total)}</td><td>${p.x >= mx && p.y >= my ? '⭐ 明星' : p.y >= my ? '🌱 潛力股' : p.x >= mx ? '🔧 實幹型' : '👀 需關注'}</td></tr>`).join('')}
    </tbody></table></div>`;
  if (!window.Chart) return;
  const css = getComputedStyle(document.documentElement);
  const textColor = css.getPropertyValue('--text').trim() || '#000';
  const lineColor = css.getPropertyValue('--line').trim() || 'rgba(0,0,0,0.1)';
  const colorOf = (p) => p.x >= mx && p.y >= my ? '#34c759' : p.y >= my ? '#007aff' : p.x >= mx ? '#ff9500' : '#ff3b30';
  const xs = pts.map((p) => p.x), ys = pts.map((p) => p.y);
  const padR = (arr) => { const lo = Math.min(...arr), hi = Math.max(...arr); const pad = Math.max(5, (hi - lo) * 0.15); return [Math.floor(lo - pad), Math.ceil(hi + pad)]; };
  const [xmin, xmax] = xs.length ? padR(xs) : [0, 100], [ymin, ymax] = ys.length ? padR(ys) : [0, 100];
  const medianLines = {
    id: 'medianLines',
    afterDraw(chart) {
      const { ctx: c, scales: { x, y } } = chart;
      c.save(); c.setLineDash([6, 6]); c.strokeStyle = 'rgba(128,128,128,0.6)'; c.lineWidth = 1;
      c.beginPath(); c.moveTo(x.getPixelForValue(mx), y.top); c.lineTo(x.getPixelForValue(mx), y.bottom); c.stroke();
      c.beginPath(); c.moveTo(x.left, y.getPixelForValue(my)); c.lineTo(x.right, y.getPixelForValue(my)); c.stroke();
      c.restore();
    },
  };
  const labels = {
    id: 'pointLabels',
    afterDatasetsDraw(chart) {
      const { ctx: c } = chart; const meta = chart.getDatasetMeta(0);
      c.save(); c.font = '700 12px -apple-system, "Noto Sans TC", sans-serif'; c.fillStyle = textColor; c.textAlign = 'left';
      meta.data.forEach((el, i) => { c.fillText(pts[i].s.name, el.x + 9, el.y + 4); });
      c.restore();
    },
  };
  charts.push(new Chart($('#matrix-chart'), {
    type: 'scatter',
    data: { datasets: [{ data: pts.map((p) => ({ x: p.x, y: p.y })), backgroundColor: pts.map(colorOf), pointRadius: 7, pointHoverRadius: 9 }] },
    options: {
      maintainAspectRatio: false, animation: { duration: 400 },
      scales: {
        x: { title: { display: true, text: '主動性', color: textColor }, min: xmin, max: xmax, grid: { color: lineColor }, ticks: { color: textColor } },
        y: { title: { display: true, text: '潛力', color: textColor }, min: ymin, max: ymax, grid: { color: lineColor }, ticks: { color: textColor } },
      },
      plugins: { legend: { display: false }, tooltip: { callbacks: { label: (t) => { const p = pts[t.dataIndex]; return `${p.s.name}：主動性 ${p.x}・潛力 ${p.y}・綜合 ${p.total}`; } } } },
      onClick: (e, els) => { if (els.length) location.hash = `#/sub/${pts[els[0].index].s.id}`; },
    },
    plugins: [medianLines, labels],
  }));
}

// ---- 統計圖表 -------------------------------------------------------------
function yearOf(d) { return d instanceof Date ? d.getFullYear() : null; }
function inYear(d, year) { return year === 'all' || yearOf(d) === Number(year); }
function renderStats(main, ctx, year) {
  const subs = Store.subs;
  const years = new Set();
  for (const s of subs) {
    for (const t of s.tasks || []) { years.add(yearOf(t.completedAt || t.date)); }
    for (const r of s.weeklyReports || []) years.add(yearOf(r.completedAt || r.date));
    for (const r of s.records || []) years.add(yearOf(r.date));
  }
  const yearList = [...years].filter(Boolean).sort((a, b) => b - a);
  const per = (fn) => subs.map((s) => ({ name: s.name, v: fn(s) }));
  const defs = [
    { key: 'leave', title: '請假時數', unit: '小時', color: '#30b0c7', fn: (s) => (s.records || []).filter((r) => r.type === '請假' && inYear(r.date, year)).reduce((a, r) => a + (typeof r.leaveHours === 'number' ? r.leaveHours : 8), 0), note: '含不扣分假別；依請假日期歸年。' },
    { key: 'tasks', title: '任務完成數', unit: '件', color: '#32ade6', fn: (s) => (s.tasks || []).filter((t) => t.isCompleted && !t.isDereliction && inYear(t.completedAt || t.date, year)).length, note: '不含「應做未作為（缺失）」；依完成時間歸年。' },
    { key: 'reports', title: '報告完成數', unit: '份', color: '#007aff', fn: (s) => (s.weeklyReports || []).filter((r) => r.isCompleted && inYear(r.completedAt || r.date, year)).length },
    { key: 'plus', title: '加分（優點・成就・改善）', unit: '分', color: '#34c759', fn: (s) => (s.records || []).filter((r) => inYear(r.date, year)).reduce((a, r) => a + (r.type === '優點' ? W.potPro : r.type === '成就' ? W.potAch : r.type === '改善' ? W.potImp : 0), 0) },
    { key: 'minus', title: '扣分（缺點・缺失・疏失・缺失任務）', unit: '分', color: '#ff3b30', fn: (s) => (s.records || []).filter((r) => inYear(r.date, year)).reduce((a, r) => a + (r.type === '缺點' ? W.potCon : r.type === '缺失' ? W.potFault : r.type === 'Miss Operation' ? (r.severity === '輕微' ? W.potMissMinor : r.severity === '嚴重' ? W.potMissSevere : W.potMissNormal) : 0), 0) + (s.tasks || []).filter((t) => t.isDereliction && t.isCompleted && inYear(t.completedAt || t.date, year)).reduce((a, t) => a + Math.abs(t.customScore ?? -1), 0) },
    { key: 'overdue', title: '逾期（含補完成）', unit: '項', color: '#ff9500', fn: (s) => { const now = new Date(); let n = 0; for (const t of s.tasks || []) { if (t.sideRoleLink || !t.dueDate || !inYear(t.dueDate, year)) continue; if (t.isCompleted) { if (t.completedAt && t.completedAt > t.dueDate) n++; } else if (t.dueDate < now) n++; } for (const r of s.weeklyReports || []) { if (!inYear(r.date, year)) continue; if (r.isCompleted) { if (r.completedAt && r.completedAt > r.date) n++; } else if (r.date < now) n++; } return n; }, note: '依截止日歸年。' },
    { key: 'act', title: '主動性（目前）', unit: '分', color: '#5856d6', fn: (s) => proactivityScore(s, ctx), current: true },
    { key: 'pot', title: '潛力（目前）', unit: '分', color: '#af52de', fn: (s) => potentialScore(s), current: true },
    { key: 'total', title: '總分（目前）', unit: '分', color: '#d4a017', fn: (s) => overallScore(s, ctx), current: true },
  ];
  main.innerHTML = `
    ${pageHead('統計圖表', '各項目依人排序；灰色長條為團隊平均（含 0 的人）')}
    <div class="filters"><span class="muted small">年度</span>
      <a class="fchip ${year === 'all' ? 'on' : ''}" href="#/stats/all">全部</a>
      ${yearList.map((y) => `<a class="fchip ${String(year) === String(y) ? 'on' : ''}" href="#/stats/${y}">${y}</a>`).join('')}
    </div>
    <div class="grid cols-2">${defs.map((c) => `<div class="card chart-card"><h3>${esc(c.title)}${c.current ? '<span class="chip">不分年度</span>' : ''}</h3><div class="chart-box" style="height:${Math.max(180, 30 * (subs.length + 1) + 40)}px"><canvas id="stat-${c.key}"></canvas></div>${c.note ? `<div class="legend-note">${esc(c.note)}</div>` : ''}</div>`).join('')}</div>`;
  if (!window.Chart) return;
  const css = getComputedStyle(document.documentElement);
  const textColor = css.getPropertyValue('--text').trim() || '#000';
  const lineColor = css.getPropertyValue('--line').trim() || 'rgba(0,0,0,0.1)';
  for (const c of defs) {
    const people = per(c.fn);
    const avg = people.length ? Math.round(people.reduce((a, r) => a + r.v, 0) / people.length * 10) / 10 : 0;
    // 團隊平均依數值排進序列（而不是固定放最下面），一眼看出誰在平均之上／之下
    const rows = people.concat([{ name: '團隊平均', v: avg, isAvg: true }]).sort((a, b) => b.v - a.v);
    const labels = rows.map((r) => r.name);
    const data = rows.map((r) => r.v);
    const colors = rows.map((r) => (r.isAvg ? 'rgba(142,142,147,0.7)' : c.color));
    const ch = new Chart($(`#stat-${c.key}`), {
      type: 'bar',
      data: { labels, datasets: [{ data, backgroundColor: colors, borderRadius: 6, barThickness: 16 }] },
      options: {
        indexAxis: 'y', maintainAspectRatio: false, animation: { duration: 350 },
        scales: { x: { beginAtZero: true, grid: { color: lineColor }, ticks: { color: textColor } }, y: { grid: { display: false }, ticks: { color: textColor, font: { weight: '700' } } } },
        plugins: { legend: { display: false }, tooltip: { callbacks: { label: (t) => `${t.raw} ${c.unit}` } } },
      },
    });
    charts.push(ch);
  }
}

// ---- 公司組織 -------------------------------------------------------------
function deptMembers(deptId) {
  const subIds = new Set(Store.subs.filter((s) => s.departmentId === deptId).map((s) => s.id));
  const people = Store.orgPeople.filter((p) => p.departmentId === deptId);
  const linked = new Set(people.map((p) => p.linkedSubordinateId).filter(Boolean));
  const extraSubs = Store.subs.filter((s) => subIds.has(s.id) && !linked.has(s.id)).map((s) => ({ id: s.id, name: s.name, jobTitle: s.jobTitle, isSub: true, subId: s.id, gradeTitleId: s.gradeTitleId }));
  return people.map((p) => ({ id: p.id, name: p.name, jobTitle: p.jobTitle, isInactive: p.isInactive, subId: p.linkedSubordinateId && subById(p.linkedSubordinateId) ? p.linkedSubordinateId : null, gradeTitleId: p.gradeTitleId, birthday: p.birthday, works: p.works || [] })).concat(extraSubs);
}
function personCard(m) {
  const g = m.gradeTitleId && gradeById(m.gradeTitleId);
  const title = m.jobTitle || (g ? g.title : '');
  return `<div class="person ${m.isInactive ? 'inactive' : ''} ${m.subId ? 'clickable' : ''}" ${m.subId ? `onclick="location.hash='#/sub/${m.subId}'"` : ''}>
    <div class="avatar sm" style="${m.subId ? '' : 'background:linear-gradient(135deg,#8e8e93,#636366)'}">${esc(initial(m.name))}</div>
    <div style="min-width:0"><div class="pn">${esc(m.name)}${m.isInactive ? ' <span class="chip">已離職</span>' : ''}${m.subId ? ' <span class="chip green">部屬</span>' : ''}</div><div class="pt">${esc(title || '—')}${g && g.grade ? '・' + esc(g.grade) : ''}</div></div>
  </div>`;
}
function renderOrg(main) {
  const q = (renderOrg.q || '').trim().toLowerCase();
  const depts = [...Store.depts].sort((a, b) => (a.code || '').localeCompare(b.code || '') || a.name.localeCompare(b.name, 'zh-Hant'));
  const noDept = Store.orgPeople.filter((p) => !p.departmentId || !deptById(p.departmentId));
  const hit = (d) => !q || (d.name + d.code + d.function).toLowerCase().includes(q) || deptMembers(d.id).some((m) => (m.name + (m.jobTitle || '')).toLowerCase().includes(q));
  main.innerHTML = `
    ${pageHead('公司組織', `${Store.depts.length} 個部門・${Store.orgPeople.length} 位人員・${Store.equipment.length} 台設備`)}
    <div class="filters"><input type="search" id="org-q" placeholder="搜尋部門／人員" value="${esc(renderOrg.q || '')}"></div>
    <div class="grid cols-3">${depts.filter(hit).map((d) => {
      const members = deptMembers(d.id); const eq = Store.equipment.filter((e) => e.departmentId === d.id);
      const managers = (d.managerIds || []).map(personName).filter(Boolean);
      return `<div class="card dept-card" onclick="location.hash='#/dept/${d.id}'">
        <div class="code">${esc(d.code || '—')}</div><div class="dname">${esc(d.name || '未命名部門')}</div><div class="dfn">${esc(d.function || '')}</div>
        <div class="chips" style="margin-top:10px"><span class="chip green">${members.filter((m) => !m.isInactive).length} 人</span>${eq.length ? `<span class="chip teal">${eq.length} 台設備</span>` : ''}${managers.length ? `<span class="chip gold">主管：${esc(managers.join('、'))}</span>` : ''}</div>
        <div class="muted small" style="margin-top:8px">${esc(members.filter((m) => !m.isInactive).slice(0, 6).map((m) => m.name).join('、'))}${members.length > 6 ? ` 等 ${members.length} 人` : ''}</div>
      </div>`;
    }).join('') || '<div class="empty">沒有符合的部門</div>'}</div>
    ${noDept.length ? `<div class="section-title">未分部門的人員（${noDept.length}）</div><div class="people-grid">${noDept.filter((p) => !q || (p.name + p.jobTitle).toLowerCase().includes(q)).map((p) => personCard({ id: p.id, name: p.name, jobTitle: p.jobTitle, isInactive: p.isInactive, subId: p.linkedSubordinateId && subById(p.linkedSubordinateId) ? p.linkedSubordinateId : null, gradeTitleId: p.gradeTitleId })).join('')}</div>` : ''}`;
  $('#org-q').oninput = (e) => { renderOrg.q = e.target.value; const pos = e.target.selectionStart; renderOrg(main); const inp = $('#org-q'); inp.focus(); inp.setSelectionRange(pos, pos); };
}
function renderDept(main, ctx, id) {
  const d = deptById(id);
  if (!d) { main.innerHTML = pageHead('找不到部門', '<a href="#/org">回公司組織</a>'); return; }
  const members = deptMembers(d.id);
  const eq = Store.equipment.filter((e) => e.departmentId === d.id);
  const rel = (ids, label) => { const list = (ids || []).map(deptById).filter(Boolean); return list.length ? `<div><span class="muted small">${label}</span> ${list.map((x) => `<a class="chip blue" href="#/dept/${x.id}">${esc(x.name)}</a>`).join(' ')}</div>` : ''; };
  const managers = (d.managerIds || []).map(personName).filter(Boolean);
  const subs = members.filter((m) => m.subId).map((m) => subById(m.subId));
  const now = new Date();
  main.innerHTML = `
    <div class="crumb"><a href="#/org">公司組織</a> › ${esc(d.name)}</div>
    <div class="card hero"><div class="avatar" style="background:linear-gradient(135deg,#5856d6,#32ade6)">${esc(initial(d.code || d.name))}</div>
      <div style="flex:1"><div class="name">${esc(d.name)}${d.code ? ` <span class="chip">${esc(d.code)}</span>` : ''}</div>
        <div class="muted" style="margin-top:2px">${esc(d.function || '')}</div>
        <div class="facts" style="margin-top:8px">${managers.length ? `<span>👑 主管：${esc(managers.join('、'))}</span>` : ''}<span>👥 ${members.filter((m) => !m.isInactive).length} 人</span><span>⚙️ ${eq.length} 台設備</span></div>
        <div class="row" style="margin-top:8px;gap:14px">${rel(d.upstreamIds, '上游')}${rel(d.downstreamIds, '下游')}${rel(d.peerIds, '平行')}</div>
      </div></div>
    <div class="section-title">成員</div>
    <div class="people-grid">${members.map(personCard).join('') || '<div class="empty">尚無成員</div>'}</div>
    ${subs.length ? `<div class="section-title">部屬評分</div><div class="card table-wrap"><table class="tbl"><thead><tr><th>姓名</th><th>職稱</th><th class="num">潛力</th><th class="num">主動性</th><th class="num">綜合</th><th class="num">未完成任務</th><th class="num">逾期</th></tr></thead><tbody>${subs.map((s) => `<tr class="clickable" onclick="location.hash='#/sub/${s.id}'"><td><b>${esc(s.name)}</b></td><td>${esc(s.jobTitle || '')}</td><td class="num">${scoreHTML(potentialScore(s))}</td><td class="num">${scoreHTML(proactivityScore(s, ctx))}</td><td class="num">${scoreHTML(overallScore(s, ctx))}</td><td class="num">${(s.tasks || []).filter((t) => !t.isCompleted).length}</td><td class="num">${overdueOpenCount(s)}</td></tr>`).join('')}</tbody></table></div>` : ''}
    <div class="section-title">設備（${eq.length}）</div>
    <div class="card table-wrap"><table class="tbl"><thead><tr><th>設備</th><th>系統別</th><th>負責人</th><th>最近 PM</th><th class="num">PM 次數</th><th>最近警報</th><th class="num">警報數</th><th class="num">近 30 天警報</th></tr></thead><tbody>
      ${[...eq].sort((a, b) => (a.system || '').localeCompare(b.system || '') || a.name.localeCompare(b.name)).map((e) => {
        const pms = [...(e.pmRecords || [])].sort((a, b) => b.date - a.date); const als = [...(e.alarms || [])].sort((a, b) => b.date - a.date);
        const recent = als.filter((a) => daysBetween(a.date, now) <= 30).length; const owner = e.ownerId && subById(e.ownerId);
        return `<tr class="clickable" onclick="location.hash='#/equipment/${e.id}'"><td><b>${esc(e.name)}</b>${e.note ? `<div class="muted small">${esc(e.note)}</div>` : ''}</td><td>${e.system ? `<span class="chip teal">${esc(e.system)}</span>` : ''}</td><td>${owner ? `<a href="#/sub/${owner.id}">${esc(owner.name)}</a>` : '<span class="muted">未指派</span>'}</td><td>${pms[0] ? fmtDate(pms[0].date) + (pms[0].phase ? `（${esc(pms[0].phase)}）` : '') : '—'}</td><td class="num">${pms.length}</td><td>${als[0] ? fmtDateTime(als[0].date) : '—'}</td><td class="num">${als.length}</td><td class="num">${recent ? `<span class="chip red">${recent}</span>` : '0'}</td></tr>`;
      }).join('') || '<tr><td colspan="8" class="empty">此部門沒有設備</td></tr>'}
    </tbody></table></div>`;
}

// ---- 設備詳細頁 -----------------------------------------------------------
/** 全部屬掃描找出連到這則警報的任務（警報自動掛任務時寫入 equipmentLink.alarmId） */
function linkedAlarmTask(alarmId) {
  for (const s of Store.subs) {
    const t = (s.tasks || []).find((x) => x.equipmentLink && x.equipmentLink.alarmId === alarmId);
    if (t) return { sub: s, task: t };
  }
  return null;
}
function renderEquipment(main, ctx, id) {
  const e = Store.equipment.find((x) => x.id === id);
  if (!e) { main.innerHTML = pageHead('找不到設備', '<a href="#/org">回公司組織</a>'); return; }
  const now = new Date();
  const d = e.departmentId && deptById(e.departmentId);
  const owner = e.ownerId && subById(e.ownerId);
  const pms = [...(e.pmRecords || [])].sort((a, b) => b.date - a.date);
  const als = [...(e.alarms || [])].sort((a, b) => b.date - a.date);
  const lastPM = pms[0] || null;
  const daysSincePM = lastPM ? daysBetween(lastPM.date, now) : null;
  const in30 = als.filter((a) => daysBetween(a.date, now) <= 30).length;
  const in90 = als.filter((a) => daysBetween(a.date, now) <= 90).length;
  // 平均警報間隔（最近 10 次警報的相鄰間隔平均）
  const gaps = []; const recentAls = als.slice(0, 10);
  for (let i = 0; i + 1 < recentAls.length; i++) gaps.push((recentAls[i].date - recentAls[i + 1].date) / 86400000);
  const mtba = gaps.length ? Math.round(gaps.reduce((a, b) => a + b, 0) / gaps.length) : null;
  // 目前是否在保養中：最新一筆 PM 是「停機」且之後沒有「完成復機」
  const inMaintenance = !!(lastPM && lastPM.phase === '停機');
  const openAlarms = als.filter((a) => { const l = linkedAlarmTask(a.id); return l && !l.task.isCompleted; }).length;

  // 時間軸：PM 與警報合併、新到舊；警報標示距上一次 PM 的天數
  const pmDatesAsc = pms.map((p) => p.date).sort((a, b) => a - b);
  const entries = pms.map((p) => ({ id: p.id, isPM: true, date: p.date, text: p.note || '', phase: p.phase || null }))
    .concat(als.map((a) => { const prior = [...pmDatesAsc].reverse().find((x) => x <= a.date); return { id: a.id, isPM: false, date: a.date, text: a.content || '', daysSincePM: prior ? daysBetween(prior, a.date) : null }; }))
    .sort((a, b) => b.date - a.date);

  // 近 12 個月警報數（含 PM 次數作對照）
  const months = []; for (let i = 11; i >= 0; i--) { const m = new Date(now.getFullYear(), now.getMonth() - i, 1); months.push(m); }
  const key = (dt) => `${dt.getFullYear()}-${dt.getMonth()}`;
  const alarmByMonth = {}, pmByMonth = {};
  for (const a of als) alarmByMonth[key(a.date)] = (alarmByMonth[key(a.date)] || 0) + 1;
  for (const p of pms) if (p.phase !== '完成復機') pmByMonth[key(p.date)] = (pmByMonth[key(p.date)] || 0) + 1;

  const kpi = (label, value, cls = '', foot = '') => `<div class="card kpi"><div class="label">${label}</div><div class="value ${cls}">${value}</div>${foot ? `<div class="foot">${foot}</div>` : ''}</div>`;
  const timelineRow = (en) => {
    if (en.isPM) {
      const icon = en.phase === '停機' ? '⏸️' : en.phase === '完成復機' ? '▶️' : '🛠️';
      const chip = en.phase === '停機' ? '<span class="chip orange">PM 停機</span>' : en.phase === '完成復機' ? '<span class="chip green">PM 完成復機</span>' : '<span class="chip green">PM</span>';
      return `<div class="task-row"><div class="tick">${icon}</div><div><div class="t-title">${esc(en.text || (en.phase ? 'PM ' + en.phase : '預防保養'))}</div><div class="t-meta">${fmtDateTime(en.date)}</div></div><div class="t-right">${chip}</div></div>`;
    }
    const l = linkedAlarmTask(en.id);
    let resp = '';
    if (l) {
      const done = l.task.isCompleted;
      resp = `<details class="agenda"><summary style="color:${done ? 'var(--green)' : 'var(--orange)'}">${done ? '✅ 已完成回報' : '🧑‍🔧 處理中'}・<a href="#/sub/${l.sub.id}/tasks">${esc(l.sub.name)}</a></summary><div class="sub-items">
        <div class="t-meta" style="padding:3px 0"><b>處理措施</b>　${esc(l.task.responseAction || '（尚未回報）')}</div>
        <div class="t-meta" style="padding:3px 0"><b>回復結果</b>　${esc(l.task.responseResult || '（尚未回報）')}</div>
        ${done && l.task.completedAt ? `<div class="t-meta" style="padding:3px 0"><b>完成時間</b>　${fmtDateTime(l.task.completedAt)}</div>` : ''}
      </div></details>`;
    }
    return `<div class="task-row"><div class="tick">🔔</div><div><div class="t-title" style="color:var(--red)">${esc(en.text || '警報')}</div><div class="t-meta">${fmtDateTime(en.date)}${en.daysSincePM != null ? `・距上次 PM ${en.daysSincePM} 天` : '・之前沒有 PM 紀錄'}</div>${resp}</div><div class="t-right"><span class="chip red">警報</span></div></div>`;
  };

  main.innerHTML = `
    <div class="crumb"><a href="#/org">公司組織</a> › ${d ? `<a href="#/dept/${d.id}">${esc(d.name)}</a> › ` : ''}${esc(e.name)}</div>
    <div class="card hero" style="background:linear-gradient(135deg, rgba(48,176,199,0.18), rgba(88,86,214,0.10))">
      <div class="avatar" style="background:linear-gradient(135deg,#30b0c7,#5856d6)">⚙️</div>
      <div style="flex:1;min-width:0">
        <div class="name">${esc(e.name || '未命名設備')} ${e.system ? `<span class="chip teal big">${esc(e.system)}</span>` : ''} ${inMaintenance ? '<span class="chip orange big">保養中（停機）</span>' : ''}</div>
        <div class="facts">
          ${d ? `<span>🏢 <a href="#/dept/${d.id}">${esc(d.name)}</a></span>` : '<span>🏢 未指定部門</span>'}
          ${owner ? `<span>👤 負責人 <a href="#/sub/${owner.id}/equipment">${esc(owner.name)}</a>${owner.jobTitle ? '（' + esc(owner.jobTitle) + '）' : ''}</span>` : '<span>👤 未指派負責人</span>'}
          ${lastPM ? `<span>🛠️ 上次 PM ${fmtDate(lastPM.date).split(' ')[0]}${lastPM.phase ? '（' + esc(lastPM.phase) + '）' : ''}</span>` : ''}
          ${als[0] ? `<span>🔔 最近警報 ${fmtDateTime(als[0].date)}</span>` : ''}
        </div>
        ${e.note ? `<div class="muted small" style="margin-top:6px">${esc(e.note)}</div>` : ''}
      </div>
    </div>
    <div class="grid cols-5 mt">
      ${kpi('PM 總數', pms.length, 'green', `停機 ${pms.filter((p) => p.phase === '停機').length}・復機 ${pms.filter((p) => p.phase === '完成復機').length}`)}
      ${kpi('距上次 PM', daysSincePM == null ? '—' : daysSincePM + ' 天', daysSincePM != null && daysSincePM >= 90 ? 'orange' : '', daysSincePM != null && daysSincePM >= 90 ? '已超過 90 天' : '')}
      ${kpi('警報總數', als.length, als.length ? 'red' : '', mtba != null ? `平均間隔約 ${mtba} 天` : '')}
      ${kpi('30 天警報', in30, in30 ? 'red' : 'green', `90 天內 ${in90} 次`)}
      ${kpi('處理中警報', openAlarms, openAlarms ? 'orange' : 'green', '已自動掛任務、尚未回報完成')}
    </div>
    <div class="grid cols-2 mt">
      <div class="card chart-card"><h3>近 12 個月警報與 PM</h3><div class="chart-box" style="height:240px"><canvas id="eq-chart"></canvas></div><div class="legend-note">紅＝警報次數，綠＝PM 次數（停機與一般 PM；復機不重複計）。</div></div>
      <div class="card"><h3>警報內容統計 <span class="count">${als.length}</span></h3>${(() => {
        const c = {}; for (const a of als) { const k = (a.content || '警報').trim(); c[k] = (c[k] || 0) + 1; }
        const rows = Object.entries(c).sort((a, b) => b[1] - a[1]).slice(0, 10);
        return rows.length ? `<div class="list">${rows.map(([k, n]) => `<div class="item"><div class="main-text"><div class="title">${esc(k)}</div></div><span class="chip red">${n} 次</span></div>`).join('')}</div>` : '<div class="empty">尚無警報</div>';
      })()}</div>
    </div>
    <div class="card mt"><h3>PM／警報時間軸 <span class="count">${entries.length}</span>
      <span class="spacer"></span><span class="chip orange">⏸️ 停機</span><span class="chip green">▶️ PM／復機</span><span class="chip red">🔔 警報</span></h3>
      ${entries.map(timelineRow).join('') || '<div class="empty">尚無 PM／警報記錄</div>'}
    </div>`;

  if (!window.Chart) return;
  const css = getComputedStyle(document.documentElement);
  const textColor = css.getPropertyValue('--text').trim() || '#000';
  const lineColor = css.getPropertyValue('--line').trim() || 'rgba(0,0,0,0.1)';
  charts.push(new Chart($('#eq-chart'), {
    type: 'bar',
    data: {
      labels: months.map((m) => `${m.getFullYear() % 100}/${m.getMonth() + 1}`),
      datasets: [
        { label: '警報', data: months.map((m) => alarmByMonth[key(m)] || 0), backgroundColor: 'rgba(255,59,48,0.75)', borderRadius: 4 },
        { label: 'PM', data: months.map((m) => pmByMonth[key(m)] || 0), backgroundColor: 'rgba(52,199,89,0.75)', borderRadius: 4 },
      ],
    },
    options: {
      maintainAspectRatio: false, animation: { duration: 350 },
      scales: { x: { grid: { display: false }, ticks: { color: textColor } }, y: { beginAtZero: true, ticks: { color: textColor, precision: 0 }, grid: { color: lineColor } } },
      plugins: { legend: { labels: { color: textColor } } },
    },
  }));
}

// ---- 兼任職務 -------------------------------------------------------------
const sideRoles = () => Store.milestones.filter((m) => m.careerSubCategory === 'sideRole');
function roleName(r) { return (r.sideRoleName || r.title || '未命名職務').trim(); }
function roleActive(r) { return !r.sideRoleEndDate || r.sideRoleEndDate >= startOfDay(new Date()); }
function roleTasks(r) { return r.sideRoleTasks || []; }
function roleMembers(r) { return r.sideRoleMembers || []; }
function roleMeetings(r) { return r.sideRoleMeetings || []; }
function roleResolutions(r) { return r.sideRoleResolutions || []; }
function roleKeyDates(r) { return r.sideRoleKeyDates || []; }
function serialLabel(res) { return res.serial != null ? '#' + String(res.serial).padStart(3, '0') : ''; }
function memberById(r, mid) { return roleMembers(r).find((m) => m.id === mid); }
/** 成員 → 連結的部屬（linkedPersonId 可能是部屬、組織人員或名片） */
function memberSub(m) {
  if (!m.linkedPersonId) return null;
  const s = subById(m.linkedPersonId); if (s) return s;
  const p = Store.orgPeople.find((x) => x.id === m.linkedPersonId || x.linkedBusinessCardId === m.linkedPersonId);
  return p && p.linkedSubordinateId ? subById(p.linkedSubordinateId) : null;
}
function nextKeyDate(r) {
  const today = startOfDay(new Date());
  return [...roleKeyDates(r)].filter((k) => k.date >= today).sort((a, b) => a.date - b.date)[0] || null;
}
function roleStats(r) {
  const now = new Date();
  const tasks = roleTasks(r);
  const done = tasks.filter((t) => t.isCompleted).length;
  const overdue = tasks.filter((t) => !t.isCompleted && t.dueDate && t.dueDate < now).length;
  return { total: tasks.length, done, overdue, members: roleMembers(r).length, meetings: roleMeetings(r).length, resolutions: roleResolutions(r).length, keyDates: roleKeyDates(r).length };
}
function renderSideRoles(main) {
  const roles = sideRoles().sort((a, b) => (roleActive(b) - roleActive(a)) || (b.date - a.date));
  main.innerHTML = `
    ${pageHead('兼任職務', `${roles.filter(roleActive).length} 個在任・${roles.length - roles.filter(roleActive).length} 個已卸任`)}
    <div class="grid cols-2">${roles.map((r) => {
      const st = roleStats(r); const nk = nextKeyDate(r); const active = roleActive(r);
      const pct = st.total ? Math.round(st.done / st.total * 100) : 0;
      return `<div class="card dept-card" onclick="location.hash='#/siderole/${r.id}'" style="${active ? '' : 'opacity:.6'}">
        <div class="row" style="justify-content:space-between;align-items:flex-start">
          <div><div class="code">${esc(r.sideRoleOrg || '兼任職務')}</div><div class="dname">${esc(roleName(r))}</div></div>
          <div class="chips">${r.sideRoleIsLead ? '<span class="chip gold">主責</span>' : '<span class="chip">協辦</span>'}${active ? '<span class="chip green">在任</span>' : '<span class="chip">已卸任</span>'}</div>
        </div>
        <div class="dfn">${esc(r.sideRoleScope || r.note || '')}</div>
        <div class="muted small" style="margin-top:6px">就任 ${fmtDate(r.date).split(' ')[0]}${r.sideRoleEndDate ? '・卸任 ' + fmtDate(r.sideRoleEndDate).split(' ')[0] : ''}${nk ? `・下個重要日期 ${fmtDate(nk.date).split(' ')[0]} ${esc(nk.title)}` : ''}</div>
        <div class="chips" style="margin-top:10px">
          <span class="chip ${st.overdue ? 'red' : 'purple'}">待辦 ${st.done}/${st.total}${st.overdue ? '・逾期 ' + st.overdue : ''}</span>
          <span class="chip indigo">決議 ${st.resolutions}</span>
          <span class="chip blue">會議 ${st.meetings}</span>
          <span class="chip teal">成員 ${st.members}</span>
          <span class="chip orange">重要日期 ${st.keyDates}</span>
        </div>
        <div style="margin-top:10px;height:6px;border-radius:3px;background:var(--card2);overflow:hidden"><div style="width:${pct}%;height:100%;background:var(--purple)"></div></div>
      </div>`;
    }).join('') || '<div class="empty">還沒有兼任職務。在 App 的職涯里程碑新增「兼任職務」後就會出現在這裡。</div>'}</div>`;
}

function sideTaskRow(r, t) {
  const now = new Date();
  const overdue = !t.isCompleted && t.dueDate && t.dueDate < now;
  const names = (t.assigneeIds || []).map((mid) => memberById(r, mid)).filter(Boolean).map((m) => { const s = memberSub(m); return s ? `<a href="#/sub/${s.id}">${esc(m.name || s.name)}</a>` : esc(m.name); }).concat((t.extraAssignees || []).map(esc));
  const links = (t.links || []).map((l) => { const s = subById(l.subordinateId); return s ? `<a class="chip cyan" href="#/sub/${s.id}/${l.kind === 'meetingItem' ? 'meetings' : 'tasks'}">${l.kind === 'meetingItem' ? '議程' : '任務'}・${esc(s.name)}</a>` : ''; }).join('');
  return `<div class="task-row"><div class="tick">${t.isCompleted ? '✅' : '⬜️'}</div>
    <div><div class="t-title ${t.isCompleted ? 'done' : ''}">${esc(t.content || '（空白待辦）')}</div>
      <div class="t-meta">${names.length ? '負責：' + names.join('、') : '未指派'}${t.dueDate ? '・截止 ' + fmtDue(t.dueDate) : ''}${t.isCompleted && t.completedAt ? '・完成 ' + fmtDateTime(t.completedAt) : ''}</div>
      ${t.note ? `<div class="t-meta">備註：${esc(t.note)}</div>` : ''}
      ${(t.categories || []).length || links ? `<div class="chips" style="margin-top:4px">${(t.categories || []).map((c) => `<span class="chip purple">${esc(c)}</span>`).join('')}${links}</div>` : ''}
    </div>
    <div class="t-right">${overdue ? `<span class="chip red">逾期 ${daysBetween(t.dueDate, now)} 天</span>` : ''}</div></div>`;
}
function resolutionCard(r, res, byId, opts = {}) {
  const refs = (res.references || []).map((id) => byId[id]).filter(Boolean);
  return `<div class="card" id="res-${res.id}" style="margin-bottom:12px">
    <div class="row" style="align-items:flex-start;gap:10px">
      ${serialLabel(res) ? `<span class="chip indigo big">${serialLabel(res)}</span>` : ''}
      <div style="flex:1;min-width:0"><div style="font-size:16px;font-weight:900">${esc(res.title || '未命名決議')}</div>
        <div class="muted small">${fmtDate(res.date)}${res.initiator ? '・發起 ' + esc(res.initiator) : ''}${res.site ? '・' + esc(res.site) : ''}</div></div>
      <div class="chips">${(res.categories || []).map((c) => `<span class="chip purple">${esc(c)}</span>`).join('')}</div>
    </div>
    ${refs.length ? `<div class="section-title" style="margin:12px 0 6px">參照前案</div>${refs.map((x) => `<details class="agenda" style="margin:0 0 6px"><summary>${serialLabel(x) ? serialLabel(x) + ' ' : ''}${esc(x.title || '未命名決議')}・${fmtDate(x.date).split(' ')[0]}</summary><div class="sub-items"><div class="t-meta" style="white-space:pre-wrap;padding:6px 0">${esc(x.content || '（無內容）')}</div></div></details>`).join('')}` : ''}
    <div class="section-title" style="margin:12px 0 6px">決議內容</div>
    <div style="white-space:pre-wrap;line-height:1.7">${esc(res.content || '（無內容）')}</div>
    ${opts.backrefs && opts.backrefs.length ? `<div class="muted small" style="margin-top:10px">被後案參照：${opts.backrefs.map((x) => `<a href="#res-${x.id}" style="color:var(--indigo)">${serialLabel(x) || esc(x.title)}</a>`).join('、')}</div>` : ''}
  </div>`;
}
const roleUI = { q: '', cat: 'all' };
function renderSideRole(main, id, tab) {
  const r = sideRoles().find((x) => x.id === id);
  if (!r) { main.innerHTML = pageHead('找不到兼任職務', '<a href="#/sideroles">回兼任職務</a>'); return; }
  const st = roleStats(r); const nk = nextKeyDate(r); const now = new Date();
  const tabs = [['tasks', `待辦 ${st.total}`], ['resolutions', `重大決議 ${st.resolutions}`], ['meetings', `會議紀錄 ${st.meetings}`], ['members', `成員 ${st.members}`], ['keydates', `重要日期 ${st.keyDates}`]];
  let body = '';
  if (tab === 'tasks') {
    const open = roleTasks(r).filter((t) => !t.isCompleted).sort((a, b) => (a.dueDate ? +a.dueDate : 8e15) - (b.dueDate ? +b.dueDate : 8e15));
    const done = roleTasks(r).filter((t) => t.isCompleted).sort((a, b) => (b.completedAt || 0) - (a.completedAt || 0));
    body = `<div class="grid cols-2"><div class="card"><h3>進行中 <span class="count">${open.length}</span></h3>${open.map((t) => sideTaskRow(r, t)).join('') || '<div class="empty">沒有進行中的待辦</div>'}</div>
      <div class="card"><h3>已完成 <span class="count">${done.length}</span></h3>${done.map((t) => sideTaskRow(r, t)).join('') || '<div class="empty">尚無完成的待辦</div>'}</div></div>`;
  } else if (tab === 'resolutions') {
    const all = [...roleResolutions(r)].sort((a, b) => ((b.serial ?? -1) - (a.serial ?? -1)) || (b.date - a.date));
    const byId = Object.fromEntries(all.map((x) => [x.id, x]));
    const backrefs = {}; for (const x of all) for (const ref of x.references || []) (backrefs[ref] = backrefs[ref] || []).push(x);
    const cats = [...new Set(all.flatMap((x) => x.categories || []))].sort();
    const q = roleUI.q.trim().toLowerCase();
    const list = all.filter((x) => (roleUI.cat === 'all' || (x.categories || []).includes(roleUI.cat)) && (!q || (x.title + x.content + x.initiator + x.site + serialLabel(x)).toLowerCase().includes(q)));
    body = `<div class="filters"><input type="search" id="res-q" placeholder="搜尋流水號／標題／內容／發起人" value="${esc(roleUI.q)}">
        <span class="fchip ${roleUI.cat === 'all' ? 'on' : ''}" data-cat="all">全部</span>${cats.map((c) => `<span class="fchip ${roleUI.cat === c ? 'on' : ''}" data-cat="${esc(c)}">${esc(c)}</span>`).join('')}
        <span class="muted small">${list.length}/${all.length} 則</span></div>
      ${list.map((x) => resolutionCard(r, x, byId, { backrefs: backrefs[x.id] })).join('') || '<div class="empty">沒有符合的決議</div>'}`;
  } else if (tab === 'meetings') {
    const ms = [...roleMeetings(r)].sort((a, b) => b.date - a.date);
    body = `<div class="card"><h3>會議紀錄 <span class="count">${ms.length}</span></h3>${ms.map((m) => `<div class="task-row"><div class="tick">🗒️</div><div>
      <div class="t-title">${esc(m.topic || '未命名會議')}</div><div class="t-meta">${fmtDateTime(m.date)}${(m.attendees || []).length ? '・出席：' + esc(m.attendees.join('、')) : ''}</div>
      ${m.decisions ? `<div class="t-meta" style="margin-top:4px;white-space:pre-wrap"><b>決議事項</b>　${esc(m.decisions)}</div>` : ''}${m.note ? `<div class="t-meta" style="white-space:pre-wrap">備註：${esc(m.note)}</div>` : ''}</div><div></div></div>`).join('') || '<div class="empty">尚無會議紀錄</div>'}</div>`;
  } else if (tab === 'members') {
    body = `<div class="people-grid">${roleMembers(r).map((m) => { const s = memberSub(m); const mine = roleTasks(r).filter((t) => (t.assigneeIds || []).includes(m.id)); const done = mine.filter((t) => t.isCompleted).length;
      return `<div class="person ${s ? 'clickable' : ''}" ${s ? `onclick="location.hash='#/sub/${s.id}'"` : ''}><div class="avatar sm" style="${s ? '' : 'background:linear-gradient(135deg,#8e8e93,#636366)'}">${esc(initial(m.name))}</div>
        <div style="min-width:0"><div class="pn">${esc(m.name || '未命名')}${s ? ' <span class="chip green">部屬</span>' : ''}</div><div class="pt">${esc(m.dutyInRole || '—')}${m.contact ? '・' + esc(m.contact) : ''}・待辦 ${done}/${mine.length}</div>${m.note ? `<div class="pt">${esc(m.note)}</div>` : ''}</div></div>`; }).join('') || '<div class="empty">尚無成員</div>'}</div>`;
  } else if (tab === 'keydates') {
    const today = startOfDay(now);
    const ks = [...roleKeyDates(r)].sort((a, b) => a.date - b.date);
    const up = ks.filter((k) => k.date >= today), past = ks.filter((k) => k.date < today).reverse();
    const row = (k) => `<div class="task-row"><div class="tick">📌</div><div><div class="t-title">${esc(k.title || '未命名')}</div><div class="t-meta">${fmtDateTime(k.date)}${k.remindDaysBefore != null ? `・提前 ${k.remindDaysBefore} 天提醒` : ''}${k.note ? '・' + esc(k.note) : ''}</div></div><div class="t-right">${k.date >= today ? `<span class="chip ${daysBetween(today, k.date) <= 7 ? 'orange' : ''}">${daysBetween(today, k.date) === 0 ? '今天' : daysBetween(today, k.date) + ' 天後'}</span>` : ''}</div></div>`;
    body = `<div class="grid cols-2"><div class="card"><h3>即將到來 <span class="count">${up.length}</span></h3>${up.map(row).join('') || '<div class="empty">沒有未來的重要日期</div>'}</div><div class="card"><h3>已過 <span class="count">${past.length}</span></h3>${past.map(row).join('') || '<div class="empty">—</div>'}</div></div>`;
  }
  const pct = st.total ? Math.round(st.done / st.total * 100) : 0;
  main.innerHTML = `
    <div class="crumb"><a href="#/sideroles">兼任職務</a> › ${esc(roleName(r))}</div>
    <div class="card hero" style="background:linear-gradient(135deg, rgba(175,82,222,0.16), rgba(88,86,214,0.10))">
      <div class="avatar" style="background:linear-gradient(135deg,#af52de,#5856d6)">🧩</div>
      <div style="flex:1;min-width:0"><div class="name">${esc(roleName(r))} ${r.sideRoleIsLead ? '<span class="chip gold big">主責</span>' : '<span class="chip big">協辦</span>'} ${roleActive(r) ? '<span class="chip green big">在任</span>' : '<span class="chip big">已卸任</span>'}</div>
        <div class="facts">${r.sideRoleOrg ? `<span>🏛️ ${esc(r.sideRoleOrg)}</span>` : ''}<span>📆 就任 ${fmtDate(r.date).split(' ')[0]}${r.sideRoleEndDate ? '・卸任 ' + fmtDate(r.sideRoleEndDate).split(' ')[0] : ''}</span>${nk ? `<span>📌 ${fmtDate(nk.date).split(' ')[0]} ${esc(nk.title)}</span>` : ''}</div>
        ${r.sideRoleScope ? `<div class="muted small" style="margin-top:6px">負責範圍：${esc(r.sideRoleScope)}</div>` : ''}${r.note ? `<div class="muted small">${esc(r.note)}</div>` : ''}</div>
    </div>
    <div class="grid cols-5 mt">
      <div class="card kpi"><div class="label">待辦完成率</div><div class="value ${pct >= 80 ? 'green' : ''}">${pct}%</div><div class="foot">${st.done}/${st.total}</div></div>
      <div class="card kpi"><div class="label">逾期待辦</div><div class="value ${st.overdue ? 'red' : 'green'}">${st.overdue}</div></div>
      <div class="card kpi"><div class="label">重大決議</div><div class="value">${st.resolutions}</div><div class="foot">最新 ${roleResolutions(r).length ? serialLabel([...roleResolutions(r)].sort((a, b) => (b.serial ?? -1) - (a.serial ?? -1))[0]) || '—' : '—'}</div></div>
      <div class="card kpi"><div class="label">會議紀錄</div><div class="value">${st.meetings}</div></div>
      <div class="card kpi"><div class="label">成員</div><div class="value">${st.members}</div><div class="foot">部屬 ${roleMembers(r).filter(memberSub).length} 人</div></div>
    </div>
    <div class="tabs">${tabs.map(([k, l]) => `<button class="${k === tab ? 'on' : ''}" data-tab="${k}">${l}</button>`).join('')}</div>
    ${body}`;
  main.querySelectorAll('.tabs button').forEach((btn) => btn.onclick = () => { location.hash = `#/siderole/${r.id}/${btn.dataset.tab}`; });
  const q = $('#res-q'); if (q) q.oninput = (e) => { roleUI.q = e.target.value; const pos = e.target.selectionStart; renderSideRole(main, id, tab); const inp = $('#res-q'); inp.focus(); inp.setSelectionRange(pos, pos); };
  main.querySelectorAll('.fchip[data-cat]').forEach((c) => c.onclick = () => { roleUI.cat = c.dataset.cat; renderSideRole(main, id, tab); });
}

// ---- 我的行事曆 -----------------------------------------------------------
const CAL_KINDS = [
  ['task', '部屬任務', 'cyan'], ['meeting', '會議', 'indigo'], ['item', '議程截止', 'blue'], ['report', '報告', 'orange'],
  ['leave', '請假', 'teal'], ['sideTask', '兼任待辦', 'purple'], ['keyDate', '重要日期', 'red'], ['personal', '個人事件', 'green'], ['birthday', '生日', 'pink'],
];
const calUI = { hidden: new Set(), day: null };
function ymdKey(d) { return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`; }
function personalOccurs(pe, day) {
  const target = startOfDay(day), start = startOfDay(pe.date);
  if (target < start) return false;
  if (pe.recurrenceEndDate && target > startOfDay(pe.recurrenceEndDate)) return false;
  switch (pe.recurrence) {
    case '每天': return true;
    case '每週': return daysBetween(start, target) % 7 === 0;
    case '每月': { const months = (target.getFullYear() - start.getFullYear()) * 12 + (target.getMonth() - start.getMonth()); if (months < 0) return false; const exp = new Date(start); exp.setMonth(start.getMonth() + months); if (exp.getDate() !== start.getDate()) exp.setDate(0); return ymdKey(exp) === ymdKey(target); }
    case '每年': return target.getMonth() === start.getMonth() && target.getDate() === start.getDate();
    default: return ymdKey(target) === ymdKey(start);
  }
}
/** 收集某一段日期範圍內的所有行事曆項目，以 yyyy-mm-dd 分組 */
function calendarItems(from, to) {
  const out = {};
  const add = (d, it) => { const k = ymdKey(d); (out[k] = out[k] || []).push(Object.assign({ date: d }, it)); };
  const inRange = (d) => d >= from && d < to;
  const now = new Date();
  for (const s of Store.subs) {
    for (const t of s.tasks || []) {
      const d = t.dueDate || t.date; if (!inRange(d)) continue;
      add(d, { kind: 'task', title: t.topic || '未命名任務', who: s.name, done: t.isCompleted, derel: t.isDereliction, time: t.dueDate && !(t.dueDate.getHours() === 0 && t.dueDate.getMinutes() === 0) ? fmtTime(t.dueDate) : '', href: `#/sub/${s.id}/tasks`, overdue: !t.isCompleted && t.dueDate && t.dueDate < now });
    }
    for (const m of s.meetings || []) {
      for (const o of expandOccurrences(m, from, to)) { if (!inRange(o.date) || o.isCancelled) continue; add(o.date, { kind: 'meeting', title: m.topic || '未命名會議', who: s.name, time: fmtTime(o.date), sub: `${o.items.length} 項議程${o.isMoved ? '・已改期' : ''}${o.isAdHoc ? '・臨時' : ''}`, href: `#/sub/${s.id}/meetings` }); }
      for (const it of allItems(m)) { if (!it.dueDate || !inRange(it.dueDate)) continue; add(it.dueDate, { kind: 'item', title: it.content || '議程項目', who: `${s.name}・${m.topic}`, done: it.isCompleted, href: `#/sub/${s.id}/meetings` }); }
    }
    for (const r of s.weeklyReports || []) { if (!inRange(r.date)) continue; add(r.date, { kind: 'report', title: r.topic || '未命名報告', who: s.name, sub: r.reportType || '', done: r.isCompleted, overdue: !r.isCompleted && r.date < now, href: `#/sub/${s.id}/reports` }); }
    for (const r of s.records || []) {
      if (r.type !== '請假') continue;
      const a = startOfDay(r.date), b = startOfDay(r.endDate || r.date);
      for (let d = new Date(a); d <= b; d.setDate(d.getDate() + 1)) { if (!inRange(d)) continue; add(new Date(d), { kind: 'leave', title: `${s.name} ${r.leaveType || '請假'}`, sub: `${typeof r.leaveHours === 'number' ? r.leaveHours : 8} 小時${r.content ? '・' + r.content : ''}`, href: `#/sub/${s.id}/leave` }); }
    }
    const bi = birthdayInfo(s.birthday);
    if (bi) { for (const y of new Set([from.getFullYear(), to.getFullYear()])) { const d = new Date(y, s.birthday.getMonth(), s.birthday.getDate()); if (inRange(d)) add(d, { kind: 'birthday', title: `🎂 ${s.name} 生日`, sub: bi.sign, href: `#/sub/${s.id}` }); } }
  }
  for (const p of Store.orgPeople) {
    if (!(p.birthday instanceof Date) || p.isInactive || (p.linkedSubordinateId && subById(p.linkedSubordinateId))) continue;
    for (const y of new Set([from.getFullYear(), to.getFullYear()])) { const d = new Date(y, p.birthday.getMonth(), p.birthday.getDate()); if (inRange(d)) add(d, { kind: 'birthday', title: `🎂 ${p.name} 生日`, sub: p.jobTitle || '', href: '#/org' }); }
  }
  // 家庭：成員／寵物／人際關係的生日與結婚紀念日（比照 App 的行事曆）
  const yearly = (date, item) => { for (const y of new Set([from.getFullYear(), to.getFullYear()])) { const d = new Date(y, date.getMonth(), date.getDate()); if (inRange(d)) add(d, item); } };
  for (const m of Store.familyMembers || []) {
    const nm = m.chineseName || m.englishName || '未命名';
    if (m.birthday instanceof Date) yearly(m.birthday, { kind: 'birthday', title: `🎂 ${nm} 生日`, sub: m.role || '', href: '#/life/family' });
    if (m.marriageDate instanceof Date && !m.isDivorced) yearly(m.marriageDate, { kind: 'birthday', title: `💍 結婚紀念日`, sub: nm, href: '#/life/family' });
  }
  for (const p of Store.pets || []) if (p.birthday instanceof Date) yearly(p.birthday, { kind: 'birthday', title: `🎂 ${p.name} 生日`, sub: p.type || '寵物', href: '#/life/family/pets' });
  for (const r of Store.relationships || []) {
    if (r.birthday instanceof Date) yearly(r.birthday, { kind: 'birthday', title: `🎂 ${r.name} 生日`, sub: r.group || '', href: '#/life/family/relations' });
    if (r.anniversary instanceof Date) yearly(r.anniversary, { kind: 'birthday', title: `🎉 ${r.name} 紀念日`, sub: r.group || '', href: '#/life/family/relations' });
  }
  for (const t of Store.familyTasks || []) {
    if (!t.dueDate || !inRange(t.dueDate)) continue;
    const who = (t.assigneeIds || []).map((id) => { const m = (Store.familyMembers || []).find((x) => x.id === id); return m ? (m.chineseName || m.englishName) : ''; }).filter(Boolean);
    add(t.dueDate, { kind: 'personal', title: `🏠 ${t.content || '家庭待辦'}`, sub: who.join('、'), done: t.isCompleted, overdue: !t.isCompleted && t.dueDate < now, href: '#/life/family/tasks' });
  }
  for (const r of sideRoles()) {
    for (const t of roleTasks(r)) { if (!t.dueDate || !inRange(t.dueDate)) continue; add(t.dueDate, { kind: 'sideTask', title: t.content || '兼任待辦', who: roleName(r), done: t.isCompleted, overdue: !t.isCompleted && t.dueDate < now, href: `#/siderole/${r.id}/tasks` }); }
    for (const k of roleKeyDates(r)) { if (!inRange(k.date)) continue; add(k.date, { kind: 'keyDate', title: k.title || '重要日期', who: roleName(r), time: (k.date.getHours() || k.date.getMinutes()) ? fmtTime(k.date) : '', sub: k.note || '', href: `#/siderole/${r.id}/keydates` }); }
    for (const m of roleMeetings(r)) { if (!inRange(m.date)) continue; add(m.date, { kind: 'meeting', title: m.topic || '兼任會議', who: roleName(r), time: fmtTime(m.date), href: `#/siderole/${r.id}/meetings` }); }
  }
  for (const pe of Store.personalEvents || []) {
    for (let d = startOfDay(from); d < to; d.setDate(d.getDate() + 1)) {
      if (!personalOccurs(pe, d)) continue;
      const at = new Date(d); at.setHours(pe.date.getHours(), pe.date.getMinutes(), 0, 0);
      add(at, { kind: 'personal', title: pe.title || '個人事件', time: pe.durationMinutes === 0 ? '全日' : fmtTime(at), sub: [pe.kind, pe.location, pe.recurrence && pe.recurrence !== '不重複' ? pe.recurrence : ''].filter(Boolean).join('・'), href: '' });
    }
  }
  for (const k of Object.keys(out)) out[k].sort((a, b) => (a.time === '全日' ? -1 : 0) || (a.date - b.date));
  return out;
}
function calChip(it) {
  const k = CAL_KINDS.find((x) => x[0] === it.kind) || CAL_KINDS[0];
  return `<a class="chip ${it.overdue ? 'red' : k[2]}" ${it.href ? `href="${it.href}"` : ''} style="max-width:100%;overflow:hidden;text-overflow:ellipsis;display:block;${it.done ? 'opacity:.55;text-decoration:line-through' : ''}">${it.time ? it.time + ' ' : ''}${esc(it.title)}</a>`;
}
function renderCalendar(main, param) {
  const today = startOfDay(new Date());
  let year = today.getFullYear(), month = today.getMonth();
  let selected = calUI.day;
  const m = /^(\d{4})-(\d{2})(?:-(\d{2}))?$/.exec(param || '');
  if (m) { year = +m[1]; month = +m[2] - 1; if (m[3]) selected = new Date(year, month, +m[3]); }
  if (!selected || selected.getFullYear() !== year || selected.getMonth() !== month) selected = (today.getFullYear() === year && today.getMonth() === month) ? today : new Date(year, month, 1);
  calUI.day = selected;
  const first = new Date(year, month, 1), last = new Date(year, month + 1, 0);
  const gridStart = new Date(first); gridStart.setDate(first.getDate() - first.getDay());
  const gridEnd = new Date(last); gridEnd.setDate(last.getDate() + (6 - last.getDay()) + 1);
  const items = calendarItems(gridStart, gridEnd);
  const visible = (list) => (list || []).filter((it) => !calUI.hidden.has(it.kind));
  const prev = new Date(year, month - 1, 1), next = new Date(year, month + 1, 1);
  const monthKey = (d) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`;
  let cells = '';
  for (let d = new Date(gridStart); d < gridEnd; d.setDate(d.getDate() + 1)) {
    const list = visible(items[ymdKey(d)]);
    const inMonth = d.getMonth() === month; const isToday = ymdKey(d) === ymdKey(today); const isSel = ymdKey(d) === ymdKey(selected);
    cells += `<div class="cal-cell ${inMonth ? '' : 'dim'} ${isToday ? 'today' : ''} ${isSel ? 'sel' : ''}" data-day="${ymdKey(d)}">
      <div class="cal-num">${d.getDate()}${isToday ? '<span class="chip green" style="margin-left:4px">今天</span>' : ''}</div>
      <div class="cal-items">${list.slice(0, 4).map(calChip).join('')}${list.length > 4 ? `<div class="muted small">+${list.length - 4}</div>` : ''}</div></div>`;
  }
  const dayList = visible(items[ymdKey(selected)]);
  const groups = CAL_KINDS.map(([k, label, color]) => [k, label, color, dayList.filter((it) => it.kind === k)]).filter((g) => g[3].length);
  // 本月摘要
  const monthAll = Object.entries(items).filter(([k]) => k.startsWith(monthKey(first))).flatMap(([, v]) => visible(v));
  const count = (k) => monthAll.filter((it) => it.kind === k).length;
  main.innerHTML = `
    ${pageHead('我的行事曆', `${year} 年 ${month + 1} 月・本月 ${monthAll.length} 項`, `<div class="row"><a class="btn small" href="#/calendar/${monthKey(prev)}">‹ 上月</a><a class="btn small" href="#/calendar/${monthKey(today)}-${pad2(today.getDate())}">今天</a><a class="btn small" href="#/calendar/${monthKey(next)}">下月 ›</a></div>`)}
    <div class="filters">${CAL_KINDS.map(([k, label, color]) => `<span class="fchip ${calUI.hidden.has(k) ? '' : 'on'}" data-kind="${k}"><span class="chip ${color}" style="padding:0 6px">●</span> ${label} ${count(k)}</span>`).join('')}</div>
    <div class="cal-layout">
      <div class="card" style="padding:12px">
        <div class="cal-head">${WD.map((w) => `<div>週${w}</div>`).join('')}</div>
        <div class="cal-grid">${cells}</div>
      </div>
      <div class="card">
        <h3>${fmtDate(selected)}${ymdKey(selected) === ymdKey(today) ? ' <span class="chip green">今天</span>' : ''} <span class="count">${dayList.length}</span></h3>
        ${groups.map(([k, label, color, list]) => `<div class="section-title" style="margin:10px 0 4px">${label}（${list.length}）</div>${list.map((it) => `<a class="item clickable" ${it.href ? `href="${it.href}"` : ''} style="display:flex;align-items:center;gap:10px;padding:8px 4px;border-top:1px solid var(--line)">
            <span class="chip ${it.overdue ? 'red' : color}">${it.time || '—'}</span>
            <div class="main-text" style="flex:1;min-width:0"><div class="title" style="${it.done ? 'text-decoration:line-through;color:var(--muted)' : ''}${it.derel ? 'color:var(--red)' : ''}">${esc(it.title)}</div><div class="meta">${[it.who, it.sub].filter(Boolean).map(esc).join('・')}${it.overdue ? '・<span style="color:var(--red)">逾期</span>' : ''}${it.done ? '・已完成' : ''}</div></div></a>`).join('')}`).join('') || '<div class="empty">這天沒有任何項目</div>'}
      </div>
    </div>`;
  main.querySelectorAll('.cal-cell').forEach((c) => c.onclick = (e) => { if (e.target.closest('a[href]')) return; location.hash = `#/calendar/${c.dataset.day}`; });
  main.querySelectorAll('.fchip[data-kind]').forEach((c) => c.onclick = () => { const k = c.dataset.kind; if (calUI.hidden.has(k)) calUI.hidden.delete(k); else calUI.hidden.add(k); renderCalendar(main, param); });
}

// ---- 收支／理財／財富（計算規則移植自 LifeFinanceView 與各理財頁）------------------
// 銀行餘額＝手動存提款（排除已由固定支出／週期收入／信用卡展開取代的連結筆）＋固定支出週期
// 展開扣款＋週期收入展開＋連結信用卡消費扣款；外幣依 currencyRates 換算台幣；美股依「美金」匯率（沒有就 31）。
const financeMilestones = () => Store.milestones.filter((m) => m.financeSubCategory);
function rateOf(code) { if (!code || code === 'NT$') return 1; const r = (Store.currencyRates || []).find((x) => x.code === code); return r && r.rate > 0 ? r.rate : 1; }
function usdRate() { const r = (Store.currencyRates || []).find((x) => x.code === '美金' || x.code === 'USD'); return r && r.rate > 0 ? r.rate : 31; }
function fmtMoney(v, symbol = 'NT$') {
  const a = Math.abs(v), sign = v < 0 ? '-' : '';
  const trim = (x) => (Number.isInteger(Math.round(x * 10) / 10) ? String(Math.round(x)) : (Math.round(x * 10) / 10).toFixed(1));
  if (a >= 1e8) return `${sign}${symbol} ${trim(a / 1e8)} 億`;
  if (a >= 1e4) return `${sign}${symbol} ${trim(a / 1e4)} 萬`;
  return `${sign}${symbol} ${Math.round(a).toLocaleString('zh-Hant-TW')}`;
}
function fmtFull(v, symbol = 'NT$') { return (v < 0 ? '-' : '') + symbol + ' ' + Math.round(Math.abs(v)).toLocaleString('zh-Hant-TW'); }
function fmtAmt(v, code) { return fmtFull(v, code || 'NT$'); }
function addMonths(d, n) { const x = new Date(d); const day = x.getDate(); x.setDate(1); x.setMonth(x.getMonth() + n); const last = new Date(x.getFullYear(), x.getMonth() + 1, 0).getDate(); x.setDate(Math.min(day, last)); return x; }
function nextRecurrence(d, rec) { return rec === '每季' ? addMonths(d, 3) : rec === '每年' ? addMonths(d, 12) : addMonths(d, 1); }
function monthlyEquivalent(amount, rec) { return rec === '每季' ? amount / 3 : rec === '每年' ? amount / 12 : amount; }
/** 這筆固定支出目前還在扣的每月等值（已停止＝0） */
function activeMonthly(e) { return isFixedEnded(e) ? 0 : monthlyEquivalent(e.amount, e.recurrence) * rateOf(e.currencyCode); }
/** 固定支出展開成逐期扣款（貸款從下一期起算，與 App 相同）
 *  結束日＝最後一次扣款日：排定扣款日 <= 結束日的那幾期才算（與 App 同一條規則） */
function fixedLimit(exp, until) { return exp.endDate && exp.endDate < until ? exp.endDate : until; }
/** 已停止（結束日已過） */
function isFixedEnded(exp) { return !!(exp.endDate && startOfDay(exp.endDate) < startOfDay(new Date())); }
/** 某一天是否仍在有效期內（起始日 <= day <= 結束日） */
function isFixedActive(exp, day) {
  const d = startOfDay(day);
  if (startOfDay(exp.date) > d) return false;
  return !exp.endDate || d <= startOfDay(exp.endDate);
}
function expandFixed(exp, until) {
  const out = []; if (!exp.recurrence) return out;
  const limit = fixedLimit(exp, until);
  let cur = exp.fixedCategory === '貸款' ? nextRecurrence(exp.date, exp.recurrence) : new Date(exp.date);
  let i = 0; while (cur <= limit && i < 1200) { out.push({ date: cur, amount: exp.amount, currency: exp.linkedBankCurrency || exp.currencyCode || 'NT$', expense: exp }); cur = nextRecurrence(cur, exp.recurrence); i++; }
  return out;
}
function nextFixedDue(exp) {
  const now = new Date(); let cur = exp.fixedCategory === '貸款' ? nextRecurrence(exp.date, exp.recurrence) : new Date(exp.date); let i = 0;
  while (cur < startOfDay(now) && i < 1200) { cur = nextRecurrence(cur, exp.recurrence); i++; }
  // 已停止、或下一期已超過結束日 → 沒有下次扣款
  if (exp.endDate && startOfDay(cur) > startOfDay(exp.endDate)) return null;
  return cur;
}
function incomeActive(inc, d) { if (!inc.endDate) return true; return new Date(d.getFullYear(), d.getMonth(), 1) <= new Date(inc.endDate.getFullYear(), inc.endDate.getMonth(), 1); }
function expandIncome(inc, until) {
  if (!inc.period || inc.period === '單次') return inc.date <= until ? [{ date: inc.date, amount: inc.amount, currency: inc.linkedBankCurrency || 'NT$', income: inc }] : [];
  const out = []; let cur = new Date(inc.date); let i = 0;
  while (cur <= until && i < 1200) { if (!incomeActive(inc, cur)) break; out.push({ date: cur, amount: inc.amount, currency: inc.linkedBankCurrency || 'NT$', income: inc }); cur = inc.period === '每年' ? addMonths(cur, 12) : addMonths(cur, 1); i++; }
  return out;
}
function creditCardEntries(cardId, until) {
  const out = [];
  for (const e of Store.expenses) {
    if (e.linkedCreditCardMilestoneId !== cardId) continue;
    if (e.expenseType === '固定支出' && e.recurrence) { for (const x of expandFixed(e, until)) out.push({ date: x.date, amount: e.amount, expense: e }); }
    else if (e.date <= until) out.push({ date: e.date, amount: e.amount, expense: e });
  }
  return out;
}
function bankBalances(ms) {
  const now = new Date(); const totals = {};
  const expById = Object.fromEntries(Store.expenses.map((e) => [e.id, e])); const incById = Object.fromEntries(Store.incomes.map((i) => [i.id, i]));
  for (const dep of ms.bankDeposits || []) {
    if (!(dep.date <= now)) continue;
    const exp = dep.linkedExpenseId && expById[dep.linkedExpenseId]; const inc = dep.linkedExpenseId && incById[dep.linkedExpenseId];
    if (exp && exp.linkedCreditCardMilestoneId) continue;
    if (exp && exp.expenseType === '固定支出' && exp.recurrence) continue;
    if (inc && inc.period && inc.period !== '單次') continue;
    totals[dep.currencyCode || 'NT$'] = (totals[dep.currencyCode || 'NT$'] || 0) + (dep.isWithdrawal ? -dep.amount : dep.amount);
  }
  for (const e of Store.expenses) if (e.expenseType === '固定支出' && e.recurrence && e.linkedBankMilestoneId === ms.id && !e.linkedCreditCardMilestoneId) for (const x of expandFixed(e, now)) totals[x.currency] = (totals[x.currency] || 0) - x.amount;
  for (const inc of Store.incomes) if (inc.period && inc.period !== '單次' && inc.linkedBankMilestoneId === ms.id) for (const x of expandIncome(inc, now)) totals[x.currency] = (totals[x.currency] || 0) + x.amount;
  for (const card of financeMilestones().filter((c) => c.financeSubCategory === '信用卡' && c.linkedBankMilestoneId === ms.id)) for (const en of creditCardEntries(card.id, now)) totals['NT$'] = (totals['NT$'] || 0) - en.amount;
  const nz = Object.fromEntries(Object.entries(totals).filter(([, v]) => v !== 0));
  return Object.keys(nz).length ? nz : totals;
}
function balanceTWD(bal) { return Object.entries(bal).reduce((a, [code, v]) => a + v * rateOf(code), 0); }
function monthKeyOf(d) { return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`; }
/** 支出逐筆展開（固定支出逐期、變動支出原筆）到 until，附台幣等值 */
function expenseEntries(until) {
  const out = [];
  for (const e of Store.expenses) {
    if (e.expenseType === '固定支出' && e.recurrence) { for (const x of expandFixed(e, until)) out.push({ date: x.date, amount: e.amount, twd: e.amount * rateOf(e.currencyCode), cat: '固定・' + (e.fixedCategory || '其他'), expense: e }); }
    else if (e.date <= until) out.push({ date: e.date, amount: e.amount, twd: e.amount * rateOf(e.currencyCode), cat: e.variableCategory || e.fixedCategory || '其他', expense: e });
  }
  return out;
}
function incomeEntries(until) { const out = []; for (const i of Store.incomes) for (const x of expandIncome(i, until)) out.push({ date: x.date, amount: x.amount, twd: x.amount * rateOf(x.currency), income: i }); return out; }
/** 近 N 個月的收入／支出（台幣等值） */
function cashflowByMonth(n) {
  const now = new Date(); const months = []; for (let i = n - 1; i >= 0; i--) months.push(new Date(now.getFullYear(), now.getMonth() - i, 1));
  const from = months[0]; const until = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);
  const exp = {}, inc = {}, byCat = {};
  for (const x of expenseEntries(until)) { if (x.date < from) continue; const k = monthKeyOf(x.date); exp[k] = (exp[k] || 0) + x.twd; byCat[x.cat] = (byCat[x.cat] || 0) + x.twd; }
  for (const x of incomeEntries(until)) { if (x.date < from) continue; const k = monthKeyOf(x.date); inc[k] = (inc[k] || 0) + x.twd; }
  return { months, exp, inc, byCat };
}
function stockView(st) {
  const isUS = /^[A-Za-z]/.test(st.symbol || ''); const f = isUS ? usdRate() : 1;
  const cost = st.shares * st.purchasePrice * f; const mv = st.shares * (st.isSold ? st.soldPrice : st.currentPrice) * f;
  return { cost, mv, pl: mv - cost, rate: cost > 0 ? (mv - cost) / cost * 100 : 0, isUS, f };
}
function mortgageRemaining(re) {
  const now = new Date(); let total = 0;
  for (const m of re.mortgageItems || []) { const elapsed = Math.max(0, (now.getFullYear() - m.startDate.getFullYear()) * 12 + (now.getMonth() - m.startDate.getMonth())); total += Math.max(0, (m.totalPeriods - elapsed)) * m.amount; }
  return total;
}
function financeSummary() {
  const now = new Date();
  const fm = financeMilestones();
  const banks = fm.filter((m) => m.financeSubCategory === '銀行' && !m.isDisabled);
  const cardsMs = fm.filter((m) => m.financeSubCategory === '信用卡');
  const bankRows = banks.map((m) => { const bal = bankBalances(m); return { m, bal, twd: balanceTWD(bal) }; }).sort((a, b) => b.twd - a.twd);
  const bankTotal = bankRows.reduce((a, r) => a + r.twd, 0);
  const activeStocks = Store.stocks.filter((s) => !s.isSold && s.shares > 0).map((s) => Object.assign({ s }, stockView(s)));
  const stockMV = activeStocks.reduce((a, x) => a + x.mv, 0), stockCost = activeStocks.reduce((a, x) => a + x.cost, 0);
  const insTotal = Store.insurances.reduce((a, i) => a + (i.currentValue || 0) * rateOf(i.currencyCode), 0);
  const reHeld = Store.realEstates.filter((r) => !r.soldDate); const reValue = reHeld.reduce((a, r) => a + (r.currentValue || 0), 0); const reDebt = reHeld.reduce((a, r) => a + mortgageRemaining(r), 0);
  const vhHeld = Store.vehicles.filter((v) => !v.soldDate); const vhValue = vhHeld.reduce((a, v) => a + (v.currentValue || 0), 0);
  const thisKey = monthKeyOf(now);
  const cardMonth = (c) => creditCardEntries(c.id, now).filter((e) => monthKeyOf(e.date) === thisKey).reduce((a, e) => a + e.amount, 0);
  return { now, fm, banks, cardsMs, bankRows, bankTotal, activeStocks, stockMV, stockCost, insTotal, reHeld, reValue, reDebt, vhHeld, vhValue, netWorth: bankTotal + stockMV + insTotal + reValue + vhValue - reDebt, thisKey, cardMonth };
}
const kpiCard = (label, value, cls = '', foot = '') => `<div class="card kpi"><div class="label">${label}</div><div class="value ${cls}" style="font-size:22px">${value}</div>${foot ? `<div class="foot">${foot}</div>` : ''}</div>`;
function chartColors() { const css = getComputedStyle(document.documentElement); return { text: css.getPropertyValue('--text').trim() || '#000', line: css.getPropertyValue('--line').trim() || 'rgba(0,0,0,0.1)' }; }
function tabsHTML(base, tabs, cur) { return `<div class="tabs">${tabs.map(([k, l]) => `<a class="${k === cur ? 'on' : ''}" href="#/${base}/${k}" style="display:inline-block;border:1px solid var(--line);background:${k === cur ? 'var(--text)' : 'var(--card)'};color:${k === cur ? 'var(--bg)' : 'var(--muted)'};padding:7px 14px;border-radius:999px;font-weight:700;${k === cur ? 'border-color:transparent' : ''}">${l}</a>`).join('')}</div>`; }
function bankNameOf(id) { const m = id && Store.milestones.find((x) => x.id === id); return m ? m.title : ''; }
const CAT_COLOR = { '飲食': '#ff9500', '交通': '#5ac8fa', '汽車': '#30b0c7', '股票': '#34c759', '房地產': '#ff3b30', '稅費': '#8e8e93', '節稅': '#a2845e', '娛樂': '#af52de', '購物': '#ff2d55', '日用品': '#ffcc00', '醫療': '#ff6b6b', '教育': '#007aff', '社交': '#ff9f0a', '其他': '#c7c7cc' };
const catColor = (c) => (c.startsWith('固定') ? '#5856d6' : (CAT_COLOR[c] || '#8e8e93'));

// ---- 收支 -------------------------------------------------------------------
const EXPENSE_TABS = [['overview', '總覽'], ['income', '收入'], ['variable', '變動支出'], ['fixed', '固定支出'], ['chart', '圖表']];
const expUI = { month: null, cat: 'all', year: 'all', q: '' };
function renderExpense(main, tab, param) {
  const now = new Date();
  const S = financeSummary();
  const cf = cashflowByMonth(12);
  const yearStart = new Date(now.getFullYear(), 0, 1);
  const untilNow = now;
  const expAll = expenseEntries(untilNow), incAll = incomeEntries(untilNow);
  const ytdExp = expAll.filter((x) => x.date >= yearStart).reduce((a, x) => a + x.twd, 0);
  const ytdInc = incAll.filter((x) => x.date >= yearStart).reduce((a, x) => a + x.twd, 0);
  const mExp = cf.exp[S.thisKey] || 0, mInc = cf.inc[S.thisKey] || 0;
  let body = '';
  if (tab === 'overview') {
    const recent = [...Store.expenses].sort((a, b) => b.date - a.date).slice(0, 10);
    const horizon = new Date(now); horizon.setDate(horizon.getDate() + 30);
    const upcoming = Store.expenses.filter((e) => e.expenseType === '固定支出' && e.recurrence && !isFixedEnded(e))
      .map((e) => ({ e, due: nextFixedDue(e) })).filter((x) => x.due && x.due <= horizon).sort((a, b) => a.due - b.due);
    body = `<div class="grid cols-2">
      <div class="card chart-card"><h3>近 12 個月收支（台幣等值）</h3><div class="chart-box" style="height:280px"><canvas id="ex-cash"></canvas></div><div class="legend-note">支出＝變動支出＋固定支出逐期展開；收入＝單次＋薪資等週期展開。外幣依匯率表換算。</div></div>
      <div class="card chart-card"><h3>近 12 個月支出分類</h3><div class="chart-box" style="height:280px"><canvas id="ex-cat"></canvas></div></div>
    </div>
    <div class="grid cols-2 mt">
      <div class="card"><h3>最近記帳 <span class="count">${recent.length}</span></h3><div class="list">${recent.map((e) => `<div class="item"><span class="chip" style="background:${catColor(e.variableCategory || '固定')}22;color:${catColor(e.variableCategory || '固定')}">${esc(e.variableCategory || e.fixedCategory || '其他')}</span><div class="main-text"><div class="title">${esc(e.title)}</div><div class="meta">${fmtDate(e.date).split(' ')[0]}${e.linkedCreditCardMilestoneId ? '・💳 ' + esc(bankNameOf(e.linkedCreditCardMilestoneId)) : e.linkedBankMilestoneId ? '・🏦 ' + esc(bankNameOf(e.linkedBankMilestoneId)) : ''}</div></div><b>${fmtAmt(e.amount, e.currencyCode)}</b></div>`).join('') || '<div class="empty">尚無記帳</div>'}</div></div>
      <div class="card"><h3>30 天內到期的固定支出 <span class="count">${upcoming.length}</span></h3><div class="list">${upcoming.map(({ e, due }) => `<a class="item clickable" href="#/expense/fixed"><span class="chip indigo">${esc(e.fixedCategory || '固定')}</span><div class="main-text"><div class="title">${esc(e.title)}</div><div class="meta">${fmtDate(due).split(' ')[0]}・${esc(e.recurrence)}${e.linkedCreditCardMilestoneId ? '・💳 ' + esc(bankNameOf(e.linkedCreditCardMilestoneId)) : e.linkedBankMilestoneId ? '・🏦 ' + esc(bankNameOf(e.linkedBankMilestoneId)) : ''}</div></div><b>${fmtAmt(e.amount, e.currencyCode)}</b></a>`).join('') || '<div class="empty">30 天內沒有到期的固定支出</div>'}</div></div>
    </div>`;
  } else if (tab === 'income') {
    const years = [...new Set(incAll.map((x) => x.date.getFullYear()))].sort((a, b) => b - a);
    const list = [...Store.incomes].sort((a, b) => b.date - a.date).filter((i) => expUI.year === 'all' || i.date.getFullYear() === Number(expUI.year));
    const recurring = list.filter((i) => i.period && i.period !== '單次'), once = list.filter((i) => !i.period || i.period === '單次');
    const IC = { '薪水': 'blue', '獎金': 'gold', '禮金': 'pink', '確幸': 'purple', '投資': 'green' };
    const row = (i) => `<tr><td>${fmtDate(i.date).split(' ')[0]}</td><td><b>${esc(i.title)}</b>${i.note ? `<div class="muted small">${esc(i.note)}</div>` : ''}</td><td><span class="chip ${IC[i.category] || ''}">${esc(i.category)}</span></td><td>${esc(i.period || '單次')}${i.endDate ? `<div class="muted small">至 ${fmtDate(i.endDate).split(' ')[0]}${i.endReason ? '・' + esc(i.endReason) : ''}</div>` : ''}</td><td class="num"><b>${fmtAmt(i.amount, i.linkedBankCurrency)}</b></td><td class="muted small">${esc(bankNameOf(i.linkedBankMilestoneId))}</td></tr>`;
    const head = '<thead><tr><th>日期</th><th>項目</th><th>分類</th><th>週期</th><th class="num">金額</th><th>入帳銀行</th></tr></thead>';
    body = `<div class="filters"><span class="muted small">年度</span><span class="fchip ${expUI.year === 'all' ? 'on' : ''}" data-year="all">全部</span>${years.map((y) => `<span class="fchip ${String(expUI.year) === String(y) ? 'on' : ''}" data-year="${y}">${y}</span>`).join('')}</div>
      <div class="card table-wrap"><h3>週期收入 <span class="count">${recurring.length}</span></h3><table class="tbl">${head}<tbody>${recurring.map(row).join('') || '<tr><td colspan="6" class="empty">—</td></tr>'}</tbody></table></div>
      <div class="card table-wrap mt"><h3>單次收入 <span class="count">${once.length}</span></h3><table class="tbl">${head}<tbody>${once.map(row).join('') || '<tr><td colspan="6" class="empty">—</td></tr>'}</tbody></table></div>`;
  } else if (tab === 'variable') {
    const m = /^(\d{4})-(\d{2})$/.exec(param || '') ; const cur = m ? new Date(+m[1], +m[2] - 1, 1) : new Date(now.getFullYear(), now.getMonth(), 1);
    const monthStart = cur, monthEnd = new Date(cur.getFullYear(), cur.getMonth() + 1, 1);
    const list = Store.expenses.filter((e) => e.expenseType !== '固定支出' && e.date >= monthStart && e.date < monthEnd).sort((a, b) => b.date - a.date);
    const cats = [...new Set(list.map((e) => e.variableCategory || '其他'))].sort();
    const filtered = list.filter((e) => (expUI.cat === 'all' || (e.variableCategory || '其他') === expUI.cat) && (!expUI.q || (e.title + (e.note || '')).toLowerCase().includes(expUI.q.toLowerCase())));
    const total = list.reduce((a, e) => a + e.amount * rateOf(e.currencyCode), 0);
    const byCat = {}; for (const e of list) { const k = e.variableCategory || '其他'; byCat[k] = (byCat[k] || 0) + e.amount * rateOf(e.currencyCode); }
    const prev = new Date(cur.getFullYear(), cur.getMonth() - 1, 1), next = new Date(cur.getFullYear(), cur.getMonth() + 1, 1);
    body = `<div class="filters"><a class="btn small" href="#/expense/variable/${monthKeyOf(prev)}">‹ 上月</a><b>${cur.getFullYear()} 年 ${cur.getMonth() + 1} 月</b><a class="btn small" href="#/expense/variable/${monthKeyOf(next)}">下月 ›</a><span class="muted small">本月變動支出 ${fmtFull(total)}・${list.length} 筆</span><span class="spacer"></span><input type="search" id="ex-q" placeholder="搜尋項目／備註" value="${esc(expUI.q)}"></div>
      <div class="filters"><span class="fchip ${expUI.cat === 'all' ? 'on' : ''}" data-cat="all">全部</span>${cats.map((c) => `<span class="fchip ${expUI.cat === c ? 'on' : ''}" data-cat="${esc(c)}">${esc(c)} ${fmtMoney(byCat[c] || 0, '')}</span>`).join('')}</div>
      <div class="card table-wrap"><table class="tbl"><thead><tr><th>日期</th><th>項目</th><th>分類</th><th class="num">金額</th><th>付款</th><th>備註</th></tr></thead><tbody>${filtered.map((e) => `<tr><td>${fmtDate(e.date).split(' ')[0]}</td><td><b>${esc(e.title)}</b>${e.linkedVehicleId ? ' <span class="chip teal">🚗</span>' : ''}${e.evKwh ? ` <span class="chip green">⚡ ${e.evKwh} kWh</span>` : ''}</td><td><span class="chip" style="background:${catColor(e.variableCategory || '其他')}22;color:${catColor(e.variableCategory || '其他')}">${esc(e.variableCategory || '其他')}${e.vehicleExpenseCategory ? '・' + esc(e.vehicleExpenseCategory) : ''}${e.socialSubCategory ? '・' + esc(e.socialSubCategory) : ''}</span></td><td class="num"><b>${fmtAmt(e.amount, e.currencyCode)}</b></td><td class="muted small">${e.linkedCreditCardMilestoneId ? '💳 ' + esc(bankNameOf(e.linkedCreditCardMilestoneId)) : e.linkedBankMilestoneId ? '🏦 ' + esc(bankNameOf(e.linkedBankMilestoneId)) : ''}</td><td class="muted small">${esc(e.note || '')}${e.placeAddress ? ' 📍' + esc(e.placeAddress) : ''}</td></tr>`).join('') || '<tr><td colspan="6" class="empty">這個月沒有變動支出</td></tr>'}</tbody></table></div>`;
  } else if (tab === 'fixed') {
    const all = Store.expenses.filter((e) => e.expenseType === '固定支出');
    // 已停止的沉到最後（各自再依分類與金額排序）
    const list = [...all].sort((a, b) => (isFixedEnded(a) - isFixedEnded(b))
      || (a.fixedCategory || '').localeCompare(b.fixedCategory || '') || b.amount - a.amount);
    const active = all.filter((e) => !isFixedEnded(e));
    const ended = all.filter(isFixedEnded);
    const monthly = all.reduce((a, e) => a + activeMonthly(e), 0);
    const yearly = monthly * 12;
    const byCat = {}; for (const e of active) { const k = e.fixedCategory || '其他'; byCat[k] = (byCat[k] || 0) + activeMonthly(e); }
    body = `<div class="grid cols-4">${kpiCard('每月固定支出（等值）', fmtMoney(monthly), 'orange', `每年約 ${fmtMoney(yearly)}・不含已停止`)}${kpiCard('進行中項目', active.length, '', `${Object.keys(byCat).length} 個分類`)}${kpiCard('已停止', ended.length, ended.length ? 'orange' : 'green', ended.length ? `每月省下 ${fmtMoney(ended.reduce((a, e) => a + monthlyEquivalent(e.amount, e.recurrence) * rateOf(e.currencyCode), 0))}` : '全部進行中')}${kpiCard('最大一項', active.length ? esc(active.reduce((a, b) => (activeMonthly(a) >= activeMonthly(b) ? a : b)).title) : '—', '')}</div>
      <div class="chips mt">${Object.entries(byCat).sort((a, b) => b[1] - a[1]).map(([c, v]) => `<span class="chip indigo">${esc(c)} ${fmtMoney(v, '')}／月</span>`).join('')}</div>
      <div class="card table-wrap mt"><table class="tbl"><thead><tr><th>項目</th><th>分類</th><th>週期</th><th class="num">金額</th><th class="num">每月等值</th><th>下次扣款</th><th>扣款方式</th><th>金額變動</th></tr></thead><tbody>${list.map((e) => { const hist = (e.amountHistory || []).slice().sort((a, b) => a.date - b.date); const due = e.recurrence ? nextFixedDue(e) : null; const first = hist[0]; const trend = hist.length > 1 ? `${fmtMoney(first.amount, '')} → ${fmtMoney(e.amount, '')}（${hist.length} 次）` : ''; const done = isFixedEnded(e); return `<tr style="${done ? 'opacity:.55' : ''}"><td><b>${esc(e.title)}</b>${done ? ` <span class="chip orange">${esc(e.endReason || '已停止')}</span>` : ''}${e.note ? `<div class="muted small">${esc(e.note)}</div>` : ''}</td><td><span class="chip indigo">${esc(e.fixedCategory || '其他')}${e.insuranceSubCategory ? '・' + esc(e.insuranceSubCategory) : ''}${e.loanSubCategory ? '・' + esc(e.loanSubCategory) : ''}</span></td><td>${esc(e.recurrence || '—')}</td><td class="num"><b>${fmtAmt(e.amount, e.currencyCode)}</b></td><td class="num">${done ? '<span class="muted">—</span>' : fmtFull(activeMonthly(e))}</td><td>${done ? `<span class="muted">${e.endDate ? '止於 ' + fmtDate(e.endDate).split(' ')[0] : '已停止'}</span>` : (due ? fmtDate(due).split(' ')[0] + (daysBetween(now, due) <= 7 ? ' <span class="chip orange">' + (daysBetween(now, due) <= 0 ? '今天' : daysBetween(now, due) + ' 天') + '</span>' : '') : '—')}</td><td class="muted small">${e.linkedCreditCardMilestoneId ? '💳 ' + esc(bankNameOf(e.linkedCreditCardMilestoneId)) : e.linkedBankMilestoneId ? '🏦 ' + esc(bankNameOf(e.linkedBankMilestoneId)) : '—'}</td><td class="muted small">${trend}${e.loanTotalAmount ? `貸款 ${fmtMoney(e.loanTotalAmount)}・${e.loanYears || '?'} 年・${e.loanRate || '?'}%` : ''}</td></tr>`; }).join('') || '<tr><td colspan="8" class="empty">尚無固定支出</td></tr>'}</tbody></table></div>`;
  } else if (tab === 'chart') {
    const years = [...new Set(expAll.concat(incAll).map((x) => x.date.getFullYear()))].sort();
    const yExp = {}, yInc = {}; for (const x of expAll) yExp[x.date.getFullYear()] = (yExp[x.date.getFullYear()] || 0) + x.twd; for (const x of incAll) yInc[x.date.getFullYear()] = (yInc[x.date.getFullYear()] || 0) + x.twd;
    const y = expUI.year === 'all' ? now.getFullYear() : Number(expUI.year);
    const byCatY = {}; for (const x of expAll) if (x.date.getFullYear() === y) byCatY[x.cat] = (byCatY[x.cat] || 0) + x.twd;
    const monthsY = []; for (let i = 0; i < 12; i++) monthsY.push(new Date(y, i, 1));
    const mExpY = {}, mIncY = {}; for (const x of expAll) if (x.date.getFullYear() === y) mExpY[x.date.getMonth()] = (mExpY[x.date.getMonth()] || 0) + x.twd; for (const x of incAll) if (x.date.getFullYear() === y) mIncY[x.date.getMonth()] = (mIncY[x.date.getMonth()] || 0) + x.twd;
    body = `<div class="filters"><span class="muted small">分類與月份圖的年度</span>${years.slice().reverse().map((yy) => `<span class="fchip ${yy === y ? 'on' : ''}" data-year="${yy}">${yy}</span>`).join('')}</div>
      <div class="grid cols-2">
        <div class="card chart-card"><h3>年度收支</h3><div class="chart-box" style="height:260px"><canvas id="ex-year"></canvas></div></div>
        <div class="card chart-card"><h3>${y} 年逐月收支</h3><div class="chart-box" style="height:260px"><canvas id="ex-monthly"></canvas></div></div>
      </div>
      <div class="card chart-card mt"><h3>${y} 年支出分類</h3><div class="chart-box" style="height:${Math.max(220, 26 * Object.keys(byCatY).length + 40)}px"><canvas id="ex-cat-y"></canvas></div></div>`;
    main.__chartData = { years, yExp, yInc, y, byCatY, monthsY, mExpY, mIncY };
  }
  main.innerHTML = `
    ${pageHead('收支', `${fmtDate(now)}・台幣等值`)}
    <div class="grid cols-5">
      ${kpiCard('本月支出', fmtMoney(mExp), mExp > mInc ? 'orange' : '', `信用卡 ${fmtMoney(S.cardsMs.filter((c) => !c.isDisabled).reduce((a, c) => a + S.cardMonth(c), 0))}`)}
      ${kpiCard('本月收入', fmtMoney(mInc), 'green')}
      ${kpiCard('本月結餘', fmtMoney(mInc - mExp), mInc - mExp >= 0 ? 'green' : 'red')}
      ${kpiCard(`${now.getFullYear()} 年支出`, fmtMoney(ytdExp), '', `${Store.expenses.length} 筆記帳`)}
      ${kpiCard(`${now.getFullYear()} 年收入`, fmtMoney(ytdInc), 'green', `結餘 ${fmtMoney(ytdInc - ytdExp)}`)}
    </div>
    ${tabsHTML('expense', EXPENSE_TABS, tab)}
    ${body}`;
  main.querySelectorAll('.fchip[data-year]').forEach((c) => c.onclick = () => { expUI.year = c.dataset.year; renderExpense(main, tab, param); });
  main.querySelectorAll('.fchip[data-cat]').forEach((c) => c.onclick = () => { expUI.cat = c.dataset.cat; renderExpense(main, tab, param); });
  const q = $('#ex-q'); if (q) q.oninput = (e) => { expUI.q = e.target.value; const pos = e.target.selectionStart; renderExpense(main, tab, param); const inp = $('#ex-q'); inp.focus(); inp.setSelectionRange(pos, pos); };
  if (!window.Chart) return;
  const { text, line } = chartColors();
  const moneyTick = (v) => fmtMoney(v, '');
  if (tab === 'overview') {
    const labels = cf.months.map((m) => `${m.getFullYear() % 100}/${m.getMonth() + 1}`);
    charts.push(new Chart($('#ex-cash'), { type: 'bar', data: { labels, datasets: [{ label: '收入', data: cf.months.map((m) => Math.round(cf.inc[monthKeyOf(m)] || 0)), backgroundColor: 'rgba(52,199,89,0.75)', borderRadius: 4 }, { label: '支出', data: cf.months.map((m) => Math.round(cf.exp[monthKeyOf(m)] || 0)), backgroundColor: 'rgba(255,59,48,0.7)', borderRadius: 4 }] }, options: { maintainAspectRatio: false, animation: { duration: 350 }, scales: { x: { grid: { display: false }, ticks: { color: text } }, y: { beginAtZero: true, grid: { color: line }, ticks: { color: text, callback: moneyTick } } }, plugins: { legend: { labels: { color: text } }, tooltip: { callbacks: { label: (t) => `${t.dataset.label} ${fmtFull(t.raw)}` } } } } }));
    const cats = Object.entries(cf.byCat).sort((a, b) => b[1] - a[1]).slice(0, 12);
    charts.push(new Chart($('#ex-cat'), { type: 'bar', data: { labels: cats.map((c) => c[0]), datasets: [{ data: cats.map((c) => Math.round(c[1])), backgroundColor: cats.map((c) => catColor(c[0])), borderRadius: 5, barThickness: 14 }] }, options: { indexAxis: 'y', maintainAspectRatio: false, animation: { duration: 350 }, scales: { x: { beginAtZero: true, grid: { color: line }, ticks: { color: text, callback: moneyTick } }, y: { grid: { display: false }, ticks: { color: text, font: { weight: '700' } } } }, plugins: { legend: { display: false }, tooltip: { callbacks: { label: (t) => fmtFull(t.raw) } } } } }));
  } else if (tab === 'chart') {
    const D = main.__chartData;
    charts.push(new Chart($('#ex-year'), { type: 'bar', data: { labels: D.years, datasets: [{ label: '收入', data: D.years.map((yy) => Math.round(D.yInc[yy] || 0)), backgroundColor: 'rgba(52,199,89,0.75)', borderRadius: 4 }, { label: '支出', data: D.years.map((yy) => Math.round(D.yExp[yy] || 0)), backgroundColor: 'rgba(255,59,48,0.7)', borderRadius: 4 }] }, options: { maintainAspectRatio: false, scales: { x: { grid: { display: false }, ticks: { color: text } }, y: { beginAtZero: true, grid: { color: line }, ticks: { color: text, callback: moneyTick } } }, plugins: { legend: { labels: { color: text } }, tooltip: { callbacks: { label: (t) => `${t.dataset.label} ${fmtFull(t.raw)}` } } } } }));
    charts.push(new Chart($('#ex-monthly'), { type: 'line', data: { labels: D.monthsY.map((m) => `${m.getMonth() + 1} 月`), datasets: [{ label: '收入', data: D.monthsY.map((m) => Math.round(D.mIncY[m.getMonth()] || 0)), borderColor: '#34c759', backgroundColor: 'rgba(52,199,89,0.15)', fill: true, tension: 0.35 }, { label: '支出', data: D.monthsY.map((m) => Math.round(D.mExpY[m.getMonth()] || 0)), borderColor: '#ff3b30', backgroundColor: 'rgba(255,59,48,0.12)', fill: true, tension: 0.35 }] }, options: { maintainAspectRatio: false, scales: { x: { grid: { display: false }, ticks: { color: text } }, y: { beginAtZero: true, grid: { color: line }, ticks: { color: text, callback: moneyTick } } }, plugins: { legend: { labels: { color: text } }, tooltip: { callbacks: { label: (t) => `${t.dataset.label} ${fmtFull(t.raw)}` } } } } }));
    const cats = Object.entries(D.byCatY).sort((a, b) => b[1] - a[1]);
    charts.push(new Chart($('#ex-cat-y'), { type: 'bar', data: { labels: cats.map((c) => c[0]), datasets: [{ data: cats.map((c) => Math.round(c[1])), backgroundColor: cats.map((c) => catColor(c[0])), borderRadius: 5, barThickness: 14 }] }, options: { indexAxis: 'y', maintainAspectRatio: false, scales: { x: { beginAtZero: true, grid: { color: line }, ticks: { color: text, callback: moneyTick } }, y: { grid: { display: false }, ticks: { color: text, font: { weight: '700' } } } }, plugins: { legend: { display: false }, tooltip: { callbacks: { label: (t) => fmtFull(t.raw) } } } } }));
  }
}

// ---- 理財 -------------------------------------------------------------------
const FINANCE_TABS = [['overview', '總覽'], ['insurance', '儲蓄險'], ['stock', '股票'], ['vehicle', '載具'], ['realestate', '房地產'], ['chart', '圖表']];
function stockRowHTML(x) {
  return `<tr class="clickable" onclick="location.hash='#/finance/stock/${x.s.id}'"><td><b>${esc(x.s.symbol)}</b> ${x.isUS ? '<span class="chip blue">美股</span>' : ''}</td><td>${esc(x.s.name)}</td><td class="num">${x.s.shares.toLocaleString()}</td><td class="num">${x.s.purchasePrice}</td><td class="num">${x.s.isSold ? x.s.soldPrice : x.s.currentPrice}</td><td class="num">${fmtFull(x.cost)}</td><td class="num">${fmtFull(x.mv)}</td><td class="num"><span class="score ${x.pl >= 0 ? 's90' : 's0'}">${x.pl >= 0 ? '+' : ''}${fmtMoney(x.pl)}</span></td><td class="num"><span class="chip ${x.pl >= 0 ? 'green' : 'red'}">${x.rate >= 0 ? '+' : ''}${x.rate.toFixed(1)}%</span></td><td class="muted small">${(x.s.dividends || []).filter((d) => d.kind === '現金股利').length ? '配息 ' + (x.s.dividends || []).filter((d) => d.kind === '現金股利').length + ' 次' : ''}</td></tr>`;
}
const STOCK_HEAD = '<thead><tr><th>代號</th><th>名稱</th><th class="num">股數</th><th class="num">成本價</th><th class="num">現價</th><th class="num">成本</th><th class="num">市值</th><th class="num">損益</th><th class="num">報酬率</th><th>配息</th></tr></thead>';
function renderFinanceHome(main, tab, id) {
  if (tab === 'stock' && id) return renderStockDetail(main, id);
  const S = financeSummary(); const now = S.now;
  let body = '';
  if (tab === 'overview') {
    const alloc = [['銀行存款', S.bankTotal, '#007aff'], ['股票', S.stockMV, '#34c759'], ['儲蓄險', S.insTotal, '#af52de'], ['房地產', S.reValue, '#ff9500'], ['車輛', S.vhValue, '#30b0c7']].filter((a) => a[1] > 0);
    const total = alloc.reduce((a, x) => a + x[1], 0) || 1;
    body = `<div class="card"><h3>資產配置（台幣等值）</h3><div style="display:flex;height:22px;border-radius:8px;overflow:hidden;border:1px solid var(--line)">${alloc.map(([l, v, c]) => `<div title="${l} ${fmtMoney(v)}" style="width:${v / total * 100}%;background:${c}"></div>`).join('')}</div><div class="chips" style="margin-top:10px">${alloc.map(([l, v, c]) => `<span class="chip" style="background:${c}22;color:${c}">${l} ${fmtMoney(v)}・${Math.round(v / total * 100)}%</span>`).join('')}${S.reDebt ? `<span class="chip red">房貸餘額 −${fmtMoney(S.reDebt)}</span>` : ''}</div></div>
    <div class="grid cols-2 mt">
      <div class="card"><h3>持股市值前五 <span class="count">${S.activeStocks.length}</span></h3><div class="list">${S.activeStocks.sort((a, b) => b.mv - a.mv).slice(0, 5).map((x) => `<a class="item clickable" href="#/finance/stock/${x.s.id}"><div class="avatar sm" style="background:linear-gradient(135deg,#34c759,#30b0c7)">${esc(initial(x.s.symbol))}</div><div class="main-text"><div class="title">${esc(x.s.symbol)} ${esc(x.s.name)}</div><div class="meta">${x.s.shares.toLocaleString()} 股・成本 ${fmtMoney(x.cost)}</div></div><div style="text-align:right"><div class="score s80">${fmtMoney(x.mv)}</div><div class="small" style="color:${x.pl >= 0 ? 'var(--green)' : 'var(--red)'}">${x.pl >= 0 ? '+' : ''}${x.rate.toFixed(1)}%</div></div></a>`).join('') || '<div class="empty">尚無持股</div>'}</div></div>
      <div class="card"><h3>銀行帳戶 <span class="count">${S.bankRows.length}</span></h3><div class="list">${S.bankRows.map(({ m, bal, twd }) => `<a class="item clickable" href="#/life/wealth"><div class="avatar sm" style="background:linear-gradient(135deg,#007aff,#5ac8fa)">${esc(initial(m.bankName || m.title))}</div><div class="main-text"><div class="title">${esc(m.title)}</div><div class="meta">${esc([m.bankName, m.branchName, m.bankAccountType].filter(Boolean).join('・'))}${Object.keys(bal).length > 1 ? '・' + Object.entries(bal).map(([c, v]) => `${c} ${Math.round(v).toLocaleString()}`).join('／') : ''}</div></div><span class="score ${twd >= 0 ? 's80' : 's0'}">${fmtMoney(twd)}</span></a>`).join('') || '<div class="empty">尚無銀行帳戶</div>'}</div></div>
    </div>`;
  } else if (tab === 'insurance') {
    body = `<div class="card table-wrap"><h3>儲蓄險 <span class="count">${Store.insurances.length}</span><span class="spacer"></span><span class="muted small">現值合計 ${fmtMoney(S.insTotal)}</span></h3><table class="tbl"><thead><tr><th>名稱</th><th>公司</th><th class="num">每期保費</th><th>週期・利率</th><th>期間</th><th class="num">目前現值</th><th class="num">預期到期</th><th>連結固定支出</th></tr></thead><tbody>${Store.insurances.map((i) => { const total = Math.max(1, (i.maturityDate - i.startDate)); const pct = Math.min(100, Math.max(0, Math.round((now - i.startDate) / total * 100))); const linked = i.linkedExpenseId && Store.expenses.find((e) => e.id === i.linkedExpenseId); return `<tr><td><b>${esc(i.name)}</b>${i.note ? `<div class="muted small">${esc(i.note)}</div>` : ''}</td><td>${esc(i.company)}</td><td class="num">${fmtAmt(i.premiumAmount, i.currencyCode)}</td><td>${esc(i.paymentPeriod)}・${i.annualRate}%</td><td>${fmtDate(i.startDate).split(' ')[0]} – ${fmtDate(i.maturityDate).split(' ')[0]}<div style="height:4px;border-radius:2px;background:var(--card2);margin-top:4px"><div style="width:${pct}%;height:100%;background:var(--purple);border-radius:2px"></div></div><div class="muted small">${pct}%・剩 ${Math.max(0, Math.round((i.maturityDate - now) / 86400000 / 30))} 個月</div></td><td class="num"><b>${fmtAmt(i.currentValue, i.currencyCode)}</b>${i.currencyCode !== 'NT$' ? `<div class="muted small">≈ ${fmtMoney(i.currentValue * rateOf(i.currencyCode))}</div>` : ''}</td><td class="num">${fmtAmt(i.expectedReturn, i.currencyCode)}</td><td class="muted small">${linked ? esc(linked.title) : '—'}</td></tr>`; }).join('') || '<tr><td colspan="8" class="empty">尚無儲蓄險</td></tr>'}</tbody></table></div>`;
  } else if (tab === 'stock') {
    const sold = Store.stocks.filter((s) => s.isSold).map((s) => Object.assign({ s }, stockView(s)));
    body = `<div class="card table-wrap"><h3>持有中 <span class="count">${S.activeStocks.length}</span><span class="spacer"></span><span class="muted small">市值 ${fmtMoney(S.stockMV)}・損益 ${S.stockMV - S.stockCost >= 0 ? '+' : ''}${fmtMoney(S.stockMV - S.stockCost)}・美金匯率 ${usdRate()}</span></h3><table class="tbl">${STOCK_HEAD}<tbody>${S.activeStocks.sort((a, b) => b.mv - a.mv).map(stockRowHTML).join('') || '<tr><td colspan="10" class="empty">尚無持股</td></tr>'}</tbody></table></div>
      ${sold.length ? `<div class="card table-wrap mt"><h3>已賣出 <span class="count">${sold.length}</span></h3><table class="tbl">${STOCK_HEAD}<tbody>${sold.map(stockRowHTML).join('')}</tbody></table></div>` : ''}`;
  } else if (tab === 'vehicle') {
    body = `<div class="grid cols-2">${Store.vehicles.map((v) => {
      const linked = Store.expenses.filter((e) => e.linkedVehicleId === v.id);
      const byCat = {}; for (const e of linked) { const k = e.vehicleExpenseCategory || e.variableCategory || '其他'; byCat[k] = (byCat[k] || 0) + e.amount * rateOf(e.currencyCode); }
      const fixedMonthly = (v.fixedExpenses || []).reduce((a, f) => a + (f.period === '年' ? f.amount / 12 : f.amount), 0);
      const ev = linked.filter((e) => e.evKwh).sort((a, b) => a.date - b.date);
      const kwh = ev.reduce((a, e) => a + e.evKwh, 0); const evCost = ev.reduce((a, e) => a + e.amount, 0);
      const caps = ev.filter((e) => e.evFromPct != null && e.evToPct != null && e.evToPct - e.evFromPct >= 15).map((e) => e.evKwh / (e.evToPct - e.evFromPct) * 100);
      const cap = caps.length ? caps.reduce((a, b) => a + b, 0) / caps.length : null;
      const years = Math.max(0.1, (now - v.purchaseDate) / 86400000 / 365);
      return `<div class="card" style="${v.soldDate ? 'opacity:.6' : ''}"><h3>🚗 ${esc(v.name)} <span class="chip teal">${esc(v.powerType)}</span>${v.soldDate ? '<span class="chip">已售出</span>' : ''}</h3>
        <div class="muted small">${esc([v.brand, v.ownerName, '購入 ' + fmtDate(v.purchaseDate).split(' ')[0]].filter(Boolean).join('・'))}${v.note ? '・' + esc(v.note) : ''}</div>
        <div class="grid cols-3 mt"><div class="kpi"><div class="label">目前價值</div><div class="value" style="font-size:20px">${fmtMoney(v.currentValue)}</div><div class="foot">購入 ${fmtMoney(v.purchasePrice)}・折舊 ${fmtMoney(v.purchasePrice - v.currentValue)}</div></div><div class="kpi"><div class="label">每月固定</div><div class="value" style="font-size:20px">${fmtMoney(fixedMonthly)}</div><div class="foot">${(v.fixedExpenses || []).map((f) => esc(f.category)).join('、') || '—'}</div></div><div class="kpi"><div class="label">累計變動支出</div><div class="value" style="font-size:20px">${fmtMoney(Object.values(byCat).reduce((a, b) => a + b, 0))}</div><div class="foot">持有 ${years.toFixed(1)} 年・每年約 ${fmtMoney(Object.values(byCat).reduce((a, b) => a + b, 0) / years)}</div></div></div>
        <div class="chips mt">${Object.entries(byCat).sort((a, b) => b[1] - a[1]).map(([k, val]) => `<span class="chip teal">${esc(k)} ${fmtMoney(val, '')}</span>`).join('') || '<span class="muted small">尚無連結的記帳</span>'}</div>
        ${ev.length ? `<div class="section-title" style="margin:12px 0 6px">⚡ 充電（${ev.length} 次）</div><div class="grid cols-3"><div class="kpi"><div class="label">累計度數</div><div class="value" style="font-size:18px">${Math.round(kwh)} kWh</div></div><div class="kpi"><div class="label">平均每度電價</div><div class="value" style="font-size:18px">NT$ ${kwh ? (evCost / kwh).toFixed(2) : '—'}</div></div><div class="kpi"><div class="label">推估電池容量</div><div class="value" style="font-size:18px">${cap ? cap.toFixed(1) + ' kWh' : '—'}</div><div class="foot">充電區間 ≥15% 的紀錄平均</div></div></div><div class="chart-box mt" style="height:180px"><canvas data-ev="${v.id}"></canvas></div>` : ''}
      </div>`;
    }).join('') || '<div class="empty">尚無載具</div>'}</div>`;
    main.__ev = Store.vehicles.map((v) => ({ id: v.id, ev: Store.expenses.filter((e) => e.linkedVehicleId === v.id && e.evKwh).sort((a, b) => a.date - b.date) }));
  } else if (tab === 'realestate') {
    body = `<div class="grid cols-2">${Store.realEstates.map((r) => {
      const debt = mortgageRemaining(r); const paid = (r.paidItems || []).reduce((a, p) => a + p.amount, 0);
      const varByCat = {}; for (const x of r.variableExpenses || []) varByCat[x.category] = (varByCat[x.category] || 0) + x.amount;
      const monthlyMortgage = (r.mortgageItems || []).reduce((a, m) => a + m.amount, 0);
      return `<div class="card" style="${r.soldDate ? 'opacity:.6' : ''}"><h3>🏠 ${esc(r.name)} ${r.buildingType ? `<span class="chip orange">${esc(r.buildingType)}</span>` : ''}${r.soldDate ? '<span class="chip">已售出</span>' : ''}</h3>
        <div class="muted small">${esc([r.city, r.address, r.pingCount ? r.pingCount + ' 坪' : '', '購入 ' + fmtDate(r.purchaseDate).split(' ')[0], r.hasElevator ? '有電梯' : ''].filter(Boolean).join('・'))}</div>
        <div class="grid cols-3 mt"><div class="kpi"><div class="label">目前價值</div><div class="value" style="font-size:20px">${fmtMoney(r.currentValue)}</div><div class="foot">購入 ${fmtMoney(r.purchasePrice)}・${r.currentValue >= r.purchasePrice ? '+' : ''}${fmtMoney(r.currentValue - r.purchasePrice)}</div></div><div class="kpi"><div class="label">房貸餘額</div><div class="value ${debt ? 'orange' : 'green'}" style="font-size:20px">${fmtMoney(debt)}</div><div class="foot">每月 ${fmtMoney(monthlyMortgage)}${r.monthlyRental ? '・月租收入 ' + fmtMoney(r.monthlyRental) : ''}</div></div><div class="kpi"><div class="label">已付價金</div><div class="value" style="font-size:20px">${fmtMoney(paid)}</div><div class="foot">${(r.paidItems || []).map((p) => esc(p.title)).join('、') || '—'}</div></div></div>
        ${(r.mortgageItems || []).length ? `<div class="section-title" style="margin:12px 0 6px">貸款</div>${r.mortgageItems.map((m) => { const elapsed = Math.max(0, (now.getFullYear() - m.startDate.getFullYear()) * 12 + (now.getMonth() - m.startDate.getMonth())); const pct = Math.min(100, Math.round(elapsed / m.totalPeriods * 100)); return `<div class="t-meta"><b>${esc(m.title)}</b>　每期 ${fmtMoney(m.amount)}・${Math.min(elapsed, m.totalPeriods)}/${m.totalPeriods} 期・起 ${fmtDate(m.startDate).split(' ')[0]}<div style="height:5px;border-radius:3px;background:var(--card2);margin:4px 0 8px"><div style="width:${pct}%;height:100%;background:var(--orange);border-radius:3px"></div></div></div>`; }).join('')}` : ''}
        ${Object.keys(varByCat).length ? `<div class="chips mt">${Object.entries(varByCat).sort((a, b) => b[1] - a[1]).map(([k, val]) => `<span class="chip orange">${esc(k)} ${fmtMoney(val, '')}</span>`).join('')}</div>` : ''}
        ${(r.elevatorMaintenances || []).length ? `<div class="muted small mt">電梯保養 ${r.elevatorMaintenances.length} 筆・最近 ${fmtDate([...r.elevatorMaintenances].sort((a, b) => b.date - a.date)[0].date).split(' ')[0]}</div>` : ''}
      </div>`;
    }).join('') || '<div class="empty">尚無房地產</div>'}</div>`;
  } else if (tab === 'chart') {
    body = `<div class="grid cols-2"><div class="card chart-card"><h3>資產配置</h3><div class="chart-box" style="height:300px"><canvas id="fin-alloc"></canvas></div></div><div class="card chart-card"><h3>持股市值與成本</h3><div class="chart-box" style="height:300px"><canvas id="fin-stocks"></canvas></div></div></div>`;
  }
  main.innerHTML = `
    ${pageHead('理財', `台幣等值概算・${fmtDate(now)}`)}
    <div class="grid cols-5">
      ${kpiCard('淨資產概算', fmtMoney(S.netWorth), S.netWorth >= 0 ? 'green' : 'red', '銀行＋股票＋保險＋房產＋車輛 − 房貸餘額')}
      ${kpiCard('銀行總餘額', fmtMoney(S.bankTotal), '', `${S.bankRows.length} 個帳戶`)}
      ${kpiCard('股票市值', fmtMoney(S.stockMV), '', `損益 ${S.stockMV - S.stockCost >= 0 ? '+' : ''}${fmtMoney(S.stockMV - S.stockCost)}`)}
      ${kpiCard('儲蓄險現值', fmtMoney(S.insTotal), '', `${Store.insurances.length} 張`)}
      ${kpiCard('房產・車輛', fmtMoney(S.reValue + S.vhValue), '', S.reDebt ? `房貸餘額 ${fmtMoney(S.reDebt)}` : '')}
    </div>
    ${tabsHTML('finance', FINANCE_TABS, tab)}
    ${body}`;
  if (!window.Chart) return;
  const { text, line } = chartColors();
  if (tab === 'vehicle') {
    for (const { id: vid, ev } of main.__ev) {
      const cv = main.querySelector(`canvas[data-ev="${vid}"]`); if (!cv || ev.length < 2) continue;
      charts.push(new Chart(cv, { type: 'line', data: { labels: ev.map((e) => `${e.date.getMonth() + 1}/${e.date.getDate()}`), datasets: [{ label: '每度電價', data: ev.map((e) => +(e.amount / e.evKwh).toFixed(2)), borderColor: '#34c759', backgroundColor: 'rgba(52,199,89,0.15)', fill: true, tension: 0.35, pointRadius: 4 }] }, options: { maintainAspectRatio: false, scales: { x: { grid: { display: false }, ticks: { color: text } }, y: { grid: { color: line }, ticks: { color: text } } }, plugins: { legend: { display: false }, tooltip: { callbacks: { label: (t) => `NT$ ${t.raw}／kWh` } } } } }));
    }
  } else if (tab === 'chart') {
    const alloc = [['銀行存款', S.bankTotal, '#007aff'], ['股票', S.stockMV, '#34c759'], ['儲蓄險', S.insTotal, '#af52de'], ['房地產', S.reValue, '#ff9500'], ['車輛', S.vhValue, '#30b0c7']].filter((a) => a[1] > 0);
    charts.push(new Chart($('#fin-alloc'), { type: 'doughnut', data: { labels: alloc.map((a) => a[0]), datasets: [{ data: alloc.map((a) => Math.round(a[1])), backgroundColor: alloc.map((a) => a[2]), borderWidth: 0 }] }, options: { maintainAspectRatio: false, plugins: { legend: { position: 'right', labels: { color: text } }, tooltip: { callbacks: { label: (t) => `${t.label} ${fmtFull(t.raw)}` } } } } }));
    const st = S.activeStocks.sort((a, b) => b.mv - a.mv);
    charts.push(new Chart($('#fin-stocks'), { type: 'bar', data: { labels: st.map((x) => x.s.symbol), datasets: [{ label: '成本', data: st.map((x) => Math.round(x.cost)), backgroundColor: 'rgba(142,142,147,0.6)', borderRadius: 4 }, { label: '市值', data: st.map((x) => Math.round(x.mv)), backgroundColor: st.map((x) => (x.pl >= 0 ? 'rgba(52,199,89,0.8)' : 'rgba(255,59,48,0.8)')), borderRadius: 4 }] }, options: { maintainAspectRatio: false, scales: { x: { grid: { display: false }, ticks: { color: text } }, y: { beginAtZero: true, grid: { color: line }, ticks: { color: text, callback: (v) => fmtMoney(v, '') } } }, plugins: { legend: { labels: { color: text } }, tooltip: { callbacks: { label: (t) => `${t.dataset.label} ${fmtFull(t.raw)}` } } } } }));
  }
}
function renderStockDetail(main, id) {
  const s = Store.stocks.find((x) => x.id === id);
  if (!s) { main.innerHTML = pageHead('找不到股票', '<a href="#/finance/stock">回股票</a>'); return; }
  const x = stockView(s); const now = new Date();
  const txs = [...(s.transactions || [])].sort((a, b) => b.date - a.date); const divs = [...(s.dividends || [])].sort((a, b) => b.date - a.date);
  const cashDiv = divs.filter((d) => d.kind === '現金股利').reduce((a, d) => a + d.perShare * d.sharesAtEvent, 0) * x.f;
  const held = s.purchaseDate ? Math.max(0.1, (now - s.purchaseDate) / 86400000 / 365) : 0;
  main.innerHTML = `
    <div class="crumb"><a href="#/finance/stock">理財・股票</a> › ${esc(s.symbol)}</div>
    <div class="card hero" style="background:linear-gradient(135deg, rgba(52,199,89,0.16), rgba(48,176,199,0.10))"><div class="avatar" style="background:linear-gradient(135deg,#34c759,#30b0c7)">${esc(initial(s.symbol))}</div>
      <div style="flex:1;min-width:0"><div class="name">${esc(s.symbol)} ${esc(s.name)} ${x.isUS ? '<span class="chip blue big">美股</span>' : ''}${s.isSold ? '<span class="chip big">已賣出</span>' : ''}</div>
        <div class="facts"><span>📆 首購 ${fmtDate(s.purchaseDate).split(' ')[0]}${held ? `（持有 ${held.toFixed(1)} 年）` : ''}</span>${s.soldDate ? `<span>售出 ${fmtDate(s.soldDate).split(' ')[0]}</span>` : ''}<span>🏦 ${esc(bankNameOf(s.linkedSecuritiesMilestoneId) || bankNameOf(s.linkedBankMilestoneId) || '—')}</span>${x.isUS ? `<span>匯率 ${x.f}</span>` : ''}</div>${s.note ? `<div class="muted small" style="margin-top:6px">${esc(s.note)}</div>` : ''}</div>
      <div class="row" style="gap:18px"><div class="score-card"><div class="muted small">市值</div><div class="big score s80" style="font-size:26px">${fmtMoney(x.mv)}</div></div><div class="score-card"><div class="muted small">損益</div><div class="big score ${x.pl >= 0 ? 's90' : 's0'}" style="font-size:26px">${x.pl >= 0 ? '+' : ''}${fmtMoney(x.pl)}</div></div><div class="score-card"><div class="muted small">報酬率</div><div class="big score ${x.pl >= 0 ? 's90' : 's0'}" style="font-size:26px">${x.rate >= 0 ? '+' : ''}${x.rate.toFixed(1)}%</div></div></div>
    </div>
    <div class="grid cols-5 mt">
      ${kpiCard('股數', s.shares.toLocaleString(), '', `${(s.shares / 1000).toFixed(3)} 張`)}
      ${kpiCard('平均成本', s.purchasePrice, '', `總成本 ${fmtMoney(x.cost)}`)}
      ${kpiCard(s.isSold ? '賣出價' : '現價', s.isSold ? s.soldPrice : s.currentPrice, '')}
      ${kpiCard('現金股利累計', fmtMoney(cashDiv), 'green', `${divs.filter((d) => d.kind === '現金股利').length} 次・含息報酬 ${x.cost ? ((x.pl + cashDiv) / x.cost * 100).toFixed(1) : '—'}%`)}
      ${kpiCard('交易次數', txs.length, '', `買 ${txs.filter((t) => t.kind === '買入').length}・賣 ${txs.filter((t) => t.kind === '賣出').length}`)}
    </div>
    <div class="grid cols-2 mt">
      <div class="card table-wrap"><h3>交易紀錄 <span class="count">${txs.length}</span></h3><table class="tbl"><thead><tr><th>日期</th><th>類型</th><th class="num">張數</th><th class="num">股數</th><th class="num">價格</th><th class="num">金額</th></tr></thead><tbody>${txs.map((t) => `<tr><td>${fmtDate(t.date).split(' ')[0]}</td><td><span class="chip ${t.kind === '買入' ? 'green' : 'red'}">${esc(t.kind)}</span></td><td class="num">${t.lots}</td><td class="num">${Math.round(t.lots * 1000).toLocaleString()}</td><td class="num">${t.price}</td><td class="num"><b>${fmtFull(t.lots * 1000 * t.price, x.isUS ? 'US$' : 'NT$')}</b></td></tr>`).join('') || '<tr><td colspan="6" class="empty">尚無交易紀錄</td></tr>'}</tbody></table></div>
      <div class="card table-wrap"><h3>配息／配股 <span class="count">${divs.length}</span></h3><table class="tbl"><thead><tr><th>日期</th><th>類型</th><th class="num">每股</th><th class="num">股數</th><th class="num">金額／股數</th><th>備註</th></tr></thead><tbody>${divs.map((d) => `<tr><td>${fmtDate(d.date).split(' ')[0]}</td><td><span class="chip ${d.kind === '現金股利' ? 'gold' : 'green'}">${esc(d.kind)}</span></td><td class="num">${d.perShare}</td><td class="num">${Math.round(d.sharesAtEvent).toLocaleString()}</td><td class="num"><b>${d.kind === '現金股利' ? fmtFull(d.perShare * d.sharesAtEvent, x.isUS ? 'US$' : 'NT$') : Math.round(d.perShare * d.sharesAtEvent / 10).toLocaleString() + ' 股'}</b></td><td class="muted small">${esc(d.note || '')}</td></tr>`).join('') || '<tr><td colspan="6" class="empty">尚無配息</td></tr>'}</tbody></table></div>
    </div>`;
}

// ---- 人生・財富（財富卡片） -------------------------------------------------
function renderWealth(main) {
  const S = financeSummary(); const now = S.now;
  const subColor = { '銀行': 'blue', '信用卡': 'orange', '證券': 'green', '保險': 'purple' };
  const order = { '銀行': 0, '信用卡': 1, '證券': 2, '保險': 3 };
  const fm = [...S.fm].sort((a, b) => (order[a.financeSubCategory] ?? 9) - (order[b.financeSubCategory] ?? 9));
  const counts = {}; for (const m of fm) counts[m.financeSubCategory] = (counts[m.financeSubCategory] || 0) + 1;
  main.innerHTML = `
    ${pageHead('財富卡片', `${fm.length} 筆帳戶・銀行總餘額 ${fmtMoney(S.bankTotal)}（台幣等值）`)}
    <div class="chips" style="margin-bottom:14px">${Object.entries(counts).map(([k, n]) => `<span class="chip ${subColor[k] || ''} big">${esc(k)} ${n}</span>`).join('')}</div>
    <div class="grid cols-2">${fm.map((m) => {
      let val = '', detail = '', extra = '';
      if (m.financeSubCategory === '銀行') {
        const bal = bankBalances(m); val = fmtMoney(balanceTWD(bal)); detail = Object.entries(bal).map(([c, v]) => `${c} ${Math.round(v).toLocaleString()}`).join('／');
        const deps = [...(m.bankDeposits || [])].sort((a, b) => b.date - a.date).slice(0, 8);
        extra = deps.length ? `<details class="agenda"><summary>最近存提 ${deps.length} 筆</summary><div class="sub-items">${deps.map((d) => `<div class="t-meta" style="padding:3px 0;display:flex;justify-content:space-between"><span>${fmtDate(d.date).split(' ')[0]}${d.isAdjust ? ' <span class="chip indigo">沖正</span>' : ''}${d.note ? '・' + esc(d.note) : ''}</span><b style="color:${d.isWithdrawal ? 'var(--red)' : 'var(--green)'}">${d.isWithdrawal ? '−' : '+'}${fmtAmt(d.amount, d.currencyCode)}</b></div>`).join('')}</div></details>` : '';
      } else if (m.financeSubCategory === '信用卡') {
        const used = S.cardMonth(m); val = fmtMoney(used) + '／本月'; detail = [m.creditLimit ? `額度 ${fmtMoney(m.creditLimit)}・${Math.round(used / m.creditLimit * 100)}%` : '', m.annualFee ? '年費 ' + fmtMoney(m.annualFee) : '', m.billingDay ? '結帳 ' + m.billingDay + ' 日' : '', m.paymentDay ? '繳款 ' + m.paymentDay + ' 日' : '', m.expiryDate ? '到期 ' + fmtDate(m.expiryDate).split(' ')[0] : '', m.linkedBankMilestoneId ? '扣款 ' + bankNameOf(m.linkedBankMilestoneId) : ''].filter(Boolean).join('・');
        const ents = creditCardEntries(m.id, now).sort((a, b) => b.date - a.date).slice(0, 8);
        extra = ents.length ? `<details class="agenda"><summary>最近消費 ${ents.length} 筆</summary><div class="sub-items">${ents.map((e) => `<div class="t-meta" style="padding:3px 0;display:flex;justify-content:space-between"><span>${fmtDate(e.date).split(' ')[0]}・${esc(e.expense.title)}</span><b>${fmtFull(e.amount)}</b></div>`).join('')}</div></details>` : '';
      } else if (m.financeSubCategory === '保險') { val = m.premiumAmount ? fmtMoney(m.premiumAmount) + '／期' : ''; detail = [m.insuranceCompany, m.insuranceType, m.policyNumber, m.beneficiary ? '受益人 ' + m.beneficiary : ''].filter(Boolean).join('・'); }
      else { const linked = Store.stocks.filter((s) => s.linkedSecuritiesMilestoneId === m.id && !s.isSold); val = fmtMoney(linked.reduce((a, s) => a + stockView(s).mv, 0)); detail = [m.securitiesAccountType, `持股 ${linked.length} 檔`].filter(Boolean).join('・'); extra = linked.length ? `<div class="chips" style="margin-top:6px">${linked.map((s) => `<a class="chip green" href="#/finance/stock/${s.id}">${esc(s.symbol)}</a>`).join('')}</div>` : ''; }
      return `<div class="card" style="${m.isDisabled ? 'opacity:.55' : ''}"><div class="row" style="align-items:flex-start"><div class="avatar sm" style="background:${m.financeSubCategory === '銀行' ? 'linear-gradient(135deg,#007aff,#5ac8fa)' : m.financeSubCategory === '信用卡' ? 'linear-gradient(135deg,#ff9500,#ffcc00)' : m.financeSubCategory === '證券' ? 'linear-gradient(135deg,#34c759,#30b0c7)' : 'linear-gradient(135deg,#af52de,#5856d6)'}">${esc(initial(m.bankName || m.insuranceCompany || m.title))}</div><div style="flex:1;min-width:0"><div style="font-weight:900;font-size:15px">${esc(m.title)} <span class="chip ${subColor[m.financeSubCategory] || ''}">${esc(m.financeSubCategory)}</span>${m.isDisabled ? ' <span class="chip">停用</span>' : ''}</div><div class="muted small">${esc([m.bankName, m.branchName, m.bankAccountType, m.cardName, m.cardLastFour ? '末' + m.cardLastFour : ''].filter(Boolean).join('・'))}</div></div><div class="score s80" style="font-size:18px">${val}</div></div><div class="muted small" style="margin-top:8px">${esc(detail)}</div>${extra}${m.note ? `<div class="muted small" style="margin-top:6px">${esc(m.note)}</div>` : ''}</div>`;
    }).join('') || '<div class="empty">尚無財富卡片</div>'}</div>`;
}

// ---- 績效評分加總 -----------------------------------------------------------
// 計分規則與 App 相同：排名在「同課 × 同職等」的組內進行，某組 N 人時第 1 名基礎分 N、
// 往下每名少 1 分，再乘上「評分者職等」的權重後加總。只計已送出的票。
function perfYears() {
  const ys = new Set((Store.ballots || []).map((b) => b.year).filter(Boolean));
  ys.add(new Date().getFullYear());
  return [...ys].sort((a, b) => b - a);
}
function perfScores(year) {
  const totals = {};
  for (const b of Store.ballots || []) {
    if (b.year !== year || !b.submittedAt) continue;
    const w = typeof b.raterWeight === 'number' && b.raterWeight > 0 ? b.raterWeight : 1;
    for (const g of b.groups || []) {
      const entries = g.entries || [];
      if (entries.length < 2) continue;
      entries.forEach((e, i) => {
        const base = entries.length - i;
        const cur = totals[e.id] || { personId: e.id, name: e.name || '未命名', total: 0, sources: [] };
        const sub = subById(e.id);
        if (sub && sub.name) cur.name = sub.name;
        cur.total += base * w;
        cur.sources.push({ raterId: b.raterId, raterName: b.raterName || '未命名', raterGradeLabel: b.raterGradeLabel || '',
          weight: w, rank: i + 1, groupSize: entries.length, groupTitle: g.departmentName || '', base, points: base * w });
        totals[e.id] = cur;
      });
    }
  }
  return Object.values(totals).sort((a, b) => b.total - a.total || a.name.localeCompare(b.name, 'zh-Hant'));
}
const num = (v) => (v === Math.round(v) ? String(v) : v.toFixed(1));
function renderPerf(main, param) {
  const years = perfYears();
  const m = /^(\d{4})$/.exec(param || '');
  const year = m ? +m[1] : years[0];
  const scores = perfScores(year);
  const submitted = (Store.ballots || []).filter((b) => b.year === year && b.submittedAt);
  const raterIds = new Set(submitted.map((b) => b.raterId));
  const pending = Store.subs.filter((s) => !raterIds.has(s.id));
  const shown = perfUI.dept === 'all' ? scores
    : scores.filter((s) => { const sub = subById(s.personId); return sub && sub.departmentId === perfUI.dept; });
  const rankColor = (r) => (r === 1 ? 'gold' : r === 2 ? '' : r === 3 ? 'orange' : '');
  main.innerHTML = `
    ${pageHead('評分加總', `${year} 年度績效互評・${submitted.length} 張已送出`)}
    <div class="filters">
      <span class="muted small">年度</span>
      ${years.map((y) => `<a class="fchip ${y === year ? 'on' : ''}" href="#/perf/${y}">${y}</a>`).join('')}
      <span class="spacer"></span>
      <span class="muted small">課別</span>
      <span class="fchip ${perfUI.dept === 'all' ? 'on' : ''}" data-d="all">全部</span>
      ${Store.depts.map((d) => `<span class="fchip ${perfUI.dept === d.id ? 'on' : ''}" data-d="${d.id}">${esc(d.name || d.code)}</span>`).join('')}
    </div>
    <div class="grid cols-4">
      ${kpiCard('已送出票', submitted.length, 'green', `尚未送出 ${pending.length}`)}
      ${kpiCard('被評分人數', shown.length, '', perfUI.dept === 'all' ? '全部課別' : '此課別')}
      ${kpiCard('最高分', shown.length ? num(shown[0].total) : '—', 'gold', shown.length ? esc(shown[0].name) : '')}
      ${kpiCard('平均分', shown.length ? num(Math.round(shown.reduce((a, s) => a + s.total, 0) / shown.length * 10) / 10) : '—', '')}
    </div>
    ${pending.length ? `<div class="card mt"><h3>⏳ 尚未送出 <span class="count">${pending.length}</span></h3><div class="chips">${pending.map((s) => `<a class="chip orange" href="#/sub/${s.id}">${esc(s.name)}</a>`).join('')}</div></div>` : ''}
    <div class="card mt"><h3>總排名 <span class="count">${shown.length}</span></h3>
      ${shown.map((sc, i) => {
        const sub = subById(sc.personId);
        const dept = sub && sub.departmentId ? (deptById(sub.departmentId) || {}).name : '';
        const grade = sub && sub.gradeTitleId ? (gradeById(sub.gradeTitleId) || {}) : null;
        const avgRank = sc.sources.length ? (sc.sources.reduce((a, x) => a + x.rank, 0) / sc.sources.length).toFixed(1) : '—';
        return `<details class="agenda" style="border-top:1px solid var(--line);padding:8px 0;margin:0">
          <summary style="list-style:none;display:flex;align-items:center;gap:12px;color:inherit;font-weight:400">
            <span class="chip ${rankColor(i + 1)} big" style="min-width:34px;justify-content:center">${i + 1}</span>
            <span style="flex:1;min-width:0"><b>${esc(sc.name)}</b>${sub ? '' : ' <span class="chip">已轉出</span>'}
              <div class="muted small">${esc([dept, grade ? (grade.grade + ' ' + grade.title).trim() : ''].filter(Boolean).join('・'))}・${sc.sources.length} 票・平均第 ${avgRank} 名</div></span>
            <span class="muted small">明細 ▾</span>
            <b style="color:var(--orange);font-size:17px;min-width:48px;text-align:right">${num(sc.total)}</b>
          </summary>
          <div class="sub-items">${sc.sources.slice().sort((a, b) => b.points - a.points).map((src) => `
            <div class="t-meta" style="display:flex;gap:8px;align-items:center;padding:3px 0">
              <span style="width:76px">${esc(src.raterName)}</span>
              <span class="chip blue">第 ${src.rank}/${src.groupSize} 名</span>
              <span class="muted">${src.base} × ${num(src.weight)}</span>
              <span class="spacer" style="flex:1"></span>
              <b style="color:var(--orange)">${num(src.points)}</b>
            </div>`).join('')}</div>
        </details>`;
      }).join('') || `<div class="empty">${scores.length ? '這個課別在這個年度沒有排名資料（同課同職等要滿 2 人才會分組）' : '這個年度還沒有已送出的評分票'}</div>`}
    </div>
    <div class="card mt"><h3>職等權重</h3><div class="chips">${Store.grades.map((g) => `<span class="chip indigo">${esc((g.grade + ' ' + g.title).trim())} ×${num(g.performanceWeight > 0 ? g.performanceWeight : 1)}</span>`).join('') || '<span class="muted small">尚未設定職等</span>'}</div>
      <div class="legend-note">某組 N 人時第 1 名基礎分 N、往下每名少 1 分，再乘上評分者職等的權重後加總。各課人數不同、基礎分上限就不同，跨課比較僅供參考。</div></div>`;
  main.querySelectorAll('.fchip[data-d]').forEach((el) => el.onclick = () => {
    perfUI.dept = el.dataset.d === 'all' ? 'all' : el.dataset.d; renderPerf(main, param);
  });
}
const perfUI = { dept: 'all' };

// ---- 稅務 -------------------------------------------------------------------
// 節稅子分類的年度上限（與 App 的 TaxSavingSubCategory.annualLimit 一致）
const TAX_LIMITS = { '捐贈': null, '保險費': 24000, '醫療': null, '房貸利息': 300000, '房租': 180000,
  '教育學費': 25000, '幼兒學前': 120000, '長期照顧': 120000, '身心障礙': 207000, '其他': null };
const TAX_ICON = { '捐贈': '🎁', '保險費': '🛡️', '醫療': '🏥', '房貸利息': '🏠', '房租': '🏢',
  '教育學費': '🎓', '幼兒學前': '🧒', '長期照顧': '💗', '身心障礙': '♿', '其他': '•' };
/** 固定支出自動推斷的節稅子分類（壽險/意外/綜合/強制險→保險費、房貸→房貸利息、房租→房租） */
function inferredTaxSub(e) {
  if (e.expenseType !== '固定支出') return null;
  if (e.fixedCategory === '保險') return '保險費';
  if (e.fixedCategory === '貸款') return e.loanSubCategory === '房貸' ? '房貸利息' : null;
  if (e.fixedCategory === '房租') return '房租';
  return null;
}
function effectivelyTaxDeductible(e) {
  if (typeof e.taxDeductibleOverride === 'boolean') return e.taxDeductibleOverride;
  if (e.expenseType !== '固定支出') return false;
  if (e.fixedCategory === '保險') return e.insuranceSubCategory !== '儲蓄險';
  if (e.fixedCategory === '貸款') return e.loanSubCategory === '房貸';
  if (e.fixedCategory === '房租') return true;
  return false;
}
/** 某年度這筆固定支出實際發生的金額（含 v25.347 的結束日截斷） */
function taxYearAmount(e, year) {
  const startY = e.date.getFullYear();
  if (startY > year) return 0;
  if (e.endDate && e.endDate.getFullYear() < year) return 0;
  const startM = startY < year ? 1 : e.date.getMonth() + 1;
  const endM = e.endDate && e.endDate.getFullYear() === year ? e.endDate.getMonth() + 1 : 12;
  const months = Math.max(0, endM - startM + 1);
  if (e.recurrence === '每月') return e.amount * months;
  if (e.recurrence === '每季') return e.amount * (months / 3);
  if (e.recurrence === '每年') return months > 0 ? e.amount : 0;
  return 0;
}
function renderTax(main, param) {
  const now = new Date();
  const years = [...new Set(Store.expenses.map((e) => e.date.getFullYear()))].sort((a, b) => b - a);
  if (!years.includes(now.getFullYear())) years.unshift(now.getFullYear());
  const m = /^(\d{4})$/.exec(param || '');
  const year = m ? +m[1] : now.getFullYear();
  const taxExp = Store.expenses.filter((e) => e.variableCategory === '稅費' && e.date.getFullYear() === year).sort((a, b) => b.date - a.date);
  const saveExp = Store.expenses.filter((e) => e.variableCategory === '節稅' && e.date.getFullYear() === year);
  const taxTotal = taxExp.reduce((a, e) => a + e.amount * rateOf(e.currencyCode), 0);
  // 節稅分桶：直接記帳的節稅 + 固定支出推斷
  const bySub = {};
  for (const e of saveExp) { const k = e.taxSavingSubCategory || '其他'; bySub[k] = bySub[k] || { direct: 0, fixed: 0 }; bySub[k].direct += e.amount * rateOf(e.currencyCode); }
  for (const e of Store.expenses) {
    if (!effectivelyTaxDeductible(e)) continue;
    const k = inferredTaxSub(e); if (!k) continue;
    bySub[k] = bySub[k] || { direct: 0, fixed: 0 };
    bySub[k].fixed += taxYearAmount(e, year) * rateOf(e.currencyCode);
  }
  const saveTotal = Object.values(bySub).reduce((a, v) => a + v.direct + v.fixed, 0);
  // 預估年收入（週期收入以起始年 <= 該年為準；單次只算當年）
  const income = Store.incomes.reduce((a, i) => {
    const y = i.date.getFullYear();
    if (i.period === '每月') return y <= year ? a + i.amount * 12 : a;
    if (i.period === '每年') return y <= year ? a + i.amount : a;
    return y === year ? a + i.amount : a;
  }, 0);
  const reCount = Store.realEstates.filter((r) => !r.soldDate).length;
  const vhCount = Store.vehicles.filter((v) => !v.soldDate).length;
  // 檢核項目：[月份, 名稱, 是否適用, 色, 對應稅費紀錄的關鍵字]
  const paidOf = (re) => taxExp.filter((e) => re.test(e.title)).reduce((a, e) => a + e.amount * rateOf(e.currencyCode), 0);
  const checklist = [
    [5, '綜合所得稅申報', true, 'indigo', /綜所|所得稅/],
    [5, '房屋稅繳納', reCount > 0, 'blue', /房屋稅/],
    [7, '汽機車使用牌照稅', vhCount > 0, 'orange', /牌照/],
    [11, '地價稅繳納', reCount > 0, 'purple', /地價/],
    [4, '汽機車燃料費', vhCount > 0, 'teal', /燃料/],
  ].filter((x) => x[2]).map(([mo, title, , color, re]) => {
    const paid = paidOf(re);
    const passed = year < now.getFullYear() || (year === now.getFullYear() && now.getMonth() + 1 > mo);
    return { mo, title, color, paid, state: paid > 0 ? '已繳' : passed ? '未見紀錄' : '尚未到期' };
  }).sort((a, b) => a.mo - b.mo);
  // 稅費月份分佈
  const byMonth = {}; for (const e of taxExp) byMonth[e.date.getMonth() + 1] = (byMonth[e.date.getMonth() + 1] || 0) + e.amount * rateOf(e.currencyCode);
  const maxMonth = Math.max(1, ...Object.values(byMonth));
  const subs = Object.entries(bySub).filter(([, v]) => v.direct + v.fixed > 0)
    .sort((a, b) => (b[1].direct + b[1].fixed) - (a[1].direct + a[1].fixed));
  main.innerHTML = `
    ${pageHead('稅務', `${year} 年度・台幣等值`)}
    <div class="filters"><span class="muted small">年度</span>${years.slice(0, 8).map((y) => `<a class="fchip ${y === year ? 'on' : ''}" href="#/tax/${y}">${y}</a>`).join('')}</div>
    <div class="grid cols-4">
      ${kpiCard('年度稅費支出', fmtMoney(taxTotal), taxTotal ? 'red' : '', `${taxExp.length} 筆`)}
      ${kpiCard('節稅累計', fmtMoney(saveTotal), 'green', `${subs.length} 個項目`)}
      ${kpiCard('預估年收入', fmtMoney(income), '', income ? `稅費占 ${(taxTotal / income * 100).toFixed(1)}%` : '')}
      ${kpiCard('資產稅負', `${reCount} 房 / ${vhCount} 車`, '', '房屋稅・地價稅・牌照稅')}
    </div>
    <div class="grid cols-2 mt">
      <div class="card"><h3>節稅累積 <span class="count">${subs.length}</span></h3>
        ${subs.map(([k, v]) => {
          const total = v.direct + v.fixed; const limit = TAX_LIMITS[k];
          const pct = limit ? Math.min(100, Math.round(total / limit * 100)) : null;
          return `<div style="padding:9px 0;border-top:1px solid var(--line)">
            <div class="row" style="justify-content:space-between">
              <span><b>${TAX_ICON[k] || '•'} ${esc(k)}</b>${v.fixed > 0 ? ` <span class="chip indigo">含固定支出 ${fmtMoney(v.fixed, '')}</span>` : ''}</span>
              <b>${fmtFull(total)}</b>
            </div>
            ${limit ? `<div style="height:6px;border-radius:3px;background:var(--card2);margin-top:6px;overflow:hidden"><div style="width:${pct}%;height:100%;background:${pct >= 100 ? 'var(--red)' : 'var(--green)'}"></div></div>
              <div class="muted small" style="margin-top:3px">上限 ${fmtMoney(limit)}・已用 ${pct}%${pct >= 100 ? '（已達上限）' : `・還可列 ${fmtMoney(limit - total)}`}</div>`
              : '<div class="muted small" style="margin-top:3px">核實認列，無固定上限</div>'}
          </div>`;
        }).join('') || '<div class="empty">這個年度還沒有節稅項目</div>'}
      </div>
      <div class="card"><h3>年度稅務檢核 <span class="count">${checklist.length}</span></h3>
        ${checklist.map((c) => `<div class="row" style="gap:10px;align-items:center;padding:7px 0;border-top:1px solid var(--line)">
          <span class="chip ${c.color}" style="min-width:46px;justify-content:center">${c.mo} 月</span>
          <span style="flex:1;min-width:0"><b>${esc(c.title)}</b>${c.paid > 0 ? `<div class="muted small">已繳 ${fmtMoney(c.paid, '')}</div>` : ''}</span>
          <span class="chip ${c.state === '已繳' ? 'green' : c.state === '未見紀錄' ? 'orange' : ''}">${c.state}</span></div>`).join('') || '<div class="empty">沒有需要檢核的項目</div>'}
        <div class="section-title">稅費月份分佈</div>
        ${Object.keys(byMonth).length ? Object.entries(byMonth).sort((a, b) => a[0] - b[0]).map(([mo, v]) => `
          <div class="row" style="gap:8px;padding:3px 0"><span class="muted small" style="width:36px">${mo} 月</span>
            <span style="flex:1;height:8px;border-radius:4px;background:var(--card2);overflow:hidden"><span style="display:block;width:${Math.round(v / maxMonth * 100)}%;height:100%;background:var(--red);opacity:.7"></span></span>
            <b class="small">${fmtMoney(v, '')}</b></div>`).join('') : '<div class="empty">這個年度沒有稅費紀錄</div>'}
      </div>
    </div>
    <div class="card table-wrap mt"><h3>稅費紀錄 <span class="count">${taxExp.length}</span></h3>
      <table class="tbl"><thead><tr><th>日期</th><th>項目</th><th class="num">金額</th><th>付款</th><th>備註</th></tr></thead><tbody>
      ${taxExp.map((e) => `<tr><td>${fmtDate(e.date).split(' ')[0]}</td><td><b>${esc(e.title)}</b></td><td class="num"><b>${fmtAmt(e.amount, e.currencyCode)}</b></td><td class="muted small">${e.linkedCreditCardMilestoneId ? '💳 ' + esc(bankNameOf(e.linkedCreditCardMilestoneId)) : e.linkedBankMilestoneId ? '🏦 ' + esc(bankNameOf(e.linkedBankMilestoneId)) : ''}</td><td class="muted small">${esc(e.note || '')}</td></tr>`).join('') || '<tr><td colspan="5" class="empty">這個年度沒有稅費紀錄</td></tr>'}
      </tbody></table></div>`;
}

// ---- 人生總覽 ---------------------------------------------------------------
function renderLifeOverview(main, ctx) {
  const now = new Date();
  const S = financeSummary();
  const p = Store.profile || {};
  const yrs = careerYears();
  const openTasks = Store.subs.reduce((a, s) => a + (s.tasks || []).filter((t) => !t.isCompleted).length, 0);
  const overdue = Store.subs.reduce((a, s) => a + (s.tasks || []).filter((t) => !t.isCompleted && t.dueDate && t.dueDate < now).length, 0);
  const famOpen = (Store.familyTasks || []).filter((t) => !t.isCompleted).length;
  // 今天與未來 7 天的行事曆項目
  const from = startOfDay(now); const to = new Date(from); to.setDate(to.getDate() + 8);
  const items = calendarItems(from, to);
  const upcoming = Object.keys(items).sort().flatMap((k) => items[k]).slice(0, 12);
  const bdays = [
    ...Store.subs.map((s) => ({ name: s.name, sub: '部屬', b: birthdayInfo(s.birthday) })),
    ...(Store.familyMembers || []).map((m) => ({ name: m.chineseName || m.englishName, sub: m.role, b: birthdayInfo(m.birthday) })),
  ].filter((x) => x.b && x.b.days <= 30).sort((a, b) => a.b.days - b.b.days);
  // 待辦：家庭待辦＋兼任職務待辦，逾期在前、再依到期日
  const todos = [
    ...(Store.familyTasks || []).filter((t) => !t.isCompleted).map((t) => ({
      title: t.content || '未命名待辦', who: '家庭', dueDate: t.dueDate, tag: '家', color: 'pink', href: '#/life/family/tasks',
    })),
    ...sideRoles().filter(roleActive).flatMap((r) => roleTasks(r).filter((t) => !t.isCompleted).map((t) => ({
      title: t.content || '未命名待辦', who: roleName(r), dueDate: t.dueDate, tag: '兼', color: 'indigo', href: `#/siderole/${r.id}/tasks`,
    }))),
  ].map((t) => Object.assign(t, { overdue: !!t.dueDate && t.dueDate < now }))
    .sort((a, b) => (b.overdue - a.overdue) || ((a.dueDate ? +a.dueDate : 8e15) - (b.dueDate ? +b.dueDate : 8e15)));
  const tile = (icon, title, href, rows) => `<a class="card" href="${href}" style="display:block">
    <h3>${icon} ${title} <span class="spacer" style="flex:1"></span><span class="muted small">開啟 ›</span></h3>
    <div class="nc-rows">${rows.map(([k, v]) => `<div><span class="nc-lbl" style="min-width:76px">${k}</span><b>${v}</b></div>`).join('')}</div></a>`;
  main.innerHTML = `
    ${pageHead('人生總覽', `${fmtDate(now)}・一頁看完所有面向`)}
    <div class="card hero" style="background:linear-gradient(135deg, rgba(52,199,89,0.16), rgba(0,122,255,0.10))">
      <div class="avatar">${esc(initial(p.chineseName || '我'))}</div>
      <div style="flex:1;min-width:0">
        <div class="name">${esc(p.chineseName || '（未填姓名）')}</div>
        <div class="facts">
          ${p.company ? `<span>🏢 ${esc(p.company)}</span>` : ''}${p.jobTitle ? `<span>💼 ${esc(p.jobTitle)}</span>` : ''}
          ${yrs ? `<span>📆 年資 ${yrs.years.toFixed(1)} 年</span>` : ''}
          <span>👥 部屬 ${Store.subs.length} 人</span><span>🧩 兼任 ${sideRoles().filter(roleActive).length} 個</span>
        </div>
      </div>
    </div>
    <div class="grid cols-4 mt">
      ${kpiCard('淨資產概算', fmtMoney(S.netWorth), S.netWorth >= 0 ? 'green' : 'red', `銀行 ${fmtMoney(S.bankTotal)}`)}
      ${kpiCard('本月支出', fmtMoney(cashflowByMonth(1).exp[monthKeyOf(now)] || 0), 'orange', `收入 ${fmtMoney(cashflowByMonth(1).inc[monthKeyOf(now)] || 0)}`)}
      ${kpiCard('部屬未完成任務', openTasks, overdue ? 'red' : '', overdue ? `逾期 ${overdue}` : '沒有逾期')}
      ${kpiCard('家庭待辦', famOpen, famOpen ? 'orange' : 'green', `${(Store.familyMembers || []).length} 位成員`)}
    </div>
    <div class="grid cols-2 mt">
      <div class="card"><h3>📅 未來 7 天 <span class="count">${upcoming.length}</span></h3>
        <div class="list">${upcoming.map((it) => `<a class="item clickable" ${it.href ? `href="${it.href}"` : ''}>
          <span class="chip ${it.overdue ? 'red' : (CAL_KINDS.find((k) => k[0] === it.kind) || CAL_KINDS[0])[2]}">${fmtDate(it.date).split(' ')[0].slice(5)}</span>
          <div class="main-text"><div class="title" style="${it.done ? 'text-decoration:line-through;color:var(--muted)' : ''}">${esc(it.title)}</div><div class="meta">${[it.who, it.sub].filter(Boolean).map(esc).join('・')}</div></div></a>`).join('') || '<div class="empty">未來 7 天沒有排定項目</div>'}</div></div>
      <div class="card"><h3>🎂 30 天內生日 <span class="count">${bdays.length}</span></h3>
        <div class="chips">${bdays.map((x) => `<span class="chip ${x.b.days <= 1 ? 'pink' : ''}">${esc(x.name)}・${esc(x.sub)}・${x.b.days === 0 ? '今天' : x.b.days + ' 天後'}</span>`).join('') || '<span class="muted small">30 天內沒有人生日</span>'}</div>
        <div class="section-title">最近里程碑</div>
        <div class="list">${[...Store.milestones].filter((x) => x.date).sort((a, b) => b.date - a.date).slice(0, 5).map((x) => `<div class="item"><span class="chip ${catChipColor(x.category)}">${catIcon(x.category)}</span><div class="main-text"><div class="title">${esc(x.title || '未命名')}</div><div class="meta">${fmtDate(x.date).split(' ')[0]}・${esc(catLabel(x.category))}</div></div></div>`).join('')}</div>
        <div class="section-title">待辦事項 <span class="count">${todos.length}</span></div>
        <div class="list">${todos.slice(0, 8).map((t) => `<a class="item ${t.href ? 'clickable' : ''}" ${t.href ? `href="${t.href}"` : ''}>
          <span class="chip ${t.overdue ? 'red' : t.color}">${t.tag}</span>
          <div class="main-text"><div class="title">${esc(t.title)}</div><div class="meta">${[t.who, t.dueDate ? '截止 ' + fmtDue(t.dueDate) : '未設截止'].filter(Boolean).map(esc).join('・')}</div></div>
        </a>`).join('') || '<div class="empty">沒有未完成的待辦 🎉</div>'}</div></div>
    </div>
    <div class="grid cols-3 mt">
      ${tile('💼', '職涯', '#/overview', [['部屬', Store.subs.length + ' 人'], ['未交報告', Store.subs.reduce((a, s) => a + (s.weeklyReports || []).filter((r) => !r.isCompleted).length, 0) + ' 份'], ['執掌設備', Store.equipment.length + ' 台']])}
      ${tile('👨‍👩‍👧', '家庭', '#/life/family', [['成員', (Store.familyMembers || []).length + ' 位'], ['寵物', (Store.pets || []).length + ' 隻'], ['人際關係', (Store.relationships || []).length + ' 位']])}
      ${tile('💰', '理財', '#/finance/overview', [['股票市值', fmtMoney(S.stockMV)], ['儲蓄險現值', fmtMoney(S.insTotal)], ['房產・車輛', fmtMoney(S.reValue + S.vhValue)]])}
    </div>`;
}

// ---- 家庭 -----------------------------------------------------------------
const FAMILY_TABS = [['members', '成員'], ['children', '兒女紀錄'], ['tasks', '家庭待辦'], ['pets', '寵物'], ['relations', '人際關係']];
const CHILD_ROLES = new Set(['兒子', '女兒']);
const PET_ICON = { '狗': '🐶', '貓': '🐱', '鳥': '🐦', '魚': '🐟', '倉鼠': '🐹', '兔子': '🐰', '爬蟲': '🦎' };
const CHILD_REC_ICON = { '疫苗': '💉', '過敏': '🤧', '成長記錄': '📏', '就醫記錄': '🏥', '教育里程碑': '🎓', '興趣才藝': '🎨', '紀念時刻': '✨' };
const CHILD_REC_COLOR = { '疫苗': 'blue', '過敏': 'orange', '成長記錄': 'green', '就醫記錄': 'red', '教育里程碑': 'indigo', '興趣才藝': 'purple', '紀念時刻': 'pink' };
function ageOf(bday) {
  if (!(bday instanceof Date)) return null;
  const now = new Date();
  let y = now.getFullYear() - bday.getFullYear();
  const m = now.getMonth() - bday.getMonth();
  if (m < 0 || (m === 0 && now.getDate() < bday.getDate())) y--;
  const months = (y * 12) + (m < 0 ? m + 12 : m);
  return { years: y, months, text: y >= 3 ? `${y} 歲` : `${y} 歲 ${((months % 12) + 12) % 12} 個月` };
}
const memberName = (m) => (m.chineseName || m.englishName || '未命名');
function renderFamily(main, tab) {
  const now = new Date();
  const members = Store.familyMembers || [];
  const children = members.filter((m) => CHILD_ROLES.has(m.role));
  const pets = Store.pets || [];
  const tasks = Store.familyTasks || [];
  const rels = Store.relationships || [];
  const openTasks = tasks.filter((t) => !t.isCompleted);
  const overdueTasks = openTasks.filter((t) => t.dueDate && t.dueDate < now);
  // 近期生日：家庭成員＋寵物＋人際關係
  const bdays = [
    ...members.map((m) => ({ name: memberName(m), sub: m.role, b: birthdayInfo(m.birthday) })),
    ...pets.map((p) => ({ name: p.name, sub: (PET_ICON[p.type] || '🐾') + ' ' + (p.type || '寵物'), b: birthdayInfo(p.birthday) })),
    ...rels.map((r) => ({ name: r.name, sub: r.group, b: birthdayInfo(r.birthday) })),
  ].filter((x) => x.b && x.b.days <= 60).sort((a, b) => a.b.days - b.b.days);
  const spouse = members.find((m) => m.role === '配偶' && !m.isDivorced);
  const marriage = spouse && spouse.marriageDate ? spouse.marriageDate : null;
  const marriageYears = marriage ? ((now - marriage) / 86400000 / 365) : null;

  let body = '';
  if (tab === 'members') {
    const bySide = { '我的': [], '配偶的': [], '其他': [] };
    for (const m of members) bySide[m.familySide === '我的' ? '我的' : m.familySide === '配偶的' ? '配偶的' : '其他'].push(m);
    const card = (m) => {
      const a = ageOf(m.birthday);
      const recs = (m.childRecords || []).length, evts = (m.familyEvents || []).length, daily = (m.dailyRecords || []).length;
      return `<div class="card"><div class="row" style="align-items:flex-start;gap:10px">
        <div class="avatar sm" style="background:linear-gradient(135deg,#ff2d55,#ff9500)">${esc(initial(memberName(m)))}</div>
        <div style="flex:1;min-width:0">
          <div style="font-weight:900;font-size:15px">${esc(memberName(m))}${m.englishName && m.chineseName ? ` <span class="muted" style="font-weight:600">${esc(m.englishName)}</span>` : ''}</div>
          <div class="muted small">${esc(m.role || '')}${m.familySide ? '・' + esc(m.familySide) + '家' : ''}${a ? '・' + a.text : ''}</div>
        </div>
        ${m.isDivorced ? '<span class="chip">已離婚</span>' : ''}
      </div>
      <div class="nc-rows" style="margin-top:8px">
        ${m.birthday ? `<div><span class="nc-lbl">生日</span>${fmtDate(m.birthday).split(' ')[0]}・${zodiac(m.birthday)}</div>` : ''}
        ${m.marriageDate ? `<div><span class="nc-lbl">結婚</span>${fmtDate(m.marriageDate).split(' ')[0]}${!m.isDivorced ? `（${((now - m.marriageDate) / 86400000 / 365).toFixed(1)} 年）` : ''}</div>` : ''}
        ${m.divorceDate ? `<div><span class="nc-lbl">離婚</span>${fmtDate(m.divorceDate).split(' ')[0]}</div>` : ''}
        ${m.relativeNote ? `<div><span class="nc-lbl">備註</span>${esc(m.relativeNote)}</div>` : ''}
      </div>
      ${recs || evts || daily || (m.vaccinations || []).length ? `<div class="chips" style="margin-top:8px">
        ${recs ? `<a class="chip green" href="#/life/family/children">兒女紀錄 ${recs}</a>` : ''}
        ${(m.vaccinations || []).length ? `<span class="chip blue">疫苗 ${(m.vaccinations || []).length}</span>` : ''}
        ${evts ? `<span class="chip orange">家庭事件 ${evts}</span>` : ''}
        ${daily ? `<span class="chip teal">日常紀錄 ${daily}</span>` : ''}
        ${(m.agreements || []).length ? `<span class="chip purple">約定 ${(m.agreements || []).length}</span>` : ''}
      </div>` : ''}
      ${(m.familyEvents || []).length ? `<details class="agenda"><summary>家庭事件 ${(m.familyEvents || []).length}</summary><div class="sub-items">${[...m.familyEvents].sort((a, b) => b.date - a.date).slice(0, 10).map((e) => `<div class="t-meta" style="padding:3px 0"><b>${fmtDate(e.date).split(' ')[0]}</b>　${esc(e.title || '')}${e.content ? '・' + esc(e.content) : ''}</div>`).join('')}</div></details>` : ''}
      </div>`;
    };
    body = ['我的', '配偶的', '其他'].filter((k) => bySide[k].length).map((k) => `<div class="section-title">${k === '其他' ? '未分家族' : k + '家'}（${bySide[k].length}）</div><div class="grid cols-3">${bySide[k].map(card).join('')}</div>`).join('')
      || '<div class="empty">尚無家庭成員</div>';
  } else if (tab === 'children') {
    body = children.map((c) => {
      const recs = [...(c.childRecords || [])].sort((a, b) => b.date - a.date);
      const a = ageOf(c.birthday);
      const growth = recs.filter((r) => r.type === '成長記錄' && (r.heightCm || r.weightKg)).sort((a2, b2) => a2.date - b2.date);
      const latest = growth[growth.length - 1];
      const byType = {}; for (const r of recs) byType[r.type] = (byType[r.type] || 0) + 1;
      return `<div class="card mt"><h3>👶 ${esc(memberName(c))} <span class="count">${recs.length} 筆紀錄</span>
          <span class="spacer"></span><span class="muted small">${c.birthday ? fmtDate(c.birthday).split(' ')[0] + '・' + (a ? a.text : '') : ''}</span></h3>
        <div class="chips">${Object.entries(byType).sort((x, y) => y[1] - x[1]).map(([t, n]) => `<span class="chip ${CHILD_REC_COLOR[t] || ''}">${CHILD_REC_ICON[t] || ''} ${esc(t)} ${n}</span>`).join('') || '<span class="muted small">尚無紀錄</span>'}
          ${latest ? `<span class="chip">最新身高體重 ${latest.heightCm ? latest.heightCm + ' cm' : ''}${latest.heightCm && latest.weightKg ? '・' : ''}${latest.weightKg ? latest.weightKg + ' kg' : ''}</span>` : ''}</div>
        ${growth.length >= 2 ? `<div class="chart-box mt" style="height:200px"><canvas data-growth="${c.id}"></canvas></div>` : ''}
        ${recs.slice(0, 20).map((r) => `<div class="task-row"><div class="tick">${CHILD_REC_ICON[r.type] || '•'}</div>
          <div><div class="t-title">${esc(r.title || r.type)}</div>
            <div class="t-meta">${fmtDate(r.date).split(' ')[0]}${r.detail ? '・' + esc(r.detail) : ''}${r.dose ? '・劑次 ' + esc(r.dose) : ''}${r.heightCm ? '・身高 ' + r.heightCm + ' cm' : ''}${r.weightKg ? '・體重 ' + r.weightKg + ' kg' : ''}${r.temperatureC ? '・體溫 ' + r.temperatureC + '°C' : ''}</div>
            ${r.note ? `<div class="t-meta">${esc(r.note)}</div>` : ''}</div>
          <div class="t-right"><span class="chip ${CHILD_REC_COLOR[r.type] || ''}">${esc(r.type)}</span>${r.severity ? `<span class="chip red">${esc(r.severity)}</span>` : ''}</div></div>`).join('')}
        ${recs.length > 20 ? `<div class="muted small" style="margin-top:6px">僅顯示最新 20 筆，共 ${recs.length} 筆</div>` : ''}
      </div>`;
    }).join('') || '<div class="empty">尚無兒女成員（角色為「兒子」或「女兒」的家庭成員會出現在這裡）</div>';
    main.__growth = children.map((c) => ({ id: c.id, pts: [...(c.childRecords || [])].filter((r) => r.type === '成長記錄' && (r.heightCm || r.weightKg)).sort((a, b) => a.date - b.date) }));
  } else if (tab === 'tasks') {
    const nameOfAssignee = (id) => { const m = members.find((x) => x.id === id); return m ? memberName(m) : (subById(id)?.name || ''); };
    const row = (t) => {
      const who = (t.assigneeIds || []).map(nameOfAssignee).filter(Boolean);
      const od = !t.isCompleted && t.dueDate && t.dueDate < now;
      return `<div class="task-row"><div class="tick">${t.isCompleted ? '✅' : '⬜️'}</div>
        <div><div class="t-title ${t.isCompleted ? 'done' : ''}">${esc(t.content || '（空白待辦）')}</div>
          <div class="t-meta">${who.length ? '負責：' + esc(who.join('、')) : '未指派'}${t.dueDate ? '・截止 ' + fmtDue(t.dueDate) : ''}${t.completedAt ? '・完成 ' + fmtDateTime(t.completedAt) : ''}</div>
          ${t.note ? `<div class="t-meta">${esc(t.note)}</div>` : ''}</div>
        <div class="t-right">${od ? `<span class="chip red">逾期 ${daysBetween(t.dueDate, now)} 天</span>` : ''}</div></div>`;
    };
    const done = tasks.filter((t) => t.isCompleted).sort((a, b) => (b.completedAt || b.createdAt || 0) - (a.completedAt || a.createdAt || 0));
    body = `<div class="grid cols-2">
      <div class="card"><h3>進行中 <span class="count">${openTasks.length}</span></h3>${openTasks.sort((a, b) => (a.dueDate ? +a.dueDate : 8e15) - (b.dueDate ? +b.dueDate : 8e15)).map(row).join('') || '<div class="empty">沒有進行中的家庭待辦</div>'}</div>
      <div class="card"><h3>已完成 <span class="count">${done.length}</span></h3>${done.slice(0, 30).map(row).join('') || '<div class="empty">尚無完成紀錄</div>'}</div></div>`;
  } else if (tab === 'pets') {
    body = `<div class="grid cols-3">${pets.map((p) => {
      const a = ageOf(p.birthday);
      const hr = [...(p.healthRecords || [])].sort((x, y) => (y.date || 0) - (x.date || 0));
      return `<div class="card"><div class="row" style="align-items:flex-start;gap:10px">
        <div class="avatar sm" style="background:linear-gradient(135deg,#af52de,#ff2d55)">${PET_ICON[p.type] || '🐾'}</div>
        <div style="flex:1;min-width:0"><div style="font-weight:900;font-size:15px">${esc(p.name || '未命名')}</div>
          <div class="muted small">${esc([p.type, p.breed].filter(Boolean).join('・'))}${a ? '・' + a.text : ''}</div></div></div>
        <div class="nc-rows" style="margin-top:8px">
          ${p.birthday ? `<div><span class="nc-lbl">生日</span>${fmtDate(p.birthday).split(' ')[0]}</div>` : ''}
          ${p.weight ? `<div><span class="nc-lbl">體重</span>${p.weight} kg</div>` : ''}
          ${p.note ? `<div><span class="nc-lbl">備註</span>${esc(p.note)}</div>` : ''}
        </div>
        ${hr.length ? `<details class="agenda"><summary>健康紀錄 ${hr.length}</summary><div class="sub-items">${hr.slice(0, 10).map((r) => `<div class="t-meta" style="padding:3px 0"><b>${r.date ? fmtDate(r.date).split(' ')[0] : ''}</b>　${esc(r.title || r.type || '')}${r.note ? '・' + esc(r.note) : ''}</div>`).join('')}</div></details>` : ''}
      </div>`;
    }).join('') || '<div class="empty">尚無寵物</div>'}</div>`;
  } else if (tab === 'relations') {
    const groups = ['家人', '朋友', '同事', '客戶', '其他'];
    const GC = { '家人': 'red', '朋友': 'green', '同事': 'blue', '客戶': 'orange', '其他': '' };
    body = groups.filter((g) => rels.some((r) => r.group === g)).map((g) => {
      const list = rels.filter((r) => r.group === g).sort((a, b) => (a.name || '').localeCompare(b.name || '', 'zh-Hant'));
      return `<div class="section-title">${g}（${list.length}）</div><div class="grid cols-3">${list.map((r) => {
        const b = birthdayInfo(r.birthday);
        const ints = [...(r.interactions || [])].sort((x, y) => (y.date || 0) - (x.date || 0));
        return `<div class="card"><div class="row" style="align-items:flex-start;gap:10px">
          <div class="avatar sm" style="background:linear-gradient(135deg,#8e8e93,#636366)">${esc(initial(r.name))}</div>
          <div style="flex:1;min-width:0"><div style="font-weight:900;font-size:15px">${esc(r.name || '未命名')}</div>
            <div class="muted small">${esc(g)}${r.phone ? '・' + esc(r.phone) : ''}</div></div>
          <span class="chip ${GC[g] || ''}">${ints.length} 次互動</span></div>
          <div class="nc-rows" style="margin-top:8px">
            ${r.birthday ? `<div><span class="nc-lbl">生日</span>${fmtDate(r.birthday).split(' ')[0]}${b && b.days <= 60 ? `（${b.days === 0 ? '今天' : b.days + ' 天後'}）` : ''}</div>` : ''}
            ${r.anniversary ? `<div><span class="nc-lbl">紀念日</span>${fmtDate(r.anniversary).split(' ')[0]}</div>` : ''}
            ${r.note ? `<div><span class="nc-lbl">備註</span>${esc(r.note)}</div>` : ''}
          </div>
          ${ints.length ? `<details class="agenda"><summary>互動紀錄 ${ints.length}</summary><div class="sub-items">${ints.slice(0, 8).map((i) => `<div class="t-meta" style="padding:3px 0"><b>${i.date ? fmtDate(i.date).split(' ')[0] : ''}</b>　${esc(i.note || '')}</div>`).join('')}</div></details>` : ''}
        </div>`;
      }).join('')}</div>`;
    }).join('') || '<div class="empty">尚無人際關係紀錄</div>';
  }

  main.innerHTML = `
    ${pageHead('家庭', `${members.length} 位成員・${pets.length} 隻寵物・${rels.length} 位人際關係`)}
    <div class="grid cols-5">
      ${kpiCard('家庭成員', members.length, '', children.length ? `兒女 ${children.length} 位` : '')}
      ${kpiCard('家庭待辦', openTasks.length, overdueTasks.length ? 'red' : openTasks.length ? 'orange' : 'green', overdueTasks.length ? `逾期 ${overdueTasks.length}` : `已完成 ${tasks.length - openTasks.length}`)}
      ${kpiCard('結婚', marriageYears != null ? marriageYears.toFixed(1) + ' 年' : '—', 'pink', marriage ? fmtDate(marriage).split(' ')[0] : '')}
      ${kpiCard('60 天內生日', bdays.length, bdays.some((x) => x.b.days <= 1) ? 'pink' : '', bdays[0] ? `最近：${esc(bdays[0].name)}（${bdays[0].b.days === 0 ? '今天' : bdays[0].b.days + ' 天後'}）` : '無')}
      ${kpiCard('寵物', pets.length, '', pets.map((p) => PET_ICON[p.type] || '🐾').join(' '))}
    </div>
    ${bdays.length ? `<div class="card mt"><h3>🎂 近期生日 <span class="count">${bdays.length}</span></h3><div class="chips">${bdays.map((x) => `<span class="chip ${x.b.days <= 1 ? 'pink' : ''}">${esc(x.name)}・${esc(x.sub || '')}・${fmtDate(x.b.next).split(' ')[0]}（${x.b.days === 0 ? '今天' : x.b.days + ' 天後'}）</span>`).join('')}</div></div>` : ''}
    ${tabsHTML('life/family', FAMILY_TABS, tab)}
    ${body}`;
  if (tab !== 'children' || !window.Chart) return;
  const { text, line } = chartColors();
  for (const g of (main.__growth || [])) {
    const cv = main.querySelector(`canvas[data-growth="${g.id}"]`); if (!cv || g.pts.length < 2) continue;
    charts.push(new Chart(cv, { data: { labels: g.pts.map((r) => fmtDate(r.date).split(' ')[0]), datasets: [
      { type: 'line', label: '身高 (cm)', data: g.pts.map((r) => r.heightCm ?? null), borderColor: '#34c759', backgroundColor: 'rgba(52,199,89,0.12)', fill: true, tension: 0.3, yAxisID: 'y', spanGaps: true, pointRadius: 4 },
      { type: 'line', label: '體重 (kg)', data: g.pts.map((r) => r.weightKg ?? null), borderColor: '#ff9500', backgroundColor: 'rgba(255,149,0,0.10)', fill: false, tension: 0.3, yAxisID: 'y1', spanGaps: true, pointRadius: 4 },
    ] }, options: { maintainAspectRatio: false, interaction: { mode: 'index', intersect: false },
      scales: { x: { grid: { display: false }, ticks: { color: text } },
        y: { position: 'left', grid: { color: line }, ticks: { color: text }, title: { display: true, text: 'cm', color: text } },
        y1: { position: 'right', grid: { display: false }, ticks: { color: text }, title: { display: true, text: 'kg', color: text } } },
      plugins: { legend: { labels: { color: text } } } } }));
  }
}

// ---- 履歷 -----------------------------------------------------------------
const CAT_META = {
  '職涯': ['briefcase', '💼', 'blue'], '學歷': ['edu', '🎓', 'indigo'], '成就': ['wealth', '💰', 'green'],
  '結婚': ['marriage', '💍', 'pink'], '家庭': ['family', '❤️', 'red'], '房地產': ['re', '🏠', 'orange'],
  '旅行': ['travel', '✈️', 'teal'], '寵物': ['pet', '🐾', 'purple'], '健康': ['health', '➕', 'cyan'], '其他': ['other', '⭐', ''],
};
/** 「成就」在 App 裡顯示為「財富」（財富卡片就是這個分類） */
const catLabel = (c) => (c === '成就' ? '財富' : c === '結婚' ? '配偶' : c);
const catIcon = (c) => (CAT_META[c] || CAT_META['其他'])[1];
const catChipColor = (c) => (CAT_META[c] || CAT_META['其他'])[2];
/** 職涯里程碑（不含兼任職務——那有自己的頁面） */
function careerMilestones() {
  return Store.milestones.filter((m) => m.category === '職涯' && m.careerSubCategory !== 'sideRole')
    .sort((a, b) => b.date - a.date);
}
function salaryOf(m) { return m.salaryAfter ?? m.salary ?? null; }
function careerYears() {
  const list = careerMilestones();
  const join = list.filter((m) => m.careerSubCategory === '入職').sort((a, b) => a.date - b.date)[0]
    || [...list].sort((a, b) => a.date - b.date)[0];
  if (!join) return null;
  const quit = list.filter((m) => m.careerSubCategory === '離職').sort((a, b) => b.date - a.date)[0];
  const end = quit && quit.date > join.date ? quit.date : new Date();
  return { from: join.date, years: (end - join.date) / 86400000 / 365, ended: !!quit };
}
const CAREER_COLOR = { '入職': 'green', '升職': 'gold', '調薪': 'blue', '轉職': 'indigo', '降職': 'orange', '離職': 'red' };
function renderResume(main, cat) {
  const now = new Date();
  const p = Store.profile || {};
  const all = [...Store.milestones].sort((a, b) => b.date - a.date);
  const cats = [...new Set(all.map((m) => m.category).filter(Boolean))];
  const CAT_ORDER = ['職涯', '學歷', '成就', '結婚', '家庭', '房地產', '旅行', '寵物', '健康', '其他'];
  cats.sort((a, b) => CAT_ORDER.indexOf(a) - CAT_ORDER.indexOf(b));
  const counts = {}; for (const m of all) counts[m.category] = (counts[m.category] || 0) + 1;
  const shown = cat === 'all' ? all : all.filter((m) => m.category === cat);
  const thisYear = all.filter((m) => m.date && m.date.getFullYear() === now.getFullYear()).length;
  const careers = careerMilestones();
  const yrs = careerYears();
  const latestJob = careers.find((m) => m.careerSubCategory !== '離職');
  // 薪資點：有薪資數字的職涯里程碑，由舊到新
  const salaryPts = careers.filter((m) => salaryOf(m)).sort((a, b) => a.date - b.date)
    .map((m) => ({ date: m.date, value: salaryOf(m), label: m.careerSubCategory || '職涯' }));
  // 依年份分組
  const byYear = {}; for (const m of shown) { const y = m.date ? m.date.getFullYear() : '—'; (byYear[y] = byYear[y] || []).push(m); }
  const years = Object.keys(byYear).sort((a, b) => b - a);
  const milestoneRow = (m) => {
    const href = m.financeSubCategory ? '#/life/wealth'
      : (m.category === '職涯' && m.careerSubCategory === 'sideRole') ? `#/siderole/${m.id}` : '';
    const bits = [];
    if (m.companyName) bits.push(m.companyName);
    if (m.department) bits.push(m.department);
    if (m.jobTitle) bits.push(m.jobTitle);
    if (m.jobGrade) bits.push(m.jobGrade);
    if (m.financeSubCategory) bits.push(m.financeSubCategory);
    const sal = (m.salaryBefore != null && m.salaryAfter != null)
      ? `${fmtMoney(m.salaryBefore)} → ${fmtMoney(m.salaryAfter)}${m.salaryBefore > 0 ? `（${m.salaryAfter >= m.salaryBefore ? '+' : ''}${Math.round((m.salaryAfter / m.salaryBefore - 1) * 100)}%）` : ''}`
      : (salaryOf(m) ? fmtMoney(salaryOf(m)) : '');
    return `<div class="task-row"><div class="tick">${catIcon(m.category)}</div>
      <div><div class="t-title">${href ? `<a href="${href}" style="color:var(--blue)">${esc(m.title || '未命名')} ›</a>` : esc(m.title || '未命名')}</div>
        <div class="t-meta">${m.date ? fmtDate(m.date).split(' ')[0] : ''}${bits.length ? '・' + esc(bits.join('・')) : ''}${sal ? '・薪資 ' + sal : ''}</div>
        ${m.note ? `<div class="t-meta" style="white-space:pre-wrap">${esc(m.note)}</div>` : ''}
        ${m.mood ? `<div class="t-meta">心情：${esc(m.mood)}</div>` : ''}
        ${m.futurePlan ? `<div class="t-meta">未來規劃：${esc(m.futurePlan)}</div>` : ''}</div>
      <div class="t-right">
        <span class="chip ${catChipColor(m.category)}">${esc(catLabel(m.category))}</span>
        ${m.careerSubCategory && m.careerSubCategory !== 'sideRole' ? `<span class="chip ${CAREER_COLOR[m.careerSubCategory] || ''}">${esc(m.careerSubCategory)}</span>` : ''}
        ${m.isManagerial ? `<span class="chip gold">管理職${m.managedUnit ? '・' + esc(m.managedUnit) : ''}</span>` : ''}
      </div></div>`;
  };
  main.innerHTML = `
    ${pageHead('履歷', `${all.length} 項里程碑・今年 ${thisYear} 項・${cats.length} 個分類`)}
    <div class="card hero" style="background:linear-gradient(135deg, rgba(255,149,0,0.16), rgba(255,204,0,0.10))">
      <div class="avatar" style="background:linear-gradient(135deg,#ff9500,#ffcc00)">${esc(initial(p.chineseName || p.englishName || '我'))}</div>
      <div style="flex:1;min-width:0">
        <div class="name">${esc(p.chineseName || '（未填姓名）')}${p.englishName ? ` <span class="muted" style="font-size:15px">${esc(p.englishName)}</span>` : ''}</div>
        <div class="facts">
          ${p.company || latestJob?.companyName ? `<span>🏢 ${esc(p.company || latestJob.companyName)}</span>` : ''}
          ${p.jobTitle || latestJob?.jobTitle ? `<span>💼 ${esc(p.jobTitle || latestJob.jobTitle)}</span>` : ''}
          ${p.spouse ? `<span>💍 ${esc(p.spouse)}</span>` : ''}
          ${yrs ? `<span>📆 年資 ${yrs.years.toFixed(1)} 年（自 ${fmtDate(yrs.from).split(' ')[0]}${yrs.ended ? '，已離職' : ''}）</span>` : ''}
        </div>
      </div>
    </div>
    <div class="grid cols-4 mt">
      ${kpiCard('里程碑', all.length, '', `今年 ${thisYear} 項`)}
      ${kpiCard('職涯異動', careers.length, '', `升職 ${careers.filter((m) => m.careerSubCategory === '升職').length}・調薪 ${careers.filter((m) => m.careerSubCategory === '調薪').length}`)}
      ${kpiCard('目前薪資', salaryPts.length ? fmtMoney(salaryPts[salaryPts.length - 1].value) : '—', 'green', salaryPts.length > 1 ? `自 ${fmtMoney(salaryPts[0].value)} 起（${salaryPts[0].value > 0 ? '+' + Math.round((salaryPts[salaryPts.length - 1].value / salaryPts[0].value - 1) * 100) + '%' : ''}）` : '')}
      ${kpiCard('兼任職務', sideRoles().length, '', `在任 ${sideRoles().filter(roleActive).length}`)}
    </div>
    ${salaryPts.length >= 2 ? `<div class="card chart-card mt"><h3>薪資歷程</h3><div class="chart-box" style="height:220px"><canvas id="rs-salary"></canvas></div><div class="legend-note">取職涯里程碑上填寫的薪資（調薪後金額優先）。</div></div>` : ''}
    ${careers.length ? `<div class="card mt"><h3>職涯時間軸 <span class="count">${careers.length}</span></h3>${careers.map(milestoneRow).join('')}</div>` : ''}
    <div class="filters mt">
      <span class="fchip ${cat === 'all' ? 'on' : ''}" data-cat="all">全部 ${all.length}</span>
      ${cats.map((c) => `<span class="fchip ${cat === c ? 'on' : ''}" data-cat="${esc(c)}">${catIcon(c)} ${esc(catLabel(c))} ${counts[c]}</span>`).join('')}
    </div>
    ${years.map((y) => `<div class="card mt"><h3>${y} <span class="count">${byYear[y].length}</span></h3>${byYear[y].map(milestoneRow).join('')}</div>`).join('') || '<div class="empty">沒有符合的里程碑</div>'}`;
  main.querySelectorAll('.fchip[data-cat]').forEach((el) => el.onclick = () => { location.hash = `#/life/resume/${encodeURIComponent(el.dataset.cat)}`; });
  if (!window.Chart || salaryPts.length < 2) return;
  const { text, line } = chartColors();
  charts.push(new Chart($('#rs-salary'), {
    type: 'line',
    data: { labels: salaryPts.map((x) => fmtDate(x.date).split(' ')[0]), datasets: [{ label: '薪資', data: salaryPts.map((x) => Math.round(x.value)), borderColor: '#34c759', backgroundColor: 'rgba(52,199,89,0.15)', fill: true, tension: 0.25, pointRadius: 5, stepped: false }] },
    options: { maintainAspectRatio: false, scales: { x: { grid: { display: false }, ticks: { color: text } }, y: { grid: { color: line }, ticks: { color: text, callback: (v) => fmtMoney(v, '') } } }, plugins: { legend: { display: false }, tooltip: { callbacks: { label: (t) => `${salaryPts[t.dataIndex].label} ${fmtFull(t.raw)}` } } } },
  }));
}

// ---- 部門職等 ---------------------------------------------------------------
function renderGrades(main) {
  const grades = [...Store.grades];
  const usage = (gid) => {
    const subs = Store.subs.filter((s) => s.gradeTitleId === gid);
    const people = Store.orgPeople.filter((p) => p.gradeTitleId === gid && !(p.linkedSubordinateId && subById(p.linkedSubordinateId)));
    return { subs, people, total: subs.length + people.length };
  };
  const used = grades.map((g) => ({ g, u: usage(g.id) })).sort((a, b) => b.u.total - a.u.total || (a.g.grade || '').localeCompare(b.g.grade || '', 'zh-Hant'));
  const noGradeSubs = Store.subs.filter((s) => !s.gradeTitleId || !gradeById(s.gradeTitleId));
  const depts = [...Store.depts].sort((a, b) => (a.code || '').localeCompare(b.code || '') || (a.name || '').localeCompare(b.name || '', 'zh-Hant'));
  const rel = (ids) => (ids || []).map(deptById).filter(Boolean).map((d) => `<a class="chip blue" href="#/dept/${d.id}">${esc(d.name)}</a>`).join(' ') || '<span class="muted">—</span>';
  main.innerHTML = `
    ${pageHead('部門職等', `${depts.length} 個部門・${grades.length} 個職等職稱`)}
    <div class="grid cols-4">
      ${kpiCard('部門', depts.length, '', `${Store.equipment.length} 台設備`)}
      ${kpiCard('職等職稱', grades.length, '', `已指派 ${used.filter((x) => x.u.total).length} 個`)}
      ${kpiCard('已套用職等的部屬', Store.subs.length - noGradeSubs.length, noGradeSubs.length ? 'orange' : 'green', noGradeSubs.length ? `未設定 ${noGradeSubs.length} 人` : '全部已設定')}
      ${kpiCard('組織人員', Store.orgPeople.length, '', `其中部屬 ${Store.orgPeople.filter((p) => p.linkedSubordinateId && subById(p.linkedSubordinateId)).length} 人`)}
    </div>
    <div class="card table-wrap mt"><h3>職等職稱 <span class="count">${grades.length}</span></h3>
      <table class="tbl"><thead><tr><th>職等</th><th>職稱</th><th class="num">使用人數</th><th>使用者</th></tr></thead><tbody>
      ${used.map(({ g, u }) => `<tr><td><b>${esc(g.grade || '—')}</b></td><td>${esc(g.title || '—')}</td><td class="num">${u.total ? `<span class="chip green">${u.total}</span>` : '<span class="muted">0</span>'}</td>
        <td>${[...u.subs.map((s) => `<a class="chip" href="#/sub/${s.id}">${esc(s.name)}</a>`), ...u.people.map((p) => `<span class="chip">${esc(p.name)}</span>`)].join(' ') || '<span class="muted">尚未指派</span>'}</td></tr>`).join('') || '<tr><td colspan="4" class="empty">尚無職等職稱</td></tr>'}
      </tbody></table>
      ${noGradeSubs.length ? `<div class="muted small" style="margin-top:10px">未設定職等的部屬：${noGradeSubs.map((s) => `<a class="chip orange" href="#/sub/${s.id}">${esc(s.name)}</a>`).join(' ')}</div>` : ''}
    </div>
    <div class="card table-wrap mt"><h3>部門 <span class="count">${depts.length}</span></h3>
      <table class="tbl"><thead><tr><th>代號</th><th>部門</th><th>功能</th><th class="num">成員</th><th class="num">設備</th><th>主管</th><th>上游</th><th>下游</th><th>平行</th></tr></thead><tbody>
      ${depts.map((d) => { const mem = deptMembers(d.id); const eq = Store.equipment.filter((e) => e.departmentId === d.id);
        return `<tr class="clickable" onclick="location.hash='#/dept/${d.id}'"><td><b>${esc(d.code || '—')}</b></td><td>${esc(d.name || '未命名')}</td><td class="muted small" style="white-space:normal;max-width:260px">${esc(d.function || '')}</td>
        <td class="num">${mem.filter((m) => !m.isInactive).length}</td><td class="num">${eq.length}</td>
        <td>${(d.managerIds || []).map(personName).filter(Boolean).map((n) => `<span class="chip gold">${esc(n)}</span>`).join(' ') || '<span class="muted">—</span>'}</td>
        <td>${rel(d.upstreamIds)}</td><td>${rel(d.downstreamIds)}</td><td>${rel(d.peerIds)}</td></tr>`; }).join('') || '<tr><td colspan="9" class="empty">尚無部門</td></tr>'}
      </tbody></table></div>`;
}

// ---- 名片 -----------------------------------------------------------------
const cardUI = { q: '', company: 'all', sort: 'date' };
/** 舊資料可能只有單數 phone／email 欄位，新資料是陣列，兩種都收 */
function cardPhones(c) { const a = Array.isArray(c.phones) ? c.phones : []; return a.length ? a : (c.phone ? [c.phone] : []); }
function cardEmails(c) { const a = Array.isArray(c.emails) ? c.emails : []; return a.length ? a : (c.email ? [c.email] : []); }
function cardFaxes(c) { return Array.isArray(c.faxes) ? c.faxes : []; }
/** 名片連到的組織人員；若該人員又連到部屬，一併回傳供跳轉 */
function cardLinks(c) {
  const p = c.linkedOrgPersonId
    ? Store.orgPeople.find((x) => x.id === c.linkedOrgPersonId)
    : Store.orgPeople.find((x) => x.linkedBusinessCardId === c.id);
  const sub = p && p.linkedSubordinateId ? subById(p.linkedSubordinateId) : null;
  const dept = p && p.departmentId ? deptById(p.departmentId) : null;
  return { person: p || null, sub, dept };
}
const telHref = (v) => 'tel:' + String(v).replace(/[^\d+#*,]/g, '');
function renderCards(main, param) {
  if (param) return renderCardDetail(main, param);
  const all = Store.cards;
  const companies = [...new Set(all.map((c) => (c.company || '').trim()).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'zh-Hant'));
  const q = cardUI.q.trim().toLowerCase();
  const list = all.filter((c) => {
    if (cardUI.company !== 'all' && (c.company || '').trim() !== cardUI.company) return false;
    if (!q) return true;
    return [c.name, c.company, c.department, c.jobTitle, c.address, c.note, c.primaryBusiness, ...cardPhones(c), ...cardEmails(c)]
      .filter(Boolean).join(' ').toLowerCase().includes(q);
  }).sort((a, b) => (cardUI.sort === 'name'
    ? (a.name || '').localeCompare(b.name || '', 'zh-Hant')
    : cardUI.sort === 'company'
      ? ((a.company || '').localeCompare(b.company || '', 'zh-Hant') || (a.name || '').localeCompare(b.name || '', 'zh-Hant'))
      : (b.date || 0) - (a.date || 0)));
  const linkedCount = all.filter((c) => cardLinks(c).person).length;
  const newest = all.length ? [...all].sort((a, b) => (b.date || 0) - (a.date || 0))[0] : null;
  main.innerHTML = `
    ${pageHead('名片', `${all.length} 張・${companies.length} 家公司`)}
    <div class="grid cols-4">
      ${kpiCard('名片總數', all.length, '', `${companies.length} 家公司`)}
      ${kpiCard('已連結組織人員', linkedCount, linkedCount ? 'green' : '', `未連結 ${all.length - linkedCount}`)}
      ${kpiCard('有電話', all.filter((c) => cardPhones(c).length).length, '', `有 Email ${all.filter((c) => cardEmails(c).length).length}`)}
      ${kpiCard('最近新增', newest ? esc(newest.name || '未命名') : '—', '', newest && newest.date ? fmtDate(newest.date).split(' ')[0] : '')}
    </div>
    <div class="filters mt">
      <input type="search" id="nc-q" placeholder="搜尋姓名／公司／職稱／電話／Email" value="${esc(cardUI.q)}">
      <span class="muted small">排序</span>
      ${[['date', '新增日期'], ['name', '姓名'], ['company', '公司']].map(([k, l]) => `<span class="fchip ${cardUI.sort === k ? 'on' : ''}" data-sort="${k}">${l}</span>`).join('')}
    </div>
    <div class="filters">
      <span class="fchip ${cardUI.company === 'all' ? 'on' : ''}" data-co="all">全部公司</span>
      ${companies.map((co) => `<span class="fchip ${cardUI.company === co ? 'on' : ''}" data-co="${esc(co)}">${esc(co)}</span>`).join('')}
      <span class="spacer"></span><span class="muted small">${list.length}/${all.length} 張</span>
    </div>
    <div class="card-grid">${list.map((c) => {
      const L = cardLinks(c);
      const phones = cardPhones(c), emails = cardEmails(c);
      return `<div class="card namecard clickable" onclick="location.hash='#/cards/${c.id}'" style="cursor:pointer">
        <div class="nc-head">
          <div class="avatar sm" style="background:linear-gradient(135deg,#5856d6,#32ade6)">${esc(initial(c.name || c.company))}</div>
          <div style="flex:1;min-width:0">
            <div class="nc-name">${esc(c.name || '未命名')}</div>
            <div class="nc-title">${esc([c.jobTitle, c.department].filter(Boolean).join('・') || '—')}</div>
          </div>
          ${L.sub ? '<span class="chip green">部屬</span>' : L.person ? '<span class="chip blue">組織</span>' : ''}
        </div>
        <div class="nc-co">🏢 ${esc(c.company || '（未填公司）')}</div>
        ${c.primaryBusiness ? `<div class="muted small">主要業務：${esc(c.primaryBusiness)}</div>` : ''}
        <div class="nc-rows">
          ${phones.slice(0, 2).map((v) => `<div><span class="nc-lbl">電話</span>${esc(v)}</div>`).join('')}
          ${emails.slice(0, 1).map((v) => `<div><span class="nc-lbl">Email</span>${esc(v)}</div>`).join('')}
          ${c.address ? `<div><span class="nc-lbl">地址</span>${esc(c.address)}</div>` : ''}
        </div>
        <div class="muted small">${c.date ? '建檔 ' + fmtDate(c.date).split(' ')[0] : ''}</div>
      </div>`;
    }).join('') || '<div class="empty">沒有符合的名片</div>'}</div>`;
  const qi = $('#nc-q');
  qi.oninput = (e) => { cardUI.q = e.target.value; const pos = e.target.selectionStart; renderCards(main, ''); const n = $('#nc-q'); n.focus(); n.setSelectionRange(pos, pos); };
  main.querySelectorAll('.fchip[data-sort]').forEach((el) => el.onclick = () => { cardUI.sort = el.dataset.sort; renderCards(main, ''); });
  main.querySelectorAll('.fchip[data-co]').forEach((el) => el.onclick = () => { cardUI.company = el.dataset.co; renderCards(main, ''); });
}
function renderCardDetail(main, id) {
  const c = Store.cards.find((x) => x.id === id);
  if (!c) { main.innerHTML = pageHead('找不到名片', '<a href="#/cards">回名片</a>'); return; }
  const L = cardLinks(c);
  const phones = cardPhones(c), emails = cardEmails(c), faxes = cardFaxes(c);
  const sameCo = Store.cards.filter((x) => x.id !== c.id && (x.company || '').trim() && (x.company || '').trim() === (c.company || '').trim());
  const row = (label, html) => html ? `<div class="task-row" style="grid-template-columns:64px 1fr"><div class="muted small">${label}</div><div>${html}</div></div>` : '';
  main.innerHTML = `
    <div class="crumb"><a href="#/cards">名片</a> › ${esc(c.name || '未命名')}</div>
    <div class="card hero" style="background:linear-gradient(135deg, rgba(88,86,214,0.16), rgba(50,173,230,0.10))">
      <div class="avatar" style="background:linear-gradient(135deg,#5856d6,#32ade6)">${esc(initial(c.name || c.company))}</div>
      <div style="flex:1;min-width:0">
        <div class="name">${esc(c.name || '未命名')}</div>
        <div class="facts">
          ${c.jobTitle ? `<span>💼 ${esc(c.jobTitle)}</span>` : ''}
          ${c.department ? `<span>🏛️ ${esc(c.department)}</span>` : ''}
          ${c.company ? `<span>🏢 ${esc(c.company)}</span>` : ''}
          ${c.date ? `<span>📆 建檔 ${fmtDate(c.date).split(' ')[0]}</span>` : ''}
        </div>
        ${L.person || L.sub ? `<div class="chips" style="margin-top:8px">
          ${L.sub ? `<a class="chip green" href="#/sub/${L.sub.id}">部屬卡片・${esc(L.sub.name)}</a>` : ''}
          ${L.dept ? `<a class="chip blue" href="#/dept/${L.dept.id}">${esc(L.dept.name)}</a>` : ''}
          ${L.person && !L.sub ? `<a class="chip blue" href="#/org">組織人員・${esc(L.person.name)}</a>` : ''}
        </div>` : ''}
      </div>
    </div>
    <div class="grid cols-2 mt">
      <div class="card"><h3>聯絡資訊</h3>
        ${row('電話', phones.map((v) => `<a href="${telHref(v)}">${esc(v)}</a>`).join('<br>'))}
        ${row('Email', emails.map((v) => `<a href="mailto:${esc(v)}">${esc(v)}</a>`).join('<br>'))}
        ${row('傳真', faxes.map(esc).join('<br>'))}
        ${row('地址', c.address ? `<a href="https://maps.apple.com/?q=${encodeURIComponent(c.address)}" target="_blank" rel="noreferrer">${esc(c.address)}</a>` : '')}
        ${row('主要業務', esc(c.primaryBusiness || ''))}
        ${!phones.length && !emails.length && !faxes.length && !c.address ? '<div class="empty">這張名片沒有聯絡資訊</div>' : ''}
      </div>
      <div class="card"><h3>備註</h3>
        <div style="white-space:pre-wrap;line-height:1.7">${esc(c.note || '') || '<span class="muted">（未填）</span>'}</div>
        ${sameCo.length ? `<div class="section-title">同公司名片（${sameCo.length}）</div><div class="chips">${sameCo.map((x) => `<a class="chip" href="#/cards/${x.id}">${esc(x.name || '未命名')}${x.jobTitle ? '・' + esc(x.jobTitle) : ''}</a>`).join('')}</div>` : ''}
      </div>
    </div>`;
}

// ---- 設定 -----------------------------------------------------------------
function renderSettings(main) {
  const token = localStorage.getItem(TOKEN_KEY) || '';
  const masked = token ? token.slice(0, 6) + '…' + token.slice(-4) : '（未設定）';
  const counts = [['部屬', Store.subs.length], ['部門', Store.depts.length], ['組織人員', Store.orgPeople.length], ['機台', Store.equipment.length], ['里程碑', Store.milestones.length], ['名片', Store.cards.length], ['個人事件', Store.personalEvents.length], ['記帳', Store.expenses.length], ['收入', Store.incomes.length], ['匯率', Store.currencyRates.length], ['儲蓄險', Store.insurances.length], ['股票', Store.stocks.length], ['載具', Store.vehicles.length], ['房地產', Store.realEstates.length]];
  const mins = Math.round(AutoRefresh.intervalMs / 60000);
  main.innerHTML = `
    ${pageHead('設定', `網頁版 v${WEB_VERSION}・設定只存在這台瀏覽器`)}
    <div class="grid cols-2">
      <div class="card"><h3>連線</h3>
        <div class="t-meta">資料來源：<b>${esc(Store.source || '—')}</b>${Store.loadedAt ? `・${fmtDateTime(Store.loadedAt)} 讀取` : ''}</div>
        <div class="t-meta" style="margin-top:6px">CloudKit API Token：<code>${esc(masked)}</code></div>
        <div class="row mt"><button class="btn small" id="st-reload">重新讀取</button><button class="btn small ghost" id="st-token">更換 Token</button><button class="btn small ghost" id="st-signout">登出</button></div>
        <div class="section-title">自動更新</div>
        <div class="row"><span class="t-meta">每</span><select id="st-interval" class="btn small">${[5, 10, 15, 30, 60].map((m) => `<option value="${m}" ${m === mins ? 'selected' : ''}>${m} 分鐘</option>`).join('')}</select><span class="t-meta">在背景重新讀取一次（只有資料變動才重畫）</span></div>
        <div class="muted small mt">${AutoRefresh.nextAt ? `下次自動更新 ${fmtTime(AutoRefresh.nextAt)}` : Store.source === 'iCloud' ? '自動更新暫停中' : '示範資料不自動更新'}</div>
      </div>
      <div class="card"><h3>已讀取的資料</h3><div class="chips">${counts.map(([k, n]) => `<span class="chip ${n ? 'green' : ''}">${k} ${n}</span>`).join('')}</div>
        <div class="section-title">說明</div>
        <div class="t-meta">評分權重使用 App 出廠預設值：App 進階設定裡調整過的權重存在手機本機，不會同步到 iCloud。</div>
        <div class="t-meta" style="margin-top:4px">美股匯率取匯率表的「美金」；沒有就用 31。</div>
        <div class="t-meta" style="margin-top:4px">網頁為唯讀，要修改資料請用 App。</div>
        <div class="t-meta" style="margin-top:4px">頁面順序與分類對齊 App：收支／理財／人生／設定。灰色項目尚未提供網頁版。</div>
        <div class="t-meta" style="margin-top:4px">網頁版 <b>v${WEB_VERSION}</b>，版本獨立於 App（更新網頁不會動到 App 版號）；更新內容見 repo 的 <code>docs/CHANGELOG.md</code>。</div>
      </div>
    </div>`;
  $('#st-reload').onclick = () => $('#reload-btn').click();
  $('#st-token').onclick = () => { localStorage.removeItem(TOKEN_KEY); location.href = location.pathname; };
  $('#st-signout').onclick = () => $('#signout-btn').click();
  $('#st-interval').onchange = (e) => { AutoRefresh.intervalMs = Number(e.target.value) * 60000; try { localStorage.setItem('lifegood_refresh_min', String(e.target.value)); } catch (err) { /* ignore */ } if (Store.source === 'iCloud') AutoRefresh.schedule(); toast(`自動更新改為每 ${e.target.value} 分鐘`); renderSettings(main); };
}

// ---------------------------------------------------------------------------
// 啟動流程
// ---------------------------------------------------------------------------
function showApp() { $('#gate').hidden = true; $('#app').hidden = false; route(); }
function showGate() { $('#app').hidden = true; $('#gate').hidden = false; }

async function startWithToken(token) {
  setStatus('連線 CloudKit 中…');
  try {
    const container = await configureCloudKit(token);
    $('#gate-token').hidden = true; $('#gate-signin').hidden = false;
    const identity = await container.setUpAuth();
    if (identity) { await afterSignIn(); }
    else {
      setStatus('請按上方按鈕以 Apple ID 登入。', '');
      container.whenUserSignsIn().then(afterSignIn).catch((e) => setStatus('登入失敗：' + (e.reason || e.message || e), 'err'));
    }
    container.whenUserSignsOut().then(() => { AutoRefresh.stop(); showGate(); $('#gate-token').hidden = true; $('#gate-signin').hidden = false; setStatus('已登出。', ''); });
  } catch (e) {
    setStatus(String(e.message || e), 'err');
    $('#gate-token').hidden = false; $('#gate-signin').hidden = true;
  }
}
async function afterSignIn() {
  setStatus('已登入，讀取 iCloud 資料中…', 'ok');
  try { await loadFromCloud(); setStatus(''); showApp(); toast(`已讀取 ${Store.subs.length} 位部屬・${Store.depts.length} 個部門`); AutoRefresh.start(); }
  catch (e) { setStatus(String(e.message || e), 'err'); }
}
function startDemo() {
  AutoRefresh.stop();
  applyData(window.LIFEGOOD_DEMO || {}, '示範資料');
  showApp();
  toast('目前顯示示範資料，非你的真實資料');
}

window.addEventListener('hashchange', () => { if (!$('#app').hidden) route(); });
document.addEventListener('DOMContentLoaded', () => {
  $('#token-save').onclick = () => { const t = $('#token-input').value.trim(); if (!t) { setStatus('請先貼上 token', 'err'); return; } localStorage.setItem(TOKEN_KEY, t); startWithToken(t); };
  $('#token-reset').onclick = () => { localStorage.removeItem(TOKEN_KEY); location.reload(); };
  $('#demo-btn').onclick = startDemo; $('#demo-btn-2').onclick = startDemo;
  $('#reload-btn').onclick = async () => { if (Store.source === '示範資料') { toast('示範資料不需重新讀取'); return; } toast('重新讀取中…'); await AutoRefresh.refresh(false); AutoRefresh.schedule(); };
  $('#signout-btn').onclick = () => { if (ckContainer && Store.source !== '示範資料') { const btn = $('#apple-sign-out-button button, #apple-sign-out-button a'); if (btn) btn.click(); else { localStorage.removeItem(TOKEN_KEY); location.reload(); } } else { showGate(); } };
  // 網址帶 token（?token=...）：第一次打開自動存進這台瀏覽器，然後立刻把 token 從網址拿掉，
  // 不留在網址列、瀏覽紀錄或書籤裡。之後打開不帶參數的網址也能直接登入。
  const params = new URLSearchParams(location.search);
  const urlToken = (params.get('token') || '').trim();
  if (urlToken) {
    try { localStorage.setItem(TOKEN_KEY, urlToken); } catch (e) { /* 私密瀏覽等情況存不進去就只用這一次 */ }
    params.delete('token');
    const clean = location.pathname + (params.toString() ? '?' + params.toString() : '') + location.hash;
    try { history.replaceState(null, '', clean); } catch (e) { /* ignore */ }
  }
  const saved = urlToken || localStorage.getItem(TOKEN_KEY);
  if (!urlToken && params.get('demo') === '1') startDemo();
  else if (saved) { $('#token-input').value = saved; startWithToken(saved); }
});
