# MelonThump Roadmap — Beyond 1.2.0

> **Last updated**: 2026-11-05 America/Los_Angeles.
>
> **最后更新**：2026-11-05（America/Los_Angeles）。

Candidates beyond the current release line. Nothing here is committed work: each candidate needs validation and an explicit go-ahead before design or implementation starts.

1.2.0 之后的候选方向。此处所列均非已立项工作：每个候选都要先过验证、再经明确批准，才进入设计与实现。

## 2.0 candidates / 2.0 候选

1. **Image recognition (photo mode) as the 2.0 headline feature** — raised by an outside suggestion on 2026-11-05; status: candidate only, not approved.
   **图像识别（拍照模式）作为 2.0 的招牌功能** — 2026-11-05 由外部建议提出；状态：仅候选，未批准。

   - **What it can and cannot judge**: a photo reads the exterior only — ground-spot (field spot) color, stripe definition, rind webbing. Ripeness of the flesh, sugar content and hollowness are invisible to a camera; the thump remains the only probe of the interior. Photo is therefore a complement to thumping, never a replacement.
     **能判与不能判**：照片只能看外皮——地脐黄斑颜色、瓜纹清晰度、表皮纹路。果肉成熟度、糖度、空心都拍不到；内部仍只有敲击声能探。所以拍照是拍瓜的补充，永远替代不了拍瓜。
   - **In-house evidence**: the 2026-11-04 freshness blind test (steak / vegetables / fish) put image-only pairwise accuracy at 67–80% — coarse good-vs-bad grading, no reliable fine ranking, and at least one dangerous-direction error (spoiled read as fresh). Watermelon photos should be expected to have the same ceiling.
     **自家实测**：2026-11-04 新鲜度盲测（牛排/蔬菜/鱼）中，纯图像成对准确率 67–80%——只能粗分好坏、排不出精确名次，且出过"把坏的读成好的"危险方向错误。西瓜照片应按同一天花板预期。
   - **Market evidence**: the main competitor already ships photo + knock dual mode and has 2 ratings in 8 months; photo mode is not what wins this category (ratings velocity and shipping cadence are).
     **市场证据**：主要竞品已做照片+敲击双模式，8 个月只有 2 个评分；赢这个品类靠的不是照片模式，而是评分速度与发版节奏。
   - **Architectural fit**: 1.2.0's model loader deliberately leaves a seam for a future real ML model; an on-device CoreML vision model keeps the "media never leaves the phone" rule intact.
     **架构契合**：1.2.0 的模型加载层已预留"将来接真 ML 模型"的位置；本地 CoreML 视觉模型不破坏"媒体不出手机"的规矩。
   - **Validation gate (must pass before any go-ahead)**: assemble a labeled sample set — photo + thump verdict + cut-open ground truth for the same melons — and blind-test whether photo + thump beats thump alone. Ship only if the combination measurably wins; otherwise drop the candidate.
     **验证门（过门才谈立项）**：攒一批同瓜三件套样本——照片 + 敲击判定 + 切开实况——盲测"照片+拍瓜"是否真胜过单拍瓜。组合确有可测的胜出才做；否则放弃该候选。
   - **Sequencing**: 1.2.0 ships first; this candidate is evaluated only after 1.2.0 is live.
     **次序**：先发 1.2.0；本候选在 1.2.0 上线之后才评估。
