package dev.melonthump.contrib;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.Immutable;

/**
 * One ad-free allowance movement (design doc 2.0 §7 item 9). The ledger
 * is append-only; a contributor's balance is the sum of their deltas.
 * Kept as a separate book from the Invite credit economy.
 */
@Entity
@Immutable
@Table(name = "ad_free_ledger")
public class AdFreeLedgerEntry {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "contributor_id", nullable = false, updatable = false)
    private UUID contributorId;

    @Column(name = "delta", nullable = false, updatable = false)
    private int delta;

    @Enumerated(EnumType.STRING)
    @Column(name = "reason", nullable = false, updatable = false, length = 32)
    private LedgerReason reason;

    @Column(name = "reference_id", updatable = false, length = 64)
    private String referenceId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected AdFreeLedgerEntry() {
    }

    public AdFreeLedgerEntry(UUID contributorId, int delta, LedgerReason reason, String referenceId) {
        this.contributorId = contributorId;
        this.delta = delta;
        this.reason = reason;
        this.referenceId = referenceId;
    }

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
    }

    public Long getId() {
        return id;
    }

    public UUID getContributorId() {
        return contributorId;
    }

    public int getDelta() {
        return delta;
    }

    public LedgerReason getReason() {
        return reason;
    }

    public String getReferenceId() {
        return referenceId;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
