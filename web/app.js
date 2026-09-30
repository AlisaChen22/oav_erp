'use strict';
/* 前端只負責「畫出 SQL Server 給的定義」與「離線佇列重傳」；欄位、檢核、計算全部在資料庫。 */

// ---------- 小工具 ----------
const $ = s => document.querySelector(s);
function el(tag, props = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v == null || v === false) continue;
    if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'class') e.className = v;
    else if (k === 'value') e.value = v;
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const c of kids.flat(9)) if (c != null && c !== false) e.append(c);
  return e;
}
const store = {
  get(k, d) { try { const v = JSON.parse(localStorage.getItem(k)); return v ?? d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* 無痕模式等 */ } },
};
const uuid = () => (crypto.randomUUID ? crypto.randomUUID() :
  'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const today = () => new Date(Date.now() - new Date().getTimezoneOffset() * 6e4).toISOString().slice(0, 10);
let toastT;
function toast(msg, ms = 2600) { const t = $('#toast'); t.textContent = msg; t.classList.add('show'); clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove('show'), ms); }
const errBox = r => el('div', { class: 'err' }, r.錯誤 || '發生錯誤');

// ---------- 連線 ----------
let online = navigator.onLine;
function setNet(v) { online = v; $('#net').classList.toggle('off', !v); $('#net').title = v ? '已連線' : '離線'; }
async function post(req) {
  const ctl = new AbortController(), t = setTimeout(() => ctl.abort(), 10000);
  try {
    const r = await fetch('api', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(req), signal: ctl.signal });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const j = await r.json(); setNet(true); return j;
  } catch (e) { setNet(false); throw e; } finally { clearTimeout(t); }
}
// 讀取：成功就快取，斷線就用快取
async function read(req) {
  const key = 'c:' + JSON.stringify(req);
  try { const r = await post(req); if (r.ok) store.set(key, r); return r; }
  catch { const c = store.get(key); if (c) { toast('離線中：顯示上次暫存的資料'); return c; } return { ok: false, 錯誤: '無法連線，且沒有暫存資料' }; }
}

// ---------- 離線佇列（寫入一律先進佇列，帶請求編號，伺服器端冪等） ----------
const done = new Map();
let flushing = null;
const outbox = () => store.get('outbox', []);
function badge() { $('#qn').textContent = outbox().length + (store.get('failed', []).length ? '!' : ''); }
async function sendAll() {
  for (let item; (item = outbox()[0]);) {
    let r;
    try { r = await post(item); } catch { break; }              // 網路問題：留在佇列，稍後重送
    store.set('outbox', outbox().filter(x => x.請求編號 !== item.請求編號));
    done.set(item.請求編號, r);
    if (!r.ok) {                                                  // 資料問題：移到失敗清單
      store.set('failed', [...store.get('failed', []), { ...item, 錯誤: r.錯誤 }]);
      if (!item.前景) toast('背景重傳失敗：' + r.錯誤, 5000);
    }
  }
}
function flush() {
  // .finally 一定非同步執行，確保 flushing 先被指定、再被清除
  return flushing ??= sendAll().finally(() => { flushing = null; badge(); });
}
async function write(req) {
  const id = uuid();
  store.set('outbox', [...outbox(), { ...req, 請求編號: id, 時間: new Date().toLocaleString(), 前景: true }]);
  badge();
  // 最多等 8 秒；網路卡住就先告訴使用者「已排隊」，背景繼續重傳
  await Promise.race([flush().then(() => outbox().some(x => x.請求編號 === id) && flush()),
                      new Promise(r => setTimeout(r, 8000))]);
  if (!done.has(id)) {
    store.set('outbox', outbox().map(x => x.請求編號 === id ? { ...x, 前景: false } : x));
    return { ok: true, 排隊: true };
  }
  const r = done.get(id); done.delete(id);
  if (!r.ok) store.set('failed', store.get('failed', []).filter(x => x.請求編號 !== id));  // 前景失敗直接提示，不留紀錄
  badge();
  return r;
}
addEventListener('online', flush);
document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && flush());
setInterval(flush, 20000);

// ---------- 畫面堆疊 ----------
const stack = [];
async function render() {
  const v = stack[stack.length - 1];
  $('#title').textContent = v.title; $('#back').hidden = stack.length < 2;
  const node = await v.fn();
  if (stack[stack.length - 1] === v) { $('#main').replaceChildren(node); scrollTo(0, 0); }
}
function go(title, fn) { stack.push({ title, fn }); history.pushState(stack.length, ''); render(); }
function replace(title, fn) { stack[stack.length - 1] = { title, fn }; render(); }
function back() { if (stack.length > 1) history.back(); }
addEventListener('popstate', e => {
  const n = Math.max(1, Math.min(stack.length, Number(e.state) || 1));
  if (n < stack.length) { stack.length = n; render(); }
});
$('#back').onclick = back;
$('#sync').onclick = () => go('同步狀態', vSync);

// ---------- 定義（欄位中繼資料，由 SQL Server 系統目錄產生） ----------
const defs = {};
async function getDef(fn) {
  if (defs[fn]) return defs[fn];
  const r = await read({ 動作: '定義', 功能: fn });
  if (!r.ok) throw new Error(r.錯誤);
  return (defs[fn] = r.資料);
}

// ---------- 欄位輸入 ----------
let dl = 0;
function field(c, obj, table, lock) {
  const type = c.型別 === 'date' ? 'date' : /int|decimal|numeric/.test(c.型別) ? 'number' : 'text';
  const ro = c.唯讀 || lock;
  const inp = el('input', {
    type, value: obj[c.欄位] ?? '', disabled: ro, maxlength: c.長度 || null, inputmode: type === 'number' ? 'numeric' : null,
    placeholder: c.主鍵 && !lock && !ro && c.型別 !== 'date' && c.欄位.endsWith('編號') && table.endsWith('主檔') ? '空白＝自動編號' : null,
    oninput: e => { const v = e.target.value; obj[c.欄位] = v === '' ? null : type === 'number' ? Number(v) : v; },
  });
  if (c.參照表 && !ro) {
    const id = 'dl' + (++dl), list = el('datalist', { id });
    inp.setAttribute('list', id);
    inp.addEventListener('focus', async () => {
      const r = await read({ 動作: '選項', 表: table, 欄: c.欄位, 列: obj });
      if (r.ok) list.replaceChildren(...r.資料.map(o => el('option', { value: o.值 }, o.說明 || null)));
    });
    return el('label', {}, el('span', { class: c.可空 ? null : 'req' }, c.欄位), inp, list);
  }
  return el('label', {}, el('span', { class: c.可空 || ro ? null : 'req' }, c.欄位), inp);
}

// ---------- 主功能表 ----------
async function vMenu() {
  const r = await read({ 動作: '功能表' });
  if (!r.ok) return errBox(r);
  const all = r.資料, kids = p => all.filter(i => (i.上層代碼 ?? null) === p);
  setTimeout(() => all.filter(i => ['主檔', '單據', '報表'].includes(i.類型)).reduce(
    (p, i) => p.then(() => getDef(i.功能代碼).catch(() => {})), Promise.resolve()), 500);   // 預載定義供離線使用
  return el('div', {}, kids(null).map(m => el('section', { class: 'mod' },
    el('h2', {}, m.名稱),
    kids(m.功能代碼).map(g => [el('h3', {}, g.名稱),
      el('div', { class: 'btns' }, kids(g.功能代碼).map(f =>
        el('button', { class: 'fn', 'data-t': f.類型, onclick: () => go(f.名稱, () => vList(f.功能代碼)) }, f.名稱)))]))));
}

// ---------- 列表 ----------
function table(cols, rows, onRow) {
  const names = cols.map(c => c.欄位), num = new Set(cols.filter(c => /int|decimal|numeric/.test(c.型別)).map(c => c.欄位));
  return [el('div', { class: 'tbl' }, el('table', {},
    el('thead', {}, el('tr', {}, names.map(n => el('th', {}, n)))),
    el('tbody', {}, rows.map(r => el('tr', { class: onRow ? 'click' : null, onclick: onRow ? () => onRow(r) : null },
      names.map(n => el('td', { class: num.has(n) ? 'n' : null }, r[n] ?? ''))))))),
  el('div', { class: 'cnt' }, `共 ${rows.length} 筆${rows.length >= 500 ? '（僅顯示前 500 筆，請用關鍵字縮小範圍）' : ''}`)];
}
async function vList(fn) {
  let def; try { def = await getDef(fn); } catch (e) { return errBox({ 錯誤: e.message }); }
  const box = el('div'), q = el('input', { type: 'search', placeholder: '關鍵字搜尋', value: store.get('q:' + fn, '') });
  const pk = def.欄位.filter(c => c.主鍵).map(c => c.欄位);
  const open = row => def.類型 === '主檔' ? go(def.名稱, () => vForm(def, row))
    : go(def.名稱, () => vDoc(def, Object.fromEntries(pk.map(k => [k, row[k]]))));
  // 報表參數（例如 年度）：名稱、型別、預設值都來自 SQL Server 的 sys.parameters
  const params = store.get('p:' + fn, null) ?? Object.fromEntries((def.參數 || []).map(p => [p.參數, p.預設 == null ? null : p.型別 === 'int' ? Number(p.預設) : p.預設]));
  const pbox = (def.參數 || []).map(p => field({ 欄位: p.參數, 型別: p.型別, 可空: true }, params, '', false));
  const load = async () => {
    store.set('q:' + fn, q.value); store.set('p:' + fn, params);
    const r = await read({ 動作: '查詢', 功能: fn, 關鍵字: q.value || null, 參數: params });
    box.replaceChildren(...(r.ok ? table(def.欄位, r.資料, def.類型 === '報表' ? null : open) : [errBox(r)]));
  };
  q.addEventListener('keydown', e => e.key === 'Enter' && load());
  load();
  return el('div', {},
    pbox.length > 0 && el('div', { class: 'bar params' }, pbox),
    el('div', { class: 'bar' }, q, el('button', { class: 'b alt', onclick: load }, '查詢'),
      def.類型 !== '報表' && el('button', { class: 'b', onclick: () => go(def.名稱, () => def.類型 === '主檔' ? vForm(def, null) : vDoc(def, null)) }, '＋ 新增')),
    box);
}

// ---------- 主檔維護 ----------
async function vForm(def, row) {
  const isNew = !row, data = { ...(row || {}) };
  const save = async () => {
    const r = await write({ 動作: '存檔', 功能: def.功能, 資料: data });
    if (!r.ok) return toast(r.錯誤, 6000);
    toast(r.排隊 ? '離線：已排入待上傳，連線後自動重傳' : '已存檔'); back();
  };
  const del = async () => {
    if (!confirm('確定刪除？')) return;
    const r = await write({ 動作: '刪除', 功能: def.功能, 鍵: Object.fromEntries(def.欄位.filter(c => c.主鍵).map(c => [c.欄位, data[c.欄位]])) });
    if (!r.ok) return toast(r.錯誤, 6000);
    toast(r.排隊 ? '離線：刪除已排入待上傳' : '已刪除'); back();
  };
  return el('div', {},
    el('div', { class: 'form' }, def.欄位.map(c => field(c, data, def.物件, !isNew && c.主鍵))),
    el('div', { class: 'acts' }, el('button', { class: 'b', onclick: save }, '存檔'),
      !isNew && el('button', { class: 'b del', onclick: del }, '刪除'),
      el('button', { class: 'b alt', onclick: back }, '取消')));
}

// ---------- 單據維護（主檔＋明細） ----------
async function vDoc(def, key) {
  let doc;
  if (key) { const r = await read({ 動作: '讀取', 功能: def.功能, 鍵: key }); if (!r.ok) return errBox(r); doc = r.資料; }
  else { doc = { 明細: [] }; def.欄位.filter(c => c.型別 === 'date' && !c.可空).forEach(c => doc[c.欄位] = today()); }
  doc.明細 ??= [];
  const pkCol = def.欄位.find(c => c.主鍵).欄位;
  const itemCol = def.明細欄位.find(c => c.主鍵 && c.欄位 !== pkCol).欄位;
  const lineCols = def.明細欄位.filter(c => c.欄位 !== pkCol && c.欄位 !== itemCol);
  const lines = el('div');
  const drawLines = () => lines.replaceChildren(...doc.明細.map((ln, i) => el('div', { class: 'form line' },
    el('div', { class: 'hd' }, el('span', {}, `項次 ${ln[itemCol] || '（新）'}`),
      el('button', { title: '刪除此項次', onclick: () => { doc.明細.splice(i, 1); drawLines(); } }, '×')),
    lineCols.map(c => field(c, ln, def.明細表, false)))));
  drawLines();
  const save = async () => {
    const r = await write({ 動作: '存檔', 功能: def.功能, 資料: doc });
    if (!r.ok) return toast(r.錯誤, 6000);
    if (r.排隊) { toast('離線：已排入待上傳，連線後自動重傳'); return back(); }
    toast(`已存檔 ${r.資料.編號}`);
    replace(def.名稱, () => vDoc(def, { [pkCol]: r.資料.編號 }));     // 重讀：顯示觸發程序帶入/計算的結果
  };
  const del = async () => {
    if (!confirm(`確定刪除單據 ${doc[pkCol]}？`)) return;
    const r = await write({ 動作: '刪除', 功能: def.功能, 鍵: { [pkCol]: doc[pkCol] } });
    if (!r.ok) return toast(r.錯誤, 6000);
    toast(r.排隊 ? '離線：刪除已排入待上傳' : '已刪除'); back();
  };
  return el('div', {},
    el('div', { class: 'form' }, def.欄位.map(c => field(c, doc, def.物件, !!key && c.主鍵))),
    el('h3', {}, `明細（${def.明細表}）`), lines,
    el('div', { class: 'acts' },
      el('button', { class: 'b alt', onclick: () => { doc.明細.push({}); drawLines(); } }, '＋ 新增項次'),
      el('button', { class: 'b', onclick: save }, '存檔'),
      key && el('button', { class: 'b del', onclick: del }, '刪除單據'),
      el('button', { class: 'b alt', onclick: back }, '取消')));
}

// ---------- 同步狀態 ----------
async function vSync() {
  const q = outbox(), f = store.get('failed', []);
  const desc = x => `${x.時間}　${x.動作}　${x.功能}　${x.資料 ? (Object.values(x.資料)[0] ?? '(新單據)') : JSON.stringify(x.鍵)}`;
  return el('div', {},
    el('h2', {}, `待上傳（${q.length}）`),
    q.length ? q.map(x => el('div', { class: 'item' }, desc(x))) : el('div', { class: 'cnt' }, '沒有待上傳的資料'),
    el('div', { class: 'acts' }, el('button', { class: 'b', onclick: async () => { await flush(); replace('同步狀態', vSync); toast(outbox().length ? '仍無法連線' : '已全部上傳'); } }, '立即重傳')),
    el('h2', {}, `重傳失敗（${f.length}）`),
    f.map(x => el('div', { class: 'item' }, desc(x), el('div', { class: 'e' }, x.錯誤))),
    f.length > 0 && el('div', { class: 'acts' }, el('button', { class: 'b del', onclick: () => { store.set('failed', []); badge(); replace('同步狀態', vSync); } }, '清除失敗紀錄')));
}

// ---------- 啟動 ----------
setNet(navigator.onLine);
badge();
stack.push({ title: 'OAV ERP 庫存管理', fn: vMenu });
history.replaceState(1, '');
render();
flush();
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
