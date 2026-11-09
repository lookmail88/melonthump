package dev.melonthump.contrib;

import dev.melonthump.contrib.ContributionService.ContributorNotFoundException;
import dev.melonthump.contrib.SampleService.ContributorNotApprovedException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Limit;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * The contribution incentive ledger (design doc 2.0 §7 item 9, §2 items
 * 6-7): ad-free units earned on approved complete samples, clawed back on
 * voiding (unused balance only, floored at zero), granted / revoked by the
 * owner, spent one at a time to unlock an app session; plus the owner's
 * permanent ad exemption for a contributor. A separate book from the
 * Invite credit economy.
 *
 * <p>Every balance-changing write first takes the contributor row lock
 * ({@code PESSIMISTIC_WRITE}), so concurrent grants / spends / clawbacks
 * on one contributor serialize and the zero floor holds. Lock order across
 * the codebase is sample → contributor (sample review) or contributor
 * alone; nothing locks a contributor and then a sample.
 */
@Service
public class IncentiveService {

    public static final String ACTION_GRANT = "ADFREE_GRANT";
    public static final String ACTION_SPENT = "ADFREE_SPENT";
    public static final String ACTION_EXEMPTION = "CONTRIBUTOR_EXEMPTION";

    /** Largest magnitude of one manual grant (keeps balances far from int/long overflow). */
    public static final int MAX_GRANT_MAGNITUDE = 1_000_000;
    /** Longest free-text reason of a manual grant. */
    public static final int MAX_GRANT_REASON_LENGTH = 64;

    private final ContributorRepository contributors;
    private final AdFreeLedgerRepository ledger;
    private final AuditLogService audit;
    private final int unitsPerApprovedSample;

    public IncentiveService(ContributorRepository contributors, AdFreeLedgerRepository ledger, AuditLogService audit,
                            @Value("${melonthump.contrib.adfree-per-approved-sample:5}") int unitsPerApprovedSample) {
        if (unitsPerApprovedSample < 0) {
            throw new IllegalArgumentException("melonthump.contrib.adfree-per-approved-sample must be >= 0");
        }
        this.contributors = contributors;
        this.ledger = ledger;
        this.audit = audit;
        this.unitsPerApprovedSample = unitsPerApprovedSample;
    }

    public record GrantResult(UUID contributorId, int requestedDelta, int appliedDelta, long balance) {
    }

    public record SpendResult(boolean spent, boolean exempt, long balance) {
    }

    public record LedgerView(Contributor contributor, long balance, List<AdFreeLedgerEntry> entries) {
    }

    public static final class InsufficientBalanceException extends RuntimeException {
        public InsufficientBalanceException(UUID id) {
            super("contributor " + id + " has no ad-free units left");
        }
    }

    public int unitsPerApprovedSample() {
        return unitsPerApprovedSample;
    }

    // ---- sample review hooks (join the review transaction) ----------------------

    /**
     * Grants the per-sample units for an approved complete sample, exactly
     * once per sample. Returns the units granted (0 when the sample is
     * incomplete, the configured amount is 0, or it was already granted).
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public int earnForApprovedSample(Sample sample) {
        if (!sample.isComplete() || unitsPerApprovedSample == 0) {
            return 0;
        }
        String ref = sample.getId().toString();
        if (!ledger.findByReferenceIdAndReasonOrderByIdAsc(ref, LedgerReason.SAMPLE_APPROVED).isEmpty()) {
            return 0;
        }
        lockContributor(sample.getContributorId());
        ledger.save(new AdFreeLedgerEntry(sample.getContributorId(), unitsPerApprovedSample,
                LedgerReason.SAMPLE_APPROVED, ref));
        return unitsPerApprovedSample;
    }

    /** Outcome of a void clawback, for the audit snapshot. */
    public record Clawback(int earned, int clawedBack, boolean alreadyClawedBack) {
    }

    /**
     * Claws back what a voided sample earned: min(current balance, earned),
     * so the balance never goes below zero (unused units only, design §7
     * item 10). Nothing happens when the sample earned nothing or a clawback
     * row already exists for it. A computed clawback of 0 (balance already
     * spent down to zero) writes no ledger row.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public Clawback clawbackForVoidedSample(Sample sample) {
        String ref = sample.getId().toString();
        int earned = ledger.findByReferenceIdAndReasonOrderByIdAsc(ref, LedgerReason.SAMPLE_APPROVED).stream()
                .mapToInt(AdFreeLedgerEntry::getDelta).sum();
        if (earned <= 0) {
            return new Clawback(0, 0, false);
        }
        if (!ledger.findByReferenceIdAndReasonOrderByIdAsc(ref, LedgerReason.VOID_CLAWBACK).isEmpty()) {
            return new Clawback(earned, 0, true);
        }
        lockContributor(sample.getContributorId());
        long balance = ledger.balanceOf(sample.getContributorId());
        int amount = (int) Math.max(0, Math.min(balance, earned));
        if (amount > 0) {
            ledger.save(new AdFreeLedgerEntry(sample.getContributorId(), -amount, LedgerReason.VOID_CLAWBACK, ref));
        }
        return new Clawback(earned, amount, false);
    }

    // ---- owner side --------------------------------------------------------------

    /**
     * Manual ledger adjustment. The ledger row carries reason
     * {@link LedgerReason#ADMIN_GRANT} (the ledger reason is an enum-mapped
     * code in a VARCHAR(32) column); the owner's free-text reason is kept
     * in the audit row. A negative delta is applied only down to a zero
     * balance; an applied amount of 0 writes no ledger row (the audit row
     * still records the request).
     */
    @Transactional
    public GrantResult grant(UUID contributorId, int delta, String reasonText, String actor) {
        if (delta == 0) {
            throw new IllegalArgumentException("delta must be non-zero");
        }
        lockContributor(contributorId);
        long before = ledger.balanceOf(contributorId);
        int applied = delta > 0 ? delta : (int) -Math.min(before, -(long) delta);
        Long entryId = null;
        if (applied != 0) {
            entryId = ledger.save(new AdFreeLedgerEntry(contributorId, applied, LedgerReason.ADMIN_GRANT, null))
                    .getId();
        }
        long after = before + applied;
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("balance", before);
        Map<String, Object> a = new LinkedHashMap<>();
        a.put("balance", after);
        a.put("requestedDelta", delta);
        a.put("appliedDelta", applied);
        a.put("reason", reasonText);
        a.put("ledgerReason", LedgerReason.ADMIN_GRANT.name());
        a.put("ledgerEntryId", entryId);
        audit.record(actor, ACTION_GRANT, AuditLogService.OBJECT_CONTRIBUTOR, contributorId.toString(), b, a);
        return new GrantResult(contributorId, delta, applied, after);
    }

    @Transactional(readOnly = true)
    public LedgerView ledger(UUID contributorId) {
        Contributor c = contributors.findById(contributorId)
                .orElseThrow(() -> new ContributorNotFoundException(contributorId));
        return new LedgerView(c, ledger.balanceOf(contributorId),
                ledger.findByContributorIdOrderByIdDesc(contributorId, Limit.unlimited()));
    }

    /** Sets the permanent ad exemption; setting the current value is a no-op without an audit row. */
    @Transactional
    public Contributor setPermanentExemption(UUID contributorId, boolean permanent, String actor) {
        Contributor c = lockContributor(contributorId);
        if (c.isAdExemptPermanent() == permanent) {
            return c;
        }
        Map<String, Object> before = exemptionSnapshot(c);
        c.setAdExemptPermanent(permanent);
        Contributor saved = contributors.saveAndFlush(c);
        audit.record(actor, ACTION_EXEMPTION, AuditLogService.OBJECT_CONTRIBUTOR, contributorId.toString(),
                before, exemptionSnapshot(saved));
        return saved;
    }

    // ---- contributor side ----------------------------------------------------------

    /**
     * Spends one unit to unlock a session. Permanent-exempt contributors
     * spend nothing; an empty balance is refused with
     * {@link InsufficientBalanceException}.
     */
    @Transactional
    public SpendResult spend(UUID contributorId) {
        Contributor c = lockContributor(contributorId);
        if (c.getStatus() != ContributorStatus.APPROVED) {
            throw new ContributorNotApprovedException(contributorId, c.getStatus());
        }
        long balance = ledger.balanceOf(contributorId);
        if (c.isAdExemptPermanent()) {
            return new SpendResult(false, true, balance);
        }
        if (balance < 1) {
            throw new InsufficientBalanceException(contributorId);
        }
        AdFreeLedgerEntry e = ledger.save(new AdFreeLedgerEntry(contributorId, -1, LedgerReason.SESSION_UNLOCK, null));
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("balance", balance);
        Map<String, Object> a = new LinkedHashMap<>();
        a.put("balance", balance - 1);
        a.put("ledgerEntryId", e.getId());
        audit.record(contributorId.toString(), ACTION_SPENT, AuditLogService.OBJECT_CONTRIBUTOR,
                contributorId.toString(), b, a);
        return new SpendResult(true, false, balance - 1);
    }

    private Contributor lockContributor(UUID contributorId) {
        return contributors.findForUpdate(contributorId)
                .orElseThrow(() -> new ContributorNotFoundException(contributorId));
    }

    private static Map<String, Object> exemptionSnapshot(Contributor c) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("contributorId", c.getContributorId().toString());
        m.put("adExemptPermanent", c.isAdExemptPermanent());
        return m;
    }
}
