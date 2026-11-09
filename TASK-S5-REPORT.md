# TASK S5 — delivery report

iOS client for MelonThump 2.0: melon records, unified capture, the Model Improvement Program, owner-install ad exemption, the hero-art fix, and version 2.0.0.
Branch `2.0`. Spec sources: `TASK-S5.md`, `docs/2.0-design.md` v0.37, `docs/2.0-checklist.md` §2, `TASK-S2-REPORT.md` §2, `ContributionAttestGate`.
No server code was changed.

## 1. Build gate and tests

| What | Command | Result |
|---|---|---|
| Device build (the gate) | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/MelonThump.xcodeproj -scheme MelonThump -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` | **BUILD SUCCEEDED, 0 warnings** (Swift 6 strict concurrency) |
| `ios/Tools/promo-gate/run.sh` | | **83/83 passed** |
| `ios/Tools/next-melon/run.sh` | | **56/56 passed** |
| `ios/Tools/contrib-attest/run.sh` (new, §4) | with `QA_BASE`/`QA_CONTRIBUTOR` set | **6/6 vectors identical to the server; live check passed** |
| `ios/Tools/recognition-diagnosis/run.sh` | | runs, exit 0 |
| `ios/Tools/ml-equivalence/run.sh` | | **fails, but it already failed before this package** (see below) |
| Simulator smoke test (Debug, iPhone 18 Pro, iOS 27) | launched with `-screenshot-records / -record / -program / -program-about` | app stays up on every stage, so the DEBUG `L10n.assertComplete()` passes for all 3 languages; screens render as expected |

**About the gate command.** The command exactly as written in the task fails on this machine before it compiles anything. The error is `No profiles for 'dev.xuyang.melonthump' were found`, and `security find-identity` shows **0 signing identities**. It fails the same way on the untouched HEAD. So I ran the same command with `CODE_SIGNING_ALLOWED=NO`, which does the full compile and link and skips only code signing. A signed build needs a machine with the team's certificate.

**About `ml-equivalence`.** There is no XCTest target; the project's tests are the `ios/Tools/*` harnesses. `ml-equivalence` fails with `cannot find 'L10n' in scope` in `LocalAnalyzer.swift`. Its harness (864fbcb) was written before the i18n commit made `LocalAnalyzer` use `L10n`. None of its input files are modified by this package, so the failure is in HEAD as well. I left it alone; the fix would be a one-line `L10n` stub in `ml-equivalence/stub.swift`.

## 2. Deliverable 1 — melon record

- **Model:** `ios/MelonThump/MelonRecord.swift`, `MelonRecord`. Fields:
  - local id, `createdAt` / `updatedAt`
  - `variety` (preset enum, raw values = the server names)
  - `weightGrams` + `weightProvenance` (`SCALE_MEASURED / MANUAL_ESTIMATE / PHOTO_ESTIMATED`)
  - `photos` (rind close-up / whole melon), `cutOpenPhoto`
  - `thumps`: one entry per analysis with its verdict, confidence, Hz, decay, model, and the **RecordingArchive stem**
  - `feedback` (own score 0–100, taste tags, band truth)
  - `submission` (sample id, last server status, return reason, and what has already been uploaded)
  - `submittedSampleId` (computed, nullable)

  The record's verdict is the newest non-UNKNOWN thump. **There is no model score anywhere.**
- **Where the store lives:**
  - `Documents/MelonRecords/index.json` holds every record, newest first, written atomically on each change.
  - `Documents/MelonRecords/<record-uuid>/` holds that record's photos at full quality.
- **Recordings are linked, not copied.**
  - `RecordingArchive.save` gained an optional `onSaved(stem)` callback, and the record stores that stem.
  - The audio pipeline itself is unchanged.
  - Retention: records the user has worked on (photos, variety, weight, feedback, created by hand, or submitted) **pin** their stems, and the newest-20 sweep skips pinned stems. Plain background history follows the normal sweep. If a recording has been swept, the record shows "Recording removed" but keeps its verdict data.
- **History UI.** The menu drawer has a new **My Melons** entry (`RecordsListView`).
  - Each row shows the date, a thumbnail (the first rind photo, else the first photo, else Stephanie's `HeroMelon`), the variety and the verdict.
  - Tapping a row reopens the record. **+** starts a new record. Swipe deletes, with a confirmation.
- **1.2.0 journey unchanged.**
  - A home-screen thump files itself into a record in the background (`MelonRecordStore.attachThump`).
  - "Thump Another Melon" is still exactly the old reset, plus clearing the record target. The next-melon harness still passes.

## 3. Deliverable 2 — unified capture (`RecordViews.swift`, `RecordDetailView`)

The same steps for everyone:

1. **Appearance photos.** Two buttons: rind close-up (main) and whole melon (secondary). The whole-melon button shows the bank-card (ID-1) guidance. Each offers camera or library.
   - Camera shots are stored as full-resolution JPEG at quality 1.0.
   - Library picks keep their original bytes when the type is jpeg/png/heic/heif/webp; anything else is re-encoded to JPEG.
2. **Thump.** "Thump this melon" closes the sheet and runs the **normal home-screen flow** with the record as the target. Gates, credits, ads, stats and invites therefore behave exactly as for any thump. A small "Next thump goes to…" line with a cancel ✕ appears under the credits row while a target is set.
3. **Weight.** Optional and never required. Grams entry plus a choice between "Weighed on a scale" and "My estimate". `PHOTO_ESTIMATED` exists in the model but is never produced; there is no estimator.
4. **Variety.** A picker only: Seedless, Seeded, Mini, Yellow-flesh, Kirin, Black Beauty, Other / not sure. There is no text field.

After eating, the user adds the cut-open photo and their own feedback in an editor: score slider 0–100, multi-select tags CRISP / MEALY / SANDY / JUICY / SWEET / BLAND, and a band-truth picker.

`Info.plist` gains `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`.

## 4. Deliverable 4 — contributor program

Code is in `ContributorProgram.swift`, `ProgramViews.swift` and `ContributionAttest.swift`.

- **Entry.** Settings → **Join the Model Improvement Program** → explanation page → enrollment note → submit.
  - The explanation page covers the four parts, the ad-free earnings, and the privacy lines following §7 item 8: only the sample package is uploaded, it is linked only to the anonymous contributor ID, it is stored on the project's own server with no third-party cloud, the label wording ("never for tracking, never shared with third parties"), withdraw/delete truly deletes with backups ageing out within 30 days, and ordinary records never leave the phone.
  - The note is required: the button stays disabled until the trimmed note is non-empty, and it is capped at 1000 characters.
  - On submit, the **contributor UUID is generated on-device and stored in the Keychain** (`ContributorIdentity`: generic password, `AfterFirstUnlockThisDeviceOnly`, not synced). It is separate from the stats `installId`, which stays in UserDefaults. The app then POSTs `/applications` as App Attest JSON.
- **Program home.** Shows the status (PENDING / APPROVED / DECLINED / REVOKED), the ad-free balance and the permanent-exemption flag, all from GET `/status`. It also links to My contributions and the explanation.
- **Submitting a sample.** For APPROVED contributors, a record shows **Contribute this melon**. It builds the multipart in this order:
  1. `meta`: contributorId, variety, melonDate, weight + provenance, feedback
  2. appearance photos (≤ 12)
  3. the newest real thump's WAV
  4. `cutOpen`

  Incomplete packages can be submitted. **Send updates** later POSTs `/samples/{id}/parts` with only what has not reached the server yet: new photos, cut-open photo, changed feedback, or a newer recording.
  - The record keeps the sample id and mirrors its server status and return reason.
  - A photo over the server's 10 MB limit is uploaded as a smaller JPEG copy; the local original stays untouched.
- **My contributions** (GET `/samples`): each sample shows its status, a four-part completeness row, complete or incomplete, and the return reason when RETURNED. SUBMITTED and RETURNED samples have **Withdraw & delete**. Its confirmation says the server copies are truly deleted, backups age out within 30 days, and the record on the phone stays. It then sends DELETE.
- **Ad-free spend.** Both rewarded-ad gate alerts (the session gate and the promo gate) show **"Use 1 ad-free unit (N left)"** when the user is APPROVED, has a balance above 0 and is not permanently exempt. The app POSTs `/adfree/spend`.
  - On `spent:true` it calls `wallet.unlockSessionWithAd()`, which is exactly what a watched ad does.
  - On `exempt:true` it switches on suppression.
  - On failure it shows a calm message; the ad remains available.
- **Ad suppression.** `CreditWallet.adsSuppressed = policyAdExempt || contributorExempt`. When it is true, the promo gate and the session gate never trigger and no ad is offered; the credits row reads "Ad-free: thump away". Everyone else's flow is unchanged, and the promo-gate harness still passes.

### How the attest payload was verified

- The canonical payload code is in its own file (`ContributionAttest.swift`, Foundation + CryptoKit only). The body encoder and the attest payload iterate the **same `[MultipartPart]` array**, so the covered order is the wire order by construction.
- Multipart calls carry `contributorId` in the covered `meta` part, not in the query. The gate uses `getRequestURI()` without the query, so a query parameter would not be covered.
- The hashing chain is unchanged: `AttestManager` does SHA-256(challenge ‖ SHA-256(payload)) with the same X-Key-Id / X-Assertion / X-Challenge headers as the existing endpoints.
- **New harness `ios/Tools/contrib-attest/run.sh`:**
  1. It compiles the production Swift file on macOS. It also runs `Check.java` against the server's compiled `ContributionAttestGate` (`server/target/classes`), calling `canonicalMultipartString` / `sha256` directly. Six vectors (multipart submit with 5 parts, append, empty part list, GET status, DELETE, GET without query) are **byte-identical**.
  2. Live check against a `-Pqa` server with an approved contributor. A sample encoded by the production multipart encoder got **201, complete:true**, and every per-part SHA-256 the server stored equals the digest in our canonical string, **in wire order**. This shows Tomcat parses our framing and that our digests are over exactly the bytes the server hashes.
- What it cannot do: a real-device assertion end to end, because the simulator and macOS have no App Attest. The server's own `ContributionAttestTest` already covers signature verification over this canonical string.

## 5. Deliverable 4 (cont.) — owner install exemption

- `APIClient.fetchClientVersion` now always sends `X-Install-Id` (the stats installId, lowercased). This applies to both the launch-gate fetch and the wallet fetch.
- `ClientVersion.adExempt: Bool?` is read in both places. An absent field (older servers, or requests below 2.0.0) counts as false.

## 6. Deliverable 5 — hero art

`HeroMelon-fixed.png` md5 verified as `21f85d143eddb94f2632de89d83a7af2` before installing. It has the same 470×447 dimensions as the old file. It was copied over `HeroMelon.imageset/HeroMelon.png`, and `Contents.json` and every other asset are untouched. The root copy `HeroMelon-fixed.png` is left untracked.

## 7. Deliverable 6 — version and robustness

- `MARKETING_VERSION = 2.0.0` (Debug + Release).
- The environment rule is unchanged (`AppIdentity.resolvedEnvironment` was not touched).
- **Fail-soft:**
  - Every contribution call maps transport errors, attestation failure, and any 404 whose body is not `{"error":"contributor_not_found"}` (for example Spring's default 404 for a missing route) to "Not available yet". The program screen then shows that state with a retry.
  - The launch standing refresh is silent.
  - Records, thumping, gates and ads never wait on or depend on these calls.
  - The last known standing is cached per environment in UserDefaults, so an offline launch keeps a contributor's balance and exemption.

## 8. Decisions I made where the spec was open

1. **When a home thump creates a record.** It continues the newest home-created record only if that record holds nothing but UNKNOWN takes from the last 15 minutes (the user is still trying the same melon). Otherwise it starts a new record.
2. **Record thumps reuse the home flow** rather than embedding a second recorder. That keeps one audio pipeline and one gate implementation.
3. **Menu drawer.** It gets a 4th entry, My Melons. The 1.2.0 "exactly three, no History" decision is superseded by design §2 item 8; the comment is updated.
4. **Variety must be chosen before Contribute.** The server requires it. "Other / not sure" is always available, and the footer says so.
5. **Not captured:** `source` (purchase source) and knock position. The task's capture steps do not list them, and the server treats them as optional.
6. **Feedback** is sent only as a whole (score + band required, tags optional), which matches the server rule.
7. **Retention pinning** applies only to records the user has worked on, so plain history does not grow storage without limit.
8. **Camera photos** are saved at JPEG quality 1.0 and full resolution. The upload copy is reduced only when it is over 10 MB.
9. **Permanent exemption** is applied from `/status` whenever the contributor is APPROVED with `adExemptPermanent`, and also from a `spend` answer of `exempt:true`.
10. **Deleting a submitted record locally** warns that the server sample stays until it is withdrawn in My contributions.
11. **New DEBUG-only screenshot stages** for QA: `-screenshot-records`, `-screenshot-record`, `-screenshot-program`, `-screenshot-program-about`.
12. **Not done in this package:**
    - the App Store privacy-label update (App Store Connect, outside the repo);
    - real-device verification of camera, Keychain and App Attest;
    - the stale `ios/gen_pbxproj.py` file list (the pbxproj is maintained by hand, as its README says);
    - the pre-existing `ml-equivalence` breakage.
    - Multipart bodies are built in memory; a record with 12 large photos plus the WAV could approach the server's 100 MB request cap.
