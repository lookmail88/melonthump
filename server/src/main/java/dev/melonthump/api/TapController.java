package dev.melonthump.api;

import dev.melonthump.dto.TapAnalysisResponse;
import dev.melonthump.service.TapAnalysisService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v1/tap")
@Tag(name = "tap", description = "Watermelon tap analysis")
public class TapController {

    private final TapAnalysisService service;

    public TapController(TapAnalysisService service) {
        this.service = service;
    }

    @Operation(summary = "Analyze a watermelon tap recording",
            description = "Upload a 16-bit PCM WAV recording of a hand tap on a watermelon. "
                    + "Returns acoustic features plus a ripeness verdict (v1: fixed heuristics).")
    @PostMapping(value = "/analyze", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public TapAnalysisResponse analyze(@RequestPart("file") MultipartFile file) {
        return service.analyze(file);
    }
}
