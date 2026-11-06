package dev.melonthump.store;

import java.security.SecureRandom;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * PostgreSQL state for invites (design doc 1.2.0 §3): invite codes and
 * invitee attributions with confirmation + reward-claim state. Every
 * multi-step operation runs in one transaction; the per-inviter cap is
 * serialized with a row lock on the inviter's code row so two replicas
 * can never reward an eleventh invite.
 */
@Component
public class InviteStore {

    /** Unambiguous alphabet: no 0/O, 1/I/L. */
    public static final String CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    public static final int CODE_LENGTH = 8;

    private final JdbcTemplate jdbc;
    private final SecureRandom random = new SecureRandom();

    public InviteStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public enum AttributeOutcome { ATTRIBUTED, ALREADY_ATTRIBUTED, UNKNOWN_CODE, SELF_INVITE,
        ATTRIBUTED_ELSEWHERE, DEVICE_ALREADY_COUNTED, ALREADY_ACTIVE }

    public enum ConfirmStatus { CONFIRMED, ALREADY_CONFIRMED, NOT_INVITED }

    public record ConfirmOutcome(ConfirmStatus status, boolean rewarded) {
    }

    public record Status(String code, int confirmedInvites, int rewardedInvites,
                         int unclaimedInviterRewards, boolean invited, boolean inviteeConfirmed,
                         boolean inviteeRewardClaimable) {
    }

    public record ClaimOutcome(int inviterRewards, boolean inviteeReward) {
    }

    /** Uppercases and strips spaces / dashes; null when the result is not a well-formed code. */
    public static String normalizeCode(String raw) {
        if (raw == null) {
            return null;
        }
        String code = raw.replaceAll("[\\s-]", "").toUpperCase(java.util.Locale.ROOT);
        if (code.length() != CODE_LENGTH) {
            return null;
        }
        for (int i = 0; i < code.length(); i++) {
            if (CODE_ALPHABET.indexOf(code.charAt(i)) < 0) {
                return null;
            }
        }
        return code;
    }

    // ---- codes ---------------------------------------------------------

    public Optional<String> findCode(UUID installId) {
        return jdbc.queryForList("SELECT code FROM invite_code WHERE install_id = ?", String.class, installId)
                .stream().findFirst();
    }

    public Optional<UUID> findInviterByCode(String code) {
        return jdbc.query("SELECT install_id FROM invite_code WHERE code = ?",
                (rs, n) -> rs.getObject("install_id", UUID.class), code).stream().findFirst();
    }

    /** Returns the install's code, issuing one on first call (idempotent, race-safe). */
    public String getOrCreateCode(UUID installId) {
        for (int attempt = 0; attempt < 8; attempt++) {
            Optional<String> existing = findCode(installId);
            if (existing.isPresent()) {
                return existing.get();
            }
            try {
                String code = randomCode();
                jdbc.update("INSERT INTO invite_code (install_id, code) VALUES (?, ?)", installId, code);
                return code;
            } catch (DuplicateKeyException e) {
                // Either a concurrent request issued this install's code
                // (re-read above) or the random code collided (retry).
            }
        }
        throw new IllegalStateException("could not issue an invite code");
    }

    private String randomCode() {
        StringBuilder sb = new StringBuilder(CODE_LENGTH);
        for (int i = 0; i < CODE_LENGTH; i++) {
            sb.append(CODE_ALPHABET.charAt(random.nextInt(CODE_ALPHABET.length())));
        }
        return sb.toString();
    }

    // ---- attribution ---------------------------------------------------

    /**
     * Records that {@code inviteeInstall} arrived via {@code code}. First
     * attribution wins; one install and one App Attest key are counted at
     * most once; self-invites and installs that already completed a real
     * analysis (per the 1.1.0 stats ledger) are refused.
     */
    @Transactional
    public AttributeOutcome attribute(UUID inviteeInstall, String inviteeKeyId, String code, String source) {
        Optional<UUID> inviter = findInviterByCode(code);
        if (inviter.isEmpty()) {
            return AttributeOutcome.UNKNOWN_CODE;
        }
        if (inviter.get().equals(inviteeInstall)) {
            return AttributeOutcome.SELF_INVITE;
        }
        List<UUID> existing = jdbc.query(
                "SELECT inviter_install_id FROM invite_attribution WHERE invitee_install_id = ?",
                (rs, n) -> rs.getObject("inviter_install_id", UUID.class), inviteeInstall);
        if (!existing.isEmpty()) {
            return existing.get(0).equals(inviter.get())
                    ? AttributeOutcome.ALREADY_ATTRIBUTED
                    : AttributeOutcome.ATTRIBUTED_ELSEWHERE;
        }
        if (inviteeKeyId != null) {
            Integer sameKey = jdbc.queryForObject(
                    "SELECT COUNT(*) FROM invite_attribution WHERE invitee_key_id = ?", Integer.class, inviteeKeyId);
            if (sameKey != null && sameKey > 0) {
                return AttributeOutcome.DEVICE_ALREADY_COUNTED;
            }
        }
        Integer analyses = jdbc.queryForObject(
                "SELECT COUNT(*) FROM app_event WHERE install_id = ? AND type = 'analysis_completed' "
                        + "AND verdict <> 'UNKNOWN'", Integer.class, inviteeInstall);
        if (analyses != null && analyses > 0) {
            return AttributeOutcome.ALREADY_ACTIVE;
        }
        try {
            jdbc.update("INSERT INTO invite_attribution (invitee_install_id, invitee_key_id, inviter_install_id, source) "
                    + "VALUES (?, ?, ?, ?)", inviteeInstall, inviteeKeyId, inviter.get(), source);
        } catch (DuplicateKeyException e) {
            return AttributeOutcome.DEVICE_ALREADY_COUNTED;
        }
        return AttributeOutcome.ATTRIBUTED;
    }

    // ---- confirmation --------------------------------------------------

    /**
     * Confirms the invitee's invite (first completed thump analysis).
     * Idempotent. Rewarded only while the inviter has fewer than
     * {@code cap} rewarded invites; past the cap the confirmation is
     * recorded without rewards for either side.
     */
    @Transactional
    public ConfirmOutcome confirm(UUID inviteeInstall, int cap) {
        record Row(long id, UUID inviter, boolean confirmed, boolean rewarded) {
        }
        List<Row> rows = jdbc.query(
                "SELECT id, inviter_install_id, confirmed_at, rewarded FROM invite_attribution "
                        + "WHERE invitee_install_id = ?",
                (rs, n) -> new Row(rs.getLong("id"), rs.getObject("inviter_install_id", UUID.class),
                        rs.getTimestamp("confirmed_at") != null, rs.getBoolean("rewarded")),
                inviteeInstall);
        if (rows.isEmpty()) {
            return new ConfirmOutcome(ConfirmStatus.NOT_INVITED, false);
        }
        Row row = rows.get(0);
        if (row.confirmed()) {
            return new ConfirmOutcome(ConfirmStatus.ALREADY_CONFIRMED, row.rewarded());
        }
        // Serialize all confirmations of one inviter (cap check + update).
        jdbc.queryForList("SELECT install_id FROM invite_code WHERE install_id = ? FOR UPDATE",
                row.inviter());
        Integer rewardedSoFar = jdbc.queryForObject(
                "SELECT COUNT(*) FROM invite_attribution WHERE inviter_install_id = ? AND rewarded = TRUE",
                Integer.class, row.inviter());
        boolean rewarded = rewardedSoFar == null || rewardedSoFar < cap;
        int updated = jdbc.update(
                "UPDATE invite_attribution SET confirmed_at = now(), rewarded = ? "
                        + "WHERE id = ? AND confirmed_at IS NULL", rewarded, row.id());
        if (updated == 0) {
            Boolean stored = jdbc.queryForObject(
                    "SELECT rewarded FROM invite_attribution WHERE id = ?", Boolean.class, row.id());
            return new ConfirmOutcome(ConfirmStatus.ALREADY_CONFIRMED, Boolean.TRUE.equals(stored));
        }
        return new ConfirmOutcome(ConfirmStatus.CONFIRMED, rewarded);
    }

    // ---- status & claims -------------------------------------------------

    public Status status(UUID installId) {
        String code = findCode(installId).orElse(null);
        Integer confirmed = jdbc.queryForObject(
                "SELECT COUNT(*) FROM invite_attribution WHERE inviter_install_id = ? AND confirmed_at IS NOT NULL",
                Integer.class, installId);
        Integer rewarded = jdbc.queryForObject(
                "SELECT COUNT(*) FROM invite_attribution WHERE inviter_install_id = ? AND rewarded = TRUE",
                Integer.class, installId);
        Integer unclaimed = jdbc.queryForObject(
                "SELECT COUNT(*) FROM invite_attribution WHERE inviter_install_id = ? AND rewarded = TRUE "
                        + "AND inviter_claim_id IS NULL", Integer.class, installId);
        record Own(boolean confirmed, boolean claimable) {
        }
        List<Own> own = jdbc.query(
                "SELECT confirmed_at, rewarded, invitee_claim_id FROM invite_attribution WHERE invitee_install_id = ?",
                (rs, n) -> new Own(rs.getTimestamp("confirmed_at") != null,
                        rs.getBoolean("rewarded") && rs.getObject("invitee_claim_id") == null),
                installId);
        return new Status(code, nz(confirmed), nz(rewarded), nz(unclaimed), !own.isEmpty(),
                !own.isEmpty() && own.get(0).confirmed(), !own.isEmpty() && own.get(0).claimable());
    }

    /**
     * Claims every unclaimed reward of this install (as inviter and as
     * invitee) under {@code claimId}. Re-sending the same claimId returns
     * the same totals and grants nothing new, so a lost response can be
     * retried safely; each reward can be claimed exactly once.
     */
    @Transactional
    public ClaimOutcome claim(UUID installId, UUID claimId) {
        jdbc.update("UPDATE invite_attribution SET inviter_claim_id = ? WHERE inviter_install_id = ? "
                + "AND rewarded = TRUE AND inviter_claim_id IS NULL", claimId, installId);
        jdbc.update("UPDATE invite_attribution SET invitee_claim_id = ? WHERE invitee_install_id = ? "
                + "AND rewarded = TRUE AND invitee_claim_id IS NULL", claimId, installId);
        Integer inviter = jdbc.queryForObject(
                "SELECT COUNT(*) FROM invite_attribution WHERE inviter_install_id = ? AND inviter_claim_id = ?",
                Integer.class, installId, claimId);
        Integer invitee = jdbc.queryForObject(
                "SELECT COUNT(*) FROM invite_attribution WHERE invitee_install_id = ? AND invitee_claim_id = ?",
                Integer.class, installId, claimId);
        return new ClaimOutcome(nz(inviter), nz(invitee) > 0);
    }

    private static int nz(Integer v) {
        return v == null ? 0 : v;
    }
}
