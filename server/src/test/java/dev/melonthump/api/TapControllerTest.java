package dev.melonthump.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import dev.melonthump.TestWavs;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class TapControllerTest {

    @Autowired
    private MockMvc mvc;

    @Test
    void healthReturnsUp() throws Exception {
        mvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    void analyzeWavTapReturnsVerdict() throws Exception {
        byte[] wav = TestWavs.sineTap(220, 16000, 1.0);
        MockMultipartFile file = new MockMultipartFile("file", "tap.wav", "audio/wav", wav);
        mvc.perform(multipart("/api/v1/tap/analyze").file(file))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.verdict").value("RIPE"))
                .andExpect(jsonPath("$.modelVersion").value("heuristic-v1"))
                .andExpect(jsonPath("$.dominantFrequencyHz").isNumber())
                .andExpect(jsonPath("$.confidence").isNumber());
    }

    @Test
    void analyzeRejectsNonWav() throws Exception {
        MockMultipartFile file =
                new MockMultipartFile("file", "tap.mp3", "audio/mpeg", "not audio".getBytes());
        mvc.perform(multipart("/api/v1/tap/analyze").file(file))
                .andExpect(status().isUnsupportedMediaType());
    }

    @Test
    void analyzeRejectsEmptyUpload() throws Exception {
        MockMultipartFile file =
                new MockMultipartFile("file", "empty.wav", "audio/wav", new byte[0]);
        mvc.perform(multipart("/api/v1/tap/analyze").file(file))
                .andExpect(status().isBadRequest());
    }
}
