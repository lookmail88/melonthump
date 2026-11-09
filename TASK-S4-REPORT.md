# TASK S4 Report — admin web page, runtime settings, Access identity, preliminary review

Branch `2.0`. This package builds on S1–S3 and does not restructure their code. iOS and k8s manifests were not touched.

## 1. Result

- **Build:** `mvn clean install` (Temurin 25, Maven 3.9.11) passed. **BUILD SUCCESS: 109 tests, 0 failures, 0 errors, 0 skipped.** S3 ended at 95 tests, so S4 adds 14. All 95 earlier tests still pass. One earlier test class was extended (`AdminDisabledTest`, see §6).
- **QA boot:** a `-Pqa` jar booted standalone with `--spring.profiles.active=qa` (H2, admin enabled, attest bypass on). Flyway applied V1–V7. Every S4 smoke command in `QA-RUN.md` was run against it over real HTTP.
- **Page URL:** `http://localhost:8080/admin/` (QA default port). `/admin` redirects to `/admin/`.

## 2. What was built

### Migration V7 (`V7__admin_settings_preliminary_review.sql`, additive)

- `admin_settings`
  - columns: `"key" VARCHAR(64)` PK, `"value" VARCHAR(256) NOT NULL`, `updated_at`, `updated_by VARCHAR(128)`.
  - `key` and `value` are **quoted** because both are keywords in H2. In PostgreSQL the quoted lower-case names are the same identifiers.
- `samples` gains three nullable columns:
  - `pepper_recommendation VARCHAR(16)`, with CHECK in `SUGGEST_APPROVE / SUGGEST_RETURN / FLAG_OWNER`;
  - `pepper_note TEXT`;
  - `pepper_reviewed_at TIMESTAMPTZ`.

### Endpoints

All of these sit behind `melonthump.admin.enabled`, like S1–S3.

| Method / path | Behaviour |
|---|---|
| `GET /api/admin/settings` | All 4 known keys, in fixed order, as `{key, value, defaultValue, overridden}`. Values are strings; `null` = unset (promo end with no promo configured). |
| `PUT /api/admin/settings` | Body `{"key","value"}`. `value` may be a string or a JSON integer.<br>Validation per key:<br>• `adfree_per_approved_sample`, `initial_free_thumps`: int ≥ 0<br>• `promo_ends_at_epoch_millis`: long ≥ 0<br>• `credit_per_ad`: −1 or int ≥ 0<br>Unknown key (including `latest_version` / `min_supported_version`) or bad value → 400.<br>Writes the row and an audit row `SETTING_CHANGED` (object `SETTING`, before/after). Returns the effective setting. |
| `DELETE /api/admin/settings/{key}` | Removes the override. Audit row `SETTING_RESET`. No override → 404 `setting_not_overridden`; unknown key → 400. |
| `POST /api/admin/samples/{id}/preliminary-review` | Body `{"recommendation", "note"?}`.<br>• `recommendation` is case-insensitive; bad or missing → 400.<br>• `note`: ≤ 1000 chars, trimmed; blank → null.<br>• Unknown sample → 404.<br>Audit row `PRELIMINARY_REVIEW` with actor `pepper`, or the Access email when the header is present. |
| `GET /api/admin/overview` | `{contributors:{PENDING,APPROVED,DECLINED,REVOKED}, samples:{SUBMITTED,APPROVED,RETURNED,VOIDED}, completeSamplesApproved, pendingReview, adFreeOutstanding}` |

- **Admin sample shapes:** the list and detail responses gain `pepperRecommendation`, `pepperNote`, `pepperReviewedAt`.
- **Contributor-facing shapes are unchanged.** A test asserts their exact field lists.

### Settings store and how values reach consumers

- `AdminSettingsService` resolves effective = DB override if present, else the existing properties/env default. The defaults are parsed with exactly the pre-S4 rules, which moved over from `VersionController`.
- Consumers now read the effective values:
  - `VersionController`: `creditPerAd`, `promoEndsAtEpochMillis`, `initialFreeThumps`.
  - `IncentiveService`: the per-approved-sample unit count.
- **Shapes and gating are untouched:**
  - `initialFreeThumps` still goes only to clients ≥ 1.2.0;
  - `adExempt` still goes only to clients ≥ 2.0.0;
  - legacy responses stay byte-identical except for the two value fields they already had.
- `latestVersion` / `minSupportedVersion` remain plain configuration with no write path anywhere.

### Access identity → audit actor

- `AdminActor` resolves the actor from `Cf-Access-Authenticated-User-Email` when that header is present and non-blank. The value is trimmed and capped at 128 chars to fit the `audit_log.actor` column.
- Otherwise the actor is `owner`, or `pepper` for preliminary review.
- It is threaded through every admin write path: applications, samples, grants, contributor exemption, install exemptions, settings and preliminary review.
- The old `AdminController.ACTOR` constant is gone.
- Client-facing actors (contributor ids) are unchanged; a test checks this.

### The admin page (`server/src/main/resources/static/admin/`)

**Files:** `index.html` (app shell), `admin.css`, `admin.js`. Vanilla ES2020, no framework, no build step, and no external URL of any kind; a test enforces this.

**Serving:**
- Served at `/admin/` through a view-controller forward, whatever the admin flag says.
- Every `/admin/*` response carries:
  - a strict same-origin CSP (`default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; media-src 'self'; connect-src 'self'; …; frame-ancestors 'none'`);
  - `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `Cache-Control: no-cache`.

**Structure:** a sticky top bar with four hash-routed tabs and a right-hand drawer for details. It is responsive: tables scroll horizontally, low-value columns hide below 640 px, and the drawer goes full-width on phones. Light and dark color schemes are supported.

**Escaping:** all DOM is built with `createElement` / `createTextNode`; nothing server-provided ever goes through `innerHTML`.

**API states:**
- At boot the page probes `GET /api/admin/overview`.
- A 404 shows the red **"Admin API disabled"** banner and blanks every section.
- A redirect, which is what Cloudflare Access does when its session expires, shows a "reload to sign in again" message.

## 3. Where each checklist §4 item landed

| Checklist §4 item | Where |
|---|---|
| **A — Contributors:** application review and roster with status filter, enrollment note, approve / decline / revoke | *Contributors* tab: status filter, note column (2-line clamp), per-row actions offered by current status. |
| A — contributor detail | Drawer: status, full note, actions; ad-free balance and ledger; permanent-exemption toggle; manual grant form (delta and reason) showing the applied delta and new balance; their samples (click opens the sample drawer); audit history. |
| **B — Sample review:** list filterable by status and contributor, completeness flags | *Sample review* tab: status and contributor filters; A/R/C/F part badges plus a complete/incomplete badge; Pepper recommendation badge. |
| B — detail with materials, feedback, approve / return / void | Drawer: appearance and cut-open images and a playable `<audio>` recording, all through `GET /api/admin/samples/{id}/files/{fileId}`; feedback (score, tags, band truth); variety, weight and provenance, source, date; Pepper box; approve, return (reason required, ≤ 500), void (confirm); audit history. |
| B — Pepper's preliminary recommendations in the review queue (§7 item 10) | List column and a detail callout. A `SUGGEST_RETURN` note pre-fills the return-reason box; the owner still edits and submits. |
| **C — Ads:** adExempt list | *Ad switches* tab: add/update (install id and note), remove. |
| C — ad-free grants, permanent exemption | Contributor drawer (section A), because grants are per contributor. |
| C — ad switches (promo end, first-N allowance, …) | Runtime settings table: effective value, default, override badge, save, "Reset to default". The promo row adds a local date/time picker. `credit_per_ad = −1` is labelled "free day". |
| C — release-class numbers not editable | Read-only card showing `latestVersion` / `minSupportedVersion` with the text "not editable here — release process only". The settings API rejects those keys with 400. |
| **D — Read-only overview** | *Overview* tab: progress toward the **30** complete-approved threshold, the pending-review backlog (click → filtered sample list), pending applications, ad-free units outstanding, per-status counts. |
| Responsive; Safari / Chrome / Edge | Responsive CSS and ES2020 only. **Not verified in real browsers:** see §5. |
| Cloudflare Access in front; no self-built login | The server stores no credentials and has no login. The Access email header is honoured for audit. The Access policy itself is deployment work. |

## 4. Tests added

| Test class | Covers |
|---|---|
| `AdminSettingsApiTest` (5) | Defaults and exact shape. Validation of every key and its boundaries, unknown and release-class keys, malformed bodies, nothing written on rejection. PUT/DELETE with before/after audit and `updated_by`. **Policy values change with an override and revert on DELETE.** Legacy, 1.2.0 and 2.0.0 responses keep identical field sets. **An approved complete sample earns the overridden unit count:** 7, then the default 5 after reset, then 0. |
| `AdminConsoleApiTest` (5) | **Actor:** the header email lands in audit rows for every admin write path; absent or blank → `owner`; client-facing writes keep the contributor id. **Preliminary review:** write, audit (`pepper`), visibility in admin list and detail, replacement, the owner's later approve keeps the Pepper fields, contributor detail and list fields exactly unchanged, contributor-visible `updatedAt` unchanged, validation (404 / 400s, 1000-char limit). |
| `AdminOverviewApiTest` (1) | Exact counts on a seeded scenario, including a voided complete sample (excluded), an incomplete approved sample (excluded), a clawback, grants and a spend. |
| `AdminPageTest` (2, real HTTP) | `/admin/` returns 200 `text/html` with CSP; JS and CSS content types; `/admin` gives 302. **No external URL scheme, protocol-relative URL or `@import` in any asset**, shell references are only relative or `data:`, all fetch targets are same-origin paths. |
| `AdminDisabledTest` (+1, and S4 paths added) | The new API paths return 404 with the flag off; the page is still served. |

**Page JS run outside a browser:** I also ran the real `admin.js` under macOS JavaScriptCore. It used a minimal DOM shim fed with **live responses from the QA server**, seeded with a real PNG/WAV sample and with `<img onerror>` / `<script>` strings in the enrollment note and Pepper note. That run covered:
- every tab, both drawers, the grant / return / settings forms and the disabled state;
- no runtime errors;
- injected markup ended up only as text;
- images and audio pointed at the download endpoint.

This shim is a throwaway check and is not committed.

## 5. Left out, and decisions I made

1. **No real-browser check.** No Chrome or Edge is installed on this machine, and Safari automation (`safaridriver`) isn't enabled here; turning it on needs admin rights. Layout and behaviour in Safari, Chrome and Edge (checklist §4 item 2) still need a manual pass, ideally on a phone as well. The CSS uses `color-mix()` for badge tints (Safari 16.2+ / Chrome 111+); older browsers fall back to un-tinted badges.
2. **The release-class display reads the public `GET /api/v1/version/getclientversion`.** It is read-only and needs no credentials, so the page can show the actual numbers. This is the page's only call outside `/api/admin/**`; dropping it would leave just the static explanation.
3. **The promo end can't be overridden to "no promo" (null).** The spec requires long ≥ 0. Setting `0`, or any past time, ends the promo for clients. "Reset" returns to the deployment default, which may itself be null.
4. **Settings cache.** Consumers re-read overrides at most every 5 s (`melonthump.admin.settings-cache-millis`); a local write takes effect immediately. With several replicas, others catch up within that window. If reading the overrides fails, the policy uses the defaults, so the policy endpoint never breaks over settings.
5. **PUT always writes a row and an audit row**, even when the value is unchanged, as the spec says.
6. **The reset audit action is named `SETTING_RESET`.** The spec only says "audit row".
7. **Preliminary review:**
   - allowed on a sample in any status;
   - a later call replaces the earlier recommendation;
   - it never changes the sample's status;
   - it is written with a bulk update so the contributor-visible `updatedAt` does not move;
   - the three columns are read-only to normal entity updates, so later approve/return/void writes cannot clobber them.
8. **"Free-day switch"** appears in design §7 item 11's list of switches. There is no separate flag for it in the code: it is `credit_per_ad = −1`, which the page labels as the free day. No fifth key was added, because the spec fixes exactly four.
9. **Access JWT verification not implemented.** Checklist §4 says "server verifies the Access JWT". As the S4 spec asks, the server only honours the email header. That header is trusted only as far as the edge is, which is why the admin API stays behind `MELONTHUMP_ADMIN_ENABLED`. Verifying `Cf-Access-Jwt-Assertion` against the team's certs is a possible follow-up.
10. **Not run against real PostgreSQL**, as in S1–S3. V7 is portable SQL. The quoted `"key"` / `"value"` columns and the JPQL bulk update are the parts most worth checking on PG.
11. **Deployment:**
    - put `/admin/` under the same Cloudflare Access application as `/api/admin/**`;
    - set `MELONTHUMP_ADMIN_ENABLED=true` once Access covers the API.

    The page is harmless while uncovered (no data, and the API answers 404), but it should sit behind Access too.
12. `TASK-S1.md` … `TASK-S4.md` (the briefs) were left untracked and are not committed.
