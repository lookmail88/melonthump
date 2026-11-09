package dev.melonthump.contrib;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import org.hibernate.annotations.Immutable;

/**
 * One row of the minimal append-only audit log (design doc 2.0 §7 item
 * 11): who, what, which object, before/after, when. {@link Immutable}
 * makes Hibernate ignore any attempted update, the class has no setters,
 * and {@link AuditLogRepository} exposes no update or delete method.
 */
@Entity
@Immutable
@Table(name = "audit_log")
public class AuditLogEntry {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "actor", nullable = false, updatable = false, length = 128)
    private String actor;

    @Column(name = "action", nullable = false, updatable = false, length = 64)
    private String action;

    @Column(name = "object_type", nullable = false, updatable = false, length = 32)
    private String objectType;

    @Column(name = "object_id", nullable = false, updatable = false, length = 64)
    private String objectId;

    @Column(name = "before_json", updatable = false)
    private String beforeJson;

    @Column(name = "after_json", updatable = false)
    private String afterJson;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected AuditLogEntry() {
    }

    public AuditLogEntry(String actor, String action, String objectType, String objectId,
                         String beforeJson, String afterJson) {
        this.actor = actor;
        this.action = action;
        this.objectType = objectType;
        this.objectId = objectId;
        this.beforeJson = beforeJson;
        this.afterJson = afterJson;
    }

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
    }

    public Long getId() {
        return id;
    }

    public String getActor() {
        return actor;
    }

    public String getAction() {
        return action;
    }

    public String getObjectType() {
        return objectType;
    }

    public String getObjectId() {
        return objectId;
    }

    public String getBeforeJson() {
        return beforeJson;
    }

    public String getAfterJson() {
        return afterJson;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
