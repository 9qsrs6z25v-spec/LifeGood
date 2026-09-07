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
};
// JSONEncoder 預設把 Date 編成「距 2001-01-01 的秒數」；這些欄位名一律還原成 Date
const DATE_KEYS = new Set([
  'date', 'dueDate', 'completedAt', 'endDate', 'joinDate', 'birthday', 'scheduledDate',
  'movedTo', 'createdAt', 'dateAdded', 'leftDate', 'sideRoleEndDate', 'updatedAt', 'recurrenceEndDate',
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
  for (const k of Object.keys(KV_KEYS)) Store[k] = reviveDates(Array.isArray(raw[k]) ? raw[k] : []);
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
  intervalMs: 10 * 60 * 1000,
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
  document.querySelectorAll('.nav a').forEach((a) => a.classList.toggle('active', a.dataset.route === page || (page === 'sub' && a.dataset.route === 'subs') || (page === 'siderole' && a.dataset.route === 'sideroles') || ((page === 'dept' || page === 'equipment') && a.dataset.route === 'org')));
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
    if (bi) { for (const y of [from.getFullYear(), to.getFullYear()]) { const d = new Date(y, s.birthday.getMonth(), s.birthday.getDate()); if (inRange(d)) add(d, { kind: 'birthday', title: `🎂 ${s.name} 生日`, sub: bi.sign, href: `#/sub/${s.id}` }); } }
  }
  for (const p of Store.orgPeople) {
    if (!(p.birthday instanceof Date) || p.isInactive || (p.linkedSubordinateId && subById(p.linkedSubordinateId))) continue;
    for (const y of [from.getFullYear(), to.getFullYear()]) { const d = new Date(y, p.birthday.getMonth(), p.birthday.getDate()); if (inRange(d)) add(d, { kind: 'birthday', title: `🎂 ${p.name} 生日`, sub: p.jobTitle || '', href: '#/org' }); }
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
