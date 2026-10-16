package dev.melonthump.dto;

import dev.melonthump.model.RipenessVerdict;
import io.swagger.v3.oas.annotations.media.Schema;

@Schema(description = "Watermelon tap analysis result")
public record TapAnalysisResponse(
        @Schema(description = "Strongest resonant frequency in Hz", example = "210.5")
        double dominantFrequencyHz,
        @Schema(description = "Spectral centroid (brightness) in Hz", example = "640.2")
        double spectralCentroidHz,
        @Schema(description = "Envelope decay time to 1/e of peak in ms", example = "180.0")
        double decayTimeMs,
        @Schema(description = "Ripeness verdict")
        RipenessVerdict verdict,
        @Schema(description = "Confidence in [0, 1]", example = "0.82")
        double confidence,
        @Schema(description = "Model version that produced the verdict", example = "heuristic-v1")
        String modelVersion) {
}
