package dev.melonthump.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.melonthump.attest.AttestException;
import dev.melonthump.contrib.ContributionService;
import dev.melonthump.contrib.Contributor;
import dev.melonthump.contrib.IncentiveService;
import dev.melonthump.dto.ContributionDtos.AdFreeSpendResponse;
import dev.melonthump.dto.ContributionDtos.ApplicationRequest;
import dev.melonthump.dto.ContributionDtos.ApplicationResponse;
import dev.melonthump.dto.ContributionDtos.ContributorStatusResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * Contributor self-service (design doc 2.0 §5 item 6): file an
 * application, read one's own standing, and (S3) spend one ad-free unit
 * to unlock a session (§7 item 9). Keyed on the anonymous
 * contributor UUID kept in the iOS Keychain. Sample submission and the
 * sample self-service queries live in {@link SampleController}.
 *
 * <p>All endpoints are App Attest gated ({@link ContributionAttestGate}):
 * the JSON POSTs cover the exact body bytes, the status GET the
 * canonical request string. The gate runs before the body / query is
 * interpreted, so an unattested caller always gets 401.
 */
@RestController
@RequestMapping("/api/v1/contributions")
@Tag(name = "contributions", description = "Model Improvement Program: contributor application and status")
public class ContributionController {

    private final ContributionService service;
    private final IncentiveService incentives;
    private final ContributionAttestGate gate;
    private final ObjectMapper objectMapper;

    public ContributionController(ContributionService service, IncentiveService incentives,
                                  ContributionAttestGate gate, ObjectMapper objectMapper) {
        this.service = service;
        this.incentives = incentives;
        this.gate = gate;
        this.objectMapper = objectMapper;
    }

    @Operation(summary = "Submit a contributor application (idempotent per contributorId)",
            description = "Creates a PENDING application and returns 201. Re-posting an existing "
                    + "contributorId returns the stored record unchanged with 200 (the note is not "
                    + "overwritten). note is required, non-blank, at most 1000 characters.")
    @PostMapping("/applications")
    public ResponseEntity<ApplicationResponse> submit(@RequestBody byte[] rawBody, HttpServletRequest http)
            throws AttestException {
        gate.verify(http, rawBody);
        ApplicationRequest request = parse(rawBody);
        if (request == null || request.contributorId() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "contributorId is required");
        }
        String note = request.note();
        if (note == null || note.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "note is required");
        }
        note = note.strip();
        if (note.length() > ContributionService.MAX_NOTE_LENGTH) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "note must be at most " + ContributionService.MAX_NOTE_LENGTH + " characters");
        }
        ContributionService.Submission submission = service.submitApplication(request.contributorId(), note);
        Contributor c = submission.contributor();
        return ResponseEntity.status(submission.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(new ApplicationResponse(c.getContributorId(), c.getStatus().name(),
                        c.getCreatedAt().toString(), c.getUpdatedAt().toString()));
    }

    @Operation(summary = "Contributor status and current ad-free balance; 404 for an unknown contributorId")
    @GetMapping("/status")
    public ContributorStatusResponse status(@RequestParam("contributorId") String contributorIdParam,
                                            HttpServletRequest http) throws AttestException {
        gate.verifyBodiless(http);
        UUID contributorId = parseUuid(contributorIdParam);
        ContributionService.Standing standing = service.standing(contributorId);
        return new ContributorStatusResponse(standing.contributor().getContributorId(),
                standing.contributor().getStatus().name(), standing.adFreeBalance(),
                standing.contributor().isAdExemptPermanent());
    }

    @Operation(summary = "Spend one ad-free unit to unlock an app session (approved contributors only)",
            description = "Body {\"contributorId\": uuid}; the assertion covers the exact body bytes. "
                    + "Permanent-exempt: 200 {spent:false, exempt:true}, nothing spent. Balance >= 1: one unit "
                    + "spent, 200 {spent:true}. Balance 0: 409 insufficient_balance. Not approved: 403; "
                    + "unknown: 404.")
    @PostMapping("/adfree/spend")
    public AdFreeSpendResponse spend(@RequestBody(required = false) byte[] rawBody, HttpServletRequest http)
            throws AttestException {
        byte[] body = rawBody == null ? new byte[0] : rawBody;
        gate.verify(http, body);
        JsonNode json;
        try {
            json = body.length == 0 ? null : objectMapper.readTree(body);
        } catch (IOException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "body is not valid JSON");
        }
        JsonNode id = json == null || !json.isObject() ? null : json.get("contributorId");
        if (id == null || !id.isTextual()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "contributorId is required");
        }
        IncentiveService.SpendResult r = incentives.spend(parseUuid(id.asText()));
        return new AdFreeSpendResponse(r.spent(), r.exempt(), r.balance());
    }

    private ApplicationRequest parse(byte[] rawBody) {
        try {
            return objectMapper.readValue(rawBody, ApplicationRequest.class);
        } catch (IOException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "body is not valid JSON");
        }
    }

    static UUID parseUuid(String raw) {
        try {
            return UUID.fromString(raw.strip());
        } catch (IllegalArgumentException | NullPointerException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "contributorId must be a UUID");
        }
    }
}
