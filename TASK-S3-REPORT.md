# TASK S3 — delivery report

Owner sample review, the incentive ledger wiring, the contributor permanent exemption, the client spend endpoint, the install-id `adExempt` policy, and the audit read endpoint for 2.0.
Branch `2.0`, building on S1 and S2. Spec sources: `docs/2.0-design.md` v0.37 (§2 item 6, §7 items 9, 10, 11) and `docs/2.0-checklist.md` §3 and §4 A–D. The design doc is unchanged.

## 1. Build gate

Command (from `server/`):

```bash
JAVA_HOME=/Users/Shared/jdks/temurin-25/Contents/Home /Users/Shared/jdks/apache-maven-3.9.11/bin/mvn -B clean install
```

Result: **BUILD SUCCESS, 95 tests, 0 failures, 0 errors, 0 skipped.**

| Suite | Tests | Status |
|---|---|---|
| Pre-2.0 suites (10) | 35 | unchanged, pass |
| S1 + S2 suites | 42 | pass. One edit: `AdminDisabledTest` now also checks every S3 admin path is 404 when the switch is off (still 1 test) |
| `api.AdminReviewApiTest` (new) | 10 | pass |
| `api.AdFreeAndExemptionApiTest` (new) | 8 | pass |
| **Total** | **95** | |

Checks I ran outside Maven:

- **Legacy byte-identity.** I booted the pre-S3 jar (`c42edf0`) and the new jar side by side with the `qa` profile. On the new server, I first put the install id I send on the allowlist, so a leak would show. Then I diffed full HTTP responses (status line, headers without `Date`, body) for 10 requests. Every request carried `X-Install-Id`. The requests were health, and the version policy with no version, 0.9.0, 1.0.0, 1.1.0, 1.2.0, 1.9.9 and 1.2.0 with attest bypass. **All 8 were identical.** The other two requests (stats summary 403 and an unknown path 404) differ only in the `timestamp` of Spring's default error body.
- **Earlier QA harnesses on the new qa jar:**
  - `qa/s1_contribution_api_qa.py`: **30 passed, 0 failed**.
  - `qa/s2_sample_api_qa.py`: **32 passed, 0 failed**.
- **Black-box smoke** of the whole S3 flow against the `-Pqa` jar with curl:
  - apply → approve → complete submit → admin list.
  - download the cut-open photo; bytes and `Content-Type` match.
  - blank-reason return → 400; return; approve while RETURNED → 409.
  - the contributor sees `returnReason`, appends, and the sample is SUBMITTED again.
  - approve (+5), approve again (200, no second grant).
  - append and withdraw on the APPROVED sample → 409 `illegal_sample_state`.
  - status shows `adExemptPermanent`; spend; negative grant stops at the zero floor; void with clawback; ledger read.
  - permanent exemption makes spend return `exempt:true`.
  - policy for 2.0.0 gives `adExempt:true` with the allowlisted header and `false` without it.
  - the audit trail of the sample reads back newest first.

As in S1/S2, tests run on H2 in PostgreSQL mode. **V6 has not been run against a real PostgreSQL.** See §8.

## 2. Migration `V6__review_incentives_exemptions.sql` (additive, portable PG / H2)

- `ALTER TABLE contributors ADD COLUMN ad_exempt_permanent BOOLEAN NOT NULL DEFAULT FALSE`. This is the one change to an existing table, and the task allows it.
- New table `ad_exemptions`:
  - `install_id VARCHAR(64) PRIMARY KEY`
  - `note VARCHAR(128) NULL`
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- New index `idx_ad_free_ledger_reference (reference_id, reason)`. It serves the per-sample earning and clawback lookups. Adding an index does not change the table's columns or data.
- **No ledger-reason constraint change was needed.** `ad_free_ledger.reason` has no CHECK in V4. The new reason `SESSION_UNLOCK` was added only to the Java enum `LedgerReason`.

## 3. Endpoints and shapes

Every `/api/admin/**` endpoint sits behind the S1 kill-switch `melonthump.admin.enabled`; when it is off, every path is a 404.
- Audit actor is the literal `owner`.
- Errors use the S1/S2 shape `{"error": code, "detail": message}` with a fixed key order.
- Malformed ids, limits and bodies on the new admin endpoints return `400 {"error":"invalid_request",…}`.

**Limits** (sample list and audit read): absent → 50; a positive integer above 200 is **capped to 200**; 0, negative or non-numeric → 400.

### 3.1 Admin sample review — `AdminReviewController`

| Endpoint | Behaviour |
|---|---|
| `GET /api/admin/samples?status=&contributorId=&limit=` | Newest first (`createdAt desc, id desc`). Both filters are optional; `status` is case-insensitive. Each entry is `{id, contributorId, status, completeness{appearance,recording,cutOpen,feedback}, complete, returnReason, variety, createdAt, updatedAt}`. |
| `GET /api/admin/samples/{id}` | The S2 sample-detail shape (`id, contributorId, status, completeness, complete, returnReason, variety, weightGrams, weightProvenance, source, melonDate, feedback, files, createdAt, updatedAt`). Each `files[]` entry also carries **`id`**, the `fileId` for download (see §7.1). |
| `GET /api/admin/samples/{id}/files/{fileId}` | The stored bytes, with the stored `Content-Type`, `Content-Length`, `Cache-Control: no-store` and `X-Content-Type-Options: nosniff`. Returns `404 file_not_found` for an unknown file, a file of another sample, or a file missing on disk. Returns `404 sample_not_found` for an unknown sample. |
| `POST /api/admin/samples/{id}/approve` | SUBMITTED → APPROVED. A **complete** sample gets a `SAMPLE_APPROVED` ledger row of N units (`reference_id` = sample id). Writes audit `SAMPLE_APPROVED`, whose after-snapshot carries `grantedUnits`. Already APPROVED → 200 no-op (no grant, no audit row). RETURNED or VOIDED → `409 illegal_sample_state`. |
| `POST /api/admin/samples/{id}/return` | Body `{"reason": "..."}`: required, a string, non-blank after trimming, at most 500 characters, stored trimmed. A missing, empty, non-JSON or invalid body → 400. SUBMITTED → RETURNED with `return_reason`; writes audit `SAMPLE_RETURNED` (the reason is in the after-snapshot). Already RETURNED → 200 no-op, and the stored reason is unchanged. APPROVED or VOIDED → 409. |
| `POST /api/admin/samples/{id}/void` | SUBMITTED, RETURNED or APPROVED → VOIDED. The row and its files stay. Applies the clawback (§4). Writes audit `SAMPLE_VOIDED`, whose after-snapshot carries `earnedUnits` and `clawedBackUnits`. Already VOIDED → 200 no-op. |

- Approve, return and void all respond with the admin sample detail.
- Unknown sample → `404 sample_not_found`; a malformed or non-positive id → 400.
- Each decision locks the sample row (`findForUpdate`, `PESSIMISTIC_WRITE`, the same as S2 appends). The status change, its ledger row and its audit row commit in **one transaction**.

### 3.2 Admin ledger and exemptions — `AdminAdsController`

| Endpoint | Behaviour |
|---|---|
| `POST /api/admin/contributors/{id}/adfree/grants` | Body `{"delta": int, "reason": string}`. Returns `{contributorId, requestedDelta, appliedDelta, balance}` and writes audit `ADFREE_GRANT`. Details below the table. |
| `GET /api/admin/contributors/{id}/adfree` | `{contributorId, balance, entries[{id, delta, reason, referenceId, createdAt}], adExemptPermanent}`. Entries are newest first and all of them are returned. Unknown contributor → 404. |
| `POST /api/admin/contributors/{id}/exemption` | Body `{"permanent": true\|false}`; the value must be a JSON boolean, otherwise 400. Returns `{contributorId, status, adExemptPermanent}` and writes audit `CONTRIBUTOR_EXEMPTION`. Setting the current value is a 200 no-op with no audit row. Unknown contributor → 404. |
| `GET /api/admin/exemptions` | `[{installId, note, createdAt}]`, newest first. |
| `POST /api/admin/exemptions` | Body `{"installId": "...", "note": "..."?}`. Returns **201** on create and **200** on update, and writes audit `EXEMPTION_SET` (object `AD_EXEMPTION` / installId). Re-setting the same note is a 200 no-op with no audit row. Validation below the table. |
| `DELETE /api/admin/exemptions/{installId}` | **204**, with audit `EXEMPTION_REMOVED`. An absent install → `404 exemption_not_found`. |

**Manual grant** (`POST …/adfree/grants`):
- `delta` must be a JSON integer, non-zero, with magnitude at most 1 000 000. A missing value, a string, a fraction or overflow → 400.
- `reason` is required, non-blank, at most 64 characters, and stored trimmed.
- A negative delta is applied only down to a zero balance.
- Unknown contributor → 404.

**Allowlist entries** (`POST /api/admin/exemptions`):
- `installId` is required, non-blank, at most 64 characters, and trimmed. A value that parses as a UUID is stored in canonical lower case, so the iOS `uuidString` (upper case) matches.
- `note` is optional, trimmed, at most 128 characters; blank becomes null.

### 3.3 Audit read — `AdminController`

`GET /api/admin/audit?objectType=&objectId=&limit=` returns, newest first (by id):

```json
[{"id", "actor", "action", "objectType", "objectId", "beforeJson", "afterJson", "createdAt"}]
```

- Both filters are optional exact matches.
- `beforeJson` / `afterJson` are the stored JSON strings, `null` where absent.
- Object types in use: `CONTRIBUTOR`, `SAMPLE`, `AD_EXEMPTION`.

### 3.4 Client endpoints (`/api/v1/contributions/**`, App Attest gated)

- **`GET /status`** gains **`adExemptPermanent`** (boolean), appended after `adFreeBalance`. This is the one intended additive change on the contributions API.
- **`POST /adfree/spend`**, body `{"contributorId": "..."}`.
  - **Attestation:** the assertion covers the exact body bytes, the same as `/applications`. The gate runs first, so an unattested caller gets 401.
  - **Body:** a missing or malformed `contributorId` → 400.
  - **Caller checks:** unknown contributor → 404; not APPROVED → `403 contributor_not_approved`.
  - **Permanent-exempt:** `200 {"spent":false,"exempt":true,"balance":<unchanged>}`. No ledger row and no audit row.
  - **Balance ≥ 1:** a ledger row with delta −1 and reason `SESSION_UNLOCK`, then `200 {"spent":true,"exempt":false,"balance":<new>}`. Audit `ADFREE_SPENT`, actor = contributor id, with balances before and after.
  - **Balance 0:** `409 {"error":"insufficient_balance","detail":…}`.

### 3.5 Version policy (`GET /api/v1/version/getclientversion`)

- New optional header **`X-Install-Id`**.
- **`currentVersion` ≥ 2.0.0:** the response gains `"adExempt": true|false`. It is true only when the normalized header value matches an `ad_exemptions` row. A missing header, an unknown id or an over-long id gives `false`. A database failure is logged and answered `false`; it never breaks the policy.
- **Older clients or no `currentVersion`:** no lookup, the header is ignored, and the field is `null` and therefore omitted (`@JsonInclude(NON_NULL)`). This is the same gating pattern as the 1.2.0 fields.
- **Unchanged:** every existing field and behaviour, verified byte-for-byte (§1).

## 4. Where each design rule landed

| Rule | Where |
|---|---|
| §7.9: 5 units per approved **complete** sample; incomplete samples earn nothing; parameter adjustable | `IncentiveService.earnForApprovedSample`. N comes from `melonthump.contrib.adfree-per-approved-sample` (env `MELONTHUMP_CONTRIB_ADFREE_PER_APPROVED_SAMPLE`, default **5**, must be ≥ 0; a negative value fails at boot). |
| §7.9: a returned, fixed, then approved sample earns normally | Return writes no ledger row; the later approve grants. Tested. |
| Grant exactly once per sample | APPROVED is a no-op state, and RETURNED/VOIDED cannot be approved. As a second guard, the grant is skipped when a `SAMPLE_APPROVED` row with that `reference_id` already exists. |
| §7.10: removal = void-marking; the record stays | `SampleReviewService.voidSample` only sets the status. Rows and files are kept (tested). |
| §7.10: clawback of unused balance only, floored at zero | `IncentiveService.clawbackForVoidedSample`. The clawback is `min(current balance, earned)`. It is skipped when the sample earned nothing or already has a `VOID_CLAWBACK` row. A computed 0 writes **no** ledger row; the audit row records `clawedBackUnits: 0`. |
| §7.11: return requires a reason the contributor sees | Return validation; the reason appears in S2 `returnReason` (list and detail) and is cleared on resubmit (S2). |
| §7.11: owner-only final decisions; minimal append-only audit | Every review / grant / exemption / allowlist change writes an audit row in the same transaction (`AuditLogService`, MANDATORY). Read through `GET /api/admin/audit`. |
| §2.6: install allowlist → `adExempt` in the policy, list never exposed | `AdExemptionService` plus `VersionController.adExempt`. Only the caller's own boolean is returned. |
| §2.6–7: contributor permanent ad exemption / countable allowance | `contributors.ad_exempt_permanent`, the admin exemption endpoint, the status field, and spend short-circuits for exempt contributors. |
| Contribution and Invite ledgers are separate books | Nothing touches the invite tables or credits. |
| Zero floor under concurrency | Every balance-changing write takes the contributor row lock first. Lock order is sample → contributor, or contributor alone, so there is no cycle. `concurrentSpendsNeverOverdraw`: 12 parallel spends on a balance of 5 → exactly 5 succeed, final balance 0. |

## 5. Tests added

**`AdminReviewApiTest` (10):**
- list filters, ordering and limit (including cap and 400s);
- detail with file ids and no paths; download bytes and content type; 404 for a foreign, unknown or missing file and sample; 400s;
- approve grants 5 once, the repeat is a no-op with no extra audit row, return after approve → 409;
- an incomplete approve earns nothing;
- return-reason validation (missing body, empty, `{}`, blank, null, non-string, non-JSON, 501 characters) and the exact 500-character boundary;
- return no-op repeat; approve while RETURNED → 409; the contributor sees the reason; resubmit via append then approve;
- void from SUBMITTED, RETURNED and APPROVED; void no-op repeat; approve/return on VOIDED → 409; materials kept; 404/400 ids;
- clawback in full (balance 8, earned 5 → 3);
- clawback partial (balance 2 → 0) and at zero balance (no row);
- already clawed back (no second clawback);
- no ledger effect without earning.

**`AdFreeAndExemptionApiTest` (8):**
- grants including the zero floor (−10 at 4 → −4, −1 at 0 → 0 with no row), the ledger read, and audit rows carrying the free text;
- grant validation;
- exemption flag, status field and no-op repeat;
- spend: insufficient, success, exempt, exempt at zero, pending, revoked, unknown, bad body, unattested;
- concurrent spends;
- allowlist CRUD with case normalization and audit;
- policy gating: 2.0.0 and 2.1.3 match (including an upper-case header), no match, no header, over-long header; 1.0.0, 1.1.0 and 1.9.9 are byte-identical with and without the header; no-version and 1.1.0 equal the legacy template; 1.2.0 equals the exact 1.2.0 body;
- audit filters, ordering, limit and fields.

## 6. QA boot

The command is unchanged; `QA-RUN.md` is updated (V6, the new config row, and a new S3 smoke section):

```bash
JAVA_HOME=/Users/Shared/jdks/temurin-25/Contents/Home \
  /Users/Shared/jdks/apache-maven-3.9.11/bin/mvn -f server/pom.xml -Pqa spring-boot:run -Dspring-boot.run.profiles=qa
```

Packaged-jar equivalent: `mvn -f server/pom.xml -Pqa clean package -DskipTests`, then `java -jar server/target/melonthump-server-1.13.0.jar --spring.profiles.active=qa`. I verified this path; every new endpoint was driven with curl.

What the `qa` profile gives you:
- the admin API is on;
- the attest simulator bypass is on, so send `X-Attest-Bypass: simulator` on `/api/v1/contributions/**`, including the new `/adfree/spend`;
- admin endpoints need no header.

**Note for Pepper: after this package, the S2 RETURNED-resubmit path and the sample-state 409 paths (append/withdraw on APPROVED or VOIDED, approve on RETURNED or VOIDED, return on APPROVED or VOIDED) are reachable black-box through the admin review endpoints, and audit rows are readable through `GET /api/admin/audit`. Pepper will re-verify them end-to-end.**

## 7. Decisions I made where the spec was open

1. **Admin detail carries file ids.** The S2 `SampleFileView` has no id, so the owner would have no `fileId` to download. The admin detail is the S2 shape with each file gaining `id` (`AdminSampleDetail` / `AdminSampleFileView`). The contributor-facing S2 detail is **unchanged**, which keeps the hard constraint on response shapes.
2. **Manual-grant ledger reason.**
   - The DB has no CHECK on `reason`, but the column is `VARCHAR(32)` and is mapped to the `LedgerReason` enum, while the spec allows up to 64 characters of free text. Storing the free text would have meant widening an existing column, which this task forbids.
   - So the ledger row stores **`ADMIN_GRANT`** for every manual grant, positive or negative. The sign of `delta` tells grant from revocation.
   - The owner's free text is kept in the `ADFREE_GRANT` audit row, together with `requestedDelta`, `appliedDelta`, balances before and after, and the ledger entry id.
   - The S1 enum value `ADMIN_REVOKE` stays unused; I followed the spec's literal `ADMIN_GRANT`.
3. **A manual grant whose applied amount is 0** (negative delta at a zero balance) writes no ledger row. It still returns 200 with `appliedDelta: 0` and still writes the audit row, so the attempt is recorded.
4. **A clawback computing to 0** writes no ledger row. The audit row records `earnedUnits` and `clawedBackUnits`.
5. **Limit over 200 is capped**, not rejected; below 1 or non-numeric → 400.
6. **Repeated owner actions with no effect** write no audit row. This covers same-value exemption sets, same-note allowlist sets, and the review no-ops. It is the S1 convention.
7. **Approving a sample of a REVOKED contributor is allowed.** The decision is about the sample; the units still go to the contributor's ledger. Spending requires APPROVED status, so a revoked contributor can't use the units until re-approved.
8. **Install-id format.** Ids are free-form strings up to 64 characters. UUIDs are normalized to lower case on write, on delete and on policy lookup.
9. **`GET …/adfree` also returns `adExemptPermanent`**, appended after `entries`, so the admin page sees both ad-free instruments in one call. This is admin-only and additive.
10. **Allowlist POST status:** 201 on create, 200 on update or no-op. **DELETE:** 204.
11. **Spend is not idempotent per session.** Each call spends one unit. The client should call it once per session unlock.
12. **Install allowlist and contributor permanent exemption are separate.** `adExempt` in the policy is driven **only** by the install allowlist, as specified. A permanent-exempt contributor is not automatically `adExempt` in the policy: the policy request has no contributor id, and the design keeps the contributor id separate from the install id. The client learns the contributor flag from `/contributions/status` (and from spend's `exempt:true`). The owner can also add that contributor's device install id to the allowlist.

## 8. Left out / please check

1. **Not run against real PostgreSQL.** V6 uses only portable SQL. I deliberately avoided `(:param is null or …)` JPQL for the optional filters, because PostgreSQL cannot infer the type of a null UUID parameter. The sample list and audit read use one derived query per filter combination instead. **Recommend one suite run against PG, or watching the first dev deploy.**
2. **Audit actor** is still the literal `owner`. Reading the Cloudflare Access identity (`Cf-Access-Authenticated-User-Email`) remains a follow-up, as in S1.
3. **The per-sample unit count is a config/env value**, not yet editable from the admin page. Design §7.9 says "admin-adjustable"; a runtime-editable setting needs a settings table and is a follow-up for the admin-page package.
4. **No ledger pagination.** `GET …/adfree` returns every entry; volumes are tiny.
5. **The spend audit row is written for real spends only.** Exempt and insufficient spends write nothing.
6. **Admin page, Pepper preliminary-review recommendations and the read-only overview (D) are not in this package.**
7. **Deployment:**
   - production still needs `MELONTHUMP_ADMIN_ENABLED=true` once Cloudflare Access covers `/api/admin/**`;
   - optionally set `MELONTHUMP_CONTRIB_ADFREE_PER_APPROVED_SAMPLE`;
   - the persistent material volume noted in S2 still applies.

   k8s manifests were not touched.
8. `TASK-S1.md`, `TASK-S2.md` and `TASK-S3.md` (the task briefs) were left untracked and are not committed.
