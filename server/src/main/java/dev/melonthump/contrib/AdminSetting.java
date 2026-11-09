package dev.melonthump.contrib;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;
import java.time.Instant;
import org.springframework.data.domain.Persistable;

/**
 * One runtime override of a known admin setting (table
 * {@code admin_settings}, V7). The {@code key} / {@code value} columns
 * are quoted identifiers because both are keywords in H2.
 */
@Entity
@Table(name = "admin_settings")
public class AdminSetting implements Persistable<String> {

    @Id
    @Column(name = "`key`", nullable = false, updatable = false, length = 64)
    private String key;

    @Column(name = "`value`", nullable = false, length = 256)
    private String value;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "updated_by", length = 128)
    private String updatedBy;

    @Transient
    private boolean fresh = true;

    protected AdminSetting() {
    }

    public AdminSetting(String key, String value, String updatedBy) {
        this.key = key;
        this.value = value;
        this.updatedBy = updatedBy;
    }

    @PrePersist
    @PreUpdate
    void touch() {
        updatedAt = Instant.now();
    }

    @PostLoad
    @PostPersist
    void markNotNew() {
        fresh = false;
    }

    @Override
    public String getId() {
        return key;
    }

    @Override
    public boolean isNew() {
        return fresh;
    }

    public String getKey() {
        return key;
    }

    public String getValue() {
        return value;
    }

    public void update(String value, String updatedBy) {
        this.value = value;
        this.updatedBy = updatedBy;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public String getUpdatedBy() {
        return updatedBy;
    }
}
