# 🍉 MelonThump

Tap a watermelon, let AI judge its ripeness.

A father-daughter side project: iOS app + Spring Boot server. The app records
the sound of your hand tapping a watermelon; the server analyzes the tap's
acoustics and returns a ripeness verdict.

## Architecture

```
┌─────────────────┐         multipart WAV          ┌──────────────────────┐
│   iOS app       │  POST /api/v1/tap/analyze ───► │  Spring Boot server  │
│   (SwiftUI)     │                                │                      │
│                 │  ◄── JSON: features + verdict ──┤  1. WavReader        │
│ - AVAudioRecorder│                               │  2. AudioFeature     │
│ - upload        │                                │     Extractor (FFT)  │
│ - verdict card  │                                │  3. RipenessModel ◄──┼── pluggable
└─────────────────┘                                │     └ Heuristic (v1) │   interface
                                                   └──────────────────────┘
```

- **Stateless server, no database (v1).** Each request is independent.
- **`RipenessModel` is a pluggable interface.** v1 ships a fixed-threshold
  heuristic; a trained ML model can replace it later without touching the API.

## v1 heuristic (placeholders!)

Ripe watermelons sound deep and hollow when tapped; unripe ones go "ping".
v1 maps the tap's **dominant resonant frequency** to a verdict:

| dominant freq | verdict   |
|---------------|-----------|
| < 160 Hz      | OVERRIPE  |
| 160–280 Hz    | RIPE      |
| > 280 Hz      | UNRIPE    |

These thresholds are **educated guesses, not calibrated measurements**.
Do not trust them for real melons yet — see Roadmap.

## Quick start

### Server

```bash
cd server
mvn clean install   # must pass before any commit
mvn spring-boot:run
```

- Health: http://localhost:8080/api/health
- Swagger UI: http://localhost:8080/swagger-ui.html

Or with Docker: `cd server && docker build -t melonthump-server .`

### iOS app

Requires Xcode 16+ and an iPhone simulator or device (iOS 17+).

```bash
open ios/MelonThump.xcodeproj
```

Set the server URL in the app (default `http://localhost:8080`; on a real
device use your Mac's LAN IP). Tap *Start Recording*, thump the melon, tap
*Stop & Analyze*.

## Roadmap

1. **v1 (now):** scaffold + fixed heuristic thresholds. ✅
2. **Labeled data collection:** record taps, then cut each melon open to record
   ground-truth ripeness. Slow, delicious work.
3. **Calibrate thresholds** against the labeled set (or train a small classifier
   on dominant freq + spectral centroid + decay time).
4. **ML model:** implement `RipenessModel` with the trained model (ONNX/CoreML
   export), A/B against the heuristic.
5. **On-device inference:** move the model into the app for orchard use
   (no signal in a watermelon field).

## Team

- UI design: Stephanie
- Architecture: Xuyang
- Coding & deployment: Pepper (AI)
