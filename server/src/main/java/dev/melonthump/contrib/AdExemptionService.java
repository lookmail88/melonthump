package dev.melonthump.contrib;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * The owner ad-exemption allowlist by install id (design doc 2.0 §2 item
 * 6), maintained from the admin page and consulted by the version policy.
 *
 * <p>Install ids are compared after {@link #normalize}: trimmed, and a
 * value that parses as a UUID is stored in canonical lower-case form, so
 * the iOS {@code uuidString} (upper-case) and a hand-typed lower-case id
 * match the same row.
 */
@Service
public class AdExemptionService {

    public static final String OBJECT_EXEMPTION = "AD_EXEMPTION";
    public static final String ACTION_SET = "EXEMPTION_SET";
    public static final String ACTION_REMOVED = "EXEMPTION_REMOVED";

    public static final int MAX_INSTALL_ID_LENGTH = 64;
    public static final int MAX_NOTE_LENGTH = 128;

    private final AdExemptionRepository repository;
    private final AuditLogService audit;
    private final TransactionTemplate tx;

    public AdExemptionService(AdExemptionRepository repository, AuditLogService audit,
                              PlatformTransactionManager transactionManager) {
        this.repository = repository;
        this.audit = audit;
        this.tx = new TransactionTemplate(transactionManager);
    }

    public static final class ExemptionNotFoundException extends RuntimeException {
        public ExemptionNotFoundException(String installId) {
            super("no ad exemption for install " + installId);
        }
    }

    /** Result of a set: {@code created} is false for an update (or an unchanged no-op). */
    public record SetResult(AdExemption exemption, boolean created) {
    }

    /** Trimmed; a UUID becomes canonical lower case. Null / blank → null. */
    public static String normalize(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        String v = raw.strip();
        try {
            UUID u = UUID.fromString(v);
            if (u.toString().equalsIgnoreCase(v)) {
                return u.toString();
            }
        } catch (IllegalArgumentException notAUuid) {
            // free-form id: kept as given (trimmed)
        }
        return v;
    }

    @Transactional(readOnly = true)
    public List<AdExemption> list() {
        return repository.findAllByOrderByCreatedAtDescInstallIdAsc();
    }

    /** Policy lookup; never throws for a missing / malformed id. */
    @Transactional(readOnly = true)
    public boolean isExempt(String rawInstallId) {
        String id = normalize(rawInstallId);
        return id != null && id.length() <= MAX_INSTALL_ID_LENGTH && repository.existsById(id);
    }

    /**
     * Creates the row, or updates its note. Setting the same note again is
     * a no-op without an audit row. {@code installId} must already be
     * normalized and validated; {@code note} trimmed or null.
     */
    public SetResult set(String installId, String note, String actor) {
        try {
            return tx.execute(status -> setInTx(installId, note, actor));
        } catch (DataIntegrityViolationException race) {
            // A concurrent create of the same id won: apply as an update.
            return tx.execute(status -> setInTx(installId, note, actor));
        }
    }

    private SetResult setInTx(String installId, String note, String actor) {
        var existing = repository.findForUpdate(installId);
        if (existing.isPresent()) {
            AdExemption e = existing.get();
            if (Objects.equals(e.getNote(), note)) {
                return new SetResult(e, false);
            }
            Map<String, Object> before = snapshot(e);
            e.setNote(note);
            AdExemption saved = repository.saveAndFlush(e);
            audit.record(actor, ACTION_SET, OBJECT_EXEMPTION, installId, before, snapshot(saved));
            return new SetResult(saved, false);
        }
        AdExemption saved = repository.saveAndFlush(new AdExemption(installId, note));
        audit.record(actor, ACTION_SET, OBJECT_EXEMPTION, installId, null, snapshot(saved));
        return new SetResult(saved, true);
    }

    @Transactional
    public void remove(String installId, String actor) {
        AdExemption e = repository.findForUpdate(installId)
                .orElseThrow(() -> new ExemptionNotFoundException(installId));
        Map<String, Object> before = snapshot(e);
        repository.delete(e);
        repository.flush();
        audit.record(actor, ACTION_REMOVED, OBJECT_EXEMPTION, installId, before, null);
    }

    private static Map<String, Object> snapshot(AdExemption e) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("installId", e.getInstallId());
        m.put("note", e.getNote());
        return m;
    }
}
