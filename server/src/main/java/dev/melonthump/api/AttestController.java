package dev.melonthump.api;

import dev.melonthump.attest.AppAttestVerifier;
import dev.melonthump.attest.AssertionService;
import dev.melonthump.attest.AttestException;
import dev.melonthump.attest.AttestProperties;
import dev.melonthump.dto.AttestDtos.ChallengeResponse;
import dev.melonthump.dto.AttestDtos.EnrollRequest;
import dev.melonthump.dto.AttestDtos.EnrollResponse;
import dev.melonthump.store.AttestStore;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * App Attest enrollment surface (design doc §3.2/§5). Challenges live
 * in PostgreSQL (prod runs 2 replicas) and are single-use.
 */
@RestController
@RequestMapping("/api/v1/attest")
@Tag(name = "attest", description = "App Attest challenges and key enrollment")
public class AttestController {

    private static final int CHALLENGE_BYTES = 32;

    private final AttestStore store;
    private final AppAttestVerifier verifier;
    private final AttestProperties properties;
    private final SecureRandom random = new SecureRandom();

    public AttestController(AttestStore store, AppAttestVerifier verifier, AttestProperties properties) {
        this.store = store;
        this.verifier = verifier;
        this.properties = properties;
    }

    @Operation(summary = "Issue a one-time attestation challenge")
    @PostMapping("/challenge")
    public ChallengeResponse challenge() {
        byte[] challenge = new byte[CHALLENGE_BYTES];
        random.nextBytes(challenge);
        store.storeChallenge(challenge,
                Instant.now().plusSeconds(properties.challengeTtlSeconds()));
        return new ChallengeResponse(
                Base64.getEncoder().encodeToString(challenge),
                properties.challengeTtlSeconds());
    }

    @Operation(summary = "Enroll an App Attest key (once per install)",
            description = "Verifies the attestation object against Apple's App Attest root CA, "
                    + "checks the challenge and app ID, and stores the public key for assertion checks.")
    @PostMapping("/enroll")
    @ResponseStatus(HttpStatus.CREATED)
    public EnrollResponse enroll(@RequestBody EnrollRequest request) throws AttestException {
        if (request.keyId() == null || request.keyId().isBlank()
                || request.attestationObject() == null || request.challenge() == null
                || request.installId() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "missing enrollment fields");
        }
        byte[] challenge = AssertionService.decodeBase64(request.challenge(), "challenge");
        byte[] attestation = AssertionService.decodeBase64(request.attestationObject(), "attestationObject");
        if (!store.consumeChallenge(challenge)) {
            throw new AttestException("challenge unknown, expired, or already used");
        }
        AppAttestVerifier.AttestationResult result =
                verifier.verifyAttestation(attestation, challenge, request.keyId());
        if ("develop".equals(result.environment()) && !properties.acceptDevelop()) {
            throw new AttestException("develop attestation not accepted by this backend");
        }
        store.upsertKey(request.keyId(), request.installId(),
                result.publicKey().getEncoded(), result.environment());
        return new EnrollResponse("enrolled", result.environment());
    }
}
