# melonthump-server

Spring Boot service behind the MelonThump iOS app: analyzes a watermelon tap
recording and returns a ripeness verdict. Stateless, no database (v1).

## Requirements

- OpenJDK 25 (LTS)
- Maven 3.9+

## Run locally

```bash
cd server
mvn clean install   # must pass before any commit
mvn spring-boot:run
```

- Health: `GET http://localhost:8080/api/health` → `{"status":"UP"}`
- Swagger UI: `http://localhost:8080/swagger-ui.html`
- OpenAPI JSON: `http://localhost:8080/v3/api-docs`

## API

`POST /api/v1/tap/analyze` — multipart form, field `file` = 16-bit PCM WAV
(the iOS app records WAV). Response:

```json
{
  "dominantFrequencyHz": 212.4,
  "spectralCentroidHz": 640.1,
  "decayTimeMs": 178.5,
  "verdict": "RIPE",
  "confidence": 0.82,
  "modelVersion": "heuristic-v1"
}
```

`verdict` is one of `UNRIPE` / `RIPE` / `OVERRIPE`.

## v1 heuristic (placeholders!)

`RipenessModel` is a pluggable interface; v1 ships `HeuristicRipenessModel`
with fixed dominant-frequency thresholds (documented in the class):

| dominant freq | verdict   |
|---------------|-----------|
| < 160 Hz      | OVERRIPE  |
| 160–280 Hz    | RIPE      |
| > 280 Hz      | UNRIPE    |

These are educated guesses from folk acoustics (ripe = deep hollow "punk",
unripe = high "ping"). They **must** be re-calibrated with labeled data
(tap recording + cut-open ground truth) before anyone trusts them.

## Docker

```bash
cd server
docker build -t melonthump-server .
docker run -p 8080:8080 melonthump-server
```
