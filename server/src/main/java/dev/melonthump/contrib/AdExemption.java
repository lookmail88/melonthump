package dev.melonthump.contrib;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;
import java.time.Instant;
import org.springframework.data.domain.Persistable;

/**
 * One install on the owner ad-exemption allowlist (table
 * {@code ad_exemptions}, V6; design doc 2.0 §2 item 6). The list never
 * appears in a client-facing response: the version policy only answers
 * {@code adExempt} for the caller's own install id.
 */
@Entity
@Table(name = "ad_exemptions")
public class AdExemption implements Persistable<String> {

    @Id
    @Column(name = "install_id", nullable = false, updatable = false, length = 64)
    private String installId;

    @Column(name = "note", length = 128)
    private String note;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Transient
    private boolean fresh = true;

    protected AdExemption() {
    }

    public AdExemption(String installId, String note) {
        this.installId = installId;
        this.note = note;
    }

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
    }

    @PostLoad
    @PostPersist
    void markNotNew() {
        fresh = false;
    }

    @Override
    public String getId() {
        return installId;
    }

    @Override
    public boolean isNew() {
        return fresh;
    }

    public String getInstallId() {
        return installId;
    }

    public String getNote() {
        return note;
    }

    public void setNote(String note) {
        this.note = note;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
