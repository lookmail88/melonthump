package dev.melonthump.store;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;

/** Challenge lifecycle and the anti-replay counter, at the store layer. */
@SpringBootTest
@ActiveProfiles("test")
@TestPropertySource(properties =
        "spring.datasource.url=jdbc:h2:mem:melonthump-store;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1")
class AttestStoreTest {

    @Autowired
    private AttestStore store;

    @Test
    void challengeIsSingleUse() {
        byte[] challenge = new byte[] {1, 2, 3, 4};
        store.storeChallenge(challenge, Instant.now().plusSeconds(60));
        assertTrue(store.consumeChallenge(challenge), "first consumption succeeds");
        assertFalse(store.consumeChallenge(challenge), "second consumption must fail");
    }

    @Test
    void expiredChallengeIsRejected() {
        byte[] challenge = new byte[] {5, 6, 7, 8};
        store.storeChallenge(challenge, Instant.now().minusSeconds(1));
        assertFalse(store.consumeChallenge(challenge));
    }

    @Test
    void unknownChallengeIsRejected() {
        assertFalse(store.consumeChallenge(new byte[] {42, 42, 42}));
    }

    @Test
    void signCountOnlyMovesForward() {
        String keyId = "test-key-" + UUID.randomUUID();
        store.upsertKey(keyId, UUID.randomUUID(), new byte[] {1}, "production");
        assertTrue(store.advanceSignCount(keyId, 5));
        assertFalse(store.advanceSignCount(keyId, 5), "same counter is a replay");
        assertFalse(store.advanceSignCount(keyId, 3), "lower counter is a replay");
        assertTrue(store.advanceSignCount(keyId, 6));
    }
}
