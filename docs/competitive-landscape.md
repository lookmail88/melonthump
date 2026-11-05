# Competitive Landscape — Watermelon Ripeness Apps

Snapshot: 2026-11-04 (US App Store). Purpose: reference for 1.2.0 planning
and store-listing decisions. All figures from Apple's public store data.

## The cluster

| App | Developer | Released | Ratings | Model | Method |
| --- | --- | --- | --- | --- | --- |
| Watermelon Picker 1 | Hanqing Guo (individual) | 2026-03-10 | 2 (5.0) | Free + IAP credits | Photo (visual) + knock sound; spectrograms, per-metric details |
| Watermelon AI | Davut Temel | 2025-06-28 | ~0 | Free + IAP | "Find the Sweetest Watermelon" |
| RipeMelon: Watermelon Analyzer | (installed by user, to test) | — | — | — | "Pick perfect melons every time" |
| Juicy Melons | — | — | — | Free + IAP | "AI Watermelon Scanner" |
| **MelonThump** | **Xuyang Gao / Stephanie Gao** | **2026-11-03** | **0 (new)** | **Free + ads** | **Knock sound only; on-device; verdict in seconds** |

## Watermelon Picker 1 — closest rival (detail)

- Bundle `com.leo.watermelonpicker`, v1.01 (one update, one day after
  launch), then silent for ~8 months. English only, iOS 18+.
- Flow: take a photo, knock and record, get a "taste prediction" from
  visual + acoustic patterns. Release notes highlight sound-metric
  detail views and spectrograms (time/frequency labels), scoring for
  frequency balance and decay.
- Credits: new users get free credits, one analysis = 1 credit, more
  credits via in-app purchase. No account required.

## Read of the field

- Nobody has traction: the whole category's rating counts are in
  single digits. There is no incumbent to displace — the shelf is
  decided by ratings velocity and shipping cadence, not feature count.
- Rivals monetize with per-analysis IAP credits; MelonThump's
  free-with-ads model is the low-friction outlier.
- Rivals are English-only. MelonThump 1.2.0 already plans zh/en/es —
  Spanish is uncontested in this category.
- Steal-worthy: a "details" view (dominant frequency / spectrogram).
  MelonThump already computes the dominant frequency on-device, so
  surfacing it is cheap credibility. Photo mode is their headline but
  heavy and of doubtful accuracy — do not copy by default.

## Strategy notes (2026-11-04)

1. Ratings engine first: prompt for a store rating at the delight
   moment (after a RIPE verdict, repeat use). 20–50 ratings would top
   the category's social proof.
2. Keep shipping: rivals shipped once and stopped (8 months silent).
3. Lean on transparency: published Hz bands and the actual frequency
   vs. black-box "AI taste prediction".
4. Seasonality: northern-hemisphere watermelon season is May–Sep.
   Have the ratings base and 1.2.0 ready before May 2027.
