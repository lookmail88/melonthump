package dev.melonthump.contrib;

import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Contributor applications and owner decisions (design doc 2.0 §5 item
 * 6, §2 item 7). Every state change writes an audit row in the same
 * transaction.
 *
 * <p>Status transitions:
 * <ul>
 *   <li>approve: PENDING / DECLINED / REVOKED → APPROVED (approving a
 *       revoked contributor is the "switch back on" toggle)</li>
 *   <li>decline: PENDING → DECLINED</li>
 *   <li>revoke: APPROVED → REVOKED</li>
 * </ul>
 * Repeating an action on a contributor already in the target state is
 * an idempotent no-op (no audit row); any other transition is refused
 * with {@link IllegalTransitionException}.
 */
@Service
public class ContributionService {

    public static final String ACTION_SUBMITTED = "APPLICATION_SUBMITTED";
    public static final String ACTION_APPROVED = "APPLICATION_APPROVED";
    public static final String ACTION_DECLINED = "APPLICATION_DECLINED";
    public static final String ACTION_REVOKED = "CONTRIBUTOR_REVOKED";

    /** Maximum enrollment note length (characters). */
    public static final int MAX_NOTE_LENGTH = 1000;

    private final ContributorRepository contributors;
    private final AdFreeLedgerRepository ledger;
    private final AuditLogService audit;
    private final TransactionTemplate tx;

    public ContributionService(ContributorRepository contributors, AdFreeLedgerRepository ledger,
                               AuditLogService audit, PlatformTransactionManager transactionManager) {
        this.contributors = contributors;
        this.ledger = ledger;
        this.audit = audit;
        this.tx = new TransactionTemplate(transactionManager);
    }

    /** Result of an application submission; {@code created} is false for an idempotent re-post. */
    public record Submission(Contributor contributor, boolean created) {
    }

    /** Contributor standing for self-service. */
    public record Standing(Contributor contributor, long adFreeBalance) {
    }

    public static final class ContributorNotFoundException extends RuntimeException {
        public ContributorNotFoundException(UUID id) {
            super("unknown contributor " + id);
        }
    }

    public static final class IllegalTransitionException extends RuntimeException {
        public IllegalTransitionException(ContributorStatus from, ContributorStatus to) {
            super("cannot move contributor from " + from + " to " + to);
        }
    }

    // ---- contributor side --------------------------------------------------

    /**
     * Files a PENDING application. Idempotent per contributorId: when a
     * record already exists (in any status) it is returned unchanged —
     * the note is not overwritten and no audit row is written.
     */
    public Submission submitApplication(UUID contributorId, String note) {
        Optional<Contributor> existing = contributors.findById(contributorId);
        if (existing.isPresent()) {
            return new Submission(existing.get(), false);
        }
        try {
            Contributor created = tx.execute(status -> {
                Contributor c = contributors.saveAndFlush(Contributor.newApplication(contributorId, note));
                audit.record(contributorId.toString(), ACTION_SUBMITTED, AuditLogService.OBJECT_CONTRIBUTOR,
                        contributorId.toString(), null, snapshot(c));
                return c;
            });
            return new Submission(created, true);
        } catch (DataIntegrityViolationException race) {
            // A concurrent request inserted the same contributorId first.
            return contributors.findById(contributorId)
                    .map(c -> new Submission(c, false))
                    .orElseThrow(() -> race);
        }
    }

    @Transactional(readOnly = true)
    public Standing standing(UUID contributorId) {
        Contributor c = contributors.findById(contributorId)
                .orElseThrow(() -> new ContributorNotFoundException(contributorId));
        return new Standing(c, ledger.balanceOf(contributorId));
    }

    @Transactional(readOnly = true)
    public long adFreeBalance(UUID contributorId) {
        return ledger.balanceOf(contributorId);
    }

    // ---- owner side ------------------------------------------------------

    @Transactional(readOnly = true)
    public List<Contributor> listApplications(ContributorStatus status) {
        return status == null
                ? contributors.findAllByOrderByCreatedAtAscContributorIdAsc()
                : contributors.findByStatusOrderByCreatedAtAscContributorIdAsc(status);
    }

    @Transactional
    public Contributor approve(UUID contributorId, String actor) {
        return transition(contributorId, ContributorStatus.APPROVED,
                EnumSet.of(ContributorStatus.PENDING, ContributorStatus.DECLINED, ContributorStatus.REVOKED),
                ACTION_APPROVED, actor);
    }

    @Transactional
    public Contributor decline(UUID contributorId, String actor) {
        return transition(contributorId, ContributorStatus.DECLINED,
                EnumSet.of(ContributorStatus.PENDING), ACTION_DECLINED, actor);
    }

    @Transactional
    public Contributor revoke(UUID contributorId, String actor) {
        return transition(contributorId, ContributorStatus.REVOKED,
                EnumSet.of(ContributorStatus.APPROVED), ACTION_REVOKED, actor);
    }

    private Contributor transition(UUID contributorId, ContributorStatus target, Set<ContributorStatus> allowedFrom,
                                   String action, String actor) {
        Contributor c = contributors.findForUpdate(contributorId)
                .orElseThrow(() -> new ContributorNotFoundException(contributorId));
        ContributorStatus from = c.getStatus();
        if (from == target) {
            return c;
        }
        if (!allowedFrom.contains(from)) {
            throw new IllegalTransitionException(from, target);
        }
        Map<String, Object> before = snapshot(c);
        c.setStatus(target);
        Contributor saved = contributors.saveAndFlush(c);
        audit.record(actor, action, AuditLogService.OBJECT_CONTRIBUTOR, contributorId.toString(),
                before, snapshot(saved));
        return saved;
    }

    private static Map<String, Object> snapshot(Contributor c) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("contributorId", c.getContributorId().toString());
        m.put("status", c.getStatus().name());
        m.put("note", c.getNote());
        return m;
    }
}
