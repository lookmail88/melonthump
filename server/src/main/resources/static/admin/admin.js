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
 *
 * UI copy (English / Simplified Chinese) lives in STRINGS below and is read
 * through t(). Static chrome in index.html carries data-i18n* attributes;
 * dynamic regions are drawn by "painters" (closures over the last loaded
 * data) so a language switch re-renders them without refetching.
 */
(function () {
  'use strict';

  const API = '/api/admin';
  const THRESHOLD = 30; // complete approved samples needed before modeling (design §5)
  const LIST_LIMIT = 200; // the admin list endpoints cap at 200
  const LANG_KEY = 'melonthump-admin-lang';
  const LANGS = ['en', 'zh'];

  // ---------------------------------------------------------------- strings

  const STRINGS = {
    en: {
      'app.title': 'MelonThump Admin',
      'brand.suffix': 'Admin',
      'nav.sections': 'Sections',
      'tab.overview': 'Overview',
      'tab.contributors': 'Contributors',
      'tab.samples': 'Sample review',
      'tab.ads': 'Ad switches',
      'btn.refresh': 'Refresh',
      'common.loading': 'Loading…',
      'common.nothing': 'Nothing here.',
      'filter.status': 'Status',
      'filter.contributor': 'Contributor',
      'filter.all': 'All',
      'filter.PENDING': 'Pending',
      'filter.APPROVED': 'Approved',
      'filter.DECLINED': 'Declined',
      'filter.REVOKED': 'Revoked',
      'filter.SUBMITTED': 'Submitted',
      'filter.RETURNED': 'Returned',
      'filter.VOIDED': 'Voided',
      'status.PENDING': 'pending',
      'status.APPROVED': 'approved',
      'status.DECLINED': 'declined',
      'status.REVOKED': 'revoked',
      'status.SUBMITTED': 'submitted',
      'status.RETURNED': 'returned',
      'status.VOIDED': 'voided',
      'ads.settings.title': 'Runtime settings',
      'ads.settings.help': 'Overrides take effect on the version policy and the incentive ledger within seconds. ' +
        'Reset returns a setting to its deployment default.',
      'ads.release.title': 'Release-class versions',
      'ads.release.badge': 'read-only',
      'ads.release.help1': 'Latest and minimum supported versions are ',
      'ads.release.help2': 'not editable here',
      'ads.release.help3': '. They change only through the release process (repository, pull request, ArgoCD).',
      'ads.exempt.title': 'Install exemption list',
      'ads.exempt.help1': 'Installs on this list get ',
      'ads.exempt.help2': ' in the version policy (2.0+ clients) and skip the ad gate entirely.',
      'ads.exempt.installId': 'Install ID',
      'ads.exempt.note': 'Note',
      'ads.exempt.submit': 'Add / update',
      'drawer.details': 'Details',
      'drawer.close': 'Close',
      'drawer.contributor': 'Contributor {id}',
      'drawer.sample': 'Sample #{id}',

      'pepper.SUGGEST_APPROVE': 'Pepper: suggest approve',
      'pepper.SUGGEST_RETURN': 'Pepper: suggest return',
      'pepper.FLAG_OWNER': 'Pepper: flag for owner',
      'pepper.other': 'Pepper: {rec}',
      'pepper.advisory': 'Advisory only — the final decision is yours.',
      'pepper.none': 'No preliminary review from Pepper yet.',
      'part.appearance': 'Appearance photo',
      'part.recording': 'Recording',
      'part.cutOpen': 'Cut-open photo',
      'part.feedback': 'Feedback',
      'part.present': '{part}: present',
      'part.missing': '{part}: missing',
      'badge.complete': 'complete',
      'badge.incomplete': 'incomplete',
      'badge.override': 'override',
      'badge.default': 'default',

      'err.network': 'Network error: the server could not be reached.',
      'err.session': 'The request was redirected. Your Cloudflare Access session may have expired: ' +
        'reload the page to sign in again.',
      'err.http': 'Request failed (HTTP {status})',
      'err.httpCode': 'Request failed (HTTP {status}, {code})',
      'err.detail': ': {detail}',
      'banner.unavailable': 'Admin API unavailable',
      'banner.disabled': 'Admin API disabled',
      'banner.disabledText': 'This server answers 404 for /api/admin/**: the admin API is switched off here ' +
        '(melonthump.admin.enabled / MELONTHUMP_ADMIN_ENABLED is false). Nothing can be shown or changed.',
      'body.disabled': 'Admin API disabled.',

      'ov.threshold': 'Modeling threshold',
      'ov.progress': '{done} of {total} complete approved samples',
      'ov.reached': ' — threshold reached.',
      'ov.notReached': '.',
      'ov.countRule': 'Only approved samples with all four parts count; voided samples never count.',
      'ov.backlog': 'Review backlog',
      'ov.samplesAwaiting': 'samples awaiting review',
      'ov.appsPending': 'applications pending',
      'ov.adFreeOutstanding': 'ad-free units outstanding',
      'ov.samples': 'Samples',

      'btn.approve': 'Approve',
      'btn.decline': 'Decline',
      'btn.revoke': 'Revoke',
      'btn.apply': 'Apply',
      'btn.void': 'Void',
      'btn.returnWithReason': 'Return with reason',
      'btn.save': 'Save',
      'btn.resetDefault': 'Reset to default',
      'btn.remove': 'Remove',
      'toast.contribApproved': 'Contributor approved',
      'toast.appDeclined': 'Application declined',
      'toast.contribRevoked': 'Contributor revoked',
      'toast.exemptGranted': 'Permanent exemption granted',
      'toast.exemptRemoved': 'Permanent exemption removed',
      'toast.deltaInvalid': 'Delta must be a non-zero whole number.',
      'toast.reasonRequired': 'A reason is required.',
      'toast.grantApplied': 'Applied {applied} (requested {requested}); balance {balance}',
      'toast.sampleApproved': 'Sample approved',
      'toast.sampleVoided': 'Sample voided',
      'toast.returnReasonRequired': 'A return reason is required.',
      'toast.sampleReturned': 'Sample returned to the contributor',
      'toast.wholeNumber': 'Enter a whole number.',
      'toast.settingSaved': '{label} saved',
      'toast.settingReset': '{label} reset to default',
      'toast.exemptionRemoved': 'Exemption removed',
      'toast.installRequired': 'Install ID is required.',
      'toast.exemptionSaved': 'Exemption saved',
      'confirm.decline': 'Decline this application?',
      'confirm.revoke': 'Revoke this contributor? They will no longer be able to submit samples.',
      'confirm.grantExempt': 'Grant permanent ad exemption to this contributor?',
      'confirm.removeExempt': 'Remove permanent ad exemption?',
      'confirm.approveComplete': 'Approve sample #{id}? It is complete and earns ad-free units.',
      'confirm.approveIncomplete': 'Approve sample #{id}? It is incomplete and earns nothing.',
      'confirm.void': 'Void sample #{id}? It stays on record but no longer counts, and unused ad-free ' +
        'units it earned are clawed back.',
      'confirm.setSetting': 'Set {label} to {value}?',
      'confirm.resetSetting': 'Remove the override of {label} (back to {value})?',
      'confirm.removeExemption': 'Remove install {id} from the exemption list?',

      'col.id': 'ID',
      'col.status': 'Status',
      'col.note': 'Enrollment note',
      'col.applied': 'Applied',
      'col.updated': 'Updated',
      'col.actions': 'Actions',
      'col.when': 'When',
      'col.delta': 'Delta',
      'col.reason': 'Reason',
      'col.sample': 'Sample',
      'col.parts': 'Parts',
      'col.pepper': 'Pepper',
      'col.submitted': 'Submitted',
      'col.who': 'Who',
      'col.action': 'Action',
      'col.beforeAfter': 'Before → after',
      'col.completeness': 'Completeness',
      'col.variety': 'Variety',
      'col.contributor': 'Contributor',
      'col.setting': 'Setting',
      'col.effective': 'Effective value',
      'col.default': 'Default',
      'col.change': 'Change',
      'col.installId': 'Install ID',
      'col.exemptNote': 'Note',
      'col.added': 'Added',

      'contrib.summaryOne': '{n} contributor, oldest first. Tap a row for details.',
      'contrib.summaryOther': '{n} contributors, oldest first. Tap a row for details.',
      'contrib.empty': 'No contributors match this filter.',
      'kv.contributorId': 'Contributor ID',
      'kv.lastChange': 'Last status change',
      'h.adFree': 'Ad-free allowance',
      'adfree.balanceOne': 'Balance: {n} unit',
      'adfree.balanceOther': 'Balance: {n} units',
      'adfree.permanent': 'Permanent ad exemption (spends nothing while on)',
      'grant.delta': 'Delta (+ grant / − revoke)',
      'grant.deltaPh': 'e.g. 5 or -2',
      'grant.reasonPh': 'reason (required)',
      'ledger.empty': 'No ledger entries yet.',
      'h.samplesN': 'Samples ({n})',
      'contribSamples.empty': 'No samples from this contributor.',
      'audit.summary': 'Audit history ({n})',
      'audit.empty': 'No audit entries.',

      'samples.summaryOne': '{n} sample, newest first{limit}. ' +
        'Parts: A appearance · R recording · C cut-open · F feedback.',
      'samples.summaryOther': '{n} samples, newest first{limit}. ' +
        'Parts: A appearance · R recording · C cut-open · F feedback.',
      'samples.limit': ' (showing the newest {limit})',
      'samples.empty': 'No samples match these filters.',
      'mat.appearancePhotos': 'Appearance photos',
      'mat.noAppearance': 'No appearance photo.',
      'mat.noRecording': 'No recording.',
      'mat.noCutOpen': 'No cut-open photo.',
      'mat.download': 'download',
      'mat.altAPPEARANCE': 'appearance photo',
      'mat.altCUT_OPEN': 'cut open photo',
      'return.label': 'Return reason',
      'return.ph': 'What should the contributor fix? (required, shown to them in the app)',
      'h.prelim': 'Preliminary review',
      'h.decision': 'Decision',
      'h.melon': 'Melon',
      'h.history': 'History',
      'kv.score': 'Score',
      'kv.tasteTags': 'Taste tags',
      'kv.bandTruth': 'Band (truth)',
      'fb.none': 'No feedback yet.',
      'kv.weight': 'Weight',
      'kv.source': 'Source',
      'kv.melonDate': 'Melon date',
      'kv.vision': 'Vision watermelon',
      'vision.scores': 'whole: {whole} / rind: {rind} / cut: {cut}',
      'vision.legacy': ' (legacy combined: {v})',

      'setting.adfree_per_approved_sample.label': 'Ad-free units per approved sample',
      'setting.adfree_per_approved_sample.help': 'Granted once when a complete sample is approved. Integer ≥ 0.',
      'setting.promo_ends_at_epoch_millis.label': 'Launch promo end',
      'setting.promo_ends_at_epoch_millis.help': 'Epoch milliseconds; the promo runs until then. ' +
        'Integer ≥ 0 (a past time ends the promo).',
      'setting.initial_free_thumps.label': 'Initial free thumps (first-N allowance)',
      'setting.initial_free_thumps.help': 'Sent to 1.2.0+ clients only. Integer ≥ 0.',
      'setting.credit_per_ad.label': 'Credits per rewarded ad',
      'setting.credit_per_ad.help': '−1 declares a free day (unlimited use, no ads). Integer −1 or ≥ 0.',
      'val.noPromo': 'not set (no promo)',
      'val.promo': '{v} ({date})',
      'val.promoPast': '{v} ({date}, in the past)',
      'val.freeDay': '-1 (free day)',
      'picker.aria': 'Promo end (local time)',
      'picker.label': 'Pick a local date/time to fill the field: ',
      'kv.latest': 'Latest version',
      'kv.minSupported': 'Minimum supported version',
      'exemptions.empty': 'The exemption list is empty.',
    },
    zh: {
      'app.title': 'MelonThump 管理台',
      'brand.suffix': '管理台',
      'nav.sections': '版块',
      'tab.overview': '总览',
      'tab.contributors': '贡献者',
      'tab.samples': '样本审核',
      'tab.ads': '广告开关',
      'btn.refresh': '刷新',
      'common.loading': '加载中…',
      'common.nothing': '暂无内容。',
      'filter.status': '状态',
      'filter.contributor': '贡献者',
      'filter.all': '全部',
      'filter.PENDING': '待审核',
      'filter.APPROVED': '已批准',
      'filter.DECLINED': '已拒绝',
      'filter.REVOKED': '已撤销',
      'filter.SUBMITTED': '已提交',
      'filter.RETURNED': '已退回',
      'filter.VOIDED': '已作废',
      'status.PENDING': '待审核',
      'status.APPROVED': '已批准',
      'status.DECLINED': '已拒绝',
      'status.REVOKED': '已撤销',
      'status.SUBMITTED': '已提交',
      'status.RETURNED': '已退回',
      'status.VOIDED': '已作废',
      'ads.settings.title': '运行时设置',
      'ads.settings.help': '覆盖值会在数秒内作用于版本策略和激励账本。重置会将设置恢复为部署默认值。',
      'ads.release.title': '发布类版本',
      'ads.release.badge': '只读',
      'ads.release.help1': '最新版本和最低支持版本',
      'ads.release.help2': '不能在此编辑',
      'ads.release.help3': '，只能通过发布流程（代码仓库、拉取请求、ArgoCD）更改。',
      'ads.exempt.title': '安装豁免名单',
      'ads.exempt.help1': '名单中的安装会在版本策略中获得 ',
      'ads.exempt.help2': '（2.0 及以上客户端），并完全跳过广告门槛。',
      'ads.exempt.installId': '安装 ID',
      'ads.exempt.note': '备注',
      'ads.exempt.submit': '添加 / 更新',
      'drawer.details': '详情',
      'drawer.close': '关闭',
      'drawer.contributor': '贡献者 {id}',
      'drawer.sample': '样本 #{id}',

      'pepper.SUGGEST_APPROVE': 'Pepper：建议批准',
      'pepper.SUGGEST_RETURN': 'Pepper：建议退回',
      'pepper.FLAG_OWNER': 'Pepper：提请负责人处理',
      'pepper.other': 'Pepper：{rec}',
      'pepper.advisory': '仅供参考——最终决定由你作出。',
      'pepper.none': 'Pepper 尚未进行初审。',
      'part.appearance': '外观照片',
      'part.recording': '录音',
      'part.cutOpen': '剖面照片',
      'part.feedback': '反馈',
      'part.present': '{part}：已提供',
      'part.missing': '{part}：缺失',
      'badge.complete': '完整',
      'badge.incomplete': '不完整',
      'badge.override': '已覆盖',
      'badge.default': '默认',

      'err.network': '网络错误：无法连接到服务器。',
      'err.session': '请求被重定向。你的 Cloudflare Access 会话可能已过期：请刷新页面重新登录。',
      'err.http': '请求失败（HTTP {status}）',
      'err.httpCode': '请求失败（HTTP {status}，{code}）',
      'err.detail': '：{detail}',
      'banner.unavailable': '管理 API 不可用',
      'banner.disabled': '管理 API 已禁用',
      'banner.disabledText': '此服务器对 /api/admin/** 返回 404：这里的管理 API 已关闭' +
        '（melonthump.admin.enabled / MELONTHUMP_ADMIN_ENABLED 为 false）。无法显示或修改任何内容。',
      'body.disabled': '管理 API 已禁用。',

      'ov.threshold': '建模门槛',
      'ov.progress': '已批准的完整样本：{done} / {total}',
      'ov.reached': '——已达到门槛。',
      'ov.notReached': '。',
      'ov.countRule': '只有四个部分齐全的已批准样本才计入；已作废的样本永不计入。',
      'ov.backlog': '待审积压',
      'ov.samplesAwaiting': '待审核样本',
      'ov.appsPending': '待审核申请',
      'ov.adFreeOutstanding': '未使用的免广告额度',
      'ov.samples': '样本',

      'btn.approve': '批准',
      'btn.decline': '拒绝',
      'btn.revoke': '撤销',
      'btn.apply': '应用',
      'btn.void': '作废',
      'btn.returnWithReason': '附原因退回',
      'btn.save': '保存',
      'btn.resetDefault': '恢复默认',
      'btn.remove': '移除',
      'toast.contribApproved': '已批准贡献者',
      'toast.appDeclined': '已拒绝申请',
      'toast.contribRevoked': '已撤销贡献者',
      'toast.exemptGranted': '已给予永久豁免',
      'toast.exemptRemoved': '已移除永久豁免',
      'toast.deltaInvalid': '变动量必须是非零整数。',
      'toast.reasonRequired': '必须填写原因。',
      'toast.grantApplied': '已应用 {applied}（请求 {requested}）；余额 {balance}',
      'toast.sampleApproved': '已批准样本',
      'toast.sampleVoided': '已作废样本',
      'toast.returnReasonRequired': '必须填写退回原因。',
      'toast.sampleReturned': '已将样本退回给贡献者',
      'toast.wholeNumber': '请输入整数。',
      'toast.settingSaved': '{label}已保存',
      'toast.settingReset': '{label}已恢复默认',
      'toast.exemptionRemoved': '已移除豁免',
      'toast.installRequired': '必须填写安装 ID。',
      'toast.exemptionSaved': '已保存豁免',
      'confirm.decline': '确定拒绝此申请？',
      'confirm.revoke': '确定撤销此贡献者？撤销后对方将无法再提交样本。',
      'confirm.grantExempt': '确定给予此贡献者永久广告豁免？',
      'confirm.removeExempt': '确定移除永久广告豁免？',
      'confirm.approveComplete': '确定批准样本 #{id}？该样本完整，将获得免广告额度。',
      'confirm.approveIncomplete': '确定批准样本 #{id}？该样本不完整，不会获得任何额度。',
      'confirm.void': '确定作废样本 #{id}？它仍会保留记录但不再计入，且它获得的未使用免广告额度将被收回。',
      'confirm.setSetting': '确定将“{label}”设为 {value}？',
      'confirm.resetSetting': '确定移除“{label}”的覆盖值（恢复为 {value}）？',
      'confirm.removeExemption': '确定将安装 {id} 从豁免名单中移除？',

      'col.id': 'ID',
      'col.status': '状态',
      'col.note': '申请留言',
      'col.applied': '申请时间',
      'col.updated': '更新时间',
      'col.actions': '操作',
      'col.when': '时间',
      'col.delta': '变动量',
      'col.reason': '原因',
      'col.sample': '样本',
      'col.parts': '组成部分',
      'col.pepper': 'Pepper',
      'col.submitted': '提交时间',
      'col.who': '操作人',
      'col.action': '动作',
      'col.beforeAfter': '变更前 → 变更后',
      'col.completeness': '完整度',
      'col.variety': '品种',
      'col.contributor': '贡献者',
      'col.setting': '设置项',
      'col.effective': '生效值',
      'col.default': '默认值',
      'col.change': '修改',
      'col.installId': '安装 ID',
      'col.exemptNote': '备注',
      'col.added': '添加时间',

      'contrib.summaryOne': '共 {n} 位贡献者，按时间从早到晚排列。点按某行查看详情。',
      'contrib.summaryOther': '共 {n} 位贡献者，按时间从早到晚排列。点按某行查看详情。',
      'contrib.empty': '没有符合此筛选条件的贡献者。',
      'kv.contributorId': '贡献者 ID',
      'kv.lastChange': '最近状态变更',
      'h.adFree': '免广告额度',
      'adfree.balanceOne': '余额：{n} 个单位',
      'adfree.balanceOther': '余额：{n} 个单位',
      'adfree.permanent': '永久广告豁免（开启期间不消耗额度）',
      'grant.delta': '变动量（+ 发放 / − 收回）',
      'grant.deltaPh': '例如 5 或 -2',
      'grant.reasonPh': '原因（必填）',
      'ledger.empty': '暂无账本记录。',
      'h.samplesN': '样本（{n}）',
      'contribSamples.empty': '该贡献者暂无样本。',
      'audit.summary': '审计记录（{n}）',
      'audit.empty': '暂无审计记录。',

      'samples.summaryOne': '共 {n} 个样本，按时间从新到旧排列{limit}。组成部分：A 外观 · R 录音 · C 剖面 · F 反馈。',
      'samples.summaryOther': '共 {n} 个样本，按时间从新到旧排列{limit}。组成部分：A 外观 · R 录音 · C 剖面 · F 反馈。',
      'samples.limit': '（仅显示最新的 {limit} 个）',
      'samples.empty': '没有符合这些筛选条件的样本。',
      'mat.appearancePhotos': '外观照片',
      'mat.noAppearance': '没有外观照片。',
      'mat.noRecording': '没有录音。',
      'mat.noCutOpen': '没有剖面照片。',
      'mat.download': '下载',
      'mat.altAPPEARANCE': '外观照片',
      'mat.altCUT_OPEN': '剖面照片',
      'return.label': '退回原因',
      'return.ph': '贡献者需要修正什么？（必填，会在应用中展示给对方）',
      'h.prelim': '初审',
      'h.decision': '决定',
      'h.melon': '西瓜',
      'h.history': '历史',
      'kv.score': '评分',
      'kv.tasteTags': '口感标签',
      'kv.bandTruth': '档位（真实值）',
      'fb.none': '暂无反馈。',
      'kv.weight': '重量',
      'kv.source': '来源',
      'kv.melonDate': '西瓜日期',
      'kv.vision': 'Vision 西瓜识别',
      'vision.scores': '整瓜：{whole} / 瓜皮：{rind} / 切面：{cut}',
      'vision.legacy': '（旧版综合：{v}）',

      'setting.adfree_per_approved_sample.label': '每个已批准样本的免广告额度',
      'setting.adfree_per_approved_sample.help': '完整样本被批准时发放一次。整数 ≥ 0。',
      'setting.promo_ends_at_epoch_millis.label': '上线促销结束时间',
      'setting.promo_ends_at_epoch_millis.help': '纪元毫秒数；促销持续到该时间为止。整数 ≥ 0（过去的时间即结束促销）。',
      'setting.initial_free_thumps.label': '初始免费拍瓜次数（前 N 次额度）',
      'setting.initial_free_thumps.help': '仅下发给 1.2.0 及以上客户端。整数 ≥ 0。',
      'setting.credit_per_ad.label': '每次激励广告的积分',
      'setting.credit_per_ad.help': '−1 表示免费日（无限使用、无广告）。整数 −1 或 ≥ 0。',
      'val.noPromo': '未设置（无促销）',
      'val.promo': '{v}（{date}）',
      'val.promoPast': '{v}（{date}，已过去）',
      'val.freeDay': '-1（免费日）',
      'picker.aria': '促销结束时间（本地时间）',
      'picker.label': '选择本地日期/时间以填入该字段：',
      'kv.latest': '最新版本',
      'kv.minSupported': '最低支持版本',
      'exemptions.empty': '豁免名单为空。',
    },
  };

  function initialLang() {
    try {
      const saved = localStorage.getItem(LANG_KEY);
      if (LANGS.indexOf(saved) >= 0) return saved;
    } catch (e) { /* storage blocked: fall through */ }
    const nav = (navigator.language || '').toLowerCase();
    return nav.slice(0, 2) === 'zh' ? 'zh' : 'en';
  }

  let lang = initialLang();

  function has(key) { return Object.prototype.hasOwnProperty.call(STRINGS.en, key); }

  function tRaw(key) {
    const table = STRINGS[lang] || STRINGS.en;
    if (Object.prototype.hasOwnProperty.call(table, key)) return table[key];
    return has(key) ? STRINGS.en[key] : key;
  }

  /** t('key', {name: v}) — the current language's copy with {name} placeholders filled in. */
  function t(key, params) {
    const s = tRaw(key);
    if (!params) return s;
    return s.replace(/\{(\w+)\}/g, function (m, k) {
      return Object.prototype.hasOwnProperty.call(params, k) ? String(params[k]) : m;
    });
  }

  /** Like t(), but returns a child list so a placeholder may be a DOM node (e.g. a <strong>). */
  function tn(key, params) {
    const s = tRaw(key);
    const out = [];
    const re = /\{(\w+)\}/g;
    let last = 0;
    let m;
    while ((m = re.exec(s)) !== null) {
      out.push(s.slice(last, m.index));
      const v = params && Object.prototype.hasOwnProperty.call(params, m[1]) ? params[m[1]] : m[0];
      out.push(v instanceof Node ? v : String(v));
      last = m.index + m[0].length;
    }
    out.push(s.slice(last));
    return out;
  }

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

  // ---------------------------------------------------------------- painters
  // A painter is a closure over already-loaded data that builds a region's DOM
  // in the current language. paint() draws a region and remembers its painter;
  // repaint() redraws it (on a language switch) keeping typed input values,
  // checkbox states, open <details> and scroll position.

  const painters = {}; // element id -> function returning children

  function paint(id, fn) {
    painters[id] = fn;
    replace($(id), fn());
  }

  function snapshot(root) {
    return {
      fields: Array.prototype.map.call(root.querySelectorAll('input, textarea, select'), function (el) {
        return { value: el.value, checked: el.checked };
      }),
      details: Array.prototype.map.call(root.querySelectorAll('details'), function (d) { return d.open; }),
      scroll: root.scrollTop,
    };
  }

  function restore(root, snap) {
    const fields = root.querySelectorAll('input, textarea, select');
    if (fields.length === snap.fields.length) {
      fields.forEach(function (el, i) {
        if (el.type === 'checkbox' || el.type === 'radio') el.checked = snap.fields[i].checked;
        else el.value = snap.fields[i].value;
      });
    }
    const details = root.querySelectorAll('details');
    if (details.length === snap.details.length) {
      details.forEach(function (d, i) { d.open = snap.details[i]; });
    }
    root.scrollTop = snap.scroll;
  }

  function repaint(id, fn) {
    const el = $(id);
    const snap = snapshot(el);
    replace(el, fn());
    restore(el, snap);
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

  /** Known status enums are UI labels (translated); an unknown one is shown humanized as served. */
  function statusLabel(status) {
    return has('status.' + status) ? t('status.' + status) : humanize(status);
  }

  function statusBadge(status) {
    return h('span', { class: 'badge badge-' + (STATUS_TONE[status] || 'muted') }, statusLabel(status));
  }

  const PEPPER_TONE = { SUGGEST_APPROVE: 'ok', SUGGEST_RETURN: 'warn', FLAG_OWNER: 'bad' };

  function pepperBadge(rec) {
    if (!rec) return h('span', { class: 'muted small' }, '—');
    const label = has('pepper.' + rec) ? t('pepper.' + rec) : t('pepper.other', { rec: humanize(rec) });
    return h('span', { class: 'badge badge-' + (PEPPER_TONE[rec] || 'muted') }, label);
  }

  function partsBadges(c) {
    c = c || {};
    const parts = [
      ['A', 'appearance', 'part.appearance'],
      ['R', 'recording', 'part.recording'],
      ['C', 'cutOpen', 'part.cutOpen'],
      ['F', 'feedback', 'part.feedback'],
    ];
    return h('span', { class: 'parts' }, parts.map(function (p) {
      const on = !!c[p[1]];
      return h('span', { class: 'part' + (on ? ' on' : ''),
        title: t(on ? 'part.present' : 'part.missing', { part: t(p[2]) }) }, p[0]);
    }));
  }

  function completeBadge(complete) {
    return complete
      ? h('span', { class: 'badge badge-ok' }, t('badge.complete'))
      : h('span', { class: 'badge badge-muted' }, t('badge.incomplete'));
  }

  /** headers: string keys, or {key, cls}; '' for a blank header. */
  function table(headers, rows, emptyText) {
    if (!rows.length) return h('p', { class: 'muted' }, emptyText || t('common.nothing'));
    return h('div', { class: 'table-wrap' },
      h('table', null,
        h('thead', null, h('tr', null, headers.map(function (x) {
          return typeof x === 'string' ? h('th', null, x ? t(x) : '') : h('th', { class: x.cls }, t(x.key));
        }))),
        h('tbody', null, rows)));
  }

  // ---------------------------------------------------------------- feedback

  let toastTimer = null;
  function toast(msg, isError) {
    const el = $('toast');
    el.textContent = msg;
    el.className = 'toast' + (isError ? ' error' : '');
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.hidden = true; }, isError ? 6000 : 3000);
  }

  let bannerPainter = null; // function returning [title, text]

  function showBanner(fn) {
    bannerPainter = fn;
    const b = $('banner');
    const parts = fn();
    replace(b, [h('strong', null, parts[0]), parts[1]]);
    b.hidden = false;
  }

  function errText(err) {
    if (err instanceof ApiError) return err.text();
    return err && err.message ? err.message : String(err);
  }

  function errorBox(err) {
    return h('p', { class: 'banner' }, errText(err));
  }

  // ---------------------------------------------------------------- API client

  /** Error messages are built at display time so they follow the current language. */
  function ApiError(status, code, key, detail) {
    this.status = status;
    this.code = code;
    this.key = key;
    this.detail = detail || '';
  }
  ApiError.prototype.text = function () {
    return t(this.key, { status: this.status, code: this.code }) +
      (this.detail ? t('err.detail', { detail: this.detail }) : '');
  };
  Object.defineProperty(ApiError.prototype, 'message', { get: function () { return this.text(); } });

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
      throw new ApiError(0, 'network', 'err.network');
    }
    if (res.type === 'opaqueredirect' || res.status === 0) {
      throw new ApiError(0, 'session', 'err.session');
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
      throw new ApiError(res.status, code, code ? 'err.httpCode' : 'err.http', detail);
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
      toast(errText(e), true);
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
    try {
      const o = await api('GET', API + '/overview');
      paint('overview-body', function () { return renderOverview(o); });
    } catch (e) {
      paint('overview-body', function () { return errorBox(e); });
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
      return order.map(function (k) { return stat(m && m[k] !== undefined ? m[k] : 0, statusLabel(k)); });
    };
    const bar = h('div', { class: 'progress', role: 'progressbar', 'aria-valuemin': 0, 'aria-valuemax': THRESHOLD,
      'aria-valuenow': Math.min(done, THRESHOLD) });
    bar.appendChild(h('div', { style: null }));
    bar.firstChild.style.width = pct + '%';
    return [
      h('div', { class: 'card' },
        h('h3', null, t('ov.threshold')),
        h('p', null, tn('ov.progress', { done: h('strong', null, String(done)), total: THRESHOLD }),
          t(done >= THRESHOLD ? 'ov.reached' : 'ov.notReached')),
        bar,
        h('p', { class: 'muted small' }, t('ov.countRule'))),
      h('div', { class: 'card' },
        h('h3', null, t('ov.backlog')),
        h('div', { class: 'stat-grid' },
          stat(o.pendingReview || 0, t('ov.samplesAwaiting'), function () {
            state.sampleFilter = { status: 'SUBMITTED', contributorId: '' };
            go('samples');
          }),
          stat(o.contributors && o.contributors.PENDING || 0, t('ov.appsPending'), function () {
            state.contribFilter = 'PENDING';
            go('contributors');
          }),
          stat(o.adFreeOutstanding || 0, t('ov.adFreeOutstanding')))),
      h('div', { class: 'card' },
        h('h3', null, t('tab.contributors')),
        h('div', { class: 'stat-grid' }, counts(o.contributors, ['PENDING', 'APPROVED', 'DECLINED', 'REVOKED']))),
      h('div', { class: 'card' },
        h('h3', null, t('ov.samples')),
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
    replace(sel, h('option', { value: '' }, t('filter.all')));
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
      const b = h('button', { type: 'button', class: 'btn btn-small btn-primary' }, t('btn.approve'));
      b.addEventListener('click', function (ev) {
        ev.stopPropagation();
        act(b, function () { return api('POST', API + '/applications/' + seg(c.contributorId) + '/approve'); },
          t('toast.contribApproved'), after);
      });
      buttons.push(b);
    }
    if (s === 'PENDING') {
      const b = h('button', { type: 'button', class: 'btn btn-small' }, t('btn.decline'));
      b.addEventListener('click', function (ev) {
        ev.stopPropagation();
        if (!confirm(t('confirm.decline'))) return;
        act(b, function () { return api('POST', API + '/applications/' + seg(c.contributorId) + '/decline'); },
          t('toast.appDeclined'), after);
      });
      buttons.push(b);
    }
    if (s === 'APPROVED') {
      const b = h('button', { type: 'button', class: 'btn btn-small btn-danger' }, t('btn.revoke'));
      b.addEventListener('click', function (ev) {
        ev.stopPropagation();
        if (!confirm(t('confirm.revoke'))) return;
        act(b, function () { return api('POST', API + '/contributors/' + seg(c.contributorId) + '/revoke'); },
          t('toast.contribRevoked'), after);
      });
      buttons.push(b);
    }
    return h('div', { class: 'actions' }, buttons);
  }

  async function loadContributors() {
    $('contrib-status').value = state.contribFilter;
    try {
      const list = await fetchContributors(state.contribFilter);
      if (!state.contribFilter) {
        state.contributors = list;
        fillContributorSelect();
      }
      paint('contrib-body', function () { return renderContributorList(list); });
    } catch (e) {
      paint('contrib-body', function () { return errorBox(e); });
    }
  }

  function renderContributorList(list) {
    const rows = list.map(function (c) {
      return h('tr', { class: 'clickable', onclick: function () { openContributor(c.contributorId); } },
        h('td', { class: 'mono nowrap', title: c.contributorId }, shortId(c.contributorId)),
        h('td', null, statusBadge(c.status)),
        h('td', { class: 'note' }, h('div', { class: 'clamp' }, c.note)),
        h('td', { class: 'nowrap small hide-sm' }, fmtTime(c.createdAt)),
        h('td', { class: 'nowrap small hide-sm' }, fmtTime(c.updatedAt)),
        h('td', null, contributorActions(c, reloadAfterContributorChange)));
    });
    return [
      h('p', { class: 'muted small' },
        t(list.length === 1 ? 'contrib.summaryOne' : 'contrib.summaryOther', { n: list.length })),
      table(['col.id', 'col.status', 'col.note', { key: 'col.applied', cls: 'hide-sm' },
        { key: 'col.updated', cls: 'hide-sm' }, 'col.actions'], rows, t('contrib.empty')),
    ];
  }

  async function reloadAfterContributorChange() {
    await loadContributors();
    if (state.drawer && state.drawer.kind === 'contributor') await openContributor(state.drawer.id);
  }

  function loadingText() { return h('p', { class: 'muted' }, t('common.loading')); }

  async function openContributor(id) {
    state.drawer = { kind: 'contributor', id: id };
    openDrawer(function () { return t('drawer.contributor', { id: shortId(id) }); }, loadingText);
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
      setDrawerBody(function () { return renderContributor(id, c, results[1], results[2], results[3]); });
    } catch (e) {
      if (state.drawer && state.drawer.id === id) setDrawerBody(function () { return errorBox(e); });
    }
  }

  function renderContributor(id, c, ledger, samples, audit) {
    const refresh = function () { return reloadAfterContributorChange(); };

    const exempt = h('input', { type: 'checkbox' });
    exempt.checked = !!ledger.adExemptPermanent;
    exempt.addEventListener('change', function () {
      const want = exempt.checked;
      const msg = want ? t('confirm.grantExempt') : t('confirm.removeExempt');
      if (!confirm(msg)) { exempt.checked = !want; return; }
      act(exempt, function () {
        return api('POST', API + '/contributors/' + seg(id) + '/exemption', { permanent: want });
      }, want ? t('toast.exemptGranted') : t('toast.exemptRemoved'), refresh);
    });

    const delta = h('input', { type: 'number', step: '1', inputmode: 'numeric', placeholder: t('grant.deltaPh'),
      required: true });
    const reason = h('input', { type: 'text', maxlength: '64', placeholder: t('grant.reasonPh'), required: true });
    const grantBtn = h('button', { type: 'submit', class: 'btn btn-primary' }, t('btn.apply'));
    const grantForm = h('form', { class: 'inline-form', novalidate: true },
      h('label', null, t('grant.delta'), delta),
      h('label', null, t('col.reason'), reason),
      grantBtn);
    grantForm.addEventListener('submit', function (ev) {
      ev.preventDefault();
      const d = Number(delta.value);
      if (!Number.isInteger(d) || d === 0) { toast(t('toast.deltaInvalid'), true); return; }
      if (!reason.value.trim()) { toast(t('toast.reasonRequired'), true); return; }
      act(grantBtn, function () {
        return api('POST', API + '/contributors/' + seg(id) + '/adfree/grants', { delta: d, reason: reason.value.trim() });
      }, function (r) {
        return t('toast.grantApplied', { applied: (r.appliedDelta > 0 ? '+' : '') + r.appliedDelta,
          requested: r.requestedDelta, balance: r.balance });
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
        h('dt', null, t('kv.contributorId')), h('dd', { class: 'mono' }, id),
        h('dt', null, t('col.status')), h('dd', null, c ? statusBadge(c.status) : '—'),
        h('dt', null, t('col.applied')), h('dd', null, c ? fmtTime(c.createdAt) : '—'),
        h('dt', null, t('kv.lastChange')), h('dd', null, c ? fmtTime(c.updatedAt) : '—')),
      h('h4', null, t('col.note')),
      h('div', { class: 'callout pre' }, c ? c.note : '—'),
      c ? contributorActions(c, refresh) : null,

      h('h4', null, t('h.adFree')),
      h('p', null, tn(ledger.balance === 1 ? 'adfree.balanceOne' : 'adfree.balanceOther',
        { n: h('strong', null, String(ledger.balance)) })),
      h('label', { class: 'check' }, exempt, t('adfree.permanent')),
      grantForm,
      table(['col.when', 'col.delta', 'col.reason', 'col.sample'], ledgerRows, t('ledger.empty')),

      h('h4', null, t('h.samplesN', { n: samples.length })),
      table(['col.id', 'col.status', 'col.parts', 'col.pepper', 'col.submitted'], sampleRows,
        t('contribSamples.empty')),

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
      h('summary', null, t('audit.summary', { n: entries.length })),
      table(['col.when', 'col.who', 'col.action', 'col.beforeAfter'], rows, t('audit.empty')));
  }

  // ---------------------------------------------------------------- B: samples

  async function loadSamples() {
    $('sample-status').value = state.sampleFilter.status;
    if (!state.contributors.length) await refreshContributorCache();
    fillContributorSelect();
    try {
      const list = await api('GET', API + '/samples' + q({
        status: state.sampleFilter.status, contributorId: state.sampleFilter.contributorId, limit: LIST_LIMIT,
      }));
      paint('sample-body', function () { return renderSampleList(list); });
    } catch (e) {
      paint('sample-body', function () { return errorBox(e); });
    }
  }

  function renderSampleList(list) {
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
    return [
      h('p', { class: 'muted small' }, t(list.length === 1 ? 'samples.summaryOne' : 'samples.summaryOther', {
        n: list.length,
        limit: list.length >= LIST_LIMIT ? t('samples.limit', { limit: LIST_LIMIT }) : '',
      })),
      table(['col.id', 'col.status', 'col.completeness', 'col.pepper', 'col.variety',
        { key: 'col.contributor', cls: 'hide-sm' }, { key: 'col.submitted', cls: 'hide-sm' }], rows,
      t('samples.empty')),
    ];
  }

  async function reloadAfterSampleChange() {
    if (currentView() === 'samples') await loadSamples();
    if (state.drawer && state.drawer.kind === 'sample') await openSample(state.drawer.id);
  }

  async function openSample(id) {
    state.drawer = { kind: 'sample', id: id };
    openDrawer(function () { return t('drawer.sample', { id: id }); }, loadingText);
    try {
      const results = await Promise.all([
        api('GET', API + '/samples/' + seg(id)),
        api('GET', API + '/audit' + q({ objectType: 'SAMPLE', objectId: id, limit: 50 })),
      ]);
      if (!state.drawer || state.drawer.id !== id) return;
      setDrawerBody(function () { return renderSample(results[0], results[1]); });
    } catch (e) {
      if (state.drawer && state.drawer.id === id) setDrawerBody(function () { return errorBox(e); });
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
        const alt = has('mat.alt' + f.part) ? t('mat.alt' + f.part) : humanize(f.part);
        return h('figure', null,
          h('a', { href: url, target: '_blank', rel: 'noopener noreferrer' },
            h('img', { src: url, alt: alt, loading: 'lazy' })),
          h('figcaption', null, fileCaption(f)));
      }));
    };
    const recordings = by('RECORDING');
    return [
      h('h4', null, t('mat.appearancePhotos')),
      images(by('APPEARANCE'), t('mat.noAppearance')),
      h('h4', null, t('part.recording')),
      recordings.length
        ? recordings.map(function (f) {
          return h('div', null,
            h('audio', { controls: true, preload: 'metadata', src: fileUrl(s.id, f.id) }),
            h('div', { class: 'small muted' }, fileCaption(f), ' · ',
              h('a', { href: fileUrl(s.id, f.id), target: '_blank', rel: 'noopener noreferrer' }, t('mat.download'))));
        })
        : h('p', { class: 'muted small' }, t('mat.noRecording')),
      h('h4', null, t('part.cutOpen')),
      images(by('CUT_OPEN'), t('mat.noCutOpen')),
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
      const approve = h('button', { type: 'button', class: 'btn btn-primary' }, t('btn.approve'));
      approve.addEventListener('click', function () {
        if (!confirm(t(s.complete ? 'confirm.approveComplete' : 'confirm.approveIncomplete', { id: s.id }))) return;
        act(approve, function () { return api('POST', API + '/samples/' + seg(s.id) + '/approve'); },
          t('toast.sampleApproved'), refresh);
      });
      actions.push(approve);
    }
    if (s.status !== 'VOIDED') {
      const voidBtn = h('button', { type: 'button', class: 'btn btn-danger' }, t('btn.void'));
      voidBtn.addEventListener('click', function () {
        if (!confirm(t('confirm.void', { id: s.id }))) return;
        act(voidBtn, function () { return api('POST', API + '/samples/' + seg(s.id) + '/void'); },
          t('toast.sampleVoided'), refresh);
      });
      actions.push(voidBtn);
    }

    let returnForm = null;
    if (s.status === 'SUBMITTED') {
      const reason = h('textarea', { maxlength: '500', required: true, placeholder: t('return.ph') });
      if (s.pepperRecommendation === 'SUGGEST_RETURN' && s.pepperNote) reason.value = s.pepperNote.slice(0, 500);
      const send = h('button', { type: 'submit', class: 'btn' }, t('btn.returnWithReason'));
      returnForm = h('form', { class: 'stack-form', novalidate: true },
        h('label', null, t('return.label'), reason), h('div', { class: 'actions' }, send));
      returnForm.addEventListener('submit', function (ev) {
        ev.preventDefault();
        const r = reason.value.trim();
        if (!r) { toast(t('toast.returnReasonRequired'), true); reason.focus(); return; }
        act(send, function () { return api('POST', API + '/samples/' + seg(s.id) + '/return', { reason: r }); },
          t('toast.sampleReturned'), refresh);
      });
    }

    const fb = s.feedback;
    const pepper = s.pepperRecommendation
      ? h('div', { class: 'callout' + (s.pepperRecommendation === 'SUGGEST_APPROVE' ? '' : ' warn') },
        h('div', null, pepperBadge(s.pepperRecommendation), ' ',
          h('span', { class: 'small muted' }, fmtTime(s.pepperReviewedAt))),
        s.pepperNote ? h('div', { class: 'pre small' }, s.pepperNote) : null,
        h('div', { class: 'small muted' }, t('pepper.advisory')))
      : h('p', { class: 'muted small' }, t('pepper.none'));

    const contributorLink = h('a', { href: '#', class: 'mono' }, s.contributorId);
    contributorLink.addEventListener('click', function (ev) { ev.preventDefault(); openContributor(s.contributorId); });

    return [
      h('div', { class: 'actions' }, statusBadge(s.status), completeBadge(s.complete), partsBadges(s.completeness)),
      h('h4', null, t('h.prelim')),
      pepper,
      s.returnReason ? [h('h4', null, t('return.label')), h('div', { class: 'callout warn pre' }, s.returnReason)] : null,
      actions.length || returnForm ? h('h4', null, t('h.decision')) : null,
      actions.length ? h('div', { class: 'actions' }, actions) : null,
      returnForm,

      h('h4', null, t('part.feedback')),
      fb
        ? h('dl', { class: 'kv' },
          h('dt', null, t('kv.score')), h('dd', null, dash(fb.score)),
          h('dt', null, t('kv.tasteTags')), h('dd', null, fb.tasteTags && fb.tasteTags.length
            ? fb.tasteTags.map(function (x) { return h('span', { class: 'badge' }, humanize(x)); }) : '—'),
          h('dt', null, t('kv.bandTruth')), h('dd', null, fb.bandTruth ? humanize(fb.bandTruth) : '—'))
        : h('p', { class: 'muted small' }, t('fb.none')),

      h('h4', null, t('h.melon')),
      h('dl', { class: 'kv' },
        h('dt', null, t('col.variety')), h('dd', null, humanize(s.variety)),
        h('dt', null, t('kv.weight')), h('dd', null, s.weightGrams ? s.weightGrams + ' g' : '—',
          s.weightProvenance ? ' (' + humanize(s.weightProvenance) + ')' : ''),
        h('dt', null, t('kv.source')), h('dd', null, dash(s.source)),
        h('dt', null, t('kv.melonDate')), h('dd', null, dash(s.melonDate)),
        h('dt', null, t('kv.vision')), h('dd', null,
          t('vision.scores', { whole: visionScore(s.visionWholeWatermelon), rind: visionScore(s.visionRindWatermelon),
            cut: visionScore(s.visionCutopenWatermelon) }),
          typeof s.visionWatermelon === 'number' ? t('vision.legacy', { v: visionScore(s.visionWatermelon) }) : ''),
        h('dt', null, t('col.contributor')), h('dd', null, contributorLink),
        h('dt', null, t('col.submitted')), h('dd', null, fmtTime(s.createdAt)),
        h('dt', null, t('col.updated')), h('dd', null, fmtTime(s.updatedAt))),

      renderMaterials(s),
      h('h4', null, t('h.history')),
      auditSection(audit),
    ];
  }

  // ---------------------------------------------------------------- C: ad switches

  /** Known settings have translated label/help; an unknown key shows as served. */
  function settingInfo(key) {
    const base = 'setting.' + key;
    return has(base + '.label')
      ? { label: t(base + '.label'), help: t(base + '.help') }
      : { label: key, help: '' };
  }

  function describeValue(key, v) {
    if (v === null || v === undefined) {
      return key === 'promo_ends_at_epoch_millis' ? t('val.noPromo') : '—';
    }
    if (key === 'promo_ends_at_epoch_millis') {
      const d = new Date(Number(v));
      const past = d.getTime() < Date.now();
      return t(past ? 'val.promoPast' : 'val.promo', { v: v, date: d.toLocaleString() });
    }
    if (key === 'credit_per_ad' && String(v) === '-1') return t('val.freeDay');
    return String(v);
  }

  function toLocalInput(ms) {
    const d = new Date(ms);
    const pad = function (n) { return String(n).padStart(2, '0'); };
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' +
      pad(d.getMinutes());
  }

  function renderSetting(s) {
    const info = settingInfo(s.key);
    const input = h('input', { type: 'text', inputmode: 'numeric', autocomplete: 'off', spellcheck: 'false',
      value: s.value === null ? '' : s.value, 'aria-label': info.label });
    const save = h('button', { type: 'submit', class: 'btn btn-primary btn-small' }, t('btn.save'));
    const form = h('form', { class: 'inline-form', novalidate: true }, input, save);
    form.addEventListener('submit', function (ev) {
      ev.preventDefault();
      const v = input.value.trim();
      if (!/^-?\d+$/.test(v)) { toast(t('toast.wholeNumber'), true); return; }
      if (!confirm(t('confirm.setSetting', { label: info.label, value: describeValue(s.key, v) }))) return;
      act(save, function () { return api('PUT', API + '/settings', { key: s.key, value: v }); },
        t('toast.settingSaved', { label: info.label }), loadSettings);
    });

    let picker = null;
    if (s.key === 'promo_ends_at_epoch_millis') {
      const dt = h('input', { type: 'datetime-local', 'aria-label': t('picker.aria') });
      if (s.value !== null && s.value !== undefined) dt.value = toLocalInput(Number(s.value));
      dt.addEventListener('change', function () {
        const ms = new Date(dt.value).getTime();
        if (!isNaN(ms)) input.value = String(ms);
      });
      picker = h('label', { class: 'small muted' }, t('picker.label'), dt);
    }

    let reset = null;
    if (s.overridden) {
      reset = h('button', { type: 'button', class: 'btn btn-small' }, t('btn.resetDefault'));
      reset.addEventListener('click', function () {
        if (!confirm(t('confirm.resetSetting', { label: info.label, value: describeValue(s.key, s.defaultValue) }))) {
          return;
        }
        act(reset, function () { return api('DELETE', API + '/settings/' + seg(s.key)); },
          t('toast.settingReset', { label: info.label }), loadSettings);
      });
    }

    return h('tr', null,
      h('td', null, h('strong', null, info.label), h('div', { class: 'mono small muted' }, s.key),
        h('div', { class: 'small muted' }, info.help)),
      h('td', null, describeValue(s.key, s.value), ' ',
        s.overridden ? h('span', { class: 'badge badge-warn' }, t('badge.override')) :
          h('span', { class: 'badge badge-muted' }, t('badge.default'))),
      h('td', { class: 'small' }, describeValue(s.key, s.defaultValue)),
      h('td', null, form, picker, reset));
  }

  async function loadSettings() {
    try {
      const list = await api('GET', API + '/settings');
      paint('settings-body', function () {
        return table(['col.setting', 'col.effective', 'col.default', 'col.change'], list.map(renderSetting));
      });
    } catch (e) {
      paint('settings-body', function () { return errorBox(e); });
    }
  }

  async function loadRelease() {
    try {
      // Public, read-only client policy endpoint: the admin API has no write path for these values.
      const p = await api('GET', '/api/v1/version/getclientversion');
      paint('release-body', function () {
        return h('dl', { class: 'kv' },
          h('dt', null, t('kv.latest')), h('dd', { class: 'mono' }, dash(p.latestVersion)),
          h('dt', null, t('kv.minSupported')), h('dd', { class: 'mono' }, dash(p.minSupportedVersion)));
      });
    } catch (e) {
      paint('release-body', function () { return errorBox(e); });
    }
  }

  async function loadExemptions() {
    try {
      const list = await api('GET', API + '/exemptions');
      paint('exemptions-body', function () { return renderExemptions(list); });
    } catch (e) {
      paint('exemptions-body', function () { return errorBox(e); });
    }
  }

  function renderExemptions(list) {
    const rows = list.map(function (e) {
      const rm = h('button', { type: 'button', class: 'btn btn-small btn-danger' }, t('btn.remove'));
      rm.addEventListener('click', function () {
        if (!confirm(t('confirm.removeExemption', { id: e.installId }))) return;
        act(rm, function () { return api('DELETE', API + '/exemptions/' + seg(e.installId)); },
          t('toast.exemptionRemoved'), loadExemptions);
      });
      return h('tr', null,
        h('td', { class: 'mono small' }, e.installId),
        h('td', { class: 'pre' }, dash(e.note)),
        h('td', { class: 'nowrap small hide-sm' }, fmtTime(e.createdAt)),
        h('td', null, rm));
    });
    return table(['col.installId', 'col.exemptNote', { key: 'col.added', cls: 'hide-sm' }, ''], rows,
      t('exemptions.empty'));
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
      if (!id) { toast(t('toast.installRequired'), true); return; }
      const btn = form.querySelector('button[type=submit]');
      act(btn, function () {
        return api('POST', API + '/exemptions', note ? { installId: id, note: note } : { installId: id });
      }, t('toast.exemptionSaved'), function () {
        $('exemption-install').value = '';
        $('exemption-note').value = '';
        return loadExemptions();
      });
    });
  }

  // ---------------------------------------------------------------- drawer

  let lastFocus = null;
  let drawerPainter = null; // { title: fn, body: fn }

  function openDrawer(titleFn, bodyFn) {
    const d = $('drawer');
    drawerPainter = { title: titleFn, body: bodyFn };
    $('drawer-title').textContent = titleFn();
    replace($('drawer-body'), bodyFn());
    if (d.hidden) {
      lastFocus = document.activeElement;
      d.hidden = false;
      document.body.classList.add('drawer-open');
      d.querySelector('.drawer-head button').focus();
    }
    $('drawer-body').scrollTop = 0;
  }

  function setDrawerBody(bodyFn) {
    if (drawerPainter) drawerPainter.body = bodyFn;
    replace($('drawer-body'), bodyFn());
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
    drawerPainter = null;
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  // ---------------------------------------------------------------- language

  /** Re-labels static chrome (data-i18n, data-i18n-placeholder, data-i18n-aria-label) and the title. */
  function applyStaticStrings() {
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      el.textContent = t(el.getAttribute('data-i18n'));
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(function (el) {
      el.setAttribute('placeholder', t(el.getAttribute('data-i18n-placeholder')));
    });
    document.querySelectorAll('[data-i18n-aria-label]').forEach(function (el) {
      el.setAttribute('aria-label', t(el.getAttribute('data-i18n-aria-label')));
    });
    document.title = t('app.title');
  }

  /**
   * Switches the UI language: static chrome, every painted region (from the
   * data already loaded — nothing is refetched), the banner and the open
   * drawer. Tab, filters and typed input are kept. The choice is persisted.
   */
  function applyLanguage(next, initial) {
    lang = LANGS.indexOf(next) >= 0 ? next : 'en';
    // Persist explicit choices only, so a browser-language default keeps following the browser.
    if (!initial) {
      try { localStorage.setItem(LANG_KEY, lang); } catch (e) { /* storage blocked: session-only choice */ }
    }
    document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
    $('lang-switch').value = lang;
    applyStaticStrings();
    fillContributorSelect();
    Object.keys(painters).forEach(function (id) { repaint(id, painters[id]); });
    if (bannerPainter && !$('banner').hidden) showBanner(bannerPainter);
    if (drawerPainter && !$('drawer').hidden) {
      $('drawer-title').textContent = drawerPainter.title();
      repaint('drawer-body', drawerPainter.body);
    }
  }

  // ---------------------------------------------------------------- boot

  async function probe() {
    try {
      await api('GET', API + '/overview');
      return true;
    } catch (e) {
      if (e.status === 404) {
        state.disabled = true;
        showBanner(function () { return [t('banner.disabled'), t('banner.disabledText')]; });
        VIEWS.forEach(function (name) {
          $('view-' + name).querySelectorAll('[id$="-body"]').forEach(function (body) {
            paint(body.id, function () { return h('p', { class: 'muted' }, t('body.disabled')); });
          });
        });
        return false;
      }
      showBanner(function () { return [t('banner.unavailable'), errText(e)]; });
      return true;
    }
  }

  function wire() {
    window.addEventListener('hashchange', route);
    $('lang-switch').addEventListener('change', function (ev) { applyLanguage(ev.target.value); });
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
    applyLanguage(lang, true);
    const enabled = await probe();
    route();
    if (enabled) refreshContributorCache();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
