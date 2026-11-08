# QA run — standalone server boot (in-memory H2)

The server boots for QA without PostgreSQL using the `qa` Spring profile:
an in-memory H2 database in PostgreSQL compatibility mode, with the schema
built by the **same Flyway migrations** as production (V1–V4). Data lives
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

## Smoke check

```bash
B=http://localhost:8080; U=$(uuidgen | tr A-Z a-z)
curl -s -XPOST $B/api/v1/contributions/applications -H 'Content-Type: application/json' \
  -d "{\"contributorId\":\"$U\",\"note\":\"QA tester\"}"          # 201, PENDING
curl -s "$B/api/v1/contributions/status?contributorId=$U"           # PENDING, adFreeBalance 0
curl -s "$B/api/admin/applications?status=PENDING"
curl -s -XPOST $B/api/admin/applications/$U/approve                 # APPROVED
curl -s -XPOST $B/api/admin/contributors/$U/revoke                  # REVOKED
```

Swagger UI: `http://localhost:8080/swagger-ui.html`. No endpoint reads
the audit log yet (it is not in this package). Audit rows are verified by
the integration tests (`ContributionApiTest`, `AdminApiTest`,
`ContributorDataLayerTest`).
