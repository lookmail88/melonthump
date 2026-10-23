# MelonThump — App Store Connect 上架材料 / Listing Materials

Prepared 2026-10-23 for version 1.0.0 (build 5), iPhone only, free with ads.
每节先给，后附中文备注。带 ★ 的是提交前必须落位的项。

---

## 1. App 名称 / Name（≤30 字符）

```
MelonThump
```

## 2. 副标题 / Subtitle（≤30 字符）

```
Is this watermelon ripe?
```

## 3. 推广文本 / Promotional Text（≤170 字符，可随时改、不需审核）

```
Thump the melon, tap record, and let MelonThump listen. In seconds you'll know whether your watermelon is unripe, ripe, or past its prime.
```

## 4. 描述 / Description

```
Thump it. Record it. Know before you cut it.

Picking a good watermelon shouldn't be guesswork. MelonThump listens to the sound of your knock and tells you what your ears can't quite decide: is this melon unripe, ripe, or already overripe?

HOW IT WORKS
1. Hold your iPhone near a watermelon and give the melon a good thump.
2. Tap record — MelonThump captures five seconds of the knock.
3. Get the verdict on the spot: Unripe, Ripe, or Overripe.

PRIVATE BY DESIGN
The analysis happens entirely on your iPhone. Your recordings are never uploaded — there is no account, no sign-up, and the app works offline. (A quick network check at launch only fetches the current app-version policy.)

GOOD TO KNOW
• Every knock is different, and so is every melon — treat the verdict as a knowledgeable friend's opinion, not a guarantee.
• MelonThump is free to use and supported by ads. New installs start with free analyses, and you can earn more by watching a short ad.
• Designed with a smile: MelonThump was created by a father-daughter team who got tired of bringing home the wrong melon.

Stop gambling on green stripes. Thump first, cut once.
```

备注：描述里"录音不上云、离线可用、启动仅拉版本策略"均属实，与本地分析架构一致。

## 5. 关键词 / Keywords（≤100 字符，逗号分隔，不要加空格）

```
watermelon,ripe,ripeness,melon,thump,pick,fruit,summer,grocery,produce,scanner,sound
```

## 6. 本次更新 / What's New（1.0.0）

```
1.0.0 — our very first release! Thump a watermelon, record the sound, and find out whether it's unripe, ripe, or overripe.
```

## 7. 类别 / Categories

- Primary: **Utilities**（与 Info.plist 的 LSApplicationCategoryType 一致）
- Secondary: **Lifestyle**（可选；也可 Food & Drink，二选一即可）

## 8. 价格与销售范围 / Pricing

- Price: **Free（免费）**
- Availability: 全部国家/地区（或按需勾选）

## 9. ★ 支持 URL / Support URL

需要一页真实可达、含联系方式的页面。建议用 GitHub Pages 托管本文档第 10 节的隐私政策页 + 一页简短支持页（仓库 docs 目录即可），URL 形态：
`https://lookmail88.github.io/melonthump/support.html`（托管方式待拍板，备选：挂到服务端静态页）。

## 10. ★ 隐私政策 / Privacy Policy（全文，托管后把 URL 填进 ASC）

```
Privacy Policy for MelonThump
Last updated: October 23, 2026

MelonThump ("the app") is developed by Xuyang Gao ("we", "us"). This policy explains what information the app does and does not handle.

WHAT THE APP DOES NOT COLLECT
• No accounts: the app has no sign-up or login and does not ask for your name, email, or contacts.
• Your recordings stay on your phone: the watermelon-knock analysis runs entirely on your device. Audio recordings are processed on-device and are never uploaded to us or stored after the analysis.

WHAT IS COLLECTED AND BY WHOM
• Advertising (Google AdMob): the app shows ads provided by Google AdMob. To serve and measure ads, Google may collect and process data such as device identifiers (including the Identifier for Advertisers, IDFA, when you allow tracking), advertising interaction and usage data, coarse location derived from IP address, and diagnostic/performance data. Google's use of this data is described in Google's Privacy Policy (https://policies.google.com/privacy) and "How Google uses data from sites or apps that use our services" (https://policies.google.com/technologies/partner-sites).
• Consent choices: on first launch the app may present Google's consent form and Apple's App Tracking Transparency prompt. You can change your tracking choice anytime in iOS Settings > Privacy & Security > Tracking.
• Version check: at launch the app contacts our server to check the current version policy. Like any web request, this exposes your IP address to the server; we do not use it to identify or track you, and we do not operate analytics on it.

CHILDREN
The app is suitable for general audiences and does not knowingly collect personal information from children.

DATA SHARING
We do not sell personal information. Data described above is processed by Google AdMob for advertising as described in Google's policies.

YOUR CHOICES
You can decline tracking in the ATT prompt or in iOS Settings, reset your advertising identifier, and still use the app (ads may be less relevant).

CONTACT
Questions about this policy: lookmail88@gmail.com
```

备注：文本与 App 实际行为对齐（本地分析、AdMob 收集项、版本检查会暴露 IP）。年龄分级若填 4+ 且面向儿童的表述保持现状即可，不要在商店页宣称"专为儿童设计"，否则会触发 Google 的儿童定向广告合规要求（需另行设置）。

## 11. ★ App 隐私问卷 / App Privacy（在 ASC 里照此勾选，均针对 AdMob）

| 数据类型 | 用途 | 与身份关联 | 用于追踪 |
|---|---|---|---|
| Identifiers → Device ID | Third-Party Advertising | 否 | **是** |
| Usage Data → Advertising Data | Third-Party Advertising | 否 | **是** |
| Usage Data → Product Interaction | Third-Party Advertising / Analytics | 否 | 是 |
| Diagnostics → Crash Data | Analytics / App Functionality | 否 | 否 |
| Diagnostics → Performance Data | Analytics / App Functionality | 否 | 否 |
| Location → Coarse Location | Third-Party Advertising | 否 | 是 |

勾选口径：Data Used to Track You = Device ID、Advertising Data、Product Interaction、Coarse Location。提交前请对照 AdMob 后台当前的数据说明复核一遍（Google 偶尔调整口径）。

## 12. 年龄分级 / Age Rating（问卷要点）

- 成人/暴力/赌博/恐怖等项全部 **None/No**
- "Advertising"（是否展示广告）：**Yes**（不影响分级结果）
- Unrestricted Web Access：No；Gambling：No
- 预期结果：**4+**

## 13. ★ 审核备注 / Notes for App Review（粘贴到 App Review Information）

```
Thank you for reviewing MelonThump.

WHAT THE APP DOES
MelonThump judges watermelon ripeness from the sound of a knock. Hold the phone near any firm fruit or object, thump it, and tap the record button: the app records 5 seconds of audio, analyzes it entirely on-device, and shows one of four verdicts (Unripe / Ripe / Overripe / Couldn't tell). A real watermelon works best, but any firm object demonstrates the full flow. No account or login is required.

PERMISSIONS
Microphone access is required to record the knock. On first launch the app also shows Google's consent form and the App Tracking Transparency prompt (it serves ads via Google AdMob).

CREDITS AND ADS
New installs include 5 free analyses (shown at the bottom of the home screen), which is enough to test the complete flow. Analyses beyond that can be earned by watching a rewarded ad. The launch promotion is disabled on the production server, so you will see the standard credit flow.

The Server selector at the bottom of the home screen chooses between our production and development version-policy endpoints; production is the default — please leave it on Prod.

CONTACT
lookmail88@gmail.com
```

## 14. 版权 / Copyright

```
© 2026 Xuyang Gao
```

---

## 提交前清单（Checklist）

- [] 构建选 1.0.0 (5)（Archive 上传后在版本页选它）
- [] ★ 隐私政策托管并填 URL（第 10 节文本）
- [] ★ 支持 URL 落位（第 9 节）
- [] App 隐私问卷按第 11 节提交
- [] 年龄分级问卷完成（第 12 节）
- [] 截图：iPhone 6.9" 一套（待补，可由 Pepper 在模拟器出图）
- [] 加密出口合规：Info.plist 已含 ITSAppUsesNonExemptEncryption=false，问卷如实选"不使用非豁免加密"
- [] 提交审核后：回 AdMob 关联 App Store 链接，真实广告才开始投放
