# TASK S1 — delivery report

Server foundation for 2.0: the contributor data layer, the application flow, the owner admin transitions, and the audit log.
Branch `2.0`. Spec sources: `docs/2.0-design.md` v0.37 (§2 items 6–8, §5 item 6, §7 items 8–11) and `docs/2.0-checklist.md` §3. The design doc is unchanged, as the task requires.

## 1. Build gate

Command (from `server/`):

```bash
JAVA_HOME=/Users/Shared/jdks/temurin-25/Contents/Home /Users/Shared/jdks/apache-maven-3.9.11/bin/mvn -B clean install
```

Result: **BUILD SUCCESS, 60 tests, 0 failures, 0 errors, 0 skipped.**

| Suite | Tests | Status |
|---|---|---|
| Baseline before this task (10 existing suites) | 35 | unchanged, all pass |
| `api.ContributionApiTest` (new) | 8 | pass |
| `api.AdminApiTest` (new) | 8 | pass |
| `api.AdminDisabledTest` (new) | 1 | pass |
| `contrib.ContributorDataLayerTest` (new) | 8 | pass |
| **Total** | **60** | |

Tests run on H2 in PostgreSQL compatibility mode. This is the project's existing test setup. **No PostgreSQL was available on this machine, so V4 has not been run against a real PostgreSQL.** See §7.

## 2. Tables — Flyway migration `V4__contributor_sample_audit_ledger.sql` (additive only)

The migration adds four new tables and does not alter any existing table. It is written to run unchanged on PostgreSQL and on H2 in PG mode, so it avoids `jsonb`, arrays and generated columns. Enum-like columns are `VARCHAR` + `CHECK`.

- **`contributors`**
  - `contributor_id UUID PK`: client-generated.
  - `note TEXT NOT NULL`: the enrollment note.
  - `status VARCHAR(16)`: CHECK `PENDING/APPROVED/DECLINED/REVOKED`.
  - `created_at`, `updated_at` (timestamptz).
  - Index `(status, created_at)`.
- **`samples`**
  - `id BIGSERIAL PK`, `contributor_id UUID FK→contributors`.
  - `variety VARCHAR(16) NOT NULL`: CHECK `SEEDLESS/SEEDED/MINI/YELLOW_FLESH/KIRIN/BLACK_BEAUTY/OTHER`. This is the §7.7 preset list; `OTHER` is "other / not sure".
  - `weight_grams INT NULL` (CHECK > 0).
  - `weight_provenance NULL`: CHECK `PHOTO_ESTIMATED/MANUAL_ESTIMATE/SCALE_MEASURED`.
  - `source VARCHAR(64) NULL`, `melon_date DATE NULL`.
  - `has_appearance / has_recording / has_cut_open / has_feedback BOOLEAN`.
  - `complete BOOLEAN`: derived. The entity recomputes it on every write, and a CHECK constraint enforces `complete = (all four)`.
  - `score INT NULL` (CHECK 0–100).
  - `taste_tags TEXT NULL`: a JSON array of strings, mapped to `List<String>` through a JPA converter.
  - `band_truth NULL`: CHECK `UNRIPE/RIPE/OVERRIPE`.
  - `status`: CHECK `SUBMITTED/APPROVED/RETURNED/VOIDED`.
  - `return_reason TEXT NULL`, `created_at`, `updated_at`.
  - Indexes `(contributor_id, created_at)` and `(status, created_at)`.
- **`audit_log`**
  - `id BIGSERIAL`, `actor VARCHAR(128)`, `action VARCHAR(64)`, `object_type VARCHAR(32)`, `object_id VARCHAR(64)`, `before_json TEXT`, `after_json TEXT`, `created_at`.
  - Indexes `(object_type, object_id, id)` and `(created_at)`.
- **`ad_free_ledger`**
  - `id BIGSERIAL`, `contributor_id UUID FK→contributors`, `delta INT`, `reason VARCHAR(32)`, `reference_id VARCHAR(64) NULL`, `created_at`.
  - Index `(contributor_id, id)`.
  - `reason` has no DB CHECK, so new reasons can be added without a migration. The Java enum `LedgerReason` holds `SAMPLE_APPROVED/VOID_CLAWBACK/ADMIN_GRANT/ADMIN_REVOKE`.

### JPA layer

New package `dev.melonthump.contrib`. The project previously had no JPA; `spring-boot-starter-data-jpa` was added (Hibernate 7.4.5). Flyway still owns the schema, with `spring.jpa.hibernate.ddl-auto=none` and `spring.jpa.open-in-view=false`. Existing JdbcTemplate stores are untouched, and the JPA transaction manager also serves their `@Transactional` methods (all existing tests pass).

- **Entities:**
  - `Contributor`: implements `Persistable` so a new id is INSERTed, not merged.
  - `Sample`.
  - `AuditLogEntry`: `@Immutable`, no setters.
  - `AdFreeLedgerEntry`: `@Immutable`.
- **Repositories** extend the bare Spring Data `Repository`, so they expose only the methods declared:
  - `AuditLogRepository` and `AdFreeLedgerRepository` have save and read only, with **no update or delete paths**.
  - `SampleRepository` has no delete method, because removal is void-marking.
  - `ContributorRepository` has no delete method.
- **Balance query:** `AdFreeLedgerRepository.balanceOf(id)` = `coalesce(sum(delta), 0)`. It is the raw sum: flooring at zero on clawback is a write-side rule for the later earning-rules package.
- **`AuditLogService.record(...)`** uses `Propagation.MANDATORY`: an audit row always commits or rolls back together with the change it describes.

## 3. Contribution APIs (`/api/v1/contributions`, new)

**`POST /api/v1/contributions/applications`** with body `{"contributorId": uuid, "note": string}`:
- `201` + `{contributorId, status:"PENDING", createdAt, updatedAt}` on create. Writes one audit row: actor = the contributor id, action `APPLICATION_SUBMITTED`, object `CONTRIBUTOR`/id, before `null`, after `{contributorId,status,note}`.
- **Idempotent:** re-posting an existing contributorId returns `200` with the stored record unchanged. The note is **not** overwritten and **no** audit row is written. This holds in any status, so a DECLINED or REVOKED applicant re-posting just gets their record back.
- Race-safe: concurrent first posts produce exactly one row and one audit row (tested with 8 threads).
- `400` when contributorId is missing or malformed, the note is missing or blank, the note is longer than **1000 chars**, or the body is not JSON. The note is stored trimmed.

**`GET /api/v1/contributions/status?contributorId=…`**:
- `200` + `{contributorId, status, adFreeBalance}`, where the balance is 0 with no ledger rows.
- Unknown id → `404` `{"error":"contributor_not_found","detail":…}`.
- Missing or malformed id → `400`.

Timestamps are ISO-8601 UTC strings (`Instant.toString()`).

## 4. Admin APIs (`/api/admin/**`, new, separate from `/api/v1`)

- **`GET /api/admin/applications[?status=PENDING|APPROVED|DECLINED|REVOKED]`** (case-insensitive) → `[{contributorId, note, status, createdAt, updatedAt}]`, oldest first. A bad status gives `400`.
- **`POST /api/admin/applications/{id}/approve`**: PENDING, DECLINED or REVOKED → APPROVED. Approving a revoked contributor is the design's "switch back on" toggle. Audit action `APPLICATION_APPROVED`.
- **`POST /api/admin/applications/{id}/decline`**: PENDING → DECLINED. Audit action `APPLICATION_DECLINED`.
- **`POST /api/admin/contributors/{id}/revoke`**: APPROVED → REVOKED. Audit action `CONTRIBUTOR_REVOKED`.

Behaviour shared by the three actions:
- Each returns the admin view and writes an audit row with actor `owner`, before `{…status:old}` and after `{…status:new}`.
- Repeating an action on a contributor already in the target state is a no-op `200` with no audit row.
- Any other transition gives `409` `{"error":"illegal_transition",…}` and writes nothing.
- Unknown id gives `404`; a malformed id gives `400`.
- Transitions take a row lock (`PESSIMISTIC_WRITE`), so concurrent admin actions serialize.

**Authentication:** none in the app, per the design (Cloudflare Access at the edge, no login). This is stated in the `AdminController` Javadoc. **Addition beyond the spec:** the controller only exists when `melonthump.admin.enabled=true` (env `MELONTHUMP_ADMIN_ENABLED`, **default false**); otherwise every `/api/admin` path is a plain 404. Reason: the app does not authenticate these calls, so deploying this build to a host whose Access policy does not yet cover `/api/admin/**` would expose unauthenticated approve and revoke on the public API host. Turn it on per environment once Access is in place. Tests and the `qa` profile enable it, and `AdminDisabledTest` covers the off state.

## 5. QA profile

- `application-qa.properties`: H2 in-memory, PG mode, schema from the **same Flyway migrations** (no separate schema needed). It also enables the admin API, the attest simulator bypass and a stats admin token, so QA can drive both new and existing endpoints.
- H2 stays `test` scope by default. The new Maven profile `-Pqa` widens it to `runtime` through a `${h2.scope}` property. **The production jar and Docker image contain no H2** (verified with `unzip -l`). Starting a non-qa build with `--spring.profiles.active=qa` fails at boot, because the H2 driver is missing, so the profile cannot silently run in prod.
- **One-command boot** (from the repo root; details in `QA-RUN.md`):
  ```bash
  JAVA_HOME=/Users/Shared/jdks/temurin-25/Contents/Home \
    /Users/Shared/jdks/apache-maven-3.9.11/bin/mvn -f server/pom.xml -Pqa spring-boot:run -Dspring-boot.run.profiles=qa
  ```
  Both this path and the packaged-jar path (`-Pqa package` then `java -jar … --spring.profiles.active=qa`) were booted and smoke-tested with curl: 201 → 200 idempotent → status → list → approve → 409 decline → revoke → 404 unknown.

## 6. Backward compatibility check

- All 35 pre-existing tests pass unchanged.
- I also booted the **pre-change jar** and the **new jar** side by side (same H2 config) and diffed full HTTP responses (status line, headers, body) for 13 existing requests. These covered health, version policy (old and 1.2.0 clients, no param), invite code/status/attribute/confirm, stats upload, stats summary (with and without a token), an unattested upload, and an unknown path.
- Result: identical, except the key order inside the existing `ApiExceptionHandler` 401 body (`{"error","detail"}` vs `{"detail","error"}`). That is **pre-existing nondeterminism**: it uses `Map.of`, whose iteration order is randomized per JVM. Two runs of the *old* jar differ in exactly the same way. I did not touch that handler (out of scope). The new handler uses a fixed order.
- `/v3/api-docs` gains the new endpoints (additive). No iOS, k8s or version-policy code was touched.

## 7. Left out / unsure — please check

1. **Not run against real PostgreSQL** (none available locally). V4 uses only portable SQL. JPA type mappings are standard (UUID → `uuid`, `Instant` → `timestamptz`, `LocalDate` → `date`, enums/strings → `varchar`, `List<String>` → `text`). Schema validation is off (`ddl-auto=none`), so any mismatch would surface at query time, not boot. **Recommend running the suite once against a PG instance, or watching the first dev deploy.**
2. **Admin enable flag** (§4) is an addition beyond the task text. In prod/dev, admin endpoints stay 404 until `MELONTHUMP_ADMIN_ENABLED=true` is set (k8s manifests deliberately not touched).
3. **Audit actor for admin actions** is the literal `owner`, as the task specifies. Design §7.11 says "who = the Cloudflare Access identity". Reading `Cf-Access-Authenticated-User-Email` is a small follow-up.
4. **Contribution endpoints are not App Attest gated** (the task did not ask for it; existing invite/stats endpoints are). The status lookup is effectively keyed on an unguessable UUID. Decide whether 2.0 should gate them.
5. Choices the spec left open, which I made:
   - Note max length is 1000.
   - Re-posting does not reopen a DECLINED or REVOKED application.
   - Approve is allowed from DECLINED and REVOKED.
   - Repeated actions are no-ops without audit rows.
   - `samples.id` is BIGSERIAL; a client record UUID for idempotent upload can be added later as an additive column.
   - `variety` is NOT NULL (the spec did not mark it nullable).
   - `source` is free text, max 64 chars.
   - Taste-tag vocabulary is not validated yet (the design lists tags as "e.g.").
6. **Not in this package** (per the task): sample APIs, material file storage, preliminary-review fields, ledger earning/clawback wiring, ad-free grants, `adExempt` policy extension, an audit-log read endpoint, the admin web page.
7. The production jar grows by Hibernate (~15 MB of `hibernate-core`, plus its dependencies).
8. `TASK-S1.md` (the task brief) was left untracked and is not committed.
