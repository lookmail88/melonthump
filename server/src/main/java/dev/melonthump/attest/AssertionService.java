package dev.melonthump.attest;

import dev.melonthump.store.AttestStore;
import java.util.Base64;
import org.springframework.stereotype.Component;

/**
 * Shared App Attest assertion gate for the new surface (design doc §5):
 * the stats upload and the attested-only field on the version policy.
 * Verifies, in order: key enrolled -> environment accepted here ->
 * challenge fresh and single-use -> signature valid -> sign counter
 * strictly increasing (atomic in PostgreSQL, safe across replicas).
 */
@Component
public class AssertionService {

    /** Header carrying the simulator debug bypass token. */
    public static final String BYPASS_HEADER = "X-Attest-Bypass";
    public static final String BYPASS_VALUE = "simulator";

    private final AttestStore store;
    private final AppAttestVerifier verifier;
    private final AttestProperties properties;

    public AssertionService(AttestStore store, AppAttestVerifier verifier, AttestProperties properties) {
        this.store = store;
        this.verifier = verifier;
        this.properties = properties;
    }

    /** A request that passed the gate. */
    public record Verified(String keyId, String environment) {
    }

    /**
     * The debug bypass (simulator) applies only when explicitly enabled
     * for this deployment — the dev manifest sets it, prod never does.
     */
    public boolean isDebugBypass(String bypassHeader) {
        return properties.debugBypassEnabled() && BYPASS_VALUE.equals(bypassHeader);
    }

    /**
     * @param keyId        X-Key-Id header
     * @param assertionB64 X-Assertion header (base64 assertion object)
     * @param challengeB64 X-Challenge header (base64 challenge used)
     * @param payload      exact bytes the assertion's client data covers
     */
    public Verified verify(String keyId, String assertionB64, String challengeB64, byte[] payload)
            throws AttestException {
        if (keyId == null || keyId.isBlank() || assertionB64 == null || challengeB64 == null) {
            throw new AttestException("missing attestation headers");
        }
        AttestStore.AttestedKey key = store.findKey(keyId)
                .orElseThrow(() -> new AttestException("key not enrolled"));
        if ("develop".equals(key.environment()) && !properties.acceptDevelop()) {
            throw new AttestException("develop attestation not accepted by this backend");
        }
        byte[] challenge = decodeBase64(challengeB64, "challenge");
        byte[] assertion = decodeBase64(assertionB64, "assertion");
        if (!store.consumeChallenge(challenge)) {
            throw new AttestException("challenge unknown, expired, or already used");
        }
        long signCount = verifier.verifyAssertion(
                AppAttestVerifier.decodeStoredPublicKey(key.publicKeyEncoded()),
                assertion, challenge, payload);
        if (!store.advanceSignCount(keyId, signCount)) {
            throw new AttestException("sign counter did not strictly increase (replay?)");
        }
        return new Verified(keyId, key.environment());
    }

    public static byte[] decodeBase64(String value, String what) throws AttestException {
        try {
            return Base64.getDecoder().decode(value);
        } catch (IllegalArgumentException e) {
            try {
                return Base64.getUrlDecoder().decode(value);
            } catch (IllegalArgumentException e2) {
                throw new AttestException(what + " is not valid base64");
            }
        }
    }
}
