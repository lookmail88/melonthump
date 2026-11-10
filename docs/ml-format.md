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
   | `modelId` | string | yes | `[a-z0-9.-]` (dot allowed — corrected 2026-11-05), unique per source. `standard` is reserved for the built-in model; the legacy id `baby-1.0` (the built-in model's id before it was renamed to Standard) also stays reserved and resolves to `standard`. |
   | `modelVersion` | string | yes | The model's own version label (e.g. `"1.0"`). |
   | `displayName` | string | yes | Shown in the model picker (e.g. `"Standard"`). |
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

   As implemented (1.2.0) — all **required**; values shown are Standard = v2.2. Integer-typed fields must be whole numbers. Beyond rule 4 below, the loader range-checks every field (finite, sensible ranges) so a file that validates can never make the analyzer misbehave.
   实现定稿（1.2.0）——全部**必填**；所示数值即 Standard = v2.2。

   Amendment (analyzer v2.4, 2026-11-06): the persistent-spectrum keys at the end of the table are **optional** — a file that omits them loads with the defaults shown, so pre-v2.4 files remain valid. All other keys stay required.
   修订（分析器 v2.4，2026-11-06）：表中末尾的持久谱参数**可选**——文件省略时按所示默认值加载，v2.4 之前的文件继续有效。其余参数仍必填。

   | Parameter | v2.2 | Meaning |
   |---|---|---|
   | `overripeBelowHz` / `ripeUpToHz` | 160 / 280 | verdict bands (above) |
   | `confidenceBase` / `confidenceSpan` / `confidenceMax` | 0.55 / 0.40 / 0.95 | confidence = base + span × min(1, distance / scale), capped |
   | `unripeConfidenceScaleHz` | 120 | confidence scale above the ripe band |
   | `unknownConfidence` | 0.3 | confidence reported with UNKNOWN |
   | `envelopeFramesPerSecond` (int) | 100 | RMS envelope frame rate (10 ms frames) |
   | `trimHeadMs` / `trimTailMs` | 300 / 200 | usable window trimmed off the clip edges |
   | `minUsableWindowFrames` (int) | 10 | below this the whole clip is used |
   | `absoluteFloor` | 0.002 | peak floor (≈ −54 dBFS; lowered in analyzer v2.3 — real knocks were rejected at the old −45 dBFS floor) |
   | `peakWidthMinFrames` (int) / `peakWidthLevelRatio` | 2 / 0.5 | peak must hold ≥ ratio × peak this many frames (v2.3: counted on a 2 ms fine envelope, so 2 frames ≈ 4 ms) |
   | `prominenceDbMin` | 10 | peak over the median envelope floor |
   | `attackLevelRatio` / `attackMaxMs` | 0.5 / 80 | rise from ratio × peak to peak |
   | `decayMaxMs` | 800 | fall to 1/e |
   | `sustainedEndLevelRatio` | 0.6 | decay exemption: clip end must be ≤ ratio × peak |
   | `segmentMs` / `segmentPrerollMs` | 500 / 30 | analysis FFT segment and its start before the peak |
   | `bandMinHz` / `bandMaxHz` | 60 / 600 | melon band (closed range) |
   | `crestNeighbourMinHz` / `crestNeighbourMaxHz` / `crestDbMin` | 15 / 75 / 18 | local spectral crest gate |
   | `snrDbMin` / `noiseSegmentAfterMs` / `noiseSegmentBeforeGapMs` | 6 / 1200 / 300 | spectral SNR against a noise segment |
   | `ringMinOffsetMs` / `ringSegmentMs` / `ringTolerance` | 100 / 250 / 0.15 | ring pitch consistency |
   | `persistWindowStartMs` / `persistWindowEndMs` | 20 / 400 | persistent-spectrum averaging window after the knock peak (v2.4, optional) |
   | `persistFrameSamples` (int) / `persistHopSamples` (int) | 2048 / 512 | STFT framing of the persistent spectrum (v2.4, optional) |
   | `persistBandMaxHz` | 800 | top of the band the estimator's reference maximum is taken over (v2.4, optional) |
   | `strongPeakRatio` | 0.30 | a local peak counts as strong at ≥ ratio × band maximum (v2.4, optional) |
   | `fundamentalMinHz` | 140 | lowest frequency the main scan accepts as the fundamental — a hard floor (a sub-floor exception was tried and removed: it admitted the LF handling-burst false positives) (v2.4, optional) |
   | `silenceGuardCrestDb` / `silenceGuardPromDb` | 3.5 / 30 | silence guard: an event failing **both** bars (persistent-spectrum crest, time-domain prominence) is rejected as not-a-knock (v2.4, optional) |

   Structural numerical guards stay in code and are not tunables: the 16-sample minimum envelope frame, the 256-sample minimum FFT segment, the 3-frame lead an attack needs to be measurable, and e (decay is defined as the fall to 1/e). Analyzer v2.3 adds two more structural rules: the peak width is measured on a 2 ms fine envelope, and the crest gate has a wide-neighbourhood (40–120 Hz) rescue that applies only at or above `overripeBelowHz` (below it, low-frequency handling transients are the false-positive class and keep the strict crest). Analyzer v2.4 supersedes the v2.3 spectral gates with a structural estimator: the dominant frequency is the lowest strong peak of the persistent spectrum (STFT magnitudes averaged over the window after the knock peak); crest and SNR are computed on that spectrum as confidence annotations rather than rejections, the ring check is dropped, and the confidence penalty factors (×0.75 / ×0.85 / ×0.7) are structural. One rejection survives: the silence guard — an event whose persistent-spectrum crest and time-domain prominence both fall below their bars is rejected, which is what keeps empty-room false positives at zero.

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

5. **The built-in model (Standard)**: ships as a bundled `standard.ml` whose parameters equal heuristic v2.2 exactly, **and** as compiled-in fallback constants with the same values. If the bundled file is missing or invalid, the constants are used. The picker always lists Standard. It was named Baby 1.0 (id `baby-1.0`) before; a selection persisted under the legacy id resolves to Standard, and external files may not claim either id.
   **内置模型（Standard）**：随包附带 `standard.ml`，参数与启发式 v2.2 逐项相等；**同时**以编译内置常量形式保存同一套数值作回退。随包文件缺失或无效时用常量。模型列表里永远有 Standard。此前名为 Baby 1.0（id `baby-1.0`）；按旧 id 保存的选择解析为 Standard，外部文件不得使用这两个 id。

6. **External mounting**: `.ml` files placed in the app's **Documents/Models** folder are scanned **at launch** and mounted read-only; valid ones join the picker. No hot reload in 1.2.0 — a newly added file takes effect on the next launch. No server-side delivery.
   **外部挂载**：放进 App 的 **Documents/Models** 文件夹的 `.ml` 文件在**启动时**扫描、只读挂载，合法的进模型列表。1.2.0 不做热重载——新加文件下次启动生效。不做服务端下发。

7. **Worked example** (`standard.ml`, thresholds shown; the full file carries the complete v2.2 parameter set):
   **示例**（`standard.ml`，此处只示阈值；正式文件带 v2.2 全套参数）：

   ```json
   {
     "formatVersion": 1,
     "modelId": "standard",
     "modelVersion": "1.0",
     "displayName": "Standard",
     "kind": "heuristic-bands",
     "parameters": {
       "overripeBelowHz": 160,
       "ripeUpToHz": 280
     }
   }
   ```
