/* DecomExch webinterface. Geen externe afhankelijkheden. Gegevens uit Exchange worden
   uitsluitend als tekst (textContent) in de pagina gezet, nooit als HTML. */
'use strict';

(() => {
  // ------------------------------------------------------------------ status
  const state = {
    token: null,
    live: false,
    status: null,
    servers: null,
    databases: null,
    cache: {},
    prefill: { identities: [], folders: [] },
    timers: [],
  };

  // ------------------------------------------------------------------ iconen (statische, vertrouwde SVG)
  const ICONS = {
    dashboard: '<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>',
    list: '<path d="M8 6h13M8 12h13M8 18h13"/><circle cx="3.5" cy="6" r="1"/><circle cx="3.5" cy="12" r="1"/><circle cx="3.5" cy="18" r="1"/>',
    mailbox: '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
    folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
    download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/>',
    trash: '<path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/>',
    log: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M8 13h8M8 17h8M8 9h2"/>',
    refresh: '<path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 3v6h-6"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
    server: '<rect x="3" y="3" width="18" height="7" rx="1.5"/><rect x="3" y="14" width="18" height="7" rx="1.5"/><path d="M7 6.5h.01M7 17.5h.01"/>',
    database: '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v14c0 1.66 3.58 3 8 3s8-1.34 8-3V5"/><path d="M4 12c0 1.66 3.58 3 8 3s8-1.34 8-3"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    unlink: '<path d="M9 17H7a5 5 0 0 1 0-10h2M15 7h2a5 5 0 0 1 4 8M8 12h3M2 2l20 20"/>',
    cert: '<circle cx="12" cy="9" r="6"/><path d="m8.5 14-1.5 8 5-3 5 3-1.5-8"/>',
    move: '<path d="M5 12h14M13 6l6 6-6 6"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 16v-4M12 8h.01"/>',
    warn: '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    x: '<path d="M18 6 6 18M6 6l12 12"/>',
    power: '<path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.8 0"/>',
    moon: '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
    file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
    plug: '<path d="M9 2v6M15 2v6M6 8h12v4a6 6 0 0 1-12 0z"/><path d="M12 18v4"/>',
    arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  };

  function icon(name) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '2');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    svg.setAttribute('aria-hidden', 'true');
    svg.innerHTML = ICONS[name] || '';
    return svg;
  }

  // ------------------------------------------------------------------ DOM-hulp
  function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    if (attrs) {
      for (const [key, value] of Object.entries(attrs)) {
        if (value === null || value === undefined || value === false) continue;
        if (key === 'class') el.className = value;
        else if (key === 'text') el.textContent = value;
        else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2), value);
        else if (key === 'dataset') Object.assign(el.dataset, value);
        else if (key in el && typeof value !== 'string') el[key] = value;
        else el.setAttribute(key, value === true ? '' : value);
      }
    }
    append(el, children);
    return el;
  }

  function append(el, children) {
    for (const child of children.flat(Infinity)) {
      if (child === null || child === undefined || child === false) continue;
      el.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return el;
  }

  const $ = (sel, root = document) => root.querySelector(sel);
  const clear = (el) => { while (el.firstChild) el.removeChild(el.firstChild); return el; };

  // ------------------------------------------------------------------ opmaak
  const nf0 = new Intl.NumberFormat('nl-NL', { maximumFractionDigits: 0 });
  const nf1 = new Intl.NumberFormat('nl-NL', { maximumFractionDigits: 1, minimumFractionDigits: 0 });
  const fmtNum = (v, dec = 0) => (v === null || v === undefined || v === '' || isNaN(v)) ? '' : (dec ? nf1 : nf0).format(Number(v));
  const fmtMb = (mb) => {
    if (mb === null || mb === undefined || mb === '') return '';
    const n = Number(mb);
    return n >= 1024 ? nf1.format(n / 1024) + ' GB' : nf1.format(n) + ' MB';
  };
  const plural = (n, one, many) => `${fmtNum(n)} ${n === 1 ? one : many}`;

  function statusBadge(status) {
    const s = String(status ?? '');
    const map = {
      OK: 'ok', Info: '', Waarschuwing: 'warn', Blokkerend: 'bad',
      Aangemaakt: 'ok', Geexporteerd: 'ok', Completed: 'ok', CompletedWithWarning: 'ok',
      Mislukt: 'bad', Failed: 'bad', Simulatie: 'accent',
      InProgress: 'warn', Queued: 'warn', CompletionInProgress: 'warn', Suspended: 'warn', AutoSuspended: 'warn',
      Error: 'bad', Warning: 'warn', Success: 'ok', Action: 'accent',
    };
    const labels = { Geexporteerd: 'Geëxporteerd', Error: 'Fout', Warning: 'Waarschuwing', Success: 'Gelukt', Action: 'Actie' };
    return h('span', { class: 'badge ' + (map[s] ?? ''), text: labels[s] || s || '-' });
  }

  const yesNo = (v, goodWhenTrue = null) => {
    const cls = goodWhenTrue === null ? '' : ((v ? goodWhenTrue : !goodWhenTrue) ? 'ok' : 'warn');
    return h('span', { class: 'badge ' + cls, text: v ? 'Ja' : 'Nee' });
  };

  // In simulatiemodus is 'niet verwijderd' de verwachte uitkomst, geen waarschuwing.
  const removedBadge = (v) => v ? h('span', { class: 'badge ok', text: 'Ja' })
    : h('span', { class: 'badge ' + (state.live ? 'warn' : ''), text: state.live ? 'Nee' : 'Simulatie' });

  function autoCell(value) {
    if (typeof value === 'boolean') return yesNo(value);
    if (value === null || value === undefined) return '';
    return String(value);
  }

  // ------------------------------------------------------------------ API
  async function api(method, path, body) {
    const res = await fetch(path, {
      method,
      headers: { 'X-DecomExch-Token': state.token, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    let data = null;
    try { data = await res.json(); } catch { /* lege of ongeldige respons */ }
    if (!res.ok) throw new Error((data && data.error) || `Fout ${res.status}`);
    return data;
  }

  // ------------------------------------------------------------------ meldingen & dialogen
  function toast(message, kind = '') {
    const el = h('div', { class: 'toast ' + kind, role: 'status' },
      icon(kind === 'bad' ? 'warn' : kind === 'ok' ? 'check' : 'info'), h('div', null, message));
    el.title = 'Klik om te sluiten';
    el.addEventListener('click', () => el.remove());
    $('#toasts').appendChild(el);
    // Lange meldingen (bijv. met een oplossing) blijven langer staan.
    const base = kind === 'bad' ? 9000 : 5000;
    setTimeout(() => el.remove(), Math.min(45000, Math.max(base, String(message).length * 70)));
  }

  function dialog({ title, message, danger = false, iconName = 'info', confirmLabel = 'OK', cancelLabel = 'Annuleren', requireText = null, body = null }) {
    return new Promise((resolve) => {
      const dlg = $('#dialog');
      clear(dlg);
      const input = requireText ? h('input', { type: 'text', class: 'input', autocomplete: 'off', placeholder: `Typ ${requireText}`, 'aria-label': `Typ ${requireText} om te bevestigen` }) : null;
      const okBtn = h('button', { type: 'button', class: 'btn ' + (danger ? 'danger' : 'primary'), text: confirmLabel, disabled: !!requireText });
      const close = (result) => { resolve(result); dlg.close(); };
      if (input) input.addEventListener('input', () => { okBtn.disabled = input.value !== requireText; });
      okBtn.addEventListener('click', () => close(true));
      append(dlg, [
        h('div', { class: 'dialog-head' },
          h('div', { class: 'icon' + (danger ? ' bad' : '') }, icon(danger ? 'warn' : iconName)),
          h('div', null, h('h3', { text: title }), message ? h('p', { text: message }) : null)),
        (body || input) ? h('div', { class: 'dialog-body' }, body, input ? h('div', { class: 'field' }, h('label', { text: `Typ ${requireText} om te bevestigen` }), input) : null) : null,
        h('div', { class: 'dialog-foot' },
          cancelLabel ? h('button', { type: 'button', class: 'btn', text: cancelLabel, onclick: () => close(false) }) : null,
          okBtn),
      ]);
      dlg.onclose = () => resolve(false);
      dlg.oncancel = () => resolve(false);
      dlg.showModal();
      (input || okBtn).focus();
    });
  }

  function busy(card, text = 'Bezig...', sub = 'Dit kan bij grote omgevingen enkele minuten duren.') {
    const el = h('div', { class: 'busy' }, h('div', { class: 'busy-inner' }, h('div', { class: 'spinner' }), text, sub ? h('small', { text: sub }) : null));
    card.appendChild(el);
    return () => el.remove();
  }

  async function withBusy(card, fn, text, sub) {
    const done = busy(card, text, sub);
    try { return await fn(); }
    catch (err) { toast(err.message, 'bad'); throw err; }
    finally { done(); }
  }

  // ------------------------------------------------------------------ CSV en rapporten
  function downloadCsv(rows, name) {
    if (!rows || !rows.length) { toast('Geen gegevens om te exporteren.', 'warn'); return; }
    const keys = [...new Set(rows.flatMap((r) => Object.keys(r)))];
    const esc = (v) => {
      const s = v === null || v === undefined ? '' : String(v);
      return /[";\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
    };
    const lines = [keys.join(';'), ...rows.map((r) => keys.map((k) => esc(r[k])).join(';'))];
    const blob = new Blob(['\ufeff' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
    const a = h('a', { href: URL.createObjectURL(blob), download: `${name}_${new Date().toISOString().slice(0, 10)}.csv` });
    document.body.appendChild(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }

  async function saveReport(title, rows) {
    if (!rows || !rows.length) { toast('Geen gegevens om op te slaan.', 'warn'); return; }
    try {
      const res = await api('POST', '/api/report', { title, rows });
      toast(`Rapport opgeslagen: ${res.file}`, 'ok');
    } catch (err) { toast(err.message, 'bad'); }
  }

  const exportButtons = (getRows, name, title) => [
    h('button', { type: 'button', class: 'btn small', onclick: () => downloadCsv(getRows(), name) }, icon('download'), 'CSV'),
    h('button', { type: 'button', class: 'btn small', onclick: () => saveReport(title, getRows()) }, icon('file'), 'HTML-rapport'),
  ];

  // ------------------------------------------------------------------ tabel
  class DataTable {
    constructor({ columns, rows = [], key = null, selectable = false, onSelect = null, limit = 500, empty = 'Geen gegevens.' }) {
      this.columns = columns;
      this.rows = rows;
      this.key = key;
      this.selectable = selectable;
      this.onSelect = onSelect;
      this.limit = limit;
      this.empty = empty;
      this.search = '';
      this.filter = null;
      this.sort = null;
      this.selected = new Set();
      this.el = h('div');
      this.render();
    }

    static auto(rows, opts = {}) {
      const keys = [...new Set((rows || []).flatMap((r) => Object.keys(r)))];
      const columns = keys.map((k) => {
        const numeric = rows.some((r) => typeof r[k] === 'number');
        return { key: k, label: k, align: numeric ? 'right' : null, format: numeric ? (v) => fmtNum(v, 1) : null, wrap: /Details|Oplossing|Fout|Opmerking|Melding|Bericht|Filter|Subject/.test(k) };
      });
      return new DataTable({ columns, rows: rows || [], ...opts });
    }

    setRows(rows) { this.rows = rows || []; this.selected.clear(); this.render(); this.emitSelect(); }
    setSearch(text) { this.search = text.trim().toLowerCase(); this.render(); }
    setFilter(fn) { this.filter = fn; this.render(); }

    visibleRows() {
      let rows = this.rows;
      if (this.filter) rows = rows.filter(this.filter);
      if (this.search) {
        const q = this.search;
        rows = rows.filter((r) => Object.values(r).some((v) => v !== null && v !== undefined && String(v).toLowerCase().includes(q)));
      }
      if (this.sort) {
        const { key, dir } = this.sort;
        const coll = new Intl.Collator('nl', { numeric: true, sensitivity: 'base' });
        rows = [...rows].sort((a, b) => {
          const x = a[key], y = b[key];
          if (x === y) return 0;
          if (x === null || x === undefined || x === '') return 1;
          if (y === null || y === undefined || y === '') return -1;
          const r = (typeof x === 'number' && typeof y === 'number') ? x - y : coll.compare(String(x), String(y));
          return dir * r;
        });
      }
      return rows;
    }

    emitSelect() { if (this.onSelect) this.onSelect(this.selectedRows()); }
    selectedRows() { return this.rows.filter((r) => this.selected.has(this.key(r))); }

    render() {
      const rows = this.visibleRows();
      clear(this.el);
      if (!this.rows.length) {
        this.el.appendChild(h('div', { class: 'empty' }, icon('info'), this.empty));
        return;
      }

      const shown = rows.slice(0, this.limit);
      const head = h('tr');
      if (this.selectable) {
        const allSelected = rows.length > 0 && rows.every((r) => this.selected.has(this.key(r)));
        const cb = h('input', { type: 'checkbox', checked: allSelected, 'aria-label': 'Alles selecteren' });
        cb.addEventListener('change', () => {
          rows.forEach((r) => cb.checked ? this.selected.add(this.key(r)) : this.selected.delete(this.key(r)));
          this.render(); this.emitSelect();
        });
        head.appendChild(h('th', { class: 'select' }, cb));
      }
      for (const col of this.columns) {
        const sorted = this.sort && this.sort.key === col.key;
        head.appendChild(h('th', {
          class: 'sortable' + (col.align === 'right' ? ' right' : ''),
          onclick: () => { this.sort = { key: col.key, dir: sorted ? -this.sort.dir : (col.align === 'right' ? -1 : 1) }; this.render(); },
        }, col.label, h('span', { class: 'arrow', text: sorted ? (this.sort.dir > 0 ? '\u25B2' : '\u25BC') : '\u2195' })));
      }

      const body = h('tbody');
      for (const row of shown) {
        const id = this.selectable ? this.key(row) : null;
        const tr = h('tr', { class: this.selectable && this.selected.has(id) ? 'selected' : null });
        if (this.selectable) {
          const cb = h('input', { type: 'checkbox', checked: this.selected.has(id), 'aria-label': 'Selecteren' });
          cb.addEventListener('change', () => {
            cb.checked ? this.selected.add(id) : this.selected.delete(id);
            tr.classList.toggle('selected', cb.checked);
            this.emitSelect();
          });
          tr.appendChild(h('td', { class: 'select' }, cb));
        }
        for (const col of this.columns) {
          const value = row[col.key];
          const content = col.format ? col.format(value, row) : autoCell(value);
          tr.appendChild(h('td', { class: [col.align === 'right' ? 'right num' : '', col.wrap ? 'wrap' : 'nowrap', col.mono ? 'mono' : ''].join(' ') }, content));
        }
        body.appendChild(tr);
      }

      this.el.appendChild(h('div', { class: 'table-wrap' }, h('table', { class: 'data' }, h('thead', null, head), body)));
      const foot = h('div', { class: 'table-foot' },
        h('span', { text: rows.length === this.rows.length ? plural(rows.length, 'rij', 'rijen') : `${fmtNum(rows.length)} van ${fmtNum(this.rows.length)} rijen (gefilterd)` }),
        rows.length > this.limit ? h('span', { text: `Eerste ${fmtNum(this.limit)} getoond; verfijn met zoeken of filters. CSV bevat alles.` }) : null);
      this.el.appendChild(foot);
    }
  }

  function searchBox(onInput, placeholder = 'Zoeken...') {
    const input = h('input', { type: 'text', class: 'input', placeholder, 'aria-label': placeholder });
    input.addEventListener('input', () => onInput(input.value));
    return h('div', { class: 'search' }, icon('search'), input);
  }

  // ------------------------------------------------------------------ gedeelde gegevens
  async function loadServers() {
    if (!state.servers) state.servers = await api('GET', '/api/servers');
    return state.servers;
  }
  async function loadDatabases() {
    if (!state.databases) state.databases = await api('GET', '/api/databases');
    return state.databases;
  }

  function serverSelect(servers, { allowAll = false, includeEdge = false } = {}) {
    const sel = h('select', { class: 'input' });
    if (allowAll) sel.appendChild(h('option', { value: '', text: 'Alle servers' }));
    for (const s of servers.filter((x) => includeEdge || !x.edge)) {
      sel.appendChild(h('option', { value: s.name, text: `${s.name}  (${s.role})` }));
    }
    return sel;
  }

  const simulate = () => !state.live;

  // Knoppen die iets wijzigen tonen 'Simuleren' of 'Uitvoeren', afhankelijk van de modus.
  function actionButton(kind, labels, onclick) {
    const btn = h('button', { type: 'button', class: 'btn', dataset: { kind, sim: labels.sim, live: labels.live }, onclick });
    updateActionButton(btn);
    return btn;
  }
  function updateActionButton(btn) {
    clear(btn);
    const live = state.live;
    btn.className = 'btn ' + (live ? (btn.dataset.kind === 'destructive' ? 'danger' : 'primary') : 'primary');
    append(btn, [icon(live ? (btn.dataset.kind === 'destructive' ? 'trash' : 'download') : 'shield'), live ? btn.dataset.live : btn.dataset.sim]);
  }
  const updateActionButtons = () => document.querySelectorAll('button[data-kind]').forEach(updateActionButton);

  async function confirmDestructive(what) {
    if (!state.live) return true;
    return dialog({
      title: 'Echt uitvoeren?',
      message: `${what}. Dit wordt nu echt uitgevoerd op de Exchange-omgeving en is mogelijk niet terug te draaien.`,
      danger: true, confirmLabel: 'Uitvoeren', requireText: 'JA',
    });
  }

  function notConnectedCard() {
    return h('div', { class: 'card' }, h('div', { class: 'card-body' },
      h('div', { class: 'callout warn' }, icon('plug'), h('div', null,
        h('strong', { text: 'Niet verbonden met Exchange. ' }),
        'Start de interface vanuit de Exchange Management Shell, of maak verbinding met een Exchange-server. ',
        h('button', { type: 'button', class: 'btn small primary', text: 'Verbinden', onclick: openConnectDialog })))));
  }

  // ------------------------------------------------------------------ pagina's
  const pages = {};

  // ---------- Dashboard
  pages.dashboard = {
    title: 'Dashboard', icon: 'dashboard', group: 'Onderzoek',
    async render(root, params) {
      if (!state.status.connected) { root.appendChild(notConnectedCard()); return; }
      const refreshBtn = h('button', { type: 'button', class: 'btn', onclick: () => load(true) }, icon('refresh'), 'Vernieuwen');
      const stamp = h('span', { class: 'muted' });
      root.appendChild(h('p', { class: 'page-intro', text: 'Overzicht van de Exchange-organisatie. De gegevens komen uit een volledige inventarisatie (alleen lezen).' }));
      const holder = h('div', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', { text: 'Kerncijfers' }), stamp, h('div', { class: 'actions' }, refreshBtn)), h('div', { class: 'card-body' }));
      const rest = h('div');
      root.appendChild(holder);
      root.appendChild(rest);

      const load = async (refresh = false) => {
        try {
          const data = await withBusy(holder, () => api('GET', '/api/overview' + (refresh ? '?refresh=1' : '')), 'Inventarisatie uitvoeren...');
          state.cache.overview = data;
          if (refresh) state.cache.inventory = null;
          draw(data);
        } catch { /* melding al getoond */ }
      };

      const draw = (d) => {
        const k = d.kpis;
        stamp.textContent = `bijgewerkt ${d.generated}`;
        const tile = (label, iconName, value, note, href, cls = '') =>
          h('a', { class: 'card kpi ' + cls, href }, h('div', { class: 'kpi-label' }, icon(iconName), label), h('div', { class: 'kpi-value', text: value }), h('div', { class: 'kpi-note', text: note }));
        const body = clear(holder.querySelector('.card-body'));
        body.appendChild(h('div', { class: 'grid kpis' },
          tile('Servers', 'server', fmtNum(k.servers), `${plural(k.databases, 'database', 'databases')}`, '#/inventory'),
          tile('Mailboxen', 'mailbox', fmtNum(k.mailboxes), `${fmtMb(k.mailboxSizeGb * 1024)} totaal`, '#/mailboxes'),
          tile('Inactieve mailboxen', 'clock', fmtNum(k.inactiveMailboxes), 'langer dan 90 dagen niet aangemeld', '#/mailboxes?inactive=1', k.inactiveMailboxes ? 'attention' : ''),
          tile('Public folders', 'folder', fmtNum(k.publicFolders), `${fmtMb(k.publicFolderSizeMb)} totaal`, '#/publicfolders'),
          tile('Losgekoppelde mailboxen', 'unlink', fmtNum(k.disconnected), 'nemen nog ruimte in', '#/cleanup', k.disconnected ? 'attention' : ''),
          tile('Verlopen certificaten', 'cert', fmtNum(k.expiredCertificates), 'op alle servers', '#/cleanup', k.expiredCertificates ? 'alert' : ''),
          tile('Open verplaatsaanvragen', 'move', fmtNum(k.openMoveRequests), 'nog niet afgerond', '#/inventory', k.openMoveRequests ? 'attention' : ''),
          tile('Databases', 'database', fmtNum(k.databases), 'mailboxdatabases', '#/inventory')));

        clear(rest);
        // Aandachtspunten
        const items = [];
        const item = (cls, iconName, text, href, linkText) => h('div', { class: 'callout ' + cls }, icon(iconName), h('div', null, text, ' ', href ? h('a', { href, text: linkText }) : null));
        if (k.expiredCertificates) items.push(item('bad', 'cert', `${plural(k.expiredCertificates, 'verlopen certificaat', 'verlopen certificaten')} gevonden.`, '#/cleanup', 'Opruimen'));
        if (k.openMoveRequests) items.push(item('warn', 'move', `${plural(k.openMoveRequests, 'verplaatsaanvraag is', 'verplaatsaanvragen zijn')} nog niet afgerond.`, '#/inventory', 'Bekijken'));
        if (k.disconnected) items.push(item('warn', 'unlink', `${plural(k.disconnected, 'losgekoppelde mailbox neemt', 'losgekoppelde mailboxen nemen')} nog ruimte in.`, '#/cleanup', 'Opruimen'));
        if (k.inactiveMailboxes) items.push(item('warn', 'clock', `${plural(k.inactiveMailboxes, 'mailbox is', 'mailboxen zijn')} al lang niet gebruikt: exporteren of verwijderen?`, '#/mailboxes?inactive=1', 'Bekijken'));
        if (k.publicFolders) items.push(item('', 'folder', `${plural(k.publicFolders, 'public folder', 'public folders')} aanwezig: migreren of exporteren naar PST voor uitfasering.`, '#/publicfolders', 'Bekijken'));
        items.push(item('', 'shield', 'Controleer per server wat de uitfasering nog blokkeert.', '#/readiness', 'Uitfaseringscontrole'));

        const serverTable = DataTable.auto(d.servers, { empty: 'Geen servers.' });
        const typeMax = Math.max(1, ...d.mailboxTypes.map((t) => Number(t.Aantal) || 0));
        rest.appendChild(h('div', { class: 'grid two' },
          h('div', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', { text: 'Aandachtspunten' })), h('div', { class: 'card-body' }, h('div', { class: 'grid' }, items))),
          h('div', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', { text: 'Mailboxen per type' })), h('div', { class: 'card-body' },
            d.mailboxTypes.length ? h('div', { class: 'barlist' }, d.mailboxTypes.map((t) => {
              const bar = h('span');
              bar.style.width = `${Math.round((Number(t.Aantal) || 0) / typeMax * 100)}%`;
              return h('div', { class: 'row' }, h('span', { text: t.Type }), h('div', { class: 'bar' }, bar), h('span', { class: 'num right', text: fmtNum(t.Aantal) }));
            })) : h('div', { class: 'empty', text: 'Geen gegevens.' })))));
        rest.appendChild(h('div', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', { text: 'Servers' })), h('div', { class: 'card-body flush' }, serverTable.el)));
        rest.appendChild(h('div', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', { text: 'Databases' })), h('div', { class: 'card-body flush' }, DataTable.auto(d.databases, { empty: 'Geen databases.' }).el)));
      };

      if (state.cache.overview) draw(state.cache.overview); else await load(false);
    },
  };

  // ---------- Inventaris
  pages.inventory = {
    title: 'Inventaris', icon: 'list', group: 'Onderzoek',
    async render(root) {
      if (!state.status.connected) { root.appendChild(notConnectedCard()); return; }
      root.appendChild(h('p', { class: 'page-intro', text: 'Alle onderdelen van de inventarisatie. Klap een onderdeel open om de details te zien; elk onderdeel is als CSV te downloaden.' }));
      const stamp = h('span', { class: 'sub' });
      const list = h('div', { class: 'card-body flush' });
      const card = h('div', { class: 'card' },
        h('div', { class: 'card-head' }, h('h2', { text: 'Inventarisatie' }), stamp, h('div', { class: 'actions' },
          h('button', { type: 'button', class: 'btn', onclick: () => load(true) }, icon('refresh'), 'Vernieuwen'),
          h('button', { type: 'button', class: 'btn primary', onclick: saveFull }, icon('file'), 'Volledig HTML-rapport opslaan'))),
        list);
      root.appendChild(card);

      async function saveFull() {
        try { const res = await api('POST', '/api/inventory/report'); toast(`Rapport opgeslagen: ${res.file}`, 'ok'); }
        catch (err) { toast(err.message, 'bad'); }
      }

      const draw = (inv) => {
        stamp.textContent = `bijgewerkt ${inv.generated}`;
        clear(list);
        for (const section of inv.sections) {
          const holder = h('div');
          const det = h('details', { class: 'section' },
            h('summary', null, section.name, h('span', { class: 'badge', text: fmtNum(section.rows.length) }),
              h('span', { class: 'actions' }, h('button', { type: 'button', class: 'btn small', onclick: (e) => { e.preventDefault(); downloadCsv(section.rows, section.name.replace(/\W+/g, '_')); } }, icon('download'), 'CSV'))),
            holder);
          det.addEventListener('toggle', () => { if (det.open && !holder.firstChild) holder.appendChild(DataTable.auto(section.rows, { empty: 'Geen gegevens in dit onderdeel.' }).el); });
          list.appendChild(det);
        }
      };

      const load = async (refresh = false) => {
        try {
          const inv = await withBusy(card, () => api('GET', '/api/inventory' + (refresh ? '?refresh=1' : '')), 'Inventarisatie uitvoeren...');
          state.cache.inventory = inv;
          if (refresh) state.cache.overview = null;
          draw(inv);
        } catch { /* gemeld */ }
      };

      if (state.cache.inventory) draw(state.cache.inventory); else await load(false);
    },
  };

  // ---------- Mailboxen
  pages.mailboxes = {
    title: 'Mailboxen', icon: 'mailbox', group: 'Onderzoek',
    async render(root, params) {
      if (!state.status.connected) { root.appendChild(notConnectedCard()); return; }
      root.appendChild(h('p', { class: 'page-intro', text: 'Grootte, archief en laatste aanmelding per mailbox. Selecteer mailboxen om ze naar PST te exporteren.' }));

      let days = state.cache.mailboxDays || 90;
      let maxSize = 1;
      const table = new DataTable({
        key: (r) => r.PrimarySmtpAddress || r.DisplayName,
        selectable: true,
        empty: 'Geen mailboxen gevonden.',
        onSelect: (sel) => updateSelection(sel),
        columns: [
          { key: 'DisplayName', label: 'Naam' },
          { key: 'PrimarySmtpAddress', label: 'E-mailadres' },
          { key: 'RecipientTypeDetails', label: 'Type', format: (v) => h('span', { class: 'badge', text: String(v || '').replace('Mailbox', '') || '-' }) },
          { key: 'Database', label: 'Database' },
          { key: 'GrootteMB', label: 'Grootte', align: 'right', format: (v) => {
            const bar = h('span'); bar.style.width = `${Math.min(100, Math.round((Number(v) || 0) / maxSize * 100))}%`;
            return h('div', null, h('div', { text: fmtMb(v) }), h('div', { class: 'bar' }, bar));
          } },
          { key: 'Items', label: 'Items', align: 'right', format: (v) => fmtNum(v) },
          { key: 'Archief', label: 'Archief', format: (v) => v ? h('span', { class: 'badge accent', text: 'Archief' }) : '' },
          { key: 'LaatsteAanmelding', label: 'Laatste aanmelding', format: (v) => v || h('span', { class: 'muted', text: 'nooit' }) },
          { key: 'Inactief', label: 'Status', format: (v) => v ? h('span', { class: 'badge warn', text: 'Inactief' }) : h('span', { class: 'badge ok', text: 'Actief' }) },
        ],
      });

      const typeSel = h('select', { class: 'input', 'aria-label': 'Type' }, h('option', { value: '', text: 'Alle types' }));
      const inactiveOnly = h('input', { type: 'checkbox', checked: params.get('inactive') === '1' });
      const daysInput = h('input', { type: 'number', class: 'input', min: 1, max: 3650, value: days, 'aria-label': 'Dagen' });
      daysInput.classList.add('num');
      const summary = h('div', { class: 'chips' });
      const selBar = h('div', { class: 'selection-bar hidden' });

      const applyFilter = () => {
        const type = typeSel.value;
        table.setFilter((r) => (!type || r.RecipientTypeDetails === type) && (!inactiveOnly.checked || r.Inactief));
      };
      typeSel.addEventListener('change', applyFilter);
      inactiveOnly.addEventListener('change', applyFilter);

      function updateSelection(sel) {
        clear(selBar);
        selBar.classList.toggle('hidden', sel.length === 0);
        if (!sel.length) return;
        const total = sel.reduce((s, r) => s + (Number(r.GrootteMB) || 0), 0);
        append(selBar, [
          `${plural(sel.length, 'mailbox', 'mailboxen')} geselecteerd (${fmtMb(total)})`,
          h('div', { class: 'actions' },
            h('button', { type: 'button', class: 'btn small', text: 'Selectie wissen', onclick: () => { table.selected.clear(); table.render(); updateSelection([]); } }),
            h('button', { type: 'button', class: 'btn small primary', onclick: () => {
              state.prefill.identities = sel.map((r) => r.PrimarySmtpAddress || r.DisplayName);
              location.hash = '#/export';
            } }, icon('download'), 'Exporteren naar PST')),
        ]);
      }

      const card = h('div', { class: 'card' },
        h('div', { class: 'card-head' }, h('h2', { text: 'Mailboxoverzicht' }), summary, h('div', { class: 'actions' },
          exportButtons(() => table.visibleRows(), 'Mailboxen', 'Mailboxoverzicht'),
          h('button', { type: 'button', class: 'btn small', onclick: () => load() }, icon('refresh'), 'Vernieuwen'))),
        h('div', { class: 'toolbar' },
          searchBox((v) => table.setSearch(v), 'Zoek op naam, adres, database...'),
          typeSel,
          h('label', { class: 'check' }, inactiveOnly, 'Alleen inactief'),
          h('label', { class: 'check' }, 'Inactief na', daysInput, 'dagen'),
          h('button', { type: 'button', class: 'btn small', text: 'Toepassen', onclick: () => { days = Number(daysInput.value) || 90; load(); } })),
        selBar,
        h('div', { class: 'card-body flush' }, table.el));
      root.appendChild(card);

      const draw = (rows) => {
        maxSize = Math.max(1, ...rows.map((r) => Number(r.GrootteMB) || 0));
        const types = [...new Set(rows.map((r) => r.RecipientTypeDetails).filter(Boolean))].sort();
        const current = typeSel.value;
        clear(typeSel).appendChild(h('option', { value: '', text: 'Alle types' }));
        types.forEach((t) => typeSel.appendChild(h('option', { value: t, text: t, selected: t === current })));
        const total = rows.reduce((s, r) => s + (Number(r.GrootteMB) || 0), 0);
        const inactive = rows.filter((r) => r.Inactief).length;
        clear(summary);
        append(summary, [h('span', { class: 'badge', text: plural(rows.length, 'mailbox', 'mailboxen') }), h('span', { class: 'badge accent', text: fmtMb(total) }), h('span', { class: 'badge warn', text: `${fmtNum(inactive)} inactief` })]);
        table.setRows(rows);
        applyFilter();
      };

      const load = async () => {
        try {
          const rows = await withBusy(card, () => api('GET', `/api/mailboxes?inactiveDays=${days}`), 'Mailboxgegevens ophalen...');
          state.cache.mailboxes = rows;
          state.cache.mailboxDays = days;
          draw(rows);
        } catch { /* gemeld */ }
      };

      if (state.cache.mailboxes) draw(state.cache.mailboxes); else await load();
    },
  };

  // ---------- Public folders
  pages.publicfolders = {
    title: 'Public folders', icon: 'folder', group: 'Onderzoek',
    async render(root) {
      if (!state.status.connected) { root.appendChild(notConnectedCard()); return; }
      root.appendChild(h('p', { class: 'page-intro', text: 'Alle public folders met aantal items en grootte. Selecteer mappen om ze via Outlook naar PST te exporteren.' }));
      const selBar = h('div', { class: 'selection-bar hidden' });
      const summary = h('div', { class: 'chips' });
      const table = new DataTable({
        key: (r) => r.Map, selectable: true, empty: 'Geen public folders gevonden.',
        onSelect: (sel) => {
          clear(selBar);
          selBar.classList.toggle('hidden', !sel.length);
          if (!sel.length) return;
          append(selBar, [`${plural(sel.length, 'map', 'mappen')} geselecteerd`, h('div', { class: 'actions' },
            h('button', { type: 'button', class: 'btn small primary', onclick: () => { state.prefill.folders = sel.map((r) => r.Map); location.hash = '#/export'; } }, icon('download'), 'Exporteren naar PST'))]);
        },
        columns: [
          { key: 'Map', label: 'Map', mono: true },
          { key: 'Items', label: 'Items', align: 'right', format: (v) => fmtNum(v) },
          { key: 'GrootteMB', label: 'Grootte', align: 'right', format: (v) => fmtMb(v) },
          { key: 'LaatsteWijziging', label: 'Laatste wijziging' },
          { key: 'MailEnabled', label: 'E-mailadres', format: (v) => v ? h('span', { class: 'badge accent', text: v }) : '' },
          { key: 'ContentMailbox', label: 'Content-mailbox' },
        ],
      });
      const card = h('div', { class: 'card' },
        h('div', { class: 'card-head' }, h('h2', { text: 'Public folders' }), summary, h('div', { class: 'actions' },
          exportButtons(() => table.visibleRows(), 'PublicFolders', 'Public folders'),
          h('button', { type: 'button', class: 'btn small', onclick: () => load() }, icon('refresh'), 'Vernieuwen'))),
        h('div', { class: 'toolbar' }, searchBox((v) => table.setSearch(v), 'Zoek op map of adres...')),
        selBar,
        h('div', { class: 'card-body flush' }, table.el));
      root.appendChild(card);

      const draw = (rows) => {
        const total = rows.reduce((s, r) => s + (Number(r.GrootteMB) || 0), 0);
        clear(summary);
        append(summary, [h('span', { class: 'badge', text: plural(rows.length, 'map', 'mappen') }), h('span', { class: 'badge accent', text: fmtMb(total) })]);
        table.setRows(rows);
      };
      const load = async () => {
        try {
          const rows = await withBusy(card, () => api('GET', '/api/publicfolders'), 'Public folders ophalen...');
          state.cache.publicfolders = rows;
          draw(rows);
        } catch { /* gemeld */ }
      };
      if (state.cache.publicfolders) draw(state.cache.publicfolders); else await load();
    },
  };

  // ---------- Uitfaseringscontrole
  pages.readiness = {
    title: 'Uitfaseringscontrole', icon: 'shield', group: 'Onderzoek',
    async render(root) {
      if (!state.status.connected) { root.appendChild(notConnectedCard()); return; }
      root.appendChild(h('p', { class: 'page-intro', text: 'Controleert of een server veilig kan worden uitgefaseerd: wat blokkeert de de-installatie, wat moet nog worden nagelopen, en hoe los je het op. Er wordt niets gewijzigd.' }));
      const servers = await loadServers().catch((e) => { toast(e.message, 'bad'); return []; });
      const sel = serverSelect(servers);
      const out = h('div');
      const card = h('div', { class: 'card' },
        h('div', { class: 'card-head' }, h('h2', { text: 'Server kiezen' })),
        h('div', { class: 'card-body' }, h('div', { class: 'form-row' },
          h('div', { class: 'field' }, h('label', { text: 'Exchange-server' }), sel),
          h('div', { class: 'field' }, h('span', { class: 'label', text: '\u00a0' }),
            h('button', { type: 'button', class: 'btn primary', onclick: run }, icon('shield'), 'Controle uitvoeren')))));
      root.appendChild(card);
      root.appendChild(out);

      async function run() {
        if (!sel.value) { toast('Kies een server.', 'warn'); return; }
        try {
          const res = await withBusy(card, () => api('POST', '/api/readiness', { server: sel.value }), `Controle van ${sel.value}...`);
          state.cache.readiness = res;
          draw(res);
        } catch { /* gemeld */ }
      }

      function draw(res) {
        clear(out);
        if (res.server) sel.value = res.server;
        const ok = res.blockers === 0;
        out.appendChild(h('div', { class: 'verdict ' + (ok ? 'ok' : 'bad') },
          h('div', { class: 'icon' }, icon(ok ? 'check' : 'x')),
          h('div', null,
            h('h3', { text: ok ? `${res.server} kan worden uitgefaseerd` : `${res.server} kan nog niet worden uitgefaseerd` }),
            h('p', { text: ok
              ? `Geen blokkerende punten. Loop de ${plural(res.warnings, 'waarschuwing', 'waarschuwingen')} na voordat je Exchange verwijdert.`
              : `${plural(res.blockers, 'blokkerend punt', 'blokkerende punten')} en ${plural(res.warnings, 'waarschuwing', 'waarschuwingen')}. Los de blokkerende punten eerst op.` }))));

        let filter = '';
        const list = h('div', { class: 'checks' });
        const chips = h('div', { class: 'chips' });
        const counts = { '': res.checks.length };
        res.checks.forEach((c) => { counts[c.Status] = (counts[c.Status] || 0) + 1; });
        const drawList = () => {
          clear(list);
          const order = { Blokkerend: 0, Waarschuwing: 1, Info: 2, OK: 3 };
          res.checks.filter((c) => !filter || c.Status === filter)
            .sort((a, b) => (order[a.Status] ?? 9) - (order[b.Status] ?? 9))
            .forEach((c) => list.appendChild(h('div', { class: 'check-item' },
              h('div', null, statusBadge(c.Status)),
              h('div', null, h('h4', { text: c.Check }),
                c.Details ? h('div', { class: 'details', text: c.Details }) : null,
                c.Oplossing && c.Status !== 'OK' ? h('div', { class: 'fix' }, h('strong', { text: 'Oplossing: ' }), c.Oplossing) : null))));
          clear(chips);
          [['', 'Alles'], ['Blokkerend', 'Blokkerend'], ['Waarschuwing', 'Waarschuwing'], ['Info', 'Info'], ['OK', 'OK']]
            .filter(([k]) => k === '' || counts[k])
            .forEach(([k, label]) => chips.appendChild(h('button', { type: 'button', class: 'chip' + (filter === k ? ' active' : ''), text: `${label} (${counts[k] || 0})`, onclick: () => { filter = k; drawList(); } })));
        };
        drawList();
        out.appendChild(h('div', { class: 'card' },
          h('div', { class: 'card-head' }, h('h2', { text: 'Resultaten' }), chips, h('div', { class: 'actions' }, exportButtons(() => res.checks, `Uitfasering_${res.server}`, `Uitfaseringscontrole ${res.server}`))),
          list));
      }

      if (state.cache.readiness) draw(state.cache.readiness);
    },
  };

  // ---------- PST-export
  pages.export = {
    title: 'PST-export', icon: 'download', group: 'Exporteren',
    async render(root) {
      root.appendChild(h('p', { class: 'page-intro', text: 'Exporteer mailboxen (met online archief) en public folders naar PST-bestanden. In simulatiemodus zie je eerst precies welke bestanden er komen.' }));
      const connected = state.status.connected;

      // Mailboxen
      const share = h('input', { type: 'text', placeholder: '\\\\fileserver\\pst$', value: state.cache.share || '' });
      const idents = h('textarea', { placeholder: 'jan@contoso.com\ninfo@contoso.com' });
      idents.value = state.prefill.identities.join('\n');
      const archive = h('input', { type: 'checkbox', checked: true });
      const modeName = 'mbx-mode';
      const mode = (value, label, checked) => h('label', null, h('input', { type: 'radio', name: modeName, value, checked }), label);
      const segmented = h('div', { class: 'segmented' }, mode('selection', 'Selectie', true), mode('database', 'Per database', false), mode('all', 'Alle mailboxen', false));
      const dbList = h('div', { class: 'checklist' }, h('span', { class: 'muted', text: 'Databases laden...' }));
      const identField = h('div', { class: 'field' }, h('label', { text: 'Mailboxen (een per regel of gescheiden door komma\'s)' }), idents,
        h('span', { class: 'hint', text: 'Tip: selecteer mailboxen op de pagina Mailboxen en kies "Exporteren naar PST".' }));
      const dbField = h('div', { class: 'field hidden' }, h('span', { class: 'label', text: 'Databases' }), dbList);
      const allField = h('div', { class: 'callout warn hidden' }, icon('warn'), h('div', null, 'Alle gebruikers-, gedeelde en resourcemailboxen worden geëxporteerd. Controleer vooraf of de share voldoende ruimte heeft (zie Mailboxen voor de totale grootte).'));
      segmented.addEventListener('change', () => {
        const v = segmented.querySelector('input:checked').value;
        identField.classList.toggle('hidden', v !== 'selection');
        dbField.classList.toggle('hidden', v !== 'database');
        allField.classList.toggle('hidden', v !== 'all');
      });
      const mbxResult = h('div', { class: 'result' });
      const mbxCard = h('div', { class: 'card export-zone' },
        h('div', { class: 'card-head' }, h('h2', { text: 'Mailboxen exporteren' })),
        h('div', { class: 'card-body' }, h('div', { class: 'form' },
          h('div', { class: 'field' }, h('label', { text: 'UNC-share voor de PST-bestanden' }), share,
            h('span', { class: 'hint', text: 'Exchange schrijft de PST zelf weg: de groep Exchange Trusted Subsystem heeft lees- en schrijfrechten nodig. Rol vereist: Mailbox Import Export.' })),
          h('div', { class: 'field' }, h('span', { class: 'label', text: 'Welke mailboxen' }), segmented),
          identField, dbField, allField,
          h('label', { class: 'check' }, archive, 'Ook online archieven exporteren (<alias>_Archief.pst)'),
          h('div', null, actionButton('export', { sim: 'Export simuleren', live: 'Export starten' }, runMailboxExport)),
          mbxResult)));
      if (!connected) mbxCard.querySelector('.card-body').prepend(notConnectedCard());

      // Public folders
      const pst = h('input', { type: 'text', placeholder: 'D:\\PST\\PublicFolders.pst', value: state.cache.pfPath || '' });
      const folders = h('textarea', { placeholder: '\\  (alles)\n\\Afdelingen\\Verkoop' });
      folders.value = state.prefill.folders.length ? state.prefill.folders.join('\n') : '\\';
      const pfResult = h('div', { class: 'result' });
      const pfCard = h('div', { class: 'card export-zone' },
        h('div', { class: 'card-head' }, h('h2', { text: 'Public folders exporteren' })),
        h('div', { class: 'card-body' }, h('div', { class: 'form' },
          h('div', { class: 'callout' }, icon('info'), h('div', null, 'Exchange heeft hiervoor geen cmdlet; de export loopt via ', h('strong', { text: 'Outlook' }),
            ' op de computer waar deze interface draait. Outlook moet een profiel hebben met leesrechten op de public folders. Grote mappen kunnen lang duren.')),
          h('div', { class: 'field' }, h('label', { text: 'PST-bestand of map' }), pst, h('span', { class: 'hint', text: 'Bij een map wordt PublicFolders_<datum>.pst gebruikt.' })),
          h('div', { class: 'field' }, h('label', { text: 'Mappen (een per regel, \\ = alles)' }), folders),
          h('div', null, actionButton('export', { sim: 'Export simuleren', live: 'Export starten' }, runPfExport)),
          pfResult)));

      root.appendChild(h('div', { class: 'grid two' }, mbxCard, pfCard));

      // Voortgang
      const statusTable = new DataTable({
        empty: 'Geen PST-exportaanvragen gevonden.',
        columns: [
          { key: 'Aanvraag', label: 'Aanvraag' },
          { key: 'Mailbox', label: 'Mailbox' },
          { key: 'Status', label: 'Status', format: (v) => statusBadge(v) },
          { key: 'Procent', label: 'Voortgang', format: (v, r) => {
            const bar = h('span'); bar.style.width = `${Number(v) || 0}%`;
            return h('div', null, h('div', { class: 'bar ' + (r.Status === 'Failed' ? 'bad' : r.Status === 'Completed' ? 'ok' : '') }, bar), h('small', { class: 'muted', text: `${fmtNum(v)}%` }));
          } },
          { key: 'Overgezet', label: 'Overgezet' },
          { key: 'Bestand', label: 'Bestand', mono: true },
          { key: 'Melding', label: 'Melding', wrap: true },
        ],
      });
      const auto = h('input', { type: 'checkbox' });
      const statusCard = h('div', { class: 'card' },
        h('div', { class: 'card-head' }, h('h2', { text: 'Voortgang mailboxexports' }), h('div', { class: 'actions' },
          h('label', { class: 'check' }, auto, 'Elke 20 seconden vernieuwen'),
          h('button', { type: 'button', class: 'btn small', onclick: () => loadStatus() }, icon('refresh'), 'Vernieuwen'))),
        h('div', { class: 'card-body flush' }, statusTable.el));
      root.appendChild(statusCard);

      const loadStatus = async (quiet = false) => {
        if (!state.status.connected) return;
        try {
          const rows = quiet ? await api('GET', '/api/export/status') : await withBusy(statusCard, () => api('GET', '/api/export/status'), 'Status ophalen...', null);
          statusTable.setRows(rows);
        } catch { /* gemeld */ }
      };
      auto.addEventListener('change', () => {
        state.timers.forEach(clearInterval); state.timers = [];
        if (auto.checked) state.timers.push(setInterval(() => loadStatus(true), 20000));
      });

      if (connected) {
        loadDatabases().then((dbs) => {
          clear(dbList);
          dbs.forEach((d) => dbList.appendChild(h('label', { class: 'check' }, h('input', { type: 'checkbox', value: d }), d)));
          if (!dbs.length) dbList.appendChild(h('span', { class: 'muted', text: 'Geen databases gevonden.' }));
        }).catch((e) => { clear(dbList).appendChild(h('span', { class: 'muted', text: e.message })); });
        loadStatus(true);
      }

      function resultTable(target, rows, cols) {
        clear(target);
        const sims = rows.filter((r) => r.Status === 'Simulatie').length;
        const failed = rows.filter((r) => r.Status === 'Mislukt').length;
        append(target, [
          h('div', { class: 'summary-line' },
            sims ? h('span', { class: 'badge accent', text: `Simulatie: ${plural(sims, 'bestand', 'bestanden')}` }) : null,
            rows.length - sims - failed ? h('span', { class: 'badge ok', text: `${fmtNum(rows.length - sims - failed)} gestart` }) : null,
            failed ? h('span', { class: 'badge bad', text: `${fmtNum(failed)} mislukt` }) : null),
          new DataTable({ rows, columns: cols, empty: 'Niets geselecteerd.' }).el,
        ]);
      }

      async function runMailboxExport() {
        const m = segmented.querySelector('input:checked').value;
        const body = {
          mode: m,
          filePath: share.value.trim(),
          includeArchive: archive.checked,
          identities: idents.value,
          databases: [...dbList.querySelectorAll('input:checked')].map((i) => i.value),
          simulate: simulate(),
        };
        if (!/^\\\\[^\\]+\\[^\\]+/.test(body.filePath)) { toast('Geef een UNC-pad op, bijvoorbeeld \\\\fileserver\\pst$.', 'warn'); share.focus(); return; }
        if (state.live && !(await dialog({ title: 'PST-export starten?', message: 'Er worden exportaanvragen aangemaakt; de Exchange-server schrijft de PST-bestanden naar de share.', confirmLabel: 'Export starten', iconName: 'download' }))) return;
        state.cache.share = body.filePath;
        try {
          const rows = await withBusy(mbxCard, () => api('POST', '/api/export/mailboxes', body), state.live ? 'Exportaanvragen aanmaken...' : 'Export simuleren...');
          resultTable(mbxResult, rows, [
            { key: 'Mailbox', label: 'Mailbox' }, { key: 'Soort', label: 'Soort' },
            { key: 'Bestand', label: 'Bestand', mono: true }, { key: 'Status', label: 'Status', format: statusBadge }, { key: 'Fout', label: 'Fout', wrap: true },
          ]);
          if (!body.simulate) { state.prefill.identities = []; loadStatus(true); }
        } catch { /* gemeld */ }
      }

      async function runPfExport() {
        const body = { filePath: pst.value.trim(), folders: folders.value, simulate: simulate() };
        if (!body.filePath) { toast('Geef een PST-bestand of map op.', 'warn'); pst.focus(); return; }
        if (state.live && !(await dialog({ title: 'Public folders exporteren?', message: 'Outlook kopieert de gekozen mappen naar de PST. Dit kan lang duren; de interface wacht tot het klaar is.', confirmLabel: 'Export starten', iconName: 'download' }))) return;
        state.cache.pfPath = body.filePath;
        try {
          const rows = await withBusy(pfCard, () => api('POST', '/api/export/publicfolders', body), state.live ? 'Public folders kopieren via Outlook...' : 'Export simuleren...');
          resultTable(pfResult, rows, [
            { key: 'Map', label: 'Map', mono: true }, { key: 'Items', label: 'Items', align: 'right', format: (v) => fmtNum(v) },
            { key: 'Bestand', label: 'Bestand', mono: true }, { key: 'Status', label: 'Status', format: statusBadge }, { key: 'Fout', label: 'Fout', wrap: true },
          ]);
          if (!body.simulate) state.prefill.folders = [];
        } catch { /* gemeld */ }
      }
    },
  };

  // ---------- Opruimen
  pages.cleanup = {
    title: 'Opruimen', icon: 'trash', group: 'Opruimen',
    async render(root) {
      if (!state.status.connected) { root.appendChild(notConnectedCard()); return; }
      root.appendChild(h('p', { class: 'page-intro', text: 'Ruim oude logbestanden, afgeronde aanvragen, losgekoppelde mailboxen en verlopen certificaten op. Draai altijd eerst een simulatie; zet daarna de LIVE-modus aan om echt uit te voeren.' }));
      const servers = await loadServers().catch((e) => { toast(e.message, 'bad'); return []; });

      const card = (title, desc, fields, button, result) => h('div', { class: 'card danger-zone' },
        h('div', { class: 'card-head' }, h('h2', { text: title })),
        h('div', { class: 'card-body' }, h('p', { class: 'desc', text: desc }), h('div', { class: 'form' }, fields, h('div', null, button)), result));

      const run = async (cardEl, path, body, what, render) => {
        if (!(await confirmDestructive(what))) return;
        try {
          const res = await withBusy(cardEl, () => api('POST', path, { ...body, simulate: simulate(), confirm: state.live ? 'JA' : undefined }), state.live ? 'Bezig met opruimen...' : 'Simuleren...');
          render(res);
          if (state.live) { state.cache.overview = null; state.cache.inventory = null; }
        } catch { /* gemeld */ }
      };

      const tableResult = (target, rows, columns, doneKey) => {
        clear(target);
        const done = doneKey ? rows.filter((r) => r[doneKey]).length : 0;
        append(target, [
          h('div', { class: 'summary-line' },
            h('span', { class: 'badge', text: plural(rows.length, 'item', 'items') + ' gevonden' }),
            state.live ? h('span', { class: 'badge ok', text: `${fmtNum(done)} verwijderd` }) : h('span', { class: 'badge accent', text: 'Simulatie: niets gewijzigd' })),
          rows.length ? new DataTable({ rows, columns }).el : null,
        ]);
      };

      // Logbestanden
      const logServer = serverSelect(servers);
      const logDays = h('input', { type: 'number', min: 1, max: 3650, value: 14 });
      const logResult = h('div', { class: 'result' });
      const logCard = card('Logbestanden', 'Diagnostische logs van Exchange (Logging, ETL-traces) en IIS ouder dan het opgegeven aantal dagen. Transactielogs van databases worden nooit aangeraakt.',
        h('div', { class: 'form-row' }, h('div', { class: 'field' }, h('label', { text: 'Server' }), logServer), h('div', { class: 'field' }, h('label', { text: 'Ouder dan (dagen)' }), logDays)),
        actionButton('destructive', { sim: 'Simuleren', live: 'Logbestanden verwijderen' }, () => run(logCard, '/api/clean/logs', { server: logServer.value, days: Number(logDays.value) || 14 },
          `Logbestanden ouder dan ${logDays.value} dagen op ${logServer.value} verwijderen`, (res) => {
            clear(logResult);
            if (res.simulated) {
              append(logResult, [h('div', { class: 'summary-line' }, h('span', { class: 'badge accent', text: 'Simulatie' }), `${plural(res.files, 'bestand', 'bestanden')}, ${fmtMb(res.sizeMb)} kan worden vrijgemaakt`),
                res.folders.length ? new DataTable({ rows: res.folders, columns: [{ key: 'Map', label: 'Map', mono: true }, { key: 'Bestanden', label: 'Bestanden', align: 'right', format: (v) => fmtNum(v) }, { key: 'MB', label: 'Grootte', align: 'right', format: (v) => fmtMb(v) }] }).el : null]);
            } else {
              const s = res.summary || { Verwijderd: 0, Mislukt: 0, VrijgemaaktMB: 0 };
              append(logResult, h('div', { class: 'callout ok' }, icon('check'), h('div', null, `${plural(s.Verwijderd, 'bestand', 'bestanden')} verwijderd, ${fmtMb(s.VrijgemaaktMB)} vrijgemaakt.`, s.Mislukt ? ` ${fmtNum(s.Mislukt)} bestand(en) overgeslagen (in gebruik).` : '')));
            }
          })),
        logResult);

      // Aanvragen
      const types = [['MoveRequest', 'Verplaatsaanvragen'], ['MigrationBatch', 'Migratiebatches'], ['ExportRequest', 'Exportaanvragen'], ['ImportRequest', 'Importaanvragen'], ['RestoreRequest', 'Herstelaanvragen']];
      const typeChecks = types.map(([v, l]) => h('label', { class: 'check' }, h('input', { type: 'checkbox', value: v, checked: true }), l));
      const failed = h('input', { type: 'checkbox' });
      const reqResult = h('div', { class: 'result' });
      const reqCard = card('Afgeronde aanvragen', 'Verwijdert afgeronde verplaats-, export-, import- en herstelaanvragen en migratiebatches. Lopende aanvragen worden nooit aangeraakt.',
        [h('div', { class: 'checklist' }, typeChecks), h('label', { class: 'check' }, failed, 'Ook mislukte aanvragen')],
        actionButton('destructive', { sim: 'Simuleren', live: 'Aanvragen verwijderen' }, () => run(reqCard, '/api/clean/requests',
          { types: typeChecks.map((l) => l.querySelector('input')).filter((i) => i.checked).map((i) => i.value), includeFailed: failed.checked },
          'Afgeronde aanvragen verwijderen', (rows) => tableResult(reqResult, rows, [
            { key: 'Soort', label: 'Soort' }, { key: 'Naam', label: 'Naam' }, { key: 'Status', label: 'Status', format: statusBadge },
            { key: 'Verwijderd', label: 'Verwijderd', format: removedBadge }, { key: 'Fout', label: 'Fout', wrap: true }], 'Verwijderd'))),
        reqResult);

      // Losgekoppelde mailboxen
      const discDays = h('input', { type: 'number', min: 0, max: 3650, value: 30 });
      const discResult = h('div', { class: 'result' });
      const discCard = card('Losgekoppelde mailboxen', 'Verwijdert disabled en soft-deleted mailboxen DEFINITIEF uit de databases. Alleen terug te halen uit een back-up.',
        h('div', { class: 'form-row' }, h('div', { class: 'field' }, h('label', { text: 'Losgekoppeld langer dan (dagen)' }), discDays)),
        actionButton('destructive', { sim: 'Simuleren', live: 'Definitief verwijderen' }, () => run(discCard, '/api/clean/disconnected', { days: Number(discDays.value) || 0 },
          'Losgekoppelde mailboxen DEFINITIEF verwijderen', (rows) => tableResult(discResult, rows, [
            { key: 'DisplayName', label: 'Naam' }, { key: 'Database', label: 'Database' }, { key: 'Reden', label: 'Reden', format: (v) => h('span', { class: 'badge', text: v }) },
            { key: 'DisconnectDate', label: 'Losgekoppeld' }, { key: 'Verwijderd', label: 'Verwijderd', format: removedBadge }, { key: 'Fout', label: 'Fout', wrap: true }], 'Verwijderd'))),
        discResult);

      // Certificaten
      const certServer = serverSelect(servers, { allowAll: true });
      const assigned = h('input', { type: 'checkbox' });
      const certResult = h('div', { class: 'result' });
      const certCard = card('Verlopen certificaten', 'Verwijdert verlopen certificaten. Certificaten die nog aan IIS/SMTP gekoppeld zijn en het OAuth-certificaat worden standaard overgeslagen.',
        [h('div', { class: 'form-row' }, h('div', { class: 'field' }, h('label', { text: 'Server' }), certServer)), h('label', { class: 'check' }, assigned, 'Ook certificaten die nog aan een dienst gekoppeld zijn')],
        actionButton('destructive', { sim: 'Simuleren', live: 'Certificaten verwijderen' }, () => run(certCard, '/api/clean/certificates', { server: certServer.value, includeAssigned: assigned.checked },
          'Verlopen certificaten verwijderen', (rows) => tableResult(certResult, rows, [
            { key: 'Server', label: 'Server' }, { key: 'Subject', label: 'Onderwerp', wrap: true }, { key: 'NotAfter', label: 'Verlopen op' }, { key: 'Services', label: 'Diensten' },
            { key: 'Verwijderd', label: 'Verwijderd', format: removedBadge }, { key: 'Opmerking', label: 'Opmerking', wrap: true }], 'Verwijderd'))),
        certResult);

      root.appendChild(h('div', { class: 'clean-grid' }, logCard, reqCard, discCard, certCard));
    },
  };

  // ---------- Logboek
  pages.log = {
    title: 'Logboek', icon: 'log', group: 'Opruimen',
    async render(root) {
      root.appendChild(h('p', { class: 'page-intro' }, 'Alle acties van deze sessie. Het volledige logbestand staat op: ', h('span', { class: 'mono', text: state.status.logFile || '-' })));
      const table = new DataTable({
        empty: 'Nog geen logregels.',
        columns: [
          { key: 'Tijd', label: 'Tijd', mono: true },
          { key: 'Niveau', label: 'Niveau', format: statusBadge },
          { key: 'Bericht', label: 'Bericht', wrap: true },
        ],
      });
      const card = h('div', { class: 'card' },
        h('div', { class: 'card-head' }, h('h2', { text: 'Logboek' }), h('div', { class: 'actions' },
          h('button', { type: 'button', class: 'btn small', onclick: () => load() }, icon('refresh'), 'Vernieuwen'))),
        h('div', { class: 'toolbar' }, searchBox((v) => table.setSearch(v), 'Zoeken in logboek...')),
        h('div', { class: 'card-body flush' }, table.el));
      root.appendChild(card);
      const load = async () => { try { table.setRows(await api('GET', '/api/log')); } catch (e) { toast(e.message, 'bad'); } };
      await load();
      state.timers.push(setInterval(load, 5000));
    },
  };

  const ORDER = ['dashboard', 'inventory', 'mailboxes', 'publicfolders', 'readiness', 'export', 'cleanup', 'log'];

  // ------------------------------------------------------------------ navigatie
  function buildNav() {
    const nav = clear($('#nav'));
    let group = null;
    for (const key of ORDER) {
      const page = pages[key];
      if (page.group !== group) { group = page.group; nav.appendChild(h('div', { class: 'nav-group', text: group })); }
      nav.appendChild(h('a', { href: `#/${key}`, dataset: { page: key } }, icon(page.icon), page.title));
    }
  }

  async function route() {
    state.timers.forEach(clearInterval);
    state.timers = [];
    const hash = location.hash.replace(/^#\/?/, '');
    const [name, query] = hash.split('?');
    const key = pages[name] ? name : 'dashboard';
    const page = pages[key];
    document.querySelectorAll('#nav a').forEach((a) => a.classList.toggle('active', a.dataset.page === key));
    $('#page-title').textContent = page.title;
    document.title = `${page.title} - DecomExch`;
    const content = clear($('#content'));
    try {
      await page.render(content, new URLSearchParams(query || ''));
    } catch (err) {
      content.appendChild(h('div', { class: 'callout bad' }, icon('warn'), h('div', null, err.message)));
    }
  }

  // ------------------------------------------------------------------ verbinding
  function drawStatus() {
    const s = state.status;
    $('#conn-dot').className = 'dot ' + (s.connected ? 'ok' : 'bad');
    $('#conn-text').textContent = s.connected ? `Verbonden${s.organization ? ' \u00b7 ' + s.organization : ''}` : 'Niet verbonden';
    const via = [s.exchangeServer ? `server ${s.exchangeServer}` : (s.connected ? 'lokale Exchange Management Shell' : ''), s.account ? `als ${s.account}` : ''].filter(Boolean).join(' ');
    $('#conn-pill').title = s.connected ? `Verbonden via ${via}. Klik om te wisselen.` : 'Klik om te verbinden met Exchange.';
    $('#foot-user').textContent = `${s.account || s.user || ''}${s.computer ? ' @ ' + s.computer : ''}  \u00b7  v${s.version || ''}`;
  }

  async function refreshStatus() {
    state.status = await api('GET', '/api/status');
    drawStatus();
  }

  async function openConnectDialog() {
    const s = state.status;
    const server = h('input', { type: 'text', class: 'input', placeholder: 'ex01.contoso.local', value: s.exchangeServer || '' });
    const accountHint = s.account
      ? `Er wordt verbonden als ${s.account} (opgegeven met -Credential bij het starten).`
      : 'Er wordt verbonden met je huidige Windows-account. Voor een ander account: start opnieuw met -Credential.';
    const auth = h('select', { class: 'input', 'aria-label': 'Aanmeldmethode' },
      ['Kerberos', 'Negotiate', 'Basic'].map((m) => h('option', { value: m, text: m, selected: m === (s.authentication || 'Kerberos') })));
    const body = h('div', { class: 'form' },
      h('div', { class: 'field' }, h('label', { text: 'Exchange-server (leeg = lokale Exchange Management Shell)' }), server,
        h('span', { class: 'hint', text: `Verbinding via http://<server>/PowerShell. Gebruik de volledige servernaam. ${accountHint}` })),
      h('div', { class: 'field' }, h('label', { text: 'Aanmeldmethode' }), auth,
        h('span', { class: 'hint', text: 'Gebruik Kerberos: dat is wat Exchange standaard accepteert, en het heeft een bereikbare domeincontroller nodig. Negotiate (NTLM) en Basic worden door Exchange standaard geweigerd (HTTP 400), tenzij ze op de server zijn ingeschakeld.' })));
    const current = s.connected
      ? `Nu verbonden${s.organization ? ' met ' + s.organization : ''}${s.exchangeServer ? ' via ' + s.exchangeServer : ''}${s.account ? ' als ' + s.account : ''}.`
      : 'Maak verbinding om de organisatie te onderzoeken.';
    const ok = await dialog({ title: 'Verbinden met Exchange', message: current, iconName: 'plug', confirmLabel: 'Verbinden', body });
    if (!ok) return;
    const t = h('div', { class: 'busy fixed' }, h('div', { class: 'busy-inner' }, h('div', { class: 'spinner' }), 'Verbinden...'));
    document.body.appendChild(t);
    try {
      await api('POST', '/api/connect', { server: server.value.trim(), authentication: auth.value });
      state.cache = {}; state.servers = null; state.databases = null;
      await refreshStatus();
      toast(state.status.connected ? 'Verbonden met Exchange.' : 'Verbinden is niet gelukt.', state.status.connected ? 'ok' : 'bad');
      route();
    } catch (err) { toast(err.message, 'bad'); }
    finally { t.remove(); }
  }

  // ------------------------------------------------------------------ thema, modus, afsluiten
  function applyTheme(theme) {
    if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;
    else delete document.documentElement.dataset.theme;
    const btn = clear($('#btn-theme'));
    append(btn, [icon('moon'), { light: 'Thema: licht', dark: 'Thema: donker' }[theme] || 'Thema: automatisch']);
  }
  function loadTheme() { try { return localStorage.getItem('decomexch-theme') || 'auto'; } catch { return 'auto'; } }
  function saveTheme(t) { try { localStorage.setItem('decomexch-theme', t); } catch { /* niet beschikbaar */ } }

  async function setLive(on) {
    if (on) {
      const ok = await dialog({
        title: 'LIVE-modus inschakelen?',
        message: 'Exports en opruimacties worden dan echt uitgevoerd op de Exchange-omgeving. Opruimacties vragen daarna nog om bevestiging met JA.',
        danger: true, confirmLabel: 'LIVE-modus aan',
      });
      if (!ok) { $('#live-toggle').checked = false; return; }
    }
    state.live = on;
    $('#live-toggle').checked = on;
    document.body.classList.toggle('live', on);
    updateActionButtons();
  }

  async function shutdown() {
    const ok = await dialog({ title: 'Webinterface afsluiten?', message: 'De webserver in PowerShell stopt; lopende Exchange-exports gaan gewoon door.', confirmLabel: 'Afsluiten', iconName: 'power' });
    if (!ok) return;
    try { await api('POST', '/api/shutdown'); } catch { /* server is al weg */ }
    showSplash('power', 'Webinterface gestopt', 'Je kunt dit tabblad sluiten. Start opnieuw met .\\DecomExch.ps1 -Action Web');
  }

  function showSplash(iconName, title, text) {
    $('#app').classList.add('hidden');
    const splash = clear($('#splash'));
    splash.classList.remove('hidden');
    splash.appendChild(h('div', { class: 'card' }, h('div', { class: 'splash-icon' }, icon(iconName)), h('h2', { text: title }), h('p', { class: 'muted', text })));
  }

  // ------------------------------------------------------------------ start
  async function init() {
    const params = new URLSearchParams(location.search);
    const fromUrl = params.get('token');
    try {
      if (fromUrl) sessionStorage.setItem('decomexch-token', fromUrl);
      state.token = fromUrl || sessionStorage.getItem('decomexch-token');
    } catch { state.token = fromUrl; }
    if (fromUrl) history.replaceState(null, '', location.pathname + location.hash);

    let theme = loadTheme();
    applyTheme(theme);
    $('#btn-theme').addEventListener('click', () => {
      theme = { auto: 'light', light: 'dark', dark: 'auto' }[theme] || 'auto';
      saveTheme(theme); applyTheme(theme);
    });
    append($('#btn-shutdown'), [icon('power'), 'Afsluiten']);
    $('#btn-shutdown').addEventListener('click', shutdown);
    $('#conn-pill').addEventListener('click', openConnectDialog);
    $('#live-toggle').addEventListener('change', (e) => setLive(e.target.checked));

    if (!state.token) {
      showSplash('warn', 'Geen sessietoken', 'Open de webinterface via de link die in de PowerShell-console wordt getoond.');
      return;
    }
    try {
      await refreshStatus();
    } catch (err) {
      showSplash('warn', 'Geen verbinding met DecomExch', err.message);
      return;
    }
    $('#app').classList.remove('hidden');
    buildNav();
    window.addEventListener('hashchange', route);
    await route();
  }

  init();
})();
