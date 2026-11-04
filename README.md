# 🍉 MelonThump

Tap a watermelon, let your iPhone judge its ripeness.

拍一拍西瓜，让 iPhone 告诉你它熟没熟。

A father-daughter side project: a native iOS app + a slim Spring Boot server.
The app records the sound of a tap on the phone itself and analyses it **on
the device** — recordings never leave the phone. The server only serves a
health check and the client version policy.

一个父女合作的业余项目：原生 iOS App + 极简 Spring Boot 服务端。App 在手机上
录下拍瓜声并**在本地完成分析**——录音永不离开手机。服务端只提供健康检查与
客户端版本策略两件事。

## Architecture 架构

```
┌────────────────────────────┐                ┌──────────────────────┐
│   iOS app (SwiftUI)        │  at launch     │  Spring Boot server  │
│                            │  GET version   │                      │
│ - AVAudioEngine recording  │ ── policy ───► │ - GET /api/health    │
│ - LocalAnalyzer (on-device │ ◄── JSON ───── │ - GET /api/v1/       │
│   FFT + thump gates)       │                │   version/           │
│ - verdict card             │                │   getclientversion   │
│ - AdMob rewarded ads +     │                │ - Swagger UI         │
│   local credit wallet      │                │                      │
└────────────────────────────┘                └──────────────────────┘
```

- **Analysis is fully on-device** (heuristic-v2.2): a 5-second countdown
  recording, time-domain + spectral thump gates, then a verdict from the
  tap's dominant resonant frequency. Offline by design; no upload, ever.
- **分析全在本地**（heuristic-v2.2）：5 秒倒计时录音，时域 + 频谱双重拍击
  门控，再按主共振频率出判定。天生离线，永不上传。
- **The server is a policy point, not a compute point.** It tells clients
  the latest app version, the minimum supported version and the credit
  policy — and, from 1.1.0, collects anonymous usage statistics (see
  Roadmap).
- **服务端是策略点，不是算力点。**它只下发最新版号、最低支持版本与 credit
  策略；1.1.0 起再加一件事：收集匿名使用量统计（见路线图）。

## Ripeness heuristic 判定规则（占位阈值）

Ripe watermelons sound deep and hollow when tapped; unripe ones go "ping".
The analyser maps the tap's **dominant resonant frequency** to a verdict:

熟瓜拍起来声音低沉空洞，生瓜则是清脆的“乒”。分析器按拍击的**主共振频率**
映射判定：

| dominant freq 主频 | verdict 判定 |
|--------------------|--------------|
| < 160 Hz           | OVERRIPE 过熟 |
| 160–280 Hz         | RIPE 熟      |
| > 280 Hz           | UNRIPE 生    |

These thresholds are **placeholders, not yet calibrated** on labelled real
melons. Collecting labelled samples (tap → cut open → record the truth) is
the current top priority.

这些阈值是**占位值，尚未用真实瓜标注样本校准**。采集标注样本（拍瓜 → 切开
→ 记录真实生熟）是当前第一优先级。

## Quick start 快速开始

### Server 服务端

```bash
cd server
mvn clean install   # must pass before any commit 任何 commit 前必须通过
mvn spring-boot:run
```

- Health 健康检查： http://localhost:8080/api/health
- Swagger UI: http://localhost:8080/swagger-ui.html
- Or with Docker 或用 Docker: `cd server && docker build -t melonthump-server .`

Environments 环境： prod `melonthump.stephaniegao.me` · dev
`melonthump-dev.stephaniegao.me` (k3s + ArgoCD; versions and images are
produced on the `development` branch only — see `server/README.md`).

环境：prod `melonthump.stephaniegao.me`、dev `melonthump-dev.stephaniegao.me`
（k3s + ArgoCD；版本与镜像只在 `development` 分支产生——见 `server/README.md`）。

### iOS app

Requires Xcode 16+ and an iPhone simulator or device (iOS 17+).

需要 Xcode 16+ 与 iPhone 模拟器或真机（iOS 17+）。

```bash
open ios/MelonThump.xcodeproj
```

The app talks to the deployed backends (in-app Prod/Dev selector, Prod by
default) — no local server needed. Tap *Start*, thump the melon once during
the countdown, and read the verdict card.

App 直连已部署的后端（应用内 Prod/Dev 选择器，默认 Prod），无需本地服务端。
点开始，在倒计时内拍一下瓜，看结果卡即可。

## Status & roadmap 现状与路线图

- **1.0.0** — submitted to App Store review (manual release); rewarded ads,
  the local credit wallet and the launch-promo mode are in.
- **1.0.0**——已提交 App Store 审核（手动发布）；激励广告、本地 credit
  钱包、上线推广模式均已就位。
- **Calibration** — labelled sample collection (target: first 100) to
  replace the placeholder thresholds.
- **校准**——采集标注样本（首批目标 100 例）替换占位阈值。
- **1.1.0 (designed)** — server ↔ client communication: anonymous usage
  statistics with an ad-request ledger reconciled against AdMob,
  server-issued ad configuration, App Attest gating.
- **1.1.0（已完成设计）**——服务端 ↔ 客户端通信：匿名使用量统计与广告请求
  流水对账（对 AdMob）、服务端下发广告配置、App Attest 门控。
- **Later** — a trained model (ONNX/CoreML) may replace the heuristic once
  the labelled dataset is big enough.
- **将来**——标注数据量足够后，用训练模型（ONNX/CoreML）替换启发式规则。

## More docs 更多文档

- `server/README.md` — server endpoints & configuration 服务端端点与配置
- `ios/README.md` — iOS project notes iOS 工程说明
- `docs/app-store-materials.md` — App Store listing materials 商店上架素材

## Team 团队

- UI design 界面设计： Stephanie
- Architecture 架构： Xuyang
- Coding & deployment 编码与部署： Pepper (AI)
