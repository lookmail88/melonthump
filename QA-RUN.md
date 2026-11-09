# QA run — standalone server boot (in-memory H2)

The server boots for QA without PostgreSQL using the `qa` Spring profile:
an in-memory H2 database in PostgreSQL compatibility mode, with the schema
built by the **same Flyway migrations** as production (V1–V7). Data lives
only for the life of the process; every boot starts empty.

The H2 driver is not in the production build. The `qa` **Maven** profile
(`-Pqa`) adds it to the runtime classpath. You need both the Maven profile
and the Spring profile.

## One command (from the repo root)

```bash
JAVA_HOME=/Users/Shared/jdks/temurin-25/Contents/Home \
  /Users/Shared/jdks/apache-maven-3.9.11/bin/mvn -f server/pom.xml -Pqa spring-boot:run -Dspring-boot.run.profiles=qa
```

The server listens on `http://localhost:8080` and is ready when
`GET /api/health` returns `{"status":"UP"}`. To use another port, add
`-Dspring-boot.run.arguments=--server.port=18081`.

## Packaged-jar equivalent

```bash
JAVA_HOME=/Users/Shared/jdks/temurin-25/Contents/Home \
  /Users/Shared/jdks/apache-maven-3.9.11/bin/mvn -f server/pom.xml -Pqa clean package -DskipTests
/Users/Shared/jdks/temurin-25/Contents/Home/bin/java -jar server/target/melonthump-server-1.13.0.jar --spring.profiles.active=qa
```

A jar built with `-Pqa` contains H2. **Never deploy it.** Production images
are built by `server/Dockerfile` without the profile.

## What the `qa` profile turns on (`server/src/main/resources/application-qa.properties`)

| Setting | Value | Why |
|---|---|---|
| datasource | `jdbc:h2:mem:melonthump-qa;MODE=PostgreSQL;...` | no external DB |
| `melonthump.admin.enabled` | `true` | `/api/admin/**` exists (in prod it is off until Cloudflare Access covers it) |
| `melonthump.attest.debug-bypass-enabled` | `true` | existing attested endpoints accept `X-Attest-Bypass: simulator` |
| `melonthump.attest.accept-develop` | `true` | dev-flavoured attestation |
| `melonthump.stats.admin-token` | `qa-admin-token` | `GET /api/v1/stats/summary` with `X-Admin-Token: qa-admin-token` |
| `melonthump.contrib.adfree-per-approved-sample` | `5` (default, not overridden) | ad-free units granted when a complete sample is approved; env `MELONTHUMP_CONTRIB_ADFREE_PER_APPROVED_SAMPLE` |
| `melonthump.contrib.storage-dir` | `${java.io.tmpdir}/melonthump-qa-materials-<random uuid>` | contributed photos/recordings go to a fresh temp dir per boot; the path is logged at startup (`contributed material storage at …`). Override with env `MELONTHUMP_CONTRIB_STORAGE_DIR`. |

**Every `/api/v1/contributions/**` endpoint is App Attest gated** (since S2).
With the `qa` profile send `X-Attest-Bypass: simulator` on those calls;
without it they return 401.

## Smoke check

```bash
B=http://localhost:8080; U=$(uuidgen | tr A-Z a-z); H='X-Attest-Bypass: simulator'
curl -s -XPOST $B/api/v1/contributions/applications -H "$H" -H 'Content-Type: application/json' \
  -d "{\"contributorId\":\"$U\",\"note\":\"QA tester\"}"          # 201, PENDING
curl -s -H "$H" "$B/api/v1/contributions/status?contributorId=$U"   # PENDING, adFreeBalance 0
curl -s "$B/api/admin/applications?status=PENDING"
curl -s -XPOST $B/api/admin/applications/$U/approve                 # APPROVED
curl -s -XPOST $B/api/admin/contributors/$U/revoke                  # REVOKED
curl -s -XPOST $B/api/admin/applications/$U/approve                 # APPROVED again

# Samples (S2): multipart submit, append, list, detail, withdraw
head -c 2000 /dev/urandom > /tmp/a.jpg; head -c 3000 /dev/urandom > /tmp/r.wav
curl -s -H "$H" $B/api/v1/contributions/samples \
  -F "meta={\"contributorId\":\"$U\",\"variety\":\"SEEDLESS\"};type=application/json" \
  -F "appearance=@/tmp/a.jpg;type=image/jpeg"                       # 201, complete:false, id N
curl -s -H "$H" "$B/api/v1/contributions/samples/N/parts?contributorId=$U" \
  -F "recording=@/tmp/r.wav;type=audio/wav"                         # 200, recording:true
curl -s -H "$H" "$B/api/v1/contributions/samples?contributorId=$U"     # newest first
curl -s -H "$H" "$B/api/v1/contributions/samples/N?contributorId=$U"   # incl. files (no paths)
curl -s -XDELETE -H "$H" "$B/api/v1/contributions/samples/N?contributorId=$U"   # 204, files gone
```

### Owner review, ledger, exemptions, audit (S3)

```bash
# Review (sample N from a complete submission). Admin calls need no bypass header.
curl -s "$B/api/admin/samples?status=SUBMITTED&contributorId=$U&limit=50"   # newest first
curl -s "$B/api/admin/samples/N"                                  # detail; files[].id for download
curl -s -o /tmp/cut.png "$B/api/admin/samples/N/files/F"          # bytes with stored content type
curl -s -XPOST $B/api/admin/samples/N/return -H 'Content-Type: application/json' \
  -d '{"reason":"cut-open photo is blurry"}'                      # RETURNED (blank/missing reason -> 400)
curl -s -XPOST $B/api/admin/samples/N/approve                     # 409 while RETURNED
curl -s -H "$H" "$B/api/v1/contributions/samples/N/parts?contributorId=$U" \
  -F "cutOpen=@/tmp/a.jpg;type=image/jpeg"                          # resubmit -> SUBMITTED
curl -s -XPOST $B/api/admin/samples/N/approve                     # APPROVED; +5 if complete
curl -s -XPOST $B/api/admin/samples/N/void                        # VOIDED; clawback min(balance, 5)

# Ledger + exemption
curl -s -XPOST $B/api/admin/contributors/$U/adfree/grants -H 'Content-Type: application/json' \
  -d '{"delta":3,"reason":"bonus"}'                               # {requestedDelta, appliedDelta, balance}
curl -s "$B/api/admin/contributors/$U/adfree"                     # balance + entries, newest first
curl -s -XPOST -H "$H" -H 'Content-Type: application/json' $B/api/v1/contributions/adfree/spend \
  -d "{\"contributorId\":\"$U\"}"                                  # {spent, exempt, balance}; 409 at 0
curl -s -XPOST $B/api/admin/contributors/$U/exemption -H 'Content-Type: application/json' \
  -d '{"permanent":true}'                                         # status gains adExemptPermanent:true

# Install allowlist + policy
I=$(uuidgen | tr A-Z a-z)
curl -s -XPOST $B/api/admin/exemptions -H 'Content-Type: application/json' -d "{\"installId\":\"$I\",\"note\":\"owner\"}"
curl -s -H "X-Install-Id: $I" "$B/api/v1/version/getclientversion?currentVersion=2.0.0"   # "adExempt":true
curl -s -H "X-Install-Id: $I" "$B/api/v1/version/getclientversion?currentVersion=1.2.0"   # no adExempt field
curl -s "$B/api/admin/exemptions"; curl -s -XDELETE "$B/api/admin/exemptions/$I"          # 204, then 404

# Audit read
curl -s "$B/api/admin/audit?objectType=SAMPLE&objectId=N&limit=50"
```

Since S3 the RETURNED-resubmit path and the APPROVED / VOIDED 409 paths of
the S2 sample endpoints are reachable black-box through the review
endpoints above, and audit rows are readable through `GET /api/admin/audit`.

### Admin page, runtime settings, Access identity, preliminary review, overview (S4)

**Admin page:** open `http://localhost:8080/admin/` in a browser (Safari, Chrome or Edge;
phone-width works too). It is plain static HTML/CSS/JS calling `/api/admin/**`; no login
locally (Cloudflare Access fronts it in production). Sections: Overview · Contributors ·
Sample review · Ad switches. `/admin` redirects to `/admin/`.

```bash
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' $B/admin/          # 200 text/html
curl -sI $B/admin/ | grep -i content-security-policy                         # same-origin CSP

# Settings -> policy values (shapes unchanged; only values move)
curl -s $B/api/admin/settings                                     # 4 keys: value, defaultValue, overridden
curl -s -XPUT $B/api/admin/settings -H 'Content-Type: application/json' \
  -d '{"key":"credit_per_ad","value":"-1"}'                       # overridden:true
curl -s "$B/api/v1/version/getclientversion?currentVersion=1.1.0"  # "creditPerAd":-1, same fields as before
curl -s -XPUT $B/api/admin/settings -H 'Content-Type: application/json' \
  -d '{"key":"initial_free_thumps","value":"4"}'
curl -s "$B/api/v1/version/getclientversion?currentVersion=1.2.0"  # "initialFreeThumps":4
curl -s -XPUT $B/api/admin/settings -H 'Content-Type: application/json' \
  -d '{"key":"latest_version","value":"9.9.9"}'                   # 400: not a setting (release process only)
curl -s -XDELETE $B/api/admin/settings/credit_per_ad              # back to default; again -> 404
curl -s -XDELETE $B/api/admin/settings/initial_free_thumps
curl -s -XPUT $B/api/admin/settings -H 'Content-Type: application/json' \
  -d '{"key":"adfree_per_approved_sample","value":"7"}'           # next approved complete sample earns 7

# Actor: the Access email header becomes the audit actor; absent -> "owner"
curl -s -XPUT $B/api/admin/settings -H 'Content-Type: application/json' \
  -H 'Cf-Access-Authenticated-User-Email: qa@example.test' -d '{"key":"credit_per_ad","value":"2"}'
curl -s "$B/api/admin/audit?objectType=SETTING&objectId=credit_per_ad&limit=1"   # "actor":"qa@example.test"

# Pepper preliminary review (actor "pepper" unless the Access header is sent)
curl -s -XPOST $B/api/admin/samples/N/preliminary-review -H 'Content-Type: application/json' \
  -d '{"recommendation":"SUGGEST_RETURN","note":"cut-open photo is blurry"}'   # pepper* fields in admin shapes
curl -s "$B/api/admin/audit?objectType=SAMPLE&objectId=N&limit=1"             # PRELIMINARY_REVIEW, actor pepper
curl -s -H "$H" "$B/api/v1/contributions/samples/N?contributorId=$U"          # contributor shape: no pepper fields

# Overview (page D)
curl -s $B/api/admin/overview   # contributors{...}, samples{...}, completeSamplesApproved, pendingReview, adFreeOutstanding
```

With `melonthump.admin.enabled=false` the page still loads and shows an "Admin API
disabled" banner (every `/api/admin/**` call is 404).

Swagger UI: `http://localhost:8080/swagger-ui.html`.
