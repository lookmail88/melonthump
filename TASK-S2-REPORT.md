# TASK S2 — delivery report

Sample submission, material storage and contributor self-service for 2.0, plus App Attest gating on all of `/api/v1/contributions/**`.
Branch `2.0`, building on S1. Spec sources: `docs/2.0-design.md` v0.37 (§2 item 8, §5 items 1 + 6, §7 items 7, 8, 10) and `docs/2.0-checklist.md` §3. The design doc is unchanged.

## 1. Build gate

Command (from `server/`):

```bash
JAVA_HOME=/Users/Shared/jdks/temurin-25/Contents/Home /Users/Shared/jdks/apache-maven-3.9.11/bin/mvn -B clean install
```

Result: **BUILD SUCCESS, 77 tests, 0 failures, 0 errors, 0 skipped.**

| Suite | Tests | Status |
|---|---|---|
| Pre-2.0 suites (10) | 35 | unchanged, pass |
| S1 suites (`ContributionApiTest`, `AdminApiTest`, `AdminDisabledTest`, `ContributorDataLayerTest`) | 25 | pass. The only edit: contribution calls now send `X-Attest-Bypass: simulator` |
| `api.SampleApiTest` (new) | 15 | pass |
| `api.ContributionAttestTest` (new) | 2 | pass |
| **Total** | **77** | |

I also ran these checks outside Maven:
- **Real Tomcat smoke test:** I booted the `-Pqa` jar and drove it with curl. Covered: 401 unattested, 403 pending, 201 complete submit, 413 for an 11 MB photo, 413 for a 26 MB recording (container limit), 413 for a 110 MB request, 400 for `text/plain`, append, list, delete. I checked the files on disk before and after the delete.
- **S1 QA harness** (`qa/s1_contribution_api_qa.py`) against the new qa jar: **30 passed, 0 failed**, after the one-line header change described in §8.
- **`/v3/api-docs`** returns 200 and lists the new paths.

As in S1, tests run on H2 in PostgreSQL mode. **V5 has not been run against a real PostgreSQL.**

## 2. Deliverable 1 — App Attest on every `/api/v1/contributions/**` endpoint

- **New `api/ContributionAttestGate`.** It uses the existing `AssertionService`, so the checks are the same as invite and stats: enrolled key, accepted environment, fresh single-use challenge, valid signature, strictly increasing counter.
- **Bypass.** It honours the same simulator bypass (`X-Attest-Bypass: simulator`), which works only when `melonthump.attest.debug-bypass-enabled=true`. The `test` and `qa` profiles already set that; prod never does.
- **Failure.** A failed check returns `401 {"error":"attestation_failed",…}` through the existing `ApiExceptionHandler`.
- **Order.** The gate runs **before** the request body or query is interpreted, so an unattested caller always gets 401 and never a 400/403/404.

What the assertion's client data covers (the client SHA-256-hashes exactly these bytes):

| Request kind | Covered bytes | Precedent |
|---|---|---|
| JSON POST (`/applications`) | exact request body bytes | same as invite / stats upload |
| GET / DELETE | `"<METHOD> <path>?<raw query>"`, e.g. `GET /api/v1/contributions/status?contributorId=…` (omit `?` if there is no query) | same pattern as the version-policy GET |
| multipart POST (samples, parts) | `"POST <path>"`, then for each part in request order `"\n<part name>:<lowercase hex sha256(part bytes)>"`, with no trailing newline | new; see §9 |

S1 endpoint changes:
- `POST /applications` now takes the raw body (so it can be attested) and parses it with Jackson.
- `GET /status` takes `contributorId` as a string and parses it after the gate.
- Responses, status codes and validation rules are otherwise unchanged. Malformed JSON, missing or bad ids, and blank notes still return 400, and the S1 tests pass unmodified apart from the header.

The `qa` and `test` profiles keep the bypass. `ContributionAttestTest` runs with the bypass **off** and real synthetic-chain assertions. It proves for each request kind that:
- a correct assertion passes;
- the bypass header, missing headers, or an assertion over different bytes (another photo, another contributorId, a GET assertion replayed as DELETE) all get 401.

## 3. Deliverable 2 — material file service (`contrib/MaterialStorage`)

- **Root directory:** `melonthump.contrib.storage-dir`, env `MELONTHUMP_CONTRIB_STORAGE_DIR`.
  - The default is `contrib-materials` under the working directory (added to `.gitignore`).
  - The `qa` profile uses `${java.io.tmpdir}/melonthump-qa-materials-<random uuid>`, a fresh directory each boot, because H2 sample ids restart at 1. The env var still overrides it.
  - The `test` profile uses a temp directory per test context.
  - The resolved path is logged at startup: `contributed material storage at …`.
- **Layout:** `<contributorId>/<sampleId>/<part>-<n>.<ext>`.
  - `part` is `appearance`, `recording` or `cut_open`.
  - `n` starts at 1 and is one more than the highest n already used for that part in that sample, whatever the extension.
  - `ext` comes from the content type (jpg/png/heic/heif/webp; wav/m4a/aac/mp3/caf/flac/aiff).
  - Files are streamed to a temp file while SHA-256 and size are computed, then renamed into place. Existing names are never overwritten.
- **Transaction-consistent:**
  - A file written inside a transaction that rolls back is deleted again (tested).
  - Deletions (withdraw, or a replaced part) run **right after commit**, which is still before the HTTP response is sent. So a rolled-back withdrawal never loses material, and a successful one has removed the files by the time the client sees 204.
  - Empty sample and contributor directories are removed too.
- **No public endpoint serves these files.** Views expose only part, sha256, size and content type, never paths or links (tested).
- **Limits** (declared content type of the part; the bytes are not sniffed):
  - Photo (appearance, cutOpen) ≤ 10 MB (10 485 760 bytes) and recording ≤ 25 MB. Larger gets `413 {"error":"file_too_large"}`.
  - Photos accept `image/jpeg|jpg|pjpeg|png|heic|heif|webp`.
  - Recordings accept `audio/wav|x-wav|wave|vnd.wave|mp4|m4a|x-m4a|aac|mpeg|caf|x-caf|flac|x-flac|aiff|x-aiff`.
  - Anything else gets `400 {"error":"unsupported_content_type"}`, and a 0-byte part gets 400.
  - **All files in a request are validated before anything is stored**, so a rejected request leaves no row, file or audit entry.
- **Container limits** in `application.properties`:
  - `spring.servlet.multipart.max-file-size` raised from 10MB to **25MB**, and `max-request-size` from 10MB to **100MB**.
  - `server.tomcat.max-part-count=32`.
  - No pre-existing endpoint accepts multipart, so this changes nothing for them.
  - Going over the container limits also gives 413 (verified on real Tomcat, with an empty body from Spring's default handler).

### Migration `V5__sample_files.sql` (additive, portable PG / H2)

`sample_files` columns:
- `id BIGSERIAL PK`
- `sample_id BIGINT NOT NULL FK→samples(id)`
- `part VARCHAR(16)`, CHECK `APPEARANCE/RECORDING/CUT_OPEN`
- `sha256 VARCHAR(64)` (lowercase hex)
- `size_bytes BIGINT`, CHECK > 0
- `content_type VARCHAR(100)` (normalized: lower-case, parameters stripped)
- `stored_path VARCHAR(512)`, UNIQUE, relative to the storage root
- `created_at timestamptz`

Index on `(sample_id, id)`. No existing table is altered. JPA: `SampleFile` entity and `SampleFileRepository`.

## 4. Deliverable 3 — `POST /api/v1/contributions/samples` (multipart/form-data)

Parts:

| Part | Content | Rule |
|---|---|---|
| `meta` | JSON object (≤ 64 KB) | required, exactly one |
| `appearance` | image | 0..n per request; ≤ **12 per sample** in total |
| `recording` | audio | ≤ 1 per request |
| `cutOpen` | image | ≤ 1 per request |
| any other name | — | 400 `invalid_part` |

`meta` fields:
- `contributorId`: UUID string, required.
- `variety`: required, one of the §7.7 presets `SEEDLESS/SEEDED/MINI/YELLOW_FLESH/KIRIN/BLACK_BEAUTY/OTHER`, exact case.
- `weightGrams`: optional positive integer.
- `weightProvenance`: optional, `PHOTO_ESTIMATED/MANUAL_ESTIMATE/SCALE_MEASURED`.
- `source`: optional string, trimmed, ≤ 64 chars, blank becomes null.
- `melonDate`: optional, `YYYY-MM-DD`.
- `feedback`: optional object `{score, tasteTags, bandTruth}`.

`null` values count as absent.

**Feedback.** If `feedback` is present it must be valid, otherwise the request gets 400:
- `score` is an integer from 0 to 100.
- `bandTruth` is `UNRIPE/RIPE/OVERRIPE`.
- `tasteTags` is an optional array drawn from **`CRISP/MEALY/SANDY/JUICY/SWEET/BLAND`**, exact case. An unknown tag gets 400 and the message names it. Duplicates are dropped.

Valid feedback sets `has_feedback`, the fourth part.

**Behaviour:**
- Creates the sample with status `SUBMITTED`.
- Stores the files and writes the `sample_files` rows.
- Sets the completeness flags from what actually arrived. `complete` is the AND of all four.
- Writes an audit row: actor = contributorId, action `SAMPLE_SUBMITTED`, object `SAMPLE`/id, before `null`, after a full snapshot including the file list (part, sha256, size, content type).
- A meta-only submission (no files) is a valid, empty, incomplete sample.

**Responses:**
- `201` with the **sample detail** (below).
- `400` for invalid meta or parts (`invalid_meta`, `invalid_part`, `unsupported_content_type`, `invalid_sample` for too many photos).
- `413` `file_too_large`.
- `403` `contributor_not_approved` (PENDING, DECLINED or REVOKED).
- `404` `contributor_not_found`.
- `401` when unattested.

Error bodies are `{"error": code, "detail": message}` with a fixed key order.

Sample detail shape, used for submit, append and GET one:

```json
{"id":1,"contributorId":"…","status":"SUBMITTED",
 "completeness":{"appearance":true,"recording":true,"cutOpen":true,"feedback":true},"complete":true,
 "returnReason":null,"variety":"KIRIN","weightGrams":4200,"weightProvenance":null,"source":null,"melonDate":null,
 "feedback":{"score":90,"tasteTags":["CRISP"],"bandTruth":"RIPE"},
 "files":[{"part":"APPEARANCE","sha256":"…","sizeBytes":2000,"contentType":"image/jpeg"}, …],
 "createdAt":"2026-11-08T17:45:50.534056Z","updatedAt":"…"}
```

`feedback` is `null` until feedback has been given.

## 5. Deliverable 4 — `POST /api/v1/contributions/samples/{sampleId}/parts` (multipart)

**Who is calling.** `contributorId` can be sent as a query parameter (`?contributorId=…`), in a `meta` part, or both. Both forms are accepted; if both are sent and they differ, the request gets 400. The optional `meta` is `{contributorId?, feedback?}`, and any other meta fields are ignored. File parts follow the same rules as submit.

**How parts are applied:**
- A new `recording` or `cutOpen` **replaces** the stored one: the old row is deleted and the old file is removed after commit.
- `appearance` photos are **added**, still capped at 12 per sample.
- `feedback` **overwrites** the stored feedback.
- Completeness is recomputed from the stored files and feedback on every append, and `updatedAt` is bumped.

**Allowed states.** Appending works while the sample is `SUBMITTED` or `RETURNED`. On a RETURNED sample it sets the status back to `SUBMITTED`, clears `return_reason`, and writes audit `SAMPLE_RESUBMITTED`. Otherwise it writes `SAMPLE_APPENDED`. Both audit rows carry before and after snapshots.

**Responses:**
- `200` with the sample detail.
- `403` `sample_forbidden`: wrong owner, or no such sample (deliberately the same response).
- `403` `contributor_not_approved`: the owner is no longer APPROVED.
- `404`: unknown contributor.
- `409` `illegal_sample_state`: the sample is APPROVED or VOIDED.
- `400` `nothing_to_append`: no files and no feedback.
- Plus the same 400/413 cases as submit.

The sample row is locked (`PESSIMISTIC_WRITE`) while an append or withdraw runs.

## 6. Deliverable 5 — self-service queries

- **`GET /api/v1/contributions/samples?contributorId=…`** returns `200 [SampleSummary]`, the caller's own samples **newest first**:
  ```json
  {"id","status","completeness":{appearance,recording,cutOpen,feedback},"complete","returnReason","variety","createdAt","updatedAt"}
  ```
  Unknown contributor gives 404; a malformed id gives 400.
- **`GET /api/v1/contributions/samples/{sampleId}?contributorId=…`** returns `200` with the sample detail, including the file list (part, sha256, sizeBytes, contentType; no paths or links). A wrong owner **or a nonexistent sample** gets `403 sample_forbidden`, so existence is never leaked. Unknown contributor gives 404; a non-numeric sampleId gives 400.
- **`DELETE /api/v1/contributions/samples/{sampleId}?contributorId=…`** returns `204`. In one transaction it deletes the file rows and the sample row and writes audit `SAMPLE_WITHDRAWN` (actor = contributor, before = full snapshot including file hashes, after = `null`). The files and the sample directory are deleted from disk right after commit, before the response is sent. Responses:
  - `409 illegal_sample_state` for APPROVED or VOIDED samples; nothing is touched.
  - `403` for a wrong owner or missing sample, so a second DELETE also gets 403.
  - `404` for an unknown contributor.

  A REVOKED or otherwise non-approved contributor **can still list, view and withdraw** their own samples (see §9).

## 7. Deliverable 6 — tests

**`SampleApiTest` (15 tests):**
- Complete submit: layout, bytes, sha256, size, the `complete` column, the audit row.
- Incomplete and meta-only submits.
- Approved and known contributor required: pending gets 403, unknown gets 404, revoked gets 403.
- Meta validation for every field, unknown part, two recordings.
- Feedback and taste-tag validation: unknown tag, wrong case, score out of range, missing or unknown band; all 6 tags accepted.
- Size limits: 413 at limit + 1 for photo, cut-open and recording; exactly-at-limit accepted.
- Type rejection: 400 for wrong types and empty files, with nothing stored.
- Appearance cap.
- Append: completes the sample, replaces the recording (old file gone), adds photos, overwrites feedback, writes audit before/after, accepts contributorId from meta, rejects an empty append or mismatched ids.
- RETURNED → SUBMITTED resubmit, with reason cleared and audit row.
- Append refused: foreign or missing sample (403), unknown contributor (404), APPROVED or VOIDED (409), revoked owner (403).
- List and detail: own samples only, newest first, no path leak, 403 for foreign or missing samples.
- Withdraw as true deletion: files and directory gone from disk, rows gone, audit row kept, a stranger's delete changes nothing.
- Withdraw rules: 409 for APPROVED or VOIDED with files intact; a revoked contributor can withdraw a RETURNED sample.
- Rollback cleanup of stored files.
- Every contribution endpoint returns 401 without the bypass header or with a wrong bypass value.

**`ContributionAttestTest` (2 tests):** real assertions with the bypass disabled, as described in §2.

## 8. QA boot

Unchanged command; `QA-RUN.md` has been updated (V5, storage directory, bypass header, sample smoke steps):

```bash
JAVA_HOME=/Users/Shared/jdks/temurin-25/Contents/Home \
  /Users/Shared/jdks/apache-maven-3.9.11/bin/mvn -f server/pom.xml -Pqa spring-boot:run -Dspring-boot.run.profiles=qa
```

Or the packaged jar: `mvn -f server/pom.xml -Pqa clean package -DskipTests`, then `java -jar server/target/melonthump-server-1.13.0.jar --spring.profiles.active=qa`.

**QA must now send `X-Attest-Bypass: simulator` on every `/api/v1/contributions/**` call.** I changed the S1 harness `qa/s1_contribution_api_qa.py` accordingly: `req()` adds the header only for `/api/v1/contributions` paths, a 4-line change. With that change it reports 30 passed, 0 failed against this build.

## 9. Decisions I made where the spec was open, and things left out

1. **Multipart attest payload.** The raw multipart body can't be reproduced on the server after Tomcat has parsed it, so the assertion covers a canonical per-part digest string instead (§2). **The iOS client must build the same string.** It is documented in the `ContributionAttestGate` Javadoc. Part order is the wire order.
2. **Attestation is checked after the multipart body is parsed** (it needs the part digests). An unattested caller can therefore make the server buffer up to 100 MB of temp multipart data before getting 401, though nothing is stored to the material directory.
3. **No binding between the attested key and the contributorId.** The invite endpoints bind the key to an installId, but there is no contributorId-to-install mapping (the contributor UUID is deliberately separate). The gate proves "a genuine app instance", as for the stats upload, but not "this contributor's device". Possible follow-up: record the attest keyId on the application and require it afterwards.
4. **Feedback validity:** `score` and `bandTruth` are required; `tasteTags` is optional and may be empty. Present-but-invalid feedback gets 400 rather than being silently ignored.
5. **Append semantics:**
   - A new recording or cut-open photo replaces the stored one, so a RETURNED sample can be fixed.
   - Appearance photos accumulate, capped at 12 per sample.
   - Feedback overwrites.
   - Appending requires the contributor to be APPROVED.
   - Bookkeeping fields (variety, weight, etc.) cannot be changed by append.
6. **403 for nonexistent samples** on append, GET and DELETE (not only GET), so existence never leaks. Unknown *contributors* still get 404, as in S1.
7. **Withdraw does not require APPROVED.** A revoked contributor keeps the §7.8 right to delete their own not-yet-approved samples. Listing and viewing are also allowed.
8. **DELETE returns 204** with no body.
9. **Submit and append return the full sample detail**, a superset of the "id, status, completeness flags, complete" the spec asks for.
10. **Content types:** the declared multipart content type is checked; the magic bytes are not. The accepted list is in §3.
11. **Limits I chose:** 12 appearance photos per sample, a 64 KB meta part, 100 MB per request.
12. **Not built in this package:**
   - Any way to move a sample to RETURNED, APPROVED or VOIDED (owner sample review is a later admin package). The resubmit and 409 paths are therefore tested by setting the status directly in the database, and **QA cannot reach them black-box yet**.
   - Admin viewing or download of materials.
   - Ledger earning when a sample is approved.
   - An audit-log read endpoint.
13. **Deployment notes** (no k8s change, per the task):
   - Production needs a persistent volume for `MELONTHUMP_CONTRIB_STORAGE_DIR`. The default `contrib-materials/` sits under the container working directory and would be lost when a pod restarts. With more than one replica the volume must be shared, or uploads pinned to a single replica.
   - Check the ingress body-size limit (nginx `proxy-body-size`, if used). Cloudflare caps requests at 100 MB.
14. **`SampleRepository` gained `delete`.** The S1 Javadoc said there was no delete path. It now exists, used only by the contributor's withdrawal, as §7.8 requires. Owner-side removal stays void-marking.
15. `TASK-S1.md` and `TASK-S2.md` (the task briefs) were left untracked and are not committed.
