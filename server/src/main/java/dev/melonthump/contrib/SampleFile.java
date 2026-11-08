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

/**
 * One stored material file of a sample (table {@code sample_files}, V5).
 * {@code storedPath} is relative to the storage root and is never
 * exposed by any public endpoint.
 */
@Entity
@Table(name = "sample_files")
public class SampleFile {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "sample_id", nullable = false, updatable = false)
    private Long sampleId;

    @Enumerated(EnumType.STRING)
    @Column(name = "part", nullable = false, length = 16, updatable = false)
    private SamplePart part;

    @Column(name = "sha256", nullable = false, length = 64, updatable = false)
    private String sha256;

    @Column(name = "size_bytes", nullable = false, updatable = false)
    private long sizeBytes;

    @Column(name = "content_type", nullable = false, length = 100, updatable = false)
    private String contentType;

    @Column(name = "stored_path", nullable = false, length = 512, updatable = false)
    private String storedPath;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected SampleFile() {
    }

    public SampleFile(Long sampleId, SamplePart part, String sha256, long sizeBytes, String contentType,
                      String storedPath) {
        this.sampleId = sampleId;
        this.part = part;
        this.sha256 = sha256;
        this.sizeBytes = sizeBytes;
        this.contentType = contentType;
        this.storedPath = storedPath;
    }

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
    }

    public Long getId() {
        return id;
    }

    public Long getSampleId() {
        return sampleId;
    }

    public SamplePart getPart() {
        return part;
    }

    public String getSha256() {
        return sha256;
    }

    public long getSizeBytes() {
        return sizeBytes;
    }

    public String getContentType() {
        return contentType;
    }

    public String getStoredPath() {
        return storedPath;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
