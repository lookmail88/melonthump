package dev.melonthump.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

/** Wire shapes for the App Attest endpoints (design doc §3.2/§5). */
public final class AttestDtos {

    private AttestDtos() {
    }

    @Schema(description = "A fresh, one-time attestation challenge (base64), stored server-side until used or expired")
    public record ChallengeResponse(
            String challenge,
            int expiresInSeconds) {
    }

    @Schema(description = "Enrollment: the attestation object produced by DCAppAttestService.attestKey over SHA-256(challenge)")
    public record EnrollRequest(
            @Schema(description = "App Attest key identifier returned by generateKey")
            String keyId,
            @Schema(description = "Base64-encoded CBOR attestation object")
            String attestationObject,
            @Schema(description = "Base64 challenge this attestation was made over (single-use)")
            String challenge,
            @Schema(description = "Anonymous install UUID this key belongs to")
            UUID installId) {
    }

    @Schema(description = "Enrollment outcome")
    public record EnrollResponse(
            String status,
            @Schema(description = "Attestation environment: production / develop")
            String environment) {
    }
}
