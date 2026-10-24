# melonthump-server

Spring Boot service behind the MelonThump iOS app. Since the 2026-10-20
architecture change it does **not** analyse audio — analysis runs on the
iPhone (`LocalAnalyzer`). The server serves exactly two things: a health
check and the client version policy.

MelonThump iOS App 背后的 Spring Boot 服务端。自 2026-10-20 架构定版后它
**不做音频分析**——分析在 iPhone 本地完成（`LocalAnalyzer`）。服务端只做
两件事：健康检查与客户端版本策略。

## Requirements 环境要求

- OpenJDK 25 (LTS)
- Maven 3.9+

## Run locally 本地运行

```bash
cd server
mvn clean install   # must pass before any commit 任何 commit 前必须通过
mvn spring-boot:run
```

- Health 健康检查： `GET http://localhost:8080/api/health` → `{"status":"UP"}`
- Swagger UI: `http://localhost:8080/swagger-ui.html`
- OpenAPI JSON: `http://localhost:8080/v3/api-docs`

## API

### `GET /api/v1/version/getclientversion?currentVersion=1.0.0`

Returns the client version policy. Version comparison is numeric per
segment (missing segments count as 0).

返回客户端版本策略。版本按段做数字比较（缺段补 0）。

```json
{
  "platform": "ios",
  "latestVersion": "1.0.0",
  "minSupportedVersion": "1.0.0",
  "updateAvailable": false,
  "forceUpdate": false,
  "updateUrl": "",
  "creditPerAd": 1,
  "promoEndsAtEpochMillis": null
}
```

- `updateAvailable` — the client is below `latestVersion`; the app shows
  its full-screen update prompt (see `VersionGate` on the iOS side).
- 客户端低于 `latestVersion`；App 全屏提示更新（见 iOS 侧 `VersionGate`）。
- `forceUpdate` — the client is below `minSupportedVersion`, the manually
  maintained hard floor.
- 客户端低于 `minSupportedVersion`——手动维护的硬下限，低于即强制更新。
- `creditPerAd` — credits granted for one completed rewarded ad;
  **-1 declares a free day** (unlimited use, no ads, for the client's
  local day).
- 看完一支激励广告可得的 credit 数；**-1 即“免费日”**（按客户端本地
  日期，当天无限用、不显示广告）。
- `promoEndsAtEpochMillis` — end of the launch promo window (null = no
  promo). During the promo, the first thump after each fresh app launch
  costs one rewarded ad, then the session is unlimited.
- 上线推广期结束时刻（null = 无推广期）。推广期内每次新开 App 第一次
  拍瓜看一支激励广告，之后本次打开内无限用。

## Configuration 配置（`application.properties`）

| Key | Notes 说明 |
|---|---|
| `melonthump.client.latest-version` | **Never edit by hand** — CI stamps it from the iOS project's `MARKETING_VERSION` at image build time (Docker build-arg). **不手动改**——CI 构建镜像时从 iOS 工程 `MARKETING_VERSION` 注入（Docker build-arg）。 |
| `melonthump.client.min-supported-version` | Manual hard floor 手动维护的硬下限 |
| `melonthump.client.update-url` | App Store link, filled in after listing 上架后填 App Store 链接 |
| `melonthump.client.credit-per-ad` | Default 1; -1 = free day 默认 1；-1 为免费日 |
| `melonthump.client.promo-ends-at-epoch-millis` | Via env `MELONTHUMP_PROMO_ENDS_AT_EPOCH_MILLIS` 由 env 注入 |

## Database 数据库（配置已就位，1.1.0 起使用）

The server is stateless today. A datasource is already wired for the
1.1.0 statistics feature: `SPRING_DATASOURCE_URL / USERNAME / PASSWORD`
are injected from the `melonthump-db` k8s Secret and point to a dedicated
`melonthump` database inside the Retax PostgreSQL instances
(`postgres.retax-<env>.svc.cluster.local:5432`). No code consumes it yet.

服务端目前无状态。为 1.1.0 统计功能已预先接好数据源：`SPRING_DATASOURCE_*`
由 k8s Secret `melonthump-db` 注入，指向 Retax 的 PostgreSQL 实例内的
专用 `melonthump` 库（`postgres.retax-<env>.svc.cluster.local:5432`）。
目前尚无代码消费它。

## Versions & deployment 版本与部署

- The **server version line** (semantic-release tags, currently v1.8.1) is
  decoupled from the app version (`MARKETING_VERSION`, currently 1.0).
  Versions are cut **on the `development` branch only**; main never bumps.
- **服务端版本线**（semantic-release 标签，现 v1.8.1）与 App 版本
  （`MARKETING_VERSION`，现 1.0）脱钩。版本**只在 `development` 分支**
  产生；main 永不 bump。
- Images (`ghcr.io/lookmail88/melonthump-server`, tags `:dev` and
  `:v<release>`) are built and pushed by the development workflow only;
  ArgoCD deploys them to the `melonthump-dev` / `melonthump-prod`
  namespaces. Promoting the server to prod is the **last step** of a
  release — after the new app version is live on the App Store.
- 镜像（`ghcr.io/lookmail88/melonthump-server`，标签 `:dev` 与
  `:v<release>`）只由 development 的 workflow 构建推送；ArgoCD 部署到
  `melonthump-dev` / `melonthump-prod`。服务端进 prod 是整个发布的
  **最后一步**——须在新版 App 上架之后。

## Docker

```bash
cd server
docker build -t melonthump-server .
docker run -p 8080:8080 melonthump-server
```
