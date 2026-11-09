/*
 * MelonThump admin page (design doc 2.0 §2 item 7, §7 item 11).
 * Vanilla ES2020, no framework, no build step, no remote resources.
 *
 * A pure client of the same-origin /api/admin/** REST API. It holds no
 * data and no credentials: in production Cloudflare Access in front of
 * /admin/ and /api/admin/ authenticates the owner (its session cookie
 * rides along on these same-origin requests).
 *
 * Every server-provided string is rendered through text nodes
 * (textContent / createTextNode), never as HTML: notes and reasons are
 * user-generated text.
 */
(function () {
  'use strict';

  const API = '/api/admin';
  const THRESHOLD = 30; // complete approved samples needed before modeling (design §5)
  const LIST_LIMIT = 200; // the admin list endpoints cap at 200

  const state = {
    disabled: false,
    contributors: [], // last full contributor list (for names in filters)
    contribFilter: '',
    sampleFilter: { status: '', contributorId: '' },
    drawer: null, // { kind: 'contributor'|'sample', id }
  };

  // ---------------------------------------------------------------- DOM helpers

  /** h('div', {class: 'x', onclick: fn, title: 't'}, child, 'text', [more]) — strings become text nodes. */
  function h(tag, props) {
    const el = document.createElement(tag);
    if (props) {
      Object.keys(props).forEach(function (k) {
        const v = props[k];
        if (v === null || v === undefined || v === false) return;
        if (k === 'class') el.className = v;
        else if (k === 'text') el.textContent = v;
        else if (k.slice(0, 2) === 'on' && typeof v === 'function') el.addEventListener(k.slice(2), v);
        else if (k === 'value') el.value = v;
        else if (v === true) el.setAttribute(k, '');
        else el.setAttribute(k, String(v));
      });
    }
    for (let i = 2; i < arguments.length; i++) append(el, arguments[i]);
    return el;
  }

  function append(el, child) {
    if (child === null || child === undefined || child === false) return;
    if (Array.isArray(child)) { child.forEach(function (c) { append(el, c); }); return; }
    if (child instanceof Node) { el.appendChild(child); return; }
    el.appendChild(document.createTextNode(String(child)));
  }

  function $(id) { return document.getElementById(id); }

  function replace(el, child) {
    while (el.firstChild) el.removeChild(el.firstChild);
    append(el, child);
  }

  function fmtTime(iso) {
    if (!iso) return '—';
    const d = new Date(iso);
    return isNaN(d.getTime()) ? String(iso) : d.toLocaleString();
  }

  function shortId(id) { return id ? String(id).slice(0, 8) : '—'; }

  function dash(v) { return v === null || v === undefined || v === '' ? '—' : String(v); }

  function humanize(code) {
    return code ? String(code).toLowerCase().replace(/_/g, ' ') : '';
  }

  const STATUS_TONE = {
    PENDING: 'warn', APPROVED: 'ok', DECLINED: 'muted', REVOKED: 'bad',
    SUBMITTED: 'info', RETURNED: 'warn', VOIDED: 'bad',
  };

  function statusBadge(status) {
    return h('span', { class: 'badge badge-' + (STATUS_TONE[status] || 'muted') }, humanize(status));
  }

  const PEPPER = {
    SUGGEST_APPROVE: { label: 'Pepper: suggest approve', tone: 'ok' },
    SUGGEST_RETURN: { label: 'Pepper: suggest return', tone: 'warn' },
    FLAG_OWNER: { label: 'Pepper: flag for owner', tone: 'bad' },
  };

  function pepperBadge(rec) {
    if (!rec) return h('span', { class: 'muted small' }, '—');
    const p = PEPPER[rec] || { label: 'Pepper: ' + humanize(rec), tone: 'muted' };
    return h('span', { class: 'badge badge-' + p.tone }, p.label);
  }

  function partsBadges(c) {
    c = c || {};
    const parts = [
      ['A', 'appearance', 'Appearance photo'],
      ['R', 'recording', 'Recording'],
      ['C', 'cutOpen', 'Cut-open photo'],
      ['F', 'feedback', 'Feedback'],
    ];
    return h('span', { class: 'parts' }, parts.map(function (p) {
      const on = !!c[p[1]];
      return h('span', { class: 'part' + (on ? ' on' : ''), title: p[2] + (on ? ': present' : ': missing') }, p[0]);
    }));
  }

  function completeBadge(complete) {
    return complete
      ? h('span', { class: 'badge badge-ok' }, 'complete')
      : h('span', { class: 'badge badge-muted' }, 'incomplete');
  }

  function table(headers, rows, emptyText) {
    if (!rows.length) return h('p', { class: 'muted' }, emptyText || 'Nothing here.');
    return h('div', { class: 'table-wrap' },
      h('table', null,
        h('thead', null, h('tr', null, headers.map(function (x) {
          return typeof x === 'string' ? h('th', null, x) : h('th', { class: x.cls }, x.text);
        }))),
        h('tbody', null, rows)));
  }

  // ---------------------------------------------------------------- feedback

  let toastTimer = null;
  function toast(msg, isError) {
    const t = $('toast');
    t.textContent = msg;
    t.className = 'toast' + (isError ? ' error' : '');
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.hidden = true; }, isError ? 6000 : 3000);
  }

  function showBanner(title, text) {
    const b = $('banner');
    replace(b, [h('strong', null, title), text]);
    b.hidden = false;
  }

  function errorBox(err) {
    return h('p', { class: 'banner' }, err && err.message ? err.message : String(err));
  }

  // ---------------------------------------------------------------- API client

  function ApiError(status, code, message) {
    this.status = status;
    this.code = code;
    this.message = message;
  }

  async function api(method, path, body) {
    const opts = {
      method: method,
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
      redirect: 'manual',
      cache: 'no-store',
    };
    if (body !== undefined) {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(body);
    }
    let res;
    try {
      res = await fetch(path, opts);
    } catch (e) {
      throw new ApiError(0, 'network', 'Network error: the server could not be reached.');
    }
    if (res.type === 'opaqueredirect' || res.status === 0) {
      throw new ApiError(0, 'session',
        'The request was redirected. Your Cloudflare Access session may have expired: reload the page to sign in again.');
    }
    if (res.status === 204) return null;
    const text = await res.text();
    let data = null;
    if (text) {
      try { data = JSON.parse(text); } catch (e) { data = null; }
    }
    if (!res.ok) {
      const code = data && typeof data.error === 'string' ? data.error : '';
      const detail = data && typeof data.detail === 'string' ? data.detail : '';
      throw new ApiError(res.status, code,
        'Request failed (HTTP ' + res.status + (code ? ', ' + code : '') + ')' + (detail ? ': ' + detail : ''));
    }
    return data;
  }

  function q(params) {
    const parts = [];
    Object.keys(params).forEach(function (k) {
      if (params[k] !== '' && params[k] !== null && params[k] !== undefined) {
        parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(params[k]));
      }
    });
    return parts.length ? '?' + parts.join('&') : '';
  }

  function seg(v) { return encodeURIComponent(String(v)); }

  /** Runs an action from a button: disables it meanwhile, toasts the outcome, then refreshes. */
  async function act(button, fn, okMsg, after) {
    if (button) button.disabled = true;
    try {
      const r = await fn();
      if (okMsg) toast(typeof okMsg === 'function' ? okMsg(r) : okMsg);
      if (after) await after(r);
      return r;
    } catch (e) {
      toast(e && e.message ? e.message : String(e), true);
      return undefined;
    } finally {
      if (button) button.disabled = false;
    }
  }

  // ---------------------------------------------------------------- routing

  const VIEWS = ['overview', 'contributors', 'samples', 'ads'];

  function currentView() {
    const v = (location.hash || '').replace(/^#/, '');
    return VIEWS.indexOf(v) >= 0 ? v : 'overview';
  }

  function route() {
    const v = currentView();
    VIEWS.forEach(function (name) {
      $('view-' + name).hidden = name !== v;
    });
    document.querySelectorAll('.tabs a').forEach(function (a) {
      a.classList.toggle('active', a.getAttribute('data-tab') === v);
      if (a.getAttribute('data-tab') === v) a.setAttribute('aria-current', 'page');
      else a.removeAttribute('aria-current');
    });
    if (!state.disabled) load(v);
  }

  function load(v) {
    if (v === 'overview') return loadOverview();
    if (v === 'contributors') return loadContributors();
    if (v === 'samples') return loadSamples();
    if (v === 'ads') return loadAds();
    return undefined;
  }

  function go(view) {
    if (location.hash === '#' + view) route();
    else location.hash = view;
  }

  // ---------------------------------------------------------------- D: overview

  async function loadOverview() {
    const body = $('overview-body');
    try {
      const o = await api('GET', API + '/overview');
      replace(body, renderOverview(o));
    } catch (e) {
      replace(body, errorBox(e));
    }
  }

  function stat(num, label, onclick) {
    return h('div', { class: 'stat' + (onclick ? ' clickable' : ''), onclick: onclick, role: onclick ? 'button' : null },
      h('div', { class: 'num' }, String(num)), h('div', { class: 'lbl' }, label));
  }

  function renderOverview(o) {
    const done = o.completeSamplesApproved || 0;
    const pct = Math.min(100, Math.round((done / THRESHOLD) * 100));
    const counts = function (m, order) {
      return order.map(function (k) { return stat(m && m[k] !== undefined ? m[k] : 0, humanize(k)); });
    };
    const bar = h('div', { class: 'progress', role: 'progressbar', 'aria-valuemin': 0, 'aria-valuemax': THRESHOLD,
      'aria-valuenow': Math.min(done, THRESHOLD) });
    bar.appendChild(h('div', { style: null }));
    bar.firstChild.style.width = pct + '%';
    return [
      h('div', { class: 'card' },
        h('h3', null, 'Modeling threshold'),
        h('p', null, h('strong', null, String(done)), ' of ', String(THRESHOLD),
          ' complete approved samples', done >= THRESHOLD ? ' — threshold reached.' : '.'),
        bar,
        h('p', { class: 'muted small' }, 'Only approved samples with all four parts count; voided samples never count.')),
      h('div', { class: 'card' },
        h('h3', null, 'Review backlog'),
        h('div', { class: 'stat-grid' },
          stat(o.pendingReview || 0, 'samples awaiting review', function () {
            state.sampleFilter = { status: 'SUBMITTED', contributorId: '' };
            go('samples');
          }),
          stat(o.contributors && o.contributors.PENDING || 0, 'applications pending', function () {
            state.contribFilter = 'PENDING';
            go('contributors');
          }),
          stat(o.adFreeOutstanding || 0, 'ad-free units outstanding'))),
      h('div', { class: 'card' },
        h('h3', null, 'Contributors'),
        h('div', { class: 'stat-grid' }, counts(o.contributors, ['PENDING', 'APPROVED', 'DECLINED', 'REVOKED']))),
      h('div', { class: 'card' },
        h('h3', null, 'Samples'),
        h('div', { class: 'stat-grid' }, counts(o.samples, ['SUBMITTED', 'APPROVED', 'RETURNED', 'VOIDED']))),
    ];
  }

  // ---------------------------------------------------------------- A: contributors

  async function fetchContributors(status) {
    return api('GET', API + '/applications' + q({ status: status }));
  }

  async function refreshContributorCache() {
    try {
      state.contributors = await fetchContributors('');
    } catch (e) {
      /* keep the previous cache */
    }
    fillContributorSelect();
  }

  function fillContributorSelect() {
    const sel = $('sample-contributor');
    const keep = state.sampleFilter.contributorId;
    replace(sel, h('option', { value: '' }, 'All'));
    state.contributors.forEach(function (c) {
      const label = shortId(c.contributorId) + ' · ' + (c.note || '').slice(0, 40);
      sel.appendChild(h('option', { value: c.contributorId }, label));
    });
    if (keep && !state.contributors.some(function (c) { return c.contributorId === keep; })) {
      sel.appendChild(h('option', { value: keep }, shortId(keep)));
    }
    sel.value = keep;
  }

  function contributorActions(c, after) {
    const buttons = [];
    const s = c.status;
    if (s === 'PENDING' || s === 'DECLINED' || s === 'REVOKED') {
      const b = h('button', { type: 'button', class: 'btn btn-small btn-primary' }, 'Approve');
      b.addEventListener('click', function (ev) {
        ev.stopPropagation();
        act(b, function () { return api('POST', API + '/applications/' + seg(c.contributorId) + '/approve'); },
          'Contributor approved', after);
      });
      buttons.push(b);
    }
    if (s === 'PENDING') {
      const b = h('button', { type: 'button', class: 'btn btn-small' }, 'Decline');
      b.addEventListener('click', function (ev) {
        ev.stopPropagation();
        if (!confirm('Decline this application?')) return;
        act(b, function () { return api('POST', API + '/applications/' + seg(c.contributorId) + '/decline'); },
          'Application declined', after);
      });
      buttons.push(b);
    }
    if (s === 'APPROVED') {
      const b = h('button', { type: 'button', class: 'btn btn-small btn-danger' }, 'Revoke');
      b.addEventListener('click', function (ev) {
        ev.stopPropagation();
        if (!confirm('Revoke this contributor? They will no longer be able to submit samples.')) return;
        act(b, function () { return api('POST', API + '/contributors/' + seg(c.contributorId) + '/revoke'); },
          'Contributor revoked', after);
      });
      buttons.push(b);
    }
    return h('div', { class: 'actions' }, buttons);
  }

  async function loadContributors() {
    const body = $('contrib-body');
    $('contrib-status').value = state.contribFilter;
    try {
      const list = await fetchContributors(state.contribFilter);
      if (!state.contribFilter) {
        state.contributors = list;
        fillContributorSelect();
      }
      const rows = list.map(function (c) {
        return h('tr', { class: 'clickable', onclick: function () { openContributor(c.contributorId); } },
          h('td', { class: 'mono nowrap', title: c.contributorId }, shortId(c.contributorId)),
          h('td', null, statusBadge(c.status)),
          h('td', { class: 'note' }, h('div', { class: 'clamp' }, c.note)),
          h('td', { class: 'nowrap small hide-sm' }, fmtTime(c.createdAt)),
          h('td', { class: 'nowrap small hide-sm' }, fmtTime(c.updatedAt)),
          h('td', null, contributorActions(c, reloadAfterContributorChange)));
      });
      replace(body, [
        h('p', { class: 'muted small' }, list.length + ' contributor' + (list.length === 1 ? '' : 's') +
          ', oldest first. Tap a row for details.'),
        table(['ID', 'Status', 'Enrollment note', { text: 'Applied', cls: 'hide-sm' },
          { text: 'Updated', cls: 'hide-sm' }, 'Actions'], rows, 'No contributors match this filter.'),
      ]);
    } catch (e) {
      replace(body, errorBox(e));
    }
  }

  async function reloadAfterContributorChange() {
    await loadContributors();
    if (state.drawer && state.drawer.kind === 'contributor') await openContributor(state.drawer.id);
  }

  async function openContributor(id) {
    state.drawer = { kind: 'contributor', id: id };
    openDrawer('Contributor ' + shortId(id), h('p', { class: 'muted' }, 'Loading…'));
    try {
      const results = await Promise.all([
        fetchContributors(''),
        api('GET', API + '/contributors/' + seg(id) + '/adfree'),
        api('GET', API + '/samples' + q({ contributorId: id, limit: LIST_LIMIT })),
        api('GET', API + '/audit' + q({ objectType: 'CONTRIBUTOR', objectId: id, limit: 50 })),
      ]);
      state.contributors = results[0];
      fillContributorSelect();
      const c = results[0].find(function (x) { return x.contributorId === id; });
      if (!state.drawer || state.drawer.id !== id) return;
      setDrawerBody(renderContributor(id, c, results[1], results[2], results[3]));
    } catch (e) {
      if (state.drawer && state.drawer.id === id) setDrawerBody(errorBox(e));
    }
  }

  function renderContributor(id, c, ledger, samples, audit) {
    const refresh = function () { return reloadAfterContributorChange(); };

    const exempt = h('input', { type: 'checkbox' });
    exempt.checked = !!ledger.adExemptPermanent;
    exempt.addEventListener('change', function () {
      const want = exempt.checked;
      const msg = want ? 'Grant permanent ad exemption to this contributor?' : 'Remove permanent ad exemption?';
      if (!confirm(msg)) { exempt.checked = !want; return; }
      act(exempt, function () {
        return api('POST', API + '/contributors/' + seg(id) + '/exemption', { permanent: want });
      }, want ? 'Permanent exemption granted' : 'Permanent exemption removed', refresh);
    });

    const delta = h('input', { type: 'number', step: '1', inputmode: 'numeric', placeholder: 'e.g. 5 or -2', required: true });
    const reason = h('input', { type: 'text', maxlength: '64', placeholder: 'reason (required)', required: true });
    const grantBtn = h('button', { type: 'submit', class: 'btn btn-primary' }, 'Apply');
    const grantForm = h('form', { class: 'inline-form', novalidate: true },
      h('label', null, 'Delta (+ grant / − revoke)', delta),
      h('label', null, 'Reason', reason),
      grantBtn);
    grantForm.addEventListener('submit', function (ev) {
      ev.preventDefault();
      const d = Number(delta.value);
      if (!Number.isInteger(d) || d === 0) { toast('Delta must be a non-zero whole number.', true); return; }
      if (!reason.value.trim()) { toast('A reason is required.', true); return; }
      act(grantBtn, function () {
        return api('POST', API + '/contributors/' + seg(id) + '/adfree/grants', { delta: d, reason: reason.value.trim() });
      }, function (r) {
        return 'Applied ' + (r.appliedDelta > 0 ? '+' : '') + r.appliedDelta + ' (requested ' + r.requestedDelta +
          '); balance ' + r.balance;
      }, refresh);
    });

    const ledgerRows = ledger.entries.map(function (e) {
      return h('tr', null,
        h('td', { class: 'nowrap small' }, fmtTime(e.createdAt)),
        h('td', { class: 'mono' }, (e.delta > 0 ? '+' : '') + e.delta),
        h('td', null, humanize(e.reason)),
        h('td', { class: 'mono small' }, e.referenceId ? '#' + e.referenceId : '—'));
    });

    const sampleRows = samples.map(function (s) {
      return h('tr', { class: 'clickable', onclick: function () { openSample(s.id); } },
        h('td', { class: 'mono' }, '#' + s.id),
        h('td', null, statusBadge(s.status)),
        h('td', null, partsBadges(s.completeness)),
        h('td', null, pepperBadge(s.pepperRecommendation)),
        h('td', { class: 'nowrap small' }, fmtTime(s.createdAt)));
    });

    return [
      h('dl', { class: 'kv' },
        h('dt', null, 'Contributor ID'), h('dd', { class: 'mono' }, id),
        h('dt', null, 'Status'), h('dd', null, c ? statusBadge(c.status) : '—'),
        h('dt', null, 'Applied'), h('dd', null, c ? fmtTime(c.createdAt) : '—'),
        h('dt', null, 'Last status change'), h('dd', null, c ? fmtTime(c.updatedAt) : '—')),
      h('h4', null, 'Enrollment note'),
      h('div', { class: 'callout pre' }, c ? c.note : '—'),
      c ? contributorActions(c, refresh) : null,

      h('h4', null, 'Ad-free allowance'),
      h('p', null, 'Balance: ', h('strong', null, String(ledger.balance)), ' unit' + (ledger.balance === 1 ? '' : 's')),
      h('label', { class: 'check' }, exempt, 'Permanent ad exemption (spends nothing while on)'),
      grantForm,
      table(['When', 'Delta', 'Reason', 'Sample'], ledgerRows, 'No ledger entries yet.'),

      h('h4', null, 'Samples (' + samples.length + ')'),
      table(['ID', 'Status', 'Parts', 'Pepper', 'Submitted'], sampleRows, 'No samples from this contributor.'),

      auditSection(audit),
    ];
  }

  function auditSection(entries) {
    const rows = entries.map(function (e) {
      return h('tr', null,
        h('td', { class: 'nowrap small' }, fmtTime(e.createdAt)),
        h('td', { class: 'small' }, e.actor),
        h('td', { class: 'small' }, humanize(e.action)),
        h('td', { class: 'small mono pre' }, (e.beforeJson || '—') + '\n→ ' + (e.afterJson || '—')));
    });
    return h('details', null,
      h('summary', null, 'Audit history (' + entries.length + ')'),
      table(['When', 'Who', 'Action', 'Before → after'], rows, 'No audit entries.'));
  }

  // ---------------------------------------------------------------- B: samples

  async function loadSamples() {
    const body = $('sample-body');
    $('sample-status').value = state.sampleFilter.status;
    if (!state.contributors.length) await refreshContributorCache();
    fillContributorSelect();
    try {
      const list = await api('GET', API + '/samples' + q({
        status: state.sampleFilter.status, contributorId: state.sampleFilter.contributorId, limit: LIST_LIMIT,
      }));
      const rows = list.map(function (s) {
        return h('tr', { class: 'clickable', onclick: function () { openSample(s.id); } },
          h('td', { class: 'mono' }, '#' + s.id),
          h('td', null, statusBadge(s.status)),
          h('td', null, partsBadges(s.completeness), ' ', completeBadge(s.complete)),
          h('td', null, pepperBadge(s.pepperRecommendation)),
          h('td', { class: 'small' }, humanize(s.variety)),
          h('td', { class: 'mono small hide-sm', title: s.contributorId }, shortId(s.contributorId)),
          h('td', { class: 'nowrap small hide-sm' }, fmtTime(s.createdAt)));
      });
      replace(body, [
        h('p', { class: 'muted small' }, list.length + ' sample' + (list.length === 1 ? '' : 's') +
          ', newest first' + (list.length >= LIST_LIMIT ? ' (showing the newest ' + LIST_LIMIT + ')' : '') +
          '. Parts: A appearance · R recording · C cut-open · F feedback.'),
        table(['ID', 'Status', 'Completeness', 'Pepper', 'Variety', { text: 'Contributor', cls: 'hide-sm' },
          { text: 'Submitted', cls: 'hide-sm' }], rows, 'No samples match these filters.'),
      ]);
    } catch (e) {
      replace(body, errorBox(e));
    }
  }

  async function reloadAfterSampleChange() {
    if (currentView() === 'samples') await loadSamples();
    if (state.drawer && state.drawer.kind === 'sample') await openSample(state.drawer.id);
  }

  async function openSample(id) {
    state.drawer = { kind: 'sample', id: id };
    openDrawer('Sample #' + id, h('p', { class: 'muted' }, 'Loading…'));
    try {
      const results = await Promise.all([
        api('GET', API + '/samples/' + seg(id)),
        api('GET', API + '/audit' + q({ objectType: 'SAMPLE', objectId: id, limit: 50 })),
      ]);
      if (!state.drawer || state.drawer.id !== id) return;
      setDrawerBody(renderSample(results[0], results[1]));
    } catch (e) {
      if (state.drawer && state.drawer.id === id) setDrawerBody(errorBox(e));
    }
  }

  function fileUrl(sampleId, fileId) {
    return API + '/samples/' + seg(sampleId) + '/files/' + seg(fileId);
  }

  function fileCaption(f) {
    return (f.contentType || '') + ' · ' + Math.round((f.sizeBytes || 0) / 1024) + ' KB';
  }

  function renderMaterials(s) {
    const files = s.files || [];
    const by = function (part) { return files.filter(function (f) { return f.part === part; }); };
    const images = function (list, emptyText) {
      if (!list.length) return h('p', { class: 'muted small' }, emptyText);
      return h('div', { class: 'media-grid' }, list.map(function (f) {
        const url = fileUrl(s.id, f.id);
        return h('figure', null,
          h('a', { href: url, target: '_blank', rel: 'noopener noreferrer' },
            h('img', { src: url, alt: humanize(f.part) + ' photo', loading: 'lazy' })),
          h('figcaption', null, fileCaption(f)));
      }));
    };
    const recordings = by('RECORDING');
    return [
      h('h4', null, 'Appearance photos'),
      images(by('APPEARANCE'), 'No appearance photo.'),
      h('h4', null, 'Recording'),
      recordings.length
        ? recordings.map(function (f) {
          return h('div', null,
            h('audio', { controls: true, preload: 'metadata', src: fileUrl(s.id, f.id) }),
            h('div', { class: 'small muted' }, fileCaption(f), ' · ',
              h('a', { href: fileUrl(s.id, f.id), target: '_blank', rel: 'noopener noreferrer' }, 'download')));
        })
        : h('p', { class: 'muted small' }, 'No recording.'),
      h('h4', null, 'Cut-open photo'),
      images(by('CUT_OPEN'), 'No cut-open photo.'),
    ];
  }

  // FIX12: advisory on-device Vision score (0-1), or a dash when not sent.
  function visionScore(v) {
    return typeof v === 'number' ? v.toFixed(2) : '—';
  }

  function renderSample(s, audit) {
    const refresh = reloadAfterSampleChange;
    const actions = [];
    if (s.status === 'SUBMITTED') {
      const approve = h('button', { type: 'button', class: 'btn btn-primary' }, 'Approve');
      approve.addEventListener('click', function () {
        if (!confirm('Approve sample #' + s.id + '?' + (s.complete ? ' It is complete and earns ad-free units.' :
          ' It is incomplete and earns nothing.'))) return;
        act(approve, function () { return api('POST', API + '/samples/' + seg(s.id) + '/approve'); },
          'Sample approved', refresh);
      });
      actions.push(approve);
    }
    if (s.status !== 'VOIDED') {
      const voidBtn = h('button', { type: 'button', class: 'btn btn-danger' }, 'Void');
      voidBtn.addEventListener('click', function () {
        if (!confirm('Void sample #' + s.id + '? It stays on record but no longer counts, and unused ad-free ' +
          'units it earned are clawed back.')) return;
        act(voidBtn, function () { return api('POST', API + '/samples/' + seg(s.id) + '/void'); },
          'Sample voided', refresh);
      });
      actions.push(voidBtn);
    }

    let returnForm = null;
    if (s.status === 'SUBMITTED') {
      const reason = h('textarea', { maxlength: '500', required: true,
        placeholder: 'What should the contributor fix? (required, shown to them in the app)' });
      if (s.pepperRecommendation === 'SUGGEST_RETURN' && s.pepperNote) reason.value = s.pepperNote.slice(0, 500);
      const send = h('button', { type: 'submit', class: 'btn' }, 'Return with reason');
      returnForm = h('form', { class: 'stack-form', novalidate: true },
        h('label', null, 'Return reason', reason), h('div', { class: 'actions' }, send));
      returnForm.addEventListener('submit', function (ev) {
        ev.preventDefault();
        const r = reason.value.trim();
        if (!r) { toast('A return reason is required.', true); reason.focus(); return; }
        act(send, function () { return api('POST', API + '/samples/' + seg(s.id) + '/return', { reason: r }); },
          'Sample returned to the contributor', refresh);
      });
    }

    const fb = s.feedback;
    const pepper = s.pepperRecommendation
      ? h('div', { class: 'callout' + (s.pepperRecommendation === 'SUGGEST_APPROVE' ? '' : ' warn') },
        h('div', null, pepperBadge(s.pepperRecommendation), ' ',
          h('span', { class: 'small muted' }, fmtTime(s.pepperReviewedAt))),
        s.pepperNote ? h('div', { class: 'pre small' }, s.pepperNote) : null,
        h('div', { class: 'small muted' }, 'Advisory only — the final decision is yours.'))
      : h('p', { class: 'muted small' }, 'No preliminary review from Pepper yet.');

    const contributorLink = h('a', { href: '#', class: 'mono' }, s.contributorId);
    contributorLink.addEventListener('click', function (ev) { ev.preventDefault(); openContributor(s.contributorId); });

    return [
      h('div', { class: 'actions' }, statusBadge(s.status), completeBadge(s.complete), partsBadges(s.completeness)),
      h('h4', null, 'Preliminary review'),
      pepper,
      s.returnReason ? [h('h4', null, 'Return reason'), h('div', { class: 'callout warn pre' }, s.returnReason)] : null,
      actions.length || returnForm ? h('h4', null, 'Decision') : null,
      actions.length ? h('div', { class: 'actions' }, actions) : null,
      returnForm,

      h('h4', null, 'Feedback'),
      fb
        ? h('dl', { class: 'kv' },
          h('dt', null, 'Score'), h('dd', null, dash(fb.score)),
          h('dt', null, 'Taste tags'), h('dd', null, fb.tasteTags && fb.tasteTags.length
            ? fb.tasteTags.map(function (t) { return h('span', { class: 'badge' }, humanize(t)); }) : '—'),
          h('dt', null, 'Band (truth)'), h('dd', null, fb.bandTruth ? humanize(fb.bandTruth) : '—'))
        : h('p', { class: 'muted small' }, 'No feedback yet.'),

      h('h4', null, 'Melon'),
      h('dl', { class: 'kv' },
        h('dt', null, 'Variety'), h('dd', null, humanize(s.variety)),
        h('dt', null, 'Weight'), h('dd', null, s.weightGrams ? s.weightGrams + ' g' : '—',
          s.weightProvenance ? ' (' + humanize(s.weightProvenance) + ')' : ''),
        h('dt', null, 'Source'), h('dd', null, dash(s.source)),
        h('dt', null, 'Melon date'), h('dd', null, dash(s.melonDate)),
        h('dt', null, 'Vision watermelon'), h('dd', null, 'whole: ', visionScore(s.visionWholeWatermelon),
          ' / rind: ', visionScore(s.visionRindWatermelon), ' / cut: ', visionScore(s.visionCutopenWatermelon),
          typeof s.visionWatermelon === 'number' ? ' (legacy combined: ' + visionScore(s.visionWatermelon) + ')' : ''),
        h('dt', null, 'Contributor'), h('dd', null, contributorLink),
        h('dt', null, 'Submitted'), h('dd', null, fmtTime(s.createdAt)),
        h('dt', null, 'Updated'), h('dd', null, fmtTime(s.updatedAt))),

      renderMaterials(s),
      h('h4', null, 'History'),
      auditSection(audit),
    ];
  }

  // ---------------------------------------------------------------- C: ad switches

  const SETTING_INFO = {
    adfree_per_approved_sample: {
      label: 'Ad-free units per approved sample',
      help: 'Granted once when a complete sample is approved. Integer ≥ 0.',
    },
    promo_ends_at_epoch_millis: {
      label: 'Launch promo end',
      help: 'Epoch milliseconds; the promo runs until then. Integer ≥ 0 (a past time ends the promo).',
    },
    initial_free_thumps: {
      label: 'Initial free thumps (first-N allowance)',
      help: 'Sent to 1.2.0+ clients only. Integer ≥ 0.',
    },
    credit_per_ad: {
      label: 'Credits per rewarded ad',
      help: '−1 declares a free day (unlimited use, no ads). Integer −1 or ≥ 0.',
    },
  };

  function describeValue(key, v) {
    if (v === null || v === undefined) {
      return key === 'promo_ends_at_epoch_millis' ? 'not set (no promo)' : '—';
    }
    if (key === 'promo_ends_at_epoch_millis') {
      const d = new Date(Number(v));
      const past = d.getTime() < Date.now();
      return v + ' (' + d.toLocaleString() + (past ? ', in the past' : '') + ')';
    }
    if (key === 'credit_per_ad' && String(v) === '-1') return '-1 (free day)';
    return String(v);
  }

  function toLocalInput(ms) {
    const d = new Date(ms);
    const pad = function (n) { return String(n).padStart(2, '0'); };
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' +
      pad(d.getMinutes());
  }

  function renderSetting(s) {
    const info = SETTING_INFO[s.key] || { label: s.key, help: '' };
    const input = h('input', { type: 'text', inputmode: 'numeric', autocomplete: 'off', spellcheck: 'false',
      value: s.value === null ? '' : s.value, 'aria-label': info.label });
    const save = h('button', { type: 'submit', class: 'btn btn-primary btn-small' }, 'Save');
    const form = h('form', { class: 'inline-form', novalidate: true }, input, save);
    form.addEventListener('submit', function (ev) {
      ev.preventDefault();
      const v = input.value.trim();
      if (!/^-?\d+$/.test(v)) { toast('Enter a whole number.', true); return; }
      if (!confirm('Set ' + info.label + ' to ' + describeValue(s.key, v) + '?')) return;
      act(save, function () { return api('PUT', API + '/settings', { key: s.key, value: v }); },
        info.label + ' saved', loadSettings);
    });

    let picker = null;
    if (s.key === 'promo_ends_at_epoch_millis') {
      const dt = h('input', { type: 'datetime-local', 'aria-label': 'Promo end (local time)' });
      if (s.value !== null && s.value !== undefined) dt.value = toLocalInput(Number(s.value));
      dt.addEventListener('change', function () {
        const ms = new Date(dt.value).getTime();
        if (!isNaN(ms)) input.value = String(ms);
      });
      picker = h('label', { class: 'small muted' }, 'Pick a local date/time to fill the field: ', dt);
    }

    let reset = null;
    if (s.overridden) {
      reset = h('button', { type: 'button', class: 'btn btn-small' }, 'Reset to default');
      reset.addEventListener('click', function () {
        if (!confirm('Remove the override of ' + info.label + ' (back to ' + describeValue(s.key, s.defaultValue) +
          ')?')) return;
        act(reset, function () { return api('DELETE', API + '/settings/' + seg(s.key)); },
          info.label + ' reset to default', loadSettings);
      });
    }

    return h('tr', null,
      h('td', null, h('strong', null, info.label), h('div', { class: 'mono small muted' }, s.key),
        h('div', { class: 'small muted' }, info.help)),
      h('td', null, describeValue(s.key, s.value), ' ',
        s.overridden ? h('span', { class: 'badge badge-warn' }, 'override') :
          h('span', { class: 'badge badge-muted' }, 'default')),
      h('td', { class: 'small' }, describeValue(s.key, s.defaultValue)),
      h('td', null, form, picker, reset));
  }

  async function loadSettings() {
    const body = $('settings-body');
    try {
      const list = await api('GET', API + '/settings');
      replace(body, table(['Setting', 'Effective value', 'Default', 'Change'], list.map(renderSetting)));
    } catch (e) {
      replace(body, errorBox(e));
    }
  }

  async function loadRelease() {
    const body = $('release-body');
    try {
      // Public, read-only client policy endpoint: the admin API has no write path for these values.
      const p = await api('GET', '/api/v1/version/getclientversion');
      replace(body, h('dl', { class: 'kv' },
        h('dt', null, 'Latest version'), h('dd', { class: 'mono' }, dash(p.latestVersion)),
        h('dt', null, 'Minimum supported version'), h('dd', { class: 'mono' }, dash(p.minSupportedVersion))));
    } catch (e) {
      replace(body, errorBox(e));
    }
  }

  async function loadExemptions() {
    const body = $('exemptions-body');
    try {
      const list = await api('GET', API + '/exemptions');
      const rows = list.map(function (e) {
        const rm = h('button', { type: 'button', class: 'btn btn-small btn-danger' }, 'Remove');
        rm.addEventListener('click', function () {
          if (!confirm('Remove install ' + e.installId + ' from the exemption list?')) return;
          act(rm, function () { return api('DELETE', API + '/exemptions/' + seg(e.installId)); },
            'Exemption removed', loadExemptions);
        });
        return h('tr', null,
          h('td', { class: 'mono small' }, e.installId),
          h('td', { class: 'pre' }, dash(e.note)),
          h('td', { class: 'nowrap small hide-sm' }, fmtTime(e.createdAt)),
          h('td', null, rm));
      });
      replace(body, table(['Install ID', 'Note', { text: 'Added', cls: 'hide-sm' }, ''], rows,
        'The exemption list is empty.'));
    } catch (e) {
      replace(body, errorBox(e));
    }
  }

  function loadAds() {
    return Promise.all([loadSettings(), loadRelease(), loadExemptions()]);
  }

  function wireExemptionForm() {
    const form = $('exemption-form');
    form.addEventListener('submit', function (ev) {
      ev.preventDefault();
      const id = $('exemption-install').value.trim();
      const note = $('exemption-note').value.trim();
      if (!id) { toast('Install ID is required.', true); return; }
      const btn = form.querySelector('button[type=submit]');
      act(btn, function () {
        return api('POST', API + '/exemptions', note ? { installId: id, note: note } : { installId: id });
      }, 'Exemption saved', function () {
        $('exemption-install').value = '';
        $('exemption-note').value = '';
        return loadExemptions();
      });
    });
  }

  // ---------------------------------------------------------------- drawer

  let lastFocus = null;

  function openDrawer(title, content) {
    const d = $('drawer');
    $('drawer-title').textContent = title;
    replace($('drawer-body'), content);
    if (d.hidden) {
      lastFocus = document.activeElement;
      d.hidden = false;
      document.body.classList.add('drawer-open');
      d.querySelector('.drawer-head button').focus();
    }
    $('drawer-body').scrollTop = 0;
  }

  function setDrawerBody(content) {
    replace($('drawer-body'), content);
  }

  function closeDrawer() {
    const d = $('drawer');
    if (d.hidden) return;
    // Stop any playing recording before the nodes go away.
    d.querySelectorAll('audio').forEach(function (a) { try { a.pause(); } catch (e) { /* ignore */ } });
    d.hidden = true;
    document.body.classList.remove('drawer-open');
    replace($('drawer-body'), null);
    state.drawer = null;
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  // ---------------------------------------------------------------- boot

  async function probe() {
    try {
      await api('GET', API + '/overview');
      return true;
    } catch (e) {
      if (e.status === 404) {
        state.disabled = true;
        showBanner('Admin API disabled',
          'This server answers 404 for /api/admin/**: the admin API is switched off here ' +
          '(melonthump.admin.enabled / MELONTHUMP_ADMIN_ENABLED is false). Nothing can be shown or changed.');
        VIEWS.forEach(function (name) {
          $('view-' + name).querySelectorAll('[id$="-body"]').forEach(function (body) {
            replace(body, h('p', { class: 'muted' }, 'Admin API disabled.'));
          });
        });
        return false;
      }
      showBanner('Admin API unavailable', e.message);
      return true;
    }
  }

  function wire() {
    window.addEventListener('hashchange', route);
    document.querySelectorAll('[data-refresh]').forEach(function (b) {
      b.addEventListener('click', function () {
        if (state.disabled) return;
        const v = b.getAttribute('data-refresh');
        if (v === 'contributors' || v === 'samples') refreshContributorCache();
        load(v);
      });
    });
    document.querySelectorAll('[data-close-drawer]').forEach(function (el) {
      el.addEventListener('click', closeDrawer);
    });
    document.addEventListener('keydown', function (ev) {
      if (ev.key === 'Escape') closeDrawer();
    });
    $('contrib-status').addEventListener('change', function (ev) {
      state.contribFilter = ev.target.value;
      loadContributors();
    });
    $('sample-status').addEventListener('change', function (ev) {
      state.sampleFilter.status = ev.target.value;
      loadSamples();
    });
    $('sample-contributor').addEventListener('change', function (ev) {
      state.sampleFilter.contributorId = ev.target.value;
      loadSamples();
    });
    wireExemptionForm();
  }

  async function boot() {
    wire();
    const enabled = await probe();
    route();
    if (enabled) refreshContributorCache();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
