package dev.melonthump.store;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * PostgreSQL-backed App Attest state (design doc §4). Everything
 * request-scoped lives here — never in pod memory — because prod runs
 * 2 replicas and either pod must verify what the other issued.
 */
@Component
public class AttestStore {

    private final JdbcTemplate jdbc;

    public AttestStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** An enrolled key as stored in attest_key. */
    public record AttestedKey(String keyId, UUID installId, byte[] publicKeyEncoded,
                              long signCount, String environment) {
    }

    // ---- challenges ----------------------------------------------------

    /** Stores a fresh challenge; expired challenges are swept on insert. */
    public void storeChallenge(byte[] challenge, Instant expiresAt) {
        jdbc.update("DELETE FROM attest_challenge WHERE expires_at <= ?",
                Timestamp.from(Instant.now()));
        jdbc.update("INSERT INTO attest_challenge (challenge, expires_at) VALUES (?, ?)",
                challenge, Timestamp.from(expiresAt));
    }

    /**
     * Single-use consumption: deletes the challenge row and reports
     * whether it existed and was still fresh. A challenge verifies at
     * most once, whichever pod issued it.
     */
    public boolean consumeChallenge(byte[] challenge) {
        int deleted = jdbc.update(
                "DELETE FROM attest_challenge WHERE challenge = ? AND expires_at > ?",
                challenge, Timestamp.from(Instant.now()));
        return deleted == 1;
    }

    // ---- keys ----------------------------------------------------------

    public Optional<AttestedKey> findKey(String keyId) {
        return jdbc.query(
                "SELECT key_id, install_id, public_key, sign_count, environment "
                        + "FROM attest_key WHERE key_id = ?",
                (rs, rowNum) -> new AttestedKey(
                        rs.getString("key_id"),
                        rs.getObject("install_id", UUID.class),
                        rs.getBytes("public_key"),
                        rs.getLong("sign_count"),
                        rs.getString("environment")),
                keyId).stream().findFirst();
    }

    /** Inserts a newly enrolled key, or replaces it on re-enrollment (counter resets). */
    public void upsertKey(String keyId, UUID installId, byte[] publicKeyEncoded, String environment) {
        try {
            jdbc.update("INSERT INTO attest_key (key_id, install_id, public_key, sign_count, environment) "
                            + "VALUES (?, ?, ?, 0, ?)",
                    keyId, installId, publicKeyEncoded, environment);
        } catch (DuplicateKeyException e) {
            jdbc.update("UPDATE attest_key SET install_id = ?, public_key = ?, sign_count = 0, "
                            + "environment = ? WHERE key_id = ?",
                    installId, publicKeyEncoded, environment, keyId);
        }
    }

    /**
     * Atomically advances the anti-replay counter; succeeds only when
     * {@code newCount} is strictly greater than the stored counter.
     */
    public boolean advanceSignCount(String keyId, long newCount) {
        int updated = jdbc.update(
                "UPDATE attest_key SET sign_count = ? WHERE key_id = ? AND sign_count < ?",
                newCount, keyId, newCount);
        return updated == 1;
    }
}
