package dev.melonthump.service;

import dev.melonthump.audio.AudioFeatureExtractor;
import dev.melonthump.audio.AudioFeatures;
import dev.melonthump.audio.WavReader;
import dev.melonthump.dto.TapAnalysisResponse;
import dev.melonthump.model.RipenessModel;
import dev.melonthump.model.RipenessResult;
import java.io.IOException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

@Service
public class TapAnalysisService {

    private final AudioFeatureExtractor extractor;
    private final RipenessModel model;

    public TapAnalysisService(AudioFeatureExtractor extractor, RipenessModel model) {
        this.extractor = extractor;
        this.model = model;
    }

    public TapAnalysisResponse analyze(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "empty upload");
        }
        final WavReader.WavData wav;
        try {
            wav = WavReader.read(file.getInputStream());
        } catch (IOException e) {
            // v1 only decodes 16-bit PCM WAV (the iOS app records WAV).
            throw new ResponseStatusException(
                    HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                    "v1 supports 16-bit PCM WAV only: " + e.getMessage());
        }
        AudioFeatures features;
        try {
            features = extractor.extract(wav);
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage());
        }
        RipenessResult result = model.classify(features);
        return new TapAnalysisResponse(
                round(features.dominantFrequencyHz()),
                round(features.spectralCentroidHz()),
                round(features.decayTimeMs()),
                result.verdict(),
                round(result.confidence()),
                model.modelVersion());
    }

    private static double round(double v) {
        return Math.round(v * 100.0) / 100.0;
    }
}
