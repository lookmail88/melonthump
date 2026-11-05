# MelonThump Model File Format (.ml) — v1

> **Status**: finalized 2026-11-05 (Pepper). Implements §1 of `docs/1.2.0-design.md`.
>
> **状态**：2026-11-05 定稿（Pepper）。落实 `docs/1.2.0-design.md` §1。

1. **Container**: a `.ml` file is a UTF-8 JSON document in a file whose name ends in `.ml`. (The extension names the role — a model — not the encoding.)
   **载体**：`.ml` 文件即一份 UTF-8 JSON 文档，文件名以 `.ml` 结尾。（扩展名表的是角色——模型文件——不是编码格式。）

2. **Top-level fields**:
   **顶层字段**：

   | Field | Type | Required | Meaning |
   |---|---|---|---|
   | `formatVersion` | number | yes | Must be `1`. A file with a higher value is skipped (forward-incompatible). |
   | `modelId` | string | yes | `[a-z0-9.-]` (dot allowed — corrected 2026-11-05), unique per source. `baby-1.0` is reserved for the built-in model. |
   | `modelVersion` | string | yes | The model's own version label (e.g. `"1.0"`). |
   | `displayName` | string | yes | Shown in the model picker (e.g. `"Baby 1.0"`). |
   | `kind` | string | yes | `"heuristic-bands"` in format v1. Other values are reserved for future model kinds (the loader seam); a v1 loader skips kinds it does not implement. |
   | `parameters` | object | yes (for `heuristic-bands`) | See item 3. |
   | `notes` | string | no | Free-form, ignored by the loader. |

3. **Parameters (`heuristic-bands`)**: every numeric tunable the analyzer uses must live here — no hard-coded duplicates in code.
   **参数（`heuristic-bands`）**：分析器用到的每个数值可调项都必须放在这里——代码里不许再留硬编码副本。

   - `overripeBelowHz` (number): dominant frequency **<** this → OVERRIPE.
     主频 **<** 此值 → 过熟。
   - `ripeUpToHz` (number): dominant frequency **<** this → RIPE; **at or above** → UNRIPE. (Corrected 2026-11-05 to match the shipped v2.2 code: exactly 280 Hz is UNRIPE. Bands: `f < 160` OVERRIPE; `160 ≤ f < 280` RIPE; `f ≥ 280` UNRIPE.)
     主频 **<** 此值 → 熟；**≥** 此值 → 生。（2026-11-05 更正，与 v2.2 代码一致：恰为 280 Hz 判生。）
   - Plus the complete remaining tunable set of the current heuristic **v2.2** (signal-quality / confidence gates and any other thresholds), extracted from `LocalAnalyzer` at implementation time and named in the same style.
     再加现行启发式 **v2.2** 的其余全部可调项（信号质量/置信度门槛等），实现时从 `LocalAnalyzer` 抽全，命名风格一致。

   As implemented (1.2.0) — all **required**; values shown are Baby 1.0 = v2.2. Integer-typed fields must be whole numbers. Beyond rule 4 below, the loader range-checks every field (finite, sensible ranges) so a file that validates can never make the analyzer misbehave.
   实现定稿（1.2.0）——全部**必填**；所示数值即 Baby 1.0 = v2.2。

   | Parameter | v2.2 | Meaning |
   |---|---|---|
   | `overripeBelowHz` / `ripeUpToHz` | 160 / 280 | verdict bands (above) |
   | `confidenceBase` / `confidenceSpan` / `confidenceMax` | 0.55 / 0.40 / 0.95 | confidence = base + span × min(1, distance / scale), capped |
   | `unripeConfidenceScaleHz` | 120 | confidence scale above the ripe band |
   | `unknownConfidence` | 0.3 | confidence reported with UNKNOWN |
   | `envelopeFramesPerSecond` (int) | 100 | RMS envelope frame rate (10 ms frames) |
   | `trimHeadMs` / `trimTailMs` | 300 / 200 | usable window trimmed off the clip edges |
   | `minUsableWindowFrames` (int) | 10 | below this the whole clip is used |
   | `absoluteFloor` | 0.0056 | peak floor (≈ −45 dBFS) |
   | `peakWidthMinFrames` (int) / `peakWidthLevelRatio` | 2 / 0.5 | peak must hold ≥ ratio × peak this many frames |
   | `prominenceDbMin` | 10 | peak over the median envelope floor |
   | `attackLevelRatio` / `attackMaxMs` | 0.5 / 80 | rise from ratio × peak to peak |
   | `decayMaxMs` | 800 | fall to 1/e |
   | `sustainedEndLevelRatio` | 0.6 | decay exemption: clip end must be ≤ ratio × peak |
   | `segmentMs` / `segmentPrerollMs` | 500 / 30 | analysis FFT segment and its start before the peak |
   | `bandMinHz` / `bandMaxHz` | 60 / 600 | melon band (closed range) |
   | `crestNeighbourMinHz` / `crestNeighbourMaxHz` / `crestDbMin` | 15 / 75 / 18 | local spectral crest gate |
   | `snrDbMin` / `noiseSegmentAfterMs` / `noiseSegmentBeforeGapMs` | 6 / 1200 / 300 | spectral SNR against a noise segment |
   | `ringMinOffsetMs` / `ringSegmentMs` / `ringTolerance` | 100 / 250 / 0.15 | ring pitch consistency |

   Structural numerical guards stay in code and are not tunables: the 16-sample minimum envelope frame, the 256-sample minimum FFT segment, the 3-frame lead an attack needs to be measurable, and e (decay is defined as the fall to 1/e).

4. **Validation — a file failing ANY rule is skipped whole** (never partially applied, never crashes the app):
   **校验——任一规则不过，整文件跳过**（绝不部分应用、绝不让 App 崩溃）：

   - File size ≤ 64 KB; content parses as JSON.
     文件 ≤ 64 KB；内容可解析为 JSON。
   - All required fields present, with the types above.
     必填字段齐全、类型如上。
   - `0 < overripeBelowHz < ripeUpToHz ≤ 2000`.
     `0 < overripeBelowHz < ripeUpToHz ≤ 2000`。
   - Unknown fields are **ignored** (forward compatibility within a format version).
     未知字段**忽略**（同一格式版本内向前兼容）。
   - Duplicate `modelId`: the built-in model wins over an external one; among external files, the first in filename order wins.
     `modelId` 重复：内置模型优先于外部文件；外部文件之间按文件名字典序第一个生效。

5. **The built-in model (Baby 1.0)**: ships as a bundled `baby-1.0.ml` whose parameters equal heuristic v2.2 exactly, **and** as compiled-in fallback constants with the same values. If the bundled file is missing or invalid, the constants are used. The picker always lists Baby 1.0.
   **内置模型（Baby 1.0）**：随包附带 `baby-1.0.ml`，参数与启发式 v2.2 逐项相等；**同时**以编译内置常量形式保存同一套数值作回退。随包文件缺失或无效时用常量。模型列表里永远有 Baby 1.0。

6. **External mounting**: `.ml` files placed in the app's **Documents/Models** folder are scanned **at launch** and mounted read-only; valid ones join the picker. No hot reload in 1.2.0 — a newly added file takes effect on the next launch. No server-side delivery.
   **外部挂载**：放进 App 的 **Documents/Models** 文件夹的 `.ml` 文件在**启动时**扫描、只读挂载，合法的进模型列表。1.2.0 不做热重载——新加文件下次启动生效。不做服务端下发。

7. **Worked example** (`baby-1.0.ml`, thresholds shown; the full file carries the complete v2.2 parameter set):
   **示例**（`baby-1.0.ml`，此处只示阈值；正式文件带 v2.2 全套参数）：

   ```json
   {
     "formatVersion": 1,
     "modelId": "baby-1.0",
     "modelVersion": "1.0",
     "displayName": "Baby 1.0",
     "kind": "heuristic-bands",
     "parameters": {
       "overripeBelowHz": 160,
       "ripeUpToHz": 280
     }
   }
   ```
