package dev.melonthump.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.attest.AttestException;
import dev.melonthump.contrib.BandTruth;
import dev.melonthump.contrib.MaterialRules;
import dev.melonthump.contrib.Sample;
import dev.melonthump.contrib.SampleFile;
import dev.melonthump.contrib.SamplePart;
import dev.melonthump.contrib.SampleService;
import dev.melonthump.contrib.SampleService.Feedback;
import dev.melonthump.contrib.SampleService.Meta;
import dev.melonthump.contrib.SampleService.SampleWithFiles;
import dev.melonthump.contrib.SampleService.Upload;
import dev.melonthump.contrib.SampleService.Vision;
import dev.melonthump.contrib.TasteTag;
import dev.melonthump.contrib.Variety;
import dev.melonthump.contrib.WeightProvenance;
import dev.melonthump.dto.ContributionDtos.Completeness;
import dev.melonthump.dto.ContributionDtos.FeedbackView;
import dev.melonthump.dto.ContributionDtos.SampleDetail;
import dev.melonthump.dto.ContributionDtos.SampleFileView;
import dev.melonthump.dto.ContributionDtos.SampleSummary;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.Part;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Contributor sample submission and self-service (design doc 2.0 §2
 * item 8, §5 items 1 + 6, §7 items 7, 8, 10). Every endpoint is App
 * Attest gated by {@link ContributionAttestGate}; the gate runs before
 * any request content is interpreted.
 *
 * <p>Multipart parts: {@code meta} (JSON), {@code appearance} (image,
 * repeatable), {@code recording} (audio, at most one per request),
 * {@code cutOpen} (image, at most one per request). Any other part name
 * is rejected. Material files are never served back: views carry only
 * part, SHA-256, size and content type.
 */
@RestController
@RequestMapping("/api/v1/contributions/samples")
@Tag(name = "contributions", description = "Model Improvement Program: contributor application and status")
public class SampleController {

    static final String PART_META = "meta";
    static final String PART_APPEARANCE = "appearance";
    static final String PART_RECORDING = "recording";
    static final String PART_CUT_OPEN = "cutOpen";
    private static final Map<String, SamplePart> FILE_PARTS = Map.of(
            PART_APPEARANCE, SamplePart.APPEARANCE,
            PART_RECORDING, SamplePart.RECORDING,
            PART_CUT_OPEN, SamplePart.CUT_OPEN);
    /** Upper bound for the JSON meta part. */
    static final int MAX_META_BYTES = 64 * 1024;
    static final int MAX_SOURCE_LENGTH = 64;

    private final SampleService service;
    private final ContributionAttestGate gate;
    private final ObjectMapper objectMapper;

    public SampleController(SampleService service, ContributionAttestGate gate, ObjectMapper objectMapper) {
        this.service = service;
        this.gate = gate;
        this.objectMapper = objectMapper;
    }

    @Operation(summary = "Submit a sample (multipart; APPROVED contributors only; App Attest gated)",
            description = "Parts: meta (JSON: contributorId, variety, weightGrams?, weightProvenance?, source?, "
                    + "melonDate?, feedback? {score 0-100, tasteTags[], bandTruth}, visionWatermelon? 0-1, "
                    + "visionCutopenWatermelon? 0-1), appearance (1..n images), "
                    + "recording (1 audio), cutOpen (0..1 image). Missing parts are allowed (incomplete sample). "
                    + "201 + sample; 400 invalid meta/part/content type; 413 photo > 10 MB or recording > 25 MB; "
                    + "403 not APPROVED; 404 unknown contributor.")
    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<SampleDetail> submit(HttpServletRequest http) throws AttestException {
        Received received = receive(http);
        gate.verifyMultipart(http, received.digests());
        JsonNode meta = interpret(received);
        if (meta == null) {
            throw SampleRequestException.badMeta("meta part is required");
        }
        Meta parsed = new Meta(
                requiredUuid(meta, "contributorId"),
                requiredEnum(meta, "variety", Variety.class),
                optionalWeight(meta),
                optionalEnum(meta, "weightProvenance", WeightProvenance.class),
                optionalSource(meta),
                optionalDate(meta),
                optionalFeedback(meta),
                optionalVision(meta));
        List<Upload> uploads = validateUploads(received.files());
        SampleWithFiles result = service.submit(parsed, uploads);
        return ResponseEntity.status(HttpStatus.CREATED).body(detail(result));
    }

    @Operation(summary = "Append parts to one's own sample (multipart; App Attest gated)",
            description = "contributorId as query parameter and/or in a meta JSON part ({contributorId, "
                    + "feedback?, visionWatermelon?, visionCutopenWatermelon?}). File parts as for submit. A new recording / cutOpen replaces the stored one; "
                    + "appearance photos are added; feedback overwrites. Allowed while SUBMITTED or RETURNED "
                    + "(RETURNED goes back to SUBMITTED). 403 not owner / unknown sample / not APPROVED; "
                    + "409 APPROVED or VOIDED; 400 nothing to append.")
    @PostMapping(path = "/{sampleId}/parts", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public SampleDetail append(@PathVariable("sampleId") String sampleIdParam,
                               @RequestParam(value = "contributorId", required = false) String contributorIdParam,
                               HttpServletRequest http) throws AttestException {
        Received received = receive(http);
        gate.verifyMultipart(http, received.digests());
        long sampleId = parseSampleId(sampleIdParam);
        JsonNode meta = interpret(received);
        UUID fromQuery = contributorIdParam == null ? null : ContributionController.parseUuid(contributorIdParam);
        UUID fromMeta = meta == null || absent(meta.get("contributorId")) ? null : requiredUuid(meta, "contributorId");
        if (fromQuery == null && fromMeta == null) {
            throw SampleRequestException.badMeta("contributorId is required");
        }
        if (fromQuery != null && fromMeta != null && !fromQuery.equals(fromMeta)) {
            throw SampleRequestException.badMeta("contributorId in query and meta differ");
        }
        Feedback feedback = meta == null ? null : optionalFeedback(meta);
        Vision vision = meta == null ? Vision.NONE : optionalVision(meta);
        List<Upload> uploads = validateUploads(received.files());
        if (uploads.isEmpty() && feedback == null) {
            throw new SampleRequestException(HttpStatus.BAD_REQUEST, "nothing_to_append",
                    "send at least one file part or feedback");
        }
        return detail(service.append(sampleId, fromQuery != null ? fromQuery : fromMeta, feedback, vision, uploads));
    }

    @Operation(summary = "The contributor's own samples, newest first (App Attest gated)")
    @GetMapping
    public List<SampleSummary> list(@RequestParam("contributorId") String contributorIdParam,
                                    HttpServletRequest http) throws AttestException {
        gate.verifyBodiless(http);
        UUID contributorId = ContributionController.parseUuid(contributorIdParam);
        return service.list(contributorId).stream().map(SampleController::summary).toList();
    }

    @Operation(summary = "One of the contributor's own samples incl. its file list (App Attest gated)",
            description = "403 when the sample does not exist or belongs to another contributor.")
    @GetMapping("/{sampleId}")
    public SampleDetail get(@PathVariable("sampleId") String sampleIdParam,
                            @RequestParam("contributorId") String contributorIdParam,
                            HttpServletRequest http) throws AttestException {
        gate.verifyBodiless(http);
        long sampleId = parseSampleId(sampleIdParam);
        UUID contributorId = ContributionController.parseUuid(contributorIdParam);
        return detail(service.get(sampleId, contributorId));
    }

    @Operation(summary = "Withdraw (truly delete) one's own sample (App Attest gated)",
            description = "Files deleted from disk, file rows and sample row removed, SAMPLE_WITHDRAWN audit "
                    + "row kept. 204; 403 unknown/foreign sample; 409 APPROVED or VOIDED.")
    @DeleteMapping("/{sampleId}")
    public ResponseEntity<Void> withdraw(@PathVariable("sampleId") String sampleIdParam,
                                         @RequestParam("contributorId") String contributorIdParam,
                                         HttpServletRequest http) throws AttestException {
        gate.verifyBodiless(http);
        long sampleId = parseSampleId(sampleIdParam);
        UUID contributorId = ContributionController.parseUuid(contributorIdParam);
        service.withdraw(sampleId, contributorId);
        return ResponseEntity.noContent().build();
    }

    // ---- multipart intake ----------------------------------------------------

    private record ReceivedFile(SamplePart part, Part part0) {
    }

    /** Parsed multipart envelope; content is interpreted only after the attest gate passed. */
    private record Received(List<Part> metaParts, List<ReceivedFile> files, List<String> unknownNames,
                            List<ContributionAttestGate.PartDigest> digests) {
    }

    private Received receive(HttpServletRequest http) {
        List<Part> parts;
        try {
            parts = new ArrayList<>(http.getParts());
        } catch (IOException | ServletException e) {
            throw new SampleRequestException(HttpStatus.BAD_REQUEST, "invalid_multipart",
                    "request is not a readable multipart body");
        }
        List<ContributionAttestGate.PartDigest> digests = new ArrayList<>();
        List<ReceivedFile> files = new ArrayList<>();
        List<Part> metaParts = new ArrayList<>();
        List<String> unknown = new ArrayList<>();
        for (Part p : parts) {
            String name = p.getName();
            digests.add(new ContributionAttestGate.PartDigest(name, digest(p)));
            if (PART_META.equals(name)) {
                metaParts.add(p);
            } else if (FILE_PARTS.containsKey(name)) {
                files.add(new ReceivedFile(FILE_PARTS.get(name), p));
            } else {
                unknown.add(name);
            }
        }
        return new Received(metaParts, files, unknown, digests);
    }

    /** Structural checks + meta JSON, after the gate. Returns the meta object or null when absent. */
    private JsonNode interpret(Received received) {
        if (!received.unknownNames().isEmpty()) {
            throw new SampleRequestException(HttpStatus.BAD_REQUEST, "invalid_part",
                    "unknown part '" + received.unknownNames().getFirst()
                            + "' (expected meta, appearance, recording, cutOpen)");
        }
        if (received.metaParts().size() > 1) {
            throw SampleRequestException.badMeta("only one meta part is allowed");
        }
        return received.metaParts().isEmpty() ? null : readMeta(received.metaParts().getFirst());
    }

    private static byte[] digest(Part p) {
        try (InputStream in = new DigestInputStream(p.getInputStream(), MessageDigest.getInstance("SHA-256"))) {
            in.transferTo(java.io.OutputStream.nullOutputStream());
            return ((DigestInputStream) in).getMessageDigest().digest();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private JsonNode readMeta(Part p) {
        if (p.getSize() > MAX_META_BYTES) {
            throw SampleRequestException.badMeta("meta part is larger than " + MAX_META_BYTES + " bytes");
        }
        try (InputStream in = p.getInputStream()) {
            JsonNode node = objectMapper.readTree(in.readAllBytes());
            if (node == null || !node.isObject()) {
                throw SampleRequestException.badMeta("meta must be a JSON object");
            }
            return node;
        } catch (IOException e) {
            throw SampleRequestException.badMeta("meta is not valid JSON");
        }
    }

    /** Per-request counts, content types and sizes; nothing is stored before all files pass. */
    private static List<Upload> validateUploads(List<ReceivedFile> files) {
        long recordings = files.stream().filter(f -> f.part() == SamplePart.RECORDING).count();
        long cutOpens = files.stream().filter(f -> f.part() == SamplePart.CUT_OPEN).count();
        if (recordings > 1) {
            throw new SampleRequestException(HttpStatus.BAD_REQUEST, "invalid_part", "at most one recording part");
        }
        if (cutOpens > 1) {
            throw new SampleRequestException(HttpStatus.BAD_REQUEST, "invalid_part", "at most one cutOpen part");
        }
        List<Upload> uploads = new ArrayList<>();
        for (ReceivedFile f : files) {
            Part p = f.part0();
            String type = MaterialRules.normalize(p.getContentType());
            if (!MaterialRules.accepts(f.part(), type)) {
                throw new SampleRequestException(HttpStatus.BAD_REQUEST, "unsupported_content_type",
                        "part '" + p.getName() + "' has content type " + p.getContentType() + "; expected "
                                + (f.part() == SamplePart.RECORDING ? "an audio/* recording" : "an image/* photo"));
            }
            long size = p.getSize();
            if (size <= 0) {
                throw new SampleRequestException(HttpStatus.BAD_REQUEST, "invalid_part",
                        "part '" + p.getName() + "' is empty");
            }
            if (size > MaterialRules.maxBytes(f.part())) {
                throw new SampleRequestException(HttpStatus.PAYLOAD_TOO_LARGE, "file_too_large",
                        "part '" + p.getName() + "' is " + size + " bytes; limit is "
                                + MaterialRules.maxBytes(f.part()) + " bytes");
            }
            uploads.add(new Upload(f.part(), type, size, p::getInputStream));
        }
        return uploads;
    }

    // ---- meta parsing ----------------------------------------------------------

    private static boolean absent(JsonNode n) {
        return n == null || n.isNull();
    }

    private static UUID requiredUuid(JsonNode meta, String field) {
        JsonNode n = meta.get(field);
        if (absent(n) || !n.isTextual()) {
            throw SampleRequestException.badMeta(field + " is required (UUID string)");
        }
        try {
            return UUID.fromString(n.asText().strip());
        } catch (IllegalArgumentException e) {
            throw SampleRequestException.badMeta(field + " must be a UUID");
        }
    }

    private static <E extends Enum<E>> E requiredEnum(JsonNode meta, String field, Class<E> type) {
        E value = optionalEnum(meta, field, type);
        if (value == null) {
            throw SampleRequestException.badMeta(field + " is required");
        }
        return value;
    }

    private static <E extends Enum<E>> E optionalEnum(JsonNode node, String field, Class<E> type) {
        JsonNode n = node.get(field);
        if (absent(n)) {
            return null;
        }
        if (!n.isTextual()) {
            throw SampleRequestException.badMeta(field + " must be a string");
        }
        try {
            return Enum.valueOf(type, n.asText());
        } catch (IllegalArgumentException e) {
            throw SampleRequestException.badMeta(field + " '" + n.asText() + "' is not one of "
                    + java.util.Arrays.toString(type.getEnumConstants()));
        }
    }

    private static Integer optionalWeight(JsonNode meta) {
        JsonNode n = meta.get("weightGrams");
        if (absent(n)) {
            return null;
        }
        if (!n.isIntegralNumber() || !n.canConvertToInt() || n.intValue() <= 0) {
            throw SampleRequestException.badMeta("weightGrams must be a positive integer");
        }
        return n.intValue();
    }

    private static String optionalSource(JsonNode meta) {
        JsonNode n = meta.get("source");
        if (absent(n)) {
            return null;
        }
        if (!n.isTextual()) {
            throw SampleRequestException.badMeta("source must be a string");
        }
        String s = n.asText().strip();
        if (s.length() > MAX_SOURCE_LENGTH) {
            throw SampleRequestException.badMeta("source must be at most " + MAX_SOURCE_LENGTH + " characters");
        }
        return s.isEmpty() ? null : s;
    }

    private static LocalDate optionalDate(JsonNode meta) {
        JsonNode n = meta.get("melonDate");
        if (absent(n)) {
            return null;
        }
        if (!n.isTextual()) {
            throw SampleRequestException.badMeta("melonDate must be an ISO date string (YYYY-MM-DD)");
        }
        try {
            return LocalDate.parse(n.asText());
        } catch (DateTimeParseException e) {
            throw SampleRequestException.badMeta("melonDate must be an ISO date (YYYY-MM-DD)");
        }
    }

    /**
     * Feedback is optional; when present it must be valid (score integer
     * 0-100 and bandTruth required, tasteTags optional preset tags).
     */
    private static Feedback optionalFeedback(JsonNode meta) {
        JsonNode f = meta.get("feedback");
        if (absent(f)) {
            return null;
        }
        if (!f.isObject()) {
            throw SampleRequestException.badMeta("feedback must be an object");
        }
        JsonNode score = f.get("score");
        if (absent(score) || !score.isIntegralNumber() || !score.canConvertToInt()
                || score.intValue() < 0 || score.intValue() > 100) {
            throw SampleRequestException.badMeta("feedback.score must be an integer 0-100");
        }
        BandTruth band = optionalEnum(f, "bandTruth", BandTruth.class);
        if (band == null) {
            throw SampleRequestException.badMeta("feedback.bandTruth is required (UNRIPE / RIPE / OVERRIPE)");
        }
        Set<TasteTag> tags = new LinkedHashSet<>();
        JsonNode tagNode = f.get("tasteTags");
        if (!absent(tagNode)) {
            if (!tagNode.isArray()) {
                throw SampleRequestException.badMeta("feedback.tasteTags must be an array");
            }
            for (JsonNode t : tagNode) {
                if (!t.isTextual()) {
                    throw SampleRequestException.badMeta("feedback.tasteTags entries must be strings");
                }
                try {
                    tags.add(TasteTag.valueOf(t.asText()));
                } catch (IllegalArgumentException e) {
                    throw SampleRequestException.badMeta("unknown taste tag '" + t.asText() + "'; allowed: "
                            + java.util.Arrays.toString(TasteTag.values()));
                }
            }
        }
        return new Feedback(score.intValue(), List.copyOf(tags), band);
    }

    /** FIX12: optional on-device Vision scores; each a number 0-1 when present. */
    private static Vision optionalVision(JsonNode meta) {
        return new Vision(optionalUnitScore(meta, "visionWatermelon"),
                optionalUnitScore(meta, "visionCutopenWatermelon"));
    }

    private static Double optionalUnitScore(JsonNode meta, String field) {
        JsonNode n = meta.get(field);
        if (absent(n)) {
            return null;
        }
        if (!n.isNumber() || !Double.isFinite(n.doubleValue()) || n.doubleValue() < 0 || n.doubleValue() > 1) {
            throw SampleRequestException.badMeta(field + " must be a number 0-1");
        }
        return n.doubleValue();
    }

    private static long parseSampleId(String raw) {
        try {
            long id = Long.parseLong(raw.strip());
            if (id <= 0) {
                throw new NumberFormatException();
            }
            return id;
        } catch (NumberFormatException e) {
            throw new SampleRequestException(HttpStatus.BAD_REQUEST, "invalid_sample_id",
                    "sampleId must be a positive integer");
        }
    }

    // ---- views -----------------------------------------------------------------

    private static Completeness completeness(Sample s) {
        return new Completeness(s.hasAppearance(), s.hasRecording(), s.hasCutOpen(), s.hasFeedback());
    }

    static SampleSummary summary(Sample s) {
        return new SampleSummary(s.getId(), s.getStatus().name(), completeness(s), s.isComplete(),
                s.getReturnReason(), s.getVariety().name(), s.getCreatedAt().toString(), s.getUpdatedAt().toString());
    }

    static SampleDetail detail(SampleWithFiles r) {
        Sample s = r.sample();
        FeedbackView feedback = s.getScore() == null && s.getBandTruth() == null ? null
                : new FeedbackView(s.getScore(), s.getTasteTags() == null ? List.of() : s.getTasteTags(),
                        s.getBandTruth() == null ? null : s.getBandTruth().name());
        List<SampleFileView> files = new ArrayList<>();
        for (SampleFile f : r.files()) {
            files.add(new SampleFileView(f.getPart().name(), f.getSha256(), f.getSizeBytes(), f.getContentType()));
        }
        return new SampleDetail(s.getId(), s.getContributorId(), s.getStatus().name(), completeness(s),
                s.isComplete(), s.getReturnReason(), s.getVariety().name(), s.getWeightGrams(),
                s.getWeightProvenance() == null ? null : s.getWeightProvenance().name(), s.getSource(),
                s.getMelonDate() == null ? null : s.getMelonDate().toString(), feedback, files,
                s.getCreatedAt().toString(), s.getUpdatedAt().toString());
    }
}
