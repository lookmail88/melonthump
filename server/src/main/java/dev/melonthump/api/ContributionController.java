package dev.melonthump.api;

import dev.melonthump.contrib.ContributionService;
import dev.melonthump.contrib.Contributor;
import dev.melonthump.dto.ContributionDtos.ApplicationRequest;
import dev.melonthump.dto.ContributionDtos.ApplicationResponse;
import dev.melonthump.dto.ContributionDtos.ContributorStatusResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
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
 * application and read one's own standing. Keyed on the anonymous
 * contributor UUID kept in the iOS Keychain. Sample upload and the
 * remaining self-service queries come in a later package.
 */
@RestController
@RequestMapping("/api/v1/contributions")
@Tag(name = "contributions", description = "Model Improvement Program: contributor application and status")
public class ContributionController {

    private final ContributionService service;

    public ContributionController(ContributionService service) {
        this.service = service;
    }

    @Operation(summary = "Submit a contributor application (idempotent per contributorId)",
            description = "Creates a PENDING application and returns 201. Re-posting an existing "
                    + "contributorId returns the stored record unchanged with 200 (the note is not "
                    + "overwritten). note is required, non-blank, at most 1000 characters.")
    @PostMapping("/applications")
    public ResponseEntity<ApplicationResponse> submit(@RequestBody ApplicationRequest request) {
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
    public ContributorStatusResponse status(@RequestParam UUID contributorId) {
        ContributionService.Standing standing = service.standing(contributorId);
        return new ContributorStatusResponse(standing.contributor().getContributorId(),
                standing.contributor().getStatus().name(), standing.adFreeBalance());
    }
}
