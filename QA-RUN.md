# QA run — standalone server boot (in-memory H2)

The server boots for QA without PostgreSQL using the `qa` Spring profile:
an in-memory H2 database in PostgreSQL compatibility mode, with the schema
built by the **same Flyway migrations** as production (V1–V6). Data lives
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

Swagger UI: `http://localhost:8080/swagger-ui.html`.
