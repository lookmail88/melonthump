package dev.melonthump.contrib;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;
import java.time.Instant;
import java.util.UUID;
import org.springframework.data.domain.Persistable;

/**
 * A contributor application / record (design doc 2.0 §5 item 6). The
 * primary key is the client-generated anonymous contributor UUID, so the
 * entity reports {@link #isNew()} itself: a fresh instance is persisted
 * (INSERT, which surfaces a duplicate-key race) instead of merged.
 */
@Entity
@Table(name = "contributors")
public class Contributor implements Persistable<UUID> {

    @Id
    @Column(name = "contributor_id", nullable = false, updatable = false)
    private UUID contributorId;

    @Column(name = "note", nullable = false)
    private String note;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private ContributorStatus status;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Transient
    private boolean fresh = true;

    protected Contributor() {
    }

    public static Contributor newApplication(UUID contributorId, String note) {
        Contributor c = new Contributor();
        c.contributorId = contributorId;
        c.note = note;
        c.status = ContributorStatus.PENDING;
        return c;
    }

    @PrePersist
    void onCreate() {
        Instant now = Instant.now();
        createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }

    @PostLoad
    @PostPersist
    void markNotNew() {
        fresh = false;
    }

    @Override
    public UUID getId() {
        return contributorId;
    }

    @Override
    public boolean isNew() {
        return fresh;
    }

    public UUID getContributorId() {
        return contributorId;
    }

    public String getNote() {
        return note;
    }

    public ContributorStatus getStatus() {
        return status;
    }

    public void setStatus(ContributorStatus status) {
        this.status = status;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
